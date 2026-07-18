import Foundation
import SwiftData

/// Authors the Home composition document from the live corpus. In M2's server
/// half the model authors this per moment through /compose; until then this
/// local author produces the same document shape from the same facts, and the
/// engine streams it identically — swapping the source later changes no visuals.
///
/// Voice constraints (Home spec): themes and content, no obligations. (The
/// standalone "Coming up" card was retired 2026-07-18 — the intelligence is one
/// card now, the "Noticed" line; dated events/reminders read off their own
/// source tiles on the board instead.) Everything on the board keeps the
/// no-obligations voice. Tile sublines read content, not status. Hero: one
/// synthesis statement, facts
/// only, priority project movement > pending decision > imminent event >
/// bridge arrival. One layout every day (2026-07-12): the weekday-triggered
/// "Your week, banked" recap and the morning/evening split were removed — the
/// screen shouldn't change shape by the clock, and the week recap lives behind
/// the composer's "What's this week?" ask, a question you pose, not a mode.
enum HomeComposition {

    /// A composed document plus which of its root-level refs are board
    /// MODULES (prd 58, Goal 1) — pinned things, a wallet's holdings map,
    /// "What's going on". Everything else at root (the cover, the quiet-day
    /// invite, the pin coach line) is fixed furniture, not a card the person
    /// drags. HomeScreen reorders only within `boardRefs`.
    struct Document {
        let lines: [String]
        let boardRefs: [String]
        /// The STABLE persistence key for each board ref whose key isn't the ref
        /// itself — `appTileN → app:<source>`, `walletMapN → wallet:<label>`.
        /// Composed here (where the source/label is known) rather than re-derived
        /// from the rendered element, because on a streamed cold-launch compose
        /// the elements aren't parsed yet when the board reads its saved order —
        /// so a `stream.els`-based key would miss and the arrangement would reset
        /// (fix 2026-07-13). Refs absent here key by themselves (media shelves,
        /// the map).
        var boardKeys: [String: String] = [:]
    }

    @MainActor
    static func compose(things: [Thing],
                        walletHoldings: [WalletIngest.HoldingsGroup] = [],
                        walletCombined: WalletIngest.HoldingsGroup? = nil,
                        walletNFTs: [WalletIngest.NFTGroup] = [],
                        walletPending: Bool = false,
                        walletUnreachable: Bool = false,
                        insight: String? = nil,
                        insightThing: String? = nil) -> Document {
        let projects = projectClusters(things: things)
        return daily(things: things, projects: projects, walletHoldings: walletHoldings,
                     walletCombined: walletCombined,
                     walletNFTs: walletNFTs, walletPending: walletPending,
                     walletUnreachable: walletUnreachable, insight: insight,
                     insightThing: insightThing)
    }

    /// True when nothing has landed today — the composition acknowledges the
    /// quiet instead of pretending motion (voice: facts, no obligations).
    private static func isQuietDay(_ things: [Thing]) -> Bool {
        !things.isEmpty && !things.contains { Calendar.current.isDateInToday($0.capturedAt) }
    }

    // MARK: - Documents

