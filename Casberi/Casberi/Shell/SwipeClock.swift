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
    #if DEBUG
    private static var t0: Date?
    private static var room: String = ""
    #endif

    /// The gesture landed. Starts the clock and names where it is going.
    static func step(to source: String) {
        #if DEBUG
        t0 = .now
        room = source
        NSLog("[Casberi] swipePerf| step to=%@", source)
        #endif
    }

    /// One mark on the current swipe. Silent when no swipe is in flight, so a
    /// deep link or a launch never prints a half-trace with no `step` above it.
    static func mark(_ event: String, detail: String = "") {
        #if DEBUG
        guard let t0 else { return }
        NSLog("[Casberi] swipePerf| %@ at=%dms room=%@%@",
              event, Int(Date.now.timeIntervalSince(t0) * 1000), room,
              detail.isEmpty ? "" : " " + detail)
        #endif
    }

    /// The swipe is over — the next `step` starts a fresh trace. Called when
    /// the new room's list appears, so a room that never draws one leaves its
    /// trace open and visibly unfinished rather than silently tidy.
    static func finish() {
        #if DEBUG
        guard t0 != nil else { return }
        mark("rows")
        t0 = nil
        #endif
    }
}
