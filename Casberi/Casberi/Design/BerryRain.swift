import SwiftUI
import UIKit

/// Pull-to-refresh delight (user, 2026-07-14): the logo's berry circles
/// rain briefly over the surface while a refresh runs — the app's own mark
/// doing the work, sibling to the avatar door's spin (TopDoors.DoorSpin;
/// both ride ShellChrome.refreshPulse). Purely decorative: hit-testing off,
/// gone in under two seconds, skipped entirely under Reduce Motion.
///
/// The fall runs on CORE ANIMATION, not SwiftUI (2026-07-28, user: "the rain
/// pour always lags on pages"). It was 16 SwiftUI views animating `.offset`
/// and `.opacity` — properties SwiftUI interpolates per frame on the MAIN
/// actor. The one moment this rain exists is the one moment the main actor is
/// busiest: a pull runs `BridgeRefresh.refreshAllConnected`, and every ingest
/// in this app is `@MainActor` (inserts and deletes on the main context, each
/// one re-emitting the feed's `@Query`). So the shower stuttered every single
/// time, by construction — the delight fired exactly when nothing could draw
/// it smoothly. Handed to the render server as `CAAnimation`s it is immune to
/// that: the drops keep falling at 120Hz while the main thread is blocked
/// solid, which is the whole reason CoreAnimation runs out of process.
struct BerryRain: View {
    /// ShellChrome.refreshPulse — each bump deals one shower.
    let trigger: Int
    /// A source's own brand hue (ShellChrome.refreshHue), read once per
    /// shower — a refresh inside that source's feed, or a moment that names
    /// one, rains in ITS color instead of the app's default berry blue
    /// (delight pass 2026-07-21: color still only ever carries identity).
    var hue: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Reduce Motion never reaches the view as a pour: the trigger it sees
        // stays 0, so no shower is ever dealt (and flipping the setting off
        // mid-session simply lets the next real bump through).
        BerryRainLayer(pour: reduceMotion ? 0 : trigger, hue: hue)
            .allowsHitTesting(false)
    }

    // MARK: - The deal

    /// The icon's berry blues, weighted to the bright end — the deep navies
    /// of the mark itself disappear on the dark page (first cut, 2026-07-14).
    private static let berry: [Color] = [
        Color.fixed("#0a84ff"), Color.fixed("#3f9fff"),
        Color.fixed("#0a84ff"), Color.fixed("#1266c4"),
    ]

    /// Deterministic per shower (a seeded LCG, never system randomness) — two
    /// runs of the same pulse deal the same drops, so a recording or a screen
    /// sweep reproduces. A source hue swaps in for the default berry blues,
    /// mixed full/dim the same way so the shape of the shower never changes,
    /// only its color.
    /// 16 was tuned against an iPhone's ~390pt width. Drop x-positions
    /// already scale to `bounds.width` at render time, so the same 16 drops
    /// spread across a wide Mac window (up to 3-4x that width) read as
    /// visibly sparser — the shower thinning out exactly where there's most
    /// room for it (Mac polish, 2026-07-28). `dropCount(for:)` scales the
    /// COUNT to match, floored at the original 16 (never thinner than the
    /// tuned iPhone shower) and capped at 48 (3x) so an ultra-wide display
    /// doesn't deal hundreds of drops.
    static func dropCount(for width: CGFloat) -> Int {
        min(48, max(16, Int((width / 390) * 16)))
    }

    fileprivate static func deal(seed: Int, hue: Color? = nil, count: Int = 16) -> [Drop] {
        let palette = hue.map { [$0, $0.opacity(0.8), $0.opacity(0.6), $0.opacity(0.9)] } ?? berry
        var state = UInt64(bitPattern: Int64(seed)) &* 2654435761 | 1
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(UInt32.max)
        }
        return (0..<count).map { i in
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

/// The shower's host — an empty, untouchable view that owns nothing between
/// pours and hands each one straight to the render server.
fileprivate struct BerryRainLayer: UIViewRepresentable {
    /// The pulse to deal. 0 means "never pour" (idle, or Reduce Motion).
    let pour: Int
    let hue: Color?

    func makeUIView(context: Context) -> BerryRainView { BerryRainView() }

    func updateUIView(_ view: BerryRainView, context: Context) {
        view.pour(pour, hue: hue)
    }
}

/// Deals one shower of `CALayer` circles per pulse and forgets them when they
/// land. Nothing is retained between showers: idle, this is an empty view.
fileprivate final class BerryRainView: UIView {
    /// The last pulse actually dealt — a pulse is poured exactly once, however
    /// many times SwiftUI re-runs `updateUIView` for the same value.
    private var dealt = 0
    /// A pulse that arrived before the view had a size (see `layoutSubviews`).
    private var waiting: (pulse: Int, hue: Color?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        // A drop starts above the top edge and ends below the bottom one —
        // clipping is what keeps it from painting over neighbouring chrome.
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("BerryRainView is code-only") }

    func pour(_ pulse: Int, hue: Color?) {
        guard pulse > 0, pulse != dealt else { return }
        dealt = pulse
        // A pulse can land before the first layout pass (the overlay mounts and
        // a refresh fires in the same beat) — hold it rather than dropping it
        // on the floor, since `dealt` has already claimed the pulse.
        guard bounds.width > 0, bounds.height > 0 else {
            waiting = (pulse, hue)
            return
        }
        deal(pulse, hue: hue)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let held = waiting, bounds.width > 0, bounds.height > 0 else { return }
        waiting = nil
        deal(held.pulse, hue: held.hue)
    }

    private func deal(_ pulse: Int, hue: Color?) {
        let drops = BerryRain.deal(seed: pulse, hue: hue, count: BerryRain.dropCount(for: bounds.width))
        let start = CACurrentMediaTime()
        var batch: [CALayer] = []
        var lands: Double = 0
        // No implicit animations on the model values below — every drop's
        // motion is the explicit group, and nothing else should tween.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for drop in drops {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: drop.diameter, height: drop.diameter)
            dot.cornerRadius = drop.diameter / 2
            dot.backgroundColor = UIColor(drop.color).cgColor
            let x = drop.x * bounds.width
            let from = CGPoint(x: x, y: -30)
            let to = CGPoint(x: x + drop.sway, y: bounds.height + 30)
            // The layer RESTS in its landed state — off the bottom edge, fully
            // faded. So when the animation is removed on completion there is
            // nothing to see and nothing to clean up urgently; `.backwards`
            // fill covers the delay before it begins, where the drop is still
            // above the top edge and clipped away regardless.
            dot.position = to
            dot.opacity = 0

            let fall = CABasicAnimation(keyPath: "position")
            fall.fromValue = NSValue(cgPoint: from)
            fall.toValue = NSValue(cgPoint: to)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.95
            fade.toValue = 0

            let group = CAAnimationGroup()
            group.animations = [fall, fade]
            group.duration = drop.duration
            group.beginTime = start + drop.delay
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .backwards
            dot.add(group, forKey: "pour")

            layer.addSublayer(dot)
            batch.append(dot)
            lands = max(lands, drop.delay + drop.duration)
        }
        CATransaction.commit()
        // Each shower reaps its OWN layers — a later pour can never be cleared
        // by an earlier one's timer, which is what the old SwiftUI version's
        // `if shower == trigger` check was guarding by hand.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(lands + 0.1))
            batch.forEach { $0.removeFromSuperlayer() }
        }
    }
}
