import Foundation
import SwiftData

/// The X archive importer (2026-08-02, prd §280) — the Instagram pattern, with
/// three quirks that belong to this export alone and must not be smoothed over.
///
/// WHY AN IMPORT AND NOT A BRIDGE. X discontinued its free API tier for new
/// developers on 2026-02-06 and moved to pay-per-usage: $0.005 per post read,
/// $0.010 per user read, no free allowance of any size. There is no keyless
/// read, no RSS, and `cdn.syndication.twimg.com` — which used to answer a post
/// without a key — now returns `{}` (measured 2026-08-02). The archive is the
/// only door, so this seat is the ChatGPT grade, like Instagram and Snapchat.
/// Unlike Instagram, it can never be supplemented later: there is no paid tier
/// worth taking and no professional-account carve-out. What this file reads is
/// the whole of X in this app, permanently.
///
/// THE SPLIT, in prd §245's terms. What you MADE — your posts and replies —
/// arrives as full text with real timestamps, and is the substance here. What
/// you TAPPED — your likes — arrives BETTER than Instagram's saves did: X
/// stores each liked post's `fullText`, so a like lands wearing the words it
/// was liked for, not just a handle.
///
/// The archive names no author for a like — `expandedUrl` is
/// `x.com/i/web/status/<id>`, which identifies the post and never the person —
/// and until 2026-08-05 this doc concluded from that that the room could never
/// rank who you like most the way Instagram's saves rank who you save most.
/// That was a fact about the FILE mistaken for a fact about X:
/// `publish.x.com/oembed` answers any public post keylessly with its author.
/// `fetchFaces` is that second act, and the room ranks now.
///
/// THE HOLE, named rather than left to be discovered: **bookmarks are not in
/// the export.** They never have been, and nothing changed in 2026. Bookmarks
/// are the pile an X user would most want here, so the offer copy and the
/// setup screen both say plainly that they can't come — a silent absence would
/// read as a broken importer.
///
/// NOT BUILT, with reasons. (1) RETWEETS: the archive stores a retweet as your
/// own row whose text is `RT @someone: …`, truncated by X's own exporter at the
/// old 140-character limit. Landing that would put half of somebody else's
/// sentence in the corpus under your name — the fake-status ban, wearing a
/// different hat. They are skipped and counted. (2) DMs: the export holds full
/// message text and it would be the largest prose corpus in the file, but
/// whether years of private conversation belong in a searchable index is a
/// decision to make deliberately, not a side effect of tapping Import — the
/// Instagram ruling, unchanged. (3) Followers/following: names and dates,
/// no content — a tally, and a thing is never a tally.
///
/// MEDIA now lands, as of 2026-08-05 (prd §310) — as a 480pt THUMBNAIL, the
/// same one every other picture in this app is. The old decline was to copying
/// originals into a mirrored store, which is still refused; the export's files
/// stay exactly where they are. See `ImportMedia`.
///
/// ## LONG POSTS ARRIVE WHOLE (2026-08-13, prd §375)
///
/// `tweets.js` is not the whole export of your own writing, and until this date
/// this file behaved as though it were. A post over 280 characters is a NOTE:
/// X stores a clipped copy in `tweets.js` — cut mid-sentence, ending in a t.co
/// link back to itself — and the real body in `note-tweet.js`, a file nothing
/// here read. So the longest and most considered things in an archive were the
/// ones that landed damaged, silently, with a receipt saying they had arrived.
/// `noteTexts` reads that file and `landTweets` prefers its body whenever it is
/// LONGER than what `tweets.js` carried, which is the whole rule: a join that
/// went wrong can only ever leave the post as it was.
///
/// ## A PHOTO POST IS A PHOTO (2026-08-13, prd §375)
///
/// A post whose only content is a picture has, in the archive, exactly one
/// piece of text: the t.co shortlink standing in for the image. `clean` kept it
/// deliberately, because a row with no text at all was dropped — so those posts
/// landed titled `https://t.co/aBc123`, which is the naked-URL failure `OEmbed`
/// exists to fix, committed by us. Now a post with no words AND a picture in
/// the export lands as a PICTURE: no invented caption, no shortlink, and a tile
/// in the room's grid beside the Snapchat and Files rooms (`FeedScreen`'s
/// `.x` shape).
///
/// ## WHAT A REPLY WAS ANSWERING (2026-08-13, prd §375)
///
/// Most of a long archive is replies, and a reply alone is a non sequitur. Two
/// halves, in the order they cost: a SELF-reply's parent is already in this
/// file, so its words are filled in at import for free; a reply to somebody
/// else is `fetchReplyContext`, a second act like `fetchFaces` — one keyless
/// oEmbed request per reply, opt-in, resumable, and never a claim about a post
/// we couldn't read.
enum XArchiveImport {

    static let source = "X"

    struct Summary {
        var posts = 0
        var replies = 0
        var liked = 0
        var skipped = 0
        var retweets = 0        // seen and deliberately not landed
        /// Rows the cap refused — see `postCap`. Reported rather than swallowed:
        /// a truncated import renders exactly like a complete one, and the
        /// person is the only one who can tell whether the missing years matter.
        var droppedPosts = 0
        var droppedLikes = 0
        /// Private messages, landed only when `ImportOptions.includeMessages`
        /// says so. See that file — the default is off and stays off.
        var messages = 0
        /// Posts that came down whole because `note-tweet.js` held their real
        /// body (2026-08-13). Counted rather than folded into `posts` because
        /// it is the one number that says a truncation was REPAIRED — an
        /// archive with long posts and a zero here means the join failed, and
        /// the rows would look completely normal either way.
        var longform = 0
        /// Wordless picture posts, landed as pictures rather than as their own
        /// shortlink. Counted for the same reason: before 2026-08-13 these
        /// landed titled `https://t.co/…`, which looked like data.
        var photos = 0
        var failed = false

        var imported: Int { posts + replies + liked + messages }
        var dropped: Int { droppedPosts + droppedLikes }
    }

    /// Per-category caps rather than one shared budget — the Instagram rule,
    /// for the same reason and with different numbers. Your own posts are the
    /// substance of this export and run to tens of thousands for a long-time
    /// account, so they get the larger share; likes are the cheaper rows and
    /// must not be able to crowd them out.
    ///
    /// RAISED 2026-08-05 from 1,000/500, which was far too low and failed
    /// SILENTLY. A reported 3,500-post archive landed 1,500 rows: the receipt
    /// read "1000 posts · 500 liked" and nothing anywhere said that two
    /// thousand posts had been refused, so the room looked complete and every
    /// search over it was quietly answering from a third of the corpus. The
    /// numbers below cover a decade-long account outright; `droppedPosts` /
    /// `droppedLikes` make any archive past them say so.
    ///
    /// They are not unbounded, but the reason is no longer the main thread:
    /// since 2026-08-05 the landing runs through `ImportCommit`, which saves and
    /// yields in chunks, so a large archive no longer holds the UI (prd §310).
    /// What the cap bounds now is simply how much of a very long life belongs
    /// in one tap — and any archive past it SAYS SO rather than truncating in
    /// silence.
    private static let postCap = 10_000
    private static let likeCap = 5_000

    // MARK: - Run

