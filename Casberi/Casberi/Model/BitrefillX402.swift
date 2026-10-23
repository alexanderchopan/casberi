import Foundation
import SwiftData

/// **THE NETWORK HALF OF BUY (prd §1473): Bitrefill's accountless door,
/// walked by this phone's account.** Measured 2026-10-22 with a throwaway
/// key, every route below answered as described:
///
/// 1. `POST /x402/connect` answers 402 with a sign-in challenge; signed by
///    the account (`YourAccountMessage`, ERC-1271) and sent back in the
///    `SIGN-IN-WITH-X` header, it answers a token good for two hours, which
///    then waives the fee on every read. Once per two hours, one Face ID.
/// 2. `GET /x402/gift-cards/search?q=&country=` answers the 25 most popular
///    (no paging), the category facets, and a word's matches. Detail prices
///    each package.
/// 3. `POST /x402/invoice/create` locks a price in USDC for 30 minutes.
/// 4. `POST /x402/invoice/pay` answers 402 with what it accepts; the
///    account signs a USDC `TransferWithAuthorization` for exactly that and
///    the retry carries it in `PAYMENT-SIGNATURE`. Bitrefill's facilitator
///    settles it on Base. Face ID again, for the money.
/// 5. The order is read back for the wallet that paid; the code is read on
///    open and never stored.
///
/// The session lives in memory and in this process only: a token is a
/// sign-in, and a sign-in is one Face ID away.
enum BitrefillX402 {

    typealias Op = YourAccountOp
    typealias Failure = YourAccountChain.Failure
    typealias Product = BitrefillBuy.Product
    typealias Invoice = BitrefillBuy.Invoice

    static let service = "Bitrefill checkout"
    static let base = BitrefillBuy.base
    /// The one network the account pays on: USDC on Base.
    static var network: Op.Network { Op.base }

    /// Buy is offered to an account that exists on this phone (§83: a verb
    /// that cannot act is not drawn).
    static var available: Bool {
        #if DEBUG
        if sample { return true }
        #endif
        return YourAccountKey.address != nil
    }

    // MARK: - The session

    @MainActor private static var session: BitrefillBuy.Session?

    @MainActor static var signedIn: Bool { session?.live == true }

    /// The token's header for a read, signing in first when there is none.
    @MainActor
    static func auth(account: String) async throws -> [String: String] {
        if let session, session.live { return [session.header: session.token] }
        let fresh = try await signIn(account: account)
        session = fresh
        return [fresh.header: fresh.token]
    }

    @MainActor static func forget() { session = nil }

    /// `POST /x402/connect`, twice: the challenge, then the signature.
    static func signIn(account: String) async throws -> BitrefillBuy.Session {
        let url = "\(base)/x402/connect"
        let (challengeJSON, status) = await IngestSupport.requestJSON(url, method: "POST", body: [:], service: service)
        guard status == 402, let challenge = BitrefillBuy.SignInChallenge.parse(challengeJSON) else {
            throw Failure(message: BitrefillBuy.refusal(challengeJSON, status: status) ?? String(localized: "Bitrefill did not answer"), from: "Bitrefill")
        }
        let address = EIP55.checksum(account)
        let message = challenge.message(address: address, chainId: network.chainId)
        let signature = try await YourAccountMessage.signText(message, on: network, account: account,
                                                              reason: String(localized: "Sign in to Bitrefill with your account"))
        guard let header = challenge.header(address: address, chainId: network.chainId, signature: signature) else {
            throw Failure(message: "The sign-in could not be written")
        }
        let (answer, status2) = await IngestSupport.requestJSON(url, method: "POST", body: [:],
                                                                headers: ["SIGN-IN-WITH-X": header], service: service)
        guard status2 == 200, let session = BitrefillBuy.Session.parse(answer) else {
            throw Failure(message: BitrefillBuy.refusal(answer, status: status2) ?? String(localized: "Bitrefill did not take the sign-in"), from: "Bitrefill")
        }
        return session
    }

    // MARK: - The catalogue

    /// The person's country, as the phone says it; the cards are per country.
    static var country: String { (Locale.current.region?.identifier ?? "US").uppercased() }

