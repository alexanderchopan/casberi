import UIKit

/// **Is the scene this shell is about to draw into in the BACKGROUND?**
/// (prd §642, 2026-09-07; corrected the same day — see the second section.)
///
/// One `Bool`, resolved once, from the only object that can answer it — and
/// the reason it exists is a third `0x8BADF00D`.
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
/// ## The first cut asked the WRONG OBJECT, and it blanked the Mac
///
/// Build 537 stamped this from `UIApplication.applicationState` inside
/// `didFinishLaunchingWithOptions`, on the documented-sounding premise that it
/// reads `.background` for a background launch and `.inactive` for a foreground
/// one. **That premise is false for a scene-based app, which every SwiftUI
/// `App` is.** `applicationState` is derived from the app's SCENES, and at
/// `didFinishLaunchingWithOptions` no scene has connected yet — so it answers
/// `.background` for EVERY launch there, foreground ones included. Measured,
/// not reasoned: every line of build 537's Mac verify logs and every simulator
/// launch stamped `backgroundLaunch: yes`.
///
/// On iOS that shipped as a near-miss — `willEnterForegroundNotification`
/// arrives a beat later and mounts the shell, so the app looked correct and the
/// screen sweep photographed a healthy app. **On Mac Catalyst it shipped as a
/// blank window**: `RootShell`'s own note records that the launch transition
/// never reaches the scene-phase observer there (the scene is already
/// `.foregroundActive` before SwiftUI attaches it), and `willEnterForeground`
/// does not post for a launch either — so neither mount door opened and the
/// window stayed at bare `DSPageBackground`. `verify-mac.sh`'s connect probe
/// caught it, which is the whole reason that step exercises the door a person
/// takes rather than the screen.
///
/// **So the question is asked of the SCENE, not the application**, and asked at
/// the moment the shell is about to be built rather than before one exists.
/// `UIScene.ActivationState` is the per-scene fact: a scene connected for a
/// background refresh is `.background`, a scene connected for a launch someone
/// is watching is `.foregroundInactive` and then `.foregroundActive`. There is
/// no earlier honest moment — a fact that does not exist yet cannot be stamped
/// early, it can only be guessed.
///
/// The answer is **memoised on first read** rather than recomputed, and that
/// property is load-bearing in the same way the stored flag was: read afresh
/// later, this would report "not background" the instant the app wakes, which
/// is precisely when the shell must still be withheld. First read happens in
/// `RootShell`'s `@State` default — i.e. while SwiftUI is building the window
/// group's content for a connected scene — so the scene set is populated.
///
/// Deliberately NOT the same fact as `scenePhase`: the phase says where the app
/// is NOW and is the right signal for MOUNTING (see `RootShell`'s four doors);
/// this says what the scene was doing when the tree was first asked for, which
/// is the only thing that can decide not to build in the first place.
enum BackgroundLaunch {
    /// The memoised answer. `nil` until the first read resolves it; written and
    /// read from the main thread. `nonisolated(unsafe)` because a `@State`
    /// default expression is not an isolated context — the same shape
    /// `LaunchPerf`'s counters take.
    nonisolated(unsafe) private static var stamped: Bool?

    /// Was the scene this process is building for connected in the background?
    /// Resolved ONCE, on first read, and never re-derived afterwards.
    static var isBackgroundLaunch: Bool {
        if let stamped { return stamped }
        let answer = resolve()
        stamped = answer
        NSLog("[Casberi] backgroundLaunch: %@", answer ? "yes" : "no")
        return answer
    }

    /// The one derivation: no connected scene is in a foreground state.
    ///
    /// Asked of `connectedScenes` rather than of `UIApplication.applicationState`
    /// — see the second section of this type's note for what that distinction
    /// cost. An empty scene set answers `false`: it means the question was asked
    /// before any scene existed, and a wrong "yes" there is a permanently blank
    /// window, while a wrong "no" is only the pre-§642 behaviour.
    private static func resolve() -> Bool {
        #if DEBUG
        // The gate's only headless door. Nothing on this machine can make iOS
        // background-launch an app, so `-forceBackgroundLaunch YES` is how a
        // probe run sees the closed branch at all (it opens again the instant
        // the scene goes active, which is itself the check that the doors work).
        if UserDefaults.standard.bool(forKey: "forceBackgroundLaunch") { return true }
        #endif
        let scenes = UIApplication.shared.connectedScenes
        guard !scenes.isEmpty else { return false }
        return !scenes.contains { scene in
            scene.activationState == .foregroundActive
                || scene.activationState == .foregroundInactive
        }
    }
}
