import Foundation
import CryptoKit
import SwiftData

/// The Spotify bridge, second life (2026-09-11). The first seat (2026-07-07,
/// removed 2026-09-02 — prd/§ Spotify-comes-out) ran OAuth PKCE against a
/// registered developer app, and Spotify's 2026 development-mode clampdown made
/// that path 403 for everyone but five hand-listed accounts. This seat DOES NOT
/// USE THE DEVELOPER API AT ALL: it signs in as the person through Spotify's own
/// web player (the same thing `open.spotify.com` runs), harvests that session's
/// cookie and bearer token, and reads the web player's own endpoints. No client
/// id, no developer standing, no per-user allowlist — the exact gate that killed
/// the first seat is never touched. Same technique as, and ported from,
/// github.com/stephancill/stupid-social, an App-Store-approved app.
///
/// What lands: your RECENTLY PLAYED tracks (`/v1/me/player/recently-played`),
/// as "Song — Artist" link things opening in Spotify, each wearing its album's
/// cover — one thing per song (dedup by track id), `capturedAt` = its play time.
///
/// The standing cost, stated plainly: `SpotifyWebPlayerToken` carries a
/// hardcoded TOTP secret and version. When Spotify rotates either, token refresh
/// stops until the constants here are updated. This is a scraping-class
/// dependency, not a stable integration — the maintenance price of a seat that
/// needs no developer standing.
enum SpotifyAuth {

    /// The whole credential: the web-player bearer token, the session cookies it
    /// was minted from (`sp_dc` is the long-lived one — effectively full account
    /// access, which is why the vault stores it DEVICE-ONLY and never syncs it),
    /// and when the bearer expires. Persisted as one JSON blob under `credsKey`.
    struct Credentials: Codable {
        var bearerToken: String
        var spDC: String
        var spT: String?
        var spKey: String?
        /// Epoch seconds; nil means "unknown, refresh before use".
        var accessTokenExpiresAt: TimeInterval?
        var username: String?
    }

    /// WHICH LINK BROKE. The seat's connect is a chain — harvest the cookie,
    /// mint a bearer from it, read `/v1/me` with that bearer — and a `Bool`
    /// over the whole chain is why a user's "Spotify connection is failing"
    /// could not be answered from the report (2026-09-12). The two cases differ
    /// in what the app should DO, which is the reason to separate them:
    /// `.refused` means the session is genuinely dead and the person has to
    /// sign in again; `.unreachable` means nobody knows yet, so the credential
    /// is KEPT and the next foreground retries it.
    enum Failure: Equatable {
        /// Spotify answered, and the answer was no. Carries the HTTP status the
        /// refusal came as — 200 is the anonymous-token case below.
        case refused(Int)
        /// No usable answer: no network, a timeout, a 5xx.
        case unreachable
        /// Nothing is stored — no sign-in has happened on this device.
        case noSession

        /// The line the connect screen shows. Says which link broke, so the
        /// next report names it.
        var line: String {
            switch self {
            case .noSession:
                return String(localized: "Sign in to connect Spotify.")
            case .unreachable:
                return String(localized: "Signed in, but couldn't reach Spotify just now — it'll retry on its own.")
            case .refused(let status):
                return String(localized: "Spotify didn't accept that sign-in (\(status)) — tap Connect to try again.")
            }
        }

        /// Whether the stored credential is now known to be worthless. Only a
        /// refusal says that; an unreachable moment says nothing at all, and
        /// wiping on it costs the person the whole web sign-in for a blip.
        var clearsCredential: Bool { self == .unreachable ? false : true }
    }

    private static let credsKey = "spotify.creds"

    static var connected: Bool { load()?.spDC.isEmpty == false }

    static func disconnect() {
        TokenVault.delete(credsKey)
    }

    // MARK: - Credential storage (one JSON blob in the device-only vault)

