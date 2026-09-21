import Foundation
import CoreGraphics

/// The feed's day seam, felt (prd §866).
///
/// One soft tick as a day divider passes under the finger, so scrolling back
/// through the corpus has a texture: you feel the days go by instead of only
/// reading them. It is the counterpart to the floor's mark — both are facts
/// about WHERE YOU ARE in the corpus, said without a word or a new row.
///
/// **Two disciplines, and they are the whole feature.**
///
/// 1. **Finger down only.** A fling crosses six days in half a second and a
///    buzz per day would be a rattle, not a texture — so the tick rides
///    `dragging`, which is true only while the hand is actually on the glass
///    (`ScrollPhase.tracking`/`.interacting`). The deceleration after a fling
///    is silent, which is also the honest reading: once you let go, the days
///    passing are the phone's doing, not yours.
///
/// 2. **Never faster than a seam can mean anything.** A fast drag is still a
///    drag, so the phase gate alone does not bound the rate. `minGap` does,
///    and it does velocity's job without measuring velocity: two seams closer
///    together than this WERE crossed too fast to feel as two, so the second
///    is dropped rather than queued. During the deliberate read-scroll this
///    exists for, days are seconds apart and the gap never fires.
///
/// Deliberately NOT in `GestureGate` (prd §666), which is the app's one fact
/// about the hand: every flag there feeds `busy` and `HitchMeter`, and a flag
/// that does neither would dilute a type whose whole value is that `busy`
/// means one thing. This reads the same hand for one screen's purpose.
///
/// Nothing here is `@Observable` on purpose — see `GestureGate`, same reason:
/// these are written mid-gesture, from a scroll phase observer and a geometry
/// action, and a view that re-rendered on them would re-render exactly when
/// the feed must stay cheap (prd §661).
enum FeedSeam {
    /// Is the hand on the glass? Written by `minimizesChrome`'s phase
    /// observer, which already runs on every screen that scrolls.
    private(set) static var dragging = false

    /// Two seams closer than this were one motion, not two. See discipline 2.
    static let minGap: Duration = .milliseconds(300)

    private static var last: ContinuousClock.Instant?

    static func set(dragging on: Bool) {
        guard dragging != on else { return }
        dragging = on
        // A new drag starts with no debt: the gap bounds ticks WITHIN one
        // motion, and making the first seam of a fresh drag wait on the last
        // seam of the previous one would silently swallow it.
        if on { last = nil }
    }

    /// A day divider crossed the top of the viewport. Fires at most one tick.
    static func crossed() {
        guard dragging else { return }
        let now = ContinuousClock.now
        if let last, now - last < minGap { return }
        last = now
        DSHaptic.seam()
    }

    /// Which side of the seam line a divider was last definitively on, kept
    /// per divider. A plain class held by `@State` rather than a `@State`
    /// value: the identity never changes, so writing through it costs no
    /// render at all — and this is written during a scroll.
    final class Tracker {
        /// -1 above the line, 1 below, 0 = not yet placed.
        var side = 0
    }

    /// Half the dead band around the line, in points.
    ///
    /// A bare `minY < 0` test would flicker for a divider parked at the line —
    /// sub-point geometry jitter reads as a crossing every frame. Nothing
    /// inside ±`band` is a crossing, and the side is only updated when a
    /// divider is clearly on one, so a parked divider says nothing and a
    /// genuine crossing says it once.
    static let band: CGFloat = 8

    /// The side a divider's top edge is on, or 0 inside the dead band. Pure —
    /// this is the `onGeometryChange` value, so it runs per geometry change
    /// and must stay a comparison.
    static func side(ofTop y: CGFloat) -> Int {
        y < -band ? -1 : (y > band ? 1 : 0)
    }

    /// Fold one reading into a tracker, ticking on a real crossing.
    static func observe(side now: Int, in tracker: Tracker) {
        guard now != 0 else { return }
        let was = tracker.side
        tracker.side = now
        // `was == 0` is the divider's FIRST placement (it just mounted, or it
        // has only ever been seen inside the band): arriving on a side is not
        // crossing to it, and ticking there would fire for every divider the
        // list mounts as you scroll.
        guard was != 0, was != now else { return }
        crossed()
    }
}
