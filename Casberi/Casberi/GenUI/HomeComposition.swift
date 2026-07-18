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
        let landed = things.first { $0.kind != .approval && $0.capturedAt <= .now }
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
        // clustering, and it shouldn't cost a scroll to reach. User-chosen, so
        // it passes the no-obligations rule: Casberi never picked these. Pinning
        // is per-APP now (2026-07-12) — a pinned app is one tile of its recent
        // things, not a single item; image sources keep their bespoke shelf
        // (appendMediaModules), everyone else composes as a Widget of rows.
        appendPinnedApps(things, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs, boardKeys: &boardKeys)
        appendGitHubGraph(to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        appendWalletHoldings(walletHoldings, combined: walletCombined, pending: walletPending, unreachable: walletUnreachable, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs, boardKeys: &boardKeys)
        appendWalletNFTs(walletNFTs, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs, boardKeys: &boardKeys)
        appendMediaModules(things, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)

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
            doc.append("map = TagMap(\(q(String(localized: "What's going on"))), null, [\(items.joined(separator: ", "))])")
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
        "map = TagMapPreview(\(q(String(localized: "What's going on"))), \(q(String(localized: "Your things map here as they land"))), [Links, Notes, Events, Mail, Screenshots])"

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

    /// The cover line — pure content (2026-07-10): the Banner became the
    /// Background setting, so the cover carries no image ref (arg 4 stays for
    /// arity, always empty). The chips now read the WHOLE corpus by kind
    /// (ruling 2026-07-12) — a stable synthesis of what your stuff is made of,
    /// the same every day, no daily reset. Today's activity was noise for
    /// anyone with feeds (always a big number, never news); recency is Feed's
    /// job. The chips complement the map: the map is your corpus by theme, the
    /// chips are your corpus by kind. Both ride every cover, quiet or active.
    private static func cover(things: [Thing]) -> String {
        let date = dateline(things: things)
        // Lifetime kind composition — the same chips every day, no reset.
        let chips = coverChips(things)
        // The chips slot always emits (empty only for an all-approval corpus)
        // so the id's seat (arg 7) holds its position.
        let chipsSeat = chips.map { ", \($0)" } ?? ", []"
        // Quiet cover — nothing landed today. The words state the quiet; the
        // chips still show the corpus's composition (a quiet day didn't change
        // what your stuff is made of). No thing id — nothing fresh to open.
        if isQuietDay(things) {
            return "cover = Cover(\(q(String(localized: "Today"))), \(q(String(localized: "A quiet day"))), \(q(String(localized: "Nothing new yet — your things keep."))), \(q("")), \(q(date)), \(q("quiet"))\(chipsSeat), \(q("")))"
        }
        // A thing actually landed today — but "Just landed" now LEADS the blue
        // intelligence card (see `daily`), not a cover hero (user 2026-07-18:
        // the cover and that card were two cards both conveying what's new). So
        // the cover here is just the date header + kind chips: empty hero fields
        // (GenCover draws no hero card when the title is empty).
        if things.contains(where: { $0.kind != .approval && $0.capturedAt <= .now }) {
            return "cover = Cover(\(q("")), \(q("")), \(q("")), \(q("")), \(q(date)), \(q(""))\(chipsSeat), \(q("")))"
        }
        return "cover = Cover(\(q(String(localized: "Now"))), \(q(String(localized: "Your things go here"))), \(q(String(localized: "Paste, speak, or share one in."))), \(q("")), \(q(date)), \(q("quiet"))\(chipsSeat), \(q("")))"
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
        // Name the top sources it came from, "You" excluded (a capture isn't an
        // app news "came from"); the count still totals everything.
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

    // MARK: - Cover chips (the corpus's kind composition — ruling 2026-07-12)

    /// The corpus's kind composition, "[Tag N, ...]", count-ordered, max 5 —
    /// the cover's chip row. Whole corpus, not today or this week: a stable
    /// read of what your stuff is made of, and a tap opens that kind in Feed.
    /// Approvals never count (they're pending asks, not saved things), and
    /// neither does the Wallet/Tokens firehose (2026-07-17): a watched wallet's
    /// auto-ingested receipts made "134 transactions" the first number on the
    /// screen, drowning the 7 links the person actually saved — the same
    /// aggregate-read exclusion the away count and the Noticed window already
    /// apply. The wallet's numbers live in its own modules. Nil only when
    /// nothing else remains.
    private static func coverChips(_ things: [Thing]) -> String? {
        var counts: [ThingKind: Int] = [:]
        for t in things where t.kind != .approval && !firehoseSources.contains(t.source) {
            counts[t.kind, default: 0] += 1
        }
        guard !counts.isEmpty else { return nil }
        let items = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.typeTag < $1.key.typeTag
        }.prefix(5).map { "\($0.key.typeTag) \($0.value)" }
        return "[\(items.joined(separator: ", "))]"
    }

    /// The image-media sources whose pin composes as a bespoke shelf
    /// (`appendMediaModules`) rather than the generic Widget tile — their
    /// content IS pictures, so a strip/grid beats a list of titled rows.
    static let mediaSources: Set<String> = ["Apple Music", "Pinterest", "Photos", "RSS"]

    /// Sources whose pin composes as a bespoke tile that is NOT a list of recent
    /// rows — GitHub's is its contribution graph (`appendGitHubGraph`). Skipped
    /// by the generic pinned-app path like the media shelves are.
    static let graphSources: Set<String> = ["GitHub"]

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
        let onBoard = Set(bySource.keys)
            .subtracting(["You", "Wallet"])
            .subtracting(mediaSources)
            .subtracting(graphSources)
            .filter { !store.isHidden($0) }
            .sorted()
        // The away window (AppVisit) powers a live per-tile signal — "N new"
        // since the last visit — so a tile reads as its world moving, not a
        // static list of recent items (tiles-as-signals, powerful-Home).
        let awayWindow = AppVisit.away

        // Pass 1 — each source's rows and its signal. The watchlist leads with
        // what MOVED (2026-07-15): the shared TokenWatchOrder (movers by
        // default) reorders the FULL set before the three-row cap, and the
        // subtitle names the day's up/down split from the SAME cached pulses,
        // so Home can never disagree with Feed's lede about which tokens moved.
        // Every other source rides `tileSignal` (overdue / upcoming / mentions,
        // else "N new" — honest, never guessed).
        struct TileSeed { let source: String; let ordered: [Thing]
                          let subtitle: String; let rank: Int }
        let seeds: [TileSeed] = onBoard.compactMap { source in
            let sourceThings = bySource[source] ?? []
            guard !sourceThings.isEmpty else { return nil }
            guard source == "Tokens" else {
                let (subtitle, rank) = tileSignal(source, sourceThings, window: awayWindow)
                return TileSeed(source: source, ordered: sourceThings,
                                subtitle: subtitle, rank: rank)
            }
            let sorted = TokenWatchOrder.shared.apply(
                sourceThings, sourceRef: \.sourceRef,
                change24h: { TokenPulse.shared.pulse(for: $0)?.change24h })
            // Two watched tokens minimum (WatchlistLede's own rule) — one
            // token's row already says everything about itself.
            let pulses = sourceThings.compactMap { TokenPulse.shared.pulse(for: $0) }
            guard pulses.count >= 2 else {
                return TileSeed(source: source, ordered: sorted, subtitle: "", rank: 0)
            }
            let up = pulses.filter { $0.change24h > 0 }.count
            let down = pulses.filter { $0.change24h < 0 }.count
            var parts: [String] = []
            if up > 0 { parts.append(String(localized: "\(up) up")) }
            if down > 0 { parts.append(String(localized: "\(down) down")) }
            let subtitle = parts.joined(separator: " · ")
            return TileSeed(source: source, ordered: sorted,
                            subtitle: subtitle, rank: subtitle.isEmpty ? 0 : 1)
        }

        // Pass 2 — signal-driven order (tool-does-the-triage, 2026-07-17):
        // what needs you (overdue, mentions) floats above what merely moved,
        // quiet tiles sink; name is the stable tiebreak so equal-signal tiles
        // never reshuffle between composes. The person's own arrangement
        // still WINS outright — HomeBoardOrder applies their saved order on
        // top of this natural one, so ranking only decides where an
        // un-arranged tile first lands.
        var ranked = seeds.sorted {
            $0.rank != $1.rank ? $0.rank > $1.rank : $0.source < $1.source
        }

        // The board is BOUNDED (2026-07-17): auto-pin grows tiles with every
        // connected source, and an eager MagazineLayout pays for all of them
        // on the first frame (the stack-overflow class this board already hit
        // twice). Past the cap, the quiet tail collapses behind one "Show N
        // more" line (`MoreTiles`, rendered by HomeScreen below the board —
        // subtract-model: the strongest-signal tiles stay, nothing is lost,
        // one tap shows all and the choice sticks). Signal order guarantees
        // the cap only ever hides the quietest tiles.
        let showAll = UserDefaults.standard.bool(forKey: "home.board.showAll")
        if !showAll, ranked.count > boardTileCap {
            let hidden = ranked.count - boardTileCap
            ranked = Array(ranked.prefix(boardTileCap))
            doc.append("moreTiles = MoreTiles(\(q("\(hidden)")))")
        }

        for (emitted, seed) in ranked.enumerated() {
            let source = seed.source
            let id = "appTile\(emitted)"
            let mail = source == "Gmail" || source == "iCloud Mail"
            let social = HomePinnedSources.autoSocial.contains(source)
            // Three is the ceiling now (2026-07-14): big shows all three as a
            // card, wide shows the first as one line, small shows it
            // full-size — no span ever needs a fourth.
            let items = Array(seed.ordered.prefix(3))
            let childIds = items.indices.map { "\(id)c\($0)" }
            // Arg 4 carries the signal RANK so HomeScreen's default span can
            // give a needs-you tile (overdue/mentions/due) a wide opening
            // without parsing the localized subtitle. GenWidget ignores it.
            doc.append("\(id) = Widget(\(q(appTitle(source))), \(q(seed.subtitle)), [\(childIds.joined(separator: ", "))], \(q(source)), \(q("\(seed.rank)")))")
            for (i, t) in items.enumerated() {
                doc.append(appChild(id: "\(id)c\(i)", t, mail: mail, social: social))
            }
            rootRefs.append(id)
            boardRefs.append(id)
            // Key by SOURCE so the tile's size/slot survive other apps being
            // pinned/unpinned above it — matches HomePinnedSources.boardKey.
            boardKeys[id] = "app:\(source)"
        }
    }

    /// The most app tiles the board shows before collapsing the quiet tail
    /// behind "Show N more" — enough for every signal-bearing tile on a busy
    /// day, few enough that the eager board's first frame stays bounded.
    private static let boardTileCap = 6

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
    /// The RANK orders the board (signal-driven, 2026-07-17) and steers the
    /// default span: what needs you outranks what merely moved —
    /// overdue 5 > mentions 4 > due 3 > upcoming 2 > new/movers 1 > quiet 0.
    private static func tileSignal(_ source: String, _ things: [Thing],
                                   window: Range<Date>?) -> (String, Int) {
        switch source {
        case "Reminders", "Todoist":
            // Overdue leads (a real deadline has passed), else what's still due
            // — both off `dueAt`, never a done item. Recovers the overdue
            // prominence the retired "Coming up" card carried (§118).
            let open = things.filter { $0.mark != .done }
            let overdue = open.filter { ($0.dueAt ?? .distantFuture) < .now }.count
            if overdue > 0 { return (String(localized: "\(overdue) overdue"), 5) }
            let due = open.filter { ($0.dueAt ?? .distantPast) >= .now }.count
            if due > 0 { return (String(localized: "\(due) due"), 3) }
        case "Calendar", "Cal.com", "Calendly":
            // What's still ahead — the rows ARE the calendar, so the subtitle
            // counts upcoming events (a future event's start rides capturedAt,
            // same read the cover uses to keep the future out of "Just landed").
            let upcoming = things.filter { $0.kind == .event && $0.capturedAt >= .now }.count
            if upcoming > 0 { return (String(localized: "\(upcoming) upcoming"), 2) }
        case "Bluesky", "Farcaster":
            // Mentions of you (the enrichment's `socialContext`) — the one
            // social read worth surfacing over raw recency.
            let mentions = things.filter { $0.socialContext == "mention" }.count
            if mentions > 0 { return (String(localized: "\(mentions) mentions"), 4) }
        default:
            break
        }
        let fresh = newSinceAway(things, window: window)
        return (fresh, fresh.isEmpty ? 0 : 1)
    }

    /// GitHub's pinned tile is its contribution graph — the green-squares year,
    /// not a list of recent rows. Emitted when GitHub is pinned AND connected
    /// (the graph needs the token's GraphQL); the tile self-fetches its data
    /// (`GitHubGraphStore`), so the doc only names the module. The board key is
    /// the ref itself (`HomePinnedSources.moduleRef`), so no `boardKeys` entry.
    private static func appendGitHubGraph(to doc: inout [String],
                                          rootRefs: inout [String],
                                          boardRefs: inout [String]) {
        // Auto-pin (2026-07-18): a connected GitHub shows its graph by default,
        // unless hidden — "connected" here is the bridge (the graph self-fetches
        // and may have no landed Things to gate on). Removing it hides "GitHub".
        guard TokenBridge.github.connected,
              !HomePinnedSources.shared.isHidden("GitHub") else { return }
        doc.append("githubGraphShelf = GithubGraph(\(q(String(localized: "Your year in code"))), \(q("")))")
        rootRefs.append("githubGraphShelf")
        boardRefs.append("githubGraphShelf")
    }

    /// A pinned app tile's header — a bespoke phrase where the app has one
    /// (its store preview's voice), else the app's own name. Sentence case,
    /// no eyebrow caps (design law): the words carry it.
    private static func appTitle(_ source: String) -> String {
        switch source {
        // "In your inbox", not "Waiting on you" — Home's voice guardrail bans
        // obligation phrasing (handoff-home: no "waiting on you"), and the
        // person pinned this themselves; the card states what's there, not a duty.
        case "Gmail", "iCloud Mail":                       return String(localized: "In your inbox")
        case "GitHub":                                     return String(localized: "In your feed")
        case "Linear":                                     return String(localized: "Assigned to you")
        case "Notion":                                     return String(localized: "Pages")
        case "Reddit", "Raindrop":                         return String(localized: "Saved")
        case "YouTube":                                    return String(localized: "Liked and saved")
        case "Twitch":                                     return String(localized: "Live now")
        // Twitch keeps its plain name (default) — a fixed "Live now" header
        // would assert real-time state the recency-ordered rows can't verify
        // (honesty rule; TwitchBridge gates its own live indicator on liveRefs).
        case "Apple Health":                               return String(localized: "Training")
        case "Strava":                                     return String(localized: "Activities")
        case "Cal.com":                                    return String(localized: "Booked with you")
        case "Calendly":                                   return String(localized: "On your schedule")
        case "Calendar":                                   return String(localized: "On your calendar")
        case "Todoist", "Reminders":                       return String(localized: "On your list")
        case "Readwise", "Kindle":                         return String(localized: "Highlights")
        case "Tokens":                                      return String(localized: "Watchlist")
        case "Kalshi":                                     return String(localized: "Markets")
        case "Bluesky", "Farcaster":                       return String(localized: "Recent posts")
        case "ChatGPT", "Claude", "Gemini":                return String(localized: "Recent chats")
        case "Substack", "Podcasts":                       return String(localized: "New")
        case "Steam":                                      return String(localized: "Recently played")
        case "Apple Notes", "Day One", "Apple Journal", "Obsidian":
                                                           return String(localized: "Notes")
        default:                                           return source
        }
    }

    /// One line inside a pinned app tile — a live TokenChip (sparkline + price)
    /// for a token link (Tokens: a token's content IS its chart, prd 51), a
    /// PostRow for Bluesky/Farcaster (the author's own avatar leads, same as the
    /// old single-post card carried), a MailRow for the inboxes (subject +
    /// snippet), a plain tappable Row for everything else. All carry the thing
    /// id so a tap opens it, and the hand-off flag so "Open in app" appears
    /// only when it goes somewhere.
    private static func appChild(id: String, _ t: Thing, mail: Bool, social: Bool = false) -> String {
        let openable = VerbDerivation.verbs(for: t).contains {
            if case .openURL = $0.action { return true } else { return false }
        } ? "app" : ""
        if t.kind == .link, let route = TokenChart.route(from: t.content) {
            return "\(id) = TokenChip(\(q(tickerSymbol(t.title))), \(q(route.chain)), \(q(route.address)), \(q(t.id.uuidString)), \(q(openable)))"
        }
        if social {
            return "\(id) = PostRow(\(q(t.authorHandle ?? "")), \(q(t.title)), \(q(t.authorAvatarURL ?? "")), \(q(t.id.uuidString)), \(q(openable)))"
        }
        if mail {
            let snippet = String(t.content.prefix(120))
            return "\(id) = MailRow(\(q(t.title)), \(q(snippet)), \(q(shortTime(t.capturedAt))), \(q(t.id.uuidString)), \(q(openable)))"
        }
        return "\(id) = Row(\(q(t.title)), \(q(t.kind.typeTag)), \(q(t.source)), \(q(shortTime(t.capturedAt))), \(q(t.id.uuidString)), \(q(openable)))"
    }

    /// The bare ticker from a watched token's own "Name · $TICKER" title
    /// (`TokenWatch`'s format) — TokenChip's symbol shares its line with the
    /// plot and price, so the FULL title truncated there (2026-07-14: even a
    /// short ticker like ETH scrolled past its slot inside "Ethereum · $ETH").
    /// One parser for the format — TokensAsk.symbol.
    private static func tickerSymbol(_ title: String) -> String {
        TokensAsk.symbol(of: title)
    }

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
        // The combined "Across your wallets" map LEADS the per-wallet ones
        // when more than one wallet is pinned (ruling 2026-07-15, softening
        // §71): the same additive bundle the Wallet screen shows, so Home's
        // total matches its per-wallet tiles. `combined` is nil with one or
        // zero pinned wallets — a single wallet's own map already is its
        // combined view. Softened voice: "Across your wallets", never "Net
        // worth" or "Portfolio".
        if let c = combined {
            let id = "walletCombined"
            boardKeys[id] = "wallet:__all__"
            doc.append("\(id) = TagMap(\(q("@pin " + String(localized: "Across your wallets"))), \(q(c.subline)), [\(c.cells.joined(separator: ", "))], \(q("token")))")
            rootRefs.append(id)
            boardRefs.append(id)
        }
        for (i, g) in groups.enumerated() {
            let id = "walletMap\(i)"
            // Key by the wallet's label so its treemap keeps its slot/size as
            // other wallets are pinned/unpinned (matches HomeScreen.moduleKey).
            boardKeys[id] = "wallet:\(g.label)"
            // "@pin " leading the eyebrow → GenTagMap renders the Pinned
            // card's tilted pin, small, before the wallet's name (ruling
            // 2026-07-10): these maps are on Home because the wallet is
            // pinned, and everything pin-born wears the pin. The Wallet
            // screen and the Feed block compose the same maps WITHOUT the
            // marker — there, nothing is pinned.
            doc.append("\(id) = TagMap(\(q("@pin " + g.label)), \(q(g.subline)), [\(g.cells.joined(separator: ", "))], \(q("token")))")
            rootRefs.append(id)
            boardRefs.append(id)
        }
        // A pinned wallet's balance fetch is a real network round-trip — the
        // slot sat empty for that whole window and read as "my holdings
        // disappeared" (device report, 2026-07-11) instead of "loading". The
        // starter-preview idiom already says this honestly elsewhere
        // (appendStarterPreviews): same muted shape, breathing, nothing to
        // tap, gone the moment real cells land. Not a board module (nothing
        // to drag before the real card exists).
        if groups.isEmpty, pending {
            doc.append("walletPreview = TagMapPreview(\(q(String(localized: "Wallet"))), \(q(String(localized: "Loading your holdings…"))), [ETH, BTC, SOL, USDC, More])")
            rootRefs.append("walletPreview")
        } else if unreachable {
            // A pinned wallet we couldn't reach AND have never sampled — the one
            // case with no card and no cache to show. It used to leave the slot
            // blank, which reads as "my holdings vanished" (device report,
            // 2026-07-17, same complaint the loading preview answered for the
            // in-flight window). Say it honestly instead: a muted, non-breathing
            // card that names the failure and the fix. Pull-to-refresh (the
            // screen's own retry gesture) reloads it; the retry/backoff in the
            // fetch means this only persists through a real outage or a dead
            // connection, not a transient rate-limit.
            doc.append("walletUnreachable = TagMapError(\(q(String(localized: "Your wallets"))), \(q(String(localized: "Couldn't reach the chain — pull down to refresh"))), [ETH, BTC, SOL, USDC, More])")
            rootRefs.append("walletUnreachable")
        }
    }

    // MARK: - Rich module interiors (prd 58, Goal 3)

    /// Music, Pinterest, screenshots, and RSS each compose a bespoke image
    /// shelf. Under auto-pin (user 2026-07-18) they show the moment ONE thing
    /// exists, unless the person hid the source — the same show-unless-hidden
    /// rule the app tiles follow, so a connected image source lands on Home by
    /// itself and is removed by subtraction. (This supersedes the old magnitude-2
    /// auto-earn / explicit-pin threshold; the firehose caveat that kept RSS
    /// opt-in is answered by the shelf being removable in one tap.)
    private static func appendMediaModules(_ things: [Thing], to doc: inout [String],
                                           rootRefs: inout [String], boardRefs: inout [String]) {
        let store = HomePinnedSources.shared
        // Connected (has a thing) and not hidden — the auto-pin gate.
        func shown(_ items: [Thing], _ name: String) -> Bool {
            !items.isEmpty && !store.isHidden(name)
        }
        let music = things.filter { $0.source == "Apple Music" }
        if shown(music, "Apple Music") {
            appendMediaShelf(id: "musicShelf", eyebrow: "Apple Music", kind: "music",
                             items: music, pinned: true,
                             to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        }
        let pins = things.filter { $0.source == "Pinterest" }
        if shown(pins, "Pinterest") {
            appendMediaShelf(id: "pinShelf", eyebrow: "Pinterest", kind: "pinterest",
                             items: pins, pinned: true,
                             to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        }
        let shots = things.filter { $0.kind == .screenshot }
        if shown(shots, "Photos") {
            appendMediaShelf(id: "shotShelf", eyebrow: "Screenshots", kind: "screenshot",
                             items: shots, pinned: true,
                             to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        }
        // RSS auto-shows too now (a feed is a firehose, but the shelf is bounded
        // and removable in one tap — the subtract model answers the flood the
        // old opt-in gate guarded against). Imaged posts lead (a clean magazine
        // strip); a text-only feed still shows its newest as tiles.
        let rssAll = things.filter { $0.source == "RSS" }
        if shown(rssAll, "RSS") {
            let imaged = rssAll.filter { !($0.previewImageURL ?? "").isEmpty }
            let rss = imaged.isEmpty ? rssAll : imaged
            appendMediaShelf(id: "rssShelf", eyebrow: "RSS", kind: "rss",
                             items: rss, pinned: true,
                             to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        }
        // Social (Bluesky/Farcaster) composes as a pinned APP tile now
        // (2026-07-12) — a plural list of recent posts, not one auto-earned
        // card — through `appendPinnedApps`. It still shows unless hidden
        // ("Show on Home"), so nothing is lost; the tile just grew from one
        // post to a feed of them.
    }

    /// A pinned wallet's NFT strip (ruling 2026-07-14) — rides the wallet
    /// pin by default as its OWN board card (removable, resizable, and
    /// reorderable independently of the treemap), through the MediaShelf
    /// idiom the image sources already wear. Wallets holding no NFTs
    /// contribute nothing; a long-press "Remove from Home" hides the strip
    /// per wallet (MediaShelf's pinned verb — arg 6 carries the address the
    /// removal is scoped to). Cells tap out to the piece on OpenSea.
    private static func appendWalletNFTs(_ groups: [WalletIngest.NFTGroup],
                                         to doc: inout [String], rootRefs: inout [String],
                                         boardRefs: inout [String],
                                         boardKeys: inout [String: String]) {
        for (i, g) in groups.enumerated() {
            let id = "nftShelf\(i)"
            // Keyed by address so the strip keeps its slot/size as other
            // wallets are pinned/unpinned (the walletMap precedent).
            boardKeys[id] = "walletNFTs:\(g.address.lowercased())"
            let capped = Array(g.nfts.prefix(12))
            let itemIds = capped.indices.map { "\(id)i\($0)" }
            doc.append("\(id) = MediaShelf(\(q("NFTs · \(g.label)")), \(q("")), [\(itemIds.joined(separator: ", "))], \(q("nft")), \(q("pin")), \(q(g.address)))")
            for (j, nft) in capped.enumerated() {
                // The thing-id slot carries the OpenSea URL — GenMediaTile
                // opens URL-shaped ids directly (an NFT is not a thing).
                doc.append("\(id)i\(j) = MediaItem(\(q(nft.name)), \(q(nft.imageURL)), \(q(nft.openseaURL?.absoluteString ?? "")), \(q("")))")
            }
            rootRefs.append(id)
            boardRefs.append(id)
        }
    }

    /// A source's image strip — newest first, capped at 12 (regular shows
    /// what fits on a scroll, large's grid shows the rest as it grows).
    private static func appendMediaShelf(id: String, eyebrow: String, kind: String, items: [Thing],
                                         pinned: Bool = false,
                                         to doc: inout [String], rootRefs: inout [String],
                                         boardRefs: inout [String]) {
        let capped = Array(items.prefix(12))
        let itemIds = capped.indices.map { "\(id)i\($0)" }
        // Arg 5 ("pin"/"") marks a shelf that's on the board by an explicit
        // pin — only then does its long-press offer "Remove from Home" (an
        // auto-earned shelf has no pin to drop; hiding it means leaving the
        // source in Apps). Trailing arg, so existing readers (0–3) are unmoved.
        doc.append("\(id) = MediaShelf(\(q(eyebrow)), \(q("")), [\(itemIds.joined(separator: ", "))], \(q(kind)), \(q(pinned ? "pin" : "")))")
        for (i, t) in capped.enumerated() { doc.append(mediaItem(id: "\(id)i\(i)", t)) }
        rootRefs.append(id)
        boardRefs.append(id)
    }

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
