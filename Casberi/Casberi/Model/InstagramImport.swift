import Foundation
import SwiftData

/// The Instagram importer (2026-07-31, prd §245) — the ChatGPT pattern, with
/// one difference that shapes the whole file and must not be forgotten.
///
/// WHAT AN INSTAGRAM EXPORT ACTUALLY CONTAINS. Meta's export gives you *your*
/// data, and on Instagram most of what you have is a record of what you
/// TAPPED, not the things themselves. The posts you saved belong to whoever
/// made them, so they don't come down. A saved post is three fields, and this
/// is the whole record (confirmed against four independent parsers, 2026-07-31):
///
///     {"title": "houseofgaming",
///      "string_map_data": {"Saved on": {"href": "https://instagram.com/reel/…",
///                                        "timestamp": 1739667172}}}
///
/// A handle, a link, a date. No caption, no image. So the export splits in two
/// and the honesty rule requires the offer copy to split with it:
///
///   - Things you MADE — your posts' captions, your comments — arrive whole and
///     are real searchable text, exactly the grade of a ChatGPT export.
///   - Things you TAPPED — saves and likes — arrive as named links. A save
///     lands as "@houseofgaming" opening on the post, which is findable and
///     honest; it is NOT the caption, and nothing here pretends otherwise.
///
/// The title is taken from the export's own `title` field rather than left
/// looking like the URL. That is deliberate and costs something: `LinkTitle.enrich`
/// only renames a link still wearing its URL as a face, so a save named
/// "@houseofgaming" is not picked up by the generic enrichment chain. The trade
/// was taken knowingly, on the reasoning that a guaranteed handle from the
/// export beats a naked URL waiting on an endpoint Meta had already stripped
/// fields out of — and measurement on 2026-08-02 settled it: `instagram_oembed`
/// answers keylessly with an embed blockquote and no title, author or
/// thumbnail, so it was removed from `OEmbed.endpoints` entirely. There is no
/// endpoint left for these rows to have waited on; the export's own handle is
/// the only face they will ever have.
///
/// MEDIA now lands, as of 2026-08-05 (prd §310), and the old decline is worth
/// keeping visible because the reasoning was half right: your own posts
/// reference their JPEGs by a path relative to a temporary security-scoped
/// folder, and copying originals into a CloudKit-mirrored store really would
/// be wrong. What lands is a 480pt THUMBNAIL — the same object every other
/// picture in this app is — read while the grant is still held. The export's
/// files stay exactly where they are. This mattered more here than anywhere
/// else: Instagram is a photo app, and its room was a wall of text.
///
/// FOUR MORE FILES, AND THE WORDLESS HALF (2026-08-18, prd §395). Until this
/// date the only thing you MADE that this importer read was `posts_N.json`, and
/// only when the post carried a caption. Both halves of that were losses nobody
/// could see:
///
///   - `reels.json`, `stories.json`, `archived_posts.json` and
///     `igtv_videos.json` sit beside it, in the same shape, and were never
///     opened. A person whose Instagram is mostly reels imported their comments
///     and nothing they had made in years, and the receipt said so in a number
///     that looked perfectly healthy.
///   - A captionless post was SKIPPED, on §245's reasoning that "the media
///     stays in the export, so a caption is the only substance such a row would
///     have". That stopped being true in §310, when this importer learned to
///     thumbnail the export's own files. It has pixels now, so a wordless
///     photograph is a thing — `XArchiveImport`'s §375 ruling, one product
///     over, and it carries the same `Photo` facet and feeds the same kind of
///     grid.
///
/// The same pass reads your own USERNAME out of `personal_information.json`, so
/// a post you wrote is introduced by you rather than by the word "Instagram";
/// stamps the kind of post a save was (`Reel`) off Meta's own permalink; and
/// stamps the ACT (`socialContext`) so the room's post card can say "Saved" or
/// "Liked" in the slot every other social room already draws it in.
///
/// NOT BUILT, with reasons. (1) DMs: full message text is in there and would be
/// the largest prose corpus in the export, but whether years of private
/// conversation belong in a searchable index is the person's call to make
/// deliberately, not a side effect of tapping Import. (3) Followers/following:
/// usernames and dates, no content — a tally, and the module doctrine says a
/// thing is never a tally.
enum InstagramImport {