    static func load() -> Credentials? {
        guard let raw = TokenVault.get(credsKey),
              let data = raw.data(using: .utf8),
              let creds = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return nil }
        return creds
    }

    static func save(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds),
              let raw = String(data: data, encoding: .utf8) else { return }
        TokenVault.set(raw, for: credsKey)
    }

    /// Store the credential the login web view harvested. The bearer's lifetime
    /// isn't known at capture time (the web player mints it without telling us),
    /// so it's left nil and the first read refreshes it.
    static func store(bearerToken: String, spDC: String, spT: String?, spKey: String?) {
        save(Credentials(bearerToken: bearerToken, spDC: spDC, spT: spT,
                         spKey: spKey, accessTokenExpiresAt: nil, username: nil))
    }

    // MARK: - A live bearer token

    private static let tokenRefreshLeeway: TimeInterval = 120

    /// A live web-player bearer token — refreshed through the stored `sp_dc`
    /// session when the current one has expired (or when its expiry is unknown).
    static func accessToken() async -> String? { await token().0 }

    /// The bearer, and the reason there isn't one. A stored bearer we couldn't
    /// refresh is still worth one try — it may not have actually expired — but
    /// the refresh's own verdict is what rides along, because a bearer that
    /// then gets refused is a refusal of the SESSION, not of that one call.
    static func token() async -> (String?, Failure?) {
        guard var creds = load(), !creds.spDC.isEmpty else { return (nil, .noSession) }
        if let expiresAt = creds.accessTokenExpiresAt,
           expiresAt - Date.now.timeIntervalSince1970 > tokenRefreshLeeway,
           !creds.bearerToken.isEmpty {
            return (creds.bearerToken, nil)
        }
        let (refreshed, failure) = await refreshWebPlayerToken(creds)
        guard let refreshed else {
            return (creds.bearerToken.isEmpty ? nil : creds.bearerToken, failure)
        }
        creds = refreshed
        return (creds.bearerToken, nil)
    }

    /// Mint a fresh web-player bearer from the `sp_dc` session, exactly the way
    /// `open.spotify.com` does: a TOTP-signed call to its own token endpoint.
    /// Saves and returns the refreshed credential, or the reason it couldn't.
    private static func refreshWebPlayerToken(_ creds: Credentials)
        async -> (creds: Credentials?, failure: Failure?) {
        let totp = SpotifyWebPlayerToken.current()
        let serverTotp = await SpotifyWebPlayerToken.serverSynchronized() ?? totp
        var comps = URLComponents(string: "https://open.spotify.com/api/token")!
        comps.queryItems = [
            URLQueryItem(name: "reason", value: "transport"),
            URLQueryItem(name: "productType", value: "web-player"),
            URLQueryItem(name: "totp", value: totp),
            URLQueryItem(name: "totpServer", value: serverTotp),
            URLQueryItem(name: "totpVer", value: SpotifyWebPlayerToken.version),
        ]
        guard let url = comps.url else { return (nil, .unreachable) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("WebPlayer", forHTTPHeaderField: "app-platform")
        request.setValue(cookieHeader(creds), forHTTPHeaderField: "cookie")
        // PRESENT THE COOKIE AS THE CLIENT THAT MINTED IT. `sp_dc` was issued
        // to a `WKWebView` identifying as Safari; this request then handed it
        // back under URLSession's default `Casberi/CFNetwork/Darwin` agent, and
        // this endpoint sits behind an anti-abuse layer (its refusals come back
        // stamped `x-sigsci-requestid`) that scores exactly that mismatch. The
        // seat is a web-player impersonation by design, so sending the web
        // player's own agent is the correct implementation rather than a
        // workaround — and it is the one difference between this request and
        // the browser request it is copying.
        request.setValue(Self.webPlayerUserAgent, forHTTPHeaderField: "user-agent")
        // The `cookie` header we just set IS the credential — nothing else may
        // touch it. With cookie handling on, URLSession merges the shared jar
        // into this header, and a stale `sp_dc` from any earlier session would
        // silently replace the one we mean to send.
        request.httpShouldHandleCookies = false
        NetworkLedger.shared.record(request, as: "Spotify")

        // A NO-ANSWER AND A REFUSAL ARE DIFFERENT FACTS, and collapsing them is
        // what made a remote "it's failing" report undiagnosable: a flat network
        // moment and a dead session both read as "that sign-in didn't take", and
        // the screen then threw the credential away for either one.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return (nil, .unreachable) }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["accessToken"] as? String, !access.isEmpty
        else {
            // 5xx is Spotify having a bad minute, not a session verdict.
            return (nil, http.statusCode >= 500 ? .unreachable
                                                : .refused(http.statusCode))
        }
        // **A 200 IS NOT A SIGNED-IN SESSION.** `open.spotify.com/api/token`
        // answers a valid TOTP with a perfectly well-formed token EVEN WITH NO
        // COOKIE AT ALL — it just marks it `isAnonymous: true` (verified live
        // 2026-09-12: cookie-less, `totpVer=61`, HTTP 200, `isAnonymous: true`).
        // An anonymous token reaches no `/v1/me` and no recently-played, so
        // taking it as the refreshed credential turns a lapsed session into a
        // seat that is "connected" and silently reads nothing forever. Treat it
        // as the refusal it is: a lapsed session, which the connect screen and
        // the ingest both already render as "sign in again".
        if json["isAnonymous"] as? Bool == true { return (nil, .refused(200)) }

        var refreshed = creds
        refreshed.bearerToken = access
        if let ms = json["accessTokenExpirationTimestampMs"] as? Double {
            refreshed.accessTokenExpiresAt = ms / 1000
        }
        save(refreshed)
        return (refreshed, nil)
    }

    /// What `open.spotify.com` is running when it mints a token: mobile Safari,
    /// which is also what the `WKWebView` the cookie came from sends.
    static let webPlayerUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    private static func cookieHeader(_ creds: Credentials) -> String {
        var parts = ["sp_dc=\(creds.spDC)"]
        if let spT = creds.spT, !spT.isEmpty { parts.append("sp_t=\(spT)") }
        if let spKey = creds.spKey, !spKey.isEmpty { parts.append("sp_key=\(spKey)") }
        return parts.joined(separator: "; ")
    }

    // MARK: - Validate (and resolve the display username)

    /// Confirms the harvested session actually works, and best-effort resolves
    /// the account's username for the connected-state line. `/v1/me` is the
    /// canonical current-user endpoint and needs only the bearer token — the
    /// same call stupid-social proves the harvested token reaches. A non-200
    /// here means the login didn't take (or has already lapsed).
    static func validate() async -> Failure? {
        let (bearer, tokenFailure) = await token()
        guard let bearer else { return tokenFailure ?? .unreachable }
        let (json, status) = await IngestSupport.getJSONStatus(
            "https://api.spotify.com/v1/me", auth: "Bearer \(bearer)", service: "Spotify")
        guard status == 200, let me = json as? [String: Any] else {
            // Status 0 is `getJSONStatus`'s own "no response at all". A 5xx is
            // Spotify's bad minute. Everything else, `/v1/me` included, is the
            // session being turned down — and if the refresh already had a
            // verdict, that one is the more specific fact.
            if status == 0 || status >= 500 { return .unreachable }
            return tokenFailure ?? .refused(status)
        }
        if var creds = load() {
            creds.username = (me["display_name"] as? String) ?? (me["id"] as? String)
            save(creds)
        }
        return nil
    }
}

