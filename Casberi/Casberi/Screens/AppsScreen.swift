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
    @State private var storyID: String?
    @State private var setupRoute: BridgeRouter.Destination?
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
        /// Nil falls back to the offer's own hook (its qualifier, else "New").
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
                  offer.connectable else { return }
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
        return Array(out.prefix(4))
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    if query.isEmpty {
                        if !stories.isEmpty {
                            storyCarousel
                            pageDots
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
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
        .sheet(isPresented: $pairing) { PairClientSheet() }
        .navigationDestination(item: $setupRoute) { dest in
            BridgeDestinationView(destination: dest)
        }
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
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "openPair") { pairing = true }
            if UserDefaults.standard.bool(forKey: "openWallet") { probe = .wallet }
            if let name = UserDefaults.standard.string(forKey: "openApp") { probe = .app(name) }
            // `-openSetup "<Offer name>"` pushes a bridge's setup screen
            // directly — the token/handle field screens have no deep link.
            if let name = UserDefaults.standard.string(forKey: "openSetup") {
                setupRoute = BridgeRouter.destination(forOffer: name)
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
            else { chrome.flash("Couldn't connect \(offer.name).") }
        }
    }

    /// The moment a one-tap connect lands: a success haptic, the app's hue
    /// blooming over the store, the toast naming what's now happening. Shared
    /// by the story card and the shelf capsule so no Connect ends silently.
    /// (The first-connect berry rain is dealt by `connectedCount`'s watcher,
    /// not here — it must fire for setup-screen connects too.)
    private func celebrateConnect(_ offer: BridgeCatalog.Offer) {
        DSHaptic.success()
        connectHue = DS.brandHue(for: offer.name) ?? DS.tint
        connectToken += 1
        chrome.flash(BridgeConnect.landingMessage(offer.name))
    }

    /// Connected, healthy bridges — the count whose 0 → 1 transition is the
    /// store's first-connect milestone.
    private var connectedCount: Int {
        store.bridges.filter { $0.status != .paused }.count
    }

    // MARK: - Story carousel (the ONE brand-gradient license)

    private var storyCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(stories) { story in
                    storyCard(story)
                        .containerRelativeFrame(.horizontal) { length, _ in length - 12 }
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        // Coverflow depth (delight, 2026-07-12): a card turns and
                        // recedes a touch as it leaves center, so the marquee has
                        // dimension instead of sliding flat. Off under Reduce Motion.
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.94)
                                .opacity(reduceMotion || phase.isIdentity ? 1 : 0.8)
                                .rotation3DEffect(.degrees(reduceMotion ? 0 : phase.value * -5),
                                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        }
                        .id(story.id)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $storyID)
        .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
    }

    @ViewBuilder
    private func storyCard(_ story: Story) -> some View {
        switch story.kind {
        case .bridge(let offer):
            // The eyebrow rotates off the offer's own hook — the adjacency
            // reason if it has one, else its honest qualifier ("No account" /
            // "One tap" / "Import"), else "New". A card that says "New"
            // forever stops being read; a card that says why it's here sells.
            storyCardBody(
                eyebrow: story.eyebrow ?? offer.qualifier ?? "New",
                headline: offer.tagline,
                iconName: offer.name,
                name: offer.name,
                brand: DS.legibleCardFill(for: offer.name),
                verb: .connect,
                previewName: offer.name
            ) {
                // Setup bridges (paste an address/token/handle) route to their
                // setup screen; only the system-permission bridges connect in
                // one tap, same split the chart uses.
                if offer.needsSetup {
                    setupRoute = BridgeRouter.destination(forOffer: offer.name)
                } else {
                    attemptConnect(offer)
                }
            }
        case .pair:
            storyCardBody(
                eyebrow: "Pair a client",
                headline: "Let Claude reach your things",
                iconName: "Claude",
                name: "Claude",
                brand: DS.tint,
                verb: .pair
            ) { pairing = true }
        }
    }

    /// LAYOUT LAW: content + token padding define the card — no fixed heights,
    /// nothing absolutely positioned, no clipping. The padding is the edge.
    private func storyCardBody(eyebrow: String, headline: String, iconName: String,
                               name: String, brand: Color, verb: CapsuleVerb,
                               previewName: String? = nil,
                               action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(LocalizedStringKey(eyebrow))
                .dsText(.label12)
                .foregroundStyle(.white.opacity(0.7))
            Text(LocalizedStringKey(headline))
                .dsText(.heading22).fontWeight(.heavy)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            // App-Store presence: the card breathes — the headline sits high,
            // the footer sits low. The middle band ghosts what lands (the
            // same sample rows the product page previews, 2026-07-13 polish:
            // a flat color field between headline and footer read as
            // unfinished, not as air). Offers without a preview keep the air.
            // Only a real offer's card ghosts samples (the pair card's
            // iconName is "Claude", whose import doc would leak an unrelated
            // takeaway here — cross-file review catch, 2026-07-13).
            let samples = previewName.map { StorePreview.samples(for: $0) } ?? []
            if samples.isEmpty {
                Spacer(minLength: DS.Space.s8)
            } else {
                Spacer(minLength: DS.Space.s2)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    // Named a preview (honesty rule): fabricated sample rows
                    // are licensed on store surfaces ONLY under explicit
                    // preview framing — unlabeled, they read as real synced
                    // content next to a live Connect verb.
                    Text("Preview")
                        .dsText(.label12)
                        .foregroundStyle(.white.opacity(0.6))
                    ForEach(Array(samples.enumerated()), id: \.offset) { idx, sample in
                        HStack(spacing: DS.Space.s2) {
                            // A social sample leads with its author's real
                            // avatar (the face is the identity, same as the
                            // feed row); every other kind keeps the dot.
                            if let avatar = sample.avatarURL {
                                RemoteThumb(urlString: avatar, size: 22, circular: true)
                            } else {
                                Circle().fill(.white.opacity(0.4))
                                    .frame(width: 6, height: 6)
                            }
                            Text(sample.title)
                                .dsText(.subhead13)
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, DS.Space.s3)
                        .frame(minHeight: 30)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.14), in: Capsule(style: .continuous))
                        // The sample rows assemble one after another the first
                        // time the card appears — the store demoing the
                        // product's own "things landing" cadence, played once.
                        .staggerIn(index: idx + 1, step: 0.08)
                    }
                }
                Spacer(minLength: DS.Space.s2)
            }
            HStack(spacing: DS.Space.s2) {
                BridgeIcon(name: iconName, size: 32)
                Text(name).dsText(.callout15).foregroundStyle(.white)
                Spacer()
                Button(action: action) {
                    Text(LocalizedStringKey(verb.label))
                        .dsText(.label12).foregroundStyle(brand)
                        .padding(.horizontal, DS.Space.s4)
                        .frame(minHeight: 32)
                        .background(.white, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background {
            // The one brand-gradient license, now with depth: the app's own
            // glyph ghosts huge across the bottom-trailing corner, bleeding
            // off the edge, so a feature card reads as inhabited instead of a
            // flat color field. White-on-hue keeps the single-gradient rule.
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [brand, brand.opacity(0.65)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: BridgeGlyph.symbol(for: iconName))
                    .font(.system(size: 150, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.10))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 44, y: 40)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
    }

    private var pageDots: some View {
        // Clamp to a live story: connecting the centered card drops it from
        // `stories` while `storyID` still holds its id, which would leave every
        // dot inactive until the next scroll. Fall back to the first card.
        let ids = stories.map(\.id)
        let current = storyID.flatMap { ids.contains($0) ? $0 : nil } ?? stories.first?.id
        return HStack(spacing: DS.Space.s2) {
            ForEach(stories) { story in
                let active = story.id == current
                // The active dot stretches into a short pill (the iOS idiom) —
                // the carousel reads as inhabited, not a row of equal dots.
                Capsule(style: .continuous)
                    .fill(active ? DS.tint : DS.gray300)
                    .frame(width: active ? 18 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
        .frame(maxWidth: .infinity)
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
                        HStack(spacing: DS.Space.s2) {
                            // The honest hook the taglines can't carry — a fact
                            // the app already ships (a keyless connect, a single
                            // permission, a one-time import), badged only on a
                            // row you can still add. Connected rows keep their
                            // live status subline instead.
                            if entry.tier == 1, let q = entry.offer.qualifier {
                                Text(LocalizedStringKey(q))
                                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                                    .padding(.horizontal, DS.Space.s2)
                                    .frame(minHeight: 20)
                                    .background(DS.fillFaint, in: Capsule(style: .continuous))
                            }
                            Text(LocalizedStringKey(subline(entry)))
                                .dsText(.subhead13)
                                .foregroundStyle(entry.tier == 0 ? DS.attention : DS.textTertiary)
                                .lineLimit(1)
                        }
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
                        setupRoute = BridgeRouter.destination(forOffer: entry.offer.name)
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
                    setupRoute = BridgeRouter.destination(forID: bridge.id)
                }
            }
        case 2:
            if let bridge = entry.bridge {
                VerbCapsule(verb: .open) {
                    setupRoute = BridgeRouter.destination(forID: bridge.id)
                }
            }
        case 1:
            if entry.offer.needsSetup {
                // Setup bridges collect input first — Connect opens their
                // screen; the connect happens there, with proof.
                VerbCapsule(verb: .connect) {
                    setupRoute = BridgeRouter.destination(forOffer: entry.offer.name)
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
