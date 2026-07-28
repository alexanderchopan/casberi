import Foundation
import AuthenticationServices
import CryptoKit
import SwiftData

/// The Slack bridge (2026-07-28) — mentions of you, landed the same shape a
/// Farcaster/Bluesky mention already is (`.chat`, full text in `postText`,
/// `socialContext = "mention"`). OAuth with PKCE, run entirely by this
/// iPhone — no server holds a secret, because Slack made PKCE generally
/// available (secretless OAuth for public/native clients) in March 2026.
/// That's what un-parks this bridge: `docs/prd.md`'s 2026-07-08 note that
/// Slack "needs the OAuth-secret server" predates PKCE-GA and is stale.
///
/// Scoped to ONE user token scope, `search:read` — Casberi can look up
/// mentions and nothing else. It never touches `conversations.history`/
/// `conversations.replies` — the endpoints Slack throttled hard in 2025 (1
/// req/min) for apps not approved for the Slack Marketplace — `search.messages`
/// sits at a different, unaffected tier (legacy but alive, user-token only).
/// "Saved Items" (the original MVP idea) was ruled out before writing any of
/// this: Slack's replacement for Stars ("Later") has no API at all.
///
/// GATED until a client ID exists: create a (free) app at api.slack.com/apps,
/// add user scope `search:read`, redirect URL `casberi://slack-auth`, enable
/// PKCE in the app's settings (self-service since March 2026 — no more
/// contacting Slack support), then paste the Client ID below. A Slack Client
/// ID is not a secret — PKCE needs nothing else.
enum SlackAuth {

    /// From api.slack.com/apps → Basic Information — empty means the bridge is off.
    static let clientID = "11698925366580.11723575765264"
    static let redirectURI = "casberi://slack-auth"
    static var ready: Bool { !clientID.isEmpty }

    private static let tokenKey = "token.slack"          // user access token
    private static let teamNameKey = "slack.team.name"
    private static let userIDKey = "slack.user.id"

    static var connected: Bool { TokenVault.get(tokenKey) != nil }

    /// The connected workspace's name — Slack's OAuth response hands this
    /// over honestly (unlike Spotify's identity-less PKCE token), so the
    /// screen can show "Connected to <workspace>" truthfully, the same way
    /// Dropbox's folder path is its identity line.
    static var teamName: String? {
        UserDefaults.standard.string(forKey: teamNameKey)
    }

    /// The signed-in user's own Slack id — what turns a search into
    /// "mentions of ME" (`search.messages?query=<@id>`), read straight off
    /// the OAuth response with no extra scope needed.
    static var userID: String? {
        UserDefaults.standard.string(forKey: userIDKey)
    }

    static func disconnect() {
        TokenVault.delete(tokenKey)
        UserDefaults.standard.removeObject(forKey: teamNameKey)
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }

    // MARK: - Sign in (PKCE: verifier stays here, challenge goes out)

