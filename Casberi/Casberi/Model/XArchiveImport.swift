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
/// was liked for, not just a handle. It is worse in one way, though, and the
/// copy says so: `like.js` carries no author, so nothing in this room can rank
/// who you like most the way Instagram's saves rank who you save most.
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
/// Instagram ruling, unchanged. (3) MEDIA: the images live under `data/`
/// as files relative to a temporary security-scoped folder, with no
/// copy-into-app-storage path here. (4) Followers/following: names and dates,
/// no content — a tally, and a thing is never a tally.
enum XArchiveImport {

    struct Summary {
        var posts = 0
        var replies = 0
        var liked = 0
        var skipped = 0
        var retweets = 0        // seen and deliberately not landed
        var failed = false

        var imported: Int { posts + replies + liked }
    }

    /// Per-category caps rather than one shared budget — the Instagram rule,
    /// for the same reason and with different numbers. Your own posts are the
    /// substance of this export and run to tens of thousands for a long-time
    /// account, so they get the larger share; likes are the cheaper rows and
    /// must not be able to crowd them out.
    private static let postCap = 1_000
    private static let likeCap = 500

    // MARK: - Run

    /// Imports an UNZIPPED archive folder. Every category is optional — an
    /// archive is one shape and always has tweets, but a brand-new account can
    /// legitimately have no likes. `failed` is reserved for "this isn't an X
    /// archive at all": neither category was found anywhere under the pick.
    @MainActor
    static func run(folder: URL, context: ModelContext) -> Summary {
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

        guard foundAnyCategory else { return Summary(failed: true) }
        for thing in landed { context.insert(thing) }
        finish(&summary, landed: landed, context: context)
        return summary
    }

    /// One save whose failure is REPORTED (a swallowed save behind a success
    /// screen is fake status), and one batched Spotlight submission rather than
    /// an XPC round-trip per row. Mirrors `InstagramImport.finish`.
    @MainActor
    private static func finish(_ summary: inout Summary, landed: [Thing],
                               context: ModelContext) {
        guard summary.imported > 0 else { return }
        // X is a `Corpus.bulkImportSources` member: its things stay out of the
        // All feed and live in their own room, so All learns the import
        // happened from this one reconciling row and nothing else. Landed
        // BEFORE the save so the receipt rides the same transaction — a receipt
        // saved separately could survive a failed import.
        ImportReceipt.land(source: "X", count: summary.imported,
                           detail: receiptDetail(summary), context: context)
        do {
            try context.save()
            SpotlightIndex.index(landed)
        } catch {
            summary = Summary(failed: true)
        }
    }

    /// The receipt's own line. Only non-zero parts appear, so a likes-only
    /// archive doesn't advertise two empty categories.
    private static func receiptDetail(_ s: Summary) -> String {
        let parts = [
            s.posts > 0   ? String(localized: "\(s.posts) posts") : nil,
            s.replies > 0 ? String(localized: "\(s.replies) replies") : nil,
            s.liked > 0   ? String(localized: "\(s.liked) liked") : nil,
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    // MARK: - Your own posts and replies (full text — the substance)

    @MainActor
    private static func landTweets(_ data: Data, summary: inout Summary,
                                   landed: inout [Thing], seen: inout Set<String>) {
        guard let entries = parseArray(data) else { return }

        struct Row { let date: Date; let text: String; let id: String; let replyTo: String? }
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
            rows.append(Row(date: date, text: text, id: id, replyTo: replyTo))
        }
        // Newest first BEFORE the cap — a cap over file order would keep the
        // oldest posts and drop everything recent.
        rows.sort { $0.date > $1.date }

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
            let face = row.replyTo.map { "\(row.text) — to @\($0)" } ?? row.text
            landed.append(Thing(
                kind: .note,
                title: IngestSupport.titleLine(face),
                content: row.text,
                source: "X",
                capturedAt: row.date,
                tags: [row.replyTo == nil ? "Post" : "Reply"],
                sourceRef: ref
            ))
            if row.replyTo == nil { summary.posts += 1 } else { summary.replies += 1 }
        }
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
