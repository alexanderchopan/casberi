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

    /// One ordered stack of pushed screens. Replaces the old pair of sibling
    /// `navigationDestination(item:)` bindings — `push` for the Apps/Settings
    /// doors, `bridgePush` for everything else — which lived at the SAME
    /// depth of the one shared NavigationStack instead of nesting. Pushing a
    /// bridge setup screen while Apps was open silently dropped Apps out of
    /// the real stack, so the native back chevron on a connect screen
    /// (Coinbase, Kalshi, …) landed on the Feed instead of the Apps catalog
    /// it was opened from (reported 2026-07-22). An ordered array pushed via
    /// `navigationDestination(for:)` always nests relative to whatever is
    /// CURRENTLY on top, so Apps → Connect → Setup is genuinely two frames
    /// deep and back pops exactly one.
    ///
    /// Appending is never gated by value equality (unlike
    /// `navigationDestination(item:)`), so the old mint-stamp workaround for
    /// a "stale" door request (a re-request indistinguishable from the value
    /// already sitting in the route) is no longer needed — every append is a
    /// real array mutation SwiftUI has never seen before.
    enum Node: Hashable {
        case apps
        case settings
        case bridge(BridgeRouter.Destination)
        /// A catalog offer's product page, keyed by name (the catalog's own
        /// join key). Pushed through the same path as `.bridge` — not a
        /// plain `NavigationLink` — so a Connect tapped FROM the product
        /// page still nests correctly: a plain-link frame isn't tracked by
        /// this path, so appending to it while one is on top silently drops
        /// it, same failure class as the Apps/bridge sibling-binding bug
        /// this whole path replaced.
        case appDetail(String)
        /// A tag's project view — the same screen the feed's Themes treemap
        /// opens. Pushed by an Ask answer's ProjectTile and the "open work"
        /// navigate intent, so a tag named from the composer lands where a
        /// treemap tap lands.
        case project(String)
    }
    var path: [Node] = []

    /// Open a shell door (Apps / Settings) so it lands there fresh —
    /// replacing whatever was on the stack, not stacking a second door on
    /// top of one already there.
    @MainActor func present(_ door: Node) {
        path = [door]
    }

    /// Push a bridge's own screen (wallet, tokens, a setup screen, …) on top
    /// of wherever the stack currently sits — Home, the Apps catalog, or a
    /// product page all nest correctly. One shared entry point for every
    /// trigger (Feed's Manage, Apps' tile capsules, a product page's
    /// Connect/Open).
    @MainActor func pushBridge(_ dest: BridgeRouter.Destination?) {
        guard let dest else { return }
        path.append(.bridge(dest))
    }

    /// Push an offer's product page on top of wherever the stack sits.
    @MainActor func pushAppDetail(_ offerName: String) {
        path.append(.appDetail(offerName))
    }

    /// An offer whose product page should open once the catalog lands — set
    /// by the empty feed's pile (a tile is a door to that app's page, not
    /// just to the shelf); AppsScreen consumes it on appear, after the
    /// `.apps` push above has mounted the stack.
    var openOffer: String?
    private init() {}
}
