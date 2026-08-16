import Foundation

/// What a price chart's range set must answer (2026-07-15) — the seam that
/// lets TokenChartView draw stocks (StockRange) with the same anatomy tokens
/// wear. rawValue is the chip label; honesty rule: the label says what the
/// window IS ("5D" for five trading days, never rounded to "7D").
protocol PriceRange: RawRepresentable<String>, CaseIterable, Hashable
    where AllCases: RandomAccessCollection {
    /// Seconds per candle — the scrub's "9h ago" math.
    var step: TimeInterval { get }
    /// The range every live symbol answers at. Failing HERE means the chart
    /// is dead (the caller's fallback renders); failing elsewhere means an
    /// honest note and a step back to a range that worked.
    static var base: Self { get }
    /// The scrub cursor's "when" label for a candle N steps from the live
    /// end — nil when the range set can't state it truthfully (stock
    /// candles skip closed-market hours, so index × step would understate
    /// the age; no label beats a wrong one).
    func agoLabel(indexFromEnd: Int) -> String?
}

extension PriceRange {
    /// "9h ago" / "3d ago" / "now" — right whenever candles are wall-clock
    /// contiguous (tokens trade 24/7).
    func agoLabel(indexFromEnd: Int) -> String? {
        let ago = Double(indexFromEnd) * step
        if ago < 1 { return "now" }
        if ago < 86_400 { return "\(Int(ago / 3600))h ago" }
        return "\(Int(ago / 86_400))d ago"
    }
}

/// A chart's time window (prd 51) — 24h stays the default everywhere the
/// range picker doesn't show (feed pulse, Home row). GeckoTerminal serves
/// all three for free: hourly candles carry 24h and 7d, daily carry 30d.
enum TokenRange: String, CaseIterable, PriceRange {
    case day = "1D", week = "7D", month = "30D"

    /// GeckoTerminal OHLCV path piece + candle count.
    var ohlcv: (timeframe: String, limit: Int) {
        switch self {
        case .day:   ("hour", 24)
        case .week:  ("hour", 168)
        case .month: ("day", 30)
        }
    }
    /// Seconds per candle — the scrub's "9h ago" math.
    var step: TimeInterval {
        switch self {
        case .day, .week: 3600
        case .month:      86_400
        }
    }

    /// 24h has the Dexscreener fallback behind it — nothing at all there
    /// means the token is dead/illiquid.
    static var base: TokenRange { .day }
}

/// A token's recent price, drawn natively (2026-07-07). The curve comes from
/// GeckoTerminal's free public OHLCV (no key) — real candles — with Alchemy's
/// Prices API as a second tier (2026-07-13) for the EVM chains it covers: real
/// hourly/daily candles too, just from a different indexer, so a token
/// GeckoTerminal hasn't crawled yet — but Alchemy has — gets a real curve
/// instead of dropping straight to the coarse fallback (and, unlike that
/// fallback, Alchemy also covers the week/month ranges). Dexscreener is the
/// last resort, for everything neither indexes (a coarse 5-point curve
/// back-solved from its m5/h1/h6/h24 change buckets, 24h only; added
/// 2026-07-09). Either way Casberi draws it itself with Swift Charts rather
/// than embedding anyone's web chart (native content, per the design law).
struct TokenChart {
    let closes: [Double]
    let price: Double
    let change: Double   // fraction over the fetched range, e.g. -0.048 = -4.8%
    /// True for the Dexscreener 5-point fallback — the chart draws it as it
    /// is (dots, straight segments, said out loud) and offers no ranges
    /// (prd 51: a fallback curve stops pretending).
    var coarse: Bool = false
    /// Market cap / FDV, riding the SAME response the curve came from
    /// (2026-07-17, the fat-row build): GeckoTerminal's pool attributes and
    /// Dexscreener's pair both report them; Alchemy's candles carry neither.
    /// nil = the source didn't say — never derived, so a row simply omits
    /// the cap instead of inventing one.
    var marketCap: Double? = nil
    var fdv: Double? = nil

