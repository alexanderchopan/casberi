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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    /// Bumped when a jump chip lands on a shelf — the header flashes once so
    /// the tap has an arrival, not just a silent scroll.
    @State private var shelfLand: [String: Int] = [:]
    /// Bumped when a category's LAST addable app connects — the shelf header
    /// glows once in the category's own color and a toast names the set now
    /// complete. Its own trigger (not `shelfLand`) so the completion glow wears
    /// the category color while a jump stays neutral tint.
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
    @State private var tasteReasons: [CatalogTaste.Reason] = []
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
    private var ranked: [Ranked] {
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

    // MARK: - Stories (selection rules; never a "Soon" app, never a connected one)

    private struct Story: Identifiable {
        enum Kind { case bridge(BridgeCatalog.Offer), pair }
        let kind: Kind
        /// An eyebrow override — the adjacency reason ("Goes with GitHub").
        /// Nil falls back to the offer's own qualifier; an offer with NEITHER
        /// holds no seat (reason-or-no-seat, ruling 2026-07-16 — "New" died).
        var eyebrow: String? = nil
        var id: String {
            switch kind { case .bridge(let o): o.name; case .pair: "pair" }
        }
    }

    /// Discover's featured picks lead the deck (user ruling 2026-07-23:
    /// "do Steam as a card and Mail as a card to start with"). Steam and Gmail
    /// now HEAD the carousel — a broad, non-crypto first impression, since the
    /// deck leading with Tokens/Wallet/Farcaster made the app read crypto-only.
    /// The crypto hooks still ride behind them (they're strong, just not the
    /// face). Order is the display order, trimmed to `prefix(4)`.
    private static let featuredStories = ["Steam", "Gmail", "Tokens", "Wallet", "Farcaster"]

    private var stories: [Story] {
        let active = Set(store.bridges.filter { $0.status != .paused }.map(\.name))
        var out: [Story] = []
        var seen = Set<String>()
        func add(_ offer: BridgeCatalog.Offer, eyebrow: String? = nil) {
            guard !seen.contains(offer.name), !active.contains(offer.name),
                  offer.connectable,
                  // Reason or no seat: the eyebrow must state something
                  // computable — an adjacency or the offer's own qualifier.
                  (eyebrow ?? offer.qualifier) != nil else { return }
            seen.insert(offer.name)
            out.append(Story(kind: .bridge(offer), eyebrow: eyebrow))
        }
        // (0) Just added — a genuinely-new offer (a real `added` date inside
        // the week) leads: the freshest news the catalog has, and now
        // COMPUTABLE, so the eyebrow is honest where the old "New" badge was
        // pure assertion (the reason "New" was retired 2026-07-16 — a date
        // brings it back legitimately).
        for offer in BridgeCatalog.offers where offer.isNew() {
            add(offer, eyebrow: "Just added")
        }
        // (1) Featured tracking bridges lead, in the order listed — unless
        // already connected (then they're in the strip, not the store).
        for name in Self.featuredStories {
            if let offer = BridgeCatalog.offers.first(where: { $0.name == name }) { add(offer) }
        }
        // (2) Because you connected — a connected app's neighbours surface
        // next, eyebrowed with the reason.
        for bridge in store.bridges where bridge.status != .paused {
            for suggestion in Self.adjacency[bridge.name] ?? [] {
                if let offer = BridgeCatalog.offers.first(where: { $0.name == suggestion }) {
                    add(offer, eyebrow: "Goes with \(bridge.name)")
                }
            }
        }
        // (2b) Because of what you keep — a real capture habit points at the
        // bridge that would keep more of it (many links → Readwise, or RSS if
        // Readwise is already connected). The first OPEN candidate in each
        // signal takes the seat; `add`'s not-connected guard falls the loop
        // through to the next.
        for reason in tasteReasons {
            for name in CatalogTaste.candidates(for: reason.offerName) {
                guard let offer = BridgeCatalog.offers.first(where: { $0.name == name }) else { continue }
                let before = out.count
                add(offer, eyebrow: reason.eyebrow)
                if out.count > before { break }
            }
        }
        // (3) Pair-a-client when no client is paired (replaces pairEntryRow).
        if MCPPairing.transportReady {
            let clientPaired = store.bridges.contains { $0.name == "Claude" && $0.status == .connected }
            if !clientPaired { out.append(Story(kind: .pair)) }
        }
        // (4) Backfill with other connectable bridges not yet connected.
        for entry in ranked where entry.tier <= 1 && entry.offer.connectable {
            add(entry.offer)
        }
        // A stable order on purpose — the daily rotation seeds the DECK's
        // index once per mount (see DiscoverDeck.onAppear). Rotating this
        // array per evaluation reshuffled the deck under a live index at
        // midnight and whenever the seat count changed (review, 2026-07-16).
        return Array(out.prefix(4))
    }

    // MARK: - Body

    /// The Discover deck's three callbacks, split out so `body`'s VStack stays
    /// a single small expression — a merged version timed out the type
    /// checker once the wall's own closures joined it (found live, 2026-07-23).
    private func onDiscoverConnect(_ offer: BridgeCatalog.Offer) {
        // Setup bridges (paste an address/token/handle) route to their setup
        // screen; only the system-permission bridges connect in one tap.
        if offer.needsSetup {
            route.openSetup(forOffer: offer.name)
        } else {
            attemptConnect(offer)
        }
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
                        searchField
                        if query.isEmpty {
                            let cards = stories
                            if !cards.isEmpty {
                                DiscoverDeck(stories: cards,
                                            onOpen: { route.pushAppDetail($0.name) },
                                            onConnect: onDiscoverConnect,
                                            onPair: { pairing = true })
                            }
                            jumpChips(proxy)
                            catalogWall
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
                    // `-appsShelf "<Category>"` — scroll the catalog to a
                    // category's card headlessly (screenshot runs have no
                    // scroll gesture; same route as a jump-chip tap). The
                    // pager half of this hook retired with shelf paging (prd
                    // §200): the wall shows every app in a category at once,
                    // nothing to page.
                    guard let name = UserDefaults.standard.string(forKey: "appsShelf") else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        proxy.scrollTo("card-" + name, anchor: .top)
                        NSLog("appsShelf: \(name)")
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
            // Read the corpus once for the taste-driven Discover seats.
            tasteReasons = CatalogTaste.reasons(context: modelContext)
        }
        // The store's shape after any connect/disconnect — drives the promote
        // lift (which row just took its seat), the count milestones, and the
        // shelf-completed glow. Keyed on the NAMES (not just the count) so the
        // just-connected row can be identified.
        .onChange(of: connectedNames) { old, new in
            handleConnectChange(old: old, new: new)
        }
        // The catalog is a GRID, so it takes the wide column (2026-07-25) —
        // it answers extra width with extra columns per band, not with longer
        // rows, which is the whole distinction `DSContentWidth` draws.
        .dsAdaptiveContentWidth(.wide)
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Apps")
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

    /// Every offer whose name, tagline, or category matches the query — a flat
    /// list you scan, in the same ranked tier order the shelves use.
    private var searchHits: [Ranked] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return ranked.filter { entry in
            entry.offer.name.lowercased().contains(q)
                || entry.offer.tagline.lowercased().contains(q)
                || category(of: entry.offer).lowercased().contains(q)
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
                            .padding(.horizontal, DS.Space.s4)
                        VStack(spacing: DS.Space.s1) { appRow(rss) }
                            .padding(.vertical, DS.Space.s1)
                            .dsCard()
                            .padding(.horizontal, DS.Space.s4)
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
            .padding(.vertical, DS.Space.s1)
            .dsCard()
            .padding(.horizontal, DS.Space.s4)
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

    // MARK: - Discover deck (the ONE brand-gradient license, dealt like cards)

    /// A real deck (ruling 2026-07-16): the front card swipes AWAY — either
    /// direction — and the next rises from underneath while the dealt card
    /// slides to the bottom of the stack (browsing, not consuming: the deck
    /// recycles). The cards behind peek above the front, scaled back. The
    /// swipe is UIKit (`DeckPanCatcher`), never a SwiftUI DragGesture — the
    /// §gotchas scroll-arbitration lesson, measured again here.
    ///
    /// A child view ON PURPOSE: it owns the drag state, so a dragged frame
    /// re-renders these three cards — not the whole store (with `dragX` on
    /// the screen, every shelf row re-diffed per frame).
    private struct DiscoverDeck: View {
        let stories: [Story]
        /// The card body's door — push this offer's product page.
        let onOpen: (BridgeCatalog.Offer) -> Void
        /// The capsule's verb — connect (or route to setup).
        let onConnect: (BridgeCatalog.Offer) -> Void
        let onPair: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var deckIndex = 0
        @State private var dragX: CGFloat = 0
        /// A deal in flight — the completion owns the state swap; new drags
        /// wait, so a fast second fling can't double-advance the index or
        /// stomp the spring mid-flight (review, 2026-07-16).
        @State private var dealing = false
        @State private var seeded = false
        /// Measured card width — the fly-off distance derives from it (a
        /// hardcoded 640 left wide layouts swapping state on-screen).
        @State private var cardWidth: CGFloat = 360

        /// The deck's feel constants, together because they must agree: a
        /// release commits past `commit`; the under-card fully rises by
        /// `rise` — which must stay below every fly distance so the risen
        /// card is already in place when the completion swaps state.
        private enum Feel {
            static let commit: CGFloat = 160
            static let rise: CGFloat = 240
        }

        /// The front card's index — clamped, because connecting the front
        /// card shrinks `stories` under a live index.
        private var top: Int { min(deckIndex, stories.count - 1) }

        var body: some View {
            VStack(spacing: DS.Space.s6) {
                deck
                // The deck's honest count — "1 of 4" states the real number
                // of live seats (replaced the page dots).
                Text("\(top + 1) of \(stories.count)")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .animation(DS.Motion.standard, value: top)
            }
            .onAppear {
                // The daily deal: which card opens FRONT rotates by
                // day-of-year — the store opens stocked, never stuck on one
                // pitch. Seeds the INDEX once per mount; rotating the seat
                // array per evaluation (the first build) reshuffled the deck
                // under a live index at midnight and whenever the seat count
                // changed.
                guard !seeded else { return }
                seeded = true
                dragX = 0
                let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
                if stories.count > 1 { deckIndex = day % stories.count }
            }
        }

        private var deck: some View {
            let count = stories.count
            // How far the front card has left — the next card rises to meet it.
            let progress = min(1, abs(dragX) / Feel.rise)
            // The FRONT card alone defines the deck's layout; the unders hang
            // off it as backgrounds (a ZStack of flexible-height cards
            // measured short of what the front card painted — border probe,
            // 2026-07-16). And because `.offset`/`.rotationEffect` are
            // render-time, backgrounds added after them stay at the layout
            // position while the front card flies — exactly the deck's
            // geometry.
            return storyCard(stories[top], parallax: reduceMotion ? 0 : dragX * 0.08)
                .offset(x: dragX)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragX / 28)),
                                anchor: .bottom)
                .background {
                    if count > 1 {
                        underCard(stories[(top + 1) % count], depth: 1, progress: progress)
                    }
                }
                .background {
                    if count > 2 {
                        underCard(stories[(top + 2) % count], depth: 2, progress: progress)
                    }
                }
                .overlay {
                    DeckPanCatcher(
                        onChanged: { x in if !dealing { dragX = x } },
                        onEnded: { t, predicted in
                            guard !dealing else { return }
                            // Commit on where the card IS when that's already
                            // past the line — a slow far drag with a wobbly
                            // release must not snap back, and must deal the
                            // way it sits (never boomerang). Otherwise the
                            // fling decides.
                            let travel = abs(t) > Feel.commit ? t : predicted
                            if abs(travel) > Feel.commit, count > 1 {
                                deal(direction: travel > 0 ? 1 : -1)
                            } else {
                                withAnimation(DS.Motion.standard) { dragX = 0 }
                            }
                        })
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
                // VoiceOver can't pan — the deck advances as a named action,
                // and the inert under-cards stay out of the tree (they'd read
                // as duplicate cards whose activation point hit-tests the
                // FRONT card).
                .accessibilityAction(named: Text("Next card")) {
                    if count > 1 { deal(direction: -1) }
                }
                // Headroom for the peeking under-cards (they offset upward
                // out of the front card's bounds).
                .padding(.top, count > 1 ? DS.Space.s4 : 0)
                .padding(.horizontal, DS.Space.s4)
        }

        /// A card waiting under the front one — peeking above it, scaled back
        /// by its depth, rising as the front card is dragged away. Inert.
        private func underCard(_ story: Story, depth: Int, progress: CGFloat) -> some View {
            let lift = CGFloat(depth) - progress
            return storyCard(story)
                .scaleEffect(1 - 0.05 * lift)
                .offset(y: -10 * lift)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }

        /// Deals the front card: it flies off past its own measured width,
        /// the next rises in the same spring (progress saturates well before
        /// the fly distance), and the COMPLETION swaps state with no
        /// animation — the risen card is already sitting exactly where the
        /// front slot will draw it, so the only visible change is the dealt
        /// card joining the bottom of the deck. Completion-based on purpose:
        /// a fixed asyncAfter raced the spring and a fast second swipe.
        private func deal(direction: CGFloat) {
            guard stories.count > 1, !dealing else { return }
            // The commit past the line is felt — a selection tick, so dealing a
            // card reads like dealing (§36v: haptics finish the motion).
            DSHaptic.selection()
            if reduceMotion {
                advance()
                return
            }
            dealing = true
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78),
                          completionCriteria: .logicallyComplete) {
                dragX = direction * (cardWidth + 100)
            } completion: {
                advance()
                dealing = false
            }
        }

        private func advance() {
            let count = stories.count
            guard count > 0 else { return }
            deckIndex = (top + 1) % count
            dragX = 0
        }

        @ViewBuilder
        private func storyCard(_ story: Story, parallax: CGFloat = 0) -> some View {
            switch story.kind {
            case .bridge(let offer):
                // The eyebrow is the seat's reason — the adjacency if it has
                // one, else the offer's honest qualifier ("No account" / "One
                // tap" / "Import"). `stories` guarantees one exists; "New"
                // died with the reason-or-no-seat rule.
                storyCardBody(
                    eyebrow: story.eyebrow ?? offer.qualifier ?? "",
                    headline: offer.tagline,
                    iconName: offer.name,
                    name: offer.name,
                    brand: DS.legibleCardFill(for: offer.name),
                    verb: .connect,
                    destination: offer,
                    parallax: parallax
                ) { onConnect(offer) }
            case .pair:
                storyCardBody(
                    eyebrow: "Pair a client",
                    headline: "Let Claude reach your things",
                    iconName: "Claude",
                    name: "Claude",
                    brand: DS.tint,
                    verb: .pair,
                    parallax: parallax
                ) { onPair() }
            }
        }

    /// LAYOUT LAW: content + token padding define the card — no fixed heights,
    /// nothing absolutely positioned, no clipping. The padding is the edge.
    ///
    /// The card is a TEASER now (ruling 2026-07-16): reason, headline, verb —
    /// the demo left the card and lives on the product page (and the peek),
    /// where the same preview document renders at full contrast. One
    /// document, one home; the card is the door.
    private func storyCardBody(eyebrow: String, headline: String, iconName: String,
                               name: String, brand: Color, verb: CapsuleVerb,
                               destination: BridgeCatalog.Offer? = nil,
                               parallax: CGFloat = 0,
                               action: @escaping () -> Void) -> some View { // in DiscoverDeck
        let card = VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(LocalizedStringKey(eyebrow))
                .dsText(.label12)
                .foregroundStyle(.white.opacity(0.7))
            Text(LocalizedStringKey(headline))
                .dsText(.heading22).fontWeight(.heavy)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.s6)
            HStack(spacing: DS.Space.s2) {
                BridgeIcon(name: iconName, size: DS.Mark.list)
                Text(name).dsText(.callout15).foregroundStyle(.white)
                Spacer()
                // Reserves the verb's seat inside the tappable card so the
                // overlaid live capsule never covers the name.
                capsuleLabel(verb, brand: brand).hidden()
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            // The one brand-gradient license, now with depth: the app's own
            // glyph ghosts huge across the bottom-trailing corner, bleeding
            // off the edge, so a feature card reads as inhabited instead of a
            // flat color field. White-on-hue keeps the single-gradient rule.
            //
            // Opaque on purpose: the deck stacks cards, so a translucent
            // gradient (the old carousel's brand.opacity(0.65)) would let
            // the card beneath bleed through. Mixing toward black keeps the
            // same fade with a solid surface.
            //
            // The glyph rides an OVERLAY of the gradient, never a ZStack
            // sibling: a rigid 150pt image in the background's ZStack made
            // the whole background TALLER than the card wherever the card's
            // content ran shorter than the glyph, and the gradient painted
            // past both edges (measured with a border probe on the Pro Max,
            // 2026-07-16 — the old minHeight 220 had been hiding it).
            LinearGradient(colors: [brand, brand.mix(with: .black, by: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: BridgeGlyph.symbol(for: iconName))
                        .accessibilityHidden(true)
                        .dsGlyph(150)
                        .foregroundStyle((BridgeGlyph.glyphTint(for: iconName) ?? .white).opacity(0.10))
                        .rotationEffect(.degrees(-12))
                        // The ghost glyph drifts a touch against the drag — the
                        // card gains cheap depth as it's pulled (the front card
                        // passes its live `dragX`; under-cards pass 0).
                        .offset(x: 44 + parallax, y: 40)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))

        // The whole card is a door: body → product page (where the demo is);
        // the capsule alone fires the verb. The pair card has no page — its
        // body and capsule share one action. A TapGesture on purpose, NOT a
        // Button/NavigationLink: a button activates on release even after the
        // finger dragged, so a deck swipe would ALSO open the page (measured
        // on the sim, 2026-07-16); a tap gesture fails on movement.
        return ZStack(alignment: .bottomTrailing) {
            card
                .onTapGesture {
                    DSHaptic.selection()
                    if let destination { onOpen(destination) } else { action() }
                }
            Button(action: action) { capsuleLabel(verb, brand: brand) }
                .buttonStyle(.plain)
                .padding(DS.Space.s4)
        }
    }

    private func capsuleLabel(_ verb: CapsuleVerb, brand: Color) -> some View {
        Text(LocalizedStringKey(verb.label))
            .dsText(.label12).foregroundStyle(brand)
            .padding(.horizontal, DS.Space.s4)
            .frame(minHeight: 32)
            .background(.white, in: Capsule(style: .continuous))
    }
    }

    // MARK: - Search field (prd §200 — leads the page, not a nav-bar pull-down)

    private var searchField: some View {
        // The slab rung, spelled as itself. It used to say
        // `height: DS.Radius.widget + 36` — a corner-radius token standing in
        // for a height, arriving at exactly `DSSlab.height` by coincidence
        // rather than by agreement (2026-08-28).
        DSSlabField(placeholder: String(localized: "Search apps"),
                    text: $query, actionLabel: "",
                    focus: $searchFocused,
                    glyph: "magnifyingglass", clearable: true,
                    size: .slab, submitLabel: .search, action: {})
    }

    // MARK: - The wall (prd §200 — a card per category, every app visible at once)

    /// The category chips: a tap scrolls to that category's card. Only
    /// categories with something to add appear — a chip always lands
    /// somewhere.
    @ViewBuilder
    private func jumpChips(_ proxy: ScrollViewProxy) -> some View {
        let live = Self.categories.filter { cat in
            ranked.contains { category(of: $0.offer) == cat.name }
        }
        if live.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(live, id: \.name) { cat in
                        Button {
                            DSHaptic.selection()
                            withAnimation(DS.Motion.standard) {
                                proxy.scrollTo("card-" + cat.name, anchor: .top)
                            }
                            // Close the loop: the card you landed on flashes
                            // once, so the tap arrives instead of scrolling in
                            // silence.
                            shelfLand[cat.name, default: 0] += 1
                        } label: {
                            HStack(spacing: DS.Space.s2) {
                                Image(systemName: BridgeGlyph.symbol(for: cat.exemplar))
                                    .dsGlyph(15, weight: .medium)
                                    .foregroundStyle(BridgeGlyph.color(for: cat.exemplar))
                                Text(LocalizedStringKey(cat.name))
                                    .dsText(.callout15).fontWeight(.medium)
                                    .foregroundStyle(DS.textPrimary)
                            }
                            .padding(.horizontal, DS.Space.s3)
                            .frame(minHeight: 44)
                            .background(DS.surfaceSheet,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressSpring())
                        .accessibilityLabel("Jump to \(cat.name)")
                    }
                }
            }
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

    /// A section of the wall: one full-width band, or two small categories
    /// paired onto a single 4-wide row (prd §201).
    private enum WallBand: Identifiable {
        case full(String, [Ranked])
        case paired(String, [Ranked], String, [Ranked])
        var id: String {
            switch self {
            case .full(let n, _): "full:" + n
            case .paired(let a, _, let b, _): "pair:" + a + "+" + b
            }
        }
    }

    /// The catalog's categories walked into bands (prd §201, mockup B). A
    /// category of two apps or fewer would waste most of a 4-wide row alone,
    /// so a SMALL category pairs with the next small one — each keeping its
    /// own label, a gap between (the user's "next to each other, not as one
    /// category" rule, turned horizontal). Everything larger is a full-width
    /// band, 4 across, its last row left-aligned. A lone small with no partner
    /// falls back to a full band (2 tiles, trailing space) rather than
    /// stretching — honest, and rare given the ruled order pairs Social+Mail.
    private var wallBands: [WallBand] {
        let sections = Self.categories.compactMap { cat -> (String, [Ranked])? in
            let apps = ranked.filter { category(of: $0.offer) == cat.name }
            return apps.isEmpty ? nil : (cat.name, apps)
        }
        var bands: [WallBand] = []
        var pending: (String, [Ranked])?
        for section in sections {
            if section.1.count <= 2 {
                if let p = pending {
                    bands.append(.paired(p.0, p.1, section.0, section.1))
                    pending = nil
                } else {
                    pending = section
                }
            } else {
                if let p = pending { bands.append(.full(p.0, p.1)); pending = nil }
                bands.append(.full(section.0, section.1))
            }
        }
        if let p = pending { bands.append(.full(p.0, p.1)) }
        return bands
    }

    /// Tiles across a full band — 4 on iPhone, 6 on iPad (2026-07-25). At the
    /// wide column's 1040pt a 4-across band drew 240pt-wide tiles around a
    /// 48pt icon, which is a grid pretending to be a list. A paired band
    /// splits this in half, so the two shapes stay one rhythm.
    private var wallColumns: Int { horizontalSizeClass == .regular ? 6 : 4 }

    private var catalogWall: some View {
        VStack(spacing: DS.Space.s3) {
            ForEach(wallBands) { band in
                switch band {
                case .full(let name, let apps):
                    bandCard { categoryColumn(name, apps: apps, columns: wallColumns) }
                case .paired(let n1, let a1, let n2, let a2):
                    bandCard {
                        HStack(alignment: .top, spacing: DS.Space.s3) {
                            categoryColumn(n1, apps: a1, columns: wallColumns / 2)
                            categoryColumn(n2, apps: a2, columns: wallColumns / 2)
                        }
                    }
                }
            }
        }
        // A connect moves its row to the strip — the wall closes the gap
        // smoothly instead of snapping.
        .animation(DS.Motion.standard, value: store.bridges.count)
    }

    /// The band's rounded card shell — one shape whether it holds one category
    /// or a pair, so the wall reads as one rhythm of bands.
    private func bandCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s3)
            .background(DS.surfaceSheet, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    /// One category inside a band — its label, then its apps in `columns`-wide
    /// tiles (4 for a full band, 2 for a paired half). Carries its own scroll
    /// anchor so a jump chip lands on it even when it shares a band.
    private func categoryColumn(_ name: String, apps: [Ranked], columns: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(LocalizedStringKey(name))
                .dsText(.label12).fontWeight(.bold).foregroundStyle(DS.textTertiary)
                .landFlash(shelfLand[name] ?? 0)
                .landFlash(shelfComplete[name] ?? 0, tint: categoryColor(name))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2),
                                     count: columns),
                      alignment: .leading, spacing: DS.Space.s3) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { i, entry in
                    appTile(entry).modifier(StockEntrance(index: i))
                        // Tiles settle in as they cross the viewport edge —
                        // scroll-driven, so it costs nothing at rest
                        // (2026-08-04). Under Reduce Motion only the fade
                        // survives, the chip strip's own convention.
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.94)
                                .opacity(phase.isIdentity ? 1 : 0.7)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("card-" + name)
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

    /// One app on the wall — icon, name underneath, home-screen style. The
    /// verb and status line moved off the tile onto the destination it opens
    /// (the product page's Connect/Open, or the manager's own proof line) —
    /// a tile states WHO, tapping it says WHAT. Connected apps wear the same
    /// status dot the old shelf row did; a Soon app dims.
    private func appTile(_ entry: Ranked) -> some View {
        let soon = entry.tier == 3
        let isConnected = entry.tier == 0 || entry.tier == 2
        let destination: HomeRoute.Node = {
            if isConnected, let bridge = entry.bridge {
                return .bridge(BridgeRouter.destination(forID: bridge.id))
            }
            return .appDetail(entry.offer.name)
        }()
        return catalogTap(roomSeat: roomSeat(entry), destination: destination) {
            VStack(spacing: DS.Space.s1) {
                BridgeIcon(name: entry.offer.name, size: DS.Mark.tile)
                    .saturation(soon ? 0 : 1)
                    .opacity(soon ? 0.5 : 1)
                    .overlay(alignment: .topTrailing) {
                        if isConnected, let bridge = entry.bridge {
                            Circle()
                                .fill(bridge.status.color)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().strokeBorder(DS.themedPage, lineWidth: 2))
                                .pulseOnChange(of: bridge.statusLine)
                                .offset(x: 3, y: -3)
                        }
                    }
                Text(entry.offer.name)
                    .dsText(.label12)
                    .foregroundStyle(soon ? DS.textSecondary : DS.textPrimary)
                    .multilineTextAlignment(.center)
                    // Names NEVER truncate (user ruling, prd §201). A
                    // multi-word name wraps to two lines; a long single word
                    // ("GeckoTerminal") that can't wrap shrinks to fit its
                    // tile instead of clipping — `minimumScaleFactor` is what
                    // makes "no truncation" true at four-per-row.
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    // `minHeight`, so the promise above survives Dynamic Type:
                    // a pinned 28 makes "names NEVER truncate" false at the
                    // first accessibility size, where two scaled lines need
                    // roughly three times it and the tile clips instead.
                    .frame(minHeight: 28, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .dsHover()
            // A catalog tile is a CARD — you click it to go somewhere — so it
            // takes the lift (2026-08-17). The wall is six columns wide on a
            // Mac window, which is the densest grid of clickable objects in
            // the app and the place a uniform hover said least.
            .macHoverLift()
        }
        .buttonStyle(PressSpring())
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
        // The just-connected tile lifts as the wall re-sorts it into its
        // connected seat — a promotion you can feel, not a silent re-order.
        .connectPromote(isTarget: entry.offer.name == justConnectedName, token: connectLiftToken)
    }

    /// One app inside a shelf — icon, name, honest subline, action capsule.
    /// The row tap opens the product page for an app you could add, and
    /// MANAGEMENT for one that's connected (its store pitch already worked).
    /// A connected tile wears the status dot the old strip carried. No rank
    /// number: a shelf is a category, not a leaderboard.
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
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        // The just-connected row lifts as the shelf re-sorts it into its
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
                VerbCapsule(verb: .connect) {
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

/// The deck's swipe input. A SwiftUI DragGesture here — plain OR
/// simultaneous, any minimumDistance — beats the enclosing UIScrollView's
/// pan, and the page stops scrolling from a finger that lands on the card
/// (measured on the sim 2026-07-16; the same class of failure as the old Home
/// board's drag-to-reorder, fixed the same way — one UIKit recognizer on the
/// enclosing scroll view). This pan begins ONLY
/// for a clearly horizontal pull that starts inside the marker's bounds;
/// vertical and diagonal drags fail it instantly, so the scroll keeps them.
/// The marker itself never eats touches (`isUserInteractionEnabled = false`)
/// — the card's tap and the Connect capsule keep working.
private struct DeckPanCatcher: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ predictedEnd: CGFloat) -> Void

    func makeUIView(context: Context) -> Marker {
        let v = Marker()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.onChanged = onChanged
        v.onEnded = onEnded
        return v
    }

    func updateUIView(_ v: Marker, context: Context) {
        v.onChanged = onChanged
        v.onEnded = onEnded
    }

    /// Delivers callbacks from its OWN touch handlers — never target-action:
    /// a stock recognizer added to SwiftUI's UIScrollView transitions state
    /// correctly, but its target-action fires only intermittently — SwiftUI's
    /// gesture environment eats the dispatch (the old Home board's
    /// drag-to-reorder lesson, 2026-07-13; CLAUDE.md gotchas). Setting
    /// `state` still feeds UIKit's exclusivity machinery, so the scroll
    /// pan is cancelled when this begins and vice versa.
    final class Pan: UIPanGestureRecognizer {
        var deliver: ((UIGestureRecognizer.State, CGFloat, CGFloat) -> Void)?

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesMoved(touches, with: event)
            if state == .began || state == .changed {
                deliver?(.changed, translation(in: view).x, velocity(in: view).x)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            let wasActive = state == .began || state == .changed
            let t = translation(in: view).x
            let v = velocity(in: view).x
            super.touchesEnded(touches, with: event)
            if wasActive { deliver?(.ended, t, v) }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            let wasActive = state == .began || state == .changed
            super.touchesCancelled(touches, with: event)
            if wasActive { deliver?(.cancelled, 0, 0) }
        }
    }

    final class Marker: UIView, UIGestureRecognizerDelegate {
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat, CGFloat) -> Void)?
        private var pan: Pan?
        private weak var host: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, pan == nil else { return }
            // The nearest enclosing scroll view IS the page's vertical
            // scroller today — the jump chips' and shelves' horizontal
            // scrollers are siblings, never ancestors. Re-check this walk if
            // the deck ever gains a scrollable ancestor of its own.
            var v: UIView? = superview
            while v != nil, !(v is UIScrollView) { v = v?.superview }
            guard let scroll = v as? UIScrollView else { return }
            let g = Pan()
            g.delegate = self
            g.deliver = { [weak self] state, t, vel in
                guard let self else { return }
                switch state {
                case .changed:
                    self.onChanged?(t)
                case .ended:
                    // A quarter second of the release velocity — enough
                    // prediction to let a short fast fling deal the card.
                    self.onEnded?(t, t + vel * 0.25)
                default:
                    self.onEnded?(0, 0)
                }
            }
            scroll.addGestureRecognizer(g)
            pan = g
            host = scroll
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            // Unmounting (search hides the deck) must not leave a dead
            // recognizer on the scroll view — and a deck unmounted MID-DRAG
            // never sends finger-up, so settle first or the card leaks a
            // half-dragged offset into the next mount.
            if newWindow == nil, let g = pan {
                if g.state == .began || g.state == .changed { onEnded?(0, 0) }
                host?.removeGestureRecognizer(g)
                pan = nil
            }
            super.willMove(toWindow: newWindow)
        }

        override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === pan, let p = pan else { return true }
            // The under-cards peek ABOVE the marker's frame — a swipe that
            // starts on the peek is still a deck swipe.
            guard bounds.insetBy(dx: 0, dy: -DS.Space.s6)
                .contains(g.location(in: self)) else { return false }
            let v = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y) * 1.2
        }
    }
}


// MARK: - Long-press peek

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
