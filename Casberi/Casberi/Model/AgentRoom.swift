import Foundation

/// THE AGENT ROOMS' HEAD (2026-08-23, prd §457) — how much you actually said,
/// and to which of them.
///
/// ChatGPT, Claude, Gemini and Claude Code are the four rooms in this corpus
/// that hold conversations, and every one of them has led with
/// `FeedInsight.topicMap` — a treemap of subjects with no time in it at all.
/// It is a good card and it answers WHAT. It cannot answer the two questions
/// somebody opening this room actually has, both of which are about shape:
/// how heavily do I lean on this thing, and when did that change.
///
/// ## What an agent room can say that nothing else in this app can
///
/// **Turns.** `messageCount` is stamped by all four importers and is the one
/// number in this corpus that separates a working session from a question —
/// a 300-turn afternoon spent getting a migration right and "what's the CSS
/// for this" are the same row everywhere else in the app. §418 put it on the
/// row; this puts it in the head, where the distribution lives.
///
/// **And the comparison.** A person with two of these seats connected owns a
/// reading none of the four products can make, because each of them can only
/// see itself: which one you actually took your work to, and since when.
///
/// ## MONTHS, not years — the one real departure from `JournalRoom`/`XRoom`
///
/// Those two chart years because a journal or an X archive is a decade deep
/// and a year strip is the honest unit. These rooms are not: ChatGPT's export
/// begins in late 2022 at the very earliest and Claude Code's transcripts
/// begin in 2025, so a year strip for a heavy user draws **three columns** —
/// a chart with no shape in it, over a corpus with plenty. A month strip over
/// the same span draws thirty-odd, which is where the pattern is.
///
/// The invariant travels intact: **silent months are DRAWN, at zero.** The
/// gap is the reading — the fortnight you stopped, the month the project
/// ended — and skipping it rescales the axis into a lie about continuity.
///
/// ## What it costs: nothing
///
/// `capturedAt`, `messageCount`, `ocrTopics`, `tags` and `sourceRef`, all
/// already on a landed row. No request, no new `Thing` property, no CloudKit
/// deploy, no `UserDefaults` — the `JournalRoom`/`XRoom`/`PeerRoom` contract,
/// for its reason: a head that can fail is a head that can fail differently
/// from the rows beneath it.
///
/// ## §349's rule, and how this meets it
///
/// `sourceHead` outranks `FeedInsight.topicMap`, so this card TAKES the slot
/// that says what you talk about. **A head must never draw less than what it
/// displaces**, which is why every month row carries its own SUBJECT, lifted
/// from the same `ocrTopics` terms the treemap ranks. The map says "SwiftUI,
/// CloudKit, the migration" about two years at once; this says which month
/// was which. It is the treemap along time rather than instead of it.
///
/// Foundation-only by design so `scripts/agent-room-selftest.sh` can compile
/// it WHOLE and unmodified — **the only proof these numbers are right**, since
/// no ChatGPT, Claude or Gemini export has ever been held by this project.
/// Everything touching `Thing` lives in `AgentRoomSource`.
struct AgentRoom: Equatable {

    // MARK: - What a row is

    /// One landed conversation, reduced to the facts the head reads.
    struct Sighting: Equatable {
        /// `Thing.sourceRef` — how a tap lands on the real row.
        let ref: String?
        /// The month it happened in, as an ORDINAL: `year * 12 + (month - 1)`.
        ///
        /// The caller owns the conversion, once, against ONE calendar — the
        /// `JournalRoom.Sighting.day` rule, and for its reason: this file is
        /// compiled without a `Calendar` or a time zone in it, and handing it
        /// a `Date` would drag both in. The encoding is fixed rather than
        /// opaque (unlike that day ordinal) because the card has to LABEL a
        /// month, and inverting `year * 12 + (month - 1)` is integer
        /// arithmetic this file can do and a harness can check — see
        /// `year(ofMonth:)`.
        let month: Int
        /// The day it happened on, as an ordinal — opaque, used only for
        /// distinct-day counting and the span floor.
        ///
        /// It is here and not derived from `month` because a span measured in
        /// calendar months can be doubled by an accident of the calendar
        /// (§398's lesson, which cost that room a `minimumSpanDays` beside its
        /// year count), and because "how many days did I use this" is a real
        /// reading that a month bucket cannot produce.
        let day: Int
        /// Turns, from `Thing.messageCount`.
        ///
        /// **Optional, and nil is not zero.** A row landed before its importer
        /// stamped a count has an unknown length, not a length of nothing —
        /// so it is counted as a conversation and excluded from every turn
        /// figure, which is what `counted` exists to make sayable.
        let turns: Int?
        /// The conversation's own topic terms (`Thing.ocrTopics`), already
        /// normalised by `ScreenshotTopics`. Empty until that sweep has run,
        /// which is the common state right after an import — so every subject
        /// here is optional and the card draws without one.
        let terms: [String]
        /// The row's title, for the longest-conversation clause. Never used
        /// for matching or ranking, only for naming the one row that wins.
        let title: String
    }

