import Foundation
import ImageIO
import SwiftData
import UIKit

/// The Snapchat bridge (2026-07-31) — a one-time import of the person's own
/// data export, the ChatGPT/Day One/Journal pattern. Snap offers no readable
/// API at all: Login Kit's whole scope list is display name, Bitmoji avatar
/// and a user id, Creative Kit only shares OUT, and nothing anywhere exposes
/// snaps, chats, memories or the friend graph. So the export is not the
/// fallback — it's the only door.
///
/// Two files in that export are worth landing, and the rest deliberately
/// aren't. `chat_history.json` holds the **saved** chats — not all chats, the
/// ones somebody pressed Save on, because Snapchat deletes the rest off its
/// own servers — which is the corpus's own semantics exactly. And
/// `memories_history.json` holds your own photos and videos with real dates.
/// `snap_history.json` is skipped on purpose: it's `{"From": "user1",
/// "Media Type": "IMAGE", "Created": …}` with the content already deleted,
/// i.e. a tally, and a tally isn't a thing (module doctrine, prd §166).
///
/// **The memories catch, and why media is a separate act.** The export ZIP
/// carries no pixels — each memory is a `Download Link` that must be POSTed
/// (the response BODY is a plain-text CDN URL), and the links die 7 days
/// after Snapchat generates the export. So `run(folder:)` lands memories as
/// dated things immediately and `fetchMedia` is its own explicit pass: N
/// requests for N memories is a different weight class from parsing a JSON,
/// and it fails permanently once the window shuts. Videos are landed but
/// never fetched — `previewImageData` is an image field — and they carry no
/// `externalLink` so they can't sit in the fetch queue forever.
///
/// **UNMEASURED** (2026-07-31): both parsers were written against open-source
/// exporters and Snap's published export docs, not against a real ZIP held in
/// hand. Both chat eras are handled (see `parseChats`) and every unknown
/// shape fails SAFE — a file that doesn't parse reports `failed`, never a
/// half-landed corpus. Re-measure against a real export before hardening.
enum SnapchatImport {

    static let source = "Snapchat"

    struct Summary {
        /// Conversations landed for the first time.
        var chats = 0
        /// Conversations already here that gained new messages — a chat GROWS
        /// (unlike a finished ChatGPT thread), so a second export updates the
        /// transcript in place rather than skipping it. The social-bridge
        /// "dedupe hit heals" rule.
        var healed = 0
        var memories = 0
        var skipped = 0
        /// Nothing in the folder parsed as a Snapchat export.
        var failed = false
    }

    /// The newest N of each kind. The ChatGPT precedent — a years-deep export
    /// shouldn't flood the corpus in one tap.
    private static let chatCap = 500
    private static let memoryCap = 500
    /// Lines kept per conversation, newest-biased, and the transcript's byte
    /// ceiling. `content` is what `ChatBubbles` draws and what `Retriever`
    /// reads; a decade of one friendship shouldn't be either.
    private static let lineCap = 60
    private static let transcriptCap = 4000

    // MARK: - Folder entry point