    /// `q` empty: the 25 most popular in the country; a word: its matches.
    @MainActor
    static func search(_ query: String, country: String = country, account: String) async throws -> [Product] {
        #if DEBUG
        if sample { return BitrefillBuy.search(query, in: sampleCatalogue) }
        #endif
        let headers = try await auth(account: account)
        var parts = URLComponents(string: "\(base)/x402/gift-cards/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "country", value: country)]
        let (json, status) = await IngestSupport.requestJSON(parts.url!.absoluteString, headers: headers, service: service)
        guard status == 200 else {
            if status == 401 || status == 402 { session = nil }
            throw Failure(message: BitrefillBuy.refusal(json, status: status) ?? String(localized: "Bitrefill did not answer"), from: "Bitrefill")
        }
        return BitrefillBuy.products(in: json)
    }

    /// Mobile top-ups, the same way.
    @MainActor
    static func searchTopUps(_ query: String, country: String = country, account: String) async throws -> [Product] {
        #if DEBUG
        if sample { return BitrefillBuy.search(query, in: sampleCatalogue.filter { $0.type == "refills" }) }
        #endif
        let headers = try await auth(account: account)
        var parts = URLComponents(string: "\(base)/x402/topups/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "country", value: country)]
        let (json, status) = await IngestSupport.requestJSON(parts.url!.absoluteString, headers: headers, service: service)
        guard status == 200 else { throw Failure(message: BitrefillBuy.refusal(json, status: status) ?? "Bitrefill did not answer", from: "Bitrefill") }
        return BitrefillBuy.products(in: json)
    }

    /// The product with its packages and prices.
    @MainActor
    static func detail(_ product: Product, account: String) async throws -> Product {
        #if DEBUG
        if sample { return product }
        #endif
        let headers = try await auth(account: account)
        var parts = URLComponents(string: "\(base)/x402/products/detail")!
        parts.queryItems = [URLQueryItem(name: "slug", value: product.id)]
        let (json, status) = await IngestSupport.requestJSON(parts.url!.absoluteString, headers: headers, service: service)
        guard status == 200, let root = json as? [String: Any] else {
            throw Failure(message: BitrefillBuy.refusal(json, status: status) ?? "Bitrefill did not answer", from: "Bitrefill")
        }
        var full = product
        full.packages = Product.packages(root["packages"])
        full.recipientType = (root["recipient_type"] as? String) ?? product.recipientType
        if let stock = root["in_stock"] as? Bool { full.inStock = stock }
        return full
    }

    // MARK: - The purchase

    /// Creates the invoice, pays it with the account's signed authorization,
    /// and answers the invoice. `stage` reports as a send does.
    @MainActor
    static func buy(product: Product, value: Double, phone: String? = nil, account: String, reason: String,
                    stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> Invoice {
        await stage(.preparing)
        let headers = try await auth(account: account)
        let (created, status) = await IngestSupport.requestJSON("\(base)/x402/invoice/create", method: "POST",
                                                                body: BitrefillBuy.createBody(product: product, value: value, phone: phone),
                                                                headers: headers, service: service)
        guard status == 200, let invoice = Invoice.parse(created) else {
            throw Failure(message: BitrefillBuy.refusal(created, status: status) ?? String(localized: "Bitrefill would not price it"), from: "Bitrefill")
        }
        // What it accepts: USDC on Base, exactly the invoice.
        let payURL = "\(base)/x402/invoice/pay"
        let (challenge, status2) = await IngestSupport.requestJSON(payURL, method: "POST", body: invoice.body, headers: headers, service: service)
        guard status2 == 402,
              let requirement = BitrefillBuy.Requirement.payable(in: challenge, chainId: network.chainId, asset: network.dollar) else {
            throw Failure(message: BitrefillBuy.refusal(challenge, status: status2) ?? String(localized: "Bitrefill does not take USDC on Base for this"), from: "Bitrefill")
        }
        guard requirement.amount == invoice.priceUnits else {
            throw Failure(message: String(localized: "Bitrefill asked for a different amount than it priced"), from: "Bitrefill")
        }
        // Enough USDC, checked before any prompt.
        let held = await YourAccountTokens.held(account, on: network)
        guard let usdc = held.first(where: { $0.token.contract?.lowercased() == network.dollar.lowercased() }),
              Op.atMost(requirement.amount, usdc.units) else {
            throw Failure(message: String(localized: "Not enough USDC on Base for \(Op.spoken(requirement.amount, decimals: 6)) USDC"))
        }
        var nonce = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &nonce) == errSecSuccess else {
            throw Failure(message: "No randomness for the nonce")
        }
        let authorization = BitrefillBuy.Authorization.make(from: EIP55.checksum(account), requirement: requirement, nonce: nonce)
        await stage(.signing)
        let signature = try await YourAccountMessage.signTypedData(authorization.typedData(requirement: requirement),
                                                                   on: network, account: account, reason: reason)
        guard let header = BitrefillBuy.paymentHeader(requirement: requirement, authorization: authorization, signature: signature,
                                                      challenge: challenge) else {
            throw Failure(message: "The payment could not be written")
        }
        await stage(.sending)
        var paid = headers
        paid["PAYMENT-SIGNATURE"] = header
        let (answer, status3) = await IngestSupport.requestJSON(payURL, method: "POST", body: invoice.body, headers: paid, service: service)
        guard status3 == 200 else {
            throw Failure(message: BitrefillBuy.refusal(answer, status: status3) ?? String(localized: "Bitrefill did not take the payment"), from: "Bitrefill")
        }
        #if DEBUG
        NSLog("bitrefillBuy| paid invoice %@ for %@ %@", invoice.id, Op.spoken(requirement.amount, decimals: 6), "USDC")
        #endif
        return invoice
    }

    // MARK: - The order

    /// Where the invoice stands, for the wallet that paid: the status route
    /// with the token, else the wallet's orders.
    @MainActor
    static func standing(invoiceID: String, account: String) async -> BitrefillBuy.Standing? {
        #if DEBUG
        if sample { return BitrefillBuy.Standing(delivered: true, failed: false,
                                                 redemption: .init(code: "SAMPLE-CODE-0000", pin: nil, link: nil, instructions: nil, expires: nil)) }
        #endif
        guard let headers = try? await auth(account: account) else { return nil }
        var parts = URLComponents(string: "\(base)/x402/invoice/status")!
        parts.queryItems = [URLQueryItem(name: "invoice_id", value: invoiceID)]
        let (json, status) = await IngestSupport.requestJSON(parts.url!.absoluteString, headers: headers, service: service)
        if status == 200, let standing = BitrefillBuy.Standing.parse(json) { return standing }
        let (orders, status2) = await IngestSupport.requestJSON("\(base)/x402/my/orders", headers: headers, service: service)
        guard status2 == 200 else { return nil }
        return BitrefillBuy.Standing.parse(orders: orders, invoiceID: invoiceID)
    }

    /// Polls until delivered, failed, or the wait is up (ninety seconds;
    /// Bitrefill delivers in seconds to a few minutes). nil: still on its way.
    @MainActor
    static func awaitDelivery(invoiceID: String, account: String, seconds: Double = 90) async -> BitrefillBuy.Standing? {
        let deadline = Date.now.addingTimeInterval(seconds)
        var latest: BitrefillBuy.Standing?
        while Date.now < deadline {
            try? await Task.sleep(for: .seconds(5))
            guard let now = await standing(invoiceID: invoiceID, account: account) else { continue }
            latest = now
            if now.delivered || now.failed { return now }
        }
        return latest?.delivered == true ? latest : nil
    }

    /// Lands the purchase as the §103 row: "Delta Air Lines · $50", the
    /// merchant as the counterparty, the value as the price, dated now,
    /// under `bitrefill:order:<invoice id>`. The code is NOT on it.
    @MainActor
    static func land(invoice: Invoice, product: Product, value: Double, delivered: Bool) -> Thing? {
        guard let context = SharedStore.live?.mainContext else { return nil }
        let ref = BitrefillBuy.ref(invoiceID: invoice.id)
        let stored = IngestSupport.thingsByRef(context, source: "Bitrefill")
        if let existing = stored[ref], existing.isLive {
            if delivered, !existing.tags.contains("Delivered") { existing.tags.append("Delivered"); context.saveHonestly() }
            return existing
        }
        let name = BitrefillBuy.shortName(product.name)
        let thing = Thing(kind: .link,
                          title: IngestSupport.titleLine(TitleSeam.join(name, product.money(value))),
                          content: "https://www.bitrefill.com/\(product.id)/",
                          source: "Bitrefill", capturedAt: .now, sourceRef: ref)
        thing.transferCounterparty = name
        thing.priceValue = value
        thing.priceCurrency = product.currency
        thing.summary = String(localized: "Paid \(BitrefillBuy.money(invoice.priceUSD, currency: "USD")) in USDC on Base from your account")
        if delivered { thing.tags = ["Delivered"] }
        context.insert(thing)
        context.saveHonestly()
        return thing
    }

    // MARK: - DEBUG

    /// `-bitrefillSample YES`: a built-in catalogue and the verb shown with
    /// no account, so the sentence can be looked at on a simulator; a
    /// purchase still needs the account. Always false in Release, and
    /// defined there so the callers compile (a `#if DEBUG` helper used by
    /// shipping code fails only in the archive).
    static var sample: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "bitrefillSample")
        #else
        false
        #endif
    }

