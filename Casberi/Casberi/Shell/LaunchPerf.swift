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

    /// `time`'s async twin (2026-09-01), for a block that yields partway
    /// through. Named apart rather than overloaded: an `async` overload of
    /// `time` resolves silently by context, and a call site that forgot its
    /// `await` would quietly measure something else.
    ///
    /// SAME WIRE FORMAT as `time` on purpose — `perf.sh` greps
    /// `timed=<label> took=<n>ms` and takes whatever labels it finds, so a
    /// spelling of its own would have made an already-reported number
    /// silently stop being reported. What the number MEANS does change: it is
    /// wall time across the suspensions, not main-actor time held, and those
    /// are the same figure only for a block that never yields. That is a
    /// distinction a format can't carry, so the CALL SITE carries it — see
    /// `RootShell`'s `[wall]` labels.
    @MainActor
    static func timeAsync<T>(_ label: String, _ work: () async -> T) async -> T {
        let t0 = Date()
        let v = await work()
        let ms = Date().timeIntervalSince(t0) * 1000
        NSLog("[Casberi] launchPerf timed=%@ took=%.1fms", label, ms)
        return v
    }

    /// Accumulates total time under a label across a launch, so a derivation
    /// that runs cheaply but MANY times shows its real aggregate cost — the
    /// shape that matters once per-call time is already small.
    nonisolated(unsafe) static var totals: [String: (calls: Int, ms: Double)] = [:]

    /// When each label last WROTE a line. The counters are exact; only the
    /// reporting is throttled — see below.
    nonisolated(unsafe) static var lastLogged: [String: Date] = [:]
    /// Minimum gap between two lines for the same label.
    private static let logThrottle: TimeInterval = 0.25

    @MainActor
    static func accumulate<T>(_ label: String, _ work: () -> T) -> T {
        let t0 = Date()
        let v = work()
        let now = Date()
        let ms = now.timeIntervalSince(t0) * 1000
        var e = totals[label] ?? (0, 0)
        e.calls += 1; e.ms += ms
        totals[label] = e
        // Throttled (2026-07-31): a line per call made this instrument cost
        // several times what it measured. A derivation running 74 times in a
        // cold launch emitted 74 NSLogs — ~700ms of logging to report 87ms of
        // work, which inflated the very launch number the pass exists to track
        // and made a fix look like a regression. The counters above are still
        // exact; only the reporting is rate-limited, and each line carries the
        // RUNNING total, which is why `perf.sh` parses the last line per label.
        // The first call always logs, so a label that fires once still reports.
        // Stated plainly: the last line can therefore omit whatever happened in
        // the final sub-250ms window — a rounding error next to the ~700ms of
        // distortion it removes, but it does mean these totals are a floor.
        let due = lastLogged[label].map { now.timeIntervalSince($0) >= logThrottle } ?? true
        guard due else { return v }
        lastLogged[label] = now
        NSLog("[Casberi] launchPerf accum=%@ calls=%d totalMs=%.1f lastMs=%.1f at=%dms",
              label, e.calls, e.ms, ms,
              Int(now.timeIntervalSince(LaunchClock.start) * 1000))
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
