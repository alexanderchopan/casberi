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
/// What lands (prd §1158, read off `spclient`, never `api.spotify.com`): the
/// albums, playlists, artists and shows you played, one row per one of them
/// per day, and each friend's newest play. Rows landed before §1158 are one
/// per SONG (`spotify:<track id>`) and stay as they are.
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
        /// The account's Spotify USERNAME (its id, never the display name
        /// above), which `spclient`'s recently-played path is keyed on. It
        /// never changes, so it is resolved once through Pathfinder and kept
        /// (prd §1158). Optional: every credential stored before it decodes.
        var userID: String?
        /// The web player's client id, as `/api/token` hands it back. A
        /// Pathfinder `client-token` is minted for it.
        var clientID: String?
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
        /// Spotify answered 429. NOT a verdict on the session: `api.spotify.com`
        /// throttles the web player's SHARED client id, so a web-player token is
        /// refused there on its very first request, from a fresh machine, with
        /// a real session or an anonymous one alike (measured 2026-09-12,
        /// `Retry-After: 48` on `/v1/tracks`, `/v1/me` and recently-played).
        /// Build 568 read it as `.refused` and threw a good sign-in away.
        case throttled
        /// Nothing is stored — no sign-in has happened on this device.
        case noSession
        /// Spotify answered 200 in a shape this build cannot read (prd §1158):
        /// the `spclient` reads are the web player's own, undocumented, so a
        /// changed shape is a fact of its own, never "couldn't reach".
        case unreadable

        /// The line the connect screen shows. Says which link broke, so the
        /// next report names it.
        var line: String {
            switch self {
            case .noSession:
                return String(localized: "Sign in to connect Spotify.")
            case .unreachable:
                return String(localized: "Signed in, but couldn't reach Spotify just now — it'll retry on its own.")
            case .throttled:
                return String(localized: "Signed in — Spotify is busy right now, so your plays will arrive shortly.")
            case .refused(let status):
                return String(localized: "Spotify didn't accept that sign-in (\(status)) — tap Connect to try again.")
            case .unreadable:
                return String(localized: "Signed in, but Spotify answered in a shape this version can't read.")
            }
        }

        /// Whether the stored credential is now known to be worthless. Only a
        /// refusal says that; an unreachable moment says nothing at all, and
        /// wiping on it costs the person the whole web sign-in for a blip.
        var clearsCredential: Bool {
            switch self {
            case .refused, .noSession: return true
            case .unreachable, .throttled, .unreadable: return false
            }
        }

        /// The one mapping from an HTTP status to a case, so the token call and
        /// every read agree on what a 429 means.
        static func from(status: Int) -> Failure {
            switch status {
            case 0: return .unreachable
            case 429: return .throttled
            case 500...: return .unreachable
            default: return .refused(status)
            }
        }
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
    static func token(forceRefresh: Bool = false) async -> (String?, Failure?) {
        guard var creds = load(), !creds.spDC.isEmpty else { return (nil, .noSession) }
        if !forceRefresh, let expiresAt = creds.accessTokenExpiresAt,
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
        let (json, failure) = await mint(creds, reason: "transport")
        guard let json, let access = json["accessToken"] as? String else {
            return (nil, failure ?? .unreachable)
        }
        var refreshed = creds
        refreshed.bearerToken = access
        if let ms = json["accessTokenExpirationTimestampMs"] as? Double {
            refreshed.accessTokenExpiresAt = ms / 1000
        }
        if let clientID = json["clientId"] as? String, !clientID.isEmpty {
            refreshed.clientID = clientID
        }
        save(refreshed)
        return (refreshed, nil)
    }

    /// One call to the web player's token endpoint, signed the way
    /// `open.spotify.com` signs it. `reason` is `transport` for the bearer
    /// every read carries, `init` for the one Pathfinder takes (stupid-social's
    /// split, prd §1158). The JSON comes back only for a SIGNED-IN mint.
    private static func mint(_ creds: Credentials, reason: String)
        async -> (json: [String: Any]?, failure: Failure?) {
        let totp = SpotifyWebPlayerToken.current()
        let serverTotp = await SpotifyWebPlayerToken.serverSynchronized() ?? totp
        var comps = URLComponents(string: "https://open.spotify.com/api/token")!
        comps.queryItems = [
            URLQueryItem(name: "reason", value: reason),
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
              (json["accessToken"] as? String)?.isEmpty == false
        else {
            // 5xx and 429 are Spotify having a bad minute, not a session verdict.
            return (nil, .from(status: http.statusCode))
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
        return (json, nil)
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
        guard let creds = load(), !creds.spDC.isEmpty else { return .noSession }
        // THE SESSION PROOF IS THE TOKEN ENDPOINT'S OWN VERDICT. It mints for
        // any valid TOTP and says `isAnonymous: false` only when `sp_dc` is a
        // live sign-in — and it is not throttled, where `api.spotify.com` is
        // (see `.throttled`). `/v1/me` used to be this gate, so a rate limit on
        // a shared client id read as a failed sign-in for every person at once.
        // A fresh mint, not `token()`: a still-valid stored bearer would skip
        // the refresh and prove nothing.
        let (refreshed, failure) = await refreshWebPlayerToken(creds)
        guard let refreshed else { return failure ?? .unreachable }
        // The display name is a nicety, never a gate — a 429 here costs the
        // "Signed in as" line, nothing else.
        let (json, status) = await IngestSupport.getJSONStatus(
            "https://api.spotify.com/v1/me", auth: "Bearer \(refreshed.bearerToken)",
            service: "Spotify")
        if status == 200, let me = json as? [String: Any], var current = load() {
            current.username = (me["display_name"] as? String) ?? (me["id"] as? String)
            save(current)
        }
        return nil
    }
}

// MARK: - The web player's own reads (prd §1158)

/// `spclient.wg.spotify.com` and Pathfinder, the hosts `open.spotify.com`
/// itself reads. `api.spotify.com` throttles every web-player token on one
/// shared client id (§711b, measured: 429 on the first request, and still
/// 429 after three honoured `Retry-After`s), so nothing that lands rows reads
/// it. Request shapes are ported from github.com/stephancill/stupid-social
/// (2026-09-29), which reads the friend feed and the username this way in an
/// App-Store app.
extension SpotifyAuth {

    /// The version the web player stamps on its own requests.
    static let webPlayerVersion = "1.2.90.229.g33aad738"

    /// GET one `spclient` path with the session's bearer. A 401 or 403 mints
    /// a fresh bearer and asks once more: the stored one may have been caught
    /// in flight with no expiry, or may have lapsed early.
    static func spclient(_ path: String) async -> (json: Any?, failure: Failure?) {
        let (bearer, tokenFailure) = await token()
        guard var current = bearer else { return (nil, tokenFailure ?? .unreachable) }
        for attempt in 0..<2 {
            let (json, status) = await IngestSupport.getJSONStatus(
                "https://spclient.wg.spotify.com/\(path)",
                auth: "Bearer \(current)",
                headers: ["spotify-app-version": webPlayerVersion,
                          "app-platform": "WebPlayer",
                          "accept": "application/json"],
                service: "Spotify")
            if status == 200 {
                if let json { return (json, nil) }
                return (nil, .unreadable)
            }
            guard attempt == 0, status == 401 || status == 403 else {
                return (nil, .from(status: status))
            }
            let (fresh, failure) = await token(forceRefresh: true)
            guard let fresh else { return (nil, failure ?? .from(status: status)) }
            current = fresh
        }
        return (nil, .unreachable)
    }

    /// The account's username, resolved once and kept. Pathfinder's
    /// `profileAttributes` answers it to an `init` bearer carrying a
    /// `client-token` minted for the web player's client id, the chain
    /// stupid-social runs (§1158). Nil with the broken link otherwise.
    static func userID() async -> (String?, Failure?) {
        guard var creds = load(), !creds.spDC.isEmpty else { return (nil, .noSession) }
        if let id = creds.userID, !id.isEmpty { return (id, nil) }

        let (initJSON, initFailure) = await mint(creds, reason: "init")
        guard let initJSON, let initBearer = initJSON["accessToken"] as? String,
              let clientID = (initJSON["clientId"] as? String) ?? creds.clientID,
              !clientID.isEmpty
        else { return (nil, initFailure ?? .unreadable) }

        let (tokenJSON, tokenStatus) = await IngestSupport.postJSONStatus(
            "https://clienttoken.spotify.com/v1/clienttoken",
            body: ["client_data": [
                "client_version": webPlayerVersion,
                "client_id": clientID,
                "js_sdk_data": ["device_brand": "", "device_id": "", "device_model": "",
                                "device_type": "", "os": "", "os_version": ""],
            ]],
            headers: ["accept": "application/json",
                      "origin": "https://open.spotify.com",
                      "referer": "https://open.spotify.com/",
                      "app-platform": "WebPlayer",
                      "user-agent": webPlayerUserAgent],
            service: "Spotify")
        guard tokenStatus == 200 else { return (nil, .from(status: tokenStatus)) }
        guard let clientToken = ((tokenJSON as? [String: Any])?["granted_token"]
                as? [String: Any])?["token"] as? String, !clientToken.isEmpty
        else { return (nil, .unreadable) }

        let (profileJSON, profileStatus) = await IngestSupport.postJSONStatus(
            "https://api-partner.spotify.com/pathfinder/v2/query",
            auth: "Bearer \(initBearer)",
            body: ["variables": [String: Any](),
                   "operationName": "profileAttributes",
                   "extensions": ["persistedQuery": [
                       "version": 1,
                       "sha256Hash": "53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced",
                   ]]],
            headers: ["client-token": clientToken,
                      "spotify-app-version": webPlayerVersion,
                      "app-platform": "WebPlayer",
                      "accept": "application/json",
                      "origin": "https://open.spotify.com",
                      "referer": "https://open.spotify.com/",
                      "user-agent": webPlayerUserAgent],
            service: "Spotify")
        guard profileStatus == 200 else { return (nil, .from(status: profileStatus)) }
        let profile = (((profileJSON as? [String: Any])?["data"] as? [String: Any])?["me"]
                       as? [String: Any])?["profile"] as? [String: Any]
        guard let id = profile?["username"] as? String, !id.isEmpty else {
            return (nil, .unreadable)
        }
        creds = load() ?? creds
        creds.userID = id
        creds.clientID = clientID
        save(creds)
        return (id, nil)
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
    /// Why the last pass landed nothing, when it failed. `refresh` keeps its
    /// `Int?` because the sweep only needs "did it work"; the SCREEN needs to
    /// tell a throttle (signed in, plays delayed) from a dead session.
    @MainActor private(set) static var lastFailure: SpotifyAuth.Failure?

    /// What you played and what your friends are playing, both read where
    /// the web player reads them (prd §1158). `api.spotify.com`'s
    /// recently-played tracks are throttled for every web-player token
    /// (§711b), so this seat reads `spclient` instead:
    ///
    /// - **You:** the albums, playlists, artists and shows you played
    ///   (`recently-played/v3`), one row per one of them per day, named and
    ///   pictured through Spotify's public oEmbed. `spclient` keeps no
    ///   per-song history, so a row is the album or playlist, not the song.
    /// - **Friends:** each friend's newest play (`presence-view/v1/buddylist`,
    ///   people you follow who share their listening), one row per play.
    ///
    /// Nil only when both reads failed; `lastFailure` names the first.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard SpotifyAuth.connected, !running else {
            return SpotifyAuth.connected ? 0 : nil
        }
        running = true
        defer { running = false }
        lastFailure = nil

        let existing = IngestSupport.existingSourceRefs(context, source: "Spotify")
        let (friends, friendsFailure) = await friendPlays(existing: existing)
        let (yours, yoursFailure) = await yourPlays(existing: existing)
        if friends == nil && yours == nil {
            lastFailure = yoursFailure ?? friendsFailure ?? .unreachable
            return nil
        }
        let things = (yours ?? []) + (friends ?? [])
        for thing in things { context.insert(thing) }
        if !things.isEmpty {
            SpotlightIndex.index(things)
            context.saveHonestly()
        }
        return things.count
    }

    // MARK: - Yours: what you played, by album, playlist, artist or show

    /// How many new rows one pass names. Each costs one oEmbed request, and
    /// a first pass over a long history is a backlog, not news.
    static let namesPerPass = 20

    @MainActor
    private static func yourPlays(existing: Set<String>) async -> ([Thing]?, SpotifyAuth.Failure?) {
        let (id, idFailure) = await SpotifyAuth.userID()
        guard let id else { return (nil, idFailure) }
        let user = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let (json, failure) = await SpotifyAuth.spclient(
            "recently-played/v3/user/\(user)/recently-played"
            + "?format=json&offset=0&limit=50&filter=default,collection-new-episodes&market=from_token")
        guard let json else { return (nil, failure) }
        guard let plays = SpotifyPlays.contexts(json) else { return (nil, .unreadable) }

        var seen = Set<String>()
        var things: [Thing] = []
        for play in plays where things.count < namesPerPass {
            let ref = play.ref
            guard seen.insert(ref).inserted, !existing.contains(ref) else { continue }
            var named = play.fixedName
            var art: String?
            if named == nil, let page = URL(string: play.page) {
                let answer = await OEmbed.resolve(page)
                named = answer?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                art = IngestSupport.imageURL(answer?.thumbnailURL)
            }
            // Unnamed is unlanded: the next pass asks again.
            guard let name = named, !name.isEmpty else { continue }
            let thing = Thing(
                kind: .link,
                title: TitleSeam.join(name, play.kindWord),
                content: play.page,
                source: "Spotify",
                capturedAt: play.playedAt,
                tags: ["Played"],
                sourceRef: ref
            )
            thing.previewImageURL = art
            // The song last played inside it, where the answer names one: the
            // one per-song fact `spclient` keeps (§1158).
            if let last = play.lastTrackPage.flatMap(URL.init(string:)),
               let song = await OEmbed.resolve(last)?.title?
                .trimmingCharacters(in: .whitespacesAndNewlines), !song.isEmpty {
                thing.summary = String(localized: "Last played: \(song)")
            }
            things.append(thing)
        }
        return (things, nil)
    }

    // MARK: - Friends: what the people you follow are playing

    @MainActor
    private static func friendPlays(existing: Set<String>) async -> ([Thing]?, SpotifyAuth.Failure?) {
        let (json, failure) = await SpotifyAuth.spclient("presence-view/v1/buddylist")
        guard let json else { return (nil, failure) }
        guard let friends = (json as? [String: Any])?["friends"] as? [[String: Any]] else {
            return (nil, .unreadable)
        }
        var things: [Thing] = []
        for friend in friends {
            guard let user = friend["user"] as? [String: Any],
                  let userURI = user["uri"] as? String,
                  let who = (user["name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !who.isEmpty,
                  let track = friend["track"] as? [String: Any],
                  let trackURI = track["uri"] as? String,
                  let song = track["name"] as? String, !song.isEmpty,
                  let ms = SpotifyPlays.millis(friend["timestamp"])
            else { continue }
            let ref = "spotify:friend:\(userURI):\(Int64(ms))"
            guard !existing.contains(ref) else { continue }
            let artist = (track["artist"] as? [String: Any])?["name"] as? String
            let thing = Thing(
                kind: .link,
                title: TitleSeam.join(String(localized: "\(who) played \(song)"), artist),
                content: SpotifyPlays.page(trackURI) ?? "https://open.spotify.com",
                source: "Spotify",
                capturedAt: Date(timeIntervalSince1970: ms / 1000),
                tags: ["Friends"],
                sourceRef: ref
            )
            thing.previewImageURL = IngestSupport.imageURL(track["imageUrl"] as? String)
            thing.authorAvatarURL = IngestSupport.imageURL(user["imageUrl"] as? String)
            if let from = ((track["context"] as? [String: Any])?["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !from.isEmpty {
                thing.summary = String(localized: "From \(from)")
            }
            things.append(thing)
        }
        return (things, nil)
    }
}
