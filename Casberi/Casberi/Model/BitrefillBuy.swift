import Foundation

/// **BUY IS MOVE'S FOURTH VERB (prd §1473).** "$50 gift card for Travel at
/// Delta with USDC on Base." Bitrefill's accountless door
/// (`api.bitrefill.com/x402`, measured 2026-10-22) needs no account and no
/// key: the person signs in with this phone's account itself, browses free,
/// and pays the invoice as an x402 authorization in USDC on Base. Nothing of
/// Bitrefill's is drawn, nothing of the person's is held by anyone but the
/// account that paid: the codes are bound to the paying wallet.
///
/// This file is the FOUNDATION-ONLY half, compiled whole by
/// `scripts/bitrefill-buy-selftest.sh`: how a product and its packages are
/// read, which of the seven groups it stands in, the sign-in message and
/// header, the invoice, the payment challenge and the authorization the
/// account signs, and how an order answers. The network is `BitrefillX402`.
enum BitrefillBuy {

    static let host = "api.bitrefill.com"
    static let base = "https://api.bitrefill.com"

    // MARK: - Products

    /// One thing Bitrefill sells, as `/x402/gift-cards/search` lists it
    /// (measured): a slug, a name, its categories, the countries it is sold
    /// in, a currency, and whether it is in stock. The packages come with
    /// its detail.
    struct Product: Equatable, Identifiable, Sendable, Codable {
        /// The slug: `amazon_com-usa`.
        let id: String
        let name: String
        /// `giftcards`, `refills`, `esims`.
        let type: String
        let categories: [String]
        let countries: [String]
        let currency: String
        var inStock = true
        var packages: [Package] = []
        /// `none`, `phone_number`: what the order must name.
        var recipientType: String = "none"

        /// A fixed denomination and what it costs (Amazon's $50 costs $52.50,
        /// measured): the value is what the card is worth, the price is what
        /// you pay.
        struct Package: Equatable, Sendable, Codable {
            let value: Double
            let price: Double
            let currency: String
        }

        static func parse(_ json: [String: Any]) -> Product? {
            guard let id = (json["slug"] as? String) ?? (json["id"] as? String), !id.isEmpty,
                  let name = json["name"] as? String, !name.isEmpty else { return nil }
            var product = Product(id: id, name: name,
                                  type: (json["type"] as? String) ?? "giftcards",
                                  categories: (json["categories"] as? [String]) ?? [],
                                  countries: (json["countries"] as? [String]) ?? [(json["country_code"] as? String) ?? ""].filter { !$0.isEmpty },
                                  currency: (json["currency"] as? String) ?? "USD",
                                  inStock: (json["in_stock"] as? Bool) ?? true)
            product.packages = packages(json["packages"])
            product.recipientType = (json["recipient_type"] as? String) ?? "none"
            return product
        }

        /// The detail's packages, smallest first.
        static func packages(_ any: Any?) -> [Package] {
            ((any as? [[String: Any]]) ?? []).compactMap { p -> Package? in
                guard let value = number(p["package_value"] ?? p["value"]) else { return nil }
                return Package(value: value, price: number(p["payment_price"]) ?? value,
                               currency: (p["payment_currency"] as? String) ?? (p["package_currency"] as? String) ?? "USD")
            }
            .sorted { $0.value < $1.value }
        }

        /// A gift card or a top-up: the kinds the sentence can say. An eSIM's
        /// packages are words (data and days), a later pass.
        var buyable: Bool { inStock && type != "esims" }

        /// The noun on the sentence's first line.
        var noun: String {
            switch type {
            case "refills": String(localized: "top-up")
            case "esims": String(localized: "eSIM")
            default: String(localized: "gift card")
            }
        }

        /// What the order must carry besides the card: a phone number for a top-up.
        var needsPhoneNumber: Bool { recipientType == "phone_number" }

        /// "$25 · $50 · $100 · $200": the values on offer, once the detail is read.
        var denominationsLine: String {
            packages.prefix(5).map { money($0.value) }.joined(separator: " · ")
        }

