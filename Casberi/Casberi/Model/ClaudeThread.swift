import Foundation

/// Claude's answer, read from claude.ai's own conversation JSON (prd §1624) —
/// the pure half, Foundation only, so `claude-thread-selftest.sh` compiles it
/// whole.
///
/// ## WHAT WAS MEASURED (2026-10-30, a real account)
///
///   · after the first message the page's address becomes `/chat/<id>`;
///   · `GET /api/organizations/<org>/chat_conversations/<id>?tree=True&
///     rendering_mode=messages` answers `chat_messages`, each with `sender`
///     (`human` / `assistant`), `index`, `created_at` (ISO 8601, fractional
///     seconds), `stop_reason` (`end_turn` when done) and `content` blocks
///     (`thinking`, then `text`: measured "meridian");
///   · the chat lives in the organization whose `capabilities` hold `chat`;
///     an API-only organization answers 401 for it.
///
/// So the answer is the LAST message, once it is the assistant's, stopped
/// and newer than the question; its words are its `text` blocks, never its
/// thinking.
enum ClaudeThread {

    static func reply(conversation: [String: Any], sentAt: Double) -> String? {
        guard let messages = conversation["chat_messages"] as? [[String: Any]],
              let last = messages.max(by: { ($0["index"] as? Int ?? -1) < ($1["index"] as? Int ?? -1) }),
              last["sender"] as? String == "assistant",
              let stop = last["stop_reason"] as? String, !stop.isEmpty else { return nil }
        // The clocks are the phone's and Anthropic's; two seconds of slack.
        if let created = (last["created_at"] as? String).flatMap(date), created.timeIntervalSince1970 < sentAt - 2 {
            return nil
        }
        let blocks = (last["content"] as? [[String: Any]]) ?? []
        var text = blocks.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n\n")
        if blocks.isEmpty { text = last["text"] as? String ?? "" }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// `2026-10-30T19:35:49.228276Z`, and the same without fractions.
    static func date(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
