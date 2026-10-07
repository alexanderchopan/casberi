import SwiftUI
import SwiftData
import EventKit

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
    /// The bar's Search (prd §1138): a field over the kind you're on. People
    /// draws its own field always, as Addresses did.
    @State private var searchOpen = false
    @State private var peopleScope = AddressScope(name: nil)
    @State private var people = 0
    @State private var calendarAdd = false
    /// The phone's own calendars Casberi reads through Calendar (prd §1150),
    /// read on the screen's task, never in a body (§628).
    @State private var phoneCalendars: [PhoneCalendar] = []
    /// People's letters, for the A–Z strip on the trailing edge (prd §1153).
    @State private var peopleLetters: [String] = []
    /// WHAT A ROW OR ADD OPENS, OVER SETTINGS (prd §1143, user: "there is no
    /// way to get back"): a subscription, a list, a follow or an add tray
    /// rises here, so a swipe down is Settings again. They used to land in
    /// the Wallet, Day or Reading, and only the tray led back.
    @State private var sheet: SettingsSheet?
    @Environment(\.openURL) private var openURL
    @State private var unsubscribing: CalendarSubscriptionStore.Entry?


    var body: some View {
        // THE ROOM'S FRAME (prd §1136f): title, box and tiles as the same
        // three list rows every room draws, so they stand where Home's,
        // Notes' and Markets' do on every screen, by construction.
        ScrollViewReader { proxy in
        List {
            YouHead(place: .settings)
                .dsRoomTitleListRow()
            Section {
                countsBox
                    .dsRoomLeadListRow()
            }
            Section {
                YouTilesRow(active: .settings)
                    .dsRoomTilesListRow()
            }
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    if !DSScopeDock<SettingsScope>.atBottom(sizeClass), !casberiOpen {
                        DSScopeTiles(sections: SettingsScope.bar, active: scope,
                                     strip: true, verbs: SettingsScope.verbs) { pick($0) }
                    }
                    // ONE SEARCH OVER EVERY KIND (prd §1153, user: "build 3 and
                    // 4"): the bar's Search opens it on any kind, People's own
                    // field included, and what it finds is grouped by kind.
                    if !casberiOpen, searchOpen || !query.isEmpty {
                        DSSlabField(placeholder: String(localized: "Search"),
                                    text: $query, actionLabel: "",
                                    focus: $searchFocused,
                                    glyph: "magnifyingglass", clearable: true,
                                    size: .slab, submitLabel: .search, action: {})
                    }
                    if casberiOpen {
                        casberiOptions
                    } else if !query.isEmpty {
                        searchEverything
                    } else {
                        switch scope {
                        case .apps:
                            casberiRow
                            appsList
                        case .calendars:
                            calendarsList
                        case .feeds:
                            kindList(feeds.filter { hit($0.name) }, empty: "Follow a feed and it lands here.") { feedRow($0) }
                        case .newsletters:
                            kindList(MailSubscriptionsReading.shared.items.filter { hit($0.name) },
                                     empty: "Lists that write to your mail land here.") { newsletterRow($0) }
                        case .people:        peopleList
                        case .subscriptions:
                            kindList(SubscriptionsReading.shared.items.filter { hit($0.name) },
                                     empty: "Track a subscription and it lands here.") { subscriptionRow($0) }
                        case .new, .search:  EmptyView()
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
        // PEOPLE'S A–Z STRIP (prd §1153): Contacts' index on the trailing
        // edge, a letter tapped or slid to jumps the list to its header.
        // Above the floating bar, under the box: the list's own column.
        .overlay(alignment: .bottomTrailing) {
            if showsLetterIndex {
                LetterIndex(letters: peopleLetters) { letter in
                    proxy.scrollTo(AddressesSection.letterID(letter), anchor: .top)
                }
                .padding(.trailing, 2)
                .padding(.bottom, ShellMetrics.bottomInset + DS.Space.s4)
            }
        }
        }
        .dsScopeDock(sections: casberiOpen || searchFocused ? [] : SettingsScope.bar,
                     active: scope, verbs: SettingsScope.verbs,
                     // A place in You stands where a room does, down to the
                     // safe area, so the bar centres on the seat as Markets' does.
                     clearance: 0) { pick($0) }
        .dsAdaptiveContentWidth(.reading)
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(Text("Settings"))
        .toolbar(.hidden, for: .navigationBar)
        .task { await read() }
        #if DEBUG
        // `-accountDetail <case>` opens one of Casberi's own settings sheets
        // (verify-mac's account-detail gate, the screen sweep): those rows sit
        // behind the pinned Casberi row since prd §1136, so the hook opens it
        // first and `SettingsRows`' own hook raises the sheet.
        .onAppear {
            if UserDefaults.standard.string(forKey: "accountDetail") != nil { casberiOpen = true }
            // `-settingsScope <kind>` lands on one of the box's counts (prd
            // §1138) with no tap, for the store captures the Mac cannot tap.
            if let raw = UserDefaults.standard.string(forKey: "settingsScope"),
               let s = SettingsScope(rawValue: raw) { scope = s }
        }
        #endif
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
        .sheet(item: $sheet) { route in
            sheetContent(route)
                // A Catalyst sheet does not inherit the presenter's
                // environment (prd §872).
                .environment(chrome)
                .environment(bridges)
                .environment(self.route)
                .environment(\.modelContext, context)
        }
        // A search closed with nothing in it folds its field away.
        .onChange(of: searchFocused) { _, focused in
            if !focused, query.isEmpty { searchOpen = false }
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
        if picked == .search {
            withAnimation(DS.Motion.standard) { searchOpen = true }
            searchFocused = true
            return
        }
        withAnimation(DS.Motion.standard) {
            scope = picked
            query = ""
            searchOpen = false
        }
    }

    /// The bar's search, over the kind you're on.
    private func hit(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    /// What + Add adds: the kind you're on (prd §1136 item 5), each through
    /// the door that already adds it. On Search, an app.
    private func add(_ kind: SettingsScope) {
        DSHaptic.selection()
        switch kind {
        case .apps, .new, .search:
            route.present(.apps)
        case .calendars:
            calendarAdd = true
        // Each kind's own add tray, over Settings (prd §1143).
        case .feeds:         sheet = .followAdd
        case .newsletters:   sheet = .mailAdd
        case .people:        sheet = .walletFollow
        case .subscriptions: sheet = .subscriptionAdd
        }
    }

    private func read() async {
        phoneCalendars = PhoneCalendar.readable()
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

    /// Markets is a place in You, not an app (prd §1123, §1138).
    private var connectedApps: [BridgeApp] {
        bridges.bridges.filter {
            $0.status != .paused && BridgeCatalog.category(forSource: $0.name) != HomeScope.markets
        }
    }

    private var feeds: [Following.Item] {
        Following.Room.allCases.flatMap { FollowingReading.shared.items(for: $0) }
    }

    /// Six counts, no headline, and THEY ARE THE FILTER (prd §1138, amending
    /// §1136 item 4 and §1136h; user, 2026-10-06: "ok lets do it"): what
    /// you're connected to over what sends you things, A–Z. Pressing one
    /// lists that kind below; the box never moves. The bar keeps the verbs.
    private var countsBox: some View {
        let counts: [(SettingsScope, Int, String)] = [
            (.apps, connectedApps.count, String(localized: "Apps")),
            (.calendars, phoneCalendars.count + CalendarSubscriptionStore.shared.calendars.count,
             String(localized: "Calendars")),
            (.feeds, feeds.count, String(localized: "Feeds")),
            (.newsletters, MailSubscriptionsReading.shared.items.count, String(localized: "Mailing lists")),
            (.people, people, String(localized: "People")),
            (.subscriptions, SubscriptionsReading.shared.items.count, String(localized: "Subscriptions")),
        ]
        // A broken connection says so in its kind's WORD (the tiles' rule,
        // never a dot), so it shows from every other kind too.
        let troubled: Set<SettingsScope> = connectedApps.contains { $0.status == .attention } ? [.apps] : []
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .leading), count: 3),
                         alignment: .leading, spacing: DS.Space.s2) {
            ForEach(counts, id: \.0) { kind, n, label in
                DSCountTile(count: n, label: label, isOn: kind == scope && !casberiOpen,
                            wants: troubled.contains(kind)) {
                    if casberiOpen { casberiOpen = false }
                    pick(kind)
                }
            }
        }
        .padding(.horizontal, DS.Space.s2)
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
               maxHeight: DSRoomChassis.leadBox, alignment: .leading)
        .dsRoomHeadBlock()
    }

    // MARK: - Casberi

    /// Casberi's own options, pinned first (prd §1136 item 3): every row
    /// below opens that connection's settings, and this is Casberi's.
    private var casberiRow: some View {
        DSPushRow(title: Text(verbatim: "Casberi"),
                  subtitle: Text("iCloud, notifications, privacy")) {
            withAnimation(DS.Motion.standard) { casberiOpen = true }
        } leading: {
            CasberiMark(size: DS.Face.row)
        }
    }

    @ViewBuilder
    private var casberiOptions: some View {
        DSPushRow(title: Text("Settings"), subtitle: Text("Back to everything you've connected")) {
            withAnimation(DS.Motion.standard) { casberiOpen = false }
        } leading: {
            Image(systemName: "chevron.left")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Face.row, height: DS.Face.row)
        }
        SettingsRows()
    }

    // MARK: - Sheets over Settings (prd §1143)

    @ViewBuilder
    private func sheetContent(_ route: SettingsSheet) -> some View {
        switch route {
        case .subscription(let id): SubscriptionSheet(id: id, showsMoney: false)
        case .subscriptionAdd:      SubscriptionAddTray()
        case .mailList(let id):
            MailSubscriptionSheet(id: id) { mailID in
                // One sheet at a time (§872): the list closes, then the mail.
                sheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    if let url = URL(string: "casberi://thing/\(mailID.uuidString)") { openURL(url) }
                }
            }
        case .mailAdd:              MailSubscriptionAddTray()
        case .following(let id, let room): FollowingSheet(id: id, room: room)
        case .followAdd:            ReadingFindSheet(mode: .follow) { _ in }
        case .walletFollow:         WalletFollowSheet()
        }
    }

    // MARK: - Apps

    /// Your apps under category headers (prd §1136 item 5), A–Z, Other
    /// last; each opens its own account page — its settings. **Only yours
    /// (prd §1145, user: "yes remove those links"):** what you could add is
    /// Add's alone, so the "N more in <Category>" links are deleted.
    @ViewBuilder
    private var appsList: some View {
        let apps = connectedApps.filter { hit($0.name) }
        if apps.isEmpty {
            DSEmptyState(headline: DSProse.text(query.isEmpty ? "No apps yet" : "No apps"),
                         words: query.isEmpty ? Text("Add an app and it lands here.")
                                              : Text("Nothing you've added matches."),
                         scale: .list(rows: 3))
        } else {
            let other = String(localized: "Other")
            let byCategory = Dictionary(grouping: apps) { BridgeCatalog.category(forSource: $0.name) ?? other }
            let categories = byCategory.keys.sorted {
                if ($0 == other) != ($1 == other) { return $1 == other }
                return $0.localizedStandardCompare($1) == .orderedAscending
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

    /// One line, as iOS Settings draws a row (prd §1157): the name, then its
    /// state at the trailing edge before the chevron, so the 30pt icon is as
    /// tall as the row's words.
    private func appRow(_ app: BridgeApp) -> some View {
        DSPushRow(title: Text(verbatim: app.name),
                  fact: Text(verbatim: app.statusLine),
                  factTone: app.status == .attention ? DS.attentionInk : DS.textTertiary) {
            route.openSetup(forOffer: app.name)
        } leading: {
            BridgeIcon(name: app.name, size: DS.Face.row)
        }
    }

    // MARK: - People

    @ViewBuilder
    private var peopleList: some View {
        AddressesSection(query: query, scope: $peopleScope,
                         openPlan: { sheet = .subscription($0) },
                         onLetters: { peopleLetters = $0 })
    }

    private var showsLetterIndex: Bool {
        scope == .people && query.isEmpty && !casberiOpen && peopleLetters.count > 3
    }

    /// What one search finds, by kind, each kind only when it has a hit, in
    /// the box's order (prd §1153).
    @ViewBuilder
    private var searchEverything: some View {
        let apps = connectedApps.filter { hit($0.name) }
        let phone = phoneCalendars.filter { hit($0.title) }
        let subscribed = CalendarSubscriptionStore.shared.calendars.filter { hit($0.displayName) }
        let feedHits = feeds.filter { hit($0.name) }
        let lists = MailSubscriptionsReading.shared.items.filter { hit($0.name) }
        let people = ContactIndexSources.contacts.contains { hit($0.name) }
        let subs = SubscriptionsReading.shared.items.filter { hit($0.name) }
        if apps.isEmpty && phone.isEmpty && subscribed.isEmpty && feedHits.isEmpty
            && lists.isEmpty && !people && subs.isEmpty {
            empty("Nothing matches.")
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if !apps.isEmpty { kindSection("Apps") { ForEach(apps) { appRow($0) } } }
                if !phone.isEmpty || !subscribed.isEmpty {
                    kindSection("Calendars") {
                        ForEach(phone) { cal in
                            DSPushRow(title: Text(verbatim: cal.title), subtitle: Text(verbatim: cal.account)) {
                                route.openSetup(forOffer: "Calendar")
                            } leading: {
                                Circle().fill(cal.color).frame(width: 14, height: 14)
                                    .frame(width: DS.Face.row, height: DS.Face.row)
                            }
                        }
                        ForEach(subscribed) { calendarRow($0) }
                    }
                }
                if !feedHits.isEmpty { kindSection("Feeds") { ForEach(feedHits) { feedRow($0) } } }
                if !lists.isEmpty { kindSection("Mailing lists") { ForEach(lists) { newsletterRow($0) } } }
                if people {
                    kindSection("People") {
                        AddressesSection(query: query, scope: $peopleScope,
                                         openPlan: { sheet = .subscription($0) })
                    }
                }
                if !subs.isEmpty { kindSection("Subscriptions") { ForEach(subs) { subscriptionRow($0) } } }
            }
        }
    }

    private func kindSection<Rows: View>(_ title: LocalizedStringKey,
                                         @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(title).dsText(.heading17).foregroundStyle(DS.brandInk)
            rows()
        }
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
            sheet = .subscription(item.id)
        } leading: { BridgeIcon(name: item.name, size: DS.Face.row) }
    }

    private func feedRow(_ item: Following.Item) -> some View {
        DSPushRow(title: Text(verbatim: item.name), subtitle: Text(verbatim: item.seat)) {
            sheet = .following(item.id, room(of: item))
        } leading: { BridgeIcon(name: item.seat, size: DS.Face.row) }
    }

    private func newsletterRow(_ item: MailSubscriptions.Item) -> some View {
        DSPushRow(title: Text(verbatim: item.name), subtitle: item.address.map { Text(verbatim: $0) }) {
            sheet = .mailList(item.id)
        } leading: { BridgeIcon(name: item.name, size: DS.Face.row) }
    }

    /// EVERY CALENDAR CASBERI READS (prd §1150, user: "it should show every
    /// calendar read"): the phone's, by account, each opening Calendar's page
    /// in Casberi, then the ones subscribed by link, each with Unsubscribe.
    @ViewBuilder
    private var calendarsList: some View {
        let phone = phoneCalendars.filter { hit($0.title) }
        let subscribed = CalendarSubscriptionStore.shared.calendars.filter { hit($0.displayName) }
        if phone.isEmpty && subscribed.isEmpty {
            if query.isEmpty {
                empty("Connect Calendar or subscribe to one, and its dates show in Coming up.")
            } else {
                empty("Nothing matches.")
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(phone) { cal in
                    DSPushRow(title: Text(verbatim: cal.title), subtitle: Text(verbatim: cal.account)) {
                        route.openSetup(forOffer: "Calendar")
                    } leading: {
                        Circle().fill(cal.color)
                            .frame(width: 14, height: 14)
                            .frame(width: DS.Face.row, height: DS.Face.row)
                    }
                }
                ForEach(subscribed) { calendarRow($0) }
            }
        }
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

/// Settings' six kinds, picked by pressing their counts in the box, and the
/// bar's two verbs (prd §1138, amending §1136h's scrolling bar of kinds).
/// No All: the box is the overview of all of it (user: "the sources screen
/// IS that list"). Add adds the kind you're on; Search searches it.
enum SettingsScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case apps, calendars, feeds, newsletters, people, subscriptions, new, search

    var id: String { rawValue }

    static let verbs: Set<SettingsScope> = [.new, .search]
    /// What the floating bar holds: the verbs alone.
    static let bar: [SettingsScope] = [.new, .search]

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
        case .search:        return String(localized: "Search")
        }
    }

    var summary: String {
        switch self {
        case .apps:          return String(localized: "Your apps, by category")
        case .calendars:     return String(localized: "Every calendar Casberi reads")
        case .feeds:         return String(localized: "Sites, channels and repos you follow")
        case .newsletters:   return String(localized: "The lists that write to your mail")
        case .people:        return String(localized: "The people behind your accounts")
        case .subscriptions: return String(localized: "What you pay for")
        case .new:           return String(localized: "Add one of the kind you're on")
        case .search:        return String(localized: "Find one of the kind you're on")
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

/// What Settings raises over itself (prd §1143).
enum SettingsSheet: Identifiable, Hashable {
    case subscription(String), subscriptionAdd
    case mailList(String), mailAdd
    case following(String, Following.Room), followAdd
    case walletFollow

    var id: String {
        switch self {
        case .subscription(let id):       "subscription:\(id)"
        case .subscriptionAdd:            "subscriptionAdd"
        case .mailList(let id):           "mailList:\(id)"
        case .mailAdd:                    "mailAdd"
        case .following(let id, let room): "following:\(room.rawValue):\(id)"
        case .followAdd:                  "followAdd"
        case .walletFollow:               "walletFollow"
        }
    }
}

/// One of the phone's calendars Casberi reads (prd §1150): every event
/// calendar EventKit holds, as `ScheduleIngest` reads them all.
struct PhoneCalendar: Identifiable {
    let id: String
    let title: String
    let account: String
    let color: Color

    /// Empty without full Calendar access: nothing is read then.
    @MainActor
    static func readable() -> [PhoneCalendar] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return EKEventStore().calendars(for: .event)
            .map { cal in
                PhoneCalendar(id: cal.calendarIdentifier, title: cal.title,
                              account: cal.source?.title ?? "",
                              color: Color(cgColor: cal.cgColor))
            }
            .sorted {
                $0.account == $1.account
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.account.localizedStandardCompare($1.account) == .orderedAscending
            }
    }
}

/// Contacts' index (prd §1153): the letters a list files under, stacked on
/// its trailing edge; a tap or a slide jumps to the letter under the finger,
/// a tick each time it changes. "Not named yet" draws as a dot.
struct LetterIndex: View {
    let letters: [String]
    let jump: (String) -> Void
    @State private var current: String?

    private static let pitch: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(verbatim: letter == "…" ? "•" : letter)
                    .dsText(.dockCaption10)
                    .foregroundStyle(DS.tint)
                    .frame(width: 20, height: Self.pitch)
            }
        }
        .padding(.vertical, DS.Space.s1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let i = Int((value.location.y - DS.Space.s1) / Self.pitch)
                    let letter = letters[max(0, min(letters.count - 1, i))]
                    guard letter != current else { return }
                    current = letter
                    DSHaptic.selection()
                    jump(letter)
                }
                .onEnded { _ in current = nil }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Index"))
        .accessibilityAdjustableAction { direction in
            let i = letters.firstIndex(of: current ?? letters[0]) ?? 0
            let next = direction == .increment ? min(letters.count - 1, i + 1) : max(0, i - 1)
            current = letters[next]
            jump(letters[next])
        }
    }
}
