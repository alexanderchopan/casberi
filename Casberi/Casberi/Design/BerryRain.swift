import SwiftUI
import UIKit

/// Pull-to-refresh delight (user, 2026-07-14): a brief shower over the surface
/// while a refresh runs, sibling to the avatar door's spin (TopDoors.DoorSpin;
/// both ride ShellChrome.refreshPulse). Purely decorative: hit-testing off,
/// gone in under two seconds, skipped entirely under Reduce Motion.
///
/// **THE DROPS ARE THE APPS THE PULL IS ASKING (prd §619, 2026-09-05 — user:
/// "the rain is trite … what if it was little apps instead").** The berries
/// were confetti: sixteen circles that said "something happened" and nothing
/// else. What falls now is the ROSTER — one tile per source this pull is
/// refreshing, in the order the sweep runs them (`ShellChrome.refreshRoster`,
/// set by the pull itself from `BridgeRefresh.roster`). On All that is every
/// connected app; inside a source's room it is that app alone; inside a
/// folded category it is the category's connected members. So the shower is
/// a fact a toast cannot state — WHO was asked — and a person who has three
/// apps connected sees three tiles, not a fixed sixteen of anything. A
/// roster shorter than the shower repeats its tiles so the fall still reads
/// as a shower (one tile falling once reads as a bug); a roster longer than
/// it is cut, never sampled, so the first tiles down are always the first
/// sources swept. Tiles rhyme deliberately with the onboarding heap
/// (`TileDrop`) and the empty feed's pile: the app's tiles fall when there is
/// nothing yet, and the same tiles fall on every refresh after.
///
/// **The berries survive for ONE case**: a pull or arrival scoped to a single
/// WATCHED WALLET rains in that wallet's own face colour (prd §171, §501),
/// because "which wallet" is an identity no tile carries — a Wallet tile
/// would say less than the colour does. An empty roster with a hue is that
/// case; an empty roster with no hue is the default berry blue, which is
/// what a headless pulse with no store to read still deals.
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
/// solid, which is the whole reason CoreAnimation runs out of process. A tile
/// is the same layer with the brand asset as its `contents` and one extra
/// rotation track — the render server does not care what it is falling.
struct BerryRain: View {
    /// ShellChrome.refreshPulse — each bump deals one shower. The pull is the
    /// rain's ONLY trigger (user ruling 2026-08-11): source moments, starred
    /// releases, connects, big imports, the away haul and the colour picker
    /// all used to deal it too, and together they had it firing constantly —
    /// each celebration keeps its toast/bloom/haptic, none of them rain.
    let trigger: Int
    /// A source's own brand hue (ShellChrome.refreshHue), read once per
    /// shower — the berries' colour for the wallet-scoped case above. Ignored
    /// when a roster is present: a tile carries its own brand.
    var hue: Color? = nil
    /// The sources this shower stands for (ShellChrome.refreshRoster), read
    /// once per shower. Empty deals berries.
    var roster: [String] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Reduce Motion never reaches the view as a pour: the trigger it sees
        // stays 0, so no shower is ever dealt (and flipping the setting off
        // mid-session simply lets the next real bump through).
        BerryRainLayer(pour: reduceMotion ? 0 : trigger, hue: hue, roster: roster)
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

    /// Tiles are bigger than berries and each one is a claim, so fewer fall:
    /// eight across an iPhone (the same scaling to width, capped at 24). A
    /// roster longer than this is cut at the count; shorter repeats.
    static func tileCount(for width: CGFloat) -> Int {
        min(24, max(8, Int((width / 390) * 8)))
    }

    fileprivate static func deal(seed: Int, hue: Color? = nil, roster: [String] = [],
                                 count: Int = 16) -> [Drop] {
        let palette = hue.map { [$0, $0.opacity(0.8), $0.opacity(0.6), $0.opacity(0.9)] } ?? berry
        var state = UInt64(bitPattern: Int64(seed)) &* 2654435761 | 1
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(UInt32.max)
        }
        if roster.isEmpty {
            return (0..<count).map { i in
                Drop(id: i,
                     x: CGFloat(next()),
                     diameter: 8 + CGFloat(next()) * 12,
                     delay: next() * 0.35,
                     duration: 0.9 + next() * 0.5,
                     sway: CGFloat(next() * 44 - 22),
                     color: palette[Int(next() * 4) % 4],
                     tile: nil, spin: 0)
            }
        }
        // Tiles fall in ROSTER ORDER — the first source swept is the first
        // tile down — so the delay is the tile's rank plus a little jitter,
        // not a free draw. The rank spacing spans the same 0.35s the berries
        // used, whatever the count, so the shower's length never changes.
        let step = 0.35 / Double(max(count - 1, 1))
        return (0..<count).map { i in
            Drop(id: i,
                 x: 0.06 + CGFloat(next()) * 0.88,   // a tile has width; keep it on the page
                 diameter: 24 + CGFloat(next()) * 8,
                 delay: Double(i) * step + next() * 0.06,
                 duration: 1.0 + next() * 0.4,
                 sway: CGFloat(next() * 36 - 18),
                 color: .clear,
                 tile: roster[i % roster.count],
                 spin: CGFloat(next() * 0.5 - 0.25))
        }
    }

    // MARK: - Tile faces

    /// One face per source, rendered once per process — the brand asset's own
    /// bitmap when the catalog has one, else `BridgeIcon`'s glyph fallback
    /// through `ImageRenderer` at a fixed 32pt. Sized by the layer, not the
    /// bitmap, so a varying `diameter` never re-renders. `TileDrop` keeps its
    /// own copy of this for the onboarding heap; the two are ten lines each
    /// and the heap is another surface's file.
    @MainActor private static var faces: [String: CGImage] = [:]

    @MainActor fileprivate static func face(for name: String, scale: CGFloat) -> CGImage? {
        if let hit = faces[name] { return hit }
        let icon = BridgeIcon(name: name, size: 32)
        let image: CGImage?
        if let asset = UIImage(named: icon.assetName)?.cgImage {
            image = asset
        } else {
            let renderer = ImageRenderer(content: icon)
            renderer.scale = scale
            image = renderer.uiImage?.cgImage
        }
        faces[name] = image
        return image
    }
}

