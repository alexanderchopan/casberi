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

    var body: some Scene {
        WindowGroup {
            RootShell()
        }
        .modelContainer(container)
    }
}
