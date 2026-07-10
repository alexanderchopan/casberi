import SwiftUI
import SwiftData
import Observation

/// Where Home's toolbar pushes (amendment 2026-07-06, late — Apps stopped being
/// a tab). Shared so deep links (`casberi://apps`) and the debug `-openSettings`
/// hook can drive the same push the toolbar buttons do.
@Observable
final class HomeRoute {
    static let shared = HomeRoute()
    enum Push: String, Identifiable { case apps, settings; var id: String { rawValue } }
    var push: Push?
    /// A tag to open as its own view — set by an Ask answer that names a tag,
    /// so "what did I save about work" opens the Work view the treemap opens.
    var openTag: String?
    private init() {}
}

/// Home — composition per moment, streamed through the gen UI engine (v94
/// grammar). The document is authored locally from the corpus until the M2
/// server half lands; the engine and visuals are final either way.
/// Generated surfaces stream; records paint.
///
/// Home also carries the app's management doors in its nav bar (the shell
/// settled to two tabs): the avatar (top-left) pushes Settings, a grid glyph
/// (top-right) pushes Apps. The grid wears an attention dot only when a bridge
/// needs reconnecting — surfaced where it's earned, never a standing banner.
struct HomeScreen: View {
    /// The liquid dissolve (2026-07-10): both doors — Settings AND the
    /// store — open through it. One pusher per screen.
    @State private var liquid = LiquidPusher()
    @Query(sort: \Thing.capturedAt, order: .reverse) private var things: [Thing]
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Bindable private var route = HomeRoute.shared
    @Bindable private var wallet = WalletStore.shared
    @State private var stream = GenStream()
    @State private var openProject: ProjectRoute?
    @State private var pinnedThing: Thing?
    @State private var walletOpen = false
    /// Bumped by pull-to-refresh — token charts key their fetch on it.
    @State private var refreshTick = 0
    /// One retiring lesson (Feed's coach grammar): with no pins yet, the
    /// Pinned slot teaches the swipe; the first real pin retires it forever.
    @AppStorage("coach.pin.done") private var pinCoachDone = false
    /// The last celebrated corpus milestone — each fires exactly once, ever.
    @AppStorage("milestone.reached") private var milestoneReached = 0
    @State private var walletHoldings: [WalletIngest.HoldingsGroup] = []
    @Namespace private var zoomNS

