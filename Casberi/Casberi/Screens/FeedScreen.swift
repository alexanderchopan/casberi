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
    @State private var quickTagThing: Thing?
    @State private var moreThing: Thing?
    @Namespace private var zoomNS
    @Environment(\.openURL) private var openURL

    /// The shape a source takes when its chip is in force.
    private enum Shape {
        case all, photos, zerion, calendar, gmail, chat, reminders, agent, safari, notes, you, plain
        init(source: String) {
            switch source {
            case "All":                 self = .all
            case "Photos":              self = .photos
            case "Zerion":              self = .zerion
            case "Calendar":            self = .calendar
            case "Gmail", "iCloud Mail": self = .gmail
            case "ChatGPT", "Claude":   self = .chat
            case "Reminders":           self = .reminders
            case "OpenClaw", "Bankr":   self = .agent
            case "Safari":              self = .safari
            case "Notes":               self = .notes
            case "You":                 self = .you
            default:                    self = .plain
            }
        }
    }
    private var shape: Shape { Shape(source: filter.source) }

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

    /// Sources by thing count — the ones that matter sit first; the tail
    /// scrolls. (Chips, never a dropdown: menus die.)
    private var sources: [String] {
        var counts: [String: Int] = [:]
        for thing in things { counts[thing.source, default: 0] += 1 }
        let ordered = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }.map(\.key)
        return ["All"] + ordered
    }

    private var pinned: [Thing] { visible.filter(\.pinned) }
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
                            .onTapGesture {
                                DSHaptic.selection()
                                withAnimation(DS.Motion.standard) { filter.tag = "All" }
                            }
                            .accessibilityLabel("Clear \(label) filter")
                        }
                        if sources.count > 2 {
                            filterChips(sources, active: filter.source) { filter.source = $0 }
                        }
                        Spacer()
                    }
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
                Text("Nothing matches.")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    .padding(DS.Space.s6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
        .listStyle(.insetGrouped)
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
            #if DEBUG
            // `-feedSource Zerion` lands on that chip for screenshots.
            if let src = UserDefaults.standard.string(forKey: "feedSource") {
                filter.source = src
            }
            #endif
        }
        .onChange(of: filter.source) { streamBlock() }
        .sheet(item: $sheetThing) { thing in
            ThingSheetView(thing: thing)
                .navigationTransition(.zoom(sourceID: thing.id, in: zoomNS))
        }
        // The swipe's quick-tag tray — tag without opening the thing.
        .sheet(item: $quickTagThing) { thing in
            QuickTagSheet(thing: thing)
        }
        // The swipe's More — the read verbs, Mail-style.
        .confirmationDialog(
            moreThing?.title ?? "",
            isPresented: Binding(get: { moreThing != nil },
                                 set: { if !$0 { moreThing = nil } }),
            titleVisibility: .visible
        ) {
            if let thing = moreThing {
                ForEach(VerbDerivation.verbs(for: thing)
                    .filter { verb in
                        if case .copyText = verb.action { return false }
                        return !verb.isWrite
                    }
                    .prefix(3)) { verb in
                    Button(verb.label) { run(verb, on: thing) }
                }
                Button("Open", systemImage: "arrow.up.right") { sheetThing = thing }
                Button("Cancel", role: .cancel) { moreThing = nil }
            }
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
        case .zerion:
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
            } else {
                groupedSections(dayGroups)
            }
        }
    }

    @ViewBuilder
    private func groupedSections(_ groups: [(String, [Thing])]) -> some View {
        ForEach(groups, id: \.0) { label, rows in
            daySection(label, rows)
        }
    }

    /// Zerion leads with holdings — the treemap through the engine (mock Z1),
    /// demo-gated like ZerionScreen.
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
    private var nextEventID: UUID? {
        unpinned.filter { $0.capturedAt > .now }.min { $0.capturedAt < $1.capturedAt }?.id
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
                ForEach(fresh) { thing in shapedListRow(thing) }
                if !stale.isEmpty {
                    if staleExpanded {
                        ForEach(stale) { thing in shapedListRow(thing) }
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

    /// OpenClaw/Bankr: pending asks lead as consent cards; the groups below
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
    private func shapedListRow(_ thing: Thing) -> some View {
        let lifted = liftedID == thing.id
        return shapedRow(thing)
            // The pin lift (§11): a brief raise while the row glides to the
            // Pinned section.
            .scaleEffect(lifted ? 1.02 : 1)
            .shadow(color: .black.opacity(lifted ? 0.2 : 0), radius: lifted ? 8 : 0)
            .contentShape(Rectangle())
            .matchedTransitionSource(id: thing.id, in: zoomNS)
            .onTapGesture { sheetThing = thing }
            .listRowBackground(DS.surfaceSheet)
            .listRowSeparator(.hidden)
            // One swipe side, Mail's anatomy (ruling 2026-07-06): Pin at the
            // edge (full swipe pins), Tag, then More for the read verbs.
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    togglePin(thing)
                } label: {
                    Label(thing.pinned ? "Unpin" : "Pin",
                          systemImage: thing.pinned ? "pin.slash" : "pin")
                }
                .tint(DS.tint)
                Button {
                    quickTagThing = thing
                } label: {
                    Label("Tag", systemImage: "tag")
                }
                .tint(DS.confirm)
                Button {
                    moreThing = thing
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .tint(DS.gray600)
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
            switch shape {
            case .zerion:    TxRow(thing: thing)
            case .calendar:  AgendaRow(thing: thing, emphasized: thing.id == nextEventID)
            case .gmail:     MailRow(thing: thing)
            case .chat:
                if thing.pinned || thing.mark == .doing {
                    TakeawayCard(thing: thing)
                } else {
                    FeedRow(thing: thing)
                }
            case .reminders: CheckRow(thing: thing, onToggle: { toggleReminder(thing) })
            case .agent:     StatusTickRow(thing: thing)
            case .safari:    LinkRow(thing: thing)
            case .notes:     NoteRow(thing: thing)
            case .you:
                if thing.kind == .voice {
                    VoiceRow(thing: thing)
                } else {
                    KindAwareRow(thing: thing)
                }
            default:         KindAwareRow(thing: thing)
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
        // The berry draws itself on; the composer is already on screen, so
        // no button (§5). One line, plain words.
        QuietStateView(line: "Things you capture land here.")
            .padding(.top, DS.Space.s6)
    }

    private func filterChips(_ labels: [String], active: String,
                             onTap: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(labels, id: \.self) { label in
                    let isActive = label == active
                    // Icons joined the chips (re-ruling 2026-07-06 — real
                    // brand assets exist now, so the icon IS the identity;
                    // the old text-only rule predates them). "All" stays
                    // words-only: it has no app.
                    HStack(spacing: DS.Space.s1 + 2) {
                        if label != "All" {
                            BridgeIcon(name: label, size: 18)
                        }
                        Text(label).dsText(.label12)
                            .foregroundStyle(isActive ? DS.page : DS.textSecondary)
                    }
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 32)
                    .background(isActive ? DS.textPrimary : DS.gray100,
                                in: Capsule(style: .continuous))
                    .onTapGesture { DSHaptic.selection(); withAnimation(DS.Motion.standard) { onTap(label) } }
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
    }

    /// A day group as a native section: rounded sheet card, native swipes
    /// (To do / Doing), native scroll — no gesture fights.
    @ViewBuilder
    private func daySection(_ label: String, _ rows: [Thing]) -> some View {
        Section {
            // Rows dispatch by shape (shaped feeds); the swipe stays triage —
            // reads only, writes live in the sheet (ruling), Copy sheet-only.
            ForEach(rows) { thing in
                shapedListRow(thing)
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(label).dsText(.heading17).foregroundStyle(DS.textPrimary)
                Text("\(rows.count)").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .contentTransition(.numericText())
            }
            .textCase(nil)
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
                thing.mark = .done
                try? modelContext.save()
                DSHaptic.success()
                chrome.flash("Approved — sent to your gateway")
            }
        case .deny:
            thing.mark = .done
            try? modelContext.save()
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

/// A Feed row: kind glyph, title, tag, pin, time. Marks ride native swipes.
struct FeedRow: View {
    let thing: Thing

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            KindGlyph(kind: thing.kind, size: 32)
            Text(thing.title)
                .dsText(.body17)
                .foregroundStyle(thing.mark == .done ? DS.textTertiary : DS.textPrimary)
                .strikethrough(thing.mark == .done, color: DS.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The glyph carries the kind; the pill carries the project when
            // the thing has one (amendment: type pills died as redundant ink).
            if let project = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) {
                TagPill(project)
            }
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }

    static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}

/// The compact Feed treemap — 5 cells, areas "a a b c / a a d e", 140pt tall,

