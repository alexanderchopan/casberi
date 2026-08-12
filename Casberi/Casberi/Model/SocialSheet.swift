import Foundation

/// WHAT A SOCIAL THING SHEET IS — the shape decision and the "how it landed"
/// reading (prd §363, 2026-08-12).
///
/// The sheet's whole social treatment used to be gated on
/// `SocialThread.isSocial`, a set of exactly three source NAMES (Bluesky,
/// Farcaster, Nostr). Four of the seven social sources were therefore refused
/// it — and every one of them stamps the same fields. The measured cost, taken
/// from the shipped code rather than guessed:
///
/// - An **X post** (`.note`) drew `Text(thing.title)` — `titleLine`'s
///   80-character clamp — at `heading34`, then repeated `content` in full at
///   `callout15`, while `postText`, `authorHandle`, `likeCount`, `repostCount`,
///   `previewImageData` and a whole thread on `enrichedText` sat unread. The
///   room's own `PostCard` draws five of those six. **The sheet you opened to
///   read a post showed less of it than the row you tapped.**
/// - An **X liked post** (`.link`) drew a `LinkPreviewCard` over an x.com URL,
///   which serves no `og:` tags at all (§280) — so the one shape whose words
///   are already in the record rendered as a naked host row.
/// - A **new follower** (`.link`) drew a headline sentence and a link preview
///   of their profile page. It is a PERSON, and the app has had
///   `SocialProfileCard` — face, bio, Watch, who-they-follow — since §169.
/// - An **Instagram or TikTok save** drew a link card and never named the
///   creator its own face pass had already stamped.
///
/// ## The ruling: the gate is a DATA test, never a source list
///
/// The question the old gate asked was "is this Bluesky, Farcaster or Nostr?".
/// The question it MEANT was "does this record carry something to read?". A
/// source list has to be remembered every time a bridge lands a post; a data
/// test covers the seat that ships next week for free. `shape(_:)` below asks
/// only about the record.
///
/// ## Why this file is Foundation-only
///
/// So `scripts/social-sheet-selftest.sh` can compile it WHOLE and unmodified.
/// Every failure here is a SILENT WRONG ANSWER that renders perfectly: a post
/// classified as a save draws a link card over prose that is sitting right
/// there; an archive's 2019 counts presented without a date read as live
/// numbers, which is the §83 fake-status ban in the one place a person would
/// believe them instantly. Nothing in a build or a screen sweep can see either.
/// Everything touching `Thing` lives in `SocialSheetSource.swift`.
enum SocialSheet {

    // MARK: - Shape

    /// The anatomy a social thing wears. Four, and there is deliberately no
    /// fifth: a shape exists only where the sheet would otherwise draw the
    /// wrong noun.
    enum Shape: String, Equatable {
        /// Words are the hero — who said it, what they said, its pictures,
        /// what it quotes, how it landed. A cast, a skeet, an archived tweet,
        /// a caption you wrote, a comment you left.
        case post
        /// A person, not a link to one. Today this is a new follower; the
        /// sheet leads with their face and its verb is Watch.
        case person
        /// Somebody else's thing that you kept, whose words we do not have —
        /// an Instagram save, a TikTok video. The creator leads, and where the
        /// export carries nothing behind the link, the sheet says so rather
        /// than drawing an empty card that reads as a failure.
        case save
        /// A conversation: two people's words in turn. Snapchat's saved chats,
        /// an imported DM thread.
        case transcript
    }

    /// The facts the shape decision reads. A value type on purpose: the
    /// decision is the thing worth testing, and it must be testable without a
    /// `Thing`, a store, or a simulator.
    struct Facts: Equatable {
        /// Is this a social source at all (the catalog's `Network` group)?
        /// A `false` here means "no social anatomy", not "draw it badly".
        var social: Bool
        /// Does the network have a thread API and a profile lookup — i.e. is
        /// it `SocialThread.isSocial`? Used for ONE thing: telling a post-kind
        /// `.chat` (a cast) from a conversation-kind one (a saved Snapchat
        /// thread), which no other field can do.
        var threadCapable: Bool
        /// `ThingKind.rawValue`, so this file needs no SwiftData.
        var kind: String
        /// Does the record carry prose to read — `postText`, else `content`,
        /// where that is not simply a URL? THE field the old gate should have
        /// been asking about.
        var hasWords: Bool
        /// `Thing.socialContext`: "liked", "recast", "mention", "reply",
        /// "follow".
        var context: String?
    }

