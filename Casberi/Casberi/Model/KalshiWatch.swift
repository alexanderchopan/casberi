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

    struct Resolved: Identifiable, PredictionOdds {
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

        /// Same floor as `PredictionMarket.isThin` (contracts, not dollars) —
        /// duplicated rather than routed through a constructed
        /// `PredictionMarket` because a browse row has no settlement state
        /// to fill in for one.
        var isThin: Bool { volume < 1_000 }
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
        /// The walk currently in flight, shared by every concurrent caller
        /// (2026-08-03). An actor SUSPENDS at each `await`, so it does not
        /// serialize a method that does I/O — and `search` and `categories`
        /// are started as siblings by `PredictionBrowseSection.loadIfNeeded`,
        /// so both used to walk into `get()` on a cold cache, both see no
        /// `fetchedAt`, and both run the full discovery walk: 6 requests for
        /// 3 pages of data, doubling the burst at exactly the moment a rate
        /// limit is the thing most likely to be biting.
        ///
        /// UNSTRUCTURED on purpose. `.task(id:)` cancels the previous load
        /// the instant the query or category changes, and a cancelled
        /// `URLSession.data(for:)` throws — so a shared walk owned by the
        /// STRUCTURED task tree would be killed by whichever browse gave up
        /// first, handing the newer load (which is waiting on it) an empty
        /// book. Detached from any one caller, the walk finishes for whoever
        /// is still listening.
        private var inFlight: Task<(events: [[String: Any]], truncated: Bool), Never>?
        /// Bumped by `invalidate()` so a walk that was already in the air
        /// when a pull-to-refresh landed can't commit its pre-pull batch
        /// over the fresh one and re-stamp `fetchedAt` with it.
        private var generation = 0
        /// The HTTP status the last discovery read answered with — 200 when
        /// the listing served, 429 when Kalshi is pacing us, 0 when nothing
        /// answered at all. `IngestSupport.getJSON` collapses all three into
        /// one nil, and the room could only ever render that as "couldn't
        /// reach", which is a claim about the network that is FALSE for two
        /// of the three (prd §83's no-fake-status rule applied to an error
        /// message). Kept here rather than threaded through the return tuple
        /// because only the empty case ever reads it.
        private(set) var lastStatus = 0

        func get() async -> (events: [[String: Any]], truncated: Bool) {
            if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 120, !events.isEmpty {
                return (events, truncated)
            }
            if let inFlight { return await inFlight.value }
            let gen = generation
            let task = Task { await self.walk(generation: gen) }
            inFlight = task
            let result = await task.value
            if generation == gen { inFlight = nil }
            return result
        }

        private func walk(generation gen: Int) async -> (events: [[String: Any]], truncated: Bool) {
            var fetched: [[String: Any]] = []
            var cursor = ""
            var more = false
            var firstStatus: Int?
            for _ in 0..<discoveryPages {
                // The cursor is an OPAQUE token and is not safe to paste into
                // a query string raw: a `+` in it decodes to a space and a
                // `=`/`&` ends the parameter early, so page 2 comes back a
                // 400 and the walk silently truncates to page 1. `.alphanumerics`
                // rather than `.urlQueryAllowed` on purpose — the query-allowed
                // set leaves exactly those three characters alone, which is
                // the whole bug.
                let paged = cursor.isEmpty ? "" :
                    "&cursor=\(cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? cursor)"
                let hit = await IngestSupport.getJSONStatus(
                    "https://api.elections.kalshi.com/trade-api/v2/events?status=open&limit=200&with_nested_markets=false\(paged)")
                if firstStatus == nil { firstStatus = hit.status }
                guard let root = hit.json as? [String: Any],
                      let batch = root["events"] as? [[String: Any]], !batch.isEmpty
                else { break }
                fetched.append(contentsOf: batch)
                cursor = (root["cursor"] as? String) ?? ""
                more = !cursor.isEmpty
                if cursor.isEmpty { break }
            }
            lastStatus = firstStatus ?? 0
            // Keep the stale batch over nothing — one bad read shouldn't blank
            // a book that already loaded.
            guard !fetched.isEmpty else { return (events, truncated) }
            // A pull-to-refresh landed while this walk was in the air. Its
            // batch must not be COMMITTED — it predates the pull, and
            // committing would re-stamp `fetchedAt` so the next 120s serve
            // pre-pull data the gesture explicitly asked past. But it must
            // still be RETURNED.
            //
            // Returning `events` here instead (the old behaviour) handed every
            // caller waiting on this walk an EMPTY book on a cold cache, and
            // the room can only render an empty book as "Couldn't reach the
            // market book just now." — on a read that reached it fine and had
            // the whole listing in hand. That is the self-reinforcing shape of
            // the reported failure: `FeedScreen.performPull` bumps
            // `chrome.refreshPulse` (which re-fires the browse `.task(id:)`,
            // starting this walk) BEFORE it awaits `invalidateCache()`, so
            // every pull-to-refresh in a prediction room raced its own reload
            // and lost — the error appears, the obvious response is to pull to
            // refresh, and the pull is what guarantees it appears again. The
            // ordering is fixed at that call site too; this is the half that
            // holds regardless of who invalidates when.
            guard generation == gen else { return (fetched, more) }
            events = fetched
            truncated = more
            fetchedAt = Date()
            return (events, truncated)
        }

        /// A deliberate pull re-fetches live (2026-07-30, the density-pass
        /// follow-up) — the same contract `WalletIngest.invalidateHoldingsCache`
        /// already holds for the wallet's own TTL cache: the window is for
        /// the automatic browse, not the gesture that explicitly asks for
        /// fresh.
        func invalidate() { fetchedAt = nil; generation &+= 1; inFlight = nil }

        var age: TimeInterval? { fetchedAt.map { Date().timeIntervalSince($0) } }
    }
    private static let cache = Cache()

    /// Room's own pull-to-refresh calls this (`FeedScreen.refreshFeed`) —
    /// see `Cache.invalidate`'s note. Polymarket's `search` never caches
    /// (every call is already live), so it has no equivalent.
    static func invalidateCache() async { await cache.invalidate() }

    /// Seconds since the last real fetch, nil before the first one — what
    /// the room's freshness line reads (`PredictionBrowseSection`).
    static func cacheAge() async -> TimeInterval? { await cache.age }

    /// Markets matching the query, most-traded first — one row per market (a
    /// two-outcome event is two markets, each naming its own side, so both
    /// are real, distinct watches). An empty query lists the busiest markets
    /// open right now, across every category rather than sports alone.
    ///
    /// `category`, when given, is applied to phase 1 the same way the text
    /// query is — an event's own `category` field, exact match, case-
    /// insensitive. Combines with a query (a category AND a search term both
    /// narrow the same candidate list) rather than replacing it.
    static func search(_ query: String, limit: Int = 8, category: String? = nil) async -> [Resolved] {
        await book(query, limit: limit, category: category).rows
    }

    /// Why a browse came back with nothing (2026-08-03). The room used to
    /// print "Couldn't reach the market book just now." for EVERY empty
    /// result, which is a claim about the network that nothing here had
    /// measured — and the reported failure was a screenshot showing that
    /// line above a fully populated category strip, i.e. above proof that
    /// the book HAD been reached. A dead control and a fake status are the
    /// same offence (prd §83), so the room now says which of these it is.
    enum BookOutcome: Equatable {
        /// Rows came back.
        case rows
        /// No read answered with a usable body, carrying the HTTP status that
        /// came back so the room can say WHICH failure it was. 0 is a
        /// transport failure — offline, DNS, a dropped connection — and the
        /// only one "couldn't reach" honestly describes. 429 is Kalshi pacing
        /// us and clears itself in seconds. A 4xx is an endpoint that moved,
        /// which no amount of retrying fixes. Three problems, three different
        /// next steps for the person holding the phone; without the status
        /// they all read as "check your wifi".
        case unreached(status: Int)
        /// The book was read fine; the query/category simply matched no open
        /// event.
        case noMatch
        /// Events matched and their markets were read, but not one of them
        /// is quoting a price — every book we opened was empty or its quote
        /// fields were unreadable. Reads as a live exchange with nothing to
        /// say, never as a network failure.
        case noQuote
    }

    struct Book {
        let rows: [Resolved]
        let outcome: BookOutcome
    }

    /// `search`, plus the reason an empty result is empty.
    static func book(_ query: String, limit: Int = 8, category: String? = nil) async -> Book {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cat = category?.lowercased()
        let (events, _) = await cache.get()
        guard !events.isEmpty else {
            return Book(rows: [], outcome: .unreached(status: await cache.lastStatus))
        }

        // Phase 1 — match on the cheap listing (title + subtitle + category).
        var candidates: [[String: Any]] = []
        for event in events {
            guard event["event_ticker"] is String else { continue }
            if let cat, (event["category"] as? String)?.lowercased() != cat { continue }
            if q.isEmpty {
                candidates.append(event)
            } else {
                let hay = [event["title"] as? String, event["sub_title"] as? String,
                           event["category"] as? String]
                    .compactMap(\.self).joined(separator: " ").lowercased()
                if hay.contains(q) { candidates.append(event) }
            }
        }
        guard !candidates.isEmpty else { return Book(rows: [], outcome: .noMatch) }

        // Phase 2 — hydrate only the matches, and only a handful of them: one
        // small per-event fetch each, bounded so a broad query ("the") can't
        // turn into hundreds of requests. Over-fetch past `limit` because an
        // event can hold many markets and the volume sort happens after.
        let hydrate = Array(candidates.prefix(max(limit, 12)))
        let hydrated = await IngestSupport.boundedGather(hydrate, maxConcurrent: 4) { event -> Hydrated in
            guard let ticker = event["event_ticker"] as? String else {
                return Hydrated(rows: [], reached: false, status: 0)
            }
            return await markets(inEvent: ticker,
                                 category: (event["category"] as? String) ?? "",
                                 query: q)
        }
        let rows = Array(hydrated.flatMap(\.rows).sorted { $0.volume > $1.volume }.prefix(limit))
        if !rows.isEmpty { return Book(rows: rows, outcome: .rows) }
        // Not one event answered. Phase 1 succeeded, so the network is
        // demonstrably fine and the status is the whole story — this is the
        // read most likely to be rate-limited, since it fires one request per
        // matching event in a burst while phase 1 fired one. Report the first
        // status anything actually answered with, falling back to 0 only when
        // nothing did.
        guard hydrated.contains(where: \.reached) else {
            let answered = hydrated.first { $0.status != 0 }?.status ?? 0
            return Book(rows: [], outcome: .unreached(status: answered))
        }
        return Book(rows: [], outcome: .noQuote)
    }

    /// One event's hydration: its rows, and whether the fetch itself
    /// answered at all. The pair is what lets `book` tell "every book is
    /// empty" from "every request failed" — indistinguishable from a bare
    /// row count, and the difference between an honest empty state and a
    /// wrong one.
    private struct Hydrated {
        let rows: [Resolved]
        let reached: Bool
        /// The HTTP status this event's read answered with — 200 when it
        /// reached, 429 when Kalshi paced us, 0 when nothing came back. What
        /// lets an all-failed hydration say WHY rather than blame the
        /// connection phase 1 just proved was working.
        let status: Int
    }

    /// One event's open markets, as watchable rows. The query is re-applied
    /// against each market's OWN title/side — an event matched on its
    /// category alone shouldn't hand back every candidate in the race.
    private static func markets(inEvent eventTicker: String, category: String,
                                query q: String) async -> Hydrated {
        let hit = await IngestSupport.getJSONStatus(
            "https://api.elections.kalshi.com/trade-api/v2/events/\(eventTicker.uppercased())?with_nested_markets=true")
        guard let root = hit.json as? [String: Any] else {
            return Hydrated(rows: [], reached: false, status: hit.status)
        }
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
                volume: volume(market),
                category: category,
                closeTime: IngestSupport.isoDate(market["close_time"])))
        }
        // A query that named a SIDE ("Chiefs") keeps only that side; one that
        // named the race keeps the field. Applied after the fetch because the
        // side's name lives on the market, not on the listing.
        guard !q.isEmpty else { return Hydrated(rows: rows, reached: true, status: hit.status) }
        let sideMatches = rows.filter { "\($0.title) \($0.subtitle)".lowercased().contains(q) }
        return Hydrated(rows: sideMatches.isEmpty ? rows : sideMatches,
                        reached: true, status: hit.status)
    }

    /// Resolves a query to its busiest matching market — the Watch button's path.
    static func resolve(_ query: String) async -> Resolved? {
        await search(query, limit: 1).first
    }

    // MARK: - Diagnosis

    /// What `-kalshiBookProbe` prints (2026-08-03). Three separate reads,
    /// reported separately, because an empty book has three causes that look
    /// identical from the room and need three different fixes:
    ///
    ///   1. discovery didn't answer          → the exchange or the network
    ///   2. discovery answered, no candidates → `event_ticker` moved/renamed
    ///   3. candidates hydrated, no quotes    → the price fields moved/renamed
    ///
    /// The reported failure could not be narrowed past "one of these" from
    /// the code alone, and it can't be narrowed from a screenshot either: the
    /// room renders the same sentence for all three. So this names the HTTP
    /// status of each phase and, decisively, the price keys the payload
    /// actually carries — a rename shows up as a `fields=` line missing the
    /// name the app reads, in one launch, with no debugger.
    ///
    /// Bypasses the 120s cache (`invalidate()` first) so a probe run is
    /// always a live measurement rather than a re-serve of the read that may
    /// itself be the problem.
    static func diagnose(limit: Int = 5) async -> [String] {
        var out: [String] = []
        await cache.invalidate()

        let listing = await IngestSupport.getJSONStatus(
            "https://api.elections.kalshi.com/trade-api/v2/events?status=open&limit=200&with_nested_markets=false")
        let root = listing.json as? [String: Any]
        let events = (root?["events"] as? [[String: Any]]) ?? []
        let ticketed = events.filter { $0["event_ticker"] is String }
        out.append("discovery status=\(listing.status) events=\(events.count) with_event_ticker=\(ticketed.count) hasMore=\((root?["cursor"] as? String)?.isEmpty == false)")
        if listing.status != 200 {
            // 0 is a transport failure, 429 a rate limit, 4xx a moved
            // endpoint — three different fixes wearing one empty room.
            out.append("discovery FAILED — nothing below could have run")
            return out
        }
        // Two different failures, said differently: an empty list is an
        // exchange with nothing open (or a moved `events` envelope), a
        // populated list with no tickers is the `event_ticker` rename. They
        // look identical from the room and neither is a network problem.
        if events.isEmpty {
            out.append("phase 1 FAILED — 200 but the `events` array is empty or absent")
            out.append("listing keys: \(Array((root ?? [:]).keys).sorted().joined(separator: ","))")
            return out
        }
        if ticketed.isEmpty {
            out.append("phase 1 FAILED — \(events.count) events, NOT ONE carrying `event_ticker`; the field moved")
            out.append("event keys: \(Array((events.first ?? [:]).keys).sorted().joined(separator: ","))")
            return out
        }
        var cats: [String: Int] = [:]
        for e in events { if let c = e["category"] as? String, !c.isEmpty { cats[c, default: 0] += 1 } }
        out.append("categories=\(cats.count): \(cats.sorted { $0.value > $1.value }.map(\.key).joined(separator: ", "))")

        var quoted = 0
        for event in ticketed.prefix(limit) {
            let ticker = (event["event_ticker"] as? String) ?? "?"
            let hit = await IngestSupport.getJSONStatus(
                "https://api.elections.kalshi.com/trade-api/v2/events/\(ticker.uppercased())?with_nested_markets=true")
            let body = hit.json as? [String: Any]
            let nested = (body?["event"] as? [String: Any])
            // Named `onWire`, not `markets` — a local called `markets` would
            // shadow `markets(inEvent:category:query:)` for the rest of this
            // scope, which is a trap for the next edit rather than a bug today.
            let onWire = (body?["markets"] as? [[String: Any]])
                ?? (nested?["markets"] as? [[String: Any]]) ?? []
            let priced = onWire.filter { liveProbability($0) != nil }
            quoted += priced.count
            // The decisive line: the price-shaped keys really on the wire,
            // beside the ones the app reads. Only the first market's — the
            // shape is per-payload, not per-row, and one is enough to see a
            // rename.
            let keys = Array((onWire.first ?? [:]).keys)
                .filter { $0.contains("bid") || $0.contains("ask") || $0.contains("volume") || $0.contains("price") }
                .sorted().joined(separator: ",")
            out.append("event \(ticker) status=\(hit.status) markets=\(onWire.count) quoted=\(priced.count) fields=[\(keys)]")
        }
        out.append(quoted > 0
                   ? "phase 2 OK — \(quoted) quoted market(s) across \(min(limit, ticketed.count)) event(s)"
                   : "phase 2 FAILED — events hydrated but NOT ONE quotes a price; compare `fields=` against yes_bid_dollars/yes_ask_dollars (and the yes_bid/yes_ask fallback)")

        // The room's own read, end to end — what the browse section would
        // have shown, and which empty-state sentence it would have printed.
        let browse = await book("", limit: 24, category: nil)
        out.append("book(\"\") rows=\(browse.rows.count) outcome=\(browse.outcome)")
        return out
    }

    /// The categories actually present in the open-events cache right now,
    /// busiest first (by event COUNT, not volume — the raw listing carries
    /// no volume, only the hydrated markets do). Free: the cache is already
    /// in memory for every browse, and `category` was already being parsed
    /// per event and used only as a search haystack (see the file header) —
    /// this is that same field, finally read for its own sake. Bounded to
    /// the cache's own truncation (prd: `discoveryPages` × 200), so a
    /// category present only in the untouched tail won't appear — an honest
    /// side effect of the same bound the browse list already lives with.
    static func categories() async -> [String] {
        let (events, _) = await cache.get()
        var counts: [String: Int] = [:]
        for event in events {
            guard let cat = event["category"] as? String, !cat.isEmpty else { continue }
            counts[cat, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// A multi-outcome event (a race, a nomination) grouped back into ONE
    /// row instead of one row per candidate — `search`/`markets(inEvent:)`
    /// deliberately return every outcome as its own `Resolved` (each is a
    /// real, separately watchable market), but a browse LIST reading eight
    /// siblings from the same race as unrelated questions is the reason it
    /// looks thin (prd: the event explosion). Outcomes sort busiest-first;
    /// `others` is the count left off after `maxOutcomes`, never silently
    /// dropped from the field's own true size.
    struct Race: Identifiable {
        let eventTicker: String
        let title: String
        let outcomes: [Resolved]
        let others: Int
        let closeTime: Date?
        var id: String { eventTicker }
    }

    /// 3, not 4 (density pass, 2026-07-29) — one fewer row on every race card
    /// in the book, still leader + two challengers before "N more" takes
    /// over; `others` keeps the field's true size honest either way.
    static func grouped(_ rows: [Resolved], maxOutcomes: Int = 3) -> [Race] {
        var order: [String] = []
        var byEvent: [String: [Resolved]] = [:]
        for row in rows {
            if byEvent[row.eventTicker] == nil { order.append(row.eventTicker) }
            byEvent[row.eventTicker, default: []].append(row)
        }
        return order.map { ticker in
            let outcomes = (byEvent[ticker] ?? []).sorted { $0.probability > $1.probability }
            return Race(eventTicker: ticker,
                        title: outcomes.first?.title ?? "",
                        outcomes: Array(outcomes.prefix(maxOutcomes)),
                        others: max(0, outcomes.count - maxOutcomes),
                        closeTime: outcomes.first?.closeTime)
        }
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
    /// The `_dollars` pair is read FIRST and wins whenever it is present, so
    /// this changes no number on a payload shaped the way 2026-07-28 measured
    /// one. The integer-CENT pair beneath it is a fallback, added 2026-08-03:
    /// those two fields were the app's single point of failure for the entire
    /// book — every market whose quote can't be read is dropped by
    /// `markets(inEvent:)`, so if Kalshi ever stops sending `yes_bid_dollars`
    /// the room goes completely empty with no error anywhere, which is
    /// exactly the shape of the reported failure (categories populated, book
    /// blank). The app was already living with this API mid-migration —
    /// `volume` measured null while `volume_fp` carried the number — and a
    /// read with one source and no fallback is what makes that drift fatal
    /// instead of cosmetic. UNMEASURED against the live API (no egress from
    /// the host this was written on); it fails to today's exact behaviour.
    private static func bookMid(_ market: [String: Any],
                                dollars: (bid: String, ask: String),
                                cents: (bid: String, ask: String)) -> Double? {
        if let mid = mid(num(market[dollars.bid]), num(market[dollars.ask]), per: 1) { return mid }
        return mid(num(market[cents.bid]), num(market[cents.ask]), per: 100)
    }

    /// The book brackets the answer, normalised to 0...1 before the empty-book
    /// test so the cents path applies the SAME rule the dollars path does —
    /// scaling after the guard would read a 0¢/100¢ empty book as a live 50%.
    private static func mid(_ bid: Double?, _ ask: Double?, per scale: Double) -> Double? {
        guard let bid, let ask else { return nil }
        let b = bid / scale, a = ask / scale
        guard b > 0 || a < 1 else { return nil }
        return (b + a) / 2
    }

    /// Now.
    static func liveProbability(_ market: [String: Any]) -> Double? {
        bookMid(market,
                dollars: ("yes_bid_dollars", "yes_ask_dollars"),
                cents: ("yes_bid", "yes_ask"))
    }

    /// The prior close, read the SAME way — a "vs last" delta has to subtract
    /// like for like, and a mid minus a last trade invents a move out of half
    /// the spread.
    static func previousProbability(_ market: [String: Any]) -> Double? {
        bookMid(market,
                dollars: ("previous_yes_bid_dollars", "previous_yes_ask_dollars"),
                cents: ("previous_yes_bid", "previous_yes_ask"))
    }

    /// Contracts traded. `volume_fp` (a STRING) is the field that carries the
    /// number today and `volume` measured null beside it (2026-07-28) — read
    /// in that order, with the plain field as the fallback for the same
    /// reason the cent quotes are one: sorting the whole book at zero is how
    /// the long tail looked inseparable from the real book last time.
    private static func volume(_ market: [String: Any]) -> Double {
        num(market["volume_fp"]) ?? num(market["volume"]) ?? 0
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
