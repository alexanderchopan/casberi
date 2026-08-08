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
        /// Conversations already here that gained their transcript and message
        /// count on this pass — see `ChatGPTImport.Summary.healed`, which this
        /// mirrors exactly. A re-import is the only thing that can reach a
        /// chat landed before this build.
        var healed = 0
        /// Conversations the cap refused (§307/§309).
        var dropped = 0
        /// Conversations whose transcript hit `ChatTranscript.cap`.
        var clamped = 0
        var failed = false
    }

    /// The newest N conversations — `ChatGPTImport.conversationCap`'s number
    /// and its reasoning, including why it wasn't raised here.
    static let conversationCap = 500

    /// Parses a `conversations.json` (Claude data export) and lands each
    /// conversation as one chat thing.
    @MainActor
    static func run(data: Data, context: ModelContext) -> Summary {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let conversations = root as? [[String: Any]] else {
            return Summary(failed: true)
        }

        // A dictionary, not a ref set — an already-imported conversation is
        // repaired here, not skipped (2026-08-08).
        let existing = IngestSupport.thingsByRef(context, source: "Claude")

        // Newest first (by last-updated), capped.
        let sorted = conversations.sorted {
            (stamp($0) ?? .distantPast) > (stamp($1) ?? .distantPast)
        }.prefix(conversationCap)

        var summary = Summary()
        summary.dropped = max(0, conversations.count - conversationCap)
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

            let script = transcript(convo)
            if script.clamped { summary.clamped += 1 }

            if let already = existing[ref] {
                // A held `Thing` — liveness before any stored read.
                guard already.isLive else { summary.skipped += 1; continue }
                if ChatImportLanding.apply(script, to: already) {
                    summary.healed += 1
                } else {
                    summary.skipped += 1
                }
                continue
            }

            let thing = Thing(
                kind: .chat,
                title: title,
                // Don't echo the opener as the subtitle when it's the title.
                // UNCHANGED by the transcript pass: `content` stays the
                // opening ask (what `ChatBubbles` draws), and the conversation
                // lands on `enrichedText`, which is retrieval-only.
                content: title == opener ? "" : opener,
                source: "Claude",
                capturedAt: when ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            ChatImportLanding.apply(script, to: thing)
            SpotlightIndex.index([thing])
            summary.imported += 1
        }
        if summary.imported > 0 || summary.healed > 0 { context.saveHonestly() }
        return summary
    }

    // MARK: - The conversation itself

    /// Every message that was really said, in order.
    ///
    /// Flat, unlike ChatGPT's graph: `chat_messages` is already chronological
    /// and carries no branches, so there is nothing to walk — which makes the
    /// interesting part the FILTER. A sender that is neither human nor
    /// assistant is chrome, and a content block that isn't prose (a
    /// `tool_use`, a `tool_result`, a `thinking` block) is machinery this room
    /// has no business holding.
    static func turns(_ convo: [String: Any]) -> [(speaker: String, text: String)] {
        guard let messages = convo["chat_messages"] as? [[String: Any]] else { return [] }
        return messages.compactMap { message in
            guard let sender = message["sender"] as? String,
                  let speaker = speakerName(sender) else { return nil }
            let text = messageText(message)
            return text.isEmpty ? nil : (speaker, text)
        }
    }

    /// Who said it. Anything else returns nil — Claude's export has carried a
    /// third sender before, and a room of somebody's chats is the wrong place
    /// to guess what a new one means.
    private static func speakerName(_ sender: String) -> String? {
        switch sender {
        case "human": return "You"
        case "assistant": return "Claude"
        default: return nil
        }
    }

    /// The whole conversation, flattened and clamped.
    static func transcript(_ convo: [String: Any]) -> ChatTranscript {
        ChatTranscript.make(turns(convo))
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
    ///
    /// The block filter (2026-08-08) is what keeps tool noise out of a
    /// transcript: a `tool_use` block carries its arguments and a `thinking`
    /// block carries reasoning nobody wrote, and both can sit in the same
    /// array as the prose. An untyped block is read as text — that is the
    /// older export's shape, where `type` is absent and the block IS the
    /// words.
    private static func messageText(_ message: [String: Any]) -> String {
        if let text = message["text"] as? String, !text.isEmpty { return text }
        guard let content = message["content"] as? [[String: Any]] else { return "" }
        return content
            .filter { (($0["type"] as? String) ?? "text") == "text" }
            .compactMap { $0["text"] as? String }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
