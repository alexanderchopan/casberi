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
    }

    static func compose(things: [Thing],
                        walletHoldings: [WalletIngest.HoldingsGroup] = [],
                        walletPending: Bool = false,
                        pinCoach: Bool = false) -> Document {
        let projects = projectClusters(things: things)
        return daily(things: things, projects: projects, walletHoldings: walletHoldings,
                     walletPending: walletPending, pinCoach: pinCoach)
    }

    /// True when nothing has landed today — the composition acknowledges the
    /// quiet instead of pretending motion (voice: facts, no obligations).
    private static func isQuietDay(_ things: [Thing]) -> Bool {
        !things.isEmpty && !things.contains { Calendar.current.isDateInToday($0.capturedAt) }
    }

    // MARK: - Documents

    private static func daily(things: [Thing], projects: [Cluster], walletHoldings: [WalletIngest.HoldingsGroup] = [],
                                     walletPending: Bool = false, pinCoach: Bool = false) -> Document {
        var doc: [String] = []
        var rootRefs: [String] = []
        var boardRefs: [String] = []

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

        // Pinned — things the person chose to keep in view, ahead of the map
        // (ruling 2026-07-09): a deliberate choice outranks an automatic
        // clustering, and it shouldn't cost a scroll to reach. User-chosen,
        // so it passes the no-obligations rule: Casberi never picked these.
        appendPinned(things, coach: pinCoach, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
        appendWalletHoldings(walletHoldings, pending: walletPending, to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
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
        return Document(lines: doc, boardRefs: boardRefs)
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

    private static func tagCounts(things: [Thing]) -> [(String, Int)] {
        projectClusters(things: things).map { ($0.name, $0.things.count) }
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

    // MARK: - Line builders

    private static func hero(eyebrow: String, title: String, subline: String) -> String {
        "hero = Hero(\(q(eyebrow)), \(q(title)), \(q(subline)))"
    }

    private static func projectTile(id: String, _ c: Cluster) -> String {
        let sources = Array(Set(c.things.map(\.source))).sorted().prefix(3).joined(separator: ",")
        // Subline reads content, not status: name the kinds inside.
        let kindWords = Array(Set(c.things.map { $0.kind.typeTag.lowercased() + "s" })).sorted().prefix(3)
        let subline = kindWords.joined(separator: ", ").capitalizedFirst
        return "\(id) = ProjectTile(\(q("1")), \(q(c.name)), \(q(sources)), \(q(subline)), \(q(String(localized: "\(c.things.count) things"))), blue)"
    }

    /// Feed pins surface on Home too (ruling 2026-07-06): a pin means "keep
    /// this in view", and Home is the view. Newest first, capped at 6
    /// (raised from 3, prd 50 — a token watchlist alone can fill three
    /// seats). With no pins yet, one retiring coach line takes the slot
    /// (2026-07-10) — the empty Pinned state taught nothing, so a new user
    /// never learned the swipe. The surface owns the retire flag.
    ///
    /// Each pin is its OWN board module now (ruling 2026-07-12): the old
    /// "Pinned" bundle wore an oversized tilted pin and was force-sized big,
    /// so one card looked and behaved unlike every other — a pin is a mark on
    /// a thing, not a kind of card. Every pin is a tile carrying the same
    /// corner pin, sized and reordered on its own; any of them can be grown to
    /// hero. Tokens already composed as their own tiles (a token's content IS
    /// its chart, prd 51); now everything else joins them, in pin order.
    private static func appendPinned(_ things: [Thing], coach: Bool,
                                     to doc: inout [String],
                                     rootRefs: inout [String],
                                     boardRefs: inout [String]) {
        let pinned = things.filter(\.pinned).prefix(6)
        guard !pinned.isEmpty else {
            if coach {
                doc.append("pinCoach = Coach(\(q(String(localized: "Swipe a thing in Feed to pin it here."))))")
                rootRefs.append("pinCoach")
                // The coach line is a lesson, not a card — it isn't dragged.
            }
            return
        }
        for (i, t) in pinned.enumerated() {
            let id = "pn\(i)"
            doc.append(row(id: id, t))
            rootRefs.append(id)
            boardRefs.append(id)
        }
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
                                             boardRefs: inout [String]) {
        for (i, g) in groups.enumerated() {
            let id = "walletMap\(i)"
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
        // Social auto-earns a card from ONE post, but the person can remove it
        // (long-press → Remove from Home, or the source screen's "Show on Home"
        // toggle) — a removed source stays off the board until brought back.
        for source in HomePinnedSources.autoSocial {
            guard !HomePinnedSources.shared.isHidden(source),
                  let latest = things.first(where: { $0.source == source }) else { continue }
            appendSocialCard(id: "social\(source)", source: source, thing: latest,
                             to: &doc, rootRefs: &rootRefs, boardRefs: &boardRefs)
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

    /// SocialCard(source, handle, avatarURL, text, imageURL, thingId,
    /// openable) — the source's single newest post. "Clean" per the ruling:
    /// one card, not a mini-feed.
    private static func appendSocialCard(id: String, source: String, thing t: Thing,
                                         to doc: inout [String], rootRefs: inout [String],
                                         boardRefs: inout [String]) {
        let openable = VerbDerivation.verbs(for: t).contains {
            if case .openURL = $0.action { return true } else { return false }
        } ? "app" : ""
        doc.append("\(id) = SocialCard(\(q(source)), \(q(t.authorHandle ?? "")), \(q(t.authorAvatarURL ?? "")), \(q(t.title)), \(q(t.previewImageURL ?? "")), \(q(t.id.uuidString)), \(q(openable)))")
        rootRefs.append(id)
        boardRefs.append(id)
    }

    /// A token link leads with its price chart, same rule as the thing sheet
    /// (ThingContent.swift) — the token's "media" is the chart, not a link
    /// row. The trailing thing id makes the row interactive on Home (tap
    /// opens, long-press offers Open/Unpin — 2026-07-10).
    private static func row(id: String, _ t: Thing) -> String {
        // Arg 6 marks a thing with a real hand-off destination — the row's
        // long-press offers "Open in app" only when it would actually go
        // somewhere (2026-07-10).
        let openable = VerbDerivation.verbs(for: t).contains {
            if case .openURL = $0.action { return true } else { return false }
        } ? "app" : ""
        if t.kind == .link, let route = TokenChart.route(from: t.content) {
            return "\(id) = TokenRow(\(q(t.title)), \(q(route.chain)), \(q(route.address)), \(q(shortTime(t.capturedAt))), \(q(t.id.uuidString)), \(q(openable)))"
        }
        return "\(id) = Row(\(q(t.title)), \(q(t.kind.typeTag)), \(q(t.source)), \(q(shortTime(t.capturedAt))), \(q(t.id.uuidString)), \(q(openable)))"
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

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
