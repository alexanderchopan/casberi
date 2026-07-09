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
        if q.contains("this week") || q.contains("the week") {
            let week = calendar.dateInterval(of: .weekOfYear, for: now)!
            return Match(range: week.start...week.end.addingTimeInterval(-1),
                         words: ["this", "the", "week"])
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
            var back = (today - target + 7) % 7
            if back == 0, !q.contains("today") { back = 0 }   // today's name = today
            return Match(range: day(-back), words: [name])
        }
        return nil
    }
}
