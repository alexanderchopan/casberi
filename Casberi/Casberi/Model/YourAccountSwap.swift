import Foundation

/// **YOUR ACCOUNT'S SWAP, STRAIGHT TO THE EXCHANGES (prd §1539, §1542;
/// replacing §1440's Relay).** No middleman: the phone asks every pool it
/// knows on the network itself — Uniswap v3 on Base, Ethereum and Robinhood
/// Chain; Aerodrome's Slipstream and v2 pools on Base — through the account's
/// own node, takes the best output, and writes the swap's calls itself. The
/// account signs those calls in its own operation, beside any sends, so Add
/// and Sweep batch swaps as before.
///
/// The phone builds every byte now, so the rules are the builder's and are
/// checked again before anything is signed (`checked`):
///
/// 1. **Where it goes.** Every call goes to an exchange router pinned below
///    (each address read on chain 2026-10-26: code there, its `factory()` and
///    `WETH9()` the ones named here, its quoter on the same factory), or is
///    the sold token's own `approve` naming that router.
/// 2. **How much.** ETH sent is exactly the amount sold; a token approved is
///    exactly the amount sold, to exactly the router that spends it.
/// 3. **What comes back.** The swap's own minimum is the quote less the
///    network's slippage limit (`Book.slippageBps`), written into the call,
///    and proven by `YourAccountChain` before Face ID: the whole operation is
///    simulated (`eth_simulateV1`) and refused unless every swap pays the
///    account at least that minimum.
/// 4. **When.** Every router call carries a deadline (`deadlineSeconds`), so
///    an operation that sat unsent cannot fill at a stale price later.
///
/// ETH is swapped as WETH by the routers' own wrapping: ETH sold is sent with
/// the call and wrapped by the router; ETH bought is paid to the router and
/// unwrapped to the account in the same call (`unwrapWETH9`, or Aerodrome
/// v2's `swapExactTokensForETH`).
///
/// Pure (Foundation, `SafeABI`, `YourAccount`'s encoders): the requests are
/// `YourAccountChain`'s (`YourAccountChain+Swap.swift`), and
/// `direct-swap-selftest.sh` reads this whole file with no network.
enum YourAccountSwap {
    typealias Op = YourAccountOp

    /// Relay's word for the network's own coin, still spoken by Receive from
    /// another network (§1453, §1470), which Relay carries.
    static let native = "0x0000000000000000000000000000000000000000"

    static func currency(_ token: Op.Token) -> String {
        token.contract?.lowercased() ?? native
    }

    // MARK: - The exchanges, pinned

    enum Kind: String, Sendable {
        /// Uniswap v3: QuoterV2 and SwapRouter02; a pool is its fee tier.
        case uniswap
        /// Aerodrome Slipstream (concentrated liquidity): a pool is its tick spacing.
        case slipstream
        /// Aerodrome's v2 pools: a pool is stable (1) or volatile (0).
        case aerodromeV2
        /// SushiSwap v3, a Uniswap v3 fork with no swap router of its own on
        /// Robinhood: a pool is its fee tier, quoted by Sushi's QuoterV2 (the
        /// same call as Uniswap's), swapped through Sushi's RedSnwapper
        /// handing the tokens to its RouteProcessor (`Venue.executor`).
        case sushi

        /// Whether a pool's fee is its tier, the step itself, read off nothing.
        var feeIsTier: Bool { self == .uniswap || self == .sushi }
    }

    /// One place to swap on one network: who quotes, who swaps, which pools.
    struct Venue: Equatable, Hashable, Sendable {
        let kind: Kind
        /// Asked for the quote (for Aerodrome v2, the router's `getAmountsOut`).
        let quoter: String
        /// The only contract a swap's calls reach, and the only spender approved.
        let router: String
        let factory: String
        /// The pools asked: fee tiers, tick spacings, or stable/volatile.
        let steps: [Int]
        /// Sushi's RouteProcessor, which the router hands the tokens to and
        /// which swaps them in the pools; nil for every other venue.
        var executor: String? = nil
        /// The exchange's name, as the sentence says it.
        var exchange: String {
            switch kind {
            case .uniswap: "Uniswap"
            case .sushi: "Sushi"
            case .slipstream, .aerodromeV2: "Aerodrome"
            }
        }
    }

    /// One network's exchanges, its WETH, the tokens a two-pool route passes
    /// through, and how far a fill may fall below its quote.
    struct Book: Equatable, Sendable {
        let chainId: Int
        let weth: String
        /// A route may pass through one of these: WETH and the network's dollar.
        let hubs: [String]
        let venues: [Venue]
        /// The least a swap pays, as the quote less this many basis points.
        let slippageBps: Int
    }

    /// Multicall3, at one address on every network the account is on (its
    /// code read on all three, 2026-10-26): every pool is asked in one call.
    static let multicall3 = "0xca11bde05977b3631167028862be2a173976ca11"

    /// Uniswap's four fee tiers, in millionths: 0.01%, 0.05%, 0.3%, 1%.
    static let uniswapFees = [100, 500, 3000, 10000]
    /// Slipstream's tick spacings; each pool's fee is its own, read off it.
    static let slipstreamSpacings = [1, 50, 100, 200, 2000]

