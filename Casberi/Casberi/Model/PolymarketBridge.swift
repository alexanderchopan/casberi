import Foundation
import SwiftData

/// Polymarket, the onchain sibling of Kalshi in the Markets group
/// (2026-07-28) — same read-only "watch the odds" shape (public price data,
/// no account, no wallet, nothing here ever places a trade), but with two
/// real divergences worth keeping rather than smoothing away for parity's
/// sake: Polymarket's Gamma API has a genuine keyword search (Kalshi's
/// doesn't — hence KalshiWatch's hardcoded sports-series list), and its CLOB
/// serves real price history, so PolymarketMarketView draws the curve
/// KalshiMarketView deliberately refuses to fake (prd §51 — a fallback stops
/// pretending, and Kalshi's own candlestick data is too thin to earn one).
///
/// Keyless throughout: gamma-api.polymarket.com and clob.polymarket.com both
/// serve public market data with no auth. UNMEASURED against the live API —
/// built from Polymarket's published Gamma/CLOB response shapes with no
/// network access to verify from this environment, same caveat every bridge
/// shipped this way in this codebase carries (PostHog, 1Claw, Bitrefill,
/// Privacy) — re-measure before hardening. Every parse below is defensive
/// (optional casts, guard-let chains) so a shape mismatch fails soft — an
/// empty search or a dead sheet fallback — rather than crashing.
enum PolymarketBridge {

    struct Resolved: Identifiable, PredictionOdds {
        let conditionId: String
        let slug: String            // event slug, for the polymarket.com URL
        /// The event's own headline ("Who wins the 2028 Democratic
        /// nomination?") — distinct from `title`, which is this OUTCOME's own
        /// phrasing ("Will Gavin Newsom win the 2028 Democratic presidential
        /// nomination?"). A single-outcome market has no event to differ
        /// from, so the two are the same string. `grouped(_:)` groups on
        /// `slug` and displays `eventTitle`, not `title`.
        let eventTitle: String
        let title: String
        let subtitle: String        // the outcome's own label within a multi-outcome event
        let probability: Double     // 0...1, the YES price
        /// The price a week ago (`oneWeekPriceChange` is the only delta
        /// field Gamma's markets response carries — there's no 1-day
        /// figure). Measured 2026-07-29. Genuinely a different window than
        /// Kalshi's previous-CLOSE read, so the two are never captioned with
        /// the same label — see the browse card's "vs last week".
        let previousProbability: Double?
        let volume: Double
        let closed: Bool
        let yesWon: Bool?
        let closeTime: Date?
        /// The event's own tag labels, lowercased — what `category`
        /// filtering and `categories()` match against. Empty for a market
        /// re-read outside an event context (`fetchMarket`).
        let tags: [String]
        /// The CLOB token id for the YES outcome — what the price-history
        /// read is keyed on, distinct from `conditionId` (Gamma's market
        /// identity) the way a Kalshi ticker differs from its event ticker.
        let yesTokenId: String?
        var id: String { conditionId }

        var url: String { "https://polymarket.com/event/\(slug)" }

        /// Same floor as `PredictionMarket.isThin` (24h dollars, not
        /// contracts) — see `KalshiWatch.Resolved.isThin`'s own note.
        var isThin: Bool { volume < 5_000 }

        var prediction: PredictionMarket {
            PredictionMarket(source: .polymarket, id: conditionId, title: title, subtitle: subtitle,
                              url: url, probability: probability, volume: volume,
                              resolved: closed, yesWon: yesWon, closeTime: closeTime)
        }
    }

    /// One request backs every keystroke's results — Polymarket's own search
    /// endpoint, unlike Kalshi's client-side filter over a hardcoded series
    /// list, so this genuinely improves on parity rather than matching it
    /// for its own sake. An empty query lists the busiest open markets.
    ///
    /// Both arms now go through the EVENT-wrapped endpoints (`/events` for
    /// browse, `public-search` for text — it already returned events)
    /// instead of the bare `/markets` list the empty-query arm used before
    /// 2026-07-29: an event carries `tags`, which `/markets` alone never
    /// exposes, and every nested market carries the exact same fields
    /// `/markets` does (measured) — so nothing is lost switching, and
    /// category browse and event grouping both become possible for free.
    ///
    /// `category`, when given, matches against the PARENT EVENT's tag
    /// labels, case-insensitive — combines with a query the way Kalshi's
    /// does.
    static func search(_ query: String, limit: Int = 8, category: String? = nil) async -> [Resolved] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if q.isEmpty {
            path = "https://gamma-api.polymarket.com/events?active=true&closed=false&order=volume24hr&ascending=false&limit=\(max(limit, 20))"
        } else {
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            path = "https://gamma-api.polymarket.com/public-search?q=\(encoded)&events_status=active&limit_per_type=\(limit)"
        }
        guard let root = await IngestSupport.getJSON(path) else { return [] }

