import Foundation

/// Grok's answer, read from grok.com's own conversation JSON (prd §1626) —
/// the pure half, Foundation only, so `grok-thread-selftest.sh` compiles it
/// whole.
///
/// ## WHAT WAS MEASURED (2026-10-30)
///
/// Signed out, grok.com chats; its `/rest/app-chat/…` and `/rest/auth/get-user`
/// answer 401 `code 16` "No credentials presented", and `/api/auth/session`
/// answers `{"status":"unauthenticated"}`. Signing in is xAI's own
/// (`accounts.x.ai/sign-in?redirect=grok-com`), and Cloudflare let it through
/// in iOS's WebKit where it refused the desktop browser pane.
///
/// The page reads a chat as its response nodes (`GET /rest/app-chat/
/// conversations/<id>/response-node`) and then the responses themselves
/// (`POST …/load-responses` with their ids). Measured in the app on the
/// user's account: `{responses: [2 × 45 keys]}`, the last the assistant's,
/// and this reader returned "lodestar" in 4 s. It reads `sender`, `message`,
/// and, where present, `partial` and `createTime`.
enum GrokThread {

    /// The finished answer in a `load-responses` read, for a question sent at
    /// an epoch second; nil while there is none.
    static func reply(conversation: [String: Any], sentAt: Double) -> String? {
        guard let responses = conversation["responses"] as? [[String: Any]],
              let last = responses.last,
              (last["sender"] as? String)?.lowercased() == "assistant",
              (last["partial"] as? Bool) != true else { return nil }
        if let created = (last["createTime"] as? String).flatMap(date), created.timeIntervalSince1970 < sentAt - 2 {
            return nil
        }
        let text = (last["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func date(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
