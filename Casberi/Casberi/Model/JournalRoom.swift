import Foundation

/// THE JOURNAL ROOMS' HEAD (2026-08-17, prd §398) — the years you kept it.
///
/// Day One and Apple Journal have led with `FeedHeatmap`'s "Your journaling
/// year" since the day they shipped: a trailing-twelve-month grid, over a
/// corpus whose entire point is that it goes back further than that. For a
/// journal kept since 2019 the grid charts the last year and says nothing at
/// all about the other five — and for one kept and then stopped, it is an empty
/// square over a decade of entries. The heatmap answers WHEN, which this file's
/// neighbours already call the weakest lead a room can have, and here it
/// answers it about the wrong window.
///
/// ## What a journal can say that nothing else in this app can
///
/// Every other room in the corpus is a record of things that ARRIVED — posts
/// read, links saved, money moved. A journal is a record of showing up, so its
/// three real facts are the span, the days, and the run: how long you have kept
/// it, how many days you actually wrote on, and the longest stretch you did it
/// without missing. None of those is derivable from a twelve-month grid, and
/// the run in particular is the one number a person who journals would
/// recognise instantly as theirs.
///
/// ## What it costs: nothing
///
/// `capturedAt`, `ocrTopics` and `sourceRef`, all already on a landed row. No
/// request, no new `Thing` property, no CloudKit deploy, no `UserDefaults` —
/// the `XRoom`/`PeerRoom`/`StripeRoom` contract, for its reason: a head that
/// can fail is a head that can fail differently from the rows beneath it.
///
/// ## Why it may displace the topic map, and the rule it had to meet
///
/// `sourceHead` outranks `FeedInsight.topicMap`, which the same pass gave these
/// rooms — so this card takes a slot that would otherwise say what the person
/// writes about. §349's rule applies: **a head must never draw less than what
/// it displaces.** That is why every year row carries its own SUBJECT, lifted
/// from the same `ocrTopics` terms the treemap ranks. The map says "Berlin,
/// running, the move" about eight years at once; this says which year was
/// which. It is the treemap along time rather than instead of it.
///
/// ## Obsidian is deliberately NOT one of these rooms
///
/// A vault note's `capturedAt` is the FILE'S MTIME (`ObsidianIngest` uses it as
/// the read watermark), so editing a 2019 note today moves it to today. Years
/// composed over that would be a chart of when files were touched, presented as
/// a chart of when someone wrote — the §83 fake status, in the room where it
/// would look most convincing. Obsidian keeps the treemap it got in §320.
///
/// ## The floors, and why one of them is in DAYS
///
/// Two calendar years is a lower bar than `XRoom`'s three, because a journal is
/// a tenth of an archive's volume and a two-year span is already a real thing
/// to have kept. But two calendar years is also what a six-week journal
/// straddling New Year has, which is why `minimumSpanDays` exists beside it:
/// the honest span is measured in days, and the calendar-year count alone can
/// be doubled by an accident of the calendar.
///
/// Foundation-only by design so `scripts/journal-room-selftest.sh` can compile
/// it WHOLE and unmodified — the only proof these numbers are right, since no
/// real Day One or Apple Journal export has ever been imported on this host.
/// Everything touching `Thing` lives in `JournalRoomSource`.
struct JournalRoom: Equatable {

    // MARK: - What a row is

    /// One landed entry, reduced to the four facts the head reads.
    struct Sighting: Equatable {
        /// `Thing.sourceRef` — how a tap lands on the real row.
        let ref: String?
        /// The calendar year it was written in, resolved by the caller against
        /// ONE calendar (see `JournalRoomSource.sighting`).
        let year: Int
        /// The day it was written, as an ORDINAL — a day number, not a date.
        ///
        /// Deliberately opaque: the only arithmetic this file does on it is
        /// adjacency (`day + 1`) and set membership, so handing it a `Date`
        /// would drag a calendar and a timezone into the one type that is
        /// compiled without either. The caller owns the conversion, once, for
        /// every row (`XRoomSource`'s one-calendar rule, one field further).
        let day: Int
        /// The entry's own topic terms (`Thing.ocrTopics`), already normalised
        /// by `ScreenshotTopics`. Empty until that sweep has run, which is the
        /// common state right after an import — so every subject here is
        /// optional and the card draws without one.
        let terms: [String]
    }

    // MARK: - The shape

    /// One year of the strip. `entries == 0` is a real, drawn year — see the
    /// type note on `years`.
    struct Year: Identifiable, Equatable {
        let year: Int
        let entries: Int
        /// Distinct days written in that year. Never larger than `entries`, and
        /// smaller whenever somebody wrote twice in a day — which is exactly
        /// the difference "how much you wrote" and "how often" describe, and
        /// the reason both are counted rather than one standing in for both.
        ///
        /// Read by `-journalRoomProbe` and not by the card, deliberately: the
        /// row line is one clamped line and already carries the count and the
        /// subject, so a third number would push the subject off it. It earns
        /// its place here because the probe is the only headless view of this
        /// room, and a year of forty long entries and a year of forty daily
        /// ones are indistinguishable without it.
        let days: Int
        /// The term that recurs most that year, or nil when the topic sweep
        /// hasn't reached it or nothing recurred.
        let subject: String?
        /// That year's newest entry, for the tap. A journal records no
        /// popularity of any kind, so unlike `XRoom` there is nothing to rank
        /// an entry by — the honest landing is simply the last one written.
        let newestRef: String?