    /// **Base.** Uniswap v3 from Uniswap's own deployments page
    /// (developers.uniswap.org, "v3 Base deployments": UniswapV3Factory
    /// 0x33128a8f…, QuoterV2 0x3d4e44Eb…, SwapRouter02 0x2626664c…).
    /// Aerodrome Slipstream's three deployments, each a factory with its own
    /// quoter and router, from Aerodrome's repository (github.com/
    /// aerodrome-finance/slipstream, README "Deployment": the initial one,
    /// Gauge Caps, and Gauges V3; WETH/USDC pools stand in all three).
    /// Aerodrome v2's Router and PoolFactory from Aerodrome's contracts
    /// repository (github.com/aerodrome-finance/contracts, README), the
    /// router's `defaultFactory()` read on chain. Every router's `WETH9()`
    /// (v2: `weth()`) reads 0x4200…0006.
    ///
    /// Slippage 0.5%: Base's sequencer orders by fee, not by a public
    /// mempool's bidding, and measured direct quotes sat within 0.12% of
    /// each other (prd §1539).
    static let base = Book(
        chainId: 8453,
        weth: "0x4200000000000000000000000000000000000006",
        hubs: ["0x4200000000000000000000000000000000000006", "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"],
        venues: [
            Venue(kind: .uniswap, quoter: "0x3d4e44eb1374240ce5f1b871ab261cd16335b76a",
                  router: "0x2626664c2603336e57b271c5c0b26f421741e481",
                  factory: "0x33128a8fc17869897dce68ed026d694621f6fdfd", steps: uniswapFees),
            Venue(kind: .slipstream, quoter: "0x254cf9e1e6e233aa1ac962cb9b05b2cfeaae15b0",
                  router: "0xbe6d8f0d05cc4be24d5167a3ef062215be6d18a5",
                  factory: "0x5e7bb104d84c7cb9b682aac2f3d509f5f406809a", steps: slipstreamSpacings),
            Venue(kind: .slipstream, quoter: "0x3d4c22254f86f64b7ec90ab8f7aec1fbfd271c6c",
                  router: "0xcbbb8035cac7d4b3ca7abb74cf7bdf900215ce0d",
                  factory: "0xade65c38cd4849adba595a4323a8c7ddfe89716a", steps: slipstreamSpacings),
            Venue(kind: .slipstream, quoter: "0x514c8b5f54112481e28028f1166bd78501089259",
                  router: "0x698cb2b6dd822994581fea6ea4fc755d1363a92f",
                  factory: "0xf8f2eb4940cfe7d13603dddd87f123820fc061ef", steps: slipstreamSpacings),
            Venue(kind: .aerodromeV2, quoter: "0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43",
                  router: "0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43",
                  factory: "0x420dd381b31aef6683db6b902084cb0ffece40da", steps: [1, 0]),
        ],
        slippageBps: 50)

    /// **Ethereum.** Uniswap v3 from Uniswap's deployments page ("v3
    /// Ethereum deployments": UniswapV3Factory 0x1F98431c…, QuoterV2
    /// 0x61fFE014…, SwapRouter02 0x68b34658…).
    ///
    /// Slippage 0.3%, tighter than Base: Ethereum's public mempool is where a
    /// swap is sandwiched, and what a sandwich can take is exactly the room
    /// between the quote and the minimum. A fill that moves further fails,
    /// and is refused before Face ID when the simulation already sees it.
    static let ethereum = Book(
        chainId: 1,
        weth: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
        hubs: ["0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"],
        venues: [
            Venue(kind: .uniswap, quoter: "0x61ffe014ba17989e743c5f6cb21bf9697530b21e",
                  router: "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45",
                  factory: "0x1f98431c8ad98523631ae4a59f267346ea31f984", steps: uniswapFees),
        ],
        slippageBps: 30)

    /// **Robinhood Chain.** Uniswap v3 from Uniswap's deployments page ("v3
    /// Robinhood Chain deployments": UniswapV3Factory 0x1f7d7550…, QuoterV2
    /// 0x33e885ed…, SwapRouter02 0xcaf681a6…); WETH is the router's own
    /// `WETH9()`. Measured 2026-10-26: its WETH/USDG pools hold about $10M,
    /// 0.1 ETH quoting within 0.01% across the 0.01% and 0.05% tiers.
    ///
    /// SushiSwap v3 from Sushi's own config (github.com/sushi-labs/sushi,
    /// `sushiswap-v3.ts`: factory 0xe51960f1…, QuoterV2 0x3e290e5e…;
    /// `red-snwapper.ts`: RedSnwapper 0x8e6fd69a…) and its web app's
    /// direct-pool swap (sushi-labs/sushiswap, `lib/swap/direct-pool`:
    /// RouteProcessor 0x0e867974…). Measured 2026-10-28: MUSEGOD's only pool
    /// on the network is Sushi's MUSEGOD/WETH 1% (~$93K), so without it "No
    /// pool on Robinhood swaps MUSEGOD for ETH"; Sushi's own WETH/USDG pools
    /// carry it on to USDG.
    static let robinhood = Book(
        chainId: 4663,
        weth: "0x0bd7d308f8e1639fab988df18a8011f41eacad73",
        hubs: ["0x0bd7d308f8e1639fab988df18a8011f41eacad73", "0x5fc5360d0400a0fd4f2af552add042d716f1d168"],
        venues: [
            Venue(kind: .uniswap, quoter: "0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7",
                  router: "0xcaf681a66d020601342297493863e78c959e5cb2",
                  factory: "0x1f7d7550b1b028f7571e69a784071f0205fd2efa", steps: uniswapFees),
            Venue(kind: .sushi, quoter: "0x3e290e5e01818002a0b672148bdc7514d861c7b3",
                  router: "0x8e6fd69a77e88ee20ba4b4fbd59dfcda3ec0e98a",
                  factory: "0xe51960f1b45f1c9fb6d166e6a884f866fc70433b", steps: uniswapFees,
                  executor: "0x0e867974275cd31c25015c2753c9d75f9f355379"),
        ],
        slippageBps: 50)

    static let books: [Book] = [base, ethereum, robinhood]