    /// Imports an UNZIPPED archive folder. Every category is optional — an
    /// archive is one shape and always has tweets, but a brand-new account can
    /// legitimately have no likes. `failed` is reserved for "this isn't an X
    /// archive at all": neither category was found anywhere under the pick.
    @MainActor
    static func run(folder: URL, context: ModelContext,
                    progress: ((Int) -> Void)? = nil) async -> Summary {
        var summary = Summary()
        var landed: [Thing] = []
        // The rows already here, as THINGS and not just their refs (2026-08-06,
        // the `landMemories` move one room over): a ref set can answer "already
        // here" and nothing else, and the avatar below has to reach a room
        // somebody imported before it existed. `landTweets` repairs on the
        // dedupe hit, which is the only pass that will ever touch those rows —
        // the archive folder is a temporary scoped pick, so unlike topics or
        // room fields this cannot be healed from a later foreground.
        let existing = IngestSupport.thingsByRef(context, source: "X")
        var seen = Set(existing.keys)
        var foundAnyCategory = false

        // "tweets" is the current name and "tweet" the older one; both are
        // read so an archive downloaded years ago still opens.
        // WHOSE archive this is (2026-08-06). Read before the posts because
        // every one of them wants it: `PostCard` leads with `authorHandle`,
        // and without one every row in the room introduced itself as "X" —
        // the room's own name, said three thousand times.
        //
        // Nothing depends on it. A missing or renamed `account.js` yields nil
        // and the rows land exactly as they did before, so this can only ever
        // add a handle, never lose a post.
        let mine = accountHandle(under: folder)
        // And your FACE, from the same archive (2026-08-06). `PostCard` has
        // always drawn `authorAvatarURL` when a row carries one and the source
        // icon when it doesn't — so before this every post in the room wore the
        // X logo, three thousand times, in a room that is entirely your own
        // writing. Same contract as the handle above: nil changes nothing.
        let face = accountAvatarURL(under: folder)
        // The long-form bodies, read BEFORE the posts because every post wants
        // to be asked about (2026-08-13). A missing or renamed `note-tweet.js`
        // yields an empty table and the posts land exactly as they did before,
        // so this can only ever repair a truncation, never cause one.
        let notes = noteTexts(under: folder)
        // The picture index, read ONCE for the whole import and used twice: to
        // tell a wordless photo post from an empty row while landing, and to
        // thumbnail the rows afterwards. It used to be built inside `mediaJobs`
        // — that is a full directory enumeration, and doing it twice for one
        // import would be the same cost paid for no reason.
        let pictures = ImportMedia.xMediaIndex(under: folder)
        var tweetFiles = readSeries("tweets", under: folder)
        if tweetFiles.isEmpty { tweetFiles = readSeries("tweet", under: folder) }
        for data in tweetFiles {
            foundAnyCategory = true
            landTweets(data, mine: mine, avatar: face, notes: notes,
                       pictures: Set(pictures.keys), existing: existing,
                       summary: &summary, landed: &landed, seen: &seen)
        }
        for data in readSeries("like", under: folder) {
            foundAnyCategory = true
            landLikes(data, summary: &summary, landed: &landed, seen: &seen)
        }
        // Only when explicitly asked. `readSeries` is reused so a long DM
        // history split across `-part1`, `-part2` … is read whole, exactly
        // like the tweets are.
        if ImportOptions.includeMessages {
            for data in readSeries("direct-messages", under: folder) {
                foundAnyCategory = true
                landMessages(data, summary: &summary, landed: &landed, seen: &seen)
            }
        }

        guard foundAnyCategory else { return Summary(failed: true) }
        // The archive's own pictures, before the rows go down so a thumbnail
        // rides the same insert (prd §310). Inside the scoped grant, which is
        // why this can't be a later heal — there is no second chance at a
        // folder the person has stopped granting.
        let pixels = await ImportMedia.decode(mediaJobs(landed, index: pictures))
        ImportMedia.apply(pixels, to: landed)
        await finish(&summary, landed: landed, context: context, progress: progress)
        return summary
    }

    /// Chunked landing whose failure is REPORTED (a swallowed save behind a
    /// success screen is fake status). The rows go through `ImportCommit` —
    /// insert, save, index, yield, per chunk — and the receipt is landed only
    /// once they are all down, so a partial run is never crowned with a receipt
    /// claiming a total it didn't reach. Mirrors `InstagramImport.finish`.
    @MainActor
    private static func finish(_ summary: inout Summary, landed: [Thing],
                               context: ModelContext,
                               progress: ((Int) -> Void)?) async {
        guard summary.imported > 0 else { return }
        // X is a `Corpus.bulkImportSources` member: its things stay out of the
        // All feed and live in their own room, so All learns the import
        // happened from this one reconciling row and nothing else. Landed
        // The rows first, in chunks that each save and yield (`ImportCommit`),
        // then the receipt — so a run that dies partway leaves real things and
        // no receipt claiming a total it never reached.
        guard await ImportCommit.commit(landed, context: context, source: "X", progress: progress) else {
            summary = Summary(failed: true)
            return
        }
        ImportReceipt.land(source: "X", count: summary.imported,
                           detail: receiptDetail(summary), context: context)
        if (try? context.save()) == nil { summary = Summary(failed: true) }
    }

