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
    /// Anchors the doors' zoom transitions (each room grows from its door).
    @Namespace private var doorNS
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
    /// One retiring lesson for the size control (prd 58a): tap a pin, the
    /// card blooms to large. Retires on the first tap, forever — same
    /// grammar as `pinCoachDone`.
    @AppStorage("coach.size.done") private var sizeCoachDone = false
    /// The last celebrated corpus milestone — each fires exactly once, ever.
    @AppStorage("milestone.reached") private var milestoneReached = 0
    @State private var walletHoldings: [WalletIngest.HoldingsGroup] = []
    /// True from the moment a pinned wallet's balance fetch starts until it
    /// resolves — lets the composer show an honest loading placeholder in
    /// the wallet's slot instead of leaving it blank (device report,
    /// 2026-07-11: the empty window during that real network round-trip
    /// read as "my holdings disappeared").
    @State private var walletHoldingsLoading = false
    @Namespace private var zoomNS
    /// The board (prd 58, Goal 1): which root refs from the last compose are
    /// drag-reorderable modules, and their current display order (natural
    /// order, permuted by any saved arrangement). `boardOrder` holds ref ids
    /// (what GenRender needs to draw them); persistence goes through stable
    /// content-derived keys (`moduleKey`) so a wallet's card stays "its"
    /// card even if its slot index shifts as wallets are pinned/unpinned.
    @State private var boardModuleRefs: Set<String> = []
    @State private var boardOrder: [String] = []
    /// The magazine packing of `boardOrder` (prd 58f): each entry is a ROW —
    /// one full-width module, or two paired image-media modules. Recomputed
    /// whenever the order or a module's size changes; the drag reorders
    /// whole rows, then flattens back to `boardOrder`.
    @State private var boardRows: [[String]] = []

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
                    // The fixed head (cover, quiet-day invite, pin coach)
                    // renders plainly, in doc order — only the board section
                    // below it is a drag-reorderable stack (prd 58).
                    let rootRefs = stream.els["root"]?.refs(0) ?? []
                    ForEach(rootRefs.filter { !boardModuleRefs.contains($0) }, id: \.self) { ref in
                        GenRender(id: ref, els: stream.els)
                    }
                    // One retiring line (prd 58a) — shown until the first
                    // pin tap, forever, same grammar as the pin coach.
                    if !sizeCoachDone, !boardOrder.isEmpty {
                        Text("Tap a pin to grow its card")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.tint)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s4)
                    }
                    // The magazine board (prd 58f): image-media modules pair
                    // into 2-up rows, everything else spans full width — the
                    // rhythm emerges from your size choices. Rows drag as
                    // units on the safe 1D reorder (prd 58d).
                    ReorderableBoard(order: $boardRows) { row in
                        if row.count == 2 {
                            // A pair — two half-width art tiles.
                            HStack(alignment: .top, spacing: DS.Space.s3) {
                                magazineTile(row[0])
                                magazineTile(row[1])
                            }
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s4)
                        } else if isPairable(row[0]),
                                  !HomeModuleSize.shared.isLarge(moduleKey(row[0])) {
                            // A lone regular media module — a full-width art
                            // tile (one beautiful frame). Tap the pin to grow
                            // it into the full shelf.
                            magazineTile(row[0])
                                .padding(.horizontal, DS.Space.s4)
                                .padding(.top, DS.Space.s4)
                        } else {
                            // Structural modules, and any LARGE media module
                            // (its full shelf/grid/hero), span full width.
                            GenRender(id: row[0], els: stream.els)
                                .environment(\.genModuleLarge, HomeModuleSize.shared.isLarge(moduleKey(row[0])))
                        }
                    } onReorder: { newRows in
                        let flat = newRows.flatMap { $0 }
                        boardOrder = flat
                        // Same keying as syncBoard's apply(), suffixes and all
                        // — bare moduleKey here broke round-trip for two
                        // same-labeled modules (dedupedKeys' note).
                        HomeBoardOrder.shared.save(dedupedKeys(flat))
                    }
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
                TopDoors(onSettings: { route.push = .settings },
                         onApps: { route.push = .apps },
                         refreshSpin: refreshTick,
                         zoomNS: doorNS)
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
                // The weekend recap is a door to the week's synthesis
                // (prd 54): the composer opens and runs the week ask.
                if name == "@week" { chrome.ask("What's this week?"); return }
                // Any OTHER @-name is a sentinel we don't know — including a
                // mid-stream partial ("@we") tapped during the typewriter
                // entrance, which GenParser fills before the line completes.
                // Falling through opened a bogus empty project (review
                // 2026-07-11); an unknown sentinel does nothing.
                if name.hasPrefix("@") { return }
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
            // Tap the pin (prd 58a) — the only way a module grows: no
            // menu, no edit mode. The pin itself never removes anything
            // (unpin lives elsewhere per module), so it's free to mean
            // "press me".
            .environment(\.genSizeToggle) { ref in
                DSHaptic.selection()
                sizeCoachDone = true
                HomeModuleSize.shared.toggle(moduleKey(ref))
                // Size decides packing (a large media module can't sit in a
                // 2-up row) — re-pack so growing a module lifts it out of its
                // pair into its own full-width row, and shrinking lets it
                // re-pair. Nothing else observes HomeModuleSize, so without
                // this the stored size flipped but the board never repainted
                // (the pin looked dead for paired Music/Screenshots cards).
                withAnimation(DS.Motion.standard) {
                    boardRows = packRows(boardOrder)
                }
            }
            // Long-press a pinned media shelf → Remove from Home. Drops the
            // source's pin (HomePinnedSources.clear also forgets its saved
            // size/order), then recomposes so the shelf leaves the board.
            .environment(\.genSourceUnpin) { ref in
                guard let source = HomePinnedSources.source(forModuleRef: ref) else { return }
                DSHaptic.tap()
                HomePinnedSources.shared.clear(source)
                CorpusSignal.shared.bump()
                streamComposition(instant: true)
                chrome.flash("Removed from Home")
            }
            // A screenshot's own stored thumbnail (prd 48) — local bytes,
            // not a URL, so the media tile resolves it by thing id.
            .environment(\.genThumbnailData) { id in
                things.first(where: { $0.id.uuidString == id })?.previewImageData
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
                case .apps:
                    AppsScreen()
                        .navigationTransition(.zoom(sourceID: "appsDoor", in: doorNS))
                case .settings:
                    SettingsScreen()
                        .navigationTransition(.zoom(sourceID: "settingsDoor", in: doorNS))
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
            // loadWalletHoldings FIRST — it sets the loading flag
            // synchronously before kicking off the fetch, so the very first
            // compose already knows to show the wallet slot's placeholder
            // rather than nothing.
            loadWalletHoldings()
            streamComposition()
            #if DEBUG
            // Debug hooks: `-openSettings YES` pushes Settings;
            // `-openProject "Work"` pushes a project — both for screenshots.
            if UserDefaults.standard.bool(forKey: "openSettings") {
                route.push = .settings
            }
            // `-openAppsDelay <s>` pushes the store after a delay — records
            // "tapping the grid door" (the zoom plays on the real push path).
            let appsDelay = UserDefaults.standard.double(forKey: "openAppsDelay")
            if appsDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(appsDelay))
                    withAnimation(DS.Motion.standard) { route.push = .apps }
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
    }

    private func streamComposition(instant: Bool = false) {
        // The first real pin is the lesson learned — the coach retires
        // forever, even if every pin is later removed.
        if !pinCoachDone, things.contains(where: \.pinned) { pinCoachDone = true }
        let doc = things.isEmpty
            ? HomeComposition.empty
            : HomeComposition.compose(things: things, walletHoldings: walletHoldings,
                                      walletPending: walletHoldingsLoading, pinCoach: !pinCoachDone)
        if instant {
            stream.paint(doc.lines)   // an update, not an entrance — no typewriter
        } else {
            stream.stream(doc.lines)
        }
        syncBoard(doc.boardRefs)
    }

    /// Re-derives the board's display order after a compose: which root refs
    /// are modules this time (a wallet can appear/disappear from one compose
    /// to the next), and where the saved arrangement puts them. Modules the
    /// composer names today but the saved order never saw (a freshly pinned
    /// wallet) land in their natural composed position — see
    /// `HomeBoardOrder.apply`.
    private func syncBoard(_ refs: [String]) {
        boardModuleRefs = Set(refs)
        let naturalKeys = dedupedKeys(refs)
        var refForKey: [String: String] = [:]
        for (ref, key) in zip(refs, naturalKeys) { refForKey[key] = ref }
        boardOrder = HomeBoardOrder.shared.apply(to: naturalKeys).compactMap { refForKey[$0] }
        boardRows = packRows(boardOrder)
    }

    /// Stable persistence keys for a run of refs, in order. Two wallets can
    /// carry the same label (WalletStore only guards address uniqueness, never
    /// label), so a colliding `moduleKey` gets a positional " #n" suffix — a
    /// second "Main" wallet earns its own slot instead of overwriting the
    /// first's. `syncBoard` (which READS the saved order) and the reorder save
    /// (which WRITES it) MUST derive keys the same way, or a duplicate-labeled
    /// board never round-trips — save wrote bare keys, apply matched suffixed
    /// ones, and the arrangement silently reset (review 2026-07-12).
    private func dedupedKeys(_ refs: [String]) -> [String] {
        var seen: [String: Int] = [:]
        var keys: [String] = []
        for ref in refs {
            var key = moduleKey(ref)
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            if count > 1 { key += " #\(count)" }
            keys.append(key)
        }
        return keys
    }

    /// Packs the flat board order into magazine rows (prd 58f): a run of
    /// REGULAR image-media modules pairs 2-up; everything else (structural
    /// modules, social posts, and any LARGE media module as a full-bleed
    /// feature) spans its own full-width row.
    private func packRows(_ order: [String]) -> [[String]] {
        var rows: [[String]] = []
        var pending: [String] = []
        func flush() {
            var i = 0
            while i < pending.count {
                if i + 1 < pending.count { rows.append([pending[i], pending[i + 1]]); i += 2 }
                else { rows.append([pending[i]]); i += 1 }
            }
            pending = []
        }
        for ref in order {
            if isPairable(ref), !HomeModuleSize.shared.isLarge(moduleKey(ref)) {
                pending.append(ref)
            } else {
                flush()
                rows.append([ref])
            }
        }
        flush()
        return rows
    }

    /// Only image-media modules pair — a music/Pinterest/screenshot shelf
    /// makes a clean half-width art tile. Structural modules (pinned, wallet,
    /// map) and text posts (social) always span full width.
    private func isPairable(_ ref: String) -> Bool {
        ["musicShelf", "pinShelf", "shotShelf"].contains { ref.hasPrefix($0) }
    }

    /// A paired media module as a half-width magazine tile.
    @ViewBuilder private func magazineTile(_ ref: String) -> some View {
        GenRender(id: ref, els: stream.els)
            .environment(\.genMediaCompact, true)
            .frame(maxWidth: .infinity)
    }

    /// A stable identity for a board ref, independent of its slot index — a
    /// wallet's holdings map keeps its own key even as other wallets are
    /// pinned/unpinned and shift `walletMapN`'s number around.
    private func moduleKey(_ ref: String) -> String {
        if ref == "pinnedW" { return "pinned" }
        if ref == "map" { return "map" }
        if ref.hasPrefix("walletMap"), let el = stream.els[ref] {
            let eyebrow = el.str(0)
            let label = eyebrow.hasPrefix("@pin ") ? String(eyebrow.dropFirst(5)) : eyebrow
            return "wallet:\(label)"
        }
        return ref
    }

    /// Composing is synchronous; the holdings fetch isn't — load in the
    /// background and repaint (instant, like any other corpus change) once
    /// it lands. Unpinning drops the cells and repaints without them.
    private func loadWalletHoldings() {
        guard wallet.addresses.contains(where: \.pinnedToHome) else {
            walletHoldingsLoading = false
            if !walletHoldings.isEmpty {
                walletHoldings = []
                streamComposition(instant: true)
            }
            return
        }
        walletHoldingsLoading = true
        Task { @MainActor in
            walletHoldings = await WalletIngest.topHoldingsByWallet(pinnedOnly: true)
            walletHoldingsLoading = false
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
