import Foundation

/// **A LIMIT ORDER, PLACED, FOLLOWED AND CANCELLED (prd §1673).** The order is
/// built on the phone (`YourAccountOrder`), CoW is told it and must name back
/// the id computed here, then one operation through the same path as every
/// account call (`privateCalls`: simulated as the account, refused if any
/// call fails, Face ID, the key change) wraps, approves and pre-signs it.
/// Cancel is `invalidateOrder` the same way. Every order placed here is kept
/// on this phone (`YourAccountOrders`), never synced, so the Wallet's Needs
/// you can say it is waiting and the receipt can follow it.
extension YourAccountChain {
    private static let cowService = "Your account"

    private static func cowURL(_ net: Network, _ path: String) -> String? {
        CowOrder.apiNetwork[net.chainId].map { "https://api.cow.fi/\($0)/api/v1/\(path)" }
    }

    /// One CoW call, the body kept whatever the status: CoW's refusals carry
    /// their reason (`description`), and its order id answers as a bare string.
    private static func cow(_ url: String, body: [String: Any]?) async -> (json: Any?, status: Int) {
        guard let u = URL(string: url) else { return (nil, 0) }
        var request = URLRequest(url: u)
        if let body, let payload = try? JSONSerialization.data(withJSONObject: body) {
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, http) = await IngestSupport.sendRequest(request, service: cowService) else { return (nil, 0) }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed), http.statusCode)
    }

    private static func cowRefusal(_ json: Any?, _ net: Network) -> Failure {
        let said = (json as? [String: Any])?["description"] as? String
        return Failure(message: said.map { String(localized: "CoW said: \($0)") }
                       ?? String(localized: "CoW did not answer on \(net.name)"))
    }

    /// Place the order: CoW takes it under the id this phone computed, then
    /// one operation pre-signs it. Kept as open once the operation landed,
    /// and once it was taken but not yet seen (prd §1988): CoW already holds
    /// the order, so it is followed, counted in `stillOpen`, cancellable and
    /// announced; `refreshOrders` settles it by CoW's word, which says
    /// expired when no pre-signature arrived before `validTo`.
    static func placeOrder(_ draft: YourAccountOrders.Draft, reason: String,
                           stage: @escaping @Sendable (Stage) async -> Void) async throws -> (sent: Sent, placed: YourAccountOrders.Placed) {
        let net = draft.network
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        guard YourAccountOrder.supported(net) else {
            throw Failure(message: String(localized: "CoW does not settle on \(net.name)"))
        }
        await stage(.preparing)
        // The approval is every open order's amount on this token, not this
        // one's alone (prd §1988), so CoW is asked first which still wait.
        await refreshOrders()
        let stillOpen = YourAccountOrder.cowToken(draft.sell, on: net, selling: true)
            .map { YourAccountOrders.stillOpen(chainId: net.chainId, token: $0) } ?? "0"
        let validTo = UInt32(Date().timeIntervalSince1970) + draft.seconds
        guard let order = YourAccountOrder.order(sell: draft.sell, buy: draft.buy, on: net, account: account,
                                                 sellUnits: draft.sellUnits, buyUnits: draft.buyUnits, validTo: validTo),
              let uid = YourAccountOrder.uid(order, owner: account, chainId: net.chainId),
              let calls = YourAccountOrder.calls(order: order, uid: uid, sellingETH: draft.sell.contract == nil, network: net,
                                                 stillOpen: stillOpen),
              let url = cowURL(net, "orders") else {
            throw Failure(message: String(localized: "This order could not be written"))
        }
        let (json, status) = await cow(url, body: YourAccountOrder.orderBody(order, owner: account))
        guard status == 201 || status == 200 else { throw cowRefusal(json, net) }
        // CoW must name the order this phone built, or nothing is signed.
        guard let said = json as? String, SafeABI.hexBytes(said) == uid else {
            throw Failure(message: String(localized: "CoW named a different order, so nothing was signed"))
        }
        let sent = try await privateCalls(calls, on: net, reason: reason, stage: stage)
        let placed = YourAccountOrders.Placed(draft: draft, uid: SafeABI.hex(uid), validTo: validTo)
        switch sent.outcome {
        case .landed, .pending: YourAccountOrders.keep(placed)
        case .dryRun: break
        }
        return (sent, placed)
    }

    /// Withdraw an order: `invalidateOrder(uid)`, one operation. An order
    /// that sold ETH also unwraps its WETH back to ETH (prd §1988), when the
    /// account holds it beyond what its other open ETH orders still need;
    /// otherwise the cancel goes alone rather than fail on a `withdraw`.
    static func cancelOrder(_ placed: YourAccountOrders.Placed, reason: String,
                            stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        var unwrap: (weth: String, units: String)?
        if placed.soldWETH, let net = placed.network, let account = YourAccountKey.address,
           let weth = YourAccountOrder.weth(chainId: net.chainId),
           let held = await balance(net, YourAccountOp.Token(symbol: "WETH", decimals: 18, contract: weth), of: account) {
            let others = YourAccountOrders.stillOpen(chainId: net.chainId, token: weth.lowercased(), excluding: placed.uid)
            if YourAccountOrder.atLeast(held, YourAccountOrder.plus(others, placed.sellUnits)) {
                unwrap = (weth, placed.sellUnits)
            }
        }
        guard let net = placed.network, let uid = SafeABI.hexBytes(placed.uid),
              let calls = YourAccountOrder.cancelCalls(uid: uid, unwrap: unwrap) else {
            throw Failure(message: String(localized: "This order could not be cancelled"))
        }
        let sent = try await privateCalls(calls, on: net, reason: reason, stage: stage)
        if case .landed = sent.outcome { YourAccountOrders.update(placed.uid) { $0.state = .cancelled } }
        return sent
    }

    /// Where an order stands, CoW's word, and what it paid out once filled.
    static func orderStanding(_ placed: YourAccountOrders.Placed) async -> (state: YourAccountOrders.State, paid: String?)? {
        guard let net = placed.network, let url = cowURL(net, "orders/" + placed.uid),
              let root = await cow(url, body: nil).json as? [String: Any],
              let status = root["status"] as? String else { return nil }
        let paid = (root["executedBuyAmount"] as? String).flatMap { $0 == "0" ? nil : $0 }
        switch status {
        case "fulfilled": return (.filled, paid)
        case "cancelled": return (.cancelled, nil)
        case "expired": return (.expired, nil)
        default: return (.open, nil)
        }
    }

    /// Ask CoW about every open order this phone placed, and keep its word.
    ///
    /// **Past its expiry is not unfilled (prd §1988).** An order can fill in
    /// its last minutes and be read after `validTo`; marking it expired
    /// unasked told the person their sale stayed put while the money had
    /// moved. CoW is asked first: filled or cancelled is its word, and only
    /// an order CoW calls open or expired, or will not answer for, is
    /// expired here.
    @discardableResult
    static func refreshOrders() async -> [YourAccountOrders.Placed] {
        for placed in YourAccountOrders.all where placed.state == .open {
            let standing = await orderStanding(placed)
            // No answer is not an answer: expired unasked only a day past
            // its end, so an offline phone never calls a filled order unfilled.
            let now = UInt32(Date().timeIntervalSince1970)
            if placed.validTo < now,
               standing?.state == .open || standing?.state == .expired || (standing == nil && placed.validTo + 86_400 < now) {
                YourAccountOrders.update(placed.uid) {
                    $0.state = .expired
                    $0.settledAt = .now
                }
                announce(placed, state: .expired, paid: nil)
                continue
            }
            guard let (state, paid) = standing, state != .open else { continue }
            YourAccountOrders.update(placed.uid) {
                $0.state = state
                if let paid { $0.paidUnits = paid }
                $0.settledAt = .now
            }
            announce(placed, state: state, paid: paid)
        }
        return YourAccountOrders.all
    }

    /// A limit order that filled or ended, told when you are away from
    /// Casberi (prd §1881): "0.5 ETH for 1,612 USDC", or what stayed put.
    ///
    /// An ETH order that ends unfilled leaves WETH, not ETH (prd §1988):
    /// placing it wrapped the ETH and an expiry calls nothing, so the words
    /// name what the account holds.
    private static func announce(_ placed: YourAccountOrders.Placed, state: YourAccountOrders.State, paid: String?) {
        let left = state != .filled && placed.soldWETH ? "WETH" : placed.sellSymbol
        let sold = YourAccountOrders.words(placed.sellUnits, decimals: placed.sellDecimals) + " " + left
        let body: String
        let kind: NotifyKind
        if state == .filled {
            let got = YourAccountOrders.words(paid ?? placed.buyUnits, decimals: placed.buyDecimals) + " " + placed.buySymbol
            body = String(localized: "\(sold) for \(got)")
            kind = .orderFilled
        } else {
            body = String(localized: "\(sold) stayed in your account")
            kind = .orderEnded
        }
        Task { await Notifications.outcome(kind, id: "order:" + placed.uid, place: "CoW Swap",
                                           body: body, mark: "CoW Swap") }
    }
}

