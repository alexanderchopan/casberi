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
        /// The event's own category ("Politics", "Sports", "Economics") —
        /// Kalshi labels every event, and once search stopped being
        /// sports-only this is what tells a result apart from its neighbours.
        let category: String
        let closeTime: Date?
        var id: String { ticker }
    }

    /// Search is TWO PHASES (rebuilt 2026-07-28), and the split is a measured
    /// one, not a preference. Kalshi still has no keyword-search endpoint, so
    /// the whole open book has to be pulled and filtered on device — but
    /// pulling it WITH nested markets costs **2.9 MB and 2.2s per page**,
    /// while the same page WITHOUT them costs **157 KB and 0.8s** (19× less).
    /// So discovery reads the cheap unnested listing (titles + categories),
    /// and only the events that actually MATCH get their markets hydrated.
    ///
    /// This replaces the previous design — seven hardcoded sports series —
    /// which was written when the unfiltered listing looked like an
    /// unsortable novelty dump. It wasn't: `volume` is always null on this
    /// API and the real field is `volume_fp` (a STRING), so the old sort
    /// ordered every market at zero and the long tail looked inseparable
    /// from the real book. Sorted on the right field, the general listing
    /// leads with the presidential election and Greenland — and it carries
    /// all **13 categories** (Politics, Economics, Financials, Climate,
    /// Entertainment, …) that sports-only search could never reach.
    ///
    /// `category=` is NOT a server-side filter — measured 2026-07-28,
    /// `?category=Economics`, `=Financials` and `=Politics` returned
    /// byte-identical pages. It's a label on the payload, nothing more.
    private static let discoveryPages = 3

    /// The open events, titles only, fetched once and reused for two minutes.
    /// Bounded at `discoveryPages` × 200 on purpose: the full walk is 2400+
    /// events across 12+ pages and still not done (measured), and 1,300 of
    /// those are the state-by-state election long tail. `truncated` says so
    /// out loud rather than letting a bounded read read as a complete one.
    private actor Cache {
        var events: [[String: Any]] = []
        var truncated = false
        var fetchedAt: Date?

        func get() async -> (events: [[String: Any]], truncated: Bool) {
            if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 120, !events.isEmpty {
                return (events, truncated)
            }
            var fetched: [[String: Any]] = []
            var cursor = ""
            var more = false
            for _ in 0..<discoveryPages {
                let paged = cursor.isEmpty ? "" : "&cursor=\(cursor)"
                guard let root = await IngestSupport.getJSON(
                    "https://api.elections.kalshi.com/trade-api/v2/events?status=open&limit=200&with_nested_markets=false\(paged)")
                    as? [String: Any],
                    let batch = root["events"] as? [[String: Any]], !batch.isEmpty
                else { break }
                fetched.append(contentsOf: batch)
                cursor = (root["cursor"] as? String) ?? ""
                more = !cursor.isEmpty
                if cursor.isEmpty { break }
            }
            guard !fetched.isEmpty else { return (events, truncated) }  // keep the stale batch over nothing
            events = fetched
            truncated = more
            fetchedAt = Date()
            return (events, truncated)
        }
    }
    private static let cache = Cache()

    /// Markets matching the query, most-traded first — one row per market (a
    /// two-outcome event is two markets, each naming its own side, so both
    /// are real, distinct watches). An empty query lists the busiest markets
    /// open right now, across every category rather than sports alone.
    static func search(_ query: String, limit: Int = 8) async -> [Resolved] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let (events, _) = await cache.get()

        // Phase 1 — match on the cheap listing (title + subtitle + category).
        var candidates: [[String: Any]] = []
        for event in events {
            guard event["event_ticker"] is String else { continue }
            if q.isEmpty {
                candidates.append(event)
            } else {
                let hay = [event["title"] as? String, event["sub_title"] as? String,
                           event["category"] as? String]
                    .compactMap(\.self).joined(separator: " ").lowercased()
                if hay.contains(q) { candidates.append(event) }
            }
        }
        // Phase 2 — hydrate only the matches, and only a handful of them: one
        // small per-event fetch each, bounded so a broad query ("the") can't
        // turn into hundreds of requests. Over-fetch past `limit` because an
        // event can hold many markets and the volume sort happens after.
        let hydrate = Array(candidates.prefix(max(limit, 12)))
        let hydrated = await IngestSupport.boundedGather(hydrate, maxConcurrent: 4) { event -> [Resolved] in
            guard let ticker = event["event_ticker"] as? String else { return [] }
            return await markets(inEvent: ticker,
                                 category: (event["category"] as? String) ?? "",
                                 query: q)
        }
        return Array(hydrated.flatMap(\.self).sorted { $0.volume > $1.volume }.prefix(limit))
    }

    /// One event's open markets, as watchable rows. The query is re-applied
    /// against each market's OWN title/side — an event matched on its
    /// category alone shouldn't hand back every candidate in the race.
    private static func markets(inEvent eventTicker: String, category: String,
                                query q: String) async -> [Resolved] {
        guard let root = await IngestSupport.getJSON(
            "https://api.elections.kalshi.com/trade-api/v2/events/\(eventTicker.uppercased())?with_nested_markets=true")
            as? [String: Any] else { return [] }
        let event = (root["event"] as? [String: Any]) ?? root
        let seriesTicker = (event["series_ticker"] as? String) ?? ""
        let eventTitle = (event["title"] as? String) ?? ""
        let markets = (root["markets"] as? [[String: Any]])
            ?? (event["markets"] as? [[String: Any]]) ?? []
        var rows: [Resolved] = []
        for market in markets {
            guard let ticker = market["ticker"] as? String,
                  let title = market["title"] as? String,
                  (market["status"] as? String) != "settled",
                  let prob = liveProbability(market) else { continue }
            let subtitle = (market["yes_sub_title"] as? String) ?? ""
            rows.append(Resolved(
                ticker: ticker, eventTicker: eventTicker, seriesTicker: seriesTicker,
                title: title.isEmpty ? eventTitle : title, subtitle: subtitle,
                probability: prob,
                previousProbability: previousProbability(market),
                volume: num(market["volume_fp"]) ?? 0,
                category: category,
                closeTime: IngestSupport.isoDate(market["close_time"])))
        }
        // A query that named a SIDE ("Chiefs") keeps only that side; one that
        // named the race keeps the field. Applied after the fetch because the
        // side's name lives on the market, not on the listing.
        guard !q.isEmpty else { return rows }
        let sideMatches = rows.filter { "\($0.title) \($0.subtitle)".lowercased().contains(q) }
        return sideMatches.isEmpty ? rows : sideMatches
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
        // The since-you-watched anchor (2026-07-28) — reusing Tokens'
        // watchPriceUsd field for a 0...1 probability instead of a dollar
        // price (same anchor shape, different unit): PredictionMoments'
        // resolution receipt reads this back the day the market settles.
        thing.watchPriceUsd = market.probability
        // A market's close IS a real deadline, so it rides `dueAt` like a
        // reminder's or a 1Claw grant's expiry — which puts it in "What's
        // coming up?" for free: that composer takes any bridge that lands a
        // real deadline, by its own ruling (KeptAskComposers.upcoming).
        thing.dueAt = market.closeTime
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
