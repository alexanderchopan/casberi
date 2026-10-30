import Foundation

/// Gemini's answer, read off gemini.google.com's own page (prd §1627) — the
/// pure half, Foundation only, so `gemini-thread-selftest.sh` compiles it
/// whole.
///
/// ## WHAT WAS MEASURED (2026-10-30, a real account)
///
/// Gemini's traffic is Google's `batchexecute` RPC — positional arrays, no
/// chat JSON a reader could lean on — so the answer is read where the page
/// draws it, as Muse's is: each answer is a `model-response` whose words sit
/// in its `message-content` (measured: "harbinger"), a chat's address is
/// `/app/<id>`, and while Gemini writes the page shows a Stop button.
///
/// So the answer is the NEWEST `model-response`, once there is one more than
/// before the question, Gemini has no Stop button up, and the words have held
/// still (`MuseThread.Settle`).
enum GeminiThread {

    /// What the page's script reports each read.
    struct Snapshot: Decodable, Equatable {
        /// Every answer's words, oldest first.
        let models: [String]
        /// A Stop button is up: Gemini is still writing.
        let generating: Bool
        let path: String
    }

    /// The chat in `/app/<id>`; nil on the new-chat page.
    static func chatID(path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "app"), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    /// The answer so far: the newest answer's words, once the page holds
    /// more answers than the `before` it held when the question went.
    static func reply(before: Int, now: Snapshot) -> String? {
        guard now.models.count > before,
              let words = now.models.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !words.isEmpty else { return nil }
        return words
    }
}
