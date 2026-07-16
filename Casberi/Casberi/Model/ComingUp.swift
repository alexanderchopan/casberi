import Foundation

/// The "Coming up" lane (2026-07-14) — the person's own dated things resurfaced
/// because a deadline is near, the way CardPointers surfaces an expiring credit.
/// Two sources, both already in the corpus:
///
/// - **Events** (Calendar/Cal.com/Calendly) carry their start in `capturedAt`;
///   the calendar ingest now reaches a week ahead (ScheduleIngest.forwardWindow),
///   so upcoming events are real things.
/// - **Reminders** carry their deadline in `dueAt` (their `capturedAt` is the
///   creation time). A reminder past due is the most urgent row — it leads, the
///   way an expired credit does.
///
/// This is a READ over the local corpus, computed synchronously when Home
/// composes — no fetch, no state. Nothing lands here that isn't already a thing.
enum ComingUp {

    /// How far ahead the lane looks. Matches ScheduleIngest.forwardWindow so the
    /// horizon the ingest fills is exactly the horizon the card reads.
    static let window: TimeInterval = ScheduleIngest.forwardWindow

    /// One row of the lane: the thing, the date its urgency is measured against
    /// (event start or reminder due), and whether it's already past due.
    struct Item: Identifiable {
        let thing: Thing
        /// Event start or reminder due date — the moment the row sorts on.
        let date: Date
        /// A reminder due before today. Events are never "overdue" (a meeting
        /// that already happened simply isn't upcoming); only a still-open
        /// reminder can be past its deadline.
        let overdue: Bool
        var id: UUID { thing.id }
    }

    /// The upcoming things, soonest (and most overdue) first. Events from the
    /// start of today through the window; reminders with a due date at or before
    /// the window's end, INCLUDING overdue ones. Cap left to the caller.
    static func items(from things: [Thing], now: Date = .now,
                      calendar: Calendar = .current) -> [Item] {
        let horizon = now.addingTimeInterval(window)
        let todayStart = calendar.startOfDay(for: now)
        var out: [Item] = []
        for t in things {
            switch t.kind {
            case .event:
                // Still-upcoming events through the horizon. A timed event that
                // already passed today isn't "coming up", so it's excluded — but
                // an all-day event today still is, and its start is midnight
                // (before `now`), so it's admitted by the midnight-start test.
                // (Only the start is stored, so all-day is inferred from it.)
                let start = t.capturedAt
                guard start <= horizon else { continue }
                let allDayToday = calendar.isDateInToday(start)
                    && start == calendar.startOfDay(for: start)
                guard start >= now || allDayToday else { continue }
                out.append(Item(thing: t, date: start, overdue: false))
            case .reminder:
                // No due date → not a deadline, so it can't be "coming up".
                // Overdue reminders lead, but only recently overdue ones: a
                // still-open reminder due months ago is stale, and a pile of
                // them would fill the card (`prefix(5)`) and bury today's real
                // items. Bound the lookback to the same week the lane looks
                // ahead — a symmetric ±window around now.
                guard let due = t.dueAt,
                      due <= horizon,
                      due >= now.addingTimeInterval(-window) else { continue }
                out.append(Item(thing: t, date: due, overdue: due < todayStart))
            default:
                continue
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// The short right-aligned label a row wears — the WHEN, in the fewest
    /// words: "Overdue", "Today", "Tomorrow", else the weekday ("Thursday").
    static func label(for item: Item, now: Date = .now,
                      calendar: Calendar = .current) -> String {
        if item.overdue { return String(localized: "Overdue") }
        if calendar.isDateInToday(item.date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(item.date) { return String(localized: "Tomorrow") }
        return item.date.formatted(.dateTime.weekday(.wide))
    }
}
