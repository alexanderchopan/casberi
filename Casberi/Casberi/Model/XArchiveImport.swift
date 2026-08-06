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
        var seen = Set(IngestSupport.thingsByRef(context, source: "X").keys)
        var foundAnyCategory = false

        // "tweets" is the current name and "tweet" the older one; both are
        // read so an archive downloaded years ago still opens.
        var tweetFiles = readSeries("tweets", under: folder)
        if tweetFiles.isEmpty { tweetFiles = readSeries("tweet", under: folder) }
        for data in tweetFiles {
            foundAnyCategory = true
            landTweets(data, summary: &summary, landed: &landed, seen: &seen)
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
        let pixels = await ImportMedia.decode(mediaJobs(landed, under: folder))
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
        guard await ImportCommit.commit(landed, context: context, progress: progress) else {
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

    // MARK: - Your own posts and replies (full text — the substance)

    @MainActor
    private static func landTweets(_ data: Data, summary: inout Summary,
                                   landed: inout [Thing], seen: inout Set<String>) {
        guard let entries = parseArray(data) else { return }

        struct Row {
            let date: Date; let text: String; let id: String; let replyTo: String?
            /// The post this one answers, when the archive names it. Only ever
            /// used to recognise a SELF-reply — see `threadTexts`.
            let parentID: String?
            let likes: Int?
            let reposts: Int?
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
            let text = clean(raw, entities: tweet["entities"] as? [String: Any])
            guard !text.isEmpty, let date = created(tweet, id: id) else { continue }
            let replyTo = (tweet["in_reply_to_screen_name"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
            rows.append(Row(date: date, text: text, id: id, replyTo: replyTo,
                            parentID: parentIdentifier(tweet),
                            likes: metric(tweet, "favorite_count"),
                            reposts: metric(tweet, "retweet_count")))
        }
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
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
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
            let face = row.replyTo.map { "To @\($0) · \(row.text)" } ?? row.text
            var tags = [row.replyTo == nil ? "Post" : "Reply"]
            let thread = threads[row.id]
            if thread != nil { tags.append("Thread") }
            let thing = Thing(
                kind: .note,
                title: IngestSupport.titleLine(face),
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
            if !row.text.isEmpty { thing.enrichedText = row.text }
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
    private static func mediaJobs(_ landed: [Thing], under folder: URL) -> [ImportMedia.Job] {
        let index = ImportMedia.xMediaIndex(under: folder)
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
