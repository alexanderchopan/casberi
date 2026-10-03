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

/// THE WATCHLIST'S DAY AS A HEAT MAP (prd §1081): the box's tiles.
///
/// The biggest move leads at double height, then the rest by size of move,
/// at most `cap` tiles (a 3×3 grid with the lead spanning two rows). A tile's
/// strength is its move against the biggest move on the board, so the board
/// always uses its whole range; a move that rounds to zero carries none (§83).
enum WatchHeat {
    struct Tile: Equatable {
        let id: String
        let symbol: String
        let change: Double
        /// 0…1, how strongly the tile is coloured.
        let strength: Double
        var up: Bool { change > 0 }
        var flat: Bool { abs(change) < 0.0005 }
    }

    static let cap = 8

    /// Where each tile sits in a unit box, by how many there are, so the
    /// board always fills the box (prd §1081): one fills it, two split it,
    /// three put the lead beside two stacked; from four the lead stands one
    /// third wide beside the next ones, full height until seven, when it
    /// gives the bottom row to the rest. The lead is always the biggest.
    static func frames(count: Int) -> [CGRect] {
        let third = 1.0 / 3.0
        switch count {
        case ..<1: return []
        case 1: return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        case 2: return [CGRect(x: 0, y: 0, width: 0.5, height: 1),
                        CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case 3: return [CGRect(x: 0, y: 0, width: 0.5, height: 1),
                        CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                        CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        case 4: return [CGRect(x: 0, y: 0, width: third, height: 1),
                        CGRect(x: third, y: 0, width: third, height: 0.5),
                        CGRect(x: 2 * third, y: 0, width: third, height: 0.5),
                        CGRect(x: third, y: 0.5, width: 2 * third, height: 0.5)]
        case 5: return [CGRect(x: 0, y: 0, width: third, height: 1),
                        CGRect(x: third, y: 0, width: third, height: 0.5),
                        CGRect(x: 2 * third, y: 0, width: third, height: 0.5),
                        CGRect(x: third, y: 0.5, width: third, height: 0.5),
                        CGRect(x: 2 * third, y: 0.5, width: third, height: 0.5)]
        case 6: return [CGRect(x: 0, y: 0, width: third, height: 1),
                        CGRect(x: third, y: 0, width: third, height: third),
                        CGRect(x: 2 * third, y: 0, width: third, height: third),
                        CGRect(x: third, y: third, width: third, height: third),
                        CGRect(x: 2 * third, y: third, width: third, height: third),
                        CGRect(x: third, y: 2 * third, width: 2 * third, height: third)]
        default:
            let n = min(count, cap)
            var out = [CGRect(x: 0, y: 0, width: third, height: 2 * third),
                       CGRect(x: third, y: 0, width: third, height: third),
                       CGRect(x: 2 * third, y: 0, width: third, height: third),
                       CGRect(x: third, y: third, width: third, height: third),
                       CGRect(x: 2 * third, y: third, width: third, height: third)]
            let rest = n - 5
            let w = 1.0 / Double(rest)
            for i in 0..<rest {
                out.append(CGRect(x: Double(i) * w, y: 2 * third, width: w, height: third))
            }
            return out
        }
    }

    static func tiles(_ moves: [(id: String, symbol: String, change: Double)]) -> [Tile] {
        let ordered = moves.sorted {
            abs($0.change) != abs($1.change) ? abs($0.change) > abs($1.change) : $0.id < $1.id
        }.prefix(cap)
        let widest = ordered.map { abs($0.change) }.max() ?? 0
        return ordered.map { move in
            let flat = abs(move.change) < 0.0005
            let strength = flat || widest <= 0 ? 0 : min(1, abs(move.change) / widest)
            return Tile(id: move.id, symbol: move.symbol, change: move.change, strength: strength)
        }
    }
}