        var id: Int { year }
    }

    /// Oldest → newest, gaps included.
    let years: [Year]
    /// Entries counted.
    let total: Int
    /// Distinct days written across the whole span.
    let days: Int
    /// The year with the most entries. Ties go to the EARLIER year, so the card
    /// names the first time you wrote that much rather than the last — and, far
    /// more importantly, so the answer is total and cannot reshuffle between two
    /// identical opens.
    let fullest: Year
    /// Years inside the span with nothing in them.
    let silent: Int
    /// The longest run of CONSECUTIVE days written, in days. 1 when no two
    /// entries were ever a day apart, which is a perfectly ordinary journal.
    let streak: Int
    /// The calendar year the longest run ENDED in, so the headline can place it.
    /// Nil only when there is no run to speak of.
    let streakYear: Int?

    var span: Int { years.count }
    var isEmpty: Bool { years.isEmpty }

    // MARK: - Composition

    /// Calendar years the entries must touch. Two, not `XRoom`'s three: a
    /// journal is a fraction of an archive's volume, and a span of two years is
    /// already the thing this card is about.
    static let minimumYears = 2
    /// …and this many days between the first entry and the last, because two
    /// calendar years is also what six weeks across New Year's Eve has. The
    /// calendar-year count can be doubled by an accident of the calendar; a day
    /// count cannot.
    static let minimumSpanDays = 180
    /// …and this many entries, so a handful of stray rows across a long gap
    /// can't dress itself up as a habit.
    static let minimumEntries = 12
    /// A run shorter than this is not a run — two consecutive days is a weekend,
    /// and a card announcing it as a streak is the app straining to congratulate
    /// somebody. Below it the headline names the fullest year instead.
    static let streakFloor = 3
    /// The card draws at most this many year ROWS under the strip. The strip
    /// itself is never capped — it is the span, and a truncated span is a lie
    /// about when you started.
    static let rowCap = 3

    /// The head, or nil when this journal has no span to show.
    static func compose(_ sightings: [Sighting]) -> JournalRoom? {
        guard sightings.count >= minimumEntries else { return nil }

        var counts: [Int: Int] = [:]
        var daysByYear: [Int: Set<Int>] = [:]
        var terms: [Int: [String: Int]] = [:]
        var newest: [Int: (ref: String?, day: Int)] = [:]
        var allDays: Set<Int> = []
        var yearOfDay: [Int: Int] = [:]
        for sight in sightings {
            counts[sight.year, default: 0] += 1
            daysByYear[sight.year, default: []].insert(sight.day)
            allDays.insert(sight.day)
            // A day can only belong to one year, so a repeated write is a
            // no-op rather than a conflict — but the FIRST writer wins by
            // construction, which keeps the map deterministic across orderings.
            if yearOfDay[sight.day] == nil { yearOfDay[sight.day] = sight.year }
            for term in sight.terms {
                let key = term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                terms[sight.year, default: [:]][key, default: 0] += 1
            }
            // STRICTLY greater, so the first entry to reach a day keeps the
            // tap — two entries written the same day must not swap the target
            // between opens.
            if sight.day > (newest[sight.year]?.day ?? Int.min) {
                newest[sight.year] = (sight.ref, sight.day)
            }
        }
        guard counts.count >= minimumYears,
              let first = counts.keys.min(), let last = counts.keys.max(),
              let firstDay = allDays.min(), let lastDay = allDays.max(),
              lastDay - firstDay >= minimumSpanDays
        else { return nil }

        var years: [Year] = []
        for year in first...last {
            let entries = counts[year] ?? 0
            years.append(Year(year: year,
                              entries: entries,
                              days: daysByYear[year]?.count ?? 0,
                              subject: subject(terms[year] ?? [:], entries: entries),
                              newestRef: newest[year]?.ref))
        }
        // Value desc, then YEAR ASC — a total order, so the headline names the
        // same year every time it is composed over the same rows.
        guard let fullest = years.max(by: { ($0.entries, $1.year) < ($1.entries, $0.year) })
        else { return nil }
        let run = longestRun(allDays)
        return JournalRoom(years: years,
                           total: sightings.count,
                           days: allDays.count,
                           fullest: fullest,
                           silent: years.filter { $0.entries == 0 }.count,
                           streak: run.length,
                           streakYear: run.end.flatMap { yearOfDay[$0] })
    }

