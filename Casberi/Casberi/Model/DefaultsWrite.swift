import Foundation

/// **A `UserDefaults` WRITE IS NEVER DONE WHILE HOLDING A LOCK (prd §720).**
///
/// This is a deadlock, not a slow path, and it killed build 570 on a real
/// phone (crash report 2026-09-13, `0x8BADF00D` scene-update watchdog,
/// *"is stuck (deadlock)"*). The give-away in that report is the CPU line:
/// **"Elapsed application CPU time (seconds): 0.017, 0% CPU."** Every other
/// watchdog in this project's history (§614, §642, §646, §657) is the app
/// doing too much work to answer in time. This one did nothing at all.
///
/// The cycle, both halves of it in the report:
///
/// 1. A background cooperative thread takes a store's `NSLock` and, while
///    holding it, calls `UserDefaults.standard.set`.
/// 2. `UserDefaults` posts `NSUserDefaultsDidChangeNotification`
///    **synchronously, on that same thread**.
/// 3. SwiftUI observes it — `UserDefaultObserver.userDefaultsDidChange`, which
///    is how `@AppStorage` invalidates — and calls `Update.enqueueAction` →
///    `Update.begin()`, which takes SwiftUI's own global update lock.
/// 4. Meanwhile the MAIN thread is inside `ViewBodyAccessor.updateBody`, so it
///    already holds SwiftUI's update lock, and the body it is evaluating asks
///    the same store for a reading — `lock.lock()`.
///
/// Background holds ours and wants SwiftUI's; main holds SwiftUI's and wants
/// ours. Neither ever moves, and the watchdog kills the process. In the
/// report five more cooperative threads are queued behind the same lock.
///
/// **Both halves were introduced deliberately and separately**, which is why
/// nobody saw the pair: §710 memoised `BridgeHealth` behind a lock (to stop a
/// body's three decodes per pass) and left its `UserDefaults` write inside
/// that lock — and the body reads §710 was making cheap are the other half.
/// `FeedFreshness`, `NetworkLedger`, `AgentSpend` and `AppMetrics` all had the
/// same shape, two of them with a comment explaining that the write stays
/// inside the lock deliberately, to keep two racing flushes in order.
///
/// **That ordering reason is real and this keeps it.** Writes go out on ONE
/// serial queue in the order they were handed over — and they are handed over
/// while the caller still holds its own lock, so the enqueue order is the
/// snapshot order. What changes is only that `UserDefaults` is touched on a
/// thread that holds nothing, so the notification it posts can wait for
/// SwiftUI's update lock without a single one of this app's locks being held.
///
/// `data(forKey:)` is the matching read: a store that round-trips through
/// `UserDefaults` (`AppMetrics` reads its rows back to fold new ones in) would
/// otherwise miss a write that has not drained yet. The memo holds the newest
/// value handed over for each key and is never cleared — there are six keys.
///
/// Deliberately NOT offered: a `drain()` that blocks until the queue is empty.
/// Called from the main thread inside a body it re-creates this exact deadlock
/// from the other direction, and nothing needs it.
enum DefaultsWrite {

    private static let queue = DispatchQueue(label: "com.casberi.defaults-write",
                                             qos: .utility)

    /// The newest value handed over per key — a write-through memo, so a read
    /// that follows a write sees the write whether or not it has drained.
    /// `Data?` VALUES, stored with `updateValue` rather than a subscript
    /// assignment: `memo[key] = nil` would REMOVE the entry, which is the
    /// opposite of recording "this key was cleared".
    private static let memoLock = NSLock()
    private static var memo: [String: Data?] = [:]

    /// Persist `data` for `key` off the caller's thread; nil removes the key.
    /// **Safe to call while holding your own lock** — that is the whole point.
    static func set(_ data: Data?, forKey key: String) {
        memoLock.lock()
        memo.updateValue(data, forKey: key)
        memoLock.unlock()
        queue.async {
            if let data {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// The value a `set` would have left, whether or not it has drained yet.
    /// Falls through to `UserDefaults` for a key this process has not written.
    static func data(forKey key: String) -> Data? {
        memoLock.lock()
        let remembered = memo[key]
        memoLock.unlock()
        if let remembered { return remembered }
        return UserDefaults.standard.data(forKey: key)
    }
}
