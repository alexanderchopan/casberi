import Foundation

/// YOUR YEARS WITH ONE PERSON (2026-08-18, prd §396).
///
/// The reading an X archive can make that X itself cannot. Search on X is
/// scoped to what its index still holds and its own product surfaces a
/// relationship nowhere at all — so "how long have I been talking to this
/// person, and when" has no answer there, while every fact it needs has been
/// sitting in this corpus since the archive landed.
///
/// ## Three ways a person appears in your archive, counted apart
///
/// A REPLY is a post of yours answering one of theirs — the archive states the
/// recipient in `in_reply_to_screen_name` and `landTweets` stamps it on
/// `Thing.parent`. A MENTION is a post of yours that names them without
/// answering them. A LIKED post is one of theirs you kept, which exists only
/// after `fetchFaces` has named its author, because the archive itself names
/// nobody for a like.
///
/// They are never summed into one word. "You replied to @foo 214 times" is a
/// statement about a decade of conversation; folding forty likes into it would
/// make reading look like talking, which is the §83 line about a number that
/// is true arriving under a label that isn't.
///
/// ## Silent years are drawn
///
/// `XRoom`'s ruling, and it matters more here: the gap between 2016 and 2021 is
/// most of what a relationship's shape IS. Skipping empty years would also
/// rescale the axis silently — two bars side by side that are five years apart.
///
/// ## What it may not do
///
/// **No claim about them.** Nothing here counts what they said to you: an
/// archive holds YOUR side and no other, so a "conversation" count would be
/// half a fact wearing a whole one's name. **No colour for more or less** —
/// talking to somebody more in 2016 than in 2022 is not a win and not a
/// failure. And **no rate, no average, no streak**: those are inferences about
/// a relationship, and the user ruling that shaped `AddressConnections` covers
/// this exactly — keep the analysis factual.
///
/// Foundation-only by design, so `scripts/x-selftest.sh` compiles it WHOLE and
/// unmodified — the only proof these numbers are right, since no real X
/// archive has ever been imported on this host and every failure in this card
/// renders as a perfectly good-looking one. Everything touching `Thing` lives
/// in `XPersonSource`.
struct XPerson: Equatable {

    // MARK: - What a row is

    /// One appearance of this person in your archive, reduced to the two facts
    /// the card reads.
    struct Sighting: Equatable {
        enum Kind: Int, Equatable {
            case reply, mention, liked
        }
        /// The calendar year, resolved by the caller against ONE calendar
        /// (see `XPersonSource.sighting`).
        let year: Int
        let kind: Kind
    }

    // MARK: - The shape

    /// One year of the strip. `total == 0` is a real, drawn year.
    struct Year: Identifiable, Equatable {
        let year: Int
        let replies: Int
        let mentions: Int
        let liked: Int

        var total: Int { replies + mentions + liked }
        var id: Int { year }
    }

    /// Oldest → newest, gaps included.
    let years: [Year]
    let replies: Int
    let mentions: Int
    let liked: Int
    /// The busiest year. Ties go to the EARLIER one — so the card names the
    /// first time you talked this much rather than the last, and, far more
    /// importantly, so the answer is total and cannot reshuffle between two
    /// identical opens.
    let busiest: Year

    var total: Int { replies + mentions + liked }
    var span: Int { years.count }
    var silent: Int { years.filter { $0.total == 0 }.count }
    var isEmpty: Bool { years.isEmpty }

    // MARK: - Composition

    /// Below this the rows say it better than a card can. Three is the
    /// smallest number that is a pattern rather than a coincidence, and a
    /// person you answered once does not have years.
    static let minimumSightings = 3

    /// Nil when there is not enough to describe, which is the common case:
    /// most handles in a long archive appear once or twice.
    static func compose(_ sightings: [Sighting]) -> XPerson? {
        guard sightings.count >= minimumSightings else { return nil }
        var replies = 0, mentions = 0, liked = 0
        var byYear: [Int: (r: Int, m: Int, l: Int)] = [:]
        for s in sightings {
            var slot = byYear[s.year] ?? (r: 0, m: 0, l: 0)
            switch s.kind {
            case .reply:   slot.r += 1; replies += 1
            case .mention: slot.m += 1; mentions += 1
            case .liked:   slot.l += 1; liked += 1
            }
            byYear[s.year] = slot
        }
        guard let first = byYear.keys.min(), let last = byYear.keys.max() else { return nil }
        let years = (first...last).map { year -> Year in
            let slot = byYear[year] ?? (r: 0, m: 0, l: 0)
            return Year(year: year, replies: slot.r, mentions: slot.m, liked: slot.l)
        }
        // Total order: count descending, then year ascending. Without the
        // second term two equally busy years race and the card renames its own
        // headline between opens.
        guard let busiest = years.max(by: {
            $0.total != $1.total ? $0.total < $1.total : $0.year > $1.year
        }) else { return nil }
        return XPerson(years: years, replies: replies, mentions: mentions,
                       liked: liked, busiest: busiest)
    }

