import SwiftUI
import SwiftData
import UserNotifications

/// Cold-launch stopwatch. `start` is stamped the instant the first line of
/// `CasberiApp.init` runs — the earliest app-owned code — so RootShell can log
/// init→ready latency once per process for the perf pass (`scripts/perf.sh`).
/// One `Date` plus one `NSLog`; it never touches the launch path's stack depth
/// (see CLAUDE.md's 4MB main-stack note).
///
/// Not `#if DEBUG` anymore (2026-07-31). It was, and that meant every launch
/// number this project has ever recorded came from an unoptimized `-Onone`
/// build — while the thing anyone actually waits on is the Release binary on
/// TestFlight. The stopwatch itself is a `Date`; what was worth gating is the
/// LOG, so that's what `reports` gates, on an explicit `-launchTimer YES`
/// argument nobody passes in normal use. A shipped build stays silent, and the
/// shipping configuration finally becomes measurable instead of merely assumed
/// to be faster.
enum LaunchClock {
    static let start = Date()
    nonisolated(unsafe) static var didLog = false   // read/written on main only

    /// DEBUG always reports (perf.sh's existing contract, unchanged). Release
    /// reports only when asked.
    static var reports: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "launchTimer")
        #endif
    }
}

/// A Home Screen quick action (long-press the icon on iOS/iPadOS) IS a Mac
/// Dock menu under Catalyst — Apple surfaces the same `UIApplicationShortcutItem`
/// list both ways, so this one registration reaches both platforms (Mac
/// polish, 2026-07-28).
///
/// "New Thing" retired 2026-08-03 (user: "we don't really have that as a
/// feature anymore") — typed text in the composer never saves (things enter
/// only via capture paths, per the design law), so a shortcut promising a
/// blank "new thing" opened a composer with nothing it could actually do.
/// "Daily Brief" replaces it: reuses `RootShell`'s existing `"brief.request"`
/// foreground flag, the same shape as the widget's Control Center button's
/// `compose.request` — a flag in the app group, read and cleared on next
/// foreground, rather than opening the `casberi://brief` URL directly, since
/// a quick action can COLD-launch the app and `onOpenURL`'s routing isn't
/// guaranteed live yet at that instant.
///
/// **Registering an action lives here; HANDLING one does not** (2026-08-14,
/// user: "long press on the app icon for daily brief takes me to the all
/// source feed instead of showing me the daily brief"). This is a scene-based
/// app — every SwiftUI `App` is — so UIKit delivers a quick action to the
/// window scene delegate, never to `application(_:performActionFor:)`. See
/// `QuickActions.swift`, which owns both doors.
///
/// `UIResponder`, not `NSObject` (2026-07-31): `buildMenu(with:)` is declared
/// on `UIResponder`, and the app delegate is the last link in the responder
/// chain UIKit walks when it builds the menu bar — so the Mac menu surgery in
/// `MacMenuBar.swift` has nowhere else to live. Every other delegate callback
/// is unaffected; `UIResponder` is itself an `NSObject`.
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: QuickAction.dailyBrief,
                localizedTitle: "Daily Brief",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "sparkles"))
        ]
        return true
    }

    /// Installs `SceneDelegate` — the object UIKit hands quick actions to, and
    /// the whole fix for a "Daily Brief" that opened the app and did nothing
    /// (see `QuickActions.swift` for why the app-delegate callback that used to
    /// stand here could never fire).
    ///
    /// The `options.shortcutItem` read here IS the cold-launch half, not a
    /// duplicate of one: `SceneDelegate` deliberately does not implement
    /// `scene(_:willConnectTo:options:)`, because that method is where SwiftUI's
    /// own scene setup lives (see `QuickActions.swift`). Both callbacks receive
    /// the same `ConnectionOptions`, and this one is called by UIKit directly,
    /// so reading it here takes nothing over.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        QuickAction.receive(options.shortcutItem)
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    /// The pre-scene door. It does NOT fire in this app — UIKit routes to
    /// `SceneDelegate.windowScene(_:performActionFor:)` instead — and is kept
    /// only so a future scene-less configuration can't silently lose the
    /// action the way the scene-based one silently lost it for eleven days.
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        QuickAction.receive(shortcutItem)
        completionHandler(true)
    }
}

