import Foundation

/// THE GITHUB ROOM'S HEAD (prd §401, 2026-08-18) — what is waiting on you.
///
/// The room has led with `githubGraphHero` since it shipped: the contributions
/// heatmap, whose own comment in `FeedScreen` calls it decorative. It answers
/// **how much did I write this year**, which is a fine thing to look at and is
/// never the reason you opened the room. Meanwhile the rows that genuinely need
/// you — a review someone requested, an issue assigned to you — sat in a plain
/// list beside your stars, your gists and every release from every repo you
/// ever starred, differentiated by nothing but the words at the front of a
/// title.
///
/// That is §247's failure shape exactly: a card owning the slot another was
/// built for. This is the other card.
///
/// ## It spends nothing
///
/// Every field is already on a landed row: the ask tag `GitHubFeedFetch`
/// stamps (`notificationAsk`), `capturedAt`, and the title. No request, no new
/// `Thing` property, no CloudKit deploy — the `CursorRoom`/`StripeRoom`
/// contract, where a head that costs a call is a head that can fail
/// differently from the rows beneath it.
///
/// ## It ranks on the TAG, never on the title
///
/// A notification's reason is written into its title as words ("Review
/// requested · org/repo · …") and that string is display copy: it is clamped
/// at 80 characters by `IngestSupport.titleLine`, so reading the reason back
/// out of it is a parse that fails on exactly the longest rows and silently
/// mis-ranks them. `CursorRoom` had to keep a title fallback because its rows
/// predated its tag; this head has no such population to serve, so it takes
/// the tag and nothing else. A row with no ask tag is not in this card.
///
/// ## Three asks, and the six that are not asks
///
/// GitHub publishes nine notification reasons. Six of them — `author`,
/// `comment`, `subscribed`, `manual`, `state_change`, `ci_activity` — mean
/// "this moved". They are real news, they are already rows, and there is
/// nothing for you to do about them. Including them would make this head a
/// second copy of the feed with a ranking on top. The three that are a request
/// are the whole subject.
///
/// ## What it may NOT draw
///
/// **No age claim stronger than the row supports.** `capturedAt` here is
/// GitHub's `updated_at` for the notification — when the thread last moved, not
/// when the ask was made. So the card says "last moved", never "waiting N
/// days": a review requested on Monday whose author pushed a fixup on Friday
/// would otherwise read as one day old when it has been waiting five. The
/// distinction is invisible and would be believed, which is why the wording
/// carries it rather than a comment.
///
/// No count of what you have "left undone" (a tally, §223), no completion rate,
/// and no trend — the notifications feed is capped at 30 rows, so any curve
/// drawn here would describe the cap.
///
/// Foundation-only by design so `scripts/github-room-selftest.sh` can compile
/// it WHOLE and unmodified.
struct GitHubRoom: Equatable {

    // MARK: - The ask

    /// What a notification is asking of you.
    ///
    /// The raw values ARE the strings `GitHubFeedFetch.notificationAsk` stamps
    /// — one table in two files, which the harness drift-guards, because this
    /// file cannot import the other: `GitHubFeeds.swift` reaches `Thing`,
    /// `IngestSupport` and the network, so no harness can compile it at all.
    enum Ask: String, Equatable, CaseIterable {
        case review    = "Review"
        case assigned  = "Assigned"
        case mentioned = "Mentioned"

        /// Ranked by how much of the work is YOURS, which is also how much a
        /// delay costs someone else. A requested review BLOCKS another person's
        /// pull request — they cannot merge without you — so it outranks work
        /// assigned to you, which is yours to schedule. A mention is the
        /// weakest: it asks for attention, and often only for a moment of it.
        var weight: Int {
            switch self {
            case .review:    3
            case .assigned:  2
            case .mentioned: 1
            }
        }

