import Foundation

/// The pure half of the Spotify seat's `spclient` reads (prd §1158): what a
/// recently-played answer says, and the page each Spotify URI opens. Foundation
/// only, so `scripts/spotify-plays-selftest.sh` compiles it whole.
///
/// UNMEASURED against Spotify: `recently-played/v3`'s shape is the web
/// player's own, undocumented, and no build host here holds a session to
/// read it. The fixtures pin THIS parser's reading; `-spotifyProbe` logs the
/// answer's keys so the first real sign-in measures it.
enum SpotifyPlays {

    /// One thing you played from: an album, a playlist, an artist, a show.
    struct Play: Equatable {
        let uri: String
        /// The open.spotify.com page it opens, and the URL oEmbed names.
        let page: String
        /// Set only where no page can name it (Liked Songs, Your Episodes).
        let fixedName: String?
        /// "Album", "Playlist" — the row's line after the seam.
        let kindWord: String?
        let playedAt: Date
        /// The song last played inside it, when the answer says.
        let lastTrackPage: String?

        /// One row per thing played from, per day: playing an album again
        /// tomorrow is news, playing it again this afternoon is not.
        var ref: String { "spotify:played:\(uri):\(SpotifyPlays.dayKey(playedAt))" }
    }

    /// The contexts in a `recently-played/v3` answer, newest first. Nil when
    /// the answer is not that shape at all, which the seat reports as
    /// `.unreadable` rather than as an empty history.
    static func contexts(_ json: Any?) -> [Play]? {
        guard let rows = (json as? [String: Any])?["playContexts"] as? [[String: Any]]
        else { return nil }
        let plays = rows.compactMap { row -> Play? in
            guard let uri = row["uri"] as? String,
                  let target = target(uri),
                  // No time, no row: a play is never dated by the sweep.
                  let ms = millis(row["lastPlayedTime"]) else { return nil }
            return Play(uri: uri, page: target.page, fixedName: target.name,
                        kindWord: target.kind,
                        playedAt: Date(timeIntervalSince1970: ms / 1000),
                        lastTrackPage: (row["lastPlayedTrackUri"] as? String).flatMap(SpotifyPlays.page))
        }
        return plays.sorted { $0.playedAt > $1.playedAt }
    }

    /// Epoch milliseconds, as a number or a numeric string.
    static func millis(_ raw: Any?) -> Double? {
        let value: Double?
        switch raw {
        case let n as NSNumber: value = n.doubleValue
        case let s as String: value = Double(s)
        default: value = nil
        }
        guard let value, value > 0 else { return nil }
        return value
    }

    /// The open.spotify.com page a URI opens, or nil for one this seat
    /// does not open.
    static func page(_ uri: String) -> String? { target(uri)?.page }

    private static func target(_ uri: String) -> (page: String, name: String?, kind: String?)? {
        let parts = uri.split(separator: ":").map(String.init)
        guard parts.count >= 2, parts[0] == "spotify" else { return nil }
        // Library collections: `spotify:user:<id>:collection` and
        // `spotify:user:<id>:collection:your-episodes`.
        if let at = parts.firstIndex(of: "collection") {
            if parts.dropFirst(at + 1).first == "your-episodes" {
                return ("https://open.spotify.com/collection/episodes",
                        String(localized: "Your Episodes"), nil)
            }
            return ("https://open.spotify.com/collection/tracks",
                    String(localized: "Liked Songs"), nil)
        }
        // `spotify:<type>:<id>`, and the older `spotify:user:<id>:playlist:<id>`.
        let typed = parts.count >= 5 && parts[1] == "user" ? Array(parts[3...]) : Array(parts[1...])
        guard typed.count == 2, !typed[1].isEmpty,
              typed[1].allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        let kind: String
        switch typed[0] {
        case "album": kind = String(localized: "Album")
        case "playlist": kind = String(localized: "Playlist")
        case "artist": kind = String(localized: "Artist")
        case "show": kind = String(localized: "Podcast")
        case "episode": kind = String(localized: "Episode")
        case "track": kind = String(localized: "Song")
        default: return nil
        }
        return ("https://open.spotify.com/\(typed[0])/\(typed[1])", nil, kind)
    }

    /// The local calendar day a play falls on, `yyyy-MM-dd`.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
