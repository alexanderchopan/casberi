import SwiftUI
import SwiftData
import Translation

/// Feed — the record paints (M3), and it is ENTIRELY a feed (re-ruling
/// 2026-07-04): source chips, machine presence, then rows. The type chart
/// moved to Home as the kind bar — its segments land here filtered via
/// FeedFilter; an active type filter clears from a chip in the same row.
///
/// SHAPED FEEDS (docs/handoff-shaped-feeds.md): when one source is in force
/// the feed takes that source's native shape — Photos becomes a grid, Zerion
/// leads with the holdings treemap, Calendar reads as an agenda, Gmail
/// surfaces what's waiting, Reminders groups by state, chats earn takeaway
/// cards. Deepened 2026-07-13: notes lead with their text, chats with their
/// opening line, posts read as author-led cards with media at width, Safari
/// reads as a reading list; Music and Tokens carry a lede block; the
/// new-since divider is per-source; each feed closes with a caught-up line.
/// "All" renders kind-aware rows; only `.approval` breaks row rhythm
/// (the consent card). Day groups, pins, swipes, the sheet, and write-confirm
/// all survive inside shapes.
struct FeedScreen: View {
    /// The source this feed IS (2026-07-16, the pager): each page owns one
    /// source for its whole life instead of the whole screen re-reading the
    /// shared filter. `FeedFilter.shared.source` is still the truth for WHICH
    /// page is up — it's the pager's selection — but a page's own shape,
    /// query, and boundary are this.
    let source: String
    /// Whether this page is the one in front. A pager keeps its neighbours
    /// MOUNTED, so `onAppear` stopped meaning "the person is looking at this"
    /// — every per-visit effect (the boundary freeze, the entrance wave, the
    /// synthesis stream, chrome minimizing) gates on this
    /// instead, or a page swiped PAST would burn its arrival unseen and stamp
    /// its own "New since" line away.
    let isActive: Bool

