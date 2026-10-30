import SwiftUI

/// **HOW MUCH OF WHAT YOU HAVE (prd §1438)** — Move's one slider, the quick
/// fill (user, 2026-10-19: "a button that lets user do 25% 50% or 100%";
/// "i like the slider"). A share of a holding, 0 to 100: the thumb snaps to
/// a quarter, a half, three quarters and all, and ticks as it lands on each.
///
/// It never stands in scroll content — a drag there beats the scroll view
/// on device (the CLAUDE.md gotcha) — so Move draws it in the foot, over the
/// keyboard. Adjustable by VoiceOver a quarter at a time.
struct DSShareSlider: View {
    @Binding var percent: Int
    var enabled = true
    /// The filled part's ink: the pick's pink, white thumb over it — the
    /// system slider's look (prd §1557, retiring §1442f's white fill: white on
    /// white hid the thumb, and the slider sets the amount, which is pink).
    var tint: Color = DS.pickInk
    /// The thumb grows under the finger (§1438b).
    @State private var holding = false
    /// Where the finger is, while it is down: the thumb and the fill sit
    /// UNDER it, never animated after it (prd §1557 — the snappy animation on
    /// every step is what made the thumb trail the finger). Nil at rest.
    @State private var dragX: CGFloat?

    private static let notches = [0, 25, 50, 75, 100]
    /// The resting thumb's radius: its travel is inset by it, so at 0 and
    /// 100 the thumb's EDGE meets the column's edge, as the system slider's
    /// does (prd §1616 item 9: centred on the edge, it hung half outside).
    private static let inset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let r = Self.inset
            let width = max(geo.size.width - 2 * r, 1)
            let rest = r + CGFloat(percent) / 100 * width
            // A quarter is a detent: within it the thumb sits on the quarter.
            let x: CGFloat = dragX.map { raw in
                let p = Int(((raw - r) / width * 100).rounded())
                if let near = Self.notches.first(where: { abs($0 - p) <= 3 }) {
                    return r + CGFloat(near) / 100 * width
                }
                return min(max(raw, r), r + width)
            } ?? rest
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fillFaint).frame(height: 6)
                // The quarters are dots inside the track; past the thumb the
                // fill covers them.
                ForEach([25, 50, 75], id: \.self) { n in
                    Circle()
                        .fill(DS.textTertiary)
                        .frame(width: 4, height: 4)
                        .offset(x: r + CGFloat(n) / 100 * width - 2)
                }
                Capsule().fill(enabled ? tint : DS.textTertiary).frame(width: x, height: 6)
                Circle()
                    .fill(enabled ? Color.white : DS.textTertiary)
                    .frame(width: holding ? 40 : 28, height: holding ? 40 : 28)
                    .shadow(color: .black.opacity(holding ? 0.55 : 0.4), radius: holding ? 8 : 4, y: 2)
                    .offset(x: x - (holding ? 20 : 14))
                    .animation(DS.Motion.standard, value: holding)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled else { return }
                        if !holding { holding = true }
                        dragX = value.location.x
                        var p = Int(((value.location.x - r) / width * 100).rounded())
                        p = min(max(p, 0), 100)
                        if let near = Self.notches.first(where: { abs($0 - p) <= 3 }) { p = near }
                        guard p != percent else { return }
                        // A quarter ticks; all of it lands.
                        if p == 100 { DSHaptic.snap() } else if Self.notches.contains(p) { DSHaptic.selection() }
                        percent = p
                    }
                    .onEnded { _ in
                        holding = false
                        // Let go: the thumb settles on the amount it set.
                        withAnimation(.snappy(duration: 0.18)) { dragX = nil }
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel(Text("How much of what you have"))
        .accessibilityValue(Text("\(percent) percent"))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: percent = min(100, (percent / 25 + 1) * 25)
            case .decrement: percent = max(0, ((percent + 24) / 25 - 1) * 25)
            @unknown default: break
            }
        }
    }
}
