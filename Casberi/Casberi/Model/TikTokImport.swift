import Foundation
import SwiftData

/// The TikTok importer (2026-08-02, prd §279) — the Instagram/Snapchat grade,
/// and the amendment to a ruling this app made twice.
///
/// WHY THIS EXISTS AT ALL. §36 declined TikTok on 2026-07-09 under a
/// live-data-only rule ("their export lands 1–4 days stale and never updates"),
/// and §244 restated that decline on 2026-07-31. Both were weighing the export
/// as a FEED, where 1–4 days stale is fatal. As an IMPORT it is not a defect:
/// nothing here claims to be current, every row is stamped with the moment it
/// actually happened, and a save from 2021 is exactly as true today as it was
/// when the export was cut. The same reasoning already shipped twice on the
/// same day §244 was written — Instagram (§245) and Snapchat (§246) are both
/// export-only, both justified because no live door exists. TikTok's three
/// other doors are still shut (no RSS ever; the Display API returns only the
/// authenticated account's OWN posts; the DMA Data Portability API is EEA-only
/// and needs the post-M2 server), which by §245's own test makes the export not
/// the stale option but the only one.
///
/// THE EXPIRY IS THE ARGUMENT FOR THIS, NOT AGAINST IT. TikTok's download link
/// dies four days after it's ready. The export is the perishable artifact; the
/// corpus is not. That is the same reasoning that built `SnapchatImport`'s
/// media fetch against a 7-day window — a short window is a reason to get the
/// data out, not a reason to leave it there.
///
/// TWO SCHEMA ERAS, BOTH READ. TikTok reorganised the export's top level: the
/// older shape files activity under `Activity`, the newer under `Your Activity`
/// with likes and favourites moved out to `Likes and Favorites`. Real exports
/// in the wild carry either, and at least one carries both. Every category
/// below is therefore looked up against a list of candidate paths rather than
/// one — the `_get_first` shape the d3i research parser uses, for the same
/// reason it does.
///
/// FIELD CASE IS NOT CONSISTENT WITHIN ONE FILE. This is measured from real
/// export type definitions, not defended against speculatively: `CommentsList`
/// entries spell their fields `date`/`comment`/`url` in lower case while the
/// `VideoList` of your own posts spells them `Date`/`Link`/`Title` in upper,
/// and the link field itself is variously `Link`, `VideoLink` or `link`
/// depending on category and era. So every field read here goes through
/// `field(_:_:)`, which tries each candidate in both cases. A fixed key would
/// give a silent zero on half the categories.
///
/// WHAT LANDS, AND WHAT DOES NOT. The export's split is the same one §245
/// forced into Instagram's copy, and it is stated in the offer for the same
/// reason:
///
///   - What you MADE — your videos' captions, your comments — is real
///     searchable text, and lands as such.
///   - What you TAPPED — saved and liked videos — arrives as a bare link and
///     nothing else. No caption, no creator, no thumbnail.
///
/// Unlike Instagram's saves, though, these rows are not stuck that way, and
/// that is the one place TikTok is the BETTER import: an Instagram save arrives
/// carrying its author's handle and nothing can add to it (`instagram_oembed`
/// answers with no title, author or thumbnail — measured 2026-08-02, which is
/// why it was removed from `OEmbed.endpoints` entirely). TikTok's oEmbed
/// endpoint is live, keyless, and answers with the caption, the creator and the
/// poster art. So a save imported here can be given a real face — see
/// `fetchFaces`, the second act.
///
/// DELIBERATELY NOT LANDED, with reasons:
///
///   - WATCH HISTORY (`Video Browsing History` / `Watch History`) is by far the
///     largest list in the export and is a record of what scrolled PAST you,
///     not what you chose. Landing it would bury every deliberate save under
///     thousands of videos nobody picked. Same call as Snapchat's
///     `snap_history.json` (§246).
///   - SEARCH HISTORY, FOLLOWERS, FOLLOWING are terms and usernames with no
///     content — a tally, and the module doctrine says a thing is never a
///     tally. §245 declined Instagram's follower list on this exact ground.
///   - DIRECT MESSAGES are in the export and would be the largest prose corpus
///     in it. §245's ruling holds unchanged: whether years of private
///     conversation belong in a searchable index is a decision the person makes
///     deliberately, not a side effect of tapping Import.
///   - LOGIN HISTORY, ADS, SHOPPING are account records, not things.
///
/// UNMEASURED AGAINST A REAL EXPORT. Every path and field name here is derived
/// from four independent parsers of real exports (a research-grade donation
/// parser handling both eras, two archivers, and a published TypeScript type
/// definition) rather than from a file this project has opened. The link
/// canonicalisation in `TikTokLink` IS measured live — see its own note. A
/// missing or renamed category is a skip, never a failure, so a schema drift
/// degrades to "nothing new" rather than to a wrong number.
enum TikTokImport {