    /// Source-scoped since 2026-07-21 (perf audit): the pager keeps every
    /// neighbor page MOUNTED (doc above), so an unfiltered `@Query` here used
    /// to mean N+1 live full-corpus queries (one per source chip, plus
    /// MainSurface's own) — a write to ANY thing, anywhere, re-materialized
    /// and re-filtered the whole corpus on every one of them. Each page now
    /// only ever observes its own source's rows; only the "All" page still
    /// queries everything, because it genuinely shows everything.
    @Query private var things: [Thing]
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.modelContext) private var modelContext

    init(source: String, isActive: Bool) {
        self.source = source
        self.isActive = isActive
        if source == "All" {
            _things = Query(sort: \Thing.capturedAt, order: .reverse)
        } else {
            _things = Query(filter: #Predicate<Thing> { $0.source == source },
                            sort: \Thing.capturedAt, order: .reverse)
        }
    }

    /// Only `tag` is read from here now — a kind filter is a cross-page state
    /// (it arrives from Home's kind bar and applies to the All room).
    @State private var filter = FeedFilter.shared
    /// The one sheet this screen can have open at a time (2026-07-24, fixing
    /// prd §196's "opens and dismisses itself on first try"). Five separate
    /// `.sheet` modifiers stacked on one view — thing/token/combined
    /// wallets/allocation/Worth-a-look — fought each other for the
    /// presentation controller: SwiftUI only reliably drives one
    /// `.sheet(item:)` + one `.sheet(isPresented:)` per view, and past that
    /// the first tap's controller got torn down mid-present by a sibling's
    /// state settling, so it flashed open and closed; the second tap then
    /// worked because the machinery had quieted. One enum route behind one
    /// `.sheet(item:)` removes the contention entirely.
    private enum FeedSheetRoute: Identifiable {
        case thing(Thing)
        case token(TokenQuickRoute)
        case allocation
        case worthALook

        var id: String {
            switch self {
            case .thing(let t): "thing:\(t.id.uuidString)"
            case .token(let r): "token:\(r.id)"
            case .allocation: "allocation"
            case .worthALook: "worthALook"
            }
        }
    }
    @State private var feedSheet: FeedSheetRoute?
    @State private var confirming: (Verb, Thing)?
    /// Translate verb, swipe-triggered — same system sheet as ThingSheetView's.
    @State private var showTranslate = false
    @State private var translateText = ""
    @State private var staleExpanded = false
    @State private var blockStream = GenStream()
    // GitHub's contribution graph rides the TOP of its own source feed (moved
    // off Home, 2026-07-18): the green-squares year is a GitHub thing, so it
    // belongs where GitHub lives. Self-fetching @Observable store, same one the
    // graph always used; the hero only paints once a real year with
    // contributions has landed (an empty grid is a skeleton, not content).
    @State private var githubGraph = GitHubGraphStore.shared
    @Bindable private var wallet = WalletStore.shared
    /// The wallet the Wallet feed is scoped to (prd §128) — nil is "All", the
    /// combined view. Set by the switcher chip strip at the top of the wallet
    /// feed; scopes the balance lede, holdings treemap, NFT strip, and the
    /// transaction rows to one watched wallet. Only meaningful on the Wallet
    /// page (each FeedScreen owns one source); nil everywhere else.
    @State private var selectedWallet: String?
    /// The Wallet feed's live reads (2026-07-20) — Aave positions and the
    /// warnings rolled up from them plus Safe/poisoning/delegation. Never a
    /// landed thing: re-read each time this feed comes forward or its scope
    /// changes, exactly as the manage screen used to hold it.
    @State private var walletLive = WalletLiveState()
    /// The combined portfolio behind the treemap (2026-07-21, prd §155) — one
    /// derivation the balance headline, the concentration line, and the
    /// allocation tray all read, so nothing on this screen can disagree with
    /// the map it's standing under. Lands with the treemap doc, from the same
    /// read.
    @State private var portfolio: WalletPortfolio?
    /// The full allocation tray — every position and which wallets hold it.
    /// Routed through `feedSheet` (`.allocation`) now, not its own bool.
    /// The balance line's window (prd §155). Narrowed to what the record can
    /// actually answer each render; the choice persists across launches.
    @State private var balanceRange: WalletRange = .watched
    /// The wallet switcher's selection fill — ONE capsule that slides from
    /// the old chip to the new (the source chips' own ruling, 2026-07-14:
    /// "selection is an object traveling, not two states blinking").
    @Namespace private var walletSwitcherNS
    /// Bumped when this page lands — rows replay their shape's
    /// entrance (each shape arrives its own way, ruling 2026-07-07).
    @State private var shapeWave = 0
    /// The last time the person left THIS feed ("feed.lastSeen" is All's
    /// original key, so nothing migrates), no per-thing read state. The
    /// boundary freezes when the page lands and holds for the whole visit
    /// (ruling 2026-07-09: the divider never moves while you look at it — a
    /// bounce out and back must not erase it), and stamps when the page is
    /// left. The old per-source dictionary + visited SET are gone with the
    /// pager (2026-07-16): one screen used to serve every room, so it had to
    /// remember which rooms it had been; a page IS its room and can only ever
    /// stamp its own key. That also retires the 2026-07-13 bug those guards
    /// existed for (the shared filter reading "Pinned" while this screen went
    /// away, stamping a junk key) — this page never sees another room's name.
    @State private var newSince: Date?
    @State private var visitFrozen = false
    /// A tapped Themes cell (2026-07-18, the All feed's own treemap) — the
    /// same project detail door Home's map already opened.
    @State private var openProject: ProjectRoute?
    /// Themes stays expanded for the rest of THIS session once tapped open
    /// (2026-07-20) — session-only by design; a fresh mount re-checks the
    /// digest and may collapse again.
    @State private var themesExpanded = false
    private static let themesSeenDigestKey = "feed.themesSeenDigest"
    struct ProjectRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }
    @Namespace private var zoomNS
    /// prd 43h: Reduce Motion is law — the hand-rolled moves (row entrances)
    /// fall back to plain state changes under it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// The shape a source takes when its chip is in force.
    private enum Shape {
        case all, photos, wallet, calendar, gmail, chat, social, reminders, safari, notes, you, music, tokens, bitrefill, oneclaw, plain
        init(source: String) {
            switch source {
            case "All":                 self = .all
            case "Photos":              self = .photos
            case "Wallet":              self = .wallet
            case "Calendar", "Cal.com", "Calendly": self = .calendar
            case "Gmail", "iCloud Mail": self = .gmail
            case "ChatGPT", "Claude", "Gemini": self = .chat
            // Posts read as posts in their own room (2026-07-13) — split from
            // .chat: a saved conversation is a snippet row, a post is a card.
            case "Farcaster", "Bluesky": self = .social
            case "Reminders", "Todoist": self = .reminders
            case "Safari":              self = .safari
            // Obsidian joins the notes room — the vault is notes (prd §59).
            case "Notes", "Day One", "Apple Journal", "Obsidian": self = .notes
            case "You", "Voice":        self = .you
            case "Apple Music", "Spotify": self = .music
            case "Tokens":              self = .tokens
            case "Bitrefill":           self = .bitrefill
            case "1Claw":               self = .oneclaw
            default:                    self = .plain
            }
        }
    }
    private var shape: Shape { Shape(source: source) }


    /// How this shape's rows arrive: the agenda slides in from the leading
    /// edge like a day filling, photos scale in like the grid, transactions
    /// rise like entries posting, everything else lifts gently.
    private var entranceStyle: RowEntrance.Style {
        switch shape {
        case .calendar: .init(dx: -28, dy: 0, scale: 1, step: 0.045)
        case .wallet, .tokens: .init(dx: 0, dy: 16, scale: 1, step: 0.04)
        case .photos:   .init(dx: 0, dy: 0, scale: 0.92, step: 0.03)
        case .music:    .init(dx: 0, dy: 10, scale: 1, step: 0.035)
        case .social:   .init(dx: 0, dy: 12, scale: 0.98, step: 0.035)
        default:        .init(dx: 0, dy: 8, scale: 1, step: 0.028)
        }
    }

    // MARK: - Derivations

    /// The corpus MINUS the search-only sources — Contacts land as things for
    /// lookup and the answer path, but never as feed rows or a source chip
    /// (ruling 2026-07-12): hundreds of names would bury the day's captures.
    /// One rule (`Corpus.surfaced`), shared with Home's synthesis.
    private var feedThings: [Thing] { Corpus.surfaced(things) }

    private var visible: [Thing] {
        feedThings.filter { thing in
            (source == "All" || thing.source == source)
                && (filter.tag == "All" || thing.tags.contains(filter.tag))
                && walletScopeAllows(thing)
        }
    }

    /// The Wallet feed's per-wallet scope (prd §128) — everything passes in
    /// "All" (selectedWallet nil, and it's never set off the Wallet page); when
    /// scoped, only transactions from that watched wallet. Matched through
    /// `WalletStore.scopeMatches` (2026-07-20): things are stamped with the
    /// RESOLVED hex while the scope is the WATCHED spelling, so the old raw
    /// compare emptied an ENS/SNS-watched wallet's scoped feed entirely.
    private func walletScopeAllows(_ thing: Thing) -> Bool {
        guard let scope = selectedWallet else { return true }
        return wallet.scopeMatches(thing.walletAddress, scope: scope)
    }
    private var isFiltered: Bool { source != "All" || filter.tag != "All" }
    private var filterLabel: String {
        let tagLabel = filter.tag == "All" ? nil
            : (ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag)
        return [source == "All" ? nil : source, tagLabel]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The connected bridge the feed is currently filtered to, if any. A source
    /// header appears only for a real, live seat — a plain source (Photos,
    /// Voice, Safari) owns no control panel, so it gets no door. Paused seats
    /// aren't "connected", so they don't either.
    private var activeSourceBridge: BridgeApp? {
        guard source != "All" else { return nil }
        return bridges.bridges.first { $0.name == source && $0.status != .paused }
    }

    /// Day groups, newest day first ("Today", "Yesterday", then dated). A feed
    /// is history — it reads from today back. A reminder/event lands with
    /// `capturedAt` set to when it's DUE, so a future-dated thing sorts newest
    /// by raw time and would LEAD the feed — a Wednesday sitting above Today
    /// (user, 2026-07-19). What's still ahead lives on Home's "Coming up" lane,
    /// not here, so future days are dropped from the walk; the feed starts on
    /// Today. (Timed things still to come LATER today stay under Today — the
    /// day, not the clock, is what leads.)
    private func dayGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let today = Self.groupingCalendar.startOfDay(for: .now)
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for thing in visible
        where Self.groupingCalendar.startOfDay(for: thing.capturedAt) <= today {
            let label = dayLabel(thing.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(thing)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Day groups, but COARSENED to week/month grain when the source lands
    /// sparsely (ruling 2026-07-21, the day-cards sequel): a source that
    /// drops one thing most days would otherwise become a ladder of one-row
    /// day cards under big headers — exactly the confetti day-cards killed,
    /// re-expressed as headers. When the trailing history averages under
    /// ~1.5 things a day (and there's enough of it to judge), the same rows
    /// regroup as "This week / Last week / <month>" instead. A dense feed
    /// (social bursts, an RSS sync) stays day-grained untouched — this is a
    /// no-op above the threshold, so every chronological source can route
    /// through it safely.
    private func chronoGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        coarsenIfSparse(dayGroups(visible))
    }

    /// The sparseness gate + regroup, shared by the plain day path and the
    /// agent path (which builds its own day groups first). Judged on the
    /// SHOWN things (dayGroups already dropped future-dated rows), so the
    /// average matches what the feed actually renders.
    private func coarsenIfSparse(_ days: [(String, [Thing])]) -> [(String, [Thing])] {
        let shown = days.flatMap { $0.1 }
        guard days.count >= 6,
              Double(shown.count) / Double(days.count) < 1.5 else { return days }
        return coarseGroups(shown)
    }

    /// Regroup already-ordered (newest-first) things by week, then month —
    /// "This week", "Last week", then month names for the tail (a week grain
    /// that ran all the way down would ladder into "3 weeks ago, 4 weeks
    /// ago"; months are how sparse history actually reads back).
    private func coarseGroups(_ things: [Thing]) -> [(String, [Thing])] {
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for t in things {
            let label = coarseLabel(t.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(t)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private func coarseLabel(_ date: Date) -> String {
        let cal = Self.groupingCalendar
        if cal.isDate(date, equalTo: .now, toGranularity: .weekOfYear) {
            return String(localized: "This week")
        }
        if let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: .now),
           cal.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear) {
            return String(localized: "Last week")
        }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// Music lands in SITTINGS, not calendar days (ruling 2026-07-21) — the
    /// day header answers "when" but the real unit of listening is the
    /// session. Consecutive plays less than 45 min apart cluster into one
    /// group, labelled by its start ("This morning", "Yesterday evening",
    /// "Mon evening"). A single session that straddles the whole day still
    /// reads as one card; two listens hours apart split honestly.
    private func sessionGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let sorted = visible.sorted { $0.capturedAt > $1.capturedAt }
        guard let first = sorted.first else { return [] }
        let gap: TimeInterval = 45 * 60
        var sessions: [[Thing]] = []
        var current: [Thing] = [first]
        for t in sorted.dropFirst() {
            if let last = current.last,
               last.capturedAt.timeIntervalSince(t.capturedAt) <= gap {
                current.append(t)
            } else {
                sessions.append(current)
                current = [t]
            }
        }
        sessions.append(current)
        let labelled = sessions.map { (sessionLabel($0.first!.capturedAt), $0) }
        // groupedSections keys its ForEach on the label, so two sittings that
        // share one ("this morning" twice, >45 min apart) would collide into
        // one SwiftUI id. Append the start clock ONLY to a colliding label, so
        // the common single-session case stays clean.
        var counts: [String: Int] = [:]
        for (label, _) in labelled { counts[label, default: 0] += 1 }
        return labelled.map { label, rows in
            guard (counts[label] ?? 0) > 1 else { return (label, rows) }
            let time = rows.first!.capturedAt.formatted(date: .omitted, time: .shortened)
            return ("\(label) · \(time)", rows)
        }
    }

    private func sessionLabel(_ date: Date) -> String {
        let cal = Self.groupingCalendar
        let part: String
        switch cal.component(.hour, from: date) {
        case 5..<12:  part = String(localized: "morning")
        case 12..<17: part = String(localized: "afternoon")
        case 17..<22: part = String(localized: "evening")
        default:      part = String(localized: "late night")
        }
        if cal.isDateInToday(date) {
            return String(localized: "This \(part)")
        }
        if cal.isDateInYesterday(date) {
            return String(localized: "Yesterday \(part)")
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(part)"
    }

    // MARK: - Bundling (ruling 2026-07-09: volume compresses, never reorders)

    /// A feed row in the All shape: a thing, or one row standing in for a
    /// source's bulk arrivals that day.
    /// `id` and `date` are STORED, captured at construction — never computed
    /// off the wrapped `Thing` on demand (2026-07-24 crash fix). As an enum
    /// whose `id` read `t.id.uuidString` lazily, `ForEach`'s identity diffing
    /// (`ForEachChild.updateValue()`) reached into the SwiftData model every
    /// graph update; when a launch-time dedupe (`SyncReconcile`) or a CloudKit
    /// merge deleted that `Thing` mid-render, the read trapped inside SwiftData
    /// (`_assertionFailure`) — the field crash reported as "crashes on open
    /// after an update, never on a fresh install," since only an updated
    /// install has synced duplicates to delete. Capturing the id/date as plain
    /// value types at construction (below, while the `Thing` is still valid)
    /// keeps the diffing path off the model entirely; the model is only touched
    /// in the row body, which renders exclusively from the post-delete `@Query`
    /// snapshot that already excludes the deleted row.
    private struct FeedRow: Identifiable {
        let id: String
        let date: Date
        let kind: Kind
        enum Kind {
            case single(Thing)
            /// `art`: up to three member preview-image URLs, newest first — the
            /// bundle's own pictures (2026-07-21), so "Shopify · 100 products"
            /// can show what actually arrived instead of one brand glyph.
            case bundle(source: String, word: String, count: Int, newest: Date, art: [String])
        }
        static func single(_ t: Thing) -> FeedRow {
            FeedRow(id: t.id.uuidString, date: t.capturedAt, kind: .single(t))
        }
        static func bundle(source: String, word: String, count: Int,
                           newest: Date, art: [String]) -> FeedRow {
            FeedRow(id: "bundle-\(source)-\(newest.timeIntervalSince1970)", date: newest,
                    kind: .bundle(source: source, word: word, count: count,
                                  newest: newest, art: art))
        }
    }

    /// A `Thing` paired with its identity captured as a plain `String` — so a
    /// `ForEach` over a DERIVED thing array (a shaped feed, the photo grid)
    /// keys on a value, never reaching into the SwiftData model during
    /// identity diffing (`ForEachChild.updateValue()`). Same 2026-07-24 crash
    /// class as `FeedRow`: when a launch-time dedupe or a CloudKit merge
    /// deletes/invalidates a `Thing` mid-render, reading its `id` off the model
    /// while `ForEach` reconciles the OLD (now-stale) children traps inside
    /// SwiftData — only on an updated install, never a fresh one. The row body
    /// still uses `.thing`, but bodies only ever render the post-delete
    /// `@Query` snapshot, which already excludes the deleted row.
    private struct KeyedThing: Identifiable {
        let id: String
        let thing: Thing
        init(_ t: Thing) { id = t.id.uuidString; thing = t }
    }
    private func keyed(_ things: [Thing]) -> [KeyedThing] { things.map(KeyedThing.init) }

    /// Machine bulk bundles; human captures never do. A screenshot, a voice
    /// note, or anything typed/pasted is one deliberate act each — an RSS
    /// sync or a wallet backfill is one act producing many rows.
    private func bundleable(_ t: Thing) -> Bool {
        t.kind != .screenshot && t.kind != .voice && t.kind != .approval
            && t.source != "You" && t.source != "Voice"
            // Social posts read individually — you follow an account to SEE the
            // posts, so Bluesky/Farcaster never collapse into an "N links"
            // bundle (user, 2026-07-12). They're deliberate reads, not machine
            // bulk like an RSS sync or a wallet backfill.
            && t.source != "Bluesky" && t.source != "Farcaster"
            // Same reasoning for watched tokens: each row wears its own
            // sparkline (TokenPulse) — collapsing 3+ into "Tokens · N things"
            // silently drops every one of them.
            && t.source != "Tokens"
            // And Bitrefill orders: each wears the product's own artwork and a
            // "name · $value" title (prd §103). They're deliberate purchases,
            // low volume — not machine bulk — so a gift-card spree stays
            // legible row by row instead of "Bitrefill · N things".
            && t.source != "Bitrefill"
            // And 1Claw grants: policies are typically created together, so
            // they share a created_at day — bundled, the grant table the
            // bridge exists to show collapses into "1Claw · N links".
            && t.source != "1Claw"
    }

    /// 3+ bundleable things from one source in one day collapse into a
    /// BundleRow at the position of their newest member (threshold lowered
    /// from 4, 2026-07-12 — smaller same-source runs were the real All-feed
    /// clutter). Order is untouched otherwise — compression, not ranking.
    /// Takes the already-computed day groups so the caller derives `dayGroups`
    /// (→`visible`→`feedThings`) ONCE per render and reuses it for the day
    /// totals too, instead of rebuilding the whole chain here a second time.
    private func bundle(_ days: [(String, [Thing])]) -> [(String, [FeedRow])] {
        days.map { label, dayThings in
            var counts: [String: Int] = [:]
            for t in dayThings where bundleable(t) { counts[t.source, default: 0] += 1 }
            let bundledSources = Set(counts.filter { $0.value >= 3 }.keys)
            var rows: [FeedRow] = []
            var seen: Set<String> = []
            for t in dayThings {
                if bundleable(t), bundledSources.contains(t.source) {
                    guard !seen.contains(t.source) else { continue }
                    seen.insert(t.source)
                    let members = dayThings.filter { bundleable($0) && $0.source == t.source }
                    let kinds = Set(members.map(\.kind))
                    let word = kinds.count == 1
                        ? kinds.first!.typeTagPlural.lowercased() : "things"
                    // The bundle's own pictures — the first three members
                    // that actually carry art, in feed order (newest first,
                    // since dayThings is).
                    let art = members.compactMap { m -> String? in
                        guard let a = m.previewImageURL, !a.isEmpty else { return nil }
                        return a
                    }.prefix(3)
                    rows.append(.bundle(source: t.source, word: word,
                                        count: members.count, newest: t.capturedAt,
                                        art: Array(art)))
                } else {
                    rows.append(.single(t))
                }
            }
            return (label, rows)
        }
    }

    /// The first row at-or-past the last-visit boundary — the "new since"
    /// divider renders above it. Nil when nothing is new (no divider at the
    /// very top) or everything is (no divider at the very bottom).
    ///
    /// Takes the already-bundled groups so the caller computes them ONCE per
    /// render and shares them — as a bare computed property this rebuilt the
    /// whole bundle chain, and it was read once per row (the Feed-freeze
    /// O(rows × corpus) blowup, perf pass 2026-07-13).
    private func boundaryID(in groups: [(String, [FeedRow])]) -> String? {
        guard let newSince else { return nil }
        let all = groups.flatMap(\.1)
        guard let first = all.first, first.date > newSince else { return nil }
        return all.first(where: { $0.date <= newSince })?.id
    }

    // MARK: - Body

    var body: some View {
        // The single surface owns the NavigationStack, the chip header, and the
        // shared doors now (MainSurface) — this is just the feed's body, hosted
        // inside that one stack. Its own inner push (a bridge control panel)
        // stays here; Apps/Settings moved up to the shell.
        feedList
            // Re-tapping the active chip pops this surface's own pushed
            // screens and sheets back to root (the old per-tab pop habit).
            .onChange(of: chrome.popHome) {
                feedSheet = nil
                HomeRoute.shared.path = []
                confirming = nil
            }
    }

    /// A slim, tappable strip above a single source's shaped feed: the app, its
    /// live status. Tapping opens the app's control panel through the router —
    /// the dedicated screen when the bridge has one (Tokens' watchlist,
    /// Wallet's addresses), the generic detail page otherwise. It rides
    /// `HomeRoute.shared.pushBridge` — the same channel a Wallet row already
    /// uses. (2026-07-11:
    /// this hardcoded `.detail`, so Tokens' Feed header opened a page with
    /// no way to watch a second token.)
    ///
    /// A slim capsule now, not a card (2026-07-14, user: the full-width block
    /// read as a settings panel dropped into the feed). Picked from three
    /// on-sim mocks — this one echoes the Dynamic-Island-style pill already
    /// riding the top of the screen instead of introducing a new rectangular
    /// shape, and it hugs its own content instead of stretching edge to edge.
    /// The per-row brand icon is gone too (it doubled the same icon in the
    /// source chip right above) — a status dot carries connection health
    /// instead.
    private func sourceHeader(_ bridge: BridgeApp, showAddHint: Bool,
                              headerCompose: SourceAction? = nil) -> some View {
        HStack(spacing: DS.Space.s2) {
        Button {
            DSHaptic.selection()
            HomeRoute.shared.pushBridge(BridgeRouter.destination(forID: bridge.id))
        } label: {
            HStack(spacing: DS.Space.s2) {
                // A glyph, not a bare dot: the three states were one shape
                // in three hues (2026-07-21). Sized to the old 6pt dot's
                // footprint so the header's rhythm is unchanged.
                Image(systemName: bridge.status.glyph)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(bridge.status == .connected ? DS.confirm
                                                                 : bridge.status.color)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(Text(bridge.status.spoken))
                HStack(spacing: 4) {
                    Text(bridge.name).fontWeight(.semibold).foregroundStyle(DS.textPrimary)
                    Text(bridge.statusLine)
                        .foregroundStyle(bridge.status == .connected ? DS.textSecondary : bridge.status.color)
                }
                .dsText(.subhead13)
                .lineLimit(1)
                // A watch/follow source advertises "there's more in here" — the
                // add-another action folds into this one capsule (which already
                // opens the same setup screen) rather than a second stacked row
                // (user, 2026-07-12). Compose sources keep their own row instead
                // — that action leaves for another app, a genuinely other place.
                Rectangle()
                    .fill(DS.textTertiary.opacity(0.3))
                    .frame(width: 1, height: 12)
                if showAddHint {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.tint)
                } else {
                    // Names the destination (2026-07-15, user: the quiet
                    // chevron read as pure status, not a control — this
                    // capsule already says "connected", so tapping it felt
                    // unclear). "Manage" not "Settings": that word is
                    // already claimed by the global Settings screen, and
                    // these panels are add/remove/disconnect surfaces, not
                    // toggle panes.
                    Text("Manage")
                        .dsText(.subhead13).fontWeight(.medium)
                        .foregroundStyle(DS.tint)
                }
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(DS.surfaceSheet, in: Capsule(style: .continuous))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Compose folds into this row as a trailing pill — "New event" /
        // "New email" / "New task" — instead of a full-width bar below (user
        // ruling 2026-07-14). It leaves for another app, so it stays a
        // distinct control from the capsule; same neutral surface, tint on
        // the label alone.
        if let headerCompose {
            Spacer(minLength: DS.Space.s2)
            Button {
                DSHaptic.selection()
                if case .openURL(let url) = headerCompose.run { openURL(url) }
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(headerCompose.label))
                        .dsText(.subhead13).fontWeight(.medium)
                }
                .foregroundStyle(DS.tint)
                .padding(.horizontal, DS.Space.s3)
                .frame(height: 30)
                .background(DS.surfaceSheet, in: Capsule(style: .continuous))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        }
        .padding(.horizontal, DS.Space.s4)
        // A generous gap above the capsule (2026-07-14, user: s3/12pt read as
        // still touching the chip row) — the chips are the strip, the capsule
        // is clearly its own thing below it.
        .padding(.top, DS.Space.s8)
        .padding(.bottom, DS.Space.s2)
    }

    /// The GitHub source feed's lede — "Your year in code · N contributions"
    /// and the green-squares grid, drawn on device and cached in
    /// `GitHubGraphStore` (the same store, and reusing `ContributionGraph`, that
    /// the retired Home tile used). Paints only for a real year with
    /// contributions (an empty grid is a skeleton, not content); the fetch that
    /// seeds that year runs from the List's own `.task` (see feedList), not
    /// here — a conditionally-empty view's `.task` wouldn't fire.
    @ViewBuilder private var githubGraphHero: some View {
        if let year = githubGraph.year, year.total > 0 {
            CalendarHeatmapHero(title: "Your year in code",
                                subtitle: "\(year.total.formatted()) contributions",
                                year: year)
        }
    }

    private var feedList: some View {
        List {
            Group {
                // The source chips moved to the shell's fixed header
                // (MainSurface / SourceChips) — the app is one surface now. What
                // stays here is the kind-clear chip: Home's kind bar and the
                // casberi://feed/type/<Tag> route can land the feed filtered by
                // type, and that filter clears from a chip in place.
                if filter.tag != "All" {
                    let label = ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag
                    HStack(spacing: DS.Space.s1) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(label).dsText(.label12)
                    }
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s3).frame(height: 28)
                    .background(DS.tintDim, in: Capsule(style: .continuous))
                    .padding(.leading, DS.Space.s4)
                    .padding(.bottom, DS.Space.s2)
                    .onTapGesture {
                        DSHaptic.selection()
                        withAnimation(DS.Motion.standard) { filter.tag = "All" }
                    }
                    .accessibilityLabel("Clear \(label) filter")
                }
                // The door back to the app: when the feed wears one connected
                // source's shape, its header opens that app's control panel
                // (Pause/Remove/ask/Reconnect) — the reverse of the detail's
                // "All in Feed". It lives inside this always-present group so it
                // inserts reliably on mount (a standalone conditional row won't).
                if let bridge = activeSourceBridge {
                    let action = SourceActions.action(forSource: bridge.name)
                    // Both actions fold into the header row now (user ruling
                    // 2026-07-14: the full-width compose bar read as an empty
                    // stretch). Expand (add-another) is a "+" hint inside the
                    // capsule — same setup screen the capsule already opens.
                    // Compose is a trailing labeled pill — it leaves for another
                    // app, a genuinely other place, so it stays a distinct
                    // control beside the capsule, not folded into it. Read-only
                    // sources get neither.
                    let composeAction: SourceAction? = {
                        if let action, case .openURL = action.run { return action }
                        return nil
                    }()
                    let showsAddHint: Bool = {
                        if let action, case .route = action.run { return true }
                        return false
                    }()
                    sourceHeader(bridge, showAddHint: showsAddHint,
                                 headerCompose: composeAction)
                }
                // GitHub's source feed leads with its contribution graph (moved
                // off Home, 2026-07-18). Gated on the source STRING, not the
                // BridgeStore seat — the graph belongs to GitHub's token
                // (`GitHubGraphStore` self-fetches with it), so it rides the
                // GitHub feed whenever it's the filter; the hero self-checks for
                // a landed year and takes no room otherwise.
                if source == "GitHub" { githubGraphHero }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())

            if feedThings.isEmpty {
                Group { emptyState }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                // Derived ONCE per render and threaded into everything below
                // — the day groups, ledes, and per-row hint/next-event ids
                // all share this one filter pass instead of each re-deriving
                // it from `feedThings` (the Feed-freeze rule, perf pass
                // 2026-07-13, extended to `visible` itself).
                let visible = self.visible
                if visible.isEmpty {
                    Group { filteredEmptyState }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                } else {
                    let nextID = nextEventID(visible)
                    // A pin is a HOME pin only (ruling 2026-07-10): the Feed's
                    // own Pinned section doubled what Home already shows and
                    // cluttered the record — pinned things now ride the feed in
                    // their natural chronological place. The holdings module
                    // lives on Home too (same-day amendment) — in Feed it shows
                    // only in the Wallet chip's own shape, never leading All.
                    shapedSections(visible, nextEventID: nextID)
                    // No closing line in the Reminders shape: its state groups
                    // deliberately render a subset (Done shows same-day only), so
                    // a `visible`-count claim would disagree with the rows above.
                    // Wallet joined it (2026-07-20) for the same reason — it
                    // previews five and hands off to the history page, so
                    // "that's everything · 131 transactions" under five rows was
                    // a flat lie. Its own "See all transactions · 131" row is
                    // the honest close.
                    if shape != .reminders && shape != .wallet {
                        caughtUpFooter(visible)
                    }
                }
            }

            // Room for the floating bar.
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        // ONE pull, both outcomes. This List carried TWO `.refreshable` until
        // 2026-07-16 — SwiftUI keeps the outermost, so the real bridge sync
        // never ran on a pull; only the 600ms pulse stub did.
        .refreshable {
            // A pull inside one source's own feed rains in ITS hue instead
            // of the app's default berry blue — "All" keeps the default
            // (delight pass 2026-07-21). Set once; both this bump and
            // refreshFeed()'s own read the same stored hue.
            // Scoped to one wallet, the rain falls in THAT wallet's colour
            // (prd §171, 2026-07-22) — the crown already retints on a scope
            // switch (§159), so the refresh that follows should agree. Every
            // other room keeps the source's hue; "All" keeps the default berry.
            chrome.refreshHue = source == "Wallet"
                ? (selectedWallet.map(WalletFace.tint) ?? DS.washHue(for: source))
                : (source == "All" ? nil : DS.washHue(for: source))
            chrome.refreshPulse += 1   // spins the avatar door, deals the berry rain
            await refreshFeed()
        }
        .animation(DS.Motion.standard, value: things.count)   // new things rise in
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        // Seed/refresh the contribution year from a RELIABLE always-present spot
        // (the conditionally-empty hero's own `.task` doesn't fire until a year
        // lands — chicken-and-egg). `source` is fixed per feed instance, so this
        // runs once when the GitHub feed appears; `refreshIfStale` self-guards.
        .task { if source == "GitHub" { await githubGraph.refreshIfStale() } }
        // The page coat moved UP to the shell (prd §159, 2026-07-21): the crown
        // pour lives in MainSurface's background so it can run behind the chip
        // strip, and painting the opaque themed coat again HERE would slide
        // black between that field and the content — the exact hard seam the
        // first, page-level cut of the pour produced (§158's version, retired
        // the same day). Only a chosen background PHOTO still renders
        // per-screen: it's the person's own atmosphere, covers the pour on
        // purpose, and DSPageBackground's scrim is part of its treatment.
        .background {
            if ThemeStore.shared.backgroundPhoto != nil { DSPageBackground() }
        }
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollIndicators(.hidden)
        .minimizesChrome(chrome, active: isActive)
        .safeAreaInset(edge: .top, spacing: 0) { walletSwitcherBar }
        .dsSoftScrollEdges()
        // Arrival is `isActive`, not `onAppear` (2026-07-16, the pager): a
        // mounted neighbour appears without ever being looked at, so landing
        // effects hang off the front page changing, and leaving stamps the
        // boundary on the way out.
        .onAppear {
            #if DEBUG
            // `-feedSource Zerion` lands on that chip for screenshots. From
            // the front page only — three mounted pages would each write it.
            if isActive, let src = UserDefaults.standard.string(forKey: "feedSource") {
                filter.source = src
            }
            #endif
            if isActive { land() }
        }
        .onDisappear { if visitFrozen { leave() } }
        .onChange(of: isActive) { _, now in
            if now { land() } else { leave() }
        }
        // Adding/removing a watched wallet re-fetches the Wallet chip's
        // holdings block — only on the page in force; a background Wallet
        // page has no reason to re-hit Alchemy.
        .onChange(of: wallet.addresses) {
            // A scope whose wallet dropped (or the list fell back to one)
            // returns to All rather than stranding the feed on a gone wallet.
            if let sel = selectedWallet,
               wallet.addresses.count <= 1
                || !wallet.addresses.contains(where: { walletSameAddress($0.address, sel) }) {
                selectedWallet = nil
            }
            if isActive { streamBlock(); loadWalletLive() }
        }
        // Scoping to a wallet (or back to All) re-paints the treemap/NFT strip
        // AND re-reads the live tiles for that scope; the rows and balance
        // re-derive from state.
        .onChange(of: selectedWallet) {
            if isActive {
                streamBlock(); loadWalletLive()
                // A scope switch retints the crown mid-flight with the
                // switcher capsule (prd §159).
                chrome.pourHue = selectedWallet.map(WalletFace.tint)
            }
        }
        .navigationDestination(item: $openProject) { route in
            ProjectDetailScreen(projectName: route.name)
                .navigationTransition(.zoom(sourceID: route.name, in: zoomNS))
        }
        // One `.sheet(item:)` for every sheet this screen presents — see
        // `FeedSheetRoute`'s doc comment for why five separate `.sheet`
        // modifiers here caused the first tap to silently self-dismiss.
        .sheet(item: $feedSheet) { route in
            switch route {
            case .thing(let thing):
                ThingSheetView(thing: thing)
                    .navigationTransition(.zoom(sourceID: thing.id, in: zoomNS))
            case .token(let route):
                TokenQuickSheet(route: route)
            case .allocation:
                if let portfolio {
                    WalletAllocationTray(portfolio: portfolio)
                }
            case .worthALook:
                WalletWorthALookTray(
                    warnings: walletLive.warnings,
                    flagged: walletLive.flagged,
                    activeApprovals: walletLive.activeApprovals)
            }
        }
        .translationPresentation(isPresented: $showTranslate, text: translateText)
        .confirmationDialog(
            // Guard the held `Thing` with `isLive` (2026-07-24 crash class):
            // a background heal can delete this exact thing while the dialog
            // sits open, and reading `$0.1.title` on a dead model traps. If it
            // dies, the presentation binding flips false and the dialog leaves.
            confirming.map { $0.1.isLive ? "\($0.0.label): \($0.1.title)?" : "" } ?? "",
            isPresented: Binding(get: { confirming?.1.isLive == true },
                                 set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let (verb, thing) = confirming, thing.isLive {
                Button(verb.label) { if thing.isLive { perform(verb, on: thing) }; confirming = nil }
                Button("Cancel", role: .cancel) { confirming = nil }
            }
        }
    }

    // MARK: - Shaped sections (one source in force = its native shape)

    /// Takes the render's one `visible` derivation (and the hint/next-event
    /// ids computed alongside it) and threads them into every shape branch —
    /// none of the branches below re-derive `visible` themselves.
    @ViewBuilder
    private func shapedSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        // The new-since divider rides every chronological shape now
        // (2026-07-13) — each source's feed keeps its own last-visit stamp.
        // Photos (a grid), Calendar (future-first) and Reminders (state
        // groups) aren't chronological top-to-bottom, so no line there.
        //
        // A per-source feed overview leads the rows — derived from THIS feed's
        // own things (the same `visible`), above whatever shape they take below.
        // Each source qualifies for at most one: a habit heatmap, a ranked-bars
        // leaderboard, a distribution bar, or a thumbnail mosaic. All render only
        // when the real data is there (guards live in FeedHeatmap / FeedInsight).
        // Derived once and reused: `heroShown` lets a shape's own recap lede
        // (music's "today", Gmail's "waiting") yield so a feed never stacks two
        // overview cards — the lede's records still ride the rows below.
        let heatmapLabel = FeedHeatmap.label(for: source)
        let leaderboard = heatmapLabel == nil ? FeedInsight.leaderboard(source: source, things: visible) : nil
        let distribution = heatmapLabel == nil && leaderboard == nil
            ? FeedInsight.distribution(source: source, things: visible) : nil
        let mosaic = heatmapLabel == nil && leaderboard == nil && distribution == nil
            ? FeedInsight.mosaic(source: source, things: visible) : nil
        let heroShown = heatmapLabel != nil || leaderboard != nil || distribution != nil || mosaic != nil
        if let heatmapLabel {
            calendarHeatmapSection(visible, label: heatmapLabel)
        } else if let leaderboard {
            insightSection { LeaderboardHero(board: leaderboard) }
        } else if let distribution {
            insightSection { DistributionHero(dist: distribution) }
        } else if let mosaic {
            insightSection { ImageMosaicHero(mosaic: mosaic) }
        }
        switch shape {
        case .photos:
            photoGridSection(visible)
        case .wallet:
            // The reads first, then the stream (2026-07-20, the surface split):
            // balance + warnings side by side, the holdings treemap, DeFi, and
            // only then the transactions — capped, with a door to all of them.
            // Everything above the rows is live state, never a landed thing.
            // (The wallet switcher isn't here: it PINS over the stream via
            // safeAreaInset — a scoping control has to stay reachable when
            // you're deep in the transactions it scopes.)
            walletTilesSection(visible)
            eachWalletSection
            holdingsBlockSection
            walletDeFiSection
            let all = visible
            let preview = Array(all.prefix(Self.walletPreviewRows))
            let days = dayGroups(preview)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
            walletSeeAllSection(total: all.count)
        case .calendar:
            groupedSections(agendaGroups(visible), nextEventID: nextEventID)
        case .gmail:
            if !heroShown { waitingSection(visible, nextEventID: nextEventID) }
            let days = chronoGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .reminders:
            reminderSections(visible, nextEventID: nextEventID)
        case .music:
            if !heroShown { listeningLedeSection(visible) }
            // Sessions, not days (2026-07-21) — a listening sitting is music's
            // real unit; boundary rides the same capturedAt-keyed helper.
            let days = sessionGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .tokens:
            watchlistLedeSection(visible)
            watchlistSection(visible, nextEventID: nextEventID)
        case .safari:
            // A reading list is doors, not reads (2026-07-21) — its lede owns
            // the return-trip guilt: how much is piling up, and the oldest
            // thing still waiting. Rows below stay chronological (coarsened
            // when saves are sparse, like any door source).
            if !heroShown { readingLedeSection(visible) }
            let days = chronoGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .bitrefill:
            bitrefillLedeSection(visible)
            let days = chronoGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .oneclaw:
            oneclawLedeSection(visible)
            let days = chronoGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        default:
            if filter.tag != "All" && shape == .all {
                daySection(filterLabel, visible, nextEventID: nextEventID)
            } else if shape == .all {
                // The Themes treemap leads the unfiltered All room (2026-07-18,
                // moved off Home) — a cross-source overview, so it only makes
                // sense over the WHOLE corpus, not a kind-filtered slice (the
                // `if` branch above).
                themesLedeSection
                // All is where volume floods — bundles + the new-since
                // divider live here. A single source's shape IS that source;
                // bundling there would collapse the whole screen into one row.
                bundledSections(visible, nextEventID: nextEventID)
            } else {
                // Live-first in a source's own room (2026-07-21): a stream
                // that's on RIGHT NOW is the one row whose relevance isn't
                // chronological, so it leads its group. No-op for sources
                // with no live set.
                let days = liveFirst(chronoGroups(visible))
                groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
            }
        }
    }

    /// The first thing at-or-past the last-visit boundary in a shaped feed's
    /// day groups — the Thing twin of `boundaryID(in:)` (which speaks FeedRow,
    /// All's bundled currency). Same freeze semantics: computed ONCE per
    /// render by the caller and passed down, never re-derived per row.
    private func boundaryThingID(in groups: [(String, [Thing])]) -> UUID? {
        guard let newSince else { return nil }
        let all = groups.flatMap(\.1)
        guard let first = all.first, first.capturedAt > newSince else { return nil }
        return all.first(where: { $0.capturedAt <= newSince })?.id
    }

    /// Music's lede: today's listening, covers lapped, count honest (the
    /// distinct songs that landed today — recently-played dedupes per song).
    @ViewBuilder
    private func listeningLedeSection(_ visible: [Thing]) -> some View {
        let today = visible.filter { Self.groupingCalendar.isDateInToday($0.capturedAt) }
        if !today.isEmpty {
            ledeSection(ListeningLede(
                covers: today.compactMap(\.previewImageURL).filter { !$0.isEmpty },
                count: today.count))
        }
    }

    /// Tokens' lede: the watchlist's 24h at a glance — from the SAME cached
    /// pulses the rows wear, so the summary can never disagree with the rows.
    /// Two watched tokens minimum: one token's row already says everything.
    @ViewBuilder
    private func watchlistLedeSection(_ visible: [Thing]) -> some View {
        let pulses = visible.compactMap { TokenPulse.shared.pulse(for: $0) }
        if pulses.count >= 2 {
            // Flat (exactly 0) is neither up nor down — "2 up" for two
            // stablecoins would claim a gain that didn't happen (honesty).
            ledeSection(WatchlistLede(
                up: pulses.filter { $0.change24h > 0 }.count,
                down: pulses.filter { $0.change24h < 0 }.count))
        }
    }

    /// Bitrefill's lede: the account at a glance — the balance its API last
    /// reported, and how many orders landed this month (from the same rows
    /// below, so the two can't disagree). Connected-only: a disconnected
    /// seat must not wear yesterday's balance as if it were current.
    @ViewBuilder
    private func bitrefillLedeSection(_ visible: [Thing]) -> some View {
        if TokenBridge.bitrefill.connected, let balance = BitrefillBalance.formatted {
            let month = visible.filter {
                BitrefillFetch.isOrderRef($0.sourceRef)
                    && Self.groupingCalendar.isDate($0.capturedAt, equalTo: .now,
                                                    toGranularity: .month)
            }.count
            ledeSection(BitrefillLede(balance: balance, monthCount: month))
        }
    }

    /// 1Claw's lede: the key's reach at a glance — the vault count its API
    /// last reported, and how many grants landed as rows below (counted from
    /// the same rows, so the two can't disagree). Connected-only: a
    /// disconnected seat must not wear yesterday's reach as if it were
    /// current.
    @ViewBuilder
    private func oneclawLedeSection(_ visible: [Thing]) -> some View {
        if TokenBridge.oneclaw.connected, let vaults = OneClawAccess.formatted {
            let grants = visible.filter { OneClawFetch.isGrantRef($0.sourceRef) }.count
            ledeSection(OneClawLede(vaults: vaults, grantCount: grants))
        }
    }

    /// The watchlist's OWN order, not chronology (2026-07-15) — day headers
    /// answer "when did I watch this", a question that stops mattering once
    /// there's more than a couple of tokens; what you actually want is what
    /// MOVED, or the order you dragged it into (TokenWatchOrder — the same
    /// shared choice the settings screen and Home's tile read). One flat
    /// section, no day breaks; the "new since" divider drops with it — it's
    /// a chronological-feed idea, and this list may no longer read top to
    /// bottom by time.
    @ViewBuilder
    private func watchlistSection(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let ordered = TokenWatchOrder.shared.apply(
            visible, sourceRef: \.sourceRef,
            change24h: { TokenPulse.shared.pulse(for: $0)?.change24h })
        // One flat run: pulsed tokens wear the fat TokenRow and stand alone
        // (standsAlone), so merging only ever joins the still-unpulsed rows.
        let positions = cardRunPositions(count: ordered.count,
                                         isBreaker: { standsAlone(ordered[$0]) })
        Section {
            ForEach(Array(keyed(ordered).enumerated()), id: \.element.id) { i, item in
                shapedListRow(item.thing, index: i, nextEventID: nextEventID,
                              position: positions[i])
            }
        }
    }

    /// A shape's one glanceable block, wearing the same card surface as the
    /// rows below it — a lede is part of the feed, not a foreign panel.
    private func ledeSection(_ content: some View) -> some View {
        Section {
            content
                .listRowBackground(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.surfaceSheet)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s1)
                        .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
                )
                .listRowInsets(.init(top: DS.Space.s2,
                                     leading: DS.Space.s4 + DS.Space.s3,
                                     bottom: DS.Space.s2,
                                     trailing: DS.Space.s4 + DS.Space.s3))
                .listRowSeparator(.hidden)
        }
    }

    private func bundledSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        // Derive ONCE per render, then share — the day bundles, each day's true
        // total, and the new-since boundary. Read inside the row/header loops
        // (as `newBoundaryID` and `dayGroups.first(where:)` were) they rebuilt
        // the whole chain per row/section — the Feed freeze (perf pass
        // 2026-07-13).
        let days = dayGroups(visible)
        let groups = bundle(days)
        let boundary = boundaryID(in: groups)
        let dayTotals = Dictionary(days.map { ($0.0, $0.1.count) },
                                   uniquingKeysWith: { first, _ in first })
        return ForEach(groups, id: \.0) { label, rows in
            // Bundles merge into the day card like any row-shaped thing —
            // only a single that stands alone (consent, token) breaks the run.
            let positions = cardRunPositions(
                count: rows.count,
                isBreaker: { i in
                    if case .single(let thing) = rows[i].kind { return standsAlone(thing) }
                    return false
                },
                isBoundary: { rows[$0].id == boundary })
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if row.id == boundary { newSinceDivider }
                    switch row.kind {
                    case .single(let thing):
                        shapedListRow(thing, index: i, nextEventID: nextEventID,
                                      position: positions[i])
                    case .bundle(let source, let word, let count, let newest, let art):
                        bundleListRow(source: source, word: word, count: count,
                                      newest: newest, art: art, index: i, position: positions[i])
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(label).dsText(.heading22).foregroundStyle(DS.textPrimary)
                    // The count stays the day's true total — a bundle
                    // compresses rows, never the record.
                    Text("\(dayTotals[label] ?? rows.count)")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .contentTransition(.numericText())
                }
                .textCase(nil)
                .padding(.leading, DS.Space.s4)
                .padding(.vertical, DS.Space.s1)
            }
        }
    }

    /// The boundary line — words only, no drawn rule (the no-hairlines law).
    /// Everything above it arrived since you last left this screen.
    private var newSinceDivider: some View {
        // A quiet capsule, not tint-colored prose (which reads as a tappable
        // link). The fill gives the boundary its line without drawing one.
        Text(newSinceText)
            .dsText(.label12)
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s1)
            .background(DS.fillFaint, in: Capsule(style: .continuous))
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s1)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The seam's words (2026-07-21): "what's new" differs by source, so the
    /// divider names it concretely instead of a bare "New since Friday". Most
    /// feeds get a count ("New since Friday · 4"); a Wallet feed — whose rows
    /// are SCANNED, not read — names the flow instead ("2 in, 1 out since
    /// Friday"), the question a wallet actually answers. Counts run over the
    /// frozen `visible` (things newer than the last-visit stamp); the divider
    /// renders once per boundary, so this reads `visible` a single time.
    private var newSinceText: String {
        guard let newSince else { return "" }
        let fresh = visible.filter { $0.capturedAt > newSince }
        if shape == .wallet {
            let inN = fresh.filter { $0.transferDirection == "received" }.count
            let outN = fresh.filter { $0.transferDirection == "sent" }.count
            if inN > 0 || outN > 0 {
                var parts: [String] = []
                if inN > 0 { parts.append(String(localized: "\(inN) in")) }
                if outN > 0 { parts.append(String(localized: "\(outN) out")) }
                return String(localized: "\(parts.joined(separator: ", ")) since \(sinceLabel)")
            }
        }
        return fresh.isEmpty
            ? String(localized: "New since \(sinceLabel)")
            : String(localized: "New since \(sinceLabel) · \(fresh.count)")
    }

    private var sinceLabel: String {
        guard let newSince else { return "" }
        if Calendar.current.isDateInToday(newSince) {
            return newSince.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(newSince) { return "yesterday" }
        return newSince.formatted(.dateTime.weekday(.wide))
    }

    /// Per-source last-visit stamps. All keeps its original "feed.lastSeen"
    /// key — an update never resets anyone's divider.
    private func lastSeenKey(for source: String) -> String {
        source == "All" ? "feed.lastSeen" : "feed.lastSeen.\(source)"
    }

    private func lastSeen(for source: String) -> Date? {
        let stamp = UserDefaults.standard.double(forKey: lastSeenKey(for: source))
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    private func stampSeen(_ source: String) {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970,
                                  forKey: lastSeenKey(for: source))
    }

    /// This page came to the front: freeze its boundary for the visit, replay
    /// the shape's entrance, stream its synthesis block. Every one of these is
    /// an ARRIVAL — spending them on a mounted-but-unseen neighbour would hand
    /// the person a page whose moment already happened.
    private func land() {
        freezeBoundary()
        shapeWave += 1
        streamBlock()
        loadWalletLive()
        // Every landing writes the crown pour's hue (prd §159): the scoped
        // wallet's face tint when you're standing inside one, else nil —
        // Casberi's own blue. Written unconditionally, not just by the Wallet
        // page, so arriving on ANY page resets a scoped tint the wallet page
        // left behind; no leave() bookkeeping to race the pager's ordering.
        chrome.pourHue = source == "Wallet" ? selectedWallet.map(WalletFace.tint) : nil
    }

    /// The person left this page — stamp what they saw, so the next visit's
    /// "New since" line is honest, and let the boundary freeze afresh then.
    private func leave() {
        stampSeen(source)
        visitFrozen = false
    }

    /// The boundary freezes on arrival and holds for the whole visit — a
    /// bounce out to another page and back can't move the line (ruling
    /// 2026-07-09). All tracks `AppVisit.away` instead of a per-page stamp
    /// (2026-07-20) — the same "since you left the app" window the agent's
    /// own "While I was away?" chip already names; there's no single page
    /// for the whole corpus to have left.
    private func freezeBoundary() {
        guard !visitFrozen else { return }
        visitFrozen = true
        newSince = source == "All" ? AppVisit.away?.lowerBound : lastSeen(for: source)
    }

    /// A bundle in the list: same card treatment as a thing row; the tap
    /// opens the source's own shape (where volume is designed to live) —
    /// no swipes, nothing here is a single thing to pin or open.
    private func bundleListRow(source: String, word: String, count: Int,
                               newest: Date, art: [String] = [], index: Int,
                               position: RunPosition = .only) -> some View {
        BundleRow(source: source, count: count, word: word, newest: newest, art: art)
            .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
            .contentShape(Rectangle())
            .onTapGesture {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { filter.source = source }
            }
            // A bundle is an ordinary row, never a designed card, so it goes
            // bare on the ink like every list row (lists are air).
            .listRowBackground(runBackground(position, bare: true))
            // Feed rhythm (2026-07-13): back to s2 — the s3 airy read made
            // every gap the same size, so days never clustered. Rows sit
            // tight within their day; the day header carries the big gap.
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DS.Space.s4 + DS.Space.s3,
                                 bottom: DS.Space.s2,
                                 trailing: DS.Space.s4 + DS.Space.s3))
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func groupedSections(_ groups: [(String, [Thing])],
                                 nextEventID: UUID?,
                                 boundary: UUID? = nil) -> some View {
        ForEach(groups, id: \.0) { label, rows in
            daySection(label, rows, nextEventID: nextEventID, boundary: boundary)
        }
    }

    /// The cross-source Themes treemap (2026-07-18: moved off Home — "should
    /// it go on all?" — a cross-source overview belongs on the cross-source
    /// feed, the same split that already sent the Wallet treemap to the
    /// Wallet feed). Synchronous, off the SAME `visible` the rows below draw
    /// from (no separate query, so the two can't disagree) — no GenStream
    /// needed, unlike the wallet block, which waits on a real network fetch.
    ///
    /// Collapses to one line once you've already seen these exact clusters
    /// (2026-07-20) — a digest of cluster name+count compared against a
    /// locally-stamped "last seen" digest (its own key, NOT `KeptAskStore`,
    /// which is scoped to kept ASKS specifically). Tapping expands the full
    /// treemap for the rest of this session and marks the digest seen.
    @ViewBuilder
    private var themesLedeSection: some View {
        // Computed once and shared with the collapsed row below (2026-07-21) —
        // this used to run `projectClusters` a second time over the same
        // `visible` set just to build the collapsed summary.
        let clusters = HomeComposition.projectClusters(things: visible)
        if let doc = HomeComposition.themesDocument(clusters: clusters) {
            let digest = doc.joined(separator: "\n")
            let unchanged = digest == UserDefaults.standard.string(forKey: Self.themesSeenDigestKey)
            if themesExpanded || !unchanged {
                let els = GenParser.parse(prefix: digest[...], isComplete: true)
                Section {
                    GenRender(id: "root", els: els)
                        // The Themes CARD (2026-07-21, the §160 ruling carried
                        // to the All room): every other feed-head read — the
                        // wallet's two parcels, the heatmaps, the leaderboards,
                        // the mosaics — wears the widget surface; this was the
                        // last one floating bare on the page. Same recipe as
                        // the holdings card: GenTagMap self-pads horizontally,
                        // so only the bottom needs closing.
                        .padding(.bottom, DS.Space.s3)
                        .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // The card needs the page gutter the bare map didn't.
                        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                                  bottom: 0, trailing: DS.Space.s4))
                        .environment(\.genProjectTap) { name in
                            openProject = ProjectRoute(name: name)
                        }
                        .onAppear {
                            // Pin expanded for the rest of this mount too —
                            // without this, stamping the digest here would
                            // make the NEXT body re-eval (any unrelated
                            // state change, still the same visit) read
                            // `unchanged` true and collapse out from under
                            // someone mid-visit.
                            themesExpanded = true
                            UserDefaults.standard.set(digest, forKey: Self.themesSeenDigestKey)
                        }
                }
            } else {
                Section {
                    Button {
                        DSHaptic.selection()
                        withAnimation(DS.Motion.standard) { themesExpanded = true }
                    } label: {
                        themesCollapsedRow(clusters)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// The collapsed Themes row — eyebrow + a one-line cluster-count summary,
    /// same voice as `daySection`'s header (name in heading weight, the
    /// count in tertiary).
    private func themesCollapsedRow(_ clusters: [HomeComposition.Cluster]) -> some View {
        let names = clusters.prefix(6).map(\.name).joined(separator: ", ")
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text("Themes").dsText(.heading17).foregroundStyle(DS.textPrimary)
            Text(names).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .accessibilityHidden(true)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
    }

    /// The list-row chrome every insight hero mounts in (clear background, no
    /// separator, edge-to-edge — the card owns its own padding).
    @ViewBuilder
    private func insightSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Section {
            content()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }

    /// A source's own consistency heatmap (2026-07-18) — the same green-squares
    /// grid the GitHub feed leads with, here derived from the feed's own things:
    /// each thing's `capturedAt` bucketed into the trailing year. Synchronous,
    /// off the SAME `visible` the rows draw from (no separate query). Renders
    /// only once a few days are lit, so a near-empty grid can't read as a
    /// loading skeleton.
    @ViewBuilder
    private func calendarHeatmapSection(_ visible: [Thing], label: FeedHeatmap.Label) -> some View {
        let year = ContributionYear.from(dates: visible.map(\.capturedAt), columns: label.columns)
        if year.activeDays >= 4 {
            let echo = OnThisDay.find(in: visible)
            Section {
                CalendarHeatmapHero(title: label.title,
                                    subtitle: FeedHeatmap.subtitle(label, total: year.total),
                                    year: year, minColumns: label.columns,
                                    onThisDay: echo,
                                    onTapOnThisDay: { feedSheet = echo.map { .thing($0.thing) } })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    /// The portfolio's own value-history line (2026-07-18), leading the
    /// treemap — real samples off `WalletStore.combinedValueSamples()`
    /// (recorded on every real holdings fetch since a wallet was watched, not
    /// synthesized). Empty (no section) until two aligned samples exist.
    /// How many transactions the feed previews before handing off to the
    /// history page (2026-07-20). Five is the count that still reads as "here's
    /// what's new" rather than a log — the reads above it are the point of this
    /// screen, and an unbounded stream buried all four of them.
    private static let walletPreviewRows = 5

    /// The wallet room's two cards are TRANSLUCENT (prd §160): they sit on the
    /// crown pour, and an opaque surface would punch a hole in the one
    /// atmospheric move the shell makes. One constant so the balance card and
    /// the holdings card can never drift apart.
    private static let walletCardFill = 0.82

    /// The balance CARD, then Worth a look as a quiet line beneath it — the two
    /// questions a wallet screen answers at a glance ("what's it worth", "is it
    /// okay").
    ///
    /// The card is prd §160 (2026-07-21, user: "i like both boxed"), amending
    /// §146/§151's page-set headline: the room's crown is already a parade of
    /// rounded shapes (source chips, wallet switcher pills, sync capsule), so
    /// the argument that a free-set number reads as "the room's voice" lost to
    /// the argument that a boxed one is easier to SCAN — parcels beat strata
    /// when the eye is looking for sections. The number keeps every ounce of
    /// its weight (price48, the pour behind it, the delta and mover with it);
    /// it just gets an edge. Translucent so the crown pour still travels under
    /// it rather than being punched out.
    ///
    /// Rendered FLAT (§gotchas' eager-head law): a plain VStack of two shallow
    /// pieces, no generic widget path. Either can be absent — no balance until
    /// two value samples exist, no warnings line when there's nothing wrong —
    /// and with both absent the section renders nothing at all rather than an
    /// empty row (the same honesty floor every section here keeps).
    @ViewBuilder
    private func walletTilesSection(_ visible: [Thing]) -> some View {
        // Scoped to the selected wallet's own value line, else the combined
        // portfolio line (prd §128). Both start honest — nil until two aligned
        // samples exist (TokenChart.from guards ≥2) — but the NUMBER no longer
        // waits on them (prd §155): the live total leads, the line joins.
        let samples = selectedWallet.map { wallet.valueSamples(forAddress: $0) }
            ?? wallet.combinedValueSamples()
        let ranges = WalletRange.offered(for: samples)
        let active = ranges.contains(balanceRange) ? balanceRange
            : WalletRange.remembered(offered: ranges)
        let windowed = active.clip(samples)
        let chart = TokenChart.from(samples: windowed)
        let total = portfolio.map(\.totalUSD).flatMap { $0 > 0 ? $0 : nil }
        let warnings = walletLive.warnings
        if chart != nil || total != nil || !warnings.isEmpty {
            Section {
                // The balance takes the room's headline; Worth a look drops to
                // a quiet line beneath it (prd §146, 2026-07-21) — the two
                // stack now rather than sitting as a matched pair of cards.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if chart != nil || total != nil {
                        // The headline is a READ, not a door (prd §208,
                        // 2026-07-25): the multi-wallet "All" view used to open
                        // a separate "Across your wallets" sheet, but that sheet
                        // re-showed this very number and line before getting to
                        // its only unique content — the per-wallet split — which
                        // now lives inline below as `eachWalletSection`. No
                        // door, no chevron; the number just states itself.
                        let hasBreakdown = wallet.addresses.count > 1 && selectedWallet == nil
                        WalletBalanceHeadline(
                            total: total,
                            chart: chart,
                            marks: walletMarks(dates: windowed.map(\.at), things: visible),
                            caption: hasBreakdown
                                ? String(localized: "Across your wallets")
                                : String(localized: "Balance"),
                            mover: moverLine(),
                            ranges: ranges,
                            range: active,
                            onPickRange: { r in
                                balanceRange = r
                                r.remember()
                            },
                            onOpen: nil,
                            onOpenMark: { id in
                                feedSheet = visible.first { $0.id == id }.map(FeedSheetRoute.thing)
                            })
                            // The card (prd §160). Padded and surfaced HERE, not
                            // inside the headline view, so the same component
                            // still renders bare wherever else it's used.
                            .padding(DS.Space.s4)
                            .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                            // Each piece arrives on its own clock — the balance
                            // reads off already-recorded samples (instant) while
                            // warnings/holdings/DeFi wait on live reads (2026-07-
                            // 20: "balance shows then the others pop in but looks
                            // unintentional"). Entrance is on the PIECE, not the
                            // row, so each one's own onAppear fires the moment
                            // IT lands, in the wallet shape's own established
                            // grammar (`entranceStyle` — the same rise every
                            // transaction row below already uses) instead of a
                            // silent, jarring insert.
                            .modifier(RowEntrance(index: 0, wave: shapeWave, style: entranceStyle))
                    }
                    if !warnings.isEmpty {
                        // A third card now (prd §196, superseding §146): still
                        // only reserves space when warnings are non-empty, but
                        // the badge row inside earns its own card the way the
                        // balance/DeFi cards above it do.
                        WalletWarningsLine(warnings: warnings) { feedSheet = .worthALook }
                            .modifier(RowEntrance(index: 0, wave: shapeWave, style: entranceStyle))
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// The transactions that landed inside the drawn window, placed against it
    /// (prd §155, 2026-07-21). A balance line conflates two different stories —
    /// prices moved, and money moved in or out — and the app holds both halves;
    /// this is the one that ties them together, so a step in the line can be
    /// read back to the send that caused it.
    ///
    /// Only things that fall BETWEEN the first and last sample are marked:
    /// a transaction from before the record began has no place on the line, and
    /// inventing one at the left edge would claim it caused a move the line
    /// never saw. Capped at the most recent ten — beyond that the punctuation
    /// becomes a second series and the line stops being readable.
    private func walletMarks(dates: [Date], things: [Thing]) -> [TokenChartMark] {
        guard dates.count >= 2, let first = dates.first, let last = dates.last else { return [] }
        return things
            .filter { $0.kind == .transaction && $0.capturedAt >= first && $0.capturedAt <= last }
            .prefix(10)
            .compactMap { thing in
                guard let i = dates.lastIndex(where: { $0 <= thing.capturedAt }) else { return nil }
                let next = min(i + 1, dates.count - 1)
                let span = dates[next].timeIntervalSince(dates[i])
                let t = span > 0 ? thing.capturedAt.timeIntervalSince(dates[i]) / span : 0
                return TokenChartMark(id: thing.id, x: Double(i) + min(max(t, 0), 1),
                                      label: thing.title)
            }
    }

    /// "Mostly ETH · +$310" — the top attributed mover, in the scope the feed
    /// is standing in (prd §155). The delta pill says the line moved; this says
    /// what moved it, off the same per-token snapshots. nil whenever the record
    /// can't attribute honestly yet — most of all on a young history, where no
    /// snapshot pair exists to difference. (This line is now the only "what
    /// moved" surface; the combined sheet that carried a fuller table retired
    /// with prd §208.)
    private func moverLine() -> String? {
        guard let top = wallet.holdingsDeltas(forAddress: selectedWallet).first else { return nil }
        let sign = top.delta >= 0 ? "+" : "−"
        return String(localized: "Mostly \(top.symbol) · \(sign)\(TokenStats.compact(abs(top.delta)))")
    }

    /// One watched wallet's own value line — the per-wallet split that used to
    /// live behind the "Across your wallets" door (prd §208, 2026-07-25). A
    /// value type keyed by address, so its ForEach never reads a live `@Model`
    /// (the crash class the CLAUDE.md ForEach rule guards). `@Generable` nesting
    /// caveats don't apply — this is a plain value type.
    private struct FeedWalletLine: Identifiable {
        let id: String        // the address — stable, value-typed
        let label: String
        let closes: [Double]
        let since: Date
        let tint: Color
    }

    /// Every watched wallet with ≥2 aligned samples, each paired with its face
    /// tint — the exact set the old combined sheet's "Each wallet" list drew.
    private var perWalletLines: [FeedWalletLine] {
        wallet.addresses.compactMap { addr in
            let samples = wallet.valueSamples(forAddress: addr.address)
            guard samples.count >= 2, let first = samples.first else { return nil }
            return FeedWalletLine(id: addr.address,
                                  label: addr.label.isEmpty ? addr.short : addr.label,
                                  closes: samples.map(\.usd), since: first.at,
                                  tint: WalletFace.tint(for: addr.address))
        }
    }

    /// The per-wallet split, inline on the "All" feed (prd §208) — the combined
    /// number said as its parts, so "which wallet drove this" is answered where
    /// the number already lives instead of behind a sheet that re-showed the
    /// number first. Only when more than one wallet is watched AND the feed is
    /// unscoped (scoped, the whole feed already IS that one wallet), and only
    /// once ≥1 wallet has the two aligned samples a line needs. A row taps to
    /// scope the feed to that wallet — the same move the switcher bar makes.
    @ViewBuilder
    private var eachWalletSection: some View {
        let lines = perWalletLines
        if wallet.addresses.count > 1, selectedWallet == nil, !lines.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text("Each wallet")
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                    ForEach(lines) { eachWalletRow($0) }
                }
                .padding(DS.Space.s4)
                .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                .modifier(RowEntrance(index: 1, wave: shapeWave, style: entranceStyle))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    private func eachWalletRow(_ line: FeedWalletLine) -> some View {
        let first = line.closes.first ?? 0
        let last = line.closes.last ?? 0
        let change = first > 0 ? (last - first) / first : 0
        return Button {
            withAnimation(DS.Motion.standard) { selectedWallet = line.id }
            DSHaptic.selection()
        } label: {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: line.id, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.label).dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(TokenStats.compact(last))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                TokenChartPlot(chart: TokenChart(closes: line.closes, price: last, change: change),
                               accent: line.tint, height: 30, pulses: false)
                    .frame(width: 80)
                    .accessibilityHidden(true)
                TokenDeltaPill(change: change,
                               label: "since \(line.since.formatted(.dateTime.month(.abbreviated).day()))",
                               compact: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Aave collateral / debt / health for the wallets in scope (2026-07-20) —
    /// moved up from the detail page so the debt side sits beside the holdings
    /// that are its collateral. Nothing renders without a position.
    @ViewBuilder
    private var walletDeFiSection: some View {
        if !walletLive.positions.isEmpty {
            Section {
                WalletDeFiTile(positions: walletLive.positions)
                    // Same reveal the balance/warnings tiles and holdings
                    // treemap wear — DeFi is usually the last of the four live
                    // reads to land, so it gets the deepest stagger.
                    .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
        // Morpho beside Aave (2026-07-21) — same live-state pass, its own
        // tile because the two books answer differently (isolated markets +
        // vaults vs one account-wide read).
        if !walletLive.morpho.isEmpty {
            Section {
                WalletMorphoTile(book: walletLive.morpho)
                    .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// The stream's door — only when there's more behind it than the preview
    /// showed (no dead control when five rows is the whole history).
    @ViewBuilder
    private func walletSeeAllSection(total: Int) -> some View {
        if total > Self.walletPreviewRows {
            Section {
                WalletSeeAllRow(count: total) {
                    HomeRoute.shared.pushBridge(.walletHistory(scope: selectedWallet))
                }
                .listRowSeparator(.hidden)
                // On the page itself, not in a card — a quiet continuation
                // line, not another surface (user, 2026-07-20, twice).
                .listRowBackground(Color.clear)
            }
        }
    }

    /// The wallet switcher (prd §128) — an "All" chip then one chip per watched
    /// wallet, each wearing its `WalletFace` and, when selected, its signature
    /// tint. Scopes the whole Wallet feed (balance, treemap, NFTs, rows) to one
    /// wallet; only shown with more than one watched. Fill-only selection (no
    /// lines, per the design law). Mirrors the Wallet screen's own switcher.
    ///
    /// PINNED, not a List section (2026-07-20, prd §136's own rule applied to
    /// itself): as a section it scrolled away with the content it scopes —
    /// unreachable exactly when you're deep in the stream wondering whose
    /// transaction that was — and its glass had nothing moving behind it.
    /// As a `safeAreaInset` bar it floats under the shell's chip strip, the
    /// stream travels beneath it, and the material finally earns its blur.
    @ViewBuilder
    private var walletSwitcherBar: some View {
        if source == "Wallet", wallet.addresses.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    walletSwitcherChip(label: "All", address: nil)
                    ForEach(wallet.addresses) { addr in
                        walletSwitcherChip(label: addr.label.isEmpty ? addr.short : addr.label,
                                           address: addr.address)
                    }
                }
                .padding(4)
                // Glass, by the law's own terms: scoping is a CONTROL, so the
                // switcher wears the floating material — one bar of glass for
                // the whole strip rather than a pane per chip.
                .dsGlass(cornerRadius: 999)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func walletSwitcherChip(label: String, address: String?) -> some View {
        let isOn = walletChipIsOn(address)
        let tint = address.map(WalletFace.tint) ?? DS.tint
        return Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { selectedWallet = address }
        } label: {
            HStack(spacing: 5) {
                if let address { WalletFace(address: address, size: 18) }
                Text(label)
                    .dsText(.subhead13)
                    .fontWeight(isOn ? .semibold : .regular)
                    .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            // The selection fill is ONE object that travels chip to chip on a
            // scope switch (matched geometry), tinting itself to the landing
            // wallet's own hue mid-flight — identity color doing the work.
            // Unselected chips keep their static faint fill underneath.
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(DS.fillFaint)
                    if isOn {
                        Capsule(style: .continuous).fill(tint.opacity(0.18))
                            .matchedGeometryEffect(id: "walletSwitcherSelection",
                                                   in: walletSwitcherNS)
                    }
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func walletChipIsOn(_ address: String?) -> Bool {
        guard let address else { return selectedWallet == nil }
        guard let sel = selectedWallet else { return false }
        return walletSameAddress(sel, address)
    }

    /// Hex compares case-insensitively (EIP-55 case is a checksum), base58
    /// exactly (Solana case is identity) — the switcher's address equality.
    private func walletSameAddress(_ a: String, _ b: String) -> Bool {
        ENS.isHexAddress(a) ? a.lowercased() == b.lowercased() : a == b
    }

    /// The wallet leads with holdings — real, from Alchemy (WalletIngest),
    /// one treemap per watched address, same doc Home and the Wallet screen
    /// render (ruling 2026-07-09: the old mock demo-only block never showed a
    /// real user anything real).
    @ViewBuilder
    private var holdingsBlockSection: some View {
        if !blockStream.els.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    GenRender(id: "root", els: blockStream.els)
                        // A tapped holdings cell opens its token's chart
                        // (2026-07-14): the thing sheet when watched, the quick
                        // sheet when it's just held; a routeless native-coin
                        // cell keeps its old door — the Wallet screen (no dead
                        // controls). The Feed sets its own handler —
                        // HomeScreen's doesn't reach this surface.
                        .environment(\.genProjectTap) { name in
                            if let route = TokenQuickRoute.from(sentinel: name) {
                                if let thing = route.watchedThing(in: modelContext) {
                                    feedSheet = .thing(thing)
                                } else {
                                    // The combined map merges wallets, so a
                                    // cell tapped there carries the "held in"
                                    // breakdown with it (prd §155) — the fact
                                    // the per-wallet maps used to carry by
                                    // never merging in the first place.
                                    feedSheet = .token(route.withHolders(
                                        portfolio?.holders(forSymbol: route.symbol ?? "") ?? []))
                                }
                            } else if name == "@wallet" {
                                HomeRoute.shared.pushBridge(.wallet)
                            }
                        }
                    // The map says WHAT you hold; this says how much of it is
                    // one thing (prd §155) — a read that only means something
                    // about a whole portfolio.
                    if let portfolio, !portfolio.isEmpty {
                        WalletConcentrationLine(
                            portfolio: portfolio,
                            onOpen: portfolio.walletCount > 1 && selectedWallet == nil
                                ? { feedSheet = .allocation } : nil)
                            .padding(.horizontal, DS.Space.s4)
                    }
                }
                // The holdings CARD (prd §160) — title, map, and the
                // concentration line become one parcel. GenTagMap already
                // self-pads horizontally by s4, which becomes this card's
                // inner gutter; only the bottom needs closing, since the map
                // pads its own top.
                .padding(.bottom, DS.Space.s3)
                .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                // The SECTION's own arrival, not the cells' — GenTagMap
                // already stages its cells once mounted; this is what
                // stops the whole treemap from hard-popping in the moment
                // the holdings read lands (2026-07-20, wallet streaming fix).
                .modifier(RowEntrance(index: 1, wave: shapeWave, style: entranceStyle))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // The card needs the page gutter the bare map didn't (it used
                // to bleed to the screen edge and self-pad its cells).
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// Photos: one continuous grid — day labels are overlay pills on the first
    /// photo of each day, never section breaks (mock P1).
    private func photoGridSection(_ visible: [Thing]) -> some View {
        Section {
            let items = visible
            // Hand-rolled row-chunking, NOT LazyVGrid: on iOS 26,
            // `GridItem.spacing` and even `.padding()`'s horizontal
            // component are silently ignored on a `.flexible()` column's
            // cross axis — confirmed empirically (a 60pt spacing value and
            // later an 80pt padding both only ever showed up as VERTICAL
            // gap, never horizontal, no matter which mechanism carried it).
            // `HStack`/`VStack` spacing has no such bug, so rows are built
            // by hand instead (user, 2026-07-13 — tiles were touching edge
            // to edge with no gutter at all).
            let perRow = items.count > 12 ? 3 : 2
            let rows = stride(from: 0, to: items.count, by: perRow).map {
                Array(items[$0..<min($0 + perRow, items.count)])
            }
            // The real fix for the leak was in `PhotoWell` (a `scaledToFill`
            // image reporting its own huge intrinsic size instead of
            // respecting the cell) — with that fixed, a plain HStack's normal
            // equal-flexible-child distribution is enough; no manual width
            // math needed here.
            VStack(spacing: DS.Space.s3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: DS.Space.s3) {
                        ForEach(Array(keyed(row).enumerated()), id: \.element.id) { colIndex, item in
                            let thing = item.thing
                            let i = rowIndex * perRow + colIndex
                            let firstOfDay = i == 0
                                || dayLabel(items[i - 1].capturedAt) != dayLabel(thing.capturedAt)
                            Button {
                                feedSheet = .thing(thing)
                            } label: {
                                PhotoCell(thing: thing, dayPill: firstOfDay ? dayLabel(thing.capturedAt) : nil)
                            }
                            // The tiles press like tiles (2026-07-10) — the same
                            // settle the Settings tiles and treemap cells wear.
                            .buttonStyle(DSTileButtonStyle())
                            .matchedTransitionSource(id: thing.id, in: zoomNS)
                        }
                        // An incomplete last row keeps its tiles at the same
                        // width as full rows rather than stretching to fill.
                        if row.count < perRow {
                            ForEach(0..<(perRow - row.count), id: \.self) { _ in
                                Color.clear
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // The grid rides the same content gutter as every other feed row —
            // tiles no longer bleed to the screen edge (which clipped the day
            // pills), and the page background reads clearly between them so a
            // run of light screenshots stops merging into one slab.
            .listRowInsets(.init(top: DS.Space.s3, leading: DS.Space.s4,
                                 bottom: DS.Space.s3, trailing: DS.Space.s4))
        }
    }

    /// Calendar reads forward: Today and upcoming days ascending, then the
    /// past, event-time order within each day (mock C2).
    private func agendaGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var buckets: [Date: [Thing]] = [:]
        for thing in visible {
            buckets[cal.startOfDay(for: thing.capturedAt), default: []].append(thing)
        }
        let futureDays = buckets.keys.filter { $0 >= today }.sorted()
        let pastDays = buckets.keys.filter { $0 < today }.sorted(by: >)
        return (futureDays + pastDays).map { day in
            (dayLabel(day), (buckets[day] ?? []).sorted { $0.capturedAt < $1.capturedAt })
        }
    }

    /// The next upcoming event — its ROW carries the emphasis (no hero).
    /// Events only: in the All shape other kinds share the list, and only
    /// an event's capture time means "starts at".
    private func nextEventID(_ visible: [Thing]) -> UUID? {
        visible.filter { $0.kind == .event && $0.capturedAt > .now }
            .min { $0.capturedAt < $1.capturedAt }?.id
    }

    /// Live right now, from the source's own current-live set (Twitch
    /// refreshes it every foreground) — never inferred from row age.
    private func isLive(_ thing: Thing) -> Bool {
        thing.source == "Twitch"
            && thing.sourceRef.map { TwitchIngest.liveRefs.contains($0) } ?? false
    }

    /// Float any live rows to the top of the NEWEST group (2026-07-21) — a
    /// stream on right now isn't a chronological row. Scoped to Twitch (the
    /// one source with a live set) and to the first group only, so history
    /// below stays in time order. A no-op everywhere else.
    private func liveFirst(_ groups: [(String, [Thing])]) -> [(String, [Thing])] {
        guard source == "Twitch", let first = groups.first,
              first.1.contains(where: isLive) else { return groups }
        let rows = first.1
        var out = groups
        out[0] = (first.0, rows.filter(isLive) + rows.filter { !isLive($0) })
        return out
    }

    /// The reading list's lede (2026-07-21) — a saved link is a DOOR, not a
    /// read, so the shape names the pile instead of pretending the rows are
    /// consumed: how many landed this month, how many are older, and the
    /// oldest one still waiting (a gentle "come back to this", never a
    /// count-shaming streak — §10). Facts only, and no "unopened" claim the
    /// model can't back (Thing tracks no read state) — "still here" is what's
    /// true. Yields to an auto hero so a shape never stacks two overviews.
    @ViewBuilder
    private func readingLedeSection(_ visible: [Thing]) -> some View {
        let cal = Self.groupingCalendar
        let thisMonth = visible.filter {
            cal.isDate($0.capturedAt, equalTo: .now, toGranularity: .month)
        }.count
        let older = visible.count - thisMonth
        // Oldest still on the list, shown only once it's genuinely aged (30d+)
        // — a fresh list has no pile to nudge about.
        let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
        let oldest = visible.filter { $0.capturedAt < monthAgo }
            .min { $0.capturedAt < $1.capturedAt }
        if visible.count >= 3 {
            ledeSection(ReadingLede(thisMonth: thisMonth, older: older, oldest: oldest))
        }
    }

    /// Gmail: what's waiting on you, capped at two (mock G1). Doing-marked
    /// only (honesty fix 2026-07-13): the old `content.contains("?")` sniff
    /// promoted any newsletter with a question mark to "waiting on you" —
    /// fake status. The section now shows only what the person marked
    /// in motion, and earns back a smarter derivation later.
    @ViewBuilder
    private func waitingSection(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let waiting = visible.filter { $0.mark == .doing }.prefix(2).map { $0 }
        if !waiting.isEmpty {
            daySection("Waiting on you", waiting, nextEventID: nextEventID)
        }
    }

    // Waiting mails stay in their day groups too (unlike agent approvals,
    // which ARE removed): a mail is a record, and excluding only the first
    // two doing-marked mails (the lede's cap) would punch order-dependent
    // holes in the day history. The lede highlights; the record stays whole.

    /// Reminders: state groups — Doing, To do (stale todos collapse), Done
    /// (same-day only).
    @ViewBuilder
    private func reminderSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let doing = visible.filter { $0.mark == .doing }
        let todos = visible.filter { $0.mark == .todo || $0.mark == .none }
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let fresh = todos.filter { $0.capturedAt > weekAgo }
        let stale = todos.filter { $0.capturedAt <= weekAgo }
        let doneToday = visible.filter {
            $0.mark == .done && Calendar.current.isDateInToday($0.capturedAt)
        }
        if !doing.isEmpty { daySection("Doing", doing, nextEventID: nextEventID) }
        if !fresh.isEmpty || !stale.isEmpty {
            // One To do card (2026-07-21): the Older toggle — or the stale
            // rows it expands into — continues the fresh rows' surface
            // instead of sitting under it as a flat band.
            let hasToggle = !stale.isEmpty && !staleExpanded
            let slots = fresh.count + (staleExpanded ? stale.count : 0) + (hasToggle ? 1 : 0)
            let positions = cardRunPositions(count: slots)
            Section {
                ForEach(Array(keyed(fresh).enumerated()), id: \.element.id) { i, item in
                    shapedListRow(item.thing, index: i, nextEventID: nextEventID,
                                  position: positions[i])
                }
                if !stale.isEmpty {
                    if staleExpanded {
                        ForEach(Array(keyed(stale).enumerated()), id: \.element.id) { i, item in
                            shapedListRow(item.thing, index: i, nextEventID: nextEventID,
                                          position: positions[fresh.count + i])
                        }
                    } else {
                        HStack {
                            Text("Older").dsText(.body17).foregroundStyle(DS.textSecondary)
                            Text("\(stale.count)").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .accessibilityHidden(true)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.textTertiary)
                        }
                        .padding(.vertical, DS.Space.s1)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(DS.Motion.standard) { staleExpanded = true } }
                        .listRowBackground(dayCardBackground(positions[slots - 1]))
                        .listRowInsets(.init(top: DS.Space.s2,
                                             leading: DS.Space.s4 + DS.Space.s3,
                                             bottom: DS.Space.s2,
                                             trailing: DS.Space.s4 + DS.Space.s3))
                        .listRowSeparator(.hidden)
                    }
                }
            } header: {
                Text("To do").dsText(.heading17).foregroundStyle(DS.textPrimary).textCase(nil)
            }
        }
        if !doneToday.isEmpty { daySection("Done", doneToday, nextEventID: nextEventID) }
    }

    // MARK: - Row dispatch (the shape decides what a row leads with)

    /// The swipe's hand-off target, when the thing has one — shared by both
    /// swipe edges so they agree on what counts as "has a destination".
    private func openVerb(for thing: Thing) -> Verb? {
        VerbDerivation.verbs(for: thing).first {
            if case .openURL = $0.action { return true } else { return false }
        }
    }

    /// Where a row sits in its day's shared card (ruling 2026-07-21,
    /// superseding 2026-07-13's gap-only clustering): a contiguous run of
    /// row-shaped things within a day merges into ONE card — the §61
    /// section-lift mechanic brought to the plain list — while the
    /// rhythm-breakers (`standsAlone`) keep free-standing cards between
    /// runs, and the new-since seam splits a day's card in two.
    private enum RunPosition { case only, first, middle, last }

    /// Positions for a section's rows, index-based so All's FeedRow bundles
    /// and plain Thing arrays share one derivation. A run breaks at a
    /// free-standing row on either side, and at the new-since boundary
    /// (the divider renders BEFORE the boundary row, so the row above it
    /// closes its run and the boundary row opens a fresh one).
    private func cardRunPositions(count: Int,
                                  isBreaker: (Int) -> Bool = { _ in false },
                                  isBoundary: (Int) -> Bool = { _ in false }) -> [RunPosition] {
        (0..<count).map { i -> RunPosition in
            let starts = i == 0 || isBreaker(i) || isBreaker(i - 1) || isBoundary(i)
            let ends = i == count - 1 || isBreaker(i) || isBreaker(i + 1) || isBoundary(i + 1)
            switch (starts, ends) {
            case (true, true):   return .only
            case (true, false):  return .first
            case (false, true):  return .last
            case (false, false): return .middle
            }
        }
    }

    /// The anatomies that earn a free-standing card — shapedRow's
    /// rhythm-breakers. Everything else (band, check, excerpt, reading,
    /// music) merges into its day's run.
    ///
    /// `thing.modelContext == nil` is the crash guard (2026-07-24, live
    /// TestFlight crash on 125/126, upgrade-only — never a fresh install):
    /// `bundledSections`' `visible` array is captured once per render, but
    /// the delete-sync heal passes (Calendar/Reminders/Contacts/HomeKit/
    /// Bluesky/Farcaster, added §prd 121) run as `Task { @MainActor in }` —
    /// correctly serialized with the UI, but still able to land BETWEEN this
    /// render's capture and this closure's evaluation inside the `ForEach`.
    /// A `Thing` SwiftData deletes gets its `modelContext` niled out first;
    /// reading that one property is documented-safe on a deleted model, but
    /// `thing.kind`/`thing.mark` below fault-resolve against the store and
    /// crashed (`_assertionFailure` inside SwiftData, real device only — a
    /// fresh install has no synced Calendar/Reminders/etc. yet to delete).
    private func standsAlone(_ thing: Thing) -> Bool {
        guard thing.modelContext != nil else { return false }
        if thing.kind == .approval && thing.mark != .done { return true }  // consent card
        if shape == .social { return true }                                // PostCard, media at width
        if shape == .chat && thing.mark == .doing { return true }          // TakeawayCard
        if TokenPulse.shared.pulse(for: thing) != nil { return true }      // TokenRow fat anatomy
        return false
    }

    /// The run-aware card surface: first/last rows carry the card's rounded
    /// shoulders and the s1 breathing edge; middle rows run square and
    /// GAPLESS, so a row's shadow falls on the adjacent same-color fill and
    /// vanishes (§61's measured mechanic) — only the run's outer silhouette
    /// casts, one lifted card instead of a stack of shadowed rows.
    private func dayCardBackground(_ position: RunPosition) -> some View {
        let r = DS.Radius.card
        let top = position == .first || position == .only
        let bottom = position == .last || position == .only
        return UnevenRoundedRectangle(topLeadingRadius: top ? r : 0,
                                      bottomLeadingRadius: bottom ? r : 0,
                                      bottomTrailingRadius: bottom ? r : 0,
                                      topTrailingRadius: top ? r : 0,
                                      style: .continuous)
            .fill(DS.surfaceSheet)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, top ? DS.Space.s1 : 0)
            .padding(.bottom, bottom ? DS.Space.s1 : 0)
            .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
    }

    /// Lists are AIR; parcels are for the reads (user ruling 2026-07-22,
    /// superseding the same-day "card is a group" cut). The day card failed
    /// at both extremes — one row wearing a full card was chrome around
    /// nothing, and a GitHub day's dozens made one giant slab — which means
    /// the card was never doing group-work at all: the DAY HEADER is the
    /// grouping. Apple Music is the named model: songs never sit in cards;
    /// surfaces are spent on featured content. So ordinary rows render bare
    /// on the ink, every shape, every run length. What keeps a surface: the
    /// designed-card anatomies (consent card, post, takeaway, fat token row
    /// — cards by anatomy, their surface IS this background) and the head
    /// reads (map, chart, mosaic, lede), which stay §160 parcels.
    @ViewBuilder
    private func runBackground(_ position: RunPosition, bare: Bool) -> some View {
        if bare {
            Color.clear
        } else {
            dayCardBackground(position)
        }
    }

    /// The row inside a list section, with the standard list plumbing attached.
    private func shapedListRow(_ thing: Thing, index: Int = 0, nextEventID: UUID?,
                               position: RunPosition = .only) -> some View {
        // AnyView: same metadata-depth insurance as GenRender (crash fix).
        return AnyView(shapedRow(thing, nextEventID: nextEventID, index: index))
            .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
            .contentShape(Rectangle())
            .matchedTransitionSource(id: thing.id, in: zoomNS)
            .onTapGesture { openThing(thing) }
            // V3b (2026-07-07, supersedes the kind-color wash): rows are
            // NEUTRAL cards — the translucent kind wash read as murk. Color
            // moved into the tag text: the project's own stable hue.
            .listRowBackground(runBackground(position, bare: !standsAlone(thing)))
            // Feed rhythm (2026-07-13): back to s2 — the s3 airy read made
            // every gap the same size, so days never clustered. Rows sit
            // tight within their day; the day header carries the big gap.
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DS.Space.s4 + DS.Space.s3,
                                 bottom: DS.Space.s2,
                                 trailing: DS.Space.s4 + DS.Space.s3))
            .listRowSeparator(.hidden)
            // One gesture, one meaning: TAP opens the sheet — tags and verbs
            // live there. The row's OTHER verbs ride a long-press (ruling
            // 2026-07-16, supersedes the both-edge swipe of 2026-07-15): the
            // feed pages between sources now, and a horizontal pan can only
            // belong to one thing. Measured before ruling — a `TabView(.page)`
            // pan claims 100% of horizontal drags, at every drag length, even
            // at the last page where it merely rubber-bands and the row still
            // never opens. So the swipe wasn't degraded, it was unreachable;
            // long-press is what's left, and it's what the Home board has used
            // for Open/Unpin all along (`GenRenderer.pinnedRowActions`).
            .contextMenu {
                if let openVerb = openVerb(for: thing) {
                    Button {
                        run(openVerb, on: thing)
                    } label: {
                        Label("Open in app", systemImage: "arrow.up.right")
                    }
                }
                ThingShareLink(thing: thing) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
    }

    @ViewBuilder
    private func shapedRow(_ thing: Thing, nextEventID: UUID?, index: Int = 0) -> some View {
        // Approval is the one rhythm-breaker everywhere: the consent card.
        if thing.kind == .approval, thing.mark != .done {
            ApprovalCard(thing: thing,
                         onApprove: { perform(Verb(label: "Approve", icon: "checkmark.circle", action: .approve), on: thing) },
                         onDeny: { perform(Verb(label: "Deny", icon: "xmark.circle", action: .deny), on: thing) })
        } else {
            // B2b (ruling 2026-07-06): ONE row anatomy — the band — for every
            // kind and every shape. The wash carries the kind; per-kind row
            // shapes retired. One earned exception: the doing chat takeaway.
            // Reminders are the band too — read-only (ruling 2026-07-25), so
            // no check circle: a done reminder is just struck through, its
            // state grouped by section, never a control that does nothing.
            switch shape {
            case .calendar:  BandRow(thing: thing, emphasized: thing.id == nextEventID)
            case .reminders: BandRow(thing: thing)
            case .music:     MusicRow(thing: thing)
            case .chat where thing.mark == .doing:
                TakeawayCard(thing: thing)
            // Native anatomies (2026-07-13): in its own room a note leads
            // with its text, a conversation with its opening line, a post
            // with its author and media, a link with where it's from. All
            // keeps the band — these relax only inside the source's shape.
            // The wallet room reads as a ledger (prd §157): the band, with the
            // moved amount pulled out of the sentence into a right-aligned
            // figure. Same anatomy as every other row — one opt-in flag.
            case .wallet: BandRow(thing: thing, moneyColumn: true, rippleIndex: index)
            case .notes:  ExcerptRow(thing: thing, lines: 3)
            case .chat:   ExcerptRow(thing: thing, lines: 2)
            case .social: PostCard(thing: thing)
            case .safari: ReadingRow(thing: thing)
            default:
                // Perishables show their clock everywhere (ruling 2026-07-09):
                // the next event's countdown and a stream's Live state ride
                // the row in All too, not just in their source's shape. A
                // watched token whose pulse has landed wears the fat anatomy
                // (TokenRow, prd §102) everywhere too; until it lands, the
                // plain band + timestamp — never a faked price.
                if let pulse = TokenPulse.shared.pulse(for: thing) {
                    TokenRow(thing: thing, pulse: pulse)
                } else {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: isLive(thing))
                }
            }
        }
    }

    // MARK: - Pieces

    /// Empty Feed — the rain come to rest (2026-07-16, replacing the quiet
    /// line + skeleton rows: skeletons mean "loading" everywhere, so an
    /// empty state wearing them forever read as stuck, not promising). The
    /// headline speaks in the display tier (the Home cover's voice), one
    /// door opens the catalog, and the settled pile is the onboarding rain
    /// landed HERE — every tile a real offer that opens its own product
    /// page, so the pile is honest by construction. Rendered FLAT (plain
    /// stacks, no Widget/Row path) — this sits in the eager feed body,
    /// where tree depth is the launch-crash class.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Let's fill this feed.")
                .dsText(.heading34).fontWeight(.heavy)
                .foregroundStyle(DS.textPrimary)
                .settleIn()
            Text("Connect an app and things start landing on their own.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s2)
                .settleIn(delay: 0.05)
            Button {
                DSHaptic.selection()
                HomeRoute.shared.present(.apps)
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Text("Open the catalog")
                        .dsText(.callout15).fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(DS.tint)
                .padding(.horizontal, DS.Space.s4)
                .frame(height: 36)
                .background(DS.tintDim, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, DS.Space.s4)
            .settleIn(delay: 0.1)
            // The other doors, named — the copy used to CLAIM capture
            // without teaching a single capture verb.
            Text("Or paste a link, share into Casberi, or snap a screenshot — those land here too.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .padding(.top, DS.Space.s3)
                .settleIn(delay: 0.15)
            Spacer(minLength: DS.Space.s6)
            EmptyFeedPile()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s6)
        // The pile rests at the FOOT of the screen (the rain lands where the
        // floor is): the row takes a fixed drop and the Spacer above hands
        // the slack to the pile. A plain minHeight, not
        // `containerRelativeFrame` — inside this List that modifier reported
        // a container shorter than the viewport and always floored (measured
        // 2026-07-16). On an oversized-type layout the Spacer collapses and
        // the row grows past the minimum instead of crowding.
        .frame(minHeight: 540, alignment: .top)
    }

    /// A filter with no matches: the filtered app's own icon, a plain line,
    /// and one way back. Never a bare "Nothing matches."
    private var filteredEmptyState: some View {
        VStack(spacing: DS.Space.s3) {
            if source != "All" {
                BridgeIcon(name: source, size: 44)
            } else if let kind = ThingKind.from(typeTag: filter.tag) {
                KindGlyph(kind: kind, size: 44)
            }
            Text(emptyLine)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    filter.source = "All"
                    filter.tag = "All"
                }
            } label: {
                Text("Show everything")
                    .dsText(.label12)
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s4)
                    .frame(height: 32)
                    .background(DS.tintDim, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            tryItChip
            // The empty room previews its own shape (2026-07-13) — the
            // all-feed empty state already does this with skeleton rows;
            // a shaped empty shows what ITS rows will look like: a grid
            // for Photos, rows for everything else.
            if source != "All" {
                emptyShapePreview
                    .padding(.top, DS.Space.s6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s6)
    }

    /// One tap demos a source that otherwise needs a first pick to mean
    /// anything — the Wallet screen's "Peek at vitalik.eth" (prd §79),
    /// generalized to every empty room that's just a search field with
    /// nothing in it (delight pass 2026-07-21). Retires the moment anything
    /// is watched — the empty state itself stops rendering.
    @ViewBuilder private var tryItChip: some View {
        if shape == .tokens {
            tryItButton(label: "Watch ETH") {
                guard let resolved = await TokenWatch.resolve("ETH") else { return }
                TokenWatch.add(resolved, context: modelContext)
                TokenWatch.registerBridge(store: bridges, context: modelContext)
            }
        } else if source == "Stocktwits" {
            tryItButton(label: "Watch $AAPL") {
                guard let resolved = await StockWatch.resolve("AAPL") else { return }
                StockWatch.add(resolved, context: modelContext)
                StockWatch.registerBridge(store: bridges, context: modelContext)
            }
        } else if source == "RSS" {
            tryItButton(label: "Follow NASA's feed") {
                guard RSSStore.shared.add("https://www.nasa.gov/feed/") else { return }
                let added = await RSSIngest.refresh(context: modelContext)
                bridges.registerConnected(id: "rss", name: "RSS",
                    proof: (added ?? 0) > 0 ? "\(added ?? 0) posts in" : "Synced just now",
                    can: ["Reads the feeds you follow."])
            }
        }
    }

    /// One chip anatomy for every try-it — the vitalik.eth capsule's exact
    /// styling, reused instead of re-spelled per source.
    private func tryItButton(label: String, action: @escaping () async -> Void) -> some View {
        Button {
            DSHaptic.tap()
            Task { await action() }
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .dsText(.subhead13).fontWeight(.medium)
            }
            .foregroundStyle(DS.tint)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(DS.tint.opacity(0.12), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, DS.Space.s2)
    }

    @ViewBuilder private var emptyShapePreview: some View {
        switch shape {
        case .photos:
            HStack(spacing: DS.Space.s3) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.gray100)
                        .frame(height: 90)
                        .staggerIn(index: i + 3)
                }
            }
        case .wallet:
            // A skeleton treemap mosaic — echoes the Wallet feed's real
            // holdings treemap (uneven tile sizes, not a uniform grid).
            RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                .fill(DS.surfaceSheet)
                .frame(height: 160)
                .overlay {
                    HStack(spacing: DS.Space.s2) {
                        VStack(spacing: DS.Space.s2) {
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100).frame(height: 88)
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100)
                        }
                        VStack(spacing: DS.Space.s2) {
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100)
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100).frame(height: 56)
                        }
                        .frame(width: 72)
                    }
                    .padding(DS.Space.s3)
                }
                .staggerIn(index: 3)
        case .calendar:
            // A skeleton agenda band — each row a tinted strip, echoing
            // BandRow's own field-of-color shape.
            VStack(spacing: DS.Space.s2) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: DS.Space.s3) {
                        Circle().fill(DS.gray100).frame(width: 24, height: 24)
                        Capsule().fill(DS.gray100).frame(height: 12)
                        Spacer(minLength: DS.Space.s2)
                        Capsule().fill(DS.gray100).frame(width: 40, height: 12)
                    }
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s3)
                    .background(DS.gray100.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .staggerIn(index: i + 3)
                }
            }
        default:
            VStack(spacing: DS.Space.s2) {
                ForEach(0..<3, id: \.self) { i in
                    GenSkeletonRow()
                        .staggerIn(index: i + 3)
                }
            }
        }
    }

    private var emptyLine: String {
        let tagLabel = ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag
        switch (source != "All", filter.tag != "All") {
        case (true, true):   return "Nothing from \(source) under \(tagLabel) yet."
        case (true, false):  return "Nothing from \(source) yet."
        case (false, true):  return "No \(tagLabel.lowercased()) yet."
        default:             return "Nothing here yet."
        }
    }

    /// Every row opens its own thing sheet — including a wallet transaction
    /// (2026-07-24, user: "when i tap 'received' on a transaction it brings me
    /// to the wallet management screen... no reason to go there"). The old
    /// ruling (2026-07-09) sent Wallet rows to the management screen because
    /// "the generic sheet had nothing more than an explorer link to show" —
    /// long obsolete: the sheet now leads with the full transfer STAGE (the
    /// parties, the signed amount, the chain, the flag banner) and its Open
    /// disc IS that explorer link. Tapping a transaction should show the
    /// transaction, not the page for managing which wallets you watch.
    private func openThing(_ thing: Thing) {
        feedSheet = .thing(thing)
    }

    /// A day group as a native section: the day's rows share ONE sheet card
    /// (2026-07-21 — see RunPosition), rhythm-breakers stand free between
    /// runs, native scroll — no gesture fights.
    @ViewBuilder
    private func daySection(_ label: String, _ rows: [Thing],
                            nextEventID: UUID?,
                            boundary: UUID? = nil) -> some View {
        let positions = cardRunPositions(count: rows.count,
                                         isBreaker: { standsAlone(rows[$0]) },
                                         isBoundary: { rows[$0].id == boundary })
        Section {
            // Rows dispatch by shape (shaped feeds); the swipe stays triage —
            // reads only, writes live in the sheet (ruling), Copy sheet-only.
            ForEach(Array(keyed(rows).enumerated()), id: \.element.id) { i, item in
                let thing = item.thing
                if thing.id == boundary { newSinceDivider }
                shapedListRow(thing, index: i, nextEventID: nextEventID,
                              position: positions[i])
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(label).dsText(.heading22).foregroundStyle(DS.textPrimary)
                // In a source's own room the count speaks the source's unit —
                // "3 events", "5 screenshots" (2026-07-13). All keeps the
                // bare number: mixed kinds have no one unit worth naming.
                Text(countLabel(rows)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .contentTransition(.numericText())
            }
            .textCase(nil)
            .padding(.leading, DS.Space.s4)
            // Days read as clusters: the gap ABOVE a day header is the
            // feed's biggest (2026-07-13), and since 2026-07-21 the day's
            // rows also share one card — the header's s6 plus the card's own
            // silhouette say "new day" without drawing a line.
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
        }
    }

    /// The day header's count: a bare number in All, the source's own unit in
    /// a shaped feed — "3 events", "1 screenshot", "4 things" when mixed.
    /// The social room says "posts": its things are kind .chat (the ingest's
    /// container), but nobody calls a Bluesky post a chat.
    private func countLabel(_ rows: [Thing]) -> String {
        guard source != "All" else { return "\(rows.count)" }
        if shape == .social {
            return rows.count == 1 ? "1 post" : "\(rows.count) posts"
        }
        let kinds = Set(rows.map(\.kind))
        guard kinds.count == 1, let kind = kinds.first else {
            return rows.count == 1 ? "1 thing" : "\(rows.count) things"
        }
        let unit = rows.count == 1 ? kind.typeTag : kind.typeTagPlural
        return "\(rows.count) \(unit.lowercased())"
    }

    /// The feed closes instead of trailing off (2026-07-13): one quiet line
    /// naming what you just read to the end of. Doubles as an honest corpus
    /// count — facts only, no streaks (§10). Speaks the same unit as the day
    /// headers ("6 events", not "6 things") via the one countLabel rule.
    /// Takes the render's `visible` (the Feed-freeze rule) instead of
    /// re-deriving it.
    private func caughtUpFooter(_ rows: [Thing]) -> some View {
        Text(source == "All"
             ? "That's everything · \(rows.count == 1 ? "1 thing" : "\(rows.count) things")"
             : "That's everything from \(source) · \(countLabel(rows))")
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s6)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // MARK: - Verbs from the swipe (reads pass, writes confirm)

    private func run(_ verb: Verb, on thing: Thing) {
        if verb.isWrite {
            confirming = (verb, thing)
        } else {
            perform(verb, on: thing)
        }
    }

    private func perform(_ verb: Verb, on thing: Thing) {
        switch verb.action {
        case .openURL(let url):
            openURL(url)
        case .addToCalendar:
            Task {
                do {
                    try await HandOff.addToCalendar(thing)
                    chrome.flash("On your calendar", tone: .success)
                } catch { chrome.flash(error.localizedDescription, tone: .failure) }
            }
        case .addToReminders:
            Task {
                do {
                    try await HandOff.addToReminders(thing)
                    chrome.flash("On your list", tone: .success)
                } catch { chrome.flash(error.localizedDescription, tone: .failure) }
            }
        case .copyText:
            UIPasteboard.general.string = thing.content.isEmpty ? thing.title : thing.content
            chrome.flash("Copied")
        case .markDone:
            // Rung-1 local mark only — app-owned things (a note turned to-do,
            // demo seeds). A real reminder's done-state is READ-ONLY, mirrored
            // from the Reminders app (ruling 2026-07-25), so it never offers
            // this verb; nothing here writes back to any external record.
            thing.mark = .done
            modelContext.saveHonestly()
        case .translate:
            translateText = thing.postText ?? thing.content
            showTranslate = true
        case .approve:
            // An MCP client asked to save a thing (PRD §34) — the approval
            // carries the payload; the tap is what commits it. Consent → write.
            if thing.sourceRef == MCPTools.saveMarker,
               let real = Capture.thing(from: thing.content, source: thing.source) {
                modelContext.insert(real)
                thing.mark = .done
                modelContext.saveHonestly()
                SpotlightIndex.index([real])
                chrome.flash("Saved", tone: .success)
            } else {
                withAnimation(DS.Motion.standard) {
                    thing.mark = .done
                    modelContext.saveHonestly()
                }
                // Honesty: the answer is recorded on the thing. Nothing is
                // sent anywhere — no agent transport exists yet (2026-07-10;
                // the old copy claimed a gateway was told).
                chrome.flash("Approved", tone: .success)
            }
        case .deny:
            withAnimation(DS.Motion.standard) {
                thing.mark = .done
                modelContext.saveHonestly()
            }
            chrome.flash("Denied")
        }
    }


    /// Loads the real per-wallet holdings for the Wallet chip's own shape —
    /// the ONLY place holdings show in Feed (amendment 2026-07-10: the
    /// module already lives on Home; leading All with it doubled that).
    /// Everything watched shows here regardless of pin — this is the
    /// wallet's native view. Composing is synchronous elsewhere in this
    /// screen; the wallet fetch isn't, so it lands in the background and
    /// repaints.
    /// Pull-to-refresh (2026-07-12): re-polls every connected bridge for fresh
    /// things, then RECOMPOSES the feed the way a source switch does — the
    /// shaped rows re-cascade (shapeWave replays their entrance) and the
    /// synthesis block re-streams. The Feed's take on Home's pull re-compose:
    /// records paint, so the delight is the cascade, not a typewriter. A short
    /// beat lets the pull read before it lands with a soft thud.
    private func refreshFeed() async {
        // A deliberate pull re-fetches live — clear the holdings cache so the
        // Wallet feed's treemap isn't served a TTL-cached read (same contract as
        // Home's pull; the cache is for the automatic fan-out, not the gesture).
        await WalletIngest.invalidateHoldingsCache()
        BridgeRefresh.refreshAllConnected(context: modelContext, store: bridges, force: true)
        chrome.refreshPulse += 1   // spins the avatar door, deals the berry rain
        shapeWave += 1
        streamBlock()
        try? await Task.sleep(for: .milliseconds(450))
        DSHaptic.success()
    }

    /// Reads the Wallet feed's live state for the current scope. Off the Wallet
    /// feed it clears rather than holding a stale read — the tiles are gone
    /// from the screen anyway, and stale state would flash on return.
    private func loadWalletLive() {
        guard source == "Wallet" else {
            if walletLive != WalletLiveState() { walletLive = WalletLiveState() }
            return
        }
        let scope = selectedWallet
        Task { @MainActor in
            let state = await WalletWatch.liveState(scopeTo: scope, context: modelContext)
            // The scope may have moved while the reads were in flight — a late
            // answer for a wallet we've since left must not paint.
            guard scope == selectedWallet else { return }
            // Animated on purpose (2026-07-20, wallet streaming fix): this
            // lands SECONDS after the balance tile (live chain reads vs a
            // local sample file), and an unanimated set hard-popped the
            // warnings/DeFi tiles into place — "looks unintentional". The
            // animation carries the LAYOUT (rows sliding to make room);
            // each tile's own RowEntrance carries its reveal.
            withAnimation(DS.Motion.standard) { walletLive = state }
        }
    }

    private func streamBlock() {
        guard source == "Wallet" else {
            if !blockStream.els.isEmpty { blockStream.paint([]) }
            if portfolio != nil { portfolio = nil }
            return
        }
        // The treemap paints as soon as holdings land, and the portfolio behind
        // it lands on the same beat — one read, both answers (prd §155), so the
        // balance number, the map, and the concentration line can never be
        // three different moments. Scoped to the selected wallet when the feed
        // is (prd §128) — the doc generator filters its groups to that address;
        // nil paints the combined map.
        let scope = selectedWallet
        Task { @MainActor in
            let read = await WalletIngest.portfolioRead(scopeTo: scope)
            // The scope may have moved while the read was in flight — a late
            // answer for a wallet we've since left must not paint (the same
            // guard `loadWalletLive` keeps).
            guard scope == selectedWallet else { return }
            if let read {
                // Same animated landing as `loadWalletLive` — the treemap is
                // the tallest late-arriving block, so ITS unanimated insert
                // was the most jarring of the pops.
                withAnimation(DS.Motion.standard) {
                    blockStream.paint(read.doc)
                    portfolio = read.portfolio
                }
            } else if !blockStream.els.isEmpty || portfolio != nil {
                withAnimation(DS.Motion.standard) {
                    blockStream.paint([])
                    portfolio = nil
                }
            }
        }
    }

    /// One calendar for the per-thing day grouping — `Calendar.current` copies
    /// the user's calendar on every access, and `dayLabel` runs once per thing
    /// inside `dayGroups`/`agendaGroups`, which the feed re-derives per paint.
    private static let groupingCalendar = Calendar.current

    private func dayLabel(_ date: Date) -> String {
        if Self.groupingCalendar.isDateInToday(date) { return String(localized: "Today") }
        if Self.groupingCalendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }
}


/// The compact Feed treemap — 5 cells, areas "a a b c / a a d e", 140pt tall,



/// Rows arrive the way their shape moves (ruling 2026-07-07): a per-shape
/// offset/scale revealed with a small stagger, replayed when the chip
/// changes. One animation per moment — this IS the shape's moment.
struct RowEntrance: ViewModifier {
    struct Style {
        var dx: CGFloat
        var dy: CGFloat
        var scale: CGFloat
        var step: Double
    }

    let index: Int
    let wave: Int
    let style: Style
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : style.dx, y: shown ? 0 : style.dy)
            .scaleEffect(shown ? 1 : style.scale)
            .onAppear { reveal() }
            .onChange(of: wave) {
                shown = false
                reveal()
            }
    }

    private func reveal() {
        withAnimation(DS.Motion.standard.delay(Double(min(index, 12)) * style.step)) {
            shown = true
        }
    }
}

// MARK: - Empty-feed pile (the rain come to rest)

/// The settled pile of app tiles at the foot of the empty feed — the
/// onboarding rain's third act (HowItWorksSheet rains them past, its step-1
/// strip shows them settled; here they rest where things will land). On
/// first appearance the tiles fall in and settle — gravity is an ease-IN,
/// the house rule — then the caption fades up. Every tile is a door to that
/// offer's product page in the catalog (no dead controls), routed through
/// HomeRoute.openOffer so the push survives the .apps hop.
private struct EmptyFeedPile: View {
    /// Hand-curated subset of the catalog — every name MUST resolve to a
    /// real BridgeCatalog offer (scripts/catalog-sync.sh checks this array
    /// by name, like the other decorative marquees). First six are the back
    /// row; the last six draw over them as the front row.
    static let pileApps = ["Notion", "Strava", "ChatGPT", "Photos",
                           "Wallet", "Reddit",
                           "Gmail", "GitHub", "Farcaster", "Bluesky",
                           "Claude", "YouTube"]

    /// Deterministic per-tile jitter — no randomness in a view body; the
    /// same pile settles identically every launch (and the screen sweep
    /// sees one design).
    private static let tilt:  [Double]  = [-5, 3, -2, 6, -4, 2,
                                           -6, 4, -3, 5, -2, 3]
    private static let restY: [CGFloat] = [3, -2, 4, 0, 2, -1,
                                           3, 1, -2, 2, 0, 3]

    /// How far above their rest the tiles wait — past the top of the screen
    /// from the pile's mid-page seat, so the fall crosses the headline the
    /// way the onboarding rain crosses the steps (no clip window: a clipped
    /// fall showed only its last inches, and the window's headroom read as
    /// a dead gap under the caption).
    private static let fallFrom: CGFloat = 700

    /// False = the tiles wait above the screen · true = they have landed.
    @State private var fell = false
    /// prd 43h: Reduce Motion is law — under it the pile is simply there,
    /// settled, no 700pt fall (nil animation makes the flip instant).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            Text("Tap any app to add it")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .opacity(fell ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(1.5),
                           value: fell)
            // Two rows nestled brick-wise: the back row smaller and shifted
            // half a pitch — depth and irregularity, a pile not a grid.
            VStack(spacing: -10) {
                row(0..<6, size: 44).offset(x: 24)
                row(6..<12, size: 52)
            }
        }
        .onAppear {
            fell = true
            #if DEBUG
            // `-pileTap "<Offer name>"` — fire a tile's tap after the fall,
            // the headless check of the tile → product-page arc.
            if let name = UserDefaults.standard.string(forKey: "pileTap") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    NSLog("pileTap: \(name)")
                    HomeRoute.shared.openOffer = name
                    HomeRoute.shared.present(.apps)
                }
            }
            #endif
        }
    }

    private func row(_ range: Range<Int>, size: CGFloat) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(range, id: \.self) { i in
                tile(Self.pileApps[i], index: i, size: size)
            }
        }
    }

    private func tile(_ name: String, index i: Int, size: CGFloat) -> some View {
        Button {
            DSHaptic.selection()
            HomeRoute.shared.openOffer = name
            HomeRoute.shared.present(.apps)
        } label: {
            BridgeIcon(name: name, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .rotationEffect(.degrees(fell ? Self.tilt[i] : Self.tilt[i] * 0.4))
        .offset(y: fell ? Self.restY[i] : -Self.fallFrom)
        .animation(reduceMotion ? nil
                                : .easeIn(duration: 0.55).delay(0.35 + Double(i) * 0.05),
                   value: fell)
    }
}
