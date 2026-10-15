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
    /// Handed on to a kind's home page (prd §1274), which a Catalyst sheet
    /// does not inherit (prd §872). Optional: not every host injects them.
    @Environment(FeedFilter.self) private var filter: FeedFilter?
    @Environment(PadDetailSelection.self) private var detail: PadDetailSelection?

    #if DEBUG
    /// `-connectTap` fires once a launch, not at every mount.
    @MainActor static var connectTapped = false
    #endif
    @State private var scope: SettingsScope = .apps
    /// Casberi's own options, opened in place from its pinned row — the way a
    /// Notes folder opens (prd §980): its name leads back.
    @State private var casberiOpen = false
    /// What Sources' Apps field filters (prd §1245), or a name the tray's
    /// search landed on (prd §1171): People narrowed to it, shown in a field
    /// you clear.
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
    /// The categories whose More was pressed: every app shown (prd §1253).
    @State private var openCategories: Set<String> = []
    /// The apps by category (the cards) or A–Z (one list under letters),
    /// remembered on this phone (prd §1253).
    @AppStorage("sources.appsAZ") private var appsAZ = false


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
                    // SOURCES FINDS ITS APPS (prd §1245, user: "there is no
                    // fab, notes, or search bar, so you can't search for
                    // apps"): risen as a sheet it covers the band's bar, so
                    // the Apps list keeps a field of its own. Elsewhere it
                    // is the name a tray search landed on (§1171), clearable.
                    if !casberiOpen, scope == .apps || !query.isEmpty {
                        DSSlabField(placeholder: String(localized: "Search"),
                                    text: $query, actionLabel: "",
                                    focus: $searchFocused,
                                    glyph: "magnifyingglass", clearable: true,
                                    size: .slab, submitLabel: .search, action: {})
                    }
                    if !casberiOpen, scope == .apps { orderWords }
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
                        // EACH KIND IS THE FEED'S CARD (prd §1265): its act
                        // first, then its rows in the Feed's anatomy.
                        case .calendars:
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                kindCard(String(localized: "Your calendars"), glyph: ScopeTileGlyph.calendars) {
                                    calendarsList
                                }
                                if calendarsEmpty { comesFrom(Self.calendarApps) }
                            }
                        case .cards:
                            cardsList
                        case .people:
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                if people == 0 { comesFrom(Self.peopleApps) } else { peopleList }
                            }
                        case .wallets:
                            walletsList
                        // ONE PLACE EACH (prd §1217): a subscription lives in
                        // the Wallet, a mail list in Life, a feed in Media; these
                        // counts open that page over Sources (prd §1274), never
                        // lists of their own.
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
            if !casberiOpen, scope == .apps, appsAZ { appsByLetter }
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
            } else if !casberiOpen, scope == .apps, appsAZ, query.isEmpty {
                LetterIndex(letters: appLetters.map(\.letter)) { letter in
                    proxy.scrollTo(Self.appLetterID(letter), anchor: .top)
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
                if let home = Self.home(of: s) { sheet = .home(home) } else { scope = s }
            }
            // `-connectTap "<Offer name>"` — the door an unconnected app's
            // Add row in Sources › Apps takes (`offerRow`: `setup`), for
            // verify-mac's connect gate. Never a direct push: a probe on a
            // route no person takes proves the screen, never the act
            // (8f4cb144, App Store 2.1(a), build 363). It says which door it
            // took, because Mac pushes where the phone raises.
            if let name = UserDefaults.standard.string(forKey: "connectTap"), !Self.connectTapped {
                Self.connectTapped = true
                scope = .apps
                let raises = BridgeRouter.destination(forOffer: name)?.raisedByConnect == true
                    && route.sheet == nil
                NSLog("[Casberi] connectTap| %@ connect form for %@",
                      raises ? "raising" : "pushing", name)
                setup(name)
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
        // One sheet at a time (prd §1238): inside Settings' sheet these push.
        .sheet(isPresented: Binding(get: { calendarAdd && route.sheet == nil },
                                    set: { calendarAdd = $0 })) {
            CalendarSubscribeSheet()
        }
        .navigationDestination(isPresented: Binding(get: { calendarAdd && route.sheet != nil },
                                                    set: { calendarAdd = $0 })) {
            CalendarSubscribeSheet().environment(\.dsInPane, true)
        }
        .confirmationDialog(Text("Add a calendar"), isPresented: $calendarChoice, titleVisibility: .visible) {
            Button("Your phone’s calendars") { setup("Calendar") }
            Button("Subscribe by link") { calendarAdd = true }
        }
        .modifier(DSOneSheet(route: $sheet, pushes: { _ in route.sheet != nil },
                             raised: { settingsSheet($0) },
                             pushed: { settingsSheet($0).environment(\.dsInPane, true) }))
        .modifier(DSOneSheet(route: $trackPick, pushes: { _ in route.sheet != nil },
                             raised: { trackTray($0) },
                             pushed: { trackTray($0).environment(\.dsInPane, true) }))
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

    /// A sheet's content with the environment a Catalyst sheet does not
    /// inherit (prd §872).
    private func settingsSheet(_ raised: SettingsSheet) -> some View {
        sheetContent(raised)
            .environment(chrome)
            .environment(bridges)
            .environment(route)
            .environment(filter)
            .environment(detail)
            .environment(\.modelContext, context)
    }

    @ViewBuilder
    private func trackTray(_ pick: TrackPick) -> some View {
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

    /// A follow landed from the Track tray: the list it joined opens here,
    /// over Sources (prd §1275), once the tray has closed. Work's Following
    /// has no page of its own outside Work, so Sources stays.
    private func landAfterTrack(_ room: Following.Room) {
        guard room != .work else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            sheet = .home(.follows)
        }
    }

    /// An app's own page, kept in Sources (prd §1275). An app with no page
    /// (Calendar, Photos, Reminders) runs its row's act here: `openSetup`'s
    /// fallback re-presented Sources on Apps, leaving the kind you were on.
    private func setup(_ name: String) {
        if BridgeRouter.destination(forOffer: name) == nil {
            openOffer(name)
        } else {
            route.openSetup(forOffer: name)
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

    /// The plus on a count (prd §1292): the verb its own page leads with,
    /// run from the box. Apps are added from the list under it and a card
    /// arrives through its app, so neither draws one; mail lists draw it
    /// once a mail app is connected, since the tray reads that mail.
    private func addVerb(_ kind: SettingsScope) -> String? {
        switch kind {
        case .apps, .cards:  nil
        case .calendars:     String(localized: "Add a calendar")
        case .feeds:         Following.Room.reading.verb
        case .newsletters:
            connectedApps.contains { Self.mailApps.contains($0.name) }
                ? String(localized: "Track a mail list") : nil
        case .people:        String(localized: "Follow someone")
        case .subscriptions: SubscriptionWords.track
        case .wallets:       String(localized: "Follow a wallet")
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
                let verb = addVerb(kind)
                DSCountTile(count: n, label: label, isOn: kind == scope && !casberiOpen,
                            wants: troubled.contains(kind), inline: true, widest: widest,
                            add: verb == nil ? nil : { add(kind) }, addLabel: verb) {
                    // A kind that lives in a room opens that room's page here
                    // (prd §1274): Back is Sources, the room's own pick stays.
                    if let home = Self.home(of: kind) {
                        DSHaptic.selection()
                        sheet = .home(home)
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
        case .home(let home):       ListHomePage(home: home)
        case .plan(let id):         SubscriptionSheet(id: id)
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
                        Text("Start here").dsText(.heading20).foregroundStyle(DS.headInk)
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
            } else if !appsAZ {
                let other = String(localized: "Other")
                let byCategory = Dictionary(grouping: offers) { BridgeCatalog.category(of: $0) }
                let categories = byCategory.keys.sorted {
                    if ($0 == other) != ($1 == other) { return $1 == other }
                    return $0.localizedStandardCompare($1) == .orderedAscending
                }
                // **EACH CATEGORY IS A CARD, AS THE FEED'S SECTIONS ARE (prd
                // §1253, user: "the section headers are too close to the list
                // ending above them"):** the Feed's panel and name (a pink
                // glyph, the name in the head ink), its row (the app over its
                // state, no chevron) and its More, which opens the rest in
                // place. "All apps" went: the cards say it. A search lists
                // every match.
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    ForEach(categories, id: \.self) { category in
                        let apps = (byCategory[category] ?? []).sorted {
                            $0.name.localizedStandardCompare($1.name) == .orderedAscending
                        }
                        let capped = query.isEmpty && !openCategories.contains(category)
                        let shown = capped ? Array(apps.prefix(Self.categoryFirstRows)) : apps
                        // The list row already stands in the room's column, so the card
                        // takes the rest of `rowInset`: rows land where the Feed's do.
                        SectionPanelCard(name: category, glyph: CategoryFold.glyph(for: category),
                                         inset: DSRoomChassis.rowInset - DSRoomChassis.inset) {
                            ForEach(shown, id: \.name) { offerRow($0.name, card: true) }
                            if shown.count < apps.count {
                                Button {
                                    DSHaptic.tap()
                                    withAnimation(DS.Motion.standard) { _ = openCategories.insert(category) }
                                } label: {
                                    DSPushRowLabel(title: Text("More from \(category)"), fact: nil,
                                                   tint: DS.tint, opens: false) {
                                        DSGlyphLead(glyph: "arrow.down", tint: DS.tint)
                                    }
                                    .frame(minHeight: DS.Hit.min)
                                }
                                .buttonStyle(RowPress())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - By category or A–Z (prd §1253)

    /// "By category A–Z", the Feed header's words (§1251): the order in the
    /// head ink, the other grey, a tap switches.
    private var orderWords: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            orderWord(Text("By category"), on: !appsAZ) { appsAZ = false }
            orderWord(Text(verbatim: "A–Z"), on: appsAZ) { appsAZ = true }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSRoomChassis.rowInset - DSRoomChassis.inset)
    }

    private func orderWord(_ word: Text, on: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            guard !on else { return }
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { pick() }
        } label: {
            word.dsText(.heading20).foregroundStyle(on ? DS.headInk : DS.textTertiary)
        }
        .buttonStyle(RowPress())
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// Every app the search admits, A–Z under its first letter; anything
    /// that does not start with a letter files under "#", last.
    private var appLetters: [(letter: String, names: [String])] {
        let names = BridgeCatalog.offers
            .filter { BridgeCatalog.category(of: $0) != HomeScope.markets && hit($0.name) }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let groups = Dictionary(grouping: names) { name -> String in
            let first = name.prefix(1).uppercased()
            return first.range(of: "^[A-Z]$", options: .regularExpression) != nil ? first : "#"
        }
        return groups.keys
            .sorted { ($0 == "#") != ($1 == "#") ? $1 == "#" : $0 < $1 }
            .map { ($0, groups[$0] ?? []) }
    }

    static func appLetterID(_ letter: String) -> String { "apps-letter-\(letter)" }

    /// The A–Z list as real rows, so the index can scroll to a letter.
    @ViewBuilder
    private var appsByLetter: some View {
        ForEach(appLetters, id: \.letter) { group in
            Section {
                ForEach(group.names, id: \.self) { name in
                    offerRow(name, card: true)
                        .listRowInsets(.init(top: DS.Space.s1, leading: DSRoomChassis.rowInset,
                                             bottom: DS.Space.s1, trailing: DSRoomChassis.rowInset))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                // The header's own insets, so the letter stands in the rows'
                // column and not the system's header inset past it.
                Text(verbatim: group.letter)
                    .dsText(.heading20)
                    .foregroundStyle(DS.headInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                         bottom: DS.Space.s1, trailing: DSRoomChassis.rowInset))
                    .id(Self.appLetterID(group.letter))
            }
            .listSectionSpacing(DS.Space.s2)
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
        // The demo is someone else's life: asking for YOUR name there reads
        // as a step of theirs left undone.
        if !hasName && !DemoMode.isActive { steps.append(.name) }
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
        // Bare and pink (prd §1272).
        Image(systemName: glyph)
            .dsGlyph(.body, weight: .regular)
            .foregroundStyle(DS.brandInk)
            .frame(width: DS.Mark.notice, height: DS.Mark.notice)
    }

    /// A kind on the Feed's card (prd §1265), in the room's column as the
    /// apps' cards stand (§1253).
    private func kindCard<Content: View>(_ name: String, glyph: String,
                                         @ViewBuilder _ content: () -> Content) -> some View {
        SectionPanelCard(name: name, glyph: glyph,
                         inset: DSRoomChassis.rowInset - DSRoomChassis.inset) { content() }
    }

    /// A kind's own act, first in its card (prd §1265): the pink glyph in
    /// the Feed's column, the verb in the page's ink, no chevron.
    private func cardVerbRow(_ glyph: String, _ title: String, action: @escaping () -> Void) -> some View {
        DSPushRow(title: Text(title), opens: false, action: action) {
            Image(systemName: glyph)
                .dsGlyph(.body, weight: .medium)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Face.seat, height: DS.Face.seat)
        }
    }

    /// One catalogue app by name: yours wears its state and opens its page,
    /// one you could add says Add and opens the page its Connect stands on.
    ///
    /// In a category's card (`card`, prd §1253) a row takes the Feed's
    /// anatomy: the 46pt mark, the name over its state, no chevron.
    @ViewBuilder
    private func offerRow(_ name: String, card: Bool = false) -> some View {
        if let app = bridges.bridges.first(where: { $0.name == name && $0.status != .paused }) {
            appRow(app, card: card)
        } else if card {
            DSPushRow(title: Text(verbatim: name), subtitle: Text("Add"),
                      subtitleTone: DS.tint, opens: false) {
                setup(name)
            } leading: {
                BridgeIcon(name: name, size: DS.Face.seat)
            }
        } else {
            DSPushRow(title: Text(verbatim: name), fact: Text("Add"), factTone: DS.tint) {
                setup(name)
            } leading: {
                BridgeIcon(name: name, size: DS.Mark.notice)
            }
        }
    }

    /// Rows a category's card shows before its More (prd §1253).
    static let categoryFirstRows = 6

    /// Where an empty kind fills from: its apps, each one tap.
    private func comesFrom(_ names: [String]) -> some View {
        // The Feed's card (prd §1272), its apps as the apps' card rows.
        kindCard(String(localized: "Comes from"), glyph: "square.grid.2x2") {
            ForEach(names.filter { n in BridgeCatalog.offers.contains { $0.name == n } }, id: \.self) {
                offerRow($0, card: true)
            }
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
        // "Cards", not "Cards Casberi can read": the card's name is one line.
        kindCard(String(localized: "Cards"), glyph: ScopeTileGlyph.cards) {
            ForEach(Self.cardApps.filter { c in BridgeCatalog.offers.contains { $0.name == c.app } }, id: \.app) { card in
                let app = bridges.bridges.first { $0.name == card.app && $0.status != .paused }
                // The Feed's row (prd §1265): the card over its app and
                // state, no chevron; Add in the tint.
                DSPushRow(title: Text(verbatim: card.cards),
                          subtitle: Text(verbatim: "\(card.app) · \(app.map { $0.statusLine } ?? String(localized: "Add"))"),
                          subtitleTone: app == nil ? DS.tint
                                        : app?.status == .attention ? DS.attentionInk : DS.textTertiary,
                          opens: false) {
                    setup(card.app)
                } leading: {
                    BridgeIcon(name: card.app, size: DS.Face.seat)
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
        return VStack(alignment: .leading, spacing: DS.Space.s6) {
            // The verb is the plus on the count (prd §1292), so a card with
            // no wallets is not drawn at all.
            if !watched.isEmpty {
            kindCard(String(localized: "Your wallets"), glyph: "wallet.bifold") {
                ForEach(watched) { addr in
                    DSPushRow(title: Text(verbatim: addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label),
                              subtitle: addr.label.isEmpty ? nil : Text(verbatim: WalletStore.shortAddress(addr.address)),
                              opens: false) {
                        route.openSetup(forOffer: CategoryFold.walletRoom)
                    } leading: {
                        // A face keeps its own ramp (face-ramp audit), centred in the
                        // Feed's 46pt column (prd §1170, §1265).
                        WalletFace(address: addr.address, size: DS.Face.row, circular: true)
                            .frame(width: DS.Face.seat, height: DS.Face.seat)
                    }
                }
            }
            }
            let apps = walletApps.filter { hit($0) }
            if !apps.isEmpty {
                kindCard(String(localized: "Wallet apps"), glyph: "square.grid.2x2") {
                    ForEach(apps, id: \.self) { offerRow($0, card: true) }
                }
            }
        }
    }

    /// One line, as iOS Settings draws a row (prd §1157): the name, then its
    /// state at the trailing edge before the chevron, so the 30pt icon is as
    /// tall as the row's words.
    @ViewBuilder
    private func appRow(_ app: BridgeApp, card: Bool = false) -> some View {
        let tone = app.status == .attention ? DS.attentionInk : DS.textTertiary
        // By the seat, as the catalogue's connected row opens (prd §1050f):
        // an offer with no setup page still has this one.
        let open = { route.openAccount(BridgeRouter.destination(forID: app.id)) }
        if card {
            DSPushRow(title: Text(verbatim: app.name), subtitle: Text(verbatim: app.statusLine),
                      subtitleTone: tone, opens: false, action: open) {
                BridgeIcon(name: app.name, size: DS.Face.seat)
            }
        } else {
            DSPushRow(title: Text(verbatim: app.name),
                      fact: Text(verbatim: app.statusLine), factTone: tone, action: open) {
                BridgeIcon(name: app.name, size: DS.Mark.notice)
            }
        }
    }

    // MARK: - People

    @ViewBuilder
    private var peopleList: some View {
        AddressesSection(query: query, scope: $peopleScope,
                         openPlan: { id in
                             // The Wallet's sheet for the plan, over Sources
                             // (prd §1275): its one home's page, not a copy.
                             sheet = .plan(id)
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
                            .frame(width: DS.Face.seat, height: DS.Face.seat)
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
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Face.seat, height: DS.Face.seat)
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
    /// count for it opens that page (prd §1274).
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
    /// A kind's home page, opened from its count (prd §1274).
    case home(ShellChrome.ListHome)
    /// A biller's plan, the Wallet's sheet for it (prd §1275).
    case plan(String)

    var id: String {
        switch self {
        case .subscriptionAdd:            "subscriptionAdd"
        case .mailAdd:                    "mailAdd"
        case .followAdd:                  "followAdd"
        case .walletFollow:               "walletFollow"
        case .home(let home):             "home:\(home)"
        case .plan(let id):               "plan:\(id)"
        }
    }
}

/// **A KIND'S HOME, OPENED FROM SOURCES (prd §1274, amends §1217 item 2).**
/// The Wallet's Subscriptions, Life's Subscriptions or Media's Following:
/// the room's own page pinned to that tile, pushed inside Sources' sheet so
/// Back is Sources, or risen with its own stack where Sources stands alone.
/// The list still lives in its room; this is that page, not a copy.
private struct ListHomePage: View {
    let home: ShellChrome.ListHome
    @Environment(\.dsInPane) private var inPane

    var body: some View {
        // The count it opened from carries the verb (prd §1292).
        if inPane {
            page.environment(\.dsAddOnCount, true)
        } else {
            NavigationStack {
                page.toolbar(.hidden, for: .navigationBar)
                    .environment(\.dsAddOnCount, true)
            }
            .environment(\.dsInSheetStack, true)
            .presentationDragIndicator(.visible)
            .presentationBackground(DS.themedPage)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch home {
        case .plans:
            FeedScreen(source: CategoryFold.walletRoom, isActive: true, inSheet: true,
                       pinnedWalletSection: .subscriptions)
        case .lists:
            FeedScreen(source: RoomAccounts.lifeRoom, isActive: true, inSheet: true,
                       pinnedSubscriptions: true)
        case .follows:
            FeedScreen(source: RoomAccounts.mediaRoom, isActive: true, inSheet: true,
                       pinnedSubscriptions: true)
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
