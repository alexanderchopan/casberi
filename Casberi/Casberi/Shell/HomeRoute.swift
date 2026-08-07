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
    // `.shared` DELETED (multi-window, 2026-08-02) — this is per-window state
    // now, held by `SceneState`. The deletion is the enforcement: see that
    // file for why a "current window" accessor would be a bug, not a
    // convenience.

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
        /// The onboarding fork ("What should I start with?"), reachable as a
        /// real destination rather than only as a page inside the onboarding
        /// cover.
        ///
        /// It exists because leaving the demo lands HERE. The fork used to run
        /// before anyone had seen anything, which is what made it a decision
        /// asked too early; after a furnished demo the same three cards are an
        /// answer to a question the person now has. Landing in the catalog
        /// instead was considered and declined — §217's own ruling is that the
        /// catalog is "a wall you have to survey" and the fork is "a fork you
        /// answer in a second", and that reasoning got stronger, not weaker,
        /// as the catalog grew past sixty seats. The catalog stays one tap
        /// away on the fork itself.
        case startHere
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
    /// Mac's ⌘[ (2026-07-28) — the native back chevron's own move, exposed
    /// as a shortcut. No ⌘] twin: `path` is reset directly from several
    /// other files (a fresh landing after naming a counterparty, closing a
    /// handle setup screen, …) and popped by the NavigationStack's own
    /// binding on a native swipe-back, so there's no single point to
    /// capture an honest forward-history from — a fake or unreliable
    /// "forward" would be worse than none.
    @MainActor func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    @MainActor func pushBridge(_ dest: BridgeRouter.Destination?) {
        guard let dest else { return }
        path.append(.bridge(dest))
    }

    /// Push an offer's product page on top of wherever the stack sits.
    @MainActor func pushAppDetail(_ offerName: String) {
        path.append(.appDetail(offerName))
    }

    /// The connect FORM, raised over whatever the person was looking at (prd
    /// §218, 2026-07-25). Mounted once, on `MainSurface`'s stack, so a Connect
    /// tapped on a catalog tile, a peek preview, the Discover deck or a product
    /// page all behave identically — and so the form itself is never a second
    /// copy of anything: it's the bridge's own setup screen, rendered by the
    /// same `BridgeDestinationView` the pushed route uses.
    var connectForm: BridgeRouter.Destination?

    /// Where an offer's Connect goes: **it raises** (prd §219). Connecting is
    /// one act — paste a key, type a handle, pick a file — so it happens over
    /// the page that sold it to you, with no door to walk. Only the wallet
    /// room is pushed, because it navigates through this very stack and its
    /// own doors would open behind a sheet.
    @MainActor func openSetup(forOffer name: String) {
        guard let dest = BridgeRouter.destination(forOffer: name) else { return }
        if dest.raisedByConnect {
            connectForm = dest
        } else {
            path.append(.bridge(dest))
        }
    }

    /// Leave the connect sheet, wherever it was raised from. Called by a
    /// screen that navigates the stack BEHIND itself (Handle setup's "See in
    /// Feed"), which would otherwise move the world under a sheet still
    /// sitting on top of it.
    @MainActor func closeConnectForm() {
        connectForm = nil
    }

    /// An offer whose product page should open once the catalog lands — set
    /// by the empty feed's pile (a tile is a door to that app's page, not
    /// just to the shelf); AppsScreen consumes it on appear, after the
    /// `.apps` push above has mounted the stack.
    var openOffer: String?
    // Per-window now, so the init is reachable — the `private` here was
    // the singleton's own guard against a second instance, and a second
    // instance is exactly what a second window is.
    init() {}
}
