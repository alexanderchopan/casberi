import Foundation
import AuthenticationServices
import SwiftData

/// The Reddit bridge (2026-07-08) — OAuth run entirely by this iPhone. Reddit's
/// "installed app" type has NO client secret, so no server is needed; the token
/// exchange authenticates with the client id alone. Your saved posts land as
/// link things. Read-only.
///
/// GATED until a client id exists: create a free app at
/// reddit.com/prefs/apps (type: "installed app", redirect
/// `https://casberi.app/reddit-auth` — their form rejects custom schemes;
/// that page forwards the code to `casberi://reddit-auth`, which the auth
/// session catches), paste the client id below, and flip the catalog offer
/// to connectable. Until then it stays a Soon card — no dead controls.
enum RedditAuth {

    /// From reddit.com/prefs/apps — empty means the bridge is off.
    static let clientID = ""
    /// Must match the registered redirect exactly (authorize + token exchange).
    static let redirectURI = "https://casberi.app/reddit-auth"
    static let scope = "identity history save read"
    static let userAgent = "ios:com.casberi.app:v0.1 (personal use)"
    static var ready: Bool { !clientID.isEmpty }

    private static let tokenKey = "token.reddit"
    private static let refreshKey = "token.reddit.refresh"
    private static let expiryKey = "reddit.token.expiry"
    private static let nameKey = "reddit.username"

    static var connected: Bool { TokenVault.get(refreshKey) != nil }
    static var username: String { UserDefaults.standard.string(forKey: nameKey) ?? "" }

    static func disconnect() {
        TokenVault.delete(tokenKey); TokenVault.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    @MainActor
    static func signIn() async -> Bool {
        guard ready else { return false }
        var auth = URLComponents(string: "https://www.reddit.com/api/v1/authorize")!
        auth.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "state", value: UUID().uuidString),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "duration", value: "permanent"),
            .init(name: "scope", value: scope),
        ]
        guard let url = auth.url,
              let callback = await RedditAuthPresenter.present(url),
              let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else { return false }

        let ok = await exchange(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
        ])
        if ok { await fetchUsername() }
        return ok
    }

    static func accessToken() async -> String? {
        let expiry = UserDefaults.standard.double(forKey: expiryKey)
        if let token = TokenVault.get(tokenKey), Date.now.timeIntervalSince1970 < expiry - 60 {
            return token
        }
        guard let refresh = TokenVault.get(refreshKey) else { return nil }
        let ok = await exchange(form: ["grant_type": "refresh_token", "refresh_token": refresh])
        return ok ? TokenVault.get(tokenKey) : nil
    }

    /// Installed-app token exchange: HTTP Basic auth with the client id and an
    /// empty password — no secret.
    private static func exchange(form: [String: String]) async -> Bool {
        var request = URLRequest(url: URL(string: "https://www.reddit.com/api/v1/access_token")!)
        request.httpMethod = "POST"
        let basic = Data("\(clientID):".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return false }
        TokenVault.set(access, for: tokenKey)
        if let refresh = json["refresh_token"] as? String { TokenVault.set(refresh, for: refreshKey) }
        let lifetime = (json["expires_in"] as? Double) ?? 3600
        UserDefaults.standard.set(Date.now.timeIntervalSince1970 + lifetime, forKey: expiryKey)
        return true
    }

    private static func fetchUsername() async {
        guard let token = TokenVault.get(tokenKey) else { return }
        if let me = await get("https://oauth.reddit.com/api/v1/me", token: token) as? [String: Any],
           let name = me["name"] as? String {
            UserDefaults.standard.set(name, forKey: nameKey)
        }
    }

    static func get(_ url: String, token: String) async -> Any? {
        guard let u = URL(string: url) else { return nil }
        var request = URLRequest(url: u)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

private enum RedditAuthPresenter {
    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
    private static let presenter = Presenter()

    @MainActor
    static func present(_ url: URL) async -> URL? {
        await withCheckedContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "casberi") { cb, _ in
                cont.resume(returning: cb)
            }
            session.presentationContextProvider = presenter
            if !session.start() { cont.resume(returning: nil) }
        }
    }
}

enum RedditIngest {

    @MainActor private static var running = false

    /// Your saved posts (newest 25) as link things.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard RedditAuth.connected, !running else { return RedditAuth.connected ? 0 : nil }
        running = true
        defer { running = false }

        guard let token = await RedditAuth.accessToken() else { return nil }
        let name = RedditAuth.username
        guard !name.isEmpty,
              let root = await RedditAuth.get(
                "https://oauth.reddit.com/user/\(name)/saved?limit=25", token: token) as? [String: Any],
              let listing = (root["data"] as? [String: Any])?["children"] as? [[String: Any]]
        else { return nil }

        let existing = IngestSupport.existingSourceRefs(context)
        let artless = IngestSupport.artlessThings(context, source: "Reddit")
        var added = 0
        var backfilled = 0
        for child in listing {
            guard let d = child["data"] as? [String: Any],
                  let id = d["name"] as? String else { continue }   // e.g. "t3_abc"
            let ref = "reddit:\(id)"
            let image = postImage(d)
            if existing.contains(ref) {
                if let image, let thing = artless[ref] {
                    thing.previewImageURL = image
                    backfilled += 1
                }
                continue
            }
            // A saved post (t3) has a title; a saved comment (t1) has link_title.
            let title = (d["title"] as? String) ?? (d["link_title"] as? String) ?? "Saved on Reddit"
            let permalink = (d["permalink"] as? String).map { "https://reddit.com\($0)" } ?? ""
            let created = (d["created_utc"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let thing = Thing(
                kind: .link,
                title: IngestSupport.titleLine(title),
                content: permalink,
                source: "Reddit",
                capturedAt: created ?? .now,
                sourceRef: ref
            )
            if let image { thing.previewImageURL = image }
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || backfilled > 0 { try? context.save() }
        return added
    }

    /// A saved post's image: the preview source (Reddit HTML-escapes the
    /// URL's ampersands), falling back to the listing thumbnail — which is
    /// a keyword ("self", "default", "nsfw"…) for posts with no image, so
    /// only a real URL counts. Text posts stay on the snoo glyph.
    private static func postImage(_ d: [String: Any]) -> String? {
        if let source = ((((d["preview"] as? [String: Any])?["images"]
                            as? [[String: Any]])?.first?["source"]
                            as? [String: Any])?["url"] as? String) {
            return source.replacingOccurrences(of: "&amp;", with: "&")
        }
        if let thumb = d["thumbnail"] as? String, thumb.hasPrefix("http") {
            return thumb
        }
        return nil
    }
}