// MARK: - Web-player TOTP

/// The one-time code `open.spotify.com` signs its token requests with. Ported
/// verbatim from stupid-social (which reverse-engineered it from the web
/// player): an HMAC-SHA1 TOTP over a fixed secret. `version` and `secret` are
/// the fragile constants — when Spotify rotates them, `SpotifyAuth`'s refresh
/// starts failing and these must be updated.
enum SpotifyWebPlayerToken {
    static let version = "61"

    private static let period: TimeInterval = 30
    private static let secret = obfuscatedSecret(",7/*F(\"rLJ2oxaKL^f+E1xvP@N")

    static func current(date: Date = Date()) -> String {
        generate(timestamp: date.timeIntervalSince1970)
    }

    /// The web player syncs its counter to Spotify's clock before signing, so a
    /// device with a skewed clock still mints a valid code. Best-effort: falls
    /// back to the local clock on any failure.
    static func serverSynchronized() async -> String? {
        var request = URLRequest(url: URL(string: "https://open.spotify.com/api/server-time")!)
        request.setValue(SpotifyAuth.webPlayerUserAgent, forHTTPHeaderField: "user-agent")
        NetworkLedger.shared.record(request, as: "Spotify")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let serverTime = (json["serverTime"] as? Double)
                ?? (json["serverTime"] as? Int).map(Double.init)
        else { return nil }
        return generate(timestamp: serverTime)
    }