    /// Reads an unzipped export folder (the JSONs sit at the root in some
    /// exports and under `json/` in others, so this looks one level down too)
    /// and lands whatever it finds. Missing either file is fine — an export
    /// that only carries chats still imports.
    @MainActor
    static func run(folder: URL, context: ModelContext) async -> Summary {
        let found = locate(["chat_history.json", "memories_history.json"], under: folder)
        var summary = Summary()

        if let url = found["chat_history.json"],
           let data = try? Data(contentsOf: url) {
            let part = landChats(data: data, context: context)
            summary.chats += part.chats
            summary.healed += part.healed
            summary.skipped += part.skipped
        }
        if let url = found["memories_history.json"],
           let data = try? Data(contentsOf: url) {
            let part = landMemories(data: data, context: context)
            summary.memories += part.memories
            summary.skipped += part.skipped
        }

        summary.failed = summary.chats == 0 && summary.healed == 0
            && summary.memories == 0 && summary.skipped == 0

        // Snapchat is a `Corpus.bulkImportSources` member: its things stay out
        // of the All feed and live in their own room, so All learns the import
        // happened from this one reconciling row and nothing else. `healed`
        // counts toward it — a conversation that GREW is a real thing this
        // import brought back, not a skip.
        let landed = summary.chats + summary.healed + summary.memories
        if landed > 0 {
            ImportReceipt.land(source: "Snapchat", count: landed,
                               detail: receiptDetail(summary), context: context)
            // `landChats`/`landMemories` each save their OWN work before
            // returning, so the receipt is inserted after the last save and
            // needs its own — without this it would live only in memory and
            // vanish, leaving All with no sign the import ran at all.
            context.saveHonestly()
        }
        return summary
    }

