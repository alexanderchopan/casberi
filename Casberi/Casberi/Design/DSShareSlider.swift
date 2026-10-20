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
    /// The filled part's ink. Move draws it white, so pink stays the
    /// values' and the signing verb's (prd §1442f).
    var tint: Color = DS.pickInk
    /// The thumb grows under the finger (§1438b).
    @State private var holding = false

    private static let notches = [0, 25, 50, 75, 100]

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let x = CGFloat(percent) / 100 * width
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fillFaint).frame(height: 6)
                // The quarters, under the fill: past the thumb they are gone.
                ForEach([25, 50, 75], id: \.self) { n in
                    Capsule()
                        .fill(DS.textTertiary)
                        .frame(width: 2, height: 12)
                        .offset(x: CGFloat(n) / 100 * width - 1)
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
                        var p = Int((value.location.x / width * 100).rounded())
                        p = min(max(p, 0), 100)
                        if let near = Self.notches.first(where: { abs($0 - p) <= 3 }) { p = near }
                        guard p != percent else { return }
                        // A quarter ticks; all of it lands.
                        if p == 100 { DSHaptic.snap() } else if Self.notches.contains(p) { DSHaptic.selection() }
                        withAnimation(.snappy(duration: 0.18)) { percent = p }
                    }
                    .onEnded { _ in holding = false }
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