    private static func generate(timestamp: TimeInterval) -> String {
        var counter = UInt64(floor(timestamp / period)).bigEndian
        let counterData = Data(bytes: &counter, count: MemoryLayout<UInt64>.size)
        let key = SymmetricKey(data: secret)
        let hash = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let bytes = Array(hash)
        let offset = Int(bytes[bytes.count - 1] & 0x0F)
        let truncated =
            (UInt32(bytes[offset] & 0x7F) << 24) |
            (UInt32(bytes[offset + 1] & 0xFF) << 16) |
            (UInt32(bytes[offset + 2] & 0xFF) << 8) |
            UInt32(bytes[offset + 3] & 0xFF)
        return String(format: "%06u", truncated % 1_000_000)
    }

    private static func obfuscatedSecret(_ value: String) -> Data {
        let scalars = Array(value.unicodeScalars)
        let decoded = scalars.enumerated().map { index, scalar in
            Int(scalar.value) ^ (index % 33 + 9)
        }
        return Data(decoded.map(String.init).joined().utf8)
    }
}

// MARK: - Ingest

enum SpotifyIngest {

    @MainActor private static var running = false

    /// Recently played, newest 50 — "Song — Artist" things linking to Spotify,
    /// each wearing its album's cover and the album it came off. One thing per
    /// SONG (dedup by track id): in Casberi a "notification" is the arrival of a
    /// new thing in the feed, so a song you replay is already landed and makes
    /// no new noise; its row simply carries its most recent play time.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard SpotifyAuth.connected, !running else {
            return SpotifyAuth.connected ? 0 : nil
        }
        running = true
        defer { running = false }

        guard let token = await SpotifyAuth.accessToken() else { return nil }
        let (json, status) = await IngestSupport.getJSONStatus(
            "https://api.spotify.com/v1/me/player/recently-played?limit=50",
            auth: "Bearer \(token)", service: "Spotify")
        // 401/403 here means the session lapsed after the token check — the
        // refresh already ran inside `accessToken()`, so there's nothing more to
        // try this pass; the seat will re-validate on the next foreground.
        guard status == 200,
              let root = json as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }

        let existing = IngestSupport.existingSourceRefs(context, source: "Spotify")
        var seen = Set<String>()
        var added = 0

        for item in items {
            guard let track = item["track"] as? [String: Any],
                  let id = track["id"] as? String,
                  let name = track["name"] as? String else { continue }
            let ref = "spotify:\(id)"
            // One row per song even if it appears several times in the window
            // (a replay), and never a duplicate of a row already landed.
            guard seen.insert(ref).inserted, !existing.contains(ref) else { continue }
            let artists = ((track["artists"] as? [[String: Any]]) ?? [])
                .compactMap { $0["name"] as? String }.joined(separator: ", ")
            let link = ((track["external_urls"] as? [String: Any])?["spotify"] as? String) ?? ""
            let when = IngestSupport.isoDate(item["played_at"])
            let album = (track["album"] as? [String: Any]) ?? [:]

            let thing = Thing(
                kind: .link,
                title: artists.isEmpty ? name : "\(name) — \(artists)",
                content: link,
                source: "Spotify",
                capturedAt: when ?? .now,
                // The facet the retriever narrows "what I played on Spotify" to,
                // and simply true: this endpoint is recently-played and nothing
                // else. No "Music" tag beside it — the source chip and type tag
                // already say that (ShapedRows' reason for dropping bridge tags).
                tags: ["Played"],
                sourceRef: ref
            )
            // The join key MediaMoments' artist crossing reads — a backend
            // field, no row draws it for Spotify.
            if !artists.isEmpty { thing.authorHandle = artists }
            thing.previewImageURL = coverURL(album)
            // The album the track came off — the one fact the payload carries
            // that the title doesn't. `summary`, not `enrichedText`: Spotify
            // authored it and handed it over, so it's shown copy, not scraped.
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
    /// picks for the same job and reasons. Nearest-to-300 rather than a fixed
    /// index: the sizes are a convention, not a contract.
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
    /// Nil for a single, where Spotify wraps the one track in an album of the
    /// same name and the line would only repeat the title back.
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
