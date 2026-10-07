import SwiftUI
import SwiftData

/// Apps — ONE catalog (ruling 2026-07-10: the Connected strip died; the feed
/// is where connected apps live, and this page is where you add and manage
/// them from a single grid). Every app sits in its category shelf; a
/// connected app's row is its STATUS and goes nowhere when it has a room —
/// the room's own door manages it (prd §1033) — a broken one wears Fix, an
/// available one wears Connect, a coming one Soon.
/// The strip's hairline died with it — the app now draws no lines at all.
///
/// LAYOUT LAW (the doc's): no fixed heights anywhere — every card, pill, and
/// row sizes to its content plus token padding (minHeight only where a target
/// needs it). Capsule verbs are honest: Connect / Fix / Open / Soon.
struct AppsScreen: View {
    @Environment(ShellChrome.self) private var chrome
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    /// Compact is the phone, where the category tiles ride the capsule
    /// beside the seat (`DSScopeDock`, prd §960) instead of standing under
    /// the search field.
    @State private var trackPick: TrackPick?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// The bar's Search (prd §1138): the field stands under the box once
    /// asked for, and folds away when it closes empty.
    @State private var searchOpen = false
    /// The connect payoff (delight): every Connect on this screen — story
    /// card OR shelf capsule — ends the same way the product page's does,
    /// the app's hue blooming over the page (the shared `.connectBloom`).
    /// `connectHue` is the app that just landed; bumping `connectToken` fires
    /// one bloom.
    @State private var connectHue: Color = DS.tint
    @State private var connectToken = 0
    // The store's first-ever connect used to rain the app's generic berries
    // once, then (2026-08-04) every connect rained the CONNECTED APP's own
    // mark. Both retired — the rain is pull-to-refresh's payoff alone (user
    // ruling 2026-08-11); the bloom and the connected tile's promote lift
    // carry the connect moment now.
    /// Which slice of the catalog is on screen — All, or one category.
    ///
    /// Deliberately NOT remembered across visits (contrast `MarketsRoom.landing`,
    /// which reopens on the venue you left). That room is somewhere you live; a
    /// catalog is a directory you consult, and arriving on a three-week-old
    /// filter hides nine tenths of it with nothing on screen saying why.
    @State private var scope = CatalogScope(name: nil)
    /// Bumped when a category's LAST addable app connects — the section header
    /// glows once in the category's own color and a toast names the set now
    /// complete.
    ///
    /// The jump-arrival flash that used to share this shape retired with the
    /// jump (prd §518): a chip FILTERS now, so the list itself changing is the
    /// arrival, and a header flash on top of it was a second answer to one tap.
    @State private var shelfComplete: [String: Int] = [:]
    /// The app that just connected, by any path — the shelf row wearing this
    /// name lifts as it takes its connected seat. `connectLiftToken` fires one
    /// lift; the name gates which row.
    @State private var justConnectedName: String?
    @State private var connectLiftToken = 0
    /// Connect-count milestones (5 / 10 / 25 seats): the highest threshold
    /// already celebrated, persisted so each fires once, forever. Seeded to the
    /// highest passed threshold on appear so a user who arrives past one never
    /// gets a late toast.
    @AppStorage("apps.connectMilestone.reached") private var connectMilestoneReached = 0
    /// "Because of what you keep" — corpus-derived Discover seats, read once per
    /// appearance (a plain fetch, counted in memory; never per frame).
    #if DEBUG
    @State private var probe: AppsProbe?
    #endif

    // MARK: - Categories (merge map over Offer.group — Browse + chart filter ONLY,
    // never vertical section headers). Lives in `BridgeCatalog` now
    // (2026-07-20) — the ruled single source of truth — so the agent's
    // `category:<name>` kept-ask kind reads the exact same mapping. Kept as
    // a thin local alias so this file's call sites don't all need renaming.

    private static var categories: [(name: String, exemplar: String, groups: Set<String>)] {
        BridgeCatalog.categories
    }

    private func category(of offer: BridgeCatalog.Offer) -> String {
        BridgeCatalog.category(of: offer)
    }

    // MARK: - Ranking (the For-you chart's one order)

    private struct Ranked: Identifiable {
        let offer: BridgeCatalog.Offer
        let bridge: BridgeApp?
        let tier: Int
        var id: String { offer.name }
    }

    private func actionable(_ offer: BridgeCatalog.Offer) -> Bool {
        offer.connectable
    }

    /// ONE ranked list for the whole catalog (2026-07-10, strip removed):
    /// tier 0 = connected but broken (Fix leads — it needs you), tier 1 =
    /// ready to connect, tier 2 = connected and healthy (Open → manage),
    /// tier 3 = coming (Soon). Every app appears exactly once.
    /// The whole catalogue, connected rows included (prd §1033, retiring
    /// §812's split): Manage is deleted, so an account you hold stands in the
    /// directory wearing its state, and managing it is the room's own door.
    /// **ONLY WHAT YOU COULD ADD (prd §1142, user: "when i click [Add] i see
    /// the same apps i'm connected to on the previous screen"):** Settings ›
    /// Apps lists what you have, so the catalogue — reached from its Add and
    /// its "N more in <Category>" links — lists what you don't. Search still
    /// reaches every app (`searchHits` reads `rankedAll`).
    private var ranked: [Ranked] { rankedAll.filter { !isAdded($0) } }

    private var rankedAll: [Ranked] {
        // Markets is a place in You, not an app category (prd §1123, §1138):
        // it is opened from its tile there, never listed here.
        BridgeCatalog.offers.compactMap { offer in
            guard BridgeCatalog.category(of: offer) != HomeScope.markets else { return nil }
            let bridge = store.bridges.first { $0.name == offer.name }
            let tier: Int
            if let bridge, bridge.status == .attention { tier = 0 }
            else if let bridge, bridge.status != .paused { tier = 2 }
            else { tier = actionable(offer) ? 1 : 3 }
            return Ranked(offer: offer, bridge: bridge, tier: tier)
        }
        .sorted { $0.tier < $1.tier }
    }


