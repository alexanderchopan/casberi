import Foundation

/// `swipePerf|` — where a room change's time actually goes (PERF 2026-08-21).
///
/// It exists because "lag swiping between screens" was, until this pass, a
/// symptom no instrument in this app could see. `perf.sh` times a cold launch,
/// steady RSS and answer latency; `askPerf|` brackets the agent's rise. A swipe
/// is none of those, so four green nightlies coexisted with the report — the
/// same shape of blindness this project's own perf memory records twice
/// already: **a metric measuring the wrong span reads clean.**
///
/// Seven marks, because the fixes for them are different and a single wall-clock
/// number cannot tell them apart:
///
///   • `step`  — the gesture decided, the source is about to change.
///   • `init`  — a `FeedScreen` value was constructed, NAMING ITS SOURCE. Two
///     of these in one swipe means the room being LEFT was rebuilt as well as
///     the one being entered; that is what it is for (PERF 2026-09-01).
///   • `chips` — the shell resolved the chip strip, i.e. one `MainSurface`
///     body pass happened. Counts the passes a swipe really costs.
///   • `body`  — that room's feed body was built, again naming its source.
///   • `mount` — the incoming `FeedScreen`'s head task ran. NOTE this fires
///     from a `.task`, so it is AFTER the first body and after SwiftUI has
///     installed the view — `init` is the mark that says when the new room
///     was first constructed.
///   • `heads` — the room's head chain finished, with the row count it read
///     and whether it came from the memo. A `heads` line that never arrives is
///     a finding, not a gap: it means the head declined or the budget is still
///     held.
///   • `rows`  — the new room's list appeared, i.e. its first content build is
///     done and the materialisation that build needed has been paid. This is
///     the mark the `rowBudget` moves; `step`→`rows` is the span a person
///     experiences as the swipe being slow.
///
/// DEBUG only and free in release: every call site is `#if DEBUG`, and the
/// clock itself compiles to nothing that runs.
///
/// NOT a `perf-history.csv` column, deliberately — that file is parsed by field
/// POSITION, so a new column silently re-reads every historical row's
/// `build_sha` as a latency (the 2026-08-16 `askPerf|` ruling). It is a
/// reported section, read from the log.
@MainActor
enum SwipeClock {
    // MARK: - Gate

    /// **THIS CLOCK REPORTS IN RELEASE NOW (PERF 2026-09-04, prd §600).**
    ///
    /// It was `#if DEBUG` from the day it shipped, which made the one
    /// instrument built for the one reported symptom — "lag swiping between
    /// screens" — structurally unable to say anything about the configuration
    /// people actually run. Every number in this project's perf record is
    /// Debug on a simulator, and the 2026-08-21 pass that built this clock
    /// closed by saying a device trace is the reading that would settle it.
    /// A DEBUG-only trace cannot be that reading.
    ///
    /// `LaunchClock.reports` (`CasberiApp.swift`) and `SweepClock.isOn` are
    /// both already shaped this way and are the precedent followed exactly:
    /// DEBUG always reports, Release reports only on an explicit
    /// `-swipeTimer YES`, which lands in `NSArgumentDomain` before any of this
    /// runs. A shipped build passes the flag to nobody and stays silent.
    ///
    /// CACHED for `SweepClock`'s stated reason: this is consulted on every
    /// instrumented call, and a `UserDefaults` hit per call is an instrument
    /// that costs what it measures.
    private static var cachedOn: Bool?
    static var isOn: Bool {
        if let cachedOn { return cachedOn }
        #if DEBUG
        let on = true
        #else
        let on = UserDefaults.standard.bool(forKey: "swipeTimer")
        #endif
        cachedOn = on
        return on
    }

    // MARK: - The trace

    /// Nil unless a swipe is in flight — so the storage is also the guard, and
    /// nothing here allocates or formats while the clock is off.
    private static var t0: Date?
    private static var room: String = ""

    /// The gesture landed. Starts the clock and names where it is going.
    static func step(to source: String) {
        guard isOn else { return }
        t0 = .now
        room = source
        NSLog("[Casberi] swipePerf| step to=%@", source)
    }

    /// One mark on the current swipe. Silent when no swipe is in flight, so a
    /// deep link or a launch never prints a half-trace with no `step` above it.
    static func mark(_ event: String, detail: String = "") {
        guard let t0 else { return }
        NSLog("[Casberi] swipePerf| %@ at=%dms room=%@%@",
              event, Int(Date.now.timeIntervalSince(t0) * 1000), room,
              detail.isEmpty ? "" : " " + detail)
    }

    /// The swipe is over — the next `step` starts a fresh trace. Called when
    /// the new room's list appears, so a room that never draws one leaves its
    /// trace open and visibly unfinished rather than silently tidy.
    static func finish() {
        guard t0 != nil else { return }
        mark("rows")
        t0 = nil
    }

    /// Time one synchronous block on the shell's own path, swipe or not
    /// (prd §600, 2026-09-04).
    ///
    /// Deliberately NOT `mark`: that one is silent unless a swipe is in flight,
    /// which is correct for a swipe trace and useless for a LAUNCH, where the
    /// shell's most expensive walk happens. `LaunchPerf.time` already does this
    /// job and its whole file is `#if DEBUG`, so it cannot answer the question
    /// that matters here — whether a cost measured in Debug on a simulator is
    /// still a cost in Release on a phone.
    ///
    /// Same gate as everything else in this file, so a shipped build that was
    /// not asked to report prints nothing.
    @discardableResult
    static func span<T>(_ label: String, _ work: () -> T) -> T {
        guard isOn else { return work() }
        let t0 = ContinuousClock.now
        let value = work()
        let ms = Double((ContinuousClock.now - t0).components.attoseconds) / 1e15
        NSLog("[Casberi] swipePerf| span=%@ took=%.1fms", label, ms)
        return value
    }
}
