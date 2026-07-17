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
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pairing = false
    /// The card body's door — a tap (not a swipe) pushes this offer's
    /// product page via `navigationDestination`.
    @State private var openOffer: String?
    @State private var query = ""
    /// The connect payoff (delight): every Connect on this screen — story
    /// card OR shelf capsule — ends the same way the product page's does,
    /// the app's hue blooming over the page (the shared `.connectBloom`).
    /// `connectHue` is the app that just landed; bumping `connectToken` fires
    /// one bloom.
    @State private var connectHue: Color = DS.tint
    @State private var connectToken = 0
    /// The store's first-ever connect rains the app's berries once — the
    /// milestone the app noticed (sibling to "Your first thing"). Guarded so
    /// it plays a single time, forever.
    @AppStorage("apps.storeFirstConnect.done") private var storeFirstConnectDone = false
    @State private var firstConnectPulse = 0
    /// Bumped when a jump chip lands on a shelf — the header flashes once so
    /// the tap has an arrival, not just a silent scroll.
    @State private var shelfLand: [String: Int] = [:]
    #if DEBUG
    @State private var probe: AppsProbe?
    #endif

    // MARK: - Categories (merge map over Offer.group — Browse + chart filter ONLY,
    // never vertical section headers)

    private static let categories: [(name: String, exemplar: String, groups: Set<String>)] = [
        ("Onchain", "Wallet",      ["Wallet", "NFTs", "Onchain"]),
        ("Life",    "Photos",      ["Photos", "Schedule", "Fitness"]),
        ("Notes",   "Apple Notes", ["Notes"]),
        ("Social",  "Bluesky",     ["Network"]),
        ("Agents",  "Claude",      ["Agent", "Machines"]),
        ("Mail",    "Gmail",       ["Mail"]),
        ("Work",    "GitHub",      ["Work"]),
        ("Reading", "Readwise",    ["Reading", "Saves"]),
        ("Media",   "Spotify",     ["Watching", "Listening", "Games", "Images"]),
        ("Shopping", "Shopify",    ["Shopping"]),
        // Markets rides LAST (user ruling 2026-07-13, tightened same day):
        // Onchain leads the catalog; prediction markets are a tail interest,
        // not the front door — the shelf closes the store.
        ("Markets", "Kalshi",      ["Markets"]),
    ]

    private func category(of offer: BridgeCatalog.Offer) -> String {
        Self.categories.first { $0.groups.contains(offer.group) }?.name ?? "Life"
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

    /// Discover leads with the "track anything" bridges — paste a token, a
    /// wallet, or a Farcaster handle and its activity lands in the feed. These
    /// are the standout hooks, so they head the carousel; everything else
    /// backfills in catalog order.
    private static let featuredStories = ["Tokens", "Wallet", "Farcaster"]

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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    if query.isEmpty {
                        let cards = stories
                        if !cards.isEmpty {
                            DiscoverDeck(
                                stories: cards,
                                onOpen: { openOffer = $0.name },
                                onConnect: { offer in
                                    // Setup bridges (paste an address/token/
                                    // handle) route to their setup screen;
                                    // only the system-permission bridges
                                    // connect in one tap — the chart's split.
                                    if offer.needsSetup {
                                        HomeRoute.shared.bridgePush = BridgeRouter.destination(forOffer: offer.name)
                                    } else {
                                        attemptConnect(offer)
                                    }
                                },
                                onPair: { pairing = true })
                        }
                        jumpChips(proxy)
                        categoryShelves
                    } else {
                        searchResults
                    }
                }
                .padding(.vertical, DS.Space.s4)
                .padding(.bottom, ShellMetrics.bottomInset)
            }
        }
        .scrollIndicators(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search apps")
        // The connect payoff blooms the app's hue over the whole store, then
        // recedes — the same beat the product page gives, now on every Connect.
        .connectBloom(hue: connectHue, token: connectToken)
        // The store's first-ever connect rains the app's berries, once.
        .overlay { BerryRain(trigger: firstConnectPulse) }
        // The milestone fires on the first connection by ANY path — the
        // featured hooks (Wallet/Tokens/Farcaster) connect on their setup
        // screen, never through `celebrateConnect`, so watch the store itself:
        // 0 → first connected bridge deals the rain. A user who already has
        // connections has passed the milestone; mark it done on appear so it
        // never fires late.
        .onAppear { if connectedCount > 0 { storeFirstConnectDone = true } }
        .onChange(of: connectedCount) { old, new in
            guard !storeFirstConnectDone, old == 0, new > 0 else { return }
            storeFirstConnectDone = true
            firstConnectPulse += 1
        }
        .dsPageBackground()
        .navigationTitle("Apps")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $openOffer) { name in
            if let offer = BridgeCatalog.offers.first(where: { $0.name == name }) {
                AppDetailScreen(offer: offer)
            }
        }
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
            if let name = HomeRoute.shared.openOffer {
                HomeRoute.shared.openOffer = nil
                if BridgeCatalog.offers.contains(where: { $0.name == name }) {
                    openOffer = name
                }
            }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "openPair") { pairing = true }
            if UserDefaults.standard.bool(forKey: "openWallet") { probe = .wallet }
            if let name = UserDefaults.standard.string(forKey: "openApp") { probe = .app(name) }
            // `-openSetup "<Offer name>"` pushes a bridge's setup screen
            // directly — the token/handle field screens have no deep link.
            if let name = UserDefaults.standard.string(forKey: "openSetup") {
                HomeRoute.shared.bridgePush = BridgeRouter.destination(forOffer: name)
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

    @ViewBuilder
    private var searchResults: some View {
        let hits = searchHits
        if hits.isEmpty {
            Text("No apps match \(Text(query).fontWeight(.semibold)).")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DS.Space.s8)
                .padding(.horizontal, DS.Space.s4)
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
        connectHue = DS.brandHue(for: offer.name) ?? DS.tint
        connectToken += 1
        chrome.flash(BridgeConnect.landingMessage(offer.name), tone: .success)
    }

    /// Connected, healthy bridges — the count whose 0 → 1 transition is the
    /// store's first-connect milestone.
    private var connectedCount: Int {
        store.bridges.filter { $0.status != .paused }.count
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
            return storyCard(stories[top])
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
        private func storyCard(_ story: Story) -> some View {
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
                    destination: offer
                ) { onConnect(offer) }
            case .pair:
                storyCardBody(
                    eyebrow: "Pair a client",
                    headline: "Let Claude reach your things",
                    iconName: "Claude",
                    name: "Claude",
                    brand: DS.tint,
                    verb: .pair
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
                BridgeIcon(name: iconName, size: 32)
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
                        .font(.system(size: 150, weight: .semibold))
                        .foregroundStyle((BridgeGlyph.glyphTint(for: iconName) ?? .white).opacity(0.10))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 44, y: 40)
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

    // MARK: - Category shelves (the catalog's spine — one section per category)

    /// Apps grouped by category. Each category with something you can add gets
    /// a labeled shelf; connected apps live in the strip above (ranked drops
    /// them), so nothing repeats. Ready-to-connect apps lead each shelf, coming
    /// ("Soon") ones trail — the tier order `ranked` already carries.
    /// App Store grammar: a big header, three rows showing, swipe sideways for
    /// the rest — the shelf never grows tall, it grows wide.
    /// The category chips, back as NAVIGATION (the filter version died with
    /// the flat chart): a tap scrolls to that shelf. Only categories with
    /// something to add appear — a chip always lands somewhere.
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
                                proxy.scrollTo("shelf-" + cat.name, anchor: .top)
                            }
                            // Close the loop: the shelf you landed on flashes
                            // once, so the tap arrives instead of scrolling in
                            // silence.
                            shelfLand[cat.name, default: 0] += 1
                        } label: {
                            HStack(spacing: DS.Space.s2) {
                                Image(systemName: BridgeGlyph.symbol(for: cat.exemplar))
                                    .font(.system(size: 15, weight: .medium))
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
                        .buttonStyle(.plain)
                        .accessibilityLabel("Jump to \(cat.name)")
                    }
                }
            }
            .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
        }
    }

    /// Which page each shelf is on — the header chevron advances it.
    @State private var shelfPage: [String: Int] = [:]

    private var categoryShelves: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            ForEach(Self.categories, id: \.name) { cat in
                let apps = ranked.filter { category(of: $0.offer) == cat.name }
                if !apps.isEmpty {
                    let pageCount = (apps.count + 2) / 3
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        shelfHeader(cat.name, pageCount: pageCount)
                        shelfPages(apps, key: cat.name)
                    }
                    .id("shelf-" + cat.name)
                }
            }
        }
        // A connect moves its row to the strip — the shelf closes the gap
        // smoothly instead of snapping.
        .animation(DS.Motion.standard, value: store.bridges.count)
    }

    /// The App Store header grammar: name + chevron when there's more to see.
    /// Honest control: the chevron appears only with a second page, and the
    /// tap advances the shelf (wrapping) — it does what it points at.
    @ViewBuilder
    private func shelfHeader(_ name: String, pageCount: Int) -> some View {
        if pageCount > 1 {
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    shelfPage[name] = ((shelfPage[name] ?? 0) + 1) % pageCount
                }
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Text(LocalizedStringKey(name))
                        .dsText(.heading22).foregroundStyle(DS.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.s4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .landFlash(shelfLand[name] ?? 0)
        } else {
            Text(LocalizedStringKey(name))
                .dsText(.heading22).foregroundStyle(DS.textPrimary)
                .padding(.horizontal, DS.Space.s4)
                .landFlash(shelfLand[name] ?? 0)
        }
    }

    /// The shelf's rows, three per page. One page renders exactly like the old
    /// full-width card; more apps page sideways, view-aligned.
    /// A one-shot "stocking the shelf" entrance — a row fades and rises into
    /// place, staggered by its position, when the shelf appears (delight,
    /// 2026-07-12). Off under Reduce Motion.
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

    private func shelfPages(_ apps: [Ranked], key: String) -> some View {
        let pages: [[Ranked]] = stride(from: 0, to: apps.count, by: 3).map {
            Array(apps[$0..<min($0 + 3, apps.count)])
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: DS.Space.s1) {
                        ForEach(Array(pages[i].enumerated()), id: \.element.id) { j, entry in
                            appRow(entry).modifier(StockEntrance(index: j))
                        }
                    }
                    .padding(.vertical, DS.Space.s1)
                    .dsCard()
                    .containerRelativeFrame(.horizontal) { length, _ in length - 12 }
                    .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding(
            // Clamped: a connect can shrink the shelf under a stored index.
            get: { min(shelfPage[key] ?? 0, max(0, pages.count - 1)) },
            set: { shelfPage[key] = $0 ?? 0 }
        ))
        .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
    }

    /// One app inside a shelf — icon, name, honest subline, action capsule.
    /// The row tap opens the product page for an app you could add, and
    /// MANAGEMENT for one that's connected (its store pitch already worked).
    /// A connected tile wears the status dot the old strip carried. No rank
    /// number: a shelf is a category, not a leaderboard.
    private func appRow(_ entry: Ranked) -> some View {
        let soon = entry.tier == 3
        let isConnected = entry.tier == 0 || entry.tier == 2
        return HStack(spacing: DS.Space.s3) {
            NavigationLink {
                if isConnected, let bridge = entry.bridge {
                    BridgeDestinationView(destination: BridgeRouter.destination(forID: bridge.id))
                } else {
                    AppDetailScreen(offer: entry.offer)
                }
            } label: {
                HStack(spacing: DS.Space.s3) {
                    BridgeIcon(name: entry.offer.name, size: 44)
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
                        Text(LocalizedStringKey(subline(entry)))
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
                        HomeRoute.shared.bridgePush = BridgeRouter.destination(forOffer: entry.offer.name)
                    } else {
                        attemptConnect(entry.offer)
                    }
                }))
            capsule(entry)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
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
                    HomeRoute.shared.bridgePush = BridgeRouter.destination(forID: bridge.id)
                }
            }
        case 2:
            if let bridge = entry.bridge {
                VerbCapsule(verb: .open) {
                    HomeRoute.shared.bridgePush = BridgeRouter.destination(forID: bridge.id)
                }
            }
        case 1:
            if entry.offer.needsSetup {
                // Setup bridges collect input first — Connect opens their
                // screen; the connect happens there, with proof.
                VerbCapsule(verb: .connect) {
                    HomeRoute.shared.bridgePush = BridgeRouter.destination(forOffer: entry.offer.name)
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
/// (measured on the sim 2026-07-16; the same class of failure as the Home
/// board's, fixed the same way — one UIKit recognizer on the enclosing
/// scroll view, per `Design/BoardDragDriver.swift`). This pan begins ONLY
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
    /// gesture environment eats the dispatch (BoardDragDriver's on-device
    /// lesson, 2026-07-13; §gotchas lesson 2). Setting `state` still feeds
    /// UIKit's exclusivity machinery, so the scroll pan is cancelled when
    /// this begins and vice versa.
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
                BridgeIcon(name: offer.name, size: 44)
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