    #if DEBUG

    static let sampleCatalogue: [Product] = {
        func p(_ id: String, _ name: String, _ cats: [String], _ values: [Double], type: String = "giftcards", markup: Double = 1.0) -> Product {
            var x = Product(id: id, name: name, type: type, categories: cats, countries: ["US"], currency: "USD")
            x.packages = values.map { .init(value: $0, price: ($0 * markup * 100).rounded() / 100, currency: "USD") }
            return x
        }
        return [
            p("virtual-prepaid-visa-usa", "Digital Prepaid Visa USA", ["payment-cards"], [20, 50, 100, 200], markup: 1.025),
            p("amazon_com-usa", "Amazon.com USA", ["online-marketplaces"], [5, 10, 20, 50, 100, 200, 500], markup: 1.05),
            p("doordash-usa", "DoorDash USA", ["food", "food-delivery"], [25, 50, 100]),
            p("apple-usa", "Apple USA", ["electronics"], [10, 25, 50, 100]),
            p("uber-eats-usa", "Uber Eats USA", ["food", "food-delivery"], [25, 50, 100]),
            p("roblox-usa", "Roblox USD", ["games", "in-game-currencies"], [10, 25, 50]),
            p("uber-usa", "Uber USA", ["transportation"], [25, 50, 100]),
            p("walmart-usa", "Walmart USA", ["department-stores"], [25, 50, 100]),
            p("steam-usa", "Steam USD", ["games", "game-stores"], [20, 50, 100], markup: 1.02),
            p("airbnb-usa", "Airbnb USA", ["travel", "accommodation"], [25, 50, 100, 200]),
            p("target-usa", "Target USA", ["department-stores"], [25, 50, 100]),
            p("sony-playstation-usa", "PlayStation Store USD", ["games", "game-stores"], [10, 25, 50, 100]),
            p("starbucks-usa", "Starbucks USA", ["food", "restaurants"], [5, 10, 25, 50]),
            p("hotels_com-usa", "Hotels.com USD", ["travel", "accommodation"], [25, 50, 100, 250]),
            p("delta-air-lines-usa", "Delta Air Lines USA", ["travel", "flights"], [50, 100, 250, 500]),
            p("netflix-usa", "Netflix USA", ["entertainment", "streaming"], [15, 30, 60]),
            p("stubhub-usa", "StubHub USA", ["entertainment", "experiences"], [25, 50, 100]),
            p("lyft-usa", "Lyft USA", ["transportation"], [25, 50, 100]),
            p("atandt-usa", "AT&T USA", ["refill"], [10, 20, 40, 60], type: "refills")
        ]
    }()
    #endif
}
