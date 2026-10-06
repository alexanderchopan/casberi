import CoreGraphics
import Foundation

/// THE ONE LINE UNDER A WATCHED NAME (prd §1081).
///
/// A watchlist row says one thing beside its name, the thing most worth
/// knowing about it for you, in this order:
/// 1. an alert you set on it ("Alert at $45") — you asked to be told;
/// 2. what you hold of it ("You hold $2,336") — it is your money;
/// 3. how it has done since you started watching ("+41% since you
///    watched"), once the move is worth a word (1% or more);
/// 4. the market's facts: the symbol and its size ("SOL · $94.1B cap"),
///    or a stock's exchange.
/// Never two of them: the row is one line (prd §902).
///
/// Foundation-only and pure: the caller hands in strings already formatted
/// by the app's one money formatter, so this decides only which one.
enum WatchLine {
    enum Line: Equatable {
        case alert(String)
        case holding(String)
        case sinceWatched(Double)
        case facts(String)
    }

    /// Below this a since-you-watched move is noise (a fraction).
    static let sinceFloor = 0.01

    static func pick(alertTarget: String?, holding: String?,
                     sinceWatched: Double?, facts: String?) -> Line? {
        if let alertTarget { return .alert(alertTarget) }
        if let holding { return .holding(holding) }
        if let sinceWatched, abs(sinceWatched) >= sinceFloor { return .sinceWatched(sinceWatched) }
        if let facts, !facts.isEmpty { return .facts(facts) }
        return nil
    }

    /// The move since you watched, from the price then and now.
    static func since(anchor: Double?, price: Double?) -> Double? {
        guard let anchor, let price, anchor > 0, price > 0 else { return nil }
        return price / anchor - 1
    }
}
