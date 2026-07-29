import SwiftUI
import SwiftData

#if DEBUG
/// Cold-launch stopwatch (DEBUG only). `start` is stamped the instant the first
/// line of `CasberiApp.init` runs — the earliest app-owned code — so RootShell
/// can log init→ready latency once per process for the perf pass
/// (`scripts/perf.sh`). One `Date` plus one `NSLog`; it never touches the
/// launch path's stack depth (see CLAUDE.md's 4MB main-stack note).
enum LaunchClock {
    static let start = Date()
    nonisolated(unsafe) static var didLog = false   // read/written on main only
}
#endif

/// Casberi — one home for a person's things.
///
/// M0: project scaffold, token layer, glass tab shell + composer, demo corpus.
/// SwiftData stays on-device for M0; CloudKit sync joins in M1 (brief §11).
@main
struct CasberiApp: App {
    let container: ModelContainer

    init() {
        #if DEBUG
        _ = LaunchClock.start   // stamp the earliest app-code moment
        #endif
        // The store lives in the app group so the share extension writes to
        // the same corpus (S3: every capture surface routes here).
        // `containerWithFallback` degrades (CloudKit off, then in-memory)
        // rather than crash-looping if the on-disk store can't open — S0:
        // the app must always launch. `SharedStore.degradeReason` is non-nil
        // when that happened; RootShell flashes it once at first appearance.
        container = SharedStore.containerWithFallback()
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

    var body: some Scene {
        WindowGroup {
            RootShell()
                #if targetEnvironment(macCatalyst)
                // Mac window sizing (2026-07-28): with no explicit frame,
                // Catalyst launches the window at the iPhone's simulated
                // point size — tall and narrow, reading as a phone screen
                // in a Mac frame rather than an app that was actually sized
                // for a desktop window. `idealWidth`/`idealHeight` set a
                // Mac-appropriate default; `minWidth` keeps the horizontal
                // chip strip (SourceChips, Mac-forced by `showsRail`) and
                // the composer field from collapsing into each other —
                // `PadLayout.readingMaxWidth` (700) is the app's own
                // "one comfortable reading column" number, so the floor is
                // a fraction under it rather than an arbitrary guess.
                // `minHeight` leaves room for the strip plus a handful of
                // feed rows above the composer.
                .frame(
                    minWidth: 560, idealWidth: 980, maxWidth: .infinity,
                    minHeight: 480, idealHeight: 760, maxHeight: .infinity)
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
            // NOTE (verified live, 2026-07-28): a custom ⌘F "Find…" here
            // does NOT work — it's absorbed into Mac Catalyst's own
            // default "Find" submenu (Find…/Find & Replace/Find Next/
            // Find Previous), which the system keeps permanently DISABLED
            // in an app with no NSTextFinder-compatible text view. The
            // button silently never fires; ⌘F does nothing rather than
            // opening the composer. Dropped rather than ship a menu item
            // that reads as broken. Reaching the composer without a mouse
            // still works via ⌘N.
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    focusedChrome?.requestRefresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    HomeRoute.shared.present(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
