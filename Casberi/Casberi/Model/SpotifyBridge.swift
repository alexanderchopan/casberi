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
    static let clientID = "2f82c5e3bf3a4c10aa39ecb9f5cc0825"
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

    /// Why a connect attempt ended the way it did, so the screen can say the
    /// true thing (audit 2026-07-31 — it said "Couldn't connect" for all of
    /// these, which reads as a breakage even when the person simply closed the
    /// sheet). The shape `StripeFetch.Outcome` set: one case per outcome that
    /// is actually distinguishable on the wire, and no more.
    enum SignIn {
        case ok
        /// The person dismissed Spotify's sheet — `canceledLogin`. Not a
        /// failure: nothing was attempted, so nothing went wrong.
        case cancelled
        /// The callback came back carrying an OAuth `error` instead of a code
        /// — Spotify asked and the answer was no.
        case declined
        /// The sign-in page never opened: the session refused to start, or the
        /// bridge has no client id to open it with.
        case cantOpen
        /// The token exchange never reached Spotify at all.
        case unreachable
        /// Spotify answered the exchange and refused it — a non-200, or an
        /// envelope with no token in it.
        case refused
    }

    @MainActor
    static func signIn() async -> SignIn {
        guard ready else { return .cantOpen }
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
        guard let url = auth.url else { return .cantOpen }
        let callback: URL
        switch await presentAuth(url: url) {
        case .callback(let landed): callback = landed
        case .cancelled: return .cancelled
        case .cantOpen: return .cantOpen
        }

        guard let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return .refused }
        // Saying no on Spotify's page still redirects here — with `error`
        // where the code would be. Only `access_denied` is that decision;
        // every other OAuth error is Spotify refusing the request, which is a
        // different sentence on the screen.
        let refusal = items.first(where: { $0.name == "error" })?.value
        if refusal == "access_denied" { return .declined }
        guard refusal == nil,
              let code = items.first(where: { $0.name == "code" })?.value
        else { return .refused }

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
        ]) == .ok
        return ok ? TokenVault.get(tokenKey) : nil
    }

    /// The token exchange, reporting WHICH way it failed — a request that
    /// never landed and one Spotify turned down are different sentences on the
    /// setup screen. The refresh path above only cares whether it worked.
    private static func exchange(form: [String: String]) async -> SignIn {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request)
        else { return .unreachable }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return .refused }
        TokenVault.set(access, for: tokenKey)
        if let refresh = json["refresh_token"] as? String {
            TokenVault.set(refresh, for: refreshKey)
        }
        let lifetime = (json["expires_in"] as? Double) ?? 3600
        UserDefaults.standard.set(Date.now.timeIntervalSince1970 + lifetime,
                                  forKey: expiryKey)
        return .ok
    }

    /// What the sign-in sheet came back with — the callback, or why there
    /// isn't one. A dismissal is the one the screen most needs told apart.
    private enum Presented {
        case callback(URL)
        case cancelled
        case cantOpen
    }

    @MainActor
    private static func presentAuth(url: URL) async -> Presented {
        await withCheckedContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: "casberi"
            ) { callback, error in
                if let callback {
                    cont.resume(returning: .callback(callback))
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    cont.resume(returning: .cancelled)
                } else {
                    cont.resume(returning: .cantOpen)
                }
            }
            session.presentationContextProvider = AuthPresenter.shared
            if !session.start() { cont.resume(returning: .cantOpen) }
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

    /// Liked songs, newest 30 — "Song — Artist" things linking to Spotify,
    /// each wearing its album's cover and the album it came off.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard SpotifyAuth.connected, !running else {
            return SpotifyAuth.connected ? 0 : nil
        }
        running = true
        defer { running = false }

        guard let token = await SpotifyAuth.accessToken() else { return nil }
        guard let root = await IngestSupport.getJSON(
            "https://api.spotify.com/v1/me/tracks?limit=30",
            auth: "Bearer \(token)") as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }

        let existing = IngestSupport.existingSourceRefs(context, source: "Spotify")
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
            let when = IngestSupport.isoDate(item["added_at"])
            let album = (track["album"] as? [String: Any]) ?? [:]

            let thing = Thing(
                kind: .link,
                title: artists.isEmpty ? name : "\(name) — \(artists)",
                content: link,
                source: "Spotify",
                capturedAt: when ?? .now,
                // What this row IS, in the vocabulary the retriever already
                // has: `Retriever.facetFilter` reads "Liked" as a facet behind
                // a named room, so "what I liked on Spotify" narrows to these
                // rather than falling back to a whole-corpus keyword scan. It
                // is also simply true — this endpoint is `/me/tracks`, the
                // Liked Songs library and nothing else. No "Music" tag beside
                // it: the source chip and the type tag already say that, and a
                // literal on every row of a source is noise (ShapedRows' own
                // reason for dropping bridge tags from the trailing slot).
                tags: ["Liked"],
                sourceRef: ref
            )
            // The join key MediaMoments' artist crossing reads (a podcast or
            // YouTube video mentioning an artist you've liked here) — no UI
            // reads this for Spotify (ShapedRows' trailing slot has no
            // "Spotify" case), it's purely a backend field.
            if !artists.isEmpty { thing.authorHandle = artists }
            // The album cover. `MediaShape.art(for:)` has declared Spotify a
            // `.cover` source since prd §219 and `MusicRow` has led with
            // `previewImageURL` at 44pt since 2026-07-11 — but nothing ever
            // filled the slot, so every Spotify row drew the bridge glyph
            // while its sibling Apple Music row (same room shape, same field)
            // wore real art. The images are in every `/me/tracks` response;
            // this bridge was simply throwing them away.
            thing.previewImageURL = coverURL(album)
            // The album a liked track came off — the one fact this payload
            // carries that the title doesn't. `summary`, not `enrichedText`:
            // Spotify authored the album name and handed it over in its own
            // payload, which is the exact line the 2026-07-22 field split
            // draws (enrichedText is text WE scraped, and is retrieval-only).
            thing.summary = albumLine(album, track: name)
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    // MARK: - Album facts (both read off `track.album`, already in hand)

    /// The album cover as a plain https URL. Spotify serves three sizes per
    /// album (640 / 300 / 64 square); 300 is what `AppleMusicIngest.artURL`
    /// picks for the same job and for the same reasons — crisp at
    /// `MusicRow`'s 44pt thumb on a 3× screen, small enough that
    /// `RemoteThumb`'s downsample stays cheap.
    ///
    /// Nearest-to-300 rather than "the middle one": the sizes are a Spotify
    /// convention, not a contract, and an album with one image would make an
    /// index-based pick silently wrong. A payload carrying no widths at all
    /// scores every entry equally and keeps the first, which is Spotify's
    /// largest — a real cover, never an invented size.
    private static func coverURL(_ album: [String: Any]) -> String? {
        let sized = ((album["images"] as? [[String: Any]]) ?? [])
            .compactMap { image -> (width: Int, url: String)? in
                guard let url = IngestSupport.imageURL(image["url"] as? String)
                else { return nil }
                return ((image["width"] as? Int) ?? 0, url)
            }
        return sized.min { abs($0.width - 300) < abs($1.width - 300) }?.url
    }

    /// "From Blonde (2016)" — display copy under the track in the thing sheet.
    ///
    /// Nil for a single, where Spotify wraps the one track in an album of the
    /// same name and the line would only repeat the title back. The year is
    /// the leading four digits of `release_date`, which the API serves as
    /// `2016-08-20`, `2016-08` or `2016` depending on
    /// `release_date_precision` — the year is present and exact in all three,
    /// and nothing finer is claimed. A date that doesn't start with four
    /// digits yields no year rather than a guessed one.
    private static func albumLine(_ album: [String: Any], track: String) -> String? {
        guard let name = (album["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              name.caseInsensitiveCompare(track) != .orderedSame else { return nil }
        let year = (album["release_date"] as? String).flatMap { raw -> String? in
            let digits = raw.prefix(4)
            return digits.count == 4 && digits.allSatisfy(\.isNumber)
                ? String(digits) : nil
        }
        guard let year else { return String(localized: "From \(name)") }
        return String(localized: "From \(name) (\(year))")
    }
}