    /// When this curve was actually READ (2026-08-16).
    ///
    /// **Why the type had no clock until now, and what that cost.** Every
    /// producer builds a `TokenChart` at the moment it parses a response, so
    /// the default below is the fetch time for free and no producer changes.
    /// Before it, nothing on the price surface could say when the number was
    /// true: the view fetches once per range with no timer and no foreground
    /// refresh, so a sheet left open went stale in silence — and did it while
    /// drawing a BREATHING endpoint halo, which is the one mark in this file
    /// that means "live". `TokenChartPlot`'s own doc had already denied the
    /// Home row that halo for overclaiming; the sheet kept it on the reasoning
    /// that it "refetches per range", which is a refetch on a CHIP TAP, not on
    /// a clock.
    ///
    /// §83 forbids a stale number wearing a fresh face, and the app already
    /// speaks this grammar elsewhere — the wallet stamps "as of Xh ago" on
    /// last-known holdings rather than letting them read as current. This is
    /// the same sentence, on the surface that needed it most.
    var fetchedAt: Date = .now

    /// Pulls the token address (and chain) out of a dexscreener link like
    /// `https://dexscreener.com/base/0x…`.
    static func route(from content: String) -> (chain: String, address: String)? {
        guard let url = URL(string: content),
              url.host()?.contains("dexscreener.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return (chain: parts[0], address: parts[1])
    }

    /// GeckoTerminal's network ids don't always match Dexscreener's chain
    /// slugs (Ethereum mainnet is "ethereum" on Dexscreener, "eth" on
    /// GeckoTerminal) — translate the chains that drift, since `route(from:)`
    /// hands callers the Dexscreener slug (it also rebuilds the dexscreener.com
    /// URL, which needs that spelling).
    private static let geckoTerminalNetwork: [String: String] = [
        "ethereum": "eth",
        "polygon": "polygon_pos",
        "avalanche": "avax",
        "fantom": "ftm",
    ]

    /// Fetches a token's price curve for the range. GeckoTerminal's OHLCV is
    /// the primary source (real candles); when it has no pool for the
    /// token — common for the long tail of memecoins it hasn't indexed —
    /// Alchemy's Prices API tries next, for chains it covers. Only if BOTH
    /// come up empty does the 24h fetch fall back to Dexscreener, which
    /// resolved the token in the first place and always has a price for it.
    /// Dexscreener's buckets only cover 24h, so week/month return nil past
    /// that point and the chart says so instead of faking a week.
    static func fetch(chain: String, address: String,
                      range: TokenRange = .day) async -> TokenChart? {
        if let chart = await geckoTerminal(chain: chain, address: address, range: range) {
            return chart
        }
        if let chart = await alchemy(chain: chain, address: address, range: range) {
            return chart
        }
        return range == .day ? await dexscreener(chain: chain, address: address) : nil
    }

    /// GeckoTerminal candles for the token's most-liquid pool.
    private static func geckoTerminal(chain: String, address: String,
                                      range: TokenRange) async -> TokenChart? {
        let network = geckoTerminalNetwork[chain] ?? chain
        let base = "https://api.geckoterminal.com/api/v2/networks/\(network)"
        guard let poolsRoot = await IngestSupport.getJSON("\(base)/tokens/\(address)/pools")
                as? [String: Any],
              let pools = poolsRoot["data"] as? [[String: Any]],
              let pool = pools.first?["attributes"] as? [String: Any],
              let poolAddress = pool["address"] as? String else { return nil }

        let (timeframe, limit) = range.ohlcv
        guard let ohlcvRoot = await IngestSupport.getJSON(
            "\(base)/pools/\(poolAddress)/ohlcv/\(timeframe)?limit=\(limit)") as? [String: Any],
              let data = ohlcvRoot["data"] as? [String: Any],
              let attrs = data["attributes"] as? [String: Any],
              let list = attrs["ohlcv_list"] as? [[Any]], list.count >= 2 else { return nil }

        // GeckoTerminal returns newest-first: [ts, open, high, low, close, vol].
        let closes = list.reversed().compactMap { row -> Double? in
            guard row.count >= 5 else { return nil }
            if let c = row[4] as? Double { return c }
            if let s = row[4] as? String { return Double(s) }
            return nil
        }
        guard let first = closes.first, let last = closes.last, first > 0 else { return nil }
        return TokenChart(closes: closes, price: last,
                          change: (last - first) / first,
                          marketCap: num(pool["market_cap_usd"]),
                          fdv: num(pool["fdv_usd"]))
    }

    /// Dexscreener's chain slugs → Alchemy's network params — the EVM chains
    /// WalletIngest already reads wallets on. A chain not in this table (or a
    /// token Alchemy hasn't priced) falls through to the Dexscreener tier.
    private static let alchemyNetwork: [String: String] = [
        "ethereum": "eth-mainnet",
        "base": "base-mainnet",
        "arbitrum": "arb-mainnet",
        "optimism": "opt-mainnet",
        "polygon": "matic-mainnet",
    ]

    /// Alchemy's Prices API historical endpoint — real candles for the EVM
    /// chains it covers, at the same resolution/count GeckoTerminal's ranges
    /// use (24 hourly points for a day, 168 for a week, 30 daily for a month)
    /// so a chart that falls to this tier reads no differently than one that
    /// didn't.
    private static func alchemy(chain: String, address: String,
                                range: TokenRange) async -> TokenChart? {
        guard let network = alchemyNetwork[chain] else { return nil }
        let (interval, span): (String, TimeInterval) = switch range {
        case .day:   ("1h", 86_400)
        case .week:  ("1h", 7 * 86_400)
        case .month: ("1d", 30 * 86_400)
        }
        let iso = ISO8601DateFormatter()
        let end = Date.now
        let body: [String: Any] = [
            "network": network, "address": address, "interval": interval,
            "startTime": iso.string(from: end.addingTimeInterval(-span)),
            "endTime": iso.string(from: end),
        ]
        guard let root = await IngestSupport.postJSON(
            "https://api.g.alchemy.com/prices/v1/\(IngestSupport.alchemyKey)/tokens/historical",
            body: body) as? [String: Any],
              let points = root["data"] as? [[String: Any]]
        else { return nil }

        // Sorted by its own timestamp rather than trusted as oldest-first —
        // a dropped/out-of-order point (a null value mid-range, say) must not
        // silently swap what `first`/`last` mean. ISO 8601 UTC strings sort
        // chronologically as plain strings, so no date parsing needed.
        let closes = points.compactMap { p -> (String, Double)? in
            guard let ts = p["timestamp"] as? String,
                  let value = (p["value"] as? String).flatMap(Double.init) else { return nil }
            return (ts, value)
        }.sorted { $0.0 < $1.0 }.map(\.1)
        guard closes.count >= 2, let first = closes.first, let last = closes.last, first > 0
        else { return nil }
        return TokenChart(closes: closes, price: last, change: (last - first) / first)
    }

    /// Dexscreener fallback — the token's live price plus its m5/h1/h6/h24
    /// change buckets, back-solved into a coarse but REAL 24h curve
    /// (price_ago = price / (1 + change%)). No web chart, no invented data:
    /// five actual price points at known offsets. Every token Casberi watches
    /// resolved through Dexscreener, so this has a price when GeckoTerminal —
    /// which only indexes pools it has crawled — does not.
    private static func dexscreener(chain: String, address: String) async -> TokenChart? {
        guard let pair = await bestPair(chain: chain, address: address),
              let priceStr = pair["priceUsd"] as? String,
              let price = Double(priceStr), price > 0 else { return nil }

        // priceChange buckets are percentages (e.g. -4.8 = -4.8%); any may be
        // absent for a thin pool, so a missing bucket means "no move" (0).
        let change = pair["priceChange"] as? [String: Any] ?? [:]
        func pct(_ key: String) -> Double { num(change[key]) ?? 0 }
        func ago(_ key: String) -> Double { price / (1 + pct(key) / 100) }

        // Oldest → newest, the order the chart draws left to right.
        let closes = [ago("h24"), ago("h6"), ago("h1"), ago("m5"), price]
        return TokenChart(closes: closes, price: price, change: pct("h24") / 100,
                          coarse: true,
                          marketCap: num(pair["marketCap"]), fdv: num(pair["fdv"]))
    }

    /// The token's most-liquid Dexscreener pair, preferring its own chain —
    /// the one selection rule for everything read off the pair payload (the
    /// coarse fallback curve above, and TokenStats below), so the two can't
    /// pick different pools and disagree.
    static func bestPair(chain: String, address: String) async -> [String: Any]? {
        guard let root = await IngestSupport.getJSON(
            "https://api.dexscreener.com/latest/dex/tokens/\(address)") as? [String: Any],
              let pairs = root["pairs"] as? [[String: Any]], !pairs.isEmpty else { return nil }
        func liquidity(_ p: [String: Any]) -> Double {
            (p["liquidity"] as? [String: Any])?["usd"] as? Double ?? 0
        }
        let onChain = pairs.filter { ($0["chainId"] as? String) == chain }
        return (onChain.isEmpty ? pairs : onChain)
            .max(by: { liquidity($0) < liquidity($1) })
    }

    /// A JSON number that may arrive as Double, Int, or String.
    fileprivate static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// Synthesizes a chart from an already-sampled close series — no fetch:
    /// the data already lives in `WalletStore.ValueSample` history (2026-07-18,
    /// "do we have that data?" — yes). nil under two points, the same honesty
    /// floor `WalletStore.combinedValueSamples()` itself keeps.
    static func from(closes: [Double]) -> TokenChart? {
        guard closes.count >= 2, let first = closes.first, first != 0,
              let last = closes.last else { return nil }
        return TokenChart(closes: closes, price: last, change: (last - first) / first)
    }

    /// The wallet-history form of `from(closes:)` — a wallet's or the combined
    /// portfolio's `ValueSample` line, drawn as the same native chart a token
    /// wears.
    static func from(samples: [WalletStore.ValueSample]) -> TokenChart? {
        from(closes: samples.map(\.usd))
    }
}

/// The market-structure numbers around a watched token (2026-07-14) —
/// liquidity, 24h volume, FDV, market cap. These ride the SAME Dexscreener
/// pair payload that resolved the token in the first place (search and this
/// endpoint are the one piece Alchemy/GeckoTerminal don't replace — neither
/// carries liquidity or FDV). A stat the pair doesn't report simply isn't
/// shown; nothing is derived or estimated.
struct TokenStats {
    let liquidityUsd: Double?
    let volume24h: Double?
    let fdv: Double?
    let marketCap: Double?

    var isEmpty: Bool {
        liquidityUsd == nil && volume24h == nil && fdv == nil && marketCap == nil
    }

    static func fetch(chain: String, address: String) async -> TokenStats? {
        guard let pair = await TokenChart.bestPair(chain: chain, address: address) else {
            return nil
        }
        let stats = TokenStats(
            liquidityUsd: TokenChart.num((pair["liquidity"] as? [String: Any])?["usd"]),
            volume24h: TokenChart.num((pair["volume"] as? [String: Any])?["h24"]),
            fdv: TokenChart.num(pair["fdv"]),
            marketCap: TokenChart.num(pair["marketCap"]))
        return stats.isEmpty ? nil : stats
    }

    /// "$1.2M" / "$340K" / "$980" — the strip's compact voice, no cents.
    static func compact(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "$%.1fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }
}
