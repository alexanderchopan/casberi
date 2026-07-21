import SwiftUI
import SwiftData

/// The one surface (2026-07-13, drastic restructure; the Pinned board
/// retired 2026-07-20, docs/agent-brief.md rulings 11-12): the app is a
/// single scrolling destination with a fixed chip header — All leads, then
/// every source. Content-first, always: the per-app glance job the board
/// used to carry moved to the agent's own kept-ask chips; this surface is
/// uniformly the feed now. The agent's bar floats over this from RootShell's
/// own ZStack (not this surface's — it rides every screen this app pushes).
///
/// This container owns the ONE `NavigationStack` and the shared management
/// doors (avatar → Settings, grid → Apps) so they can't drift between screens
/// or reconcile two route singletons the way the old Home/Feed split did. Each
/// body keeps its own inner pushes (a project, a bridge panel) but no longer
/// carries a stack of its own.
struct MainSurface: View {
    @Query(sort: \Thing.capturedAt, order: .reverse) private var things: [Thing]
    @Environment(ShellChrome.self) private var chrome
    @Bindable private var filter = FeedFilter.shared
    @Bindable private var route = HomeRoute.shared
    /// Wallet moments (NFT arrivals, new highs) — the data paths can't reach
    /// the corpus-arrival watcher that fires the release rain (NFTs/holdings
    /// aren't things), so they enqueue here and this surface deals the same
    /// berry rain + toast (delight 2026-07-15).
    private let walletMoments = WalletMoments.shared
    /// Anchors the doors' zoom transitions (each room grows from its door).
    @Namespace private var doorNS

    /// The corpus MINUS search-only sources (Contacts) — the same rule Home and
    /// Feed already share (`Corpus.surfaced`), so the chip row lists exactly the
    /// sources the feed shows.
    private var feedThings: [Thing] { Corpus.surfaced(things) }

    /// First-ever thing from a source blooms its hue across the header once.
    @State private var bloomHue: Color?
    /// Generation token — a second bloom inside the first's 1.4s window must
    /// not be cut short by the first's clear timer (review catch 2026-07-13).
    @State private var bloomGen = 0
    /// The ids seen at the last watcher pass — the arrival watcher diffs
    /// against them, because "newest thing changed + captured recently" was
    /// wrong twice over (review catches 2026-07-13): a DELETION resurfaces
    /// the runner-up, and a bridge item lands with its PUBLISH date as
    /// capturedAt, so an article published an hour ago never read as fresh
    /// even though it just arrived. Set-diff on the real records instead.
    @State private var seenIDs: Set<UUID>?