    static func book(_ chainId: Int) -> Book? { books.first { $0.chainId == chainId } }

    /// Where the account swaps: every live network it is on (Base, Ethereum,
    /// Robinhood Chain, prd §1454), so send, receive and swap arrive
    /// together. Never a test network.
    static func supported(_ network: Op.Network) -> Bool {
        !network.isTest && book(network.chainId) != nil
    }

    /// Every router on `chainId`: the only contracts a swap may call or approve.
    static func routers(_ chainId: Int) -> Set<String> {
        Set(book(chainId)?.venues.map(\.router) ?? [])
    }

    /// The exchange a router belongs to, on any network: a grant to one in the
    /// Wallet's history is named by it.
    static func exchange(ofRouter address: String) -> String? {
        let a = address.lowercased()
        return books.lazy.flatMap(\.venues).first { $0.router == a }?.exchange
    }

    /// How long a swap's call stays fillable after it is written.
    static let deadlineSeconds = 1_800

    // MARK: - Calls, encoded

    /// An ABI value: a static word, dynamic bytes, a tuple, or an array.
    indirect enum Arg {
        case word([UInt8])
        case bytes([UInt8])
        case tuple([Arg])
        case array([Arg])

        var isDynamic: Bool {
            switch self {
            case .word: false
            case .bytes, .array: true
            case .tuple(let items): items.contains(where: \.isDynamic)
            }
        }

        static func address(_ a: String) -> Arg { .word(YourAccount.w(a)) }
        static func uint(_ n: Int) -> Arg { .word(YourAccount.w(n)) }
        /// A decimal string; nil past 256 bits.
        static func amount(_ units: String) -> Arg? { SafeABI.word(uint256: units).map(Arg.word) }
    }

    /// The standard head-and-tail encoding of a list of values.
    static func encode(_ args: [Arg]) -> [UInt8] {
        let headSize = args.reduce(0) { $0 + ($1.isDynamic ? 32 : encoded($1).count) }
        var head: [UInt8] = []
        var tail: [UInt8] = []
        for arg in args {
            if arg.isDynamic {
                head += YourAccount.w(headSize + tail.count)
                tail += encoded(arg)
            } else {
                head += encoded(arg)
            }
        }
        return head + tail
    }

    private static func encoded(_ arg: Arg) -> [UInt8] {
        switch arg {
        case .word(let w): w
        case .bytes(let b): YourAccount.dynamic(b)
        case .tuple(let items): encode(items)
        case .array(let items): YourAccount.w(items.count) + encode(items)
        }
    }

    static func call(_ signature: String, _ args: [Arg]) -> [UInt8] {
        YourAccount.sel(signature) + encode(args)
    }

    // MARK: - Asking every pool

    /// One pool between two tokens: a fee tier, a tick spacing, or stable (1).
    struct Hop: Equatable, Hashable, Sendable {
        let from: String
        let to: String
        let step: Int
    }

    /// A way through one venue: one pool, or two through a hub.
    struct Route: Equatable, Sendable {
        let venue: Venue
        let hops: [Hop]
        /// Each pool's fee in millionths, as the pool charges it; empty when
        /// it could not be read (the words then name the exchange alone).
        var fees: [Int] = []
        /// Each pool's address, read off the factory: Sushi's route names
        /// its pools, so a Sushi route without them cannot be written.
        var pools: [String] = []
    }

    /// One question to a quoter: what the last hop of `hops` pays for `amount`.
    struct Ask: Equatable, Sendable {
        let venue: Venue
        /// The route so far; the last hop is the one asked.
        let hops: [Hop]
        /// What goes into the last hop, in base units.
        let amount: String

        var hop: Hop { hops[hops.count - 1] }

        /// The quoter call, or nil when the amount is not a uint256.
        var call: (to: String, data: [UInt8])? {
            guard let amount = Arg.amount(amount) else { return nil }
            let h = hop
            switch venue.kind {
            case .uniswap, .sushi:
                return (venue.quoter, YourAccountSwap.call("quoteExactInputSingle((address,address,uint256,uint24,uint160))",
                                                           [.tuple([.address(h.from), .address(h.to), amount, .uint(h.step), .uint(0)])]))
            case .slipstream:
                return (venue.quoter, YourAccountSwap.call("quoteExactInputSingle((address,address,uint256,int24,uint160))",
                                                           [.tuple([.address(h.from), .address(h.to), amount, .uint(h.step), .uint(0)])]))
            case .aerodromeV2:
                return (venue.quoter, YourAccountSwap.call("getAmountsOut(uint256,(address,address,bool,address)[])",
                                                           [amount, .array([v2Route(h, venue)])]))
            }
        }
    }

    private static func v2Route(_ h: Hop, _ venue: Venue) -> Arg {
        .tuple([.address(h.from), .address(h.to), .uint(h.step == 1 ? 1 : 0), .address(venue.factory)])
    }

    /// A route and what it pays.
    struct Priced: Equatable, Sendable {
        let route: Route
        let out: String
    }

    /// The first round: every pool straight from `sell` to `buy`, and every
    /// pool from `sell` into a hub, on every venue. Tokens are contracts
    /// (ETH as the book's WETH).
    static func firstRound(_ book: Book, sell: String, buy: String, amount: String) -> [Ask] {
        let s = sell.lowercased(), b = buy.lowercased()
        guard s != b else { return [] }
        let hubs = book.hubs.filter { $0 != s && $0 != b }
        var asks: [Ask] = []
        for venue in book.venues {
            for step in venue.steps {
                asks.append(Ask(venue: venue, hops: [Hop(from: s, to: b, step: step)], amount: amount))
                for hub in hubs {
                    asks.append(Ask(venue: venue, hops: [Hop(from: s, to: hub, step: step)], amount: amount))
                }
            }
        }
        return asks
    }

