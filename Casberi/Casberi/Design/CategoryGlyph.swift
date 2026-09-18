import SwiftUI

/// A category tile's glyph (prd §662) — an SF Symbol at a FROZEN size in a
/// fixed box, so the caption's seat under it never moves whichever symbol the
/// category wears (`laptopcomputer` is wide, `note.text` is tall) and never
/// moves with the text setting either: the strip's rhythm is fixed by design,
/// as the "All" chip says of the marks beside it. Frozen through `.font` on
/// purpose and not `dsGlyph`, which would grow it with the caption — the
/// design-ramp audit deliberately leaves a non-literal size alone.
///
/// Its ONE motion: a single bounce when the tile becomes the active one — the
/// beat the word chips lost when §359 removed their flip, because a spinning
/// word is not an identity moment; a glyph bouncing once is exactly what the
/// flip was for a mark. Nothing ambient (no breathe, no wiggle): the dock's
/// chrome never explains itself (§630). Leaving a chip bounces nothing —
/// `landTick` moves only on arrival — and under Reduce Motion it never moves.
/// Its own view so the tick invalidates this glyph and not the strip (the
/// 2026-09-09 lesson `ChipIdentityFlip` records).
///
/// Shared since 2026-09-17: the Accounts category strip is the dock's tiles
/// (`DSScopeTiles(strip: true)`), so it lands with the dock's one bounce too.
struct CategoryGlyph: View {
    let name: String
    let size: CGFloat
    let isActive: Bool
    @State private var landTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .frame(width: size + 6, height: size + 2)
            .symbolEffect(.bounce.up, value: landTick)
            .onChange(of: isActive) { _, on in
                if on, !reduceMotion { landTick += 1 }
            }
    }
}
