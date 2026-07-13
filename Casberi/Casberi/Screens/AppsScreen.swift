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
    #if DEBUG
    @State private var probe: AppsProbe?
    #endif

    // MARK: - Categories (merge map over Offer.group — Browse + chart filter ONLY,
    // never vertical section headers)

    private static let categories: [(name: String, exemplar: String, groups: Set<String>)] = [
        ("Onchain", "Wallet",      ["Wallet"]),
        ("Markets", "Kalshi",      ["Markets"]),
        ("Life",    "Photos",      ["Photos", "Schedule", "Fitness"]),
        ("Notes",   "Apple Notes", ["Notes"]),
        ("Social",  "Bluesky",     ["Network", "Messages"]),
        ("Agents",  "Claude",      ["Agent", "Machines"]),
        ("Mail",    "Gmail",       ["Mail"]),
        ("Work",    "GitHub",      ["Work"]),
        ("Reading", "Readwise",    ["Reading", "Saves"]),
        ("Media",   "Spotify",     ["Watching", "Listening", "Games"]),
    ]

    private func category(of offer: BridgeCatalog.Offer) -> String {
        Self.categories.first { $0.groups.contains(offer.group) }?.name ?? "Life"
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
        // (1) Featured tracking bridges lead, in the order listed — unless
        // already connected (then they're in the strip, not the store).
        for name in Self.featuredStories where !active.contains(name) {
            guard let offer = BridgeCatalog.offers.first(where: { $0.name == name }),
                  offer.connectable else { continue }
            out.append(Story(kind: .bridge(offer)))
        }
        // (2) Pair-a-client when no client is paired (replaces pairEntryRow).
        if MCPPairing.transportReady {
            let clientPaired = store.bridges.contains { $0.name == "Claude" && $0.status == .connected }
            if !clientPaired { out.append(Story(kind: .pair)) }
        }
        // (3) Backfill with other connectable bridges not yet connected.
        for entry in ranked where entry.tier <= 1 && entry.offer.connectable
            && !Self.featuredStories.contains(entry.offer.name) {
            out.append(Story(kind: .bridge(entry.offer)))
        }
        return Array(out.prefix(4))
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    if !stories.isEmpty {
                        storyCarousel
                        pageDots
                    }
                    jumpChips(proxy)
                    categoryShelves
                }
                .padding(.vertical, DS.Space.s4)
                .padding(.bottom, ShellMetrics.bottomInset)
            }
        }
        .scrollIndicators(.hidden)
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
            storyCardBody(
                eyebrow: "New",
                headline: offer.tagline,
                iconName: offer.name,
                name: offer.name,
                brand: DS.legibleCardFill(for: offer.name),
                verb: .connect
            ) {
                // Setup bridges (paste an address/token/handle) route to their
                // setup screen; only the system-permission bridges connect in
                // one tap, same split the chart uses.
                if offer.needsSetup {
                    setupRoute = BridgeRouter.destination(forOffer: offer.name)
                } else {
                    BridgeConnect.connect(offer, store: store, context: modelContext) { ok in
                        if !ok { chrome.flash("Couldn't connect \(offer.name).") }
                    }
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
            // the footer sits low, air between them (minHeight, never fixed).
            Spacer(minLength: DS.Space.s8)
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
        .background(
            LinearGradient(colors: [brand, brand.opacity(0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
    }

    private var pageDots: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(stories) { story in
                Circle()
                    .fill(story.id == (storyID ?? stories.first?.id) ? DS.tint : DS.gray300)
                    .frame(width: 7, height: 7)
            }
        }
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
        } else {
            Text(LocalizedStringKey(name))
                .dsText(.heading22).foregroundStyle(DS.textPrimary)
                .padding(.horizontal, DS.Space.s4)
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
                VerbCapsule(verb: .connect) {
                    BridgeConnect.connect(entry.offer, store: store, context: modelContext) { ok in
                        if !ok { chrome.flash("Couldn't connect \(entry.offer.name).") }
                    }
                }
            }
        default:
            VerbCapsule(verb: .soon)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .dsText(.label12)
            .foregroundStyle(DS.textSecondary)
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


extension String: @retroactive Identifiable {
    public var id: String { self }
}
