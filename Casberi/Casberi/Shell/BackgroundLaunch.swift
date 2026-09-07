import UIKit

/// **Was this process launched into the BACKGROUND?** (prd §642, 2026-09-07.)
///
/// One `Bool`, stamped once, from the one callback that can answer it
/// truthfully — and the reason it exists is a third `0x8BADF00D`.
///
/// iOS launches this app with nobody looking: `WalletBackgroundRefresh`
/// registers a `BGAppRefreshTask`, and `handleDeactivation` submits one every
/// time the app backgrounds. When the OS decides to run it, the app is started
/// by `launchd` with `procRole: Background` — and a scene-based app STILL gets
/// its window scene connected, so SwiftUI builds the entire shell where no
/// frame will ever be shown. Build 534 died exactly there: the main thread
/// inside one `GraphHost.flushTransactions` → `DynamicBody.updateValue` →
/// `EnvironmentBox.update` → `_swift_getGenericMetadata`, killed by the
/// scene-update watchdog for exhausting "real (wall clock) time allowance of
/// 10.00 seconds". No Casberi frame on the stack, no crash to find, nothing
/// wrong with the code it died in.
///
/// **The arithmetic is the whole argument, and it is the app's own number.**
/// prd §628 measured this app's first real paint on a phone at **1.3s**. The
/// report's own line reads `Elapsed application CPU time (seconds): 9.976,
/// 16% CPU` — a backgrounded app is CPU-throttled, and at 16% a 1.3s build is
/// about **8 seconds of wall clock** before the store, the first query or a
/// single row is counted. So building this shell for a background-connected
/// scene was never a race the app could reliably win; it was a coin flip
/// against a 10-second wall, taken on every background refresh.
///
/// **Why the fix is here and not in the view.** `UIApplication.applicationState`
/// is `.background` at `didFinishLaunchingWithOptions` for a background launch
/// and `.inactive` for a foreground one — that is the documented difference,
/// and it is only reliable BEFORE anything else runs. Read later, from a view
/// initializer on some arbitrary turn, it answers about the moment it was
/// asked rather than about the launch. So `AppDelegate` stamps it, once, and
/// every reader gets the same answer for the life of the process.
///
/// Deliberately NOT the same fact as `scenePhase`: the phase says where the
/// app is NOW and is the right signal for MOUNTING (see `RootShell`'s two
/// doors); this says how the process STARTED, which is the only thing that can
/// decide not to build in the first place.
enum BackgroundLaunch {
    /// Written once from the main thread inside `didFinishLaunchingWithOptions`,
    /// read from view initializers on the main thread afterwards. `nonisolated`
    /// because a `@State` default expression is not an isolated context — the
    /// same shape `LaunchPerf`'s counters take.
    nonisolated(unsafe) private(set) static var isBackgroundLaunch = false

    /// Stamp the launch. Idempotent in effect: called once, from the one
    /// callback UIKit guarantees runs before any scene or view exists.
    static func record(_ application: UIApplication) {
        var background = application.applicationState == .background
        #if DEBUG
        // The gate's only headless door. Nothing on this machine can make iOS
        // background-launch an app, so `-forceBackgroundLaunch YES` is how a
        // probe run sees the closed branch at all (it opens again the instant
        // the simulator's scene goes active, which is itself the check that
        // the doors work).
        if UserDefaults.standard.bool(forKey: "forceBackgroundLaunch") { background = true }
        #endif
        isBackgroundLaunch = background
        NSLog("[Casberi] backgroundLaunch: %@", background ? "yes" : "no")
    }
}