    /// The receipt's own line — what the count is made of. Only non-zero
    /// parts appear, so a chats-only export doesn't advertise empty ones.
    private static func receiptDetail(_ s: Summary) -> String {
        let parts = [
            s.chats > 0 ? String(localized: "\(s.chats) conversations") : nil,
            s.healed > 0 ? String(localized: "\(s.healed) updated") : nil,
            s.memories > 0 ? String(localized: "\(s.memories) memories") : nil,
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    /// Depth-2 search for the named files. Bounded (`fileCap`) because a
    /// person can hand this any folder they like, including one holding their
    /// whole Files app.
    private static func locate(_ names: Set<String>, under folder: URL) -> [String: URL] {
        var hits: [String: URL] = [:]
        let fm = FileManager.default
        let fileCap = 4000
        var seen = 0

        func scan(_ dir: URL, depth: Int) {
            guard depth <= 2, hits.count < names.count else { return }
            let entries = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for entry in entries {
                seen += 1
                guard seen < fileCap else { return }
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                if isDir {
                    scan(entry, depth: depth + 1)
                } else if names.contains(entry.lastPathComponent),
                          hits[entry.lastPathComponent] == nil {
                    hits[entry.lastPathComponent] = entry
                }
            }
        }
        scan(folder, depth: 0)
        return hits
    }

    // MARK: - Chats

    /// One saved conversation, flattened for landing.
    struct Conversation {
        let handle: String
        let newest: Date
        /// Oldest → newest, already capped and speaker-prefixed.
        let lines: [String]
        /// Every message this conversation holds — counted BEFORE `lines` was
        /// clamped to `lineCap`, so it survives the clamp that `transcript`
        /// then applies again. This is the only moment the true number exists:
        /// nothing downstream can recover it from a stored transcript, which
        /// is why `Thing.messageCount` is a field and not a computed line
        /// count. The room's "Who you snap with" bars rank on it.
        let total: Int

        var transcript: String {
            String(lines.joined(separator: "\n").prefix(SnapchatImport.transcriptCap))
        }
    }

    /// Parses `chat_history.json` in EITHER era. Snapchat reshaped this file
    /// in 2024 and both forms are still in the wild (an export's contents
    /// depend on when the account's history was written, not on today's
    /// date), so the shape is detected rather than assumed:
    ///
    ///  * **pre-2024** — top-level `"Received Saved Chat History"` /
    ///    `"Sent Saved Chat History"` arrays, each entry carrying `From`/`To`,
    ///    `Media Type`, `Created`, `Text`. The counterpart is `From` on a
    ///    received row and `To` on a sent one.
    ///  * **2024+** — top-level is the counterpart's USERNAME mapped to that
    ///    conversation's messages, each carrying `From`, `Media Type`,
    ///    `Created`, `Content` (nullable), `IsSender`.
    ///
    /// Returns nil when the root isn't a dictionary at all — i.e. not this
    /// file — so the caller can say so plainly instead of landing nothing and
    /// calling it success.
    static func parseChats(_ data: Data) -> [Conversation]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let legacy = root.keys.contains { $0.lowercased().contains("chat history") }
        var byHandle: [String: [(date: Date, line: String)]] = [:]

        for (key, value) in root {
            guard let rows = value as? [[String: Any]] else { continue }
            let sentSection = key.lowercased().contains("sent")
            for row in rows {
                guard let date = stamp(row["Created"], fallback: row["Created(microseconds)"])
                else { continue }

                let fromMe: Bool
                let handle: String
                if legacy {
                    fromMe = sentSection
                    let other = (sentSection ? row["To"] : row["From"]) as? String
                    handle = (other ?? row["From"] as? String ?? row["To"] as? String ?? "").trimmed
                } else {
                    fromMe = (row["IsSender"] as? Bool) ?? false
                    handle = key.trimmed
                }
                guard !handle.isEmpty else { continue }

                let body = (row["Content"] as? String ?? row["Text"] as? String)?.trimmed ?? ""
                let speaker = fromMe ? "You" : handle
                let text = body.isEmpty
                    ? "\(speaker) sent a \(mediaWord(row["Media Type"]))"
                    : "\(speaker): \(body)"
                byHandle[handle, default: []].append((date: date, line: text))
            }
        }
        guard !byHandle.isEmpty else { return nil }

        return byHandle.map { handle, messages in
            let ordered = messages.sorted { $0.date < $1.date }
            return Conversation(
                handle: handle,
                newest: ordered.last?.date ?? .distantPast,
                lines: ordered.suffix(lineCap).map(\.line),
                total: ordered.count
            )
        }.sorted { $0.newest > $1.newest }
    }

    /// Lands parsed conversations, healing the ones already here.
    @MainActor
    private static func landChats(data: Data, context: ModelContext) -> Summary {
        guard let conversations = parseChats(data) else { return Summary() }
        let existing = IngestSupport.thingsByRef(context, source: source)
        var summary = Summary()
        // A conversation landed by an earlier build carries no `messageCount`.
        // Repairing that is not a heal — nothing about the conversation
        // changed, we simply learned a number we can only read here — so it
        // rides its own flag rather than inflating `healed`, and forces the
        // save an otherwise all-skipped re-import would never make.
        var backfilled = false

        for conversation in conversations.prefix(chatCap) {
            let ref = "snapchat:chat:\(conversation.handle.lowercased())"
            let transcript = conversation.transcript

            if let already = existing[ref] {
                guard already.isLive else { continue }
                if already.messageCount != conversation.total {
                    already.messageCount = conversation.total
                    backfilled = true
                }
                // Only a genuinely newer conversation is news. An identical
                // re-import must read as "already here", not as a heal.
                guard conversation.newest > already.capturedAt
                        || already.content != transcript else {
                    summary.skipped += 1
                    continue
                }
                already.content = transcript
                already.capturedAt = max(already.capturedAt, conversation.newest)
                summary.healed += 1
                continue
            }

            let thing = Thing(
                kind: .chat,
                title: "Chat with \(conversation.handle)",
                content: transcript,
                source: source,
                capturedAt: conversation.newest,
                sourceRef: ref
            )
            thing.authorHandle = conversation.handle
            thing.messageCount = conversation.total
            context.insert(thing)
            SpotlightIndex.index([thing])
            summary.chats += 1
        }

        if summary.chats > 0 || summary.healed > 0 || backfilled { context.saveHonestly() }
        return summary
    }

    // MARK: - Memories

    /// One memory as the export describes it — the pixels are elsewhere.
    struct Memory {
        let date: Date
        /// "Image" / "Video" / "PHOTO" as the export happens to spell it.
        let mediaType: String
        /// POST this to get a CDN URL. Dead 7 days after the export was made.
        let downloadLink: String
        /// Some exports carry the capture location; many don't.
        let location: String?

        var isVideo: Bool { mediaType.uppercased().contains("VIDEO") }
    }

    /// Parses `memories_history.json`. The array's key is normally
    /// `"Saved Media"`, but this takes the first array-of-objects value
    /// whatever it's called — the key has been renamed before and the shape
    /// is unambiguous.
    static func parseMemories(_ data: Data) -> [Memory]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root.values.compactMap({ $0 as? [[String: Any]] })
                  .max(by: { $0.count < $1.count })
        else { return nil }

        let memories: [Memory] = rows.compactMap { row in
            guard let date = stamp(row["Date"], fallback: nil) else { return nil }
            let link = (row["Download Link"] as? String)?.trimmed ?? ""
            let location = (row["Location"] as? String)?.trimmed
            return Memory(
                date: date,
                mediaType: (row["Media Type"] as? String)?.trimmed ?? "",
                downloadLink: link,
                location: (location?.isEmpty ?? true) ? nil : location
            )
        }
        return memories.isEmpty ? nil : memories.sorted { $0.date > $1.date }
    }

