import SwiftUI
import SwiftData

/// Apps — store anatomy (docs/handoff-apps-page.md, mock M4): the connected
/// strip (management) sits above a hairline; everything below the "Discover"
/// heading is the store — a swipeable story carousel, a Browse category
/// shelf, and one ranked "For you" chart. The grouped directory and the
/// hardcoded featured hero died with it (singleton section headers, a wall of
/// "Soon"); `CatalogScreen` is deleted — this page IS the catalog.
///
/// LAYOUT LAW (the doc's): no fixed heights anywhere — every card, pill, and
/// row sizes to its content plus token padding (minHeight only where a target
/// needs it). Capsule verbs are honest: Connect / Pair / Fix / Open / Soon.
struct AppsScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var modelContext
    @State private var pairing = false
    @State private var storyID: String?
    @State private var setupRoute: BridgeRouter.Destination?
    #if DEBUG
    @State private var probe: AppsProbe?
    #endif

    // MARK: - Categories (merge map over Offer.group — Browse + chart filter ONLY,
    // never vertical section headers)

    private static let categories: [(name: String, exemplar: String, groups: Set<String>)] = [
        ("Onchain",      "Wallet",    ["Your wallet"]),
        ("Your life",    "Photos",    ["Your photos", "Your schedule", "Your fitness"]),
        ("Social",       "Bluesky",   ["Your network"]),
        ("Your agents",  "Claude",    ["Your agent", "Your machines"]),
        ("Your mail",    "Gmail",     ["Your mail"]),
        ("Your work",    "GitHub",    ["Your work"]),
        ("Your reading", "Readwise",  ["Your reading", "Your saves"]),
        ("Your media",   "Spotify",   ["Your watching", "Your listening", "Your messages", "Your games"]),
    ]

    private func category(of offer: BridgeCatalog.Offer) -> String {
        Self.categories.first { $0.groups.contains(offer.group) }?.name ?? "Your life"
    }

    // MARK: - Ranking (the For-you chart's one order)

    private struct Ranked: Identifiable {
        let offer: BridgeCatalog.Offer
        let bridge: BridgeApp?
        let tier: Int
        var id: String { offer.name }
    }

    /// Claude pairs over MCP, so it acts without a wired bridge — but only
    /// once the transport is real; until then it's a Soon row.
    private func actionable(_ offer: BridgeCatalog.Offer) -> Bool {
        offer.connectable || (offer.name == "Claude" && MCPPairing.transportReady)
    }

    /// The chart is SMART (ruling 2026-07-06): it never repeats what the
    /// strip already shows. Connected apps — healthy or broken — live in the
    /// strip (breakage = the attention-dot grammar + Fix on the detail);
    /// the chart is only what you can ADD: ready bridges, then coming ones.
    private var ranked: [Ranked] {
        BridgeCatalog.offers.compactMap { offer in
            let bridge = store.bridges.first { $0.name == offer.name }
            // In the strip → not in the chart.
            if let bridge, bridge.status != .paused { return nil }
            let tier = actionable(offer) ? 1 : 3           // ready → Connect / Pair; coming → Soon
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
    private static let featuredStories = ["Dexscreener", "Wallet", "Farcaster"]

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

    /// The strip = active seats only. Paused bridges aren't connected — they
    /// move to the chart as Connect, so nothing appears twice on this page.
    private var connected: [BridgeApp] {
        store.bridges.filter { $0.status != .paused }
            .sorted { $0.status.rank < $1.status.rank }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if !connected.isEmpty { connectedStrip }
                discoverDivide
                if !stories.isEmpty {
                    storyCarousel
                    pageDots
                }
                categoryShelves
            }
            .padding(.vertical, DS.Space.s4)
            .padding(.bottom, ShellMetrics.bottomInset)
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

    // MARK: - Connected strip (management — it never merchandises)

    private var connectedStrip: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            sectionHeader("Connected")
                .padding(.horizontal, DS.Space.s4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s4) {
                    ForEach(connected) { app in
                        NavigationLink {
                            BridgeDestinationView(destination: BridgeRouter.destination(forID: app.id))
                        } label: {
                            connectedChip(app)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
        }
    }

    private func connectedChip(_ app: BridgeApp) -> some View {
        let paused = app.status == .paused
        return VStack(spacing: DS.Space.s1) {
            BridgeIcon(name: app.name, size: 56)
                .overlay(alignment: .topTrailing) {
                    if !paused {
                        Circle()
                            .fill(app.status.color)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(DS.themedPage, lineWidth: 2))
                            // One soft blink when the seat's proof updates —
                            // "just checked", said without words.
                            .pulseOnChange(of: app.statusLine)
                            .offset(x: 3, y: -3)
                    }
                }
            Text(paused ? "Paused" : app.name)
                .dsText(.subhead13)
                .foregroundStyle(paused ? DS.textTertiary : DS.textPrimary)
                .lineLimit(1)
        }
        .frame(width: 64)
        .opacity(paused ? 0.5 : 1)
    }

    // MARK: - The divide (management above, store below)

    private var discoverDivide: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if !connected.isEmpty {
                Rectangle().fill(DS.fillLine).frame(height: 1)
                    .padding(.horizontal, DS.Space.s4)
            }
            Text("Discover").dsText(.heading22).foregroundStyle(DS.textPrimary)
                .padding(.horizontal, DS.Space.s4)
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
                brand: BridgeGlyph.color(for: offer.name),
                verb: .connect
            ) {
                // Setup bridges (paste an address/token/handle) route to their
                // setup screen; only the system-permission bridges connect in
                // one tap, same split the chart uses.
                if offer.needsSetup {
                    setupRoute = BridgeRouter.destination(forOffer: offer.name)
                } else {
                    BridgeConnect.connect(offer, store: store, context: modelContext, chrome: chrome)
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
        // A pale brand (ChatGPT's white, Notes' yellow) turns white ink
        // invisible — the Connect capsule vanished into it. Ink flips to dark
        // over light fills so the card, and its one control, stay legible.
        let ink: Color = brand.isLight ? .black : .white
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(eyebrow)
                .dsText(.label12)
                .foregroundStyle(ink.opacity(0.7))
            Text(headline)
                .dsText(.heading22).fontWeight(.heavy)
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            // App-Store presence: the card breathes — the headline sits high,
            // the footer sits low, air between them (minHeight, never fixed).
            Spacer(minLength: DS.Space.s8)
            HStack(spacing: DS.Space.s2) {
                BridgeIcon(name: iconName, size: 32)
                Text(name).dsText(.callout15).foregroundStyle(ink)
                Spacer()
                Button(action: action) {
                    Text(verb.label)
                        .dsText(.label12).foregroundStyle(brand)
                        .padding(.horizontal, DS.Space.s4)
                        .frame(minHeight: 32)
                        .background(ink, in: Capsule(style: .continuous))
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
                    Text(name)
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
            Text(name)
                .dsText(.heading22).foregroundStyle(DS.textPrimary)
                .padding(.horizontal, DS.Space.s4)
        }
    }

    /// The shelf's rows, three per page. One page renders exactly like the old
    /// full-width card; more apps page sideways, view-aligned.
    private func shelfPages(_ apps: [Ranked], key: String) -> some View {
        let pages: [[Ranked]] = stride(from: 0, to: apps.count, by: 3).map {
            Array(apps[$0..<min($0 + 3, apps.count)])
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: DS.Space.s1) {
                        ForEach(pages[i]) { entry in appRow(entry) }
                    }
                    .padding(.vertical, DS.Space.s1)
                    .background(DS.surfaceSheet,
                                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .containerRelativeFrame(.horizontal) { length, _ in length - 12 }
                    .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding(
            get: { shelfPage[key] ?? 0 },
            set: { shelfPage[key] = $0 ?? 0 }
        ))
        .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
    }

    /// One app inside a shelf — icon, name, honest subline, action capsule. The
    /// row tap (outside the capsule) opens the product page. No rank number: a
    /// shelf is a category, not a leaderboard.
    private func appRow(_ entry: Ranked) -> some View {
        let soon = entry.tier == 3
        return HStack(spacing: DS.Space.s3) {
            NavigationLink { AppDetailScreen(offer: entry.offer) } label: {
                HStack(spacing: DS.Space.s3) {
                    BridgeIcon(name: entry.offer.name, size: 44)
                        .saturation(soon ? 0 : 1)
                        .opacity(soon ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.offer.name)
                            .dsText(.body17).fontWeight(.semibold)
                            .foregroundStyle(soon ? DS.textSecondary : DS.textPrimary)
                            .lineLimit(1)
                        Text(subline(entry))
                            .dsText(.subhead13)
                            .foregroundStyle(entry.tier == 0 ? DS.attention : DS.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        case 1:
            if entry.offer.name == "Claude" {
                VerbCapsule(verb: .pair) { pairing = true }
            } else if entry.offer.needsSetup {
                // Setup bridges collect input first — Connect opens their
                // screen; the connect happens there, with proof.
                VerbCapsule(verb: .connect) {
                    setupRoute = BridgeRouter.destination(forOffer: entry.offer.name)
                }
            } else {
                VerbCapsule(verb: .connect) {
                    BridgeConnect.connect(entry.offer, store: store, context: modelContext, chrome: chrome)
                }
            }
        default:
            VerbCapsule(verb: .soon)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
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
