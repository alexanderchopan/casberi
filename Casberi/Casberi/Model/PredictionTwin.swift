import Foundation
import SwiftData

/// The same question, priced by the other exchange (2026-07-28).
///
/// `PredictionMoments.checkDisagreement` can only fire when a person has
/// ALREADY watched the same question on both Kalshi and Polymarket — which
/// nobody does by accident, so as built it was a moment waiting on a
/// coincidence. This is the designed path to it: watch a market on one
/// exchange, and the app goes and asks the other whether it prices the same
/// question. Two independent crowds disagreeing is the one thing neither
/// exchange's own app can ever show you.
///
/// Deliberately INFORMATIONAL, never a trade signal. The copy says two
/// crowds disagree; it never computes a spread, ranks which is "right", or
/// suggests acting on the gap — the same line every other surface in this
/// pair holds (see `PredictionMoments`' header).
@MainActor
enum PredictionTwin {

    struct Offer: Identifiable {
        let source: PredictionSource
        let title: String
        let probability: Double
        /// The already-watched market's own odds, for the comparison line.
        let counterpartProbability: Double
        /// Resolved rows carry what it takes to actually add the twin — a
        /// bridge-specific payload, since the two `add` paths take different
        /// shapes.
        let kalshi: KalshiWatch.Resolved?
        let polymarket: PolymarketBridge.Resolved?
        var id: String { "\(source.refPrefix):\(title)" }

        /// "Kalshi prices this at 61% — 7 points apart." Points, never
        /// percent (a probability gap is measured in points; see
        /// `TokenDeltaPill.points`), and the gap is stated, not judged.
        var line: String {
            let pct = Int((probability * 100).rounded())
            let gap = Int((abs(probability - counterpartProbability) * 100).rounded())
            if gap < 1 {
                return String(localized: "\(source.rawValue) prices this at \(pct)% too — the two agree.")
            }
            return String(localized: "\(source.rawValue) prices this at \(pct)% — \(gap) points apart.")
        }
    }

    /// The gap below which two exchanges are just quoting the same thing
    /// through different spreads. Under this, an offer still appears (the
    /// twin is worth watching either way) but the line says they agree.
    static let notableGap: Double = 0.05

    /// Looks for the just-watched market's twin on the OTHER exchange.
    /// Returns nil when there's no match, when the twin is already watched,
    /// or when the search comes back empty — a silent nil, since "no twin"
    /// is the common case and not worth a message.
    static func find(for market: PredictionMarket, context: ModelContext) async -> Offer? {
        // The query is the market's own question. Kalshi's search is a
        // title filter over its open book and Polymarket's is a real search
        // endpoint, so both take the same words and neither needs the
        // other's vocabulary.
        let query = market.title
        switch market.source {
        case .kalshi:
            let hits = await PolymarketBridge.search(query, limit: 5)
            guard let hit = hits.first(where: {
                PredictionMoments.titlesMatch(market.title, $0.title)
            }) else { return nil }
            guard !IngestSupport.hasSourceRef(context, source: "Polymarket",
                                              ref: "\(PolymarketBridge.refPrefix)\(hit.conditionId)")
            else { return nil }
            return Offer(source: .polymarket, title: hit.title, probability: hit.probability,
                         counterpartProbability: market.probability,
                         kalshi: nil, polymarket: hit)
        case .polymarket:
            let hits = await KalshiWatch.search(query, limit: 5)
            guard let hit = hits.first(where: {
                PredictionMoments.titlesMatch(market.title, $0.title)
            }) else { return nil }
            guard !IngestSupport.hasSourceRef(context, source: "Kalshi",
                                              ref: "kalshi:\(hit.ticker)")
            else { return nil }
            return Offer(source: .kalshi, title: hit.title, probability: hit.probability,
                         counterpartProbability: market.probability,
                         kalshi: hit, polymarket: nil)
        }
    }

    /// Watches the offered twin. Returns the landed thing, or nil when it
    /// was already there.
    @discardableResult
    static func accept(_ offer: Offer, context: ModelContext) -> Thing? {
        if let k = offer.kalshi { return KalshiWatch.add(k, context: context) }
        if let p = offer.polymarket { return PolymarketBridge.add(p, context: context) }
        return nil
    }
}
