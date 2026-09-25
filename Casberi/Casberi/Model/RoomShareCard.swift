import Foundation

/// A room's own share card (docs/social-spec.md section 6, item 3): a week on
/// GitHub, a streak on Duolingo — a figure the room can stand behind, drawn
/// by the same `ShareCardView` a thing's card is, reached by one door row
/// under the room's tiles.
///
/// Every figure here is READ, never estimated (§83): GitHub's week is the
/// contribution calendar GitHub itself serves, a Duolingo streak is the
/// profile's own number, and when that profile cannot be read the card says
/// what the room holds instead — XP this week, off the rows — rather than a
/// streak it guessed.
enum RoomShareCard {

    /// What the door hands the tray: the room's name and the rows' bare
    /// facts, copied out on the tap so the sheet never holds a `Thing`.
    struct Input: Identifiable, Hashable {
        let source: String
        /// (when, title) per row, newest first.
        let rows: [Row]
        var id: String { source }

        struct Row: Hashable {
            let at: Date
            let title: String
        }
    }

    /// The rooms that offer a card, and the door's word for each.
    static func doorLabel(source: String) -> String? {
        switch source {
        case "GitHub":   return "Share this week"
        case "Duolingo": return "Share your streak"
        default:         return nil
        }
    }

    /// The card. nil when the room cannot honestly draw one.
    @MainActor
    static func model(_ input: Input, now: Date = .now) async -> ShareCard.Model? {
        switch input.source {
        case "GitHub":   return await gitHubWeek(input, now: now)
        case "Duolingo": return await duolingoStreak(input, now: now)
        default:         return nil
        }
    }

    // MARK: GitHub

    /// GitHub's own contribution calendar when the store holds one; else
    /// what the room holds — the rows that landed this week — under a
    /// caption that says which of the two it is. Never a contribution count
    /// the app did not read.
    @MainActor
    private static func gitHubWeek(_ input: Input, now: Date) async -> ShareCard.Model? {
        await GitHubGraphStore.shared.refreshIfStale()
        let name = BridgeCatalog.seatName(forSource: "GitHub")
        if let year = GitHubGraphStore.shared.year {
            let counts = lastSevenDays(of: year, now: now)
            if counts.count == 7 {
                return ShareCard.Model(source: "GitHub", sourceName: name, author: nil,
                                       day: weekRange(now: now), title: "", words: "",
                                       link: nil, artURL: nil, faceURL: nil,
                                       figure: String(counts.reduce(0, +)),
                                       caption: String(localized: "contributions this week"),
                                       bars: counts)
            }
        }
        let landed = perDay(input.rows, now: now) { _ in 1 }
        let total = landed.reduce(0, +)
        guard total > 0 else { return nil }
        return ShareCard.Model(source: "GitHub", sourceName: name, author: nil,
                               day: weekRange(now: now), title: "", words: "",
                               link: nil, artURL: nil, faceURL: nil,
                               figure: String(total),
                               caption: String(localized: "landed from GitHub this week"),
                               bars: landed)
    }

    /// The last seven days of the calendar, today last. A day carries its
    /// date when GitHub served it; the synthetic demo year does not, so the
    /// position in the grid stands in — the grid's last column is this week,
    /// and today's offset in it is the same arithmetic `ContributionYear.from`
    /// laid it out with.
    static func lastSevenDays(of year: ContributionYear, now: Date,
                              calendar: Calendar = .current) -> [Int] {
        let days = year.weeks.flatMap(\.days)
        guard !days.isEmpty else { return [] }
        if days.contains(where: { $0.date != nil }) {
            let start = calendar.startOfDay(for: now)
            var out = [Int](repeating: 0, count: 7)
            for day in days {
                guard let date = day.date else { continue }
                let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: start).day ?? -1
                if back >= 0 && back < 7 { out[6 - back] = day.count }
            }
            return out
        }
        let weekday = calendar.component(.weekday, from: now)
        let offsetIntoWeek = (weekday - calendar.firstWeekday + 7) % 7
        let todayIndex = min(days.count - 1, (year.weeks.count - 1) * 7 + offsetIntoWeek)
        let from = max(0, todayIndex - 6)
        return Array(days[from...todayIndex].map(\.count))
    }

    /// "Sep 18 – 24", the seven days the card counts.
    static func weekRange(now: Date, calendar: Calendar = .current) -> String {
        let start = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        let f = DateIntervalFormatter()
        f.calendar = calendar
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: start, to: now)
    }

    // MARK: Duolingo

    @MainActor
    private static func duolingoStreak(_ input: Input, now: Date) async -> ShareCard.Model? {
        let xp = xpPerDay(input.rows, now: now)
        let weekXP = xp.reduce(0, +)
        let (profile, _) = await DuolingoLive.profile()
        // The course: the profile's, the remembered one, else the one the
        // rows themselves name ("38 XP in Spanish").
        let course = profile?.course ?? DuolingoLiveAuth.course ?? courseNamed(in: input.rows)
        let name = BridgeCatalog.seatName(forSource: "Duolingo")
        if let profile, profile.streak > 0 {
            let caption = course.map { String(localized: "day streak · \($0)") }
                          ?? String(localized: "day streak")
            return ShareCard.Model(source: "Duolingo", sourceName: name, author: nil,
                                   day: weekRange(now: now), title: "",
                                   words: weekXP > 0 ? String(localized: "\(weekXP) XP this week") : "",
                                   link: nil, artURL: nil, faceURL: nil,
                                   figure: String(profile.streak), caption: caption,
                                   bars: weekXP > 0 ? xp : nil)
        }
        // No readable profile: the rows' own XP is the figure, and no streak
        // is claimed.
        guard weekXP > 0 else { return nil }
        let caption = course.map { String(localized: "XP this week · \($0)") }
                      ?? String(localized: "XP this week")
        return ShareCard.Model(source: "Duolingo", sourceName: name, author: nil,
                               day: weekRange(now: now), title: "", words: "",
                               link: nil, artURL: nil, faceURL: nil,
                               figure: String(weekXP), caption: caption, bars: xp)
    }

    /// XP per day for the last seven days, today last, read off the rows'
    /// titles ("38 XP in Spanish" — `DuolingoDay` writes the number first).
    static func xpPerDay(_ rows: [Input.Row], now: Date, calendar: Calendar = .current) -> [Int] {
        perDay(rows, now: now, calendar: calendar) { leadingInt($0.title) }
    }

    /// A value per day for the last seven days, today last; a row outside
    /// the week, or one `value` declines, counts nothing.
    static func perDay(_ rows: [Input.Row], now: Date, calendar: Calendar = .current,
                       value: (Input.Row) -> Int?) -> [Int] {
        var out = [Int](repeating: 0, count: 7)
        let start = calendar.startOfDay(for: now)
        for row in rows {
            let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: row.at), to: start).day ?? -1
            guard back >= 0 && back < 7, let v = value(row) else { continue }
            out[6 - back] += v
        }
        return out
    }

    /// The language a row's title names after " in ", if every titled row
    /// agrees on one.
    static func courseNamed(in rows: [Input.Row]) -> String? {
        let names = Set(rows.compactMap { row -> String? in
            guard let range = row.title.range(of: " in ") else { return nil }
            let name = row.title[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        })
        return names.count == 1 ? names.first : nil
    }

    private static func leadingInt(_ s: String) -> Int? {
        let digits = s.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
