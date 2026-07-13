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
    /// Rendered as an OVERLAY, not a background: FeedScreen's own
    /// `.dsPageBackground()` is opaque and painted behind its entire List, so
    /// as a background this wash was fully hidden the instant the List began
    /// — a hard cut right under the chip row, not the fade the gradient
    /// itself describes (user, 2026-07-13). Sitting on top lets the same
    /// gradient tint the List's own background through to wherever it
    /// actually reaches `.clear`, instead of being clipped by whatever
    /// happens to render underneath it.
    @ViewBuilder private var shapeWash: some View {
        if let hue = DS.washHue(for: filter.source) {
            LinearGradient(colors: [hue.opacity(0.9), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
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
            .overlay(alignment: .top) { shapeWash }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                // The shared doors — one place now, not duplicated onto two
                // tab roots. Home's pull-to-refresh spins the avatar; the feed
                // never spins, so no spin trigger flows here.
                TopDoors(onSettings: { route.push = .settings },
                         onApps: { route.push = .apps },
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
