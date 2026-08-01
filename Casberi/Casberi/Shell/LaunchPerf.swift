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
    nonisolated(unsafe) static var heavyBuilds: [String: Int] = [:]

    /// Call at the top of the HEAVY tree (`feedList`), so this counts actual
    /// deep feed-tree assembly. The 2026-07-30 finding: `TabView(.page)` built
    /// this for ALL ~10 source pages on every render pass (≈110 assemblies in
    /// the first second of a cold launch); the `nearActive` gate cut it to the
    /// active page plus its neighbour (≈24). Re-measure with `xcrun simctl
    /// spawn booted log stream --predicate 'eventMessage CONTAINS "HEAVYBUILD"'`.
    @MainActor
    static func buildTick(_ source: String) {
        heavyBuilds[source, default: 0] += 1
        let n = heavyBuilds[source] ?? 0
        let ms = Int(Date().timeIntervalSince(LaunchClock.start) * 1000)
        NSLog("[Casberi] launchPerf HEAVYBUILD source=%@ build#%d at=%dms", source, n, ms)
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

    /// Accumulates total time under a label across a launch, so a derivation
    /// that runs cheaply but MANY times shows its real aggregate cost — the
    /// shape that matters once per-call time is already small.
    nonisolated(unsafe) static var totals: [String: (calls: Int, ms: Double)] = [:]

    @MainActor
    static func accumulate<T>(_ label: String, _ work: () -> T) -> T {
        let t0 = Date()
        let v = work()
        let ms = Date().timeIntervalSince(t0) * 1000
        var e = totals[label] ?? (0, 0)
        e.calls += 1; e.ms += ms
        totals[label] = e
        NSLog("[Casberi] launchPerf accum=%@ calls=%d totalMs=%.1f lastMs=%.1f at=%dms",
              label, e.calls, e.ms, ms,
              Int(Date().timeIntervalSince(LaunchClock.start) * 1000))
        return v
    }
}
#endif

/// Release-safe timing shim — `#if DEBUG` inside a `@ViewBuilder` `let` is
/// awkward, so call sites use this and pay nothing in release.
@MainActor @inline(__always)
func perfAccum<T>(_ label: String, _ work: () -> T) -> T {
    #if DEBUG
    return LaunchPerf.accumulate(label, work)
    #else
    return work()
    #endif
}
