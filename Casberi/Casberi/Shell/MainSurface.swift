import SwiftUI
import SwiftData

/// The one surface (2026-07-13, drastic restructure): Home and Feed stopped
/// being separate tabs. The app is a single scrolling destination with a fixed
/// chip header — Pinned (your board) leads, then All, then every source. The
/// body under the header swaps between the board (Pinned) and the feed
/// (everything else); the composer is a FAB the shell floats over this.
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

    /// Chip order: Pinned, All, then every source most-recent-first (the app you
    /// just heard from sits up front). `things` is newest-first, so first
    /// appearance IS the newest thing per source.
    private var chipLabels: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for thing in feedThings where seen.insert(thing.source).inserted {
            ordered.append(thing.source)
        }
        return ["Pinned", "All"] + ordered
    }

    private var showingBoard: Bool { filter.source == "Pinned" }

    /// A shaped feed wears its source's hue (B ruling 2026-07-10): the whole
    /// top of the screen — status bar, doors, chip strip, then the feed's own
    /// header — sits on the source's wash hue, fading out as the day groups
    /// begin. Lives here (not inside FeedScreen) because the chip strip and
    /// status bar are OUTSIDE the feed's own view, on this shared surface
    /// (bug, 2026-07-14: the wash used to start at the feed's List, leaving
    /// the chips and status bar flat black above it). One recipe, no per-hue
    /// tuning — `DS.washHue` normalizes the brand hex (2026-07-13; the old
    /// mix-toward-black turned yellows olive and near-black marks to smudge)
    /// — and nil (no wash) for Pinned/All/a hueless source, honestly.
    ///
    /// Rendered as a BACKGROUND now, and BOLD (user ruling 2026-07-13,
    /// "bold like Cash App"): the hue is the solid field the content sits
    /// ON — full-strength at the crown, flowing into the page color — not a
    /// translucent film laid over the rows. The old overlay approach (which
    /// existed because FeedScreen's opaque page paint hid a background wash)
    /// is retired the right way: a SHAPED feed skips its own opaque coat
    /// (`FeedScreen` checks the same `washHue`), so this field genuinely
    /// shows through behind the rows instead of tinting them from above.
    @ViewBuilder private var shapeWash: some View {
        if let hue = DS.washHue(for: filter.source) {
            LinearGradient(stops: [
                .init(color: hue, location: 0),
                .init(color: hue, location: 0.4),
                .init(color: hue.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: 620)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
                .id(filter.source)   // crossfade between hues, not a smear
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The fixed navigation strip — always in reach, never scrolls
                // away with content (the whole point of dropping the tab bar).
                SourceChips(labels: chipLabels, active: filter.source) { label in
                    if label == filter.source {
                        // Re-tapping the chip you're already on pops back to
                        // root (the old per-tab habit) instead of doing nothing.
                        chrome.popHome += 1
                        return
                    }
                    withAnimation(DS.Motion.standard) {
                        filter.source = label
                        // Leaving the board for the feed clears any stray kind
                        // filter so "All" means all; entering the board is
                        // source-only. A specific source keeps its own tag.
                        if label == "Pinned" || label == "All" { filter.tag = "All" }
                    }
                }
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s2)

                // The body under the header — the board, or the feed.
                Group {
                    if showingBoard {
                        HomeScreen()
                    } else {
                        FeedScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // The themed page behind the chip header too — the header sits
            // OUTSIDE the screens' own dsPageBackground, so in light mode the
            // stack's white UIKit backing showed through here and drew a hard
            // seam against the gray page below (the no-hairlines law, made of
            // background). Just the color coat, not DSPageBackground: the
            // screens already render the theme photo themselves, and a second
            // full render here would be pure waste under an opaque layer.
            .background {
                ZStack(alignment: .top) {
                    DS.themedPage
                    shapeWash
                }
                .ignoresSafeArea()
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
            // The FAB rides the ROOT surface only (2026-07-13 polish): pushed
            // rooms (Apps, Settings, a token form) slide over it — a compose
            // button isn't theirs. RootShell still owns the composer sheet.
            .overlay(alignment: .bottomTrailing) {
                ComposerFAB {
                    DSHaptic.tap()
                    chrome.openComposer()
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
            }
            // Refresh delight (2026-07-14): every pull on this one surface
            // bumps chrome.refreshPulse — the berry rain falls over the
            // content and the avatar door spins (below). Decorative only;
            // hit-testing is off inside BerryRain.
            .overlay { BerryRain(trigger: chrome.refreshPulse) }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                // The shared doors — one place now, not duplicated onto two
                // tab roots. Any pull-to-refresh spins the avatar (the old
                // Home-only rule died with the tabs; restored 2026-07-14
                // after the tab-drop rewire orphaned the trigger).
                TopDoors(onSettings: { route.push = .settings },
                         onApps: { route.push = .apps },
                         refreshSpin: chrome.refreshPulse,
                         zoomNS: doorNS)
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
        }
        .tint(DS.tint)
    }
}
