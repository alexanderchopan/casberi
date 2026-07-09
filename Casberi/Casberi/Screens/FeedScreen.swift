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
/// cards. "All" renders kind-aware rows; only `.approval` breaks row rhythm
/// (the consent card). Day groups, pins, swipes, the sheet, and write-confirm
/// all survive inside shapes.
struct FeedScreen: View {
    @Query(sort: \Thing.capturedAt, order: .reverse) private var things: [Thing]
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.modelContext) private var modelContext

    @State private var filter = FeedFilter.shared
    @State private var sheetThing: Thing?
    @State private var confirming: (Verb, Thing)?
    @State private var staleExpanded = false
    @State private var blockStream = GenStream()
    @State private var doorPush: HomeRoute.Push?
    @State private var liftedID: UUID?
    // First-run teaching (option 4: no demo mode — these live in the real
    // app and retire on first use, forever).
    @AppStorage("coach.chip.done") private var chipCoachDone = false
    @AppStorage("coach.swipe.done") private var swipeCoachDone = false
    /// Bumped when the source chip changes — rows replay their shape's
    /// entrance (each shape arrives its own way, ruling 2026-07-07).
    @State private var shapeWave = 0
    /// The last time the person left this screen — one timestamp, no
    /// per-thing read state. Frozen into `newSince` on each visit so the
    /// divider doesn't move while you look at it (ruling 2026-07-09).
    @AppStorage("feed.lastSeen") private var lastSeenStamp = 0.0
    @State private var newSince: Date?
    @Namespace private var zoomNS
    @Environment(\.openURL) private var openURL

    /// The shape a source takes when its chip is in force.
    private enum Shape {
        case all, photos, wallet, calendar, gmail, chat, reminders, agent, safari, notes, you, plain
        init(source: String) {
            switch source {
            case "All":                 self = .all
            case "Photos":              self = .photos
            case "Wallet":              self = .wallet
            case "Calendar", "Cal.com", "Calendly": self = .calendar
            case "Gmail", "iCloud Mail": self = .gmail
            case "ChatGPT", "Claude", "Slack", "Farcaster", "Bluesky": self = .chat
            case "Reminders", "Todoist": self = .reminders
            case "OpenClaw":            self = .agent
            case "Safari":              self = .safari
            case "Notes":               self = .notes
            case "You", "Voice":        self = .you
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
        case .wallet:   .init(dx: 0, dy: 16, scale: 1, step: 0.04)
        case .photos:   .init(dx: 0, dy: 0, scale: 0.92, step: 0.03)
        default:        .init(dx: 0, dy: 8, scale: 1, step: 0.028)
        }
    }

    // MARK: - Derivations

    private var visible: [Thing] {
        things.filter { thing in
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

    /// Sources ordered by TODAY's count first, then total, then name — the
    /// apps moving right now lead the row; a quiet bridge's chip drifts back
    /// instead of squatting up front on lifetime volume (ruling 2026-07-09).
    /// (Chips, never a dropdown: menus die.)
    private var sources: [String] {
        var total: [String: Int] = [:]
        var today: [String: Int] = [:]
        for thing in things {
            total[thing.source, default: 0] += 1
            if Calendar.current.isDateInToday(thing.capturedAt) {
                today[thing.source, default: 0] += 1
            }
        }
        let ordered = total.keys.sorted {
            let ta = today[$0] ?? 0, tb = today[$1] ?? 0
            if ta != tb { return ta > tb }
            if total[$0]! != total[$1]! { return total[$0]! > total[$1]! }
            return $0 < $1
        }
        return ["All"] + ordered
    }

    private var pinned: [Thing] { visible.filter(\.pinned) }

    /// The one row that teaches the swipe (demo only, once): it nudges left,
    /// a pin peeks out, it settles back. Motion, not a tooltip.
    private var hintThingID: UUID? {
        guard !swipeCoachDone else { return nil }
        return unpinned.first(where: { $0.kind != .approval })?.id
    }
    private var unpinned: [Thing] { visible.filter { !$0.pinned } }

    /// Day groups, newest day first ("Today", "Yesterday", then dated).
    private var dayGroups: [(String, [Thing])] {
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for thing in unpinned {
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
    }

    /// 4+ bundleable things from one source in one day collapse into a
    /// BundleRow at the position of their newest member. Order is untouched
    /// otherwise — compression, not ranking.
    private var bundledDayGroups: [(String, [FeedRow])] {
        dayGroups.map { label, dayThings in
            var counts: [String: Int] = [:]
            for t in dayThings where bundleable(t) { counts[t.source, default: 0] += 1 }
            let bundledSources = Set(counts.filter { $0.value >= 4 }.keys)
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
    private var newBoundaryID: String? {
        guard let newSince else { return nil }
        let all = bundledDayGroups.flatMap(\.1)
        guard let first = all.first, first.date > newSince else { return nil }
        return all.first(where: { $0.date <= newSince })?.id
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            feedList
                .navigationTitle("Feed")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    // The shell's doors ride every tab root (ruling 2026-07-06)
                    // — Feed had no way to Apps/Settings without visiting Home.
                    TopDoors(onSettings: { doorPush = .settings },
                             onApps: { doorPush = .apps })
                }
                .navigationDestination(item: $doorPush) { push in
                    switch push {
                    case .apps:     AppsScreen()
                    case .settings: SettingsScreen()
                    }
                }
        }
        .tint(DS.tint)
        // Re-tapping the Feed tab pops pushed screens and sheets back to root.
        .onChange(of: chrome.popFeed) {
            doorPush = nil
            sheetThing = nil
        }
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
                // A feed is a feed (re-ruling): one chip row — sources, plus
                // a clear chip when Home's kind bar filtered by type. The
                // type chart itself lives on Home.
                if sources.count > 2 || filter.tag != "All" {
                    HStack(spacing: DS.Space.s2) {
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
                            .onTapGesture {
                                DSHaptic.selection()
                                withAnimation(DS.Motion.standard) { filter.tag = "All" }
                            }
                            .accessibilityLabel("Clear \(label) filter")
                        }
                        if sources.count > 2 {
                            filterChips(sources, active: filter.source) { label in
                                filter.source = label
                                chipCoachDone = true   // lesson learned — coach retires
                            }
                        }
                        Spacer()
                    }
                }
                // The one feed coach line — first run only, retires on the
                // first chip tap. Plain words, no overlays, no arrows.
                if !chipCoachDone, sources.count > 2 {
                    Text("Tap a chip — the feed takes that app's shape.")
                        .dsText(.subhead13)
                        .foregroundStyle(DS.tint)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s1)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())

            if things.isEmpty {
                Group { emptyState }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else if visible.isEmpty {
                Group { filteredEmptyState }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                if !pinned.isEmpty, shape != .photos {
                    daySection("Pinned", pinned)
                }
                shapedSections
            }

            // Room for the floating bar.
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .animation(DS.Motion.standard, value: things.count)   // new things rise in
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollIndicators(.hidden)
        .minimizesChrome(chrome)
        .dsSoftTopEdge()
        .refreshable {
            // Pull to refresh runs sync (M1 CloudKit half wires in here).
            try? await Task.sleep(for: .milliseconds(600))
        }
        // The one synthesis block a shaped source earns streams through the
        // engine when its chip lands (skeleton entrance, same as Home).
        .onAppear {
            streamBlock()
            // Freeze the boundary for this visit; leaving re-stamps it.
            newSince = lastSeenStamp > 0 ? Date(timeIntervalSince1970: lastSeenStamp) : nil
            #if DEBUG
            // `-feedSource Zerion` lands on that chip for screenshots.
            if let src = UserDefaults.standard.string(forKey: "feedSource") {
                filter.source = src
            }
            #endif
        }
        .onDisappear { lastSeenStamp = Date.now.timeIntervalSince1970 }
        .onChange(of: filter.source) {
            shapeWave += 1
            streamBlock()
        }
        .sheet(item: $sheetThing) { thing in
            ThingSheetView(thing: thing)
                .navigationTransition(.zoom(sourceID: thing.id, in: zoomNS))
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

    @ViewBuilder
    private var shapedSections: some View {
        switch shape {
        case .photos:
            photoGridSection
        case .wallet:
            holdingsBlockSection
            groupedSections(dayGroups)
        case .calendar:
            groupedSections(agendaGroups)
        case .gmail:
            waitingSection
            groupedSections(dayGroups)
        case .reminders:
            reminderSections
        case .agent:
            needsYouSection
            groupedSections(agentDayGroups)
        default:
            if filter.tag != "All" && shape == .all {
                daySection(filterLabel, unpinned)
            } else if shape == .all {
                // All is where volume floods — bundles + the new-since
                // divider live here. A single source's shape IS that source;
                // bundling there would collapse the whole screen into one row.
                bundledSections
            } else {
                groupedSections(dayGroups)
            }
        }
    }

    @ViewBuilder
    private var bundledSections: some View {
        ForEach(bundledDayGroups, id: \.0) { label, rows in
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if row.id == newBoundaryID { newSinceDivider }
                    switch row {
                    case .single(let thing):
                        shapedListRow(thing, index: i)
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
                    Text("\(dayGroups.first(where: { $0.0 == label })?.1.count ?? rows.count)")
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
        Text("New since \(sinceLabel)")
            .dsText(.label12)
            .foregroundStyle(DS.tint)
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
            )
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DS.Space.s4 + DS.Space.s3,
                                 bottom: DS.Space.s2,
                                 trailing: DS.Space.s4 + DS.Space.s3))
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func groupedSections(_ groups: [(String, [Thing])]) -> some View {
        ForEach(groups, id: \.0) { label, rows in
            daySection(label, rows)
        }
    }

    /// Zerion leads with holdings — the treemap through the engine (mock Z1),
    /// demo-gated like WalletScreen.
    @ViewBuilder
    private var holdingsBlockSection: some View {
        if SourceComposition.block(source: filter.source, demo: DemoState.seedsDemoData) != nil {
            Section {
                GenRender(id: "root", els: blockStream.els)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    /// Photos: one continuous grid — day labels are overlay pills on the first
    /// photo of each day, never section breaks (mock P1).
    private var photoGridSection: some View {
        Section {
            let items = visible
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6),
                                count: items.count > 12 ? 3 : 2)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, thing in
                    let firstOfDay = i == 0
                        || dayLabel(items[i - 1].capturedAt) != dayLabel(thing.capturedAt)
                    PhotoCell(thing: thing, dayPill: firstOfDay ? dayLabel(thing.capturedAt) : nil)
                        .contentShape(Rectangle())
                        .matchedTransitionSource(id: thing.id, in: zoomNS)
                        .onTapGesture { sheetThing = thing }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }
    }

    /// Calendar reads forward: Today and upcoming days ascending, then the
    /// past, event-time order within each day (mock C2).
    private var agendaGroups: [(String, [Thing])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var buckets: [Date: [Thing]] = [:]
        for thing in unpinned {
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
    private var nextEventID: UUID? {
        unpinned.filter { $0.kind == .event && $0.capturedAt > .now }
            .min { $0.capturedAt < $1.capturedAt }?.id
    }

    /// Live right now, from the source's own current-live set (Twitch
    /// refreshes it every foreground) — never inferred from row age.
    private func isLive(_ thing: Thing) -> Bool {
        thing.source == "Twitch"
            && thing.sourceRef.map { TwitchIngest.liveRefs.contains($0) } ?? false
    }

    /// Gmail: what's waiting on you, capped at two (mock G1).
    private var waiting: [Thing] {
        unpinned.filter { $0.mark == .doing || $0.content.contains("?") }.prefix(2).map { $0 }
    }

    @ViewBuilder
    private var waitingSection: some View {
        if !waiting.isEmpty {
            daySection("Waiting on you", waiting)
        }
    }

    private var waitingIDs: Set<UUID> { Set(waiting.map(\.id)) }

    /// Reminders: state groups — Doing, To do (stale todos collapse), Done
    /// (same-day only).
    @ViewBuilder
    private var reminderSections: some View {
        let doing = unpinned.filter { $0.mark == .doing }
        let todos = unpinned.filter { $0.mark == .todo || $0.mark == .none }
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let fresh = todos.filter { $0.capturedAt > weekAgo }
        let stale = todos.filter { $0.capturedAt <= weekAgo }
        let doneToday = unpinned.filter {
            $0.mark == .done && Calendar.current.isDateInToday($0.capturedAt)
        }
        if !doing.isEmpty { daySection("Doing", doing) }
        if !fresh.isEmpty || !stale.isEmpty {
            Section {
                ForEach(Array(fresh.enumerated()), id: \.element.id) { i, thing in shapedListRow(thing, index: i) }
                if !stale.isEmpty {
                    if staleExpanded {
                        ForEach(Array(stale.enumerated()), id: \.element.id) { i, thing in shapedListRow(thing, index: i) }
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
        if !doneToday.isEmpty { daySection("Done", doneToday) }
    }

    /// OpenClaw: pending asks lead as consent cards; the groups below
    /// carry runs and jobs with their status ticks.
    private var pendingApprovals: [Thing] {
        unpinned.filter { $0.kind == .approval && $0.mark != .done }
    }

    @ViewBuilder
    private var needsYouSection: some View {
        if !pendingApprovals.isEmpty {
            daySection("Needs you", pendingApprovals)
        }
    }

    /// Day groups minus the approvals already shown above.
    private var agentDayGroups: [(String, [Thing])] {
        let shown = Set(pendingApprovals.map(\.id))
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for thing in unpinned where !shown.contains(thing.id) {
            let label = dayLabel(thing.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(thing)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    // MARK: - Row dispatch (the shape decides what a row leads with)

    /// The row inside a list section, with the standard list plumbing attached.
    private func shapedListRow(_ thing: Thing, index: Int = 0) -> some View {
        let lifted = liftedID == thing.id
        // AnyView: same metadata-depth insurance as GenRender (crash fix).
        return AnyView(shapedRow(thing))
            .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
            .modifier(SwipeHintNudge(active: thing.id == hintThingID) {
                swipeCoachDone = true
            })
            // The pin lift (§11): a brief raise while the row glides to the
            // Pinned section.
            .scaleEffect(lifted ? 1.02 : 1)
            .shadow(color: .black.opacity(lifted ? 0.2 : 0), radius: lifted ? 8 : 0)
            .contentShape(Rectangle())
            .matchedTransitionSource(id: thing.id, in: zoomNS)
            .onTapGesture { sheetThing = thing }
            // V3b (2026-07-07, supersedes the kind-color wash): rows are
            // NEUTRAL cards — the translucent kind wash read as murk. Color
            // moved into the tag text: the project's own stable hue.
            .listRowBackground(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.surfaceSheet)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s1)
            )
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DS.Space.s4 + DS.Space.s3,
                                 bottom: DS.Space.s2,
                                 trailing: DS.Space.s4 + DS.Space.s3))
            .listRowSeparator(.hidden)
            // One gesture, one meaning (re-ruling 2026-07-07): TAP opens the
            // sheet — tags and verbs live there — and SWIPE is Pin plus the
            // real hand-off: Open IN THE SOURCE APP, only when the thing has
            // a destination (calshow://, the link, photos-redirect://…).
            // Tag left the swipe — it was the tap in disguise, and reaching
            // past it kept misfiring the pin.
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    togglePin(thing)
                } label: {
                    Label(thing.pinned ? "Unpin" : "Pin",
                          systemImage: thing.pinned ? "pin.slash" : "pin")
                }
                .tint(DS.tint)
                if let openVerb = VerbDerivation.verbs(for: thing).first(where: {
                    if case .openURL = $0.action { return true } else { return false }
                }) {
                    Button {
                        run(openVerb, on: thing)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                    .tint(DS.gray600)
                }
            }
    }

    @ViewBuilder
    private func shapedRow(_ thing: Thing) -> some View {
        // Approval is the one rhythm-breaker everywhere: the consent card.
        if thing.kind == .approval, thing.mark != .done {
            ApprovalCard(thing: thing,
                         onApprove: { perform(Verb(label: "Approve", icon: "checkmark.circle", action: .approve), on: thing) },
                         onDeny: { perform(Verb(label: "Deny", icon: "xmark.circle", action: .deny), on: thing) })
        } else {
            // B2b (ruling 2026-07-06): ONE row anatomy — the band — for every
            // kind and every shape. The wash carries the kind; per-kind row
            // shapes retired. Two earned exceptions: the reminders check
            // circle (the lightest write) and the pinned/doing chat takeaway.
            switch shape {
            case .calendar:  BandRow(thing: thing, emphasized: thing.id == nextEventID)
            case .reminders: CheckRow(thing: thing, onToggle: { toggleReminder(thing) })
            case .chat where thing.pinned || thing.mark == .doing:
                TakeawayCard(thing: thing)
            default:
                // Perishables show their clock everywhere (ruling 2026-07-09):
                // the next event's countdown and a stream's Live state ride
                // the row in All too, not just in their source's shape.
                BandRow(thing: thing,
                        emphasized: thing.id == nextEventID,
                        live: isLive(thing))
            }
        }
    }

    /// The check circle IS the consent for the lightest write; tapping again
    /// is the undo (shaped-feeds ruling).
    private func toggleReminder(_ thing: Thing) {
        let nowDone = thing.mark != .done
        thing.mark = nowDone ? .done : .todo
        try? modelContext.save()
        DSHaptic.success()
        chrome.flash(nowDone ? "Done — tap again to undo" : "Back on the list")
        Task { await ScheduleIngest.setCompleted(thing.sourceRef, nowDone) }
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
                doorPush = .apps
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
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s6)
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

    private func filterChips(_ labels: [String], active: String,
                             onTap: @escaping (String) -> Void) -> some View {
        // ScrollViewReader keeps the ACTIVE chip visible — a deep link
        // (casberi://feed/source/Zerion) can select a chip that sits past
        // the fold, and a filter you can't see reads as no filter at all.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(labels, id: \.self) { label in
                        let isActive = label == active
                        // Icons joined the chips (re-ruling 2026-07-06 — real
                        // brand assets exist now, so the icon IS the identity).
                        // Inactive chips are icon-ONLY (ruling 2026-07-09): the
                        // labels were what made the row scroll; only the active
                        // chip names itself. "All" keeps its word — it has no app.
                        HStack(spacing: DS.Space.s1 + 2) {
                            if label != "All" {
                                BridgeIcon(name: label, size: 24)
                            }
                            if isActive || label == "All" {
                                Text(label).dsText(.label12)
                                    .foregroundStyle(isActive ? DS.page : DS.textSecondary)
                            }
                        }
                        // Icon-only chips are true 32pt circles — the logo
                        // fills the chip instead of floating in it.
                        .padding(.horizontal, isActive || label == "All" ? DS.Space.s3 : DS.Space.s1)
                        .frame(height: 32)
                        .background(isActive ? DS.textPrimary : DS.gray100,
                                    in: Capsule(style: .continuous))
                        .id(label)
                        .onTapGesture { DSHaptic.selection(); withAnimation(DS.Motion.standard) { onTap(label) } }
                    }
                }
                .padding(.horizontal, DS.Space.s4)
            }
            .onAppear {
                if active != "All" { proxy.scrollTo(active, anchor: .center) }
            }
            .onChange(of: active) { _, now in
                guard now != "All" else { return }
                withAnimation(DS.Motion.standard) { proxy.scrollTo(now, anchor: .center) }
            }
        }
    }

    /// A day group as a native section: rounded sheet card, native swipes
    /// (To do / Doing), native scroll — no gesture fights.
    @ViewBuilder
    private func daySection(_ label: String, _ rows: [Thing]) -> some View {
        Section {
            // Rows dispatch by shape (shaped feeds); the swipe stays triage —
            // reads only, writes live in the sheet (ruling), Copy sheet-only.
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, thing in
                shapedListRow(thing, index: i)
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(label).dsText(.heading17).foregroundStyle(DS.textPrimary)
                Text("\(rows.count)").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .contentTransition(.numericText())
            }
            .textCase(nil)
            .padding(.leading, DS.Space.s4)
            .padding(.vertical, DS.Space.s1)
        }
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
            try? modelContext.save()
        case .approve:
            // An MCP client asked to save a thing (PRD §34) — the approval
            // carries the payload; the tap is what commits it. Consent → write.
            if thing.sourceRef == MCPTools.saveMarker,
               let real = Capture.thing(from: thing.content, source: thing.source) {
                modelContext.insert(real)
                thing.mark = .done
                try? modelContext.save()
                SpotlightIndex.index([real])
                DSHaptic.success()
                chrome.flash("Saved")
            } else {
                withAnimation(DS.Motion.standard) {
                    thing.mark = .done
                    try? modelContext.save()
                }
                DSHaptic.success()
                chrome.flash("Approved — sent to your gateway")
            }
        case .deny:
            withAnimation(DS.Motion.standard) {
                thing.mark = .done
                try? modelContext.save()
            }
            chrome.flash("Denied — your gateway was told")
        }
    }

    private func togglePin(_ thing: Thing) {
        DSHaptic.tap()
        liftedID = thing.id
        withAnimation(DS.Motion.standard) {
            thing.pinned.toggle()
            try? modelContext.save()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(DS.Motion.standard) { liftedID = nil }
        }
    }

    private func streamBlock() {
        if let doc = SourceComposition.block(source: filter.source,
                                             demo: DemoState.seedsDemoData) {
            blockStream.stream(doc)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
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


/// The demo's swipe lesson: the first row nudges left once, the pin peeks
/// from the trailing edge, and the row settles back. Plays a single time.
struct SwipeHintNudge: ViewModifier {
    let active: Bool
    var onDone: () -> Void
    @State private var nudge: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: nudge)
            .background(alignment: .trailing) {
                if active {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.tint)
                        .opacity(nudge < -8 ? Double(min(1, -nudge / 48)) : 0)
                }
            }
            .onAppear {
                guard active else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1400))
                    withAnimation(.spring(duration: 0.45, bounce: 0.35)) { nudge = -56 }
                    try? await Task.sleep(for: .milliseconds(800))
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) { nudge = 0 }
                    try? await Task.sleep(for: .milliseconds(400))
                    onDone()
                }
            }
    }
}
