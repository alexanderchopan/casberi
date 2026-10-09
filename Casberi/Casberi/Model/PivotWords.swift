import Foundation

/// GENERATIVE SEARCH, v1 (prd §1209): words become a page, with no model.
///
/// What you type is resolved on the phone into the things a page can be made
/// of — a person, an app, a category, a stretch of time, or plain words —
/// and the page is composed by rules over what you already keep (`PivotPage`).
/// Nothing here guesses: a name resolves only to something the app holds, a
/// time phrase only to a calendar span, and anything left over is matched as
/// words. Foundation-only, so the rules are testable whole
/// (`CasberiTests/PivotWordsTests`).
struct PivotQuery: Identifiable, Hashable, Sendable {
    enum Subject: Hashable, Sendable {
        /// A person in Addresses, by the index's id.
        case person(id: String, name: String)
        /// An app or service, by its catalogue name.
        case app(String)
        /// A dock category.
        case category(String)
        /// Words, matched in titles, senders and handles.
        case words(String)
        /// Nothing but the time span.
        case span
    }

    var subject: Subject
    /// A stretch of time the page is narrowed to, and how it was said.
    var span: DateInterval? = nil
    var spanLabel: String? = nil

    var id: String {
        let s: String = switch subject {
        case .person(let id, _): "person:" + id
        case .app(let name): "app:" + name
        case .category(let name): "cat:" + name
        case .words(let w): "words:" + w.lowercased()
        case .span: "span"
        }
        return s + "|" + (spanLabel ?? "")
    }

    /// The page's title: the subject, else the span.
    var title: String {
        switch subject {
        case .person(_, let name): name
        case .app(let name): name
        case .category(let name): name
        case .words(let w): "“\(w)”"
        case .span: spanLabel ?? ""
        }
    }

    /// The pick the title wears after its dot, when both are set.
    var pick: String? {
        if case .span = subject { return nil }
        return spanLabel
    }
}

enum PivotWords {

    /// A time phrase found in the words: the span, how to say it, and the
    /// words with the phrase taken out.
    struct Found: Equatable {
        let span: DateInterval
        let label: String
        let rest: String
    }

    /// The phrases understood, longest first so "last week" wins over "week".
    /// English only in v1; anything else stays words.
    static func timeSpan(in words: String, now: Date = .now,
                         calendar: Calendar = .current) -> Found? {
        let folded = words.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = calendar
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today) ?? today }
        func span(_ unit: Calendar.Component, offset: Int) -> DateInterval? {
            guard let base = cal.date(byAdding: unit, value: offset, to: now),
                  let interval = cal.dateInterval(of: unit, for: base) else { return nil }
            return interval
        }
        var table: [(String, String, () -> DateInterval?)] = [
            ("this week", String(localized: "This week"), { span(.weekOfYear, offset: 0) }),
            ("last week", String(localized: "Last week"), { span(.weekOfYear, offset: -1) }),
            ("next week", String(localized: "Next week"), { span(.weekOfYear, offset: 1) }),
            ("this month", String(localized: "This month"), { span(.month, offset: 0) }),
            ("last month", String(localized: "Last month"), { span(.month, offset: -1) }),
            ("next month", String(localized: "Next month"), { span(.month, offset: 1) }),
            ("this year", String(localized: "This year"), { span(.year, offset: 0) }),
            ("last year", String(localized: "Last year"), { span(.year, offset: -1) }),
            ("yesterday", String(localized: "Yesterday"), { DateInterval(start: day(-1), end: day(0)) }),
            ("today", String(localized: "Today"), { DateInterval(start: day(0), end: day(1)) }),
            ("tomorrow", String(localized: "Tomorrow"), { DateInterval(start: day(1), end: day(2)) }),
        ]
        // A month by name: this year's, or last year's when it has not come yet.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let thisYear = cal.component(.year, from: now)
        let thisMonth = cal.component(.month, from: now)
        for (i, name) in formatter.monthSymbols.enumerated() {
            let month = i + 1
            let year = month > thisMonth ? thisYear - 1 : thisYear
            let label = name
            table.append((name.lowercased(), label, {
                guard let start = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
                return cal.dateInterval(of: .month, for: start)
            }))
        }
        for (phrase, label, make) in table.sorted(by: { $0.0.count > $1.0.count }) {
            guard let range = wordRange(of: phrase, in: folded), let span = make() else { continue }
            var rest = folded
            rest.removeSubrange(range)
            rest = rest.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for joiner in ["in", "from", "on", "during"] where rest.hasSuffix(" " + joiner) || rest == joiner {
                rest = String(rest.dropLast(joiner.count)).trimmingCharacters(in: .whitespaces)
            }
            return Found(span: span, label: label, rest: rest)
        }
        return nil
    }

    /// The range of `phrase` in `text` on word boundaries ("may" in "maybe"
    /// is not May).
    static func wordRange(of phrase: String, in text: String) -> Range<String.Index>? {
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: phrase, range: search) {
            let before = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter
            let after = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if before && after { return r }
            search = r.upperBound..<text.endIndex
        }
        return nil
    }

    /// Whether a thing's date falls in the span: an event by when it is,
    /// anything else by when it came.
    static func inSpan(_ span: DateInterval?, captured: Date, due: Date?) -> Bool {
        guard let span else { return true }
        return span.contains(due ?? captured)
    }

    /// "3 days ago", "Today", "In 2 days" — a fact the page states, counted.
    static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return String(localized: "today")
        case -1: return String(localized: "yesterday")
        case 1: return String(localized: "tomorrow")
        case ..<0: return String(localized: "\(-days) days ago")
        default: return String(localized: "in \(days) days")
        }
    }
}