    /// Another agent seat's standing, for the comparison — the only part of
    /// this card that reads outside its own room.
    struct Rival: Equatable {
        /// The seat's display name, as the catalog spells it.
        let name: String
        /// Conversations per month ordinal. Counts ONLY — see `leadSince`.
        let months: [Int: Int]

        var total: Int { months.values.reduce(0, +) }
    }

    // MARK: - The shape

    /// One month of the strip. `conversations == 0` is a real, drawn month.
    struct Month: Identifiable, Equatable {
        /// The ordinal (see `Sighting.month`).
        let month: Int
        let conversations: Int
        /// Turns across the conversations in this month that carried a count.
        let turns: Int
        /// The term that recurs most that month, or nil when the topic sweep
        /// hasn't reached it or nothing recurred.
        let subject: String?
        /// That month's newest conversation, for the tap.
        let newestRef: String?

        var id: Int { month }
        /// The calendar year, inverted from the ordinal.
        var year: Int { AgentRoom.year(ofMonth: month) }
        /// 1…12.
        var monthOfYear: Int { AgentRoom.monthOfYear(month) }
    }

    /// The deepest single conversation in the room.
    struct Longest: Equatable {
        let title: String
        let turns: Int
        let ref: String?
        let month: Int
    }

    /// Oldest → newest, gaps included.
    let months: [Month]
    /// Conversations counted.
    let total: Int
    /// Turns across every conversation that carried a count.
    let turns: Int
    /// How many conversations that figure was computed over. Equal to `total`
    /// on a fully-stamped room and smaller on one holding rows from an older
    /// build — which is the difference between "you said this much" and "you
    /// said this much, that we can see", and the card says so when they differ.
    let counted: Int
    /// The month with the most conversations. Ties go to the EARLIER month, so
    /// the answer is total and cannot reshuffle between two identical opens.
    let busiest: Month
    /// The deepest conversation, or nil when nothing carried a usable count.
    let longest: Longest?
    /// Months inside the span with nothing in them.
    let silent: Int
    /// Distinct days used across the whole span.
    let days: Int
    /// The other agent seats that have anything in them, richest first.
    let rivals: [Rival]
    /// The earliest month from which this room has held more conversations
    /// than its strongest rival, counting from there to the end of the span —
    /// or nil when it has never led. See `leadSince`.
    let leadSince: Int?
    /// The rival that comparison was made against, if any.
    let rival: Rival?

    var span: Int { months.count }
    var isEmpty: Bool { months.isEmpty }

    // MARK: - Month arithmetic

    /// `year * 12 + (month - 1)` → the year.
    ///
    /// Integer division, so this is only correct for the positive ordinals a
    /// real calendar year produces. That is not a limitation worth guarding:
    /// a conversation dated before year 0 is a corrupt row, and the card would
    /// have larger problems than its axis label.
    static func year(ofMonth ordinal: Int) -> Int { ordinal / 12 }

    /// …and the month within it, 1…12.
    static func monthOfYear(_ ordinal: Int) -> Int { ordinal % 12 + 1 }

    // MARK: - Composition

