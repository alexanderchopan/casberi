import Foundation

/// Find-a-person search for the handle bridges (2026-07-11) — type a few
/// letters into the Bluesky field, see matching accounts, tap one to watch
/// it. The endpoint is the same public, keyless surface the ingest already
/// rides: Bluesky's AppView serves a typeahead. A failed or empty search
/// shows nothing — typing the exact name still connects, unchanged.
enum UserSearch {

    struct Hit: Identifiable {
        /// What connect stores — the full Bluesky handle (the stores
        /// normalize again on add; harmless).
        let handle: String
        /// The human name, falling back to the handle when the profile has
        /// none — the row never shows an empty first line.
        let displayName: String
        let avatarURL: String?
        /// Podcasts only — the show's public RSS feed, carried from the
        /// iTunes search so picking a result stores the feed with no second
        /// lookup. nil for the people bridges.
        var feedURL: String? = nil
        // Podcasts from one network share an artist (the handle), so key the
        // row on the unique feed when there is one — else two NPR shows would
        // collide in a ForEach and only one would render.
        var id: String { feedURL ?? handle }
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
                       avatarURL: IngestSupport.imageURL(actor["avatar"] as? String))
        }
    }

    /// Shared with `SocialFollows`, which builds the same Hit rows from the
    /// networks' profile shapes.
    static func name(_ raw: Any?, fallback: String) -> String {
        let trimmed = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
