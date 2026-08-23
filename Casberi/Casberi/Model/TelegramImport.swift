import Foundation
import SwiftData

/// A Telegram Desktop export, landed (prd §456, 2026-08-23).
///
/// The SwiftData half. Every byte of parsing lives in `TelegramExport`, which
/// is Foundation-only so a harness can compile it whole; this file does
/// nothing but turn what that returns into `Thing`s.
///
/// **This is the second of the seat's two doors.** The first — following
/// public channels — is live, keyless and needs no file (`TelegramChannel` +
/// `FeedFollowKind.telegram`). They share one source and one catalog seat
/// because they are one product, and `Corpus.liveRefPrefixes` is what keeps
/// the All feed honest about the difference: a followed channel's post drips
/// in and belongs in All, while this can land tens of thousands of rows at
/// once and must not.
///
/// **UNMEASURED against a real export.** No Telegram export has ever been held
/// by this project; the schema is derived from Telegram Desktop's own
/// generator plus real third-party fixtures (see `TelegramExport`'s header).
/// Every read fails SAFE — a missing or odd field is a skip, never a crash and
/// never a wrong date — and a folder that isn't an export is refused outright
/// rather than landing a half-room.
enum TelegramImport {

    static let source = TelegramExport.source

    struct Summary {
        var saved = 0
        var channelPosts = 0
        var conversations = 0
        var skipped = 0
        var dropped = 0
        var failed = false
        /// Why it failed, in words the screen can show. nil on success.
        var reason: String?

        var imported: Int { saved + channelPosts + conversations }

        /// What the screen says after a run. Names each half separately: a
        /// person who imported with messages off and sees one number cannot
        /// tell whether their chats were skipped by choice or lost.
        var landedLine: String {
            guard imported > 0 else {
                return skipped > 0
                    ? String(localized: "Nothing new — it's all already here.")
                    : String(localized: "Nothing to import from that folder.")
            }
            var parts: [String] = []
            if saved > 0 { parts.append(String(localized: "\(saved) saved")) }
            if channelPosts > 0 { parts.append(String(localized: "\(channelPosts) channel posts")) }
            if conversations > 0 { parts.append(String(localized: "\(conversations) conversations")) }
            if dropped > 0 { parts.append(String(localized: "\(dropped) older not imported")) }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - Run

    @MainActor
    static func run(folder: URL, context: ModelContext,
                    progress: ((Int) -> Void)? = nil) async -> Summary {
        var summary = Summary()

        guard let file = resultFile(in: folder) else {
            summary.failed = true
            summary.reason = String(localized: "No result.json in that folder — export as JSON, then bring the unzipped folder.")
            return summary
        }
        guard let data = try? Data(contentsOf: file),
              let root = TelegramExport.decode(data) else {
            summary.failed = true
            // The likeliest cause by far, and one nobody could guess: Telegram
            // writes control bytes as `\xNN`, which is not valid JSON.
            // `decode` repairs that before parsing, so reaching here means
            // something else entirely.
            summary.reason = String(localized: "Couldn't read result.json — it may be incomplete.")
            return summary
        }

        let parsed = TelegramExport.parse(root, includeMessages: ImportOptions.includeMessages)
        guard parsed.isExport else {
            summary.failed = true
            summary.reason = String(localized: "That folder doesn't look like a Telegram export.")
            return summary
        }

        let existing = IngestSupport.thingsByRef(context, source: source)
        var seen = Set(existing.keys)
        var landed: [Thing] = []
        var jobs: [ImportMedia.Job] = []

        // Saved Messages — the pile of links you send yourself, and the
        // strongest reason this seat exists.
        for entry in parsed.savedMessages {
            let ref = TelegramExport.savedRef(messageID: entry.id)
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)
            let thing = row(entry, ref: ref, tags: ["Saved"], handle: nil)
            landed.append(thing)
            addMediaJob(entry, ref: ref, folder: folder, into: &jobs)
            summary.saved += 1
        }

        // Channels you were subscribed to. Their posts are somebody's
        // broadcast, so they wear the channel as their author exactly as a
        // followed channel's posts do.
        for channel in parsed.channels {
            for entry in channel.entries {
                let ref = TelegramExport.channelRef(chatID: channel.id, messageID: entry.id)
                guard !seen.contains(ref) else { summary.skipped += 1; continue }
                seen.insert(ref)
                let thing = row(entry, ref: ref, tags: ["Channel"], handle: channel.name)
                landed.append(thing)
                addMediaJob(entry, ref: ref, folder: folder, into: &jobs)
                summary.channelPosts += 1
            }
        }

        // Conversations — ONE thing each, never one per message, and the count
        // is the pre-clamp total because a leaderboard ranks on it.
        for conversation in parsed.conversations {
            let ref = TelegramExport.chatRef(chatID: conversation.id)
            if let held = existing[ref], held.isLive {
                // A chat GROWS, unlike a finished post, so a re-import heals
                // it in place rather than skipping it (Snapchat's rule).
                if conversation.newest > held.capturedAt {
                    held.content = conversation.transcript
                    held.capturedAt = conversation.newest
                    held.messageCount = conversation.total
                    held.embedding = nil
                }
                summary.skipped += 1
                continue
            }
            guard !seen.contains(ref) else { summary.skipped += 1; continue }
            seen.insert(ref)
            let thing = Thing(
                kind: .chat,
                title: String(localized: "Chat with \(conversation.handle)"),
                content: conversation.transcript,
                source: source,
                capturedAt: conversation.newest,
                tags: ["Conversation"],
                sourceRef: ref
            )
            thing.authorHandle = conversation.handle
            thing.messageCount = conversation.total
            landed.append(thing)
            summary.conversations += 1
        }

        summary.dropped = parsed.counts.dropped

        guard summary.imported > 0 else {
            // Nothing new is a real outcome, not a failure — but a heal above
            // may still have changed a conversation, so save either way.
            if (try? context.save()) == nil {
                summary.failed = true
                summary.reason = String(localized: "Couldn't save what was read.")
            }
            return summary
        }

        // Pictures are the same 480pt thumbnail every other import writes —
        // read INSIDE the caller's security-scoped grant, which is held across
        // this await for the reason `ImportCommit` records.
        let pixels = await ImportMedia.decode(jobs, folder: folder)
        ImportMedia.apply(pixels, to: landed)

        guard await ImportCommit.commit(landed, context: context,
                                        source: source, progress: progress) else {
            summary.failed = true
            summary.reason = String(localized: "Couldn't save what was read.")
            return summary
        }
        ImportReceipt.land(source: source, count: summary.imported,
                           detail: summary.landedLine, context: context)
        if (try? context.save()) == nil {
            summary.failed = true
            summary.reason = String(localized: "Couldn't save what was read.")
        }
        return summary
    }

