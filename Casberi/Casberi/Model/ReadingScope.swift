import Foundation

/// The Reading room's tiles (prd §1085, §1118): All, Highlights — every
/// passage you kept, from any app — Subscriptions, every feed you follow
/// with Track a subscription as its first row, then the verb, Search, last.
/// Foundation-only, its conformance beside every other in
/// `ScopeTileGlyphs.swift`.
enum ReadingScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, highlights, subscriptions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:        return String(localized: "All")
        case .highlights: return String(localized: "Highlights")
        case .subscriptions: return String(localized: "Subscriptions")
        }
    }

    var summary: String {
        switch self {
        case .all:        return String(localized: "Everything you read and save")
        case .highlights: return String(localized: "Every passage you kept")
        case .subscriptions: return String(localized: "Every site you follow")
        }
    }

}

/// The Reading room's pure rules (prd §1085), compiled whole by
/// `reading-room-selftest.sh`.
enum ReadingRoom {
    /// The apps whose every row is a passage someone highlighted.
    static let highlightSources: Set<String> = ["Readwise", "Kindle"]

    /// Whether a row is a highlight: a Readwise or Kindle passage, or one you
    /// kept from a reading body yourself (`Highlight.isHighlight`, prd §1020 —
    /// a note of yours whose ref names its origin).
    static func isHighlight(source: String, kind: String, sourceRef: String?) -> Bool {
        guard kind == "note" else { return false }
        if highlightSources.contains(source) { return true }
        return source == "You" && (sourceRef?.hasPrefix("highlight:") ?? false)
    }

    /// A save: a link you kept, with when you kept it.
    struct Save: Sendable {
        let url: String
        let at: Date
    }

    /// A site worth following: you saved from it more than once lately and
    /// follow nothing there.
    struct Suggestion: Equatable, Sendable {
        let host: String
        let count: Int
    }

    /// The apps a link is SAVED in. A feed's or a rating board's own rows
    /// (RSS, Substack, L2BEAT, Walletbeat, NerdWallet) link to the site that
    /// published them, so they would suggest following what you already read.
    static let saveSources: Set<String> = ["Bookmarks", "Raindrop", "Readwise"]

    /// How far back a save counts, and how many make a habit.
    static let window: TimeInterval = 60 * 86_400
    static let threshold = 2
    static let suggestionCap = 5

    /// Sites a person reads WITHOUT a feed to follow there: social networks,
    /// video, code hosts, search and shops. A save from one says nothing about
    /// a writer, so it is never offered.
    static let notWriters: Set<String> = [
        "x.com", "twitter.com", "t.co", "youtube.com", "youtu.be", "m.youtube.com",
        "instagram.com", "tiktok.com", "facebook.com", "threads.net", "bsky.app",
        "warpcast.com", "farcaster.xyz", "reddit.com", "linkedin.com", "github.com",
        "gist.github.com", "google.com", "docs.google.com", "drive.google.com",
        "maps.apple.com", "apps.apple.com", "amazon.com", "open.spotify.com",
        "music.apple.com", "podcasts.apple.com", "notion.so", "figma.com",
        "readwise.io", "read.readwise.io", "getpocket.com", "raindrop.io",
        "wikipedia.org", "medium.com",
    ]

    /// Whether a site is one of `notWriters`, or under one (`en.wikipedia.org`).
    static func isNotWriter(_ host: String) -> Bool {
        notWriters.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// A link's site, lower-cased, without `www.`; nil when it has none.
    static func host(of raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: text.contains("://") ? text : "https://" + text)
        guard let host = url?.host()?.lowercased(), host.contains(".") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Whether `host` is one a followed feed already covers: the same site, or
    /// one under it (a feed at `feeds.example.com` covers `example.com`'s
    /// saves, and a feed at `example.com` covers `blog.example.com`'s).
    static func covered(_ host: String, by followed: Set<String>) -> Bool {
        followed.contains { f in host == f || host.hasSuffix("." + f) || f.hasSuffix("." + host) }
    }

    /// The sites you keep saving from and follow nothing at: two saves or more
    /// in sixty days, most saved first, then A to Z, at most five.
    static func suggestions(saves: [Save], followed: Set<String>, now: Date) -> [Suggestion] {
        var counts: [String: Int] = [:]
        for save in saves where now.timeIntervalSince(save.at) <= window && save.at <= now {
            guard let host = host(of: save.url), !isNotWriter(host),
                  !covered(host, by: followed) else { continue }
            counts[host, default: 0] += 1
        }
        return counts.filter { $0.value >= threshold }
            .map { Suggestion(host: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.host < $1.host }
            .prefix(suggestionCap).map { $0 }
    }

    /// The site a typed query names, if it names one: a bare address
    /// ("stratechery.com") or a pasted link. A word with no dot is a search,
    /// never a site.
    static func site(in query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !q.contains(" "), q.contains("."),
              let host = host(of: q), !isNotWriter(host) else { return nil }
        // A TLD of letters only, two or more: "v1.2" is not a site.
        guard let tld = host.split(separator: ".").last, tld.count >= 2,
              tld.allSatisfy(\.isLetter) else { return nil }
        return host
    }
}
