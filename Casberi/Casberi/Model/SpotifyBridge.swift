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

    /// Seconds until the cached access token stops being trusted — negative
    /// once the next read will spend the refresh token instead. For
    /// `-spotifyProbe` only: the cache is trusted on a CLOCK, so a phone whose
    /// clock is wrong looks exactly like one whose clock is right, and this is
    /// the only place that shows it. An accessor rather than the probe reading
    /// the defaults key itself, so the key stays spelled once.
    static var secondsUntilTokenRefresh: Int {
        Int(UserDefaults.standard.double(forKey: expiryKey) - Date.now.timeIntervalSince1970)
    }

    static func disconnect() {
        TokenVault.delete(tokenKey)
        TokenVault.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }

#if DEBUG
    /// Plant a refresh token Spotify is certain to refuse, for
    /// `-spotifySeedDeadGrant`. It exists because the branch this file was
    /// written on turns on ONE outcome — a sign-in Spotify has retired — and
    /// that outcome cannot otherwise be reached on demand: it needs a real
    /// account whose grant has been revoked, which is not something a test can
    /// arrange and not something anybody should wait for. Seeding it walks the
    /// whole path against the LIVE token endpoint (measured 2026-09-02: a
    /// refresh token Spotify does not know answers `400 invalid_grant`, which
    /// is exactly the code `refreshToken` clears on), so the proof is of the
    /// real wire and not of a stub.
    ///
    /// It writes into the same Keychain items a real sign-in uses, which is
    /// the point — `connected` must read true, or the screen shows Connect and
    /// the state under test never exists. The expiry is stamped in the PAST so
    /// the very next read spends the refresh token rather than trusting a
    /// cached access token that was never real. Nothing here is a credential:
    /// the value is a literal that cannot authenticate anything.
    static func seedDeadGrant() {
        TokenVault.set("casberi-dead-grant-probe", for: refreshKey)
        TokenVault.set("casberi-dead-access-probe", for: tokenKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970 - 3600, forKey: expiryKey)
    }
#endif

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

        switch await exchange(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]) {
        case .ok: return .ok
        case .unreachable: return .unreachable
        case .refused: return .refused
        }
    }

    /// What asking for a live access token came back with.
    ///
    /// It used to be `String?`, which collapsed three outcomes the caller has
    /// to tell apart: a sign-in Spotify has RETIRED (reconnect), a network
    /// that never answered (wait), and never having connected at all. All
    /// three surfaced as one sentence on the setup screen — the same
    /// undiagnosable shape `getJSONBody` was added for (prd §530).
    enum Token {
        case ok(String)
        /// The refresh grant came back `invalid_grant` — the stored sign-in
        /// is dead and will never work again, so the credentials are cleared
        /// and the screen honestly reads disconnected. See `refreshToken`.
        case expired
        /// The exchange never reached Spotify, or Spotify answered with
        /// something transient. The sign-in is kept; try again later.
        case unreachable
        /// Nothing stored — this bridge was never connected on this device.
        case noCredential
    }

    /// A live access token — refreshed through the stored refresh token when
    /// the current one has expired.
    ///
    /// `forceRefresh` skips the cached token and mints a new one. It exists
    /// for the 401 retry in `SpotifyIngest`: the cache is trusted on a CLOCK
    /// (`expires_in` written at exchange time), and a token Spotify has since
    /// stopped honouring — the authorization revoked from spotify.com, a
    /// server-side invalidation, a phone whose clock is behind — still looks
    /// live by that clock. Without this the bridge answers "couldn't read
    /// your liked songs" on every open until the recorded hour runs out, with
    /// a perfectly good refresh token sitting unused in the Keychain.
    static func token(forceRefresh: Bool = false) async -> Token {
        let expiry = UserDefaults.standard.double(forKey: expiryKey)
        if !forceRefresh, let token = TokenVault.get(tokenKey),
           Date.now.timeIntervalSince1970 < expiry - 60 {
            return .ok(token)
        }
        return await refreshToken()
    }

    /// Spend the stored refresh token on a new access token.
    ///
    /// **A refused grant CLEARS the credentials, and that is the fix for the
    /// green-check-over-a-dead-connection screen.** `connected` is "is there
    /// a refresh token in the Keychain", and the iOS Keychain OUTLIVES the
    /// app — deleting Casberi and reinstalling it leaves the old item behind,
    /// so the setup screen said "Connected — liked songs land in your feed."
    /// over a sign-in the person never made in this install and Spotify no
    /// longer honours. Nothing healed it: the read failed, the token stayed,
    /// and the only way out was noticing Disconnect.
    ///
    /// Only `invalid_grant` clears. RFC 6749 §5.2 reserves that code for a
    /// grant that is expired, revoked or was never ours, which is precisely
    /// "this will never work again" — a 5xx, a 429 or a dead network must
    /// never cost somebody their connection, so those keep it and report
    /// `.unreachable`. An answer this build can't classify keeps it too.
    private static func refreshToken() async -> Token {
        guard let refresh = TokenVault.get(refreshKey) else { return .noCredential }
        switch await exchange(form: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ]) {
        case .ok:
            guard let token = TokenVault.get(tokenKey) else { return .unreachable }
            return .ok(token)
        case .unreachable:
            return .unreachable
        case .refused(_, let error):
            guard error == "invalid_grant" else { return .unreachable }
            disconnect()
            // The seat outlives the credential on purpose — the rows stay, the
            // room door stays, and the catalog says "needs reconnecting"
            // rather than silently forgetting Spotify was ever set up. Without
            // this the tile would keep its green proof line over a sign-in
            // this function just deleted, which is the fake status §83 bans.
            BridgeHealth.markAuthRefused("Spotify")
            return .expired
        }
    }

