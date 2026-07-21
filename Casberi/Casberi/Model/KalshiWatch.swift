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

    /// The series Casberi searches — Kalshi's unfiltered event listing buries
    /// real games under its long tail of novelty/futures markets (award
    /// winners, division odds, "will X be named host"), so search goes
    /// straight to each league's own game series instead. NBA and NCAAB return
    /// nothing out of season — that's Kalshi's own open-market list, not a bug
    /// here. Any series that doesn't resolve is silently skipped by Cache.get(),
    /// so a stale or seasonal ticker costs nothing but the request.
    ///
    /// FIFA World Cup 2026 is the one curated future that earns a place beside
    /// the game series: Kalshi is the tournament's official market partner, and
    /// "who wins the World Cup" is the headline market people search for — not
    /// the novelty long-tail the rule above guards against. KXMENWORLDCUP (the
    /// winner future) is confirmed from the live market URL; KXWORLDCUPGAME is
    /// the per-match series, best-effort until verified on-device against the
    /// live API (unreachable from CI) — harmless if the ticker's off.
    private static let searchSeries = [
        "KXNFLGAME", "KXNCAAFGAME", "KXMLBGAME", "KXNBAGAME", "KXNCAABGAME",
        "KXMENWORLDCUP", "KXWORLDCUPGAME",
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
            for series in searchSeries {
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
                      let prob = liveProbability(market) else { continue }
                let subtitle = (market["yes_sub_title"] as? String) ?? ""
                if !q.isEmpty {
                    let hay = "\(eventTitle) \(title) \(subtitle)".lowercased()
                    guard hay.contains(q) else { continue }
                }
                rows.append(Resolved(
                    ticker: ticker, eventTicker: eventTicker, seriesTicker: seriesTicker,
                    title: title, subtitle: subtitle, probability: prob,
                    previousProbability: previousProbability(market),
                    volume: num(market["volume_fp"]) ?? 0))
            }
        }
        return Array(rows.sorted { $0.volume > $1.volume }.prefix(limit))
    }

    /// Resolves a query to its busiest matching market — the Watch button's path.
    static func resolve(_ query: String) async -> Resolved? {
        await search(query, limit: 1).first
    }

    /// The book brackets the market's own answer: yes trades somewhere in
    /// [bid, ask], so its midpoint IS the probability — one-sided books
    /// included (a 99¢ bid with no ask is a near-certainty, a 1¢ ask with no
    /// bid is a long shot; both are real quotes). Bid 0 / ask 1 is the one
    /// bracket that says nothing — the whole range, i.e. no orders either
    /// side — and that is exactly the emptied book, so it quotes nothing.
    ///
    /// `last_price` is deliberately NOT consulted: Kalshi leaves a market
    /// listed after its book empties, and the residual trade left behind
    /// (often a tenth of a cent) is what printed "0%" against the USA to win
    /// a World Cup it hasn't played. A stale trade is not a price (prd §83 ②).
    private static func bookMid(_ market: [String: Any], bid bidKey: String,
                               ask askKey: String) -> Double? {
        guard let bid = num(market[bidKey]), let ask = num(market[askKey]),
              bid > 0 || ask < 1 else { return nil }
        return (bid + ask) / 2
    }

    /// Now.
    static func liveProbability(_ market: [String: Any]) -> Double? {
        bookMid(market, bid: "yes_bid_dollars", ask: "yes_ask_dollars")
    }

    /// The prior close, read the SAME way — a "vs last" delta has to subtract
    /// like for like, and a mid minus a last trade invents a move out of half
    /// the spread.
    static func previousProbability(_ market: [String: Any]) -> Double? {
        bookMid(market, bid: "previous_yes_bid_dollars", ask: "previous_yes_ask_dollars")
    }

    /// Adds a resolved market to the watchlist. Returns the new thing, or
    /// nil when it's already watched (dedupe by market ticker).
    @MainActor
    @discardableResult
    static func add(_ market: Resolved, context: ModelContext) -> Thing? {
        let ref = "kalshi:\(market.ticker)"
        guard !IngestSupport.hasSourceRef(context, source: "Kalshi", ref: ref) else { return nil }
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
        context.saveHonestly()
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
