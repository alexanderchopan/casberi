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
    static let agentWidth: CGFloat = 44

    /// The air between the bar's trailing edge and the first chip.
    ///
    /// `s2` rather than the strip's own `chipGap`: this gap separates two
    /// DIFFERENT objects (a glass pill and a run of marks) where the chip gap
    /// separates peers, and a seam that matches the pitch inside the run reads
    /// as the bar being the first chip — which it deliberately is not, since
    /// tapping it does not change the room.
    static let seam: CGFloat = DS.Space.s2

    /// What the strip must yield at its leading edge for the bar to stand in.
    ///
    /// Measured from the bar's own frame plus the seam, NOT from the cluster's
    /// outer padding: `RootShell` already pays `DS.Space.s4` on the cluster and
    /// the strip already pays the same on its own content, so those two cancel
    /// and counting either would inset the run twice.
    static var agentSeat: CGFloat { agentWidth + seam }
}