    /// The longest stretch of consecutive days in a set of day ordinals, and the
    /// day it ended on.
    ///
    /// Sorted-and-walked rather than a per-day `contains` scan: the set may hold
    /// thousands of days and the walk is linear in what is actually there, not
    /// in the span. Ties keep the EARLIEST run — the same rule as `fullest`, and
    /// for the same reason (a card that names a different year on each open over
    /// unchanged rows reads as broken).
    static func longestRun(_ days: Set<Int>) -> (length: Int, end: Int?) {
        guard !days.isEmpty else { return (0, nil) }
        let sorted = days.sorted()
        var best = 1
        var bestEnd = sorted[0]
        var current = 1
        for i in 1..<sorted.count {
            current = sorted[i] == sorted[i - 1] + 1 ? current + 1 : 1
            if current > best {
                best = current
                bestEnd = sorted[i]
            }
        }
        return (best, bestEnd)
    }

    /// A year's subject: its most common term, and only when the term RECURS.
    ///
    /// The floor is two mentions or a tenth of the year's entries, whichever is
    /// larger — `FeedInsight.topicMap`'s own recurrence rule in miniature, and it
    /// exists for that card's reason: one entry mentioning Lisbon does not make
    /// Lisbon what the year was about, and a card that says it does is §83
    /// wearing a label. Ties break alphabetically so the answer is
    /// deterministic. Nil is normal and the card is built for it.
    static func subject(_ terms: [String: Int], entries: Int) -> String? {
        let floor = max(2, entries / 10)
        let top = terms
            .filter { $0.value >= floor }
            .max(by: { ($0.value, $1.key) < ($1.value, $0.key) })
        return top?.key
    }

    // MARK: - Words

    /// The whole finding as one sentence, and it has two shapes.
    ///
    /// The RUN leads when there is one, because it is the fact a person who
    /// keeps a journal would recognise as theirs and the only one here that no
    /// other room in this app could produce. Below `streakFloor` there is no run
    /// worth naming, and the fullest year leads instead — never the newest,
    /// which is what the rows underneath already show, and a head that restates
    /// the feed is a wasted slot.
    ///
    /// Both years are interpolated as STRINGS, and that is not a style choice:
    /// an `Int` in a localized interpolation is formatted with the locale's
    /// grouping separator, so `2019` renders as "2,019" — a year printed as a
    /// quantity, in the largest type on the card. `XRoom` shipped exactly that
    /// bug and its harness caught it on the first run.
    static func headline(_ room: JournalRoom) -> String {
        if room.streak >= streakFloor, let year = room.streakYear {
            return String(localized: "You wrote \(room.streak.formatted()) days straight in \(String(year))")
        }
        return String(localized: "\(String(room.fullest.year)) was your fullest year — \(room.fullest.entries.formatted()) entries")
    }

    /// What the strip cannot say for itself: how much, how often, and over how
    /// long.
    ///
    /// Entries AND days, never one standing in for the other — they are
    /// different questions ("how much did I write" against "how often did I
    /// show up"), and for a journal the second is the one being kept.
    ///
    /// A span with no silent years says so as a whole number of years rather
    /// than claiming "every year", which would be true of the span and false of
    /// the person for anyone who started in June.
    static func note(_ room: JournalRoom) -> String {
        if room.silent == 0 {
            return String(localized: "\(room.total.formatted()) entries on \(room.days.formatted()) days across \(room.span) years")
        }
        let written = room.span - room.silent
        return String(localized: "\(room.total.formatted()) entries on \(room.days.formatted()) days — you wrote in \(written) of \(room.span) years")
    }

    /// A year row's own line: what it held, and what it was about when we know.
    static func yearLine(_ year: Year) -> String {
        guard let subject = year.subject else {
            return String(localized: "\(year.entries.formatted()) entries")
        }
        return String(localized: "\(year.entries.formatted()) entries · mostly \(subject)")
    }

    /// The rows the card draws — fullest first, ties by year ascending, capped.
    /// Silent years are never rows: a bar of nothing under a label is a row that
    /// says "0" in the shape of a finding.
    static func rows(_ room: JournalRoom) -> [Year] {
        room.years
            .filter { $0.entries > 0 }
            .sorted { ($0.entries, $1.year) > ($1.entries, $0.year) }
            .prefix(rowCap)
            .map { $0 }
    }

    /// A bar's share of the fullest year drawn. Zero-safe: a room whose fullest
    /// year is somehow empty draws flat bars rather than dividing by nothing
    /// (the NaN a SwiftUI frame draws as nothing at all).
    static func share(entries: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(1, Double(entries) / Double(top))
    }

    /// The years the card had no subject for, said out loud — or nil.
    ///
    /// It exists because a strip whose rows carry no "mostly …" clause has two
    /// causes that look identical: the topic sweep hasn't reached those rows yet
    /// (it runs bounded, on foregrounds), or nothing in that year recurred often
    /// enough to name. The first heals itself and the second never will, so the
    /// card says which it is rather than leaving a person to wonder whether
    /// something is broken.
    static func footnote(_ room: JournalRoom) -> String? {
        let drawn = rows(room)
        let unnamed = drawn.filter { $0.subject == nil }.count
        guard unnamed > 0 else { return nil }
        if unnamed == drawn.count {
            return String(localized: "Subjects arrive once the room has been read.")
        }
        return String(localized: "\(unnamed) of these years had no recurring subject.")
    }
}
