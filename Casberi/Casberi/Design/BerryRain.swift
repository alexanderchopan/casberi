import SwiftUI

/// Pull-to-refresh delight (user, 2026-07-14): the logo's berry circles
/// rain briefly over the surface while a refresh runs — the app's own mark
/// doing the work, sibling to the avatar door's spin (TopDoors.DoorSpin;
/// both ride ShellChrome.refreshPulse). Purely decorative: hit-testing off,
/// gone in under two seconds, skipped entirely under Reduce Motion.
struct BerryRain: View {
    /// ShellChrome.refreshPulse — each bump deals one shower.
    let trigger: Int
    /// A source's own brand hue (ShellChrome.refreshHue), read once per
    /// shower — a refresh inside that source's feed, or a moment that names
    /// one, rains in ITS color instead of the app's default berry blue
    /// (delight pass 2026-07-21: color still only ever carries identity).
    var hue: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pulse currently falling (0 = idle, nothing in the tree).
    @State private var shower = 0
    @State private var showerHue: Color?

    var body: some View {
        GeometryReader { geo in
            if shower > 0 {
                ForEach(Self.deal(seed: shower, hue: showerHue)) { drop in
                    FallingBerry(drop: drop, size: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            guard !reduceMotion, trigger > 0 else { return }
            shower = trigger
            showerHue = hue
            // Clear after the slowest drop lands — the tree goes back to empty.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.9))
                if shower == trigger { shower = 0 }
            }
        }
    }

    // MARK: - The deal

    /// The icon's berry blues, weighted to the bright end — the deep navies
    /// of the mark itself disappear on the dark page (first cut, 2026-07-14).
    private static let berry: [Color] = [
        Color.fixed("#0a84ff"), Color.fixed("#3f9fff"),
        Color.fixed("#0a84ff"), Color.fixed("#1266c4"),
    ]

    /// Deterministic per shower (a seeded LCG, never system randomness) so a
    /// mid-fall body re-evaluation deals the SAME drops — SwiftUI identity
    /// holds and nothing teleports. A source hue swaps in for the default
    /// berry blues, mixed full/dim the same way so the shape of the shower
    /// never changes, only its color.
    fileprivate static func deal(seed: Int, hue: Color? = nil) -> [Drop] {
        let palette = hue.map { [$0, $0.opacity(0.8), $0.opacity(0.6), $0.opacity(0.9)] } ?? berry
        var state = UInt64(bitPattern: Int64(seed)) &* 2654435761 | 1
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(UInt32.max)
        }
        return (0..<16).map { i in
            Drop(id: i,
                 x: CGFloat(next()),
                 diameter: 8 + CGFloat(next()) * 12,
                 delay: next() * 0.35,
                 duration: 0.9 + next() * 0.5,
                 sway: CGFloat(next() * 44 - 22),
                 color: palette[Int(next() * 4) % 4])
        }
    }
}

/// One dealt circle — where it starts, how it falls.
fileprivate struct Drop: Identifiable {
    let id: Int
    let x: CGFloat        // 0…1 across the width
    let diameter: CGFloat
    let delay: Double
    let duration: Double
    let sway: CGFloat     // horizontal drift over the whole fall, in points
    let color: Color
}

/// A drop's fall: eased in from above the top edge to past the bottom,
/// swaying a touch, fading as it goes.
fileprivate struct FallingBerry: View {
    let drop: Drop
    let size: CGSize
    @State private var fell = false

    var body: some View {
        Circle()
            .fill(drop.color)
            .frame(width: drop.diameter, height: drop.diameter)
            .opacity(fell ? 0 : 0.95)
            .offset(x: drop.x * size.width + (fell ? drop.sway : 0),
                    y: fell ? size.height + 30 : -30)
            .onAppear {
                withAnimation(.easeIn(duration: drop.duration).delay(drop.delay)) {
                    fell = true
                }
            }
    }
}