/// The limit orders this phone placed (prd §1673 item 7): device-only, the
/// newest 50, read by Move's receipt and the Wallet's Needs you.
enum YourAccountOrders {
    enum State: String, Codable, Sendable { case open, filled, cancelled, expired }

    /// What the sentence asked for, before CoW and Face ID.
    struct Draft: Equatable, Sendable {
        let network: YourAccountOp.Network
        let sell: YourAccountOp.Token
        let buy: YourAccountOp.Token
        let sellUnits: String
        /// At least this comes back, or the order does not fill.
        let buyUnits: String
        /// The token "when … is", and its price as the sentence said it.
        let pricedSymbol: String
        let priceWords: String
        var seconds: UInt32 = YourAccountOrder.defaultSeconds
    }

    struct Placed: Codable, Equatable, Identifiable, Sendable {
        let uid: String
        let chainId: Int
        let sellSymbol: String
        let sellDecimals: Int
        let sellUnits: String
        let buySymbol: String
        let buyDecimals: Int
        let buyUnits: String
        let pricedSymbol: String
        let priceWords: String
        let validTo: UInt32
        let placedAt: Date
        var state: State = .open
        var paidUnits: String? = nil
        var settledAt: Date? = nil
        /// The token CoW pulls from the account, lowercased: WETH when ETH
        /// was sold (prd §1988). Nil on an order kept before it was recorded.
        var sellToken: String? = nil
        /// ETH was sold, so the account wrapped it: what stays when the
        /// order does not fill is WETH (prd §1988).
        var wrapped: Bool? = nil

