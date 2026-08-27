import Foundation

/// What a social room DOES — one table, nine sources (prd §489, 2026-08-26).
///
/// **Why this exists.** Nine sources land the same three things: a post with an
/// author, a link somebody shared, a conversation. The `Thing` model is
/// identical for all of them. What differed was the ROOM, and the room was
/// decided by `FeedScreen.Shape.init` — a switch each source joined one at a
/// time by copying the last one, with the row rules re-spelled inline every
/// time. Five copies of one decision, drifting apart:
///
///   • Nostr had NO case at all, so its rows fell to the generic band while
///     `PostCard`, `SocialThreadCard`, `SocialThread.replies` and
///     `NostrStore.socialAccounts` all already carried Nostr-specific code
///     nothing could reach.
///   • TikTok had none either — a room of saved videos drawing as
///     80-character title rows.
///   • `standsAlone` was fixed for X (§396a) and never carried to Instagram or
///     Telegram, so both drew post cards squeezed into a merged run.
///   • `isXPostRow` and `isTelegramPostRow` answered the same question in two
///     dialects, and Instagram answered it a third way inline.
///
/// **The shape of the fix.** `rowKind` is the ONE answer to "what anatomy does
/// this row wear", and `standsAlone` is derived FROM it rather than spelled
/// beside it — which is what makes the §396a class structurally impossible
/// rather than fixed per room. The house split applies: this half is
/// Foundation-only so `social-room-selftest.sh` compiles it whole and mutation-
/// proves every source's rules, and `SocialRoomSource` holds the store lookups
/// where there is no judgement to test (`StripeRoom`/`StripeRoomSource`,
/// `PeerRoom`/`PeerRoomSource`, and every room head since).
///
/// **What this deliberately does NOT decide.** Grid membership stays in
/// `FeedScreen` with the other photo-tile tests — a mixed room's split between
/// a picture wall and rows is LAYOUT, it reads `previewImageData` (a heavy
/// column), and the four rooms that have one each answer it differently for a
/// stated reason. And it does not decide the HEAD: §349 requires a head to say
/// something true about its own room, so those stay per-room registries.
enum SocialRoom {

    // MARK: - The table

    /// What a room declares about itself. Two fields, because two is all that
    /// legitimately varies once `rowKind` below carries the rest.
    struct Facts: Equatable {
        /// Whether a person's own consecutive self-replies fold into one
        /// thread card.
        ///
        /// True only where a parent post can be named EXACTLY: the three live
        /// networks carry a protocol reply ref, and X's archive names a
        /// self-reply's parent id in the same file. Instagram's and TikTok's
        /// exports name no parent at all, and Telegram's channel scrape names
        /// none either — §309's standing split between what generalises across
        /// the import rooms and what is one export's own fact.
        var foldsThreads: Bool

        /// Whether the room's authors are accounts you WATCH — the face rail.
        ///
        /// The three live networks only. An import room's authors are whoever
        /// fills the archive, which is a leaderboard's question and not a
        /// control's: a rail is a place you return to, and the set behind it
        /// has to be stable and yours. Telegram follows CHANNELS, which would
        /// qualify — except no channel picture is reachable on the body path
        /// (the follow store keeps a name and a feed URL, and the icon lands on
        /// the rows), and a rail of nine identical Telegram glyphs is the
        /// defect R4.2 and §313 both name.
        var hasRoster: Bool
    }

    /// Every source that gets the social-room treatment.
    ///
    /// Guarded against the catalog by `social-room-selftest.sh`: a `Network`
    /// seat must resolve here or be named in that script's `KNOWN_NO_ROOM`
    /// with a written reason. That guard is the whole point of the pass — every
    /// drift above has one shape, a source joining the catalog, the ingest and
    /// the sheet while nobody remembered the room.
    static let table: [String: Facts] = [
        "Bluesky":   Facts(foldsThreads: true,  hasRoster: true),
        "Farcaster": Facts(foldsThreads: true,  hasRoster: true),
        "Nostr":     Facts(foldsThreads: true,  hasRoster: true),
        "X":         Facts(foldsThreads: true,  hasRoster: false),
        "Instagram": Facts(foldsThreads: false, hasRoster: false),
        "Telegram":  Facts(foldsThreads: false, hasRoster: false),
        "TikTok":    Facts(foldsThreads: false, hasRoster: false),
        "Snapchat":  Facts(foldsThreads: false, hasRoster: false),
    ]

    static func facts(for source: String) -> Facts? { table[source] }