    struct Summary {
        var saved = 0
        var liked = 0
        var posts = 0
        /// How many of `posts` landed as PICTURES rather than captions — a
        /// SUBSET, never added to `imported`. Your Instagram is full of posts
        /// whose caption is the empty string, and until 2026-08-18 every one of
        /// them was skipped: `landOwnMedia` required a caption, so a wordless
        /// photograph had, in its own words, no substance. It has a photograph.
        var photos = 0
        var comments = 0
        /// Private messages, landed only when `ImportOptions.includeMessages`
        /// says so. Off by default and stays off.
        var messages = 0
        var skipped = 0
        /// Rows the cap refused. Reported rather than swallowed — see `tapCap`.
        var dropped = 0
        var failed = false

        var imported: Int { saved + liked + posts + comments + messages }
    }

    /// The newest N per category. Each category is capped on its own rather
    /// than sharing one budget: a saves library runs to thousands while your
    /// own posts are in the dozens, and a shared cap would let the cheap rows
    /// crowd out the ones carrying real text.
    ///
    /// RAISED 2026-08-05 from a single 500 (prd §309, generalising §307). Five
    /// hundred was far too low for an export covering years, and it failed
    /// SILENTLY: the receipt for a truncated import read word-for-word like the
    /// receipt for a complete one, so a library of six thousand saves landed
    /// five hundred and nothing anywhere said so. `dropped` is what makes the
    /// difference visible.
    ///
    /// Two numbers now, not one, because the halves aren't worth the same: what
    /// you WROTE is the substance of an export and what you TAPPED is a link
    /// and a date. That was already this doc's reasoning for capping per
    /// category; it just had one number to say it with.
    private static let writingCap = 10_000
    private static let tapCap = 5_000

    /// Where each category lives inside an export, relative to the folder that
    /// holds `your_instagram_activity`. Instagram splits large categories
    /// across numbered files (`posts_1.json`, `posts_2.json`, …), so the
    /// numbered ones are walked until a gap.
    private static let savedPath    = "your_instagram_activity/saved/saved_posts.json"
    private static let likedPath    = "your_instagram_activity/likes/liked_posts.json"
    private static let postsStem    = "your_instagram_activity/media/posts_"
    private static let commentsStem = "your_instagram_activity/comments/post_comments_"
    /// Where the export states your own username — the one place it appears as
    /// data rather than inside a path. Without it every row you WROTE
    /// introduced itself as "Instagram" in the room's own post cards, beside
    /// saves that correctly name the account they came from.
    private static let selfPath     = "personal_information/personal_information.json"

    /// The name every row of this room carries.
    static let source = "Instagram"

    /// The OTHER four files under `media/` holding things you made, none of
    /// which were read until 2026-08-18 (prd §395). `posts_N.json` is the only
    /// numbered one and the only bare array; the rest are single-key envelopes
    /// whose key differs per category — which is exactly why `entries(in:)`
    /// below takes the first array it finds instead of matching a key we would
    /// have to keep in step with Meta's naming.
    ///
    /// Each carries its own `ref` prefix and its own §308 facet, so "my reels"
    /// and "my stories" are filters rather than hopes, and so a story and a
    /// post posted in the same second can never collide on one `sourceRef`.
    /// Archived posts and IGTV keep the plain `Post` facet — an archived post
    /// is a post you hid, not a different kind of object, and IGTV is a product
    /// Instagram itself retired.
    private static let ownMedia: [(path: String, ref: String, facet: String)] = [
        ("your_instagram_activity/media/reels.json",          "reel",     "Reel"),
        ("your_instagram_activity/media/stories.json",        "story",    "Story"),
        ("your_instagram_activity/media/archived_posts.json", "archived", "Post"),
        ("your_instagram_activity/media/igtv_videos.json",    "igtv",     "Post"),
    ]

