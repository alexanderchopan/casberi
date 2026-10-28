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
    /// **THE PANE'S LIBRARY BOX (prd §1407):** this instance draws the counts
    /// box alone, in the pane at rest beside Library, as a room's pane
    /// instance draws its box (§1403); the list column's instance draws no box.
    var boxOnly = false
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
    /// When this page mounted, for the box's arrival (prd §1379).
    @State private var waveAt = Date.timeIntervalSinceReferenceDate
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
    /// Add a calendar's two ways (prd §1166): the phone's, or one by link.
    @State private var calendarChoice = false
    /// The Track tray of an app that needs only a name (prd §1119), raised
    /// by a door that named it (prd §1234; the Apps screen's until then).
    @State private var trackPick: TrackPick?
    /// The folder sprung open over the page (prd §1316).
    @State private var openFolder: String?
    /// The category a door named (`route.openCategory`, prd §1300): its
    /// folder springs open once the page has risen, then lets go.
    @State private var landCategory: String?
    /// Bumped when a person is kept by hand, so People's list reads again.
    @State private var peopleRevision = 0
    /// **AN ADD SHOWS WHAT IT ADDED (prd §1588).** The kind a tray or sheet
    /// adds to, and its count when it rose: once it closes, every reading is
    /// read again, and a count that grew lands its list.
    @State private var adding: (kind: SettingsScope, before: Int)?


    /// Casberi's folder: a card of tiles over the page on the phone (§1321),
    /// a list in the pane beside Library where there is one (prd §1405).
    private func openCasberiFolder() {
        #if DEBUG
        NSLog("[Casberi] casberiFolder| split=%d path=%d sheet=%d place=%@ hosts=%d",
              route.accountsSplit ? 1 : 0, route.path.count, route.sheet == nil ? 0 : 1,
              route.shownPlace.map { "\($0)" } ?? "nil", route.paneHostsPushes ? 1 : 0)
        #endif
        if route.paneHostsPushes {
            // Once: a second door while the folder, or a page from it, is up
            // would replace the pane's stack with the folder again.
            guard !route.accountsPane.contains(.settingsFolder) else { return }
            route.fromAccountsList { route.push(.settingsFolder) }
        } else {
            withAnimation(DS.Motion.folder) { casberiOpen = true }
        }
    }

    var body: some View {
        // THE ROOM'S FRAME (prd §1136f): title, box and tiles as the same
        // three list rows every room draws, so they stand where Home's,
        // Notes' and Markets' do on every screen, by construction.
        ScrollViewReader { proxy in
        List {
            // THE TITLE IS THE WAY BACK (prd §1312): Casberi's settings
            // open inside Sources, so the title says both, "Sources ·
            // Settings", and "Sources" presses back, as the category's word
            // does over an app's pick (§1262). The "‹ Sources" row it replaces
            // stood in the content because §752 kept the top clear.
            // LIBRARY IS A TAB (prd §1327 items 2, 5): its name alone, as
            // every tab's page reads; the bar says where the others are.
            if !boxOnly {
                DSRoomTitleRow(title: String(localized: "Library"))
                    .demoTagOnTitle()
                    .dsRoomTitleListRow(inSheet: route.sheet != nil)
            }
            Section {
                // The kinds you connected; Casberi's own settings are its
                // folder's tiles since prd §1321, never the box.
                Group {
                    if startsInBox { startBox.transition(.opacity) }
                    else { countsBox.transition(.opacity) }
                }
                // Your first add turns the four ways in into the counts, a
                // crossfade, never a cut (prd §1588).
                .animation(reduceMotion ? nil : DS.Motion.standard, value: startsInBox)
                .dsRoomLeadListRow()
            }
            if !boxOnly {
            // The places' row is gone (prd §1327 item 1): they are tabs.
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    // SOURCES FINDS ITS APPS (prd §1245, user: "there is no
                    // fab, notes, or search bar, so you can't search for
                    // apps"): risen as a sheet it covers the band's bar, so
                    // the Apps list keeps a field of its own. Elsewhere it
                    // is the name a tray search landed on (§1171), clearable.
                    // On the phone Sources is a page under the band (prd
                    // §1321), whose search finds every app: the field stays
                    // only for a name a search landed on.
                    if !casberiOpen, (scope == .apps && !Self.bandSearches) || !query.isEmpty {
                        DSSlabField(placeholder: String(localized: "Search"),
                                    text: $query, actionLabel: "",
                                    focus: $searchFocused,
                                    glyph: "magnifyingglass", clearable: true,
                                    size: .slab, submitLabel: .search, action: {})
                    }
                    Group {
                        switch scope {
                        case .apps:
                            // THE LIBRARY (prd §1316): every category a
                            // folder, Casberi's own settings the first slot
                            // (it leads Sources, §1231, and Apps only, §1307).
                            // The field focused or holding words lists every
                            // app A–Z instead, as the App Library's does.
                            if appsSearching {
                                appsList
                            } else {
                                SourcesLibrary(folders: libraryFolders, has: isYours,
                                               open: { category in
                                                   withAnimation(DS.Motion.folder) { openFolder = category }
                                               },
                                               openCasberi: { openCasberiFolder() })
                                .padding(.horizontal, DSRoomChassis.rowInset - DSRoomChassis.inset - DS.Space.s1)
                            }
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
                        // the Wallet, a mail list in Life, a feed in Media. Under
                        // the box is the same list drawn again, its rows and
                        // their sheets, never a copy of what it holds (§1317).
                        // No mail app, no lists and no plus: where they come
                        // from, one tap each (prd §1588).
                        case .newsletters where !hasMailApp:
                            comesFrom(Self.mailApps)
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
            if !casberiOpen, scope == .apps, appsSearching { appsByLetter }
            // Following, Mail lists, Subscriptions: a cell per row (§1317),
            // on panels as wide as Sources' own cards and box (§1320).
            kindLists
                .environment(\.feedSectionPanelInset, DS.Space.s4)
            // Room for the floating bar, as every room leaves it.
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        // The page's wave (prd §1379): the box arrives with the page and
        // stands at rest when scrolled back to, as a feed page's does.
        .environment(\.feedWaveAt, waveAt)
        .dsRoomList()
        .onChange(of: landCategory) { _, category in
            guard let category else { return }
            #if DEBUG
            NSLog("[Casberi] sourcesCategory: %@", category)
            #endif
            Task { @MainActor in
                // After the sheet has risen, so the spring is seen.
                try? await Task.sleep(for: .milliseconds(550))
                withAnimation(DS.Motion.folder) { openFolder = category }
                landCategory = nil
            }
        }
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
            } else if !casberiOpen, scope == .apps, appsSearching, query.isEmpty {
                LetterIndex(letters: appLetters.map(\.letter)) { letter in
                    proxy.scrollTo(Self.appLetterID(letter), anchor: .top)
                }
                .padding(.trailing, 2)
                .padding(.bottom, ShellMetrics.bottomInset + DS.Space.s4)
            }
        }
        // Casberi's folder springs open on its settings, each a tile like an
        // app (prd §1321).
        .overlay {
            if casberiOpen, !boxOnly {
                SourcesSettingsFolder(close: { withAnimation(DS.Motion.folder) { casberiOpen = false } })
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        // A folder springs open over the page (prd §1316).
        .overlay {
            if let category = openFolder, !casberiOpen, !boxOnly, scope == .apps,
               let folder = libraryFolders.first(where: { $0.category == category }) {
                SourcesOpenFolder(folder: folder, has: isYours,
                                  open: { openFromFolder($0) },
                                  settings: { name in yours(name).map { app in { openPage(app) } } },
                                  close: { withAnimation(DS.Motion.folder) { openFolder = nil } },
                                  // The Notes folder leads with the Notes
                                  // page, pushed beside Library (prd §1347).
                                  notesPage: category == BridgeCatalog.notesCategory
                                      ? { route.push(.notes) } : nil)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
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
            // A beat after mount: the pane's split is written by the shell
            // after its first layout, and the folder goes where the split is.
            if UserDefaults.standard.string(forKey: "accountDetail") != nil {
                Task { @MainActor in
                    // The split is written after the shell's first layout;
                    // wait for it, bounded, so the folder goes where it would
                    // on a tap. A narrow window never splits and falls through.
                    for _ in 0..<30 where !route.paneHostsPushes {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    openCasberiFolder()
                }
            }
            // `-settingsScope <kind>` lands on one of the box's counts (prd
            // §1138) with no tap, for the store captures the Mac cannot tap.
            if let raw = UserDefaults.standard.string(forKey: "settingsScope"),
               let s = SettingsScope(rawValue: raw) {
                scope = s
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
        // One sheet at a time (prd §1238): inside Settings' sheet these push.
        .sheet(isPresented: Binding(get: { calendarAdd && route.sheet == nil },
                                    set: { calendarAdd = $0 })) {
            CalendarSubscribeSheet()
        }
        .navigationDestination(isPresented: Binding(get: { calendarAdd && route.sheet != nil },
                                                    set: { calendarAdd = $0 })) {
            CalendarSubscribeSheet().environment(\.dsInPane, true).dsSheetStep()
        }
        .confirmationDialog(Text("Add a calendar"), isPresented: $calendarChoice, titleVisibility: .visible) {
            Button("Your phone’s calendars") { setup("Calendar") }
            Button("Subscribe by link") { calendarAdd = true }
        }
        // Every add's way in, and its close: the readings read again and a
        // count that grew lands its list (prd §1588).
        .onChange(of: sheet) { was, now in
            if was == nil, let now, let kind = Self.adds(now) { adding = (kind, count(kind)) }
            if was != nil, now == nil, adding != nil { Task { await landAdded() } }
        }
        .onChange(of: trackPick?.id) { was, now in
            if was == nil, now != nil { adding = (.feeds, count(.feeds)) }
            if was != nil, now == nil { Task { await landAdded() } }
        }
        .onChange(of: calendarAdd) { was, now in
            if now { adding = (.calendars, count(.calendars)) }
            if was, !now { Task { await landAdded() } }
        }
        // An app connected from here (Calendar's one tap, a folder's app)
        // changes what the counts read.
        .onChange(of: bridges.bridges.count) { _, _ in if !boxOnly { Task { await read() } } }
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
            // A door that named a category (Social's +, the agent's empty
            // chat) lands on its card, every app in it shown (prd §1300).
            let category = route.openCategory
            route.openSources = false
            route.openCategory = nil
            route.openConnect = false
            withAnimation(DS.Motion.standard) {
                casberiOpen = false
                scope = .apps
                query = ""
            }
            landCategory = category
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
            guard let pick, !boxOnly else { return }
            // Every door to the folder takes the same one (prd §1405): the
            // pane where Library has one, the card over the page elsewhere.
            if pick == .casberi { openCasberiFolder() }
            else { withAnimation(DS.Motion.standard) { casberiOpen = false } }
            chrome.settingsPick = nil
        }
        .onChange(of: chrome.settingsLanding, initial: true) { _, landing in
            if boxOnly { return }
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
        raisedContent(raised)
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
            // A connected app's page is a page (prd §1321 item 2).
            route.pushBridge(BridgeRouter.destination(forID: bridge.id))
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
                // The success flash carries the one buzz (prd §1587).
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
            withAnimation(DS.Motion.standard) { scope = .feeds; query = "" }
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
        // ...its folder sprung open: the card apps live in the Wallet's (prd §1588).
        case .cards:
            withAnimation(DS.Motion.standard) { casberiOpen = false; scope = .apps; query = "" }
            landCategory = Self.cardApps.lazy.compactMap { c in BridgeCatalog.offers.first { $0.name == c.app } }
                .first.map(BridgeCatalog.category(of:))
        // Each kind's own add tray, over Settings (prd §1143).
        // Following and People list their apps (`addMenu`), as the Feed's
        // Media and Social do (prd §1300); People opened the Wallet's tray.
        case .feeds, .people: break
        case .newsletters:   sheet = .mailAdd
        case .wallets:       sheet = .walletFollow
        case .subscriptions: sheet = .subscriptionAdd
        }
    }

    /// THE SAME PLUS AS THE FEED'S (prd §1300, user: "lets also make sure we
    /// are consistent in the plus menus on the sources page … rn if you click
    /// on the plus for people it opens wallet"): Following lists Media's
    /// follow-by-name apps, as Media's + does. People is the one list of
    /// everyone (user: "people is also contacts", "it should be a master
    /// contacts list"), so its plus adds a person: Contacts, or New contact.
    private func addMenu(_ kind: SettingsScope) -> [SectionAdd] {
        switch kind {
        case .feeds:
            return FollowByName.doors(in: RoomAccounts.mediaRoom).map { door in
                SectionAdd(label: door.app, detail: door.what, app: door.app) { followByName(door.app) }
            }
        case .people:
            // A MASTER LIST (user: "people's i guess should add contacts and
            // a contact entry if they don't want to import"): import the
            // address book, or keep one person by hand.
            return [
                SectionAdd(label: "Contacts", detail: String(localized: "Import your address book"),
                           app: "Contacts") {
                    DSHaptic.selection()
                    setup("Contacts")
                },
                SectionAdd(label: String(localized: "New contact"),
                           detail: String(localized: "A name and an email or address"),
                           glyph: "person.crop.circle.badge.plus") {
                    DSHaptic.selection()
                    sheet = .newContact
                },
            ]
        default:
            return []
        }
    }

    /// One row of a count's plus (prd §1300): `FollowByName.landing`, the
    /// Feed's own rule, through the trays Sources raises. Following's plus
    /// lists Media's apps, so a Social follow never lands here; were one to,
    /// it opens its app's page (prd §1309).
    private func followByName(_ app: String) {
        DSHaptic.selection()
        let connected = connectedApps.contains { $0.name == app }
        switch FollowByName.landing(for: app) {
        case .reading:         trackPick = TrackPick(room: .reading, seat: app)
        case .calendar:        calendarAdd = true
        case .track(let room): trackPick = TrackPick(room: room, seat: app)
        case .github:
            if connected { trackPick = TrackPick(room: .work, seat: app) } else { setup(app) }
        case .mail:
            if connected { sheet = .mailAdd } else { setup(app) }
        case .page, .socialFollow: setup(app)
        }
    }

    /// The plus on a count (prd §1292): the verb its own page leads with,
    /// run from the box. Apps are added from the list under it and a card
    /// arrives through its app, so neither draws one; mail lists draw it
    /// once a mail app is connected, since the tray reads that mail.
    private func addVerb(_ kind: SettingsScope) -> String? {
        switch kind {
        // Apps' list below IS the catalogue, so its + would land where you
        // stand; a card has an add, the app it arrives through (prd §1388).
        case .apps:          nil
        case .cards:         String(localized: "Connect a card")
        case .calendars:     String(localized: "Add a calendar")
        case .feeds:         String(localized: "Follow something")
        case .newsletters:
            connectedApps.contains { Self.mailApps.contains($0.name) }
                ? String(localized: "Track a mail list") : nil
        case .people:        String(localized: "Add a contact")
        case .subscriptions: SubscriptionWords.track
        case .wallets:       String(localized: "Follow an account")
        }
    }

    private func read() async {
        // The readings the box's kinds keep, for Library and the Feed
        // (`FirstRun`, prd §1365); read again after every add (§1588).
        await FirstRun.shared.refresh(context)
        withAnimation(DS.Motion.standard) {
            phoneCalendars = FirstRun.shared.phoneCalendars
            people = FirstRun.shared.people
        }
        // A calendar subscribed elsewhere (or before this page existed) reads
        // its count fresh.
        if CalendarSubscriptionStore.shared.calendars.contains(where: { $0.lastRead == nil }) {
            await CalendarSubscriptionIngest.refresh(context: context)
        }
    }

    /// The kind each sheet adds to, nil for one that only shows.
    static func adds(_ raised: SettingsSheet) -> SettingsScope? {
        switch raised {
        case .subscriptionAdd: .subscriptions
        case .mailAdd:         .newsletters
        case .walletFollow:    .wallets
        case .newContact:      .people
        default:               nil
        }
    }

    /// An add has closed: every reading is read again, so the count and the
    /// list say what was added, and a count that grew lands its list.
    private func landAdded() async {
        let was = adding
        adding = nil
        await read()
        peopleRevision += 1
        guard let was, count(was.kind) > was.before else { return }
        // The pane's box lands the list column's instance, where the list is.
        if boxOnly { chrome.settingsLanding = .kind(was.kind); return }
        guard scope != was.kind else { return }
        withAnimation(DS.Motion.standard) {
            casberiOpen = false
            openFolder = nil
            scope = was.kind
            query = ""
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
    /// A kind's count, as the box draws it.
    private func count(_ kind: SettingsScope) -> Int {
        switch kind {
        case .apps: connectedApps.count
        case .calendars: phoneCalendars.count + CalendarSubscriptionStore.shared.calendars.count
        case .cards: connectedCards.count
        case .feeds: feeds.count
        case .newsletters: MailSubscriptionsReading.shared.items.count
        case .people: people
        case .subscriptions: SubscriptionsReading.shared.items.count
        case .wallets: WalletStore.shared.addresses.count
        }
    }

    private var hasMailApp: Bool { connectedApps.contains { Self.mailApps.contains($0.name) } }

    private var countsBox: some View {
        let counts: [(SettingsScope, Int, String)] = SettingsScope.kinds.map { kind in
            (kind, count(kind), kind.label)
        }
        // A broken connection says so in its kind's WORD (the tiles' rule,
        // never a dot), so it shows from every other kind too.
        let troubled: Set<SettingsScope> = connectedApps.contains { $0.status == .attention } ? [.apps] : []
        let widest = counts.map(\.1).max()
        return DSCountGrid(items: counts.count) {
            ForEach(counts, id: \.0) { kind, n, label in
                let verb = addVerb(kind)
                let menu = addMenu(kind)
                DSCountTile(count: n, label: label, isOn: kind == scope && !casberiOpen,
                            wants: troubled.contains(kind), inline: true, widest: widest,
                            add: verb == nil ? nil : { add(kind) }, addLabel: verb,
                            addMenu: menu,
                            // Apps has no add (prd §1388); its count still ends
                            // where the others do (prd §1390).
                            reservesPlus: verb == nil && menu.isEmpty) {
                    // EVERY COUNT PICKS WHAT STANDS UNDER THE BOX (prd §1317,
                    // user: "why doesn't it open in the screen below like cards
                    // and apps do"): no count opens a page over Sources.
                    if casberiOpen { casberiOpen = false }
                    pick(kind)
                }
            }
        }
    }

    // MARK: - Casberi


    // MARK: - Sheets over Settings (prd §1143)

    /// A plan's, a list's or a follow's sheet opens onward (Edit, a mail, a
    /// recent row): risen over Sources it hosts a stack, so that step pushes
    /// inside it instead of rising over it (prd §1315).
    @ViewBuilder
    private func raisedContent(_ route: SettingsSheet) -> some View {
        switch route {
        case .follow, .list, .plan: sheetContent(route).dsRaisedStack()
        default: sheetContent(route)
        }
    }

    @ViewBuilder
    private func sheetContent(_ route: SettingsSheet) -> some View {
        switch route {
        case .subscriptionAdd:      SubscriptionAddTray()
        // A list you already track opens here, over Library (prd §1143, §1588).
        case .mailAdd:              MailSubscriptionAddTray(onOpen: { id in sheet = .list(id) })
        case .walletFollow:         WalletFollowSheet()
        case .newContact:
            // The close lands People with the person in it (`landAdded`),
            // even when keeping them named someone already counted.
            NewContactSheet { adding?.before = -1 }
        case .follow(let id, let room): FollowingSheet(id: id, room: room)
        case .list(let id):         MailSubscriptionSheet(id: id)
        case .plan(let id):         SubscriptionSheet(id: id)
        }
    }

    // MARK: - Apps

    /// APPS, THE FIRST LANDING (prd §1166, user: "it shouldn't just be
    /// start here, it should be all the apps"): every app, yours and the
    /// ones you could add, as the library's folders (§1316) or, searching,
    /// A–Z. This draws only the search's empty answer; the letters follow
    /// as rows of their own.
    @ViewBuilder
    private var appsList: some View {
        if appCategories.isEmpty {
            DSEmptyState(headline: DSProse.text("No apps"), words: Text("Nothing matches."),
                         scale: .list(rows: 3))
        }
    }

    /// Every app the search admits, under its category: categories A–Z,
    /// Other last; apps A–Z.
    private var appCategories: [(category: String, apps: [BridgeCatalog.Offer])] {
        let offers = BridgeCatalog.offers.filter { Self.inLibrary($0) && hit($0.name) }
        let other = String(localized: "Other")
        let byCategory = Dictionary(grouping: offers) { BridgeCatalog.category(of: $0) }
        // THE FEED'S ORDER (prd §1347): Library's folders and the Feed's
        // sections are one list in one order, so a reorder on the Feed moves
        // the folders too. A name the order has never heard of sorts A–Z
        // after it (`CategoryOrder.sorted`), and Other is last.
        let named = CategoryOrder.sorted(byCategory.keys.filter { $0 != other })
        return (named + (byCategory[other] == nil ? [] : [other]))
            .map { category in
                (category, (byCategory[category] ?? []).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                })
            }
    }

    /// The phone's band carries the one search (prd §1321).
    static var bandSearches: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .phone
        #endif
    }

    /// Whether an app is yours, as its row says it (a paused one is not).
    private func isYours(_ name: String) -> Bool {
        bridges.bridges.contains { $0.name == name && $0.status != .paused }
    }

    /// Every category as a folder, yours first in each (prd §1316).
    private var libraryFolders: [SourcesLibrary.Folder] {
        SourcesLibrary.folders(appCategories, has: isYours)
    }

    /// The field focused or holding words: every app A–Z, as the App
    /// Library's search lists them (prd §1316).
    private var appsSearching: Bool { searchFocused || !query.isEmpty }

    /// An app in an open folder, as its row opens it: yours goes, the rest
    /// their way in.
    private func openFromFolder(_ name: String) {
        DSHaptic.selection()
        if let app = yours(name) {
            openYours(app)
        } else {
            setup(name)
        }
    }

    private func yours(_ name: String) -> BridgeApp? {
        bridges.bridges.first { $0.name == name && $0.status != .paused }
    }

    /// **AN APP YOU HAVE GOES; HOLDING IT MANAGES IT (prd §1418, reverses
    /// §1050f's tap).** Library draws the App Library, where a tap opens the
    /// app, so one of yours lands where the tray's icon does: its feed rises
    /// over Library. Its page is the long press's Settings, or Casberi ›
    /// Apps. One with nowhere to go (`landsNothing`) or one that needs you
    /// opens its page, the step it needs next.
    private func openYours(_ app: BridgeApp) {
        if app.status == .attention || LiveRoomSources.landsNothing.contains(app.name) {
            openPage(app)
        } else {
            chrome.sourceRequest = Self.landing(forApp: app)
        }
    }

    /// An app's own page, pushed beside Library (prd §1321 item 2); only a
    /// connect form rises.
    private func openPage(_ app: BridgeApp) {
        route.pushBridge(BridgeRouter.destination(forID: app.id))
    }

    /// The source a tap on one of your apps asks for: its seat's in a merged
    /// room, as the tray's icon asks (`RoomsTray.appItem`), else its own.
    static func landing(forApp app: BridgeApp) -> String {
        if let offer = BridgeCatalog.offers.first(where: { $0.name == app.name }),
           let room = RoomAccounts.room(ofCategory: BridgeCatalog.category(of: offer)),
           let seat = RoomAccounts.seats(for: room).first(where: { $0.name == app.name }) {
            return seat.source ?? seat.name
        }
        return BridgeRouter.roomSource(forID: app.id) ?? app.name
    }

    // MARK: - A–Z (prd §1253, the search's list since §1316)

    /// Every app the search admits, A–Z under its first letter; anything
    /// that does not start with a letter files under "#", last.
    private var appLetters: [(letter: String, names: [String])] {
        let names = BridgeCatalog.offers
            .filter { Self.inLibrary($0) && hit($0.name) }
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

    /// The built-ins are not apps you add: Markets is automatic (§1167),
    /// and the Wallet seat is the wallets you follow, added by the Wallets
    /// count's plus (user: "wallet should no longer be a tile in the wallet
    /// folder").
    static func inLibrary(_ offer: BridgeCatalog.Offer) -> Bool {
        BridgeCatalog.category(of: offer) != HomeScope.markets && offer.name != "Wallet"
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

    // MARK: - The first box (prd §1314)

    /// THE FIRST BOX: "START WITH ANY OF THESE" (prd §1314, user: "start here
    /// in the box: LOVE IT", "if they do one let it clear and not be below
    /// the box", "the user may think it is a checklist … like 'start with
    /// any of these'"). Eight zeros read as a report card on day one. Until
    /// anything arrives the box offers four ways in as Settings' rows (user,
    /// of three layouts: "C is more purposefully designed. what would apple
    /// do"): glyph, name, a grey value, the plus, A–Z so none is first; the
    /// first one done turns it into the counts. Nothing stands under the box (the
    /// step-by-step Start here of §1166 is deleted), and your name is not a
    /// way in: it lives in Casberi's own settings.
    private var startsInBox: Bool {
        FirstRun.shared.isEmpty(bridges: bridges)
    }

    /// The four ways in, shared with the empty Feed (`StartWaysIn`, prd
    /// §1365); each opens this page's own add.
    private var startBox: some View {
        StartWaysIn { way in
            switch way {
            case .app:
                if Self.bandSearches {
                    withAnimation(DS.Motion.standard) { chrome.roomsTray = true }
                } else {
                    searchFocused = true
                }
            case .calendar:     add(.calendars)
            case .card:         add(.cards)
            case .subscription: add(.subscriptions)
            case .wallet:       add(.wallets)
            }
        }
    }

    private var calendarsEmpty: Bool {
        phoneCalendars.isEmpty && CalendarSubscriptionStore.shared.calendars.isEmpty
    }

    /// A kind on the Feed's card (prd §1265), in the room's column as the
    /// apps' cards stand (§1253).
    private func kindCard<Content: View>(_ name: String, glyph: String,
                                         @ViewBuilder _ content: () -> Content) -> some View {
        SectionPanelCard(name: name, glyph: glyph,
                         inset: DSRoomChassis.rowInset - DSRoomChassis.inset) { content() }
            // Bare (prd §1383): Library's lists stand as the Feed's do.
            .environment(\.feedSectionPanelFilled, false)
    }

    /// A kind's own act, first in its card (prd §1265): the pink glyph in
    /// the Feed's column, the verb in the page's ink, no chevron.
    private func cardVerbRow(_ glyph: String, _ title: String, action: @escaping () -> Void) -> some View {
        DSPushRow(title: Text(title), opens: false, action: action) {
            Image(systemName: glyph)
                .dsGlyph(.body, weight: .medium)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Mark.row, height: DS.Mark.row)
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
                      subtitleTone: DS.pickInk, opens: false) {
                setup(name)
            } leading: {
                BridgeIcon(name: name, size: DS.Face.row)
                    // A row's mark is the row size (§1071), in the Feed's own lead column
                    // (`DS.Mark.row`, `DSFeedRow.leadSize`), so every list on Sources starts on one line.
                    .frame(width: DS.Mark.row, height: DS.Mark.row)
            }
        } else {
            DSPushRow(title: Text(verbatim: name), fact: Text("Add"), factTone: DS.pickInk) {
                setup(name)
            } leading: {
                BridgeIcon(name: name, size: DS.Mark.row)
            }
        }
    }

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
        ("MetaMask Card", "MetaMask Card"),
        ("Plasma One", "Plasma One card"),
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
                          subtitleTone: app == nil ? DS.pickInk
                                        : app?.status == .attention ? DS.attentionInk : DS.textTertiary,
                          opens: false) {
                    setup(card.app)
                } leading: {
                    BridgeIcon(name: card.app, size: DS.Face.row)
                    // A row's mark is the row size (§1071), in the Feed's own lead column
                    // (`DS.Mark.row`, `DSFeedRow.leadSize`), so every list on Sources starts on one line.
                    .frame(width: DS.Mark.row, height: DS.Mark.row)
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
            kindCard(String(localized: "Wallet"), glyph: "wallet.bifold") {
                ForEach(watched) { addr in
                    DSPushRow(title: Text(verbatim: addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label),
                              subtitle: addr.label.isEmpty ? nil : Text(verbatim: WalletStore.shortAddress(addr.address)),
                              opens: false) {
                        // The Wallet, on this account (prd §1588): the room
                        // this place feeds, never one page for every wallet.
                        chrome.openWallet()
                        chrome.walletScope = addr.address
                    } leading: {
                        // A face keeps its own ramp (face-ramp audit), centred in the
                        // Feed's 46pt column (prd §1170, §1265).
                        WalletFace(address: addr.address, size: DS.Face.row, circular: true)
                            .frame(width: DS.Mark.row, height: DS.Mark.row)
                    }
                    // What you follow goes from a hold on its row (prd §1302),
                    // through the book row's own unwatch, Undo included.
                    .contextMenu {
                        if let entry = AddressBook.shared.entry(for: addr.address) {
                            Button(role: .destructive) {
                                WalletUnwatch.perform(entry, context: context, chrome: chrome, bridges: bridges)
                            } label: {
                                Label(String(localized: "Stop following"), systemImage: "trash")
                            }
                        }
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
        // As its folder icon opens (prd §1418): it goes, and its page is the
        // long press's.
        let open = { openYours(app) }
        Group {
        if card {
            DSPushRow(title: Text(verbatim: app.name), subtitle: Text(verbatim: app.statusLine),
                      subtitleTone: tone, opens: false, action: open) {
                BridgeIcon(name: app.name, size: DS.Face.row)
                    // A row's mark is the row size (§1071), in the Feed's own lead column
                    // (`DS.Mark.row`, `DSFeedRow.leadSize`), so every list on Sources starts on one line.
                    .frame(width: DS.Mark.row, height: DS.Mark.row)
            }
        } else {
            DSPushRow(title: Text(verbatim: app.name),
                      fact: Text(verbatim: app.statusLine), factTone: tone, action: open) {
                BridgeIcon(name: app.name, size: DS.Mark.row)
            }
        }
        }
        .contextMenu { AppMenu(open: open, settings: { openPage(app) }) }
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
        .id(peopleRevision)
        // In the kind card's column (prd §1265, §1253): the letters and the
        // faces stand where the Wallet's and every other kind's rows do, the
        // 12pt a `SectionPanelCard` insets on Library — a list standing 12pt
        // short of its neighbours read as an error (user, 2026-10-18).
        .padding(.horizontal, DSRoomChassis.rowInset - DSRoomChassis.inset)
    }

    /// No strip at the edge (prd §752, §1392): the letters are group words
    /// in the list, and nothing else stands beside it.
    private var showsLetterIndex: Bool { false }

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
                            .frame(width: DS.Mark.row, height: DS.Mark.row)
                    }
                }
                ForEach(subscribed) { calendarRow($0) }
            }
        }
    }

    // MARK: - Following, mail lists, subscriptions (prd §1317)

    /// The kind a count picked, when its rows are list rows of their own:
    /// each row is its own cell, as in its room, so its hold raises its menu
    /// (in one shared cell a hold read as a tap, measured 2026-10-15).
    @ViewBuilder
    private var kindLists: some View {
        if !casberiOpen {
            switch scope {
            case .feeds:         followsList
            case .newsletters:   listsList
            case .subscriptions: plansList
            default:             EmptyView()
            }
        }
    }

    /// What you follow on the web and in Media, its room's rows (§1118).
    @ViewBuilder
    private var followsList: some View {
        let rooms: [Following.Room] = [.reading, .media]
        let items = rooms.flatMap { room in
            FollowingReading.shared.items(for: room).filter { hit($0.name) }.map { (room, $0) }
        }
        kindGroup(SettingsScope.feeds.label, glyph: ScopeTileGlyph.feeds, empty: items.isEmpty,
                  words: "Follow a site, a channel or a show with the plus.") {
            ForEach(items, id: \.1.id) { room, item in
                kindRow({ sheet = .follow(item.id, room) }) {
                    FollowingRow(room: room, item: item)
                } menu: {
                    StopMenus.follow(item, room, context: context, chrome: chrome)
                }
            }
        }
    }

    /// The mailing lists that write to you, Life's rows (§1115).
    @ViewBuilder
    private var listsList: some View {
        let items = MailSubscriptionsReading.shared.items.filter { hit($0.name) }
        kindGroup(SettingsScope.newsletters.label, glyph: ScopeTileGlyph.newsletters, empty: items.isEmpty,
                  words: "Lists that write to your mail show here.") {
            ForEach(items) { item in
                kindRow({ sheet = .list(item.id) }) {
                    MailSubscriptionRow(item: item, paid: FeedScreen.mailSubscriptionIsPaid(item))
                } menu: {
                    StopMenus.list(item, context: context, chrome: chrome)
                }
            }
        }
    }

    /// What you pay for, the Wallet's rows (§1105).
    @ViewBuilder
    private var plansList: some View {
        let items = SubscriptionsReading.shared.items.filter { hit($0.name) }
        kindGroup(SettingsScope.subscriptions.label, glyph: ScopeTileGlyph.subscriptions, empty: items.isEmpty,
                  words: "Track one with the plus.") {
            ForEach(items) { item in
                kindRow({ sheet = .plan(item.id) }) {
                    WalletSubscriptionRow(item: item, writes: FeedScreen.walletSubscriptionWrites(item))
                        // What you just tracked glows, as on the Wallet (prd §1588).
                        .arrivalWash(SubscriptionStore.shared.justTracked(item.id), hue: DS.brand)
                } menu: {
                    StopMenus.plan(item, context: context, chrome: chrome)
                }
            }
        }
    }

    /// The Feed's card for a kind's rows (`SectionPanelGroup`): the name on
    /// the panel's top, a row per cell, the end cap; empty, its one clause.
    private func kindGroup<Rows: View>(_ name: String, glyph: String, empty isEmpty: Bool,
                                       words: LocalizedStringKey,
                                       @ViewBuilder rows: () -> Rows) -> some View {
        SectionPanelGroup {
            SectionPanelName(name: name, glyph: glyph)
        } rows: {
            if isEmpty {
                empty(query.isEmpty ? words : "Nothing matches.")
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: 0, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
            } else {
                rows()
            }
        }
        // Bare (prd §1383).
        .environment(\.feedSectionPanelFilled, false)
    }

    /// One row of a kind's list, as its room draws it: the row opens its
    /// sheet over Sources, and a hold offers what its room's hold does.
    private func kindRow<Row: View, Menu: View>(_ open: @escaping () -> Void,
                                                @ViewBuilder row: () -> Row,
                                                @ViewBuilder menu: () -> Menu) -> some View {
        Button {
            DSHaptic.selection()
            open()
        } label: {
            row().contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .contextMenu { menu() }
        .dsHover()
        .listRowInsets(EdgeInsets(top: FeedScreen.rowAir, leading: DSRoomChassis.rowInset,
                                  bottom: FeedScreen.rowAir, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    /// **A TAP NEVER LEAVES (prd §1588).** A subscribed calendar is a fact,
    /// as the phone's are; Unsubscribe is its hold, as what you follow goes
    /// (§1302), and the flash offers it back.
    private func calendarRow(_ entry: CalendarSubscriptionStore.Entry) -> some View {
        DSPushRowLabel(title: Text(verbatim: entry.displayName),
                       subtitle: Text(calendarLine(entry)), opens: false) {
            Image(systemName: ScopeTileGlyph.calendars)
                .dsGlyph(.body, weight: .regular)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Mark.row, height: DS.Mark.row)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) { unsubscribe(entry) } label: {
                Label(String(localized: "Unsubscribe"), systemImage: "minus.circle")
            }
        }
    }

    private func unsubscribe(_ entry: CalendarSubscriptionStore.Entry) {
        let url = entry.url
        withAnimation(DS.Motion.standard) { CalendarSubscriptionIngest.remove(entry.id, context: context) }
        chrome.flash(String(localized: "Unsubscribed from \(entry.displayName)"),
                     action: ShellChrome.ToastAction(label: String(localized: "Undo")) {
            guard let back = CalendarSubscriptionStore.shared.add(url) else { return }
            Task { @MainActor in await CalendarSubscriptionIngest.refresh(context: context, only: back.id) }
        })
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
        // Where what you follow lands: the Feed's Media section (prd §1323,
        // user: "why isn't all that stuff media? it's what goes in the media
        // section of the feed"). "Following" promised wallets and people too.
        case .feeds:         return String(localized: "Media")
        // Whole everywhere since prd §1166 (user: "we going to say 'Subs'
        // everywhere?"): no shortened word on any surface.
        case .newsletters:   return String(localized: "Mail lists")
        // One word with its plus's "New contact" and "Contacts" (prd §1323,
        // user: "when you click plus it says add contact or contacts").
        case .people:        return String(localized: "Contacts")
        case .subscriptions: return String(localized: "Subscriptions")
        case .wallets:       return String(localized: "Wallet")
        }
    }

    var summary: String {
        switch self {
        case .apps:          return String(localized: "Every app, by category")
        case .cards:         return String(localized: "The cards your card apps read")
        case .wallets:       return String(localized: "The accounts you follow, and their apps")
        case .calendars:     return String(localized: "Every calendar Casberi reads")
        case .feeds:         return String(localized: "The sites and shows you follow")
        case .newsletters:   return String(localized: "The lists that write to your mail")
        case .people:        return String(localized: "Everyone you know, from every app")
        case .subscriptions: return String(localized: "What renews, free or paid")
        }
    }
}

/// Subscribe to a calendar by its address (prd §1137).
struct CalendarSubscribeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @State private var link = ""
    @State private var refused: String?
    @FocusState private var focused: Bool

    var body: some View {
        DSTray(title: String(localized: "Subscribe to a calendar"), height: 300) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSSlabField(placeholder: String(localized: "webcal:// or https:// link"),
                            text: $link, actionLabel: String(localized: "Subscribe"),
                            focus: $focused, glyph: "calendar", clearable: true,
                            size: .slab, submitLabel: .go,
                            // A link is copied, never typed (prd §1588).
                            paste: { link = $0 }) { subscribe() }
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
        // Said, and felt once, as every add is (prd §1588).
        chrome?.flash(String(localized: "Subscribed to \(entry.displayName)"), tone: .success)
        dismiss()
    }
}

/// Where the tray's search lands in Settings (prd §1171): a person on People
/// with their name in the field, a kind's list, or a row's own sheet.
enum SettingsLanding: Hashable {
    case person(String)
    case kind(SettingsScope)
    case sheet(SettingsSheet)
}

/// What Settings raises over itself (prd §1143).
enum SettingsSheet: Identifiable, Hashable {
    case subscriptionAdd, mailAdd
    case walletFollow
    /// Keep a person by hand (prd §1300), People's plus.
    case newContact
    /// What you follow, its sheet (prd §1317).
    case follow(String, Following.Room)
    /// A mailing list, its sheet (prd §1317).
    case list(String)
    /// A biller's plan, the Wallet's sheet for it (prd §1275).
    case plan(String)

    var id: String {
        switch self {
        case .subscriptionAdd:            "subscriptionAdd"
        case .mailAdd:                    "mailAdd"
        case .walletFollow:               "walletFollow"
        case .newContact:                 "newContact"
        case .follow(let id, let room):   "follow:\(room):\(id)"
        case .list(let id):               "list:\(id)"
        case .plan(let id):               "plan:\(id)"
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
                    .foregroundStyle(DS.pickInk)
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
