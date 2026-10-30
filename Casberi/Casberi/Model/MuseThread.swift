import Foundation

/// Muse's one chat, read off its own page (prd §1619) — the pure half,
/// Foundation only, so `muse-thread-selftest.sh` compiles it whole.
///
/// ## WHAT WAS MEASURED (2026-10-30, a real account)
///
/// Muse (muse.ai, Meta's agent) has no API a client may call. Its page talks
/// to `wss://hatch.metaaivm.com/v1/noise` — binary frames inside a Noise
/// handshake, opened with a session token and a Meta "notary" endorsement —
/// so nothing outside the page can speak it. What the page DRAWS is plain:
///
///   · every message is a `[data-message-item="true"]` element carrying
///     `data-message-id` and `data-message-role` (`user` / `assistant`);
///   · a person's message reads "You:" over its words; an assistant's words
///     sit in `[data-hatch-assistant-message-body]`;
///   · the composer is the page's one `textarea`, and Enter sends it.
///
/// So `MuseWeb` keeps the page open out of sight, types into it and reads
/// these elements back, and this file decides which of them are the reply.
///
/// ## ONE THREAD, NOT A CHAT PER QUESTION
///
/// Muse has a single conversation per person, and it answers in it the way
/// a person texts: a reply can be several messages, and it may open with news
/// of its own before it gets to the question ("Quick update I owe you
/// first…" then "ready", measured). The reply is therefore EVERY assistant
/// message after the one this app sent, joined, and it is final only when
/// the page has gone quiet (`Settle`).
enum MuseThread {

    struct Message: Equatable, Decodable {
        let id: String
        let role: String
        let text: String
    }

    /// A person's message with the page's "You:" heading taken off.
    static func words(_ message: Message) -> String {
        var text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("You:") {
            text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Where the message this app sent stands on the page now: the last NEW
    /// person's message whose words are `sent`, else the last new person's
    /// message (the page may tidy whitespace). Nil until it shows.
    static func sentIndex(sent: String, before: Set<String>, now: [Message]) -> Int? {
        let wanted = sent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fresh = now.indices.filter { now[$0].role == "user" && !before.contains(now[$0].id) }
        return fresh.last(where: { words(now[$0]) == wanted }) ?? fresh.last
    }

    /// The reply so far: every assistant message after the one sent, joined
    /// by a blank line. Nil while Muse has said nothing after it.
    static func reply(sent: String, before: Set<String>, now: [Message]) -> String? {
        guard let index = sentIndex(sent: sent, before: before, now: now) else { return nil }
        let parts = now[(index + 1)...]
            .filter { $0.role == "assistant" }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// The page shows no "working" state (measured: its `role=status`
    /// regions stay empty while Muse writes), so a reply is final once it has
    /// stopped changing for `quietPolls` reads in a row.
    struct Settle {
        let quietPolls: Int
        private(set) var last: String?
        private(set) var unchanged = 0

        init(quietPolls: Int) { self.quietPolls = quietPolls }

        /// Takes one read; true when the reply has settled.
        mutating func see(_ reply: String?) -> Bool {
            guard let reply else { last = nil; unchanged = 0; return false }
            if reply == last {
                unchanged += 1
            } else {
                last = reply
                unchanged = 0
            }
            return unchanged >= quietPolls
        }
    }
}