    // MARK: - What it says

    /// The card's own sentence, and it names WHICH count it is reporting.
    ///
    /// The largest of the three leads, because that is the true shape of the
    /// relationship: somebody you answered two hundred times and somebody
    /// whose posts you liked two hundred times are not the same person to you.
    /// Ties break reply → mention → liked, which is strongest-evidence-first
    /// (a reply is unambiguously a conversation; a like is a tap).
    static func headline(_ person: XPerson, handle: String) -> String {
        let name = "@" + handle
        if person.replies >= person.mentions && person.replies >= person.liked {
            return String(localized: "You replied to \(name) \(person.replies) times")
        }
        if person.mentions >= person.liked {
            return String(localized: "You mentioned \(name) \(person.mentions) times")
        }
        return String(localized: "You liked \(person.liked) of \(name)'s posts")
    }

    /// The span underneath it. Years are printed by the CALLER's formatter, not
    /// interpolated here — `String(localized: "\(year)")` groups an `Int` with
    /// the locale's separator, and `XRoom`'s harness caught exactly that
    /// rendering a headline as "2,019 was your loudest year".
    static func note(_ person: XPerson) -> String {
        let from = plainYear(person.years.first?.year ?? 0)
        let to = plainYear(person.years.last?.year ?? 0)
        guard person.span > 1 else { return from }
        guard person.silent > 0 else { return "\(from)–\(to)" }
        return String(localized: "\(from)–\(to) · \(person.silent) quiet")
    }

    /// A year as four digits, never grouped. See `note`.
    static func plainYear(_ year: Int) -> String { String(year) }

    /// A year's height on the strip's own axis, 0…1. Zero when there is
    /// nothing to divide by, so a card can never draw a NaN width (SwiftUI
    /// draws those as nothing at all, which reads as a chart that failed).
    static func share(_ count: Int, of maximum: Int) -> Double {
        guard maximum > 0, count > 0 else { return 0 }
        return min(1, Double(count) / Double(maximum))
    }

    /// The tallest year, for the axis.
    static func peak(_ person: XPerson) -> Int {
        max(person.years.map(\.total).max() ?? 0, 1)
    }

    // MARK: - Reading a mention out of a post

    /// Does this text name `@handle`?
    ///
    /// Bounded on BOTH sides, and both bounds are load-bearing. Without the
    /// leading `@` a post about "the design of it" names `@design`; without
    /// the trailing boundary `@ben` matches every post that ever mentioned
    /// `@benedict`, which on a long archive silently merges two people into
    /// one relationship — and the card renders perfectly either way.
    ///
    /// Case-insensitive because X handles are, and because the archive's own
    /// spelling of a handle varies with whatever the person typed that day.
    static func mentions(_ text: String, handle: String) -> Bool {
        let needle = handle.trimmingCharacters(in: CharacterSet(charactersIn: " @")).lowercased()
        guard !needle.isEmpty else { return false }
        let hay = Array(text.lowercased())
        let pin = Array("@" + needle)
        guard hay.count >= pin.count else { return false }
        var index = 0
        while index + pin.count <= hay.count {
            if Array(hay[index..<(index + pin.count)]) == pin {
                let after = index + pin.count
                let boundary = after >= hay.count || !isHandleCharacter(hay[after])
                // A handle is never preceded by another handle character —
                // "foo@bar" is an email address, not a mention.
                let before = index == 0 || !isHandleCharacter(hay[index - 1])
                if boundary && before { return true }
            }
            index += 1
        }
        return false
    }

    /// What X allows in a handle: letters, digits and underscore. A dot is
    /// deliberately OUT — it ends a handle on X, which is what makes
    /// "@foo.com" name @foo.
    private static func isHandleCharacter(_ c: Character) -> Bool {
        c == "_" || c.isLetter || c.isNumber
    }
}
