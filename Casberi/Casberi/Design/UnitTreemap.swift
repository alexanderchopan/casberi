import SwiftUI

/// The 4×3 unit-grid tiling every treemap in this app draws on (extracted
/// 2026-08-04 from `TopicMapHero`, which had owned it privately since
/// 2026-07-30, when the receipts screen became its second caller).
///
/// **Rank-ordered slots, not area-proportional cells — and the difference is
/// deliberate.** A true squarified treemap sizes each cell to its exact share,
/// which on a phone card means the tail arrives as slivers too thin to hold a
/// label, so the cells that need naming most are the ones that can't be named.
/// This tiles a FIXED table by rank instead — bigger slots first — and lets
/// `DS.wash(_:magnitude:)` carry the real magnitude in the fill. Area says
/// "roughly where in the order", opacity says "how much", and every cell keeps
/// a legible label. The `GenTagMap`/`MiniTreemap` heroes read the same way, so
/// the small map and the big one can never disagree about which is largest.
///
/// Six is the ceiling because the table ends there. A caller with more must
/// FOLD its tail into a final cell that says so ("9 more") rather than passing
/// seven and having the seventh silently vanish — a chart that drops rows
/// without saying it looks exactly like a chart that had nothing to drop.
struct UnitTreemap<Cell: View>: View {
    /// How many cells to tile, 0…6. Clamped rather than trapped: an empty map
    /// draws nothing, which is what a caller with no data should get.
    let count: Int
    var height: CGFloat = 200
    var gap: CGFloat = DS.Space.s2
    /// The cell face for slot `i`. Sizing, placement and the entrance are this
    /// view's; the fill, the words and the magnitude wash are the caller's.
    @ViewBuilder var cell: (Int) -> Cell

    /// (x, y, w, h) in grid units, per cell count. Sized so a 1- to 6-cell map
    /// always fills the board with no holes.
    static func frames(_ n: Int) -> [(Int, Int, Int, Int)] {
        switch n {
        case 0, 1: return [(0, 0, 4, 3)]
        case 2:    return [(0, 0, 2, 3), (2, 0, 2, 3)]
        case 3:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 4, 1)]
        case 4:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 2, 1)]
        case 5:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 1, 1), (3, 2, 1, 1)]
        default:   return [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 1, 1), (3, 1, 1, 2), (0, 2, 2, 1), (2, 2, 1, 1)]
        }
    }

    static var maxCells: Int { 6 }

    var body: some View {
        let shown = min(max(count, 0), Self.maxCells)
        let table = Self.frames(shown)
        GeometryReader { geo in
            let uw = (geo.size.width - gap * 3) / 4
            let uh = (height - gap * 2) / 3
            ZStack(alignment: .topLeading) {
                ForEach(0..<shown, id: \.self) { i in
                    let f = table[i]
                    cell(i)
                        .frame(width: uw * CGFloat(f.2) + gap * CGFloat(f.2 - 1),
                               height: uh * CGFloat(f.3) + gap * CGFloat(f.3 - 1),
                               alignment: .topLeading)
                        .offset(x: CGFloat(f.0) * (uw + gap), y: CGFloat(f.1) * (uh + gap))
                        // The map settles in cell by cell, biggest first
                        // (delight, 2026-08-03) — the entrance grammar the feed's
                        // rows already speak. Lives here rather than at each call
                        // site so the two maps can't drift on the beat.
                        .settleIn(delay: Double(i) * 0.06)
                }
            }
        }
        .frame(height: height)
    }
}