    struct ProjectRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }

    var body: some View {
        NavigationStack {
            // The cover is full-bleed (H7): the scroll ignores the top safe
            // area and the nav buttons overlay it; the geometry reader hands
            // the cover the inset its date eyebrow needs. The 34pt "Home"
            // title is gone — the cover is the title.
            GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GenRender(id: "root", els: stream.els)
                }
                .padding(.bottom, ShellMetrics.bottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            // Live modules re-fetch on pull (2026-07-10): holdings straight
            // from Alchemy, and the tick bump re-keys every token chart's
            // fetch (a recompose alone reuses the old task id).
            .refreshable { await refreshLive() }
            .environment(\.genCoverTopInset, geo.safeAreaInsets.top)
            .environment(\.genRefreshTick, refreshTick)
        .minimizesChrome(chrome)
            .homePageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                // The shell's doors — shared with Feed (every tab root wears
                // them): avatar → Settings, grid (+ attention dot) → Apps.
                TopDoors(onSettings: { liquid.open(push: { route.push = .settings },
                                                    pop: { route.push = nil }) },
                         onApps: { liquid.open(push: { route.push = .apps },
                                               pop: { route.push = nil }) },
                         refreshSpin: refreshTick)
            }
            // Topic blocks open project detail, not a Feed filter (gap §9.1).
            // The source-fallback map's cells name APPS, not tags — those open
            // the source's feed (a tag view for a nonexistent tag is a dead end).
            .environment(\.genProjectTap) { name in
                // A holdings cell routes to the Wallet screen — there's no
                // per-token view to open (2026-07-10).
                if name == "@wallet" { walletOpen = true; return }
                // The quiet day's invite opens the Apps page.
                if name == "@apps" { route.push = .apps; return }
                let isTag = things.contains { $0.tags.contains(name) }
                if !isTag, things.contains(where: { $0.source == name }) {
                    FeedFilter.shared.source = name
                    FeedFilter.shared.tag = "All"
                    // Home caused this switch — Feed's back arrow only
                    // appears when that's true (2026-07-09).
                    chrome.jumpedFromHome = true
                    if let url = URL(string: "casberi://feed") { openURL(url) }
                } else {
                    openProject = ProjectRoute(name: name)
                }
            }
            // Pinned rows are interactive (2026-07-10): tap opens the
            // thing; long-press offers Open/Unpin. Unpinning recomposes
            // immediately — the pin flip changes no count, so nothing else
            // would repaint.
            .environment(\.genThingOpen) { id in
                if let thing = things.first(where: { $0.id.uuidString == id }) {
                    pinnedThing = thing
                }
            }
            .environment(\.genThingUnpin) { id in
                guard let thing = things.first(where: { $0.id.uuidString == id }) else { return }
                DSHaptic.tap()
                thing.pinned = false
                try? modelContext.save()
                streamComposition(instant: true)
                chrome.flash("Unpinned from Home")
            }
            // The real hand-off — the same "Open in app" the Feed swipe
            // carries (2026-07-10: moving pins to Home must not cost it).
            .environment(\.genThingHandoff) { id in
                guard let thing = things.first(where: { $0.id.uuidString == id }),
                      let verb = VerbDerivation.verbs(for: thing).first(where: {
                          if case .openURL = $0.action { return true } else { return false }
                      }),
                      case .openURL(let url) = verb.action else { return }
                DSHaptic.selection()
                openURL(url)
            }
            .sheet(item: $pinnedThing) { thing in
                ThingSheetView(thing: thing)
            }
            .environment(\.genZoomNS, zoomNS)
            .navigationDestination(item: $openProject) { route in
                ProjectDetailScreen(projectName: route.name)
                    .navigationTransition(.zoom(sourceID: route.name, in: zoomNS))
            }
            // An Ask answer named a tag — open its view (same push the treemap
            // makes). Bind through openProject so pop/re-tap clears it too.
            .onAppear {
                // A navigation ask can set the tag before Home ever mounts —
                // onChange never fires for a pre-set value, so consume it here.
                if let name = route.openTag {
                    openProject = ProjectRoute(name: name); route.openTag = nil
                }
            }
            .onChange(of: route.openTag) { _, name in
                if let name { openProject = ProjectRoute(name: name); route.openTag = nil }
            }
            .navigationDestination(item: $route.push) { push in
                switch push {
                case .apps:     AppsScreen()
                case .settings: SettingsScreen()
                }
            }
            .navigationDestination(isPresented: $walletOpen) {
                BridgeDestinationView(destination: .wallet)
            }
            }
        }
        .tint(DS.tint)
        // Re-tapping the Home tab pops pushed screens and sheets back to root.
        .onChange(of: chrome.popHome) {
            route.push = nil
            openProject = nil
            pinnedThing = nil
            walletOpen = false
        }
        // The corpus changed under the composition (a capture, the demo
        // seeds, the dissolve) — repaint instantly, no replayed entrance.
        .onChange(of: things.count) {
            streamComposition(instant: true)
            celebrateMilestone()
        }
        // A tag rename/retag leaves the count unchanged but changes what Home
        // composes from — repaint so the renamed tag shows immediately.
        .onChange(of: CorpusSignal.shared.revision) { streamComposition(instant: true) }
        // Pinning/unpinning a wallet (WalletScreen) re-fetches (or drops) its
        // holdings treemap — same "pin means keep this in view" rule as a
        // Thing pin, just without a Thing to observe via things.count. Pin is
        // per-address now, so the whole list is the thing to watch.
        .onChange(of: wallet.addresses) { loadWalletHoldings() }
        .onAppear {
            streamComposition()
            loadWalletHoldings()
            #if DEBUG
            // Debug hooks: `-openSettings YES` pushes Settings;
            // `-openProject "Work"` pushes a project — both for screenshots.
            if UserDefaults.standard.bool(forKey: "openSettings") {
                route.push = .settings
            }
            // `-openSettingsDroplet <s>` waits, then opens Settings through
            // the liquid transition — a recording of "tapping the avatar".
            let dropletDelay = UserDefaults.standard.double(forKey: "openSettingsDroplet")
            if dropletDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(dropletDelay))
                    liquid.open(push: { route.push = .settings },
                                pop: { route.push = nil })
                }
            }
            // `-openAppsLiquid <s>` — same, for the store door.
            let appsDelay = UserDefaults.standard.double(forKey: "openAppsLiquid")
            if appsDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(appsDelay))
                    liquid.open(push: { route.push = .apps },
                                pop: { route.push = nil })
                }
            }
            // `-liquidPopDemo <s>` — after the delay, pops back through the
            // liquid (records the way back).
            let popDelay = UserDefaults.standard.double(forKey: "liquidPopDemo")
            if popDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(popDelay))
                    liquid.liquidPop()
                }
            }
            if let name = UserDefaults.standard.string(forKey: "openProject") {
                // `-openProjectDelay <s>` shows Home first, then opens the tag
                // (with the tile's zoom) — a recording of "tapping the tile".
                let delay = UserDefaults.standard.double(forKey: "openProjectDelay")
                if delay > 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        withAnimation(DS.Motion.standard) {
                            openProject = ProjectRoute(name: name)
                        }
                    }
                } else {
                    openProject = ProjectRoute(name: name)
                }
            }
            #endif
        }
        .liquidPushOverlay(liquid)
        .environment(liquid)
        // The route emptied by another hand (tab re-tap, deep link) — the
        // pusher's remembered way back would be stale.
        .onChange(of: route.push) { _, now in
            if now == nil, !liquid.active { liquid.clearPop() }
        }
    }

    private func streamComposition(instant: Bool = false) {
        // The first real pin is the lesson learned — the coach retires
        // forever, even if every pin is later removed.
        if !pinCoachDone, things.contains(where: \.pinned) { pinCoachDone = true }
        let doc = things.isEmpty
            ? HomeComposition.empty
            : HomeComposition.compose(things: things, walletHoldings: walletHoldings,
                                      pinCoach: !pinCoachDone)
        if instant {
            stream.paint(doc)   // an update, not an entrance — no typewriter
        } else {
            stream.stream(doc)
        }
    }

    /// Composing is synchronous; the holdings fetch isn't — load in the
    /// background and repaint (instant, like any other corpus change) once
    /// it lands. Unpinning drops the cells and repaints without them.
    private func loadWalletHoldings() {
        guard wallet.addresses.contains(where: \.pinnedToHome) else {
            if !walletHoldings.isEmpty {
                walletHoldings = []
                streamComposition(instant: true)
            }
            return
        }
        Task { @MainActor in
            walletHoldings = await WalletIngest.topHoldingsByWallet(pinnedOnly: true)
            streamComposition(instant: true)
        }
    }

    /// A real count crossing a round threshold earns ONE toast, ever —
    /// "500 things banked." Rare by construction (2026-07-10): thresholds
    /// only, each fires once, nothing recurring, no streaks.
    private func celebrateMilestone() {
        let thresholds = [100, 500, 1_000, 5_000, 10_000]
        guard let crossed = thresholds.last(where: { things.count >= $0 }),
              crossed > milestoneReached else { return }
        milestoneReached = crossed
        DSHaptic.success()
        chrome.flash("\(crossed.formatted()) things banked.")
    }

    /// Pull-to-refresh: awaited (the spinner shows real work), then one
    /// repaint. The tick bump re-fetches every token chart.
    private func refreshLive() async {
        refreshTick += 1
        if wallet.addresses.contains(where: \.pinnedToHome) {
            walletHoldings = await WalletIngest.topHoldingsByWallet(pinnedOnly: true)
        }
        streamComposition(instant: true)
        // The refresh LANDS — a soft thud when the fresh data is on screen
        // (2026-07-10 haptics pass: motion that completes gets felt).
        DSHaptic.success()
    }
}
