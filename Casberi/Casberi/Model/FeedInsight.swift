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
        case "Snapchat":
            return snapchatConversations(things)
        case "Instagram":
            return instagramAuthors(things)
        default:
            return nil
        }
    }

    /// Who you actually talk to on Snapchat (2026-07-31) — the saved
    /// conversations ranked by how many messages each really holds.
    ///
    /// It ranks on `messageCount`, a field the importer stamps, and NOT on the
    /// stored transcript: `content` keeps only the newest `lineCap` lines
    /// inside a byte ceiling, so counting the lines a row holds would flatten
    /// a ten-year friendship onto a week-old one and call it a ranking. A
    /// conversation whose count is nil (landed before the field existed, and
    /// not yet repaired by a re-import) is left OUT rather than counted as
    /// zero — an unknown length is not a short one.
    private static func snapchatConversations(_ things: [Thing]) -> Leaderboard? {
        var best: [String: Int] = [:]
        var order: [String] = []
        var total = 0
        for thing in things where thing.kind == .chat {
            guard let count = thing.messageCount, count > 0 else { continue }
            let who = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !who.isEmpty else { continue }
            if best[who] == nil { order.append(who) }
            // A handle appears once per export, but max() rather than += so a
            // re-import can never double a conversation's length.
            best[who] = max(best[who] ?? 0, count)
            total += count
        }
        guard best.count >= 2 else { return nil }
        let subtitle = "\(total.formatted()) \(total == 1 ? "saved message" : "saved messages")"
        return Leaderboard(title: "Who you snap with", subtitle: subtitle,
                           rows: ranked(order, best) { ($0, $0.formatted()) })
    }

    /// Whose posts fill your Instagram (2026-07-31) — the export's single most
    /// surprising fact, because nobody knows their own most-saved account.
    ///
    /// SAVES AND LIKES ARE NOT SUMMED. They're different acts — a save is a
    /// deliberate keep, a like is a reaction in passing — and one ranking over
    /// both would be a number with no meaning. Saves lead; an export with too
    /// few of them falls back to likes and SAYS SO in the title, rather than
    /// quietly changing what the bars mean. Only the `authorHandle` the
    /// importer stamped is read, never the "@handle" title, so the rare entry
    /// the export gave no author simply doesn't rank.
    private static func instagramAuthors(_ things: [Thing]) -> Leaderboard? {
        func board(_ tag: String, title: String,
                   unit: (String, String)) -> Leaderboard? {
            counted(things.filter { $0.tags.contains(tag) },
                    title: title, unit: unit, key: handle)
        }
        return board("Saved", title: "Who you save most", unit: ("save", "saves"))
            ?? board("Liked", title: "Whose posts you like", unit: ("like", "likes"))
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
        let subtitle = "\(total.formatted()) \(total == 1 ? unit.one : unit.many)"
        return Leaderboard(title: title, subtitle: subtitle,
                           rows: ranked(order, counts) { ($0, "\($0)") })
    }

    /// The shape every board ends in: biggest first, ties broken by name so the
    /// order is deterministic across launches, capped at what the card draws.
    /// `bar` turns a group's measured value into the bar's magnitude and the
    /// text printed beside it — the two differ for playtime (hours scaled to an
    /// Int, printed as "3.4h") and coincide for a plain count, which is the
    /// only reason each board used to spell this out for itself.
    private static func ranked<V: Comparable>(_ order: [String], _ values: [String: V],
                                              bar: (V) -> (Int, String)) -> [LeaderRow] {
        order
            .sorted { (values[$0]!, $1) > (values[$1]!, $0) }   // value desc, then name asc
            .prefix(6)
            .map { name in
                let (value, detail) = bar(values[name]!)
                return LeaderRow(label: name, value: value, detail: detail)
            }
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
        return Leaderboard(title: "Recently played", subtitle: "past two weeks",
                           rows: ranked(order, best) {
                               (Int(($0 * 10).rounded()), String(format: "%.1fh", $0))
                           })
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
        case "Linear":     return linearWorkload(things)
        default: return nil
        }
    }

    /// Where your assigned Linear work sits — the tracker's standing question
    /// (prd §164's "mood" tier; 2026-07-22). Deliberately NOT the GitHub
    /// heatmap treatment it superficially resembles: Linear's only date is
    /// `updatedAt`, which moves when ANYONE touches an issue you're assigned,
    /// so a contribution-style grid would chart your teammates' activity while
    /// looking like your own. State is a fact the API states outright.
    ///
    /// Reads `mark`, which `TokenBridges.linearMark` maps from Linear's own
    /// state type — so an issue whose state we couldn't classify counts in
    /// neither bucket rather than being guessed into one.
    private static func linearWorkload(_ things: [Thing]) -> Distribution? {
        var todo = 0, doing = 0, done = 0
        for thing in things {
            switch thing.mark {
            case .todo:  todo += 1
            case .doing: doing += 1
            case .done:  done += 1
            default:     break
            }
        }
        let total = todo + doing + done
        // Needs enough classified issues to describe a workload — and at
        // least one still open, or this is a finished list, not a state of
        // play. A corpus synced before the state field existed marks nothing,
        // so it correctly draws no card until the next sync reconciles it.
        guard total >= 4, (todo + doing) >= 1 else { return nil }
        let segments = [
            Segment(label: "In progress", count: doing, tone: .positive),
            Segment(label: "Todo", count: todo, tone: .neutral),
            Segment(label: "Done", count: done, tone: .neutral),
        ].filter { $0.count > 0 }
        return Distribution(title: "Where your work sits",
                            subtitle: "\(total) \(total == 1 ? "issue" : "issues")",
                            segments: segments)
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
        /// One piece of art on the shelf, carrying the same age wash its ROW
        /// wears below (prd §219). Without this the head painted the newest
        /// items at full color while the rows beneath showed those identical
        /// images drained — one screen telling two stories about the same
        /// picture, which reads as a bug rather than a design (caught on the
        /// sim, 2026-07-25, against a Pinterest feed of 2012 pins).
        struct Tile {
            let url: String
            let freshness: Double
        }
        let title: String
        let subtitle: String
        let tiles: [Tile]
        /// The bridge glyph that stands in for a dead image.
        let fallback: String
        /// The medium's own proportions (prd §219), or nil for a source whose
        /// art has no inherent shape — the shelf then stays the square grid.
        /// The renderer reads the tile aspect and the across-count from here,
        /// so "texture of what's arriving" is told in the medium's language
        /// instead of five media flattened into one grid of squares.
        let art: MediaShape.Art?
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
        let art = MediaShape.art(for: source)
        var tiles: [Mosaic.Tile] = []
        var seen = Set<String>()
        for thing in things {
            guard let url = thing.previewImageURL, !url.isEmpty, seen.insert(url).inserted else { continue }
            // Only a declared medium decays — a source with no inherent art
            // shape keeps the neutral square grid it has always drawn, at
            // full color.
            tiles.append(Mosaic.Tile(
                url: url,
                freshness: art == nil ? 1 : MediaShape.freshness(of: thing.capturedAt)))
            if tiles.count >= 8 { break }
        }
        // A wide medium fills its shelf with fewer, larger tiles (two 16:9
        // frames, not eight), so it qualifies on fewer images than the square
        // grid needs — the bar is "enough to fill the shelf", which differs
        // per medium, not a fixed four.
        let needed = art.map { min(4, $0.shelf.columns * $0.shelf.maxRows) } ?? 4
        guard tiles.count >= needed else { return nil }
        let subtitle = "\(things.count.formatted()) \(things.count == 1 ? unit.one : unit.many)"
        return Mosaic(title: title, subtitle: subtitle, tiles: tiles, fallback: source, art: art)
    }

    // MARK: Topic map (OCR treemap)

    struct TopicMap {
        struct Cell: Identifiable {
            let id = UUID()
            let label: String
            let count: Int
        }
        let title: String
        let subtitle: String
        /// Largest first, capped at 6.
        let cells: [Cell]
    }

    /// The Photos feed's hero: a treemap of what the screenshots are ABOUT,
    /// built from the terms OCR already lifted onto each shot's `ocrTopics`
    /// (2026-07-30). It leads the Photos feed AHEAD of the calendar heatmap —
    /// `FeedHeatmap` still registers "Your capture year" for Photos, so when
    /// there isn't enough OCR text to say anything (a wordless library, or too
    /// few shots), this returns nil and the feed falls back to that heatmap
    /// gracefully rather than leading with nothing.
    ///
    /// A pure count over stored fields — no NLTagger here (that ran once at
    /// heal time); this is the same cheap arithmetic shape as `leaderboard`.
    static func topicMap(source: String, things: [Thing]) -> TopicMap? {
        // What the map is made of, per source. The extraction is the same
        // deterministic term reader either way (`ScreenshotTopics.terms`
        // stamped `ocrTopics` at heal time) — it never cared where the text
        // came from, only Photos had ever handed it any. Instagram's own
        // WRITING is the second corpus worth this treatment (2026-07-31): an
        // export's captions and comments are years of a person's own words,
        // and the room's other half (saves and likes) is somebody else's, so
        // the map is deliberately built from the `.note` half alone — "what
        // you write about" would be a lie if it counted what you tapped.
        let title: String
        let unit: (one: String, many: String)
        let kind: ThingKind
        switch source {
        case "Photos":
            title = "What you screenshot"; unit = ("screenshot", "screenshots"); kind = .screenshot
        case "Instagram":
            title = "What you write about"; unit = ("post", "posts"); kind = .note
        default:
            return nil
        }

        var perShot: [[String]] = []
        var total = 0
        for thing in things where thing.kind == kind && !Corpus.isImportReceipt(thing) {
            total += 1
            if !thing.ocrTopics.isEmpty { perShot.append(thing.ocrTopics) }
        }
        // Needs a real spread of items that read as SOMETHING — a couple of
        // them across one recurring term isn't a portrait.
        guard perShot.count >= 6 else { return nil }
        let ranked = ScreenshotTopics.cells(perShot: perShot)
        guard ranked.count >= 2 else { return nil }
        let subtitle = "\(total.formatted()) \(total == 1 ? unit.one : unit.many)"
        return TopicMap(title: title, subtitle: subtitle,
                        cells: ranked.map { TopicMap.Cell(label: $0.label, count: $0.count) })
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
