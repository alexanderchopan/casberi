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
/// `frames` is that claim's ONE table, and every 4×3 map in the app calls it —
/// `GenTagMap` (the wallet's holdings, the themes lede) delegates here rather
/// than spelling its own, since it spelled its own until 2026-08-07 and kept
/// the inverted six-cell layout for a day after this one was corrected, so the
/// two maps disagreed about rank 3 exactly as the paragraph above forbids.
/// `MiniTreemap` needs no table — one big cell beside up to three equal ones
/// can't invert a rank — but it draws `items[0]` largest for the same reason.
/// Guarded in `scripts/x402-selftest.sh`, which checks this table's areas at
/// every cell count AND fails on a second table appearing anywhere in the app.
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
    /// What slot `i` says under a cursor (2026-08-17) — Mac only, via the
    /// tooltip vocabulary, so it costs the phone nothing and adds no new hover
    /// mechanism to keep in step with `Design/MacDelight.swift`.
    ///
    /// **A treemap is the figure that most needs this and can least show it.**
    /// The tiling is rank-ordered rather than area-proportional (see `frames`),
    /// and the smallest cells are the ones whose label is clipped or dropped —
    /// so precisely the cells a person hovers to identify are the ones the map
    /// cannot name. The readout is the answer, and it is the caller's to write
    /// because only the caller knows whether its magnitude is requests, spend,
    /// posts or services.
    ///
    /// Optional, and absent by default: a map whose cells are already fully
    /// labelled gains nothing from restating them, and `dsTooltip` on every
    /// figure in the app would be the noise the vocabulary exists to prevent.
    var readout: ((Int) -> String?)? = nil

    /// (x, y, w, h) in grid units, per cell count. Sized so a 1- to 6-cell map
    /// always fills the board with no holes.
    static func frames(_ n: Int) -> [(Int, Int, Int, Int)] {
        switch n {
        case 0, 1: return [(0, 0, 4, 3)]
        case 2:    return [(0, 0, 2, 3), (2, 0, 2, 3)]
        case 3:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 4, 1)]
        case 4:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 2, 1)]
        case 5:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 1, 1), (3, 2, 1, 1)]
        // AREA MUST NEVER RISE WITH RANK (fixed 2026-08-06, user-reported:
        // "the treemap is a bit off"). The old six-cell table was
        // `(2,1,1,1), (3,1,1,2)` — rank 3 got ONE unit while ranks 4 and 5 got
        // TWO, so the third-biggest term drew visibly SMALLER than the fourth
        // and fifth. Reported against the X room's map, where "t.co · 97" sat
        // in a small tile beside "app · 63" in a tall one, which reads as the
        // map being wrong about its own numbers — and it was.
        //
        // Rank order is this map's ONLY claim (§300: it is deliberately not
        // area-proportional, because true squarified cells arrive as slivers
        // too thin to label). A layout that inverts two ranks breaks the one
        // thing it promises. Areas now run 4·2·2·2·1·1, non-increasing, and
        // still tile all twelve units with no holes — guarded in
        // `scripts/x402-selftest.sh`, which checks every cell count.
        default:   return [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 2, 1), (0, 2, 2, 1), (2, 2, 1, 1), (3, 2, 1, 1)]
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
                        .dsTooltipIfPresent(readout?(i))
                }
            }
        }
        .frame(height: height)
    }
}
