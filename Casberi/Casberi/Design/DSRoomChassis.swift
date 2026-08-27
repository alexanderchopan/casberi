import SwiftUI

/// THE ROOM CHASSIS — the geometry Wallet and Vibenet share (prd §491).
///
/// Both rooms are the same machine: one fixed box holding a figure, an account
/// rail under it, a scope switcher under that, then content. Both already share
/// the PARTS — `FaceScopeRail` draws the faces in both, `DSSectionSwitcher` the
/// chips — and until this file they shared none of the SPACING between them.
///
/// **That is why they drifted, and why measuring was the wrong fix.** Wallet
/// lays its chassis out as `List` sections with `listRowInsets`; Vibenet as a
/// `VStack` with padding, inheriting `stackedRoom`'s `s6` card separation. Two
/// hand-tuned stacks cannot stay equal — reported three times in one session
/// ("the toggle bar is in the wrong place", then "they are NOT the same"), and
/// each time the fix was another measurement rather than a shared number. A
/// room that has to be re-measured to match is a room that will drift again the
/// next time either side is touched.
///
/// So the numbers live here, once, and both call sites read them. Nothing about
/// how each room COMPOSES its chassis changes — Wallet keeps its sections and
/// Vibenet its stack, because those are load-bearing for other reasons — but
/// the distances between the three pieces can no longer disagree.
///
/// **What this deliberately does NOT own**: the figures themselves, the rail's
/// own internals, and the switcher's. Those are already one component each. It
/// owns exactly the gaps, which were the only thing with two owners.
enum DSRoomChassis {

    /// The fixed box every scope's figure draws into.
    ///
    /// FIXED, never fitted, and spelled rather than measured — a measured
    /// height settles the bar a frame LATE, which is the same walk arriving
    /// slower. The box holds the crown OR the scope's figure, never both
    /// stacked: Wallet's Positions scope opens "Deposited $61,000" in place of
    /// the wallet total, and a room that draws its crown AND a figure is a room
    /// whose bar sits a third of a screen lower than the one it copied.
    static let visualSlot: CGFloat = 210

    // **THE THREE GAPS WERE TIGHTENED ONE RUNG (prd §495, user: "should we
    // move the silouhette rail and the toggle rail higher on both vibenet and
    // wallet to let more of the lists show" → "just a tiny bit higher… so
    // maybe one more row of lists shows").**
    //
    // MEASURED FIRST, because the answer to "one more row" is a number: the
    // chrome above the first row is 535pt of an 874pt screen — 61% — and a
    // two-line event row is ~90pt. So a whole extra row costs ~85pt, and the
    // only place that much slack exists is `visualSlot`, which every scope's
    // drawing was just made to fill.
    //
    // What is FREE is the air: these three gaps plus the switcher's own
    // vertical padding come to ~22pt with nothing behind them. That is a
    // quarter of a row, and it reads as more than it measures because four
    // separate gaps close at once. The slot is deliberately untouched.
    //
    // Worth knowing when reading any screenshot of this: the 48pt demo banner
    // is not in a real install, so a shipping room already shows half a row
    // more than the demo does.

    /// Figure → account rail.
    static let railGap: CGFloat = DS.Space.s1

    /// Account rail → scope switcher.
    ///
    /// Tighter than `railGap` on purpose: the rail and the switcher are two
    /// controls that scope the same room, and they read as a pair rather than
    /// as two unrelated strips.
    ///
    /// It stays EQUAL to `railGap` rather than smaller: at `s1` the two are
    /// already as close as the ramp goes, and the pairing it exists to state
    /// is carried by both being the tightest gap on the page while
    /// `contentGap` below them is the widest.
    static let switcherGap: CGFloat = DS.Space.s1

    /// Scope switcher → the first thing it scopes.
    ///
    /// The widest of the three, and the only one that is a SEPARATION rather
    /// than a grouping: everything above it is chrome about the room, and
    /// everything below is the room.
    ///
    /// It keeps its rung while the two above drop one, so the separation it
    /// states gets STRONGER rather than weaker as the group tightens — which
    /// is the whole point of tightening a group rather than the page.
    static let contentGap: CGFloat = DS.Space.s2

    /// The page inset the chassis and its figures share.
    static let inset: CGFloat = DS.Space.s4
}