    @MainActor
    private static func daily(things: [Thing], projects: [Cluster], walletHoldings: [WalletIngest.HoldingsGroup] = [],
                                     walletCombined: WalletIngest.HoldingsGroup? = nil,
                                     walletNFTs: [WalletIngest.NFTGroup] = [],
                                     walletPending: Bool = false,
                                     walletUnreachable: Bool = false,
                                     insight: String? = nil,
                                     insightThing: String? = nil) -> Document {
        var doc: [String] = []
        var rootRefs: [String] = []
        var boardRefs: [String] = []
        var boardKeys: [String: String] = [:]

        // The COVER (H7) replaces the sheet-card hero: the day's newest image
        // thing when one landed (this week as the fallback image), else the
        // quiet 140pt cover carrying the same Hero content and priority rules.
        // The doc only names facts; the renderer owns image, bleed, fallbacks.
        doc.append(cover(things: things))
        rootRefs.append("cover")

        // The intelligence is ONE card (user 2026-07-18): "Just landed", "While
        // you were away", and "Noticed" all convey what's new / what the app
        // noticed, so they share ONE blue card instead of a cover hero plus two
        // synthesis cards. Three eyebrow-and-line sections in one `Insight`:
        //   1. Just landed — the newest thing that ACTUALLY landed (capturedAt
        //      at or before now; a future calendar event isn't "just landed",
        //      it surfaces in its own tile). Tappable — opens the thing (arg 6).
        //   2. While you were away — the firehose-excluded read of what landed
        //      since the last visit.
        //   3. Noticed — the on-device model's one genuine cross-thing
        //      connection (prd §36c reopened; the model may DECLINE, so it's
        //      only ever a real observation).
        // Each section is skipped when its line is empty; the card is omitted
        // only when all three are. "Coming up" stays retired (its dated items
        // read off their own source tiles). Fixed furniture like the cover, NOT
        // a board module — no size pin, no remove badge.
        // ONE quiet paragraph (user 2026-07-18, second pass: three mini
        // sections "haven't earned that space"): just-landed + what arrived
        // while away + the model's connection compose into a single flowing
        // text under one "Noticed" eyebrow, each sentence skipped when it has
        // nothing to say, the card omitted when none do. One tap — the most
        // specific door available: the thing the model's connection ran
        // through (`insightThing`), else what just landed, else the feed
        // (whose "New since" divider marks the away window).
        // Firehose-excluded like every aggregate read (§119): a token-watch
        // refresh re-landing "dogwifhat · $WIF" isn't the day's headline. And
        // no calendar EVENTS: "Just landed: Team standup" reads as news about
        // a meeting that was merely synced — scheduled things belong to the
        // Calendar row, not the landed slot.
        let landed = things.first {
            $0.kind != .approval && $0.kind != .event
                && !firehoseSources.contains($0.source) && $0.capturedAt <= .now
        }
        let landedSentence = landed.map { String(localized: "Just landed: \($0.title).") } ?? ""
        let away = awayLine(things)
        let noticed = insight ?? ""
        let paragraph = [landedSentence, away, noticed]
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") || $0.hasSuffix("!") || $0.hasSuffix("?") ? $0 : $0 + "." }
            .joined(separator: " ")
        if !paragraph.isEmpty {
            let openID = insightThing ?? (landed?.id.uuidString ?? "")
            let feedFallback = openID.isEmpty && !away.isEmpty ? "feed" : ""
            doc.append("insight = Insight(\(q(paragraph)), \(q("")), \(q(openID)), \(q(feedFallback)))")
            rootRefs.append("insight")
        }

        // A quiet day's slot invites more apps (2026-07-10, user — the
        // berry said quiet twice under the quiet cover and did nothing).
        if isQuietDay(things) {
            doc.append("invite = AppsInvite(\(q(String(localized: "Connect another app"))), \(q(String(localized: "More of your day lands by itself."))))")
            rootRefs.append("invite")
        }

        // Pinned apps — the sources the person chose to keep in view, ahead of
        // the map (ruling 2026-07-09): a deliberate choice outranks an automatic
        // clustering, and it shouldn't cost a scroll to reach. Every connected
        // source is one row now (`appendPinnedApps`) — image sources included,
        // their peek a thumbnail filmstrip (2026-07-18: the media shelf-card
        // retired; a row carries the medium-native peek). The Wallet is a row
        // too (its total + top holdings); its treemap and NFT strips live ONLY
        // on the Wallet feed now (user 2026-07-18), so Home is uniformly rows.
        appendPinnedApps(things, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs, boardKeys: &boardKeys)
        appendWalletHoldings(walletHoldings, combined: walletCombined, pending: walletPending, unreachable: walletUnreachable, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs, boardKeys: &boardKeys)

        // Where the map belongs even when it didn't compose yet — the starter
        // preview slots in here, not at the tail.
        let mapSlot = rootRefs.count
        // Projects — an interactive treemap: magnitude fill, tap opens the
        // project. Chips were tried and reverted same day (2026-07-10).
        // The map is the on-device intelligence's THEMES view now, not a source
        // tally (auto-pin tune, user 2026-07-18): every connected source is its
        // own board tile, so a source-clustered map just repeats them. The map
        // earns its place only when it can show what the tiles can't — projects,
        // the cross-source themes your things are about. When no projects have
        // formed yet, there's no map (the tiles carry the screen); it returns
        // the moment a theme does. The old "By app" fallback map is retired.
        if !projects.isEmpty {
            let items = projects.prefix(6).map { "\($0.name) \($0.things.count)" }
            // "Themes" (2026-07-17): the vague, conversational "What's going on"
            // didn't say what this section IS — the cross-app THREADS your
            // things are about, a different lens from the per-app rows above
            // (which is why it's a treemap, not a row). The plain name reads as
            // that distinct lens, matching the app rows' own name-what-it-is.
            doc.append("map = TagMap(\(q(String(localized: "Themes"))), null, [\(items.joined(separator: ", "))])")
            rootRefs.append("map")
            boardRefs.append("map")
        }
        appendStarterPreviews(things: things,
                              hasMap: rootRefs.contains("map"),
                              mapSlot: mapSlot, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)

        doc.insert("root = Stack([\(rootRefs.joined(separator: ", "))])", at: 0)
        return Document(lines: doc, boardRefs: boardRefs, boardKeys: boardKeys)
    }

