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

    @State private var scope: SettingsScope = .apps
    /// Casberi's own options, opened in place from its pinned row — the way a
    /// Notes folder opens (prd §980): its name leads back.
    @State private var casberiOpen = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var peopleScope = AddressScope(name: nil)
    @State private var people = 0
    @State private var calendarAdd = false
    @State private var unsubscribing: CalendarSubscriptionStore.Entry?


    var body: some View {
        // THE ROOM'S FRAME (prd §1136f): title, box and tiles as the same
        // three list rows every room draws, so they stand where Home's,
        // Notes' and Markets' do on every screen, by construction.
        List {
            YouHead(place: .settings)
                .dsRoomTitleListRow()
            Section {
                countsBox
                    .dsRoomLeadListRow()
            }
            Section {
                YouTilesRow(active: .sources)
                    .dsRoomTilesListRow()
            }
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    if !DSScopeDock<SettingsScope>.atBottom(sizeClass), !casberiOpen {
                        DSScopeTiles(sections: SettingsScope.allCases, active: scope,
                                     strip: true, verbs: SettingsScope.verbs) { pick($0) }
                    }
                    if casberiOpen {
                        casberiOptions
                    } else {
                        switch scope {
                        case .apps:
                            casberiRow
                            appsList
                        case .calendars:
                            kindList(CalendarSubscriptionStore.shared.calendars,
                                     empty: "Subscribe to a calendar and its dates show in Coming up.") { calendarRow($0) }
                        case .feeds:
                            kindList(feeds, empty: "Follow a feed and it lands here.") { feedRow($0) }
                        case .newsletters:
                            kindList(MailSubscriptionsReading.shared.items,
                                     empty: "Lists that write to your mail land here.") { newsletterRow($0) }
                        case .people:        peopleList
                        case .subscriptions:
                            kindList(SubscriptionsReading.shared.items,
                                     empty: "Track a subscription and it lands here.") { subscriptionRow($0) }
                        case .new:           EmptyView()
                        }
                    }
                }
                .listRowInsets(.init(top: DS.Space.s2, leading: DS.Space.s4,
                                     bottom: DS.Space.s4, trailing: DS.Space.s4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            // Room for the floating bar, as every room leaves it.
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .dsRoomList()
        .dsScopeDock(sections: casberiOpen || searchFocused ? [] : SettingsScope.allCases,
                     active: scope, verbs: SettingsScope.verbs,
                     // A place in You stands where a room does, down to the
                     // safe area, so the bar centres on the seat as Markets' does.
                     clearance: 0) { pick($0) }
        .dsAdaptiveContentWidth(.reading)
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(Text("Sources"))
        .toolbar(.hidden, for: .navigationBar)
        .task { await read() }
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
            add(scope)
            return
        }
        withAnimation(DS.Motion.standard) {
            scope = picked
            query = ""
        }
    }

    /// What + Add adds: the kind you're on (prd §1136 item 5), each through
    /// the door that already adds it. On Search, an app.
    private func add(_ kind: SettingsScope) {
        DSHaptic.selection()
        switch kind {
        case .apps, .new:
            route.present(.apps)
        case .calendars:
            calendarAdd = true
        case .feeds:
            // The room's follow list, through the landing's own door
            // (prd §1118), which a landing's tile reset honours.
            chrome.landingFollowing = .reading
            chrome.sourceRequest = RoomAccounts.readingRoom
        case .newsletters:
            // Day's Subscriptions tile, whose Track tray adds a list.
            chrome.dayScope = .subscriptions
            chrome.sourceRequest = RoomAccounts.dayRoom
        case .people:
            chrome.walletFollowPending = true
            chrome.sourceRequest = CategoryFold.walletRoom
        case .subscriptions:
            chrome.walletScope = nil
            chrome.walletSection = .subscriptions
            chrome.sourceRequest = CategoryFold.walletRoom
        }
    }

    private func read() async {
        await SubscriptionsReading.shared.refresh(context)
        MailSubscriptionsReading.shared.refresh(context)
        for room in Following.Room.allCases { FollowingReading.shared.refresh(room, context: context) }
        let everyone = ContactIndexSources.rebuild(context: context)
            .filter { !ContactIndexSources.isYours($0) }
        people = everyone.count
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
        // A–Z, the order the bar's tiles stand in (§995), so a count and its
        // filter sit in the same place (user: "those should be on the capsule").
        let counts: [(Int, String)] = [
            (connectedApps.count, String(localized: "Apps")),
            (CalendarSubscriptionStore.shared.calendars.count, String(localized: "Calendars")),
            (feeds.count, String(localized: "Feeds")),
            (MailSubscriptionsReading.shared.items.count, String(localized: "Mailing lists")),
            (people, String(localized: "People")),
            (SubscriptionsReading.shared.items.count, String(localized: "Subscriptions")),
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
    private var appsList: some View {
        let apps = connectedApps
        if apps.isEmpty {
            DSEmptyState(headline: DSProse.text("No apps yet"),
                         words: Text("Add an app and it lands here."),
                         scale: .list(rows: 3))
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

    private func empty(_ words: LocalizedStringKey) -> some View {
        DSEmptyState(headline: DSProse.text("Nothing yet"), words: Text(words), scale: .list(rows: 3))
    }

    /// One kind's whole list, or what would fill it (prd §769).
    @ViewBuilder
    private func kindList<Item: Identifiable, Row: View>(_ items: [Item], empty words: LocalizedStringKey,
                                                         @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        if items.isEmpty { empty(words) } else { rows(items, row: row) }
    }

    private func subscriptionRow(_ item: Subscriptions.Item) -> some View {
        DSPushRow(title: Text(verbatim: item.name),
                  subtitle: item.next.map { Text("Renews \($0.formatted(.dateTime.month(.abbreviated).day()))") }) {
            chrome.open(.plan(item.id))
        } leading: { BridgeIcon(name: item.name, size: DS.Face.row) }
    }

    private func feedRow(_ item: Following.Item) -> some View {
        DSPushRow(title: Text(verbatim: item.name), subtitle: Text(verbatim: item.seat)) {
            chrome.open(.followed(item.id, room(of: item)))
        } leading: { BridgeIcon(name: item.seat, size: DS.Face.row) }
    }

    private func newsletterRow(_ item: MailSubscriptions.Item) -> some View {
        DSPushRow(title: Text(verbatim: item.name), subtitle: item.address.map { Text(verbatim: $0) }) {
            chrome.open(.list(item.id))
        } leading: { BridgeIcon(name: item.name, size: DS.Face.row) }
    }

    private func calendarRow(_ entry: CalendarSubscriptionStore.Entry) -> some View {
        DSPushRow(title: Text(verbatim: entry.displayName),
                  subtitle: Text(calendarLine(entry)), opens: false) {
            unsubscribing = entry
        } leading: {
            Image(systemName: ScopeTileGlyph.calendars)
                .dsGlyph(.body, weight: .regular)
                .foregroundStyle(DS.textSecondary)
                .frame(width: DS.Face.row, height: DS.Face.row)
        }
    }

    private func rows<Item: Identifiable, Row: View>(_ items: [Item],
                                                     @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            ForEach(items) { row($0) }
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

/// Sources' own filters, on the floating bar (prd §1136h): the box's six
/// kinds A–Z, then Add — the bar scrolls (user: "it's life. it'll just have
/// to scroll"), Add pinned at its end.
/// No All: the box is the overview of all of it (user: "the sources screen
/// IS that list"). Add adds the kind you're on.
enum SettingsScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case apps, calendars, feeds, newsletters, people, subscriptions, new

    var id: String { rawValue }

    static let verbs: Set<SettingsScope> = [.new]

    var label: String {
        switch self {
        case .apps:          return String(localized: "Apps")
        case .calendars:     return String(localized: "Calendars")
        case .feeds:         return String(localized: "Feeds")
        // Short on the bar (user: "makes these say Lists and Subs"); the box
        // names them whole ("Mailing lists", "Subscriptions").
        case .newsletters:   return String(localized: "Lists")
        case .people:        return String(localized: "People")
        case .subscriptions: return String(localized: "Subs")
        case .new:           return String(localized: "Add")
        }
    }

    var summary: String {
        switch self {
        case .apps:          return String(localized: "Your apps, by category")
        case .calendars:     return String(localized: "The calendars you subscribe to")
        case .feeds:         return String(localized: "Sites, channels and repos you follow")
        case .newsletters:   return String(localized: "The lists that write to your mail")
        case .people:        return String(localized: "The people behind your accounts")
        case .subscriptions: return String(localized: "What you pay for")
        case .new:           return String(localized: "Add one of the kind you're on")
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
