import SwiftUI
import UIKit

/// Pull-to-refresh delight (user, 2026-07-14): a brief shower over the surface
/// while a refresh runs, sibling to the avatar door's spin (TopDoors.DoorSpin;
/// both ride ShellChrome.refreshPulse). Purely decorative: hit-testing off,
/// gone in under two seconds, skipped entirely under Reduce Motion.
///
/// **WAS `BerryRain` UNTIL prd §655 (2026-09-08), and the old name was wrong
/// TWICE.** It rained no berries after §619 gave it tiles, and it never should
/// have claimed one anyway — **the app's mark is an OCTOPUS, not a berry**
/// (user, 2026-09-08, correcting a misreading this file's own doc had been
/// repeating: its deleted drop palette was commented "the icon's berry
/// blues"). `TileRain` says what falls, and rhymes with `TileDrop`, the
/// onboarding heap it was already documented as rhyming with. The hook is
/// `-rainPulse` now; it was `-berryPulse`, which is what to grep for in
/// anything written before today.
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
/// **THE BERRIES ARE GONE — every shower is tiles now (prd §655, 2026-09-08;
/// user: "there are a few places in the app like Wallet where the confetti is
/// literally confetti and not app tiles … any confetti should be app
/// tiles").** §619 kept one berry case alive: a pull or arrival scoped to a
/// single WATCHED WALLET rained in that wallet's own face colour (§171,
/// §501), on the reasoning that "which wallet" is an identity no tile
/// carries. That was true and it was not enough — one surface raining
/// confetti reads as confetti everywhere, and the wallet's stop is already
/// said at full strength by the crown's retint (§159), its rail seat and its
/// row. So a wallet moment rains WALLET tiles, and this file has one branch.
///
/// **An empty roster deals NOTHING, and that is the honest reading** rather
/// than a fallback: no source was asked, so no tile falls. It is reachable
/// only with nothing connected, where the door's spin and the pull's own
/// `DSHaptic.success()` still answer the gesture. Keeping a berry there would
/// be keeping the whole confetti path alive for the one screen that has
/// least to celebrate.
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
struct TileRain: View {
    /// ShellChrome.refreshPulse — each bump deals one shower. The pull is the
    /// rain's ONLY trigger (user ruling 2026-08-11): source moments, starred
    /// releases, connects, big imports, the away haul and the colour picker
    /// all used to deal it too, and together they had it firing constantly —
    /// each celebration keeps its toast/bloom/haptic, none of them rain.
    let trigger: Int
    /// The sources this shower stands for (ShellChrome.refreshRoster), read
    /// once per shower. Empty deals nothing — see the note above.
    var roster: [String] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Reduce Motion never reaches the view as a pour: the trigger it sees
        // stays 0, so no shower is ever dealt (and flipping the setting off
        // mid-session simply lets the next real bump through).
        TileRainLayer(pour: reduceMotion ? 0 : trigger, roster: roster)
            .allowsHitTesting(false)
    }

    // MARK: - The deal

    /// Tiles are each a claim, so the shower is sparse: eight across an
    /// iPhone. The count scales to width and is capped at 24 (Mac polish,
    /// 2026-07-28 — the same x-positions spread over a 3-4x wider window read
    /// as a shower thinning out exactly where there is most room for it), and
    /// floored at the tuned iPhone eight. A roster longer than this is cut at
    /// the count, never sampled, so the first tiles down are always the first
    /// sources swept; a roster shorter repeats, so one connected app still
    /// reads as a shower rather than as a single falling square.
    static func tileCount(for width: CGFloat) -> Int {
        min(24, max(8, Int((width / 390) * 8)))
    }

    /// Deterministic per shower (a seeded LCG, never system randomness) — two
    /// runs of the same pulse deal the same drops, so a recording or a screen
    /// sweep reproduces.
    fileprivate static func deal(seed: Int, roster: [String], count: Int) -> [Drop] {
        guard !roster.isEmpty else { return [] }
        var state = UInt64(bitPattern: Int64(seed)) &* 2654435761 | 1
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(UInt32.max)
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

/// One dealt drop — which source's tile it is, where it starts, how it falls.
fileprivate struct Drop: Identifiable {
    let id: Int
    let x: CGFloat        // 0…1 across the width
    let diameter: CGFloat
    let delay: Double
    let duration: Double
    let sway: CGFloat     // horizontal drift over the whole fall, in points
    let tile: String
    let spin: CGFloat     // radians of tilt over the whole fall
}

/// The shower's host — an empty, untouchable view that owns nothing between
/// pours and hands each one straight to the render server.
fileprivate struct TileRainLayer: UIViewRepresentable {
    /// The pulse to deal. 0 means "never pour" (idle, or Reduce Motion).
    let pour: Int
    let roster: [String]

    func makeUIView(context: Context) -> TileRainView { TileRainView() }

    func updateUIView(_ view: TileRainView, context: Context) {
        view.pour(pour, roster: roster)
    }
}

/// Deals one shower of `CALayer`s per pulse and forgets them when they land.
/// Nothing is retained between showers: idle, this is an empty view.
fileprivate final class TileRainView: UIView {
    /// The last pulse actually dealt — a pulse is poured exactly once, however
    /// many times SwiftUI re-runs `updateUIView` for the same value.
    private var dealt = 0
    /// A pulse that arrived before the view had a size (see `layoutSubviews`).
    private var waiting: (pulse: Int, roster: [String])?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        // A drop starts above the top edge and ends below the bottom one —
        // clipping is what keeps it from painting over neighbouring chrome.
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("TileRainView is code-only") }

    func pour(_ pulse: Int, roster: [String]) {
        guard pulse > 0, pulse != dealt else { return }
        dealt = pulse
        // A pulse can land before the first layout pass (the overlay mounts and
        // a refresh fires in the same beat) — hold it rather than dropping it
        // on the floor, since `dealt` has already claimed the pulse.
        guard bounds.width > 0, bounds.height > 0 else {
            waiting = (pulse, roster)
            return
        }
        deal(pulse, roster: roster)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let held = waiting, bounds.width > 0, bounds.height > 0 else { return }
        waiting = nil
        deal(held.pulse, roster: held.roster)
    }

    private func deal(_ pulse: Int, roster: [String]) {
        let drops = TileRain.deal(seed: pulse, roster: roster,
                                   count: TileRain.tileCount(for: bounds.width))
        // One shower, one pour, felt (2026-09-06, the haptic grammar) —
        // here rather than at the pulse's writers, so a bump that deals no
        // drops (no bounds yet) feels like nothing, which it is.
        //
        // **OFF THE LAYOUT PASS, and that is not a precaution.** `deal` is
        // reached from `layoutSubviews`, and `DSHaptic.pour()` mutates
        // `HapticBus`, an `@Observable` that `RootShell`'s own body reads
        // through `dsSensoryFeedback()` — so bumping it here invalidates the
        // shell from inside UIKit's layout of a view the shell contains,
        // which is the classic re-entrant "modifying state during view
        // update". A hop to the next run-loop turn puts the write after the
        // pass that produced it and changes nothing anyone can feel.
        if !drops.isEmpty { DispatchQueue.main.async { DSHaptic.pour() } }
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
            dot.contents = TileRain.face(for: drop.tile, scale: scale)
            dot.contentsGravity = .resizeAspectFill
            dot.contentsScale = scale
            dot.cornerRadius = DS.Radius.appIcon(drop.diameter)
            dot.cornerCurve = .continuous
            dot.masksToBounds = true
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
            fade.fromValue = 1
            fade.toValue = 0
            // A tile tumbles a little as it falls — a quarter turn at most,
            // either way, so it still reads as its app at the bottom.
            let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
            tilt.fromValue = -drop.spin
            tilt.toValue = drop.spin

            let group = CAAnimationGroup()
            group.animations = [fall, fade, tilt]
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
