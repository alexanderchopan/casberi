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
    /// one operation pre-signs it. Kept as open once the operation landed.
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
        let validTo = UInt32(Date().timeIntervalSince1970) + draft.seconds
        guard let order = YourAccountOrder.order(sell: draft.sell, buy: draft.buy, on: net, account: account,
                                                 sellUnits: draft.sellUnits, buyUnits: draft.buyUnits, validTo: validTo),
              let uid = YourAccountOrder.uid(order, owner: account, chainId: net.chainId),
              let calls = YourAccountOrder.calls(order: order, uid: uid, sellingETH: draft.sell.contract == nil, network: net),
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
        if case .landed = sent.outcome { YourAccountOrders.keep(placed) }
        return (sent, placed)
    }

    /// Withdraw an order: `invalidateOrder(uid)`, one operation.
    static func cancelOrder(_ placed: YourAccountOrders.Placed, reason: String,
                            stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let net = placed.network, let uid = SafeABI.hexBytes(placed.uid),
              let calls = YourAccountOrder.cancelCalls(uid: uid) else {
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
    @discardableResult
    static func refreshOrders() async -> [YourAccountOrders.Placed] {
        for placed in YourAccountOrders.all where placed.state == .open {
            if placed.validTo < UInt32(Date().timeIntervalSince1970) {
                YourAccountOrders.update(placed.uid) { $0.state = .expired }
                continue
            }
            guard let (state, paid) = await orderStanding(placed), state != .open else { continue }
            YourAccountOrders.update(placed.uid) {
                $0.state = state
                if let paid { $0.paidUnits = paid }
                $0.settledAt = .now
            }
        }
        return YourAccountOrders.all
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
        }
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

    /// "1 ETH for USDC at $2,400", the row's and the receipt's name.
    static func title(_ p: Placed) -> String {
        let sold = YourAccountOp.spoken(p.sellUnits, decimals: p.sellDecimals)
        return String(localized: "\(sold) \(p.sellSymbol) for \(p.buySymbol) at \(p.priceWords)")
    }
}