    static let source = "TikTok"

    struct Summary {
        var saved = 0
        var liked = 0
        var posts = 0
        var comments = 0
        var skipped = 0
        /// Rows the cap refused. Reported rather than swallowed — see `tapCap`.
        var dropped = 0
        var failed = false

        var imported: Int { saved + liked + posts + comments }
    }

    /// The newest N per category, each capped on its own rather than sharing a
    /// budget. Instagram's reason (§245) applies harder here: a likes list runs
    /// to five figures while your own posts are in the dozens, so one shared
    /// cap would let the contentless rows crowd out every row carrying text.
    ///
    /// RAISED 2026-08-05 from a single 500 (prd §309, generalising §307), and
    /// split in two for the reason the paragraph above already gives: a likes
    /// list running to five figures and a comments list of your own words are
    /// not worth the same number. Five hundred failed SILENTLY — the receipt
    /// for a truncated import was word-for-word the receipt for a complete one
    /// — which is what `dropped` now fixes.
    private static let writingCap = 10_000
    private static let tapCap = 5_000

    // MARK: - Where each category lives

    /// Candidate paths per category, tried in order. The first that resolves to
    /// a non-empty array wins; a category present under neither era is simply
    /// absent, which is normal for an export requested with some boxes unticked.
    private static let favoritePaths: [[String]] = [
        ["Likes and Favorites", "Favorite Videos", "FavoriteVideoList"],
        ["Your Activity", "Favorite Videos", "FavoriteVideoList"],
        ["Activity", "Favorite Videos", "FavoriteVideoList"],
    ]
    private static let likePaths: [[String]] = [
        ["Likes and Favorites", "Like List", "ItemFavoriteList"],
        ["Your Activity", "Like List", "ItemFavoriteList"],
        ["Activity", "Like List", "ItemFavoriteList"],
    ]
    /// Your own published videos. `RecentlyDeletedPosts` sits beside this in the
    /// export and is deliberately not read — a record of something already gone
    /// is the `snap_history.json` case.
    private static let postPaths: [[String]] = [
        ["Video", "Videos", "VideoList"],
        ["Post", "Posts", "VideoList"],
    ]
    private static let commentPaths: [[String]] = [
        ["Comment", "Comments", "CommentsList"],
    ]

    // MARK: - Run

