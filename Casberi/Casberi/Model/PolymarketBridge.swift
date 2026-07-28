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

    struct Resolved: Identifiable {
        let conditionId: String
        let slug: String            // event slug, for the polymarket.com URL
        let title: String
        let subtitle: String        // the outcome's own label within a multi-outcome event
        let probability: Double     // 0...1, the YES price
        let volume: Double
        let closed: Bool
        let yesWon: Bool?
        let closeTime: Date?
        /// The CLOB token id for the YES outcome — what the price-history
        /// read is keyed on, distinct from `conditionId` (Gamma's market
        /// identity) the way a Kalshi ticker differs from its event ticker.
        let yesTokenId: String?
        var id: String { conditionId }

        var url: String { "https://polymarket.com/event/\(slug)" }

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
    static func search(_ query: String, limit: Int = 8) async -> [Resolved] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if q.isEmpty {
            path = "https://gamma-api.polymarket.com/markets?active=true&closed=false&order=volume24hr&ascending=false&limit=\(limit)"
        } else {
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            path = "https://gamma-api.polymarket.com/public-search?q=\(encoded)&events_status=active&limit_per_type=\(limit)"
        }
        guard let root = await IngestSupport.getJSON(path) else { return [] }

        var marketDicts: [[String: Any]] = []
        if q.isEmpty {
            marketDicts = (root as? [[String: Any]]) ?? []
        } else if let dict = root as? [String: Any] {
            let events = (dict["events"] as? [[String: Any]]) ?? []
            for event in events {
                marketDicts.append(contentsOf: (event["markets"] as? [[String: Any]]) ?? [])
            }
            marketDicts.append(contentsOf: (dict["markets"] as? [[String: Any]]) ?? [])
        }
        let resolved = marketDicts.compactMap(resolve(from:))
        return Array(resolved.sorted { $0.volume > $1.volume }.prefix(limit))
    }

    /// Resolves a query to its busiest matching market — the Watch button's path.
    static func resolve(_ query: String) async -> Resolved? {
        await search(query, limit: 1).first
    }

    /// Re-reads one market by its condition id — the Pulse refresh's path,
    /// and the only call a watched market needs after it's landed.
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

    private static func resolve(from market: [String: Any]) -> Resolved? {
        guard let conditionId = market["conditionId"] as? String,
              let question = market["question"] as? String,
              let slug = eventSlug(market),
              let probability = yesPrice(market)
        else { return nil }
        let closed = (market["closed"] as? Bool) ?? false
        return Resolved(
            conditionId: conditionId, slug: slug, title: question,
            subtitle: (market["groupItemTitle"] as? String) ?? "",
            probability: probability,
            volume: num(market["volume24hr"]) ?? num(market["volume"]) ?? 0,
            closed: closed,
            // Only an unambiguous, thoroughly settled price collapse counts —
            // a market that's merely closed-but-unresolved (arbitration still
            // pending) reports `yesWon: nil`, so no receipt fires on a guess.
            yesWon: closed ? (probability > 0.98 ? true : (probability < 0.02 ? false : nil)) : nil,
            closeTime: IngestSupport.isoDate(market["endDate"]),
            yesTokenId: clobYesTokenId(market))
    }

    /// Gamma nests the parent event for its slug on a multi-outcome market's
    /// read; a single-market event's own `slug` resolves the same page too.
    private static func eventSlug(_ market: [String: Any]) -> String? {
        if let events = market["events"] as? [[String: Any]],
           let slug = events.first?["slug"] as? String { return slug }
        return market["slug"] as? String
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
