import Foundation
import SwiftData

/// The shared read both prediction-market bridges resolve into (2026-07-28,
/// added alongside Polymarket) — the SocialBridge move (one shape, several
/// networks) applied to odds instead of posts, so PredictionPulse and
/// PredictionMoments serve Kalshi AND Polymarket off ONE implementation
/// instead of two that quietly drift apart. Each bridge's own search/fetch
/// stays bridge-specific on purpose — Kalshi has no keyword search and no
/// usable price history (KalshiWatch's hardcoded sports series, KalshiMarket's
/// no-chart fallback), Polymarket has both — only the RESULT shape is shared.
enum PredictionSource: String {
    case kalshi = "Kalshi"
    case polymarket = "Polymarket"

    /// The lowercase sourceRef prefix ("kalshi:", "polymarket:") — matches
    /// the convention every watch-list bridge already uses (`tokens:`,
    /// `stocktwits:sym:`, …).
    var refPrefix: String { rawValue.lowercased() }
}

struct PredictionMarket {
    let source: PredictionSource
    /// The bridge-local id — a Kalshi ticker or a Polymarket condition id.
    let id: String
    let title: String
    let subtitle: String
    let url: String
    /// 0...1 — the live YES price, i.e. the market's odds.
    let probability: Double
    /// The market's own traded volume, in its exchange's units (Kalshi
    /// contracts, Polymarket dollars) — carried so the app can say what it
    /// doesn't know. 73% on a book that has traded $400 is not the same
    /// claim as 73% on $2M, and prd §83 ② already ruled that a price nobody
    /// is actually making is not a price. Never rendered as a number (the
    /// two exchanges' units aren't comparable) — only used to mark a book
    /// THIN, and to keep a noise market from firing a moment.
    let volume: Double
    /// True once the market has a final, settled answer. Never inferred from
    /// a probability near 0 or 1 (a 98% market is still live and could still
    /// flip) — each bridge reads its own explicit settlement signal, so a
    /// market that's merely lopsided never gets mistaken for a resolved one.
    let resolved: Bool
    /// Which side won — nil until `resolved` is true, and nil even then if a
    /// bridge's own settlement field is ambiguous. Never populated from a
    /// probability guess.
    let yesWon: Bool?
    let closeTime: Date?

    var sourceRef: String { "\(source.refPrefix):\(id)" }

    /// A book too thinly traded for its own number to mean much. The floor
    /// is per-exchange because the units differ (Kalshi counts CONTRACTS,
    /// Polymarket counts DOLLARS) — comparing them directly would be the
    /// decimals bug in a new coin. Deliberately generous: this marks "treat
    /// this number gently", not "this market is fake".
    var isThin: Bool {
        switch source {
        case .kalshi: volume < 1_000        // contracts traded
        case .polymarket: volume < 5_000    // USD of 24h volume
        }
    }

    /// Dispatches to the right bridge's re-fetch by reading the watched
    /// thing's own sourceRef/content — PredictionPulse's only call, so it
    /// never needs to know which bridge landed a given row.
    static func fetch(for thing: Thing) async -> PredictionMarket? {
        // Build 256: a detached Task runs LATER than it was created, so this
        // row can already be deleted by the time this line does (prd §297).
        guard thing.isLive else { return nil }
        switch thing.source {
        case PredictionSource.kalshi.rawValue:
            guard let route = KalshiMarket.route(from: thing.content) else { return nil }
            return await KalshiMarket.fetch(series: route.series, event: route.event)?.prediction
        case PredictionSource.polymarket.rawValue:
            guard let id = PolymarketBridge.conditionId(from: thing) else { return nil }
            return await PolymarketBridge.fetchMarket(conditionId: id)?.prediction
        default:
            return nil
        }
    }
}

/// Both bridges' `Resolved` rows already carry exactly these four fields —
/// this just names them once so the browse room's three orderings (2026-07-29,
/// prd §233) sort either venue without a duplicate switch statement per
/// screen. Not a persistence shape, not shared with `PredictionMarket` (that
/// one carries settlement state neither `Resolved` type has yet at browse
/// time) — purely the sort key.
protocol PredictionOdds {
    var probability: Double { get }
    var previousProbability: Double? { get }
    var volume: Double { get }
    var closeTime: Date? { get }
}

enum PredictionOrder: String, CaseIterable, Identifiable {
    case busiest = "Busiest"
    case closingSoon = "Closing soon"
    case biggestMove = "Biggest move"
    var id: String { rawValue }

    func sorted<Row: PredictionOdds>(_ rows: [Row]) -> [Row] {
        switch self {
        case .busiest:
            return rows.sorted { $0.volume > $1.volume }
        case .closingSoon:
            // No close time reads as "not closing soon" — sorts last rather
            // than first, so a market with an unknown close doesn't crowd
            // out the ones that actually are closing.
            return rows.sorted { ($0.closeTime ?? .distantFuture) < ($1.closeTime ?? .distantFuture) }
        case .biggestMove:
            return rows.sorted { moveSize($0) > moveSize($1) }
        }
    }

    private func moveSize<Row: PredictionOdds>(_ row: Row) -> Double {
        guard let previous = row.previousProbability else { return 0 }
        return abs(row.probability - previous)
    }
}
