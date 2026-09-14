import Foundation

/// Persist a store's snapshot to `UserDefaults` WITHOUT posting its change
/// notification from inside a lock (prd §721).
///
/// **The crash this exists to prevent.** Build 570 on a phone died
/// `0x8BADF00D` — a scene-update watchdog, main thread deadlocked, four
/// minutes after launch. It is not §614's family (nothing was rendering too
/// slowly) and not §646's (no query was re-read): the main thread and a bridge
/// sweep took two locks in opposite orders.
///
///   · MAIN, inside a view body, holds SwiftUI's update lock (every body runs
///     under `Update.ensure`) and asks `BridgeHealth` for a seat's record —
///     which takes `BridgeHealth.lock`. Every account page does this: 55
///     screens call `AccountPageState.of` from their body.
///   · A SWEEP, off the main actor, holds `BridgeHealth.lock` (its whole
///     load-modify-save is one critical section, prd §710) and calls
///     `UserDefaults.standard.set` inside it. **That posts
///     `didChangeNotification` synchronously, on the calling thread**, and any
///     app with an `@AppStorage` anywhere has SwiftUI's own observer on it:
///     `UserDefaultObserver.userDefaultsDidChange` → `Update.enqueueAction` →
///     `Update.begin` → the update lock main is holding.
///
/// Neither side can finish. The app freezes wherever it is standing — a tap on
/// the catalogue does nothing, no page redraws — and the watchdog kills it
/// however many seconds later. Nothing here could ever see it: the deadlock
/// needs a sweep response and a body evaluation to overlap on a device, both
/// builds are clean, and every screenshot pass and probe launch renders it
/// perfectly.
///
/// **THE RULE, and it is broader than this file.** Code holding a lock that
/// the main thread can contend must not call out to anything that takes
/// SwiftUI's update lock. `UserDefaults.set` is the one that hides it — it
/// reads as a pure store write and is a synchronous notification post.
/// `scripts/defaults-lock-audit.py` is that rule, mechanically.
///
/// **What this changes, and what it does not.** The value still moves under
/// the store's own lock — the in-memory cache is authoritative and every one
/// of these stores reads it, so nothing reads stale. Only the `UserDefaults`
/// call is handed to this one serial queue, which keeps same-key writes in the
/// order they were made (the reason those writes were put inside the lock in
/// the first place: two flushes racing must not leave the older snapshot on
/// disk). The queue is the ONLY thing holding those writes, and it holds no
/// other lock, so the cycle above cannot form.
///
/// **Durability, stated rather than assumed — there IS a new loss window.**
/// The disk was never synchronous (CFPreferences coalesces and flushes on its
/// own schedule), but the value used to reach `UserDefaults`' own in-memory
/// store on the calling line and now reaches it when the queue runs, so a
/// process that dies in between loses a write that would previously have
/// survived. The real case is a background sweep: a `BGAppRefreshTask` that
/// calls `setTaskCompleted` can be suspended with a block still queued, and a
/// suspended process that is then killed never runs it. The window is
/// microseconds on an unloaded queue, every one of these stores keeps the
/// value in its own cache for the life of the process, and what can be lost is
/// one sweep's health/receipt record — weighed against an app that freezes on
/// every page until the watchdog kills it, the trade is not close. There is
/// deliberately no blocking drain: a `queue.sync` from the main thread would
/// re-open the exact deadlock this closes, one lock further out.
enum DefaultsWrite {

    /// Serial, so writes to one key land in the order they were made.
    ///
    /// **`.userInitiated`, not `.utility`, and that is the deadlock's own
    /// argument turned around**: `defaults.set` enters SwiftUI's update lock
    /// on this thread, and the main thread contends that lock on every body.
    /// A background-priority thread holding it is a priority inversion with no
    /// donation — a frame waiting on a queue the scheduler is in no hurry to
    /// run. Nothing on screen waits for the VALUE (every reader of these
    /// stores reads their in-memory cache); the main thread can wait for the
    /// LOCK the write takes, which is a different thing and the reason for the
    /// priority.
    private static let queue = DispatchQueue(label: "com.casberi.defaults.write",
                                             qos: .userInitiated)

    static func set(_ value: Data, forKey key: String,
                    in defaults: UserDefaults = .standard) {
        queue.async { defaults.set(value, forKey: key) }
    }

    /// Removal rides the SAME queue as the writes. A synchronous
    /// `removeObject` would be overtaken by a write still queued for that key
    /// — "delete everything" followed by the record it was meant to delete.
    static func remove(_ key: String, in defaults: UserDefaults = .standard) {
        queue.async { defaults.removeObject(forKey: key) }
    }
}