    /// Whether this source draws the social room's rows at all.
    ///
    /// Snapchat is in the table and answers FALSE here on purpose: its room is
    /// memories and saved chats, it holds no post in the sense the other seven
    /// do, and its rows are already the excerpt/grid split §247 gave it. It is
    /// listed so the catalog guard can see it decided rather than forgotten.
    static func drawsPosts(_ source: String) -> Bool {
        facts(for: source) != nil && source != "Snapchat"
    }

    /// The three live networks — the set with a roster, stated as a function so
    /// callers read the reason rather than a name list.
    static func hasRoster(_ source: String) -> Bool {
        facts(for: source)?.hasRoster == true
    }

    static func foldsThreads(_ source: String) -> Bool {
        facts(for: source)?.foldsThreads == true
    }

    // MARK: - One row, one anatomy

    /// The facts a row's anatomy is decided from — every one of them a light
    /// column or a value already in hand.
    ///
    /// `hasPreviewImage` is the ONE heavy read, and it is asked only where the
    /// answer changes the anatomy (an Instagram picture post whose thumbnail
    /// never landed). Callers hand it in; nothing here faults a store.
    struct RowFacts: Equatable {
        var source: String
        /// `Thing.kind.rawValue` — a string so this file needs no SwiftData.
        var kind: String
        var tags: [String]
        var isImportReceipt: Bool
        /// `Corpus.arrivedLive` — Telegram's live/import split, which is a fact
        /// about the ref rather than about the source.
        var arrivedLive: Bool
        var hasPostText: Bool
        var hasPreviewImage: Bool
        var socialContext: String?

        init(source: String, kind: String, tags: [String] = [],
             isImportReceipt: Bool = false, arrivedLive: Bool = false,
             hasPostText: Bool = false, hasPreviewImage: Bool = false,
             socialContext: String? = nil) {
            self.source = source
            self.kind = kind
            self.tags = tags
            self.isImportReceipt = isImportReceipt
            self.arrivedLive = arrivedLive
            self.hasPostText = hasPostText
            self.hasPreviewImage = hasPreviewImage
            self.socialContext = socialContext
        }
    }

    /// The four anatomies any of these rooms can draw, and no fifth.
    ///
    /// `whole` is the words rule (§396a): an ARCHIVE of somebody's own writing
    /// draws the post entire, because the words are the whole content of the
    /// row and there is nothing live to scroll past; a drip room clamps, because
    /// the next post is the point.
    enum RowKind: Equatable {
        /// Our own note about a sync, a fact about the account, a post with
        /// nothing left to show — the plain band every other room draws.
        case band
        /// A conversation, or a sentence left on somebody else's post.
        case excerpt(lines: Int)
        /// A link somebody shared, or a video you saved — it reads as the
        /// reading-list entry it is.
        case reading
        case post(whole: Bool)
        case thread(whole: Bool)

        /// Whether this anatomy is a CARD, and therefore never merges into a
        /// run of bare rows.
        ///
        /// Derived, never spelled beside `rowKind` — §396a happened because
        /// `shapedRow` and `standsAlone` answered the same question in two
        /// places and drifted, and were then fixed in one room and not the two
        /// beside it.
        var standsAlone: Bool {
            switch self {
            case .post, .thread: return true
            case .band, .excerpt, .reading: return false
            }
        }

        /// Whether this row is somebody's post, for the day header's noun.
        var isPost: Bool { standsAlone }
    }

