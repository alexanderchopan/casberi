import Foundation

/// The music rooms' tiles (prd §995): Activity · Albums · Artists · Songs,
/// on the template every room scopes with. Apple Music and Spotify share one
/// face (`.music`), so they share these tiles.
///
/// **A tile here is an ORDER, not a filter** (user, 2026-09-29: "if i press
/// song it would show all songs a-z, same for album, same for artist").
/// Activity is the room as it was — your listening, in sittings. Songs is the
/// same rows A–Z under letter headers. Albums and Artists are A–Z lists of
/// NAMES, each with how many songs it holds; one opens in place, its songs
/// A–Z under it, and its name as a row that leads back — the Notes room's
/// folder shape (prd §980).
///
/// "All songs" means the songs in Casberi, never the whole library: both
/// bridges land what you played, one row per song.
///
/// Foundation-only, so `scripts/music-shelf-selftest.sh` compiles it whole;
/// the glyphs are `ScopeTileGlyphs.swift`'s.
enum MusicScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    // A–Z (user, 2026-09-29: "all tiles need to be alphabetical"), so
    // the room opens on Activity because it is the first word, too.
    case activity, albums, artists, songs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activity: return String(localized: "Activity")
        case .songs:    return String(localized: "Songs")
        case .albums:   return String(localized: "Albums")
        case .artists:  return String(localized: "Artists")
        }
    }

    /// Read by VoiceOver and the tooltip.
    var summary: String {
        switch self {
        case .activity: return String(localized: "What you played, newest first")
        case .songs:    return String(localized: "Every song, A to Z")
        case .albums:   return String(localized: "Every album, A to Z")
        case .artists:  return String(localized: "Every artist, A to Z")
        }
    }

    /// The two tiles whose list is names you open.
    var groups: Bool { self == .albums || self == .artists }
}

enum MusicShelf {

    /// The section a name files under: its first letter, folded ("Émile" is
    /// E), or `#` for anything that does not start with a letter.
    static func letter(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let folded = String(first).folding(options: [.diacriticInsensitive, .caseInsensitive],
                                           locale: nil).uppercased()
        return folded.first?.isLetter == true ? folded : "#"
    }

    /// A–Z the way Finder and Music read names: case-blind, numbers by value.
    static func ordered(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    /// `items` A–Z by `name`, cut into letter sections in drawing order —
    /// `#` last, where the Music app puts it.
    static func sections<T>(_ items: [T], name: (T) -> String) -> [(letter: String, items: [T])] {
        let sorted = items.map { (name($0), $0) }.sorted { ordered($0.0, $1.0) }
        var out: [(letter: String, items: [T])] = []
        var tail: [T] = []
        for (n, item) in sorted {
            let l = letter(n)
            if l == "#" { tail.append(item); continue }
            if out.last?.letter == l { out[out.count - 1].items.append(item) }
            else { out.append((l, [item])) }
        }
        if !tail.isEmpty { out.append(("#", tail)) }
        return out
    }

    /// One album or artist: the name as first met, how many songs, and the
    /// first artwork met — the rows arrive newest first, so the newest.
    struct Group: Hashable, Sendable {
        let name: String
        let count: Int
        let art: String?
    }

    /// Names folded case- and space-blind, so "Blonde" and "blonde " are one
    /// album. Rows with no name are left out — the album gap is accepted
    /// (user, 2026-09-29).
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func groups(_ rows: [(name: String?, art: String?)]) -> [Group] {
        var first: [String: String] = [:]
        var counts: [String: Int] = [:]
        var art: [String: String] = [:]
        for row in rows {
            guard let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            let k = key(name)
            if first[k] == nil { first[k] = name }
            counts[k, default: 0] += 1
            if art[k] == nil, let a = row.art, !a.isEmpty { art[k] = a }
        }
        return first.map { Group(name: $0.value, count: counts[$0.key] ?? 0, art: art[$0.key]) }
    }

    /// The album a row came off. Apple Music stores it as a fact; Spotify
    /// writes it into its line, "From Blonde (2016)", sometimes followed by
    /// " · from playlist" — read here the way `MediaSheetHead` reads it.
    static func album(fact: String?, summary: String?) -> String? {
        if let fact = fact?.trimmingCharacters(in: .whitespacesAndNewlines), !fact.isEmpty {
            return fact
        }
        guard var line = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              line.hasPrefix("From ") else { return nil }
        line = String(line.dropFirst(5))
        if let dot = line.range(of: " · ") { line = String(line[..<dot.lowerBound]) }
        // The release year Spotify appends, and only that: an album called
        // "1999 (Deluxe)" keeps its own parentheses.
        if let open = line.range(of: " (", options: .backwards), line.hasSuffix(")") {
            let inner = line[open.upperBound..<line.index(before: line.endIndex)]
            if inner.count == 4, inner.allSatisfy(\.isNumber) { line = String(line[..<open.lowerBound]) }
        }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    /// The artist a row names: the stored handle, else the title's line
    /// ("Song — Artist").
    static func artist(handle: String?, titleLine: String?) -> String? {
        for raw in [handle, titleLine] {
            if let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        }
        return nil
    }
}