    @MainActor
    private static func landMemories(data: Data, context: ModelContext) -> Summary {
        guard let memories = parseMemories(data) else { return Summary() }
        let existing = IngestSupport.existingSourceRefs(context, source: source)
        var summary = Summary()

        for memory in memories.prefix(memoryCap) {
            // Date + type is the only stable key the export offers: the
            // download link is minted per export and the array's order isn't
            // promised. Two memories saved in the same second wearing the
            // same type collapse into one — rare, and the alternative (an
            // index) would re-land the whole library on every re-import.
            let ref = "snapchat:memory:\(Int(memory.date.timeIntervalSince1970))"
                + "-\(memory.mediaType.lowercased())"
            guard !existing.contains(ref) else { summary.skipped += 1; continue }

            var note = memory.isVideo ? "Video" : "Photo"
            if let place = memory.location, !place.isEmpty { note += " · \(place)" }
            // (`place(inMemoryNote:)` reads this format back — keep them together.)

            let thing = Thing(
                kind: .file,
                title: "Memory · \(memoryStamp.string(from: memory.date))",
                content: note,
                source: source,
                capturedAt: memory.date,
                sourceRef: ref
            )
            // A video can't become `previewImageData`, so it never joins the
            // fetch queue — no link, no retry, no row that stays "pending"
            // forever. It stays a dated entry, which is what it honestly is.
            if !memory.isVideo, !memory.downloadLink.isEmpty {
                thing.externalLink = memory.downloadLink
            }
            context.insert(thing)
            SpotlightIndex.index([thing])
            summary.memories += 1
        }

        if summary.memories > 0 { context.saveHonestly() }
        return summary
    }

    /// The place a landed memory names, or nil. `landMemories` writes the note
    /// as "Photo"/"Video", optionally " · <place>"; this reads that back, and
    /// lives beside the writer so the two can't drift apart. Used by the room's
    /// memory grid, where the tile's date is already on its day pill and the
    /// place is the only thing left worth saying. Never invented — an export
    /// that carried no location simply gets no caption.
    static func place(inMemoryNote note: String) -> String? {
        guard let separator = note.range(of: " · ") else { return nil }
        let place = String(note[separator.upperBound...]).trimmed
        return place.isEmpty ? nil : place
    }

    // MARK: - Media fetch (the second, explicit act)

    struct MediaResult {
        var fetched = 0
        var failed = 0
        /// Every attempt failed and at least one was tried — the honest read
        /// on a dead 7-day window. Never claimed off a single failure.
        var expired: Bool { fetched == 0 && failed > 0 }
    }

    /// What's still waiting for pixels.
    @MainActor
    static func pendingMediaCount(context: ModelContext) -> Int {
        pending(context: context).count
    }

