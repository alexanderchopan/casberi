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
    @State private var yoursOnly = false
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

    /// "Because you connected" — connecting one app suggests its natural
    /// neighbours in the story carousel, eyebrowed with the reason. Cheap
    /// adjacency, but it reads as the store knowing you: connect GitHub and
    /// Linear surfaces; connect a Wallet and Tokens/OpenSea/Farcaster do.
    private static let adjacency: [String: [String]] = [
        "GitHub":       ["Linear", "Notion"],
        "Linear":       ["GitHub", "Notion"],
        "Notion":       ["GitHub", "Linear"],
        "Wallet":       ["Tokens", "OpenSea", "Farcaster"],
        "Tokens":       ["Wallet", "OpenSea"],
        "OpenSea":      ["Wallet", "Tokens"],
        "Farcaster":    ["Bluesky", "Wallet"],
        "Bluesky":      ["Farcaster"],
        "Apple Health": ["Strava"],
        "Strava":       ["Apple Health"],
        "Readwise":     ["Kindle", "RSS"],
        "Reddit":       ["YouTube"],
        "Gmail":        ["Calendar"],
        "Photos":       ["Apple Notes"],
    ]

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
    /// `rankedAll` narrowed to the Yours | All scope. Everything downstream
    /// (chips, sections, search, the attention dots) reads THIS, so a category
    /// with nothing connected drops its chip under Yours rather than filtering
    /// to an empty list behind a selected chip.
    private var ranked: [Ranked] {
        yoursOnly ? rankedAll.filter { $0.tier == 0 || $0.tier == 2 } : rankedAll
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
                        // The search field leads the page (user ruling,
                        // 2026-07-23: "make sure the search bar is at the
                        // top") — a visible slab, not the nav bar's
                        // pull-down `.searchable` field, which the App Store
                        // shape hid a scroll below the fold.
                        HStack(spacing: DS.Space.s2) {
                            searchField
                            scopeSegment
                        }
                        if query.isEmpty {
                            scopeStrip(proxy)
                            catalogList
                        } else {
                            searchResults
                        }
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s4)
                    .padding(.bottom, ShellMetrics.bottomInset)
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
                yoursOnly = connectedCount > 0
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
        .dsScreenTitle("Accounts")
        .sheet(isPresented: $pairing) { PairClientSheet() }
        #if DEBUG
        .navigationDestination(item: $probe) { p in
            switch p {
            case .wallet: WalletScreen()
            case .app(let name):
                if let offer = BridgeCatalog.offers.first(where: { $0.name == name }) {
                    AppDetailScreen(offer: offer)
                }
            }
        }
        #endif
        .onAppear {
            // A tile on the empty feed's pile landed here wanting its
            // product page — same double-push the `-openApp` probe proved.
            // Resolve before pushing: navigationDestination's `if let` falls
            // through to EmptyView, so an unresolvable name (a renamed offer
            // outrunning the pile array) would push a blank screen.
            if let name = route.openOffer {
                route.openOffer = nil
                if BridgeCatalog.offers.contains(where: { $0.name == name }) {
                    route.pushAppDetail(name)
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
            if let name = UserDefaults.standard.string(forKey: "openApp") { probe = .app(name) }
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
        return ranked.filter { entry in
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
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
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
        chrome.flash(BridgeConnect.landingMessage(offer.name), tone: .success)
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
        // (4) Promote-lift the row that just took its seat.
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


    // MARK: - Yours | All (the Accounts door's scope, 2026-09-06)

    /// Two words, both always visible, the chosen one filled — never a lone
    /// toggle whose off state has to be inferred ("a gray Yours isn't
    /// clear"), and never a third chip in the category strip, whose first
    /// chip is A–Z on purpose so this pair can say All without a collision.
    /// Flipping it resets the category to A–Z: a chip picked under one scope
    /// may have no rows under the other, and a selected chip over an empty
    /// list reads as a broken screen.
    private var scopeSegment: some View {
        HStack(spacing: 2) {
            scopeSegmentHalf(String(localized: "Yours"), on: yoursOnly) { yoursOnly = true }
            scopeSegmentHalf(String(localized: "All"), on: !yoursOnly) { yoursOnly = false }
        }
        .padding(2)
        .background(DS.fillFaint, in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Which accounts"))
    }

    private func scopeSegmentHalf(_ word: String, on: Bool, act: @escaping () -> Void) -> some View {
        Button {
            guard !on else { return }
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) {
                act()
                scope = CatalogScope(name: nil)
            }
        } label: {
            Text(word)
                .dsText(.label12)
                .foregroundStyle(on ? Color.white : DS.textSecondary)
                .padding(.horizontal, DS.Space.s3)
                .frame(minHeight: 32)
                .background(on ? DS.tint : Color.clear, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Search field (prd §200 — leads the page, not a nav-bar pull-down)

    private var searchField: some View {
        // The slab rung, spelled as itself. It used to say
        // `height: DS.Radius.widget + 36` — a corner-radius token standing in
        // for a height, arriving at exactly `DSSlab.height` by coincidence
        // rather than by agreement (2026-08-28).
        DSSlabField(placeholder: String(localized: "Search accounts"),
                    text: $query, actionLabel: "",
                    focus: $searchFocused,
                    glyph: "magnifyingglass", clearable: true,
                    size: .slab, submitLabel: .search, action: {})
    }

    // MARK: - The catalog list (prd §518 — a directory, not a wall)

    /// Which slice of the catalog is on screen. `nil` is **All** — every
    /// category, in catalog order, each under its own header.
    ///
    /// ONE stored property on purpose. `DSSectionSwitcher` compares `active`
    /// against the strip's own elements with `==`, so a scope that ALSO stored
    /// its count would stop equalling its chip the moment an app connected —
    /// the selected fill would silently drop off the strip on the one event
    /// this screen exists to produce. Label and summary are DERIVED.
    private struct CatalogScope: DSSectionScope {
        /// nil is All; otherwise a `BridgeCatalog.categories` name.
        let name: String?

        /// A sentinel no category can collide with — category names are
        /// ordinary words, and an id shared with a real chip makes both the
        /// strip's selection and its `scrollTo` ambiguous.
        var id: String { name ?? "\u{1}all" }

        var label: String { name ?? String(localized: "A–Z") }

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
        [CatalogScope(name: nil)] + Self.categories.compactMap { cat in
            ranked.contains { category(of: $0.offer) == cat.name }
                ? CatalogScope(name: cat.name) : nil
        }
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

    /// The category filter.
    ///
    /// TEXT chips, deliberately. `CategoryVenueSwitcher` and the sources tray
    /// both draw `BridgeIcon`, and a strip of brand marks above a list of brand
    /// marks is exactly the grammar collision this pass exists to end (prd
    /// §518): the tray holds the sources you already have, the catalog holds
    /// what you could add, and the two had been wearing one face.
    ///
    /// Hidden below two categories, where a filter narrows nothing.
    @ViewBuilder
    private func scopeStrip(_ proxy: ScrollViewProxy) -> some View {
        let all = scopes
        if all.count > 2 {
            DSSectionSwitcher(sections: all, active: scope,
                              attention: troubledScopes) { picked in
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
            if yoursOnly && ranked.isEmpty {
                // Reachable only by choosing Yours with nothing connected —
                // the seed opens a first run on All. One sentence, and the
                // way out is the control the person just used.
                Text("Nothing connected yet. All has everything you can add.")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
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

    private var flatCatalogList: some View {
        VStack(spacing: DS.Space.s1) {
            ForEach(Array(allAppsSorted.enumerated()), id: \.element.id) { i, entry in
                appRow(entry).modifier(StockEntrance(index: i))
            }
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
                    .dsText(.subhead13)
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

    /// A catalog cell's tap. Almost every cell PUSHES, as a plain
    /// `NavigationLink` value — the product page for an app you could add, the
    /// manager for one that's connected. A wallet-riding seat with no screen
    /// of its own instead opens the room its rows land in
    /// (`BridgeRouter.roomSource`), which is a POP, not a push, so it cannot
    /// be a link value and takes a `Button` wearing the same style.
    @ViewBuilder
    private func catalogTap<Label: View>(roomSeat id: String?,
                                         destination: HomeRoute.Node,
                                         @ViewBuilder label: () -> Label) -> some View {
        if let id {
            Button {
                DSHaptic.tap()
                BridgeRouter.open(seatID: id, route: route, chrome: chrome)
            } label: {
                label()
            }
        } else {
            NavigationLink(value: destination) {
                label()
            }
        }
    }

    /// One app — icon, name, honest subline, action capsule.
    ///
    /// The catalog's ONE cell since prd §518, where it had been the search
    /// results' alone and the wall drew a separate `appTile` beside it. That
    /// split is what a list ends: the row has room for the tagline and the
    /// live status line a 4-across tile had to push onto the screen behind it,
    /// so the catalog now says what an app DOES before you tap it.
    ///
    /// The row tap opens the product page for an app you could add, and
    /// MANAGEMENT for one that's connected (its store pitch already worked).
    /// A connected row wears the status dot the old strip carried. No rank
    /// number: a category is not a leaderboard.
    private func appRow(_ entry: Ranked) -> some View {
        let soon = entry.tier == 3
        let isConnected = entry.tier == 0 || entry.tier == 2
        let destination: HomeRoute.Node = {
            if isConnected, let bridge = entry.bridge {
                return .bridge(BridgeRouter.destination(forID: bridge.id))
            }
            return .appDetail(entry.offer.name)
        }()
        return HStack(spacing: DS.Space.s3) {
            catalogTap(roomSeat: roomSeat(entry), destination: destination) {
                HStack(spacing: DS.Space.s3) {
                    BridgeIcon(name: entry.offer.name, size: DS.Mark.tile)
                        .saturation(soon ? 0 : 1)
                        .opacity(soon ? 0.5 : 1)
                        .overlay(alignment: .topTrailing) {
                            if isConnected, let bridge = entry.bridge {
                                Circle()
                                    .fill(bridge.status.color)
                                    .frame(width: 11, height: 11)
                                    .overlay(Circle().strokeBorder(DS.themedPage, lineWidth: 2))
                                    // One soft blink when the seat's proof
                                    // updates — "just checked", without words.
                                    .pulseOnChange(of: bridge.statusLine)
                                    .offset(x: 3, y: -3)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.offer.name)
                            .dsText(.body17).fontWeight(.semibold)
                            .foregroundStyle(soon ? DS.textSecondary : DS.textPrimary)
                            .lineLimit(1)
                        // The qualifier badge died here (user, 2026-07-16:
                        // "'no account' repeatedly under the names... extra
                        // text the user doesn't need") — every addable row
                        // wearing one made it wallpaper. The qualifier still
                        // serves as a Discover eyebrow, where ONE card states
                        // its reason.
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
                        .dsText(.subhead13)
                        .foregroundStyle(entry.tier == 0 ? DS.attention : DS.textTertiary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            // A tactile press-pop when you tap into an app (delight, 2026-07-12)
            // — the row springs slightly under the finger instead of a flat
            // .plain tap. Keeps the plain look, adds the give.
            .buttonStyle(PressSpring())
            // Long-press peek — the App Store's own gesture: the app's shape,
            // painted through the real gen-UI engine, with a Connect action,
            // before you commit. Only on an addable row (tier 1) with a preview
            // — a connected app shows real things, a Soon app can't be added,
            // and an actionless menu can suppress the peek entirely.
            .modifier(PeekPreview(
                offer: entry.offer,
                enabled: entry.tier == 1 && StorePreview.doc(for: entry.offer.name) != nil,
                onConnect: {
                    if entry.offer.needsSetup {
                        route.openSetup(forOffer: entry.offer.name)
                    } else {
                        attemptConnect(entry.offer)
                    }
                }))
            capsule(entry)
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
    private func walletSeatVerb(_ offer: BridgeCatalog.Offer) -> CapsuleVerb? {
        guard let id = BridgeRouter.id(forOffer: offer.name),
              WalletSeatStanding.rides(id: id) else { return nil }
        return CapsuleVerb(WalletSeatStanding.verb(
            watched: WalletStore.shared.addresses.count))
    }

    @ViewBuilder
    private func capsule(_ entry: Ranked) -> some View {
        switch entry.tier {
        case 0:
            // Broken connection — Fix opens management, where Reconnect lives.
            if let bridge = entry.bridge {
                VerbCapsule(verb: .fix) {
                    route.pushBridge(BridgeRouter.destination(forID: bridge.id))
                }
            }
        case 2:
            if let bridge = entry.bridge {
                VerbCapsule(verb: .open) {
                    BridgeRouter.open(seatID: bridge.id, route: route, chrome: chrome)
                }
            }
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
                VerbCapsule(verb: walletSeatVerb(entry.offer) ?? .connect) {
                    route.openSetup(forOffer: entry.offer.name)
                }
            } else {
                VerbCapsule(verb: .connect) { attemptConnect(entry.offer) }
            }
        default:
            VerbCapsule(verb: .soon)
        }
    }

    #if DEBUG
    enum AppsProbe: Identifiable, Hashable {
        case wallet, app(String)
        var id: String {
            switch self { case .wallet: "wallet"; case .app(let n): "app:\(n)" }
        }
    }
    #endif
}


// MARK: - Deck pan (UIKit)


/// The App Store's peek gesture, in Casberi's grammar: long-press a shelf row
/// and the app's shape rises in a preview — painted through the real gen-UI
/// engine from the same document its product page streams, so the peek never
/// disagrees with the page. Inert; the real thing arrives when the bridge does.
private struct PeekPreview: ViewModifier {
    let offer: BridgeCatalog.Offer
    let enabled: Bool
    let onConnect: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu {
                // A real action — an empty menu can suppress the peek, and
                // Connect is the honest verb for an addable row (no dead
                // control: it does exactly what the row's capsule does).
                Button(action: onConnect) {
                    Label("Connect", systemImage: "plus.circle")
                }
            } preview: {
                AppPeek(offer: offer)
            }
        } else {
            content
        }
    }
}

/// The peek card — icon, name, tagline, and the preview shape painted whole
/// (a peek is a glance, not a stream). Preview framing is explicit: fabricated
/// rows are honest on a store surface only when labelled.
private struct AppPeek: View {
    let offer: BridgeCatalog.Offer
    @State private var stream = GenStream()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: offer.name, size: DS.Mark.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.name).dsText(.body17).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                    Text(LocalizedStringKey(offer.tagline)).dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Text("Preview").dsText(.label12).foregroundStyle(DS.textTertiary)
            GenRender(id: "root", els: stream.els)
                .allowsHitTesting(false)
        }
        .padding(DS.Space.s4)
        .frame(width: 320, alignment: .leading)
        .background(DS.surfaceSheet)
        .onAppear { if let doc = StorePreview.doc(for: offer.name) { stream.paint(doc) } }
    }
}


extension String: @retroactive Identifiable {
    public var id: String { self }
}