    /// The second round: on each venue, from the best pool into each hub, on
    /// to `buy` for what that pool paid. Two pools of one venue: their
    /// answers add up exactly, since they never share a pool.
    static func secondRound(_ asked: [Ask], answers: [String?], buy: String) -> [Ask] {
        let b = buy.lowercased()
        var best: [(venue: Venue, hub: String, ask: Ask, out: String)] = []
        for (ask, out) in zip(asked, answers) where ask.hop.to != b {
            guard let out, isPositive(out) else { continue }
            if let i = best.firstIndex(where: { $0.venue == ask.venue && $0.hub == ask.hop.to }) {
                if !Op.atMost(out, best[i].out) { best[i] = (ask.venue, ask.hop.to, ask, out) }
            } else {
                best.append((ask.venue, ask.hop.to, ask, out))
            }
        }
        return best.flatMap { leg in
            leg.venue.steps.map { step in
                Ask(venue: leg.venue, hops: leg.ask.hops + [Hop(from: leg.hub, to: b, step: step)], amount: leg.out)
            }
        }
    }

    /// Every route that reaches `buy`, with what it pays.
    static func priced(_ asked: [Ask], answers: [String?], buy: String) -> [Priced] {
        let b = buy.lowercased()
        return zip(asked, answers).compactMap { ask, out in
            guard ask.hop.to == b, let out, isPositive(out) else { return nil }
            return Priced(route: Route(venue: ask.venue, hops: ask.hops), out: out)
        }
    }

    /// **THE BEST OUTPUT.** The most paid; on a tie, one pool over two, then
    /// the book's own order (Uniswap first), so the same answers always pick
    /// the same route.
    static func best(_ routes: [Priced], in book: Book) -> Priced? {
        func rank(_ p: Priced) -> Int { book.venues.firstIndex(of: p.route.venue) ?? .max }
        return routes.enumerated().min { x, y in
            let a = x.element, b = y.element
            if a.out != b.out { return !Op.atMost(a.out, b.out) }
            if a.route.hops.count != b.route.hops.count { return a.route.hops.count < b.route.hops.count }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return x.offset < y.offset
        }?.element
    }

    /// What a quoter answered, as the amount out: the first word, or the
    /// last entry of `getAmountsOut`'s array. nil for a refusal or nonsense.
    static func amountOut(_ kind: Kind, ok: Bool, data: [UInt8]) -> String? {
        guard ok, data.count >= 32 else { return nil }
        switch kind {
        case .uniswap, .slipstream, .sushi:
            return SafeCalldata.decimal(Array(data[0..<32]))
        case .aerodromeV2:
            guard let offset = small(data, at: 0), let count = small(data, at: offset), count > 0,
                  let last = word(data, at: offset + 32 * count) else { return nil }
            return SafeCalldata.decimal(last)
        }
    }

    // MARK: - Multicall3

    /// `aggregate3`: every question in one call, each allowed to fail alone.
    static func aggregate3(_ calls: [(to: String, data: [UInt8])]) -> [UInt8] {
        call("aggregate3((address,bool,bytes)[])",
             [.array(calls.map { .tuple([.address($0.to), .uint(1), .bytes($0.data)]) })])
    }

    /// `aggregate3`'s answer: `(bool success, bytes returnData)[]`; nil when
    /// it does not read as one, or a length runs past the answer.
    static func aggregate3Results(_ data: [UInt8]) -> [(ok: Bool, data: [UInt8])]? {
        guard let offset = small(data, at: 0), let count = small(data, at: offset) else { return nil }
        let base = offset + 32
        var out: [(Bool, [UInt8])] = []
        for i in 0..<count {
            guard let at = small(data, at: base + 32 * i).map({ base + $0 }),
                  let ok = small(data, at: at), ok <= 1,
                  let bytesAt = small(data, at: at + 32).map({ at + $0 }),
                  let length = small(data, at: bytesAt),
                  bytesAt + 32 + length <= data.count else { return nil }
            out.append((ok == 1, Array(data[(bytesAt + 32)..<(bytesAt + 32 + length)])))
        }
        return out
    }

    private static func word(_ data: [UInt8], at i: Int) -> [UInt8]? {
        guard i >= 0, i + 32 <= data.count else { return nil }
        return Array(data[i..<(i + 32)])
    }

    /// A word that must be a small number (an offset, a length, a flag).
    private static func small(_ data: [UInt8], at i: Int) -> Int? {
        guard let w = word(data, at: i), w[0..<28].allSatisfy({ $0 == 0 }) else { return nil }
        return w[28..<32].reduce(0) { $0 << 8 | Int($1) }
    }

    // MARK: - The minimum

    /// The quote less `bps` basis points, rounded down: the least the swap
    /// may pay, written into its call.
    static func minimum(_ quoted: String, bps: Int) -> String? {
        guard isPositive(quoted), (0..<10_000).contains(bps) else { return nil }
        return divided(times(quoted, 10_000 - bps), by: 10_000)
    }

    private static func times(_ a: String, _ n: Int) -> String {
        var out: [Character] = []
        var carry = 0
        for ch in a.reversed() {
            let d = (ch.wholeNumberValue ?? 0) * n + carry
            out.append(Character(String(d % 10)))
            carry = d / 10
        }
        while carry > 0 { out.append(Character(String(carry % 10))); carry /= 10 }
        let s = String(out.reversed()).drop { $0 == "0" }
        return s.isEmpty ? "0" : String(s)
    }

