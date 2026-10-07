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
    /// Add a calendar's two ways (prd §1166): the phone's, or one by link.
    @State private var calendarChoice = false


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
                            appsList
                        case .calendars:
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                verbRow("calendar.badge.plus", String(localized: "Add a calendar")) { add(.calendars) }
                                calendarsList
                                if calendarsEmpty { comesFrom(Self.calendarApps) }
                            }
                        case .cards:
                            cardsList
                        case .feeds:
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                verbRow("plus", String(localized: "Follow a feed")) { add(.feeds) }
                                kindList(feeds.filter { hit($0.name) }, empty: "Follow a feed and it lands here.") { feedRow($0) }
                                if feeds.isEmpty { comesFrom(Self.feedApps) }
                            }
                        case .newsletters:
                            newslettersList
                        case .people:
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                verbRow("person.badge.plus", String(localized: "Add a person")) { add(.people) }
                                if people == 0 { comesFrom(Self.peopleApps) } else { peopleList }
                            }
                        case .wallets:
                            walletsList
                        case .subscriptions:
                            // The verb leads, as on the Wallet's list (prd
                            // §1117), so an empty list is never a dead end
                            // (§1164): the tray opens on Popular.
                            VStack(alignment: .leading, spacing: DS.Space.s1) {
                                if query.isEmpty {
                                    DSDoorRow(icon: "plus", title: Text(SubscriptionWords.track)) { add(.subscriptions) }
                                }
                                kindList(SubscriptionsReading.shared.items.filter { hit($0.name) },
                                         empty: "Track a subscription and it lands here.") { subscriptionRow($0) }
                            }
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
        .confirmationDialog(Text("Add a calendar"), isPresented: $calendarChoice, titleVisibility: .visible) {
            Button("Your phone’s calendars") { route.openSetup(forOffer: "Calendar") }
            Button("Subscribe by link") { calendarAdd = true }
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
            calendarChoice = true
        // A card arrives through its app, so Add opens the catalogue.
        case .cards:
            route.present(.apps)
        // Each kind's own add tray, over Settings (prd §1143).
        case .feeds:         sheet = .followAdd
        case .newsletters:   sheet = .mailAdd
        case .people, .wallets: sheet = .walletFollow
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

    /// Eight counts, two across, A–Z, and THEY ARE THE FILTER (prd §1138;
    /// eight since prd §1166, user: "i wonder if 'wallets' should be one of
    /// the items in the card too … we could also have one for cards"): each
    /// figure and its whole word on one line, as Reminders' grid draws them,
    /// so nothing is shortened. Pressing one lists that kind below; the box
    /// never moves. The bar keeps the verbs.
    private var countsBox: some View {
        let counts: [(SettingsScope, Int, String)] = SettingsScope.kinds.map { kind in
            let n: Int = switch kind {
            case .apps: connectedApps.count
            case .calendars: phoneCalendars.count + CalendarSubscriptionStore.shared.calendars.count
            case .cards: connectedCards.count
            case .feeds: feeds.count
            case .newsletters: MailSubscriptionsReading.shared.items.count
            case .people: people
            case .subscriptions: SubscriptionsReading.shared.items.count
            case .wallets: WalletStore.shared.addresses.count
            case .new, .search: 0
            }
            return (kind, n, kind.label)
        }
        // A broken connection says so in its kind's WORD (the tiles' rule,
        // never a dot), so it shows from every other kind too.
        let troubled: Set<SettingsScope> = connectedApps.contains { $0.status == .attention } ? [.apps] : []
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .leading), count: 2),
                         alignment: .leading, spacing: DS.Space.s1) {
            ForEach(counts, id: \.0) { kind, n, label in
                DSCountTile(count: n, label: label, isOn: kind == scope && !casberiOpen,
                            wants: troubled.contains(kind), inline: true) {
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
                  subtitle: Text("Name, photo, data")) {
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

    /// APPS, THE FIRST LANDING (prd §1166, user: "it shouldn't just be
    /// start here, it should be all the apps"): Start here's steps while any
    /// is left, Casberi's own row once your name is in, then EVERY app under
    /// its category (categories A–Z, Other last; apps A–Z), yours wearing
    /// their state and the rest Add. Supersedes §1145's "only yours": this is
    /// where a first run sets up, so what you could add stands here too.
    @ViewBuilder
    private var appsList: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if query.isEmpty {
                if hasName { casberiRow }
                if !startHere.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("Start here").dsText(.heading20).foregroundStyle(DS.brandInk)
                        ForEach(startHere) { step in startRow(step) }
                    }
                }
            }
            let offers = BridgeCatalog.offers.filter {
                BridgeCatalog.category(of: $0) != HomeScope.markets && hit($0.name)
            }
            if offers.isEmpty {
                DSEmptyState(headline: DSProse.text("No apps"), words: Text("Nothing matches."),
                             scale: .list(rows: 3))
            } else {
                let other = String(localized: "Other")
                let byCategory = Dictionary(grouping: offers) { BridgeCatalog.category(of: $0) }
                let categories = byCategory.keys.sorted {
                    if ($0 == other) != ($1 == other) { return $1 == other }
                    return $0.localizedStandardCompare($1) == .orderedAscending
                }
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    if query.isEmpty {
                        Text("All apps").dsText(.heading20).foregroundStyle(DS.brandInk)
                    }
                    ForEach(categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text(category).dsText(.heading17).foregroundStyle(DS.textSecondary)
                            ForEach((byCategory[category] ?? []).sorted {
                                $0.name.localizedStandardCompare($1.name) == .orderedAscending
                            }, id: \.name) { offerRow($0.name) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Start here (prd §1166)

    /// The four first steps. Each stands until its own act is done, never
    /// dismissed and never on a timer (user: "i like the idea of leaving it
    /// there until a user adds it"), and doing one never takes another.
    enum StartStep: String, Identifiable { case name, calendar, wallet, subscription; var id: String { rawValue } }

    private var hasName: Bool { !(ProfileStore.shared.name ?? "").isEmpty }

    private var calendarsEmpty: Bool {
        phoneCalendars.isEmpty && CalendarSubscriptionStore.shared.calendars.isEmpty
    }

    private var startHere: [StartStep] {
        var steps: [StartStep] = []
        if !hasName { steps.append(.name) }
        if calendarsEmpty && !bridges.bridges.contains(where: { $0.name == "Calendar" && $0.status != .paused }) {
            steps.append(.calendar)
        }
        if WalletStore.shared.addresses.isEmpty { steps.append(.wallet) }
        if SubscriptionStore.shared.all.isEmpty && SubscriptionsReading.shared.items.isEmpty {
            steps.append(.subscription)
        }
        return steps
    }

    @ViewBuilder
    private func startRow(_ step: StartStep) -> some View {
        switch step {
        case .name:
            // Casberi's own page, under its mark: your name, your photo and
            // what the app reaches (user: "that should be the casberi icon").
            DSPushRow(title: Text("Add name, photo, preferences")) {
                withAnimation(DS.Motion.standard) { casberiOpen = true }
            } leading: { CasberiMark(size: DS.Face.row) }
        case .calendar:
            DSPushRow(title: Text("Add a calendar"), subtitle: Text("Your phone’s, or any by link")) {
                add(.calendars)
            } leading: { BridgeIcon(name: "Calendar", size: DS.Face.row) }
        case .wallet:
            DSPushRow(title: Text("Watch a wallet"), subtitle: Text("Any address or name, no keys")) {
                add(.wallets)
            } leading: { BridgeIcon(name: "Wallet", size: DS.Face.row) }
        case .subscription:
            DSPushRow(title: Text(SubscriptionWords.track), subtitle: Text("Netflix, iCloud+, free ones too")) {
                add(.subscriptions)
            } leading: { glyphLead(SubscriptionWords.planGlyph) }
        }
    }

    private func glyphLead(_ glyph: String) -> some View {
        Image(systemName: glyph)
            .dsGlyph(.body, weight: .regular)
            .foregroundStyle(DS.tint)
            .frame(width: DS.Face.row, height: DS.Face.row)
            .background(RoundedRectangle(cornerRadius: DS.Radius.appIcon(DS.Face.row), style: .continuous)
                .fill(DS.fillFaint))
    }

    /// A kind's own act, first in its list, as Subscriptions' Track leads.
    private func verbRow(_ glyph: String, _ title: String, action: @escaping () -> Void) -> some View {
        DSDoorRow(icon: glyph, title: Text(title)) { action() }
    }

    /// One catalogue app by name: yours wears its state and opens its page,
    /// one you could add says Add and opens the page its Connect stands on.
    @ViewBuilder
    private func offerRow(_ name: String) -> some View {
        if let app = bridges.bridges.first(where: { $0.name == name && $0.status != .paused }) {
            appRow(app)
        } else {
            DSPushRow(title: Text(verbatim: name), fact: Text("Add"), factTone: DS.tint) {
                route.openSetup(forOffer: name)
            } leading: {
                BridgeIcon(name: name, size: DS.Face.row)
            }
        }
    }

    /// Where an empty kind fills from: its apps, each one tap.
    private func comesFrom(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Comes from").dsText(.heading17).foregroundStyle(DS.textSecondary)
            ForEach(names.filter { n in BridgeCatalog.offers.contains { $0.name == n } }, id: \.self) { offerRow($0) }
        }
    }

    static let calendarApps = ["Calendar", "Cal.com", "Calendly"]
    static let feedApps = ["RSS", "Substack", "YouTube", "Podcasts"]
    static let mailApps = ["Gmail", "iCloud Mail"]
    static let peopleApps = ["Contacts", "Bluesky", "Instagram", "Telegram", "Threads", "TikTok", "X"]
    /// The card apps, each with the cards it reads (user: "Cards could show
    /// those cards tho").
    static let cardApps: [(app: String, cards: String)] = [
        ("Apple Wallet", "Apple Card, Apple Cash"),
        ("Gnosis Pay", "Gnosis Pay card"),
        ("MetaMask Card", "MetaMask Card"),
        ("ether.fi", "ether.fi Cash"),
    ]

    private var connectedCards: [String] {
        Self.cardApps.map(\.app).filter { name in
            bridges.bridges.contains { $0.name == name && $0.status != .paused }
        }
    }

    // MARK: - Cards, mail lists, wallets (prd §1166)

    /// The cards Casberi can read, by name, each saying the app that reads
    /// it; one you have wears its app's state.
    private var cardsList: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Cards Casberi can read").dsText(.heading17).foregroundStyle(DS.textSecondary)
            ForEach(Self.cardApps.filter { c in BridgeCatalog.offers.contains { $0.name == c.app } }, id: \.app) { card in
                let app = bridges.bridges.first { $0.name == card.app && $0.status != .paused }
                DSPushRow(title: Text(verbatim: card.cards), subtitle: Text(verbatim: card.app),
                          fact: Text(app.map { $0.statusLine } ?? String(localized: "Add")),
                          factTone: app == nil ? DS.tint
                                    : app?.status == .attention ? DS.attentionInk : DS.textTertiary) {
                    route.openSetup(forOffer: card.app)
                } leading: {
                    BridgeIcon(name: card.app, size: DS.Face.row)
                }
            }
        }
    }

    /// A list arrives through mail: with none connected, the mail apps;
    /// with one, Track over the lists.
    @ViewBuilder
    private var newslettersList: some View {
        let mailOn = bridges.bridges.contains { Self.mailApps.contains($0.name) && $0.status != .paused }
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if mailOn {
                verbRow("plus", String(localized: "Track a mail list")) { add(.newsletters) }
                kindList(MailSubscriptionsReading.shared.items.filter { hit($0.name) },
                         empty: "Lists that write to your mail land here.") { newsletterRow($0) }
            } else {
                Text("Connect your mail and the lists that write to you show here.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                comesFrom(Self.mailApps)
            }
        }
    }

    /// Watch a wallet, the wallets you watch, then every Wallet app, so the
    /// kind is the wallets' settings too (user: "Wallet is wallet settings
    /// or shows all the wallet stuff").
    private var walletsList: some View {
        let watched = WalletStore.shared.addresses.filter { hit($0.label) || hit($0.address) }
        let walletApps = BridgeCatalog.offers
            .filter { BridgeCatalog.category(of: $0) == CategoryFold.walletRoom }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return VStack(alignment: .leading, spacing: DS.Space.s4) {
            verbRow("eye", String(localized: "Watch a wallet")) { add(.wallets) }
            if !watched.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    ForEach(watched) { addr in
                        DSPushRow(title: Text(verbatim: addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label),
                                  subtitle: addr.label.isEmpty ? nil : Text(verbatim: WalletStore.shortAddress(addr.address))) {
                            route.openSetup(forOffer: CategoryFold.walletRoom)
                        } leading: {
                            WalletFace(address: addr.address, size: DS.Face.row, circular: true)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Wallet apps").dsText(.heading17).foregroundStyle(DS.textSecondary)
                ForEach(walletApps.filter { hit($0) }, id: \.self) { offerRow($0) }
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
                if !lists.isEmpty { kindSection("Mail lists") { ForEach(lists) { newsletterRow($0) } } }
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
    case apps, calendars, cards, feeds, newsletters, people, subscriptions, wallets, new, search

    var id: String { rawValue }

    /// The box's eight kinds, A–Z by their words (prd §1166).
    static let kinds: [SettingsScope] = [.apps, .calendars, .cards, .feeds, .newsletters,
                                         .people, .subscriptions, .wallets]

    static let verbs: Set<SettingsScope> = [.new, .search]
    /// What the floating bar holds: the verbs alone.
    static let bar: [SettingsScope] = [.new, .search]

    var label: String {
        switch self {
        case .apps:          return String(localized: "Apps")
        case .calendars:     return String(localized: "Calendars")
        case .cards:         return String(localized: "Cards")
        case .feeds:         return String(localized: "Feeds")
        // Whole everywhere since prd §1166 (user: "we going to say 'Subs'
        // everywhere?"): no shortened word on any surface.
        case .newsletters:   return String(localized: "Mail lists")
        case .people:        return String(localized: "People")
        case .subscriptions: return String(localized: "Subscriptions")
        case .wallets:       return String(localized: "Wallets")
        case .new:           return String(localized: "Add")
        case .search:        return String(localized: "Search")
        }
    }

    var summary: String {
        switch self {
        case .apps:          return String(localized: "Every app, by category")
        case .cards:         return String(localized: "The cards your card apps read")
        case .wallets:       return String(localized: "The wallets you watch, and their apps")
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
