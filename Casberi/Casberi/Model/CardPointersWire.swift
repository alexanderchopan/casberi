import Foundation

/// The CardPointers wire, as MEASURED against the live service on 2026-08-20
/// (prd §420) — not as read off their docs, which cannot be opened, nor off
/// their CLI alone, which is where every earlier description of this protocol
/// came from and which got two things wrong.
///
/// Foundation-only BY DESIGN so `scripts/cardpointers-selftest.sh` can compile
/// it WHOLE and unmodified. Everything here is a pure function over bytes; the
/// requests themselves live in `CardPointersBridge`.
///
/// **The two corrections measurement bought, both of which would have shipped
/// a bridge that never returned a single row:**
///
/// 1. **The host is `mcp.cardpointers.com`, and that includes the sign-in.**
///    Device flow reads as "plain REST outside MCP", which invites the
///    assumption that it lives on the marketing host; it does not.
///    `/api/device/code` and `/api/device/token` are both on the MCP host.
/// 2. **Responses are SSE-framed, not JSON.** A `tools/call` answers
///    `event: message\ndata: {…}`, so handing the body straight to
///    `JSONSerialization` fails on byte one. The failure is the expensive
///    kind: it is indistinguishable from an empty account, because a decode
///    that returns nil and an account with no offers both render as a room
///    with nothing in it.
enum CardPointersWire {

    static let apiBase = "https://mcp.cardpointers.com"
    static let mcpPath = "/mcp"

    // MARK: - SSE framing

    /// Pull the JSON-RPC envelope out of an SSE body.
    ///
    /// The LAST `data:` line wins, deliberately. SSE is a stream and the
    /// service is free to send progress frames ahead of the result; taking the
    /// first would return whatever it said before it had an answer. A body
    /// with no framing at all is returned unchanged, so if they ever serve
    /// plain JSON this keeps working rather than going silent.
    static func unframe(_ body: String) -> String {
        let data = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("data:") }
            .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        return data.last ?? body
    }

    // MARK: - JSON-RPC

    /// What a `tools/call` can come back as. `subscriptionRequired` is its own
    /// case rather than an error string because it is not a failure — it is
    /// the state MOST people who tap this tile will be in, it is knowable in
    /// advance from `is_pro`, and it has a real door (`upgradeURL`) rather
    /// than a dead end.
    enum Answer: Equatable {
        case payload(String)
        case subscriptionRequired(upgradeURL: String?)
        case failed(code: Int, message: String)
        case unreadable
    }

    /// Their "not a subscriber" code. Measured 2026-08-20 against a free
    /// account: ALL FIVE tools answer with it — `recommend_card` included,
    /// which is the one a reasonable person would expect to be free, since it
    /// recommends from a wallet you could have entered yourself. Nothing is
    /// readable without CardPointers+, so the seat states that before the tap.
    static let subscriptionRequiredCode = -32001

    static func answer(from body: String) -> Answer {
        guard let data = unframe(body).data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .unreadable }

        if let error = root["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 0
            if code == subscriptionRequiredCode {
                let info = error["data"] as? [String: Any]
                return .subscriptionRequired(upgradeURL: info?["upgrade_url"] as? String)
            }
            return .failed(code: code, message: error["message"] as? String ?? "")
        }

        // The payload arrives as a JSON STRING inside the first content block,
        // so a caller decodes twice. Kept as a String here rather than decoded
        // because this type never learns what a card or an offer looks like —
        // no account on this project has ever been able to read one.
        guard let result = root["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else { return .unreadable }
        return .payload(text)
    }

    static func callBody(tool: String, arguments: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
         "params": ["name": tool, "arguments": arguments]]
    }

    // MARK: - Device flow (RFC 8628)

    /// What `/api/device/code` hands back. `verificationURLComplete` already
    /// carries the user code, so in practice nobody types anything — but
    /// `userCode` is still shown, because a browser that opens to a signed-out
    /// session sends them round a sign-in first and the code has to survive
    /// that trip.
    struct DeviceCode: Equatable {
        var deviceCode: String
        var userCode: String
        var verificationURLComplete: String
        var interval: Int
        var expiresIn: Int
    }

    static func deviceCode(from json: Any?) -> DeviceCode? {
        guard let d = json as? [String: Any],
              let device = d["device_code"] as? String, !device.isEmpty,
              let user = d["user_code"] as? String, !user.isEmpty
        else { return nil }
        let complete = (d["verification_uri_complete"] as? String)
            ?? (d["verification_uri"] as? String) ?? ""
        return DeviceCode(
            deviceCode: device,
            userCode: user,
            verificationURLComplete: complete,
            // Measured: interval 5, expires_in 900. Defaulted rather than
            // required — RFC 8628 makes both optional, and a missing interval
            // must never become a zero-second poll loop against their host.
            interval: max(1, d["interval"] as? Int ?? 5),
            expiresIn: d["expires_in"] as? Int ?? 900)
    }

    /// The poll's outcomes. `pending` is not an error and must not be
    /// surfaced as one — it is the normal answer for as long as somebody is
    /// still reading the approval page.
    ///
    /// **MEASURED, and it is the trap in this whole flow: a pending poll
    /// answers HTTP 400, not 200** (2026-08-20). The reason lives in the body;
    /// the status says only that this is not a token. So the caller must read
    /// the body REGARDLESS of status — `IngestSupport.postJSONStatus` returns
    /// `(nil, 400)` and discards it, which would turn "they haven't clicked
    /// yet" into a hard failure and make sign-in impossible to complete.
    /// Their own CLI never inspects the status code at all, which is why no
    /// amount of reading it would have surfaced this.
    enum Poll: Equatable {
        case pending
        case granted(Token)
        case denied
        case expired
        case unreadable
    }

    /// The sign-in response — and `isPro` is the find that shapes the whole
    /// seat. Subscription status arrives WITH THE TOKEN, so the app knows what
    /// this account can do before it makes a single MCP call. Without it the
    /// only way to learn was to connect, read, fail, and show somebody an
    /// empty room; with it the connect screen can state the truth the instant
    /// sign-in lands.
    ///
    /// `email` and `uuid` are deliberately NOT modelled. They are identity we
    /// have no use for, and a field that is never read is a field that cannot
    /// leak.
    struct Token: Equatable {
        var accessToken: String
        var isPro: Bool
    }

    static func poll(from json: Any?) -> Poll {
        guard let d = json as? [String: Any] else { return .unreadable }
        if let error = d["error"] as? String {
            switch error {
            case "authorization_pending", "slow_down": return .pending
            case "access_denied": return .denied
            // `invalid_grant` is theirs for "Device code not found" (measured
            // against a fabricated code). Terminal, not pending: a code that
            // is unknown now will not become known by asking again, and
            // treating it as pending polls their host for fifteen minutes over
            // a code that will never work.
            case "expired_token", "invalid_grant": return .expired
            default: return .unreadable
            }
        }
        guard let token = d["access_token"] as? String, !token.isEmpty else { return .unreadable }
        // Absent `is_pro` reads as NOT pro. The pessimistic default is the
        // honest one: claiming a subscription somebody does not have puts them
        // in front of a room that can never fill (§83).
        return .granted(Token(accessToken: token, isPro: d["is_pro"] as? Bool ?? false))
    }
}
