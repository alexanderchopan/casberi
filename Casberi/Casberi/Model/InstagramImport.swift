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
/// "@houseofgaming" will not be picked up by the generic enrichment chain, and
/// `OEmbed`'s Instagram entry therefore serves pasted/shared links rather than
/// these. The trade is taken knowingly — a guaranteed handle from the export
/// beats a naked URL waiting on an endpoint that Meta has already stripped the
/// author and thumbnail fields out of (see `OEmbed.endpoints`).
///
/// NOT BUILT, with reasons. (1) MEDIA: your own posts reference their JPEGs by
/// a path relative to the export folder, and that folder is a temporary
/// security-scoped pick — landing them would need a copy-into-app-storage path
/// this importer doesn't have. Captions land; the pictures stay in the export,
/// and the screen says so. (2) DMs: full message text is in there and would be
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
        var comments = 0
        var skipped = 0
        var failed = false

        var imported: Int { saved + liked + posts + comments }
    }

    /// The newest N per category. Each category is capped on its own rather
    /// than sharing one budget: a saves library runs to thousands while your
    /// own posts are in the dozens, and a shared cap would let the cheap rows
    /// crowd out the ones carrying real text.
    private static let cap = 500

    /// Where each category lives inside an export, relative to the folder that
    /// holds `your_instagram_activity`. Instagram splits large categories
    /// across numbered files (`posts_1.json`, `posts_2.json`, …), so the
    /// numbered ones are walked until a gap.
    private static let savedPath    = "your_instagram_activity/saved/saved_posts.json"
    private static let likedPath    = "your_instagram_activity/likes/liked_posts.json"
    private static let postsStem    = "your_instagram_activity/media/posts_"
    private static let commentsStem = "your_instagram_activity/comments/post_comments_"

    // MARK: - Run

    /// Imports an UNZIPPED export folder. Every category is optional — an
    /// export requested with only some boxes ticked is normal, and a missing
    /// file is not an error. `failed` is reserved for "this isn't an Instagram
    /// export at all": no category was found anywhere under the picked folder.
    @MainActor
    static func run(folder: URL, context: ModelContext) -> Summary {
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
        for data in readNumbered(postsStem, under: folder) {
            foundAnyCategory = true
            landPosts(data, summary: &summary, landed: &landed, seen: &seen)
        }
        for data in readNumbered(commentsStem, under: folder) {
            foundAnyCategory = true
            landComments(data, summary: &summary, landed: &landed, seen: &seen)
        }

        guard foundAnyCategory else { return Summary(failed: true) }
        for thing in landed { context.insert(thing) }
        finish(&summary, landed: landed, backfilled: backfilled, context: context)
        return summary
    }

    /// One save whose failure is REPORTED (a swallowed save behind a success
    /// screen is fake status), and one batched Spotlight submission rather
    /// than an XPC round-trip per row. Mirrors `DayOneImport.finish`.
    @MainActor
    private static func finish(_ summary: inout Summary, landed: [Thing],
                               backfilled: Bool, context: ModelContext) {
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
        ImportReceipt.land(source: "Instagram", count: summary.imported,
                           detail: receiptDetail(summary), context: context)
        do {
            try context.save()
            SpotlightIndex.index(landed)
        } catch {
            summary = Summary(failed: true)
        }
    }

    /// The receipt's own line — what the count is made of, in the order a
    /// person would care about. Only non-zero parts appear, so a saves-only
    /// export doesn't advertise three empty categories.
    private static func receiptDetail(_ s: Summary) -> String {
        let parts = [
            s.saved > 0 ? String(localized: "\(s.saved) saved") : nil,
            s.liked > 0 ? String(localized: "\(s.liked) liked") : nil,
            s.posts > 0 ? String(localized: "\(s.posts) posts") : nil,
            s.comments > 0 ? String(localized: "\(s.comments) comments") : nil,
        ].compactMap { $0 }
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

        for row in dated.prefix(cap) {
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
            let thing = Thing(
                kind: .link,
                title: IngestSupport.titleLine(name),
                content: row.link,
                source: "Instagram",
                capturedAt: row.date,
                tags: [marker == "saved" ? "Saved" : "Liked"],
                sourceRef: ref
            )
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

    // MARK: - Your own posts (captions — real text)

    /// Your own posts. The caption may sit at the top level or on the first
    /// media item depending on whether the post was a single image or a
    /// carousel, so both are read. A captionless post is SKIPPED rather than
    /// landed as an empty note: the media stays in the export (see the type
    /// doc), so a caption is the only substance such a row would have.
    @MainActor
    private static func landPosts(_ data: Data, summary: inout Summary,
                                  landed: inout [Thing], seen: inout Set<String>) {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        let dated: [(date: Date, caption: String)] = entries.compactMap { entry in
            let media = entry["media"] as? [[String: Any]] ?? []
            let rawCaption = (entry["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (media.first?["title"] as? String)
                ?? ""
            let stamp = (entry["creation_timestamp"] as? Double)
                ?? (media.first?["creation_timestamp"] as? Double)
                ?? 0
            let caption = repairMojibake(rawCaption).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !caption.isEmpty, stamp > 0 else { return nil }
            return (Date(timeIntervalSince1970: stamp), caption)
        }.sorted { $0.date > $1.date }

        for row in dated.prefix(cap) {
            let ref = "instagram:post:\(Int(row.date.timeIntervalSince1970))"
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)
            landed.append(Thing(
                kind: .note,
                title: IngestSupport.titleLine(row.caption),
                content: row.caption,
                source: "Instagram",
                capturedAt: row.date,
                tags: ["Post"],
                sourceRef: ref
            ))
            summary.posts += 1
        }
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

        for row in dated.prefix(cap) {
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