    /// Chip order: All, then every source most-recent-first (the app you just
    /// heard from sits up front). `things` is newest-first, so first
    /// appearance IS the newest thing per source.
    private var chipLabels: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for thing in feedThings where seen.insert(thing.source).inserted {
            ordered.append(thing.source)
        }
        return ["All"] + ordered
    }

    /// The pager's pages — every chip is a feed now (the board's own
    /// non-swiping page retired with it, 2026-07-20).
    private var feedLabels: [String] {
        var labels = chipLabels
        // The selected source ALWAYS gets a page, even with nothing in it.
        // The chip row is built from things that exist, but `filter.source` is
        // written unvalidated — a deep link (casberi://feed/source/Gmail), a
        // bridge connected but not yet synced, or deleting the last thing from
        // the room you're standing in all name a source with no chip. Without
        // this, the selection matches no `.tag`, and a TabView with an
        // unmatched selection quietly renders a DIFFERENT page: the Gmail wash
        // painted over the All feed, no chip lit, and the honest "Nothing from
        // Gmail yet" empty state unreachable (measured 2026-07-16).
        if !labels.contains(filter.source) {
            labels.append(filter.source)
        }
        return labels
    }

    // The per-source brand-hue wash that once flooded this surface is gone
    // (user ruling 2026-07-18: full ink). A feed's identity lives in its chip
    // and icon, not a borrowed brand-color field — the wash read as decoration
    // over the content, and hues like Calendar's red collided with the
    // alert/loss meaning red carries elsewhere. The feed now sits on the
    // neutral `DS.themedPage` like the board does. (`DS.washHue` stays for the
    // sheet/detail/setup surfaces, which still wear a source's identity.)

    var body: some View {
        NavigationStack {
            // The feeds are one pager (2026-07-16): a chip tap and a swipe are
            // the same move, because selection binds to the SAME value the chips
            // write — so the strip, the wash, and every deep link
            // (casberi://feed/source/X) all keep working with no second source of
            // truth to reconcile. Uniformly the feed now (the board's own
            // non-swiping page retired 2026-07-20).
            TabView(selection: $filter.source) {
                ForEach(feedLabels, id: \.self) { label in
                    FeedScreen(source: label,
                               isActive: label == filter.source)
                        .tag(label)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The strip FLOATS over the feed rather than sitting above it
            // (2026-07-20). It was a VStack sibling, which meant nothing ever
            // passed behind the chips — so the glass they wear blurred a flat
            // color and rendered indistinguishable from a solid fill, paying a
            // backdrop blur for nothing. `safeAreaInset` reserves the strip's
            // height at rest (rows still start below it, untouched) while letting
            // scrolled content travel UNDER it, which is the only thing that makes
            // the material read as glass. Pairs with each feed's `dsSoftTopEdge()`:
            // the scroll edge dissolves content as it goes under, so rows melt into
            // the strip instead of colliding with it.
            .safeAreaInset(edge: .top, spacing: 0) {
                // The fixed navigation strip — always in reach, never scrolls
                // away with content (the whole point of dropping the tab bar).
                // The avatar leads it now too (2026-07-20) — the system nav
                // bar it used to sit in alone is hidden below, so this strip
                // owns the top of the screen outright; the extra top padding
                // (was s2) is that vacated space becoming air, not bigger
                // chips (the 56pt Stories size is a 2026-07-10 ruling, not
                // being revisited here).
                SourceChips(labels: chipLabels, active: filter.source,
                            onApps: { route.push = .apps },
                            onSettings: { route.push = .settings },
                            refreshSpin: chrome.refreshPulse,
                            zoomNS: doorNS) { label in
                    if label == filter.source {
                        // Re-tapping the chip you're already on pops back to
                        // root (the old per-tab habit) instead of doing nothing.
                        chrome.popHome += 1
                        return
                    }
                    withAnimation(DS.Motion.standard) {
                        filter.source = label
                        // Entering "All" means all; a specific source keeps
                        // its own tag.
                        if label == "All" { filter.tag = "All" }
                    }
                }
                .padding(.top, DS.Space.s6)
                .padding(.bottom, DS.Space.s2)
            }
            // The themed page behind the chip header too — the header sits
            // OUTSIDE the screens' own dsPageBackground, so in light mode the
            // stack's white UIKit backing showed through here and drew a hard
            // seam against the gray page below (the no-hairlines law, made of
            // background). Just the color coat, not DSPageBackground: the
            // screens already render the theme photo themselves, and a second
            // full render here would be pure waste under an opaque layer.
            .background {
                DS.themedPage.ignoresSafeArea()
            }
            // The first-thing bloom — a new app's first landing washes its
            // hue across the header for a beat, then fades. The one moment
            // the connect promise visibly comes true (delight 2026-07-13).
            .overlay(alignment: .top) {
                if let bloomHue {
                    LinearGradient(colors: [bloomHue.opacity(0.8), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 300)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onAppear {
                seenIDs = Set(feedThings.map(\.id))
                // A door push that raced launch — casberi://settings arriving
                // before the first frame — was set before this stack
                // registered its navigationDestination, and SwiftUI drops
                // such a push: the app lands on Home with the route pointing
                // at a room that never opened (audit 2026-07-13; .settings
                // dropped on early sets while post-mount sets always land).
                // Re-land it now that the stack is up: clear, then set one
                // turn later so the destination sees a fresh value.
                if let early = route.push {
                    route.push = nil
                    Task { @MainActor in route.push = early }
                }
            }
            .onChange(of: feedThings.count) { _, _ in
                let ids = Set(feedThings.map(\.id))
                defer { seenIDs = ids }
                // nil = the query hasn't been baselined yet (cold mount).
                guard let seen = seenIDs else { return }
                let fresh = ids.subtracting(seen)
                // 1–12 fresh records is an arrival (one capture, one bridge
                // sync burst); more is a backfill (an import, the initial
                // populate) — a bob for a bulk import would be noise.
                guard !fresh.isEmpty, fresh.count <= 12 else { return }
                // The loudest voice of the batch: its newest member.
                guard let lead = feedThings.first(where: { fresh.contains($0.id) })
                else { return }
                // First-ever = nothing OLDER from this source survives AND
                // the source has never bloomed before (persistent — pruning
                // old things must not replay the connect celebration).
                let bloomedKey = "bloom.seen.\(lead.source)"
                let hasOlder = feedThings.contains {
                    $0.source == lead.source && !fresh.contains($0.id)
                }
                let firstEver = !hasOlder
                    && !UserDefaults.standard.bool(forKey: bloomedKey)
                chrome.chipCaught(lead.source, firstEver: firstEver)
                // A repo you star shipping a MAJOR release (a clean x.0.0) is a
                // moment worth marking: the berry rain falls and a toast names
                // it. One celebration per arrival batch — the marker is stamped
                // at ingest (GitHubFeedFetch.isMajorRelease).
                if let major = feedThings.first(where: {
                    fresh.contains($0.id) && $0.source == "GitHub"
                        && $0.tags.contains(GitHubFeedFetch.majorReleaseTag)
                }) {
                    chrome.refreshPulse += 1
                    chrome.flash(String(localized: "\(major.title) is out 🎉"))
                }
                if firstEver {
                    UserDefaults.standard.set(true, forKey: bloomedKey)
                    let hue = DS.washHue(for: lead.source) ?? DS.tint
                    bloomGen += 1
                    let gen = bloomGen
                    withAnimation(.easeOut(duration: 0.45)) { bloomHue = hue }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1400))
                        // Only the LATEST bloom clears itself — an older
                        // timer must not cut a newer bloom short.
                        guard gen == bloomGen else { return }
                        withAnimation(.easeOut(duration: 0.9)) { bloomHue = nil }
                    }
                }
            }
            // A wallet moment landed (an NFT arrived, a new high) — deal the
            // same berry rain + toast the starred-repo release uses, so every
            // wallet celebration reads the same. The line names the moment.
            .onChange(of: walletMoments.pulse) {
                let lines = walletMoments.drain()
                guard let latest = lines.last else { return }
                // Rain once for the batch; name the most recent moment. A queue
                // (not a single slot) means a moment fired while backgrounded
                // survives here until this drain runs on foreground.
                chrome.refreshPulse += 1
                chrome.flash(latest)
            }
            // The agent bar moved OFF MainSurface entirely (docs/agent-brief.md
            // ruling 6): it now rides RootShell's own ZStack, above EVERY
            // screen this app can push (Apps, Settings, a bridge setup form),
            // not just this one's root — the FAB used to stop at MainSurface's
            // edge on purpose; the bar deliberately doesn't.
            // Refresh delight (2026-07-14): every pull on this one surface
            // bumps chrome.refreshPulse — the berry rain falls over the
            // content and the avatar door spins (below). Decorative only;
            // hit-testing is off inside BerryRain.
            .overlay { BerryRain(trigger: chrome.refreshPulse) }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // The nav bar itself is hidden now (2026-07-20) — nothing lives
            // in it anymore. The avatar (was the sole trailing toolbar item,
            // `TopDoors`) joined the catalogue door as a fixed leading chip
            // in `SourceChips` above; that strip owns the top of the screen
            // outright. First `.toolbar(.hidden, for:)` in this codebase —
            // there was nothing to hide FROM before this move.
            .toolbar(.hidden, for: .navigationBar)
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
            // The ONE bridge-screen registration for the whole stack (see
            // `HomeRoute.bridgePush`) — Feed's Manage, an Apps tile's
            // capsule, and a product page's Connect/Open all push through
            // this single binding regardless of how deep they sit, so the
            // pushed screen always gets a correct back chevron.
            .navigationDestination(item: $route.bridgePush) { dest in
                BridgeDestinationView(destination: dest)
            }
        }
        .tint(DS.tint)
    }
}
