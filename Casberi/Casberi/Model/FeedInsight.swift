import Foundation

/// The per-source feed overviews, derived ONLY from data the bridges actually
/// store on `Thing` (the honesty rule — no invented groupings). Three shapes:
///   • a ranked-bars leaderboard (top senders, subreddits, artists, …),
///   • a distribution bar (a ticker's declared mood, how a social feed arrives),
///   • an image mosaic (a wall of the source's own thumbnails).
/// Each `make…` returns nil unless the source qualifies and enough real data
/// exists to say something — a near-empty overview simply doesn't render.
enum FeedInsight {

    // MARK: Leaderboard (ranked bars)

    struct LeaderRow: Identifiable {
        let id = UUID()
        let label: String
        /// Bar magnitude.
        let value: Int
        /// Right-aligned display ("23", "3.4h").
        let detail: String
    }
    struct Leaderboard {
        let title: String
        let subtitle: String
        let rows: [LeaderRow]
    }

    /// The bars a source leads with, and the stored field each ranks on.
    static func leaderboard(source: String, things: [Thing]) -> Leaderboard? {
        switch source {
        case "Reddit":
            return counted(things, title: "Your subreddits", unit: ("post", "posts"), key: redditGroup)
        case "Gmail", "iCloud Mail":
            return counted(things, title: "Who writes you", unit: ("message", "messages"), key: sender)
        case "Readwise", "Kindle":
            return counted(things, title: "Most highlighted", unit: ("highlight", "highlights"), key: book)
        case "Spotify", "Apple Music":
            return counted(things, title: "Your top artists", unit: ("track", "tracks"), key: artist)
        case "Raindrop":
            return counted(things, title: "Where you save from", unit: ("bookmark", "bookmarks"), key: domain)
        case "Substack":
            return counted(things, title: "Your publications", unit: ("post", "posts"), key: handle)
        // RSS names its publisher in the same `authorHandle` slot Substack and
        // Podcasts use (RSSIngest stamps the feed's title there), so "where my
        // reading comes from" is the identical read — it was simply never
        // wired (2026-07-22). A reader following one feed falls through to the
        // mosaic below, same as a Substack reader with one publication.
        case "RSS":
            return counted(things, title: "Your publishers", unit: ("story", "stories"), key: handle)
        case "Podcasts":
            return counted(things, title: "Your shows", unit: ("episode", "episodes"), key: handle)
        case "Steam":
            return steamPlaytime(things)
        default:
            return nil
        }
    }

