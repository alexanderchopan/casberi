import BackgroundTasks
import Foundation

/// Opportunistic wallet sampling (2026-07-15) — the value line is only ever as
/// dense as how often you open the app (holdings sample at most once per 4h,
/// on foreground). A BGAppRefreshTask lets iOS run a holdings read while you're
/// away, so the line fills in between opens WITHOUT changing the honesty: each
/// sample is still a real onchain read, still forward-only, never back-filled —
/// there are simply more of them. The footer copy softens from "sampled as you
/// use Casberi" accordingly.
///
/// iOS decides IF and WHEN this runs (it never fires on a fixed clock, and
/// never at all on the Simulator) — the app only registers a handler and asks
/// politely. Registration MUST happen before the app finishes launching, so it
/// runs from `CasberiApp.init`; scheduling runs each time we background.
enum WalletBackgroundRefresh {
    static let taskID = "com.casberi.app.walletsample"

    /// Registered once at launch (CasberiApp.init). No-op harm if the OS never
    /// schedules the task — it just sits idle.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false); return
            }
            handle(refresh)
        }
    }

    /// Asks iOS for a future run — only when there's a wallet to sample. Called
    /// on background (RootShell scenePhase) and after each run (self-chaining).
    /// `earliestBeginDate` mirrors the 4h sample throttle: a sooner run would
    /// only be throttled out by recordSample anyway.
    static func schedule() {
        guard !WalletStore.shared.addresses.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Chain the next run first, so a crash mid-work still leaves one queued.
        schedule()
        // The expiration handler is armed BEFORE the work starts (an early OS
        // expiration must still find a cancel hook), and completion runs
        // exactly once — either the work finishes (success unless cancelled) or
        // expiration reports failure. Leaving a task un-completed makes iOS
        // treat it as a failure and throttle future scheduling.
        let state = CompletionState()
        task.expirationHandler = {
            state.work?.cancel()
            state.complete(task, success: false)
        }
        state.work = Task { @MainActor in
            // The same read a foreground does: holdings (records the sample,
            // checks the combined/single new high). Any moment it detects queues
            // on WalletMoments and shows on the next foreground.
            _ = await WalletIngest.topHoldingsByWallet()
            state.complete(task, success: !Task.isCancelled)
        }
    }

    /// One-shot completion + a slot for the work handle, so the expiration
    /// handler can be armed before the work exists and neither path double-
    /// calls setTaskCompleted (Apple requires exactly one call).
    private final class CompletionState {
        private let lock = NSLock()
        private var done = false
        var work: Task<Void, Never>?

        func complete(_ task: BGAppRefreshTask, success: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            task.setTaskCompleted(success: success)
        }
    }
}
