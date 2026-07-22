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
    /// A shell door, plus a mint stamp that makes every request for it a value
    /// SwiftUI has never seen before.
    ///
    /// `navigationDestination(item:)` gates on VALUE EQUALITY, so a plain enum
    /// made every re-request of a door indistinguishable from the one already
    /// sitting in the route — and the route does go stale (SwiftUI does not
    /// reliably write `nil` back on every dismiss, worse under a `.zoom`
    /// transition). A stale `.apps` meant `push = .apps` equalled the current
    /// value, SwiftUI saw no change, and the catalogue door read as dead. The
    /// stamp is what the fix rests on: `.apps` MINTS a fresh value every time
    /// it is read, so every assignment is a real change and no stale route can
    /// swallow it.
    ///
    /// This replaced a clear-then-set-one-runloop-later dance that measurably
    /// made things WORSE (2026-07-22): setting `nil` first asks SwiftUI to
    /// dismiss, and the dismissal writes its own `nil` back into the binding
    /// AFTER the deferred set landed — clobbering it. Measured as
    /// `pushRendered: apps -> nil` with no return edge, which is precisely the
    /// reported "it presses but nothing opens". Never route a door through
    /// `nil` to force an edge; mint a new stamp instead.
    struct Push: Identifiable, Hashable {
        enum Door: String { case apps, settings }
        let door: Door
        private let stamp: Int
        var id: String { "\(door.rawValue)#\(stamp)" }

        @MainActor private static var minted = 0
        @MainActor private static func mint(_ door: Door) -> Push {
            minted += 1
            return Push(door: door, stamp: minted)
        }
        @MainActor static var apps: Push { mint(.apps) }
        @MainActor static var settings: Push { mint(.settings) }
        /// The same door, freshly stamped — for re-landing a request that was
        /// set before the stack could receive it.
        @MainActor var renewed: Push { Push.mint(door) }
    }
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

    /// Open a shell door (Apps / Settings) so it PUSHES every time.
    ///
    /// One assignment, no `nil` round-trip: the caller's `.apps` / `.settings`
    /// is already freshly stamped (see `Push`), so this is always a change
    /// SwiftUI acts on — whatever stale value the route was holding.
    @MainActor func present(_ target: Push) {
        push = target
    }
}