    /// Count things by a grouping key, rank the top groups, format the subtitle
    /// from the honest total. Renders only with a few things across ≥2 groups —
    /// a one-bar chart claims a ranking it doesn't have.
    private static func counted(_ things: [Thing], title: String,
                                unit: (one: String, many: String),
                                key: (Thing) -> String?) -> Leaderboard? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        var total = 0
        for thing in things {
            guard let raw = key(thing)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            if counts[raw] == nil { order.append(raw) }
            counts[raw, default: 0] += 1
            total += 1
        }
        guard total >= 3, counts.count >= 2 else { return nil }
        let rows = order
            .sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }   // count desc, then name asc
            .prefix(6)
            .map { LeaderRow(label: $0, value: counts[$0]!, detail: "\(counts[$0]!)") }
        let subtitle = "\(total.formatted()) \(total == 1 ? unit.one : unit.many)"
        return Leaderboard(title: title, subtitle: subtitle, rows: Array(rows))
    }

    /// Steam ranks by the trailing-two-weeks hours baked into `content`
    /// ("· 3.4h past two weeks") — the only playtime the bridge stores.
    private static func steamPlaytime(_ things: [Thing]) -> Leaderboard? {
        var best: [String: Double] = [:]
        var order: [String] = []
        for thing in things {
            guard let hours = steamHours(thing.content), hours > 0 else { continue }
            let game = thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !game.isEmpty else { continue }
            if best[game] == nil { order.append(game) }
            best[game] = max(best[game] ?? 0, hours)
        }
        guard best.count >= 2 else { return nil }
        let rows = order
            .sorted { (best[$0]!, $1) > (best[$1]!, $0) }
            .prefix(6)
            .map { LeaderRow(label: $0, value: Int((best[$0]! * 10).rounded()),
                             detail: String(format: "%.1fh", best[$0]!)) }
        return Leaderboard(title: "Recently played", subtitle: "past two weeks", rows: Array(rows))
    }

    // MARK: Distribution (stacked bar)

    enum Tone { case positive, negative, neutral, accent, alt1, alt2 }
    struct Segment: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let tone: Tone
    }
    struct Distribution {
        let title: String
        let subtitle: String
        let segments: [Segment]
    }

    static func distribution(source: String, things: [Thing]) -> Distribution? {
        switch source {
        case "Stocktwits": return stocktwitsMood(things)
        default: return nil
        }
    }

    /// The declared mood of the posters on your tickers — Stocktwits stores each
    /// author's own Bullish / Bearish call as a tag. Neutral is the rest. It's
    /// the crowd's stated stance, never a prediction of ours.
    private static func stocktwitsMood(_ things: [Thing]) -> Distribution? {
        var bull = 0, bear = 0, neutral = 0
        for thing in things {
            if thing.tags.contains("Bullish") { bull += 1 }
            else if thing.tags.contains("Bearish") { bear += 1 }
            else { neutral += 1 }
        }
        let total = bull + bear + neutral
        // Needs a real split to mean anything — an all-neutral feed says nothing.
        guard total >= 4, (bull + bear) >= 2 else { return nil }
        let segments = [
            Segment(label: "Bullish", count: bull, tone: .positive),
            Segment(label: "Bearish", count: bear, tone: .negative),
            Segment(label: "Neutral", count: neutral, tone: .neutral),
        ].filter { $0.count > 0 }
        return Distribution(title: "The mood on your tickers",
                            subtitle: "\(total) \(total == 1 ? "post" : "posts")", segments: segments)
    }

    // MARK: Mosaic (thumbnail wall)

    struct Mosaic {
        let title: String
        let subtitle: String
        let urls: [String]
        /// The bridge glyph that stands in for a dead image.
        let fallback: String
    }

    static func mosaic(source: String, things: [Thing]) -> Mosaic? {
        let title: String
        let unit: (one: String, many: String)
        switch source {
        case "OpenSea":     title = "New drops";     unit = ("collection", "collections")
        case "Pinterest":   title = "Your pins";     unit = ("pin", "pins")
        case "Shopify":     title = "New arrivals";  unit = ("product", "products")
        case "YouTube":     title = "Latest uploads"; unit = ("video", "videos")
        // The media sources with stable art whose head could go missing
        // (2026-07-21, prd §164). Deals had NO head at all. Steam, Podcasts,
        // and Substack have leaderboards — which outrank the mosaic in the
        // dispatch order but refuse to render under two groups, so for
        // someone following a single show/publication/game these are the
        // fallback head where the feed previously led with nothing. Twitch
        // is EXCLUDED on purpose — its previewImageURL is a live stream
        // frame, perishable by the same honesty rule that keeps it off stale
        // rows; a mosaic of dead frames would claim streams are on. Twitch's
        // head-worthy fact is "live right now", which live-first ordering
        // already carries.
        case "Steam":       title = "Recently played"; unit = ("game", "games")
        case "Podcasts":    title = "Latest episodes"; unit = ("episode", "episodes")
        case "Substack":    title = "Latest posts";   unit = ("post", "posts")
        case "Deals":       title = "Fresh deals";    unit = ("deal", "deals")
        case "RSS":         title = "Latest stories"; unit = ("story", "stories")
        default: return nil
        }
        var urls: [String] = []
        var seen = Set<String>()
        for thing in things {
            guard let url = thing.previewImageURL, !url.isEmpty, seen.insert(url).inserted else { continue }
            urls.append(url)
            if urls.count >= 8 { break }
        }
        guard urls.count >= 4 else { return nil }
        let subtitle = "\(things.count.formatted()) \(things.count == 1 ? unit.one : unit.many)"
        return Mosaic(title: title, subtitle: subtitle, urls: urls, fallback: source)
    }

    // MARK: - Grouping keys (each reads a field the bridge really stores)

    /// A feed-follow item names its channel/subreddit/publication in
    /// `authorHandle` (FeedFollowBridges sets it); Reddit's older path leaves it
    /// nil, so fall back to the `r/<sub>` segment inside the permalink `content`.
    private static func redditGroup(_ t: Thing) -> String? {
        if let h = t.authorHandle, !h.isEmpty { return h }
        guard let r = t.content.range(of: #"/r/[^/\s?#]+"#, options: .regularExpression) else { return nil }
        return "r/" + t.content[r].dropFirst(3)
    }

    private static func handle(_ t: Thing) -> String? {
        t.authorHandle.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Mail stores the sender in `authorHandle` as "Name <addr>" or a bare
    /// address — prefer the display name, else the address inside the angles.
    private static func sender(_ t: Thing) -> String? {
        guard let raw = t.authorHandle?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        guard let lt = raw.firstIndex(of: "<") else { return raw }
        let name = raw[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        if !name.isEmpty { return String(name) }
        if let gt = raw.firstIndex(of: ">"), raw.index(after: lt) < gt {
            return String(raw[raw.index(after: lt)..<gt])
        }
        return raw
    }

    /// Readwise/Kindle put "Book — Author" in `content`; group by the book title.
    private static func book(_ t: Thing) -> String? {
        let c = t.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return nil }
        return c.components(separatedBy: " — ").first
    }

    /// Music stores "Song — Artist" in `title`; group by the primary artist.
    private static func artist(_ t: Thing) -> String? {
        let parts = t.title.components(separatedBy: " — ")
        guard parts.count >= 2, let credited = parts.last else { return nil }
        return credited.components(separatedBy: ", ").first?.trimmingCharacters(in: .whitespaces)
    }

    /// A bookmark's `content` is its URL; group by host, minus the "www.".
    private static func domain(_ t: Thing) -> String? {
        guard let host = URL(string: t.content)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Steam bakes the trailing-two-weeks hours into `content` as "· 3.4h …".
    private static func steamHours(_ content: String) -> Double? {
        guard let r = content.range(of: #"·\s*[0-9]+(\.[0-9]+)?h"#, options: .regularExpression) else { return nil }
        return Double(content[r].filter { $0.isNumber || $0 == "." })
    }
}
