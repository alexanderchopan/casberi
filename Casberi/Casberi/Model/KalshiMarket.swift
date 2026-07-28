import Foundation

/// A Kalshi market's live read (2026-07-11) — the probability-market analog
/// of TokenChart, without a historical curve: Kalshi's public candlestick
/// endpoint is thin for most game markets, so rather than fake a chart,
/// Casberi shows the one honest number it can stand behind — the live YES
/// price (the market's odds) — against the price it last moved from.
struct KalshiMarket {
    let ticker: String
    let title: String
    let subtitle: String
    let probability: Double        // 0...1
    let previousProbability: Double?
    let status: String             // "active", "closed", "settled", …
    let closeTime: Date?
    /// Kalshi's own settlement field on a market object: "" while live, else
    /// "yes"/"no" — read directly rather than inferred from price, since a
    /// near-0/near-1 LIVE market can still flip (prd §83 ②'s reasoning
    /// extended to resolution: a probability is never treated as a verdict).
    let result: String?
    /// The kalshi.com market page — carried here (not just built ad hoc at
    /// each call site) so `prediction` below can hand it to the shared
    /// PredictionMarket shape.
    let url: String

    var resolved: Bool { status == "settled" || status == "finalized" }
    var yesWon: Bool? {
        switch result?.lowercased() {
        case "yes": return true
        case "no": return false
        default: return nil
        }
    }

    /// Contracts traded — `volume_fp`, a STRING (`volume` itself is always
    /// null on this API; measured 2026-07-28, and sorting on the null field
    /// silently ordered every search result at zero).
    let volume: Double

    /// This market, in the shape PredictionPulse/PredictionMoments share
    /// with Polymarket.
    var prediction: PredictionMarket {
        PredictionMarket(source: .kalshi, id: ticker, title: title, subtitle: subtitle,
                          url: url, probability: probability, volume: volume,
                          resolved: resolved, yesWon: yesWon, closeTime: closeTime)
    }

    /// Pulls a market's series+event tickers out of a kalshi.com market URL
    /// (`https://kalshi.com/markets/kxnflgame/kxnflgame-26sep14denkc`).
    static func route(from content: String) -> (series: String, event: String)? {
        guard let url = URL(string: content),
              url.host()?.contains("kalshi.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3, parts[0] == "markets" else { return nil }
        return (series: parts[1], event: parts[2])
    }

    /// Refetches a market's current price by its event ticker — the leaf
    /// market ticker isn't in the URL (a game's two outcomes share one
    /// page), so this reads the event's still-open market, or its first
    /// market at all once the game has settled.
    static func fetch(series: String, event: String) async -> KalshiMarket? {
        guard let root = await IngestSupport.getJSON(
            "https://api.elections.kalshi.com/trade-api/v2/events/\(event.uppercased())?with_nested_markets=true")
            as? [String: Any],
            let markets = root["markets"] as? [[String: Any]]
        else { return nil }
        let market = markets.first { ($0["status"] as? String) == "active" } ?? markets.first
        guard let market,
              let ticker = market["ticker"] as? String,
              let title = market["title"] as? String,
              // A market whose book has emptied quotes nothing; the card takes
              // its honest unavailable fallback rather than print a stale
              // `last_price` as live odds (prd §83 ②).
              let prob = KalshiWatch.liveProbability(market)
        else { return nil }
        return KalshiMarket(
            ticker: ticker, title: title,
            subtitle: (market["yes_sub_title"] as? String) ?? "",
            probability: prob,
            previousProbability: KalshiWatch.previousProbability(market),
            status: (market["status"] as? String) ?? "active",
            closeTime: IngestSupport.isoDate(market["close_time"]),
            result: market["result"] as? String,
            url: "https://kalshi.com/markets/\(series.lowercased())/\(event.lowercased())",
            volume: num(market["volume_fp"]) ?? 0)
    }

    private static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