        func money(_ value: Double) -> String {
            BitrefillBuy.money(value, currency: currency)
        }

        /// The package for a value, if Bitrefill sells it at that value.
        func package(for value: Double) -> Package? {
            packages.first { abs($0.value - value) < 0.005 }
        }

        /// The exact value string the invoice names (`package_value`): "50",
        /// "7.5".
        static func valueText(_ value: Double) -> String {
            value.rounded() == value ? String(Int(value)) : String(value)
        }

        /// Why `value` cannot be bought, in a sentence; nil when it can.
        func refusal(_ value: Double) -> String? {
            if package(for: value) != nil { return nil }
            if value <= 0 { return String(localized: "Type an amount first") }
            if packages.isEmpty { return String(localized: "Reading what \(name) sells…") }
            return String(localized: "\(name) comes in \(denominationsLine)")
        }

        /// The value the sentence opens on: $50 where it is sold, else the
        /// middle of the list; nil until the detail is read.
        var suggestedValue: Double? {
            guard !packages.isEmpty else { return nil }
            for candidate in [50.0, 25.0, 20.0, 100.0, 10.0] where package(for: candidate) != nil { return candidate }
            return packages[packages.count / 2].value
        }
    }

    /// "$52.50", "€25", "SEK 12": the shared style, whole amounts without cents.
    static func money(_ value: Double, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "\(currency) \(value)"
    }

    /// A number however the API spells it: `50`, `50.0` or `"50"`.
    static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// The products in a search answer, in Bitrefill's order (popularity for
    /// an empty query, measured: the first 25 of 576 are Visa, Amazon,
    /// DoorDash, Apple…), the ones in stock.
    static func products(in answer: Any?) -> [Product] {
        guard let root = answer as? [String: Any] else { return [] }
        return ((root["products"] as? [[String: Any]]) ?? []).compactMap(Product.parse)
    }

    // MARK: - The seven groups

    /// **BITREFILL'S CATEGORIES, FOLDED TO SEVEN (prd §1473, user: "it makes
    /// more sense to use their own categories but not 21 different
    /// categories").** The search answers forty category slugs with counts
    /// (measured 2026-10-22); each product carries its own. The fold is by
    /// slug, never by Casberi's categories: a card is a spend and lands in
    /// Wallet whatever it is for.
    enum Group: String, CaseIterable, Sendable {
        case shopping, food, travel, games, entertainment, phone, money

        var title: String {
            switch self {
            case .shopping: String(localized: "Shopping")
            case .food: String(localized: "Food")
            case .travel: String(localized: "Travel")
            case .games: String(localized: "Games")
            case .entertainment: String(localized: "Entertainment")
            case .phone: String(localized: "Phone")
            case .money: String(localized: "Money")
            }
        }

        /// The cards people know it by, for the row under the sentence.
        var examples: String {
            switch self {
            case .shopping: "Amazon, Apple, Walmart, Target"
            case .food: "DoorDash, Starbucks, Uber Eats"
            case .travel: "Airbnb, Delta, Hotels.com, Uber"
            case .games: "Steam, PlayStation, Xbox, Roblox"
            case .entertainment: "Netflix, Spotify, StubHub"
            case .phone: String(localized: "mobile top-ups")
            case .money: String(localized: "prepaid Visa and Mastercard")
            }
        }

        /// Words a search for this group's cards answers to, beyond the
        /// popular list: the search matches names and keywords, 25 at a time.
        var searches: [String] {
            switch self {
            case .shopping: ["store", "amazon"]
            case .food: ["food", "restaurant"]
            case .travel: ["travel", "airline", "hotel"]
            case .games: ["games", "playstation"]
            case .entertainment: ["streaming", "netflix", "entertainment"]
            case .phone: []
            case .money: ["prepaid", "visa"]
            }
        }
    }

