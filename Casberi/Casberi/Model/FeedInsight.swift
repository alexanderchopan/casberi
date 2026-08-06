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
            return savedAuthors(things)
        // TikTok is the same shape as Instagram and reads the same field, but
        // it earns its handles differently: Instagram's export names the author
        // of every save, while TikTok's names nobody at all — `authorHandle`
        // arrives later, from the oEmbed pass that gives a saved video its face
        // (`TikTokImport.fetchFaces`). So this board is empty until that has
        // run, and `counted` declining on too few groups is exactly the right
        // behaviour rather than something to work around.
        case "TikTok":
            return savedAuthors(things)
        // X, 2026-08-05 — the same board as Instagram and TikTok, reached the
        // TikTok way: the archive names no author for a liked post, so the
        // handles arrive from `XArchiveImport.fetchFaces` and this board is
        // empty until that pass has run. It only ever renders the "Liked" arm,
        // since an X archive has no saves to lead with — `savedAuthors` falls
        // through to it by construction rather than by a special case here.
        case "X":
            return savedAuthors(things)
        // The wallet-riding seats, 2026-08-05 (prd §311). Each earns a room
        // and each led with nothing until now.
        //
        // Peer ranks on the funding RAIL, which `PeerBridge` has always
        // resolved (it is what makes a title say "with Venmo") and, until this
        // date, only ever interpolated into a string. Stamped on
        // `authorHandle` now — the same groupable slot Instagram and X rank
        // their authors in — so this is `counted` unchanged.
        case "Peer":
            return counted(things, title: "How you fund",
                           unit: ("trade", "trades"), key: handle)
        case "Gnosis Pay":
            return cardMonths(things, title: "What the card spent")
        case "ether.fi":
            return cardMonths(things, title: "What the card spent")
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

    /// Whose posts fill your Instagram, or your TikTok (2026-07-31) — the single most
    /// surprising fact, because nobody knows their own most-saved account.
    ///
    /// SAVES AND LIKES ARE NOT SUMMED. They're different acts — a save is a
    /// deliberate keep, a like is a reaction in passing — and one ranking over
    /// both would be a number with no meaning. Saves lead; an export with too
    /// few of them falls back to likes and SAYS SO in the title, rather than
    /// quietly changing what the bars mean. Only the `authorHandle` the
    /// importer stamped is read, never the "@handle" title, so the rare entry
    /// the export gave no author simply doesn't rank.
    /// Shared with TikTok since 2026-08-02 — the two rooms differ in where the
    /// handle comes from (Instagram's export names it, TikTok's is learned from
    /// the oEmbed face pass) and not at all in how it ranks.
    private static func savedAuthors(_ things: [Thing]) -> Leaderboard? {
        func board(_ tag: String, title: String,
                   unit: (String, String)) -> Leaderboard? {
            counted(things.filter { $0.tags.contains(tag) },
                    title: title, unit: unit, key: handle)
        }
        return board("Saved", title: "Who you save most", unit: ("save", "saves"))
            ?? board("Liked", title: "Whose posts you like", unit: ("like", "likes"))
    }

    /// What a card actually spent, month by month (2026-08-05, prd §311).
    ///
    /// THE CEILING IS THE POINT, and it is why this is a shape of its own
    /// rather than a leaderboard. The merchant, the MCC and the original
    /// currency never reach the chain — that is stated in both card bridges'
    /// own docs and it is permanent — so this room can honestly say WHEN and
    /// HOW MUCH and can never say WHERE. A "top merchants" board is the one
    /// card card readers expect and the one thing this data cannot support;
    /// building it would mean inventing the labels.
    ///
    /// Reads `priceValue`, which both card bridges stamp precisely so an
    /// amount can be re-formatted and compared. A row without one is left OUT
    /// rather than counted as zero — an unread amount is not a free purchase.
    static func cardMonths(_ things: [Thing], title: String) -> Leaderboard? {
        let calendar = Calendar.current
        var totals: [String: Double] = [:]
        var order: [String] = []
        var currency: String?
        var spent = 0.0
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        for thing in things {
            guard thing.kind == .transaction, let value = thing.priceValue, value > 0
            else { continue }
            // One currency only. A card settles in whichever stablecoin the
            // account holds, and summing EUR into USD to make a bar longer is
            // the kind of quiet arithmetic §83 bans; the majority currency
            // wins and the rest simply don't count toward these bars.
            if currency == nil { currency = thing.priceCurrency }
            guard thing.priceCurrency == currency else { continue }
            let label = formatter.string(from: thing.capturedAt)
            if totals[label] == nil { order.append(label) }
            totals[label, default: 0] += value
            spent += value
        }
        guard totals.count >= 2 else { return nil }
        let subtitle = PriceFormat.string(spent, currency: currency)
            .map { String(localized: "\($0) in \(totals.count) months") }
            ?? String(localized: "\(totals.count) months")
        // Newest first — a card statement reads backwards from now.
        let ranked = order.reversed().prefix(12).map { label in
            LeaderRow(label: label, value: Int((totals[label] ?? 0).rounded()),
                      detail: PriceFormat.string(totals[label] ?? 0, currency: currency)
                          ?? WalletIngest.format(totals[label] ?? 0))
        }
        return Leaderboard(title: title, subtitle: subtitle, rows: Array(ranked))
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
