import SwiftUI
import SwiftData

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
/// polish, 2026-07-28). Reuses the exact "open the composer next foreground"
/// flag the widget's Control Center button already writes — RootShell's
/// existing foreground check (`compose.request` in the app group) picks it
/// up with no new consumer code.
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
                type: "com.casberi.app.newThing",
                localizedTitle: "New Thing",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle"))
        ]
        return true
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "com.casberi.app.newThing" {
            UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: "compose.request")
        }
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
                        focusedScene?.filter.source = order[n - 1]
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                    .disabled(n > order.count)
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
                // sources, and the zero that shows you all of them. The tray's
                // only other trigger is a 0.45s hold on the agent bar — a
                // gesture a mouse will never discover, since click-and-wait
                // isn't something anyone tries (see `BarSecondaryMenu`).
                Button("Your Sources") { focusedChrome?.openSources() }
                    .keyboardShortcut("0", modifiers: .command)
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
