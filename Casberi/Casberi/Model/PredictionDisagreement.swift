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

    /// The same join walked from the OTHER side (2026-08-10) — for each
    /// Polymarket row, does Kalshi price the same question?
    ///
    /// It exists because the Markets fold retired the merged `.all` scope that
    /// `find` was written for. Disagreement had been gated on standing in that
    /// scope, so with the venues now browsed separately the comparison would
    /// simply have disappeared — and it is the one reading an aggregate creates
    /// that neither venue can produce alone. Un-gated, `find` covers a Kalshi
    /// room (whose own rows are in hand); this covers a Polymarket one, where
    /// no Kalshi row has been fetched at all.
    ///
    /// **It reads Kalshi's open book ONCE and matches locally — it does NOT
    /// mirror `find` with the arguments swapped, and the first cut of it did,
    /// which could never have matched anything.**
    ///
    /// The two venues are not symmetric in the one way that decides this.
    /// `PolymarketBridge.search` is a real server-side relevance search, so
    /// handing it a whole Kalshi question returns plausible hits for
    /// `titlesMatch` to filter. `KalshiWatch.book` is NOT a search: its phase 1
    /// is `hay.contains(q)`, a literal substring test of the ENTIRE query
    /// against each cached event's title/subtitle/category. A full Polymarket
    /// question is essentially never a verbatim substring of a Kalshi title, so
    /// a per-row `book(p.title)` returns `.noMatch` every time — six awaits
    /// that always answer `[]`, with the room rendering perfectly and the doc
    /// claiming the comparison survives. Exactly the invisible-wrong-answer
    /// class `retriever-selftest` exists for, one venue over.
    ///
    /// So the query goes empty (matching the whole cached listing, which the
    /// browse has usually just warmed) and `titlesMatch` does the work it was
    /// written to do. That is also strictly CHEAPER than the shape it replaces
    /// — one read behind a 120s cache instead of six sequential ones — which
    /// matters more now that this runs per room load rather than only in the
    /// merged scope.
    static func findReverse(among polymarketRows: [PolymarketBridge.Resolved],
                            limit: Int = 6) async -> [Pair] {
        let kalshi = await KalshiWatch.book("", limit: 60).rows
        guard !kalshi.isEmpty else { return [] }
        var pairs: [Pair] = []
        for p in polymarketRows.prefix(limit) {
            guard let k = kalshi.first(where: { PredictionMoments.titlesMatch(p.title, $0.title) })
            else { continue }
            pairs.append(Pair(kalshi: k, polymarket: p))
        }
        return pairs
    }
}
