import SwiftUI
import SwiftData

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
    @Query(sort: \Thing.capturedAt, order: .reverse) private var things: [Thing]
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.modelContext) private var modelContext

    @State private var filter = FeedFilter.shared
    @State private var sheetThing: Thing?
    /// A tapped holdings cell whose token isn't watched — its quick chart
    /// (2026-07-14). Watched ones open their thing via sheetThing.
    @State private var quickToken: TokenQuickRoute?
    @State private var confirming: (Verb, Thing)?
    @State private var staleExpanded = false
    @State private var blockStream = GenStream()
    @Bindable private var wallet = WalletStore.shared
    @State private var pushedBridge: BridgeRouter.Destination?
    // First-run teaching (option 4: no demo mode — this lives in the real
    // app and retires on first use, forever).
    @AppStorage("coach.swipe.done") private var swipeCoachDone = false
    /// Bumped when the source chip changes — rows replay their shape's
    /// entrance (each shape arrives its own way, ruling 2026-07-07).
    @State private var shapeWave = 0
    /// Eases 1 → 0 on each source switch: the app's hue floods down over the
    /// feed for a beat, then recedes as the shaped rows compose beneath it —
    /// the color arriving, so a switch reads as "entering this app's feed"
    /// (delight, 2026-07-12) instead of a quiet crossfade behind the content.
    @State private var flood: CGFloat = 0
    /// The last time the person left each feed — one timestamp per source
    /// (All included; "feed.lastSeen" is All's original key, so nothing
    /// migrates), no per-thing read state. Each room's boundary freezes the
    /// FIRST time it lands during a visit and holds for the whole visit
    /// (ruling 2026-07-09: the divider never moves while you look at it —
    /// a chip bounce out and back must not erase it), and every room visited
    /// is stamped only when the screen goes away. onDisappear reads the
    /// visited SET, not `filter.source`: switching to the Pinned chip swaps
    /// this screen out with the shared filter already reading "Pinned",
    /// which would stamp a junk key and skip the real room (review
    /// 2026-07-13).
    @State private var newSince: Date?
    @State private var visitFrozen: [String: Date?] = [:]
    @State private var visitedSources: Set<String> = []
    @Namespace private var zoomNS
    /// prd 43h: Reduce Motion is law — the hand-rolled moves (the switch flood,
    /// row entrances) fall back to plain state changes under it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// The shape a source takes when its chip is in force.
    private enum Shape {
        case all, photos, wallet, calendar, gmail, chat, social, reminders, agent, safari, notes, you, music, tokens, plain
        init(source: String) {
            switch source {
            case "All":                 self = .all
            case "Photos":              self = .photos
            case "Wallet":              self = .wallet
            case "Calendar", "Cal.com", "Calendly": self = .calendar
            case "Gmail", "iCloud Mail": self = .gmail
            case "ChatGPT", "Claude", "Gemini", "Slack": self = .chat
            // Posts read as posts in their own room (2026-07-13) — split from
            // .chat: a saved conversation is a snippet row, a post is a card.
            case "Farcaster", "Bluesky": self = .social
            case "Reminders", "Todoist": self = .reminders
            case "OpenClaw":            self = .agent
            case "Safari":              self = .safari
            // Obsidian joins the notes room — the vault is notes (prd §59).
            case "Notes", "Day One", "Apple Journal", "Obsidian": self = .notes
            case "You", "Voice":        self = .you
            case "Apple Music", "Spotify": self = .music
            case "Tokens":              self = .tokens
            default:                    self = .plain
            }
        }
    }
    private var shape: Shape { Shape(source: filter.source) }


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
            (filter.source == "All" || thing.source == filter.source)
                && (filter.tag == "All" || thing.tags.contains(filter.tag))
        }
    }
    private var isFiltered: Bool { filter.source != "All" || filter.tag != "All" }
    private var filterLabel: String {
        let tagLabel = filter.tag == "All" ? nil
            : (ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag)
        return [filter.source == "All" ? nil : filter.source, tagLabel]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The connected bridge the feed is currently filtered to, if any. A source
    /// header appears only for a real, live seat — a plain source (Photos,
    /// Voice, Safari) owns no control panel, so it gets no door. Paused seats
    /// aren't "connected", so they don't either.
    private var activeSourceBridge: BridgeApp? {
        guard filter.source != "All" else { return nil }
        return bridges.bridges.first { $0.name == filter.source && $0.status != .paused }
    }

    /// The one row that teaches the swipe (demo only, once): it nudges left,
    /// a pin peeks out, it settles back. Motion, not a tooltip.
    /// Takes the already-computed `visible` so the caller derives it ONCE per
    /// render and shares it, same convention as `bundle`/`boundaryID` below.
    private func hintThingID(_ visible: [Thing]) -> UUID? {
        guard !swipeCoachDone else { return nil }
        return visible.first(where: { $0.kind != .approval })?.id
    }

    /// Day groups, newest day first ("Today", "Yesterday", then dated).
    private func dayGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for thing in visible {
            let label = dayLabel(thing.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(thing)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    // MARK: - Bundling (ruling 2026-07-09: volume compresses, never reorders)

    /// A feed row in the All shape: a thing, or one row standing in for a
    /// source's bulk arrivals that day.
    private enum FeedRow: Identifiable {
        case single(Thing)
        case bundle(source: String, word: String, count: Int, newest: Date)
        var id: String {
            switch self {
            case .single(let t): t.id.uuidString
            case .bundle(let source, _, _, let newest):
                "bundle-\(source)-\(newest.timeIntervalSince1970)"
            }
        }
        var date: Date {
            switch self {
            case .single(let t): t.capturedAt
            case .bundle(_, _, _, let newest): newest
            }
        }
    }

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
                    rows.append(.bundle(source: t.source, word: word,
                                        count: members.count, newest: t.capturedAt))
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
            .navigationDestination(item: $pushedBridge) { BridgeDestinationView(destination: $0) }
            // Re-tapping the active chip pops this surface's own pushed
            // screens and sheets back to root (the old per-tab pop habit).
            .onChange(of: chrome.popHome) {
                sheetThing = nil
                pushedBridge = nil
                confirming = nil
            }
    }

    /// The switch flood (delight, 2026-07-12): the source's hue sweeps down
    /// over the feed and fades out as you land on its chip. Top-heavy and
    /// brief so it never buries the rows — `flood` eases 1 → 0 in ~0.5s — and
    /// it's the color moment the quiet background crossfade lacked. Absent for
    /// All (no identity hue) and under Reduce Motion (`flood` never rises).
    @ViewBuilder private var switchFlood: some View {
        if let hue = DS.washHue(for: filter.source) {
            // A TOP-BAND kiss, not a full-bleed veil: it reinforces the resting
            // wash's zone and clears well before the rows, so even a dark-hued
            // source is a brief tint at the crown, never a screen-wide dim.
            LinearGradient(colors: [hue.opacity(0.34), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .frame(maxWidth: .infinity, alignment: .top)
                .opacity(flood)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    /// A slim, tappable strip above a single source's shaped feed: the app, its
    /// live status. Tapping opens the app's control panel through the router —
    /// the dedicated screen when the bridge has one (Tokens' watchlist,
    /// Wallet's addresses), the generic detail page otherwise. It rides
    /// `pushedBridge` — the same channel a Wallet row already uses. (2026-07-11:
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
    /// instead, same grammar as the OpenClaw presence line below the chips.
    private func sourceHeader(_ bridge: BridgeApp, showAddHint: Bool,
                              headerCompose: SourceAction? = nil) -> some View {
        HStack(spacing: DS.Space.s2) {
        Button {
            DSHaptic.selection()
            pushedBridge = BridgeRouter.destination(forID: bridge.id)
        } label: {
            HStack(spacing: DS.Space.s2) {
                Circle()
                    .fill(bridge.status == .connected ? DS.confirm : bridge.status.color)
                    .frame(width: 6, height: 6)
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

    private var feedList: some View {
        List {
            Group {
                // Machine presence (S11) — one line, only when a gateway
                // listens. Status is a signal here, never a screen.
                if let gateway = bridges.bridges.first(where: {
                    $0.name == "OpenClaw" && $0.status == .connected
                }) {
                    HStack(spacing: DS.Space.s2) {
                        Circle().fill(DS.confirm).frame(width: 6, height: 6)
                        Text("\(gateway.name) · \(gateway.statusLine)")
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s2)
                }
                // The source chips moved to the shell's fixed header
                // (MainSurface / SourceChips) — the app is one surface now. What
                // stays here is the kind-clear chip: Home's kind bar and the
                // casberi://feed/type/<Tag> route can land the feed filtered by
                // type, and that filter clears from a chip in place.
                if filter.tag != "All" {
                    let label = ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag
                    HStack(spacing: DS.Space.s1) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
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
                    let hintID = hintThingID(visible)
                    let nextID = nextEventID(visible)
                    // A pin is a HOME pin only (ruling 2026-07-10): the Feed's
                    // own Pinned section doubled what Home already shows and
                    // cluttered the record — pinned things now ride the feed in
                    // their natural chronological place. The holdings module
                    // lives on Home too (same-day amendment) — in Feed it shows
                    // only in the Wallet chip's own shape, never leading All.
                    shapedSections(visible, hintID: hintID, nextEventID: nextID)
                    // No closing line in the Reminders shape: its state groups
                    // deliberately render a subset (Done shows same-day only), so
                    // a `visible`-count claim would disagree with the rows above.
                    if shape != .reminders {
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
        .refreshable { await refreshFeed() }
        .animation(DS.Motion.standard, value: things.count)   // new things rise in
        .scrollContentBackground(.hidden)
        .overlay(alignment: .top) { switchFlood }
        // A SHAPED feed sits directly on MainSurface's bold hue field (user
        // ruling 2026-07-13, Cash-App bold): painting the opaque page here
        // would hide it — the very bug that once forced the wash to be an
        // overlay. Pinned/All/hueless keep the normal page coat.
        .background {
            if DS.washHue(for: filter.source) == nil {
                DSPageBackground()
            }
        }
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollIndicators(.hidden)
        .minimizesChrome(chrome)
        .dsSoftTopEdge()
        .refreshable {
            // Pull to refresh runs sync (M1 CloudKit half wires in here).
            chrome.refreshPulse += 1   // spins the avatar door, deals the berry rain
            try? await Task.sleep(for: .milliseconds(600))
        }
        // The one synthesis block a shaped source earns streams through the
        // engine when its chip lands (skeleton entrance, same as Home).
        .onAppear {
            streamBlock()
            #if DEBUG
            // `-feedSource Zerion` lands on that chip for screenshots.
            if let src = UserDefaults.standard.string(forKey: "feedSource") {
                filter.source = src
            }
            #endif
            // Freeze the boundary for this visit; leaving re-stamps it.
            // (After the DEBUG hook, so a forced chip reads its own stamp
            // and All is never marked visited by a hooked launch.)
            freezeBoundary(for: filter.source)
        }
        .onDisappear { visitedSources.forEach(stampSeen) }
        .onChange(of: filter.source) { _, new in
            freezeBoundary(for: new)
            shapeWave += 1
            // The hue floods in, then recedes as the shaped rows compose.
            if !reduceMotion {
                flood = 1
                withAnimation(.easeOut(duration: 0.55)) { flood = 0 }
            }
            streamBlock()
        }
        // Adding/removing a watched wallet re-fetches the Wallet chip's
        // holdings block while it's in force.
        .onChange(of: wallet.addresses) { streamBlock() }
        .sheet(item: $sheetThing) { thing in
            ThingSheetView(thing: thing)
                .navigationTransition(.zoom(sourceID: thing.id, in: zoomNS))
        }
        .sheet(item: $quickToken) { route in
            TokenQuickSheet(route: route)
        }
        .confirmationDialog(
            confirming.map { "\($0.0.label): \($0.1.title)?" } ?? "",
            isPresented: Binding(get: { confirming != nil },
                                 set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let (verb, thing) = confirming {
                Button(verb.label) { perform(verb, on: thing); confirming = nil }
                Button("Cancel", role: .cancel) { confirming = nil }
            }
        }
    }

    // MARK: - Shaped sections (one source in force = its native shape)

    /// Takes the render's one `visible` derivation (and the hint/next-event
    /// ids computed alongside it) and threads them into every shape branch —
    /// none of the branches below re-derive `visible` themselves.
    @ViewBuilder
    private func shapedSections(_ visible: [Thing], hintID: UUID?, nextEventID: UUID?) -> some View {
        // The new-since divider rides every chronological shape now
        // (2026-07-13) — each source's feed keeps its own last-visit stamp.
        // Photos (a grid), Calendar (future-first) and Reminders (state
        // groups) aren't chronological top-to-bottom, so no line there.
        switch shape {
        case .photos:
            photoGridSection(visible)
        case .wallet:
            holdingsBlockSection
            let days = dayGroups(visible)
            groupedSections(days, hintID: hintID, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .calendar:
            groupedSections(agendaGroups(visible), hintID: hintID, nextEventID: nextEventID)
        case .gmail:
            waitingSection(visible, hintID: hintID, nextEventID: nextEventID)
            let days = dayGroups(visible)
            groupedSections(days, hintID: hintID, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .reminders:
            reminderSections(visible, hintID: hintID, nextEventID: nextEventID)
        case .agent:
            let approvals = pendingApprovals(visible)
            needsYouSection(approvals, hintID: hintID, nextEventID: nextEventID)
            let days = agentDayGroups(visible, excluding: approvals)
            groupedSections(days, hintID: hintID, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .music:
            listeningLedeSection(visible)
            let days = dayGroups(visible)
            groupedSections(days, hintID: hintID, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .tokens:
            watchlistLedeSection(visible)
            let days = dayGroups(visible)
            groupedSections(days, hintID: hintID, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        default:
            if filter.tag != "All" && shape == .all {
                daySection(filterLabel, visible, hintID: hintID, nextEventID: nextEventID)
            } else if shape == .all {
                // All is where volume floods — bundles + the new-since
                // divider live here. A single source's shape IS that source;
                // bundling there would collapse the whole screen into one row.
                bundledSections(visible, hintID: hintID, nextEventID: nextEventID)
            } else {
                let days = dayGroups(visible)
                groupedSections(days, hintID: hintID, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
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

    private func bundledSections(_ visible: [Thing], hintID: UUID?, nextEventID: UUID?) -> some View {
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
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if row.id == boundary { newSinceDivider }
                    switch row {
                    case .single(let thing):
                        shapedListRow(thing, index: i, hintID: hintID, nextEventID: nextEventID)
                    case .bundle(let source, let word, let count, let newest):
                        bundleListRow(source: source, word: word, count: count,
                                      newest: newest, index: i)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(label).dsText(.heading17).foregroundStyle(DS.textPrimary)
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
        Text("New since \(sinceLabel)")
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

    /// Lands on a room: its boundary freezes on FIRST arrival this visit and
    /// re-reads from the frozen copy after — a bounce out to another chip and
    /// back can't move the line. Pinned isn't a feed room (the board swaps
    /// this screen out), so it never freezes or stamps.
    private func freezeBoundary(for source: String) {
        guard source != "Pinned" else { return }
        visitedSources.insert(source)
        if let frozen = visitFrozen[source] {
            newSince = frozen
        } else {
            let stamp = lastSeen(for: source)
            visitFrozen[source] = stamp
            newSince = stamp
        }
    }

    /// A bundle in the list: same card treatment as a thing row; the tap
    /// opens the source's own shape (where volume is designed to live) —
    /// no swipes, nothing here is a single thing to pin or open.
    private func bundleListRow(source: String, word: String, count: Int,
                               newest: Date, index: Int) -> some View {
        BundleRow(source: source, count: count, word: word, newest: newest)
            .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
            .contentShape(Rectangle())
            .onTapGesture {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { filter.source = source }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.surfaceSheet)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s1)
                    .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
            )
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
                                 hintID: UUID?, nextEventID: UUID?,
                                 boundary: UUID? = nil) -> some View {
        ForEach(groups, id: \.0) { label, rows in
            daySection(label, rows, hintID: hintID, nextEventID: nextEventID, boundary: boundary)
        }
    }

    /// The wallet leads with holdings — real, from Alchemy (WalletIngest),
    /// one treemap per watched address, same doc Home and the Wallet screen
    /// render (ruling 2026-07-09: the old mock demo-only block never showed a
    /// real user anything real).
    @ViewBuilder
    private var holdingsBlockSection: some View {
        if !blockStream.els.isEmpty {
            Section {
                GenRender(id: "root", els: blockStream.els)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    // A tapped holdings cell opens its token's chart
                    // (2026-07-14): the thing sheet when watched, the quick
                    // sheet when it's just held; a routeless native-coin
                    // cell keeps its old door — the Wallet screen (no dead
                    // controls). The Feed sets its own handler —
                    // HomeScreen's doesn't reach this surface.
                    .environment(\.genProjectTap) { name in
                        if let route = TokenQuickRoute.from(sentinel: name) {
                            if let thing = route.watchedThing(in: modelContext) {
                                sheetThing = thing
                            } else {
                                quickToken = route
                            }
                        } else if name == "@wallet" {
                            pushedBridge = .wallet
                        }
                    }
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
                        ForEach(Array(row.enumerated()), id: \.element.id) { colIndex, thing in
                            let i = rowIndex * perRow + colIndex
                            let firstOfDay = i == 0
                                || dayLabel(items[i - 1].capturedAt) != dayLabel(thing.capturedAt)
                            Button {
                                sheetThing = thing
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

    /// Gmail: what's waiting on you, capped at two (mock G1). Doing-marked
    /// only (honesty fix 2026-07-13): the old `content.contains("?")` sniff
    /// promoted any newsletter with a question mark to "waiting on you" —
    /// fake status. The section now shows only what the person marked
    /// in motion, and earns back a smarter derivation later.
    @ViewBuilder
    private func waitingSection(_ visible: [Thing], hintID: UUID?, nextEventID: UUID?) -> some View {
        let waiting = visible.filter { $0.mark == .doing }.prefix(2).map { $0 }
        if !waiting.isEmpty {
            daySection("Waiting on you", waiting, hintID: hintID, nextEventID: nextEventID)
        }
    }

    // Waiting mails stay in their day groups too (unlike agent approvals,
    // which ARE removed): a mail is a record, and excluding only the first
    // two doing-marked mails (the lede's cap) would punch order-dependent
    // holes in the day history. The lede highlights; the record stays whole.

    /// Reminders: state groups — Doing, To do (stale todos collapse), Done
    /// (same-day only).
    @ViewBuilder
    private func reminderSections(_ visible: [Thing], hintID: UUID?, nextEventID: UUID?) -> some View {
        let doing = visible.filter { $0.mark == .doing }
        let todos = visible.filter { $0.mark == .todo || $0.mark == .none }
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let fresh = todos.filter { $0.capturedAt > weekAgo }
        let stale = todos.filter { $0.capturedAt <= weekAgo }
        let doneToday = visible.filter {
            $0.mark == .done && Calendar.current.isDateInToday($0.capturedAt)
        }
        if !doing.isEmpty { daySection("Doing", doing, hintID: hintID, nextEventID: nextEventID) }
        if !fresh.isEmpty || !stale.isEmpty {
            Section {
                ForEach(Array(fresh.enumerated()), id: \.element.id) { i, thing in shapedListRow(thing, index: i, hintID: hintID, nextEventID: nextEventID) }
                if !stale.isEmpty {
                    if staleExpanded {
                        ForEach(Array(stale.enumerated()), id: \.element.id) { i, thing in shapedListRow(thing, index: i, hintID: hintID, nextEventID: nextEventID) }
                    } else {
                        HStack {
                            Text("Older").dsText(.body17).foregroundStyle(DS.textSecondary)
                            Text("\(stale.count)").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.textTertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(DS.Motion.standard) { staleExpanded = true } }
                        .listRowBackground(DS.surfaceSheet)
                        .listRowSeparator(.hidden)
                    }
                }
            } header: {
                Text("To do").dsText(.heading17).foregroundStyle(DS.textPrimary).textCase(nil)
            }
        }
        if !doneToday.isEmpty { daySection("Done", doneToday, hintID: hintID, nextEventID: nextEventID) }
    }

    /// OpenClaw: pending asks lead as consent cards; the groups below
    /// carry runs and jobs with their status ticks.
    private func pendingApprovals(_ visible: [Thing]) -> [Thing] {
        visible.filter { $0.kind == .approval && $0.mark != .done }
    }

    @ViewBuilder
    private func needsYouSection(_ approvals: [Thing], hintID: UUID?, nextEventID: UUID?) -> some View {
        if !approvals.isEmpty {
            daySection("Needs you", approvals, hintID: hintID, nextEventID: nextEventID)
        }
    }

    /// Day groups minus the approvals already shown above. Takes the
    /// approvals the caller already derived (`pendingApprovals`) instead of
    /// recomputing them a second time in the same render.
    private func agentDayGroups(_ visible: [Thing], excluding approvals: [Thing]) -> [(String, [Thing])] {
        let shown = Set(approvals.map(\.id))
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for thing in visible where !shown.contains(thing.id) {
            let label = dayLabel(thing.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(thing)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    // MARK: - Row dispatch (the shape decides what a row leads with)

    /// The swipe's hand-off target, when the thing has one — shared by both
    /// swipe edges so they agree on what counts as "has a destination".
    private func openVerb(for thing: Thing) -> Verb? {
        VerbDerivation.verbs(for: thing).first {
            if case .openURL = $0.action { return true } else { return false }
        }
    }

    /// The row inside a list section, with the standard list plumbing attached.
    private func shapedListRow(_ thing: Thing, index: Int = 0, hintID: UUID?, nextEventID: UUID?) -> some View {
        // AnyView: same metadata-depth insurance as GenRender (crash fix).
        return AnyView(shapedRow(thing, nextEventID: nextEventID))
            .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
            .modifier(SwipeHintNudge(active: thing.id == hintID) {
                swipeCoachDone = true
            })
            .contentShape(Rectangle())
            .matchedTransitionSource(id: thing.id, in: zoomNS)
            .onTapGesture { openThing(thing) }
            // V3b (2026-07-07, supersedes the kind-color wash): rows are
            // NEUTRAL cards — the translucent kind wash read as murk. Color
            // moved into the tag text: the project's own stable hue.
            .listRowBackground(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.surfaceSheet)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s1)
                    .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
            )
            // Feed rhythm (2026-07-13): back to s2 — the s3 airy read made
            // every gap the same size, so days never clustered. Rows sit
            // tight within their day; the day header carries the big gap.
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DS.Space.s4 + DS.Space.s3,
                                 bottom: DS.Space.s2,
                                 trailing: DS.Space.s4 + DS.Space.s3))
            .listRowSeparator(.hidden)
            // One gesture, one meaning: TAP opens the sheet — tags and verbs
            // live there — and SWIPE is the real hand-off: Open IN THE SOURCE
            // APP, only when the thing has a destination (calshow://, the link,
            // photos-redirect://…). Pinning left the swipe entirely (ruling
            // 2026-07-12): a pin is per-APP now, placed from the app's own
            // screen, not a per-item Feed gesture. Share joined the trailing
            // edge (2026-07-13, user): it sits ahead of Open so a full swipe
            // still hands off to the source app unchanged — full swipe is
            // gated to ONLY when Open exists, so a thing with no destination
            // (a voice note, a chat import) doesn't get Share fired by a full
            // swipe that used to do nothing.
            .swipeActions(edge: .trailing, allowsFullSwipe: openVerb(for: thing) != nil) {
                if let openVerb = openVerb(for: thing) {
                    Button {
                        run(openVerb, on: thing)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                    .tint(DS.gray600)
                }
                ThingShareLink(thing: thing) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(DS.tint)
            }
            // The hand-off earns its own edge too (2026-07-10, user):
            // full-swipe RIGHT opens in the source app — the second button
            // on the left-swipe stays for one-handed reach either way.
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let openVerb = openVerb(for: thing) {
                    Button {
                        run(openVerb, on: thing)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                    .tint(DS.confirm)
                }
            }
    }

    @ViewBuilder
    private func shapedRow(_ thing: Thing, nextEventID: UUID?) -> some View {
        // Approval is the one rhythm-breaker everywhere: the consent card.
        if thing.kind == .approval, thing.mark != .done {
            ApprovalCard(thing: thing,
                         onApprove: { perform(Verb(label: "Approve", icon: "checkmark.circle", action: .approve), on: thing) },
                         onDeny: { perform(Verb(label: "Deny", icon: "xmark.circle", action: .deny), on: thing) })
        } else {
            // B2b (ruling 2026-07-06): ONE row anatomy — the band — for every
            // kind and every shape. The wash carries the kind; per-kind row
            // shapes retired. Two earned exceptions: the reminders check
            // circle (the lightest write) and the doing chat takeaway.
            switch shape {
            case .calendar:  BandRow(thing: thing, emphasized: thing.id == nextEventID)
            case .reminders: CheckRow(thing: thing, onToggle: { toggleReminder(thing) })
            case .music:     MusicRow(thing: thing)
            case .chat where thing.mark == .doing:
                TakeawayCard(thing: thing)
            // Native anatomies (2026-07-13): in its own room a note leads
            // with its text, a conversation with its opening line, a post
            // with its author and media, a link with where it's from. All
            // keeps the band — these relax only inside the source's shape.
            case .notes:  ExcerptRow(thing: thing, lines: 3)
            case .chat:   ExcerptRow(thing: thing, lines: 2)
            case .social: PostCard(thing: thing)
            case .safari: ReadingRow(thing: thing)
            default:
                // Perishables show their clock everywhere (ruling 2026-07-09):
                // the next event's countdown and a stream's Live state ride
                // the row in All too, not just in their source's shape —
                // and a watched token its 24h pulse (Option A, 2026-07-10).
                BandRow(thing: thing,
                        emphasized: thing.id == nextEventID,
                        live: isLive(thing),
                        pulse: TokenPulse.shared.pulse(for: thing))
            }
        }
    }

    /// The check circle IS the consent for the lightest write; tapping again
    /// is the undo (shaped-feeds ruling). The local mark flips optimistically
    /// (the tap needs to feel instant), but if the real reminder's write
    /// fails, it's reverted and the toast corrects itself — a check mark
    /// that silently doesn't stick is the "fake status" the design law bans.
    private func toggleReminder(_ thing: Thing) {
        let nowDone = thing.mark != .done
        let wasMark = thing.mark
        thing.mark = nowDone ? .done : .todo
        modelContext.saveHonestly()
        DSHaptic.success()
        chrome.flash(nowDone ? "Done — tap again to undo" : "Back on the list")
        let sourceRef = thing.sourceRef
        Task {
            let ok = await ScheduleIngest.setCompleted(sourceRef, nowDone)
            guard !ok else { return }
            await MainActor.run {
                thing.mark = wasMark
                modelContext.saveHonestly()
                chrome.flash("Couldn't reach Reminders — not marked")
            }
        }
    }

    // MARK: - Pieces

    /// Empty Feed — the surface's own choreography with skeletons; the copy
    /// points to the first action (brief §7 empty states).
    private var emptyState: some View {
        // The berry draws itself on; the composer is already on screen. One
        // line, one door: an empty feed's next move is connecting an app.
        VStack(spacing: DS.Space.s3) {
            QuietStateView(line: "Things you capture land here.")
            Button {
                DSHaptic.selection()
                HomeRoute.shared.push = .apps
            } label: {
                Text("Browse apps")
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s4)
                    .frame(height: 36)
                    .background(DS.tintDim, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            // The shape of what's coming — a day header and skeleton rows
            // that stagger in the way the real feed will.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Today")
                    .dsText(.heading17).foregroundStyle(DS.textTertiary)
                    .settleIn(delay: 0.15)
                ForEach(0..<3, id: \.self) { i in
                    GenSkeletonRow()
                        .staggerIn(index: i + 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s6)
    }

    /// A filter with no matches: the filtered app's own icon, a plain line,
    /// and one way back. Never a bare "Nothing matches."
    private var filteredEmptyState: some View {
        VStack(spacing: DS.Space.s3) {
            if filter.source != "All" {
                BridgeIcon(name: filter.source, size: 44)
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
            // The empty room previews its own shape (2026-07-13) — the
            // all-feed empty state already does this with skeleton rows;
            // a shaped empty shows what ITS rows will look like: a grid
            // for Photos, rows for everything else.
            if filter.source != "All" {
                emptyShapePreview
                    .padding(.top, DS.Space.s6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s6)
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
        switch (filter.source != "All", filter.tag != "All") {
        case (true, true):   return "Nothing from \(filter.source) under \(tagLabel) yet."
        case (true, false):  return "Nothing from \(filter.source) yet."
        case (false, true):  return "No \(tagLabel.lowercased()) yet."
        default:             return "Nothing here yet."
        }
    }

    /// A wallet-sourced row (an onchain transaction) opens the Wallet screen
    /// — holdings and activity together — instead of the generic sheet,
    /// which had nothing more than an explorer link to show (ruling 2026-07-09).
    private func openThing(_ thing: Thing) {
        if thing.source == "Wallet" {
            pushedBridge = .wallet
        } else {
            sheetThing = thing
        }
    }

    /// A day group as a native section: rounded sheet card, native swipes
    /// (To do / Doing), native scroll — no gesture fights.
    @ViewBuilder
    private func daySection(_ label: String, _ rows: [Thing],
                            hintID: UUID?, nextEventID: UUID?,
                            boundary: UUID? = nil) -> some View {
        Section {
            // Rows dispatch by shape (shaped feeds); the swipe stays triage —
            // reads only, writes live in the sheet (ruling), Copy sheet-only.
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, thing in
                if thing.id == boundary { newSinceDivider }
                shapedListRow(thing, index: i, hintID: hintID, nextEventID: nextEventID)
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(label).dsText(.heading17).foregroundStyle(DS.textPrimary)
                // In a source's own room the count speaks the source's unit —
                // "3 events", "5 screenshots" (2026-07-13). All keeps the
                // bare number: mixed kinds have no one unit worth naming.
                Text(countLabel(rows)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .contentTransition(.numericText())
            }
            .textCase(nil)
            .padding(.leading, DS.Space.s4)
            // Days read as clusters (2026-07-13): the gap ABOVE a day header
            // is the feed's biggest — rows within a day sit at s2, so the s6
            // says "new day" without merging cards or drawing a line.
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
        }
    }

    /// The day header's count: a bare number in All, the source's own unit in
    /// a shaped feed — "3 events", "1 screenshot", "4 things" when mixed.
    /// The social room says "posts": its things are kind .chat (the ingest's
    /// container), but nobody calls a Bluesky post a chat.
    private func countLabel(_ rows: [Thing]) -> String {
        guard filter.source != "All" else { return "\(rows.count)" }
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
        Text(filter.source == "All"
             ? "That's everything · \(rows.count == 1 ? "1 thing" : "\(rows.count) things")"
             : "That's everything from \(filter.source) · \(countLabel(rows))")
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
                    DSHaptic.success()
                    chrome.flash("On your calendar")
                } catch { chrome.flash(error.localizedDescription) }
            }
        case .addToReminders:
            Task {
                do {
                    try await HandOff.addToReminders(thing)
                    DSHaptic.success()
                    chrome.flash("On your list")
                } catch { chrome.flash(error.localizedDescription) }
            }
        case .copyText:
            UIPasteboard.general.string = thing.content.isEmpty ? thing.title : thing.content
            chrome.flash("Copied")
        case .markDone:
            thing.mark = .done
            modelContext.saveHonestly()
        case .approve:
            // An MCP client asked to save a thing (PRD §34) — the approval
            // carries the payload; the tap is what commits it. Consent → write.
            if thing.sourceRef == MCPTools.saveMarker,
               let real = Capture.thing(from: thing.content, source: thing.source) {
                modelContext.insert(real)
                thing.mark = .done
                modelContext.saveHonestly()
                SpotlightIndex.index([real])
                DSHaptic.success()
                chrome.flash("Saved")
            } else {
                withAnimation(DS.Motion.standard) {
                    thing.mark = .done
                    modelContext.saveHonestly()
                }
                DSHaptic.success()
                // Honesty: the answer is recorded on the thing. Nothing is
                // sent anywhere — no agent transport exists yet (2026-07-10;
                // the old copy claimed a gateway was told).
                chrome.flash("Approved")
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
        BridgeRefresh.refreshAllConnected(context: modelContext, store: bridges)
        chrome.refreshPulse += 1   // spins the avatar door, deals the berry rain
        shapeWave += 1
        streamBlock()
        try? await Task.sleep(for: .milliseconds(450))
        DSHaptic.success()
    }

    private func streamBlock() {
        guard filter.source == "Wallet" else {
            if !blockStream.els.isEmpty { blockStream.paint([]) }
            return
        }
        Task { @MainActor in
            if let doc = await WalletIngest.holdingsChart() {
                blockStream.paint(doc)
            } else if !blockStream.els.isEmpty {
                blockStream.paint([])
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
