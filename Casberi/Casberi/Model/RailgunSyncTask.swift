import BackgroundTasks
import Foundation

/// **RAILGUN SYNCS WHILE THE PHONE CHARGES (prd §2009 item 4, user: "do 1-5").**
/// A first sync took minutes on the user's phone with Casberi held open
/// (prd §1885), and every later one still takes seconds before a private
/// move can price. A processing task asks iOS for a few minutes while the
/// phone is on power and online, so the trees and the balance are current
/// before you open Move. iOS decides if and when it runs; it never runs on
/// the Simulator, and the engine's web view in the background is UNMEASURED
/// on a phone.
enum RailgunSyncTask {
    static let taskID = "com.casberi.app.railgunsync"

    /// Registered once at launch (CasberiApp.init), beside the wallet's tasks.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false); return
            }
            handle(processing)
        }
    }

    /// Asked for on background, only where a Railgun wallet exists.
    @MainActor
    static func schedule() {
        guard RailgunHoldings.shared.shows, RailgunPocket.hasWallet, !DemoMode.isActive else { return }
        let request = BGProcessingTaskRequest(identifier: taskID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGProcessingTask) {
        Task { @MainActor in schedule() }
        let done = Once()
        let work = Task { @MainActor in
            await RailgunHoldings.shared.refresh(force: true)
            NSLog("railgunSync| background | read %@", RailgunHoldings.shared.readAt.map { "\($0)" } ?? "nothing")
            done.run { task.setTaskCompleted(success: !Task.isCancelled) }
        }
        task.expirationHandler = {
            work.cancel()
            done.run { task.setTaskCompleted(success: false) }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var ran = false
        func run(_ body: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            guard !ran else { return }
            ran = true
            body()
        }
    }
}