// `ConnectRain` (the app's own GLYPH raining as its connection lands,
// 2026-08-04) lived here until 2026-08-11 — retired with every other
// non-pull shower under the same user ruling; `.connectBloom` alone carries
// the connect payoff now.

/// One dealt drop — where it starts, how it falls. A berry when `tile` is
/// nil; a source's tile otherwise.
fileprivate struct Drop: Identifiable {
    let id: Int
    let x: CGFloat        // 0…1 across the width
    let diameter: CGFloat
    let delay: Double
    let duration: Double
    let sway: CGFloat     // horizontal drift over the whole fall, in points
    let color: Color
    let tile: String?
    let spin: CGFloat     // radians of tilt over the whole fall (tiles only)
}

/// The shower's host — an empty, untouchable view that owns nothing between
/// pours and hands each one straight to the render server.
fileprivate struct BerryRainLayer: UIViewRepresentable {
    /// The pulse to deal. 0 means "never pour" (idle, or Reduce Motion).
    let pour: Int
    let hue: Color?
    let roster: [String]

    func makeUIView(context: Context) -> BerryRainView { BerryRainView() }

    func updateUIView(_ view: BerryRainView, context: Context) {
        view.pour(pour, hue: hue, roster: roster)
    }
}

/// Deals one shower of `CALayer`s per pulse and forgets them when they land.
/// Nothing is retained between showers: idle, this is an empty view.
fileprivate final class BerryRainView: UIView {
    /// The last pulse actually dealt — a pulse is poured exactly once, however
    /// many times SwiftUI re-runs `updateUIView` for the same value.
    private var dealt = 0
    /// A pulse that arrived before the view had a size (see `layoutSubviews`).
    private var waiting: (pulse: Int, hue: Color?, roster: [String])?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        // A drop starts above the top edge and ends below the bottom one —
        // clipping is what keeps it from painting over neighbouring chrome.
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("BerryRainView is code-only") }

    func pour(_ pulse: Int, hue: Color?, roster: [String]) {
        guard pulse > 0, pulse != dealt else { return }
        dealt = pulse
        // A pulse can land before the first layout pass (the overlay mounts and
        // a refresh fires in the same beat) — hold it rather than dropping it
        // on the floor, since `dealt` has already claimed the pulse.
        guard bounds.width > 0, bounds.height > 0 else {
            waiting = (pulse, hue, roster)
            return
        }
        deal(pulse, hue: hue, roster: roster)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let held = waiting, bounds.width > 0, bounds.height > 0 else { return }
        waiting = nil
        deal(held.pulse, hue: held.hue, roster: held.roster)
    }

    private func deal(_ pulse: Int, hue: Color?, roster: [String]) {
        let count = roster.isEmpty ? BerryRain.dropCount(for: bounds.width)
                                   : BerryRain.tileCount(for: bounds.width)
        let drops = BerryRain.deal(seed: pulse, hue: hue, roster: roster, count: count)
        // One shower, one pour, felt (2026-09-06, the haptic grammar) —
        // here rather than at the pulse's writers, so a bump that deals no
        // drops (no bounds yet) feels like nothing, which it is.
        if !drops.isEmpty { DSHaptic.pour() }
        let start = CACurrentMediaTime()
        let scale = traitCollection.displayScale
        var batch: [CALayer] = []
        var lands: Double = 0
        // No implicit animations on the model values below — every drop's
        // motion is the explicit group, and nothing else should tween.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for drop in drops {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0,
                                width: drop.diameter, height: drop.diameter)
            if let tile = drop.tile {
                dot.contents = BerryRain.face(for: tile, scale: scale)
                dot.contentsGravity = .resizeAspectFill
                dot.contentsScale = scale
                dot.cornerRadius = DS.Radius.appIcon(drop.diameter)
                dot.cornerCurve = .continuous
                dot.masksToBounds = true
            } else {
                dot.cornerRadius = drop.diameter / 2
                dot.backgroundColor = UIColor(drop.color).cgColor
            }
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
            fade.fromValue = drop.tile == nil ? 0.95 : 1
            fade.toValue = 0
            var tracks: [CAAnimation] = [fall, fade]
            if drop.tile != nil {
                // A tile tumbles a little as it falls — a quarter turn at
                // most, either way, so it still reads as its app at the
                // bottom. Berries are round and have nothing to tumble.
                let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
                tilt.fromValue = -drop.spin
                tilt.toValue = drop.spin
                tracks.append(tilt)
            }

            let group = CAAnimationGroup()
            group.animations = tracks
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
