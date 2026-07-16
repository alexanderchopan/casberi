import Foundation
import SwiftData

/// The Claude bridge (2026-07-12) — a one-time import, the grade PRD S9 always
/// named for Claude ("import — batch via official export"). Anthropic offers no
/// live user-data read, so the person's own export is the sanctioned way in.
/// The export's `conversations.json` parses into chat things — one per
/// conversation, titled as the person titled it, dated when it last moved.
/// Re-imports dedupe on the conversation uuid.
///
/// Claude's export differs from ChatGPT's in three ways this parser handles:
/// the title lives in `name` (not `title`), timestamps are ISO-8601 strings
/// (not Unix doubles), and messages are a flat `chat_messages` array with a
/// `sender` of "human"/"assistant" (not a `mapping` graph).
enum ClaudeImport {

    struct Summary {
        var imported = 0
        var skipped = 0
        var failed = false
    }

    /// Parses a `conversations.json` (Claude data export) and lands each
    /// conversation as one chat thing. Caps at the newest 500 — a years-deep
    /// export shouldn't flood the corpus in one tap.
    @MainActor
    static func run(data: Data, context: ModelContext) -> Summary {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let conversations = root as? [[String: Any]] else {
            return Summary(failed: true)
        }

        let existing = IngestSupport.existingSourceRefs(context)

        // Newest first (by last-updated), cap 500.
        let sorted = conversations.sorted {
            (stamp($0) ?? .distantPast) > (stamp($1) ?? .distantPast)
        }.prefix(500)

        var summary = Summary()
        for convo in sorted {
            let name = (convo["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Claude leaves `name` empty for short or never-titled chats far
            // more often than ChatGPT — fall back to the opening ask so those
            // chats still land; skip only when there's neither a title nor a
            // human line to name it by.
            let opener = firstHumanLine(convo)
            let title = name.isEmpty ? opener : name
            guard !title.isEmpty else { summary.skipped += 1; continue }

            let when = stamp(convo)
            let id = (convo["uuid"] as? String)
                ?? "\(title)-\(when?.timeIntervalSince1970 ?? 0)"
            let ref = "claude:\(id)"
            guard !existing.contains(ref) else { summary.skipped += 1; continue }

            let thing = Thing(
                kind: .chat,
                title: title,
                // Don't echo the opener as the subtitle when it's the title.
                content: title == opener ? "" : opener,
                source: "Claude",
                capturedAt: when ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            summary.imported += 1
        }
        if summary.imported > 0 { context.saveHonestly() }
        return summary
    }

    /// When the conversation last moved — `updated_at`, falling back to
    /// `created_at`. Both are ISO-8601 strings in Claude's export.
    private static func stamp(_ convo: [String: Any]) -> Date? {
        parseDate(convo["updated_at"] as? String)
            ?? parseDate(convo["created_at"] as? String)
    }

    /// The opening ask — the first human message, the one line that reminds you
    /// what the chat was. `chat_messages` is already chronological.
    private static func firstHumanLine(_ convo: [String: Any]) -> String {
        guard let messages = convo["chat_messages"] as? [[String: Any]] else { return "" }
        for message in messages {
            guard (message["sender"] as? String) == "human" else { continue }
            let text = messageText(message)
            guard !text.isEmpty else { continue }
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.count > 200 ? String(line.prefix(200)) + "…" : line
        }
        return ""
    }

    /// A message's text — the top-level `text`, or the joined `content` blocks
    /// (newer exports carry structured content and leave `text` empty).
    private static func messageText(_ message: [String: Any]) -> String {
        if let text = message["text"] as? String, !text.isEmpty { return text }
        guard let content = message["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { $0["text"] as? String }.joined(separator: " ")
    }

    // MARK: - Dates (ISO-8601, tolerant of Claude's 6-digit microseconds)

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses an ISO-8601 stamp. Claude writes microseconds (6 fractional
    /// digits); `ISO8601DateFormatter` accepts exactly 3 (`iso`) or none
    /// (`isoPlain`). On a miss we strip the whole fractional component and
    /// retry — one path that covers 6-digit microseconds, a 1–2 digit
    /// fraction, and a numeric "+00:00" offset in place of "Z" alike (a wrong
    /// date would otherwise fall back to `.now` and jump the chat to the top of
    /// the feed).
    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = iso.date(from: s) { return d }
        if let d = isoPlain.date(from: s) { return d }
        let stripped = s.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        return stripped == s ? nil : isoPlain.date(from: stripped)
    }
}
