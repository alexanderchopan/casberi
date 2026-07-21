import Foundation
import SwiftData

/// The Steam bridge (2026-07-08) — what you play lands in your feed. Steam's
/// Web API is key-based and free (steamcommunity.com/dev/apikey), read-only,
/// and serves any PUBLIC profile: recently played games land as link things
/// to their store pages. The key stays in the Keychain; the profile is public
/// data. No OAuth, no server.
enum SteamBridge {
    static let tokenKey = "token.steam"            // Web API key → Keychain
    private static let profileKey = "steam.profile"       // what the person typed
    private static let steamIDKey = "steam.steamid64"     // resolved, cached

    static var connected: Bool { TokenVault.get(tokenKey) != nil }

    static var profile: String {
        get { UserDefaults.standard.string(forKey: profileKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: profileKey)
            UserDefaults.standard.removeObject(forKey: steamIDKey)   // re-resolve
        }
    }

    /// "https://steamcommunity.com/id/gabelogannewell" → "gabelogannewell".
    static func normalize(_ raw: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["https://", "http://", "www.", "steamcommunity.com/id/",
                     "steamcommunity.com/profiles/"] {
            if n.lowercased().hasPrefix(junk) { n.removeFirst(junk.count) }
        }
        if let slash = n.firstIndex(of: "/") { n = String(n[..<slash]) }
        return n
    }

    static func disconnect() {
        TokenVault.delete(tokenKey)
        UserDefaults.standard.removeObject(forKey: steamIDKey)
    }

    /// The SteamID64 for the saved profile — used directly when the person
    /// pasted the 17-digit id, resolved (once) from the vanity name otherwise.
    static func steamID(key: String) async -> String? {
        if let cached = UserDefaults.standard.string(forKey: steamIDKey) { return cached }
        let name = normalize(profile)
        guard !name.isEmpty else { return nil }
        if name.count == 17, name.allSatisfy(\.isNumber) {
            UserDefaults.standard.set(name, forKey: steamIDKey)
            return name
        }
        guard let root = await IngestSupport.getJSON(
            "https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/?key=\(key)&vanityurl=\(name)"
        ) as? [String: Any],
              let response = root["response"] as? [String: Any],
              (response["success"] as? Int) == 1,
              let id = response["steamid"] as? String else { return nil }
        UserDefaults.standard.set(id, forKey: steamIDKey)
        return id
    }
}

enum SteamIngest {

    @MainActor private static var running = false

    /// Recently played games land as link things to their store pages —
    /// once per game (the ref is the app id). Returns nil when Steam
    /// couldn't be reached or the key/profile doesn't resolve.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard SteamBridge.connected, !running else {
            return SteamBridge.connected ? 0 : nil
        }
        running = true
        defer { running = false }

        guard let key = TokenVault.get(SteamBridge.tokenKey),
              let steamID = await SteamBridge.steamID(key: key),
              let root = await IngestSupport.getJSON(
                "https://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v1/?key=\(key)&steamid=\(steamID)"
              ) as? [String: Any],
              let response = root["response"] as? [String: Any] else { return nil }
        let games = (response["games"] as? [[String: Any]]) ?? []   // none is a real answer

        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0
        var backfilled = false

        // Header art is a pure function of the appid already stored in the
        // ref, so EVERY artless row gets patched — not just games inside the
        // two-week recently-played window. Steady state: the fetch matches
        // nothing and this is a no-op. (A delisted game's header can 404 —
        // RemoteThumb falls back to the Steam glyph, never a gray hole.)
        for (ref, thing) in IngestSupport.artlessThings(context, source: "Steam") {
            guard let appID = Int(ref.dropFirst("steam:".count)) else { continue }
            thing.previewImageURL = headerArt(appID)
            backfilled = true
        }

        for game in games {
            guard let appID = game["appid"] as? Int,
                  let name = game["name"] as? String else { continue }
            let ref = "steam:\(appID)"
            guard !existing.contains(ref) else { continue }
            let mins = (game["playtime_2weeks"] as? Int) ?? 0
            let hours = String(format: "%.1f", Double(mins) / 60)
            let thing = Thing(
                kind: .link,
                title: "Played \(name)",
                content: "https://store.steampowered.com/app/\(appID) · \(hours)h past two weeks",
                source: "Steam",
                capturedAt: .now,
                sourceRef: ref
            )
            thing.previewImageURL = headerArt(appID)
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || backfilled { context.saveHonestly() }
        return added
    }

    /// The store header — the most reliably present of Steam's art assets
    /// (capsule/library art is spotty for older games). RemoteThumb
    /// center-crops the wide frame into the row's square.
    private static func headerArt(_ appID: Int) -> String {
        "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg"
    }
}
