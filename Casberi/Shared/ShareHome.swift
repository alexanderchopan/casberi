import Foundation

/// Where a share into Casberi lands (prd §1200): the screen you would look
/// for it on later, chosen for you and named on the pill. An article is
/// Reading's, a video or a show Media's, your own words and pictures Notes'.
/// Nothing is asked at share time; anything with no home is not taken.
///
/// A link is stamped with the ROOM's own name as its source. A room's
/// members are `[room] + its seats' sources` (`RoomAccounts.roomSources`),
/// so the row stands in that room and under its category on Home with no
/// app connected, and no seat is claimed for a share it never made.
/// Foundation-only: compiled into the app, the share extension and
/// `share-home-selftest.sh`.
enum ShareHome: String, Sendable, CaseIterable {
    case reading, media, notes

    /// The source a shared thing is stamped with. Reading and Media are
    /// `RoomAccounts.readingRoom` / `.mediaRoom`, spelled here because the
    /// extension does not compile `RoomAccounts`; the self-test holds them
    /// equal. Notes is `NoteSheetSource.keptSource`, a note of yours.
    var source: String {
        switch self {
        case .reading: return "Reading"
        case .media:   return "Media"
        case .notes:   return "You"
        }
    }

    /// The pill's words: the place, never "Casberi".
    var confirmation: String {
        switch self {
        // Media's Read since Reading folded into Media (prd §1204); the
        // source stays "Reading", which is what Read lists.
        case .reading: return String(localized: "Saved to Media")
        case .media:   return String(localized: "Saved to Media")
        case .notes:   return String(localized: "Saved to Notes")
        }
    }

    /// The hosts whose pages are something you watch or listen to. A
    /// subdomain counts (`m.youtube.com`, `music.youtube.com`). Social video
    /// (TikTok, Instagram, X) is not here: those are posts, and a post is
    /// read where it was posted.
    static let mediaHosts: [String] = [
        "youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "twitch.tv",
        "podcasts.apple.com", "music.apple.com", "tv.apple.com", "open.spotify.com",
        "soundcloud.com", "overcast.fm", "pca.st", "pocketcasts.com", "bandcamp.com",
    ]

    /// A link's home: Media for a watch or listen host, else Reading.
    static func forLink(_ url: URL) -> ShareHome {
        // `www.` needs no strip: it is a subdomain like any other.
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return .reading }
        let isMedia = mediaHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        return isMedia ? .media : .reading
    }

    /// Shared TEXT is a link only when the link is all it is; words around
    /// an address are something you wrote or copied to keep, which is a
    /// note. Returns the link's address when the text is one.
    static func link(inText text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }
}
