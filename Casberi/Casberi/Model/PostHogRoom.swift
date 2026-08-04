import Foundation

/// THE POSTHOG ROOM'S HEAD (2026-08-04, prd §298) — what you ship, moving.
///
/// The room had a real visualization all along and kept it in the wrong place:
/// `MetricDisc` — a metric's own seven-day curve inside a milestone ring — was
/// built for the setup screen's roster and the metric detail sheet, and the
/// FEED room, the surface people actually live in, led with plain rows. This is
/// the same disc at the room's head, one per watched metric.
///
/// ## It spends nothing
///
/// Everything is already on the device: `PostHogState.Metric` persists up to
/// thirty daily counts, an all-time `total`, and the `silent` flag, all
/// synchronously readable. No request, no new `Thing` field.
///
/// ## The doctrine, which shapes this more than any layout choice
///
/// PostHog is a firehose of counts and §223's whole design is that **a count is
/// never a thing**. That ruling is about what may LAND as a row, and it leaves
/// exactly one honest home for a number: a state surface that updates in place.
/// This card is that surface — which is why it may draw a curve and a total
/// that no row is allowed to carry, and why it must never grow a "12 events
/// this week" tally line. The curve IS the tally, drawn.
///
/// Three refusals inherited from §223 and kept here:
///
/// - **A metric with no series draws an EMPTY disc, never a flat line.**
///   Unread and genuinely-zero are indistinguishable at a glance, and a
///   straight line across a card is a claim about a week nobody measured.
/// - **No ring at `total == 0`** — absent, not zeroed, for the same reason.
/// - **Silence is a state, not a number.** The Metric carries a `Bool` and a
///   day-stamped row; "silent for 3 days" is not a fact this app holds, so it
///   is never spoken.
///
/// Foundation-only so `scripts/stripe-room-selftest.sh`'s sibling can compile
/// it whole; the ordering rule below is the part that fails invisibly.
struct PostHogRoom: Equatable {

    struct Metric: Identifiable, Equatable {
        /// The event name — its own identity, and its own label. A generic
        /// glyph would name nothing (the `TickerDisc` reasoning).
        var id: String { event }
        let event: String
        /// Daily counts, oldest first, dense — empty days are REAL zeroes by
        /// §223's ruling, never interpolated away.
        let series: [Int]
        /// All-time, which is what the milestone ladder rides: a rolling total
        /// crosses the same rung in both directions forever.
        let total: Int
        /// This week against the week before, or nil when there isn't enough
        /// series to say. Never a placeholder zero.
        let change: Double?
        let silent: Bool
    }

    let metrics: [Metric]
    /// Watched events whose reading has never been fetched on this device — a
    /// fresh install syncs the rows but not the `UserDefaults` state, so this
    /// is the honest "we don't know yet" count rather than a row of empty discs
    /// pretending to be data.
    let unread: Int

    var isEmpty: Bool { metrics.isEmpty }

    // MARK: - Order

    /// Which metric leads.
    ///
    /// **Silent first, then busiest by this week's volume.** The order is a
    /// judgement and it is the opposite of what a dashboard would do: a metric
    /// that STOPPED is the most valuable thing analytics can tell someone who
    /// ships (§223's own words), and it is also the one a volume sort buries,
    /// because it has no volume left. Ties fall back to the name so the roster
    /// can't reshuffle between two equal reads.
    static func ranked(_ metrics: [Metric]) -> [Metric] {
        metrics.sorted { a, b in
            if a.silent != b.silent { return a.silent }
            let aWeek = week(a.series), bWeek = week(b.series)
            if aWeek != bWeek { return aWeek > bWeek }
            return a.event < b.event
        }
    }

    /// This week's volume — the last seven dense days.
    static func week(_ series: [Int]) -> Int { series.suffix(7).reduce(0, +) }

    /// Week over week, or nil when the series can't support the claim.
    /// Fourteen days minimum, and a zero prior week yields nil rather than an
    /// infinite rise — the flat-change rule (§83 ③) in its division form.
    static func change(_ series: [Int]) -> Double? {
        guard series.count >= 14 else { return nil }
        let thisWeek = series.suffix(7).reduce(0, +)
        let lastWeek = series.dropLast(7).suffix(7).reduce(0, +)
        guard lastWeek > 0 else { return nil }
        return Double(thisWeek - lastWeek) / Double(lastWeek)
    }

    // MARK: - Words

    /// The card's one sentence. Silence leads, because it is the finding;
    /// otherwise the head states what is being watched, and the discs carry the
    /// rest. Deliberately NOT "1,240 events this week" — that is the tally the
    /// doctrine refuses, and the curve beneath already says it better.
    static func headline(_ room: PostHogRoom) -> String {
        let silent = room.metrics.filter(\.silent)
        if silent.count == 1 {
            return String(localized: "\(silent[0].event) has stopped firing")
        }
        if silent.count > 1 {
            return String(localized: "\(silent.count) metrics have stopped firing")
        }
        if room.metrics.count == 1 {
            return String(localized: "Watching \(room.metrics[0].event)")
        }
        return String(localized: "Watching \(room.metrics.count) metrics")
    }

    /// The line under it — the next rung for the leading metric, which is the
    /// only forward-looking fact this room holds. A metric with nothing read
    /// says so instead.
    static func note(_ room: PostHogRoom, nextRung: (Int) -> Int) -> String {
        if room.unread > 0, room.metrics.allSatisfy({ $0.series.isEmpty }) {
            return String(localized: "Not read on this device yet")
        }
        guard let lead = ranked(room.metrics).first, lead.total > 0 else {
            return String(localized: "Nothing counted yet")
        }
        return String(localized: "\(lead.event) is at \(compact(lead.total)) of \(compact(nextRung(lead.total)))")
    }

    /// "1.2K" — the room's own number voice, matching what the discs sit under.
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
                .replacingOccurrences(of: ".0M", with: "M")
        }
        if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
                .replacingOccurrences(of: ".0K", with: "K")
        }
        return "\(n)"
    }

    /// What the head can't see. Stated rather than swallowed: a roster of four
    /// discs on an account watching nine metrics is a different claim from one
    /// drawn over everything.
    static func coverageNote(shown: Int, total: Int, unread: Int) -> String? {
        var parts: [String] = []
        if total > shown { parts.append(String(localized: "\(total - shown) more watched")) }
        if unread > 0 { parts.append(String(localized: "\(unread) not read yet")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