        /// Whether the account wrapped ETH for this order; an order kept
        /// before `wrapped` was recorded sold ETH when its symbol says so.
        var soldWETH: Bool { wrapped ?? (sellSymbol == "ETH") }

        /// The token the approval is on; an older order knows it only when
        /// it sold ETH.
        var pulledToken: String? {
            sellToken ?? (soldWETH ? YourAccountOrder.weth(chainId: chainId)?.lowercased() : nil)
        }

        var id: String { uid }
        var network: YourAccountOp.Network? { YourAccountOp.networks.first { $0.chainId == chainId } }
        var expires: Date { Date(timeIntervalSince1970: TimeInterval(validTo)) }

        init(draft: Draft, uid: String, validTo: UInt32) {
            self.uid = uid
            chainId = draft.network.chainId
            sellSymbol = draft.sell.symbol
            sellDecimals = draft.sell.decimals
            sellUnits = draft.sellUnits
            buySymbol = draft.buy.symbol
            buyDecimals = draft.buy.decimals
            buyUnits = draft.buyUnits
            pricedSymbol = draft.pricedSymbol
            priceWords = draft.priceWords
            self.validTo = validTo
            placedAt = .now
            sellToken = YourAccountOrder.cowToken(draft.sell, on: draft.network, selling: true)
            wrapped = draft.sell.contract == nil
        }
    }

    /// Base units as a person reads them: "0.5", "1,612.04", at most four
    /// places after the point.
    static func words(_ units: String, decimals: Int) -> String {
        guard let raw = Decimal(string: units) else { return units }
        var scale = Decimal(1)
        for _ in 0..<max(0, decimals) { scale *= 10 }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        return f.string(from: NSDecimalNumber(decimal: raw / scale)) ?? units
    }