    /// Imports a TikTok export. Accepts the `user_data_tiktok.json` file
    /// directly or a folder holding it, because the JSON download arrives
    /// sometimes as a bare file and sometimes zipped around one — and which the
    /// person picks should not be a thing the screen has to explain.
    ///
    /// `failed` is reserved for "this isn't a TikTok export": the JSON didn't
    /// parse, or parsed and carried none of the four categories.
    @MainActor
    static func run(file url: URL, context: ModelContext,
                    progress: ((Int) -> Void)? = nil) async -> Summary {
        guard let data = locate(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return Summary(failed: true) }

        var summary = Summary()
        var landed: [Thing] = []
        var seen = Set(IngestSupport.thingsByRef(context, source: source).keys)
        var foundAnyCategory = false

        // Saves before likes, and both keyed by VIDEO ID rather than by act, so
        // a video that was both saved and liked is ONE row wearing both tags
        // rather than two rows of the same video. Instagram lands those as two
        // things; that is livable there (a saves library and a likes library
        // barely overlap) and would not be here, where the overlap is most of
        // the saves list.
        if let entries = list(root, favoritePaths) {
            foundAnyCategory = true
            landVideos(entries, tag: "Saved", summary: &summary,
                       landed: &landed, seen: &seen, context: context)
        }
        if let entries = list(root, likePaths) {
            foundAnyCategory = true
            landVideos(entries, tag: "Liked", summary: &summary,
                       landed: &landed, seen: &seen, context: context)
        }
        if let entries = list(root, postPaths) {
            foundAnyCategory = true
            landPosts(entries, summary: &summary, landed: &landed, seen: &seen)
        }
        if let entries = list(root, commentPaths) {
            foundAnyCategory = true
            landComments(entries, summary: &summary, landed: &landed, seen: &seen)
        }

        guard foundAnyCategory else { return Summary(failed: true) }
        await finish(&summary, landed: landed, context: context, progress: progress)
        return summary
    }

    /// One save whose failure is REPORTED — a swallowed import behind a success
    /// screen is fake status — and one batched Spotlight submission rather than
    /// an XPC round-trip per row. Mirrors `InstagramImport.finish`.
    @MainActor
    private static func finish(_ summary: inout Summary, landed: [Thing],
                               context: ModelContext,
                               progress: ((Int) -> Void)?) async {
        guard summary.imported > 0 else { return }
        // TikTok is a `Corpus.bulkImportSources` member: its things stay out of
        // the All feed and live in their own room, so All learns the import
        // happened from this one reconciling row and nothing else. Landed
        // BEFORE the save so the receipt rides the same transaction — a receipt
        // saved separately could survive a failed import.
        guard await ImportCommit.commit(landed, context: context, source: source, progress: progress) else {
            summary = Summary(failed: true)
            return
        }
        ImportReceipt.land(source: source, count: summary.imported,
                           detail: receiptDetail(summary), context: context)
        if (try? context.save()) == nil { summary = Summary(failed: true) }
    }