    private static func divided(_ a: String, by n: Int) -> String {
        var out = ""
        var rest = 0
        for ch in a {
            let cur = rest * 10 + (ch.wholeNumberValue ?? 0)
            out.append(Character(String(cur / n)))
            rest = cur % n
        }
        let s = out.drop { $0 == "0" }
        return s.isEmpty ? "0" : String(s)
    }

    static func isPositive(_ units: String) -> Bool {
        !units.isEmpty && units.allSatisfy(\.isNumber) && units.contains { $0 != "0" }
    }

    // MARK: - The swap's calls

    struct Call: Equatable, Sendable {
        let to: String
        let value: String
        let data: [UInt8]
    }

    struct Quote: Equatable, Sendable {
        /// What is sold, all of it.
        let sellAmount: String
        /// What the best pool pays now.
        let buyAmount: String
        /// At least this comes back, or the swap is refused before Face ID.
        let minimumBuy: String
        /// The pools it goes through; nil for the demo's estimate.
        let route: Route?
        /// The calls that do it: an exact approval, then one router call.
        /// To another network (prd §1555): the swap's calls, if anything is
        /// swapped first, then the crossing's.
        let calls: [Call]
        /// The crossing, for a swap whose token is on another network: what
        /// `buyAmount` arrives through, and Across's terms (prd §1555).
        var across: YourAccountAcross.Leg? = nil
        /// WETH and ETH on one network: the network's own WETH contract,
        /// one for one, no pool (prd §1559).
        var wrap: Wrap? = nil

        var exchange: String? { route?.venue.exchange }
    }

    // MARK: - WETH and ETH, one for one (prd §1559)

    /// **WETH IS ETH, WRAPPED.** No pool trades a token for itself, so WETH
    /// for ETH found no route ("No pool … swaps WETH for ETH") and a refund
    /// that came back as WETH (§1556) could not be ETH again. Now it is one
    /// for one, exactly what is sold, no fee but the network's:
    ///
    /// - **ETH for WETH** is the network's WETH's own `deposit()`, the amount
    ///   sent with it.
    /// - **WETH for ETH** cannot be WETH's own `withdraw`: it pays out with a
    ///   2,300-gas `transfer`, and a Safe's proxy takes more than that unless
    ///   its code is already warm — measured 2026-10-26, a `withdraw` straight
    ///   to a real SafeL2 1.4.1 proxy reverts on Base and Ethereum (and on
    ///   Robinhood with the proxy in place), so the simulation before Face ID
    ///   would refuse every unwrap. So the WETH goes to the network's pinned
    ///   SwapRouter02 and its `unwrapWETH9(amount, account)` withdraws it and
    ///   pays the account with a full-gas call, in the same transaction (one
    ///   MultiSend: the second call failing undoes the first). The router
    ///   takes no fee for it. Simulated from a cold Safe on all three
    ///   networks: the account gains exactly the amount.
    enum Wrap: String, Equatable, Sendable {
        /// WETH for ETH: through the router's `unwrapWETH9`.
        case unwrap
        /// ETH for WETH: `deposit()`, the amount sent with it.
        case wrap
    }

    /// Whether selling `sell` for `buy` on `chainId` is a wrap or an unwrap
    /// of the network's own WETH; nil for anything else.
    static func wrap(sell: Op.Token, buy: Op.Token, chainId: Int) -> Wrap? {
        guard let weth = book(chainId)?.weth else { return nil }
        let s = sell.contract?.lowercased(), b = buy.contract?.lowercased()
        if s == weth, b == nil { return .unwrap }
        if s == nil, b == weth { return .wrap }
        return nil
    }

    /// The network's Uniswap SwapRouter02: the one that unwraps.
    static func unwrapper(_ chainId: Int) -> String? {
        book(chainId)?.venues.first { $0.kind == .uniswap }?.router
    }

    static let depositSelector: [UInt8] = [0xd0, 0xe3, 0x0d, 0xb0]
    static let transferSelector: [UInt8] = [0xa9, 0x05, 0x9c, 0xbb]
    static let unwrapSelector: [UInt8] = [0x49, 0x40, 0x4b, 0x7c]

    /// The calls: `deposit()` with the amount; or the WETH's `transfer` of
    /// exactly the amount to the router, then `unwrapWETH9(amount, account)`.
    static func wrapCalls(_ w: Wrap, amount: String, account: String, chainId: Int) -> [Call]? {
        guard let weth = book(chainId)?.weth, isPositive(amount), let units = SafeABI.word(uint256: amount),
              SafeABI.word(address: account) != nil else { return nil }
        switch w {
        case .wrap:
            return [Call(to: weth, value: amount, data: depositSelector)]
        case .unwrap:
            guard let router = unwrapper(chainId) else { return nil }
            return [Call(to: weth, value: "0", data: transferSelector + YourAccount.w(router) + units),
                    Call(to: router, value: "0", data: unwrapSelector + units + YourAccount.w(account))]
        }
    }

    /// The quote: what is sold comes back, exactly.
    static func wrapQuote(_ w: Wrap, amount: String, account: String, chainId: Int) -> Quote? {
        guard let calls = wrapCalls(w, amount: amount, account: account, chainId: chainId) else { return nil }
        return Quote(sellAmount: amount, buyAmount: amount, minimumBuy: amount, route: nil, calls: calls, wrap: w)
    }

