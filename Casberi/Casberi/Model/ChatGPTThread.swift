import Foundation

/// ChatGPT's answer, read from its own conversation JSON (prd §1623) — the
/// pure half, Foundation only, so `chatgpt-thread-selftest.sh` compiles it
/// whole.
///
/// ## WHAT WAS MEASURED (2026-10-30, a real account)
///
/// Every message ChatGPT's page sends is preceded by a proof of work its own
/// script computes (`sentinel/chat-requirements/prepare` → `finalize`), so
/// `ChatGPTWeb` types into the page and lets it send. Reading is plainer:
///
///   · after the first message the page's address becomes `/c/<id>`;
///   · `GET /backend-api/conversation/<id>`, with the session's own bearer
///     from `/api/auth/session`, answers the whole chat: `current_node` and a
///     `mapping` of nodes, each `message` carrying `author.role`, `status`
///     (`finished_successfully` when done), `create_time` in epoch seconds
///     and `content.parts` (measured: "harbor", `finished_successfully`).
///
/// So the reply is the CURRENT node, once it is the assistant's, finished,
/// and newer than the question — a real "done", where Muse's page has only
/// silence.
enum ChatGPTThread {

    enum Reply: Equatable {
        /// Nothing finished after the question yet.
        case pending
        case done(String)
    }

    /// The chat's id in a page address: `/c/<id>`, also under a GPT
    /// (`/g/<gpt>/c/<id>`). Nil on the home page.
    static func conversationID(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.lastIndex(of: "c"), index + 1 < parts.count else { return nil }
        let id = parts[index + 1]
        return id.isEmpty ? nil : id
    }

    /// The reply in a conversation read, for a question sent at `sentAt`
    /// (epoch seconds). A current node that is the question itself, still
    /// writing, older than the question or with no words is `.pending`.
    static func reply(conversation: [String: Any], sentAt: Double) -> Reply {
        guard let current = conversation["current_node"] as? String,
              let mapping = conversation["mapping"] as? [String: Any],
              let node = mapping[current] as? [String: Any],
              let message = node["message"] as? [String: Any],
              let author = message["author"] as? [String: Any],
              author["role"] as? String == "assistant",
              (message["status"] as? String)?.hasPrefix("finished") == true else { return .pending }
        // The clocks are the phone's and OpenAI's; two seconds of slack.
        if let created = message["create_time"] as? Double, created < sentAt - 2 { return .pending }
        let content = message["content"] as? [String: Any]
        let text = ((content?["parts"] as? [Any]) ?? [])
            .compactMap { $0 as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .pending : .done(text)
    }

    /// Which ChatGPT chat a Casberi conversation continues: keyed by its
    /// first question, so a follow-up lands in the chat that holds its
    /// context and a new conversation starts a new chat.
    static func chatKey(firstQuestion: String) -> String {
        firstQuestion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
