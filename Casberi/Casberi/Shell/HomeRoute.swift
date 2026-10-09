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
        /// APPS (prd §1111): one list of every app, connected or not, with
        /// the Added filter. §1050g folded Settings into it for four days;
        /// §1111 gave Settings its own door back.
        ///
        /// `.apps`, `.casberi` and `.addresses` are DOORS, never pushed since
        /// prd §1129: `present` and `toggle` land them as places in You
        /// (`HomeScope.Place`), so the screen changes and nothing slides.
        case apps
        /// SETTINGS: Casberi's own (theme, iCloud sync, the Data tray, What
        /// this app reaches, Diagnostics), the tray's Settings door and
        /// `casberi://settings` (prd §933, again since §1111).
        case casberi
        /// The Addresses directory, its own screen for the same reason (§933;
        /// it was Accounts' fourth section since §916's amendment).
        case addresses
        /// What this app reaches and what it reached — one pushed directory
        /// of the registry and the ledger (prd §967), so its category tiles
        /// can ride the seat's capsule like Accounts' and Addresses' (§960).
        /// It was two sheets under the Data tray.
        case reach
        case bridge(BridgeRouter.Destination)
        /// A tag's project view — the same screen the feed's Themes treemap
        /// opens. Pushed by an Ask answer's ProjectTile and the "open work"
        /// navigate intent, so a tag named from the composer lands where a
        /// treemap tap lands.
        case project(String)
        /// Walletbeat's full directory (prd §421).
        ///
        /// Its own node so the ROOM can reach it in one push. §234 already ruled that a
        /// browse belongs at the head of the room and "never by a setup screen —
        /// connecting an exchange is not browsing it"; this screen was reachable only
        /// through the connect screen, so reading the directory meant a trip into the
        /// catalog and a second tap. The connect screen keeps its own link, which is the
        /// naming step rather than a browse.
        case walletbeatDirectory
        /// L2BEAT's full directory (prd §428) — its own node for the same reason
        /// Walletbeat's has one: §234's ruling that a browse belongs at the head of the
        /// room, never behind the setup screen.
        case l2beatDirectory
        /// The address book — everyone you have dealt with (prd §461).
        ///
        /// Its own node rather than a `.bridge` destination, and that is the
        /// whole point of the split: a bridge destination is a SETUP screen for
        /// a catalog seat, and this is a room. `.bridge(.wallet)` still opens
        /// the roster — the five addresses the app reads — which is the only
        /// thing on that side of the line now.

        /// One page of Settings, drawn in the Accounts pane (prd §876). Only
        /// ever placed in `accountsPane`: on a layout with no pane the same
        /// rows raise their sheets, as they always have.
        case settingsPage(SettingsPage)
    }
    /// The pushed stack — the Mac's only, since prd §1132: on the phone and
    /// the iPad nothing pushes, and every step `place` takes rises in `sheet`.
    /// Emptying it means "back to the room", so it closes the sheet too: the
    /// fifteen doors that end by writing `path = []` (a landing after a
    /// connect, a deep link, a Spotlight hit) leave whatever is raised.
    var path: [Node] = [] {
        didSet { if path.isEmpty, sheet != nil { closeSheet() } }
    }

    /// **NOTHING PUSHES ON THE PHONE (prd §1132, user: "agree no pushes").**
    /// Places switch in place (§1129); anything you open to look at or act on
    /// rises here: an account page, the wallet's history, What this app
    /// reaches, a directory, a project. A step deeper from inside stacks in
    /// the sheet's own stack (`sheetPath`), the way Apple's sheets do. So the
    /// face is always the tray's door and never a back door. The connect form
    /// (§218) is this same sheet, rooted at `.connect`.
    var sheet: SheetRoot?

    /// The steps taken inside the sheet, under its root.
    var sheetPath: [Node] = []

    /// What the one sheet is rooted at.
    enum SheetRoot: Hashable, Identifiable {
        /// A connect form, with its own rule: a one-shot form leaves once its
        /// key lands (`ConnectFormSheet`).
        case connect(BridgeRouter.Destination)
        /// Any screen that used to push.
        case node(Node)
        var id: Self { self }
    }

    func closeSheet() {
        sheet = nil
        sheetPath = []
    }

    /// The You place on screen (prd §1129), written by `MainSurface` from the
    /// source it shows. Leaving Apps takes its pane with it, so the next
    /// visit opens on the list rather than on a page chosen last week.
    var shownPlace: HomeScope.Place? {
        didSet { if shownPlace != .apps { accountsPane = [] } }
    }

    /// A place asked for (or "All", Home, to leave one), handed to
    /// `MainSurface`, which owns the source switch, as `ShellChrome.sourceRequest`
    /// is. Read once and cleared.
    var placeRequest: String?

    /// The door that opens a place — the inverse of `place(_:)`.
    static func door(for place: HomeScope.Place) -> Node {
        switch place {
        case .apps: .apps
        case .addresses: .addresses
        case .settings: .casberi
        }
    }

    /// The place a door names, or nil for a screen that pushes.
    /// Whether a place rises as a sheet: the phone's one rule (§1208m).
    @MainActor static var risesAsSheet: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .phone
        #endif
    }

    static func place(_ door: Node) -> HomeScope.Place? {
        switch door {
        // The catalogue is no place since prd §1136 (Apps left You's tiles):
        // it rises as a sheet over Settings, so a swipe down is the way back
        // (prd §1142, user: "there is no way to get back").
        case .addresses: .addresses
        case .casberi: .settings
        default: nil
        }
    }

    /// **Accounts is two columns where the shell has a pane (prd §876).** The
    /// list keeps `PadLayout.listColumnWidth` and whatever a row opens — an
    /// account page, a setup page, a Settings page — is drawn beside it
    /// instead of being pushed over it, the way the feed's pane shows a thing.
    /// Its own small stack, because an account page can push onward inside
    /// itself and the seat's Back has to walk that first.
    var accountsPane: [Node] = []

    /// Written by `MainSurface` from its measured width — true whenever the
    /// shell draws a detail pane. Nothing else should derive the breakpoint.
    var accountsSplit = false

    /// True while pushes land in the Accounts pane rather than on `path`.
    var paneHostsPushes: Bool { accountsSplit && path.isEmpty && sheet == nil && shownPlace == .apps }

    /// The frame the person is actually looking at: the pane's top while it
    /// hosts pushes, else the stack's. `ConnectPushWatcher` asks this, so a
    /// finished connect form closes where it was drawn.
    var topNode: Node? {
        if paneHostsPushes && !accountsPane.isEmpty { return accountsPane.last }
        if let last = sheetPath.last { return last }
        if case .node(let root)? = sheet { return root }
        return path.last
    }

    /// Set only for the length of a call from the Accounts LIST, so a row
    /// REPLACES what the pane shows while a push from inside a page stacks.
    private var paneReplaces = false

    /// A row on the Accounts list opening something: its push replaces the
    /// pane's page. Everywhere else a push is a step deeper, as before.
    @MainActor func fromAccountsList(_ open: () -> Void) {
        paneReplaces = true
        open()
        paneReplaces = false
    }

    /// Every push goes through here, so the pane cannot be skipped by one
    /// caller that spelled `path.append` itself.
    @MainActor private func place(_ node: Node) {
        guard paneHostsPushes else { stack(node); return }
        if paneReplaces { accountsPane = [node] } else { accountsPane.append(node) }
    }

    /// A step deeper: the Mac pushes; everywhere else it rises, or stacks in
    /// the sheet already up (prd §1132).
    @MainActor private func stack(_ node: Node) {
        #if targetEnvironment(macCatalyst)
        path.append(node)
        #else
        if sheet == nil {
            sheetPath = []
            sheet = .node(node)
        } else {
            sheetPath.append(node)
        }
        #endif
    }

    /// Open a shell door (Apps / Settings) so it lands there fresh —
    /// replacing whatever was on the stack, not stacking a second door on
    /// top of one already there.

    ///
    /// A You place (Apps, Addresses, Settings) lands in place instead (prd
    /// §1129): the stack empties and the shell cuts to it.
    @MainActor func present(_ door: Node) {
        // ONE RULE ON THE PHONE (prd §1208m, user: "we decided 1 rule"):
        // Settings, Sources and Addresses rise as a sheet over the Feed, as
        // Markets, your notes and every app do; the Wallet alone stands
        // beside the Feed. iPad and the Mac keep their places.
        if let place = Self.place(door), !Self.risesAsSheet {
            path = []
            closeSheet()
            placeRequest = place.source
        } else {
            #if targetEnvironment(macCatalyst)
            path = [door]
            #else
            sheetPath = []
            sheet = .node(door)
            #endif
        }
    }

    /// The avatar's own door: press it once to land on `door`, press it again
    /// to leave (user, 2026-09-12 — "if you press your avatar again it closes
    /// that screen"). The door was Settings then and is Accounts since §796.
    ///
    /// The face is the one seat that survives INTO the screen it opens (it is
    /// hosted on `RootShell`'s layer, above the stack — see `DockDoors`), so
    /// while that screen is up the control is still under the thumb and the only
    /// honest reading of a second press is "put it back". A door that stays
    /// lit and does nothing is the dead control §83 forbids.
    ///
    /// Pops ONE frame rather than clearing the stack, so a door opened over
    /// something (Apps → Settings) returns to what was underneath — `present`
    /// having replaced the path means the top frame is the only one this can
    /// match anyway.
    @MainActor func toggle(_ door: Node) {
        if let place = Self.place(door), path.isEmpty, shownPlace == place {
            placeRequest = "All"
        } else if path.last == door {
            path.removeLast()
        } else {
            present(door)
        }
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
        // The pane's page is a step the person took, so Back closes it
        // before it leaves Accounts (prd §876).
        if paneHostsPushes, !accountsPane.isEmpty {
            accountsPane.removeLast()
            return
        }
        // A step inside the sheet first, then the sheet itself (prd §1132).
        if !sheetPath.isEmpty { sheetPath.removeLast(); return }
        if sheet != nil { closeSheet(); return }
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    @MainActor func pushBridge(_ dest: BridgeRouter.Destination?) {
        guard let dest else { return }
        place(.bridge(dest))
    }

    /// Push any node on top of wherever the stack sits — the general form of
    /// `pushBridge`, for a destination that is not one.
    @MainActor func push(_ node: Node) {
        place(node)
    }

    /// The connect FORM, raised over whatever the person was looking at (prd
    /// §218, 2026-07-25). Mounted once, on `MainSurface`'s stack, so a Connect
    /// tapped on a catalog tile, a peek preview, the Discover deck or a product
    /// page all behave identically — and so the form itself is never a second
    /// copy of anything: it's the bridge's own setup screen, rendered by the
    /// same `BridgeDestinationView` the pushed route uses.
    ///
    /// Since prd §1132 it is the one sheet rooted at `.connect`; this reads
    /// and writes that root so the form's callers keep their word.
    var connectForm: BridgeRouter.Destination? {
        get { if case .connect(let dest)? = sheet { dest } else { nil } }
        set {
            if let newValue {
                sheetPath = []
                sheet = .connect(newValue)
            } else if connectForm != nil {
                closeSheet()
            }
        }
    }

    /// Where an offer's Connect goes: **it raises** (prd §219). Connecting is
    /// one act — paste a key, type a handle, pick a file — so it happens over
    /// the page that sold it to you, with no door to walk. Only the wallet
    /// room is pushed, because it navigates through this very stack and its
    /// own doors would open behind a sheet.
    @MainActor func openSetup(forOffer name: String) {
        guard let dest = BridgeRouter.destination(forOffer: name) else { return }
        openAccount(dest)
    }

    /// An account page, by the same rule Connect takes (prd §1033): raised
    /// over where you stand, or pushed for the wallet room. The room's own
    /// door opens a CONNECTED seat's page (`destination(forID:)`), which for
    /// Peer and the pools is their own screen rather than the wallet manager
    /// their Connect leads to.
    @MainActor func openAccount(_ dest: BridgeRouter.Destination) {
        // A connect asked for from inside a sheet stacks in it rather than
        // raising a second sheet over the first, which SwiftUI drops.
        if dest.raisedByConnect, sheet == nil {
            connectForm = dest
        } else {
            place(.bridge(dest))
        }
    }

    /// Leave the connect sheet, wherever it was raised from. Called by a
    /// screen that navigates the stack BEHIND itself (Handle setup's "See in
    /// Feed"), which would otherwise move the world under a sheet still
    /// sitting on top of it.
    @MainActor func closeConnectForm() {
        // Whatever is raised, since §1132 made every account page a sheet:
        // the screen calling this is about to move the world behind it.
        closeSheet()
    }

    /// An offer whose product page should open once the catalog lands — set
    /// by the empty feed's pile (a tile is a door to that app's page, not
    /// just to the shelf); AppsScreen consumes it on appear, after the
    /// `.apps` push above has mounted the stack.
    var openOffer: String?

    /// Land Accounts on Connect — the rooms tray's one door to the catalog
    /// (prd §930; its Manage door is deleted, §958, because the screen's own
    /// switcher reaches Manage). Set beside `present(.apps)` and consumed by
    /// `AppsScreen` — on appear, and while it is already up, because the tray
    /// can be opened over Accounts and the door must still land.
    var openConnect = false

    /// A catalog CATEGORY the Apps screen should land filtered to — set by a
    /// door that named the category in the same gesture ("Set up an agent"),
    /// consumed by `AppsScreen` on appear, exactly as `openOffer` above is.
    ///
    /// It is the ONE exception to that screen's own ruling that the filter is
    /// never remembered across visits, and the exception is what makes it
    /// honest rather than an inconsistency: that ruling exists because
    /// arriving on a three-week-old filter "hides nine tenths of it with
    /// nothing on screen saying why". Here the thing on screen saying why is
    /// the link you just tapped, one gesture ago. Nothing is hidden without
    /// explanation, and the All chip is the first thing in the strip.
    var openCategory: String?
    // Per-window now, so the init is reachable — the `private` here was
    // the singleton's own guard against a second instance, and a second
    // instance is exactly what a second window is.
    init() {}
}

/// The Settings rows that open a page of their own (prd §876). On a layout
/// with a pane each is drawn there; without one, the row raises the sheet it
/// always did, and this enum is never read.
enum SettingsPage: String, Hashable {
    case data, notifications, diagnostics, language, dockOrder
}
