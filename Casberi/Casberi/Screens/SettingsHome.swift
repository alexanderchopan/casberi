import SwiftUI
import SwiftData

/// SOURCES, THE MASTER LIST (prd §1136 items 3–6, user: "i do feel some
/// master list … is lacking"; "people can 'add' in these settings"; then "lets
/// call 'settings' 'sources' i think sources makes more sense now"). Its
/// place keeps `HomeScope.Place.settings` and the `.casberi` door, so every
/// deep link and ⌘, that opened Settings opens it.
///
/// Everything you've connected, each row opening its own settings page:
/// Casberi pinned first (its own options, as today's Settings), then your
/// apps, the people behind your accounts, and what sends you things. It
/// replaces the Apps and Addresses places. Like every place in You it is
/// title, box, You's four tiles, list — and its own filters ride the
/// floating bar at the bottom (§1136 item 2).
struct SettingsHome: View {
    @Environment(BridgeStore.self) private var bridges
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var scope: SettingsScope = .all
    /// Casberi's own options, opened in place from its pinned row — the way a
    /// Notes folder opens (prd §980): its name leads back.
    @State private var casberiOpen = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var peopleScope = AddressScope(name: nil)
    @State private var people = 0
    @State private var adding = false
    @State private var calendarAdd = false
    @State private var unsubscribing: CalendarSubscriptionStore.Entry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                YouHead(place: .settings)
                countsBox
                YouTilesRow(active: .sources)
                if !DSScopeDock<SettingsScope>.atBottom(sizeClass), !casberiOpen {
                    DSScopeTiles(sections: SettingsScope.allCases, active: scope,
                                 strip: true, verbs: [.new]) { pick($0) }
                }
                if casberiOpen {
                    casberiOptions
                } else {
                    switch scope {
                    case .all:           allList
                    case .apps:          appsList(grouped: true)
                    case .people:        peopleList
                    case .subscriptions: subsList
                    case .new:           EmptyView()
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
            // The You row stands where a feed's title stands (prd §1129).
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Space.s4)
        }
        .dsScopeDock(sections: casberiOpen || searchFocused ? [] : SettingsScope.allCases,
                     active: scope, verbs: [.new],
                     // A place in You stands where a room does, down to the
                     // safe area, so the bar centres on the seat as Markets' does.
                     clearance: 0) { pick($0) }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth(.reading)
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(Text("Sources"))
        .toolbar(.hidden, for: .navigationBar)
        .task { await read() }
        .confirmationDialog(Text("Add"), isPresented: $adding, titleVisibility: .hidden) {
            addChoices(for: scope)
        }
        .confirmationDialog(Text("Unsubscribe from this calendar?"),
                            isPresented: Binding(get: { unsubscribing != nil },
                                                 set: { if !$0 { unsubscribing = nil } }),
                            presenting: unsubscribing) { entry in
            Button("Unsubscribe", role: .destructive) {
                CalendarSubscriptionIngest.remove(entry.id, context: context)
            }
        } message: { entry in
            Text("Its events leave Coming up and Day.")
        }
        .sheet(isPresented: $calendarAdd) {
            CalendarSubscribeSheet()
        }
        .onChange(of: chrome.settingsPeopleQuery, initial: true) { _, asked in
            // The tray's search found a person (prd §1136 item 3): land on
            // People with their name in the field.
            guard let asked else { return }
            scope = .people
            casberiOpen = false
            query = asked
            chrome.settingsPeopleQuery = nil
        }
    }

    // MARK: - Acts

    private func pick(_ picked: SettingsScope) {
        if picked == .new {
            adding = true
            return
        }
        withAnimation(DS.Motion.standard) {
            scope = picked
            query = ""
        }
    }

    /// What + Add adds: the kind you're on (prd §1136 item 5).
    @ViewBuilder
    private func addChoices(for scope: SettingsScope) -> some View {
        if scope == .all || scope == .apps {
            Button("Add an app") { route.present(.apps) }
        }
        if scope == .all || scope == .people {
            Button("Follow a wallet") {
                chrome.walletFollowPending = true
                chrome.sourceRequest = CategoryFold.walletRoom
            }
        }
        if scope == .all || scope == .subscriptions {
            Button("Track a subscription") {
                chrome.walletScope = nil
                chrome.walletSection = .subscriptions
                chrome.sourceRequest = CategoryFold.walletRoom
            }
            Button("Follow a feed") {
                // The room's follow list, through the landing's own door
                // (prd §1118), which a landing's tile reset honours.
                chrome.landingFollowing = .reading
                chrome.sourceRequest = RoomAccounts.readingRoom
            }
            Button("Subscribe to a calendar") { calendarAdd = true }
        }
    }

    private func read() async {
        await SubscriptionsReading.shared.refresh(context)
        MailSubscriptionsReading.shared.refresh(context)
        for room in Following.Room.allCases { FollowingReading.shared.refresh(room, context: context) }
        people = ContactIndexSources.rebuild(context: context)
            .filter { !ContactIndexSources.isYours($0) }.count
        // A calendar subscribed elsewhere (or before this page existed) reads
        // its count fresh.
        if CalendarSubscriptionStore.shared.calendars.contains(where: { $0.lastRead == nil }) {
            await CalendarSubscriptionIngest.refresh(context: context)
        }
    }

    // MARK: - The box

    private var connectedApps: [BridgeApp] {
        bridges.bridges.filter { $0.status != .paused }
    }

    private var feeds: [Following.Item] {
        Following.Room.allCases.flatMap { FollowingReading.shared.items(for: $0) }
    }

    /// Six counts, no headline, not buttons (prd §1136 item 4): what you're
    /// connected to over what sends you things. Plain figures — the bar below
    /// filters, so a square that pressed would be a second door to it.
    private var countsBox: some View {
        let counts: [(Int, String)] = [
            (connectedApps.count, String(localized: "Apps")),
            (people, String(localized: "People")),
            (SubscriptionsReading.shared.items.count, String(localized: "Subscriptions")),
            (feeds.count, String(localized: "Feeds")),
            (MailSubscriptionsReading.shared.items.count, String(localized: "Newsletters")),
            (CalendarSubscriptionStore.shared.calendars.count, String(localized: "Calendars")),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3, alignment: .leading), count: 3),
                         alignment: .leading, spacing: DS.Space.s4) {
            ForEach(counts, id: \.1) { n, label in
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.formatted())
                        .dsText(.heading28)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                    Text(label)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
               maxHeight: DSRoomChassis.leadBox, alignment: .leading)
        .dsRoomHeadBlock()
    }

    // MARK: - All

    @ViewBuilder
    private var allList: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            casberiRow
            group(String(localized: "Apps"), count: connectedApps.count, to: .apps) {
                appsList(grouped: false, limit: 3)
            }
            group(String(localized: "People"), count: people, to: .people) {
                AddressesSection(query: "", scope: $peopleScope)
                    .frame(maxHeight: nil)
            }
            group(String(localized: "Subscriptions"),
                  count: SubscriptionsReading.shared.items.count + feeds.count
                    + MailSubscriptionsReading.shared.items.count
                    + CalendarSubscriptionStore.shared.calendars.count,
                  to: .subscriptions) {
                subsList
            }
        }
    }

    /// A group under All: its name, a door to its whole list, its rows.
    @ViewBuilder
    private func group<Rows: View>(_ title: String, count: Int, to target: SettingsScope,
                                   @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).dsText(.heading17).foregroundStyle(DS.brandInk)
                Spacer()
                if count > 0 {
                    Button { pick(target) } label: {
                        Text("All \(count)")
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("All \(title)"))
                }
            }
            rows()
        }
    }

    // MARK: - Casberi

    /// Casberi's own options, pinned first (prd §1136 item 3): every row
    /// below opens that connection's settings, and this is Casberi's.
    private var casberiRow: some View {
        DSPushRow(title: Text(verbatim: "Casberi"),
                  subtitle: Text("Settings · iCloud, notifications, privacy")) {
            withAnimation(DS.Motion.standard) { casberiOpen = true }
        } leading: {
            CasberiMark(size: DS.Face.row)
        }
    }

    @ViewBuilder
    private var casberiOptions: some View {
        DSPushRow(title: Text("Sources"), subtitle: Text("Back to everything you've connected")) {
            withAnimation(DS.Motion.standard) { casberiOpen = false }
        } leading: {
            Image(systemName: "chevron.left")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Face.row, height: DS.Face.row)
        }
        SettingsRows()
    }

    // MARK: - Apps

    /// Your apps under category headers (prd §1136 item 5), in the dock's
    /// order; each opens its own account page — its settings.
    @ViewBuilder
    private func appsList(grouped: Bool, limit: Int? = nil) -> some View {
        let apps = connectedApps
        if apps.isEmpty {
            DSEmptyState(headline: DSProse.text("No apps yet"),
                         words: Text("Add an app and it lands here."),
                         scale: .list(rows: 3))
        } else if !grouped {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(apps.prefix(limit ?? apps.count)) { appRow($0) }
            }
        } else {
            let order = chrome.chipOrder
            let byCategory = Dictionary(grouping: apps) { BridgeCatalog.category(forSource: $0.name) ?? String(localized: "Other") }
            let categories = byCategory.keys.sorted {
                let a = order.firstIndex(of: $0) ?? .max, b = order.firstIndex(of: $1) ?? .max
                return a == b ? $0 < $1 : a < b
            }
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                ForEach(categories, id: \.self) { category in
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(category).dsText(.heading17).foregroundStyle(DS.brandInk)
                        ForEach(byCategory[category] ?? []) { appRow($0) }
                    }
                }
            }
        }
    }

    private func appRow(_ app: BridgeApp) -> some View {
        DSPushRow(title: Text(verbatim: app.name),
                  subtitle: Text(verbatim: app.statusLine),
                  subtitleTone: app.status == .attention ? DS.attentionInk : DS.textTertiary) {
            route.openSetup(forOffer: app.name)
        } leading: {
            BridgeIcon(name: app.name, size: DS.Face.row)
        }
    }

    // MARK: - People

    @ViewBuilder
    private var peopleList: some View {
        DSSlabField(placeholder: String(localized: "Search people"),
                    text: $query, actionLabel: "",
                    focus: $searchFocused,
                    glyph: "magnifyingglass", clearable: true,
                    size: .slab, submitLabel: .search, action: {})
        AddressesSection(query: query, scope: $peopleScope)
    }

    // MARK: - Subscriptions, feeds, newsletters, calendars

    @ViewBuilder
    private var subsList: some View {
        let paid = SubscriptionsReading.shared.items
        let lists = MailSubscriptionsReading.shared.items
        let calendars = CalendarSubscriptionStore.shared.calendars
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if paid.isEmpty, feeds.isEmpty, lists.isEmpty, calendars.isEmpty {
                DSEmptyState(headline: DSProse.text("Nothing yet"),
                             words: Text("Track a subscription, follow a feed or subscribe to a calendar."),
                             scale: .list(rows: 3))
            }
            section(String(localized: "Subscriptions"), paid) { item in
                DSPushRow(title: Text(verbatim: item.name),
                          subtitle: item.next.map { Text("Renews \($0.formatted(.dateTime.month(.abbreviated).day()))") }) {
                    chrome.open(.plan(item.id))
                } leading: { BridgeIcon(name: item.name, size: DS.Face.row) }
            }
            section(String(localized: "Feeds"), feeds) { item in
                DSPushRow(title: Text(verbatim: item.name), subtitle: Text(verbatim: item.seat)) {
                    chrome.open(.followed(item.id, room(of: item)))
                } leading: { BridgeIcon(name: item.seat, size: DS.Face.row) }
            }
            section(String(localized: "Newsletters"), lists) { item in
                DSPushRow(title: Text(verbatim: item.name), subtitle: item.address.map { Text(verbatim: $0) }) {
                    chrome.open(.list(item.id))
                } leading: { BridgeIcon(name: item.name, size: DS.Face.row) }
            }
            section(String(localized: "Calendars"), calendars) { entry in
                DSPushRow(title: Text(verbatim: entry.displayName),
                          subtitle: Text(calendarLine(entry)), opens: false) {
                    unsubscribing = entry
                } leading: {
                    Image(systemName: "calendar")
                        .dsGlyph(.body, weight: .regular)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: DS.Face.row, height: DS.Face.row)
                }
            }
        }
    }

    @ViewBuilder
    private func section<Item: Identifiable, Row: View>(_ title: String, _ items: [Item],
                                                         @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).dsText(.heading17).foregroundStyle(DS.brandInk)
                ForEach(items) { row($0) }
            }
        }
    }

    private func room(of item: Following.Item) -> Following.Room {
        Following.Room.allCases.first { FollowingReading.shared.items(for: $0).contains { $0.id == item.id } } ?? .reading
    }

    private func calendarLine(_ entry: CalendarSubscriptionStore.Entry) -> String {
        guard let read = entry.lastRead else { return String(localized: "Not read yet") }
        let ahead = entry.ahead == 1
            ? String(localized: "1 event ahead")
            : String(localized: "\(entry.ahead) events ahead")
        return "\(ahead) · " + String(localized: "read \(read.formatted(.relative(presentation: .named)))")
    }
}