    static let key = "move.orders.v1"
    static let cap = 50
    static let refPrefix = "wallet:order:"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Placed]?

    static var all: [Placed] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let read = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Placed].self, from: $0) } ?? []
        cache = read
        return read
    }

    /// Orders waiting to fill, newest first.
    static var open: [Placed] { all.filter { $0.state == .open }.sorted { $0.placedAt > $1.placedAt } }

    /// What the open, unexpired orders on `token` still need approved, in
    /// base units (prd §1988): a new order's approval adds it, a cancel's
    /// unwrap leaves it.
    static func stillOpen(chainId: Int, token: String, excluding uid: String? = nil) -> String {
        let now = UInt32(Date().timeIntervalSince1970)
        return all.filter { $0.state == .open && $0.validTo > now && $0.chainId == chainId
                            && $0.uid != uid && $0.pulledToken == token.lowercased() }
            .reduce("0") { YourAccountOrder.plus($0, $1.sellUnits) }
    }

    private static func save(_ list: [Placed]) {
        var list = list
        if list.count > cap { list.removeFirst(list.count - cap) }
        lock.lock(); cache = list; lock.unlock()
        if let data = try? JSONEncoder().encode(list) { DefaultsWrite.set(data, forKey: key) }
    }

    static func keep(_ placed: Placed) { save(all.filter { $0.uid != placed.uid } + [placed]) }

    static func update(_ uid: String, _ change: (inout Placed) -> Void) {
        var list = all
        guard let i = list.firstIndex(where: { $0.uid == uid }) else { return }
        change(&list[i])
        save(list)
    }

    /// "1 ETH for USDC at $2,400", the row's and the receipt's name; when
    /// neither token is a dollar, "1 AERO for ETH at 1 AERO = 0.0004 ETH".
    static func title(_ p: Placed) -> String {
        let sold = YourAccountOp.spoken(p.sellUnits, decimals: p.sellDecimals)
        return String(localized: "\(sold) \(p.sellSymbol) for \(p.buySymbol) at \(p.priceTerms)")
    }

    /// **A rate, not a price, when neither token is a dollar (prd §1988).**
    /// `buyUnits` fixed the rate from the sold token's dollar price at
    /// placement, so "when ETH is $2,400" promised a trigger the order does
    /// not hold: it fills at that rate whatever either is worth in dollars.
    /// The words say the rate, at most six significant figures, rounded
    /// down so it never promises more than the order's minimum.
    static func rateWords(sellUnits: String, sellDecimals: Int, sellSymbol: String,
                          buyUnits: String, buyDecimals: Int, buySymbol: String) -> String? {
        guard let s = Decimal(string: sellUnits), let b = Decimal(string: buyUnits), s > 0, b > 0 else { return nil }
        var sScale = Decimal(1), bScale = Decimal(1)
        for _ in 0..<max(0, sellDecimals) { sScale *= 10 }
        for _ in 0..<max(0, buyDecimals) { bScale *= 10 }
        let rate = (b / bScale) / (s / sScale)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = 6
        f.roundingMode = .down
        guard let n = f.string(from: NSDecimalNumber(decimal: rate)) else { return nil }
        return String(localized: "1 \(sellSymbol) = \(n) \(buySymbol)")
    }

    /// Whether neither token is a dollar, by symbol (an order kept on the
    /// phone carries no buy contract): the rate case (prd §1988).
    static func isRate(sellSymbol: String, buySymbol: String) -> Bool {
        !YourAccountOrder.isDollarSymbol(sellSymbol) && !YourAccountOrder.isDollarSymbol(buySymbol)
    }
}

extension YourAccountOrders.Placed {
    /// Neither token a dollar: the order holds a rate (prd §1988).
    var isRate: Bool { YourAccountOrders.isRate(sellSymbol: sellSymbol, buySymbol: buySymbol) }

    /// "1 AERO = 0.0004 ETH" for a rate order, nil otherwise.
    var rateWords: String? {
        guard isRate else { return nil }
        return YourAccountOrders.rateWords(sellUnits: sellUnits, sellDecimals: sellDecimals, sellSymbol: sellSymbol,
                                           buyUnits: buyUnits, buyDecimals: buyDecimals, buySymbol: buySymbol)
    }

    /// What the order holds, after "at": the rate, or the price as typed.
    var priceTerms: String { rateWords ?? priceWords }
}

extension YourAccountOrders.Draft {
    /// Neither token a dollar: the order holds a rate (prd §1988).
    var isRate: Bool {
        !YourAccountOrder.isDollar(sell, on: network) && !YourAccountOrder.isDollar(buy, on: network)
    }

    /// "1 AERO = 0.0004 ETH" for a rate order, nil otherwise.
    var rateWords: String? {
        guard isRate else { return nil }
        return YourAccountOrders.rateWords(sellUnits: sellUnits, sellDecimals: sell.decimals, sellSymbol: sell.symbol,
                                           buyUnits: buyUnits, buyDecimals: buy.decimals, buySymbol: buy.symbol)
    }
}