    /// What the count is made of, in the order a person would care about. Only
    /// non-zero parts appear, so a saves-only export doesn't advertise three
    /// empty categories.
    private static func receiptDetail(_ s: Summary) -> String {
        var parts = [
            s.saved > 0 ? String(localized: "\(s.saved) saved") : nil,
            s.liked > 0 ? String(localized: "\(s.liked) liked") : nil,
            s.posts > 0 ? String(localized: "\(s.posts) posts") : nil,
            s.comments > 0 ? String(localized: "\(s.comments) comments") : nil,
        ].compactMap { $0 }
        // A capped import SAYS SO — truncated and complete are otherwise the
        // same sentence, here and in the room that follows.
        if s.dropped > 0 {
            parts.append(String(localized: "\(s.dropped) older not imported"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Saved and liked videos (a link and a date — for now)

    /// Saves and likes share one shape: a date and a video link, nothing else.
    /// Both land as `.link` things keyed on the video's own id, so the second
    /// pass over the same file (or a later export) dedupes exactly and a video
    /// that is both saved and liked collects the second tag instead of a second
    /// row.
    @MainActor
    private static func landVideos(_ entries: [[String: Any]], tag: String,
                                   summary: inout Summary, landed: inout [Thing],
                                   seen: inout Set<String>, context: ModelContext) {
        // Newest first BEFORE the cap — a cap over file order would keep the
        // oldest saves and drop everything recent.
        let dated: [(date: Date, id: String, link: String)] = entries.compactMap { entry in
            guard let raw = field(entry, ["Link", "VideoLink", "url"]),
                  let video = TikTokLink.video(raw) else { return nil }
            let date = stamp(field(entry, ["Date"])) ?? Date(timeIntervalSince1970: 0)
            return (date, video.id, video.canonical)
        }.sorted { $0.date > $1.date }
        summary.dropped += max(0, dated.count - tapCap)

        for row in dated.prefix(tapCap) {
            let ref = "tiktok:video:\(row.id)"
            guard !seen.contains(ref) else {
                // Already here from the other half of this same file, or from a
                // previous import: add this act's tag rather than landing a
                // duplicate. Both arrays are walked in one `run`, so the row may
                // still be sitting in `landed` unsaved.
                addTag(tag, ref: ref, landed: landed, context: context)
                summary.skipped += 1
                continue
            }
            seen.insert(ref)
            // The link IS the title, deliberately: it is the whole of what the
            // export gives, and `LinkTitle.enrich` only renames a link still
            // wearing its URL as a face. Naming these rows anything prettier
            // here (Instagram's choice, forced on it by having a handle and no
            // working endpoint) would lock them out of `fetchFaces` forever.
            landed.append(Thing(
                kind: .link,
                title: row.link,
                content: row.link,
                source: source,
                capturedAt: row.date,
                tags: [tag],
                sourceRef: ref
            ))
            if tag == "Saved" { summary.saved += 1 } else { summary.liked += 1 }
        }
    }

    /// Adds a tag to a row already landed in this pass or already in the store.
    /// `isLive` because a heal or a CloudKit-propagated delete can tombstone a
    /// stored row between the fetch at the top of `run` and this write.
    @MainActor
    private static func addTag(_ tag: String, ref: String,
                               landed: [Thing], context: ModelContext) {
        if let pending = landed.first(where: { $0.sourceRef == ref }) {
            if !pending.tags.contains(tag) { pending.tags.append(tag) }
            return
        }
        guard let stored = IngestSupport.thingsByRef(context, source: source)[ref],
              stored.isLive, !stored.tags.contains(tag) else { return }
        stored.tags.append(tag)
    }

    // MARK: - Your own videos (captions — real text)

    /// Your own published videos. The caption (`Title`) is the substance and
    /// the link is openable, so these land as `.link` with the caption as both
    /// the face and the retrieval text — not as a `.note`, which is what
    /// Instagram's own posts had to be because that export gives no permalink.
    ///
    /// A captionless video still lands: unlike an Instagram post with no
    /// caption (which would be an empty note), this row has a working link and
    /// `fetchFaces` can still give it a thumbnail and a creator.
    @MainActor
    private static func landPosts(_ entries: [[String: Any]], summary: inout Summary,
                                  landed: inout [Thing], seen: inout Set<String>) {
        let dated: [(date: Date, id: String, link: String, caption: String, likes: Int?)] =
            entries.compactMap { entry in
                guard let raw = field(entry, ["Link", "VideoLink", "url"]),
                      let video = TikTokLink.video(raw) else { return nil }
                let date = stamp(field(entry, ["Date"])) ?? Date(timeIntervalSince1970: 0)
                let caption = (field(entry, ["Title"]) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (date, video.id, video.canonical, caption,
                        field(entry, ["Likes"]).flatMap { Int($0) })
            }.sorted { $0.date > $1.date }
        summary.dropped += max(0, dated.count - writingCap)

        for row in dated.prefix(writingCap) {
            // A distinct ref from the saved/liked rows on purpose: liking your
            // own video is a different act from posting it, and collapsing them
            // would make one disappear.
            let ref = "tiktok:post:\(row.id)"
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)
            let thing = Thing(
                kind: .link,
                title: IngestSupport.titleLine(row.caption.isEmpty ? row.link : row.caption),
                content: row.link,
                source: source,
                capturedAt: row.date,
                tags: ["Post"],
                sourceRef: ref
            )
            // The caption in full, past the title's 80-character clamp, so the
            // answer path can reach a video by words the face had to drop.
            if !row.caption.isEmpty { thing.enrichedText = row.caption }
            // The export's own like count. A count is never a thing here (the
            // module doctrine), but it is legitimate as a FIELD on a thing that
            // exists for another reason.
            if let likes = row.likes { thing.likeCount = likes }
            landed.append(thing)
            summary.posts += 1
        }
    }

    // MARK: - Your own comments (text, with the video they were left on)

    /// Comments you wrote. The parent video is named by a link in most exports
    /// but its caption is not in the file, so a row carries the comment itself
    /// and keeps the link as `externalLink` rather than pretending to quote
    /// something we don't have.
    @MainActor
    private static func landComments(_ entries: [[String: Any]], summary: inout Summary,
                                     landed: inout [Thing], seen: inout Set<String>) {
        let dated: [(date: Date, text: String, link: String?)] = entries.compactMap { entry in
            let text = (field(entry, ["Comment"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard let date = stamp(field(entry, ["Date"])) else { return nil }
            let link = field(entry, ["url", "Url", "Link"]).flatMap { TikTokLink.video($0)?.canonical }
            return (date, text, link)
        }.sorted { $0.date > $1.date }
        summary.dropped += max(0, dated.count - writingCap)

        for row in dated.prefix(writingCap) {
            // NOT `hashValue`: Swift seeds string hashing per PROCESS, so a ref
            // built from one would differ on every launch and a re-import would
            // duplicate every comment instead of deduping it.
            let ref = "tiktok:comment:\(Int(row.date.timeIntervalSince1970))-\(stableHash(row.text))"
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)
            let thing = Thing(
                kind: .note,
                title: IngestSupport.titleLine(row.text),
                content: row.text,
                source: source,
                capturedAt: row.date,
                tags: ["Comment"],
                sourceRef: ref
            )
            thing.externalLink = row.link
            landed.append(thing)
            summary.comments += 1
        }
    }

    /// FNV-1a over the text's UTF-8, rendered hex. A `sourceRef` has to mean the
    /// same thing on every launch for dedupe to work at all, and Swift's own
    /// `hashValue` is seeded per process — so this is spelled out rather than
    /// borrowed. Two comments posted in the same second with the same text are
    /// the same comment for our purposes.
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - The second act: faces

    struct FaceResult {
        var named = 0
        var missed = 0
        /// Videos TikTok says are deleted or private (2026-08-05, prd §309) —
        /// a real answer, not a failure, and the read no service makes about
        /// your own library: it remembers what TikTok has forgotten.
        var gone = 0
        /// Every attempt failed WITHOUT a status, and at least one was made:
        /// an endpoint that has changed or a network that isn't there.
        /// Deletions are excluded — a library of long-dead saves would
        /// otherwise report the endpoint broken on every pass, which is the
        /// opposite of what happened.
        var unreachable: Bool { named == 0 && gone == 0 && missed > 0 }
    }

    /// What's still wearing its URL as a face.
    @MainActor
    static func pendingFaceCount(context: ModelContext) -> Int {
        pending(context: context).count
    }

    @MainActor
    private static func pending(context: ModelContext) -> [Thing] {
        // Bound into a local: a `#Predicate` captures values, not static
        // members, and referring to `source` directly doesn't compile.
        let name = source
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        // A row is pending when its title is still the link it was born with —
        // the same test `LinkTitle.enrich` makes, so this can never fight it.
        //
        // A row TikTok has told us is GONE will never gain a face, so without
        // the second clause it stays pending forever and spends a request per
        // dead video on every pass, for the life of the install (2026-08-05).
        return all.live.filter {
            $0.kind == .link && $0.title == $0.content && !$0.tags.contains("Gone")
        }
    }

    /// Gives imported videos their real faces: caption, creator and poster art,
    /// from TikTok's own keyless oEmbed endpoint, one request each.
    ///
    /// A SEPARATE, EXPLICIT ACT by the same ruling that split Snapchat's media
    /// fetch out of its import (§246). The import itself is instant and offline
    /// — it touches no network at all — while this reaches TikTok once per
    /// video, and a person importing a decade of saves should choose to spend
    /// that rather than discover it. Unlike Snapchat's, though, this fetch is
    /// under NO deadline: the export's download link expires in four days, but
    /// the videos it names do not, so a library imported today can be given its
    /// faces next month. The screen says so.
    ///
    /// Bounded per run so one tap can't become ten thousand requests; run it
    /// again for the next slice.
    @MainActor
    static func fetchFaces(limit: Int = 200, context: ModelContext) async -> FaceResult {
        let waiting = pending(context: context).prefix(limit)
        let jobs: [Job] = waiting.compactMap { thing in
            guard let ref = thing.sourceRef, let url = URL(string: thing.content) else { return nil }
            return Job(ref: ref, url: url)
        }
        guard !jobs.isEmpty else { return FaceResult() }

        // Four at a time, the concurrency every other bulk fetch in this app
        // uses. TikTok publishes no rate limit for this endpoint, so the shared
        // ceiling is the conservative read rather than a number invented here.
        let answers = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            let outcome = await OEmbed.ask(job.url)
            return (job.ref, outcome.response, outcome.status)
        }

        let byRef = IngestSupport.thingsByRef(context, source: source)
        var result = FaceResult()
        var changed: [Thing] = []
        for (ref, embed, status) in answers {
            guard let thing = byRef[ref], thing.isLive else { continue }
            // GONE is recorded on the row rather than counted as a miss
            // (2026-08-05, prd §309). `OEmbed.resolve` collapsed every failure
            // into one nil, so a deleted video and a dead network were the
            // same event here: the row was re-asked forever and a library of
            // old saves reported the endpoint as broken.
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

    /// Writes an oEmbed answer onto a row. Mirrors `LinkTitle.applyOEmbed`'s
    /// discipline — nothing written unless it actually changed, and a change
    /// drops the stale vector so the next semantic sweep re-embeds on the real
    /// words — and adds the one field that path has no use for: the creator's
    /// handle as DATA, which is what makes the room's "Who you save most"
    /// possible at all.
    @MainActor
    private static func apply(_ embed: OEmbed.Response, to thing: Thing) -> Bool {
        var changed = false
        if let title = OEmbed.title(embed, host: "TikTok"), title != thing.title {
            thing.title = title
            changed = true
        }
        if let art = embed.thumbnailURL, art != thing.previewImageURL {
            thing.previewImageURL = art
            changed = true
        }
        if let text = OEmbed.enrichedText(embed), text != thing.enrichedText {
            thing.enrichedText = text
            changed = true
        }
        if let handle = embed.authorHandle, thing.authorHandle != handle {
            thing.authorHandle = handle
            changed = true
        }
        if changed { thing.embedding = nil }
        return changed
    }

    // MARK: - Reading the file

    /// The export's bytes, from a picked file or from a folder holding one.
    /// Bounded depth-2 scan for the folder case, because a person can hand this
    /// any folder they like — including one holding their whole Files app.
    private static func locate(_ url: URL) -> Data? {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if !isDirectory { return try? Data(contentsOf: url) }

        let manager = FileManager.default
        var folders = [url]
        for _ in 0..<2 {
            var next: [URL] = []
            for folder in folders {
                let children = (try? manager.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                for child in children.prefix(200) {
                    if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        next.append(child)
                    } else if child.pathExtension.lowercased() == "json",
                              child.lastPathComponent.lowercased().contains("user_data"),
                              let data = try? Data(contentsOf: child) {
                        return data
                    }
                }
            }
            folders = next
        }
        return nil
    }

    /// The first candidate path that resolves to a non-empty array of objects.
    private static func list(_ root: [String: Any], _ paths: [[String]]) -> [[String: Any]]? {
        for path in paths {
            var node: Any? = root
            for key in path {
                node = (node as? [String: Any])?[key]
                if node == nil { break }
            }
            if let entries = node as? [[String: Any]], !entries.isEmpty { return entries }
        }
        return nil
    }

    /// The first present field among `keys`, tried in the given case and then in
    /// lower case. TikTok is not consistent about this WITHIN a single export —
    /// see the type doc — so a fixed key would silently read nothing for whole
    /// categories. Numbers are accepted and rendered, since `Likes` arrives as
    /// a string in some exports and a number in others.
    private static func field(_ entry: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            for candidate in [key, key.lowercased()] {
                guard let raw = entry[candidate] else { continue }
                if let text = raw as? String {
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { return clean }
                } else if let number = raw as? Int {
                    return String(number)
                } else if let number = raw as? Double {
                    return String(Int(number))
                }
            }
        }
        return nil
    }

    /// The export's own stamp, `2024-01-15 14:23:45`, in UTC. Pinned to
    /// `en_US_POSIX` — a device locale would reinterpret the digits — with an
    /// ISO fallback and finally an epoch one, so an era that changes format
    /// degrades to a dated row rather than to no row.
    private static let exportStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func stamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = exportStamp.date(from: raw) { return date }
        if let date = IngestSupport.isoDate(raw) { return date }
        if let seconds = Double(raw), seconds > 0 {
            return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds)
        }
        return nil
    }
}

/// A TikTok video link, reduced to the one form every reader in this app can
/// use.
///
/// MEASURED 2026-08-02, and the reason this type exists at all. TikTok's export
/// writes its links as `https://www.tiktokv.com/share/video/<id>/` — a
/// DIFFERENT HOST from `tiktok.com`, which means `OEmbed.handles` returns false
/// for every imported row and the enrichment that is the whole point of this
/// import would silently never run. Three forms were called against the live
/// keyless endpoint:
///
///   - `www.tiktok.com/@user/video/<id>`  → 200, full fields
///   - `www.tiktok.com/video/<id>`        → 200, IDENTICAL answer — the id
///                                          alone resolves, and the response
///                                          still names the real author
///   - `www.tiktokv.com/share/video/<id>/` → 400 (the export's own form)
///
/// The 400 is the FORM, not a dead video: the same id answers 200 in the other
/// two shapes. So every link is canonicalised to the username-less form on the
/// way in — which is also why `sourceRef` keys on the id rather than the URL,
/// making dedupe immune to TikTok changing the link shape again.
enum TikTokLink {

    struct Video {
        let id: String
        /// `https://www.tiktok.com/video/<id>` — accepted by the oEmbed
        /// endpoint, and opens in the app or the browser like any other.
        var canonical: String { "https://www.tiktok.com/video/\(id)" }
    }

    /// The video in a link of any shape TikTok has used, or nil when there
    /// isn't one. A photo-mode post (`/photo/<id>`) carries an id the endpoint
    /// answers for too, so it is read the same way.
    static func video(_ raw: String) -> Video? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host()?.lowercased() else { return nil }
        // Label-boundary match, never `contains` — the rule `OEmbed.endpoint`
        // is built on. `tiktok.com.attacker.example` is not TikTok.
        let known = ["tiktok.com", "tiktokv.com", "tiktokv.us"]
        guard known.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }

        // The id is the last all-digit path component: every shape TikTok uses
        // ends in one (`/share/video/<id>/`, `/@user/video/<id>`, `/video/<id>`,
        // `/photo/<id>`), and reading it positionally would need a different
        // rule per shape.
        let digits = url.pathComponents.last(where: { component in
            component.count >= 6 && component.allSatisfy(\.isNumber)
        })
        guard let id = digits else { return nil }
        return Video(id: id)
    }
}