    /// The empty state previews the real modules — the muted map shows the
    /// SHAPE of home and says plainly that connecting apps fills it.
    /// Preview, not fake data: kind names, no counts, nothing to tap.
    static let empty = Document(lines: [
        "root = Stack([hero, map])",
        "hero = Hero(\(q(String(localized: "Getting started"))), \(q(String(localized: "Your home builds itself"))), \(q(String(localized: "Connect an app or capture one thing - what lands composes this screen."))))",
        previewMapLine,
    ], boardRefs: [])

    /// The preview module, shared by the empty doc and the sparse-corpus path.
    private static let previewMapLine =
        "map = TagMapPreview(\(q(String(localized: "Themes"))), \(q(String(localized: "Your things map here as they land"))), [Links, Notes, Events, Mail, Screenshots])"

    /// A corpus this small hasn't earned real modules yet — one connected app
    /// or a first capture. The previews stay alongside the real rows so the
    /// screen shows where it's going instead of trailing off.
    private static func isSparse(_ things: [Thing]) -> Bool { things.count < 8 }

    /// Appends the preview map when the real one didn't compose. `mapSlot`
    /// is where a real map would have landed in `rootRefs` (right after
    /// cover/quiet/insight) — the preview takes that slot too, instead of
    /// trailing behind pinned content composed after it.
    private static func appendStarterPreviews(things: [Thing], hasMap: Bool, mapSlot: Int,
                                              to doc: inout [String], rootRefs: inout [String],
                                              boardRefs: inout [String]) {
        guard isSparse(things), !hasMap else { return }
        doc.append(previewMapLine)
        rootRefs.insert("map", at: mapSlot)
        // The preview isn't tappable (no real modules exist yet), so it
        // isn't a board module either — nothing to drag before things land.
    }

    // MARK: - Derivations

    struct Cluster {
        let name: String
        let things: [Thing]
    }

    /// Until tags form, the map speaks in APPS: real things clustered by
    /// source (min 2, "You" included). Honest for a fresh corpus — bridge
    /// things arrive untagged, and a real user's Home earned no map at all.
    static func sourceClusters(things: [Thing]) -> [Cluster] {
        var buckets: [String: [Thing]] = [:]
        for thing in things { buckets[thing.source, default: []].append(thing) }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { Cluster(name: $0.key, things: $0.value) }
            .sorted {
                $0.things.count != $1.things.count
                    ? $0.things.count > $1.things.count
                    : $0.name < $1.name
            }
    }

    /// A project is a computed cluster; membership rides a tag (brief §3).
    static func projectClusters(things: [Thing]) -> [Cluster] {
        let typeTags = Set(ThingKind.allCases.map { $0.typeTag.lowercased() })
        var buckets: [String: [Thing]] = [:]
        for thing in things {
            for tag in thing.tags where !typeTags.contains(tag.lowercased()) {
                buckets[tag, default: []].append(thing)
            }
        }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { Cluster(name: $0.key, things: $0.value) }
            .sorted {
                // Magnitude, then name — stable. (Project pins died 2026-07-07.)
                $0.things.count != $1.things.count
                    ? $0.things.count > $1.things.count
                    : $0.name < $1.name
            }
    }

    // MARK: - Cover (H7 — the doc names facts; the renderer owns the rest)

