import Foundation

/// Relative-date words in an ask ("what landed today", "links from last
/// week", "what's on thursday") become a real date range, so the answer
/// path can filter by WHEN instead of scoring "thursday" as a text term.
enum DateQuery {

    struct Match {
        let range: ClosedRange<Date>
        /// The words that named the range — strip them from term scoring.
        let words: Set<String>
    }

    /// The first date phrase found in the query, if any.
    static func match(in query: String, now: Date = .now,
                      calendar: Calendar = .current) -> Match? {
        let q = query.lowercased()
        func day(_ offset: Int) -> ClosedRange<Date> {
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: now)!)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
            return start...end
        }

        if q.contains("yesterday") { return Match(range: day(-1), words: ["yesterday"]) }
        if q.contains("today") { return Match(range: day(0), words: ["today"]) }
        if q.contains("last week") {
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let start = calendar.date(byAdding: .day, value: -7, to: thisWeekStart)!
            return Match(range: start...thisWeekStart.addingTimeInterval(-1),
                         words: ["last", "week"])
        }
        if q.contains("weekend") {
            // The most recent Saturday–Sunday (including one in progress).
            let today = calendar.component(.weekday, from: now)   // 1=Sun…7=Sat
            let satBack = today == 7 ? 0 : today % 7   // Sun(1)→1, Mon(2)→2, …, Sat(7)→0
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -satBack, to: now)!)
            let end = calendar.date(byAdding: .day, value: 2, to: start)!.addingTimeInterval(-1)
            return Match(range: start...end, words: ["weekend", "this", "the", "last"])
        }
        if q.contains("week") {
            // Any remaining "week" phrase means the current one — "last week"
            // and "weekend" already matched and returned above. Bare
            // `.contains("week")` (not "this week"/"the week" only) matters
            // because the built-in Siri/Spotlight shortcut literally asks
            // "What's my week" — that phrase silently missed this filter
            // before, so "week" fell through as a plain search term and a
            // Calendar event whose title never says "week" scored zero and
            // never showed (2026-07-09).
            let week = calendar.dateInterval(of: .weekOfYear, for: now)!
            return Match(range: week.start...week.end.addingTimeInterval(-1),
                         words: ["this", "the", "my", "week"])
        }
        if q.contains("this month") {
            let month = calendar.dateInterval(of: .month, for: now)!
            return Match(range: month.start...month.end.addingTimeInterval(-1),
                         words: ["this", "month"])
        }

        // A weekday name means the MOST RECENT one (including today) — asks
        // look back at what landed; the calendar owns the future.
        let symbols = calendar.weekdaySymbols.map { $0.lowercased() }   // sunday…
        for (i, name) in symbols.enumerated() {
            guard q.contains(name) else { continue }
            let target = i + 1   // Calendar weekday units are 1-based
            let today = calendar.component(.weekday, from: now)
            let back = (today - target + 7) % 7   // 0 = that name IS today
            return Match(range: day(-back), words: [name])
        }
        return nil
    }
}
