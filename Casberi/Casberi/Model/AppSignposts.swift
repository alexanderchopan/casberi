import Foundation
#if canImport(MetricKit)
import MetricKit
import os
#endif

/// The three spans this app is judged on, measured on REAL DEVICES in RELEASE
/// (2026-09-05) — `docs/perf-spec.md`'s P0, running by itself.
///
/// **What this fixes.** The perf spec ranks "baseline the phone" above every
/// other workstream and says everything below re-ranks against it; it is still
/// open, marked *needs the phone*, because both existing instruments
/// (`LaunchClock`, `AskClock`, `SweepClock`) report to `NSLog` and somebody has
/// to be holding the device with a console attached. So every number in the
/// perf record — six measured passes, 2026-08-06 through 2026-09-01 — is Debug
/// on a simulator, and the spec says so in its own first paragraph.
///
/// `mxSignpost` closes that. An interval emitted through
/// `MXMetricManager.makeLogHandle` comes back in the daily `MXMetricPayload` as
/// an `MXSignpostMetric`: a DURATION HISTOGRAM of that span, plus its CPU time,
/// average memory and (iOS 15+) hitch-time ratio, aggregated from whichever
/// devices ran the build. Nobody runs anything. See `AppMetrics` for delivery.
///
/// **Sparingly, and that word is Apple's.** `MXSignpost.h`: *"THESE CALLS ARE
/// MUCH MORE EXPENSIVE THAN NORMAL OS_SIGNPOST_* CALLS and are meant to be
/// called sparingly. Bulk replacing of calls to os_signpost with MXSignpost
/// will lead to potentially large performance regressions."* Each call takes a
/// snapshot of process-level metrics. So the rule here is hard and mechanical:
///
///   **A span fires at most once per user-initiated event, and NEVER from a
///   view body, a loop, or a per-row path.**
///
/// This repo has already paid for the softer version of that lesson —
/// `LaunchPerf.accumulate` emitted one `NSLog` per call and cost ~700ms to
/// report 87ms of work, inflating the very launch number it existed to track
/// and making a fix look like a regression. An expensive instrument inside the
/// thing it measures does not produce a slightly-worse number; it produces a
/// wrong one. `scripts/metrics-selftest.sh` enforces the call-site rule.
///
/// **Worst case per session**: one Launch pair, one ForegroundSweep pair per
/// activation, two pairs per ask. An ask already costs a network round trip and
/// a model run; a sweep already polls every connected bridge.
///
/// **The room swipe is deliberately NOT instrumented.** It is the span most
/// often reported as jittery, and it is exactly the one where the instrument
/// would land inside the animation's own frames — several times a minute, in
/// the window the fix is supposed to protect. `MXAnimationMetric`'s
/// `scrollHitchTimeRatio` already arrives in every payload, app-wide, at zero
/// cost; read that first. If it says something, `mxSignpostAnimationIntervalBegin`
/// on a SAMPLED subset of swipes is the next step — not before.
enum AppSignposts {

    #if canImport(MetricKit)
    /// One handle for the process. `makeLogHandle` is what makes an interval
    /// eligible for `MXSignpostMetric` — a plain `OSLog` emits a signpost
    /// Instruments can see and MetricKit will never report.
    private static let log = MXMetricManager.makeLogHandle(category: "Casberi")
    #endif

    // Pairing guards. `mxSignpost` uses `.exclusive` as its signpost id, so a
    // second `.begin` before the matching `.end` overlaps two intervals on one
    // id and the samples that come back are nonsense. Every span here is
    // logically single-flight already (one launch, one activation at a time,
    // `askGeneration` cancels the previous ask) — these guards mean a path that
    // stops being single-flight degrades to a MISSING sample rather than a
    // wrong one, which is the direction a measurement should fail in.
    @MainActor private static var launchOpen = false
    @MainActor private static var sweepOpen = false
    @MainActor private static var askOpen = false
    @MainActor private static var askPaintOpen = false

    // MARK: - Launch  (init → first content, once per process)

    /// Paired with `LaunchClock.start`'s own stamp — called from
    /// `CasberiApp.init`, the earliest app-owned code.
    @MainActor static func beginLaunch() {
        guard !launchOpen else { return }
        launchOpen = true
        #if canImport(MetricKit)
        mxSignpost(.begin, log: log, name: "Launch")
        #endif
    }

    /// The same moment `launchTimer init→ready` is logged: the first frame's
    /// view tree is assembled. Called once; later calls are ignored.
    @MainActor static func endLaunch() {
        guard launchOpen else { return }
        launchOpen = false
        #if canImport(MetricKit)
        mxSignpost(.end, log: log, name: "Launch")
        #endif
    }

    // MARK: - Foreground sweep  (once per activation)

    /// Brackets `runForegroundWork` — polling every connected bridge, the
    /// embedding backfill, the insight/kept-ask/whisper recompute. Suspected as
    /// the cause of app lag four separate times and measured innocent once
    /// (~5%, within noise); this is the first reading of it that will ever come
    /// from a real device, which is the only place the question was ever open.
    @MainActor static func beginForegroundSweep() {
        guard !sweepOpen else { return }
        sweepOpen = true
        #if canImport(MetricKit)
        mxSignpost(.begin, log: log, name: "ForegroundSweep")
        #endif
    }

    @MainActor static func endForegroundSweep() {
        guard sweepOpen else { return }
        sweepOpen = false
        #if canImport(MetricKit)
        mxSignpost(.end, log: log, name: "ForegroundSweep")
        #endif
    }

    // MARK: - Ask  (tap → first paint, and tap → settled)

    /// TWO intervals from one entry, because they answer different questions —
    /// `AskClock`'s ruling, carried to the device. `AskSettled` is when the real
    /// document lands; `AskFirstPaint` is what the person experiences.
    @MainActor static func beginAsk() {
        guard !askOpen else { return }
        askOpen = true
        askPaintOpen = true
        #if canImport(MetricKit)
        mxSignpost(.begin, log: log, name: "AskSettled")
        mxSignpost(.begin, log: log, name: "AskFirstPaint")
        #endif
    }

    /// First writer wins — a later paint is the document being refined, not the
    /// wait ending (`AskClock.paint`'s rule).
    @MainActor static func askFirstPaint() {
        guard askPaintOpen else { return }
        askPaintOpen = false
        #if canImport(MetricKit)
        mxSignpost(.end, log: log, name: "AskFirstPaint")
        #endif
    }

    /// Closes `AskFirstPaint` too when no early channel ever fired.
    ///
    /// That is deliberate and it is NOT the same as `AskClock`'s
    /// `firstPaint=never`. A histogram measures "how long until anything
    /// appeared", and for a branch with no early channel the answer really is
    /// the settle time — the person saw nothing until it finished. Leaving the
    /// interval open instead would drop the sample AND leave an unmatched
    /// `.begin` on `.exclusive` for the next ask to overlap.
    @MainActor static func endAsk() {
        askFirstPaint()
        guard askOpen else { return }
        askOpen = false
        #if canImport(MetricKit)
        mxSignpost(.end, log: log, name: "AskSettled")
        #endif
    }
}