        /// The card's own words for it. Sentence case, a phrase not a label —
        /// design law bans the ALL-CAPS eyebrow this would otherwise become.
        var line: String {
            switch self {
            case .review:    String(localized: "Review requested")
            case .assigned:  String(localized: "Assigned to you")
            case .mentioned: String(localized: "You were mentioned")
            }
        }

        /// Reads the ask off a row's tags. Nil when there is none, which is the
        /// common case and not a failure — six of GitHub's nine reasons carry
        /// no ask by design.
        static func from(tags: [String]) -> Ask? {
            for tag in tags {
                if let ask = Ask(rawValue: tag) { return ask }
            }
            return nil
        }
    }

    // MARK: - Items

    struct Item: Equatable {
        let ask: Ask
        /// The row's title, as landed. Display copy — the card draws it and
        /// never reads it.
        let title: String
        /// When the THREAD last moved (GitHub's `updated_at`), which is not
        /// when the ask was made. See the type's own doc: the card's wording
        /// must not upgrade this into a waiting time.
        let lastMoved: Date
        /// The row, so a tap opens it.
        let ref: String
    }

    /// Every open ask, most-blocking first.
    let items: [Item]
    /// How many rows carried an ask this card could not place — always zero
    /// today, kept because `Ask.from` can start returning nil for a tag that
    /// gets renamed on one side of the mirror, and a head that silently drops
    /// rows is the failure this project keeps re-learning.
    let unplaced: Int

    /// The card's headline. Names the strongest ask present, because that is
    /// the one that decides whether you open the room now or later.
    var headline: String {
        guard let top = items.first else { return String(localized: "Nothing waiting") }
        let sameAsk = items.filter { $0.ask == top.ask }.count
        if sameAsk == 1 { return top.ask.line }
        switch top.ask {
        case .review:    return String(localized: "\(sameAsk) reviews requested")
        case .assigned:  return String(localized: "\(sameAsk) assigned to you")
        case .mentioned: return String(localized: "\(sameAsk) mentions")
        }
    }

    /// The count line under it, when there is more than one KIND of ask —
    /// otherwise the headline already said everything and this would repeat it.
    var subline: String? {
        let kinds = Set(items.map(\.ask))
        guard kinds.count > 1 else { return nil }
        return String(localized: "\(items.count) waiting on you")
    }

    // MARK: - Compose

    /// The most items the card draws. A head is a reading, not the room —
    /// past this the list beneath it is the better surface, and an unbounded
    /// card would simply be the feed twice.
    static let cap = 5

    /// Builds the card, or nil when nothing is waiting.
    ///
    /// `rows` is (tags, title, lastMoved, ref) — deliberately NOT `[Thing]`, so
    /// this file stays Foundation-only and the harness can compile it whole.
    /// `GitHubRoomSource` is the thin adapter that reads the model.
    static func compose(rows: [(tags: [String], title: String,
                                lastMoved: Date, ref: String)]) -> GitHubRoom? {
        var items: [Item] = []
        var unplaced = 0
        for row in rows {
            guard let ask = Ask.from(tags: row.tags) else { continue }
            let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // A row with no title has nothing to draw and nothing to tap
            // toward — counted rather than silently dropped.
            guard !title.isEmpty else { unplaced += 1; continue }
            items.append(Item(ask: ask, title: title,
                              lastMoved: row.lastMoved, ref: row.ref))
        }
        guard !items.isEmpty else { return nil }
        // TOTAL, so the card cannot reshuffle between two opens over identical
        // data — the `ASCRoom` rule. Weight, then most-recently-moved, then the
        // ref, which is unique and breaks every remaining tie.
        items.sort {
            if $0.ask.weight != $1.ask.weight { return $0.ask.weight > $1.ask.weight }
            if $0.lastMoved != $1.lastMoved { return $0.lastMoved > $1.lastMoved }
            return $0.ref < $1.ref
        }
        return GitHubRoom(items: Array(items.prefix(cap)), unplaced: unplaced)
    }
}
