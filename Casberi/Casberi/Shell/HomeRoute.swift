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
    var push: Push? {
        #if DEBUG
        didSet { NSLog("[Casberi] route.push: %@ -> %@", oldValue?.rawValue ?? "nil", push?.rawValue ?? "nil") }
        #endif
    }
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

    /// Open a shell door (Apps / Settings) so it PUSHES every time.
    ///
    /// `navigationDestination(item: $push)` does not reliably reset `push` to
    /// nil after an interactive swipe-back dismiss (a documented SwiftUI issue,
    /// worse under a `.zoom` transition — see the same drop class called out in
    /// `RootShell`'s onboarding-CTA and launch re-land notes). When `push` is
    /// left STALE at `.apps`, a bare `push = .apps` equals the current value and
    /// SwiftUI, seeing no change, does nothing — so the catalogue button reads
    /// as dead until some other path happens to clear the route. That is the
    /// reported "pressing the app catalogue button isn't working every time":
    /// it isn't a missed tap, it's a no-op set.
    ///
    /// Force a fresh nil→value edge instead: clear now, set one runloop later so
    /// SwiftUI always sees a real change and pushes. Harmless when `push` is
    /// already nil (the clear is a no-op; the deferred set still pushes), and
    /// the destination's zoom transition plays regardless of which runloop set
    /// it (the same deferred-set the `-openAppsDelay` hook already relies on).
    @MainActor func present(_ target: Push) {
        push = nil
        Task { @MainActor in push = target }
    }
}
