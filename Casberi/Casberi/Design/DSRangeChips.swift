import SwiftUI

/// **THE WINDOW PICKER, ONCE (prd §686).**
///
/// The segmented 7d / 30d / Watched track lived inside `WalletBalanceHeadline`
/// as a private property, which was fine while the crown was the only thing
/// that offered a window. The Activity chart offers the same three windows over
/// the same records, so the choice was to draw a second one or to lift this one
/// out. A control drawn twice drifts — that is the whole finding of §683, one
/// surface down.
///
/// It draws NOTHING under two ranges, and that is the rule rather than the
/// caller's manners: a lone chip is a control with no alternative, which §83
/// calls a dead control.
struct DSRangeChips: View {
    let ranges: [WalletRange]
    let range: WalletRange
    let onPick: (WalletRange) -> Void

    var body: some View {
        if ranges.count > 1 {
            HStack(spacing: DS.Space.s1) {
                ForEach(ranges, id: \.self) { r in
                    Button {
                        guard r != range else { return }
                        DSHaptic.tap()
                        onPick(r)
                    } label: {
                        // STOCKS' SEGMENTED BOX (2026-08-16, the Apple redraw) —
                        // the chips share one recessed track and the selected one
                        // is a raised tile inside it, rather than a lone capsule
                        // floating in space.
                        Text(r.chipLabel)
                            .dsText(.label12)
                            .fontWeight(r == range ? .semibold : .regular)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(r == range ? DS.textPrimary : DS.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            // Concentric with the track below (prd §412): the
                            // segment's corner is the track's minus the 3pt
                            // inset, so the gap around it stays even through the
                            // bend rather than swelling at each corner.
                            .background(r == range ? DS.fillStrong : .clear,
                                        in: RoundedRectangle(
                                            cornerRadius: DS.Radius.nested(
                                                parent: DS.Radius.card, inset: 3),
                                            style: .continuous))
                    }
                    .buttonStyle(PressSpring())
                }
            }
            .padding(3)
            .dsWell()
        }
    }
}