    // MARK: - Rows

    /// One landable message.
    ///
    /// `.link` when the message is a bare link somebody sent themselves —
    /// which most of Saved Messages is — and `.note` otherwise, so the room
    /// draws a reading row for the first and a post card for the second.
    private static func row(_ entry: TelegramExport.Entry, ref: String,
                            tags: [String], handle: String?) -> Thing {
        var tags = tags
        if entry.forwardedFrom != nil { tags.append("Forwarded") }
        if entry.isPhoto { tags.append("Photo") }

        let link = entry.links.first
        let isBareLink = entry.isWordless == false
            && link != nil
            && entry.text.trimmingCharacters(in: .whitespacesAndNewlines) == link

        let title = entry.text.isEmpty
            ? (entry.mediaLabel ?? String(localized: "Message"))
            : IngestSupport.titleLine(entry.text)

        let thing = Thing(
            kind: isBareLink || (entry.isWordless && link != nil) ? .link : .note,
            title: title,
            // A link's `content` is the permalink every other bridge puts
            // there, so open/share/route logic is untouched; anything else
            // keeps its own words.
            content: isBareLink ? (link ?? entry.text) : entry.text,
            source: source,
            capturedAt: entry.date,
            tags: tags,
            sourceRef: ref
        )
        if !entry.text.isEmpty { thing.postText = entry.text }
        if let handle { thing.authorHandle = handle }
        // A forward names somebody the channel is not — the same field a
        // followed channel's forward lands on.
        if let from = entry.forwardedFrom { thing.postAuthor = from }
        if let link, !isBareLink { thing.externalLink = link }
        return thing
    }

    private static func addMediaJob(_ entry: TelegramExport.Entry, ref: String,
                                    folder: URL, into jobs: inout [ImportMedia.Job]) {
        guard jobs.count < ImportMedia.perImport,
              let relative = entry.mediaPath,
              let file = ImportMedia.resolve(relative, under: folder) else { return }
        jobs.append(ImportMedia.Job(ref: ref, file: file,
                                    isVideo: ImportMedia.isVideoFile(file)))
    }

    // MARK: - Finding the file

    /// `result.json` sits at the export root — but people bring the folder
    /// they unzipped, which is often one level up from it, so this looks one
    /// deep as well (`SnapchatImport.locate`'s reasoning).
    private static func resultFile(in folder: URL) -> URL? {
        let direct = folder.appendingPathComponent("result.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        guard let kids = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return nil }
        for kid in kids.prefix(40) {
            let nested = kid.appendingPathComponent("result.json")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }
}
