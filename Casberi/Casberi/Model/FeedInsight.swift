import Foundation

/// The per-source feed overviews, derived ONLY from data the bridges actually
/// store on `Thing` (the honesty rule — no invented groupings). Two shapes:
///   • a distribution bar (a ticker's declared mood, how a social feed arrives),
///   • an image mosaic (a wall of the source's own thumbnails),
/// plus the OCR topic map below them.
/// Each `make…` returns nil unless the source qualifies and enough real data
/// exists to say something — a near-empty overview simply doesn't render.
///
/// **THERE WAS A THIRD, AND IT IS DELETED (prd §721, 2026-09-14.)** A
/// ranked-bars leaderboard headed about fifteen rooms — "Your publishers",
/// "Your top artists", "Who writes you", "Your subreddits" — and the user
/// ruled it out entirely: *"i don't think it really matters … seems like we
/// were trying to add visualization data just for the sake of it."* Gone with
/// it: `Leaderboard`, `LeaderRow`, its `.publisher`/`.writer` `Scope` (§455's
/// tap-a-bar-to-narrow control), every builder that fed it (`counted`,
/// `bylines`, `cardMonths`, `savedAuthors`, `snapchatConversations`,
/// `xBoard`, `steamPlaytime`, `ranked`), every grouping key that existed only
/// to rank (`redditGroup`, `handle`, `writer`, `sender`, `book`, `artist`,
/// `merchant`, `domain`, `steamHours`, `repliedTo`), and `LeaderboardHero`.
/// A room that led with a board now falls through this same chain to whatever
/// ranks next — a distribution, a mosaic, its year heatmap — or draws no head
/// at all, which is `RoomFigure`'s own standing ruling: an absent figure beats
/// one that answers nothing.
enum FeedInsight {

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
        case "Privacy Pools": return shieldedReview(things)
        default: return nil
        }
    }

    /// Where your shielded deposits sit in 0xBow's review (2026-08-05,
    /// prd §311) — the room's standing question, and the only one it has.
    ///
    /// A Privacy Pools room is deposits and status flips, and the flip is the
    /// whole product: a deposit is not spendable privately until the ASP
    /// clears it. Until now that state existed only inside an alert's title
    /// text and a UserDefaults watchlist, so the room could not answer "how
    /// much is still waiting" — the one thing a person with money in a pool
    /// wants to know at a glance.
    ///
    /// Reads the state TAG `PrivacyPoolsBridge.retag` maintains, never the
    /// title's words. A deposit carries exactly one state tag at a time, so a
    /// deposit that cleared can't be counted twice.
    ///
    /// COUNTS, not amounts. The room's rows carry their amounts as text in a
    /// dozen different tokens, and summing across ETH and USDC to make a
    /// segment longer would be arithmetic nobody asked for (§83). How many
    /// deposits are in each state is a fact; their total is not one number.
    private static func shieldedReview(_ things: [Thing]) -> Distribution? {
        var counts: [String: Int] = [:]
        for thing in things where thing.tags.contains("Shielded") {
            for state in ["Pending", "Cleared", "Declined", "Needs proof"]
            where thing.tags.contains(state) {
                counts[state, default: 0] += 1
            }
        }
        let total = counts.values.reduce(0, +)
        guard total >= 2 else { return nil }
        // Fixed order, so the bar reads as a JOURNEY (waiting → cleared) and
        // doesn't reshuffle itself every time one deposit changes state.
        // The tones carry the meaning: waiting is neutral, needing you is the
        // one that should catch an eye, cleared is the good outcome.
        let order: [(state: String, tone: Tone)] = [
            ("Pending", .neutral), ("Needs proof", .negative),
            ("Cleared", .positive), ("Declined", .alt1),
        ]
        let segments = order.compactMap { entry -> Segment? in
            guard let n = counts[entry.state], n > 0 else { return nil }
            return Segment(label: entry.state, count: n, tone: entry.tone)
        }
        guard segments.count >= 2 else { return nil }
        let waiting = (counts["Pending"] ?? 0) + (counts["Needs proof"] ?? 0)
        let subtitle = waiting > 0
            ? String(localized: "\(waiting) of \(total) still waiting to clear")
            : String(localized: "\(total) deposits, all reviewed")
        return Distribution(title: "Where your deposits stand",
                            subtitle: subtitle, segments: segments)
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
    ///
    /// POSTS ONLY (2026-08-12). `StockWatch.watch` lands the watch itself as
    /// a `.link` thing in this same room — the watch IS the thing, no
    /// separate store — and counting those tallied each watched TICKER as a
    /// neutral POST: the subtitle over-reported ("11 posts" for 8), and every
    /// watch dragged the neutral segment up, so a room whose posters were
    /// evenly split read as mostly undecided. Wrong in the real app for
    /// anyone with a watchlist, and invisible until the demo grew one.
    private static func stocktwitsMood(_ things: [Thing]) -> Distribution? {
        var bull = 0, bear = 0, neutral = 0
        for thing in things where thing.kind == .chat {
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
        // A SET since 2026-08-05 (prd §309), not one kind. TikTok was declined
        // a map entirely because its writing spans two — captions ride the
        // `.link` rows of your own videos, comments are `.note`s — and a map
        // over one kind would have covered half the writing while claiming all
        // of it. `belongs` then narrows within those kinds, which is what keeps
        // somebody else's video out of a map about your words.
        let kinds: Set<ThingKind>
        // What the count in the subtitle COUNTS, beyond the kind. Photos and
        // Instagram never needed this (their kind IS the membership), but a
        // Files room holds PDFs and text files under the same `.file` kind as
        // its images, and the map only ever reads the images' OCR — so the
        // subtitle counts images alone, or "214 files" would claim text the
        // map never looked at.
        var belongs: (Thing) -> Bool = { _ in true }
        switch source {
        case "Photos":
            title = "What you screenshot"; unit = ("screenshot", "screenshots"); kinds = [.screenshot]
        case "Instagram":
            title = "What you write about"; unit = ("post", "posts"); kinds = [.note]
            // A WORDLESS picture post is a `.note` too since 2026-08-18 (prd
            // §395) and has, by definition, nothing to say — so it is excluded
            // rather than counted into the "N of M" denominator this subtitle
            // prints. Left in, a room of photographs would read as a map
            // covering a third of what you wrote, which is a statement about
            // our own parser rather than about the person.
            belongs = { !$0.tags.contains("Photo") }
        // X, 2026-08-05. Instagram's split exactly, and the strongest corpus in
        // the app for this card: an X archive's `.note` half is years of the
        // person's own sentences, written to be read, with none of a caption's
        // brevity. The `.link` half is posts they liked — somebody else's
        // words — so it is left out for the same reason Instagram leaves out
        // its saves, and TikTok gets no map at all because ITS writing spans
        // both kinds and a map over one would cover half of it silently.
        case "X":
            title = "What you post about"; unit = ("post", "posts"); kinds = [.note]
        // TikTok, 2026-08-05 — the gap the comment above used to describe as
        // permanent. Its writing really does span two kinds, and the fix is to
        // map BOTH and narrow by tag: your own videos' captions carry the
        // `Post` tag on a `.link` row, your comments carry `Comment` on a
        // `.note`. Saves and likes are `.link` rows too and are excluded by
        // exactly that test — they are somebody else's videos, the same reason
        // Instagram's map leaves out its saves.
        case "TikTok":
            title = "What you write about"; unit = ("post", "posts")
            kinds = [.link, .note]
            belongs = { $0.tags.contains("Post") || $0.tags.contains("Comment") }
        // Obsidian, 2026-08-06. The room this card was always most obviously
        // for, and the last one to get it: a vault is nothing BUT the person's
        // own writing, one kind, no import receipt to exclude and no
        // somebody-else half to leave out. Its absence is why the vault room
        // led with a year heatmap — which answers WHEN, the weakest lead in
        // the chain — over the years of subjects sitting under it.
        case "Obsidian":
            title = "What you write about"; unit = ("note", "notes"); kinds = [.note]
        // YouTube, 2026-08-06 — the first room here mapping words the person
        // did NOT write, which is the whole of the title's job: these are the
        // descriptions the channels wrote for their own uploads, so the card
        // says whose subjects it is ranking. "What you write about" over
        // somebody else's copy would be §83 in one word, and the room's other
        // heads (a wall of stills, a count of uploads) can't say it at all.
        //
        // One kind, no `belongs`: every row a followed channel lands is a
        // `.link`, and a Short is a video like any other — nothing in this
        // room belongs to anybody but the channels.
        // The two journal rooms, 2026-08-17 (prd §398). Obsidian's case exactly
        // — one kind, the person's own writing — and the pair that waited
        // longest for it: until this pass the only thing either room could say
        // about years of somebody's diary was WHICH DAYS they wrote on.
        //
        // "write", not "post" or "capture": these are the only two rooms in the
        // app where that verb is unambiguously true of every row.
        case "Day One", "Apple Journal":
            title = "What you write about"; unit = ("entry", "entries"); kinds = [.note]
        case "YouTube":
            title = "What your channels cover"; unit = ("video", "videos"); kinds = [.link]
        // The three chat imports, 2026-08-08. The rooms that had the least to
        // lead with — no pictures, no authors, no counts worth ranking, and
        // (until the transcript landed) no text either, so they led with a
        // year heatmap over a corpus of subjects.
        //
        // TITLE, and it is a §83 question rather than a wording one. A
        // ChatGPT or Claude transcript is BOTH voices: the person's asks and
        // the model's answers, which are the longer half by far. "What you ask
        // about" over that would credit the person with words they didn't
        // write, which is exactly what YouTube's card refuses to do one case
        // above. So these two say what they really rank — what the
        // conversations were about — and only Gemini, whose export carries the
        // asks and nothing else (see `GeminiImport.turns`), can honestly say
        // "ask".
        //
        // One kind, no `belongs`: every row in these rooms is a `.chat` the
        // person had, there is no somebody-else half to leave out, and the
        // import receipt is excluded by the loop below.
        case "ChatGPT", "Claude":
            title = "What your chats are about"; unit = ("chat", "chats"); kinds = [.chat]
        case "Gemini":
            title = "What you ask about"; unit = ("prompt", "prompts"); kinds = [.chat]
        case "Files":
            // The connected folder's images, read the Photos way (2026-08-02):
            // `FilesIngest.heal` already OCRs them into `content` and
            // `ScreenshotTopics.healTopics` lifts the same deterministic
            // terms. "Images", not "screenshots" — a folder makes no claim
            // about where its pictures came from.
            title = "What your images say"; unit = ("image", "images"); kinds = [.file]
            belongs = { FilesIngest.isImageRef($0.sourceRef) }
        default:
            return nil
        }

        var perShot: [[String]] = []
        var total = 0
        for thing in things where kinds.contains(thing.kind) && belongs(thing) && !Corpus.isImportReceipt(thing) {
            total += 1
            if !thing.ocrTopics.isEmpty { perShot.append(thing.ocrTopics) }
        }
        // Needs a real spread of items that read as SOMETHING — a couple of
        // them across one recurring term isn't a portrait.
        guard perShot.count >= 6 else { return nil }
        let ranked = ScreenshotTopics.cells(perShot: perShot)
        guard ranked.count >= 2 else { return nil }
        // WHAT THE CELLS ACTUALLY COVER (2026-08-06). The subtitle used to
        // count every row in the room while the cells only ever hold the rows
        // credited to a top-six recurring term — fine for a screenshot library,
        // where nearly every shot carries one, and a straight misstatement for
        // an archive: "3,500 posts" sat above six cells summing to a few
        // hundred, so the card read as a partition of the room when it is a
        // partition of the part we could read. Says "N of M" only when the two
        // really differ, so a map that does cover its room is unchanged.
        let covered = ranked.reduce(0) { $0 + $1.count }
        let noun = total == 1 ? unit.one : unit.many
        let subtitle = covered < total
            ? String(localized: "\(covered.formatted()) of \(total.formatted()) \(noun)")
            : "\(total.formatted()) \(noun)"
        return TopicMap(title: title, subtitle: subtitle,
                        cells: ranked.map { TopicMap.Cell(label: $0.label, count: $0.count) })
    }
}