    /// Picture extensions `ImportMedia.thumbnail` can actually decode.
    ///
    /// Load-bearing, and the reason a wordless VIDEO is still skipped: a
    /// captionless row's whole substance is its picture, and `CGImageSource`
    /// cannot open an `.mp4`. Landing one anyway would put a row titled "Photo"
    /// with no photo in it into a room whose grid promises pixels — the §83
    /// fake status, spelled as a placeholder.
    private static let pictureExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif",
    ]

    /// Whether the export's own path for an entry names a picture we can read.
    static func isPicture(uri: String?) -> Bool {
        guard let uri, let dot = uri.lastIndex(of: ".") else { return false }
        let ext = uri[uri.index(after: dot)...].lowercased()
        return pictureExtensions.contains(ext)
    }

    /// A saved or liked post's §308 facet, read off the permalink Meta wrote.
    ///
    /// Free — no request, no new field, no guess: Instagram encodes the KIND of
    /// post in its own URL path, and until now a saved reel and a saved
    /// photograph were indistinguishable in a room made mostly of saves. The
    /// YouTube-Shorts precedent (prd §312), one product over.
    ///
    /// `/tv/` is IGTV, which Instagram folded into reels; it answers the same
    /// facet because that is what the person would search for. Everything else
    /// — `/p/`, and anything Meta ships next — earns no extra facet rather than
    /// a guessed one: `Saved` and `Liked` already say what the row is.
    static func linkFacet(_ link: String) -> String? {
        let lower = link.lowercased()
        for marker in ["/reel/", "/reels/", "/tv/"] where lower.contains(marker) {
            return "Reel"
        }
        return nil
    }

    // MARK: - Run

    /// Imports an UNZIPPED export folder. Every category is optional — an
    /// export requested with only some boxes ticked is normal, and a missing
    /// file is not an error. `failed` is reserved for "this isn't an Instagram
    /// export at all": no category was found anywhere under the picked folder.
    @MainActor
    static func run(folder: URL, context: ModelContext,
                    progress: ((Int) -> Void)? = nil) async -> Summary {
        var summary = Summary()
        var landed: [Thing] = []
        // The stored rows themselves, not just their refs: a save landed by a
        // build before `authorHandle` existed carries no author, and a
        // re-import would dedupe it out and leave it faceless forever. The
        // export names the author every time, so a repeat pass repairs it
        // from the same field it would have landed with — no title-parsing,
        // no guess.
        let stored = IngestSupport.thingsByRef(context, source: "Instagram")
        var seen = Set(stored.keys)       // grows as we land, so two files can't collide
        var backfilled = false
        var foundAnyCategory = false
        // ref → the picture path the export states for that post.
        var mediaURIs: [String: String] = [:]

        if let data = read(savedPath, under: folder) {
            foundAnyCategory = true
            landSaves(data, key: "saved_saved_media", context: "saved",
                      summary: &summary, landed: &landed, seen: &seen,
                      stored: stored, backfilled: &backfilled)
        }
        if let data = read(likedPath, under: folder) {
            foundAnyCategory = true
            landSaves(data, key: "likes_media_likes", context: "liked",
                      summary: &summary, landed: &landed, seen: &seen,
                      stored: stored, backfilled: &backfilled)
        }
        // Read BEFORE the rows that wear it. Nil is normal (an export requested
        // without the profile box ticked has no such file) and costs only the
        // byline, never a row.
        let me = ownUsername(under: folder)
        for data in readNumbered(postsStem, under: folder) {
            foundAnyCategory = true
            landOwnMedia(data, refPrefix: "post", facet: "Post", me: me,
                         summary: &summary, landed: &landed, seen: &seen,
                         mediaURIs: &mediaURIs)
        }
        // Reels, stories, archived posts and IGTV (2026-08-18, prd §395). Same
        // reader, same shape, four files this importer had simply never opened
        // — so a person whose Instagram is mostly reels imported their comments
        // and nothing they had made in years.
        for category in ownMedia {
            guard let data = read(category.path, under: folder) else { continue }
            foundAnyCategory = true
            landOwnMedia(data, refPrefix: category.ref, facet: category.facet, me: me,
                         summary: &summary, landed: &landed, seen: &seen,
                         mediaURIs: &mediaURIs)
        }
        for data in readNumbered(commentsStem, under: folder) {
            foundAnyCategory = true
            landComments(data, summary: &summary, landed: &landed, seen: &seen)
        }

        if ImportOptions.includeMessages {
            for data in readInbox(under: folder) {
                foundAnyCategory = true
                landMessages(data, summary: &summary, landed: &landed, seen: &seen)
            }
        }

        guard foundAnyCategory else { return Summary(failed: true) }
        // The export's own pictures, before the rows go down so a thumbnail
        // rides the same insert (prd §310). Inside the scoped grant — there is
        // no second chance at a folder the person has stopped granting.
        let pixels = await ImportMedia.decode(
            mediaJobs(landed, uris: mediaURIs, under: folder))
        ImportMedia.apply(pixels, to: landed)
        await finish(&summary, landed: landed, backfilled: backfilled,
                     context: context, progress: progress)
        return summary
    }

    /// One save whose failure is REPORTED (a swallowed save behind a success
    /// screen is fake status), and one batched Spotlight submission rather
    /// than an XPC round-trip per row. Mirrors `DayOneImport.finish`.
    @MainActor
    private static func finish(_ summary: inout Summary, landed: [Thing],
                               backfilled: Bool, context: ModelContext,
                               progress: ((Int) -> Void)?) async {
        // A repeat import that landed nothing new may still have repaired
        // authors on rows already here; that needs its own save, but never a
        // receipt — nothing arrived, so All must not be told anything did.
        guard summary.imported > 0 else {
            if backfilled { _ = context.saveHonestly() }
            return
        }
        // Instagram is a `Corpus.bulkImportSources` member: its things stay
        // out of the All feed and live in their own room, so All learns the
        // import happened from this one reconciling row and nothing else.
        // Landed BEFORE the save, so the receipt rides the same transaction —
        // a receipt saved separately could survive a failed import.
        guard await ImportCommit.commit(landed, context: context, source: "Instagram", progress: progress) else {
            summary = Summary(failed: true)
            return
        }
        ImportReceipt.land(source: "Instagram", count: summary.imported,
                           detail: receiptDetail(summary), context: context)
        if (try? context.save()) == nil { summary = Summary(failed: true) }
    }

    /// Gives each landed post the picture its own export entry names.
    ///
    /// Posts only — a SAVE's picture belongs to whoever made it and Instagram
    /// does not ship those files, so there is nothing to attach.

    /// The pictures, in three parts so that NO `Thing` is ever held across a
    /// suspension — `jobs` reads the models synchronously and hands out plain
    /// values, `ImportMedia.decode` awaits with no model in scope at all, and
    /// `apply` writes back synchronously.
    ///
    /// The split is defensive rather than decorative, and worth stating because
    /// the obvious shortcut is wrong in a way that fails silently: the usual
    /// remedy for holding models across an await is to re-filter `.live`
    /// afterwards, and these rows have not been INSERTED yet, so `isLive`
    /// (`modelContext != nil`) is false for every one of them. That guard would
    /// skip the lot and disable media while every check reported green.
    ///
    /// (Un-inserted models are in fact safe to hold — nothing can tombstone a
    /// row that is not in the context, which is what the liveness rules are
    /// about. This shape avoids relying on that being true forever.)
    @MainActor
    private static func mediaJobs(_ landed: [Thing], uris: [String: String],
                                  under folder: URL) -> [ImportMedia.Job] {
        guard !uris.isEmpty else { return [] }
        var jobs: [ImportMedia.Job] = []
        for thing in landed where thing.kind == .note {
            guard jobs.count < ImportMedia.perImport,
                  let ref = thing.sourceRef, let uri = uris[ref],
                  let file = ImportMedia.resolve(uri, under: folder) else { continue }
            jobs.append(ImportMedia.Job(ref: ref, file: file))
        }
        return jobs
    }

    // MARK: - Private messages (only when asked — see `ImportOptions`)

    /// Every thread's `message_1.json` under `messages/inbox/`.
    ///
    /// Instagram files each conversation in its OWN folder, so unlike every
    /// other category here this is a DIRECTORY walk rather than a known path.
    /// Bounded at `writingCap` folders: a person can hand this any folder they
    /// like, and an unbounded enumeration of somebody's whole Files app is the
    /// same hazard `locate` already guards against elsewhere.
    private static func readInbox(under root: URL) -> [Data] {
        let manager = FileManager.default
        var roots = [root]
        if let children = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            roots += children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
        }
        for base in roots {
            let inbox = base.appending(path: "your_instagram_activity/messages/inbox")
            guard let threads = try? manager.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: nil), !threads.isEmpty else { continue }
            var out: [Data] = []
            for thread in threads.prefix(writingCap) {
                // `message_1.json` is the newest page; older pages are
                // `_2`, `_3` … and are deliberately not walked — the clamp
                // below keeps only the newest lines anyway, so reading them
                // would be work whose result is thrown away.
                if let data = try? Data(contentsOf: thread.appending(path: "message_1.json")) {
                    out.append(data)
                }
            }
            if !out.isEmpty { return out }
        }
        return []
    }

    /// One thing per CONVERSATION, never per message — see
    /// `XArchiveImport.landMessages` for the reasoning, which is the same here
    /// and deliberately produces the same shape.
    @MainActor
    private static func landMessages(_ data: Data, summary: inout Summary,
                                     landed: inout [Thing], seen: inout Set<String>) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return }
        let title = (root["title"] as? String).map(repairMojibake) ?? ""

        var lines: [(date: Date, text: String)] = []
        for message in messages {
            let raw = (message["content"] as? String) ?? ""
            let text = repairMojibake(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // Instagram stamps in MILLISECONDS here, unlike the seconds every
            // other category in this export uses.
            let ms = (message["timestamp_ms"] as? Double) ?? 0
            guard ms > 0 else { continue }
            let who = (message["sender_name"] as? String).map(repairMojibake) ?? ""
            lines.append((Date(timeIntervalSince1970: ms / 1000),
                          who.isEmpty ? text : "\(who): \(text)"))
        }
        guard !lines.isEmpty else { return }
        lines.sort { $0.date < $1.date }

        // Keyed on the thread's own title: the export's folder name carries a
        // per-export suffix, so a ref built from it would re-land every
        // conversation on the next import.
        let ref = "instagram:dm:\(title.lowercased())"
        guard !title.isEmpty, !seen.contains(ref) else { summary.skipped += 1; return }
        seen.insert(ref)

        var transcript = lines.suffix(transcriptLines).map(\.text).joined(separator: "\n")
        if transcript.count > transcriptBytes {
            transcript = String(transcript.suffix(transcriptBytes))
        }
        let thing = Thing(
            kind: .chat,
            title: String(localized: "Messages with \(title)"),
            content: transcript,
            source: "Instagram",
            capturedAt: lines.last?.date ?? Date(timeIntervalSince1970: 0),
            tags: ["Conversation"],
            sourceRef: ref
        )
        thing.authorHandle = title
        thing.messageCount = lines.count
        landed.append(thing)
        summary.messages += 1
    }

    /// `SnapchatImport`'s numbers — two rooms holding the same kind of object
    /// hold the same amount of it.
    private static let transcriptLines = 60
    private static let transcriptBytes = 4_000

    /// The receipt's own line — what the count is made of, in the order a
    /// person would care about. Only non-zero parts appear, so a saves-only
    /// export doesn't advertise three empty categories.
    private static func receiptDetail(_ s: Summary) -> String {
        var parts = [
            s.saved > 0 ? String(localized: "\(s.saved) saved") : nil,
            s.liked > 0 ? String(localized: "\(s.liked) liked") : nil,
            s.posts > 0 ? String(localized: "\(s.posts) posts") : nil,
            s.photos > 0 ? String(localized: "\(s.photos) photos") : nil,
            s.comments > 0 ? String(localized: "\(s.comments) comments") : nil,
            s.messages > 0 ? String(localized: "\(s.messages) conversations") : nil,
        ].compactMap { $0 }
        // A capped import SAYS SO — without it, truncated and complete read
        // identically here and in the room that follows.
        if s.dropped > 0 {
            parts.append(String(localized: "\(s.dropped) older not imported"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Saves and likes (a handle, a link, a date)

    /// Saves and likes share a shape: a list of entries each naming an author
    /// and carrying one permalink. They differ only in which envelope key
    /// holds them and whether the permalink rides `string_map_data` (saves) or
    /// `string_list_data` (likes) — so both readers are tried on both, since a
    /// format that changes under us should degrade to "nothing new", not to a
    /// silent zero.
    @MainActor
    private static func landSaves(_ data: Data, key: String, context marker: String,
                                  summary: inout Summary, landed: inout [Thing],
                                  seen: inout Set<String>,
                                  stored: [String: Thing], backfilled: inout Bool) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root[key] as? [[String: Any]] else { return }

        // Newest first BEFORE the cap — a cap applied to file order would keep
        // the oldest saves and drop everything recent.
        let dated: [(date: Date, handle: String, link: String)] = entries.compactMap { entry in
            guard let (href, stamp) = permalink(in: entry) else { return nil }
            let handle = (entry["title"] as? String).map(repairMojibake) ?? ""
            return (Date(timeIntervalSince1970: stamp), handle, href)
        }.sorted { $0.date > $1.date }
        summary.dropped += max(0, dated.count - tapCap)

        for row in dated.prefix(tapCap) {
            let ref = "instagram:\(marker):\(row.link)"
            guard !seen.contains(ref) else {
                // Already here — repair its author if it predates the field.
                // `isLive` because a heal or a CloudKit delete can tombstone a
                // row between the fetch above and this write.
                if let already = stored[ref], already.isLive,
                   already.authorHandle == nil, !row.handle.isEmpty {
                    already.authorHandle = row.handle
                    backfilled = true
                }
                summary.skipped += 1
                continue
            }
            seen.insert(ref)
            // The handle is the only name this row will ever have; a rare
            // entry with none falls back to the permalink so it is still
            // openable rather than being dropped.
            let name = row.handle.isEmpty ? row.link : "@" + row.handle
            // Saved/Liked says WHICH act; `Reel` says what kind of post it was,
            // read off Meta's own permalink (2026-08-18, prd §395) — free, and
            // the only thing separating a saved reel from a saved photograph in
            // a room made mostly of saves.
            var tags = [marker == "saved" ? "Saved" : "Liked"]
            if let facet = linkFacet(row.link) { tags.append(facet) }
            let thing = Thing(
                kind: .link,
                title: IngestSupport.titleLine(name),
                content: row.link,
                source: "Instagram",   // the literal — see `landOwnMedia`
                capturedAt: row.date,
                tags: tags,
                sourceRef: ref
            )
            // The WHY, in the slot the room's post card already draws it in
            // (`SocialThread.contextLabel`) — the same marker Farcaster, Bluesky
            // and X have carried since §239. A tag is a filter; this is the word
            // on the card, and the two are read by different things.
            thing.socialContext = marker
            // The handle is stored as a FIELD as well as spoken in the title
            // (2026-07-31). The title is display text — "@handle" or, for the
            // rare entry with no title, a bare URL — so grouping on it would
            // rank the "@" prefix and the fallback URLs as accounts. Every
            // reader that groups by author (`FeedInsight.leaderboard`'s
            // `handle(_:)`, the person surfaces) reads this instead, which is
            // what makes "Who you save most" possible at all: the export
            // names the author of each save, and this is the only place that
            // name is preserved as data rather than as a face.
            if !row.handle.isEmpty { thing.authorHandle = row.handle }
            landed.append(thing)
            if marker == "saved" { summary.saved += 1 } else { summary.liked += 1 }
        }
    }

    /// The permalink and its timestamp, from either envelope Instagram uses.
    /// `string_map_data` is keyed by a human label that differs per category
    /// ("Saved on", "Liked on"), so the FIRST value carrying an href is taken
    /// rather than matching a label we'd have to keep in step with Meta's copy.
    private static func permalink(in entry: [String: Any]) -> (String, Double)? {
        if let map = entry["string_map_data"] as? [String: Any] {
            for value in map.values {
                guard let field = value as? [String: Any],
                      let href = field["href"] as? String, !href.isEmpty else { continue }
                return (href, (field["timestamp"] as? Double) ?? 0)
            }
        }
        if let list = entry["string_list_data"] as? [[String: Any]] {
            for field in list {
                guard let href = field["href"] as? String, !href.isEmpty else { continue }
                return (href, (field["timestamp"] as? Double) ?? 0)
            }
        }
        return nil
    }

    // MARK: - Your own posts, reels, stories and archive

    /// Everything you MADE, from whichever of the five `media/` files it came
    /// out of. The caption may sit at the top level or on the first media item
    /// depending on whether the post was a single image or a carousel, so both
    /// are read.
    ///
    /// A CAPTIONLESS ENTRY NOW LANDS AS A PICTURE (2026-08-18, prd §395), where
    /// it used to be skipped outright. The old rule — "the media stays in the
    /// export, so a caption is the only substance such a row would have" — was
    /// written in §245, before §310 taught this importer to thumbnail the
    /// export's own files. It has pixels now, so a wordless photograph is a
    /// thing; skipping it silently dropped whole years for anyone whose posting
    /// is pictures rather than paragraphs. This is `XArchiveImport`'s own §375
    /// ruling, one product over, and it carries the same `Photo` facet.
    ///
    /// Only when the picture is one we can actually DECODE, though: `isPicture`
    /// gates on the file's own extension, so a wordless video is still skipped
    /// rather than landing as a row titled "Photo" with nothing behind it.
    @MainActor
    private static func landOwnMedia(_ data: Data, refPrefix: String, facet: String,
                                     me: String?, summary: inout Summary,
                                     landed: inout [Thing], seen: inout Set<String>,
                                     mediaURIs: inout [String: String]) {
        let dated: [(date: Date, caption: String, uri: String?)] = entries(in: data).compactMap { entry in
            let media = entry["media"] as? [[String: Any]] ?? []
            let rawCaption = (entry["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (media.first?["title"] as? String)
                ?? ""
            let stamp = (entry["creation_timestamp"] as? Double)
                ?? (media.first?["creation_timestamp"] as? Double)
                ?? 0
            let caption = repairMojibake(rawCaption).trimmingCharacters(in: .whitespacesAndNewlines)
            // The export states its own picture's path relative to the export
            // root. Carried through so `run` can thumbnail it while the scoped
            // grant is still held (prd §310).
            let uri = (entry["uri"] as? String) ?? (media.first?["uri"] as? String)
            guard stamp > 0, !caption.isEmpty || isPicture(uri: uri) else { return nil }
            return (Date(timeIntervalSince1970: stamp), caption, uri)
        }.sorted { $0.date > $1.date }
        summary.dropped += max(0, dated.count - writingCap)

        for row in dated.prefix(writingCap) {
            // The prefix is what keeps a story and a post published in the same
            // second from claiming one `sourceRef` — and `post` is spelled
            // exactly as it always was, so nothing already in a corpus moves.
            let ref = "instagram:\(refPrefix):\(Int(row.date.timeIntervalSince1970))"
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)
            let wordless = row.caption.isEmpty
            var tags = [facet]
            // Beside the facet, never instead of it: a wordless reel is still a
            // reel, and the room's grid membership reads this tag together with
            // the pixels (`FeedScreen.isInstagramPhotoTile`).
            if wordless { tags.append("Photo") }
            let thing = Thing(
                kind: .note,
                title: IngestSupport.titleLine(wordless ? String(localized: "Photo") : row.caption),
                content: row.caption,
                // The LITERAL, not `source`, in every `Thing(` in this file.
                // `source:` is the only thing a bridge and the demo seed are
                // guaranteed to agree on, so it is what `demo-parity-audit.py`
                // keys every one of its checks on — and a variable there makes
                // this room's rows unattributable to that audit, which then
                // silently stops checking them.
                source: "Instagram",
                capturedAt: row.date,
                tags: tags,
                sourceRef: ref
            )
            // The caption is a POST — the room draws every one of these as a
            // post card, and that card reads `postText` for the words it shows
            // (`title` is only ever `titleLine`'s 80-character clamp). Left nil
            // for a wordless picture, so the card shows the photograph rather
            // than the placeholder word under it.
            if !wordless { thing.postText = row.caption }
            // Whose post this is. Without it the card falls back to the SOURCE
            // name, so every row you wrote introduced itself as "Instagram"
            // beside saves correctly naming the account they came from.
            if let me, !me.isEmpty { thing.authorHandle = me }
            landed.append(thing)
            if let uri = row.uri, !uri.isEmpty { mediaURIs[ref] = uri }
            summary.posts += 1
            if wordless { summary.photos += 1 }
        }
    }

    /// The entries inside one `media/` file, whichever envelope it uses.
    ///
    /// `posts_N.json` is a bare array; `reels.json`, `stories.json`,
    /// `archived_posts.json` and `igtv_videos.json` each wrap theirs in a
    /// single-key object (`ig_reels_media`, `ig_stories`, …). The FIRST array of
    /// objects is taken rather than the key matched, for `permalink`'s reason
    /// one function up: the labels are Meta's copy, and a format that changes
    /// under us should degrade to "nothing new" rather than to a silent zero.
    private static func entries(in data: Data) -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = root as? [[String: Any]] { return array }
        guard let object = root as? [String: Any] else { return [] }
        for value in object.values {
            if let array = value as? [[String: Any]], !array.isEmpty { return array }
        }
        return []
    }

    /// Your own username, from the export's own profile file.
    ///
    /// Read as DATA rather than parsed out of a folder name: the zip unpacks to
    /// `instagram-<name>-<date>-<hash>/`, and taking the handle from there means
    /// splitting a string Meta is free to re-shape, on a screen where getting it
    /// wrong labels every post you ever wrote with somebody else's name.
    private static func ownUsername(under root: URL) -> String? {
        guard let data = read(selfPath, under: root),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = object["profile_user"] as? [[String: Any]]
        else { return nil }
        for profile in profiles {
            guard let map = profile["string_map_data"] as? [String: Any] else { continue }
            for key in ["Username", "username"] {
                if let name = field(map, key)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty {
                    return repairMojibake(name)
                }
            }
        }
        return nil
    }

    // MARK: - Your own comments (text, decontextualised on purpose)

    /// Comments you wrote. The parent post is NOT in the export — Instagram
    /// gives the comment and, usually, whose post it was on, so a row reads
    /// "on @handle" rather than pretending to quote something we don't have.
    @MainActor
    private static func landComments(_ data: Data, summary: inout Summary,
                                     landed: inout [Thing], seen: inout Set<String>) {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        let dated: [(date: Date, text: String, owner: String)] = entries.compactMap { entry in
            guard let map = entry["string_map_data"] as? [String: Any] else { return nil }
            let text = repairMojibake(field(map, "Comment") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let owner = repairMojibake(field(map, "Media Owner") ?? "")
            let stamp = stamp(map, "Time") ?? 0
            guard stamp > 0 else { return nil }
            return (Date(timeIntervalSince1970: stamp), text, owner)
        }.sorted { $0.date > $1.date }
        summary.dropped += max(0, dated.count - writingCap)

        for row in dated.prefix(writingCap) {
            // NOT `hashValue`: Swift seeds string hashing per PROCESS, so a
            // ref built from one would differ on every launch and a re-import
            // would duplicate every comment instead of deduping it.
            let ref = "instagram:comment:\(Int(row.date.timeIntervalSince1970))-\(stableHash(row.text))"
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)
            let face = row.owner.isEmpty ? row.text : "\(row.text) — on @\(row.owner)"
            landed.append(Thing(
                kind: .note,
                title: IngestSupport.titleLine(face),
                content: row.text,
                source: "Instagram",
                capturedAt: row.date,
                tags: ["Comment"],
                sourceRef: ref
            ))
            summary.comments += 1
        }
    }

    /// FNV-1a over the text's UTF-8, rendered hex. A `sourceRef` has to mean
    /// the same thing on every launch for dedupe to work at all, and Swift's
    /// own `hashValue` is seeded per process — so this is spelled out rather
    /// than borrowed. Two comments posted in the same second with the same
    /// text are the same comment for our purposes.
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    private static func field(_ map: [String: Any], _ key: String) -> String? {
        (map[key] as? [String: Any])?["value"] as? String
    }

    private static func stamp(_ map: [String: Any], _ key: String) -> Double? {
        (map[key] as? [String: Any])?["timestamp"] as? Double
    }

    // MARK: - Reading the folder

    /// A file at `relative`, looked for under the picked folder and then one
    /// level down. Instagram's zip unpacks to a named folder
    /// (`instagram-you-2026-07-31-abc123/`), and whether the person picks that
    /// folder or the one they extracted it into is a coin flip — so both work
    /// rather than the screen having to explain the difference.
    private static func read(_ relative: String, under root: URL) -> Data? {
        if let data = try? Data(contentsOf: root.appending(path: relative)) { return data }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            if let data = try? Data(contentsOf: child.appending(path: relative)) { return data }
        }
        return nil
    }

    /// The numbered files for a category (`posts_1.json`, `posts_2.json`, …),
    /// read until the first gap. Bounded rather than open-ended: a category
    /// that somehow numbered into the hundreds shouldn't hold the import open.
    private static func readNumbered(_ stem: String, under root: URL) -> [Data] {
        var out: [Data] = []
        for index in 1...20 {
            guard let data = read("\(stem)\(index).json", under: root) else { break }
            out.append(data)
        }
        return out
    }

    // MARK: - Mojibake

    /// Instagram writes its JSON as UTF-8 bytes that have already been escaped
    /// as if they were Latin-1, so an em dash arrives as "â€”" and an emoji as
    /// a run of four characters. This is a long-standing, well-known property
    /// of their export rather than a corrupt download, and left alone it puts
    /// the mangled form into both the title and the search index.
    ///
    /// The repair is only attempted when EVERY scalar fits in a byte — that is
    /// what makes a string a candidate for having been mis-decoded — and it is
    /// kept only when the re-decode round-trips into something different and
    /// valid. A caption that was always clean has scalars above 255 (any real
    /// emoji) or fails the round-trip, and is returned untouched.
    static func repairMojibake(_ text: String) -> String {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value < 256 }),
              text.unicodeScalars.contains(where: { $0.value > 127 })
        else { return text }
        let bytes = text.unicodeScalars.map { UInt8($0.value) }
        guard let repaired = String(bytes: bytes, encoding: .utf8), repaired != text
        else { return text }
        return repaired
    }
}
