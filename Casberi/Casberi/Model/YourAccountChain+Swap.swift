import Foundation

/// **SWAP QUOTES, ASKED OF THE POOLS THEMSELVES (prd §1539, §1542).** Every
/// pool `YourAccountSwap.Book` names on the network is asked at once through
/// Multicall3, by the account's own node (`rpc`: the public nodes through
/// Tor, or your own node, §1517): every pool straight across, and every pool
/// into WETH or the network's dollar; then, on each venue, the best pool on
/// from there. The best output wins, its pools' fees are read for the words,
/// and the calls are written here, on the phone, with the minimum and the
/// deadline in them. No quote service is asked, so none can refuse, reroute
/// or see a swap before it is signed.
extension YourAccountChain {

    /// Every question in one `aggregate3`, in slices a node's call gas cap
    /// takes (measured: 63 quotes answer in one call on Base, in ~0.15s).
    static func aggregate(_ net: Network, _ calls: [(to: String, data: [UInt8])]) async throws -> [(ok: Bool, data: [UInt8])] {
        var out: [(ok: Bool, data: [UInt8])] = []
        var start = 0
        while start < calls.count {
            let slice = Array(calls[start..<min(start + 64, calls.count)])
            let hex = try await ethCall(net, to: YourAccountSwap.multicall3, data: YourAccountSwap.aggregate3(slice))
            guard let bytes = SafeABI.hexBytes(hex), let answers = YourAccountSwap.aggregate3Results(bytes),
                  answers.count == slice.count else {
                throw Failure(message: String(localized: "\(net.name) did not answer"))
            }
            out += answers
            start += slice.count
        }
        return out
    }

    /// The best route for `amount` of `sell` into `buy` on `net`, priced;
    /// nil when no pool trades it. Tokens are contracts, ETH as WETH.
    static func bestRoute(_ net: Network, sell: String, buy: String, amount: String) async throws -> YourAccountSwap.Priced? {
        typealias S = YourAccountSwap
        guard let book = S.book(net.chainId), S.isPositive(amount) else { return nil }
        func ask(_ asks: [S.Ask]) async throws -> [String?] {
            let calls = asks.compactMap(\.call)
            guard calls.count == asks.count else { return asks.map { _ in nil } }
            let answers = try await aggregate(net, calls)
            return zip(asks, answers).map { S.amountOut($0.venue.kind, ok: $1.ok, data: $1.data) }
        }
        let first = S.firstRound(book, sell: sell, buy: buy, amount: amount)
        let firstAnswers = try await ask(first)
        let second = S.secondRound(first, answers: firstAnswers, buy: buy)
        let secondAnswers = second.isEmpty ? [] : try await ask(second)
        let routes = S.priced(first, answers: firstAnswers, buy: buy) + S.priced(second, answers: secondAnswers, buy: buy)
        guard var best = S.best(routes, in: book) else { return nil }
        best = S.Priced(route: await withFees(best.route, net), out: best.out)
        return best
    }

    /// An Aerodrome route's pool fees, read off its pools (Slipstream's are
    /// each pool's own, v2's the factory's); a route whose fees cannot be
    /// read keeps none, and its words name the exchange alone. A Sushi
    /// route's pools are read here too, since its calls name them; one
    /// without them cannot be written ("This swap could not be written").
    private static func withFees(_ route: YourAccountSwap.Route, _ net: Network) async -> YourAccountSwap.Route {
        typealias S = YourAccountSwap
        let finds = route.hops.compactMap { S.poolCall(route.venue, $0) }
        guard finds.count == route.hops.count, let pools = try? await aggregate(net, finds) else { return route }
        let addresses = pools.map { $0.ok ? S.pool(fromAnswer: $0.data) : nil }
        if route.venue.kind == .sushi {
            let found = addresses.compactMap { $0 }
            guard found.count == route.hops.count else { return route }
            var r = route
            r.pools = found
            return r
        }
        let reads = zip(route.hops, addresses).compactMap { hop, pool in pool.flatMap { S.feeCall(route.venue, hop, pool: $0) } }
        guard reads.count == route.hops.count, let answers = try? await aggregate(net, reads) else { return route }
        let fees = answers.compactMap { $0.ok ? S.fee(route.venue, answer: $0.data) : nil }
        guard fees.count == route.hops.count else { return route }
        var r = route
        r.fees = fees
        return r
    }

