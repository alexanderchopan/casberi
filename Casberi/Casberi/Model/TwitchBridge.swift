import Foundation
import SwiftData

/// The Twitch bridge (2026-07-08) — followed channels' LIVE streams land as
/// link things. Auth is Twitch's device-code flow: made for public clients,
/// no client secret, refresh tokens included — the person enters a short code
/// at twitch.tv/activate once and the phone holds the session. No server.
///
/// ACTIVE (2026-07-08): the client id below is the user's registered public
/// app from dev.twitch.tv/console/apps. A client id is not a secret — it
/// identifies the app; the device-code flow needs nothing else.
enum TwitchAuth {

    /// From dev.twitch.tv/console/apps (client type: Public).
    static let clientID = "49rla6akq1thul05u8utbxk013xv0t"
    static let scope = "user:read:follows"
    static var ready: Bool { !clientID.isEmpty }

    private static let tokenKey = "token.twitch"
    private static let refreshKey = "token.twitch.refresh"
    private static let userKey = "twitch.userid"

    static var connected: Bool { TokenVault.get(refreshKey) != nil }

    static func disconnect() {
        TokenVault.delete(tokenKey)
        TokenVault.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    // MARK: - Device-code flow

    struct DeviceCode {
        let userCode: String      // what the person types at twitch.tv/activate
        let deviceCode: String    // what we poll with
        let interval: Int
        /// Twitch's activate URL with the code prefilled — one tap approves.
        let verificationURL: URL?
    }

    /// Step 1 — ask Twitch for a code the person enters on their own session.
    static func startDeviceFlow() async -> DeviceCode? {
        guard ready,
              let root = await postForm("https://id.twitch.tv/oauth2/device",
                                        form: ["client_id": clientID, "scopes": scope]),
              let user = root["user_code"] as? String,
              let device = root["device_code"] as? String else { return nil }
        return DeviceCode(userCode: user, deviceCode: device,
                          interval: (root["interval"] as? Int) ?? 5,
                          verificationURL: (root["verification_uri"] as? String).flatMap(URL.init))
    }

    /// Step 2 — poll until the person approves (or the code expires).
    /// Returns true on success; "authorization_pending" keeps polling.
    static func poll(_ code: DeviceCode, attempts: Int = 36) async -> Bool {
        for _ in 0..<attempts {
            try? await Task.sleep(for: .seconds(code.interval))
            if Task.isCancelled { return false }
            guard let root = await postForm("https://id.twitch.tv/oauth2/token", form: [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "scopes": scope,
            ]) else { continue }
            if let access = root["access_token"] as? String {
                TokenVault.set(access, for: tokenKey)
                if let refresh = root["refresh_token"] as? String {
                    TokenVault.set(refresh, for: refreshKey)
                }
                return true
            }
            // "authorization_pending" → keep waiting; anything else is fatal.
            if let message = root["message"] as? String,
               message != "authorization_pending" { return false }
        }
        return false
    }

    /// A live access token, refreshed through the stored refresh token.
    static func accessToken() async -> String? {
        if let token = TokenVault.get(tokenKey), await validate(token) { return token }
        guard let refresh = TokenVault.get(refreshKey),
              let root = await postForm("https://id.twitch.tv/oauth2/token", form: [
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": refresh,
              ]),
              let access = root["access_token"] as? String else { return nil }
        TokenVault.set(access, for: tokenKey)
        if let newRefresh = root["refresh_token"] as? String {
            TokenVault.set(newRefresh, for: refreshKey)
        }
        return access
    }

    /// The signed-in user's id (cached) — the follows query needs it.
    static func userID(token: String) async -> String? {
        if let cached = UserDefaults.standard.string(forKey: userKey) { return cached }
        guard let root = await IngestSupport.getJSON(
            "https://api.twitch.tv/helix/users",
            auth: "Bearer \(token)", headers: ["Client-Id": clientID]
        ) as? [String: Any],
              let user = (root["data"] as? [[String: Any]])?.first,
              let id = user["id"] as? String else { return nil }
        UserDefaults.standard.set(id, forKey: userKey)
        return id
    }

    private static func validate(_ token: String) async -> Bool {
        await IngestSupport.getJSON("https://id.twitch.tv/oauth2/validate",
                                    auth: "OAuth \(token)") != nil
    }

    /// Form-encoded POST that returns JSON even on non-200 (the device flow
    /// answers "authorization_pending" as a 400 — that is data, not failure).
    private static func postForm(_ url: String, form: [String: String]) async -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - Ingest

enum TwitchIngest {

    @MainActor private static var running = false

    /// The streams live as of the LAST sync — the feed's "Live" indicator
    /// reads this set, so a row only claims live while Twitch itself said so
    /// (refreshed every foreground via BridgeRefresh). Ended streams simply
    /// drop out; their things stay as records with their timestamps.
    private static let liveKey = "twitch.live.refs"
    static var liveRefs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: liveKey) ?? [])
    }

    /// Followed channels that are LIVE right now — each stream lands once
    /// (the ref is the stream id, which changes per broadcast).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard TwitchAuth.connected, !running else {
            return TwitchAuth.connected ? 0 : nil
        }
        running = true
        defer { running = false }

        guard let token = await TwitchAuth.accessToken(),
              let userID = await TwitchAuth.userID(token: token),
              let root = await IngestSupport.getJSON(
                "https://api.twitch.tv/helix/streams/followed?user_id=\(userID)",
                auth: "Bearer \(token)", headers: ["Client-Id": TwitchAuth.clientID]
              ) as? [String: Any],
              let streams = root["data"] as? [[String: Any]] else { return nil }

        let existing = IngestSupport.existingSourceRefs(context)
        let artless = IngestSupport.artlessThings(context, source: "Twitch")
        var added = 0
        var changed = false
        var liveNow: [String] = []

        for stream in streams {
            guard let id = stream["id"] as? String,
                  let name = stream["user_name"] as? String,
                  let login = stream["user_login"] as? String else { continue }
            let ref = "twitch:\(id)"
            liveNow.append(ref)
            // A frame of the stream RIGHT NOW — Helix hands a
            // {width}x{height} template; the CDN refreshes the capture every
            // few minutes. Honest only while live: the pass below strips it
            // the refresh after the stream ends.
            let frame = (stream["thumbnail_url"] as? String)?
                .replacingOccurrences(of: "{width}", with: "320")
                .replacingOccurrences(of: "{height}", with: "180")
            if existing.contains(ref) {
                if let frame, let thing = artless[ref] {
                    thing.previewImageURL = frame
                    changed = true
                }
                continue
            }
            let game = (stream["game_name"] as? String) ?? ""
            // Sentence case (caps law) — the feed's Live indicator carries
            // the state; the title just names who and what.
            let thing = Thing(
                kind: .link,
                title: game.isEmpty ? "\(name) live" : "\(name) live — \(game)",
                content: "https://twitch.tv/\(login)",
                source: "Twitch",
                capturedAt: IngestSupport.isoDate(stream["started_at"]) ?? .now,
                sourceRef: ref
            )
            thing.previewImageURL = frame
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        UserDefaults.standard.set(liveNow, forKey: liveKey)

        // Honesty rule: a "live frame" on a stream that ended is fake status
        // (the CDN swaps in a stale capture or a 404 card). Rows that left
        // the live set drop back to the Twitch glyph.
        let withFrames = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "Twitch" && $0.previewImageURL != nil
        })
        for thing in (try? context.fetch(withFrames)) ?? []
        where !liveNow.contains(thing.sourceRef ?? "") {
            thing.previewImageURL = nil
            changed = true
        }

        if added > 0 || changed { try? context.save() }
        return added
    }
}