    /// The anatomy, or nil for a social thing that needs none (a Snapchat
    /// memory is a picture; a Farcaster signer grant is a permission notice).
    ///
    /// Order is load-bearing and each step earns its place:
    ///
    /// 1. **A follower is a person** before it is anything else — it is the one
    ///    context that changes the NOUN rather than the layout.
    /// 2. **A `.chat` forks on the network, not on its words.** A cast and a
    ///    saved Snapchat thread are the same kind, both carry text, and only
    ///    `threadCapable` separates them. This is also what preserves today's
    ///    behaviour exactly for a Bluesky post landed before `postText` existed
    ///    (nil words, still a post) — the one case a pure words test would
    ///    regress, and it is every row in an install that predates prd 81.
    /// 3. **Then, and only then, words decide.** This is the widening: an X
    ///    post, an X like, an Instagram caption, a TikTok comment all reach
    ///    `.post` here on the strength of their own record.
    /// 4. **A social link with no words of its own is a save.**
    static func shape(_ f: Facts) -> Shape? {
        guard f.social else { return nil }
        if f.context == "follow" { return .person }
        if f.kind == "chat" { return f.threadCapable ? .post : .transcript }
        if f.hasWords { return .post }
        if f.kind == "link" || f.kind == "product" { return .save }
        return nil
    }

    // MARK: - The rest of a thread

    /// The continuations of a self-thread, or nil when there is no thread to
    /// show (prd §363).
    ///
    /// §307 gave an X thread's HEAD the whole chain on `enrichedText`, joined
    /// by blank lines, so the retriever could find the fourth post's argument
    /// from the first post's row. It was retrieval-only by the 2026-07-15
    /// ruling and therefore invisible on every screen — which for a thread is
    /// the wrong half to hide: X itself only surfaces a thread from its head,
    /// and the head is exactly the row a person taps. This is the same
    /// exception `enrichedText` already carries for an Obsidian note (the
    /// words are the payoff, not a machine's paraphrase) and for Privacy
    /// Pools, Peer and Railgun.
    ///
    /// **The first part is DROPPED, and the drop is proven, not assumed.** The
    /// chain includes the head, whose words the sheet is already showing in
    /// display type — so slicing blind would repeat the post, and slicing the
    /// wrong field would print a stranger's text under somebody's own name.
    /// The guard is that the first part must BE this post's words; anything
    /// else returns nil and the section simply does not render.
    ///
    /// `count` is the archive's own tally (`messageCount`), never
    /// `parts.count`: they agree today, and if they ever stop, the number the
    /// importer measured is the true one and a disagreement is a bug worth
    /// showing rather than papering over.
    static func threadRest(enriched: String?, words: String, count: Int?) -> [String]? {
        guard let enriched, let count, count > 1 else { return nil }
        let parts = enriched.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return nil }
        let head = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty, parts[0] == head else { return nil }
        return Array(parts.dropFirst())
    }
}

/// HOW IT LANDED — the block that replaces the spec table on a social sheet.
///
/// The spec table rendered exactly one row on a social post (`From — saved by
/// you`), inside its own card, behind an 80pt label column. It was the only
/// thing on the sheet that looked like a form, and it was the sheet's whole
/// answer to "why is this here". This says the same fact in a sentence, and
/// puts beside it the two readings the record already held and nobody drew.
///
/// ## What this is allowed to be, and what it must never become
///
/// §223's module doctrine bans a COUNT from being a *thing*. It does not ban a
/// state surface from stating one — which is why the engagement line has
/// existed since 2026-07-16. This block is a **reading of one post**, never
/// news: it updates in place, it is never a row, and it never says "+3 since
/// yesterday". A count the source did not report has no cell at all — an
/// absent number and a reported zero are different facts (honesty rule), and
/// that distinction is the only reason the numbers here can be trusted.
struct SocialReception: Equatable {

    /// One reported number and its noun. `text` is pre-rendered because
    /// `SocialCount` already owns the "97+" honesty valve (a full page means
    /// "at least this many"), and re-deciding it here would make two places
    /// that can disagree about the same number.
    struct Reading: Equatable {
        var text: String
        var noun: String
    }

    /// What the network reported, in a fixed order, absent readings excluded.
    var readings: [Reading] = []
    /// Names, never a bare number (§239) — `SocialLikeRoll.line`, which is nil
    /// unless at least one liker could be NAMED. It renders in the feed row
    /// and, until now, nowhere in the sheet you opened to find out who.
    var likers: String?
    /// One sentence saying how this arrived. Replaces the `From` spec row.
    var provenance: String?
    /// Present only when the readings are a SNAPSHOT rather than a live read —
    /// an archive's counts, frozen the day it was exported. Without it a 2019
    /// post's 412 likes read as a number somebody just measured.
    var recorded: String?
    /// What the source structurally cannot give us, said out loud, for the one
    /// shape where an empty card would otherwise read as a broken fetch.
    var ceiling: String?

    var isEmpty: Bool {
        readings.isEmpty && likers == nil && provenance == nil
            && recorded == nil && ceiling == nil
    }