    /// Bitrefill's slugs, each under one of the seven. A slug not listed is
    /// Shopping, and a product's first listed category decides.
    static let slugGroups: [String: Group] = [
        "food": .food, "restaurants": .food, "food-delivery": .food, "groceries": .food,
        "travel": .travel, "accommodation": .travel, "flights": .travel, "cruises": .travel,
        "car-rental": .travel, "transportation": .travel, "online-travel-agencies": .travel,
        "bus": .travel, "train": .travel, "gasoline": .travel,
        "games": .games, "in-game-currencies": .games, "game-stores": .games,
        "entertainment": .entertainment, "streaming": .entertainment, "experiences": .entertainment,
        "literature": .entertainment,
        "refill": .phone, "pin": .phone, "bundles": .phone, "esim": .phone, "voip": .phone,
        "payment-cards": .money, "bitcoin": .money, "vpn": .money,
        "online-marketplaces": .shopping, "apparel": .shopping, "home": .shopping,
        "sports-n-outdoors": .shopping, "department-stores": .shopping, "health-beauty": .shopping,
        "multi-brand": .shopping, "kids": .shopping, "gifts": .shopping, "electronics": .shopping,
        "pets": .shopping, "cosmetics": .shopping, "spa": .shopping, "pharmacy": .shopping,
        "natural-herbal-care": .shopping
    ]

    static func group(of product: Product) -> Group {
        if product.type == "refills" || product.type == "esims" { return .phone }
        for slug in product.categories {
            if let g = slugGroups[slug] { return g }
        }
        return .shopping
    }

    /// The products in a group, in the order given (Bitrefill's), in stock,
    /// each once.
    static func products(in group: Group, of products: [Product]) -> [Product] {
        var seen = Set<String>()
        return products.filter { $0.buyable && Self.group(of: $0) == group && seen.insert($0.id).inserted }
    }

