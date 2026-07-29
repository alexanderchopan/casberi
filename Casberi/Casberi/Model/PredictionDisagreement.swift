import Foundation

/// The "All" browse scope's own live join (prd §233, 2026-07-29) — reuses
/// `PredictionMoments.titlesMatch` (the exact word-overlap test the watched-
/// market disagreement MOMENT already fires on) to surface the same
/// cross-venue comparison at BROWSE time, before either side is watched.
///
/// Deliberately NOT persisted. `PredictionTwin.find` already does the
/// one-shot single-market version of this at watch time; this is its batch
/// sibling for a browse list, recomputed on every visit rather than backed
/// by a stored join — the busiest markets change day to day, and a stale
/// pairing would be a worse bug than a slightly slower re-fetch. Bounded to
/// the first `limit` Kalshi rows (each check costs one Polymarket search),
/// same shape as `KalshiWatch.search`'s own hydration cap — a browse screen
/// fans out to a handful of requests, never an unbounded one per row.
@MainActor
enum PredictionDisagreement {
    struct Pair: Identifiable {
        let kalshi: KalshiWatch.Resolved
        let polymarket: PolymarketBridge.Resolved
        var id: String { "\(kalshi.ticker):\(polymarket.conditionId)" }
    }

    static func find(among kalshiRows: [KalshiWatch.Resolved], limit: Int = 6) async -> [Pair] {
        var pairs: [Pair] = []
        for k in kalshiRows.prefix(limit) {
            let hits = await PolymarketBridge.search(k.title, limit: 3)
            guard let p = hits.first(where: { PredictionMoments.titlesMatch(k.title, $0.title) }) else { continue }
            pairs.append(Pair(kalshi: k, polymarket: p))
        }
        return pairs
    }
}
