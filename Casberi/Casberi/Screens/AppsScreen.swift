import SwiftUI
import SwiftData

/// Apps — ONE catalog (ruling 2026-07-10: the Connected strip died; the feed
/// is where connected apps live, and this page is where you add and manage
/// them from a single grid). Every app sits in its category shelf; a
/// connected app's tile wears its status dot and opens MANAGEMENT, a
/// broken one wears Fix, an available one wears Connect, a coming one Soon.
/// The strip's hairline died with it — the app now draws no lines at all.
///
/// LAYOUT LAW (the doc's): no fixed heights anywhere — every card, pill, and
/// row sizes to its content plus token padding (minHeight only where a target
/// needs it). Capsule verbs are honest: Connect / Pair / Fix / Open / Soon.
struct AppsScreen: View {
    @Environment(ShellChrome.self) private var chrome
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var pairing = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
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
    /// Yours | All (user ruling 2026-09-06, the Accounts door): Yours shows
    /// only connected accounts, still under the same chips; All is the whole
    /// catalog with connected rows wearing their state in place. Seeded once
    /// per mount from whether anything is connected at all — a first run has
    /// nothing to manage, so it opens on the catalog.
    @State private var section: AccountsHeld = .all
    @State private var scopeSeeded = false
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
        /// Connected, healthy or broken: the row belongs on Manage.
        var isHeld: Bool { tier == 0 || tier == 2 }
    }

    private func actionable(_ offer: BridgeCatalog.Offer) -> Bool {
        offer.connectable
    }

    /// ONE ranked list for the whole catalog (2026-07-10, strip removed):
    /// tier 0 = connected but broken (Fix leads — it needs you), tier 1 =
    /// ready to connect, tier 2 = connected and healthy (Open → manage),
    /// tier 3 = coming (Soon). Every app appears exactly once.
    /// `rankedAll` narrowed to the Yours | All scope. Everything downstream
    /// (chips, sections, search, the attention dots) reads THIS, so a category
    /// with nothing connected drops its chip under Yours rather than filtering
    /// to an empty list behind a selected chip.
    ///
    /// The two lists SPLIT the catalogue (prd §812, user: "should it operate by
    /// having only the items you have not connected?"): Manage holds what you
    /// have connected, Connect only what you have not. Connect is a verb, so a
    /// row there always has something to do; an account is on exactly one of
    /// the two. Search reads `rankedAll`, so it finds an app on either side.
    private var ranked: [Ranked] {
        section == .yours
            ? rankedAll.filter(\.isHeld)
            : rankedAll.filter { !$0.isHeld }
    }

    private var rankedAll: [Ranked] {
        BridgeCatalog.offers.compactMap { offer in
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
                        // The screen's name, in the content (prd §767).
                        DSScreenHead(title: Text("Accounts"))
                        // The search field leads the page (user ruling,
                        // 2026-07-23: "make sure the search bar is at the
                        // top") — a visible slab, not the nav bar's
                        // pull-down `.searchable` field, which the App Store
                        // shape hid a scroll below the fold.
                        // Search, then Manage | Connect | Settings (user, prd
                        // §796): the face in the dock opens THIS screen, and
                        // Settings is its third section, not a screen of its own.
                        // The three sections are big words and search has
                        // its own row (user, 2026-09-17: search sharing a
                        // row with three chips left it too short to type in,
                        // and the head read as grey words on grey glass).
                        VStack(alignment: .leading, spacing: DS.Space.s4) {
                            scopeSegment
                            searchField
                        }
                        sections(proxy)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s4)
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
                        proxy.scrollTo(Self.scopeAnchor, anchor: .top)
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
        if !query.isEmpty {
            searchResults
        } else if section == .settings {
            SettingsRows()
        } else {
            scopeStrip(proxy)
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
        .onAppear {
            // Seed the connect-count milestone to the highest already-passed
            // threshold so arriving past one never fires a late toast.
            let passed = Self.connectMilestones.filter { $0 <= connectedCount }.max() ?? 0
            if passed > connectMilestoneReached { connectMilestoneReached = passed }
            if !scopeSeeded {
                scopeSeeded = true
                section = connectedCount > 0 ? .yours : .all
            }
            // The three direct doors to Settings — ⌘, on the Mac,
            // `casberi://settings` and `-openSettings YES` — present this
            // screen and leave this request (prd §796); consumed here, after
            // the seed, so it wins.
            if route.openSettings {
                route.openSettings = false
                section = .settings
            }
        }
        // The store's shape after any connect/disconnect — drives the promote
        // lift (which row just took its seat), the count milestones, and the
        // shelf-completed glow. Keyed on the NAMES (not just the count) so the
        // just-connected row can be identified.
        .onChange(of: connectedNames) { old, new in
            handleConnectChange(old: old, new: new)
        }
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
        .navigationTitle(Text("Accounts"))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $pairing) { PairClientSheet() }
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
                if let entry = ranked.first(where: { $0.offer.name == name }) {
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
            if UserDefaults.standard.bool(forKey: "openPair") { pairing = true }
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
        // (4) Promote-lift the row that just took its seat. Since §812 that
        // seat is on Manage, not further down the same list, so a connect
        // made from Connect takes the switcher with it: the row leaves the
        // list you were on and lifts in on the one it joined.
        if let name = added.first {
            if section == .all { section = .yours }
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


    // MARK: - Manage | Connect (the Accounts door's scope, 2026-09-06; renamed from Yours | All, prd §793)

    /// Two words, both always visible, the chosen one filled — never a lone
    /// toggle whose off state has to be inferred ("a gray Yours isn't
    /// clear"), and never a third chip in the category strip, whose first
    /// chip is A–Z on purpose so this pair can say All without a collision.
    /// Flipping it resets the category to A–Z: a chip picked under one scope
    /// may have no rows under the other, and a selected chip over an empty
    /// list reads as a broken screen.
    private var scopeSegment: some View {
        // Three words at the lead's words rung, the chosen one in primary and
        // the others tertiary (user, 2026-09-17: "manage and connect big …
        // settings should be a third word big there too"). A word, not a
        // pill: §746 allows two pills, and this is neither a choice among
        // filters nor a fact, it is which page of the screen you are on.
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            ForEach(AccountsHeld.allCases) { picked in
                let isOn = picked == section
                Button {
                    guard !isOn else { return }
                    DSHaptic.selection()
                    withAnimation(DS.Motion.standard) {
                        section = picked
                        scope = CatalogScope(name: nil)
                    }
                } label: {
                    Text(picked.label)
                        .dsText(.heading24)
                        .foregroundStyle(isOn ? DS.textPrimary : DS.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsHover()
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Which accounts"))
    }

    /// The screen's three sections (prd §796): what you hold, what you could
    /// add, and the app's own settings. Settings is a SECTION and not a door
    /// (user, 2026-09-17: "it should be a button that says settings … or can
    /// it toggle? like manage and connect"): the same switcher, the same
    /// screen, the list below swaps — so the dock's face toggles one screen in
    /// and out, and nothing is pushed.
    private enum AccountsHeld: String, CaseIterable, DSSectionScope {
        // Connect, Manage, Settings (user, 2026-09-20): read left to right
        // it is the journey, and the first word cues the first act. Where the
        // screen OPENS is still the seed's — this is only the reading order.
        case all, yours, settings
        var id: String { rawValue }
        var label: String {
            // "Manage" and "Connect" (user, 2026-09-16, prd §793): what you do
            // on each side — look after what you hold, add what you don't.
            switch self {
            case .yours:    String(localized: "Manage")
            case .all:      String(localized: "Connect")
            case .settings: String(localized: "Settings")
            }
        }
    }

    // MARK: - Search field (prd §200 — leads the page, not a nav-bar pull-down)

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
            guard let name else { return String(localized: "Every account, A to Z") }
            let n = Self.counts[name] ?? 0
            return n == 1 ? String(localized: "1 account") : String(localized: "\(n) accounts")
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

    /// The strip's scroll anchor: a pick pulls the CONTROL to the top, so the
    /// chips stay reachable and the list below them is the thing that changed.
    private static let scopeAnchor = "catalog-scope"

    /// All, then every category with something behind it.
    ///
    /// A category with no offers never gets a chip — a control that filters to
    /// an empty list is the dead control §83 bans, and a strip is the one place
    /// on this screen where that stays invisible until somebody taps it.
    private var scopes: [CatalogScope] {
        // All, then A to Z (user, 2026-09-17). The home dock keeps the ruled
        // wall order (§322); this strip is a directory's index, and the list
        // under it is already alphabetical.
        [CatalogScope(name: nil)] + Self.categories
            .filter { cat in ranked.contains { category(of: $0.offer) == cat.name } }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { CatalogScope(name: $0) }
    }

    /// The chips wearing the attention dot — a category holding a seat that
    /// stopped working (tier 0, the one tier whose verb is Fix).
    ///
    /// This is what a filter strip buys that jump chips could not. Under the
    /// wall a broken seat was findable by scrolling to its band; under a FILTER
    /// it is invisible from every other chip, so the dot is not decoration but
    /// the thing that keeps the filter honest. Never set for All, which draws
    /// every section — there the row itself is already on screen saying it.
    private var troubledScopes: Set<CatalogScope> {
        Set(ranked.filter { $0.tier == 0 }
                  .map { CatalogScope(name: category(of: $0.offer)) })
    }

    /// The category filter: the dock's own tiles, glyph over word, in one
    /// scrolling row (user, 2026-09-17). It was TEXT chips so a strip of
    /// brand marks would not stand over a list of brand marks (prd §518); a
    /// category glyph is not a brand mark, so that reason still holds.
    ///
    /// Hidden below two categories, where a filter narrows nothing.
    @ViewBuilder
    private func scopeStrip(_ proxy: ScrollViewProxy) -> some View {
        let all = scopes
        if all.count > 2 {
            DSScopeTiles(sections: all, active: scope,
                         attention: troubledScopes, strip: true) { picked in
                withAnimation(DS.Motion.standard) {
                    scope = picked
                    proxy.scrollTo(Self.scopeAnchor, anchor: .top)
                }
            }
            .id(Self.scopeAnchor)
        }
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
    /// (the Fix/Connect/Open verb, the attention dot, the `troubledScopes`
    /// filter dot) — only the ORDER within a section is re-sorted here.
    private var listSections: [(name: String, apps: [Ranked])] {
        Self.categories.compactMap { cat in
            if let picked = scope.name, picked != cat.name { return nil }
            let apps = ranked
                .filter { category(of: $0.offer) == cat.name }
                .sorted { $0.offer.name.localizedStandardCompare($1.offer.name) == .orderedAscending }
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
            if section == .yours && ranked.isEmpty {
                // Reachable only by choosing Manage with nothing connected —
                // the seed opens a first run on Connect. One sentence, and the
                // way out is the control the person just used.
                DSEmptyState(headline: DSProse.text("Nothing connected yet"),
                             words: Text("Nothing connected yet. Everything you can add is under Connect."))
                    .padding(.vertical, DS.Space.s4)
            } else if section == .all && ranked.isEmpty {
                // Every app in the catalogue is connected (prd §812): Connect
                // holds only what you have not added, so this is its honest end.
                DSEmptyState(headline: DSProse.text("Everything is connected"),
                             words: Text("Everything is connected."))
                    .padding(.vertical, DS.Space.s4)
            } else if scope.name == nil {
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
        ranked.sorted { $0.offer.name.localizedStandardCompare($1.offer.name) == .orderedAscending }
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
        guard section == .all, connectedCount == 0 else { return [] }
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
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // The directory is named only while something stands above
                // it — `A–Z` because the category chip's own word is already
                // `All`; alone, Connect already says what it holds. Air
                // and a second header separate the two — nothing draws a line.
                if !lead.isEmpty {
                    listHeader(Text("A–Z"), count: allAppsSorted.count)
                }
                VStack(spacing: DS.Space.s1) {
                    ForEach(Array(allAppsSorted.enumerated()), id: \.element.id) { i, entry in
                        appRow(entry).modifier(StockEntrance(index: i))
                    }
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

    /// One category: its name and size, then its apps as rows in a card.
    ///
    /// The header sits ABOVE the card, where the wall's band label sat inside
    /// it — a card full of rows IS a list, so a label inside it reads as the
    /// first row. Sentence case, no eyebrow, and no rule under it (design law:
    /// the app draws no lines at all).
    private func categorySection(_ name: String, apps: [Ranked]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(LocalizedStringKey(name))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                // What the section holds, before you scroll it. Tabular, or
                // the digits shift the name beside them as a connect changes
                // nothing about the count but everything about its width.
                Text(apps.count.formatted())
                    .dsText(.subhead12)
                    .monospacedDigit()
                    .foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
            }
            // Was `s1` — a category heading and its own rows on two edges
            // (prd §590). One edge now, the page's.
            .landFlash(shelfComplete[name] ?? 0, tint: categoryColor(name))
            VStack(spacing: DS.Space.s1) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { i, entry in
                    appRow(entry).modifier(StockEntrance(index: i))
                }
            }
        }
    }

    /// The seat id a cell should open as a ROOM rather than push, or nil.
    ///
    /// Tier 2 ONLY — a tier-0 cell is a BROKEN seat whose tap means Fix, and
    /// fixing happens in the manager. Routing that to a room would be a
    /// control that looks like it repairs something and doesn't (§83).
    private func roomSeat(_ entry: Ranked) -> String? {
        guard entry.tier == 2, let bridge = entry.bridge,
              BridgeRouter.roomSource(forID: bridge.id) != nil else { return nil }
        return bridge.id
    }

    /// A catalog cell's tap. ONE DESTINATION PER ROW (prd §641): until the
    /// product page was deleted a row had two — the row itself pushed
    /// `AppDetailScreen` while the capsule beside it opened setup, so the same
    /// tile meant two things depending on which half of it you hit. Both
    /// halves run `rowAction` now.
    ///
    /// A connected seat with a screen of its own still PUSHES, as a plain
    /// `NavigationLink` value. Everything else is a `Button`: a wallet-riding
    /// seat opens the room its rows land in (`BridgeRouter.roomSource`), which
    /// is a POP and cannot be a link value; an addable seat runs the connect
    /// where it stands. A row with nowhere to go (a Soon offer, whose capsule
    /// already says so) is inert rather than pushing a page that only repeated
    /// the tagline it is sitting on.
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

    private func rowOpen(_ entry: Ranked) -> (() -> Void)? {
        if let id = roomSeat(entry) {
            return { DSHaptic.tap(); BridgeRouter.open(seatID: id, route: route, chrome: chrome) }
        }
        switch entry.tier {
        case 0:
            guard let bridge = entry.bridge else { return nil }
            return { route.pushBridge(BridgeRouter.destination(forID: bridge.id)) }
        case 2:
            guard let bridge = entry.bridge else { return nil }
            return { BridgeRouter.open(seatID: bridge.id, route: route, chrome: chrome) }
        case 1:
            // A seat that needs input goes to its setup page; a one-tap seat
            // has no page to go to and fires the system ask where it stands.
            return entry.offer.needsSetup
                ? { route.openSetup(forOffer: entry.offer.name) }
                : { attemptConnect(entry.offer) }
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
                    Spacer(minLength: DS.Space.s2)
                    // THE VERB IS THE ROW'S LAST WORD (prd §746) — the
                    // capsule that sat beside the row ran the same
                    // `rowAction`, so it was one act drawn twice.
                    if let rowVerb = verb(entry) {
                        DSPushRowTrail(verb: rowVerb)
                    } else if entry.tier == 2, entry.bridge != nil {
                        // A connected account is a door, and the chevron says
                        // so; "Open" in green on every one said nothing (§767).
                        DSPushRowTrail()
                    }
                }
                .contentShape(Rectangle())
            }
            // A tactile press-pop when you tap into an app (delight, 2026-07-12)
            // — the row springs slightly under the finger instead of a flat
            // .plain tap. Keeps the plain look, adds the give.
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
        case 0:  DS.attention
        case 2:  entry.bridge?.status.color ?? DS.confirm
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