#if DEBUG
    /// Ask two endpoints with the SAME live token and report both statuses,
    /// for `-spotifyProbe`. It exists because a 403 out of `/me/tracks` has
    /// two causes that are one sentence apart and only one is ours to fix:
    /// a scope the stored grant predates (Spotify answers
    /// `{"error":{"message":"Insufficient client scope"}}`) versus an app
    /// still in Development Mode whose allowlist this account is not on
    /// (Spotify answers a BARE 403, no body at all). `/me` needs no scope, so
    /// the pair separates them: 403 on both is the account being shut out of
    /// the whole app, 200 then 403 is the scope.
    ///
    /// The token is used and never logged, here or by the caller.
    static func diagnose() async -> String {
        let token: String
        switch await SpotifyAuth.token() {
        case .ok(let live):  token = live
        case .expired:       return "no live token — the sign-in is expired"
        case .unreachable:   return "no live token — could not reach Spotify"
        case .noCredential:  return "no live token — nothing stored"
        }
        func ask(_ url: String) async -> String {
            let answer = await IngestSupport.getJSONBody(url, auth: "Bearer \(token)")
            let said = ((answer.json as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
            return "\(answer.status) \(said ?? "(no body)")"
        }
        let me = await ask("https://api.spotify.com/v1/me")
        let tracks = await ask("https://api.spotify.com/v1/me/tracks?limit=1")
        return "me=[\(me)] tracks=[\(tracks)]"
    }
#endif

    /// What the token endpoint said. Finer than `SignIn` on purpose: the
    /// refresh path needs the OAuth error CODE to tell a dead grant from a
    /// bad afternoon (see `refreshToken`), and the sign-in path throws that
    /// detail away one line later.
    private enum Exchange {
        case ok
        /// No response at all — offline, DNS, a reset connection.
        case unreachable
        /// Spotify answered and turned it down. `error` is the OAuth code out
        /// of the body (`invalid_grant`, `invalid_client`, …) where there was
        /// one; a 200 carrying no `access_token` lands here too, with nil.
        case refused(status: Int, error: String?)
    }

    /// The token exchange, reporting WHICH way it failed — a request that
    /// never landed and one Spotify turned down are different sentences on the
    /// setup screen.
    ///
    /// The body is read on a NON-200 as well, which every other helper in this
    /// app deliberately doesn't do (`IngestSupport.getJSONBody`'s own reason,
    /// prd §530): for OAuth the refusal's `error` field is the entire
    /// diagnosis, and dropping it is what made a retired sign-in and an
    /// unreachable host the same sentence.
    private static func exchange(form: [String: String]) async -> Exchange {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .unreachable }
        // The sign-in host reached the health book for the first time here.
        // Every other read in the app rides `IngestSupport.send`, which folds
        // its status in for free — this one holds its own `URLSession` (it is
        // form-encoded, not JSON), so a refused token exchange was invisible
        // to `BridgeHealth` and the seat read healthy while it was shut out.
        BridgeHealth.record(host: request.url?.host, status: http.statusCode, named: nil)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let oauthError = json?["error"] as? String
        guard http.statusCode == 200, let json,
              let access = json["access_token"] as? String
        else { return .refused(status: http.statusCode, error: oauthError) }
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

    /// How a read of the liked-songs library ended.
    ///
    /// It used to be `Int?`, and the nil carried SIX outcomes the setup screen
    /// printed one sentence for: not connected, a retired sign-in, a network
    /// that never answered, a rate limit, a refusal from Spotify, and a body
    /// this build couldn't parse. "Couldn't read your liked songs — try again
    /// in a moment" is true of exactly one of those (the rate limit) and is
    /// advice that can never work for three of them. Each case here has a
    /// different next move, which is the bar `SpotifyAuth.SignIn` already set
    /// on the other half of this file.
    enum Read {
        /// The read worked. 0 is a real answer — you have liked nothing new.
        case landed(Int)
        /// Nothing stored to read with.
        case notConnected
        /// The sign-in is retired and has been cleared; connect again.
        case signInExpired
        /// Spotify is rate-limiting us (429). The one case where trying again
        /// in a moment is the right advice.
        case busy
        /// Spotify answered and said no — a scope the stored token predates,
        /// an account restriction, or an app still in Development Mode whose
        /// allowlist this account is not on. `message` is Spotify's own words
        /// out of the error body, carried for the reason `invalid_grant` is
        /// carried on the auth half: at this status the refusal's own text is
        /// the entire diagnosis, and the three causes above are one sentence
        /// apart. Nothing DISPLAYS it — the screen still says the one true
        /// thing for the whole status — it exists so `-spotifyProbe` can name
        /// which of them happened in a single launch.
        case refused(status: Int, message: String?)
        /// Nothing answered at all.
        case unreachable
        /// A 200 whose body this build could not read — the endpoint's shape
        /// moved. Not a thing the person can act on, and it must not be
        /// reported as one.
        case unreadable
        /// Another pass is mid-read. NOT `.landed(0)`, which is what this
        /// returned while the setup screen was the only caller: the sweep is
        /// a second caller now (`BridgeRefresh`), so opening the screen just
        /// after a foreground would have printed "Up to date" — a claim about
        /// a read this call never made.
        case alreadyRunning
    }

    /// Liked songs, newest 30 — "Song — Artist" things linking to Spotify,
    /// each wearing its album's cover and the album it came off.
    @MainActor
    static func refresh(context: ModelContext) async -> Read {
        guard SpotifyAuth.connected else { return .notConnected }
        guard !running else { return .alreadyRunning }
        running = true
        defer { running = false }

        let token: String
        switch await SpotifyAuth.token() {
        case .ok(let live):    token = live
        case .expired:         return .signInExpired
        case .unreachable:     return .unreachable
        case .noCredential:    return .notConnected
        }

        let url = "https://api.spotify.com/v1/me/tracks?limit=30"
        var answer = await IngestSupport.getJSONBody(url, auth: "Bearer \(token)")
        // A 401 here means the token Spotify handed us has stopped being
        // honoured EARLY — before the `expires_in` we cached it against. One
        // forced refresh, once: the stored refresh token is a different
        // credential and is very often still good, and without this retry the
        // bridge stays dead until that cached hour elapses.
        if answer.status == 401 {
            switch await SpotifyAuth.token(forceRefresh: true) {
            case .ok(let minted):
                answer = await IngestSupport.getJSONBody(url, auth: "Bearer \(minted)")
            case .expired:     return .signInExpired
            case .unreachable: return .unreachable
            case .noCredential: return .notConnected
            }
        }
        switch answer.status {
        case 200:  break
        case 0:    return .unreachable
        case 429:  return .busy
        default:
            // Spotify's Web API wraps its refusals as
            // `{"error": {"status": 403, "message": "..."}}` — a different
            // shape from the token endpoint's flat OAuth `error`, which is why
            // this is read here and not in `exchange`.
            let body = (answer.json as? [String: Any])?["error"] as? [String: Any]
            return .refused(status: answer.status, message: body?["message"] as? String)
        }
        guard let root = answer.json as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return .unreadable }

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
        return .landed(added)
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