    /// "Thursday, July 9" — the day, stated plainly (ruling 2026-07-09: the
    /// landed count was noise for anyone with feeds — always a big number,
    /// never news; the kind pills below already tell today's story, and the
    /// quiet cover carries the quiet-day fact).
    private static func dateline(things: [Thing]) -> String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// The cover line — the DATE, plus the quiet/empty message when there's
    /// nothing to lead with. Kind chips retired 2026-07-17 (a whole-corpus
    /// lifetime tally that only looked like signal — the feed filters by kind
    /// natively, and the board's rows carry the live signal now); arg 6 stays
    /// `[]` for arity so the id's seat (arg 7) holds its position.
    private static func cover(things: [Thing]) -> String {
        let date = dateline(things: things)
        // Quiet cover — nothing landed today. The words state the quiet; no
        // thing id (nothing fresh to open).
        if isQuietDay(things) {
            return "cover = Cover(\(q(String(localized: "Today"))), \(q(String(localized: "A quiet day"))), \(q(String(localized: "Nothing new yet — your things keep."))), \(q("")), \(q(date)), \(q("quiet")), [], \(q("")))"
        }
        // A thing landed today — "Just landed" leads the blue intelligence card
        // (see `daily`), not a cover hero, so the cover is just the date header
        // (GenCover draws no hero card when the title is empty).
        if things.contains(where: { $0.kind != .approval && $0.capturedAt <= .now }) {
            return "cover = Cover(\(q("")), \(q("")), \(q("")), \(q("")), \(q(date)), \(q("")), [], \(q("")))"
        }
        return "cover = Cover(\(q(String(localized: "Now"))), \(q(String(localized: "Your things go here"))), \(q(String(localized: "Paste, speak, or share one in."))), \(q("")), \(q(date)), \(q("quiet")), [], \(q("")))"
    }