    /// What the person DID, which is the verb the provenance sentence turns
    /// on. Derived at the source layer from tags and `socialContext`, decided
    /// into words here so the wording is harnessed.
    enum Act: String, Equatable {
        case posted, replied, liked, saved, wrote, followed

        /// Past tense, second person. "You *liked* this on 4 March."
        var verb: String {
            switch self {
            case .posted:   return String(localized: "posted")
            case .replied:  return String(localized: "replied")
            case .liked:    return String(localized: "liked")
            case .saved:    return String(localized: "saved")
            case .wrote:    return String(localized: "wrote")
            case .followed: return String(localized: "followed")
            }
        }
    }

    /// Everything the sentence and the readings are built from. One struct
    /// rather than nine arguments, so a new fact can be added without every
    /// call site and every fixture having to be rewritten.
    struct Input {
        var source: String
        var shape: SocialSheet.Shape
        /// True for `Corpus.bulkImportSources` — the rooms whose whole content
        /// arrived in one afternoon from a file.
        var archive: Bool
        /// When the act happened, as the record holds it (`capturedAt`). For
        /// an archive row this is the REAL past date, which is exactly why the
        /// sentence can state it.
        var when: Date?
        /// When the archive was read, off the import receipt. nil is fine —
        /// the sentence simply says less.
        var importedAt: Date?
        var act: Act?
        /// `SocialThread.contextPhrase` — "you liked this", "in /design". One
        /// vocabulary for why-it's-here, shared with the eyebrow, so the two
        /// lines on one screen can never contradict each other.
        var phrase: String?
        var likes: Reading?
        var reposts: Reading?
        var replies: Reading?
        var likers: String?
        /// The export's own limit, where there is one worth saying.
        var ceiling: String?
    }

    /// The reading, or nil when there is nothing honest to say.
    ///
    /// Never a spinner and never a zero standing in for an unknown: a block
    /// with no readings and no sentence simply does not render, the same rule
    /// the engagement line has always kept.
    static func compose(_ i: Input) -> SocialReception? {
        var out = SocialReception()
        // Fixed order, absent excluded. Likes lead because they are the one
        // reading every network reports; replies trail because the sheet's own
        // Replies section states that number again, better, with the words.
        out.readings = [i.likes, i.reposts, i.replies].compactMap { $0 }
        out.likers = i.likers
        out.provenance = sentence(i)
        out.ceiling = i.ceiling
        // The staleness clause rides the READINGS, not the row: an archive
        // sentence already dates the act, and a block with no numbers has
        // nothing that could be mistaken for a live measurement.
        if i.archive, !out.readings.isEmpty {
            out.recorded = i.importedAt.map {
                String(localized: "Counts as your \(i.source) archive recorded them, \(month($0)).")
            } ?? String(localized: "Counts as your \(i.source) archive recorded them.")
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - The sentence

    /// One sentence, three grammars, chosen by where the thing came from.
    ///
    /// The archive grammar is the one that earns this whole function: it names
    /// the FILE as the origin and the person's own act as the event, with a
    /// real past date. "From your X archive — you liked this on 16 April 2019"
    /// is a complete answer to "why am I looking at this"; `From: saved by you`
    /// was not an answer at all.
    private static func sentence(_ i: Input) -> String? {
        if i.shape == .person {
            return String(localized: "Followed you on \(i.source).")
        }
        if i.archive {
            guard let act = i.act else {
                return String(localized: "From your \(i.source) archive.")
            }
            guard let when = i.when else {
                return String(localized: "From your \(i.source) archive — you \(act.verb) this.")
            }
            return String(localized:
                "From your \(i.source) archive — you \(act.verb) this on \(day(when)).")
        }
        // A live source. The phrase is the same one the eyebrow wears, so the
        // sheet says why once and means it twice; with no phrase there is
        // nothing to add and the bare source is the whole honest sentence.
        guard let phrase = i.phrase, !phrase.isEmpty else {
            return String(localized: "On \(i.source).")
        }
        return String(localized: "On \(i.source) — \(phrase).")
    }

    // MARK: - Dates
    //
    // Spelled out rather than taken from a shared formatter: this file is
    // Foundation-only by design so the harness can compile it whole, and both
    // of these are stable, locale-aware `Date.FormatStyle` reads with no
    // dependency to import.

    /// "16 April 2019" — a full date, because the whole point of an archive
    /// sentence is that the act is OLD. A relative age ("6y ago") would make
    /// the reader do the arithmetic the sentence exists to save them.
    private static func day(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.wide).year())
    }

    /// "Aug 2026" — when the archive was read. The day is noise here; the
    /// month is what tells you how stale the numbers are.
    private static func month(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).year())
    }
}