    /// Conversations the room must hold. Twelve, matching `JournalRoom` — a
    /// handful of chats is a room you are still filling, and a strip over it
    /// is mostly gaps.
    static let minimumConversations = 12
    /// Months the conversations must touch.
    static let minimumMonths = 2
    /// …and days between the first and the last, because two calendar months
    /// is also what a fortnight across the 31st has (§398's floor, which is in
    /// days for exactly this reason).
    static let minimumSpanDays = 45
    /// The card draws at most this many month ROWS under the strip. The strip
    /// itself is never capped — it is the span, and a truncated span is a lie
    /// about when you started.
    static let rowCap = 3

    /// The head, or nil when this room has no shape to show.
    ///
    /// `rivals` is supplied rather than fetched: this type is compiled without
    /// a store, and the source is the one place that knows which other seats
    /// exist and which of them is this room (a room is never its own rival).
    static func compose(_ sightings: [Sighting],
                        rivals: [Rival] = []) -> AgentRoom? {
        guard sightings.count >= minimumConversations else { return nil }

        var counts: [Int: Int] = [:]
        var turnsByMonth: [Int: Int] = [:]
        var terms: [Int: [String: Int]] = [:]
        var newest: [Int: (ref: String?, day: Int)] = [:]
        var allDays: Set<Int> = []
        var totalTurns = 0
        var counted = 0
        var longest: Longest?

        for sight in sightings {
            counts[sight.month, default: 0] += 1
            allDays.insert(sight.day)
            // A turn count of zero is a conversation we read and found empty,
            // which is a real answer; nil is one we never counted. Only the
            // second is excluded — see `Sighting.turns`.
            if let turns = sight.turns {
                totalTurns += turns
                counted += 1
                turnsByMonth[sight.month, default: 0] += turns
                // STRICTLY greater, so the first conversation to reach a depth
                // keeps the title — two sessions of equal length must not swap
                // the headline between opens.
                if turns > (longest?.turns ?? Int.min) {
                    longest = Longest(title: sight.title, turns: turns,
                                      ref: sight.ref, month: sight.month)
                }
            }
            for term in sight.terms {
                let key = term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                terms[sight.month, default: [:]][key, default: 0] += 1
            }
            if sight.day > (newest[sight.month]?.day ?? Int.min) {
                newest[sight.month] = (sight.ref, sight.day)
            }
        }

        guard counts.count >= minimumMonths,
              let first = counts.keys.min(), let last = counts.keys.max(),
              let firstDay = allDays.min(), let lastDay = allDays.max(),
              lastDay - firstDay >= minimumSpanDays
        else { return nil }

        var months: [Month] = []
        for ordinal in first...last {
            let conversations = counts[ordinal] ?? 0
            months.append(Month(month: ordinal,
                                conversations: conversations,
                                turns: turnsByMonth[ordinal] ?? 0,
                                subject: subject(terms[ordinal] ?? [:],
                                                 conversations: conversations),
                                newestRef: newest[ordinal]?.ref))
        }
        // Value desc, then MONTH ASC — a total order, so the card names the
        // same month every time it is composed over the same rows.
        guard let busiest = months.max(by: {
            ($0.conversations, $1.month) < ($1.conversations, $0.month)
        }) else { return nil }

        // A conversation with no depth we could read cannot be "the longest".
        if (longest?.turns ?? 0) < 2 { longest = nil }

        let ranked = rivals
            .filter { $0.total > 0 }
            .sorted { ($0.total, $1.name) > ($1.total, $0.name) }
        let strongest = ranked.first
        let lead = strongest.flatMap { leadSince(counts, over: $0.months, through: last) }

        return AgentRoom(months: months,
                         total: sightings.count,
                         turns: totalTurns,
                         counted: counted,
                         busiest: busiest,
                         longest: longest,
                         silent: months.filter { $0.conversations == 0 }.count,
                         days: allDays.count,
                         rivals: ranked,
                         leadSince: lead,
                         rival: strongest)
    }