    /// Erased to `AnyView` at this ONE boundary (prd §200, found live,
    /// 2026-07-23): the wall added a sibling view (`searchField`) ahead of
    /// the old single if/else, which turns the VStack's content into a tuple
    /// the type checker must carry through `ScrollView`/`ScrollViewReader`
    /// AND the ~16-modifier chain `body` closes with — together enough to
    /// blow the checker's budget ("unable to type-check … in reasonable
    /// time"), confirmed by bisection: every individual piece here type-checks
    /// fine alone. Erasing right where the reader closes lets the modifier
    /// chain solve against plain `AnyView` instead of the fully generic
    /// nested type; nothing behavioral changes; `proxy` still reaches every
    /// scrollTo call inside.
    private var scrollContent: AnyView {
        AnyView(
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        // APPS (prd §1111): everything you can connect, what
                        // you have marked; Casberi's settings left for their
                        // own door. A place in You since prd §1129, so the
                        // category's row stands where the screen's name did.
                        YouHead(place: .apps)
                            .id(Self.topAnchor)
                        // The search field leads the page (user ruling,
                        // 2026-07-23: "make sure the search bar is at the
                        // top") — a visible slab, not the nav bar's
                        // pull-down `.searchable` field, which the App Store
                        // shape hid a scroll below the fold.
                        // The categories ARE the box (prd §1138): what you
                        // have in each, pressed to filter the list. Search
                        // rides the bar and opens its field under the box;
                        // the Added chip is deleted, Sources lists what you
                        // have.
                        categoryBox
                        if searchShown {
                            searchField
                        }
                        sections(proxy)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    // The You row stands where a feed's title stands (prd §1129):
                    // the feed's `s2` above it, so a switch moves nothing.
                    .padding(.top, DS.Space.s2)
                    .padding(.bottom, DS.Space.s4)
                }
                // The category tiles within the thumb's reach on the phone
                // (prd §960): a capsule beside the seat. Down while a search
                // is up — the hits are not a catalogue, and the strip never
                // stood over them either.
                // A place in You stands where a room does, down to the safe
                // area, so the bar centres on the seat (prd §1136e's fix).
                .dsScopeDock(sections: query.isEmpty && !searchFocused ? [AppsBarScope.search] : [],
                             active: AppsBarScope.search, verbs: [.search], clearance: 0) { _ in
                    withAnimation(DS.Motion.standard) { searchOpen = true }
                    searchFocused = true
                }
                .onChange(of: searchFocused) { _, focused in
                    if !focused, query.isEmpty { searchOpen = false }
                }
                #if DEBUG
                .onAppear {
                    // `-appsShelf "<Category>"` — PICK a category headlessly
                    // (screenshot runs have no tap; same route as the chip).
                    //
                    // It used to `scrollTo` the category's card, and the verb
                    // changed with the control (prd §518): a chip filters now,
                    // so the honest headless equivalent is the write the chip
                    // makes, not a scroll to a card that no longer exists.
                    // A name matching no chip leaves the scope on All and says
                    // so — silently landing on All would read as the pick
                    // having worked.
                    guard let name = UserDefaults.standard.string(forKey: "appsShelf") else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        let live = scopes.contains { $0.name == name }
                        if live { scope = CatalogScope(name: name) }
                        NSLog("appsShelf: %@ %@ (%d apps)", name,
                              live ? "picked" : "NO SUCH CHIP — still A–Z",
                              listSections.reduce(0) { $0 + $1.apps.count })
                        proxy.scrollTo(Self.topAnchor, anchor: .top)
                    }
                }
                .onAppear {
                    // `-appsCatalogProbe YES` — one line per section the
                    // catalog would draw, in order, with its row count.
                    //
                    // An empty or short catalog list has causes that render
                    // identically: a category whose offers all resolve to a
                    // DIFFERENT category (the `category(of:)` group map is the
                    // single source of truth and a renamed group falls through
                    // to "Life"), a scope filtering to nothing, or a genuinely
                    // small section. Only the first two are bugs, and the
                    // per-section counts are what separate them.
                    guard UserDefaults.standard.bool(forKey: "appsCatalogProbe") else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        NSLog("appsCatalog| scope=%@ chips=%d sections=%d",
                              scope.name ?? "A–Z", scopes.count, listSections.count)
                        // One NSLog PER section, never a joined string — the
                        // log reader truncates a long multi-line message
                        // mid-document (the `-todayProbe` lesson).
                        for section in listSections {
                            NSLog("appsSection| %@ apps=%d", section.name, section.apps.count)
                        }
                    }
                }
                #endif
            }
        )
    }

    /// What stands under the head row — the search hits, the settings rows, or
    /// the catalogue with its category strip.
    ///
    /// ITS OWN `@ViewBuilder`, not a third branch inline. The VStack above is
    /// the one whose tuple `scrollContent` erases to `AnyView` to stay inside
    /// the type checker's budget (see there): a two-way if/else was already
    /// enough to need that erasure, so §796's third arm is lifted out rather
    /// than added to it.
    @ViewBuilder
    private func sections(_ proxy: ScrollViewProxy) -> some View {
        // Two arms again since prd §933: Settings and Addresses left for
        // screens of their own, taking §916's "the field filters the list
        // you are on" with them (`AddressesScreen` has its own field).
        if !query.isEmpty {
            searchResults
        } else {
            catalogList
        }
    }

    var body: some View {
        scrollContent
        .scrollIndicators(.hidden)
        // The connect payoff blooms the app's hue over the whole store, then
        // recedes — the same beat the product page gives, now on every Connect.
        // (The glyph rain that fell through the bloom retired 2026-08-11,
        // user ruling: berry rain is pull-to-refresh's payoff alone. The
        // bloom + tile promote carry the moment.)
        .connectBloom(hue: connectHue, token: connectToken)
        // The Track tray of an app that needs only a name (prd §1119). The
        // environment is handed on: a Catalyst sheet does not inherit it
        // (prd §872).
        .sheet(item: $trackPick) { pick in
            trackTray(pick)
                .environment(chrome)
                .environment(store)
                .environment(route)
                .environment(\.modelContext, modelContext)
        }
        .onAppear {
            // Seed the connect-count milestone to the highest already-passed
            // threshold so arriving past one never fires a late toast.
            let passed = Self.connectMilestones.filter { $0 <= connectedCount }.max() ?? 0
            if passed > connectMilestoneReached { connectMilestoneReached = passed }
            // The rooms tray's Connect door (prd §930, §958) lands on the
            // whole catalogue.
            landRequestedSection()
        }
        // The store's shape after any connect/disconnect — drives the promote
        // lift (which row just took its seat), the count milestones, and the
        // shelf-completed glow. Keyed on the NAMES (not just the count) so the
        // just-connected row can be identified.
        .onChange(of: connectedNames) { old, new in
            handleConnectChange(old: old, new: new)
        }
        // The tray can be raised OVER this screen and a second door tapped, so
        // a request made while it is already up still lands (prd §930).
        .onChange(of: route.openConnect) { _, _ in landRequestedSection() }
        // The catalog is a LIST now (prd §518), so it takes the READING column
        // — and that is the same distinction `DSContentWidth` draws, answered
        // the other way. It was `.wide` because a grid spends extra width on
        // extra columns per band; a single file of rows spends it on longer
        // rows, and a 1040pt row holding a 44pt icon, a name and a capsule is
        // three objects marooned at opposite edges of an inch of nothing.
        .dsAdaptiveContentWidth(.reading)
        .dsPageBackground()
        .dsSoftScrollEdges()
        // The name is in the content and the way back is the dock's seat, so
        // nothing stands at the top edge (prd §767).
        .navigationTitle(Text("Settings"))
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .navigationDestination(item: $probe) { p in
            switch p {
            case .wallet: WalletScreen()
            }
        }
        #endif
        .onAppear {
            // A tile on the empty feed's pile landed here wanting its product
            // page. There is no product page since §641, so it lands where
            // every other Connect lands — the seat's own setup page, through
            // the SAME `rowAction` the row it named would run, so a tile and
            // the row it points at cannot disagree. Resolve first: an
            // unresolvable name (a renamed offer outrunning the pile array)
            // simply leaves the catalog standing.
            if let name = route.openOffer {
                route.openOffer = nil
                if let entry = rankedAll.first(where: { $0.offer.name == name }) {
                    rowAction(entry)?()
                }
            }
            // …and a door that named a CATEGORY lands filtered to it (prd
            // §550 — the agent's empty-chat link). Resolved against `scopes`
            // rather than against the catalog's raw category list, for the
            // same reason that property drops an empty category: a scope with
            // no chip in the strip would filter the list to nothing while the
            // strip showed All selected, which reads as a broken screen. An
            // unresolvable name simply leaves All standing.
            if let category = route.openCategory {
                route.openCategory = nil
                if let picked = scopes.first(where: { $0.name == category }) {
                    scope = picked
                }
            }
            #if DEBUG
            // `-openWallet YES` takes the TRACKED route (prd §442, found on a
            // device). It used to set `probe`, which is a
            // `navigationDestination(item:)` binding of this screen's own —
            // so the manager arrived on a frame `HomeRoute.path` does not
            // know about, and anything the manager later PUSHED through
            // `route.push` was silently dropped (CLAUDE.md's own
            // "a plain NavigationLink pushes a frame the bound path doesn't
            // track"). §440 gave the manager a real push for the first time —
            // a group's own screen — and it opened from the app and did
            // nothing under the probe, which is the shape this file's
            // neighbouring comment already warns about: a probe that opens a
            // screen by a route no person can take proves the screen and
            // never the act.
            if UserDefaults.standard.bool(forKey: "openWallet") {
                route.pushBridge(.wallet)
            }
            // `-openSetup "<Offer name>"` pushes a bridge's setup screen
            // directly — the token/handle field screens have no deep link.
            // `-connectTap "<Offer name>"` — the door the Connect BUTTON takes.
            //
            // It exists because `-openSetup` below does NOT take it, and that
            // gap shipped a crash. `-openSetup` calls `route.pushBridge`, which
            // PUSHES the setup screen; every real Connect calls
            // `route.openSetup`, which for any non-wallet destination RAISES it
            // as a sheet. Two doors onto the same screen, and only the pushed
            // one had a probe — so the sheet presentation was never exercised
            // here, and `ConnectFormSheet`'s required
            // `@Environment(BridgeStore.self)` went missing on Mac for every
            // setup bridge in the catalog (App Store review 2.1(a), build 363).
            // A probe that opens the screen by a route no person can take
            // proves the screen, never the act.
            //
            // Both hooks stay: the push is what the screenshot sweep wants
            // (a full screen, no presentation to dismiss), the raise is what
            // the crash gate wants. See scripts/verify-mac.sh step 2c.
            //
            // **On Mac `openSetup` PUSHES now (2026-08-20, see
            // `Destination.raisedByConnect`), so this hook says which door it
            // actually took.** The word matters: the line above claimed
            // "raising" unconditionally, so on Mac the gate reading it would
            // have gone green while describing a presentation that no longer
            // happens — a check passing for the wrong reason, which is worse
            // than one that fails. Note the 2.1(a) crash class itself cannot
            // arise on the pushed door: a push inherits the stack's
            // environment, and it was a sheet's own hosting controller not
            // inheriting it that trapped. The gate is still worth running
            // there — it exercises the door a PERSON takes, which is the
            // lesson that bought it — it just proves something different now.
            if let name = UserDefaults.standard.string(forKey: "connectTap") {
                let raises = BridgeRouter.destination(forOffer: name)?.raisedByConnect == true
                NSLog("[Casberi] connectTap| %@ connect form for %@",
                      raises ? "raising" : "pushing", name)
                route.openSetup(forOffer: name)
            }
            // `-appsTrack "<Offer name>"` — the row tap of an app that needs
            // only a name (prd §1119): its Track tray over the catalogue.
            if let name = UserDefaults.standard.string(forKey: "appsTrack"),
               let room = FollowingReading.trackRoom(forSeat: name) {
                NSLog("[Casberi] appsTrack| %@ → %@ tray", name, room.rawValue)
                trackPick = TrackPick(room: room, seat: name)
            }
            if let name = UserDefaults.standard.string(forKey: "openSetup") {
                route.pushBridge(BridgeRouter.destination(forOffer: name))
            }
            // `-openBridgeDetail "<BridgeStore id>"` takes a CONNECTED seat's
            // Open — its manage screen, or its ROOM for a wallet-riding seat
            // that has none (prd §494). The setup hook above can't reach it: a
            // bridge whose connect is a system permission (Photos, Calendar…)
            // has no setup screen, so `destination(forOffer:)` gives nothing
            // to push.
            if let id = UserDefaults.standard.string(forKey: "openBridgeDetail") {
                // Through the shared door, not `pushBridge` — a wallet-riding
                // seat opens its ROOM now, and a probe that still pushed the
                // manager would exercise a route no person takes.
                NSLog("[Casberi] openBridgeDetail| %@ -> %@", id,
                      BridgeRouter.roomSource(forID: id) ?? "push")
                BridgeRouter.open(seatID: id, route: route, chrome: chrome)
            }
            #endif
        }
    }

    // MARK: - Search (App Store grammar — 40+ apps is past what chips can hold)

    /// Every offer whose name, tagline, category — or the named things it
    /// reads — matches the query. A flat list you scan, in the same ranked tier
    /// order the shelves use.
    ///
    /// `alsoReads` is what makes "aave" findable (prd §515). Those five had
    /// seats of their own until §515 and lost them for landing no rows of their
    /// own; searching for one now answers with the seat that really reads it,
    /// which is a better answer than the one it replaced — that seat opened
    /// somebody else's room.
    ///
    /// Matched with `hasPrefix` on WHOLE names rather than `contains` over the
    /// joined list: substring-matching a list of proper nouns makes short
    /// queries hit things they do not name ("a", "eth"), and a person typing a
    /// protocol types its first letters.
    private var searchHits: [Ranked] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        // Across BOTH lists (prd §812): someone who connected Spotify and
        // types it from Connect is shown their Spotify, not nothing.
        return rankedAll.filter { entry in
            entry.offer.name.lowercased().contains(q)
                || entry.offer.tagline.lowercased().contains(q)
                || category(of: entry.offer).lowercased().contains(q)
                || entry.offer.alsoReads.contains { $0.lowercased().hasPrefix(q) }
        }
    }

    /// A query that looks like a site or newsletter — a dot (a domain), or a
    /// word that names web-publishing. RSS follows most of these, so the miss
    /// becomes a connect path instead of a dead end.
    private func looksLikeSite(_ q: String) -> Bool {
        let s = q.lowercased()
        if s.contains(".") { return true }
        return ["feed", "blog", "newsletter", "rss", "substack", "site", "website"]
            .contains { s.contains($0) }
    }

    /// The RSS offer as an addable row — nil if RSS is already connected (then
    /// there's nothing to suggest).
    private var rssSuggestion: Ranked? {
        ranked.first { $0.offer.name == "RSS" && $0.tier == 1 }
    }

    @ViewBuilder
    private var searchResults: some View {
        let hits = searchHits
        if hits.isEmpty {
            VStack(spacing: DS.Space.s4) {
                Text("No apps match \(Text(query).fontWeight(.semibold)).")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, DS.Space.s4)
                // A website-looking query has an answer even when no app name
                // matches: RSS follows most sites. Honest — the row's own
                // Connect opens RSS's real setup.
                if looksLikeSite(query), let rss = rssSuggestion {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("RSS can follow most sites.")
                            .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                        VStack(spacing: DS.Space.s1) { appRow(rss) }
                    }
                }
            }
            .padding(.top, DS.Space.s8)
        } else {
            VStack(spacing: DS.Space.s1) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { i, entry in
                    appRow(entry).modifier(StockEntrance(index: i))
                }
            }
            // NO CARD (prd §590). §518's note about a second horizontal inset
            // is kept in spirit and answered better: there is no card left to
            // inset from, and `appRow` gave up its own `s4` in the same pass,
            // so a row's words now sit on the page inset — the same left edge
            // as the search field above them.
        }
    }

    // MARK: - Connect payoff (delight parity across every Connect on this screen)

    /// One-tap connect (a system-permission bridge) fired from the store, with
    /// the shared payoff on success. Setup bridges never reach here — Connect
    /// opens their setup screen, where the connect (and its proof) happens.
    /// The app a Track tray opened on (prd §1119).
    struct TrackPick: Identifiable {
        let room: Following.Room
        let seat: String
        var id: String { seat }
    }

    @ViewBuilder
    private func trackTray(_ pick: TrackPick) -> some View {
        let landed = { landAfterTrack(pick.room) }
        if pick.room == .reading {
            ReadingFindSheet(mode: .follow, onTracked: landed)
        } else {
            FollowTrackTray(room: pick.room, seat: pick.seat, onTracked: landed)
        }
    }

    /// The follow landed: leave the catalogue for the room that now lists it.
    private func landAfterTrack(_ room: Following.Room) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            route.closeConnectForm()
            route.path = []
            chrome.landOnFollowing(room)
        }
    }

    private func attemptConnect(_ offer: BridgeCatalog.Offer) {
        BridgeConnect.connect(offer, store: store, context: modelContext) { ok in
            if ok { celebrateConnect(offer) }
            else { chrome.flash("Couldn't connect \(offer.name).", tone: .failure) }
        }
    }

    /// The moment a one-tap connect lands: a success haptic, the app's hue
    /// blooming over the store, the toast naming what's now happening. Shared
    /// by the story card and the shelf capsule so no Connect ends silently.
    /// (The first-connect berry rain is dealt by `connectedCount`'s watcher,
    /// not here — it must fire for setup-screen connects too.)
    private func celebrateConnect(_ offer: BridgeCatalog.Offer) {
        // Glyph-colored marks bloom their glyph (Tokens' green) — a
        // near-black tile hue is no payoff (BridgeGlyph.signalColor's rule).
        // An app with no honest color at all blooms neutral, not blue
        // (2026-08-10) — a fake brand color is exactly what this payoff
        // shouldn't invent.
        connectHue = BridgeGlyph.glyphTint(for: offer.name)
            ?? DS.brandHue(for: offer.name) ?? DS.neutralBadge
        connectToken += 1
        chrome.flash(BridgeConnect.landingMessage(offer), tone: .success)
    }

    /// Connected, healthy bridges — the count whose 0 → 1 transition is the
    /// store's first-connect milestone.
    private var connectedCount: Int {
        store.bridges.filter { $0.status != .paused }.count
    }

    /// The connected-seat count milestones — quiet count-up toasts, the sibling
    /// of §36v's "N things banked." at the catalog. First-connect is its own
    /// berry-rain moment; these mark the collection filling out.
    private static let connectMilestones = [5, 10, 25]

    /// The connected bridges' names, sorted — a stable value whose changes name
    /// exactly which seat filled or emptied.
    private var connectedNames: [String] {
        store.bridges.filter { $0.status != .paused }.map(\.name).sorted()
    }

    /// Connectable-but-not-connected offers per category, for a given set of
    /// connected names — the "still addable" count whose fall to zero completes
    /// a shelf.
    private func addableByCategory(connected: Set<String>) -> [String: Int] {
        var out: [String: Int] = [:]
        for offer in BridgeCatalog.offers
        where offer.connectable && !connected.contains(offer.name) {
            out[category(of: offer), default: 0] += 1
        }
        return out
    }

    /// A category's identity color — its exemplar's glyph color, for the
    /// shelf-completed glow.
    private func categoryColor(_ name: String) -> Color {
        let exemplar = Self.categories.first { $0.name == name }?.exemplar ?? name
        return BridgeGlyph.color(for: exemplar)
    }

    /// One connect/disconnect reconciled into the three store-shape moments:
    /// the just-connected row's promote lift, the count milestones, and a
    /// completed shelf's glow. All read from the name delta so every connect
    /// path (one-tap AND setup-screen) lands here identically.
    private func handleConnectChange(old: [String], new: [String]) {
        let added = Set(new).subtracting(Set(old))
        // (4) Promote-lift the row that just took its seat — it stays in the
        // list it was on, now wearing its state (§1033).
        if let name = added.first {
            justConnectedName = name
            connectLiftToken += 1
        }
        // (2) Count milestones — fire the highest newly-crossed threshold once.
        if new.count > old.count {
            let crossed = Self.connectMilestones
                .filter { $0 <= new.count && $0 > connectMilestoneReached }
                .max()
            if let t = crossed {
                connectMilestoneReached = t
                chrome.flash("\(t) apps connected.", tone: .success)
            }
        }
        // (1) Shelf completed — a category whose last addable app just
        // connected glows in its own color and the toast names the set. Only a
        // real set (≥2 connectable offers) earns the moment; a lone-app
        // category completing is trivial.
        let before = addableByCategory(connected: Set(old))
        let after = addableByCategory(connected: Set(new))
        for cat in Self.categories {
            guard (before[cat.name] ?? 0) > 0, (after[cat.name] ?? 0) == 0 else { continue }
            let total = BridgeCatalog.offers.filter {
                $0.connectable && category(of: $0) == cat.name
            }.count
            guard total >= 2 else { continue }
            shelfComplete[cat.name, default: 0] += 1
            chrome.flash("\(cat.name) — all connected.", tone: .success)
        }
    }


    /// Consume `HomeRoute.openConnect` — the rooms tray's door to Accounts
    /// (prd §930, §958) — and land on the whole catalogue. Cleared on read.
    private func landRequestedSection() {
        guard route.openConnect else { return }
        route.openConnect = false
        scope = CatalogScope(name: nil)
    }

    // MARK: - Search field (prd §200 — leads the page, not a nav-bar pull-down)

    /// What you have: connected or broken, never paused (`connectedNames`'s
    /// rule, so the box's counts and Sources' agree).
    private func isAdded(_ entry: Ranked) -> Bool {
        guard let bridge = entry.bridge else { return false }
        return bridge.status != .paused
    }

    private var searchField: some View {
        // The slab rung, spelled as itself. It used to say
        // `height: DS.Radius.widget + 36` — a corner-radius token standing in
        // for a height, arriving at exactly `DSSlab.height` by coincidence
        // rather than by agreement (2026-08-28).
        // "Search", not "Search accounts" (prd §796): the title above already
        // says accounts, and three words now share the row with this field.
        DSSlabField(placeholder: String(localized: "Search"),
                    text: $query, actionLabel: "",
                    focus: $searchFocused,
                    glyph: "magnifyingglass", clearable: true,
                    size: .slab, submitLabel: .search, action: {})
    }

    // MARK: - The catalog list (prd §518 — a directory, not a wall)

    /// Which slice of the catalog is on screen. `nil` is **All** — every
    /// category, in catalog order, each under its own header.
    ///
    /// ONE stored property on purpose. `DSScopeTiles` compares `active`
    /// against the strip's own elements with `==`, so a scope that ALSO stored
    /// its count would stop equalling its chip the moment an app connected —
    /// the selected fill would silently drop off the strip on the one event
    /// this screen exists to produce. Label and summary are DERIVED.
    private struct CatalogScope: DSTileScope {
        /// nil is All; otherwise a `BridgeCatalog.categories` name.
        let name: String?

        /// A sentinel no category can collide with — category names are
        /// ordinary words, and an id shared with a real chip makes both the
        /// strip's selection and its `scrollTo` ambiguous.
        var id: String { name ?? "\u{1}all" }

        var label: String { name ?? String(localized: "All") }

        /// The dock's own glyph for the category, and its "All" glyph for
        /// All — the strip is the dock's tiles (user, 2026-09-17).
        var glyph: String { CategoryFold.glyph(for: name ?? "All") }

        /// The tooltip and the accessibility clause. A chip's short noun is
        /// learnable but not self-explaining, and the useful second fact here
        /// is how much sits behind it.
        var summary: String {
            guard let name else { return String(localized: "Every app, A to Z") }
            let n = Self.counts[name] ?? 0
            return n == 1 ? String(localized: "1 app") : String(localized: "\(n) apps")
        }

        /// Counted ONCE off the static catalog, not per chip per body pass.
        /// Counts every offer the section will DRAW, `Soon` included — a
        /// header reading 7 over a list of 8 is the small wrongness that costs
        /// a screen its credibility.
        private static let counts: [String: Int] = {
            var out: [String: Int] = [:]
            for offer in BridgeCatalog.offers {
                out[BridgeCatalog.category(of: offer), default: 0] += 1
            }
            return out
        }()
    }

    /// The page's top: on the phone the chips ride the bottom capsule (prd
    /// §960), and a pick there scrolls the list back to its start.
    private static let topAnchor = "catalog-top"

    /// All, then every category with something behind it.
    ///
    /// A category with no offers never gets a chip — a control that filters to
    /// an empty list is the dead control §83 bans, and a strip is the one place
    /// on this screen where that stays invisible until somebody taps it.
    private var scopes: [CatalogScope] {
        // All, then the categories A–Z (prd §1138, user: "we should
        // alphabetize them"): they are the box's counts now, and a room's
        // tiles read A–Z (§995), not the dock's order (§1050j).
        [CatalogScope(name: nil)] + Self.categories
            .filter { cat in ranked.contains { category(of: $0.offer) == cat.name } }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { CatalogScope(name: $0) }
    }

    /// **THE CATEGORIES ARE THE BOX (prd §1138), A GLYPH AND A NAME (§1142,
    /// user: "do we just get rid of the count and use glyph and category on
    /// Apps?").** A–Z, then the categories with something left to add, A–Z;
    /// pressed, the list below is that category, and pressing the picked one
    /// again is A–Z. No figure: a count of apps you don't have is the
    /// catalogue's size, and every figure in the app means yours.
    private var categoryBox: some View {
        let cats = scopes
        let columns = min(5, max(3, (cats.count + 1) / 2))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns),
                         spacing: DS.Space.s2) {
            ForEach(cats) { cat in
                DSCountTile(count: nil, label: cat.name ?? String(localized: "A–Z"), glyph: cat.glyph,
                            isOn: scope == cat) {
                    withAnimation(DS.Motion.standard) {
                        scope = scope == cat ? CatalogScope(name: nil) : cat
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
               maxHeight: DSRoomChassis.leadBox)
        .dsRoomHeadBlock()
    }

    /// Search on the phone is the bar's verb; where the rail stands there is
    /// no bar, so the field stands under the box.
    private var searchShown: Bool {
        !DSScopeDock<AppsBarScope>.atBottom(sizeClass) || searchOpen || !query.isEmpty
    }

    /// A one-shot entrance — a tile fades and rises into place, staggered by
    /// its position (delight, 2026-07-12, kept from the old shelf). Off under
    /// Reduce Motion.
    private struct StockEntrance: ViewModifier {
        let index: Int
        @State private var shown = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        func body(content: Content) -> some View {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 12)
                .onAppear {
                    guard !reduceMotion else { shown = true; return }
                    withAnimation(DS.Motion.standard.delay(Double(min(index, 8)) * 0.05)) {
                        shown = true
                    }
                }
        }
    }

    /// The catalog's sections for the active scope: All gives every category in
    /// the ruled catalog order, a picked category gives just its own.
    ///
    /// The SECTION order is `BridgeCatalog.categories`' — never the ranking's,
    /// and never the strip's tap history. §201 and §322 set that order band by
    /// band, it is the single source of truth the agent's `category:` ask
    /// reads, and a catalog that reshuffled between visits reads as broken
    /// (`CategoryVenueSwitcher`'s own display-order rule, one screen over).
    ///
    /// The APPS inside a section are alphabetical BY NAME (user ruling,
    /// 2026-08-29 — "that makes it easier for user"), not `ranked`'s tier
    /// order: a directory you can scan for a known app by its name beats a
    /// status-triage ordering that reshuffles as bridges connect and
    /// disconnect. `ranked`'s tiers still decide everything ELSE on the row
    /// (the Fix/Connect/Open verb, the attention dot) — only the ORDER within a section is re-sorted here.
    private var listSections: [(name: String, apps: [Ranked])] {
        Self.categories.compactMap { cat in
            if let picked = scope.name, picked != cat.name { return nil }
            let apps = ranked
                .filter { category(of: $0.offer) == cat.name }
                .sorted { Self.azBefore($0.offer.name, $1.offer.name) }
            return apps.isEmpty ? nil : (cat.name, apps)
        }
    }

    /// The catalog — one file of rows under category headers (prd §518),
    /// EXCEPT under All (user ruling, 2026-08-29), which flattens to one
    /// alphabetical directory with no headers at all — see `flatCatalogList`.
    ///
    /// `LazyVStack` over the SECTIONS, each section's rows eager inside its own
    /// card. Making the rows lazy instead would mean giving up the card that
    /// groups them, and the largest section is 19 rows, which costs nothing.
    /// What the laziness buys is the other nine sections not building until you
    /// reach them — the wall had this backwards, an eager `ForEach` over bands
    /// wrapping a lazy grid inside each.
    private var catalogList: some View {
        Group {
            if scope.name == nil {
                flatCatalogList
            } else {
                LazyVStack(alignment: .leading, spacing: DS.Space.s6) {
                    ForEach(listSections, id: \.name) { section in
                        categorySection(section.name, apps: section.apps)
                    }
                }
            }
        }
        // A connect re-sorts its row into the connected tier — the list closes
        // the gap smoothly instead of snapping.
        .animation(DS.Motion.standard, value: store.bridges.count)
    }

    /// Every connectable/Soon offer, alphabetical by name, no category
    /// headers — the All chip's own directory (user ruling, 2026-08-29: "if
    /// a user clicks the 'all' chip should it show all apps in alphabetical
    /// order, not by category?"). A category chip still narrows to that
    /// category's own headed section (`categorySection`) — the browse-by-kind
    /// question ("what's in Wallet") is answered THERE now, not under All.
    private var allAppsSorted: [Ranked] {
        ranked.sorted { Self.azBefore($0.offer.name, $1.offer.name) }
    }

    /// A–Z, with a name that starts with a digit AFTER Z, as Contacts files
    /// it under "#" (user, 2026-10-05: "0xBow Privacy Pools" led the list
    /// only because a digit sorts before every letter).
    nonisolated static func azBefore(_ a: String, _ b: String) -> Bool {
        let aDigit = a.first?.isNumber == true, bDigit = b.first?.isNumber == true
        if aDigit != bDigit { return bDigit }
        return a.localizedStandardCompare(b) == .orderedAscending
    }

    /// The three a first run leads with (user, 2026-09-20): the one-tap grant
    /// that always has rows, the one that brings pictures, and builders'
    /// money. Files was weighed for Photos and declined on the phone — a
    /// folder pick there is a vague ask and a poor pick is an empty room.
    /// ALPHABETICAL, like the directory under it: an order nobody has to
    /// defend, and it happens to put the two one-tap grants ahead of the one
    /// that wants an address pasted.
    private static let startHere = ["Calendar", "Photos", "Wallet"]

    /// Drawn ONLY while nothing is connected — the same fact that seeds this
    /// screen to Connect, so there is no counter and no dismissal to keep. The
    /// first connect spends it, and a finished row is never refilled: a block
    /// that tops itself up is a promo shelf (the carousel §738 removed).
    /// Resolved through `ranked`, so a name this platform's catalogue lacks
    /// draws no row rather than a dead one (§83).
    private var startHereRows: [Ranked] {
        guard connectedCount == 0 else { return [] }
        return Self.startHere.compactMap { name in ranked.first { $0.offer.name == name } }
    }

    private var flatCatalogList: some View {
        let lead = startHereRows
        return VStack(alignment: .leading, spacing: DS.Space.s6) {
            if !lead.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    listHeader(Text("Start here"), count: nil)
                    VStack(spacing: DS.Space.s1) {
                        ForEach(lead) { entry in appRow(entry) }
                    }
                }
            }
            VStack(spacing: DS.Space.s1) {
                ForEach(Array(allAppsSorted.enumerated()), id: \.element.id) { i, entry in
                    appRow(entry).modifier(StockEntrance(index: i))
                }
            }
        }
    }

    /// `categorySection`'s header, without the shelf flash: a name, then what
    /// it holds.
    private func listHeader(_ name: Text, count: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            name
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
            if let count {
                Text(count.formatted())
                    .dsText(.subhead12)
                    .monospacedDigit()
                    .foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    /// One category's page: what is left to add in it (prd §1142), A–Z. The
    /// box names the category, so the list draws no header of its own.
    private func categorySection(_ name: String, apps: [Ranked]) -> some View {
        VStack(spacing: DS.Space.s1) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { i, entry in
                appRow(entry).modifier(StockEntrance(index: i))
            }
        }
        .landFlash(shelfComplete[name] ?? 0, tint: categoryColor(name))
    }

    /// The seat id a cell should open as a ROOM rather than push, or nil.
    ///
    /// Tier 2 ONLY — a tier-0 cell is a BROKEN seat whose tap means Fix, and
    /// fixing happens in the manager. Routing that to a room would be a
    /// control that looks like it repairs something and doesn't (§83).
    @ViewBuilder
    private func catalogTap<Label: View>(destination: HomeRoute.Node?,
                                         action: (() -> Void)?,
                                         @ViewBuilder label: () -> Label) -> some View {
        if let action {
            Button(action: action) { label() }
        } else if let destination {
            NavigationLink(value: destination) { label() }
        } else {
            label()
        }
    }

    /// What tapping this row does — the SAME call the capsule makes, shared so
    /// the two halves cannot drift apart again.
    /// Wrapped in `fromAccountsList` (prd §876): where Accounts has a pane, a
    /// row REPLACES the page beside the list rather than stacking onto it.
    private func rowAction(_ entry: Ranked) -> (() -> Void)? {
        guard let open = rowOpen(entry) else { return nil }
        return { route.fromAccountsList(open) }
    }

    /// **A DEVNET OPENS ITS ROOM, connected or not (user, 2026-09-28: "watch
    /// addresses is kind of confusing").** Its account page led with a watch
    /// field and addresses worth watching, so making your own account meant
    /// watching a stranger first, then finding Activity, then Home. The room
    /// always draws now, and its first act is Create account.
    private static let devnetRooms: Set<String> = [FramesIdentity.source]

    /// **A CONNECTED ROW OPENS ITS ACCOUNT PAGE (prd §1050f, reversing
    /// §1040's land-in-room and §1033's status row).** An app's settings live
    /// here and nowhere else: no room draws a sliders disc, and a merged room's
    /// apps have no room of their own to land in. So every connected row is a
    /// door again, chevron and all.
    private func rowOpen(_ entry: Ranked) -> (() -> Void)? {
        if entry.tier == 0 || entry.tier == 2, let bridge = entry.bridge {
            let destination = BridgeRouter.destination(forID: bridge.id)
            return { DSHaptic.tap(); route.openAccount(destination) }
        }
        // A devnet row with no account yet still opens its room, where its
        // own create verb lives.
        if Self.devnetRooms.contains(entry.offer.name) {
            let room = entry.offer.name
            return { DSHaptic.tap(); route.path = []; chrome.sourceRequest = room }
        }
        switch entry.tier {
        case 1:
            // **AN APP THAT NEEDS ONLY A NAME OPENS ITS TRAY, HERE (prd
            // §1119).** RSS, YouTube, npm: nothing to sign in to, so a first
            // follow IS the connect, and a page asking "what to follow?" was
            // a detour. The tray rises over the catalogue with the app
            // picked; a follow lands the person in the room that lists it.
            if let room = FollowingReading.trackRoom(forSeat: entry.offer.name) {
                let seat = entry.offer.name
                return { DSHaptic.tap(); trackPick = TrackPick(room: room, seat: seat) }
            }
            // **AN APP NOT CONNECTED OPENS ITS PAGE TOO (prd §1050h)**, the
            // page its Connect stands on; a one-tap seat with no page still
            // fires the system ask where it stands.
            if entry.offer.needsSetup {
                return { route.openSetup(forOffer: entry.offer.name) }
            }
            if let destination = BridgeRouter.destination(forOffer: entry.offer.name) {
                return { DSHaptic.tap(); route.openAccount(destination) }
            }
            return { attemptConnect(entry.offer) }
        default:
            return nil   // Soon — the capsule already says it
        }
    }

    /// One app — icon, name, honest subline, and its verb as the row's last
    /// word (prd §746; an action capsule until then).
    ///
    /// The catalog's ONE cell since prd §518, where it had been the search
    /// results' alone and the wall drew a separate `appTile` beside it. That
    /// split is what a list ends: the row has room for the tagline and the
    /// live status line a 4-across tile had to push onto the screen behind it,
    /// so the catalog now says what an app DOES before you tap it.
    ///
    /// The row tap runs `rowAction` — setup for an app you could add, the room
    /// or manager for one that's connected (prd §641; it opened a product page
    /// until that was deleted). A connected row wears the status dot the old
    /// strip carried. No rank number: a category is not a leaderboard.
    private func appRow(_ entry: Ranked) -> some View {
        let soon = entry.tier == 3
        let isConnected = entry.tier == 0 || entry.tier == 2
        let destination: HomeRoute.Node? = isConnected && entry.bridge != nil
            ? .bridge(BridgeRouter.destination(forID: entry.bridge!.id))
            : nil
        return HStack(spacing: DS.Space.s3) {
            catalogTap(destination: destination, action: rowAction(entry)) {
                HStack(spacing: DS.Space.s3) {
                    // No status dot on the icon (user, 2026-09-24): the
                    // subline says the state, in the state's own tone.
                    BridgeIcon(name: entry.offer.name, size: DS.Mark.tile)
                        .saturation(soon ? 0 : 1)
                        .opacity(soon ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        // Regular, as every row title is (prd §764).
                        Text(entry.offer.name)
                            .dsText(.body17)
                            .foregroundStyle(soon ? DS.textSecondary : DS.textPrimary)
                            .lineLimit(1)
                        // The qualifier badge died here (user, 2026-07-16:
                        // "'no account' repeatedly under the names... extra
                        // text the user doesn't need") — every addable row
                        // wearing one made it wallpaper. The cost lives in the
                        // CAPSULE's verb since §653 (Allow / Sign in / Add key
                        // / Import), the slot the row already had.
                        //
                        // A connected row's subline is its live status line
                        // ("3 games in") — rolled up through the numeric-text
                        // count-up so the proof arrives rather than sitting
                        // (the same grammar the setup screen's result wears).
                        // The other tiers stay plain, localizable copy.
                        // No line when an addable app has nothing the name
                        // doesn't already say (prd §1148).
                        if !subline(entry).isEmpty {
                            Group {
                                if entry.tier == 2 {
                                    CountUpText(text: subline(entry))
                                } else {
                                    Text(LocalizedStringKey(subline(entry)))
                                }
                            }
                            .dsText(.subhead12)
                            .foregroundStyle(sublineColor(entry))
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: DS.Space.s2)
                    // THE VERB IS THE ROW'S LAST WORD (prd §746) — the
                    // capsule that sat beside the row ran the same
                    // `rowAction`, so it was one act drawn twice.
                    if let rowVerb = verb(entry) {
                        DSPushRowTrail(verb: rowVerb)
                    } else if entry.tier == 2, entry.bridge != nil {
                        // A connected account with no room is a door, and the
                        // chevron says so; one with a room is a status and
                        // draws none (§1033).
                        DSPushRowTrail()
                    }
                }
                .contentShape(Rectangle())
            }
            // A tactile press-pop when you tap into an app (delight, 2026-07-12)
            // — the row springs slightly under the finger instead of a flat
            // .plain tap. Keeps the plain look, adds the give. A STATUS row
            // takes the row's own press (`RowPress`, prd §965) instead: it
            // lands in its room, and a status should not spring like a verb
            // (prd §1040).
            // Every row is a door or a verb now (prd §1050f): the spring.
            .buttonStyle(PressSpring())
            // (The long-press peek retired with the product page, prd §641 —
            // it painted a `StorePreview` doc only 74 of 97 offers had, and a
            // hand-authored preview of a generated surface reads as a ceiling
            // on a seat that has none: Wallet's was a treemap and two rows for
            // a seat that lands approvals, delegation warnings, poisoned
            // transfers, gas, six protocols and the Safe queue.)
        }
        // NO HORIZONTAL INSET OF ITS OWN (prd §590). This `s4` held the row
        // off the card's edge; with the card gone it was a second page inset
        // stacked on the scroll content's, putting a row's words 30pt in while
        // the search field above sat at 15. The §583 finding, one screen over:
        // an object around a block hides the block's own misalignment.
        .padding(.vertical, DS.Space.s2)
        // The just-connected row lifts as the list re-sorts it into its
        // connected seat — a promotion you can feel, not a silent re-order.
        .connectPromote(isTarget: entry.offer.name == justConnectedName, token: connectLiftToken)
    }

    /// The line under a row's name says its STATE in colour (prd §811, user:
    /// "if they are connected already it should all be green, or yellow for
    /// needs fixing"): every connected account's live line is green, one that
    /// needs fixing wears attention, and an app you could add keeps the grey
    /// of a tagline. No third state: a stale but working seat is still
    /// connected and still green.
    private func sublineColor(_ entry: Ranked) -> Color {
        switch entry.tier {
        case 0:  DS.attentionInk
        // Connected reads grey, as Settings' own rows do (prd §1149,
        // reversing §811's green): only a word that needs you takes a hue.
        case 2:  DS.textTertiary
        default: DS.textTertiary
        }
    }

    /// Sublines are honest states or the tagline — never marketing fluff.
    private func subline(_ entry: Ranked) -> String {
        switch entry.tier {
        case 0:  "Needs reconnecting"
        case 2:  entry.bridge?.statusLine ?? "Connected"
        default: entry.offer.tagline
        }
    }

    /// The verb a wallet-riding seat wears while it is dark (prd §515) — nil
    /// for every ordinary bridge, which keeps Connect.
    private func walletSeatVerb(_ offer: BridgeCatalog.Offer) -> RowVerb? {
        guard let id = BridgeRouter.id(forOffer: offer.name),
              WalletSeatStanding.rides(id: id) else { return nil }
        return RowVerb(WalletSeatStanding.verb(
            watched: WalletStore.shared.addresses.count))
    }

    /// The row's verb — the row's LAST WORD since prd §746, where it had been
    /// a capsule beside the row running the same `rowAction`. Two controls for
    /// one act, and the louder of the two was the pill, repeated down every
    /// row of the catalogue. nil draws no trailing word at all (a connected
    /// tier whose bridge record is missing has nowhere to go).
    private func verb(_ entry: Ranked) -> RowVerb? {
        switch entry.tier {
        case 0:
            // Broken connection — Fix opens management, where Reconnect lives.
            return entry.bridge == nil ? nil : .fix
        case 2:
            // No word (prd §767): the row's chevron is the door, and a word on
            // every connected row carries nothing. The trail draws it.
            return nil
        case 1:
            if entry.offer.needsSetup {
                // Setup bridges collect input first — Connect raises their
                // form (a pasted key, a sign-in) or pushes their manager (a
                // watch list); the connect happens there, with proof (§218).
                //
                // Except a WALLET-RIDING seat (prd §515), which has no connect
                // to make: its sweep runs for every watched address whether the
                // seat exists or not, so the word is `Watch` while there is no
                // address and `Automatic` once there is. The destination does
                // not move — every one of these still has somewhere real to go
                // (its own screen, or the addresses it reads) — only the claim
                // the word makes changes.
                //
                // Otherwise THE VERB SAYS THE PRICE (prd §653): Sign in, Add
                // key, Import, or Connect for the free ones — `Offer.mode`,
                // the same fact the setup screen's chip draws.
                //
                // EXCEPT A PAUSED SEAT, which lands in this tier too (see
                // `rankedAll`) and has already paid the price: a paused Stripe
                // wearing "Add key" promises a step the screen it opens does
                // not ask for — it says "Update" — and a paused Dropbox
                // wearing "Sign in" is the §83 claim-about-nothing. Connect is
                // the word that makes no specific claim, which is what this
                // row said before §653. "Resume" was weighed and DECLINED
                // (user, 2026-09-08: "i like connect better") — a paused seat
                // is one tap from reading again, and a verb of its own for a
                // state that resolves itself is furniture.
                return walletSeatVerb(entry.offer)
                    ?? (entry.bridge == nil ? RowVerb(mode: entry.offer.mode) : .connect)
            }
            // One system sheet — the tap IS the grant, so the word is
            // Allow (§653), not a Connect that hides which kind it is.
            return .allow
        default:
            return .soon
        }
    }

    #if DEBUG
    enum AppsProbe: Identifiable, Hashable {
        case wallet
        var id: String {
            switch self { case .wallet: "wallet" }
        }
    }
    #endif
}


// MARK: - Deck pan (UIKit)





extension String: @retroactive Identifiable {
    public var id: String { self }
}

/// The Apps catalogue's bar: Search alone, its filters being the box's
/// categories (prd §1138).
enum AppsBarScope: String, Identifiable, Hashable, Sendable {
    case search
    var id: String { rawValue }
    var label: String { String(localized: "Search") }
    var summary: String { String(localized: "Find an app by name") }
}
