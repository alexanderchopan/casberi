import Foundation

/// Which sources lead their feed with a calendar heatmap — the GitHub
/// contribution graph, generalized. A heatmap answers "how consistently do you
/// do this over time", so it fits the sources that read as a habit: journaling,
/// training, capturing, note-keeping. Each entry carries the card's title and
/// the noun its count is measured in (singular / plural), so the subtitle stays
/// honest per source ("142 entries", "38 workouts", "210 screenshots").
///
/// GitHub itself is NOT here — it owns a richer hero fed by its own API
/// (real quartiles from the contributions calendar); this registry is for
/// sources whose grid is derived from the corpus's own dates.
enum FeedHeatmap {
    struct Label {
        let title: String
        /// Count noun, singular (1 entry) and plural (N entries).
        let unit: String
        let units: String
        /// Grid width in weeks. A full year (53) for the habit sources; a short
        /// recent window for the social feeds, whose corpus is a rolling capped
        /// sample — a trailing year there would be a mostly-empty grid with one
        /// bright recent smudge, so they draw the last few months instead.
        var columns: Int = 53
        /// The kinds this grid counts, or nil for everything in the room
        /// (2026-07-31). Every source registered before this held ONE kind of
        /// thing, so the room and the habit were the same set. Snapchat is the
        /// first that isn't: its room holds saved conversations beside dated
        /// memories, and "your memory year" has to mean memories or the noun
        /// is a lie. A filter, not a second registry — the grid still draws
        /// off the feed's own `visible` things and costs no query.
        var kinds: Set<ThingKind>? = nil
    }

    static let labels: [String: Label] = [
        "Day One":       Label(title: "Your journaling year", unit: "entry",      units: "entries"),
        "Apple Journal": Label(title: "Your journaling year", unit: "entry",      units: "entries"),
        "Obsidian":      Label(title: "Your writing year",    unit: "note",       units: "notes"),
        "Notion":        Label(title: "Your writing year",    unit: "page",       units: "pages"),
        "Photos":        Label(title: "Your capture year",    unit: "screenshot", units: "screenshots"),
        "Apple Health":  Label(title: "Your training year",   unit: "workout",    units: "workouts"),
        "Strava":        Label(title: "Your training year",   unit: "activity",   units: "activities"),
        "ChatGPT":       Label(title: "Your chat year",       unit: "chat",       units: "chats"),
        "Claude":        Label(title: "Your chat year",       unit: "chat",       units: "chats"),
        "Gemini":        Label(title: "Your chat year",       unit: "chat",       units: "chats"),
        // Social feeds: every item is a cast/post (your own, ones you liked, ones
        // that mention you, channel casts — all casts), so the grid honestly reads
        // as casting density. Windowed to ~14 weeks (see `columns`).
        "Farcaster":     Label(title: "Casting activity",     unit: "cast",       units: "casts", columns: 14),
        "Bluesky":       Label(title: "Posting activity",     unit: "post",       units: "posts", columns: 14),
        // Nostr, 2026-08-26 (prd §489) — the third live network, and it had no
        // entry here, so a Nostr room with one watched account (no rail, since
        // the rail needs two) had NOTHING above its rows at all: no head, no
        // board, no grid. Bluesky's entry exactly, because the room is the same
        // room and every item in it is a note somebody posted.
        "Nostr":         Label(title: "Posting activity",     unit: "note",       units: "notes", columns: 14),
        // The two import sources (2026-07-31). Both are a FULL year on
        // purpose, unlike the social feeds above: an export is dated across
        // years rather than being a rolling recent sample, so the grid it
        // draws is the real shape of a habit and not a recent smudge.
        //
        // Snapchat counts memories only (`kinds`) — the room's saved chats are
        // dated by their newest message, which is when a conversation last
        // moved, not a day you captured anything. Instagram counts the whole
        // room because everything in it IS one dated act: a save, a like, a
        // post, a comment. Both are FALLBACKS in the hero chain, below the
        // cards that name WHO and WHAT (see `FeedScreen.shapedSections`).
        "Snapchat":      Label(title: "Your memory year",     unit: "memory",     units: "memories",
                               kinds: [.file]),
        "Instagram":     Label(title: "Your Instagram year",  unit: "entry",      units: "entries"),
        // TikTok counts the whole room, the Instagram reason: a save, a like, a
        // post and a comment are each one dated act, and the export dates every
        // one of them.
        "TikTok":        Label(title: "Your TikTok year",     unit: "entry",      units: "entries"),
        // X counts the whole room for TikTok's and Instagram's reason: a post,
        // a reply and a like are each one dated act, and the archive dates
        // every one of them exactly — replies and posts from `created_at`,
        // likes decoded from the post's own snowflake id. "Entries" rather
        // than "posts" because a third of them are somebody else's posts that
        // this person liked, and the noun in a subtitle has to be true of
        // everything it counts.
        "X":             Label(title: "Your X year",          unit: "entry",      units: "entries"),
        // "entry" for the same reason X uses it: this room mixes a followed
        // channel's broadcasts with your own saved messages and chats, and the
        // noun in a subtitle has to be true of everything it counts.
        "Telegram":      Label(title: "Your Telegram year",  unit: "entry",      units: "entries"),
        // Privacy.com, 2026-09-01 (prd §558) — the fallback beneath "Where the
        // cards go", which declines below three charges across two merchants.
        // WHEN is the weakest lead and it is the right one here: this grid can
        // never state an amount, and an amount is the one thing this seat's
        // rows cannot do arithmetic with (see `Corpus.cardSpendSources`).
        "Privacy":       Label(title: "Your card year",      unit: "charge",     units: "charges"),
    ]

    static func label(for source: String) -> Label? { labels[source] }

    /// The things a label's grid actually counts. Two exclusions, both so the
    /// subtitle's noun stays true: the kinds this label doesn't measure, and
    /// the import receipt (`Corpus.isImportReceipt`) — the app's own row about
    /// an import, which would light up today as if the person had captured
    /// something. Caller passes the feed's own `visible`; no query.
    static func counted(_ things: [Thing], label: Label) -> [Thing] {
        things.filter { thing in
            guard !Corpus.isImportReceipt(thing) else { return false }
            guard let kinds = label.kinds else { return true }
            return kinds.contains(thing.kind)
        }
    }

    /// The honest count subtitle for a heatmap card.
    static func subtitle(_ label: Label, total: Int) -> String {
        "\(total.formatted()) \(total == 1 ? label.unit : label.units)"
    }
}