    /// Typing narrows whatever is showing: by name, then by slug.
    static func search(_ query: String, in products: [Product]) -> [Product] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return products }
        let starts = products.filter { $0.name.lowercased().hasPrefix(q) }
        let within = products.filter { !$0.name.lowercased().hasPrefix(q) && ($0.name.lowercased().contains(q) || $0.id.contains(q)) }
        return starts + within
    }

    /// "Amazon.com USA" → "Amazon.com": the country Bitrefill appends is not
    /// the name.
    static func shortName(_ name: String) -> String {
        var s = name
        for suffix in [" USA", " USD", " US", " United States", " International", " (US)"] where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Where you spend

    /// **CASBERI'S OWN LIST, FIRST (prd §1473).** Spending's places,
    /// Subscriptions and what was bought before, matched by name to the
    /// products found — "Amazon" against "Amazon.com USA", "Uber Eats"
    /// against "Uber Eats USA". The web suffix and a trailing country are
    /// not names.
    static func whereYouSpend(_ names: [String], in products: [Product]) -> [Product] {
        var out: [Product] = []
        var seen = Set<String>()
        for raw in names {
            let key = stem(raw)
            guard key.count >= 3 else { continue }
            let hits = products.filter { $0.buyable && stem($0.name) == key }
                .sorted { $0.name.count < $1.name.count }
            if let hit = hits.first ?? products.first(where: { $0.buyable && stem($0.name).hasPrefix(key + " ") }),
               !seen.contains(hit.id) {
                seen.insert(hit.id)
                out.append(hit)
            }
        }
        return out
    }

    /// "Amazon.com USA" → "amazon"; "Uber Eats US" → "uber eats"; "SQ *Delta
    /// Air Lines" → "delta air lines".
    static func stem(_ name: String) -> String {
        var s = name.lowercased()
        for prefix in ["sq *", "tst* ", "sp "] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        // The web suffix, wherever it stands ("Amazon.com USA").
        s = s.replacingOccurrences(of: #"\.(com|co\.uk|net|de|ca|fr|es|it)\b"#, with: "", options: .regularExpression)
        var words = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        while words.count > 1, let last = words.last, ["us", "usa", "usd", "uk", "gb", "ca", "au", "eu", "de", "fr", "international"].contains(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    // MARK: - Sign-in with the account (CAIP-122 / EIP-4361)

    /// The challenge a 402 carries under `extensions["sign-in-with-x"].info`
    /// (measured): the domain, the route as its URI, a nonce, the times, a
    /// statement and resources. The chain is the caller's pick from
    /// `supportedChains`; Base is `eip155:8453`.
    struct SignInChallenge: Equatable, Sendable {
        let domain: String
        let uri: String
        let version: String
        let nonce: String
        let issuedAt: String
        let expirationTime: String?
        let statement: String?
        let resources: [String]

        static func parse(_ any: Any?) -> SignInChallenge? {
            guard let root = any as? [String: Any],
                  let ext = (root["extensions"] as? [String: Any])?["sign-in-with-x"] as? [String: Any],
                  let info = ext["info"] as? [String: Any],
                  let domain = info["domain"] as? String, let uri = info["uri"] as? String,
                  let nonce = info["nonce"] as? String, let issuedAt = info["issuedAt"] as? String
            else { return nil }
            return SignInChallenge(domain: domain, uri: uri, version: (info["version"] as? String) ?? "1",
                                   nonce: nonce, issuedAt: issuedAt,
                                   expirationTime: info["expirationTime"] as? String,
                                   statement: info["statement"] as? String,
                                   resources: (info["resources"] as? [String]) ?? [])
        }

        /// The message the account signs, line for line as EIP-4361 lays it
        /// out and as Bitrefill rebuilds it from the header's fields
        /// (measured: the statement, the expiry and the resources must all
        /// be in it, and `Chain ID` is the bare number).
        func message(address: String, chainId: Int) -> String {
            var lines = ["\(domain) wants you to sign in with your Ethereum account:", address, ""]
            if let statement, !statement.isEmpty { lines += [statement, ""] }
            lines += ["URI: \(uri)", "Version: \(version)", "Chain ID: \(chainId)", "Nonce: \(nonce)", "Issued At: \(issuedAt)"]
            if let expirationTime { lines.append("Expiration Time: \(expirationTime)") }
            if !resources.isEmpty {
                lines.append("Resources:")
                lines += resources.map { "- \($0)" }
            }
            return lines.joined(separator: "\n")
        }

        /// The `SIGN-IN-WITH-X` header: the decomposed fields and the
        /// signature, as JSON, base64. `chainId` is the CAIP-2 id here
        /// (`eip155:8453`, measured: the bare number is refused) and the
        /// statement, expiry and resources ride along so the server can
        /// rebuild the very message that was signed.
        func header(address: String, chainId: Int, signature: [UInt8]) -> String? {
            var fields: [String: Any] = [
                "domain": domain, "address": address, "uri": uri, "version": version,
                "chainId": "eip155:\(chainId)", "type": "eip191", "nonce": nonce, "issuedAt": issuedAt,
                "signature": "0x" + signature.map { String(format: "%02x", $0) }.joined()
            ]
            if let statement { fields["statement"] = statement }
            if let expirationTime { fields["expirationTime"] = expirationTime }
            if !resources.isEmpty { fields["resources"] = resources }
            guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return nil }
            return data.base64EncodedString()
        }
    }

    /// What `/x402/connect` answers a good signature with: a token for the
    /// `X-Access-Token` header, good for `expires_in` seconds (7,200 measured).
    struct Session: Equatable, Sendable {
        let token: String
        let header: String
        let expires: Date

        /// The header the token rides, as the door names it (measured).
        static let tokenHeader = "X-Access-Token"

        var live: Bool { Date.now < expires.addingTimeInterval(-60) }

        static func parse(_ any: Any?, now: Date = .now) -> Session? {
            guard let root = any as? [String: Any], let token = root["token"] as? String, !token.isEmpty else { return nil }
            let seconds = number(root["expires_in"]) ?? 7200
            return Session(token: token, header: (root["token_header"] as? String) ?? tokenHeader,
                           expires: now.addingTimeInterval(seconds))
        }
    }

    // MARK: - The invoice

    /// `/x402/invoice/create` (measured): the invoice id, the price in USDC
    /// base units and in dollars, and how long it stands (30 minutes).
    struct Invoice: Equatable, Sendable {
        let id: String
        /// USDC base units, exactly what the payment moves.
        let priceUnits: String
        let priceUSD: Double
        let expiresMinutes: Int

        static func parse(_ any: Any?) -> Invoice? {
            guard let root = any as? [String: Any], let id = root["invoice_id"] as? String, !id.isEmpty,
                  let units = (root["price_usdc"] as? String) ?? (number(root["price_usdc"]).map { String(format: "%.0f", $0) }),
                  !units.isEmpty else { return nil }
            return Invoice(id: id, priceUnits: units, priceUSD: number(root["price_usd"]) ?? 0,
                           expiresMinutes: Int(number(root["expires_in_minutes"]) ?? 30))
        }

        var body: [String: Any] { ["invoice_id": id] }
    }

    /// The request that creates it: one product at one of its values; a
    /// top-up names the phone.
    static func createBody(product: Product, value: Double, phone: String? = nil) -> [String: Any] {
        var item: [String: Any] = ["product_id": product.id, "package_value": Product.valueText(value)]
        if let phone, !phone.isEmpty { item["refill_input"] = phone }
        return ["items": [item]]
    }

    // MARK: - The payment (x402, scheme "exact", USDC on Base)

    /// One way the 402 accepts payment (measured on `/x402/invoice/pay`):
    /// the exact amount in the asset's base units, the asset, who is paid,
    /// how long the authorization may stand, and the token's EIP-712 name
    /// and version.
    struct Requirement: Equatable, Sendable {
        let scheme: String
        let network: String
        let amount: String
        let asset: String
        let payTo: String
        let maxTimeoutSeconds: Int
        let name: String
        let version: String
        /// The entry as it came, echoed back as `accepted`.
        let raw: [String: AnySendableJSON]

        var chainId: Int? {
            guard network.hasPrefix("eip155:") else { return nil }
            return Int(network.dropFirst("eip155:".count))
        }

        static func parse(_ any: Any) -> Requirement? {
            guard let d = any as? [String: Any], let scheme = d["scheme"] as? String, let network = d["network"] as? String,
                  let amount = (d["amount"] as? String) ?? (d["maxAmountRequired"] as? String),
                  let asset = d["asset"] as? String, let payTo = d["payTo"] as? String else { return nil }
            let extra = (d["extra"] as? [String: Any]) ?? [:]
            return Requirement(scheme: scheme, network: network, amount: amount, asset: asset, payTo: payTo,
                               maxTimeoutSeconds: Int(number(d["maxTimeoutSeconds"]) ?? 1800),
                               name: (extra["name"] as? String) ?? "USD Coin", version: (extra["version"] as? String) ?? "2",
                               raw: AnySendableJSON.object(d))
        }

        /// Every requirement a 402 offers.
        static func all(in any: Any?) -> [Requirement] {
            guard let root = any as? [String: Any], let accepts = root["accepts"] as? [Any] else { return [] }
            return accepts.compactMap(parse)
        }

        /// The one this phone can pay: exact, on `chainId`, in `asset`.
        static func payable(in any: Any?, chainId: Int, asset: String) -> Requirement? {
            all(in: any).first { $0.scheme == "exact" && $0.chainId == chainId && $0.asset.lowercased() == asset.lowercased() }
        }
    }

    /// The `TransferWithAuthorization` the account signs (EIP-3009, as
    /// x402's exact scheme uses it): the typed data as `eth_signTypedData_v4`
    /// takes it, under the token's own domain.
    struct Authorization: Equatable, Sendable {
        let from: String
        let to: String
        let value: String
        let validAfter: String
        let validBefore: String
        /// 32 random bytes, hex.
        let nonce: String

        static func make(from: String, requirement: Requirement, now: Date = .now, nonce: [UInt8]) -> Authorization {
            Authorization(from: from, to: requirement.payTo, value: requirement.amount,
                          validAfter: "0",
                          validBefore: String(Int(now.timeIntervalSince1970) + requirement.maxTimeoutSeconds),
                          nonce: "0x" + nonce.map { String(format: "%02x", $0) }.joined())
        }

        func typedData(requirement: Requirement) -> [String: Any] {
            [
                "types": [
                    "EIP712Domain": [["name": "name", "type": "string"], ["name": "version", "type": "string"],
                                     ["name": "chainId", "type": "uint256"], ["name": "verifyingContract", "type": "address"]],
                    "TransferWithAuthorization": [["name": "from", "type": "address"], ["name": "to", "type": "address"],
                                                  ["name": "value", "type": "uint256"], ["name": "validAfter", "type": "uint256"],
                                                  ["name": "validBefore", "type": "uint256"], ["name": "nonce", "type": "bytes32"]]
                ],
                "primaryType": "TransferWithAuthorization",
                "domain": ["name": requirement.name, "version": requirement.version,
                           "chainId": requirement.chainId ?? 8453, "verifyingContract": requirement.asset],
                "message": ["from": from, "to": to, "value": value, "validAfter": validAfter, "validBefore": validBefore, "nonce": nonce]
            ]
        }

        var json: [String: Any] {
            ["from": from, "to": to, "value": value, "validAfter": validAfter, "validBefore": validBefore, "nonce": nonce]
        }
    }

    /// The payment as the `PAYMENT-SIGNATURE` header carries it (x402 v2):
    /// the version, the requirement accepted as it was offered, and the
    /// authorization with its signature, JSON, base64.
    static func paymentHeader(requirement: Requirement, authorization: Authorization, signature: [UInt8],
                              challenge: Any? = nil) -> String? {
        var payload: [String: Any] = [
            "x402Version": 2,
            "accepted": requirement.raw.mapValues { $0.value },
            "payload": [
                "signature": "0x" + signature.map { String(format: "%02x", $0) }.joined(),
                "authorization": authorization.json
            ]
        ]
        // The resource and the extensions, echoed as the 402 gave them (the
        // spec's rule; the reference client copies both).
        if let root = challenge as? [String: Any] {
            if let resource = root["resource"] { payload["resource"] = resource }
            if let extensions = root["extensions"] { payload["extensions"] = extensions }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
        return data.base64EncodedString()
    }

    /// Whether a pay answer took the payment (measured shape: `accepted`,
    /// `success`, or a status word).
    static func paymentAccepted(_ any: Any?) -> Bool {
        guard let root = any as? [String: Any] else { return false }
        if let ok = root["accepted"] as? Bool, ok { return true }
        if let ok = root["success"] as? Bool, ok { return true }
        if let status = root["status"] as? String, ["payment_confirmed", "payment_detected", "complete", "paid"].contains(status) { return true }
        return false
    }

    /// Why a 402 or an error answer refused, in Bitrefill's words when it has any.
    static func refusal(_ any: Any?, status: Int) -> String? {
        guard let root = any as? [String: Any] else { return status == 0 ? nil : "Bitrefill refused (\(status))" }
        for key in ["message", "error_description", "agent_instructions", "error"] {
            if let text = root[key] as? String, !text.isEmpty, text != "Payment required" { return text }
        }
        if let code = root["error_code"] as? String { return code.replacingOccurrences(of: "_", with: " ").lowercased() }
        return status == 0 ? nil : "Bitrefill refused (\(status))"
    }

    // MARK: - The order

    /// What the person needs once an order is delivered (core concepts):
    /// read ON OPEN, held while the sheet is open, never stored — a code on
    /// a synced row is money in plain text.
    struct Redemption: Equatable, Sendable {
        let code: String?
        let pin: String?
        let link: String?
        let instructions: String?
        let expires: String?

        var isEmpty: Bool { code == nil && link == nil && pin == nil }

        static func parse(_ info: Any?) -> Redemption? {
            guard let info = info as? [String: Any] else { return nil }
            func text(_ key: String) -> String? {
                (info[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            }
            let r = Redemption(code: text("code"), pin: text("pin"), link: text("link") ?? text("redemption_url") ?? text("url"),
                               instructions: text("instructions"), expires: text("expiration_date"))
            return r.isEmpty && r.instructions == nil ? nil : r
        }
    }

    /// An invoice's standing, from `/x402/invoice/status` or a row of
    /// `/x402/my/orders`: whether it is delivered, and the first order's
    /// redemption when it is.
    struct Standing: Equatable, Sendable {
        let delivered: Bool
        let failed: Bool
        let redemption: Redemption?

        static func parse(_ any: Any?) -> Standing? {
            guard let root = any as? [String: Any] else { return nil }
            let words = [root["delivery_status"], root["orders_delivery_status"], root["invoice_status"], root["status"]]
                .compactMap { $0 as? String }
            let delivered = words.contains { ["all_delivered", "delivered", "complete"].contains($0) }
            let failed = words.contains { ["failed", "refunded", "expired", "denied", "blocked", "payment_error"].contains($0) }
            // Orders at the root, or under `redemption_info.orders` (the
            // status route's shape for the paying wallet), each with its
            // own `redemption_info`.
            let nested = ((root["redemption_info"] as? [String: Any])?["orders"] as? [[String: Any]]) ?? []
            let orders = ((root["orders"] as? [[String: Any]]) ?? []) + nested
            let redemption = orders.lazy.compactMap { Redemption.parse($0["redemption_info"]) }.first
                ?? Redemption.parse(root["redemption_info"])
            return Standing(delivered: delivered || (redemption != nil && !redemption!.isEmpty), failed: failed, redemption: redemption)
        }

        /// The row for `invoiceID` in `/x402/my/orders`, when the list keys
        /// orders by invoice.
        static func parse(orders any: Any?, invoiceID: String) -> Standing? {
            guard let root = any as? [String: Any], let rows = root["orders"] as? [[String: Any]] else { return nil }
            let mine = rows.filter { row in
                [row["invoice_id"], row["invoiceId"], (row["invoice"] as? [String: Any])?["id"]].compactMap { $0 as? String }.contains(invoiceID)
            }
            guard !mine.isEmpty else { return nil }
            return parse(["orders": mine, "status": mine.allSatisfy { ($0["status"] as? String) == "delivered" } ? "delivered" : "pending"])
        }
    }

    /// The order's id out of its row's ref (`bitrefill:order:<invoice id>`,
    /// the §103 shape, so the sheet and the row are the ones every
    /// Bitrefill order wears).
    static func orderID(ref: String?) -> String? {
        guard let ref, ref.hasPrefix("bitrefill:order:") else { return nil }
        let id = String(ref.dropFirst("bitrefill:order:".count))
        return id.isEmpty ? nil : id
    }

    static func ref(invoiceID: String) -> String { "bitrefill:order:\(invoiceID)" }

    // MARK: - Words

    /// What Face ID says: the payment, and what it is for.
    static func faceWords(spoken: String, value: String, product: Product) -> String {
        String(localized: "Pay \(spoken) USDC to Bitrefill for a \(value) \(shortName(product.name)) \(product.noun)")
    }
}

/// JSON that can cross an actor: the 402's requirement, echoed back as it came.
indirect enum AnySendableJSON: Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null
    case array([AnySendableJSON]), object([String: AnySendableJSON])

    static func from(_ any: Any) -> AnySendableJSON {
        switch any {
        case let s as String: .string(s)
        case let n as NSNumber: CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let a as [Any]: .array(a.map(from))
        case let o as [String: Any]: .object(o.mapValues(from))
        default: .null
        }
    }

    static func object(_ dict: [String: Any]) -> [String: AnySendableJSON] { dict.mapValues(from) }

    var value: Any {
        switch self {
        case .string(let s): s
        case .number(let n): n.rounded() == n && abs(n) < 1e15 ? Int(n) : n
        case .bool(let b): b
        case .null: NSNull()
        case .array(let a): a.map(\.value)
        case .object(let o): o.mapValues(\.value)
        }
    }
}
