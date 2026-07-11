import Foundation

/// Find-a-person search for the handle bridges (2026-07-11) — type a few
/// letters into the Bluesky or Farcaster field, see matching accounts, tap
/// one to watch it. Both endpoints are the same public, keyless surfaces
/// the ingests already ride: Bluesky's AppView serves a typeahead, and the
/// Farcaster team's own client API serves user search. A failed or empty
/// search shows nothing — typing the exact name still connects, unchanged.
enum UserSearch {

    struct Hit: Identifiable {
        /// What connect stores — the full Bluesky handle, or the Farcaster
        /// username (the stores normalize again on add; harmless).
        let handle: String
        /// The human name, falling back to the handle when the profile has
        /// none — the row never shows an empty first line.
        let displayName: String
        let avatarURL: String?
        /// Farcaster only — carrying the fid saves the name→fid resolve
        /// the first sync would otherwise pay.
        let fid: Int?
        var id: String { handle }
    }

    static let limit = 6

    static func bluesky(_ query: String) async -> [Hit] {
        var comps = URLComponents(
            string: "https://public.api.bsky.app/xrpc/app.bsky.actor.searchActorsTypeahead")!
        comps.queryItems = [URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "limit", value: "\(limit)")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let actors = root["actors"] as? [[String: Any]] else { return [] }
        return actors.compactMap { actor in
            guard let handle = actor["handle"] as? String, !handle.isEmpty else { return nil }
            return Hit(handle: handle,
                       displayName: name(actor["displayName"], fallback: handle),
                       avatarURL: IngestSupport.imageURL(actor["avatar"] as? String),
                       fid: nil)
        }
    }

    static func farcaster(_ query: String) async -> [Hit] {
        var comps = URLComponents(string: "https://client.farcaster.xyz/v2/search-users")!
        comps.queryItems = [URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "limit", value: "\(limit)")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let users = result["users"] as? [[String: Any]] else { return [] }
        return users.compactMap { user in
            guard let username = user["username"] as? String, !username.isEmpty else { return nil }
            let pfp = (user["pfp"] as? [String: Any])?["url"] as? String
            return Hit(handle: username,
                       displayName: name(user["displayName"], fallback: username),
                       avatarURL: IngestSupport.imageURL(pfp),
                       fid: user["fid"] as? Int)
        }
    }

    private static func name(_ raw: Any?, fallback: String) -> String {
        let trimmed = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