/// Settings' own filters, on the floating bar (prd §1136 item 5): All · Apps
/// · People · Subs · + Add. Add is a verb: it adds the kind you're on.
enum SettingsScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, apps, people, subscriptions, new

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:           return String(localized: "All")
        case .apps:          return String(localized: "Apps")
        case .people:        return String(localized: "People")
        case .subscriptions: return String(localized: "Subs")
        case .new:           return String(localized: "Add")
        }
    }

    var summary: String {
        switch self {
        case .all:           return String(localized: "Everything you've connected")
        case .apps:          return String(localized: "Your apps, by category")
        case .people:        return String(localized: "The people behind your accounts")
        case .subscriptions: return String(localized: "Subscriptions, feeds, newsletters and calendars")
        case .new:           return String(localized: "Add an app, a person or a subscription")
        }
    }
}

/// Subscribe to a calendar by its address (prd §1137).
struct CalendarSubscribeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var link = ""
    @State private var refused: String?
    @FocusState private var focused: Bool

    var body: some View {
        DSTray(title: String(localized: "Subscribe to a calendar"), height: 300) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSSlabField(placeholder: String(localized: "webcal:// or https:// link"),
                            text: $link, actionLabel: String(localized: "Subscribe"),
                            focus: $focused, glyph: "calendar", clearable: true,
                            size: .slab, submitLabel: .go) { subscribe() }
                if let refused {
                    Text(refused).dsText(.label12).foregroundStyle(DS.attentionInk)
                }
                DSFootnote(Text("Casberi reads the calendar itself, and its events show in Coming up and Day. Nothing is added to your Calendar app."))
            }
        }
        .onAppear { focused = true }
    }

    private func subscribe() {
        guard CalendarSubscriptionStore.normalized(link) != nil else {
            refused = String(localized: "That isn't a calendar link.")
            return
        }
        guard let entry = CalendarSubscriptionStore.shared.add(link) else {
            refused = String(localized: "You already subscribe to that calendar.")
            return
        }
        Task { @MainActor in await CalendarSubscriptionIngest.refresh(context: context, only: entry.id) }
        dismiss()
    }
}