        var events: [[String: Any]] = []
        if q.isEmpty {
            events = (root as? [[String: Any]]) ?? []
        } else if let dict = root as? [String: Any] {
            events = (dict["events"] as? [[String: Any]]) ?? []
        }

        let cat = category?.lowercased()
        var resolved: [Resolved] = []
        for event in events {
            let tags = eventTags(event)
            if let cat, !tags.contains(cat) { continue }
            let slug = (event["slug"] as? String) ?? ""
            let eventTitle = (event["title"] as? String) ?? ""
            for market in (event["markets"] as? [[String: Any]]) ?? [] {
                if let row = resolve(from: market, parentSlug: slug, eventTitle: eventTitle, tags: tags) {
                    resolved.append(row)
                }
            }
        }
        return Array(resolved.sorted { $0.volume > $1.volume }.prefix(limit))
    }

    /// Resolves a query to its busiest matching market — the Watch button's path.
    static func resolve(_ query: String) async -> Resolved? {
        await search(query, limit: 1).first
    }

    /// The categories actually present in the busiest ~40 open events right
    /// now — no dedicated tag-list endpoint is worth calling for this (the
    /// site-wide `/tags` list is a folksonomy of hundreds, dominated by
    /// noise like "virgins"/"redbull"); reading them off events already
    /// being fetched for browse keeps the list short and grounded in what's
    /// actually open. Narrowed to a curated set of real top-level categories
    /// (Kalshi's own 13 are real API categories; Polymarket's tags aren't
    /// categorized that way, so this curation is a judgment call, not a
    /// server fact) so the strip doesn't surface a stray granular tag like
    /// "Jerome Powell" as if it were a section of the book.
    private static let knownCategories = [
        "Politics", "Elections", "Economy", "Crypto", "Sports",
        "Entertainment", "Science", "Business", "World"
    ]

    static func categories() async -> [String] {
        guard let root = await IngestSupport.getJSON(
            "https://gamma-api.polymarket.com/events?active=true&closed=false&order=volume24hr&ascending=false&limit=40")
            as? [[String: Any]]
        else { return [] }
        var counts: [String: Int] = [:]
        for event in root {
            let tags = Set(eventTags(event))
            for known in knownCategories where tags.contains(known.lowercased()) {
                counts[known, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// A multi-outcome event grouped back into one row — the
    /// `KalshiWatch.Race` shape, applied here for the same reason (a browse
    /// list reading each candidate in a race as an unrelated question is
    /// what makes it look thin).
    struct Race: Identifiable {
        let slug: String
        let title: String
        let outcomes: [Resolved]
        let others: Int
        let closeTime: Date?
        var id: String { slug }
    }

    static func grouped(_ rows: [Resolved], maxOutcomes: Int = 4) -> [Race] {
        var order: [String] = []
        var bySlug: [String: [Resolved]] = [:]
        for row in rows {
            if bySlug[row.slug] == nil { order.append(row.slug) }
            bySlug[row.slug, default: []].append(row)
        }
        return order.map { slug in
            let outcomes = (bySlug[slug] ?? []).sorted { $0.probability > $1.probability }
            return Race(slug: slug,
                        title: outcomes.first?.eventTitle ?? "",
                        outcomes: Array(outcomes.prefix(maxOutcomes)),
                        others: max(0, outcomes.count - maxOutcomes),
                        closeTime: outcomes.first?.closeTime)
        }
    }

    /// Re-reads one market by its condition id — the Pulse refresh's path,
    /// and the only call a watched market needs after it's landed. Outside
    /// an event context, so `eventTitle` falls back to the market's own
    /// question and `tags` is empty — neither is read again once a market
    /// is already watched.
    static func fetchMarket(conditionId: String) async -> Resolved? {
        guard let root = await IngestSupport.getJSON(
            "https://gamma-api.polymarket.com/markets?condition_ids=\(conditionId)") as? [[String: Any]],
            let market = root.first
        else { return nil }
        return resolve(from: market)
    }

    /// The token id behind a market's YES price — needed separately from
    /// `fetchMarket` because the sheet's chart reads it once and reuses it,
    /// rather than re-parsing `clobTokenIds` on every price-history request.
    static func yesTokenId(conditionId: String) async -> String? {
        await fetchMarket(conditionId: conditionId)?.yesTokenId
    }

    /// The real price history Kalshi can't offer — up to `points` closes over
    /// the given window, oldest first. `clob.polymarket.com/prices-history`
    /// is keyed on the CLOB token id (one per outcome), not the condition id.
    static func priceHistory(yesTokenId: String, interval: String = "1w") async -> [Double] {
        guard let root = await IngestSupport.getJSON(
            "https://clob.polymarket.com/prices-history?market=\(yesTokenId)&interval=\(interval)&fidelity=60")
            as? [String: Any],
            let points = root["history"] as? [[String: Any]]
        else { return [] }
        return points.compactMap { num($0["p"]) }
    }

    private static func resolve(from market: [String: Any], parentSlug: String? = nil,
                                eventTitle: String? = nil, tags: [String] = []) -> Resolved? {
        guard let conditionId = market["conditionId"] as? String,
              let question = market["question"] as? String,
              let slug = parentSlug ?? eventSlug(market),
              let probability = yesPrice(market)
        else { return nil }
        let closed = (market["closed"] as? Bool) ?? false
        return Resolved(
            conditionId: conditionId, slug: slug,
            eventTitle: eventTitle?.isEmpty == false ? eventTitle! : question,
            title: question,
            subtitle: (market["groupItemTitle"] as? String) ?? "",
            probability: probability,
            previousProbability: num(market["oneWeekPriceChange"]).map { probability - $0 },
            volume: num(market["volume24hr"]) ?? num(market["volume"]) ?? 0,
            closed: closed,
            // Only an unambiguous, thoroughly settled price collapse counts —
            // a market that's merely closed-but-unresolved (arbitration still
            // pending) reports `yesWon: nil`, so no receipt fires on a guess.
            yesWon: closed ? (probability > 0.98 ? true : (probability < 0.02 ? false : nil)) : nil,
            closeTime: IngestSupport.isoDate(market["endDate"]),
            tags: tags,
            yesTokenId: clobYesTokenId(market))
    }

    /// Gamma nests the parent event for its slug on a multi-outcome market's
    /// read; a single-market event's own `slug` resolves the same page too.
    /// Only consulted when the caller has no parent event of its own
    /// (`fetchMarket`'s bare re-read) — every browse path already knows its
    /// event and passes `parentSlug` directly.
    private static func eventSlug(_ market: [String: Any]) -> String? {
        if let events = market["events"] as? [[String: Any]],
           let slug = events.first?["slug"] as? String { return slug }
        return market["slug"] as? String
    }

    /// An event's own tag labels, lowercased — `search`/`categories()`'s
    /// shared read of the one field `/markets` alone never exposes.
    private static func eventTags(_ event: [String: Any]) -> [String] {
        ((event["tags"] as? [[String: Any]]) ?? []).compactMap { ($0["label"] as? String)?.lowercased() }
    }

    /// `outcomePrices` arrives as a JSON-ENCODED STRING (`"[\"0.34\", \"0.66\"]"`),
    /// not a native array — Gamma's own quirk, not a parsing choice here.
    /// Index 0 is the YES price by construction (`outcomes` is `["Yes","No"]`
    /// for a binary market).
    private static func yesPrice(_ market: [String: Any]) -> Double? {
        decodedStringArray(market["outcomePrices"]).first.flatMap(Double.init)
    }

    private static func clobYesTokenId(_ market: [String: Any]) -> String? {
        decodedStringArray(market["clobTokenIds"]).first
    }

    private static func decodedStringArray(_ raw: Any?) -> [String] {
        if let array = raw as? [String] { return array }
        guard let s = raw as? String, let data = s.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return array
    }

    private static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let s = any as? String { return Double(s) }
        return nil
    }

    // MARK: - Watching

    static let refPrefix = "polymarket:"

    /// The condition id off a landed Polymarket thing's sourceRef — the
    /// PostHogWatch.event(from:) precedent (ThingContent.swift's ThingChart
    /// dispatch), since a Polymarket URL alone can't identify which of an
    /// event's several outcome-markets a row watches.
    static func conditionId(from thing: Thing) -> String? {
        guard let ref = thing.sourceRef, ref.hasPrefix(refPrefix) else { return nil }
        return String(ref.dropFirst(refPrefix.count))
    }

    /// Adds a resolved market to the watchlist. Returns the new thing, or
    /// nil when it's already watched (dedupe by condition id).
    @MainActor
    @discardableResult
    static func add(_ market: Resolved, context: ModelContext) -> Thing? {
        let ref = "\(refPrefix)\(market.conditionId)"
        guard !IngestSupport.hasSourceRef(context, source: "Polymarket", ref: ref) else { return nil }
        let thing = Thing(
            kind: .link,
            title: market.title,
            content: market.url,
            source: "Polymarket",
            capturedAt: .now,
            tags: ["Watchlist"],
            sourceRef: ref
        )
        // Same since-you-watched anchor as Kalshi's — a 0...1 probability
        // riding Tokens' watchPriceUsd field — and the same close-time-as-
        // deadline, which puts a watched market in "What's coming up?".
        thing.watchPriceUsd = market.probability
        thing.dueAt = market.closeTime
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return thing
    }
}
