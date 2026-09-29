import Foundation

/// The Calendar room's tiles (prd §994): Today · Week · Month · New, under a
/// month grid that stands in the lead box and lights the span the pick shows.
///
/// No All tile (user: "we need a 'new' too, so maybe not 'all'"). The room
/// holds only what is ahead, so Month IS everything, and a fourth scope would
/// be a second name for it.
///
/// The spans ROLL from today rather than follow the calendar's own weeks and
/// months, because the room holds nothing behind today (the 2026-07-29
/// re-ruling): a calendar Week on a Saturday would be one day, and a calendar
/// Month on the 29th two. Week is today and the six days after it; Month is
/// today up to the same date next month.
///
/// New is a VERB, like the Notes and Reminders rooms': it never lights, and
/// its tap opens Calendar, where an event is made. Nothing here writes one.
///
/// Foundation-only, like every scope enum, so a harness can compile it whole;
/// the glyphs are `ScopeTileGlyphs.swift`'s.
enum CalendarScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today, week, month, new

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return String(localized: "Today")
        case .week:  return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .new:   return String(localized: "New")
        }
    }

    /// Read by VoiceOver and the tooltip.
    var summary: String {
        switch self {
        case .today: return String(localized: "What's on today")
        case .week:  return String(localized: "Today and the next six days")
        case .month: return String(localized: "Today and the month ahead")
        case .new:   return String(localized: "Make an event in Calendar")
        }
    }

    /// What the list under the tiles says when the span holds nothing. One
    /// clause (prd §799).
    var emptyLine: String {
        switch self {
        case .today: return String(localized: "Nothing on today.")
        case .week:  return String(localized: "Nothing this week.")
        case .month, .new: return String(localized: "Nothing this month.")
        }
    }

    /// The tiles that SCOPE the list; New is a verb and never stands.
    var isVerb: Bool { self == .new }

    /// The days this scope shows, from the start of today. Nil for the verb.
    func span(now: Date, calendar: Calendar) -> Range<Date>? {
        let today = calendar.startOfDay(for: now)
        let end: Date?
        switch self {
        case .today: end = calendar.date(byAdding: .day, value: 1, to: today)
        case .week:  end = calendar.date(byAdding: .day, value: 7, to: today)
        case .month: end = calendar.date(byAdding: .month, value: 1, to: today)
        case .new:   return nil
        }
        guard let end else { return nil }
        return today..<end
    }

    /// Whether a thing dated `date` stands under this scope. A date before
    /// today is behind every scope — the past sits behind its own door.
    func allows(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let span = span(now: now, calendar: calendar) else { return true }
        return span.contains(date)
    }
}

/// The month grid in the Calendar room's lead (prd §994): six weeks from the
/// start of this one, so today is always in the first row and Month's span —
/// at most 31 days from today — always fits (6 × 7 = 42 ≥ 6 + 31).
enum CalendarGrid {
    static let weeks = 6

    struct Day: Hashable, Sendable {
        let date: Date
        let number: Int
        /// Inside the room's reach: today through the Month span's end. A day
        /// outside it draws faint and never carries a dot — nothing before
        /// today is held, and nothing past the month is fetched.
        let reachable: Bool
        let isToday: Bool
    }

    /// The 42 days, row by row, starting on the locale's first weekday.
    static func days(now: Date, calendar: Calendar) -> [Day] {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -back, to: today),
              let reach = CalendarScope.month.span(now: now, calendar: calendar)
        else { return [] }
        return (0..<(weeks * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return Day(date: date,
                       number: calendar.component(.day, from: date),
                       reachable: reach.contains(date),
                       isToday: date == today)
        }
    }

    /// The weekday letters over the grid, in the grid's order.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The grid's name: the month it opens in, and the next one when the six
    /// weeks cross into it — "September – October". Read off the REACHABLE
    /// days, so a last row that only grazes a third month never names it.
    static func title(_ days: [Day], calendar: Calendar) -> String {
        let reachable = days.filter(\.reachable)
        guard let first = reachable.first?.date, let last = reachable.last?.date else { return "" }
        let format = Date.FormatStyle(calendar: calendar).month(.wide)
        let a = first.formatted(format)
        let b = last.formatted(format)
        return a == b ? a : "\(a) – \(b)"
    }

    /// Which grid cells the pick lights, as runs per row: each run is the
    /// row's first and last lit column. A span that crosses a week draws as
    /// two runs, one ending a row and one starting the next.
    static func runs(_ days: [Day], span: Range<Date>?) -> [Int: ClosedRange<Int>] {
        guard let span else { return [:] }
        var out: [Int: ClosedRange<Int>] = [:]
        for (index, day) in days.enumerated() where span.contains(day.date) {
            let row = index / 7, column = index % 7
            if let run = out[row] {
                out[row] = min(run.lowerBound, column)...max(run.upperBound, column)
            } else {
                out[row] = column...column
            }
        }
        return out
    }
}

/// The days Calendar holds an event on, as EventKit hands them — every
/// occurrence, where the room's rows are one per SERIES (a daily meeting is
/// one row dated its next occurrence, `ScheduleIngest`). The grid's dots read
/// this, so a weekly meeting marks every week it meets rather than only the
/// next (prd §994). Written by the ingest on every refresh, read by the grid.
///
/// Keys are `yyyy-MM-dd` in the calendar they were written with.
enum CalendarBusyDays {
    static let defaultsKey = "calendar.busyDays.v1"

    static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Every day an event covers, from its start through its end, clipped to
    /// `window`. An event ending exactly at midnight (every all-day event)
    /// does not cover the day that midnight begins.
    static func days(of events: [(start: Date, end: Date)], within window: Range<Date>,
                     calendar: Calendar) -> Set<String> {
        var out: Set<String> = []
        for event in events {
            let from = max(event.start, window.lowerBound)
            let last = max(event.start, event.end.addingTimeInterval(-1))
            let to = min(last, window.upperBound.addingTimeInterval(-1))
            guard from <= to else { continue }
            var day = calendar.startOfDay(for: from)
            var guardDays = 0
            while day <= to, guardDays < 400 {
                out.insert(key(day, calendar: calendar))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardDays += 1
            }
        }
        return out
    }

    /// The in-memory copy the grid reads (every reader of a defaults store
    /// reads its cache, `DefaultsWrite`'s note): loaded once, replaced by
    /// the ingest's `remember` on every refresh.
    @MainActor private static var cached: Set<String>?

    @MainActor static var current: Set<String> {
        if let cached { return cached }
        let read = decode(UserDefaults.standard.data(forKey: defaultsKey))
        cached = read
        return read
    }

    @MainActor static func remember(_ days: Set<String>) { cached = days }

    static func encode(_ days: Set<String>) -> Data {
        (try? JSONEncoder().encode(days.sorted())) ?? Data()
    }

    static func decode(_ data: Data?) -> Set<String> {
        guard let data, let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }
}
