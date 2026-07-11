import Foundation

/// A chart's time window (prd 51) — 24h stays the default everywhere the
/// range picker doesn't show (feed pulse, Home row). GeckoTerminal serves
/// all three for free: hourly candles carry 24h and 7d, daily carry 30d.
enum TokenRange: String, CaseIterable {
    case day = "24h", week = "7d", month = "30d"

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
}

/// A token's recent price, drawn natively (2026-07-07). The curve comes from
/// GeckoTerminal's free public OHLCV (no key) — real candles — with a
/// Dexscreener fallback for the long tail of tokens GeckoTerminal hasn't
/// indexed (a coarse 5-point curve back-solved from its m5/h1/h6/h24 change
/// buckets; added 2026-07-09 after pinned memecoins stayed chartless on
/// device). Either way Casberi draws it itself with Swift Charts rather than
/// embedding anyone's web chart (native content, per the design law).
struct TokenChart {
    let closes: [Double]
    let price: Double
    let change: Double   // fraction over the fetched range, e.g. -0.048 = -4.8%
    /// True for the Dexscreener 5-point fallback — the chart draws it as it
    /// is (dots, straight segments, said out loud) and offers no ranges
    /// (prd 51: a fallback curve stops pretending).
    var coarse: Bool = false

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
    /// the primary source (real candles); when it has no pool for the token —
    /// common for the long tail of memecoins it hasn't indexed — the 24h
    /// fetch falls back to Dexscreener, which resolved the token in the first
    /// place and always has a price for it. Longer ranges have no fallback
    /// (Dexscreener's buckets only cover 24h): they return nil and the chart
    /// says so instead of faking a week.
    static func fetch(chain: String, address: String,
                      range: TokenRange = .day) async -> TokenChart? {
        if let chart = await geckoTerminal(chain: chain, address: address, range: range) {
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
                          change: (last - first) / first)
    }

    /// Dexscreener fallback — the token's live price plus its m5/h1/h6/h24
    /// change buckets, back-solved into a coarse but REAL 24h curve
    /// (price_ago = price / (1 + change%)). No web chart, no invented data:
    /// five actual price points at known offsets. Every token Casberi watches
    /// resolved through Dexscreener, so this has a price when GeckoTerminal —
    /// which only indexes pools it has crawled — does not.
    private static func dexscreener(chain: String, address: String) async -> TokenChart? {
        guard let root = await IngestSupport.getJSON(
            "https://api.dexscreener.com/latest/dex/tokens/\(address)") as? [String: Any],
              let pairs = root["pairs"] as? [[String: Any]], !pairs.isEmpty else { return nil }

        func liquidity(_ p: [String: Any]) -> Double {
            (p["liquidity"] as? [String: Any])?["usd"] as? Double ?? 0
        }
        // Prefer a pair on the token's own chain; otherwise the deepest pool.
        let onChain = pairs.filter { ($0["chainId"] as? String) == chain }
        guard let pair = (onChain.isEmpty ? pairs : onChain)
                .max(by: { liquidity($0) < liquidity($1) }),
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
                          coarse: true)
    }

    /// A JSON number that may arrive as Double, Int, or String.
    private static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
