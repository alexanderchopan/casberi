import Foundation

/// A token's recent price, drawn natively (2026-07-07). Dexscreener's own API
/// gives only a current price, no history — so the curve comes from
/// GeckoTerminal's free public OHLCV (no key), and Casberi draws it itself
/// with Swift Charts rather than embedding anyone's web chart (native content,
/// per the design law). A token link → its address → its top pool → candles.
struct TokenChart {
    let closes: [Double]
    let price: Double
    let change24h: Double   // fraction, e.g. -0.048 = -4.8%

    /// Pulls the token address (and chain) out of a dexscreener link like
    /// `https://dexscreener.com/base/0x…`.
    static func route(from content: String) -> (chain: String, address: String)? {
        guard let url = URL(string: content),
              url.host()?.contains("dexscreener.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return (chain: parts[0], address: parts[1])
    }

    /// Fetches ~24h of hourly candles for the token's most-liquid pool.
    /// Returns nil when the token has no pool (dead/illiquid) — the sheet then
    /// shows the plain link, never an empty chart.
    static func fetch(chain: String, address: String) async -> TokenChart? {
        let base = "https://api.geckoterminal.com/api/v2/networks/\(chain)"
        guard let poolsRoot = await IngestSupport.getJSON("\(base)/tokens/\(address)/pools")
                as? [String: Any],
              let pools = poolsRoot["data"] as? [[String: Any]],
              let pool = pools.first?["attributes"] as? [String: Any],
              let poolAddress = pool["address"] as? String else { return nil }

        guard let ohlcvRoot = await IngestSupport.getJSON(
            "\(base)/pools/\(poolAddress)/ohlcv/hour?limit=24") as? [String: Any],
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
                          change24h: (last - first) / first)
    }
}