/// Casberi — one home for a person's things.
///
/// M0: project scaffold, token layer, glass tab shell + composer, demo corpus.
/// SwiftData stays on-device for M0; CloudKit sync joins in M1 (brief §11).
@main
struct CasberiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer

    init() {
        _ = LaunchClock.start   // stamp the earliest app-code moment
        // The store lives in the app group so the share extension writes to
        // the same corpus (S3: every capture surface routes here).
        // `containerWithFallback` degrades (CloudKit off, then in-memory)
        // rather than crash-looping if the on-disk store can't open — S0:
        // the app must always launch. `SharedStore.degradeReason` is non-nil
        // when that happened; RootShell flashes it once at first appearance.
        #if DEBUG
        container = LaunchPerf.time("containerWithFallback") { SharedStore.containerWithFallback() }
        #else
        container = SharedStore.containerWithFallback()
        #endif
        // Clear the CloudKit "attempt in flight" marker on the first proof
        // this launch survived setup — either CoreData's mirror event or a
        // clean background handoff. See `CloudSyncGuard`.
        CloudSyncGuard.begin()
        // The Data tray's honest read on whether sync is ACTUALLY working,
        // not just switched on — remembers the mirror's real last outcome
        // for the whole session, not just at launch. See `CloudSyncStatus`.
        CloudSyncStatus.begin()
        // The demo corpus seeds only in debug, never for a fresh user (real
        // users start empty — the empty states are the product too).
        if DemoState.seedsDemoData {
            DemoCorpus.seedIfNeeded(container.mainContext)
        }
        #if DEBUG
        // An explicit -fresh YES re-runs the first launch: onboarding shows.
        if DemoState.freshRequestedThisLaunch {
            UserDefaults.standard.removeObject(forKey: "onboarded")
        }
        #endif
        // Register the wallet background-refresh handler before launch
        // finishes (BGTaskScheduler's requirement). One call, no work — the
        // OS decides if it ever runs; scheduling happens when we background.
        WalletBackgroundRefresh.register()
        // Publish the container so the background task can sweep the corpus
        // for notifications (prd §306) with no view above it. Must be the SAME
        // container the UI runs on — see `SharedStore.live`.
        SharedStore.adopt(container)
        // The notification delegate has to be set before the app finishes
        // launching, or a tap that COLD-LAUNCHES the app is delivered before
        // anything is listening and the deep link is lost — the one case a
        // notification most needs to route correctly.
        UNUserNotificationCenter.current().delegate = NotifyDelegate.shared
    }

    /// Reads RootShell's per-window `chrome` back through `FocusedValues`
    /// (see `ShellChromeFocusedKey`) — commands live at the Scene level,
    /// outside the view hierarchy `chrome` is injected into.
    @FocusedValue(\.shellChrome) private var focusedChrome: ShellChrome?
    /// The frontmost window's navigation, source filter and pane selection
    /// (multi-window, 2026-08-02). A menu command fires from outside every
    /// window's view hierarchy, so it has to be TOLD which window it meant —
    /// the same argument `focusedChrome` above already makes. Before this,
    /// ⌘, ⌘[ ⌘1–⌘9 and Escape all drove process singletons, which with two
    /// windows open would have moved the wrong one.
    @FocusedValue(\.sceneState) private var focusedScene: SceneState?
    /// False when the platform can't open a second window — the New Window
    /// item disables itself rather than sitting there doing nothing.
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    /// The venue the frontmost window would land on `delta` steps along its
    /// room switcher, or nil if there is nowhere to go (prd §360, 2026-08-11).
    ///
    /// **One function answers both "what does this item do" and "is it live",
    /// which is why it returns the destination rather than a Bool.** Written as
    /// two expressions the action and the `.disabled` gate drift, and the shape
    /// that drift takes is an enabled menu item that does nothing — the honesty
    /// law's own first clause, broken in the menu bar where nobody looks.
    ///
    /// Gated on the switcher actually being ON SCREEN: its own floor
    /// (`CategoryFold.switcherFloor`, mirroring `MainSurface.categorySwitcher`)
    /// and `shellChromeClear`, since `roomControls` is mounted inside the
    /// NavigationStack precisely so a pushed room covers it.
    ///
    /// Clamped at both ends rather than wrapping — `ShellChrome.walkStep`'s
    /// ruling ("a walk that wrapped would silently jump a reader from the newest
    /// thing to the oldest"), and the same argument holds for rooms: ⌘⇧] off the
    /// end of Markets should stop, not reappear at the far side.
    private func venueNeighbour(_ delta: Int) -> String? {
        guard focusedChrome?.shellChromeClear == true,
              let source = focusedScene?.filter.source,
              let category = BridgeCatalog.category(forSource: source),
              let present = focusedChrome?.categoryVenues[category],
              present.count >= CategoryFold.switcherFloor else { return nil }
        // The order the switcher DRAWS, not the learned order it is handed —
        // ⌘⇧] must mean the mark to the right of the one lit up.
        let venues = CategoryFold.scopes(category: category, present: Set(present))
        guard let here = venues.firstIndex(of: source) else { return nil }
        let next = here + delta
        guard venues.indices.contains(next) else { return nil }
        return venues[next]
    }

    /// The wallet rail's slots in the order it draws them — "All", then each
    /// watched wallet — or empty when the rail isn't showing (prd §360).
    ///
    /// Positional against what is on screen, exactly as ⌘1–⌘9 is against
    /// `chipOrder`: ⌥3 must mean the third face you can SEE. The watch list is
    /// process-wide (`WalletStore.shared`, one list for every window) while the
    /// SCOPE is per-window (`ShellChrome.walletScope`) — so this reads the
    /// singleton and writes through `focusedChrome`, which is the same split
    /// `MainSurface` already makes.
    private var focusedWalletScopes: [WalletStore.WatchedAddress?] {
        guard focusedChrome?.shellChromeClear == true,
              let source = focusedScene?.filter.source else { return [] }
        let watched = WalletStore.shared.addresses
        guard WalletScopeRail.shows(source: source, watched: watched.count) else { return [] }
        return [nil] + watched.map { Optional($0) }
    }
    @Environment(\.openURL) private var openURL

    var body: some Scene {
        WindowGroup {
            RootShell()
                #if targetEnvironment(macCatalyst)
                // Mac window sizing (2026-07-28): with no explicit frame,
                // Catalyst launches the window at the iPhone's simulated
                // point size — tall and narrow, reading as a phone screen
                // in a Mac frame rather than an app that was actually sized
                // for a desktop window. `idealWidth`/`idealHeight` set a
                // Mac-appropriate default; `minWidth` keeps the CONTENT
                // column from collapsing under the composer field —
                // `PadLayout.readingMaxWidth` (700) is the app's own "one
                // comfortable reading column" number, so the floor is a
                // fraction under it rather than an arbitrary guess.
                // `minHeight` leaves room for a handful of feed rows above
                // the composer.
                //
                // The rail is ADDED to that floor rather than eaten out of
                // it (2026-08-01, when the source chips became a vertical
                // rail on Mac too — see `MainSurface.showsRail`). The 560
                // was always a statement about the content column; leaving
                // it alone once a fixed 88pt rail moved in would have
                // quietly redefined it as 472 and broken its own stated
                // intent. Stated as arithmetic so it tracks `railWidth`.
                // Both numbers come from `PadLayout` now (2026-08-02) — see
                // `macMinWindowSize` for the drift this cost. Note this
                // `minWidth` is a HINT here and nothing more: the floor that
                // actually binds is the `sizeRestrictions` call in RootShell,
                // which reads the same constant.
                .frame(
                    minWidth: PadLayout.macMinWindowSize.width,
                    idealWidth: PadLayout.macIdealWindowSize.width, maxWidth: .infinity,
                    minHeight: PadLayout.macMinWindowSize.height,
                    idealHeight: PadLayout.macIdealWindowSize.height, maxHeight: .infinity)
                #endif
        }
        .modelContainer(container)
        // Mac menu bar commands (2026-07-28, Mac polish): the app is
        // otherwise chromeless by design (no nav bar, no tab bar — the chip
        // strip owns the top of the screen), which reads as an unfinished
        // Mac app if the menu bar carries only the system defaults. These
        // mirror the FAB/composer, the pull-to-refresh gesture, and Settings
        // — the same three doors the phone already has, just also reachable
        // without a touchscreen.
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thing…") {
                    focusedChrome?.openComposer()
                }
                .keyboardShortcut("n", modifiers: .command)
                // A second window (multi-window, 2026-08-02). ⇧⌘N rather than
                // the Mac-conventional ⌘N because ⌘N was already spent on the
                // app's own primary verb, and moving it would retrain the one
                // shortcut people already use to capture something.
                //
                // `requestSceneSessionActivation` is the Catalyst door.
                // SwiftUI's `openWindow` addresses a WindowGroup by id, which
                // this app's group doesn't carry, and giving it one to serve a
                // menu item would change how the scene is restored.
                Button("New Window") {
                    UIApplication.shared.requestSceneSessionActivation(
                        nil, userActivity: nil, options: nil, errorHandler: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!supportsMultipleWindows)
            }
            // NOTE (verified live, 2026-07-28): Mac Catalyst's default
            // document-menu scaffolding (Duplicate/Move/Rename/Export As —
            // this app has no document model, so all four are dead
            // controls, the honesty rule) is NOT reachable through
            // SwiftUI's `CommandGroup` — `.saveItem`/`.importExport`
            // replacements compile but do nothing, confirmed by rebuilding
            // and checking the live File menu. UIKit synthesizes these
            // outside the placements Commands can address; removing them
            // needs a `UIApplicationDelegate.buildMenu(with:)` override
            // (`builder.remove(menu:)` on the relevant identifiers) — a
            // separate, untried change, not attempted here.
            // ⌘F, working since 2026-07-31. The 2026-07-28 note that used to
            // stand here was right about the cause and wrong about the fix
            // being impossible: Catalyst's synthesized Find submenu claimed
            // the key equivalent while staying permanently disabled (no
            // NSTextFinder-compatible text view exists in this app), so a
            // custom ⌘F silently never fired. `MacMenuBar.swift` removes that
            // menu in `buildMenu(with:)` — the only door, since no
            // `CommandGroup` placement can address it — which hands the
            // shortcut back to this item. Edit → Find is where a Mac user
            // looks for it, and it opens the same Find door the bar's
            // magnifier does (§215): field focused, nothing running until
            // they type.
            CommandGroup(after: .pasteboard) {
                Button("Find…") { focusedChrome?.openFind() }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    focusedChrome?.requestRefresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    focusedScene?.route.present(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // ⌘[ back (2026-07-28) — the native chevron's own pop. See
            // `HomeRoute.goBack()` for why there's no ⌘] forward.
            CommandGroup(after: .toolbar) {
                Button("Back") {
                    focusedScene?.route.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)
            }
            // ⌘1–⌘9 switch the source chip in that position (2026-07-28) —
            // Safari/Chrome's numbered-tab grammar. Position-based against
            // `focusedChrome?.chipOrder` (mirrored live from MainSurface's
            // own chip order, see `ShellChrome.chipOrder`), so a re-sort
            // never strands the shortcut on a chip that moved. "All" is
            // always first, so ⌘1 is always valid regardless of what's
            // connected; later numbers disable themselves once there's no
            // chip in that position rather than doing nothing silently.
            CommandGroup(after: .toolbar) {
                ForEach(1...9, id: \.self) { n in
                    let order = focusedChrome?.chipOrder ?? ["All"]
                    Button(n <= order.count ? "Switch to \(order[n - 1])" : "Switch to Chip \(n)") {
                        guard n <= order.count else { return }
                        let label = order[n - 1]
                        // A folded chip is a LABEL, not a source (prd §351,
                        // generalizing 2026-08-10, see `CategoryFold`) —
                        // resolved here the same way the strip's own tap
                        // resolves it. Written raw it would put a category
                        // name into `FeedFilter.source`, where no predicate
                        // matches it and the room is empty forever, while the
                        // chip lights up as if it worked. This stays
                        // positional against `chipOrder` on purpose: ⌘3 must
                        // mean the third chip you can SEE.
                        if CategoryFold.isCategory(label) {
                            let venues = focusedChrome?.categoryVenues[label] ?? []
                            guard let venue = CategoryFold.landing(category: label, present: venues)
                            else { return }
                            focusedScene?.filter.source = venue
                        } else {
                            focusedScene?.filter.source = label
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                    .disabled(n > order.count)
                }
            }
            // ⌘⇧[ / ⌘⇧] — one room left or right INSIDE a folded category
            // (prd §360, 2026-08-11). Safari's own adjacent-tab pair, and the
            // grammar ⌘1–⌘9 above already borrowed: those nine reach the chip
            // STRIP, which since §351 folds a whole category behind one chip,
            // so until now the seats behind that chip — every market venue,
            // every wallet room — had no key at all. The category is resolved
            // from wherever the window is standing, so the same two keys serve
            // whichever fold you are in and disable themselves everywhere else.
            //
            // Worth doing only NOW: before §357 the switcher was a
            // `safeAreaInset` on a screen carrying `.id(filter.source)`, so
            // every venue change destroyed and rebuilt the control. A key that
            // drives a control which tears itself down on each press is not a
            // shortcut anyone would keep using.
            CommandGroup(after: .toolbar) {
                Button(venueNeighbour(-1).map { "Previous Venue (\($0))" } ?? "Previous Venue") {
                    if let venue = venueNeighbour(-1) { focusedChrome?.sourceRequest = venue }
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(venueNeighbour(-1) == nil)
                Button(venueNeighbour(1).map { "Next Venue (\($0))" } ?? "Next Venue") {
                    if let venue = venueNeighbour(1) { focusedChrome?.sourceRequest = venue }
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(venueNeighbour(1) == nil)
            }
            // ⌥1–⌥6 — the wallet the room is scoped to (prd §360). "All" is
            // always ⌥1, then one key per watched wallet in rail order, so the
            // run is `WalletStore.watchLimit + 1` long and never grows.
            //
            // OPTION, not command: ⌘1–⌘9 is spent on the chip strip, and these
            // two runs must not be the same key doing different things
            // depending on which room you happen to be in. The cost is that
            // ⌥ + digit types a character (⌥1 is "¡"), which is exactly why
            // every item here disables unless the rail is drawn AND
            // `shellChromeClear` — a disabled item's key equivalent falls
            // through to the responder chain, so the composer keeps its keys.
            CommandGroup(after: .toolbar) {
                ForEach(1...(WalletStore.watchLimit + 1), id: \.self) { n in
                    let scopes = focusedWalletScopes
                    let slot = n <= scopes.count ? scopes[n - 1] : nil
                    Button(n <= scopes.count
                           ? (slot.map { "Scope to \($0.label.isEmpty ? $0.short : $0.label)" }
                              ?? "Scope to All Wallets")
                           : "Scope to Wallet \(n)") {
                        guard n <= scopes.count else { return }
                        // Animated, matching the rail's own tap — the lit face
                        // and the room's re-derivation ride one curve either way.
                        withAnimation(DS.Motion.standard) {
                            focusedChrome?.walletScope = scopes[n - 1]?.address
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .option)
                    .disabled(n > scopes.count)
                }
            }
            // The keyboard walk (2026-07-31) — the list half of list+detail,
            // arrow-walkable. See `KeyboardWalk.swift` for the feed's end of
            // it and `ShellChrome.canWalk` for the gate.
            //
            // These are MENU ITEMS holding bare keys rather than an
            // `onKeyPress` on a focusable view, and both halves of that matter.
            // A menu key equivalent is delivered with no focus to win first,
            // which is what makes ↑/↓ work while the pointer is anywhere. And
            // a DISABLED item's equivalent falls straight through to the
            // responder chain, while an enabled one does not — so `canWalk`
            // going false (the agent risen, the sources tray up, a pushed
            // Settings form full of text fields) genuinely hands ↑/↓/Return
            // back to whatever should have had them, rather than swallowing
            // them into a no-op. Everything here is Mac-only by that same
            // gate; there is no menu bar to hold it anywhere else.
            CommandGroup(after: .sidebar) {
                Button("Next Item") { focusedChrome?.walkStep(1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .disabled(!(focusedChrome?.canWalk ?? false))
                Button("Previous Item") { focusedChrome?.walkStep(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .disabled(!(focusedChrome?.canWalk ?? false))
                Button("Open Item") { focusedChrome?.walkOpen() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!(focusedChrome?.canWalk ?? false)
                              || focusedChrome?.walkSelected == nil)
                // Escape closes what the pane is showing, and is enabled ONLY
                // when the pane is actually showing something. That condition
                // is the whole design: Escape is the key UIKit uses to dismiss
                // a sheet, so an item that held it unconditionally would break
                // sheet dismissal everywhere in the app to serve a pane that
                // is usually empty.
                Button("Close Item") { focusedScene?.detail.clear() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(focusedScene?.detail.thing == nil)
                Divider()
                // ⌘0, continuing the ⌘1–⌘9 chip run below: nine numbered
                // sources, and the zero that opens the dock's first folder —
                // the four doors that are not a feed (§591 amendment). It named
                // "Your Sources" while that folder held a grid of every source;
                // the sources are the numbered chips themselves now, and what
                // is left behind the octopus is everything else.
                Button("Everything Else") { focusedChrome?.openSources() }
                    .keyboardShortcut("0", modifiers: .command)
                // THE AGENT GETS A KEY (prd §607). Everything else the dock
                // does has had one since §256 — the sources tray on ⌘0, the
                // nine chips, the walk, the pane — and the surface the whole
                // app is arranged around had none. §390 made the agent a HOLD
                // on the bar, a gesture a pointer does not have; the Mac's
                // only door has been `BarSecondaryMenu`'s right-click, which
                // is discoverable by accident and by nothing else.
                //
                // ⌘⇧A, not ⌘A (select-all) and not ⌘K (the Mac has no such
                // convention and ⌘K is a link in every editor). It goes in
                // this same group because raising the agent is the same class
                // of act as opening the tray: a door onto a surface, not an
                // edit.
                Button("Talk to Your Agents") { focusedChrome?.openComposer() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
            // Help → the real docs, Mac convention (2026-07-28) — replaces
            // the system's default "Casberi Help" item, which without this
            // opens nothing (no .help bookshelf is bundled).
            CommandGroup(replacing: .help) {
                Button("Casberi Help") {
                    openURL(URL(string: "https://casberi.app/docs.html")!)
                }
            }
        }
    }
}
