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
    @Bindable private var route = HomeRoute.shared
    @Bindable private var wallet = WalletStore.shared
    @State private var stream = GenStream()
    @State private var openProject: ProjectRoute?
    @State private var pinnedThing: Thing?
    @State private var walletOpen = false
    /// Bumped by pull-to-refresh — token charts key their fetch on it.
    @State private var refreshTick = 0
    /// One retiring lesson for the size control (prd 58a): tap a pin, the
    /// card blooms to large. Retires on the first tap, forever.
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
    /// The composer's ref → stable-key map for this composition (`app:<source>`,
    /// `wallet:<label>`). Read by `moduleKey` so a board ref resolves to its
    /// persistence key WITHOUT waiting for the streamed doc to finish parsing —
    /// a `stream.els`-based key would be empty during the cold-launch stream and
    /// reset the saved arrangement (fix 2026-07-13).
    @State private var boardKeys: [String: String] = [:]
    /// Bumped when a module's size flips (tap the pin) so the board re-reads
    /// each module's magazine-vs-full state and re-packs. `HomeModuleSize`
    /// isn't observable, so this @State is what actually forces the repaint;
    /// the packing itself now lives in the board's `MagazineLayout` (prd 58h,
    /// free drag), not a precomputed `[[String]]` of rows.
    @State private var boardSizeRevision = 0
    /// Drag-to-reorder auto-scroll (prd 58d): the board can grow past one
    /// screen, so a drag into the top/bottom edge nudges the ScrollView while
    /// the card keeps tracking the finger. `probe` carries the live scroll
    /// offset + viewport bounds to the board (a plain class — written every
    /// scroll frame, must not repaint); `scrollPos` is the board's handle to
    /// nudge the scroll. The board owns the loop (it also owns the drag and
    /// the reorder that must re-run as content slides).
    @State private var probe = BoardScrollProbe()
    @State private var scrollPos = ScrollPosition(edge: .top)
    /// Board edit mode (2026-07-12) — the long-press-to-jiggle rearrange state.
    /// Home owns it so the Done button can live in the fixed toolbar; the board
    /// flips it on the first lift and clears it on leaving Home.
    @State private var boardEditing = false

    struct ProjectRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }

    /// Thing-by-id lookup for the media tiles' thumbnail resolver — built once
    /// per render so each tile is an O(1) read, not a full corpus scan.
    private var thingsByID: [String: Thing] {
        Dictionary(things.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
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
                    // The magazine board — extracted so the body stays within
                    // the type-checker's budget (the merge of magazine packing
                    // and auto-scroll plumbing pushed it over, 2026-07-11).
                    boardSection
                }
                .padding(.bottom, ShellMetrics.bottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            // Auto-scroll plumbing for drag-to-reorder on a tall board: a
            // programmatic scroll handle, the live offset fed to the board's
            // probe, and the viewport's global bounds (the edge bands a drag
            // enters). All idle until a card is actually dragged to an edge.
            .scrollPosition($scrollPos)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                probe.y = y
            }
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { setViewport(g.frame(in: .global)) }
                        .onChange(of: g.frame(in: .global)) { _, f in setViewport(f) }
                }
            }
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
            // Edit mode's exit — the leading edge TopDoors leaves clear. Only
            // present while rearranging; tapping it stills the jiggle and locks
            // the new order in place (the board already persisted each move).
            .toolbar {
                if boardEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            DSHaptic.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                boardEditing = false
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
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
                // (The weekend recap's "@week" door is gone with the weekend
                // layout — prd 58j; the week ask lives in the composer now.)
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
            // A pinned app tile's rows are interactive: tap opens the thing;
            // long-press offers Open / Open in app. Removal is the whole app's
            // (the card's long-press "Remove from Home"), so a row carries no
            // Unpin — pinning is per-app now, not per-item.
            .environment(\.genThingOpen) { id in
                if let thing = things.first(where: { $0.id.uuidString == id }) {
                    pinnedThing = thing
                }
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
            // Tap the pin (prd 58a/58h) — cycles the module through the spans
            // it allows (small → wide → big, skipping any it can't take). The
            // pin never removes anything (unpin lives elsewhere per module),
            // so it's free to mean "press me".
            .environment(\.genSizeToggle) { ref in
                DSHaptic.selection()
                sizeCoachDone = true
                HomeModuleSize.shared.cycle(moduleKey(ref),
                                            allowed: allowedSpans(ref),
                                            default: defaultSpan(ref))
                // Span decides packing — bump the revision so the board re-reads
                // spans and re-packs (a grown module leaves its 2-up pair for a
                // full-width row, a shrunk one re-pairs). HomeModuleSize is
                // observed, but the board reads it through closures the revision
                // forces to re-run.
                withAnimation(DS.Motion.standard) {
                    boardSizeRevision += 1
                }
            }
            // Long-press → Remove from Home. A media shelf maps its ref → source
            // via the static table; a generic app tile carries its source in the
            // element (arg 3). An explicit pin is dropped (clear also forgets its
            // saved size/order); an auto-social account is hidden instead, so
            // "Show on Home" can bring it back. Either way, recompose so the
            // module leaves the board.
            .environment(\.genSourceUnpin) { ref in
                let source = HomePinnedSources.source(forModuleRef: ref)
                    ?? (ref.hasPrefix("appTile") ? stream.els[ref]?.str(3) : nil)
                guard let source else { return }
                DSHaptic.tap()
                // Drop any explicit pin first (also forgets the tile's saved
                // size/order). An auto-social account can be BOTH explicitly
                // pinned AND auto-shown, so also suppress the auto-show — else
                // its `sources` membership would resurrect the tile on the next
                // compose (setHidden alone left the explicit pin standing).
                HomePinnedSources.shared.clear(source)
                if HomePinnedSources.autoSocial.contains(source) {
                    HomePinnedSources.shared.setHidden(source, true)
                }
                CorpusSignal.shared.bump()
                streamComposition(instant: true)
                chrome.flash("Removed from Home")
            }
            // A screenshot's own stored thumbnail (prd 48) — local bytes,
            // not a URL, so the media tile resolves it by thing id. One O(1)
            // dict lookup per tile — the old `things.first(where:)` was a full
            // corpus scan per tile, up to 12 tiles a shelf (perf pass
            // 2026-07-13).
            .environment(\.genThumbnailData) { [thingsByID] id in
                thingsByID[id]?.previewImageData
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
        // Home synthesizes the surfaced corpus — search-only sources (Contacts)
        // stay out of the treemap the same way they stay out of the feed.
        let surfaced = Corpus.surfaced(things)
        let doc = surfaced.isEmpty
            ? HomeComposition.empty
            : HomeComposition.compose(things: surfaced, walletHoldings: walletHoldings,
                                      walletPending: walletHoldingsLoading)
        if instant {
            stream.paint(doc.lines)   // an update, not an entrance — no typewriter
        } else {
            stream.stream(doc.lines)
        }
        // Capture the stable keys BEFORE syncBoard reads them — the streamed
        // doc's elements aren't parsed yet, so moduleKey can't derive them from
        // stream.els; the composer handed them over instead.
        boardKeys = doc.boardKeys
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

    /// Only image-media modules pair — a music/Pinterest/screenshot shelf
    /// makes a clean half-width art tile. Structural modules (pinned, wallet,
    /// map) and text posts (social) always span full width.
    private func isPairable(_ ref: String) -> Bool {
        ["musicShelf", "pinShelf", "shotShelf"].contains { ref.hasPrefix($0) }
    }

    /// A module's effective span: the person's stored choice, or the default
    /// that opens the board one-hero.
    private func spanOf(_ ref: String) -> ModuleSpan {
        HomeModuleSize.shared.span(moduleKey(ref)) ?? defaultSpan(ref)
    }

    /// One-hero opening (prd 58h, revised 2026-07-12): the FIRST board module
    /// leads big — a hero slot that's positional, not welded to any one card.
    /// The old rule sized the "Pinned" bundle big; now that pins are ordinary
    /// tiles, the hero is a place any card can occupy (reorder to change it,
    /// grow any card yourself). A module that can't take `big` (a social post)
    /// stays small even when it leads. Everything else starts small and pairs.
    private func defaultSpan(_ ref: String) -> ModuleSpan {
        let allowed = allowedSpans(ref)
        // The hero slot leads big when its module can take it.
        if ref == boardOrder.first, allowed.contains(.big) { return .big }
        // A module that can't be a 1×1 square (an app tile is a full-width
        // list, never a paired thumbnail) starts at its smallest ALLOWED span,
        // not the shared `.small` default it can't render.
        if !allowed.contains(.small) { return allowed.first ?? .wide }
        return .small
    }

    /// The spans a module allows (the bento guardrails): a treemap needs area
    /// so it skips `wide`; an app tile is a full-width list of rows, so it
    /// skips the 1×1 `small` (a cramped square can't hold a readable row).
    /// Everything else can still shrink to a small square.
    private func allowedSpans(_ ref: String) -> [ModuleSpan] {
        if ref.hasPrefix("walletMap") || ref == "map" { return [.small, .big] }
        if ref.hasPrefix("appTile") { return [.wide, .big] }
        return [.small, .wide, .big]
    }

    /// A small (1×1) tile is what packs 2-up on the board; wide and big span
    /// the full width (a phone board is two columns), so only smalls pair.
    private func isMagazine(_ ref: String) -> Bool {
        spanOf(ref) == .small
    }

    /// The bento board (prd 58h): a single FLAT module order the person
    /// reorders freely — drag any card anywhere, it re-packs on drop. Small
    /// tiles pair 2-up; wide and big span the full width. The board linearizes
    /// while a drag is in flight so the drop is unambiguous, and auto-scrolls
    /// when a drag reaches an edge of a tall board (prd 58d).
    @ViewBuilder private var boardSection: some View {
        // Read so a span change (which bumps this) re-runs this body and hands
        // the board fresh spans — the pin's grow/shrink re-packing.
        let _ = boardSizeRevision
        ReorderableBoard(
            order: $boardOrder,
            editing: $boardEditing,
            content: { ref in moduleView(ref) },
            isMagazine: { isMagazine($0) },
            onReorder: { flat in
                // The board mutates $boardOrder in place; here we only persist.
                // Same keying as syncBoard's apply(), suffixes and all — bare
                // moduleKey here broke round-trip for two same-labeled modules.
                HomeBoardOrder.shared.save(dedupedKeys(flat))
            },
            scrollProbe: probe,
            scrollBy: { dy in
                withAnimation(.linear(duration: 0.05)) {
                    scrollPos.scrollTo(y: max(0, probe.y + dy))
                }
            })
    }

    /// One board module, rendered at its span. `genSpan` drives the distinct
    /// small (1×1) forms; `genModuleLarge` / `genMediaCompact` are derived from
    /// it so the existing two-state renderers (media strip/hero, moodboard)
    /// keep working. A small media shelf renders as its compact art tile.
    @ViewBuilder private func moduleView(_ ref: String) -> some View {
        let span = spanOf(ref)
        GenRender(id: ref, els: stream.els)
            .environment(\.genSpan, span)
            .environment(\.genModuleLarge, span == .big)
            .environment(\.genMediaCompact, span == .small && isPairable(ref))
            .frame(maxWidth: .infinity)
    }

    /// A stable identity for a board ref, independent of its slot index — a
    /// wallet's holdings map keeps its own key even as other wallets are
    /// pinned/unpinned and shift `walletMapN`'s number around.
    /// A ref's stable persistence key: the composer's `app:<source>` /
    /// `wallet:<label>` when it supplied one (see `HomeComposition.Document`),
    /// else the ref itself (media shelves, the map). Independent of the streamed
    /// doc's parse state, so a saved arrangement round-trips on cold launch.
    private func moduleKey(_ ref: String) -> String {
        boardKeys[ref] ?? ref
    }

    // MARK: - Drag-to-reorder auto-scroll

    private func setViewport(_ frame: CGRect) {
        probe.viewportTop = frame.minY
        probe.viewportBottom = frame.maxY
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
        // Pull RE-STREAMS the composition, it doesn't just repaint (A, ruling
        // 2026-07-12): the modules dissolve to their skeletons and stream back
        // in — the same entrance the first compose plays — so a pull reads as
        // the agent re-authoring Home before your eyes, not a spinner. (Every
        // other in-session update stays `instant` so only a deliberate pull
        // earns the re-compose.)
        streamComposition(instant: false)
        // The refresh LANDS — a soft thud as the fresh document starts landing
        // (2026-07-10 haptics pass: motion that completes gets felt).
        DSHaptic.success()
    }
}
