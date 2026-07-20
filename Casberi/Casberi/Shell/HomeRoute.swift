import SwiftUI
import SwiftData
import Observation

/// The shell's own push target (extracted from the old HomeScreen.swift when
/// the Pinned board retired, 2026-07-20 — this class was never board-specific,
/// it's the whole app's shared navigation-route singleton). Shared so deep
/// links (`casberi://apps`) and the debug `-openSettings` hook can drive the
/// same push the toolbar buttons do.
@Observable
final class HomeRoute {
    static let shared = HomeRoute()
    enum Push: String, Identifiable { case apps, settings; var id: String { rawValue } }
    var push: Push?
    /// A bridge's own screen (wallet, tokens, a setup screen, …) — ONE shared
    /// push target for every entry point (Feed's Manage, Apps' tile capsules,
    /// a product page's Connect/Open), registered as a single
    /// `navigationDestination` at the shell (`MainSurface`). Before this,
    /// three screens each registered their own `navigationDestination(item:)`
    /// for the same `BridgeRouter.Destination` type at different depths of
    /// the one shared NavigationStack — undefined per Apple's "one
    /// destination provider per type per stack" rule, and the reported
    /// symptom (audit 2026-07-15) was a pushed bridge screen with no working
    /// back chevron.
    var bridgePush: BridgeRouter.Destination?
    /// A tag to open as its own view — set by an Ask answer that names a tag,
    /// so "what did I save about work" opens the Work view the treemap opens.
    var openTag: String?
    /// An offer whose product page should open once the catalog lands — set
    /// by the empty feed's pile (a tile is a door to that app's page, not
    /// just to the shelf); AppsScreen consumes it on appear, after the
    /// `.apps` push above has mounted the stack.
    var openOffer: String?
    private init() {}
}
