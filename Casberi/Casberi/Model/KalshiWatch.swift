import Foundation
import SwiftData

/// Watching a Kalshi market (2026-07-11) — the prediction-markets sibling of
/// TokenWatch. Kalshi is a CFTC-regulated event-contracts exchange; its
/// market data is public and keyless (no auth, no wallet, no account). This
/// reads a market's live probability only — Casberi never places a trade or
/// shows a path to one. Kalshi has no keyword-search endpoint (unlike
/// Dexscreener), so search fetches the open Sports-category events once,
/// cached briefly, and matches the query against their titles client-side.
enum KalshiWatch {

    struct Resolved: Identifiable {
        let ticker: String          // the leaf market ticker — one per outcome, e.g. "…-KC"
        let eventTicker: String     // the game/event ticker — the kalshi.com URL's second path piece
        let seriesTicker: String    // the league/series ticker — the URL's first path piece
        let title: String           // the market question
        let subtitle: String        // the named side, e.g. "Kansas City"
        let probability: Double     // 0...1 — the YES price, i.e. the market's odds
        let previousProbability: Double?
        let volume: Double
        var id: String { ticker }
    }

    /// The per-game series for the leagues Casberi searches — Kalshi's
    /// unfiltered event listing buries real games under its long tail of
    /// novelty/futures markets (award winners, division odds, "will X be
    /// named host"), so search goes straight to each league's own game
    /// series instead. NBA and NCAAB return nothing out of season — that's
    /// Kalshi's own open-market list, not a bug here.
    private static let gameSeries = [
        "KXNFLGAME", "KXNCAAFGAME", "KXMLBGAME", "KXNBAGAME", "KXNCAABGAME",
    ]

    /// The open games across those series, fetched once and reused for two
    /// minutes — Kalshi has no keyword search, so one batch backs every
    /// keystroke's client-side filter instead of a round trip per character.
    private actor Cache {
        var events: [[String: Any]] = []
        var fetchedAt: Date?

        func get() async -> [[String: Any]] {
            if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 120, !events.isEmpty {
                return events
            }
            var fetched: [[String: Any]] = []
            for series in gameSeries {
                guard let root = await IngestSupport.getJSON(
                    "https://api.elections.kalshi.com/trade-api/v2/events?series_ticker=\(series)&status=open&with_nested_markets=true&limit=200")
                    as? [String: Any],
                    let batch = root["events"] as? [[String: Any]]
                else { continue }
                fetched.append(contentsOf: batch)
            }
            guard !fetched.isEmpty else { return events }   // keep the stale batch over nothing
            events = fetched
            fetchedAt = Date()
            return events
        }
    }
    private static let cache = Cache()

    /// Markets whose event or team name contains the query, most-traded
    /// first — one row per market (a two-team game is two markets, each
    /// naming its own side, so both are real, distinct watches). An empty
    /// query lists the busiest markets open right now.
    static func search(_ query: String, limit: Int = 8) async -> [Resolved] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows: [Resolved] = []
        for event in await cache.get() {
            guard let eventTicker = event["event_ticker"] as? String,
                  let seriesTicker = event["series_ticker"] as? String,
                  let markets = event["markets"] as? [[String: Any]] else { continue }
            let eventTitle = (event["title"] as? String) ?? ""
            for market in markets {
                guard let ticker = market["ticker"] as? String,
                      let title = market["title"] as? String,
                      let prob = num(market["last_price_dollars"]) else { continue }
                let subtitle = (market["yes_sub_title"] as? String) ?? ""
                if !q.isEmpty {
                    let hay = "\(eventTitle) \(title) \(subtitle)".lowercased()
                    guard hay.contains(q) else { continue }
                }
                rows.append(Resolved(
                    ticker: ticker, eventTicker: eventTicker, seriesTicker: seriesTicker,
                    title: title, subtitle: subtitle, probability: prob,
                    previousProbability: num(market["previous_price_dollars"]),
                    volume: num(market["volume_fp"]) ?? 0))
            }
        }
        return Array(rows.sorted { $0.volume > $1.volume }.prefix(limit))
    }

    /// Resolves a query to its busiest matching market — the Watch button's path.
    static func resolve(_ query: String) async -> Resolved? {
        await search(query, limit: 1).first
    }

    /// Adds a resolved market to the watchlist. Returns the new thing, or
    /// nil when it's already watched (dedupe by market ticker).
    @MainActor
    @discardableResult
    static func add(_ market: Resolved, context: ModelContext) -> Thing? {
        let ref = "kalshi:\(market.ticker)"
        guard !IngestSupport.existingSourceRefs(context).contains(ref) else { return nil }
        let thing = Thing(
            kind: .link,
            title: market.title,
            content: "https://kalshi.com/markets/\(market.seriesTicker.lowercased())/\(market.eventTicker.lowercased())",
            source: "Kalshi",
            capturedAt: .now,
            tags: ["Watchlist"],
            sourceRef: ref
        )
        context.insert(thing)
        try? context.save()
        SpotlightIndex.index([thing])
        return thing
    }

    /// A JSON number that may arrive as Double or String (Kalshi sends
    /// dollar amounts as strings, e.g. "0.5800").
    private static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