    /// **NOTHING SIGNED BUT THESE CALLS.** A wrap is exactly one `deposit()`
    /// to the network's pinned WETH sending exactly the amount; an unwrap is
    /// exactly the pinned WETH's `transfer` of exactly the amount to the
    /// network's pinned SwapRouter02, then that router's `unwrapWETH9` of
    /// exactly the amount to the account, neither sending ETH. No approval.
    /// nil otherwise.
    static func checkedWrap(_ quote: Quote, sell: Op.Token, buy: Op.Token, amount: String, account: String,
                            chainId: Int) -> [Call]? {
        guard let w = wrap(sell: sell, buy: buy, chainId: chainId), quote.wrap == w, quote.sellAmount == amount,
              quote.buyAmount == amount, quote.minimumBuy == amount,
              let weth = book(chainId)?.weth, let units = SafeABI.word(uint256: amount),
              SafeABI.word(address: account) != nil else { return nil }
        let calls = quote.calls
        switch w {
        case .wrap:
            guard calls.count == 1, calls[0].to.lowercased() == weth, calls[0].value == amount,
                  calls[0].data == depositSelector else { return nil }
        case .unwrap:
            guard let router = unwrapper(chainId), calls.count == 2,
                  calls[0].to.lowercased() == weth, calls[0].value == "0",
                  calls[0].data == transferSelector + YourAccount.w(router) + units,
                  calls[1].to.lowercased() == router, calls[1].value == "0",
                  calls[1].data == unwrapSelector + units + YourAccount.w(account) else { return nil }
        }
        return calls
    }

    /// "Unwraps WETH · no fee": the foot's words, and Details'.
    static func words(_ w: Wrap) -> String {
        switch w {
        case .unwrap: String(localized: "Unwraps WETH · no fee")
        case .wrap: String(localized: "Wraps ETH · no fee")
        }
    }

    static let approveSelector: [UInt8] = [0x09, 0x5e, 0xa7, 0xb3]

    /// Router02's stand-in for "the router itself": what it is paid when it
    /// unwraps WETH for the account in the same call.
    static let router02Itself = "0x0000000000000000000000000000000000000002"

    /// The calls that swap `amount` along `route` for at least `minimum`,
    /// paid to `account`: the sold token's exact approval to the route's
    /// router (none when ETH is sold, sent with the call instead), then one
    /// router call with the deadline. nil when the route cannot be written
    /// (ETH on a side the route does not wrap, an amount past 256 bits).
    static func calls(_ route: Route, in book: Book, sellsETH: Bool, buysETH: Bool, amount: String,
                      minimum: String, account: String, deadline: Int) -> [Call]? {
        guard let first = route.hops.first, let last = route.hops.last,
              !sellsETH || first.from == book.weth, !buysETH || last.to == book.weth,
              !(sellsETH && buysETH),
              let amountIn = Arg.amount(amount), let least = Arg.amount(minimum),
              SafeABI.word(address: account) != nil else { return nil }
        let venue = route.venue
        let router = venue.router
        let data: [UInt8]
        switch venue.kind {
        case .uniswap:
            let to = buysETH ? router02Itself : account
            let swap = route.hops.count == 1
                ? call("exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))",
                       [.tuple([.address(first.from), .address(first.to), .uint(first.step), .address(to), amountIn, least, .uint(0)])])
                : call("exactInput((bytes,address,uint256,uint256))",
                       [.tuple([.bytes(path(route.hops)), .address(to), amountIn, least])])
            var inner: [Arg] = [.bytes(swap)]
            if buysETH { inner.append(.bytes(call("unwrapWETH9(uint256,address)", [least, .address(account)]))) }
            data = call("multicall(uint256,bytes[])", [.uint(deadline), .array(inner)])
        case .slipstream:
            let to = buysETH ? router : account
            let swap = route.hops.count == 1
                ? call("exactInputSingle((address,address,int24,address,uint256,uint256,uint256,uint160))",
                       [.tuple([.address(first.from), .address(first.to), .uint(first.step), .address(to), .uint(deadline),
                                amountIn, least, .uint(0)])])
                : call("exactInput((bytes,address,uint256,uint256,uint256))",
                       [.tuple([.bytes(path(route.hops)), .address(to), .uint(deadline), amountIn, least])])
            var inner: [Arg] = [.bytes(swap)]
            if buysETH { inner.append(.bytes(call("unwrapWETH9(uint256,address)", [least, .address(account)]))) }
            data = call("multicall(bytes[])", [.array(inner)])
        case .aerodromeV2:
            let routes: Arg = .array(route.hops.map { v2Route($0, venue) })
            if sellsETH {
                data = call("swapExactETHForTokens(uint256,(address,address,bool,address)[],address,uint256)",
                            [least, routes, .address(account), .uint(deadline)])
            } else if buysETH {
                data = call("swapExactTokensForETH(uint256,uint256,(address,address,bool,address)[],address,uint256)",
                            [amountIn, least, routes, .address(account), .uint(deadline)])
            } else {
                data = call("swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)",
                            [amountIn, least, routes, .address(account), .uint(deadline)])
            }
        case .sushi:
            guard let executor = venue.executor, route.pools.count == route.hops.count,
                  let quoted = Arg.amount(minimum) else { return nil }
            let tokenIn: Arg = .address(sellsETH ? sushiNative : first.from)
            let tokenOut: Arg = .address(buysETH ? sushiNative : last.to)
            // The RouteProcessor's own floor is the minimum, and the surplus
            // is the account's (`takeSurplus` false: measured 2026-10-28, true
            // hands everything over that floor to Sushi). No fee is
            // transferred (`amountValueTransfer` 0). RedSnwapper then refuses
            // unless the account's balance of what it bought rose by at least
            // the minimum.
            let process = call("processRouteWithTransferValueOutput(address,uint256,address,uint256,address,uint256,address,bytes,bool,uint32)",
                               [.address(account), .uint(0), tokenIn, amountIn, tokenOut, quoted, .address(account),
                                .bytes(sushiRoute(route, weth: book.weth, executor: executor, sellsETH: sellsETH, buysETH: buysETH)),
                                .uint(0), .uint(0)])
            data = call("snwap(address,uint256,address,address,uint256,address,bytes)",
                        [tokenIn, amountIn, .address(account), tokenOut, least, .address(executor), .bytes(process)])
        }
        var out: [Call] = []
        if !sellsETH {
            out.append(Call(to: first.from, value: "0", data: approveSelector + YourAccount.w(router) + SafeABI.word(uint256: amount)!))
        }
        out.append(Call(to: router, value: sellsETH ? amount : "0", data: data))
        return out
    }