    @MainActor
    private static func pending(context: ModelContext) -> [Thing] {
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Snapchat" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.live.filter {
            $0.kind == .file && $0.previewImageData == nil
                && !($0.externalLink ?? "").isEmpty
        }
    }

    /// Walks the pending memories: POST the export's link, read the CDN URL
    /// out of the response BODY, GET the bytes, store a thumbnail. Bounded
    /// per run so one tap can't become a thousand requests; run it again for
    /// the next slice.
    @MainActor
    static func fetchMedia(limit: Int = 300, context: ModelContext) async -> MediaResult {
        let waiting = pending(context: context).prefix(limit)
        let jobs: [Job] = waiting.compactMap { thing in
            guard let ref = thing.sourceRef, let link = thing.externalLink else { return nil }
            return Job(ref: ref, link: link)
        }
        guard !jobs.isEmpty else { return MediaResult() }

        let fetched = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            (job.ref, await pixels(for: job.link))
        }

        let byRef = IngestSupport.thingsByRef(context, source: source)
        var result = MediaResult()
        for (ref, data) in fetched {
            guard let thing = byRef[ref], thing.isLive else { continue }
            if let data {
                thing.previewImageData = data
                result.fetched += 1
            } else {
                result.failed += 1
            }
        }
        if result.fetched > 0 { context.saveHonestly() }
        return result
    }

    private struct Job: Sendable {
        let ref: String
        let link: String
    }

    /// The two-step download. Snapchat's export link is not the media: it's
    /// an endpoint that answers a POST with the real (signed, expiring) CDN
    /// URL as plain text.
    private static func pixels(for link: String) async -> Data? {
        guard let endpoint = URL(string: link) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20

        guard let (body, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: body, encoding: .utf8)?.trimmed,
              text.hasPrefix("http"), let media = URL(string: text)
        else { return nil }

        guard let (bytes, mediaResponse) = try? await URLSession.shared.data(from: media),
              (mediaResponse as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return thumbnail(bytes)
    }

    /// The same 480pt / q0.7 thumbnail every other `previewImageData` writer
    /// stores (`FilesBridge`, `ScreenshotIngest`), so every reader already
    /// knows how to draw it — and so a memories library can't put full-size
    /// originals into the CloudKit-mirrored store.
    private static func thumbnail(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
    }

    // MARK: - Shared

    /// The export's own stamp format, e.g. `2018-08-09 14:40:38 UTC`. Pinned
    /// to `en_US_POSIX` — a device locale would reinterpret the digits.
    private static let exportStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return f
    }()

    /// Same, for exports that omit the zone word.
    private static let exportStampNoZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let memoryStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// The string stamp first, the numeric one only as a fallback — and its
    /// magnitude decides the unit rather than the field name, because the
    /// 2024+ export spells the key `Created(microseconds)` while the value
    /// measured as milliseconds. Trusting the label would put every message
    /// a thousand years out.
    private static func stamp(_ raw: Any?, fallback: Any?) -> Date? {
        if let text = (raw as? String)?.trimmed, !text.isEmpty {
            if let date = exportStamp.date(from: text) { return date }
            if let date = exportStampNoZone.date(from: text) { return date }
            if let date = IngestSupport.isoDate(text) { return date }
        }
        guard let number = (fallback as? Double) ?? (fallback as? Int).map({ Double($0) }),
              number > 0 else { return nil }
        let seconds: Double
        switch number {
        case 1e15...: seconds = number / 1_000_000   // microseconds
        case 1e12...: seconds = number / 1_000       // milliseconds
        default:      seconds = number
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func mediaWord(_ raw: Any?) -> String {
        let type = ((raw as? String) ?? "").uppercased()
        if type.contains("VIDEO") { return "video" }
        if type.contains("IMAGE") || type.contains("PHOTO") { return "photo" }
        if type.contains("SHARE") || type.contains("LINK") { return "link" }
        if type.contains("NOTE") || type.contains("AUDIO") { return "voice note" }
        if type.contains("STICKER") { return "sticker" }
        return "snap"
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
