import Foundation

#if DEBUG
/// Cold-launch profiling counters (DEBUG only, 2026-07-30) — for the "first
/// open lags / slow motion" investigation. The `launchTimer init→ready` marker
/// (CasberiApp/RootShell) measures only up to the FIRST frame; this measures
/// what happens AFTER — the repeated body re-evaluations and derivation passes
/// that saturate the main thread through the entrance window, which is what a
/// first-frame marker can't see.
///
/// Read headlessly: `xcrun simctl spawn booted log stream --predicate
/// 'eventMessage CONTAINS "launchPerf"'` during a cold launch. Zero cost in
/// release (whole file is `#if DEBUG`).
enum LaunchPerf {
    nonisolated(unsafe) static var bodyEvals: [String: Int] = [:]
    nonisolated(unsafe) static var derivations = 0
    nonisolated(unsafe) static var lastLog = Date()

    /// Call at the top of a screen `body`. Logs a running per-source count and
    /// the ms since launch, so a flood of rebuilds during the launch window is
    /// visible as a burst of ticks in the first few seconds.
    @MainActor
    static func bodyTick(_ source: String, active: Bool) {
        bodyEvals[source, default: 0] += 1
        let n = bodyEvals[source] ?? 0
        // Log every eval for the first 40, then every 10th — enough to see the
        // burst without drowning the stream on a long-lived page.
        guard n <= 40 || n % 10 == 0 else { return }
        let ms = Int(Date().timeIntervalSince(LaunchClock.start) * 1000)
        NSLog("[Casberi] launchPerf body source=%@ active=%d eval#%d at=%dms", source, active ? 1 : 0, n, ms)
    }

    /// Call when an expensive corpus derivation runs (bundling, treemap), to
    /// count how many fire during launch.
    @MainActor
    static func derivationTick(_ label: String, count: Int) {
        derivations += 1
        let ms = Int(Date().timeIntervalSince(LaunchClock.start) * 1000)
        NSLog("[Casberi] launchPerf derive=%@ n=%d over=%d at=%dms", label, derivations, count, ms)
    }

    /// Times a synchronous block and logs it (for the container load / first
    /// derivation). Returns the block's value.
    @MainActor
    static func time<T>(_ label: String, _ work: () -> T) -> T {
        let t0 = Date()
        let v = work()
        let ms = Date().timeIntervalSince(t0) * 1000
        NSLog("[Casberi] launchPerf timed=%@ took=%.1fms", label, ms)
        return v
    }
}
#endif
