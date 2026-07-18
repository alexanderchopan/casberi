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
    /// A bridge's own screen (wallet, tokens, a setup screen, …) — ONE shared
    /// push target for every entry point (Feed's Manage, Apps' tile capsules,
    /// a product page's Connect/Open), registered as a single
    /// `navigationDestination` at the shell (`MainSurface`). Before this,
    /// three screens each registered their own `navigationDestination(item:)`
    /// for the same `BridgeRouter.Destination` type at different depths of
    /// the one shared NavigationStack — undefined per Apple's "one
    /// destination provider per type per stack" rule, and the reported
    /// symptom (audit 2026-07-15) was a pushed bridge screen with no working
    /// back chevron.
    var bridgePush: BridgeRouter.Destination?
    /// A tag to open as its own view — set by an Ask answer that names a tag,
    /// so "what did I save about work" opens the Work view the treemap opens.
    var openTag: String?
    /// An offer whose product page should open once the catalog lands — set
    /// by the empty feed's pile (a tile is a door to that app's page, not
    /// just to the shelf); AppsScreen consumes it on appear, after the
    /// `.apps` push above has mounted the stack.
    var openOffer: String?
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
    @Query(sort: \Thing.capturedAt, order: .reverse) private var things: [Thing]
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Bindable private var route = HomeRoute.shared
    @Bindable private var wallet = WalletStore.shared
    @State private var stream = GenStream()
    /// The typewriter entrance plays ONCE per app session. MainSurface swaps
    /// HomeScreen in and out with an `if showingBoard` (board vs feed), so
    /// re-selecting the "Pinned" chip REBUILDS HomeScreen from scratch —
    /// resetting @State (including `stream`) and replaying the whole reveal on
    /// every visit, which read as "Home loads slowly" (report 2026-07-15). This
    /// process-lifetime flag keeps the cold-launch reveal but makes every later
    /// return an instant paint. Pull-to-refresh still re-streams deliberately
    /// (it passes `instant: false` itself).
    @MainActor private static var didPlayEntrance = false
    @State private var openProject: ProjectRoute?
    @State private var pinnedThing: Thing?
    @State private var walletOpen = false
    /// A tapped holdings cell whose token isn't watched — its quick chart.
    @State private var quickToken: TokenQuickRoute?
    /// Bumped by pull-to-refresh — token charts key their fetch on it.
    @State private var refreshTick = 0
    /// One retiring lesson for the size control (prd 58a): tap a pin, the
    /// card blooms to large. Retires on the first tap, forever.
    @AppStorage("coach.size.done") private var sizeCoachDone = false
    /// The last celebrated corpus milestone — each fires exactly once, ever.
    @AppStorage("milestone.reached") private var milestoneReached = 0
    @State private var walletHoldings: [WalletIngest.HoldingsGroup] = []
    /// The combined "Across your wallets" bundle across PINNED wallets — nil
    /// with one or zero pinned (2026-07-15). Leads the per-wallet maps on the
    /// board, matching the Wallet screen's combined view.
    @State private var walletCombined: WalletIngest.HoldingsGroup?
    /// True from the moment a pinned wallet's balance fetch starts until it
    /// resolves — lets the composer show an honest loading placeholder in
    /// the wallet's slot instead of leaving it blank (device report,
    /// 2026-07-11: the empty window during that real network round-trip
    /// read as "my holdings disappeared").
    @State private var walletHoldingsLoading = false
    /// True when at least one pinned wallet couldn't be reached AND has no
    /// last-known snapshot to fall back on — the one case that earns an honest
    /// "couldn't reach" card instead of a blank slot (ruling 2026-07-17). A
    /// reachable-but-empty wallet, or one showing its stale last-known card,
    /// leaves this false.
    @State private var walletUnreachable = false
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
    /// Board edit mode (2026-07-12) — the long-press-to-jiggle rearrange state.
    /// Home owns it so the Done button can live in the fixed toolbar; the board
    /// flips it on the first lift and clears it on leaving Home.
    @State private var boardEditing = false
    /// A corpus change arrived while the board was being rearranged
    /// (2026-07-13): recomposing then would REPLACE the board's modules under
    /// the lifted card — the drag dies, edit mode tears down, the person's
    /// grip just vanishes. Latch the recompose instead and run it when
    /// editing ends.
    @State private var recomposeDeferred = false
    /// Recompose storm guard (2026-07-15): a foreground triggers ~25
    /// concurrent bridge refreshes, each a separate `things.count` change —
    /// without this, each one ran a full synchronous `HomeComposition.compose`
    /// (O(corpus): project/source clustering plus a `things.filter` per pinned
    /// app and media shelf) back to back. The FIRST change in a burst still
    /// recomposes immediately (a solo capture must feel instant, unchanged);
    /// changes arriving during the cooldown window that follows are coalesced
    /// into exactly one trailing recompose instead of one each.
    @State private var recomposeCooldownActive = false
    @State private var recomposePendingDuringCooldown = false
    private static let recomposeCooldown: Duration = .milliseconds(400)

    struct ProjectRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }

    /// Thing-by-id lookup for the media tiles' thumbnail resolver — built once
    /// per render so each tile is an O(1) read, not a full corpus scan.
    private var thingsByID: [String: Thing] {
        Dictionary(things.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Topic blocks open project detail, not a Feed filter (gap §9.1). The
    /// source-fallback map's cells name APPS, not tags — those open the
    /// source's feed (a tag view for a nonexistent tag is a dead end).
    /// Extracted from the body (2026-07-14): inline, the closure tipped the
    /// board's already-deep expression over the type-checker's budget.
    private func handleProjectTap(_ name: String) {
        // A routed holdings cell opens its token's chart (2026-07-14):
        // the thing sheet when the token is watched, the quick sheet
        // when it isn't.
        if let tokenRoute = TokenQuickRoute.from(sentinel: name) {
            if let thing = tokenRoute.watchedThing(in: modelContext) {
                pinnedThing = thing
            } else {
                quickToken = tokenRoute
            }
            return
        }
        // A routeless holdings cell (a native coin) routes to the
        // Wallet screen — no per-token view to open (2026-07-10).
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
            // Selecting the source in the shared header swaps the board
            // for that source's shaped feed — no separate destination,
            // no back arrow (the chip strip is the way back now).
            withAnimation(DS.Motion.standard) {
                FeedFilter.shared.source = name
                FeedFilter.shared.tag = "All"
            }
        } else {
            openProject = ProjectRoute(name: name)
        }
    }

    var body: some View {
            // The single surface (MainSurface) owns the NavigationStack, the
            // fixed chip header, and the shared doors now — this is the board
            // body hosted inside that one stack, shown when "Pinned" leads. The
            // cover no longer bleeds to the status bar (the chip strip sits
            // above it); the geometry reader still hands the cover its eyebrow
            // inset.
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
                    // No section header over the board (user 2026-07-17: the
                    // "Keeping an eye on" title "just sounds trite — pinned to
                    // Home IS the point of the page"). The board follows the
                    // one intelligence card directly; the tiles' own names and
                    // signals carry it.
                    //
                    // One retiring line (prd 58a) — shown until the first
                    // resize (or the first edit-mode entry), forever, same
                    // grammar as the pin coach. Now that the size pin lives in
                    // edit mode, the coach teaches the hold that reveals it.
                    if !sizeCoachDone, !boardOrder.isEmpty {
                        // Secondary ink, not tint — a coach line isn't a
                        // control, and tint-colored prose reads as a link.
                        // "Rearrange" only (2026-07-17): rows — most of the
                        // board now — drag but never resize; the size pin
                        // teaches itself in edit mode on the modules that
                        // still take it.
                        Text("Touch and hold to rearrange")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s1)
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
            .environment(\.genProjectTap) { handleProjectTap($0) }
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
            //
            // The pin shows ONLY in edit mode now (de-cute, 2026-07-18): every
            // board tile wore a standing size pin at rest — three pieces of
            // meta-chrome (pin + wallet @pin mark + edit badges) on a screen
            // whose law is "no dead controls, the content carries it". Every
            // ShelfSizePin render site gates on this closure being non-nil
            // (`if let sizeToggle`), so handing it nil at rest hides all nine at
            // once; a long-press lift arms edit mode and brings them back beside
            // the remove badge (the iOS hold → wobble → resize grammar removal
            // already moved to, ruling 2026-07-14). Sizes still render at rest;
            // only the CONTROL hides.
            .environment(\.genSizeToggle, sizeToggleAction)
            // Long-press → Remove from Home. A media shelf maps its ref → source
            // via the static table; a generic app tile carries its source in the
            // element (arg 3). An explicit pin is dropped (clear also forgets its
            // saved size/order); an auto-social account is hidden instead, so
            // "Show on Home" can bring it back. Either way, recompose so the
            // module leaves the board.
            .environment(\.genSourceUnpin) { ref in moduleRemoval(ref)?() }
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
            .sheet(item: $quickToken) { route in
                TokenQuickSheet(route: route)
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
            // Apps/Settings moved to the shell's shared destination
            // (MainSurface) — the doors live there once now.
            .navigationDestination(isPresented: $walletOpen) {
                BridgeDestinationView(destination: .wallet)
            }
            }
        // Re-tapping the surface pops pushed screens and sheets back to root.
        .onChange(of: chrome.popHome) {
            route.push = nil
            openProject = nil
            pinnedThing = nil
            walletOpen = false
            quickToken = nil
        }
        // The corpus changed under the composition (a capture, the demo
        // seeds, the dissolve) — repaint instantly, no replayed entrance.
        // While the board is being rearranged the repaint DEFERS (see
        // recomposeDeferred) so a bridge sync can't yank the modules out
        // from under a drag in flight.
        .onChange(of: things.count) {
            recomposeOrDefer()
            celebrateMilestone()
        }
        // A tag rename/retag leaves the count unchanged but changes what Home
        // composes from — repaint so the renamed tag shows immediately.
        .onChange(of: CorpusSignal.shared.revision) { recomposeOrDefer() }
        // Edit mode ended — land any recompose that arrived mid-rearrange.
        // Entering it retires the resize coach (the hold it teaches just
        // happened), so someone who only ever reorders isn't nagged forever.
        .onChange(of: boardEditing) { _, editing in
            if editing { sizeCoachDone = true }
            if !editing, recomposeDeferred {
                recomposeDeferred = false
                streamComposition(instant: true)
            }
        }
        // The on-device "Noticed" line landed (or changed, or cleared) — repaint
        // so it appears under the cover. Routed through recomposeOrDefer so it
        // waits out an in-flight rearrange like any other recompose.
        .onChange(of: HomeInsightStore.shared.line) { recomposeOrDefer() }
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
            // Stream the reveal on the session's first Home compose; every later
            // board rebuild (chip re-tap) paints instantly (see didPlayEntrance).
            streamComposition(instant: HomeScreen.didPlayEntrance)
            #if DEBUG
            // Debug hook: `-openProject "Work"` pushes a project — for
            // screenshots. (`-openSettings`/`-openAppsDelay` moved to
            // RootShell's onAppear, 2026-07-14: this screen only mounts when
            // the landing chip is "Pinned", so on an unpinned install the
            // hooks here never fired — and even when they did, a first-frame
            // push could land before MainSurface's navigationDestination
            // registered and get dropped. Audit finding 2026-07-13.)
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

    /// Recompose now — unless the person is mid-rearrange, in which case
    /// latch it for the moment they tap Done (or leave Home). Otherwise runs
    /// through the recompose-storm cooldown: the first call in a burst fires
    /// immediately, later calls during the cooldown window coalesce into one
    /// trailing recompose (see `recomposeCooldownActive`'s doc).
    private func recomposeOrDefer() {
        if boardEditing {
            recomposeDeferred = true
            return
        }
        guard !recomposeCooldownActive else {
            recomposePendingDuringCooldown = true
            return
        }
        streamComposition(instant: true)
        recomposeCooldownActive = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.recomposeCooldown)
            recomposeCooldownActive = false
            if recomposePendingDuringCooldown {
                recomposePendingDuringCooldown = false
                recomposeOrDefer()
            }
        }
    }

    private func streamComposition(instant: Bool = false) {
        // Any full recompose satisfies a deferral latched mid-edit.
        recomposeDeferred = false
        // Home synthesizes the surfaced corpus — search-only sources (Contacts)
        // stay out of the treemap the same way they stay out of the feed.
        let surfaced = Corpus.surfaced(things)
        // Refresh the on-device "Noticed" line off the render path. Cheap and
        // idempotent (a signature check returns early when nothing moved), so
        // calling it on every compose is the natural throttle — a landed line
        // repaints through the `HomeInsightStore.shared.line` observer above.
        HomeInsightStore.shared.refresh(from: surfaced)
        let doc = surfaced.isEmpty
            ? HomeComposition.empty
            : HomeComposition.compose(things: surfaced, walletHoldings: walletHoldings,
                                      walletCombined: walletCombined,
                                      walletPending: walletHoldingsLoading,
                                      walletUnreachable: walletUnreachable,
                                      insight: HomeInsightStore.shared.line,
                                      insightThing: HomeInsightStore.shared.pickedThingID)
        if instant {
            stream.paint(doc.lines)   // an update, not an entrance — no typewriter
        } else {
            stream.stream(doc.lines)
            // The one entrance for this session has now played — later board
            // rebuilds (a "Pinned" re-tap) paint instantly instead of replaying.
            HomeScreen.didPlayEntrance = true
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

    /// The board's size control, handed to the renderer via `genSizeToggle`.
    /// nil at rest (the size pin gates on it, so nil hides every pin); the
    /// live cycle-through-spans closure only in edit mode (de-cute 2026-07-18).
    /// A typed property, not an inline ternary, so the closure's type is
    /// unambiguous and the escaping `self` capture reads plainly.
    private var sizeToggleAction: ((String) -> Void)? {
        guard boardEditing else { return nil }
        return { ref in
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
    }

    /// A module's effective span: the person's stored choice, or the default
    /// that opens the board one-hero.
    private func spanOf(_ ref: String) -> ModuleSpan {
        // CLAMP the person's stored choice to what the module currently allows
        // (2026-07-17): a module's allowed spans can shrink under it — app rows
        // went wide-only, the GitHub graph to one width — and a stale stored
        // size (a Bluesky/Farcaster row still carrying `.small` from its
        // resizable-tile era) would otherwise pair a full-width row 2-up at
        // half width (the "Farcaster" that wrapped). An out-of-range stored
        // size is ignored, falling back to the default.
        let allowed = allowedSpans(ref)
        if let stored = HomeModuleSize.shared.span(moduleKey(ref)), allowed.contains(stored) {
            return stored
        }
        return defaultSpan(ref)
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
        if !allowed.contains(.small) { return allowed.first ?? .wide }
        return .small
    }

    /// The spans a module allows (the bento guardrails). Every board module
    /// left on Home is a row now (Themes and the wallet treemap both moved to
    /// feeds, 2026-07-18) — the only remaining non-row is GitHub's grid.
    private func allowedSpans(_ ref: String) -> [ModuleSpan] {
        // The contribution graph is a 53-wide grid — one wide strip, full
        // width, content height (2026-07-17: it never squared into a tile or
        // resized; the grid IS its size).
        if ref == "githubGraphShelf" { return [.wide] }
        // An app ROW has exactly one size (prd 120), the Wallet row included —
        // draggable for order, never resizable, never paired. One form is the
        // point.
        if ref.hasPrefix("appRow") || ref == "walletRow" { return [.wide] }
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
    /// when a drag reaches an edge of a tall board (prd 58d) — the board's
    /// UIKit drag driver finds the enclosing scroll view and owns all of it.
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
            })
    }

    /// One board module, rendered at its span. `genSpan` drives the distinct
    /// small (1×1) forms; `genModuleLarge` / `genMediaCompact` are derived from
    /// it so the existing two-state renderers (media strip/hero, moodboard)
    /// keep working. A small media shelf renders as its compact art tile.
    /// While the board wobbles, removable modules wear the minus badge —
    /// removal's reachable home (ruling 2026-07-14): the board's long-press
    /// belongs to lift/reorder (the drag driver pre-empts context menus), so
    /// removal lives where iOS taught it: hold → wobble → tap the minus.
    @ViewBuilder private func moduleView(_ ref: String) -> some View {
        let span = spanOf(ref)
        GenRender(id: ref, els: stream.els)
            .environment(\.genSpan, span)
            .environment(\.genModuleLarge, span == .big)
            .environment(\.genMediaCompact, span == .small && isPairable(ref))
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                if boardEditing, let remove = moduleRemoval(ref) {
                    BoardRemoveBadge(action: remove)
                        // Overhangs the corner, the system's own grammar —
                        // the size pin keeps the opposite corner.
                        .offset(x: -6, y: -6)
                }
            }
    }

    /// The board's remove verb for a module, when it has one — the edit-mode
    /// badge and the (currently driver-shadowed) context menus share this
    /// single derivation, so the two paths can't drift. nil for modules with
    /// nothing to remove (auto-earned shelves, the cover) — those wear no
    /// badge (honesty rule: no dead controls).
    private func moduleRemoval(_ ref: String) -> (() -> Void)? {
        // The Wallet row — removing it unpins every wallet that put it there
        // (the treemap/NFTs stay, they're the Wallet FEED's now, not Home's;
        // 2026-07-18). Its own source name doesn't route through
        // `HomePinnedSources` like every other row (the Wallet row's presence
        // is driven by `pinnedToHome`, not the hide/show set), so it needs
        // this dedicated case.
        if ref == "walletRow" {
            guard wallet.addresses.contains(where: \.pinnedToHome) else { return nil }
            return {
                DSHaptic.tap()
                for i in wallet.addresses.indices { wallet.addresses[i].pinnedToHome = false }
                loadWalletHoldings()
                chrome.flash("Removed from Home")
            }
        }
        let source = HomePinnedSources.source(forModuleRef: ref)
            ?? (stream.els[ref]?.comp == "AppRow" ? stream.els[ref]?.str(0) : nil)
        guard let source, !source.isEmpty else { return nil }
        // An auto-earned media shelf has no pin to drop (its context menu
        // hides for the same reason) — no badge.
        if let el = stream.els[ref], el.comp == "MediaShelf", el.str(4) != "pin" {
            return nil
        }
        return {
            DSHaptic.tap()
            // Auto-pin (2026-07-18): every connected source shows unless hidden,
            // so removing a tile HIDES its source — that's the subtract control.
            // Clear any explicit pin too (and its saved size/order); clear()
            // also drops a stale hide, so set the hide AFTER it.
            HomePinnedSources.shared.clear(source)
            HomePinnedSources.shared.setHidden(source, true)
            CorpusSignal.shared.bump()
            streamComposition(instant: true)
            chrome.flash("Removed from Home")
        }
    }

    /// A ref's stable persistence key: the composer's `app:<source>` when it
    /// supplied one (see `HomeComposition.Document`), else the ref itself.
    /// Independent of the streamed doc's parse state, so a saved arrangement
    /// round-trips on cold launch.
    private func moduleKey(_ ref: String) -> String {
        boardKeys[ref] ?? ref
    }

    /// Composing is synchronous; the holdings fetch isn't — load in the
    /// background and repaint (instant, like any other corpus change) once
    /// it lands. Unpinning drops the cells and repaints without them. Both
    /// repaints ride the edit-mode deferral: these land asynchronously, so
    /// they must not replace the board under an in-flight rearrange.
    private func loadWalletHoldings() {
        guard wallet.addresses.contains(where: \.pinnedToHome) else {
            walletHoldingsLoading = false
            walletUnreachable = false
            if !walletHoldings.isEmpty || walletCombined != nil {
                walletHoldings = []
                walletCombined = nil
                recomposeOrDefer()
            }
            return
        }
        walletHoldingsLoading = true
        Task { @MainActor in
            // Holdings and the combined bundle are independent reads,
            // overlapped. The combined fetch returns nil with one pinned
            // wallet, so it costs nothing then. (NFTs dropped 2026-07-18 —
            // the Wallet row on Home carries only the total + top holdings;
            // the NFT strip lives on the Wallet feed now, fetched there.)
            async let pinned = WalletIngest.pinnedWalletHoldings()
            async let combined = WalletIngest.combinedHoldings(pinnedOnly: true)
            let holdings = await pinned
            walletHoldings = holdings.groups
            walletUnreachable = holdings.unreachableNoCache
            walletCombined = await combined
            walletHoldingsLoading = false
            recomposeOrDefer()
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
        // The corpus lives behind the All chip — a milestone gives it one
        // proud catch bob alongside the toast. Deferred half a second: the
        // capture that CROSSED the milestone is bobbing its own source chip
        // in this same runloop, and chipCaught's shared slot would clobber
        // one of the two beats (review catch 2026-07-13).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            chrome.chipCaught("All")
        }
        chrome.flash("\(crossed.formatted()) things banked.", tone: .success)
    }

    /// Pull-to-refresh: awaited (the spinner shows real work), then one
    /// repaint. The tick bump re-fetches every token chart.
    private func refreshLive() async {
        // A deliberate pull while the board is still jiggling reads as "I'm
        // done arranging" — end edit mode so the re-stream doesn't rebuild
        // the modules under a wobbling board.
        boardEditing = false
        refreshTick += 1
        chrome.refreshPulse += 1   // spins the avatar door, deals the berry rain
        // A deliberate pull means "re-fetch now" — drop the holdings cache so the
        // reads below go live, not TTL-cached (the cache exists to collapse the
        // automatic foreground fan-out, not to blunt an explicit pull).
        await WalletIngest.invalidateHoldingsCache()
        if wallet.addresses.contains(where: \.pinnedToHome) {
            async let pinned = WalletIngest.pinnedWalletHoldings()
            async let combined = WalletIngest.combinedHoldings(pinnedOnly: true)
            let holdings = await pinned
            walletHoldings = holdings.groups
            walletUnreachable = holdings.unreachableNoCache
            walletCombined = await combined
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

/// The edit-mode remove badge (ruling 2026-07-14) — a minus in a filled
/// circle on a removable module's top-left corner while the board wobbles.
/// Removal means "off the board", never delete, but the minus is the glyph
/// every thumb already knows for this exact gesture.
private struct BoardRemoveBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.textPrimary)
                .frame(width: 24, height: 24)
                .background(DS.gray200, in: Circle())
                // The visual stays a quiet 24pt; the target is a finger's.
                .contentShape(Circle().inset(by: -10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove from Home")
    }
}
