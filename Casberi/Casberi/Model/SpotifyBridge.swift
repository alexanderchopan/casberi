import Foundation
import AuthenticationServices
import CryptoKit
import SwiftData

/// The Spotify bridge (2026-07-07) — OAuth with PKCE, run entirely by this
/// iPhone: no server holds a secret, because PKCE was designed for exactly
/// this. Liked songs land as link things.
///
/// GATED until a client ID exists: create a (free) app at
/// developer.spotify.com/dashboard, add redirect URI `casberi://spotify-auth`,
/// paste the client ID below, and flip the catalog offer to
/// `connectable: true, needsSetup: true`. Until then the offer stays a
/// Soon card and none of this runs — no dead controls.
enum SpotifyAuth {

    /// From developer.spotify.com/dashboard — empty means the bridge is off.
    static let clientID = ""
    static let redirectURI = "casberi://spotify-auth"
    static var ready: Bool { !clientID.isEmpty }

    private static let tokenKey = "token.spotify"        // access token
    private static let refreshKey = "token.spotify.refresh"
    private static let expiryKey = "spotify.token.expiry"

    static var connected: Bool { TokenVault.get(refreshKey) != nil }

    static func disconnect() {
        TokenVault.delete(tokenKey)
        TokenVault.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }

    // MARK: - Sign in (PKCE: verifier stays here, challenge goes out)

    @MainActor
    static func signIn() async -> Bool {
        guard ready else { return false }
        let verifier = randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64URLEncoded()

        var auth = URLComponents(string: "https://accounts.spotify.com/authorize")!
        auth.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user-library-read"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        guard let url = auth.url,
              let callback = await presentAuth(url: url) else { return false }

        guard let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else { return false }

        return await exchange(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    /// A live access token — refreshed through the stored refresh token when
    /// the current one has expired.
    static func accessToken() async -> String? {
        let expiry = UserDefaults.standard.double(forKey: expiryKey)
        if let token = TokenVault.get(tokenKey),
           Date.now.timeIntervalSince1970 < expiry - 60 {
            return token
        }
        guard let refresh = TokenVault.get(refreshKey) else { return nil }
        let ok = await exchange(form: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ])
        return ok ? TokenVault.get(tokenKey) : nil
    }

    private static func exchange(form: [String: String]) async -> Bool {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return false }
        TokenVault.set(access, for: tokenKey)
        if let refresh = json["refresh_token"] as? String {
            TokenVault.set(refresh, for: refreshKey)
        }
        let lifetime = (json["expires_in"] as? Double) ?? 3600
        UserDefaults.standard.set(Date.now.timeIntervalSince1970 + lifetime,
                                  forKey: expiryKey)
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
            session.presentationContextProvider = AuthPresenter.shared
            if !session.start() { cont.resume(returning: nil) }
        }
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

private final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresenter()
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

enum SpotifyIngest {

    @MainActor private static var running = false

    /// Liked songs, newest 30 — "Song — Artist" things linking to Spotify.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard SpotifyAuth.connected, !running else {
            return SpotifyAuth.connected ? 0 : nil
        }
        running = true
        defer { running = false }

        guard let token = await SpotifyAuth.accessToken() else { return nil }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks?limit=30")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }

        let existing = Set(((try? context.fetch(FetchDescriptor<Thing>())) ?? [])
            .compactMap(\.sourceRef))
        let iso = ISO8601DateFormatter()
        var added = 0

        for item in items {
            guard let track = item["track"] as? [String: Any],
                  let id = track["id"] as? String,
                  let name = track["name"] as? String else { continue }
            let ref = "spotify:\(id)"
            guard !existing.contains(ref) else { continue }
            let artists = ((track["artists"] as? [[String: Any]]) ?? [])
                .compactMap { $0["name"] as? String }.joined(separator: ", ")
            let link = ((track["external_urls"] as? [String: Any])?["spotify"] as? String) ?? ""
            let when = (item["added_at"] as? String).flatMap { iso.date(from: $0) }

            let thing = Thing(
                kind: .link,
                title: artists.isEmpty ? name : "\(name) — \(artists)",
                content: link,
                source: "Spotify",
                capturedAt: when ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }
}
