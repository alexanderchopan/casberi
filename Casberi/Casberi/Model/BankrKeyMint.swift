import Foundation

/// Casberi makes the Bankr key itself (prd §800) — the pure half, Foundation
/// only, so `bankr-mint-selftest.sh` compiles it whole.
///
/// ## WHAT WAS MEASURED, AND WHAT IT ALLOWS
///
/// The seat used to end in an errand: sign in at bankr.bot, find the key page,
/// tick the right boxes, copy the key, come back, paste. §529 said only Bankr
/// could remove that last step. The web-session capture (§777) said otherwise,
/// on a real account, 2026-09-16:
///
///   · bankr.bot's own key page creates a key with ONE call —
///     `POST api.bankr.bot/api-keys`, body `{name, agentApiEnabled, readOnly,
///     walletApiEnabled, tokenLaunchApiEnabled, llmGatewayEnabled}`, → 201
///     with `apiKey` in the body;
///   · the call carries NO auth header. The pass is the `privy-token` cookie
///     (HttpOnly, on `.bankr.bot`) that signing in writes, sent because the
///     page asks with `credentials: include`;
///   · a key made that way with Agent API on shows the Agent API badge — the
///     block Bankr's CLI states ("must be enabled from the website") is the
///     CLI's, not the server's.
///
/// So the sheet signs in on Bankr's own page, and then asks for the key FROM
/// that page, the way the page does. Casberi never reads the cookie; WebKit
/// attaches it, exactly as it did for the person's own tap.
///
/// ## THE SCOPE IS CASBERI'S, NOT A CHECKBOX
///
/// The paste flow asked a person to remember to tick read-only. Here the
/// request says it, and a key that comes back any wider than asked is NOT
/// stored (`Outcome.tooWide`) — a key that can trade is not the one this app
/// asked for, whatever Bankr decided to issue.
enum BankrKeyMint {

    /// Where the sheet starts: bankr.bot's chat, which is where its home
    /// page's "Chat with Bankr" goes (read from bankr.bot's own bundle,
    /// 2026-09-16: `onClick: () => navigate("/terminal/chat")`) and which
    /// raises the sign-in when signed out. `/api-keys` was the first choice
    /// and signed out it lands on the home page, whose two buttons ("Launch
    /// your token", "Chat with Bankr") left people guessing which one signs
    /// in (user, 2026-09-16). The key call does not need the key page: any
    /// bankr.bot page is the origin it runs from.
    static let startURL = URL(string: "https://bankr.bot/terminal/chat")!
    static let endpoint = "https://api.bankr.bot/api-keys"

    /// The cookie whose arrival means a sign-in finished. Its NAME only.
    static let sessionCookie = "privy-token"

    /// The permissions Casberi asks for. Agent API is what `BankrAgent` calls;
    /// everything else is off, because nothing in this app calls it.
    struct Scope: Equatable {
        var agentApi: Bool
        var readOnly: Bool
        var walletApi: Bool
        var tokenLaunchApi: Bool
        var llmGateway: Bool
    }

    static let scope = Scope(agentApi: true, readOnly: true, walletApi: false,
                             tokenLaunchApi: false, llmGateway: false)

    /// "Casberi 2026-09-16" — the name a person sees on bankr.bot's key list,
    /// so the key this app made is findable and revocable there.
    static func keyName(on date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "Casberi \(f.string(from: date))"
    }

    /// The request body, keys exactly as bankr.bot's own page sends them.
    static func requestBody(name: String, scope: Scope = scope) -> String {
        let body: [String: Any] = [
            "name": name,
            "agentApiEnabled": scope.agentApi,
            "readOnly": scope.readOnly,
            "walletApiEnabled": scope.walletApi,
            "tokenLaunchApiEnabled": scope.tokenLaunchApi,
            "llmGatewayEnabled": scope.llmGateway,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether the jar holds a Bankr session — by cookie NAME and domain.
    /// A lookalike domain (`notbankr.bot`) is not Bankr.
    static func isSignedIn(_ cookies: [(name: String, domain: String)]) -> Bool {
        cookies.contains { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return cookie.name == sessionCookie
                && (domain == "bankr.bot" || domain.hasSuffix(".bankr.bot"))
        }
    }

    /// Whether the page is on Bankr's own origin, where the page's
    /// `credentials: include` call is the one its CORS allows.
    static func isBankrPage(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "bankr.bot" || host == "www.bankr.bot"
    }

    enum Outcome: Equatable {
        case minted(key: String)
        /// 401/403 — the session was not ready, or was refused.
        case signedOut
        /// Bankr issued a key wider than asked. Not stored.
        case tooWide
        /// Any other status, or a body that is not a key.
        case failed(status: Int)
    }

    /// The response, read. `apiKey` must be present AND the flags Bankr echoes
    /// must be the ones asked for; an absent flag is not a yes.
    static func outcome(status: Int, body: String) -> Outcome {
        if status == 401 || status == 403 { return .signedOut }
        guard (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let key = json["apiKey"] as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failed(status: status) }
        guard json["readOnly"] as? Bool == true,
              json["agentApiEnabled"] as? Bool == true,
              json["walletApiEnabled"] as? Bool != true,
              json["tokenLaunchApiEnabled"] as? Bool != true
        else { return .tooWide }
        return .minted(key: key)
    }

    /// The sentence for a key that did not arrive. Nil for a key that did.
    static func line(for outcome: Outcome) -> String? {
        switch outcome {
        case .minted:
            return nil
        case .signedOut:
            return String(localized: "Bankr didn't accept the sign-in. Sign in again.")
        case .tooWide:
            return String(localized: "Bankr made a key that can do more than read, so it wasn't saved. Remove it on bankr.bot.")
        case .failed(let status):
            return status == 0
                ? String(localized: "Couldn't reach Bankr to make a key.")
                : String(localized: "Bankr couldn't make a key (\(status)).")
        }
    }

    /// A link the page wants to hand to ANOTHER app — Farcaster's sign-in
    /// approves in its own app, and a web view never leaves itself. Any
    /// non-web scheme, and Farcaster's own sign-in hosts.
    static func isAppHandoff(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "http" && scheme != "https" { return scheme != "about" && scheme != "blob" && scheme != "data" }
        let host = url.host?.lowercased() ?? ""
        return ["farcaster.xyz", "warpcast.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