    /// The earliest month from which this room has held more conversations
    /// than `other`, counting every month from there through `last`.
    ///
    /// **Walked backwards from the end and NOT month-by-month**, and the
    /// difference is the whole honesty of the claim. A per-month "who won"
    /// comparison flips on a quiet fortnight, so the card would announce a
    /// change of allegiance every time somebody took a week off. This asks a
    /// question with one answer: over the whole stretch from here to now, is
    /// this room ahead? The earliest month for which that is true is the
    /// point the lead really began.
    ///
    /// Ties do NOT count as leading. "More than" means more than.
    ///
    /// **Conversations only, never turns** — see `comparison`.
    static func leadSince(_ mine: [Int: Int], over theirs: [Int: Int],
                          through last: Int) -> Int? {
        let earliest = min(mine.keys.min() ?? last, theirs.keys.min() ?? last)
        guard earliest <= last else { return nil }
        var mineRunning = 0
        var theirsRunning = 0
        var answer: Int?
        var ordinal = last
        while ordinal >= earliest {
            mineRunning += mine[ordinal] ?? 0
            theirsRunning += theirs[ordinal] ?? 0
            if mineRunning > theirsRunning { answer = ordinal }
            ordinal -= 1
        }
        return answer
    }

    /// A month's subject: its most common term, and only when the term RECURS.
    ///
    /// The floor is two mentions or a tenth of the month's conversations,
    /// whichever is larger — `FeedInsight.topicMap`'s recurrence rule in
    /// miniature, and it exists for that card's reason: one conversation
    /// mentioning Postgres does not make Postgres what the month was about.
    /// Ties break alphabetically so the answer is deterministic. Nil is normal
    /// and the card is built for it.
    static func subject(_ terms: [String: Int], conversations: Int) -> String? {
        let floor = max(2, conversations / 10)
        let top = terms
            .filter { $0.value >= floor }
            .max(by: { ($0.value, $1.key) < ($1.value, $0.key) })
        return top?.key
    }

    // MARK: - Words

    /// The headline: the deepest conversation in the room, or nothing.
    ///
    /// It leads because it is the fact no other room in this app could produce
    /// and no part of this drawing states — the strip is conversations per
    /// month, and one enormous session is a single tick in it. It is also the
    /// honest superlative here, unlike `XRoom`'s refusal to call anything
    /// "biggest" on like counts frozen at export time: `messageCount` is what
    /// the importer really counted, and a re-import updates it.
    ///
    /// Nil below `longestFloor`, because "your longest conversation ran 3
    /// turns" is the app straining to find you a superlative. The card leads
    /// with `note` instead — the branch §451/§452 left every other room with.
    static let longestFloor = 20

    static func headline(_ room: AgentRoom) -> String? {
        guard let longest = room.longest, longest.turns >= longestFloor else { return nil }
        return String(localized: "Your longest ran \(longest.turns.formatted()) turns")
    }

    /// What the strip cannot say for itself: how many, how deep, over how long.
    ///
    /// Conversations AND turns, never one standing in for the other — they are
    /// different questions ("how often did I come here" against "how much did
    /// I actually work through"), and a room of four hundred one-line
    /// questions and a room of forty long sessions are the same strip.
    ///
    /// The turn figure is withheld entirely when nothing carried a count,
    /// rather than printed as zero.
    static func note(_ room: AgentRoom) -> String {
        let conversations = room.total.formatted()
        guard room.counted > 0 else {
            return String(localized: "\(conversations) conversations on \(room.days.formatted()) days")
        }
        // A partial count says so. Reporting 12,000 turns "across 400
        // conversations" when 90 of them were never counted is a figure
        // attached to a denominator it wasn't measured over.
        if room.counted < room.total {
            return String(localized: "\(conversations) conversations · \(room.turns.formatted()) turns across \(room.counted.formatted()) of them")
        }
        return String(localized: "\(conversations) conversations · \(room.turns.formatted()) turns on \(room.days.formatted()) days")
    }

