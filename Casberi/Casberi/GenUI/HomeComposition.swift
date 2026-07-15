import Foundation
import SwiftData

/// Authors the Home composition document from the live corpus. In M2's server
/// half the model authors this per moment through /compose; until then this
/// local author produces the same document shape from the same facts, and the
/// engine streams it identically — swapping the source later changes no visuals.
///
/// Voice constraints (Home spec): themes and content, no obligations. Tile
/// sublines read content, not status. Hero: one synthesis statement, facts
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

    static func compose(things: [Thing],
                        walletHoldings: [WalletIngest.HoldingsGroup] = [],
                        walletNFTs: [WalletIngest.NFTGroup] = [],
                        walletPending: Bool = false) -> Document {
        let projects = projectClusters(things: things)
        return daily(things: things, projects: projects, walletHoldings: walletHoldings,
                     walletNFTs: walletNFTs, walletPending: walletPending)
    }

    /// True when nothing has landed today — the composition acknowledges the
    /// quiet instead of pretending motion (voice: facts, no obligations).
    private static func isQuietDay(_ things: [Thing]) -> Bool {
        !things.isEmpty && !things.contains { Calendar.current.isDateInToday($0.capturedAt) }
    }

    // MARK: - Documents

    private static func daily(things: [Thing], projects: [Cluster], walletHoldings: [WalletIngest.HoldingsGroup] = [],
                                     walletNFTs: [WalletIngest.NFTGroup] = [],
                                     walletPending: Bool = false) -> Document {
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
        appendWalletHoldings(walletHoldings, pending: walletPending, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs, boardKeys: &boardKeys)
        appendWalletNFTs(walletNFTs, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs, boardKeys: &boardKeys)
        appendMediaModules(things, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)

        // Where the map belongs even when it didn't compose yet — the starter
        // preview slots in here, not at the tail.
        let mapSlot = rootRefs.count
        // Projects — an interactive treemap: magnitude fill, tap opens the
        // project. Chips were tried and reverted same day (2026-07-10):
        // without a pinned wallet Home would have no treemap at all, and
        // the map IS the visual anchor of the screen.
        if !projects.isEmpty {
            let items = projects.prefix(6).map { "\($0.name) \($0.things.count)" }
            doc.append("map = TagMap(\(q(String(localized: "What's going on"))), null, [\(items.joined(separator: ", "))])")
            rootRefs.append("map")
            boardRefs.append("map")
        } else {
            let sources = sourceClusters(things: things)
            if !sources.isEmpty {
                let items = sources.prefix(6).map { "\($0.name) \($0.things.count)" }
                doc.append("map = TagMap(\(q(String(localized: "What's going on"))), \(q(String(localized: "By app — tags take over as they form"))), [\(items.joined(separator: ", "))], \(q("source")))")
                rootRefs.append("map")
                boardRefs.append("map")
            }
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
        // so the id's seat (arg 8) holds its position.
        let chipsSeat = chips.map { ", \($0)" } ?? ", []"
        // Quiet cover — nothing landed today. The words state the quiet; the
        // chips still show the corpus's composition (a quiet day didn't change
        // what your stuff is made of). No thing id — nothing fresh to open.
        if isQuietDay(things) {
            return "cover = Cover(\(q(String(localized: "Today"))), \(q(String(localized: "A quiet day"))), \(q(String(localized: "Nothing new yet — your things keep."))), \(q("")), \(q(date)), \(q("quiet"))\(chipsSeat), \(q("")))"
        }
        if let latest = things.first(where: { $0.kind != .approval }) {
            // Arg 5 marks the stream complete so the renderer's black field
            // doesn't flash in before the doc settles. Arg 4 (the old banner
            // slot) carries the SOURCE — the card leads with its app icon
            // (2026-07-10, user). Arg 8 is the thing's id — the card opens
            // what landed (2026-07-11, user).
            let subline = chips != nil ? "" : "\(latest.kind.typeTag) · \(latest.source)"
            return "cover = Cover(\(q(String(localized: "Just landed · \(latest.source)"))), \(q(latest.title)), \(q(subline)), \(q(latest.source)), \(q(date)), \(q(latest.kind.typeTag))\(chipsSeat), \(q(latest.id.uuidString)))"
        }
        return "cover = Cover(\(q(String(localized: "Now"))), \(q(String(localized: "Your things go here"))), \(q(String(localized: "Paste, speak, or share one in."))), \(q("")), \(q(date)), \(q("quiet"))\(chipsSeat), \(q("")))"
    }

    // MARK: - Cover chips (the corpus's kind composition — ruling 2026-07-12)

    /// The corpus's kind composition, "[Tag N, ...]", count-ordered, max 5 —
    /// the cover's chip row. Whole corpus, not today or this week: a stable
    /// read of what your stuff is made of, and a tap opens that kind in Feed.
    /// Approvals never count (they're pending asks, not saved things). Nil
    /// only for an all-approval (or empty) corpus.
    private static func coverChips(_ things: [Thing]) -> String? {
        var counts: [ThingKind: Int] = [:]
        for t in things where t.kind != .approval { counts[t.kind, default: 0] += 1 }
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
    private static func appendPinnedApps(_ things: [Thing],
                                         to doc: inout [String],
                                         rootRefs: inout [String],
                                         boardRefs: inout [String],
                                         boardKeys: inout [String: String]) {
        let store = HomePinnedSources.shared
        let onBoard = store.sources
            .union(HomePinnedSources.autoSocial.filter { !store.isHidden($0) })
            .subtracting(mediaSources)
            .sorted()
        var emitted = 0
        for source in onBoard {
            // Pinning doesn't invent content — a source with nothing landed
            // yet shows no tile (its pin persists; the tile appears when the
            // first thing arrives), same rule the media shelves follow. Three
            // is the ceiling now (2026-07-14): big shows all three as a card,
            // wide shows the first as one line, small shows it full-size —
            // no span ever needs a fourth.
            let items = Array(things.filter { $0.source == source }.prefix(3))
            guard !items.isEmpty else { continue }
            let id = "appTile\(emitted)"
            let mail = source == "Gmail" || source == "iCloud Mail"
            let social = HomePinnedSources.autoSocial.contains(source)
            let childIds = items.indices.map { "\(id)c\($0)" }
            doc.append("\(id) = Widget(\(q(appTitle(source))), \(q("")), [\(childIds.joined(separator: ", "))], \(q(source)))")
            for (i, t) in items.enumerated() {
                doc.append(appChild(id: "\(id)c\(i)", t, mail: mail, social: social))
            }
            rootRefs.append(id)
            boardRefs.append(id)
            // Key by SOURCE so the tile's size/slot survive other apps being
            // pinned/unpinned above it — matches HomePinnedSources.boardKey.
            boardKeys[id] = "app:\(source)"
            emitted += 1
        }
    }

    /// A pinned app tile's header — a bespoke phrase where the app has one
    /// (its store preview's voice), else the app's own name. Sentence case,
    /// no eyebrow caps (design law): the words carry it.
    private static func appTitle(_ source: String) -> String {
        switch source {
        case "Gmail", "iCloud Mail":                       return String(localized: "Waiting on you")
        case "GitHub":                                     return String(localized: "In your feed")
        case "Linear":                                     return String(localized: "Assigned to you")
        case "Notion":                                     return String(localized: "Pages")
        case "Reddit", "Raindrop":                         return String(localized: "Saved")
        case "X":                                          return String(localized: "Bookmarked")
        case "YouTube":                                    return String(localized: "Liked and saved")
        case "Twitch":                                     return String(localized: "Live now")
        case "Telegram", "Slack":                          return String(localized: "Worth keeping")
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
                                             pending: Bool = false,
                                             to doc: inout [String],
                                             rootRefs: inout [String],
                                             boardRefs: inout [String],
                                             boardKeys: inout [String: String]) {
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
        }
    }

    // MARK: - Rich module interiors (prd 58, Goal 3)

    /// Music, Pinterest, and screenshots each earn a board module once a
    /// source has landed enough to be worth its own card — same threshold
    /// `sourceClusters` uses for the treemap (2, min-magnitude rule). Social
    /// (Bluesky/Farcaster) earns a card the moment ONE post exists: it's a
    /// single latest-post card, not a magnitude cluster, so there's no
    /// "not enough yet" state to wait out.
    private static func appendMediaModules(_ things: [Thing], to doc: inout [String],
                                           rootRefs: inout [String], boardRefs: inout [String]) {
        let pinned = HomePinnedSources.shared.sources
        // A pinned source (prd 58, Goal 4 — "Pin to Home" on the source's
        // own screen) earns its card the moment it has ONE real thing,
        // instead of waiting to cross the automatic magnitude threshold —
        // pinning doesn't invent content, it just skips the wait.
        func earned(_ items: [Thing], pinnedAs name: String) -> Bool {
            items.count >= 2 || (pinned.contains(name) && !items.isEmpty)
        }
        let music = things.filter { $0.source == "Apple Music" }
        if earned(music, pinnedAs: "Apple Music") {
            appendMediaShelf(id: "musicShelf", eyebrow: "Apple Music", kind: "music",
                             items: music, pinned: pinned.contains("Apple Music"),
                             to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        }
        let pins = things.filter { $0.source == "Pinterest" }
        if earned(pins, pinnedAs: "Pinterest") {
            appendMediaShelf(id: "pinShelf", eyebrow: "Pinterest", kind: "pinterest",
                             items: pins, pinned: pinned.contains("Pinterest"),
                             to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        }
        let shots = things.filter { $0.kind == .screenshot }
        if earned(shots, pinnedAs: "Photos") {
            appendMediaShelf(id: "shotShelf", eyebrow: "Screenshots", kind: "screenshot",
                             items: shots, pinned: pinned.contains("Photos"),
                             to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        }
        // RSS earns its shelf ONLY by an explicit pin — a feed is a firehose,
        // already surfaced in the "What's going on" source map, so it never
        // auto-crosses the magnitude threshold onto the board. Imaged posts
        // lead (a clean magazine strip); a text-only feed still shows its
        // newest as tiles so the pin is never a dead control.
        if pinned.contains("RSS") {
            let rssAll = things.filter { $0.source == "RSS" }
            let imaged = rssAll.filter { !($0.previewImageURL ?? "").isEmpty }
            let rss = imaged.isEmpty ? rssAll : imaged
            if !rss.isEmpty {
                appendMediaShelf(id: "rssShelf", eyebrow: "RSS", kind: "rss",
                                 items: rss, pinned: true,
                                 to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
            }
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
