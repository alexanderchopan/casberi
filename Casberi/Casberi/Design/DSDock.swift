import SwiftUI

/// The dock's shared metrics (prd §591, 2026-09-03).
///
/// The source strip sits against the bottom edge now and the agent bar stands
/// in its leading corner — but they are two views on two layers, not one
/// object: the strip is a `.safeAreaInset` inside `MainSurface`'s
/// `NavigationStack`, and the bar is hosted on `RootShell`'s own ZStack so it
/// survives into Settings, a bridge form and every pushed room, which that
/// inset does not. Both need the same number and neither can read it off the
/// other, so it lives here.
///
/// **Spelled once because the failure is asymmetric and neither half is
/// visible from the other.** Too small and the leading source scrolls under
/// the bar and becomes a room you can see and cannot tap — which is the exact
/// objection that took the bar off the top of the sources panel on 2026-08-16.
/// Too large and the dock opens with a hole in it that reads as a missing
/// chip. A constant in each file would drift the moment either one moved.
enum DSDock {
    /// The bar's own drawn width at rest — `AgentBar` frames itself to 44pt
    /// when it is not expanded, and it hugs its contents rather than filling.
    /// Measured on the simulator at 43pt of visible glass; 46 is that frame
    /// plus the two points of soft edge `dsGlass` draws beyond it, because what
    /// this constant has to clear is the glass, not the frame.
    static let agentWidth: CGFloat = 46

    /// The air between the bar's trailing edge and the first chip.
    ///
    /// `s2` rather than the strip's own `chipGap`: this gap separates two
    /// DIFFERENT objects (a glass pill and a run of marks) where the chip gap
    /// separates peers, and a seam that matches the pitch inside the run reads
    /// as the bar being the first chip — which it deliberately is not, since
    /// tapping it does not change the room.
    static let seam: CGFloat = DS.Space.s2

    /// The cluster's own outer inset — `RootShell` pays `DS.Space.s4` on the
    /// horizontal padding of the floating cluster, so the bar's LEADING edge is
    /// this far from the window and its trailing edge is this plus its width.
    static let clusterInset: CGFloat = DS.Space.s4

    /// What the strip must yield at its leading edge for the bar to stand in.
    ///
    /// **The first cut counted the width and the seam and NOTHING ELSE, and it
    /// shipped an overlap — measured on the simulator at 9pt of the "All" chip
    /// sitting under the bar's glass.** The reasoning was that the cluster's
    /// `s4` and the strip's own `s4` cancel; they do not, because the strip's
    /// chips are inside a `ScrollView` whose leading padding is `contentLead`
    /// (the melt's ramp, 16pt) rather than `s4`. So the two insets never met
    /// and the run began 9pt to the LEFT of where the bar ends.
    ///
    /// Spelled from the window edge outward instead, which is the only frame of
    /// reference both sides actually share: where the cluster starts, how wide
    /// the bar is, then the seam.
    static var agentSeat: CGFloat { clusterInset + agentWidth + seam }

    /// The bar's own drawn HEIGHT at rest — the same 44pt square `AgentBar`
    /// frames itself to when it is not expanded.
    static let agentHeight: CGFloat = 44

    /// How far the bar sits off the bottom edge so its centre lands on the
    /// chips' centre.
    ///
    /// **The bar and the chips are the same distance off the bottom and are
    /// still not aligned, which is why this exists** (user, 2026-09-03: "the
    /// octopus and the category chips need to be aligned. right now octopus is
    /// lower"). Both wear the strip's bottom padding, but a chip is 56pt tall
    /// and the bar is 44 — so bottom-aligning them puts the bar's centre 6pt
    /// below the row it is supposed to be the first seat of. The gap is
    /// exactly half the height difference, and it CHANGES when the strip folds
    /// on scroll (the chip goes 56 → 48 and the strip's own bottom padding
    /// `s2` → `s1`), so a constant would be right at rest and wrong the moment
    /// anybody scrolled.
    ///
    /// Both halves of the sum are the strip's own numbers, restated here
    /// because `RootShell` hosts the bar and cannot see inside `SourceChips`.
    /// They are the one thing in this file that must be re-derived if the chip
    /// ramp moves; the drift guard in `dock-selftest.sh` pins them together.
    static func agentBottomInset(minimized: Bool) -> CGFloat {
        let chip: CGFloat = minimized ? 48 : 56
        let stripBottom = minimized ? DS.Space.s1 : DS.Space.s2
        return stripBottom + (chip - agentHeight) / 2
    }
}
