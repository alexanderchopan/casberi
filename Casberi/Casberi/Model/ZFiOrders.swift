import Foundation

/// The orders a watched wallet holds on zFi's boards (2026-10-12, prd §1281):
/// the app half of `ZFiWire`. Rides the watched wallets like Aztec's stakes:
/// no account, no key, keyless `eth_call`s through `WalletApprovals`'
/// mainnet pool — one per board, then each token's symbol and decimals.
///
/// An order's escrow has left the wallet's balance, so without this a wallet
/// that listed 2 ETH reads as one that spent it. Holdings' Positions states
/// each order in its own units, never priced: an escrow comes back whole on
/// a cancel, but what a fill pays depends on a price nobody quoted here.
enum ZFiOrders {
    private static let network = "eth-mainnet"

    struct Book: Equatable, Sendable {
        var orders: [ZFiWire.Order] = []
        var tokens: [String: ZFiWire.Token] = [:]
        /// False when some board could not be read: what was found is true,
        /// and what was not is not yet known.
        var complete = true
        var isEmpty: Bool { orders.isEmpty }
    }

    private static let cache = CoalescingCache<Book>()

    /// nil when no board could be read. Five minutes fresh: an order moves
    /// when someone fills it, and the boards are read whole each time.
    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty else { return Book() }
        let holders = Set(addresses.map { $0.lowercased() })
        let key = holders.sorted().joined(separator: ",")
        return await cache.value(key: key, ttl: 300) {
            await fetchBook(holders: holders)
        }
    }

    private static func fetchBook(holders: Set<String>) async -> Book? {
        async let v2 = swapOrders(board: ZFiWire.swapboard, holders: holders) {
            ZFiWire.swapOrders(reply: $0, firstID: $1, holders: holders)
        }
        async let v1 = swapOrders(board: ZFiWire.swapboardV1, holders: holders) {
            ZFiWire.swapOrdersV1(reply: $0, firstID: $1, holders: holders)
        }
        async let lots = ranged(board: ZFiWire.dutchboard, call: ZFiWire.listingsCall) {
            ZFiWire.auctions(reply: $0, holders: holders)
        }
        async let standing = ranged(board: ZFiWire.floorboard, call: ZFiWire.bidsCall) {
            ZFiWire.bids(reply: $0, holders: holders)
        }
        let reads = await [v2, v1, lots, standing]
        guard reads.contains(where: { $0 != nil }) else { return nil }
        var book = Book()
        book.complete = !reads.contains { $0 == nil }
        book.orders = reads.compactMap { $0 }.flatMap { $0 }
        // Waiting money first, then the newest.
        book.orders.sort {
            let a = ZFiWire.needsYou($0), b = ZFiWire.needsYou($1)
            return a != b ? a : $0.id > $1.id
        }
        let wanted = Set(book.orders.flatMap { [$0.escrowToken, $0.otherToken] }).subtracting([ZFiWire.ether])
        book.tokens = await tokens(wanted)
        if book.tokens.count < wanted.count { book.complete = false }
        return book
    }

    private static let tokensKey = "zfi.tokens.v1"

    /// Each token's symbol and decimals, read once and kept: neither changes
    /// for a deployed token, and a read the host drops (measured 2026-10-12:
    /// one pass lost Z's, the next read it) would otherwise leave its row
    /// without a name or an amount. A token that cannot be read is left out.
    private static func tokens(_ wanted: Set<String>) async -> [String: ZFiWire.Token] {
        let d = UserDefaults.standard
        var stored = d.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        var out: [String: ZFiWire.Token] = [:]
        for token in wanted {
            if let entry = stored[token], let bar = entry.lastIndex(of: "|"),
               let decimals = Int(entry[entry.index(after: bar)...]) {
                out[token] = ZFiWire.Token(symbol: String(entry[..<bar]), decimals: decimals)
                continue
            }
            async let s = call(token, ZFiWire.symbolCall)
            async let dec = call(token, ZFiWire.decimalsCall)
            guard let symbol = ZFiWire.symbol(reply: await s) else { continue }
            // An NFT collection answers no `decimals()` (its amounts are
            // counts), and a dropped read looks the same, so only a token
            // with both is kept; the other is named and asked again.
            let decimals = ZFiWire.decimals(reply: await dec)
            out[token] = ZFiWire.Token(symbol: symbol, decimals: decimals)
            if let decimals { stored[token] = "\(symbol)|\(decimals)" }
        }
        d.set(stored, forKey: tokensKey)
        return out
    }

    /// A Swapboard read whole, in pages of `ZFiWire.page` ids.
    private static func swapOrders(board: String, holders: Set<String>,
                                   decode: @Sendable (String?, Int) -> [ZFiWire.Order]?) async -> [ZFiWire.Order]? {
        guard let n = ZFiWire.count(reply: await call(board, ZFiWire.nextOrderId)) else { return nil }
        var out: [ZFiWire.Order] = []
        for from in stride(from: 0, to: n, by: ZFiWire.page) {
            guard let page = decode(await call(board, ZFiWire.ordersCall(from: from, to: min(n, from + ZFiWire.page))), from)
            else { return nil }
            out += page
        }
        return out
    }

    /// A Dutchboard or Floorboard read whole, in pages.
    private static func ranged(board: String, call make: (Int, Int) -> String,
                               decode: @Sendable (String?) -> [ZFiWire.Order]?) async -> [ZFiWire.Order]? {
        guard let n = ZFiWire.count(reply: await call(board, ZFiWire.nextId)) else { return nil }
        var out: [ZFiWire.Order] = []
        for from in stride(from: 0, to: n, by: ZFiWire.page) {
            guard let page = decode(await call(board, make(from, min(n, from + ZFiWire.page)))) else { return nil }
            out += page
        }
        return out
    }

    private static func call(_ to: String, _ data: String) async -> String? {
        await read("eth_call", [["to": to, "data": data], "latest"]) as? String
    }

    /// One read through the Wallet's mainnet pool, asked up to four times
    /// over about three seconds: `rpc.mevblocker.io` fails in streaks
    /// (measured for Aztec's reads, prd §1277).
    private static func read(_ method: String, _ params: [Any]) async -> Any? {
        let pauses: [Int] = [300, 800, 1_600]
        for attempt in 0...pauses.count {
            if let result = await WalletApprovals.rpcRead(network: network, method: method, params: params) {
                return result
            }
            if attempt < pauses.count { try? await Task.sleep(for: .milliseconds(pauses[attempt])) }
        }
        return nil
    }

    #if DEBUG
    /// `-zfiOrdersProbe <0x wallet>` — one wallet's orders on zFi's boards,
    /// read without watching it, one NSLog line each.
    static func probe(address: String) async -> [String] {
        guard let book = await book(addresses: [address]) else { return ["book UNREACHABLE"] }
        var lines = book.orders.map { o in
            "\(o.kind.rawValue) #\(o.id) | \(ZFiWire.title(o, book.tokens)) | "
                + "\(ZFiWire.phrase(o.escrowRaw, o.escrowToken, book.tokens, isNFT: o.escrowIsNFT) ?? "?") in escrow | "
                + "\(ZFiWire.state(o, book.tokens))\(ZFiWire.needsYou(o) ? " | needs you" : "")"
        }
        lines.append("\(book.orders.count) orders | complete=\(book.complete)")
        return lines
    }
    #endif
}