    /// Sushi's word for the network's own coin, in `snwap` and the route.
    static let sushiNative = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    /// **SUSHI'S ROUTE, PACKED.** Sushi's direct-pool encoding (its web app's
    /// `encodeDirectPoolSwap`), one step per pool: a header; ETH sold is
    /// wrapped first; each pool takes what the RouteProcessor holds of its
    /// token, all of it (share 0xffff), through a v3 pool (type 1) in the
    /// direction the token order says, paying the RouteProcessor; ETH bought
    /// is unwrapped last, and the RouteProcessor pays the account. Two pools
    /// chain the same step, the shape Sushi's own API writes for MUSEGOD to
    /// USDG. Every shape here simulated on Robinhood, 2026-10-28, paying
    /// exactly the quote, ETH into a SafeL2 1.4.1 proxy included.
    static func sushiRoute(_ route: Route, weth: String, executor: String, sellsETH: Bool, buysETH: Bool) -> [UInt8] {
        let a = YourAccount.addressBytes
        let all: [UInt8] = [0xFF, 0xFF]
        var out: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 2]
        if sellsETH { out += [3, 1] + all + [2, 1] + a(executor) + a(weth) }
        for (hop, pool) in zip(route.hops, route.pools) {
            let zeroForOne: UInt8 = hop.from.lowercased() < hop.to.lowercased() ? 1 : 0
            out += [1] + a(hop.from) + [1] + all + [1] + a(pool) + [zeroForOne] + a(executor) + [0] + [UInt8](repeating: 0, count: 6)
        }
        if buysETH { out += [1] + a(weth) + [1] + all + [2, 0] + a(executor) }
        return out
    }

    /// A multi-pool path: token, then each pool's 3-byte fee or tick
    /// spacing and the next token.
    static func path(_ hops: [Hop]) -> [UInt8] {
        guard let first = hops.first else { return [] }
        var out = Array(YourAccount.w(first.from).suffix(20))
        for h in hops {
            let step = UInt32(truncatingIfNeeded: h.step) & 0xFF_FFFF
            out += [UInt8(step >> 16 & 0xFF), UInt8(step >> 8 & 0xFF), UInt8(step & 0xFF)]
            out += Array(YourAccount.w(h.to).suffix(20))
        }
        return out
    }

    // MARK: - The check

    /// **NOTHING SIGNED BUT WHAT THESE RULES ALLOW.** The quote's calls, if
    /// every one is a router pinned for `chainId` or the sold token's exact
    /// approval to one, ETH leaves only when ETH is sold and only the amount
    /// sold, and there is exactly one swap; nil otherwise. An `approve` is
    /// returned apart, so a batch can approve each token once for the sum.
    static func checked(_ quote: Quote, sell: Op.Token, amount: String, chainId: Int)
        -> (approvals: [(token: String, spender: String, amount: String)], calls: [Call])? {
        let pinned = routers(chainId)
        guard quote.sellAmount == amount, !pinned.isEmpty else { return nil }
        var approvals: [(String, String, String)] = []
        var calls: [Call] = []
        for call in quote.calls {
            if call.data.starts(with: approveSelector) {
                // approve(spender, amount) on the sold token, to a pinned
                // router, for exactly what is sold.
                guard let contract = sell.contract?.lowercased(), call.to.lowercased() == contract, call.value == "0",
                      call.data.count == 4 + 64,
                      let spender = address(fromWord: Array(call.data[4..<36])),
                      pinned.contains(spender),
                      SafeCalldata.decimal(Array(call.data[36..<68])) == amount else { return nil }
                approvals.append((contract, spender, amount))
                continue
            }
            guard pinned.contains(call.to.lowercased()) else { return nil }
            // ETH leaves only when ETH is sold, and only the amount sold.
            guard call.value == (sell.contract == nil ? amount : "0") else { return nil }
            calls.append(call)
        }
        guard calls.count == 1 else { return nil }
        // A token sold is approved once, to the router that swaps it.
        if sell.contract == nil {
            guard approvals.isEmpty else { return nil }
        } else {
            guard approvals.count == 1, approvals[0].1 == calls[0].to.lowercased() else { return nil }
        }
        return (approvals, calls)
    }

    private static func address(fromWord word: [UInt8]) -> String? {
        guard word.count == 32, word[0..<12].allSatisfy({ $0 == 0 }) else { return nil }
        return SafeABI.hex(Array(word[12..<32])).lowercased()
    }

    /// Every swap's approvals, once per token and spender for the sum: an
    /// `approve` replaces an allowance, so two would leave the first swap
    /// short (the rule §1436 set for CoW, kept).
    static func approvalCalls(_ approvals: [(token: String, spender: String, amount: String)]) -> [YourAccount.Call]? {
        var order: [String] = []
        var sums: [String: (token: String, spender: String, amount: String)] = [:]
        for a in approvals {
            let key = a.token + "|" + a.spender
            if let have = sums[key] {
                sums[key] = (a.token, a.spender, Op.sum(have.amount, a.amount))
            } else {
                order.append(key)
                sums[key] = a
            }
        }
        var out: [YourAccount.Call] = []
        for key in order {
            guard let a = sums[key], let amount = SafeABI.word(uint256: a.amount), let zero = SafeABI.word(uint256: "0")
            else { return nil }
            out.append(.init(operation: 0, to: a.token,
                             value: zero, data: approveSelector + YourAccount.w(a.spender) + amount))
        }
        return out
    }

    /// A checked call as one of the account's own.
    static func accountCall(_ call: Call) -> YourAccount.Call? {
        guard let value = SafeABI.word(uint256: call.value) else { return nil }
        return .init(operation: 0, to: call.to, value: value, data: call.data)
    }

    // MARK: - Each pool's fee

    /// The question that finds a pool's address, for a venue whose fee is
    /// the pool's own or whose route names its pools; nil for Uniswap.
    static func poolCall(_ venue: Venue, _ hop: Hop) -> (to: String, data: [UInt8])? {
        switch venue.kind {
        case .uniswap: nil
        case .sushi:
            (venue.factory, call("getPool(address,address,uint24)", [.address(hop.from), .address(hop.to), .uint(hop.step)]))
        case .slipstream:
            (venue.factory, call("getPool(address,address,int24)", [.address(hop.from), .address(hop.to), .uint(hop.step)]))
        case .aerodromeV2:
            (venue.factory, call("getPool(address,address,bool)", [.address(hop.from), .address(hop.to), .uint(hop.step == 1 ? 1 : 0)]))
        }
    }

    /// The question that reads a found pool's fee.
    static func feeCall(_ venue: Venue, _ hop: Hop, pool: String) -> (to: String, data: [UInt8])? {
        switch venue.kind {
        case .uniswap, .sushi: nil
        case .slipstream: (pool, YourAccount.sel("fee()"))
        case .aerodromeV2: (venue.factory, call("getFee(address,bool)", [.address(pool), .uint(hop.step == 1 ? 1 : 0)]))
        }
    }

    /// A fee answer in millionths: Slipstream answers in millionths, Aerodrome
    /// v2's factory in basis points. nil past 10%.
    static func fee(_ venue: Venue, answer: [UInt8]) -> Int? {
        guard answer.count >= 32, let n = Int(SafeCalldata.decimal(Array(answer[0..<32]))) else { return nil }
        let pips = venue.kind == .aerodromeV2 ? n * 100 : n
        return pips <= 100_000 ? pips : nil
    }

    /// A pool address answer; nil for the zero address (no such pool).
    static func pool(fromAnswer answer: [UInt8]) -> String? {
        guard answer.count >= 32, let a = address(fromWord: Array(answer[0..<32])), a != native else { return nil }
        return a
    }

    // MARK: - In words

    /// **A POOL FEE, ROUNDED FOR READING (user, 2026-10-26, prd §1545).**
    /// Millionths as a percentage to at most two places, trailing zeros
    /// trimmed: 3000 → "0.3%", 500 → "0.05%", 773 → "0.08%", 10000 → "1%";
    /// anything below a hundredth of a percent reads "under 0.01%" (80, a
    /// Slipstream pool's 0.008%). Words only: the route keeps the exact fee.
    static func percent(pips: Int) -> String {
        guard pips >= 100 else { return String(localized: "under 0.01%") }
        var d = Decimal(pips) / 10_000
        var r = Decimal()
        NSDecimalRound(&r, &d, 2, .plain)
        return NSDecimalNumber(decimal: r).stringValue + "%"
    }

    /// "On Uniswap"
    static func on(_ exchange: String) -> String { String(localized: "On \(exchange)") }

    /// **THE EXCHANGE THAT DID IT (user ruling, prd §1539).** "On Uniswap ·
    /// 0.05% pool fee"; through two pools, "On Aerodrome · under 0.01% and 0.3%
    /// pool fees"; the exchange alone when the fees could not be read. The
    /// pool fee is part of the price: there is no middleman's fee to add.
    static func words(_ route: Route) -> String {
        let name = route.venue.exchange
        let fees = route.venue.kind.feeIsTier ? route.hops.map(\.step) : route.fees
        guard fees.count == route.hops.count, !fees.isEmpty else { return on(name) }
        if fees.count == 1 { return String(localized: "On \(name) · \(percent(pips: fees[0])) pool fee") }
        let list = fees.map { percent(pips: $0) }.formatted(.list(type: .and))
        return String(localized: "On \(name) · \(list) pool fees")
    }

    /// **A DETAILS ROW'S VALUE FITS ONE LINE (user, 2026-10-26, prd §1556).**
    /// The exchange and its pools' fees, nothing else: "Uniswap · 0.01%",
    /// "Aerodrome · 0.05% + 0.3%", the exchange alone when the fees could not
    /// be read. The row's name ("Swaps", "Round-up") says what it is.
    static func brief(_ route: Route) -> String {
        let name = route.venue.exchange
        let fees = route.venue.kind.feeIsTier ? route.hops.map(\.step) : route.fees
        guard fees.count == route.hops.count, !fees.isEmpty else { return name }
        return name + " · " + fees.map { percent(pips: $0) }.joined(separator: " + ")
    }

    /// One line for several swaps: the one route's words, else the
    /// exchanges they use: "On Uniswap and Aerodrome".
    static func credit(_ routes: [Route]) -> String? {
        guard let first = routes.first else { return nil }
        if routes.allSatisfy({ $0 == first }) { return words(first) }
        var names: [String] = []
        for r in routes where !names.contains(r.venue.exchange) { names.append(r.venue.exchange) }
        return on(names.formatted(.list(type: .and)))
    }
}