    /// What anatomy a row wears.
    ///
    /// `hasReplies` is whether the caller folded self-replies underneath it,
    /// which only a room with `foldsThreads` can produce.
    static func rowKind(_ row: RowFacts, hasReplies: Bool = false) -> RowKind {
        guard facts(for: row.source) != nil else { return .band }
        // Our own note about an import is never anybody's post, in any room.
        if row.isImportReceipt { return .band }

        switch row.source {

        // THE THREE LIVE NETWORKS. Their posts land as `.chat` by kind (see
        // `BlueskyIngest`/`FarcasterIngest`/`NostrIngest`), so — unlike every
        // room below — a `.chat` here is the post itself and must NOT take the
        // transcript branch.
        case "Bluesky", "Farcaster", "Nostr":
            // A FOLLOWER IS A PERSON, not an article somebody shared
            // (2026-08-12). `SocialInbound.landFollower` lands a follow as a
            // `.link`, and the link branch below would read it as a shared
            // article — the row would then disagree with its own sheet, which
            // `SocialSheet.shape` already sends to the person anatomy.
            if row.socialContext == "follow" { return .band }
            // An article a post shared lands as its own thing (2026-07-27) and
            // reads like the reading list it actually is, not like a post with
            // no author of its own.
            if row.kind == "link" { return .reading }
            return hasReplies ? .thread(whole: false) : .post(whole: false)

        // AN ARCHIVE OF SOMEBODY'S OWN WRITING (§313, §375, §396a).
        case "X":
            if row.kind == "chat" { return .excerpt(lines: 2) }
            // A fact about the ACCOUNT rather than about anything it posted —
            // a connected app, the day you joined, a handle you used to wear.
            // A post card over one would draw a face and a handle over a fact.
            if row.tags.contains("Access") || row.tags.contains("Account") { return .band }
            return hasReplies ? .thread(whole: true) : .post(whole: true)

        // THE ONE ROOM THAT IS LIVE AND IMPORT AT ONCE (§456).
        case "Telegram":
            if row.kind == "chat" { return .excerpt(lines: 2) }
            // A channel's broadcast is written to be read, and the words are
            // the whole row — X's ruling, for the same reason.
            if row.arrivedLive { return .post(whole: true) }
            // A saved message is usually a bare link you sent yourself, so it
            // reads as one. With no words and nothing live, all the row
            // honestly carries is a date.
            return row.hasPostText ? .reading : .band

        case "Instagram":
            if row.kind == "chat" { return .excerpt(lines: 2) }
            // A comment is not a post. It is a sentence you left on somebody
            // else's, and the export does not carry the post it was left on —
            // so it reads as an excerpt rather than as a card claiming to show
            // something it cannot.
            if row.tags.contains("Comment") { return .excerpt(lines: 3) }
            // A save whose words `InstagramCaptions` has not read back yet,
            // which right after an import is most of the room. It is a handle
            // and a date and nothing else (§245), and a post card over it
            // would print that handle TWICE — once as the byline and once as
            // the body, since `PostCard.words` falls back to the title.
            if row.kind == "link" && !row.hasPostText { return .excerpt(lines: 2) }
            // A picture post whose thumbnail never landed. The grid correctly
            // refuses it (a tile promises a picture), and a post card would
            // show the placeholder word "Photo" as its entire body.
            if row.tags.contains("Photo") && !row.hasPreviewImage { return .band }
            return .post(whole: false)

        // A ROOM OF SAVED VIDEOS (2026-08-26). It had no shape at all until
        // this pass, so every row drew as an 80-character title band.
        //
        // NO POST CARDS HERE, and that is a data fact rather than a taste:
        // `TikTokImport` stamps no `postText` on any row — the caption lands on
        // `enrichedText`, which is retrieval-only by the 2026-07-15 ruling — so
        // `PostCard.words` would fall back to the title and print the row's own
        // face as its body. Before `fetchFaces` has run that title is the raw
        // t.co-style share URL, which is the naked-link failure `OEmbed` exists
        // to fix, committed by us. A saved video with a cover and a title IS a
        // reading-list entry, and reads as the one Telegram's saved messages
        // and the Bookmarks room already draw.
        case "TikTok":
            if row.tags.contains("Comment") { return .excerpt(lines: 3) }
            if row.kind == "link" { return .reading }
            return .band

        // Snapchat's room is memories and saved chats — already split into a
        // grid and rows by §247, and holding no post. Listed in the table so
        // the catalog guard sees it decided; it never reaches here.
        default:
            return .band
        }
    }

    /// Whether a row stands on a card of its own. Derived from `rowKind`, never
    /// spelled beside it — see `RowKind.standsAlone`.
    static func standsAlone(_ row: RowFacts) -> Bool {
        rowKind(row).standsAlone
    }

    // MARK: - The day header's noun

    /// Whether a day's rows may be called POSTS.
    ///
    /// Every row in the group has to be one, which is X's rule (§396a)
    /// generalised: a room also holds shared articles, transcripts, follows and
    /// our own notes about a sync, and calling those posts is worse than saying
    /// "things". An empty group is never posts — nothing is not a post.
    ///
    /// A DELIBERATE CHANGE to the three live rooms, which said "posts"
    /// unconditionally: a day holding twelve casts and one shared article now
    /// falls through to the generic noun rather than counting the article as a
    /// thirteenth post.
    static func groupIsPosts(_ rows: [RowFacts]) -> Bool {
        guard !rows.isEmpty else { return false }
        return rows.allSatisfy { rowKind($0).isPost }
    }
}