    @MainActor
    static func signIn() async -> Bool {
        guard ready else { return false }
        let verifier = randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64URLEncoded()

        var auth = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
        auth.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            // A USER scope, not a bot scope — no app is being installed to
            // post or watch anything, only to search on the signed-in
            // person's own behalf.
            URLQueryItem(name: "user_scope", value: "search:read"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        guard let url = auth.url,
              let callback = await presentAuth(url: url) else { return false }

        guard let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else { return false }

        return await exchange(code: code, verifier: verifier)
    }

    /// Slack's default user tokens don't expire (token rotation is an
    /// opt-in app setting Slack ships off) — so unlike Dropbox/Spotify,
    /// there's no refresh-token cycle to run here. If token rotation is ever
    /// turned on for this app, this is where a refresh arm would go.
    private static func exchange(code: String, verifier: String) async -> Bool {
        let form: [String: String] = [
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]
        var request = URLRequest(url: URL(string: "https://slack.com/api/oauth.v2.access")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["ok"] as? Bool) == true,
              // A user-scope-only request carries the token under
              // `authed_user`, not the top-level `access_token` (that slot
              // is for a bot install, which never happens here).
              let authedUser = json["authed_user"] as? [String: Any],
              let token = authedUser["access_token"] as? String,
              let userID = authedUser["id"] as? String
        else { return false }
        TokenVault.set(token, for: tokenKey)
        UserDefaults.standard.set(userID, forKey: userIDKey)
        if let team = json["team"] as? [String: Any], let name = team["name"] as? String {
            UserDefaults.standard.set(name, forKey: teamNameKey)
        }
        return true
    }

    @MainActor
    private static func presentAuth(url: URL) async -> URL? {
        await withCheckedContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: "casberi"
            ) { callback, _ in
                cont.resume(returning: callback)
            }
            session.presentationContextProvider = SlackAuthPresenter.shared
            if !session.start() { cont.resume(returning: nil) }
        }
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

private final class SlackAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SlackAuthPresenter()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

private extension Data {
    /// Base64url, the OAuth flavor — no padding, URL-safe alphabet.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Ingest

enum SlackIngest {

    @MainActor private static var running = false

    /// Mentions of you, newest 20, through `search.messages` (legacy but
    /// alive, user-token scoped, a Tier the 2025 non-Marketplace throttle
    /// never touched). Landed the same shape a Farcaster/Bluesky mention is.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard SlackAuth.connected, !running else {
            return SlackAuth.connected ? 0 : nil
        }
        running = true
        defer { running = false }

        guard let token = TokenVault.get("token.slack"),
              let userID = SlackAuth.userID else { return nil }

        var comps = URLComponents(string: "https://slack.com/api/search.messages")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: "<@\(userID)>"),
            URLQueryItem(name: "sort", value: "timestamp"),
            URLQueryItem(name: "sort_dir", value: "desc"),
            URLQueryItem(name: "count", value: "20"),
        ]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url, auth: "Bearer \(token)") as? [String: Any],
              (root["ok"] as? Bool) == true,
              let messages = root["messages"] as? [String: Any],
              let matches = messages["matches"] as? [[String: Any]] else { return nil }

        let existing = IngestSupport.existingSourceRefs(context, source: "Slack")
        var added = 0

        for match in matches {
            guard let channel = match["channel"] as? [String: Any],
                  let channelID = channel["id"] as? String,
                  let ts = match["ts"] as? String,
                  let text = match["text"] as? String, !text.isEmpty else { continue }
            // ts is unique per message within a workspace — channel+ts avoids
            // any cross-channel collision.
            let ref = "slack:\(channelID):\(ts)"
            guard !existing.contains(ref) else { continue }

            let permalink = (match["permalink"] as? String) ?? ""
            let username = (match["username"] as? String) ?? "Slack"
            let when = Double(ts).map { Date(timeIntervalSince1970: $0) } ?? .now

            let thing = Thing(
                kind: .chat,
                title: IngestSupport.titleLine(text),
                content: permalink,
                source: "Slack",
                capturedAt: when,
                sourceRef: ref
            )
            thing.postText = text
            thing.authorHandle = username
            thing.socialContext = "mention"
            thing.channelName = channel["name"] as? String
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1

            // A mention is the highest-signal event this bridge has, and
            // used to land silently (same delight bus a Farcaster/Bluesky
            // mention already rides). NEWS ONLY: a mention older than a day
            // heals in quiet — connecting an account shouldn't rain 40
            // toasts for months of old @s.
            if when.timeIntervalSinceNow > -86400 {
                let channelLabel = (channel["name"] as? String).map { "#\($0)" } ?? "Slack"
                SourceMoments.shared.fire(
                    String(localized: "@\(username) mentioned you in \(channelLabel)"),
                    source: "Slack")
            }
        }
        if added > 0 { context.saveHonestly() }
        return added
    }
}
