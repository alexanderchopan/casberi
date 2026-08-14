import Foundation

/// Relative-date words in an ask ("what landed today", "links from last
/// week", "what's on thursday") become a real date range, so the answer
/// path can filter by WHEN instead of scoring "thursday" as a text term.
enum DateQuery {

    struct Match {
        let range: ClosedRange<Date>
        /// The words that named the range — strip them from term scoring.
        let words: Set<String>
        /// What to CALL this range on screen (2026-08-13) — the composer's
        /// scope chips show every filter the retriever resolved, and a date
        /// filter has to be nameable to be droppable.
        ///
        /// Authored here, at each construction site, rather than derived from
        /// `words`: that is an unordered Set, so "last week" renders as
        /// "week last" about half the time, and a bound's bag carries filler
        /// ("in", "the", "year") that was never in the person's question.
        let label: String
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

        if q.contains("yesterday") {
            return Match(range: day(-1), words: ["yesterday"],
                         label: String(localized: "Yesterday"))
        }
        if q.contains("today") {
            return Match(range: day(0), words: ["today"],
                         label: String(localized: "Today"))
        }
        // "weekend" before "last week": "last weekend" CONTAINS "last week",
        // and matching the wrong phrase handed it the full prior week
        // (review 2026-07-11).
        if q.contains("weekend") {
            // The most recent Saturday–Sunday (including one in progress).
            let today = calendar.component(.weekday, from: now)   // 1=Sun…7=Sat
            let satBack = today == 7 ? 0 : today % 7   // Sun(1)→1, Mon(2)→2, …, Sat(7)→0
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -satBack, to: now)!)
            let end = calendar.date(byAdding: .day, value: 2, to: start)!.addingTimeInterval(-1)
            return Match(range: start...end, words: ["weekend", "this", "the", "last"],
                         label: String(localized: "Weekend"))
        }
        if q.contains("last week") {
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let start = calendar.date(byAdding: .day, value: -7, to: thisWeekStart)!
            return Match(range: start...thisWeekStart.addingTimeInterval(-1),
                         words: ["last", "week"],
                         label: String(localized: "Last week"))
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
                         words: ["this", "the", "my", "week"],
                         label: String(localized: "This week"))
        }
        if q.contains("this month") {
            let month = calendar.dateInterval(of: .month, for: now)!
            return Match(range: month.start...month.end.addingTimeInterval(-1),
                         words: ["this", "month"],
                         label: String(localized: "This month"))
        }

        // A weekday name means the MOST RECENT one (including today) — asks
        // look back at what landed; the calendar owns the future.
        let symbols = calendar.weekdaySymbols.map { $0.lowercased() }   // sunday…
        for (i, name) in symbols.enumerated() {
            guard q.contains(name) else { continue }
            let target = i + 1   // Calendar weekday units are 1-based
            let today = calendar.component(.weekday, from: now)
            let back = (today - target + 7) % 7   // 0 = that name IS today
            // `weekdaySymbols` is already the calendar's own localized name,
            // so the chip reads in the reader's language for free.
            return Match(range: day(-back), words: [name],
                         label: calendar.weekdaySymbols[i])
        }

        // A YEAR (2026-08-05, prd §307). Last, after every relative phrase
        // above, because those are more specific and a year can't collide with
        // them.
        //
        // WHY IT WAS MISSING AND WHY IT MATTERS NOW. Every phrase above is
        // relative — today, this week, last Thursday — which is the whole
        // vocabulary a corpus that arrives a few rows at a time ever needs. An
        // IMPORT is the other shape: an X archive lands fifteen years at once,
        // and "what did I post in 2019" is the first question anyone asks it.
        // Without this, "2019" scored as a text term and matched the handful of
        // things that happen to contain that string.
        return yearMatch(in: q, now: now, calendar: calendar)
    }

    /// A year, a bound, or a span. Written as one function because the four
    /// phrasings share their parsing and differ only in which end is open.
    ///
    /// FOUR DIGITS AND PLAUSIBLE, or it isn't a year. An ask can carry all
    /// kinds of numbers — a price, a count, part of a name — and treating any
    /// of them as a date filter would silently empty the answer. The window is
    /// deliberately narrow: below 1990 there is nothing in anyone's corpus, and
    /// one year ahead is as far as a forward-dated thing (a calendar event)
    /// can plausibly sit.
    private static func yearMatch(in q: String, now: Date,
                                  calendar: Calendar) -> Match? {
        let thisYear = calendar.component(.year, from: now)
        let plausible = 1990...(thisYear + 1)

        func start(_ year: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        }
        func end(_ year: Int) -> Date? {
            start(year + 1).map { $0.addingTimeInterval(-1) }
        }

        // Whole words only — a four-digit run inside a longer number or an
        // identifier is not a year somebody typed.
        let words = q.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let years = words.compactMap { word -> Int? in
            guard word.count == 4, let n = Int(word), plausible.contains(n) else { return nil }
            return n
        }
        guard let first = years.first else { return nil }

        // A SPAN needs two years and a joining word, and it reads inclusively
        // at both ends — "between 2015 and 2018" means four years, not three.
        if years.count >= 2, q.contains("between") || q.contains("from") || q.contains(" to ") {
            let second = years[1]
            let lower = min(first, second), upper = max(first, second)
            guard let a = start(lower), let b = end(upper) else { return nil }
            return Match(range: a...b,
                         words: Set(["between", "from", "to", "and",
                                     String(lower), String(upper)]),
                         // Plain digits and an en dash — never `String(localized:)`
                         // with an Int argument, which GROUPS it ("2,015–2,018").
                         // That defect shipped once already in `XRoom`'s headline
                         // (prd §375); a year is a name, not a quantity.
                         label: "\(lower)–\(upper)")
        }

        // A BOUND. "before 2020" is exclusive of 2020 and "after 2015"
        // exclusive of 2015, which is how the words read in English; "since"
        // and "in" are inclusive, which is also how they read. Getting this
        // backwards is a silently-wrong answer, not an error — it just returns
        // a neighbouring year's things.
        let bounding = ["before", "after", "since", "until", "up to", "prior to"]
        let bound = bounding.first { q.contains($0) }
        if let bound {
            // The year as plain digits, so the labels below interpolate a
            // STRING rather than an Int — see the span's note above.
            let year = String(first)
            let bag: Set<String> = [bound, year, "in", "the", "year"]
            switch bound {
            case "before", "until", "up to", "prior to":
                guard let a = start(plausible.lowerBound), let b = start(first) else { return nil }
                return Match(range: a...b.addingTimeInterval(-1), words: bag,
                             label: String(localized: "Before \(year)"))
            default:   // "after", "since"
                let from = bound == "since" ? first : first + 1
                guard let a = start(from), let b = end(plausible.upperBound) else { return nil }
                // The label states the range as RESOLVED, not as typed: "after
                // 2015" is exclusive, so it really means since 2016, and a chip
                // that said "After 2015" beside a result holding nothing from
                // 2015 would read as the filter misfiring.
                return Match(range: a...b, words: bag,
                             label: String(localized: "Since \(String(from))"))
            }
        }

        // A bare year, or "in 2019".
        guard let a = start(first), let b = end(first) else { return nil }
        return Match(range: a...b, words: [String(first), "in", "the", "year"],
                     label: String(first))
    }
}