    /// The "While you were away" line — a factual, bounded read of what
    /// MEANINGFULLY landed since the last visit (AppVisit's frozen window, with
    /// the Wallet/Tokens firehose and pending approvals excluded, so it's signal
    /// not "29 mostly wallet spam"). Empty when the gap was trivial or nothing
    /// meaningful arrived. Shares the ONE intelligence card with the Noticed
    /// line (user 2026-07-18 — the two are combined, not two cards).
    private static func awayLine(_ things: [Thing]) -> String {
        guard let window = AppVisit.away else { return "" }
        let arrived = things.filter {
            $0.kind != .approval && !firehoseSources.contains($0.source)
                && window.contains($0.capturedAt)
        }
        guard !arrived.isEmpty else { return "" }
        // Surface the DECISION-shaped part of the arrivals when there is one
        // (user 2026-07-17: a raw count is a volume, not a signal). Mentions of
        // you are the one "someone's waiting on you" read honestly derivable
        // from what arrived (the enrichment's `socialContext`); when any came
        // in, the line names them instead of a bare "mostly from X".
        let mentions = arrived.filter { $0.socialContext == "mention" }.count
        if mentions > 0 {
            return String(localized: "\(arrived.count) new while you were away, \(mentions) mentioning you.")
        }
        // Otherwise name the top sources it came from, "You" excluded (a capture
        // isn't an app news "came from"); the count still totals everything.
        var bySource: [String: Int] = [:]
        for t in arrived where t.source != "You" { bySource[t.source, default: 0] += 1 }
        let top = bySource.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }.prefix(2).map { $0.key }
        let sources = top.joined(separator: " and ")
        // A full sentence — it joins the card's one paragraph now (2026-07-18),
        // so the "while you were away" frame rides the words themselves.
        return sources.isEmpty
            ? String(localized: "\(arrived.count) new while you were away.")
            : String(localized: "\(arrived.count) new while you were away, mostly from \(sources).")
    }

    // The cover's kind-count chips (a whole-corpus lifetime tally) retired
    // 2026-07-17 — they looked like signal but never changed; the feed filters
    // by kind natively, and the board's live signals do the real work.

    /// The image-media sources whose pin composes as a bespoke shelf
    /// (`appendMediaModules`) rather than the generic Widget tile — their
    /// content IS pictures, so a strip/grid beats a list of titled rows.
    /// RSS is NOT here (2026-07-18 correction) despite carrying article
    /// images: its content is the headline, not the picture — a filmstrip
    /// row was suppressing the title text entirely (isMedia guards it out
    /// in GenAppRow) for a source where the title is the whole point.
    static let mediaSources: Set<String> = ["Apple Music", "Pinterest", "Photos"]

    /// High-volume auto-ingest sources that own their own Home surfaces — the
    /// wallet's holdings treemap, the token charts — and would otherwise
    /// dominate any newest-N read with transaction/price noise. Excluded from
    /// the synthesis head's aggregate reads (the cover's "+N new" away count and
    /// the "Noticed" line's candidate window) so those summarize the meaningful
    /// arrivals, not the firehose. Per-tile signals are unaffected — a Tokens
    /// tile still shows its own movers.
    static let firehoseSources: Set<String> = ["Wallet", "Tokens"]

    /// A pinned app is one board tile of its recent things (ruling 2026-07-12):
    /// pinning is per-APP now, not per-item — you keep "your reminders" in
    /// view, not one reminder. Each non-image pinned source composes as a
    /// `Widget(title, [rows], source)` — the same shape its store-page preview
    /// draws (StorePreview), now filled from the corpus. The trailing `source`
    /// arg marks the Widget a board module (draggable, sizable via its corner
    /// pin, removable via long-press) and names which pin its "Remove from
    /// Home" drops. Image sources keep their shelf; the wallet keeps its
    /// treemap; both compose elsewhere and are skipped here.
    ///
    /// Which sources land here: every explicitly pinned source, plus the
    /// auto-social accounts (Bluesky/Farcaster) that show unless hidden — the
    /// same "on the board" set the old single-post card used, now plural.
    /// Sorted by name so the natural order is stable across composes (the
    /// person's own arrangement rides `HomeBoardOrder` on top).
    @MainActor
    private static func appendPinnedApps(_ things: [Thing],
                                         to doc: inout [String],
                                         rootRefs: inout [String],
                                         boardRefs: inout [String],
                                         boardKeys: inout [String: String]) {
        let store = HomePinnedSources.shared
        // Auto-pin (user 2026-07-18): every CONNECTED source is on the board by
        // default — the person subtracts what they don't want (less mental than
        // building the board from empty), the same show-unless-hidden model
        // Bluesky/Farcaster already used, now generalized to all. "Connected" =
        // has landed at least one thing (pinning never invents content); the
        // only control is hide (the tile's "Remove from Home" → `setHidden`).
        // Image/graph sources compose as their own shelves elsewhere; "Wallet"
        // has its own treemap + NFT modules (pinned per-address via WalletStore),
        // so a generic activity tile beside it would be a redundant second
        // wallet; "You" is the person's own captures (the cover already leads
        // with the newest), not an app connection. All stay off the generic
        // tile path.
        var bySource: [String: [Thing]] = [:]
        for t in things { bySource[t.source, default: []].append(t) }
        // Media sources (Photos/Pinterest/Music) are rows too now (user
        // 2026-07-18) — a text row is a lossy translation of an image source,
        // so their row's content peek is a THUMBNAIL FILMSTRIP in the source's
        // native medium, not the shelf-card that broke Home's one-row rule.
        // RSS stays off the filmstrip path (its content is headlines, not
        // pictures) and reads as a normal titled row. Only "You" (own
        // captures — the cover leads with them) and "Wallet" (its own
        // treemap/NFT modules) stay off the row path entirely.
        let onBoard = Set(bySource.keys)
            .subtracting(["You", "Wallet"])
            .filter { !store.isHidden($0) }
            .sorted()
        // The away window (AppVisit) powers a live per-tile signal — "N new"
        // since the last visit — so a tile reads as its world moving, not a
        // static list of recent items (tiles-as-signals, powerful-Home).
        let awayWindow = AppVisit.away

        // Pass 1 — each source's signal and the thing it points at. The
        // watchlist's signal is its movers split, from the SAME cached pulses
        // Feed's lede reads, so the two can never disagree; its exemplar is
        // the top mover (TokenWatchOrder). Every other source rides
        // `tileSignal` (overdue / upcoming / mentions, else "N new" — honest,
        // never guessed).
        struct RowSeed { let source: String; let exemplar: Thing?
                         let signal: String; let rank: Int; var filmstrip: [Thing] = [] }
        let seeds: [RowSeed] = onBoard.compactMap { source in
            let sourceThings = bySource[source] ?? []
            guard !sourceThings.isEmpty else { return nil }
            guard source == "Tokens" else {
                let (signal, rank, exemplar) = tileSignal(source, sourceThings, window: awayWindow)
                // An image source's peek is its newest imaged things (up to a
                // filmstrip's worth); a source with no imagery falls back to
                // the text exemplar (medium-native — the honesty gate).
                let film = mediaSources.contains(source)
                    ? Array(sourceThings.filter(Self.hasImage).prefix(4))
                    : []
                return RowSeed(source: source, exemplar: exemplar,
                               signal: signal, rank: rank, filmstrip: film)
            }
            let sorted = TokenWatchOrder.shared.apply(
                sourceThings, sourceRef: \.sourceRef,
                change24h: { TokenPulse.shared.pulse(for: $0)?.change24h })
            // Two watched tokens minimum (WatchlistLede's own rule) — one
            // token's row already says everything about itself.
            let pulses = sourceThings.compactMap { TokenPulse.shared.pulse(for: $0) }
            let up = pulses.filter { $0.change24h > 0 }.count
            let down = pulses.filter { $0.change24h < 0 }.count
            var parts: [String] = []
            if pulses.count >= 2, up > 0 { parts.append(String(localized: "\(up) up")) }
            if pulses.count >= 2, down > 0 { parts.append(String(localized: "\(down) down")) }
            let signal = parts.joined(separator: " · ")
            return RowSeed(source: source, exemplar: sorted.first,
                           signal: signal, rank: signal.isEmpty ? 0 : 1)
        }

        // Pass 2 — ONE ROW PER APP (user ruling 2026-07-17). Every app is one
        // row (icon · name · signal · a content PEEK · time); tapping opens
        // that app's feed. The peek renders in the source's native medium
        // (2026-07-18): a text line for text sources, the sparkline for Tokens,
        // a thumbnail filmstrip for image sources — one row anatomy, medium-
        // native content, so a card is never needed for an app. Rows are
        // draggable board modules in signal order; only true source-level
        // VISUALIZATIONS (the wallet treemap, the GitHub graph) stay cards.
        let ranked = seeds.sorted {
            $0.rank != $1.rank ? $0.rank > $1.rank : $0.source < $1.source
        }
        for (i, seed) in ranked.enumerated() {
            let id = "appRow\(i)"
            let item = seed.exemplar
            // The Tokens row keeps its SPARKLINE (user 2026-07-17: "WE NEED
            // THE SPARKLINE") — the one visual the card form carried that a
            // text row can't. Args 5-7 hand the renderer the top mover's
            // chain/address/ticker; its second line becomes the live chip
            // (sparkline + price + 1D delta, drawn on-device — prd 51: a
            // token's content IS its chart). Every other app's args 5-7 are
            // empty and the row stays plain text.
            var chipSeat = ", \(q("")), \(q("")), \(q(""))"
            if seed.source == "Tokens", let item,
               let route = TokenChart.route(from: item.content) {
                chipSeat = ", \(q(route.chain)), \(q(route.address)), \(q(TokensAsk.symbol(of: item.title)))"
            }
            // Arg 8 = the signal RANK, so the row can EMPHASIZE a needs-you
            // signal (overdue/mentions/due, rank ≥ 3) in primary ink — the one
            // row that wants you stands out of the monochrome list without a
            // new color (2026-07-17). GenAppRow reads it; other readers ignore.
            // Arg 9 = the filmstrip's MediaItem refs (image sources) — the row's
            // peek is those thumbnails instead of a text line (user 2026-07-18);
            // empty for every non-image source.
            let filmIds = seed.filmstrip.indices.map { "\(id)f\($0)" }
            let filmSeat = ", [\(filmIds.joined(separator: ", "))]"
            doc.append("\(id) = AppRow(\(q(seed.source)), \(q(seed.signal)), \(q(item?.title ?? "")), \(q(item.map { shortTime($0.capturedAt) } ?? "")), \(q(item?.id.uuidString ?? ""))\(chipSeat), \(q("\(seed.rank)"))\(filmSeat))")
            for (j, t) in seed.filmstrip.enumerated() {
                doc.append(mediaItem(id: "\(id)f\(j)", t))
            }
            rootRefs.append(id)
            // Rows are DRAGGABLE board modules (user 2026-07-17: "what if
            // someone wants to change their order?") — signal order is only
            // the natural default; a drag pins the person's own order via
            // HomeBoardOrder, exactly as the tiles worked. One size though:
            // rows never resize or pair (allowedSpans keeps them wide-only).
            boardRefs.append(id)
            boardKeys[id] = "app:\(seed.source)"
        }
    }

    /// A tile's "N new" subtitle — how many of its things landed inside the
    /// away window (what changed since the last visit). Empty when there's no
    /// away gap or the source was quiet, so a tile only claims motion when it
    /// really moved (honesty rule).
    private static func newSinceAway(_ things: [Thing], window: Range<Date>?) -> String {
        guard let window else { return "" }
        let n = things.filter { window.contains($0.capturedAt) }.count
        return n > 0 ? String(localized: "\(n) new") : ""
    }

    /// A pinned tile's subtitle — its sharpest HONEST live signal, chosen per
    /// source and derived entirely from the corpus (never a guessed status,
    /// e.g. mail "needs a reply", which we can't know). Each source falls back
    /// to "N new" when it has no sharper honest read. Tokens is handled inline
    /// (its movers ride cached pulses); this covers every other source.
    ///
    /// The RANK orders the rows (signal-driven, 2026-07-17): what needs you
    /// outranks what merely moved — overdue 5 > mentions 4 > due 3 >
    /// upcoming 2 > new/movers 1 > quiet 0. The EXEMPLAR is the one thing the
    /// signal points at — the row shows IT, not just the newest item: the
    /// most-overdue reminder, the next event, the latest mention.
    private static func tileSignal(_ source: String, _ things: [Thing],
                                   window: Range<Date>?) -> (String, Int, Thing?) {
        switch source {
        case "Reminders", "Todoist":
            // Overdue leads (a real deadline has passed), else what's still due
            // — both off `dueAt`, never a done item. Recovers the overdue
            // prominence the retired "Coming up" card carried (§118).
            let open = things.filter { $0.mark != .done }
            let overdue = open.filter { ($0.dueAt ?? .distantFuture) < .now }
            if !overdue.isEmpty {
                return (String(localized: "\(overdue.count) overdue"), 5,
                        overdue.min { ($0.dueAt ?? .now) < ($1.dueAt ?? .now) })
            }
            let due = open.filter { ($0.dueAt ?? .distantPast) >= .now }
            if !due.isEmpty {
                return (String(localized: "\(due.count) due"), 3,
                        due.min { ($0.dueAt ?? .now) < ($1.dueAt ?? .now) })
            }
        case "Calendar", "Cal.com", "Calendly":
            // What's still ahead — a future event's start rides capturedAt,
            // same read the cover uses to keep the future out of "Just landed".
            let upcoming = things.filter { $0.kind == .event && $0.capturedAt >= .now }
            if !upcoming.isEmpty {
                return (String(localized: "\(upcoming.count) upcoming"), 2,
                        upcoming.min { $0.capturedAt < $1.capturedAt })
            }
        case "Bluesky", "Farcaster":
            // Mentions of you (the enrichment's `socialContext`) — the one
            // social read worth surfacing over raw recency.
            let mentions = things.filter { $0.socialContext == "mention" }
            if !mentions.isEmpty {
                return (String(localized: "\(mentions.count) mentions"), 4, mentions.first)
            }
        default:
            break
        }
        let fresh = newSinceAway(things, window: window)
        return (fresh, fresh.isEmpty ? 0 : 1, things.first)
    }

    // The bespoke tile-header phrases (appTitle: "On your list", "In your
    // inbox", "Watchlist", "Recent chats"…) died 2026-07-17 (user: "shouldn't
    // it just be called what it is?") — a tile's header is the app's own name,
    // and the live signal subtitle carries the state.

    // appChild (the per-kind row forms inside app cards — TokenChip, PostRow,
    // MailRow, Row) died with the cards themselves (2026-07-17): an app is one
    // AppRow now; its per-kind richness lives where it always did, in the
    // app's own feed.

    /// Wallet holdings on Home (ruling 2026-07-08): pinning the wallet shows
    /// each watched wallet's own top-5-by-value treemap, the same TagMap
    /// idiom the map itself uses — synthesis, not a thing, so it rides
    /// alongside Pinned rather than inside it. One map per wallet, not
    /// combined (ruling 2026-07-09): two watched addresses are usually two
    /// different purposes, and summing them hid which wallet held what.
    /// Groups arrive pre-computed (WalletIngest.topHoldingsByWallet()) since
    /// composing the doc is synchronous and the fetch is not.
    private static func appendWalletHoldings(_ groups: [WalletIngest.HoldingsGroup],
                                             combined: WalletIngest.HoldingsGroup? = nil,
                                             pending: Bool = false,
                                             unreachable: Bool = false,
                                             to doc: inout [String],
                                             rootRefs: inout [String],
                                             boardRefs: inout [String],
                                             boardKeys: inout [String: String]) {
        // Wallet is ONE ROW on Home now (user 2026-07-18: the treemap belongs
        // ONLY on the Wallet source feed — it was duplicated here and was the
        // last visualization breaking Home's one-row-per-app rule). The row
        // shows the total value and the top holdings; tapping opens the Wallet
        // feed, where the treemap (and NFTs, and transactions) live. Loading and
        // unreachable read as the row's OWN signal — never a vanished slot (the
        // device-report failure the preview/error cards answered), just an
        // honest word in the row that was already there.
        let total = combined?.totalUSD ?? groups.first?.totalUSD
        let cells = combined?.cells ?? groups.first?.cells ?? []
        // Cell format is "SYMBOL weight" — the symbol is the first token; cells
        // are value-ordered, so the first few are the biggest holdings.
        let topSymbols = cells.prefix(3).compactMap { $0.split(separator: " ").first.map(String.init) }
        let signal: String
        let peek: String
        if let total {
            signal = walletTotalText(total)
            peek = topSymbols.joined(separator: " · ")
        } else if pending {
            signal = String(localized: "Loading…"); peek = ""
        } else if unreachable {
            signal = String(localized: "Couldn't reach"); peek = ""
        } else {
            return   // no pinned wallet / no data — no row
        }
        let id = "walletRow"
        boardKeys[id] = "app:Wallet"
        // rank 0 — a balance is ambient, not a needs-you signal, so the total
        // reads in the quiet tertiary ink. Source "Wallet" routes the row tap
        // to the wallet feed (chip/addr fields empty, no filmstrip).
        doc.append("\(id) = AppRow(\(q("Wallet")), \(q(signal)), \(q(peek)), \(q("")), \(q("")), \(q("")), \(q("")), \(q("")), \(q("0")), [])")
        rootRefs.append(id)
        boardRefs.append(id)
    }

    /// A wallet's total, whole dollars with grouping — "$12,345". Cents are
    /// noise at a glance (the feed's treemap carries the precision).
    private static func walletTotalText(_ usd: Double) -> String {
        "$" + Int(usd.rounded()).formatted(.number.grouping(.automatic))
    }

    // MARK: - Rich module interiors (prd 58, Goal 3)

    /// A thing carries a real image — a remote preview URL OR local thumbnail
    /// bytes (a screenshot's are local, resolved by thing id). The gate for an
    /// image source's Home filmstrip: only imaged things become thumbnails, and
    /// a source with none falls back to its text peek (honesty — no grey
    /// placeholder strips, the demo's old empty-visual problem).
    static func hasImage(_ t: Thing) -> Bool {
        !(t.previewImageURL ?? "").isEmpty || t.previewImageData != nil
    }

    // A pinned wallet's NFT strip retired from Home 2026-07-18 (user: the
    // wallet's visualizations live on the Wallet feed, where the NFT block
    // already composes) — Home carries the one Wallet row instead.

    /// MediaItem(title, imageURL, thingId, openable) — a shelf's child line.
    /// A screenshot carries no image URL (its bytes are local, prd 48); the
    /// renderer resolves those by thing id instead (`genThumbnailData`).
    private static func mediaItem(id: String, _ t: Thing) -> String {
        let openable = VerbDerivation.verbs(for: t).contains {
            if case .openURL = $0.action { return true } else { return false }
        } ? "app" : ""
        return "\(id) = MediaItem(\(q(t.title)), \(q(t.previewImageURL ?? "")), \(q(t.id.uuidString)), \(q(openable)))"
    }

    private static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// Quotes a string for the document; strips embedded quotes rather than
    /// escaping (the line grammar has no escape sequence).
    private static func q(_ s: String) -> String {
        // GenParser splits the whole document on "\n" per line (brief §5) —
        // a raw newline inside a value (a multi-line social post, Goal 3)
        // would fracture one doc line into several malformed ones. Collapse
        // to spaces, same "no escape sequence" treatment as embedded quotes.
        let flat = s.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(flat.replacingOccurrences(of: "\"", with: ""))\""
    }
}
