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
        guard let kind = kindWord(typed[0]) else { return nil }
        return ("https://open.spotify.com/\(typed[0])/\(typed[1])", nil, kind)
    }

    /// The row's line for a Spotify type, where the page names no one.
    static func kindWord(_ type: String) -> String? {
        switch type {
        case "album": String(localized: "Album")
        case "playlist": String(localized: "Playlist")
        case "artist": String(localized: "Artist")
        case "show": String(localized: "Podcast")
        case "episode": String(localized: "Episode")
        case "track": String(localized: "Song")
        default: nil
        }
    }

    // MARK: - Who made it (prd §1305)

    /// The type of an open.spotify.com page (`album`, `track`, …), or nil
    /// for any other address.
    static func pageType(_ page: String) -> String? {
        guard let url = URL(string: page), url.host() == "open.spotify.com" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        return path.count == 2 ? path[0] : nil
    }

    /// The pages whose head names who made them: an album's and a song's
    /// artists, a podcast's publisher. A playlist's head names its owner by
    /// a user URL only, an artist's page is the artist, and an episode's head
    /// is the web player's stock one (all measured 2026-10-14).
    static func hasByline(_ page: String) -> Bool {
        ["album", "track", "show"].contains(pageType(page) ?? "")
    }

    /// Who made what a page opens, read off its `<head>`. Spotify's oEmbed
    /// answers a title and a picture and has never named an artist, but the
    /// page itself does, keylessly, in every locale measured (en, de, ja):
    ///
    /// - album: `og:description` "Drake · album · 2018 · 25 songs" — the
    ///   artists lead
    /// - song: `music:musician_description` "Drake, Wizkid, Kyla", else the
    ///   description's lead
    /// - podcast: `og:description` "Podcast · Joe Rogan · The official…" —
    ///   the publisher second
    ///
    /// nil for any other page, a head without the tag, or a blank name.
    static func byline(head html: String, page: String) -> String? {
        let parts = meta(html, "og:description")?
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let name: String?
        switch pageType(page) {
        case "album": name = parts.count >= 2 ? parts[0] : nil
        case "track": name = meta(html, "music:musician_description") ?? (parts.count >= 2 ? parts[0] : nil)
        case "show": name = parts.count >= 3 ? parts[1] : nil
        default: name = nil
        }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        return name
    }

    /// A `<meta property|name="key" content="…">` value, entities decoded.
    static func meta(_ html: String, _ key: String) -> String? {
        for attribute in ["property", "name"] {
            let open = "\(attribute)=\"\(key)\" content=\""
            guard let start = html.range(of: open),
                  let end = html[start.upperBound...].firstIndex(of: "\"") else { continue }
            let value = decode(String(html[start.upperBound..<end]))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// The entities a Spotify head writes ("Simon &amp; Garfunkel").
    static func decode(_ s: String) -> String {
        var out = s
        for (entity, char) in [("&quot;", "\""), ("&#x27;", "'"), ("&#39;", "'"),
                               ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }

    /// The local calendar day a play falls on, `yyyy-MM-dd`.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