    /// The cross-assistant line, or nil.
    ///
    /// **CONVERSATIONS ONLY. Turns are never compared across seats**, and that
    /// is not caution, it is the §247 no-summing rule in the place it would do
    /// the most damage: a Claude Code session runs to hundreds of turns
    /// because an agent narrates its own tool use, and a Gemini row is one
    /// prompt by construction. Ranking those by turns would report the tool
    /// with the chattiest transcript format as the one you rely on — a wrong
    /// answer that renders perfectly and reads as insight.
    ///
    /// A conversation is a conversation in all four, so counting them is fair.
    ///
    /// Three states, and the third is the one worth having: leading from the
    /// start of the span is stated without a date (naming the first month
    /// implies something changed then, when nothing did), leading from a month
    /// inside it names that month, and not leading at all says so plainly
    /// rather than going quiet — a card that only ever speaks when you are
    /// winning is a scoreboard, not a reading.
    static func comparison(_ room: AgentRoom) -> String? {
        guard let rival = room.rival, let first = room.months.first?.month else { return nil }
        guard let since = room.leadSince else {
            return String(localized: "\(rival.name) still holds more — \(rival.total.formatted()) to \(room.total.formatted())")
        }
        guard since > first else {
            return String(localized: "More of your conversations are here than in \(rival.name)")
        }
        return String(localized: "More of your conversations have been here than in \(rival.name) since \(monthLabel(since))")
    }

    /// A month row's own line: what it held, and what it was about when we know.
    static func monthLine(_ month: Month) -> String {
        guard let subject = month.subject else {
            return String(localized: "\(month.conversations.formatted()) conversations")
        }
        return String(localized: "\(month.conversations.formatted()) conversations · mostly \(subject)")
    }

    /// The rows the card draws — busiest first, ties by month ascending,
    /// capped. Silent months are never rows: a bar of nothing under a label is
    /// a row that says "0" in the shape of a finding.
    static func rows(_ room: AgentRoom) -> [Month] {
        room.months
            .filter { $0.conversations > 0 }
            .sorted { ($0.conversations, $1.month) > ($1.conversations, $0.month) }
            .prefix(rowCap)
            .map { $0 }
    }

    /// A bar's share of the busiest month drawn. Zero-safe: a room whose
    /// busiest month is somehow empty draws flat bars rather than dividing by
    /// nothing (the NaN a SwiftUI frame draws as nothing at all).
    static func share(conversations: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(1, Double(conversations) / Double(top))
    }

    /// The months the card had no subject for, said out loud — or nil.
    ///
    /// It exists because a strip whose rows carry no "mostly …" clause has two
    /// causes that look identical: the topic sweep hasn't reached those rows
    /// yet (it runs bounded, on foregrounds), or nothing in that month
    /// recurred often enough to name. The first heals itself and the second
    /// never will, so the card says which rather than leaving somebody to
    /// wonder whether something is broken.
    static func footnote(_ room: AgentRoom) -> String? {
        let drawn = rows(room)
        let unnamed = drawn.filter { $0.subject == nil }.count
        guard unnamed > 0 else { return nil }
        if unnamed == drawn.count {
            return String(localized: "Subjects arrive once the room has been read.")
        }
        return String(localized: "\(unnamed) of these months had no recurring subject.")
    }

    /// "March 2026" for a month ordinal, without a `DateFormatter`.
    ///
    /// Hand-rolled rather than formatted, and the reason is the same one that
    /// keeps this file free of a `Calendar`: a formatter needs a `Date`, a
    /// `Date` needs a time zone, and a time zone here would put a
    /// conversation in a different month from the one the caller bucketed it
    /// into — the two would disagree on exactly the rows that sit near a
    /// boundary. The names are localized individually.
    static func monthLabel(_ ordinal: Int) -> String {
        let name = monthName(monthOfYear(ordinal))
        return String(localized: "\(name) \(String(year(ofMonth: ordinal)))")
    }

    static func monthName(_ month: Int) -> String {
        switch month {
        case 1:  return String(localized: "January")
        case 2:  return String(localized: "February")
        case 3:  return String(localized: "March")
        case 4:  return String(localized: "April")
        case 5:  return String(localized: "May")
        case 6:  return String(localized: "June")
        case 7:  return String(localized: "July")
        case 8:  return String(localized: "August")
        case 9:  return String(localized: "September")
        case 10: return String(localized: "October")
        case 11: return String(localized: "November")
        case 12: return String(localized: "December")
        default: return ""
        }
    }
}
