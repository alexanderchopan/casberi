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

    @State private var scope: SettingsScope = .apps
    /// Casberi's own options, opened in place from its pinned row — the way a
    /// Notes folder opens (prd §980): its name leads back.
    @State private var casberiOpen = false
    /// A name the tray's search landed on (prd §1171): People narrowed to it,
    /// shown in a field you clear. Settings has no search of its own; the
    /// tray's is the one search.
    @State private var query = ""
    @FocusState private var searchFocused: Bool
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var unsubscribing: CalendarSubscriptionStore.Entry?
    /// Add a calendar's two ways (prd §1166): the phone's, or one by link.
    @State private var calendarChoice = false
    /// The Track tray of an app that needs only a name (prd §1119), raised
    /// by a door that named it (prd §1234; the Apps screen's until then).
    @State private var trackPick: TrackPick?


    var body: some View {
        // THE ROOM'S FRAME (prd §1136f): title, box and tiles as the same
        // three list rows every room draws, so they stand where Home's,
        // Notes' and Markets' do on every screen, by construction.
        ScrollViewReader { proxy in
        List {
            DSRoomTitleRow(title: casberiOpen ? String(localized: "Settings") : String(localized: "Sources"))
                .dsRoomTitleListRow(inSheet: route.sheet != nil)
            Section {
                // Under the Settings tile the box is Casberi's own settings
                // (prd §1208c); under Sources, the kinds you connected.
                Group {
                    if casberiOpen { SettingsRows(style: .box) } else { countsBox }
                }
                .dsRoomLeadListRow()
            }
            // Risen as a sheet (prd §1208m) it stands on nothing: the Feed's
            // tiles belong to the Feed, and the pull closes it.
            if route.sheet == nil {
                Section {
                    YouTilesRow(active: .sources)
                        .dsRoomTilesListRow()
                }
            }
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    // The name a tray search landed on (prd §1171), clearable.
                    if !casberiOpen, !query.isEmpty {
                        DSSlabField(placeholder: String(localized: "Search"),
                                    text: $query, actionLabel: "",
                                    focus: $searchFocused,
                                    glyph: "magnifyingglass", clearable: true,
                                    size: .slab, submitLabel: .search, action: {})
                    }
                    if casberiOpen {
                        // The way back, in the content (prd §752): Sources.
                        DSDoorRow(icon: "chevron.left", title: Text("Sources")) {
                            withAnimation(DS.Motion.standard) { casberiOpen = false }
                        }
                        casberiOptions
                    } else {
                        // CASBERI LEADS SOURCES (prd §1231, user: "casberi
                        // becomes a source but is at the top above the
                        // apps"): its own options, where an app's settings
                        // are on the phone.
                        DSPushRow(title: Text(verbatim: "Casberi"),
                                  subtitle: Text("Settings, data and notifications")) {
                            withAnimation(DS.Motion.standard) { casberiOpen = true }
                        } leading: {
                            CasberiMark(size: DS.Mark.notice * 0.7)
                                .frame(width: DS.Mark.notice, height: DS.Mark.notice)
                        }
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
                        case .people:
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                verbRow("eye", String(localized: "Follow a wallet")) { add(.people) }
                                if people == 0 { comesFrom(Self.peopleApps) } else { peopleList }
                            }
                        case .wallets:
                            walletsList
                        // ONE PLACE EACH (prd §1217): a subscription lives in
                        // the Wallet, a mail list in Day, a feed in Media; these
                        // counts are doors to them, never lists of their own.
                        case .feeds, .newsletters, .subscriptions:
                            EmptyView()
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
               let s = SettingsScope(rawValue: raw) {
                if let home = Self.home(of: s) { route.closeSheet(); chrome.openHome(home) } else { scope = s }
            }
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
        .background {
            Color.clear.sheet(item: $trackPick) { pick in
                Group {
                    if pick.room == .reading {
                        ReadingFindSheet(onTracked: { landAfterTrack(pick.room) })
                    } else {
                        FollowTrackTray(room: pick.room, seat: pick.seat,
                                        onTracked: { landAfterTrack(pick.room) })
                    }
                }
                .environment(chrome)
                .environment(bridges)
                .environment(route)
                .environment(\.modelContext, context)
            }
        }
        // **A DOOR THAT ASKED FOR THE CATALOGUE LANDS HERE (prd §1234)**:
        // Sources, on Apps, and an app it named runs as its row would.
        .onChange(of: route.openSources, initial: true) { _, wanted in
            guard wanted else { return }
            route.openSources = false
            route.openCategory = nil
            route.openConnect = false
            withAnimation(DS.Motion.standard) {
                casberiOpen = false
                scope = .apps
                query = ""
            }
        }
        .onChange(of: route.openOffer, initial: true) { _, name in
            guard let name else { return }
            route.openOffer = nil
            withAnimation(DS.Motion.standard) {
                casberiOpen = false
                scope = .apps
            }
            openOffer(name)
        }
        .onChange(of: chrome.settingsPick, initial: true) { _, pick in
            guard let pick else { return }
            withAnimation(DS.Motion.standard) { casberiOpen = pick == .casberi }
            chrome.settingsPick = nil
        }
        .onChange(of: chrome.settingsLanding, initial: true) { _, landing in
            // The tray's search found something Settings holds (prd §1171):
            // a person lands on People with their name in the field, a kind
            // on its list, a feed, list or plan on its own sheet.
            guard let landing else { return }
            casberiOpen = false
            switch landing {
            case .person(let name):
                scope = .people
                query = name
            case .kind(let kind):
                scope = kind
                query = ""
            case .sheet(let raised):
                query = ""
                sheet = raised
            }
            chrome.settingsLanding = nil
        }
    }

    // MARK: - Acts

    private func pick(_ picked: SettingsScope) {
        withAnimation(DS.Motion.standard) {
            scope = picked
            query = ""
        }
    }

    /// The landed name, over the kind you're on.
    private func hit(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    /// An app that needs only a name, and the room its follows list in.
    struct TrackPick: Identifiable {
        let room: Following.Room
        let seat: String
        var id: String { seat }
    }

    /// An app named by a door (prd §1234): a connected one opens its page;
    /// one that needs only a name raises its Track tray; one with a page
    /// opens it; a one-tap app (Calendar, Photos, Reminders) fires the
    /// system's ask right here. Never back through `openSetup`, whose
    /// fallback for a pageless app is this.
    private func openOffer(_ name: String) {
        if let bridge = bridges.bridges.first(where: { $0.name == name }) {
            route.openAccount(BridgeRouter.destination(forID: bridge.id))
            return
        }
        guard let offer = BridgeCatalog.offers.first(where: { $0.name == name }) else { return }
        if let room = FollowingReading.trackRoom(forSeat: name) {
            trackPick = TrackPick(room: room, seat: name)
            return
        }
        if let destination = BridgeRouter.destination(forOffer: name) {
            route.openAccount(destination)
            return
        }
        BridgeConnect.connect(offer, store: bridges, context: context) { ok in
            if ok {
                DSHaptic.success()
                chrome.flash(BridgeConnect.landingMessage(offer), tone: .success)
            } else {
                chrome.flash("Couldn't connect \(offer.name).", tone: .failure)
            }
        }
    }

    /// A follow landed from the Track tray: leave for the room that lists it.
    private func landAfterTrack(_ room: Following.Room) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            route.closeSheet()
            route.path = []
            chrome.landOnFollowing(room)
        }
    }

    /// Each kind's own act, behind its first row (prd §1166): the bar's Add
    /// that also ran it is deleted, a second door to the same place.
    private func add(_ kind: SettingsScope) {
        DSHaptic.selection()
        switch kind {
        case .apps:
            withAnimation(DS.Motion.standard) { scope = .apps }
        case .calendars:
            calendarChoice = true
        // A card arrives through its app, so Add opens Apps, here (§1234).
        case .cards:
            withAnimation(DS.Motion.standard) { scope = .apps; query = "" }
        // Each kind's own add tray, over Settings (prd §1143).
        case .feeds:         sheet = .followAdd
        case .newsletters:   sheet = .mailAdd
        case .people, .wallets: sheet = .walletFollow
        case .subscriptions: sheet = .subscriptionAdd
        }
    }

    private func read() async {
        phoneCalendars = PhoneCalendar.readable(context)
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

    /// What the Following count's door lands on (Media's tile, prd §1230):
    /// sites and channels. Work's repos count in Work, not here.
    private var feeds: [Following.Item] {
        [Following.Room.reading, .media].flatMap { FollowingReading.shared.items(for: $0) }
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
            }
            return (kind, n, kind.label)
        }
        // A broken connection says so in its kind's WORD (the tiles' rule,
        // never a dot), so it shows from every other kind too.
        let troubled: Set<SettingsScope> = connectedApps.contains { $0.status == .attention } ? [.apps] : []
        let widest = counts.map(\.1).max()
        return DSCountGrid(items: counts.count) {
            ForEach(counts, id: \.0) { kind, n, label in
                DSCountTile(count: n, label: label, isOn: kind == scope && !casberiOpen,
                            wants: troubled.contains(kind), inline: true, widest: widest) {
                    if let home = Self.home(of: kind) {
                        DSHaptic.selection()
                        route.closeSheet()
                        chrome.openHome(home)
                        return
                    }
                    if casberiOpen { casberiOpen = false }
                    pick(kind)
                }
            }
        }
    }

    // MARK: - Casberi


    @ViewBuilder
    /// Under the Settings tile the settings are the box (prd §1208c), so the
    /// list is only the colophon; Sources is the tile beside it.
    private var casberiOptions: some View {
        SettingsRows(style: .colophon)
    }

    // MARK: - Sheets over Settings (prd §1143)

    @ViewBuilder
    private func sheetContent(_ route: SettingsSheet) -> some View {
        switch route {
        case .subscriptionAdd:      SubscriptionAddTray()
        case .mailAdd:              MailSubscriptionAddTray()
        case .followAdd:            ReadingFindSheet()
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
                if !startHere.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
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
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
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
            } leading: {
                // On a tile like every icon beside it (user: "the app tiles
                // and rows are too small"), Today's 38pt (prd §1170).
                CasberiMark(size: DS.Mark.notice * 0.7)
                    .frame(width: DS.Mark.notice, height: DS.Mark.notice)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.appIcon(DS.Mark.notice), style: .continuous)
                        .fill(DS.fillFaint))
            }
        case .calendar:
            DSPushRow(title: Text("Add a calendar"), subtitle: Text("Your phone’s, or any by link")) {
                add(.calendars)
            } leading: { BridgeIcon(name: "Calendar", size: DS.Mark.notice) }
        case .wallet:
            DSPushRow(title: Text("Follow a wallet"), subtitle: Text("Any address or name, no keys")) {
                add(.wallets)
            } leading: { BridgeIcon(name: "Wallet", size: DS.Mark.notice) }
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
            .frame(width: DS.Mark.notice, height: DS.Mark.notice)
            .background(RoundedRectangle(cornerRadius: DS.Radius.appIcon(DS.Mark.notice), style: .continuous)
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
                BridgeIcon(name: name, size: DS.Mark.notice)
            }
        }
    }

    /// Where an empty kind fills from: its apps, each one tap.
    private func comesFrom(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
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
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Cards Casberi can read").dsText(.heading17).foregroundStyle(DS.textSecondary)
            ForEach(Self.cardApps.filter { c in BridgeCatalog.offers.contains { $0.name == c.app } }, id: \.app) { card in
                let app = bridges.bridges.first { $0.name == card.app && $0.status != .paused }
                DSPushRow(title: Text(verbatim: card.cards), subtitle: Text(verbatim: card.app),
                          fact: Text(app.map { $0.statusLine } ?? String(localized: "Add")),
                          factTone: app == nil ? DS.tint
                                    : app?.status == .attention ? DS.attentionInk : DS.textTertiary) {
                    route.openSetup(forOffer: card.app)
                } leading: {
                    BridgeIcon(name: card.app, size: DS.Mark.notice)
                }
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
            verbRow("eye", String(localized: "Follow a wallet")) { add(.wallets) }
            if !watched.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(watched) { addr in
                        DSPushRow(title: Text(verbatim: addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label),
                                  subtitle: addr.label.isEmpty ? nil : Text(verbatim: WalletStore.shortAddress(addr.address))) {
                            route.openSetup(forOffer: CategoryFold.walletRoom)
                        } leading: {
                            // A face keeps its own ramp (face-ramp audit), centred in the
                            // rows' 38pt icon column (prd §1170).
                            WalletFace(address: addr.address, size: DS.Face.row, circular: true)
                                .frame(width: DS.Mark.notice, height: DS.Mark.notice)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
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
            // By the seat, as the catalogue's connected row opens (prd
            // §1050f): an offer with no setup page still has this one.
            route.openAccount(BridgeRouter.destination(forID: app.id))
        } leading: {
            BridgeIcon(name: app.name, size: DS.Mark.notice)
        }
    }

    // MARK: - People

    @ViewBuilder
    private var peopleList: some View {
        AddressesSection(query: query, scope: $peopleScope,
                         openPlan: { id in
                             // A plan's one home is the Wallet (prd §1217).
                             route.closeSheet()
                             chrome.open(.plan(id))
                         },
                         onLetters: { peopleLetters = $0 })
    }

    private var showsLetterIndex: Bool {
        scope == .people && query.isEmpty && !casberiOpen && peopleLetters.count > 3
    }

    // MARK: - Subscriptions, feeds, newsletters, calendars

    private func empty(_ words: LocalizedStringKey) -> some View {
        DSEmptyState(headline: DSProse.text("Nothing yet"), words: Text(words), scale: .list(rows: 3))
    }

    /// EVERY CALENDAR CASBERI READS (prd §1150, user: "it should show every
    /// calendar read"): the phone's, by account, as facts, then the ones
    /// subscribed by link, each with Unsubscribe.
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
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(phone) { cal in
                    // A fact, not a door: the phone's calendars are chosen
                    // in iOS, so the row draws no chevron (honesty rule).
                    DSPushRowLabel(title: Text(verbatim: cal.title), subtitle: Text(verbatim: cal.account),
                                   opens: false) {
                        Circle().fill(cal.color)
                            .frame(width: 14, height: 14)
                            .frame(width: DS.Mark.notice, height: DS.Mark.notice)
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
                .frame(width: DS.Mark.notice, height: DS.Mark.notice)
        }
    }

    private func rows<Item: Identifiable, Row: View>(_ items: [Item],
                                                     @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        // A row that leaves folds shut and the rest close the gap; one that
        // arrives opens its place (prd §1199). The kind's count rolls with it.
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(items) {
                row($0).transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                               removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.standard, value: items.map(\.id))
    }

    private func calendarLine(_ entry: CalendarSubscriptionStore.Entry) -> String {
        guard let read = entry.lastRead else { return String(localized: "Not read yet") }
        let ahead = entry.ahead == 1
            ? String(localized: "1 event ahead")
            : String(localized: "\(entry.ahead) events ahead")
        return "\(ahead) · " + String(localized: "read \(read.formatted(.relative(presentation: .named)))")
    }
}

/// Settings' eight kinds (prd §1166), picked by pressing their counts in the
/// box. No All: the box is the overview of all of it (user: "the sources
/// screen IS that list"). No bar since prd §1171: its one verb was Search,
/// and the tray's search finds every kind.
enum SettingsScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case apps, calendars, cards, feeds, newsletters, people, subscriptions, wallets

    var id: String { rawValue }

    /// The box's eight kinds, A–Z by their words (prd §1166).
    static let kinds: [SettingsScope] = [.apps, .calendars, .cards, .feeds, .newsletters,
                                         .people, .subscriptions, .wallets]

    var label: String {
        switch self {
        case .apps:          return String(localized: "Apps")
        case .calendars:     return String(localized: "Calendars")
        case .cards:         return String(localized: "Cards")
        case .feeds:         return String(localized: "Following")
        // Whole everywhere since prd §1166 (user: "we going to say 'Subs'
        // everywhere?"): no shortened word on any surface.
        case .newsletters:   return String(localized: "Mail lists")
        case .people:        return String(localized: "People")
        case .subscriptions: return String(localized: "Subscriptions")
        case .wallets:       return String(localized: "Wallets")
        }
    }

    var summary: String {
        switch self {
        case .apps:          return String(localized: "Every app, by category")
        case .cards:         return String(localized: "The cards your card apps read")
        case .wallets:       return String(localized: "The wallets you follow, and their apps")
        case .calendars:     return String(localized: "Every calendar Casberi reads")
        case .feeds:         return String(localized: "Sites, channels and repos you follow")
        case .newsletters:   return String(localized: "The lists that write to your mail")
        case .people:        return String(localized: "The people behind your accounts")
        case .subscriptions: return String(localized: "What renews, free or paid")
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
                DSFootnote(Text("Its events show in Coming up and Day — nothing is added to your Calendar app."))
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

/// Where the tray's search lands in Settings (prd §1171): a person on People
/// with their name in the field, a kind's list, or a row's own sheet.
extension SettingsHome {
    /// The one home of a kind that lives in a room (prd §1217): Sources'
    /// count for it is a door there.
    static func home(of kind: SettingsScope) -> ShellChrome.ListHome? {
        switch kind {
        case .subscriptions: .plans
        case .newsletters:   .lists
        case .feeds:         .follows
        default:             nil
        }
    }
}

enum SettingsLanding: Hashable {
    case person(String)
    case kind(SettingsScope)
    case sheet(SettingsSheet)
}

/// What Settings raises over itself (prd §1143).
enum SettingsSheet: Identifiable, Hashable {
    case subscriptionAdd, mailAdd, followAdd
    case walletFollow

    var id: String {
        switch self {
        case .subscriptionAdd:            "subscriptionAdd"
        case .mailAdd:                    "mailAdd"
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

    /// Empty without full Calendar access: nothing is read then. The demo
    /// reads its own events' calendars instead (`demo(_:)`).
    @MainActor
    static func readable(_ context: ModelContext) -> [PhoneCalendar] {
        if DemoMode.isActive { return demo(context) }
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

extension PhoneCalendar {
    /// The demo's calendars: the calendar each of its Calendar events was
    /// filed under (the tag `ScheduleIngest` writes), on one iCloud account,
    /// because the demo's person has no EventKit store to read (user: "in the
    /// demo it shows 0 calendars connected. that's gotta be wrong").
    @MainActor
    static func demo(_ context: ModelContext) -> [PhoneCalendar] {
        let source = "Calendar"
        let d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        let titles = ((try? context.fetch(d)) ?? []).filter { $0.isLive && ($0.sourceRef ?? "").hasPrefix("demo:cal:") }
            // The kind's tag ("Event") comes first; the calendar is added last.
            .compactMap(\.tags.last)
        let colors: [Color] = [.blue, .orange, .green, .purple, .red]
        return Array(Set(titles)).sorted().enumerated().map { i, title in
            PhoneCalendar(id: "demo:" + title, title: title, account: "iCloud", color: colors[i % colors.count])
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
