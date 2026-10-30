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
/// replaces the Apps and Addresses places.
///
/// **NO BOX (user, 2026-10-30: "this whole section … is confusing and just
/// makes the app feel harder to use … we don't really need it").** Library
/// is its title and the folders. The counts box and the eight lists it
/// switched between are deleted: what you follow, your mail lists and your
/// subscriptions list in their rooms (§1217), the cards and the wallets in
/// the Wallet, the apps are the folders, and the two that lived nowhere else
/// are their apps' pages: Contacts (`ContactsPage`, in Social's folder) and
/// Calendar (`CalendarsPage`, in Day's).
struct SettingsHome: View {
    @Environment(BridgeStore.self) private var bridges
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route
    @Environment(\.modelContext) private var context

    #if DEBUG
    /// `-connectTap` fires once a launch, not at every mount.
    @MainActor static var connectTapped = false
    #endif
    /// Casberi's own options, opened in place from its pinned row — the way a
    /// Notes folder opens (prd §980): its name leads back.
    @State private var casberiOpen = false
    /// What Library's field filters (prd §1245).
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Track tray of an app that needs only a name (prd §1119), raised
    /// by a door that named it (prd §1234; the Apps screen's until then).
    @State private var trackPick: TrackPick?
    /// The folder sprung open over the page (prd §1316).
    @State private var openFolder: String?
    /// The category a door named (`route.openCategory`, prd §1300): its
    /// folder springs open once the page has risen, then lets go.
    @State private var landCategory: String?
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
            DSRoomTitleRow(title: String(localized: "Library"))
                .demoTagOnTitle()
                .dsRoomTitleListRow(inSheet: route.sheet != nil)
            // The places' row is gone (prd §1327 item 1): they are tabs.
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    // SOURCES FINDS ITS APPS (prd §1245, user: "there is no
                    // fab, notes, or search bar, so you can't search for
                    // apps"): risen as a sheet it covers the band's bar, so
                    // the Apps list keeps a field of its own. On the phone
                    // Library is a page under the band (prd §1321), whose
                    // search finds every app: the field stays only for a
                    // name a search landed on.
                    if !casberiOpen, !Self.bandSearches || !query.isEmpty {
                        DSSlabField(placeholder: String(localized: "Search"),
                                    text: $query, actionLabel: "",
                                    focus: $searchFocused,
                                    glyph: "magnifyingglass", clearable: true,
                                    size: .slab, submitLabel: .search, action: {})
                    }
                    // THE LIBRARY (prd §1316): every category a folder,
                    // Casberi's own settings the first slot. The field
                    // focused or holding words lists every app A–Z instead,
                    // as the App Library's does.
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
                }
                .listRowInsets(.init(top: DS.Space.s2, leading: DS.Space.s4,
                                     bottom: DS.Space.s4, trailing: DS.Space.s4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if !casberiOpen, appsSearching { appsByLetter }
            // Room for the floating bar, as every room leaves it.
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
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
        // The A–Z strip (prd §1153): the apps' index on the trailing edge,
        // a letter tapped or slid to jumps the list to its header.
        .overlay(alignment: .bottomTrailing) {
            if !casberiOpen, appsSearching, query.isEmpty {
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
            if casberiOpen {
                SourcesSettingsFolder(close: { withAnimation(DS.Motion.folder) { casberiOpen = false } })
                    .transition(folderSpring)
            }
        }
        // A folder springs open over the page (prd §1316).
        .overlay {
            if let category = openFolder, !casberiOpen,
               let folder = libraryFolders.first(where: { $0.category == category }) {
                SourcesOpenFolder(folder: folder, has: isYours,
                                  open: { openFromFolder($0) },
                                  settings: { name in yours(name).map { app in { openPage(app) } } },
                                  close: { withAnimation(DS.Motion.folder) { openFolder = nil } },
                                  // The Notes folder leads with the Notes
                                  // page, pushed beside Library (prd §1347).
                                  notesPage: category == BridgeCatalog.notesCategory
                                      ? { route.push(.notes) } : nil)
                    .transition(folderSpring)
            }
        }
        }
        .dsAdaptiveContentWidth(.reading)
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(Text("Settings"))
        .toolbar(.hidden, for: .navigationBar)
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
            // `-connectTap "<Offer name>"` — the door an unconnected app's
            // Add row in Sources › Apps takes (`offerRow`: `setup`), for
            // verify-mac's connect gate. Never a direct push: a probe on a
            // route no person takes proves the screen, never the act
            // (8f4cb144, App Store 2.1(a), build 363). It says which door it
            // took, because Mac pushes where the phone raises.
            if let name = UserDefaults.standard.string(forKey: "connectTap"), !Self.connectTapped {
                Self.connectTapped = true
                let raises = BridgeRouter.destination(forOffer: name)?.raisedByConnect == true
                    && route.sheet == nil
                NSLog("[Casberi] connectTap| %@ connect form for %@",
                      raises ? "raising" : "pushing", name)
                setup(name)
            }
        }
        #endif
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
                query = ""
            }
            landCategory = category
        }
        .onChange(of: route.openOffer, initial: true) { _, name in
            guard let name else { return }
            route.openOffer = nil
            withAnimation(DS.Motion.standard) { casberiOpen = false }
            openOffer(name)
        }
        .onChange(of: chrome.settingsPick, initial: true) { _, pick in
            guard let pick else { return }
            // Every door to the folder takes the same one (prd §1405): the
            // pane where Library has one, the card over the page elsewhere.
            if pick == .casberi { openCasberiFolder() }
            else { withAnimation(DS.Motion.standard) { casberiOpen = false } }
            chrome.settingsPick = nil
        }
        .onChange(of: chrome.settingsLanding, initial: true) { _, landing in
            // The tray's search found what Library's apps hold (prd §1171):
            // a person lands on Contacts with their name in its field, a
            // calendar on Calendars.
            guard let landing else { return }
            casberiOpen = false
            switch landing {
            case .contacts(let name): route.push(.contacts(name))
            case .calendars:          route.push(.calendars)
            }
            chrome.settingsLanding = nil
        }
    }

    /// A folder springs open from its tile; under Reduce Motion it fades.
    private var folderSpring: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity)
    }

    // MARK: - Acts

    /// The landed name, over the kind you're on.
    private func hit(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    @ViewBuilder
    private func trackTray(_ pick: TrackPick) -> some View {
        Group {
            if pick.room == .reading {
                ReadingFindSheet(onTracked: {})
            } else {
                FollowTrackTray(room: pick.room, seat: pick.seat, onTracked: {})
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
        // CONTACTS AND CALENDAR OPEN THEIR LISTS (user, 2026-10-30): the two
        // lists Library's box held that live nowhere else are their apps'
        // pages, each with its own way in, whether or not the app is yours.
        if name == "Contacts" { route.push(.contacts("")); return }
        // Calendar of yours GOES, to its events, like every app of yours
        // (user, 2026-10-29: tapping it "just showed me what calendars i was
        // subscribed to"); the calendars list stays for one you haven't added.
        if name == "Calendar", yours(name) == nil { route.push(.calendars); return }
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

/// Where the tray's search lands in Library (prd §1171): a person on the
/// Contacts page with their name in its field, or the Calendars page.
enum SettingsLanding: Hashable {
    case contacts(String)
    case calendars
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