    /// The receipt's own line. Only non-zero parts appear, so a likes-only
    /// archive doesn't advertise two empty categories.
    ///
    /// A capped import SAYS SO. Without that clause the receipt for a
    /// truncated archive is word-for-word the receipt for a complete one, and
    /// the room that follows looks equally finished either way — the honesty
    /// rule's fake-status ban, in the one place a person could still act on it
    /// (by trimming the archive, or by asking for the cap to move).
    private static func receiptDetail(_ s: Summary) -> String {
        var parts = [
            s.posts > 0   ? String(localized: "\(s.posts) posts") : nil,
            s.replies > 0 ? String(localized: "\(s.replies) replies") : nil,
            s.liked > 0   ? String(localized: "\(s.liked) liked") : nil,
            s.messages > 0 ? String(localized: "\(s.messages) conversations") : nil,
        ].compactMap { $0 }
        if s.dropped > 0 {
            parts.append(String(localized: "\(s.dropped) older not imported"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Repairing rows that predate the room's own shape

    /// Give rows landed before 2026-08-06 the three fields the room now DRAWS.
    ///
    /// Until the X room had a shape of its own, nothing rendered a post's full
    /// sentence, nobody's handle, and no reply's recipient — so the importer
    /// had no reason to fill `postText`, `socialContext` or `parent`. All
    /// three are derivable from what those rows already hold, which is the
    /// point: no archive, no folder grant, no network. A re-import CANNOT do
    /// this job, because `landTweets` skips a ref it has already seen.
    ///
    /// It deliberately does not reach `authorHandle` for your own posts. Only
    /// `account.js` names you, and a handle is the one thing here worth
    /// nothing if guessed — those rows keep the room's own icon until the next
    /// import.
    ///
    /// One-shot through a UserDefaults flag, so the steady state costs a
    /// `bool(forKey:)` and no fetch — `ScreenshotTopics.restamp`'s shape, for
    /// the same reason, and chunked with a yield for the same one too: this
    /// dirties every row in the room, and one save over thousands of models is
    /// the freeze `ImportCommit` exists to avoid. `postText == nil` is the
    /// fetch's cheap first cut and an exact proxy for "landed before this
    /// date": every row the importer lands now sets it.
    @MainActor
    static func healRoom(context: ModelContext, chunk: Int = 200) async -> Int {
        let key = "x.roomFields.backfill"
        guard !UserDefaults.standard.bool(forKey: key) else { return 0 }
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == "X" && $0.postText == nil })
        // A post keeps its words in `content`; a liked post keeps a PERMALINK
        // there and its words in `enrichedText`. Reading the wrong one would
        // put a bare URL in the card's body.
        func words(of thing: Thing) -> String {
            (thing.kind == .link ? (thing.enrichedText ?? "") : thing.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // The recipient, back out of the title the importer wrote it into.
        // Reading our OWN format rather than inferring anything: `landTweets`
        // has led a reply's title with exactly "To @<handle> · " since the
        // seat shipped, so this is as exact as the archive was.
        func repliedTo(_ thing: Thing) -> String? {
            guard thing.kind == .note, thing.title.hasPrefix("To @"),
                  let sep = thing.title.range(of: " · ") else { return nil }
            let handle = thing.title[thing.title.index(thing.title.startIndex, offsetBy: 4)..<sep.lowerBound]
            return handle.isEmpty ? nil : String(handle)
        }
        func liked(_ thing: Thing) -> Bool {
            thing.kind == .link && thing.tags.contains("Liked") && thing.socialContext == nil
        }
        // Rows this pass can actually change. A liked post whose text never
        // came down has no words to copy and keeps `postText == nil` forever,
        // so it is filtered OUT here rather than left to be revisited — and
        // never stamped with an empty `postText` to push it out of the
        // predicate, which was the other way and is wrong: `Verbs` reads
        // `postText ?? content` for a copy body, so an empty string would take
        // away the permalink such a row carries instead of words.
        let pending = ((try? context.fetch(descriptor)) ?? []).filter {
            guard !Corpus.isImportReceipt($0) else { return false }
            return !words(of: $0).isEmpty || liked($0)
                || ($0.parent == nil && repliedTo($0) != nil)
        }
        guard !pending.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return 0
        }
        var changed = 0
        for (offset, thing) in pending.enumerated() {
            // Per-ROW liveness, not a re-filter of the array (COROLLARY 6):
            // this list is held across every yield below, and a bridge heal
            // can tombstone a row inside one.
            if thing.isLive {
                let text = words(of: thing)
                if !text.isEmpty { thing.postText = text }
                if liked(thing) { thing.socialContext = "liked" }
                if thing.parent == nil, let handle = repliedTo(thing) {
                    thing.parent = SocialCard(handle: handle, text: "", avatarURL: nil, url: nil, ref: nil)
                }
                changed += 1
            }
            if offset % chunk == chunk - 1 {
                _ = context.saveHonestly()
                await Task.yield()
            }
        }
        if changed > 0 { _ = context.saveHonestly() }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// The account's own `@handle`, from the archive's `account.js`.
    ///
    /// Pure and failure-tolerant by construction: every step is an optional
    /// read and the whole thing returns nil rather than guessing, because the
    /// one thing worse than an unnamed post is somebody else's name on it.
    /// The leading "@" is dropped — `PostCard` renders a handle as written and
    /// the rest of the app stores them bare.
    static func accountHandle(under root: URL) -> String? {
        for data in readSeries("account", under: root) {
            guard let entries = parseArray(data) else { continue }
            for entry in entries {
                let account = (entry["account"] as? [String: Any]) ?? entry
                guard let name = account["username"] as? String else { continue }
                let handle = name.trimmingCharacters(in: CharacterSet(charactersIn: " @"))
                if !handle.isEmpty { return handle }
            }
        }
        return nil
    }

    /// The account's own avatar, from the archive's `profile.js`.
    ///
    /// **Fenced to one host, and that is not a formality.** This URL comes out
    /// of a file the person picked off their disk, and it goes straight into a
    /// `RemoteThumb` that fetches it — so an unfenced read lets a data file
    /// name an arbitrary host for the app to call, and lets it do so once per
    /// row on a screen full of them. The same reasoning as `OEmbed.endpoints`
    /// being an allowlist rather than following the spec's own discovery, and
    /// as `ImportMedia`'s fence on a relative path. HTTPS only, and the host
    /// must be X's own image CDN matched on the LABEL boundary — `pbs.twimg.com`
    /// itself or a subdomain of it, never `pbs.twimg.com.attacker.example`.
    ///
    /// It can go stale: an archive downloaded two years ago names the avatar
    /// you had two years ago, and X may have stopped serving that file. That
    /// costs a row its face and falls back to the source icon, which is exactly
    /// what every row looks like today.
    static func accountAvatarURL(under root: URL) -> String? {
        for data in readSeries("profile", under: root) {
            guard let entries = parseArray(data) else { continue }
            for entry in entries {
                let profile = (entry["profile"] as? [String: Any]) ?? entry
                guard let raw = profile["avatarMediaUrl"] as? String,
                      let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
                      url.scheme?.lowercased() == "https",
                      let host = url.host?.lowercased(),
                      host == avatarHost || host.hasSuffix("." + avatarHost)
                else { continue }
                return url.absoluteString
            }
        }
        return nil
    }

    /// X's image CDN — the only host an archive is allowed to point the app at.
    private static let avatarHost = "pbs.twimg.com"

    // MARK: - Your own posts and replies (full text — the substance)

    @MainActor
    private static func landTweets(_ data: Data, mine: String?, avatar: String?,
                                   notes: [String: String], pictures: Set<String>,
                                   existing: [String: Thing], summary: inout Summary,
                                   landed: inout [Thing], seen: inout Set<String>) {
        guard let entries = parseArray(data) else { return }

        struct Row {
            let date: Date; let text: String; let id: String; let replyTo: String?
            /// The post this one answers, when the archive names it. Used to
            /// recognise a SELF-reply (see `threadTexts`), and since
            /// 2026-08-13 to build the parent's own permalink.
            let parentID: String?
            let likes: Int?
            let reposts: Int?
            /// Nothing but a picture — no words of its own. See the type doc.
            let wordless: Bool
            /// This post's body came from `note-tweet.js` rather than from the
            /// clipped copy in `tweets.js`. Carried on the row rather than
            /// counted where it is discovered, so the count is incremented
            /// once, where the row actually LANDS or is repaired — a post the
            /// cap refused never happened, and must not be reported as fixed.
            let longform: Bool
        }
        var rows: [Row] = []
        for entry in entries {
            // An entry is either `{"tweet": {…}}` or the tweet object itself,
            // depending on when the archive was generated.
            let tweet = (entry["tweet"] as? [String: Any]) ?? entry
            guard let id = identifier(tweet) else { continue }
            let raw = (tweet["full_text"] as? String) ?? (tweet["text"] as? String) ?? ""
            // A retweet is somebody else's words, truncated by X's own
            // exporter. Counted so the screen can say it skipped them, never
            // landed. See the type doc.
            if raw.hasPrefix("RT @") || tweet["retweeted_status"] != nil {
                summary.retweets += 1
                continue
            }
            let entities = tweet["entities"] as? [String: Any]
            var text = clean(raw, entities: entities)
            // THE LONG BODY, when this post is a note (2026-08-13). Taken only
            // when it is longer than what `tweets.js` carried: `note-tweet.js`
            // is joined on an id out of a second file, and the one thing a
            // wrong join must never be able to do is shorten a post.
            var longform = false
            if let long = notes[id], long.count > text.count {
                text = long
                longform = true
            }
            // A PICTURE POST. `wordsWithoutMedia` is empty exactly when the
            // post's only text was the shortlink standing in for its own
            // image; paired with a file in the export, that is a photograph
            // and not an empty row.
            let wordless = wordsWithoutMedia(raw, entities: entities).isEmpty
                && pictures.contains(id)
            guard !text.isEmpty || wordless, let date = created(tweet, id: id) else { continue }
            let replyTo = (tweet["in_reply_to_screen_name"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
            rows.append(Row(date: date, text: wordless ? "" : text, id: id, replyTo: replyTo,
                            parentID: parentIdentifier(tweet),
                            likes: metric(tweet, "favorite_count"),
                            reposts: metric(tweet, "retweet_count"),
                            wordless: wordless, longform: longform))
        }
        // Every post's own words, keyed by id — what fills in a SELF-reply's
        // parent for free (2026-08-13). Built over the whole file before the
        // cap, exactly as `threadTexts` is, so a continuation still knows what
        // it was answering even when the parent itself was capped out.
        let textByID = Dictionary(rows.map { ($0.id, $0.text) },
                                  uniquingKeysWith: { a, _ in a })
        // Threads, before the cap so a chain is measured over the whole file.
        let threads = threadTexts(rows.map { ($0.id, $0.parentID, $0.text, $0.date) })
        // Newest first BEFORE the cap — a cap over file order would keep the
        // oldest posts and drop everything recent.
        rows.sort { $0.date > $1.date }
        summary.droppedPosts += max(0, rows.count - postCap)

        for row in rows.prefix(postCap) {
            // Keyed on the tweet id alone, NOT on whether it reads as a reply:
            // the ref has to survive this file deciding differently about the
            // same post, or a re-import would land it twice.
            let ref = "x:tweet:\(row.id)"
            guard !seen.contains(ref) else {
                // REPAIR ON THE DEDUPE HIT (2026-08-06, the Snapchat-tag
                // shape). A room imported before the face was read can only be
                // reached from here: the avatar lives in the archive folder,
                // which is a temporary scoped pick, so no later foreground
                // sweep can go and get it the way topics and room fields are
                // healed. Without this a re-import would skip every row it
                // already had and change nothing, which reads as the fix not
                // having landed.
                if let existingRow = existing[ref], existingRow.isLive {
                    if existingRow.authorHandle == nil, let mine { existingRow.authorHandle = mine }
                    if existingRow.authorAvatarURL == nil, let avatar { existingRow.authorAvatarURL = avatar }
                    // THE TRUNCATION, repaired in place (2026-08-13). A room
                    // imported before `note-tweet.js` was read holds every long
                    // post cut mid-sentence, and — like the avatar above — this
                    // is the only pass that can ever reach it: the bodies live
                    // in the archive folder, a temporary scoped pick, so no
                    // later foreground sweep can go and get them.
                    //
                    // Longer only, and the stored vector is dropped with the
                    // change: a row whose words grew by three paragraphs is
                    // described by an embedding of its opening sentence.
                    if row.longform, row.text.count > existingRow.content.count {
                        existingRow.content = row.text
                        existingRow.postText = row.text
                        existingRow.title = IngestSupport.titleLine(
                            face(reply: row.replyTo, text: row.text, wordless: row.wordless))
                        existingRow.embedding = nil
                        summary.longform += 1
                    }
                }
                summary.skipped += 1
                continue
            }
            seen.insert(ref)
            // A reply says who it was to. The parent post is NOT in the
            // archive, so the row names the recipient rather than pretending
            // to quote something we don't have — the Instagram comment rule.
            //
            // THE RECIPIENT LEADS, and that is the §303 clamp ruling rather
            // than a style choice. `titleLine` cuts at 80 characters, so a
            // trailing "— to @someone" is precisely what the cut eats: every
            // reply longer than about sixty characters — most of them — landed
            // with no visible recipient at all, and the one word that makes a
            // reply searchable ("@someone") never reached the title, which is
            // the field the retriever scores highest. Leading with it survives
            // the clamp and costs the tail of a sentence whose full text is on
            // `content` regardless.
            var tags = [row.replyTo == nil ? "Post" : "Reply"]
            let thread = threads[row.id]
            if thread != nil { tags.append("Thread") }
            // A §308 facet for the picture posts, so "photos I posted" is a
            // filter rather than a hope. It rides beside Post/Reply rather than
            // replacing either: a wordless picture is still a post or still a
            // reply, and the room's own grid membership reads the pixels, not
            // this tag.
            if row.wordless { tags.append("Photo"); summary.photos += 1 }
            if row.longform { summary.longform += 1 }
            let thing = Thing(
                kind: .note,
                title: IngestSupport.titleLine(
                    face(reply: row.replyTo, text: row.text, wordless: row.wordless)),
                content: row.text,
                source: "X",
                capturedAt: row.date,
                tags: tags,
                sourceRef: ref
            )
            // A THREAD's head carries the whole chain as retrieval text
            // (2026-08-05, prd §307). X only ever surfaces a thread if you find
            // its head; here, a word from the fourth post finds the first one,
            // and the on-device model reading this row reads the argument
            // rather than its opening sentence.
            //
            // The continuations still land as their own rows, deliberately —
            // they were real posts, folding them away would change what
            // `sourceRef` means for rows already in the store, and a re-import
            // has to stay stable. This adds a way IN to the thread; it doesn't
            // rewrite what the archive was.
            if let thread {
                thing.enrichedText = thread.text
                thing.messageCount = thread.count
            }
            // THE WORDS, in the field the room actually draws (2026-08-06).
            // `title` is `titleLine`'s 80-character clamp and `content` is
            // what the retriever reads — neither is what `PostCard` renders,
            // which is `postText`, and until the X room had a shape of its own
            // nothing rendered a post's full sentence at all. No new field:
            // `postText` has been on `Thing` since prd 81's social pass, and
            // this is the same fact arriving through a different door.
            //
            // `row.text`, never `face` — the "To @someone · " lead belongs to
            // the clamped title, where it survives a cut that would eat it at
            // the end. The card has room to say who a reply answers on its own
            // line and shouldn't repeat it inside the sentence.
            //
            // Never an EMPTY string on a picture post (2026-08-13): `Verbs`
            // copies `postText ?? content`, so an empty one there would hand
            // somebody a blank clipboard where a nil hands them the row —
            // `healRoom`'s ruling, one field over.
            if !row.text.isEmpty { thing.postText = row.text }
            // Yours, when the archive said so. Same slot a liked post's author
            // lands in, which is what lets one card render both halves of the
            // room without asking which half it's drawing.
            thing.authorHandle = mine
            // …and your face beside it. Only ever on YOUR OWN posts: a liked
            // row's author is somebody else and X's oEmbed serves no image at
            // all, so `landLikes` has nothing to put here and must not borrow
            // this one — a stranger's post wearing your avatar is the plainest
            // fake status there is.
            thing.authorAvatarURL = avatar
            // WHO A REPLY ANSWERS, in the slot the card already draws
            // (2026-08-06). `PostCard` renders `parent` as "Replying to
            // @someone" and reads NOTHING else off the card — not its text,
            // not a permalink, not a protocol ref — so a handle-only card
            // states exactly what the archive knows and fabricates none of
            // the post we don't have. Without it the recipient survived only
            // in `title`'s "To @someone · " lead, which the card doesn't
            // draw, and a room of replies would have read as a room of
            // non sequiturs.
            //
            // `ref` deliberately stays nil: it is what `foldThreadReplies`
            // walks, and X's chains are already handled at import (a head
            // carries its own `enrichedText`).
            //
            // TWO FIELDS ADDED 2026-08-13, and they are the difference between
            // a label and context. `url` is the parent's own permalink, built
            // from the two things the archive states — who was answered and
            // which post — which makes the sheet's `ReplyingToCard` a door
            // rather than a caption, and is what `fetchReplyContext` reads to
            // ask X what that post said. `text` is filled here, for free, for
            // a SELF-reply: the post being answered is in this very file, so a
            // thread continuation carries the sentence it continues with no
            // request at all. A reply to somebody else keeps an empty `text`
            // until the second act names it — never a guess, and
            // `ReplyingToCard` draws no words when there are none.
            if let replyTo = row.replyTo {
                thing.parent = SocialCard(
                    handle: replyTo,
                    text: parentPreview(row.parentID.flatMap { textByID[$0] }),
                    avatarURL: nil,
                    url: row.parentID.map { permalink(handle: replyTo, id: $0) },
                    ref: nil)
            }
            // What the post actually did. No new field — `likeCount` and
            // `repostCount` have been on `Thing` since prd 81's social pass,
            // and this is the same fact from a different door. A count is never
            // a thing on its own (the module doctrine), but it makes the one
            // superlative worth asking answerable: your best post, which X's
            // own product makes remarkably hard to find.
            thing.likeCount = row.likes
            thing.repostCount = row.reposts
            landed.append(thing)
            if row.replyTo == nil { summary.posts += 1 } else { summary.replies += 1 }
        }
    }

    /// Self-reply chains, as the full text of each thread keyed by its HEAD.
    ///
    /// A self-reply is recognised without knowing whose archive this is: a post
    /// whose parent id is ALSO IN THIS FILE is by definition a reply to
    /// something the same person wrote. That is exact and needs no user id,
    /// no handle and no guess — the two fields the archive would otherwise
    /// force us to infer it from (`in_reply_to_user_id`, and the account's own
    /// id, which is in a different file entirely).
    ///
    /// Bounded at `threadCap` posts per chain — that is the real bound, and no
    /// thread anybody wrote needs more. The `seen` set beside it is NOT what
    /// stops a cycle: a node has exactly one parent, so a cycle is by
    /// construction unreachable from a head (a head is a node with no parent in
    /// the file). It guards the one shape that CAN revisit an id — an archive
    /// listing the same post twice, where a child list can hold a duplicate.
    private static func threadTexts(_ rows: [(id: String, parent: String?,
                                              text: String, date: Date)])
        -> [String: (text: String, count: Int)] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Child lists, so a head can be walked DOWN its own chain.
        var children: [String: [String]] = [:]
        for row in rows {
            guard let parent = row.parent, byID[parent] != nil else { continue }
            children[parent, default: []].append(row.id)
        }
        guard !children.isEmpty else { return [:] }

        // A head is a post with children of its own that is not itself a
        // continuation — the first post of the thread as written.
        var out: [String: (text: String, count: Int)] = [:]
        for row in rows {
            guard children[row.id] != nil else { continue }
            if let parent = row.parent, byID[parent] != nil { continue }
            var parts: [String] = []
            var cursor: String? = row.id
            var seen = Set<String>()
            while let id = cursor, parts.count < threadCap, seen.insert(id).inserted {
                guard let post = byID[id] else { break }
                parts.append(post.text)
                // Oldest child first — a thread is written in order, and X
                // stores no explicit sequence.
                cursor = children[id]?
                    .compactMap { byID[$0] }
                    .min(by: { $0.date < $1.date })?
                    .id
            }
            guard parts.count > 1 else { continue }
            out[row.id] = (parts.joined(separator: "\n\n"), parts.count)
        }
        return out
    }

    /// A thread longer than this is almost certainly a malformed archive rather
    /// than something somebody wrote.
    private static let threadCap = 60

    /// The post this one answers. `_str` first for the same reason
    /// `identifier` prefers `id_str`: a modern snowflake is past the range
    /// where a JSON number survives as a Double.
    private static func parentIdentifier(_ tweet: [String: Any]) -> String? {
        if let s = tweet["in_reply_to_status_id_str"] as? String, !s.isEmpty { return s }
        if let n = tweet["in_reply_to_status_id"] as? UInt64 { return String(n) }
        if let s = tweet["in_reply_to_status_id"] as? String, !s.isEmpty { return s }
        return nil
    }

    /// An engagement count, which the archive writes as a STRING in every
    /// vintage seen ("favorite_count": "12") and which some tools rewrite as a
    /// number. Both are read; anything else is absent rather than zero, since
    /// a post with no count recorded is not a post nobody liked.
    private static func metric(_ tweet: [String: Any], _ key: String) -> Int? {
        if let s = tweet[key] as? String, let n = Int(s) { return n }
        if let n = tweet[key] as? Int { return n }
        return nil
    }

    // MARK: - Your likes (text AND a link — better than Instagram's saves)

    /// Liked posts. Each entry is `{"like": {tweetId, fullText, expandedUrl}}`
    /// — real words, which is why these land as openable links carrying their
    /// own retrieval text rather than as bare handles.
    ///
    /// NO AUTHOR, and no way to derive one: `expandedUrl` is
    /// `https://x.com/i/web/status/<id>`, which names the post and never the
    /// person who wrote it. That is why this room can't rank who you like the
    /// way Instagram's room ranks who you save.
    @MainActor
    private static func landLikes(_ data: Data, summary: inout Summary,
                                  landed: inout [Thing], seen: inout Set<String>) {
        guard let entries = parseArray(data) else { return }

        struct Row { let date: Date; let text: String; let link: String; let id: String }
        var rows: [Row] = []
        for entry in entries {
            let like = (entry["like"] as? [String: Any]) ?? entry
            guard let id = (like["tweetId"] as? String) ?? identifier(like) else { continue }
            let text = clean((like["fullText"] as? String) ?? "", entities: nil)
            let link = (like["expandedUrl"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? "https://x.com/i/web/status/\(id)"
            // A like carries NO timestamp anywhere in the archive, so its date
            // comes from the post's own id. See `snowflakeDate`.
            guard let date = snowflakeDate(id) else { continue }
            rows.append(Row(date: date, text: text, link: link, id: id))
        }
        rows.sort { $0.date > $1.date }
        summary.droppedLikes += max(0, rows.count - likeCap)

        for row in rows.prefix(likeCap) {
            let ref = "x:like:\(row.id)"
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)
            // A like whose text didn't come down (a deleted post, an older
            // archive) still lands: the link is openable and dated, which is
            // more than a dropped row would be.
            let thing = Thing(
                kind: .link,
                title: IngestSupport.titleLine(row.text.isEmpty ? row.link : row.text),
                content: row.link,
                source: "X",
                capturedAt: row.date,
                tags: ["Liked"],
                sourceRef: ref
            )
            // The words are the whole reason a like is worth keeping, and
            // `title` is clamped to 80 characters — so the full text rides
            // `enrichedText`, which is what the answer path actually reads.
            //
            // And `postText` beside it (2026-08-06), which is what the room
            // DRAWS. `enrichedText` is retrieval-only by the 2026-07-15
            // ruling, so until now a liked post's full sentence was in the
            // store and on no screen: the room showed its first eighty
            // characters and nothing else could reach the rest. Both, not one
            // — they are read by different halves of the app and collapsing
            // them would quietly change what the answer path indexes.
            if !row.text.isEmpty {
                thing.enrichedText = row.text
                thing.postText = row.text
            }
            // WHY this row is here (2026-08-06). Half the X room is somebody
            // else's writing, and once every row renders as a post card the
            // author's handle is the only thing separating the halves — which
            // says nothing at all for the years before `fetchFaces` has named
            // one. `socialContext` is the existing marker for exactly this
            // ("Liked", "Mentions you", "Recast"), so the room gets the same
            // word every other social room already wears, drawn by the same
            // `SocialThread.contextLabel`.
            thing.socialContext = "liked"
            landed.append(thing)
            summary.liked += 1
        }
    }

    /// Gives each landed post the picture the archive filed under its id.
    ///
    /// Only YOUR OWN posts have media in the archive — a liked post's pictures
    /// are somebody else's and X does not ship them — so this reaches `.note`
    /// rows and skips the likes, which is why it keys on the tweet id inside
    /// `sourceRef`.

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
    private static func mediaJobs(_ landed: [Thing],
                                  index: [String: URL]) -> [ImportMedia.Job] {
        guard !index.isEmpty else { return [] }
        var jobs: [ImportMedia.Job] = []
        for thing in landed where thing.kind == .note {
            guard jobs.count < ImportMedia.perImport,
                  let ref = thing.sourceRef, ref.hasPrefix("x:tweet:") else { continue }
            let id = String(ref.dropFirst("x:tweet:".count))
            if let file = index[id] { jobs.append(ImportMedia.Job(ref: ref, file: file)) }
        }
        return jobs
    }

    // MARK: - The second act: who wrote the things you liked

    struct FaceResult {
        var named = 0
        var missed = 0
        /// Posts X says are deleted or private — a real answer, not a failure,
        /// and the one thing in this room a person cannot learn on X itself.
        var gone = 0
        /// Every attempt failed WITHOUT a status, and at least one was made:
        /// the honest read on an endpoint that has changed or a network that
        /// isn't there. Deletions are excluded on purpose — an archive full of
        /// long-dead posts would otherwise report the endpoint as broken every
        /// pass, which is the opposite of what happened.
        var unreachable: Bool { named == 0 && gone == 0 && missed > 0 }
    }

    /// Liked posts still missing their author.
    @MainActor
    static func pendingFaceCount(context: ModelContext) -> Int {
        pending(context: context).count
    }

    /// A liked row is pending while `authorHandle` is nil.
    ///
    /// Deliberately NOT TikTok's test (`title == content`, a row still wearing
    /// its own URL): an X like lands with the post's real WORDS as its title
    /// because `like.js` carries `fullText`. What it can never carry is the
    /// author — `expandedUrl` is `x.com/i/web/status/<id>`, which names the
    /// post and not the person — so the missing field is the author, and the
    /// author is what this pass exists to fetch.
    @MainActor
    private static func pending(context: ModelContext) -> [Thing] {
        let name = source
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.live.filter {
            // A row X has told us is gone stays unnamed forever, so without
            // this it would be re-asked on every pass for the life of the
            // install — spending a request per dead post to learn the same
            // thing again. The "Gone" tag is the answer, not a pending state.
            $0.kind == .link && $0.tags.contains("Liked")
                && $0.authorHandle == nil && !$0.tags.contains("Gone")
        }
    }

    /// Names the author of each liked post, from X's own keyless oEmbed
    /// endpoint, one request each (prd §280 amendment, 2026-08-05).
    ///
    /// A SEPARATE, EXPLICIT ACT — the ruling that split Snapchat's media fetch
    /// (§246) and TikTok's face pass (§279) out of their imports. The import
    /// itself is instant and offline; this reaches X once per liked post, and
    /// a person importing years of likes should choose to spend that rather
    /// than discover it. Unlike Snapchat's, it is under no deadline: a public
    /// post does not expire the way an export's download links do, so an
    /// unfinished pass simply resumes.
    ///
    /// WHY IT IS WORTH A REQUEST AT ALL. `XArchiveImport`'s own type doc said
    /// this room "can't rank who you like most the way Instagram's room ranks
    /// who you save most" — true of the ARCHIVE, and not true of X, which
    /// publishes the author of any public post keylessly at
    /// `publish.x.com/oembed`. That endpoint was already in `OEmbed.endpoints`
    /// for saved links; this points it at the rows the import landed. Once a
    /// handle is stamped the room's leaderboard, the handle-scoped ask
    /// ("what did I like from @someone") and Spotlight all read it for free.
    ///
    /// UNMEASURED against a real archive's likes, like everything else in this
    /// file. Every failure returns nil and leaves the row exactly as it landed,
    /// so a dead endpoint costs a pass and never a face that was already right.
    @MainActor
    @discardableResult
    static func fetchFaces(limit: Int = 200, context: ModelContext) async -> FaceResult {
        let waiting = pending(context: context).prefix(limit)
        let jobs: [Job] = waiting.compactMap { thing in
            guard let ref = thing.sourceRef, let url = URL(string: thing.content) else { return nil }
            return Job(ref: ref, url: url)
        }
        guard !jobs.isEmpty else { return FaceResult() }

        // Four at a time, the shared ceiling every bulk fetch in this app uses.
        let answers = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            let outcome = await OEmbed.ask(job.url)
            return (job.ref, outcome.response, outcome.status)
        }

        let byRef = IngestSupport.thingsByRef(context, source: source)
        var result = FaceResult()
        var changed: [Thing] = []
        for (ref, embed, status) in answers {
            guard let thing = byRef[ref], thing.isLive else { continue }
            // GONE is recorded on the row, not just counted (2026-08-05). It is
            // the read this room can make that X cannot: your own archive
            // remembers a post that no longer exists anywhere. Marked with a
            // tag rather than a new field, so it is filterable and searchable
            // the day it lands and needs no CloudKit deploy.
            if OEmbed.meansGone(status) {
                result.gone += 1
                if !thing.tags.contains("Gone") {
                    thing.tags.append("Gone")
                    changed.append(thing)
                }
                continue
            }
            guard let embed, apply(embed, to: thing) else { result.missed += 1; continue }
            result.named += 1
            changed.append(thing)
        }
        if !changed.isEmpty {
            context.saveHonestly()
            SpotlightIndex.index(changed)
        }
        return result
    }

    private struct Job: Sendable {
        let ref: String
        let url: URL
    }

    // MARK: - The other second act: what a reply was answering

    struct ContextResult {
        /// Replies that now carry the words they were answering.
        var filled = 0
        /// Parents X says are deleted or private. The reply keeps its
        /// recipient and loses only the door — see `fetchReplyContext`.
        var gone = 0
        var missed = 0
        /// Every attempt failed WITHOUT a status, and at least one was made —
        /// `FaceResult.unreachable`'s reasoning exactly, including why
        /// deletions are excluded from it.
        var unreachable: Bool { filled == 0 && gone == 0 && missed > 0 }
    }

    /// Replies still missing the post they answer.
    @MainActor
    static func pendingContextCount(context: ModelContext) -> Int {
        pendingContext(context: context).count
    }

    /// A reply is pending while its parent card has a permalink and no words.
    ///
    /// Three clauses, each load-bearing. A card with no `url` predates
    /// 2026-08-13 or came from an archive that named no parent id, and there is
    /// nothing to ask about. A card with words is either a self-reply (filled
    /// at import, for free) or one this pass already answered. And a card whose
    /// parent turned out to be gone has had its `url` cleared, which is what
    /// takes it out of this queue for good — see `fetchReplyContext`.
    @MainActor
    private static func pendingContext(context: ModelContext) -> [Thing] {
        let name = source
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.live.filter {
            guard $0.kind == .note, let parent = $0.parent else { return false }
            return parent.text.isEmpty && !(parent.url ?? "").isEmpty
        }
    }

    /// Fills in the post each reply was answering, from X's own keyless oEmbed
    /// endpoint, one request each (2026-08-13, prd §375).
    ///
    /// WHY IT IS WORTH A REQUEST. Most of a long-lived account's archive is
    /// replies, and a reply on its own is a non sequitur: "yes, exactly this"
    /// filed under your name in 2019 with no way to learn what "this" was. X's
    /// own product cannot answer it either once the conversation is old. The
    /// import already names the RECIPIENT — that is free, it is in the file —
    /// and this names what they SAID, which is the difference between a label
    /// and context. `ReplyingToCard` in the thing sheet has drawn those words
    /// since the social pass; there were simply never any to draw.
    ///
    /// A SEPARATE, EXPLICIT ACT, like `fetchFaces` and for its reasons: the
    /// import is instant and offline, this is one request per reply, and
    /// somebody importing a decade of them should choose to spend that rather
    /// than discover it. Under no deadline either — a public post does not
    /// expire — so an unfinished pass simply resumes.
    ///
    /// A GONE PARENT LOSES ITS DOOR AND KEEPS ITS NAME. When X answers 404 /
    /// 410 / 403 the card's `url` is cleared: the row still says who was
    /// answered (the archive's own fact, still true), the sheet stops offering
    /// a door onto a post that isn't there (P4 — a control that does nothing),
    /// and the row leaves this queue permanently. That is deliberately NOT the
    /// "Gone" tag `fetchFaces` uses: there it is the LIKED POST — the row
    /// itself — that has died, and tagging your own surviving reply the same
    /// way would make the facet mean two different things.
    ///
    /// UNMEASURED against a real archive. Every failure returns nil and leaves
    /// the row exactly as it landed.
    @MainActor
    @discardableResult
    static func fetchReplyContext(limit: Int = 200, context: ModelContext) async -> ContextResult {
        let waiting = pendingContext(context: context).prefix(limit)
        let jobs: [Job] = waiting.compactMap { thing in
            guard let ref = thing.sourceRef,
                  let raw = thing.parent?.url, let url = URL(string: raw) else { return nil }
            return Job(ref: ref, url: url)
        }
        guard !jobs.isEmpty else { return ContextResult() }

        // Four at a time, the shared ceiling every bulk fetch in this app uses.
        let answers = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            let outcome = await OEmbed.ask(job.url)
            return (job.ref, outcome.response, outcome.status)
        }

        let byRef = IngestSupport.thingsByRef(context, source: source)
        var result = ContextResult()
        var changed: [Thing] = []
        for (ref, embed, status) in answers {
            guard let thing = byRef[ref], thing.isLive, var card = thing.parent else { continue }
            if OEmbed.meansGone(status) {
                result.gone += 1
                card.url = nil
                thing.parent = card
                changed.append(thing)
                continue
            }
            guard let embed, let words = embed.title, !words.isEmpty else {
                result.missed += 1
                continue
            }
            card.text = parentPreview(words)
            // The handle X answers with beats the one the archive recorded: a
            // reply from 2016 names whoever that account was called in 2016,
            // and a renamed account's old handle is a dead link and an
            // unsearchable name. Only ever an overwrite with something real.
            if let handle = embed.authorHandle, !handle.isEmpty { card.handle = handle }
            thing.parent = card
            result.filled += 1
            changed.append(thing)
        }
        if !changed.isEmpty {
            context.saveHonestly()
            SpotlightIndex.index(changed)
        }
        return result
    }

    /// Writes an oEmbed answer onto a liked row.
    ///
    /// The HANDLE is the point — it groups, so it is what the room's board and
    /// a handle-scoped ask read. The author's display NAME joins `enrichedText`
    /// beside the post's words, which is retrieval substance rather than
    /// chrome: "what did I like from Paul Graham" then reaches a post whose
    /// title is only its own sentence.
    ///
    /// THE TITLE IS LEFT ALONE, unlike TikTok's pass. A TikTok save arrives
    /// wearing a bare URL and has nothing to lose; an X like already arrives
    /// wearing the post's real words, which are a better face than anything
    /// this answer carries. Overwriting them with the same text re-fetched
    /// would spend a write, drop the row's vector and change nothing a person
    /// can see.
    @MainActor
    private static func apply(_ embed: OEmbed.Response, to thing: Thing) -> Bool {
        var changed = false
        if let handle = embed.authorHandle, thing.authorHandle != handle {
            thing.authorHandle = handle
            changed = true
        }
        if let author = embed.authorName {
            let words = thing.enrichedText ?? thing.title
            let enriched = "\(words) · \(author)"
            if !words.contains(author), thing.enrichedText != enriched {
                thing.enrichedText = enriched
                changed = true
            }
        }
        // A changed row's stored vector describes text that no longer matches
        // it — dropped so the next semantic sweep re-embeds on the real words.
        if changed { thing.embedding = nil }
        return changed
    }

    // MARK: - Private messages (only when asked — see `ImportOptions`)

    /// Direct-message conversations, one thing per CONVERSATION rather than one
    /// per message.
    ///
    /// A message is not a thing: on its own it is a fragment with no subject,
    /// and ten thousand of them would bury a corpus in the same way §246 said
    /// Snapchat's per-snap history would. A conversation IS one — it has two
    /// people, a span and a subject — which is also exactly the shape
    /// `SnapchatImport` already lands, so this room and that one agree about
    /// what a chat looks like without either having to know about the other.
    ///
    /// The transcript is CLAMPED like Snapchat's, newest-biased, for its
    /// reason: `content` is what the retriever reads and what a bubble view
    /// draws, and a decade of one friendship should be neither. `messageCount`
    /// carries the real total, so the room can rank on the whole conversation
    /// rather than on the slice that was kept.
    ///
    /// UNMEASURED, like everything else in this file. Every failure returns
    /// early, so a shape that isn't what this expects lands nothing at all
    /// rather than landing something wrong.
    @MainActor
    private static func landMessages(_ data: Data, summary: inout Summary,
                                     landed: inout [Thing], seen: inout Set<String>) {
        guard let entries = parseArray(data) else { return }

        for entry in entries {
            let conversation = (entry["dmConversation"] as? [String: Any]) ?? entry
            guard let id = conversation["conversationId"] as? String, !id.isEmpty,
                  let messages = conversation["messages"] as? [[String: Any]]
            else { continue }

            var lines: [(date: Date, text: String)] = []
            for wrapper in messages {
                guard let create = (wrapper["messageCreate"] as? [String: Any]) else { continue }
                let raw = (create["text"] as? String) ?? ""
                let text = clean(raw, entities: create["urls"].map { ["urls": $0] })
                guard !text.isEmpty else { continue }
                let stamp = (create["createdAt"] as? String).flatMap(isoStamp) ?? Date(timeIntervalSince1970: 0)
                lines.append((stamp, text))
            }
            guard !lines.isEmpty else { continue }
            lines.sort { $0.date < $1.date }

            let ref = "x:dm:\(id)"
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)

            let kept = lines.suffix(transcriptLines)
            var transcript = kept.map(\.text).joined(separator: "\n")
            if transcript.count > transcriptBytes {
                transcript = String(transcript.suffix(transcriptBytes))
            }
            let newest = lines.last?.date ?? Date(timeIntervalSince1970: 0)
            let thing = Thing(
                kind: .chat,
                title: String(localized: "Messages · \(lines.count) in a conversation"),
                content: transcript,
                source: "X",
                capturedAt: newest,
                tags: ["Conversation"],
                sourceRef: ref
            )
            thing.messageCount = lines.count
            landed.append(thing)
            summary.messages += 1
        }
    }

    /// Newest N lines kept, inside a byte ceiling — `SnapchatImport`'s numbers,
    /// deliberately the same so two rooms holding the same kind of object hold
    /// the same amount of it.
    private static let transcriptLines = 60
    private static let transcriptBytes = 4_000

    /// X stamps a DM in ISO 8601 (`2019-04-16T12:34:56.000Z`), not the
    /// `created_at` shape its tweets use.
    private static func isoStamp(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    // MARK: - Dates

    /// A tweet's own `created_at`, or — when that field is missing or in a
    /// shape we don't know — the date encoded in its id.
    private static func created(_ tweet: [String: Any], id: String) -> Date? {
        if let raw = tweet["created_at"] as? String,
           let parsed = twitterDateFormatter.date(from: raw) {
            return parsed
        }
        return snowflakeDate(id)
    }

    /// "Wed Mar 21 20:50:14 +0000 2006". Pinned to POSIX and UTC: the month and
    /// weekday names in this field are always English regardless of the
    /// person's locale, and a device formatter would fail to parse them for
    /// anyone whose phone isn't in English.
    private static let twitterDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return f
    }()

    /// The date inside a post id.
    ///
    /// Every X id since November 2010 is a snowflake: its top bits are a
    /// millisecond timestamp offset from a fixed epoch (1288834974657). This is
    /// the ONLY way to date a liked post — `like.js` carries no timestamp of
    /// any kind — and it is exact, not an estimate.
    ///
    /// VERIFIED 2026-08-02, not taken from a doc: id 2044919377544261979
    /// decodes to 2026-04-16, which is the date `publish.x.com` independently
    /// reports for that same post.
    ///
    /// Ids from before the snowflake era are small sequential integers with no
    /// date in them at all — id 20 (the first tweet, 2006) decodes to the epoch
    /// itself, 2010-11-04, which would be a confident wrong answer. So anything
    /// below the first snowflake is refused rather than dated.
    static func snowflakeDate(_ id: String) -> Date? {
        guard let value = UInt64(id), value >= 30_000_000_000 else { return nil }
        let ms = (value >> 22) + 1_288_834_974_657
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    // MARK: - Text

    /// A post's words, made readable.
    ///
    /// Two repairs, both measured properties of this export rather than
    /// guesses. (1) X escapes `&`, `<` and `>` inside `full_text`, so a post
    /// about "Q&amp;A" arrives wearing the entity and would be indexed that
    /// way. (2) Every link in a post is stored as its t.co shortening, which
    /// names nothing and is unsearchable; `entities.urls` carries the real
    /// destination for each one, so they are swapped back. A link with no
    /// expansion is left as it is rather than dropped — an opaque link still
    /// opens.
    private static func clean(_ raw: String, entities: [String: Any]?) -> String {
        let full = expandedText(raw, entities: entities)
        let stripped = wordsWithoutMedia(raw, entities: entities)
        return stripped.isEmpty ? full : stripped
    }

    /// The post with its own picture links taken out — EMPTY exactly when the
    /// post was nothing but a picture (2026-08-13).
    ///
    /// A PICTURE'S OWN SHORTLINK (2026-08-06). An attached photo, video or GIF
    /// puts a bare `t.co` shortlink in `full_text` and files itself under
    /// `entities.media` — a DIFFERENT key from the `urls` `expandedText`
    /// swaps — so that shortlink survived every clean and rode into `content`
    /// on every post anybody ever attached an image to. X's own client has
    /// never shown it, and downstream it was worse than ugly: `ScreenshotTopics`
    /// read `t.co` as a hostname, it cleared `normalize` (four characters,
    /// three letters, no stoplist entry), it recurred across thousands of rows,
    /// and `cells` — which credits each row to its single most common
    /// qualifying term — collapsed the whole room into one cell labelled `t.co`
    /// under the title "What you post about".
    ///
    /// Split out of `clean` rather than folded into it because the two answers
    /// mean different things and one caller needs both: `clean` must never
    /// return an empty string for a photo-only post (an empty row was dropped,
    /// so every picture would stop importing), while `landTweets` needs to know
    /// that emptiness is exactly what happened, so it can file the row as a
    /// photograph instead of as its own shortlink.
    static func wordsWithoutMedia(_ raw: String, entities: [String: Any]?) -> String {
        let text = expandedText(raw, entities: entities)
        guard let media = entities?["media"] as? [[String: Any]], !media.isEmpty else {
            return text
        }
        var stripped = text
        for item in media {
            guard let short = item["url"] as? String, !short.isEmpty else { continue }
            stripped = stripped.replacingOccurrences(of: short, with: " ")
        }
        return stripped
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The post's words with its t.co links swapped back and its entities
    /// decoded — everything `clean` does except the picture-link strip.
    private static func expandedText(_ raw: String, entities: [String: Any]?) -> String {
        guard !raw.isEmpty else { return "" }
        var text = raw
        if let urls = entities?["urls"] as? [[String: Any]] {
            for url in urls {
                guard let short = url["url"] as? String, !short.isEmpty,
                      let full = url["expanded_url"] as? String, !full.isEmpty
                else { continue }
                text = text.replacingOccurrences(of: short, with: full)
            }
        }
        return IngestSupport.decodeHTMLEntities(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Long-form posts (`note-tweet.js`)

    /// The real body of every post too long for `tweets.js`, keyed by the tweet
    /// it belongs to (2026-08-13, prd §375).
    ///
    /// X files a post over 280 characters as a NOTE: `tweets.js` keeps a copy
    /// cut mid-sentence with a t.co link back to the note, and the body lives
    /// here. `landTweets` prefers this text whenever it is LONGER, which is the
    /// safety property of the whole feature — a join that resolves to the wrong
    /// id, or to nothing, can only leave the post exactly as it was.
    ///
    /// UNMEASURED against a real archive, like everything else in this file.
    /// Both known spellings of the join key are tried and every step is an
    /// optional read, so a shape this doesn't recognise contributes nothing.
    static func noteTexts(under root: URL) -> [String: String] {
        var out: [String: String] = [:]
        for data in readSeries("note-tweet", under: root) {
            guard let entries = parseArray(data) else { continue }
            for entry in entries {
                let note = (entry["noteTweet"] as? [String: Any]) ?? entry
                let core = (note["core"] as? [String: Any]) ?? note
                guard let raw = core["text"] as? String, !raw.isEmpty,
                      let id = noteTarget(note) else { continue }
                let text = clean(raw, entities: noteEntities(core))
                guard !text.isEmpty else { continue }
                // Longest wins. A note that was edited appears more than once
                // in some vintages, and the fullest copy is the one to keep —
                // the same rule the caller applies against `tweets.js`.
                if text.count > (out[id]?.count ?? 0) { out[id] = text }
            }
        }
        return out
    }

    /// Which post a note belongs to. `lifecycle.initialTweetId` is the join X
    /// documents; `noteTweetId` is the NOTE's own id and is deliberately not
    /// used as a fallback — it does not equal the tweet id, so accepting it
    /// would file a body against a post that never had one.
    private static func noteTarget(_ note: [String: Any]) -> String? {
        if let lifecycle = note["lifecycle"] as? [String: Any] {
            if let s = lifecycle["initialTweetId"] as? String, !s.isEmpty { return s }
            if let n = lifecycle["initialTweetId"] as? UInt64 { return String(n) }
        }
        if let s = note["tweetId"] as? String, !s.isEmpty { return s }
        return nil
    }

    /// A note's links in the shape `clean` reads.
    ///
    /// `note-tweet.js` spells the same fact in camelCase (`expandedUrl`) where
    /// `tweets.js` uses snake_case (`expanded_url`) — the field-case drift this
    /// export is already known for (see `TikTokImport`'s two eras). Both are
    /// accepted; a note with no `urls` at all yields nil and its t.co links are
    /// left as they are, which is what `clean` already does for a post whose
    /// link carries no expansion.
    private static func noteEntities(_ core: [String: Any]) -> [String: Any]? {
        guard let urls = core["urls"] as? [[String: Any]] else { return nil }
        let mapped: [[String: Any]] = urls.compactMap { entry in
            guard let short = entry["url"] as? String, !short.isEmpty,
                  let full = (entry["expandedUrl"] as? String)
                    ?? (entry["expanded_url"] as? String), !full.isEmpty
            else { return nil }
            return ["url": short, "expanded_url": full]
        }
        return mapped.isEmpty ? nil : ["urls": mapped]
    }

    // MARK: - Small shapes the landing reads

    /// A row's clamped face. The recipient LEADS a reply (the §303 clamp
    /// ruling, see the call site) and a wordless picture post says so plainly
    /// rather than wearing the shortlink that used to stand in for its image.
    static func face(reply: String?, text: String, wordless: Bool) -> String {
        if wordless { return String(localized: "Photo") }
        return reply.map { "To @\($0) · \(text)" } ?? text
    }

    /// A post's own web address, from the two facts the archive states.
    ///
    /// X resolves a status by its ID and ignores the handle in the path, so
    /// this is a real permalink even for an account that has since been
    /// renamed — and it is also what `fetchReplyContext` hands to oEmbed.
    static func permalink(handle: String, id: String) -> String {
        "https://x.com/\(handle)/status/\(id)"
    }

    /// What a parent card carries of the post it names.
    ///
    /// Clamped, because this text is stored inside the reply's own row — a
    /// thread of forty self-replies would otherwise keep thirty-nine copies of
    /// its own chain, and the card draws two lines of it. nil or blank in,
    /// empty out: an empty `text` is what `ReplyingToCard` reads as "we don't
    /// know what that post said", which is the truth for a reply to somebody
    /// else until the second act runs.
    static func parentPreview(_ text: String?) -> String {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return "" }
        guard text.count > parentPreviewChars else { return text }
        return String(text.prefix(parentPreviewChars)) + "…"
    }

    private static let parentPreviewChars = 280

    /// A tweet's id as a string, from whichever field this archive's vintage
    /// used. `id` may arrive as a JSON number, which for a modern snowflake is
    /// beyond Double's exact integer range — so `id_str` is preferred and a
    /// numeric `id` is read as an integer, never through a Double.
    private static func identifier(_ tweet: [String: Any]) -> String? {
        if let s = tweet["id_str"] as? String, !s.isEmpty { return s }
        if let n = tweet["id"] as? UInt64 { return String(n) }
        if let s = tweet["id"] as? String, !s.isEmpty { return s }
        return nil
    }

    // MARK: - Reading the folder

    /// A category's files: `data/<base>.js`, then `data/<base>-part1.js`,
    /// `-part2.js` … until the first gap. X splits a large category across
    /// numbered parts and a long-lived account really does have several.
    /// Bounded rather than open-ended.
    private static func readSeries(_ base: String, under root: URL) -> [Data] {
        var out: [Data] = []
        if let first = read("data/\(base).js", under: root) { out.append(first) }
        for index in 1...50 {
            guard let data = read("data/\(base)-part\(index).js", under: root) else { break }
            out.append(data)
        }
        return out
    }

    /// A file at `relative`, looked for under the picked folder and then one
    /// level down. An X archive unzips to a named folder
    /// (`twitter-2026-08-02-abc123/`), and whether the person picks that folder
    /// or the one they extracted it into is a coin flip — so both work rather
    /// than the screen having to explain the difference. Mirrors
    /// `InstagramImport.read`.
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

    /// The array inside one of the archive's files.
    ///
    /// These are NOT JSON files despite holding JSON: each is a JavaScript
    /// assignment, `window.YTD.tweets.part0 = [ … ]`, meant to be loaded by the
    /// archive's own offline viewer. Handing one straight to
    /// `JSONSerialization` fails on the very first character, which is the kind
    /// of failure that reads as an empty export rather than as a format
    /// mismatch. The prefix contains no bracket, so cutting at the first `[` is
    /// enough and doesn't need the assignment's shape parsed.
    ///
    /// Plain JSON is tried first anyway, so a file already unwrapped by some
    /// other tool still reads.
    static func parseArray(_ data: Data) -> [[String: Any]]? {
        if let direct = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return direct
        }
        guard let open = data.firstIndex(of: UInt8(ascii: "[")) else { return nil }
        let json = data[open...]
        return try? JSONSerialization.jsonObject(with: json) as? [[String: Any]]
    }
}