    /// The best pool's price and calls for selling `amount` of `sell` for
    /// `buy`, the account as sender and receiver, on one network.
    static func swapQuote(_ net: Network, sell: YourAccountOp.Token, buy: YourAccountOp.Token,
                          amount: String, account: String) async throws -> YourAccountSwap.Quote {
        guard YourAccountSwap.supported(net), let book = YourAccountSwap.book(net.chainId) else {
            throw Failure(message: String(localized: "Swaps are not on \(net.name)"))
        }
        // WETH and ETH are one for one through the network's WETH, no pool
        // (prd §1559): exact, so the demo's estimate is the same.
        if let w = YourAccountSwap.wrap(sell: sell, buy: buy, chainId: net.chainId) {
            guard let q = YourAccountSwap.wrapQuote(w, amount: amount, account: account, chainId: net.chainId) else {
                throw Failure(message: String(localized: "This swap could not be written"))
            }
            return q
        }
        // The demo's estimate comes off its own prices (§1475), never a node.
        if YourAccountDemo.isDemo(account) {
            guard let q = YourAccountDemo.quote(sell: sell, buy: buy, amount: amount) else {
                throw Failure(message: String(localized: "No price for this in the demo"))
            }
            return q
        }
        let from = sell.contract?.lowercased() ?? book.weth
        let to = buy.contract?.lowercased() ?? book.weth
        let key = [String(net.chainId), sell.contract?.lowercased() ?? "eth", buy.contract?.lowercased() ?? "eth", amount, account.lowercased()]
            .joined(separator: "|")
        if let kept = await quotes.fresh(key) { return kept }
        guard let best = try await bestRoute(net, sell: from, buy: to, amount: amount) else {
            throw Failure(message: String(localized: "No pool on \(net.name) swaps \(sell.symbol) for \(buy.symbol)"))
        }
        let deadline = Int(Date().timeIntervalSince1970) + YourAccountSwap.deadlineSeconds
        guard let least = YourAccountSwap.minimum(best.out, bps: book.slippageBps),
              let calls = YourAccountSwap.calls(best.route, in: book, sellsETH: sell.contract == nil, buysETH: buy.contract == nil,
                                                amount: amount, minimum: least, account: account, deadline: deadline) else {
            throw Failure(message: String(localized: "This swap could not be written"))
        }
        let quote = YourAccountSwap.Quote(sellAmount: amount, buyAmount: best.out, minimumBuy: least, route: best.route, calls: calls)
        await quotes.keep(quote, key)
        return quote
    }

    /// **ONE QUOTE, ASKED ONCE (prd §1601).** The sentence's quote, its
    /// preview's and signing's assembly asked the pools for the same swap one
    /// after another, two to four round trips over Tor each; a quote younger
    /// than `quoteLife` is taken again. Never older: the preview, asked again
    /// every 40 seconds, asks the pools afresh, and every quote signed is
    /// still simulated against the chain first.
    static let quoteLife: TimeInterval = 20
    private static let quotes = Quotes()

    private actor Quotes {
        private var kept: [String: (quote: YourAccountSwap.Quote, at: Date)] = [:]
        func fresh(_ key: String) -> YourAccountSwap.Quote? {
            kept = kept.filter { -$0.value.at.timeIntervalSinceNow < YourAccountChain.quoteLife }
            return kept[key]?.quote
        }
        func keep(_ quote: YourAccountSwap.Quote, _ key: String) { kept[key] = (quote, Date()) }
    }

    @MainActor private static var ethPrices: [Int: (price: Double, at: Date)] = [:]
    /// A token's pool price, kept a minute as ETH's is (prd §1601): Move
    /// reads the holdings again on every return, and each price was two to
    /// four rounds over Tor.
    @MainActor private static var tokenPrices: [String: (price: Double, at: Date)] = [:]

    /// **A DOLLAR PRICE OFF THE POOLS (prd §1542; was Relay's price API).**
    /// ETH: what 0.01 ETH buys of the network's dollar, times a hundred, kept
    /// a minute. Any other token: what one whole token buys of ETH, at that.
    /// The pools' own fee and depth are in it, so it is what the token would
    /// fetch, never more. nil where nothing trades it.
    @MainActor
    static func exchangePrice(_ net: Network, _ token: YourAccountOp.Token) async -> Double? {
        guard let book = YourAccountSwap.book(net.chainId), !net.isTest else { return nil }
        if YourAccountDemo.isOn { return YourAccountDemo.price(token) }
        let ethPrice: Double
        if let kept = ethPrices[net.chainId], kept.at.timeIntervalSinceNow > -60 {
            ethPrice = kept.price
        } else {
            let dollar = YourAccountOp.dollar(on: net)
            guard let r = try? await bestRoute(net, sell: book.weth, buy: dollar.contract?.lowercased() ?? "", amount: "10000000000000000"),
                  let units = Double(r.out) else { return nil }
            ethPrice = units / pow(10, Double(dollar.decimals)) * 100
            guard ethPrice.isFinite, ethPrice > 0 else { return nil }
            ethPrices[net.chainId] = (ethPrice, .now)
        }
        guard let contract = token.contract?.lowercased() else { return ethPrice }
        let key = "\(net.chainId)|\(contract)"
        if let kept = tokenPrices[key], kept.at.timeIntervalSinceNow > -60 { return kept.price }
        let one = "1" + String(repeating: "0", count: max(token.decimals, 0))
        guard let r = try? await bestRoute(net, sell: contract, buy: book.weth, amount: one),
              let wei = Double(r.out) else { return nil }
        let price = wei / 1e18 * ethPrice
        guard price.isFinite, price > 0 else { return nil }
        tokenPrices[key] = (price, .now)
        return price
    }
}
