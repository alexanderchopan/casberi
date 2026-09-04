import SwiftUI
import SwiftData
import UIKit

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
// `WalletSection` is Foundation-only so `wallet-section-selftest.sh` can
// compile it WHOLE; the SwiftUI protocol therefore lands here, beside the
// only place that consumes it, rather than on the declaration. Vibenet's
// own scope enum conforms the same way beside its own call site — one
// control, two vocabularies, neither type dragging SwiftUI into a harness.
extension WalletSection: DSSectionScope {}

// Conformed beside the call site rather than on the declaration, for the
// reason Wallet's own does: `VibenetSection` stays Foundation-only so a
// `swiftc` harness can compile it WHOLE, and a SwiftUI protocol on the
// declaration ends that (prd §482).
extension VibenetSection: DSSectionScope {}
// The third room to take this control (prd §486), conformed beside the call
// site for the reason the two above are: `PrivacyPoolsSection` stays
// Foundation-only so `wallet-rooms-selftest.sh` can compile it WHOLE beside
// the room it scopes.
extension PrivacyPoolsSection: DSSectionScope {}

struct MainSurface: View {
    // Whole corpus, newest first — but hydrating ONLY the columns this surface
    // reads (2026-07-24 perf). This screen never renders a Thing's body
    // (FeedScreen does, with its own query); it only needs source/capturedAt
    // for the chip strip and id/tags/title for the arrival watcher. Without
    // `propertiesToFetch`, every write re-materialized the whole corpus WITH
    // its heavy inline text (content/enrichedText/postText) on the main
    // thread — the dominant steady-state cost as the corpus grows. Every
    // property read off `things`/`feedThings` here is in this set, so nothing
    // faults; the objects never leave this view.
    @Query(MainSurface.chipCorpus) private var things: [Thing]
    @Environment(\.modelContext) private var modelContext
    private static var chipCorpus: FetchDescriptor<Thing> {
        var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.propertiesToFetch = [\.id, \.source, \.capturedAt, \.title, \.tags]
        // BOUNDED (2026-08-06). `propertiesToFetch` made each row cheap and
        // never bounded how many, so this materialised the whole corpus every
        // time the body touched it — and `.onChange(of: things.count)` below
        // touches it on EVERY body pass, which is what made it 25.0% of the
        // main thread on a 6,000-row corpus (`main-thread-profile.sh`).
        //
        // What survives the bound is exactly what this query is still for: the
        // newest row for the resting pane (`latestArrival`), and the id set the
        // arrival watcher diffs. Both are inherently about what just landed, so
        // a recent window is the RIGHT input, not a compromised one — an
        // arrival is by construction near the top of a newest-first list.
        //
        // The chip SET no longer comes from here at all (`newestPerSource`),
        // because that question needs an exact answer at any age and a window
        // cannot give one. Two questions, two shapes.
        //
        // Two things the watcher relies on that the bound leaves intact: rows
        // ageing OUT of the window can never fake an arrival, since `fresh` is
        // a set SUBTRACTION and only additions count; and `firstEver` is
        // additionally gated on a persistent `bloom.seen.<source>` flag, so a
        // source whose older rows sit outside the window still cannot replay
        // its connect celebration.
        d.fetchLimit = 400
        return d
    }
    @Environment(ShellChrome.self) private var chrome
    /// Read for the LIVE-room chips only (prd §234) — a connected Kalshi or
    /// Polymarket earns a chip with nothing landed yet, since its room's
    /// content is the live book rather than the corpus.
    @Environment(BridgeStore.self) private var store
    // Per-WINDOW, not per-process (see `SceneState`): `RootShell` owns one of
    // each and injects them, so a second window routes and filters on its own.
    @Environment(FeedFilter.self) private var filter
    @Environment(HomeRoute.self) private var route
    /// The watch list behind the wallet face rail (prd §357) — this surface now
    /// draws that rail, so it reads the store directly rather than through the
    /// feed. Process-wide by nature: which wallets you watch is not a property
    /// of a window.
    @Bindable private var wallet = WalletStore.shared
    /// Mirrors `DemoMode.isActive` — the standing demo banner rides this
    /// surface's top inset (see the `.safeAreaInset` below). `@AppStorage`
    /// rather than a plain read so Exit removes it on the spot.
    // Reads the SAME store `DemoMode` writes. Under `-storeScratch` that is a
    // per-process suite, so a harness run still shows its own banner while
    // writing nothing into the person's real defaults; outside scratch this is
    // `.standard` exactly as before.
    @AppStorage("demo.mode.active", store: ScratchDefaults.standard)
    private var demoActive = false
    /// Anchors the doors' zoom transitions (each room grows from its door).
    @Namespace private var doorNS

    /// iPad (2026-07-25). `regular` alone decides the RAIL; the detail pane
    /// additionally needs real width (see `PadLayout.minWidthForPane`), so
    /// the shell measures itself rather than guessing from the idiom — an
    /// iPad mini in portrait and an iPad in Slide Over are both "iPad" and
    /// neither can hold two columns.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var surfaceWidth: CGFloat = 0
    @Environment(PadDetailSelection.self) private var detail

    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var showsPane: Bool { isRegular && surfaceWidth >= PadLayout.minWidthForPane }
    /// The rail is every regular-width surface now — iPad AND Mac (user
    /// ruling 2026-08-01, reversing 2026-07-28's "Mac keeps the horizontal
    /// strip"). That ruling pre-dates living with the detail pane, and the
    /// pane is what made it wrong:
    ///
    ///   • The strip is a `.safeAreaInset(edge: .top)` applied INSIDE the
    ///     pane's own trailing inset, so it spans the feed column only — and
    ///     the pane takes up to 560pt the moment the window passes
    ///     `minWidthForPane`. The strip's room therefore SHRINKS exactly when
    ///     the window grows enough to earn a pane, which is how it came to be
    ///     cutting chips off (user report).
    ///   • Horizontal scrolling with hidden indicators is a touch idiom.
    ///     Chips past the fold are invisible to a cursor and reachable only by
    ///     shift+scroll; a rail takes a plain wheel and shows more sources at
    ///     once than the pane-narrowed strip ever did.
    ///   • The rail lives OUTSIDE the NavigationStack (see `body`), so it
    ///     survives into Apps, Settings and every bridge form — the strip
    ///     vanishes in all of them. The argument the iPad rail was built on
    ///     ("primary navigation that disappears the moment you use it is the
    ///     phone's compromise, made because a phone has no room to keep it")
    ///     is if anything stronger on a desktop window.
    ///   • Position is half the identity of an icon-only chip. A horizontal
    ///     strip's visible set changes on every window resize; a rail's
    ///     doesn't.
    ///
    /// This also settles a mismatch that shipped with the 2026-07-28 ruling:
    /// `PadShellInsets` insets the floating agent bar by `railWidth` for any
    /// REGULAR shell, and Mac reports regular — so the bar has been floating
    /// 88pt clear of a rail that wasn't rendered. The two agree again now.
    ///
    /// The detail pane (`showsPane`) is untouched — that's a width question,
    /// not an axis one.
    private var showsRail: Bool { isRegular }

    /// What sits BELOW the feed: the demo's marking, the room's own controls,
    /// then the source strip against the bottom edge (prd §591, 2026-09-03,
    /// user: *"what if the rail for source chips was at the bottom of the
    /// screen instead of the top and fab became one of them but was first and
    /// fixed on the left"* — "it would kind of be like a mac dock", "on the
    /// phone").
    ///
    /// **The argument was already written in this codebase, against the
    /// arrangement it shipped with.** `AgentBar`'s own note gives three reasons
    /// the sources tray lives on the bar rather than on the strip's catalogue
    /// door, and the first is *"this bar is in the bottom thumb zone and the
    /// strip is at the top, which is the hardest place to reach on a phone"* —
    /// said of the strip that IS this app's primary navigation. A door was
    /// moved to the bottom because the top could not be reached; the fix is to
    /// move the thing that could not be reached.
    ///
    /// **The stacking order is reading order, and it inverts with the edge.**
    /// At the top the strip led and the room's controls sat under it, nearer
    /// the room. At the bottom the same relationship puts the strip LAST —
    /// against the edge, in the shortest reach, since it is the control used
    /// most and from every room — with the room's own controls above it and
    /// the demo's marking above those. Nothing about what each row IS changed;
    /// only which edge the stack grows from.
    ///
    /// **Why the banner is HERE and not on the shell.** It was tried twice on
    /// `RootShell` — once as a top-aligned child of its ZStack, once as a
    /// `safeAreaInset` on this whole surface — and both drew it straight over
    /// the chips, clipping the avatar and the first two rooms. The cause is
    /// that this strip is itself a `.safeAreaInset` applied INSIDE the
    /// NavigationStack, whose toolbar is hidden so it owns the top of the
    /// screen outright (see `.toolbar(.hidden, for: .navigationBar)` below):
    /// an inset applied further out reserves space the strip simply ignores.
    /// So the marking joins the one inset that already owns this edge.
    ///
    /// **Why it is its own property.** Inlining these two into the modifier
    /// chain blew the type-checker's budget outright ("unable to type-check
    /// this expression in reasonable time") — the same failure `shellPhaseAware`
    /// was split out of in `RootShell`, and it only appears on a cold build,
    /// so an incremental build will happily hide it until a TestFlight archive.
    @ViewBuilder
    private var bandInset: some View {
        // **This band wears the FEED's own geometry — the rail's column reserved,
        // then the same reading cap, centred the same way (prd §361, 2026-08-11,
        // user: "the demo banner is too wide… lets make it thinner").**
        //
        // Both halves are one bug with two faces, and it is worth stating why a
        // hand-rolled inset could not have fixed either. `topInset` is a
        // `.safeAreaInset(edge: .top)` applied INSIDE the NavigationStack while
        // the rail is a `.safeAreaInset(edge: .leading)` applied OUTSIDE it, on
        // the stack — so the rail spans the window's full height from its very
        // top, and this band is laid out across the FULL width beneath it. The
        // stack's CONTENT respects the leading safe area and is then capped by
        // `dsAdaptiveContentWidth()`; a top inset view inherits neither. So the
        // band ran under the rail's doors at one end and past the feed column at
        // the other — the banner's first word sitting behind the avatar, its
        // "Exit" hanging ~100pt beyond the card below it.
        //
        // Reserving the rail with a spacer and applying the FEED'S OWN modifier
        // to what remains makes the two provably agree, rather than approximately
        // agree: same cap, same centring, same region, one modifier. A
        // `.padding(.leading, railWidth)` (the first cut) fixed only the overlap
        // and left the column mismatch, because the cap is not a padding.
        //
        // `dsAdaptiveContentWidth()` is a no-op on compact, and `showsRail` is
        // false there, so the iPhone keeps its full-width band exactly as before.
        //
        // The banner is the visible casualty but not the only one: `roomControls`
        // moved into this inset today (§357), so the venue switcher and the face
        // rail were mis-columned too — harder to notice, since a control is still
        // tappable everywhere it is not covered.
        //
        // **The rail's column is reserved with PADDING, not a spacer view, and
        // that is a measured correction rather than a style preference.** The
        // first cut put `Color.clear.frame(width: railWidth)` in an `HStack`
        // beside the band — and `Color` is a shape that fills whatever it is
        // offered, so constraining only its WIDTH left its height unbounded and
        // it grew to the full window. The top inset then owned the entire
        // surface: the feed rendered nothing at all and the banner floated in the
        // vertical middle of an empty canvas. Caught on the Mac renderer, one
        // snapshot after the change; it builds and it passes every static check.
        //
        // The padding is applied OUTSIDE the cap on purpose. It reduces the width
        // proposed to `dsAdaptiveContentWidth()`, so the 700pt column centres
        // within what remains after the rail — which is precisely the geometry
        // the feed's own content gets from the leading safe area. Inside the cap
        // it would instead eat 88pt OF the column and shift it off-centre.
        // **Capped like the feed but pinned LEADING, and that difference is
        // measured rather than chosen.** `dsAdaptiveContentWidth()` — the
        // modifier the feed itself wears — caps at `readingMaxWidth` and CENTRES;
        // applied here it produced a band of exactly the right width sitting
        // 43pt to the right of the card beneath it, because the feed's column is
        // left-biased in practice rather than centred. Pinning the band to the
        // leading edge instead lands its capsule within ~6pt of the card's edge
        // (measured off the Mac renderer: card at 112pt, banner capsule at 106pt
        // once `DemoBanner`'s own `s4` inset is counted).
        //
        // So this deliberately does NOT reuse the feed's modifier, and says why:
        // sharing a modifier is only worth it when it produces agreement, and
        // here it produced a matching WIDTH with a mismatched EDGE — which reads
        // worse than the overhang it replaced, since the eye tracks the left
        // edge of a stack of cards.
        //
        // **The `.padding(.leading, railWidth)` this used to end with is GONE
        // (2026-08-12).** It was this band paying for the rail on its own,
        // because nothing else did; the pager now reserves that column for
        // everything inside it (`dsRailColumn`), and keeping the padding here
        // as well would inset the band twice and put it 88pt right of the
        // cards it sits above. The cap and the leading pin stay exactly as
        // measured above — the band still wears the feed's own geometry, it
        // just no longer has to reach outside itself to get it.
        bandContent
            // Publishes the band's real height so `RoomGear` can float just
            // below it — see `BandHeightKey` for why this is measured rather
            // than a constant, and which two placements failed on device first.
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: BandHeightKey.self,
                                           value: proxy.size.height)
                }
            }
            // THE SCRIM (2026-08-23, inverted by §591). This band had NO
            // background of its own: each chip carries its own glass, and the
            // gaps BETWEEN the strips were fully transparent — so scrolling
            // content passed through the chrome and collided with it. Reported
            // on the Wallet room, where three strips stack (source chips,
            // venue switcher, face rail) and a card headline was legible in
            // the gaps between all three at once.
            //
            // A GRADIENT, not a plate: this band is up to three rows tall,
            // and a flat opaque block that deep reads as a second header
            // rather than as chrome the page slides under. Solid where the
            // chips sit, clearing at the edge that faces the feed, so the
            // page still visibly continues underneath — the thing that makes
            // this surface feel airy, kept, minus the collision.
            //
            // `DS.page`, never a material: design law puts Liquid Glass on
            // the FLOATING layer alone, and this is chrome that content
            // scrolls beneath, not a floating panel.
            //
            // **THE POUR IS NOT COMPOSITED HERE ANY MORE, and that is the
            // edge change rather than a reversal of the 2026-08-24 fix.** That
            // fix existed because this band sat in `crownPour`'s densest stop:
            // an opaque plate there blanked the one field §159 promises
            // "everywhere, always". At the bottom of the screen the pour has
            // already faded to nothing (150pt from the top, `crownPourRecipe`),
            // so there is nothing under this band to preserve — compositing it
            // would paint a second, upside-down pour against the bottom edge,
            // which is a wash §524 does not describe and no other surface
            // wears. The pour itself is untouched and still drawn by `body`.
            //
            // The mask runs the other way for the same reason the stack does:
            // solid against the bottom edge where the chips sit, clearing
            // upward into the feed.
            .background(alignment: .bottom) {
                DS.page
                    .mask(alignment: .bottom) {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0), location: 0),
                                .init(color: .black, location: 0.25),
                                .init(color: .black, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: showsRail ? PadLayout.readingMaxWidth : .infinity,
                   alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the top band actually stacks. Split out of `topInset` only so that
    /// view can reserve the rail's column around it — see there.
    @ViewBuilder
    private var bandContent: some View {
        VStack(spacing: 0) {
            // The demo's marking is NOT in this band any more (§591 amendment,
            // user: "i think for demo purposes the demo banner should be at the
            // top of the screen"). Its 2026-08-07 note said it had to join this
            // inset because two attempts to host it on `RootShell` drew it
            // straight over the chips — and that was a fact about the CHIPS
            // being at the top, not about the banner. With the band at the
            // bottom the top of the screen is empty, so the obstacle is gone
            // and the reason to move is plain: this is a marking about the
            // whole app state, not a control, and at the bottom it was pushing
            // the dock up by its own height while sitting in the thumb zone
            // reserved for things you press. See `demoBannerInset`.
            // The room's own two controls, ABOVE the strip and BELOW the feed
            // (prd §357, moved to this edge by §591). Both were
            // `safeAreaInset`s on `FeedScreen` until §357 — see `roomControls`
            // for why that could not work, an argument the edge does not
            // change.
            roomControls
            if !showsRail {
                sourceStrip(axis: .horizontal)
                    // **THE DOCK'S FIRST SEAT BELONGS TO THE AGENT (§591), and
                    // the strip runs UNDER it rather than beside it.** The bar
                    // is hosted on `RootShell`'s ZStack one layer above this
                    // band, so it survives into every pushed room the way this
                    // inset does not; the strip yields nothing here and instead
                    // melts its chips out as they pass beneath the bar
                    // (`SourceChips.headTrailingEdge` reads `DSDock.agentSeat`).
                    // A `.padding(.leading, agentSeat)` stood here first and
                    // drew the scroll view's clip as a flat vertical line
                    // against the bar's round glass.
                    // **The s6 of air is GONE and its reason went with it
                    // (§591).** It replaced iPhone's hidden system nav bar —
                    // a fact about the TOP of the screen and nothing else —
                    // and at the bottom there is no vacated bar to stand in
                    // for: the home indicator's own safe area is already
                    // reserved beneath this inset, so a second s6 would be
                    // ~40pt of dead chrome under the last row of chips. What
                    // survives is the 2026-07-30 half of that ruling, which
                    // was never about the nav bar: air is the first thing
                    // handed back when the strip folds.
                    .padding(.vertical, 5)
                    // **THE DOCK IS A GLASS BAR** (§591d, user: "it seems like
                    // the category chips are on a bar but you can't really see
                    // the bar. can we make it more glass like our silhouette
                    // and scope chip rail in wallet is? that way it looks more
                    // purposeful and separate").
                    //
                    // The band's own scrim is a page-coloured gradient whose
                    // job is to stop content colliding with the chips — it
                    // blocks, it does not CONTAIN, so the strip read as chips
                    // floating at the bottom of the feed rather than as one
                    // control. `DSRoomRailSlab` answered the identical question
                    // for the wallet's fused rail (§547, "what if we made the
                    // silhouette row and the scope rail seem like more of a
                    // component together") and its answer is this modifier: the
                    // same `dsGlass` at the same `DSRoomChassis.slabRadius`, so
                    // the dock and that rail are visibly the same kind of
                    // object rather than two dialects.
                    //
                    // Glass is correct here by the design law's own division —
                    // this is chrome the feed scrolls UNDER, which is the
                    // floating layer, never content.
                    //
                    // Inset by `s4` so the bar has edges to be separate FROM;
                    // full bleed is what made it invisible. The chips inside
                    // still run full width and still melt under the agent bar
                    // (`DSDock.agentSeat`), so nothing about the scroll or the
                    // seat moved — this is a background gaining a shape.
                    .background {
                        Color.clear
                            .dsGlass(cornerRadius: DSRoomChassis.slabRadius)
                            .padding(.horizontal, DS.Space.s4)
                    }
                    .padding(.bottom, chrome.minimized ? DS.Space.s1 : DS.Space.s2)
            }
        }
    }

    /// The demo's marking, on the top edge (§591 amendment).
    ///
    /// Its own `.safeAreaInset(edge: .top)`, applied beside the band's bottom
    /// one, rather than a `RootShell` overlay — the 2026-08-07 finding that an
    /// inset applied further out is drawn over by this stack's own chrome is
    /// unchanged, and this is that stack's inset. What changed is only which
    /// edge it takes, which is now free.
    ///
    /// No scrim of its own: `crownPour` already darkens this exact region, and
    /// a second wash under a capsule that carries its own fill would read as a
    /// header band the page stops at.
    @ViewBuilder
    private var demoBannerInset: some View {
        if demoActive {
            DemoBanner()
                .padding(.top, ProcessInfo.processInfo.isMacCatalystApp
                         ? DS.Space.s2 : DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
                .frame(maxWidth: showsRail ? PadLayout.readingMaxWidth : .infinity,
                       alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The folded-category switcher and the wallet face rail, mounted at the
    /// SHELL rather than inside the feed (prd §357, 2026-08-11).
    ///
    /// **They were pinned to the one thing that gets destroyed on every move
    /// they make.** Both were `.safeAreaInset(edge: .top)` on `FeedScreen`, and
    /// this surface renders exactly one `FeedScreen` carrying `.id(filter.source)`
    /// under an asymmetric move transition (see `surface`) — so picking a venue
    /// tore down the switcher that was picked, slid it off one edge, and slid an
    /// identically-configured new one in from the other. Three costs, all
    /// invisible as bugs because everything still worked:
    ///
    ///   • `CategoryVenueSwitcher`'s selection fill rides `matchedGeometryEffect`
    ///     and its `@Namespace` died with the screen. A venue pick is the ONLY
    ///     event that changes `active`, so the fill could never once travel —
    ///     the control documented "a selection fill traveling on matched
    ///     geometry" and shipped two states blinking, which is precisely what
    ///     the source chips' own 2026-07-14 ruling forbids. Same for its
    ///     `proxy.scrollTo(active)` re-centre, which was a fresh `onAppear`
    ///     every time rather than the animated move it is written as.
    ///   • The wallet rail replayed five identical faces sliding out and back
    ///     in to say nothing had changed — §356 moved the SCOPE to the shell
    ///     because it spans the category, while the control that sets it stayed
    ///     a property of one room.
    ///   • Chrome that is pinned so content can travel beneath it was itself
    ///     travelling. That is the whole argument the pinning was chosen for.
    ///
    /// Mounted here they stand still and the room moves under them, which also
    /// means the transition animates only what actually changed.
    ///
    /// **They still vanish into a pushed room, and that is not incidental.**
    /// This inset is applied INSIDE the `NavigationStack` (unlike `railInset`),
    /// so wallet history, the wallet manager and every bridge form cover it —
    /// the behaviour they had for free as feed insets, kept deliberately: a
    /// scope control above a screen it does not scope is a dead control.
    ///
    /// Gating lives with each control (`CategoryFold.switcherFloor`,
    /// `WalletScopeRail.shows`) rather than being restated here.
    /// **One rail, two rooms** (prd §362, 2026-08-11). The social faces were a
    /// head CARD inside the feed (`SocialRosterHero`) that scrolled away and
    /// navigated; they are the same pinned filtering rail the wallets wear now.
    /// They can never both draw — a source is in the Wallet category or it is a
    /// social room, never both — so the two `if`s are alternatives, not a stack.
    @ViewBuilder
    private var roomControls: some View {
        // The octopus's folder (§591 amendment). It sits in the same slot the
        // room's own row uses — one row, one folder — so the two can never
        // stack, and it reaches this band rather than a raised tray because the
        // ruling was that the bar "needs to open the same way the others do in
        // a strip", "not in a tray".
        if chrome.openFolder == .doors {
            DoorsStrip(compact: chrome.minimized && !showsRail,
                       onAgent: {
                           chrome.openFolder = nil
                           chrome.openComposer()
                       },
                       onApps: {
                           chrome.openFolder = nil
                           route.present(.apps)
                       },
                       onAddressBook: {
                           chrome.openFolder = nil
                           route.push(.addressBook)
                       },
                       onSettings: {
                           chrome.openFolder = nil
                           route.present(.settings)
                       })
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        if roomControlsShown {
            categorySwitcher
        socialScopeRail
        // **VIBENET'S FACE RAIL IS FOLDED INTO ITS CROWN (prd §482
        // amendment, 2026-08-26, user: "we cannot have four rows of chips").**
        // It and the value chips under the sparkline were both a strip of
        // this room's accounts — one above the crown, one below it — and only
        // the lower one said what each account was worth. The scoping moved
        // down into those chips, which costs a row of chrome and loses
        // nothing. Wallet's rail is untouched: its crown carries no
        // per-account strip to fold into.
        }
    }

    // `roomControlsAvailable` was DELETED in the §591 amendment. It existed to
    // decide whether a re-tap on the active chip should toggle the room's row
    // or fall back to popping the stack, back when a chip tap ALSO switched
    // rooms and the two behaviours had to share one gesture. A folder tap no
    // longer switches anything, so `CategoryFold.isCategory` answers the whole
    // question at the call site: a category chip opens, everything else moves.

    /// The category the room you are STANDING IN belongs to, if any.
    private var currentCategory: String? {
        BridgeCatalog.category(forSource: filter.source)
    }

    private var roomControlsShown: Bool {
        if case .category = chrome.openFolder { return true }
        // §357: a live scope forces its own room's rail open whatever the
        // folder says — a filter you are standing in must show you that you are
        // in it, and must show its own exit.
        return chrome.personScope != nil
    }

    @ViewBuilder
    private var categorySwitcher: some View {
        // **THE OPEN FOLDER, NOT THE CURRENT ROOM (§591 amendment).** This read
        // `BridgeCatalog.category(forSource: filter.source)` while a category
        // chip's tap switched rooms, so the two questions had one answer. A
        // folder tap no longer moves the feed, so they diverge: you can open
        // Social while standing in Kalshi, and this row must then list Social's
        // seats. `active:` stays `filter.source`, so nothing in the row is lit
        // in that case — which is the honest drawing, not a gap.
        if case .category(let category) = chrome.openFolder {
            let venues = categoryVenues[category] ?? []
            if venues.count >= CategoryFold.switcherFloor {
                CategoryVenueSwitcher(
                    venues: CategoryFold.scopes(category: category, present: Set(venues)),
                    active: filter.source,
                    // THE SAME EXPRESSION BOTH FACE RAILS TAKE, deliberately
                    // spelled rather than derived (prd §541). This control sits
                    // directly above `socialScopeRail`, whose captioned faces
                    // fold 36→26 on this signal — so a switcher that did not
                    // fold put a 36pt mark row above a 26pt face row on every
                    // scroll, which is §483's own complaint wearing the folded
                    // state. `!showsRail` carries the same axis gate for the
                    // same reason the rails give: a surface wide enough for the
                    // vertical rail is not short of vertical space, and one
                    // control resizing there reads as a twitch, not a system.
                    compact: chrome.minimized && !showsRail) { venue in
                    chrome.sourceRequest = venue
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
                // On a regular-width surface the horizontal source strip is not
                // in this inset at all (it is the leading `railInset` there), so
                // nothing above has reserved the top edge and this takes the air
                // the strip would otherwise have given it. `showsRail` is the
                // SOURCE rail, not `WalletScopeRail`.
                .padding(.top, showsRail && !demoActive ? DS.Space.s2 : 0)
            }
        }
    }

    /// The wallet face rail — see `WalletScopeRail`, which owns the whole of its
    /// construction and the one predicate saying when it draws.
    ///
    /// `compact:` is the shell's existing fold state, so the rail shrinks on the
    /// same scroll that folds the chips rather than growing an observer of its
    /// own. `minimizesChrome` already animates that flip and already ignores the
    /// inset change its own toggle causes (its settle window), which is what
    /// makes a fold-sensitive control safe to put in this inset at all.
    ///
    /// **…and `!showsRail`, which is `SourceChips.folds`' own axis gate spelled
    /// for this control** (2026-08-11). The strip already refuses to fold on a
    /// regular-width surface — `folds` is `minimized && axis == .horizontal`,
    /// and the strip is vertical exactly when `showsRail` — so on Mac and iPad
    /// the chrome above this rail holds still while you scroll. Left
    /// unqualified the rail was the ONE piece of shell chrome that resized
    /// there, which does not read as a system compressing; it reads as one
    /// control twitching. The reason the strip declines is the same reason this
    /// one should: folding buys back vertical space, and a surface wide enough
    /// to wear a rail is not short of it.
    @ViewBuilder
    private var vibenetScopeRail: some View {
        // Derived from the ROOM, never from the watch list directly — the
        // two can legitimately disagree (in the demo the card is a fixed
        // fixture while the watch list holds whatever this device really
        // watches), and a rail offering faces the card beneath it has
        // never heard of is a control that cannot scope anything. One
        // source of truth, so a pick always names a row the card has.
        let addresses = VibenetRoomSource.card()?.items.map(\.address) ?? []
        if VibenetScopeRail.shows(source: filter.source, watched: addresses.count) {
            FaceScopeRail(
                items: VibenetScopeRail.items(addresses),
                scope: chrome.vibenetScope,
                compact: chrome.minimized && !showsRail,
                // MATCHES THE WALLET RAIL (2026-08-23). These are adjacent
                // venues inside the same folded category, so switching
                // between them must not restructure the control that sits
                // above both — captioned here and captionless there meant
                // the rail changed height, slot width and fold behaviour
                // on a venue tap, which reads as the chrome jumping. The
                // room card directly below names every account, exactly as
                // the crown card does for wallets (§450), so the caption
                // is redundant here for the same reason it is there.
                namesInRoom: true,
                matches: VibenetScopeRail.matches,
                onPick: { picked in
                    withAnimation(DS.Motion.standard) { chrome.vibenetScope = picked }
                },
                onReTap: nil,
                // ONE slot, not two (prd §465, dropped 2026-08-24). Wallet's
                // rail carries a "+" AND a book door because they lead to two
                // DIFFERENT places — the roster's own field, and everyone
                // else. Vibenet has one tier: watching another account and
                // seeing the whole list are the same screen now, so a second
                // slot pointing at the identical destination is chrome, not a
                // choice. `addTitle`/`onAdd` deliberately left nil.
                addTitle: nil,
                onAdd: nil,
                bookTitle: nil)
            .padding(.top, showsRail && !demoActive ? DS.Space.s2 : 0)
        }
    }

    @ViewBuilder
    private var socialScopeRail: some View {
        let accounts = socialAccounts
        if SocialScopeRail.shows(source: filter.source, accounts: accounts.count) {
            FaceScopeRail(
                items: SocialScopeRail.items(accounts, source: filter.source,
                                             fresh: chrome.freshHandles),
                scope: chrome.personScope,
                compact: chrome.minimized && !showsRail,
                matches: SocialScopeRail.matches,
                onPick: { picked in
                    withAnimation(DS.Motion.standard) { chrome.personScope = picked }
                },
                // Re-tapping the lit face opens that person's own room — the
                // door the first tap used to be, kept one tap away now that the
                // first tap filters instead. `RootShell` presents it through the
                // same sheet `casberi://person/…` opens.
                onReTap: { item in
                    chrome.personRequest = SocialProfile(
                        source: filter.source, handle: item.id,
                        displayName: item.caption, bio: nil,
                        avatarURL: {
                            if case .avatar(let url, _) = item.face { return url }
                            return nil
                        }())
                })
            .padding(.top, showsRail && !demoActive ? DS.Space.s2 : 0)
        }
    }

    /// The watched accounts behind whichever social room is showing.
    ///
    /// Read straight off the network's store — no corpus walk, so this costs
    /// nothing on the body path, which matters because `topInset` is evaluated on
    /// every body pass and is already this surface's most expensive property
    /// (see `chipSnapshot`).
    private var socialAccounts: [SocialAccount] {
        // ONE DISPATCH, shared with the room itself (2026-08-26, prd §489).
        // This was a two-case switch that failed CLOSED — which is why Nostr's
        // rail simply never drew, silently, for as long as that seat has
        // existed, while `HandleSetupScreen` had the complete three-case
        // version all along. See `SocialRoomSource.accounts(for:)`.
        SocialRoomSource.accounts(for: filter.source)
    }

    /// One pushed room. Split out of the `navigationDestination` closure only
    /// so that closure can reserve the rail's column around it (see there) —
    /// the switch itself is unchanged, case for case.
    @ViewBuilder
    private func pushedRoom(_ node: HomeRoute.Node) -> some View {
        switch node {
        case .apps:
            AppsScreen()
                .navigationTransition(.zoom(sourceID: "appsDoor", in: doorNS))
        case .settings:
            SettingsScreen()
                .navigationTransition(.zoom(sourceID: "settingsDoor", in: doorNS))
        case .bridge(let dest):
            // Mac's connect form is PUSHED, not raised (see
            // `Destination.raisedByConnect`), so the one behaviour the sheet
            // owned — a one-shot form leaving once its key lands — rides here
            // instead. No-op on touch, where the sheet still owns it.
            BridgeDestinationView(destination: dest)
                .connectPushWatcher(dest)
        case .appDetail(let name):
            if let offer = BridgeCatalog.offers.first(where: { $0.name == name }) {
                AppDetailScreen(offer: offer)
            }
        case .project(let name):
            ProjectDetailScreen(projectName: name)
        case .walletbeatDirectory:
            WalletbeatDirectoryScreen()
        case .l2beatDirectory:
            L2beatDirectoryScreen()
        case .addressGroup(let name):
            AddressGroupScreen(group: name)
        case .addressBook:
            AddressBookScreen()
        }
    }

    /// The rail: the same source strip turned 90° down the leading edge of
    /// every regular-width surface (see `showsRail`), ridden as the stack's
    /// own `.safeAreaInset(edge: .leading)` — see `body` for why.
    ///
    /// It adds NO container material of its own. The doors and the "All" chip
    /// already wear glass inside `SourceChips`, and a slab behind them would
    /// be glass on glass; a source chip is an app icon and stays unfrosted by
    /// the same 2026-07-20 ruling the horizontal strip follows. What the move
    /// changes is not how much glass the rail wears but what is behind it.
    ///
    /// `SourceChips` pins `PadLayout.railWidth` on its vertical branch, so
    /// the width this inset reserves is the same number `PadShellInsets`
    /// holds the agent bar clear by — one constant, not two that can drift.
    @ViewBuilder
    private var railInset: some View {
        if showsRail {
            sourceStrip(axis: .vertical)
                // Clearance for the traffic lights (2026-08-17). With the
                // title bar collapsed (`RootShell.applyMacWindowChrome`) the
                // content runs to the top edge, and the window buttons float
                // over the top-LEFT — which on this layout is exactly where
                // the rail's first source chip sits. Without this the close
                // button lands on a chip: the chip is unclickable and the
                // button looks like part of the app.
                //
                // A fixed inset rather than a safe-area read, because Catalyst
                // reports no safe area for the window buttons — they are drawn
                // by the window, not the scene, so nothing publishes their
                // frame. 32pt is measured against the standard macOS button
                // row (~28pt tall from the top edge) plus a hair, and it is
                // spent only on the Mac.
                .padding(.top, ProcessInfo.processInfo.isMacCatalystApp
                         ? DS.Space.s8 : 0)
        }
    }

    /// The corpus MINUS search-only sources (Contacts) — the same rule Home and
    /// Feed already share (`Corpus.surfaced`), so the chip row lists exactly the
    /// sources the feed shows.
    /// The whole corpus, minus search-only sources — a full walk and a fresh
    /// array every call, so it is read from EVENTS (mount, foreground, an
    /// arrival) and never from a body pass. Measured 2026-07-31: it ran 74
    /// times in one cold launch, because both `chipLabels` and the arrival
    /// watcher's `onChange(of:)` value asked for it on every body evaluation.
    /// See `liveChips` and the watcher below for the two fixes.
    private var feedThings: [Thing] { perfAccum("MainSurface.feedThings") { Corpus.surfaced(things) } }

    /// What the two `onChange(of:)` watchers below key on (2026-08-11) — see
    /// `FeedScreen.corpusRevision` for the full argument; both halves of it
    /// apply here unchanged.
    ///
    /// The part that is specific to this surface: `chipCorpus` is bounded at
    /// 400, so past that `things.count` was pinned and NEITHER watcher ever
    /// fired — no arrival bob, no berry rain, no `refreshLiveChips()` on a
    /// source appearing, no `detail.pruneIfDead()`. Silent, and it reads as
    /// "delight is a bit random" rather than as a broken trigger.
    ///
    /// The watcher still reads `feedThings` INSIDE its closure, where it is
    /// paid once per arrival rather than once per body pass — the point of
    /// the split.
    private var corpusRevision: Corpus.Revision { Corpus.revision(in: modelContext) }

    /// The pane's resting companion to the day (2026-08-02): the newest thing
    /// the All feed would show, rendered as the record it IS rather than named
    /// in a row. See `paneRest`.
    ///
    /// A deliberate exception to the chip corpus's "nothing faults" invariant
    /// above — the card renders a real body, so SwiftData faults the heavy
    /// inline columns back in for exactly ONE object, once. That is precisely
    /// why this isn't a second `@Query`: a fully-hydrated fetch would
    /// materialize a window of records on every write, on every device,
    /// including the phone, where this pane is never rendered and nobody reads
    /// the result. One fault on the surface that shows it beats a standing
    /// cost on the surface that doesn't.
    ///
    /// The eligibility rule is All's own (`Corpus.showsInAll`), so the pane and
    /// the column beside it can never disagree about what just landed — plus
    /// the import receipt, which All keeps and this drops: a receipt is a fact
    /// about the pile, and §249 keeps those off the app's resting surfaces.
    ///
    /// A FUTURE `capturedAt` is skipped, which is the one place this parts from
    /// All's order on purpose. A calendar event carries the event's own time as
    /// its `capturedAt` (that is what lets the agenda lead with what's next), so
    /// the top of All is routinely something that hasn't happened — and a card
    /// captioned "Latest" over "Evening run · in 45 minutes" is a wrong word,
    /// not a debatable one. What's ahead is the DAY's job, one card up.
    ///
    /// `first` on a newest-first array short-circuits, so this walks a handful
    /// of elements, and only `source` is read for a non-bulk thing (both
    /// `Corpus` checks guard on it before reaching `sourceRef`, which is NOT in
    /// the fetch set above).
    private var latestArrival: Thing? {
        let now = Date.now
        return things.first {
            $0.isLive
                && $0.capturedAt <= now
                && !Corpus.searchOnlySources.contains($0.source)
                && Corpus.showsInAll($0)
                && !Corpus.isImportReceipt($0)
        }
    }

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

    /// The order the strip is actually WEARING — frozen at launch and at each
    /// foreground (2026-07-30). See `chipLabels`.
    @State private var frozenChips: [String] = []
    @Environment(\.scenePhase) private var scenePhase

    /// The strip's order, held still while you use it (2026-07-30).
    ///
    /// `computedChipLabels` below is derived, so it recomputed on EVERY body
    /// evaluation of this surface — and both of its inputs move on their own:
    /// recency changes whenever anything lands anywhere in the corpus, and the
    /// learned weight changes on every chip tap. A Bluesky post arriving while
    /// you were reaching for Photos could slide the chips sideways under your
    /// thumb, and the order differed between one launch and the next.
    ///
    /// That is fatal for THIS strip specifically. These are 56pt icon-only
    /// circles with no labels (ruling 2026-07-09) — an icon-only control is
    /// legible at a glance only because you know where it lives. Position is
    /// half the identity, and it was the half that wouldn't hold still.
    ///
    /// So the learning is unchanged and the freeze is on the DISPLAY: the order
    /// is computed at launch and at each foreground — moments when nobody is
    /// mid-reach — and held for the whole session in between. A tap still
    /// counts (`ChipMemory.visited`); it simply lands next time you come back.
    /// The live label set, cached (2026-07-31 perf).
    ///
    /// `computedChipLabels` walks the WHOLE corpus and sorts it, and `chipLabels`
    /// reads it to decide which frozen slots still have a source behind them —
    /// so before this cache, every body evaluation of the shell paid for a full
    /// corpus walk. Measured: 74 walks in one cold launch, which is the shell's
    /// single largest launch-window cost and one that grows with the corpus
    /// forever.
    ///
    /// `nil` means "never computed", which only happens on the very first body
    /// pass — it computes inline there rather than rendering an empty strip for
    /// a frame and writing state to fix it. After that it is refreshed from the
    /// three events that can genuinely change the SET of sources: mount,
    /// foreground, and a corpus count change (an arrival or a deletion). A chip
    /// tap changes only the ORDER, which is frozen until foreground anyway.
    @State private var liveChips: [String]?

    /// Connected live-room bridges (Kalshi, Polymarket) earn a chip with nothing
    /// landed, so connecting one changes the label set without changing the
    /// corpus count. Cheap enough to read per body pass — it walks the ~25
    /// bridges, not the corpus — and it's what lets a chip appear the moment you
    /// come back from connecting rather than waiting for the next foreground.
    private var liveRoomChipCount: Int {
        store.bridges.filter { $0.status == .connected && LiveRoomSources.has($0.name) }.count
    }

    private var chipLabels: [String] {
        foldedLabels(live: liveChips ?? computedChipLabels)
    }

    /// `chipLabels` over an ALREADY-RESOLVED live list.
    ///
    /// Split out (2026-08-11) so `chipSnapshot` can fold the strip's three
    /// answers out of ONE walk. Pure set arithmetic over two arrays — the
    /// expensive half is entirely in resolving `live`.
    private func foldedLabels(live: [String]) -> [String] {
        guard !frozenChips.isEmpty else { return live }
        // Anything the freeze knows about keeps its frozen slot; a source whose
        // last thing was deleted meanwhile drops out.
        let liveSet = Set(live)
        let held = frozenChips.filter { liveSet.contains($0) }
        let heldSet = Set(held)
        let fresh = live.filter { !heldSet.contains($0) }
        guard !fresh.isEmpty else { return held }
        // A source with no chip until now is a NEW ROOM — it goes to the head,
        // not the tail, because it arrives wearing the bloom and the catch bob
        // (see the arrival watcher below) and a celebration that happens off
        // the right edge of the strip is a celebration nobody sees. This is the
        // one thing allowed to move the strip mid-session, and it moves it for
        // an event the person can watch happen.
        return [held.first ?? "All"] + fresh + held.dropFirst()
    }

    /// Freeze the order as it stands. Called at mount and on every foreground —
    /// never mid-session, which is the whole point. One walk serves both the
    /// freeze and the live cache, since at this instant they are the same list.
    /// When the strip last froze. See `freezeChips(force:)`.
    @State private var lastFreeze: Date?
    /// Two freezes closer together than this cannot mean two different orders.
    private static let freezeCoalesce: TimeInterval = 1.0

    private func freezeChips(force: Bool = false) {
        // Coalesced (2026-08-11). A cold launch fires this TWICE within
        // milliseconds — `onAppear` and the first `.active` scenePhase — and on
        // the Mac every focus flip fires it again. That was genuinely free
        // while this was a pure local sort over an already-materialised array,
        // which is what the call site below still says; since 2026-08-06 it is
        // `newestPerSource()`, one indexed store read per candidate seat, and a
        // cold-launch profile put the pair at ~640 of 4,300 main-thread samples.
        //
        // `force` belongs to the `onAppear` call and only it: that one runs
        // AFTER `-chipStats` seeds `ChipMemory`, so letting it be the freeze
        // that gets skipped would quietly stop the probe deciding the order it
        // exists to decide.
        if !force, let lastFreeze,
           Date().timeIntervalSince(lastFreeze) < Self.freezeCoalesce { return }
        lastFreeze = Date()
        let computed = computedChips()
        liveChips = computed.labels
        frozenChips = computed.labels
        categoryVenues = computed.venues
    }

    /// Refresh the live set WITHOUT re-freezing — a source arriving or leaving
    /// mid-session must be reflected (that's what earns a new room its head
    /// slot in `chipLabels`), but re-freezing here would slide the strip under
    /// a thumb, which is the one thing the freeze exists to prevent.
    private func refreshLiveChips() {
        let computed = computedChips()
        liveChips = computed.labels
        // The venue list is NOT frozen with the order (unlike `frozenChips`):
        // it decides which scopes the switcher offers, and a seat that just
        // landed its first row must be reachable from inside the room the same
        // foreground — the fold is what took away its own chip, so if this
        // waited it would be a source with no door at all.
        categoryVenues = computed.venues
    }

    /// The seats behind every folded category chip, in LEARNED order, keyed by
    /// category, published to `ShellChrome.categoryVenues` (prd §351,
    /// 2026-08-11 — generalizes what was a single-array `marketVenues`).
    @State private var categoryVenues: [String: [String]] = [:]

    // The unfolded `sourceOrder` mirror was DELETED in §591 with the tray that
    // was its only reader — see `ShellChrome` for the whole reasoning.
    // `computedChips().sources` still exists and is still computed, because
    // `chipLabels` is derived FROM it; nothing publishes it any more.

    /// Everything the strip needs, from AT MOST ONE walk (2026-08-11).
    ///
    /// The strip's three arguments — labels, the active chip, and the folded
    /// room's venues — are all derived from the same list, and each used to
    /// resolve it independently: `chipLabels` walked, `activeChip` walked
    /// again through `chipLabels`, and `displayedMarketVenues` walked a third
    /// time (and a fourth, since its own guard read `chipLabels`). A cold
    /// launch profile on a 6,000-row corpus put that at **34% of the main
    /// thread** — `MainSurface.topInset` 1603 of 4722 samples, nearly all of it
    /// inside `newestPerSource`'s per-seat SQLite reads, and launch at 3.5–4.4s
    /// against 2.8–2.9s before the markets fold added the last two call sites.
    ///
    /// Each answer is still exactly what it was; they are simply asked once.
    /// `walk()` is lazy AND memoised, so the steady state — `liveChips` warm,
    /// `categoryVenues` mirrored — costs zero walks rather than one per reader.
    ///
    /// The venue fallback keeps its reason for existing (see below) but no
    /// longer pays for it up front: it used to test `marketVenues.isEmpty`
    /// FIRST, which is true for everyone who has not folded a Markets chip —
    /// i.e. almost everyone — and then evaluate the expensive half of the `&&`
    /// on every single body pass to prove a fold it was never going to find.
    /// (Now checked per-category, and per-category the same shortcut still
    /// applies — see the loop below.)
    private func chipSnapshot()
        -> (labels: [String], active: String, venues: [String: [String]], standing: String) {
        var walked: (labels: [String], venues: [String: [String]], sources: [String])?
        func walk() -> (labels: [String], venues: [String: [String]], sources: [String]) {
            if let walked { return walked }
            let fresh = computedChips()
            walked = fresh
            return fresh
        }
        let labels = foldedLabels(live: liveChips ?? walk().labels)
        // The mirror, but falling back to a fresh computation when it is empty
        // while the labels already carry a folded chip — which is exactly the
        // first body pass, before `onAppear` runs `freezeChips()`. Without this
        // a freshly-folded chip renders as a bare grey circle with no marks on
        // every cold launch (and, briefly, with no attention ring and no venue
        // names in its accessibility label). Checked per-category (2026-08-11,
        // generalizing what was a single `marketVenues.isEmpty` test): the
        // mirror can be warm for some categories and cold for a brand-new one
        // in the same pass.
        var venues = categoryVenues
        for label in labels where CategoryFold.isCategory(label) && venues[label] == nil {
            venues[label] = walk().venues[label] ?? []
        }
        // **THE LIT CHIP IS THE OPEN FOLDER (§591c, user: "when a user selects a
        // category chip, it should turn blue" — "right now when i click wallet
        // it stays white").**
        //
        // It was `chipLabel(for: filter.source)`, which was the whole answer
        // while a chip tap switched rooms: what you tapped and where you stood
        // were one thing. §591a made a folder tap open without moving the feed,
        // so tapping Wallet left `filter.source` alone and the chip you had
        // just pressed stayed unlit — a control that gives no sign it received
        // your tap, which is the worst thing a control can do.
        //
        // The strip's selection is what you last SELECTED, so the open folder
        // takes it. The two coincide almost always, because arriving in a room
        // opens that room's folder; they diverge only when you deliberately
        // open one folder while standing in another, and then the blue follows
        // your finger, which is what was asked for.
        //
        // Where you are standing is not lost in that case — see `standingChip`,
        // which the strip rings.
        //
        // `filter.source` is always a REAL seat, so inside a folded category
        // room it names a source with no circle of its own — and an active
        // room with no lit chip reads as no filter at all.
        let standing = CategoryFold.chipLabel(for: filter.source, folded: labels)
        let lit: String = {
            if case .category(let open) = chrome.openFolder, labels.contains(open) {
                return open
            }
            return standing
        }()
        return (labels, lit, venues, standing)
    }

    /// The chip that should read as active. See `chipSnapshot`, which is what
    /// the strip itself uses; this serves the readers that need it alone.
    private var activeChip: String {
        CategoryFold.chipLabel(for: filter.source, folded: chipLabels)
    }

    /// A cheap stand-in for `chipLabels` as an `.onChange` key.
    ///
    /// `.onChange(of:)` evaluates its key on EVERY body pass, so keying the
    /// `chrome.chipOrder` mirror off `chipLabels` put a fifth full walk on the
    /// body path. These two `@State` arrays are the only inputs `foldedLabels`
    /// has, so they change exactly when the folded order does — and the walk
    /// then happens once, inside the handler, where it is rare.
    private var chipOrderKey: [String] { (liveChips ?? []) + ["\u{0}"] + frozenChips }

    /// Every source that owns at least one row, newest first — one indexed
    /// `fetchLimit: 1` read per candidate name.
    ///
    /// CANDIDATES are the catalog's own seats plus whatever the recent window
    /// happens to name. The catalog half is what makes this exact where a
    /// bounded corpus walk was not: a seat is asked directly, so a source whose
    /// newest row is years old still answers and still earns its chip. The
    /// window half catches a source the catalog does NOT name — a retired seat,
    /// a demo seed — which can only be found by having a row, and is therefore
    /// subject to the same recency limit the old code had for everything. That
    /// is a strictly smaller blind spot than before, not a new one.
    ///
    /// `capturedAt` can sit in the FUTURE (a calendar event carries the event's
    /// own time), so ordering on it puts a source with something scheduled
    /// ahead of one that just landed. That is the order the strip has always
    /// had — `things` is sorted the same way and first-appearance drove the old
    /// list — so it is preserved deliberately rather than quietly corrected.
    private func newestPerSource() -> [(String, Date)] {
        var candidates = Set(store.bridges.map(\.name))
        for thing in things where thing.isLive { candidates.insert(thing.source) }
        var out: [(String, Date)] = []
        for name in candidates where Corpus.earnsRoom(name) {
            var d = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == name },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = 1
            // Only the column the sort and the order need. Without this the one
            // row faults its heavy inline text in — per source, per refresh.
            d.propertiesToFetch = [\.source, \.capturedAt]
            guard let newest = (try? modelContext.fetch(d))?.first, newest.isLive
            else { continue }
            out.append((name, newest.capturedAt))
        }
        return out.sorted { $0.1 > $1.1 }
    }

    /// Chip order: All, then every source — most-recent-first is still the
    /// baseline (`things` is newest-first, so first appearance IS the newest
    /// thing per source), but a source you actually VISIT often (`ChipMemory`,
    /// amends §131, 2026-07-21) sorts ahead of it. `sorted` is stable, so a
    /// zero-weight tie keeps the recency order untouched — this only ever
    /// promotes a chip you use, never reorders the rest.
    private var computedChipLabels: [String] { computedChips().labels }

    /// The strip's labels AND the market seats behind its folded chip, from ONE
    /// walk (2026-08-10).
    ///
    /// All three answers come out of the same pass because the expensive half
    /// is `newestPerSource()` — one indexed fetch per candidate seat — and
    /// asking it three times to learn three things about the same list would
    /// triple the strip's whole cost.
    ///
    /// They are derived from the same instant, so the tuple is internally
    /// consistent. That is NOT the same as the VIEW seeing them consistently:
    /// `chipLabels` can compute inline on the first body pass while the `@State`
    /// mirrors are still empty, which is why `sourceStrip` hands the strip a
    /// venue list with its own fallback rather than reading the mirror (see
    /// `chipSnapshot`).
    private func computedChips() -> (labels: [String], venues: [String: [String]], sources: [String]) {
        // Asked SOURCE BY SOURCE since 2026-08-06, not by walking the corpus.
        //
        // This used to read `feedThings`, i.e. the whole corpus materialised as
        // model objects, to learn two things: which sources exist, and how
        // recent each one's newest row is. `scripts/main-thread-profile.sh` put
        // `MainSurface.things.getter` at 25.0% of the main thread on a
        // 6,000-row corpus — a quarter of the thread spent instantiating every
        // row the person owns to answer a question about a few dozen names.
        //
        // The feed's bound (`FeedScreen.allRoomFetchLimit`) cannot be copied
        // here, and that is the whole reason this is shaped differently: a
        // newest-N limit answers "which sources exist" WRONGLY, by dropping any
        // source whose newest row is older than the Nth newest row overall.
        // That is a room vanishing from the strip — a correctness bug, not the
        // recency trade the feed accepted.
        //
        // So each candidate is asked for its newest row alone: one indexed
        // fetch, one object, per name. Dozens of tiny reads instead of
        // thousands of materialisations, and the answer is exact at any corpus
        // size. It stays off the body path for the reason it always did — the
        // callers are `freezeChips`/`refreshLiveChips`, driven by mount,
        // foreground and arrival.
        var ordered: [String] = []
        for (name, _) in newestPerSource() { ordered.append(name) }
        var seen = Set(ordered)
        // A LIVE-room source earns its chip by being CONNECTED, not by having
        // landed anything (prd §234, `LiveRoomSources`): Kalshi and Polymarket
        // have no sync, so a corpus-only rule left a connected exchange with
        // no chip — and therefore no room to browse the book from, which is
        // the entire point of connecting one. Appended after the corpus
        // sources so the learned sort below still decides real order.
        for bridge in store.bridges where bridge.status == .connected
            && LiveRoomSources.has(bridge.name) && seen.insert(bridge.name).inserted {
            ordered.append(bridge.name)
        }
        let (counts, lastVisit) = ChipMemory.snapshot()
        let learned = ordered.sorted {
            ChipMemory.weight(for: $0, counts: counts, lastVisit: lastVisit)
                > ChipMemory.weight(for: $1, counts: counts, lastVisit: lastVisit)
        }
        // Pinned sits second, right after All, and does NOT enter the learned
        // sort above (2026-08-10). Two reasons it is placed rather than ranked:
        // it is not a source, so `ChipMemory`'s recency-and-visits weighting has
        // nothing meaningful to say about it; and its position is the one thing
        // about it that should never move, because a list you built by hand is
        // useless if you have to hunt for the door to it.
        //
        // Gated on something actually being pinned — an empty Pinned room would
        // be a chip that opens nothing, which is the dead control §83 forbids.
        // It disappears again when you unpin the last thing, and that is
        // correct: the room's whole content is your own list, so an empty one
        // has nothing to explain.
        let pinned = Pinboard.hasAny(in: modelContext) ? [Pinboard.room] : []
        // EVERY catalog category folds into its own chip, ALWAYS (prd §351,
        // 2026-08-11 — generalizes what was one Markets-specific fold applied
        // above a floor of 2). Applied LAST, over the finished list, so the
        // fold is a presentation of the learned order rather than a competitor
        // to it: each folded chip inherits the position of the best-ranked
        // seat it replaces, and every member's weight is still recorded.
        // Composable across categories because membership is disjoint — see
        // `CategoryFold.foldAll`. Nothing above this line knows any fold
        // exists.
        let unfolded = ["All"] + pinned + learned
        let folded = CategoryFold.foldAll(unfolded)
        // The category chips sit in a FIXED order (user ruling 2026-08-11:
        // "wallet, markets, work, agents, life, social, media, reading, notes,
        // voice, shopping" — Wallet first because it's "more important to
        // users", Social placed "after life and before media" on request) —
        // not the learned order every other kind of chip still earns. That
        // ruling is now the DEFAULT rather than the only answer: it is
        // `CategoryOrder.defaultOrder`, and Settings lets the person rearrange
        // it (prd §533). Everything else about this line is unchanged — "All"
        // and Pinned are untouched (never part of this ordering) and split off
        // first so the sort below only ever touches what comes after them; a
        // stable sort keeps their relative position exact, and a label the
        // order has never heard of still keeps its learned-order slot at the
        // tail (`rank`'s `Int.max`).
        //
        // Read ONCE per walk, not once per comparison: `current` deserializes
        // a UserDefaults array, and an O(n log n) comparator asking for it per
        // compare is exactly the mistake `ChipMemory.snapshot()` exists to
        // stop (2026-07-21 audit).
        let order = CategoryOrder.current
        let head = Array(folded.prefix(1 + pinned.count))
        let rest = Array(folded.dropFirst(1 + pinned.count))
            .sorted { CategoryOrder.rank(of: $0, in: order)
                    < CategoryOrder.rank(of: $1, in: order) }
        let labels = head + rest
        // The tray gets the SOURCES, so Pinned is dropped from its list for the
        // same reason a folded category label is: it is a room, not a source.
        // The tray groups by catalog category itself and the catalog has never
        // heard of Pinned, so it landed in the trailing "Other" block wearing
        // the generic placeholder mark — a cell that looks like a connection
        // nobody can name, on the one screen whose job is to name every source.
        let sources = ["All"] + learned
        // Venues for every category that actually folded, keyed by category
        // name. Unconditional now — there is no floor below which a category
        // keeps its members' own chips (that floor lived on the OLD Markets-
        // only fold; see `MarketsRoom.switcherFloor` for the different
        // question of when a SWITCHER control is worth drawing).
        //
        // LEARNED order, not catalog order, and the distinction is
        // load-bearing in one place: `CategoryFold.landing` takes the first
        // entry as its fallback, so catalog order would open a folded chip on
        // the catalog's first member for somebody who lives in a different
        // one — "the fold does not cost a tap" failing on the very first tap.
        // Markets' own switcher re-sorts its scope into catalog order for
        // DISPLAY (`FeedScreen.marketsSwitcher`), because a four-word capsule
        // has not earned learned order and one that reshuffles between opens
        // reads as broken. Two orders, each where it belongs.
        var venues: [String: [String]] = [:]
        for category in BridgeCatalog.categories where labels.contains(category.name) {
            venues[category.name] = learned.filter { CategoryFold.isMember($0, of: category.name) }
        }
        return (labels, venues, sources)
    }

    // `feedLabels` retired here (2026-08-10). It existed to guarantee the
    // selected source always had a PAGE — `filter.source` is written
    // unvalidated (a deep link, a bridge connected but not yet synced, the last
    // thing in the room you're standing in being deleted), and a
    // `TabView(.page)` with an unmatched selection quietly renders a DIFFERENT
    // page: the Gmail wash over the All feed, no chip lit, and the honest
    // "Nothing from Gmail yet" empty state unreachable (measured 2026-07-16).
    //
    // §265 replaced the pager with ONE `FeedScreen(source: filter.source)`
    // carrying `.id(filter.source)`, which renders whatever the filter names
    // whether or not a chip exists for it — so the guarantee became structural
    // and this became a list nothing read. Its last two callers (`go(to:)` and
    // `step(_:)`) moved to `chipLabels`, which is the right domain for both:
    // one asks where a chip sits, the other walks chips.

    // The per-source brand-hue wash that once flooded this surface is gone
    // (user ruling 2026-07-18: full ink). A feed's identity lives in its chip
    // and icon, not a borrowed brand-color field — the wash read as decoration
    // over the content, and hues like Calendar's red collided with the
    // alert/loss meaning red carries elsewhere. (`DS.washHue` stays for the
    // sheet/detail/setup surfaces, which still wear a source's identity.)
    //
    // What replaced it (prd §159, 2026-07-21, user: "the app could permanently
    // have that blue pour up there instead of black"): a PERMANENT crown pour
    // — one owned field, everywhere, always, which is the boldness §129
    // itself endorsed ("Cash App is bold in ONE color that's *theirs*") and
    // none of what it retired (nothing borrowed, nothing per-source, nothing
    // deciding per screen). Scoped to a wallet, the Wallet feed re-tints it to
    // that wallet's face color through `chrome.pourHue` — identity as
    // information, the switcher capsule's own grammar at room scale.
    //
    // AMENDED prd §204 (2026-07-24, user: "let user choose their tint bleed
    // color"): the fallback is the PERSON's color now, not just ours —
    // `DS.bleed`, one of six curated options. The trade is stated on purpose in
    // §204: the pour stops being only Casberi's and becomes theirs. The
    // wallet-face carve-out (`pourHue`) is unchanged and still wins first;
    // `DS.tint`, the pressable signal at 157 other sites, does not move.
    //
    // It lives HERE, not on the feed pages, because the first cut lived on the
    // page and taught why that can't work (user screenshot, 2026-07-21): the
    // chip strip floats over the pager on a `safeAreaInset`, so a page-level
    // field stops at the page's edge and the strip zone stays flat black — a
    // hard seam exactly on the no-hairlines law. The shell owns the crown; the
    // field must too.
    //
    // AMENDED AGAIN (2026-08-04, user: "one as black / ink, so in case a user
    // doesn't want to see crown pours they don't have to", then "lets make the
    // default dark mode be black / ink theme not blue"): Ink is a sixth option
    // that does not pour, and it is now the DEFAULT — so out of the box this
    // field is off and the crown is the page. It takes the dose to zero rather
    // than painting black, because black at the light theme's own 0.16 is a
    // grey stain across the top of every screen; an absence has to be absent,
    // not dark. A SCOPED wallet still tints: that pour says which room you're
    // standing in, which is the same reason §297 drains the dose on a source
    // room without dropping the hue. So the pour survives exactly where it
    // carries information and is silent everywhere it was decoration —
    // which is §159's own argument, arriving at the opposite default.
    // AMENDED A THIRD TIME (2026-08-15, user: "on the wallet screen, i don't
    // want a crown pour to change color when you select different wallets b/c
    // it doesn't match the blue card"). THIS REVERSES the wallet-face
    // carve-out described at length above, and the reversal is recorded rather
    // than quietly deleted because that carve-out was a real ruling twice
    // over: §159 introduced it and the §204 amendment deliberately preserved
    // it as "identity as information".
    //
    // What changed underneath it is that the information MOVED. The wallet
    // room's balance card became a bright `DS.tint` hero the same day, so the
    // room now states its own identity in the loudest element on the screen —
    // and a per-wallet hue pouring down the crown above a fixed blue card is
    // two identity colours on one screen disagreeing, which is worse than
    // either alone. §297's test still decides it: a pour survives where it
    // carries information and is silent where it is decoration. It is
    // decoration now, because the card got there first.
    //
    // Scoped to the CROWN on purpose. `chrome.pourHue` still publishes the
    // scoped wallet's hue, so `AgentBar.roomTint` — which reads the same field
    // — is untouched: the bottom chrome keeps saying which wallet you are in,
    // where there is no card beside it to argue with. Killing the field at its
    // source would have silently un-tinted that bar too.
    /// The pour's stops and dose, shared by the full-page field below and the
    /// chip band's own scrim (`topInset`) — so the two can never paint two
    /// different answers for the same room. Split out 2026-08-24 auditing the
    /// pour rules: the band's scrim used to reset to a flat `DS.page` for its
    /// own height, which quietly painted over this field's densest stop for
    /// the whole time the chips are on screen — the crown was only ever
    /// visible in the gaps BETWEEN rows, never behind the chrome itself.
    private var crownPourRecipe: (stops: [Gradient.Stop], dose: Double) {
        let hue = DS.bleed
        // Photo themes force the dark treatment (DS.themedPage's own rule);
        // only a true light page halves the dose — the same field that reads
        // as atmosphere on ink reads as a stain on white.
        let light = ThemeStore.shared.isLight && ThemeStore.shared.backgroundPhoto == nil
        // The scoped-wallet exemption goes with the carve-out above: a wallet
        // room no longer forces a pour through an Ink theme, so "Ink does not
        // pour" is now true everywhere without exception.
        let dose = ThemeStore.shared.bleed.pours ? chrome.pourDose : 0
        return ([
            .init(color: hue.opacity(light ? 0.16 : 0.30), location: 0),
            .init(color: hue.opacity(light ? 0.05 : 0.10), location: 0.5),
            .init(color: hue.opacity(0), location: 1),
        ], dose)
    }

    private var crownPour: some View {
        let recipe = crownPourRecipe
        // Folded into the dose rather than gating the view, so picking Ink
        // fades the field out on the same beat a colour swap re-tints it —
        // and so `crownPour` keeps ONE view identity through the pager's own
        // `.transition(.opacity)`.
        return LinearGradient(stops: recipe.stops, startPoint: .top, endPoint: .bottom)
            .frame(height: 500)
            .frame(maxHeight: .infinity, alignment: .top)
            // How much of it this room gets (§297) — full on All and inside a
            // wallet, drained on a source room, which owns its own identity.
            //
            // As a view opacity, NOT baked into the stops. Scaling all three
            // stop alphas by the dose is arithmetically identical (the third is
            // already zero, and gradient interpolation is linear in alpha), but
            // animating it that way makes SwiftUI re-resolve and re-rasterize a
            // full-width 500pt gradient every frame on the main thread — during
            // a page transition that is already remounting a room. A layer
            // opacity is one property the render server drives out of process.
            .opacity(recipe.dose)
            // A room switch drains or refills the dose as one move with the
            // switcher capsule's slide — not a hard cut. The COLOUR itself no
            // longer moves (the wallet-face carve-out this once described was
            // reversed 2026-08-15 — `chrome.pourHue` is read by `AgentBar`'s
            // bottom chrome now, not by this field), so only `dose` needs a
            // tracked animation here.
            .animation(DS.Motion.standard, value: recipe.dose)
    }

    /// The chip strip in whichever orientation this device wears it. One
    /// call site for the taps so the strip and the rail can never drift on
    /// what a chip actually DOES.
    private func sourceStrip(axis: Axis) -> some View {
        // One walk for all three, not three (2026-08-11) — see `chipSnapshot`.
        let chips = chipSnapshot()
        #if DEBUG
        SwipeClock.mark("chips")
        #endif
        return SourceChips(labels: chips.labels, active: chips.active,
                    standing: chips.standing,
                    axis: axis,
                    categoryVenues: chips.venues,
                    minimized: chrome.minimized,
                    onApps: { route.present(.apps) },
                    onSettings: { route.present(.settings) },
                    refreshSpin: chrome.refreshPulse,
                    zoomNS: doorNS) { label in
            // Compared against the CHIP, not the source: re-tapping the folded
            // Markets chip while standing in Kalshi is a re-tap of the chip
            // you're on, and comparing raw sources would read it as a switch
            // and silently do nothing (the guard in `go(to:)` catches it).
            // **A FOLDER OPENS; IT DOES NOT MOVE THE FEED (§591 amendment,
            // user: "if you tap a folder on mac dock for example it doesn't
            // switch what is on your screen").** Every source-bearing chip is a
            // category chip with no floor (§351), so this is nearly every tap:
            // it toggles that category's sources above the strip and leaves the
            // room alone. Picking one of those sources is what moves you, via
            // `chrome.sourceRequest`.
            //
            // Compared against the LABEL, so re-tapping an open folder shuts
            // it — including the folder of the room you are standing in, which
            // is the "make the second row go away" the amendment started from.
            if CategoryFold.isCategory(label) {
                withAnimation(DS.Motion.standard) {
                    chrome.openFolder =
                        chrome.openFolder == .category(label) ? nil : .category(label)
                }
                return
            }
            // "All" and any bare source are not folders — there is nothing
            // inside them to open, so their tap is the switch it always was,
            // and it shuts whatever folder was showing.
            if label == chips.active {
                // Re-tapping the room you are already in pops back to root, the
                // old per-tab habit, as it did before folders existed.
                chrome.popHome += 1
                return
            }
            let before = filter.source
            withAnimation(DS.Motion.standard) { chrome.openFolder = nil }
            go(to: label)
                        if filter.source != before { ChipMemory.visited(filter.source) }
        }
    }

    /// The detail pane. Always present once the shell is wide enough — the
    /// two-pane shape is the layout, not a state the layout enters, so the
    /// canvas never collapses back to one column and half a screen of black
    /// under a tap.
    ///
    /// `isLive` guards the held model (the 2026-07-24 crash class): a
    /// foreground bridge heal can delete the open thing under the pane, and
    /// reading any stored property on it then traps inside SwiftData. Unlike
    /// a sheet there is nothing to dismiss here — it simply falls back to the
    /// resting state, which sidesteps the presentation-transition corollary
    /// (build 142) entirely.
    @ViewBuilder private var detailPane: some View {
        Group {
            if let thing = detail.thing, thing.isLive {
                // Ink, exactly as this view is everywhere else it appears
                // (`dsInk` — a detail surface is black in both themes). The
                // ink starts only when there IS a detail: painting it at rest
                // put a hard black column beside the poured feed, which is
                // the no-hairlines law broken with a background instead of a
                // stroke.
                ThingSheetView(thing: thing, onBack: { detail.clear() })
                    .id(thing.id)
                    // Fill the column BEFORE the ink goes on: `dsInk`'s black
                    // is a `.background`, which sizes to its content — without
                    // this the ink stopped at the bottom of a short record and
                    // left the rest of the pane showing the feed's own field
                    // through a hard horizontal edge.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .dsInk()
                    .transition(.opacity)
            } else {
                // At rest the pane is a WINDOW, not a surface: the shell's own
                // themed page and crown pour run straight through it, so the
                // two columns read as one canvas until something is opened in
                // this one.
                paneRest
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: corpusRevision) { _, _ in detail.pruneIfDead() }
    }

    /// The pane at rest — the largest single area the app shows when nothing is
    /// selected: up to 560pt of the widest column, for the whole session.
    ///
    /// It held a mark and "Pick something to open it here" until §248 (a
    /// sentence describing the layout is not content), then the DAY as a card
    /// (2026-07-31), and now the newest record itself.
    ///
    /// The day line reads `chrome.paneBrief` — composed by the same `DayBrief`
    /// pass the whisper capsule uses, published ungated (see
    /// `ShellChrome.paneBrief`), so the pane and the capsule can never state
    /// different days. On a day with nothing to say it composes nil and the
    /// line simply doesn't draw: the honesty law forbids manufacturing a
    /// headline to fill a column.
    ///
    /// No berry anywhere in here — §249's ruling ("i like our logo in the
    /// search / whisper bar, but not inside the daily brief itself"). The mark
    /// survives only in the nothing-landed branch, which has no brief and no
    /// record for it to be inside of.
    ///
    /// **The pane at rest holds the newest RECORD, open (2026-08-02).** A brief
    /// is three or four lines and the pane is a full-height column, so leading
    /// with the day still left most of it empty — the same complaint §248 was
    /// answering, one size down. What fills a reading column is something to
    /// read, so the pane opens the newest thing exactly as a selection would:
    /// the real `ThingSheetView`, real body, real verbs. This is the shape Mail
    /// and Notes keep, and the reason it isn't duplication of the column beside
    /// it is that the column lists ENTRIES and this shows a BODY.
    ///
    /// The day keeps its lead (§248) as one line above it — the capsule's own
    /// sentence (§165) rather than a card, opening the same Today brief through
    /// the same door (§132). Nothing about what the day says changes; only how
    /// much of the column it occupies.
    ///
    /// **`detail.thing` stays nil.** This is deliberately NOT a selection made
    /// on your behalf: `pruneIfDead`, `clear()` and above all the Mac's
    /// `displaced` hand-off (narrowing the window re-opens the pane's thing as
    /// a sheet) all describe something the person chose, and firing them for a
    /// record nobody picked would open sheets out of nowhere. So the rest
    /// branch RENDERS the record without selecting it, and the "Latest" marker
    /// says which of the two states you're looking at — the honesty law applied
    /// to a state rather than to a control.
    ///
    /// The ink comes with the record, and the §248 objection it was avoiding
    /// ("painting it at rest put a hard black column beside the poured feed")
    /// no longer applies: that was ink under a PLACEHOLDER. With a record here
    /// the pane wears exactly the background it wears the moment you click
    /// anything, so there is no state where the seam is new information.
    ///
    /// The nothing-landed branch (a fresh install) is UNCHANGED — no ink, no
    /// strip, the centered mark on the shell's own poured page.
    @ViewBuilder private var paneRest: some View {
        if let latest = latestArrival {
            VStack(alignment: .leading, spacing: 0) {
                if let brief = chrome.paneBrief {
                    paneDayStrip(brief)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                }
                Text("Latest")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, chrome.paneBrief == nil ? DS.Space.s4 : DS.Space.s6)
                // `.id` so switching to a newer arrival rebuilds the record
                // rather than re-theming the old one in place — the same
                // reason the selection branch above carries one.
                ThingSheetView(thing: latest, inlineRest: true)
                    .id(latest.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .dsInk()
        } else {
            VStack(spacing: DS.Space.s3) {
                CasberiMark(size: 44)
                    .opacity(0.32)
                Text("Pick something to open.")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(DS.Space.s6)
        }
    }

    /// The day as one line above the record. Tapping opens the real Today
    /// brief, routed through `chrome.askRequest` — the same door the whisper
    /// capsule, the bar's own tap and a typed "how's my day" all use (§132),
    /// so a fourth entry point can't drift into a fourth presentation of one
    /// screen.
    ///
    /// The accent is read against DARK explicitly, not off the environment:
    /// this line renders inside `dsInk`, which forces `.colorScheme(.dark)`,
    /// while `@Environment(\.colorScheme)` on this surface is measured OUTSIDE
    /// that background — in light mode the two disagree, and the one that
    /// decides whether a gain reads green is this one.
    private func paneDayStrip(_ brief: DayBrief.Whisper) -> some View {
        Button {
            DSHaptic.tap()
            chrome.ask(TodayBrief.title)
            chrome.openComposer()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text(brief.title)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textPrimary)
                brief.detailText(scheme: .dark)
                    .dsText(.subhead13)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .dsGlyph(11)
                    .foregroundStyle(DS.textTertiary)
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(brief.title). \(brief.detail)")
        .accessibilityHint("Opens your day")
    }

    var body: some View {
        // The rail rides the NavigationStack's own LEADING safe-area inset
        // (2026-08-10) rather than sitting beside it in an HStack — the same
        // mechanism the phone's strip has used on `.top` since 2026-07-20,
        // one axis apart. It is still applied to the STACK and not inside its
        // content closure, so it survives into every pushed room, which is
        // the property the whole rail was built on (see `showsRail`).
        //
        // Why it moved. As an HStack sibling the rail was a column the feed
        // started BESIDE, so nothing ever passed behind it — and the glass
        // its doors and "All" chip wear was blurring a flat themed fill,
        // paying a backdrop blur for nothing. That is the 2026-07-20 lesson
        // verbatim ("it was a VStack sibling, which meant nothing ever passed
        // behind the chips, so the glass they wear blurred a flat color and
        // rendered indistinguishable from a solid fill"), which the rail was
        // built without a year later. As an inset the stack spans the full
        // width, rows travel UNDER the rail, and the material finally has
        // something to blur — paired with `dsSoftScrollEdges()`, which gained
        // a `.leading` edge on regular width in the same change so rows melt
        // under the rail instead of meeting it with a hard edge.
        //
        // Two things this DELETES rather than fixes. The rail no longer
        // carries the shell's field itself: outside the stack's opaque UIKit
        // backing (the standing gotcha) it had to paint its own copy of
        // `DS.themedPage` plus the pour, and that copy then had to be gated
        // on `route.path.isEmpty` — because a pushed room paints an opaque
        // page with no pour, so a rail that kept pouring met it as a hard
        // vertical edge, the no-hairlines law broken with a background. Glass
        // over the stack has no seam to manage and nothing to gate: it
        // samples whatever the room behind it painted, feed or Apps or a
        // bridge form, and the pour reaches under it because the stack is now
        // full-width.
        surface
        // Measured on the WHOLE surface — the stack now spans it, but this
        // stays true of the pane too:
        // `minWidthForPane` and `paneWidth(for:)` are both stated against the
        // device's total width (and `RootShell` reads the same number for the
        // agent bar), so measuring the post-rail remainder here would put the
        // two out of step by exactly `railWidth` — enough to drop the pane in
        // portrait on the one iPad that most wants it.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            surfaceWidth = width
            detail.layoutSettled = true
            #if DEBUG
            // The iPad shape, stated. Every branch here is invisible on the
            // device that DOESN'T take it — a mini falling back to the sheet
            // and a 13" opening the pane look identical in a screenshot of
            // the feed alone — so the shell says which one it computed. Logs
            // on every rotation, which is exactly when it changes.
            NSLog("[Casberi] padLayout: width=%.0f regular=%@ rail=%.0f pane=%@",
                  width, showsRail ? "YES" : "NO",
                  showsRail ? PadLayout.railWidth : 0,
                  showsPane ? String(format: "%.0f", PadLayout.paneWidth(for: width))
                            : "none (sheet)")
            #endif
        }
        // Told once, read everywhere: a row-tap site asks the selection
        // whether a pane exists rather than re-deriving the breakpoint.
        .onChange(of: showsPane, initial: true) { _, now in
            detail.paneActive = now
            // Rotating a mini into a shape that can't hold a pane must
            // not strand a selection nothing renders. On Mac this same
            // transition fires on an ordinary window drag rather than a
            // deliberate rotation, so hand the open thing to RootShell's
            // sheet fallback instead of silently discarding it (see
            // `PadDetailSelection.displaced`).
            if !now {
                if ProcessInfo.processInfo.isMacCatalystApp,
                   let thing = detail.thing, thing.isLive {
                    detail.displaced = thing
                }
                detail.thing = nil
            }
        }
        // Mac's ⌘1–⌘9 (2026-07-28) reads this mirror — see `ShellChrome.chipOrder`.
        .onChange(of: chipOrderKey, initial: true) { _, _ in
            // Nothing to publish until the strip has resolved its own order.
            // The initial fire lands BEFORE `onAppear`, so without this guard
            // `chipLabels` walks the store here for an answer `freezeChips` is
            // about to compute a few milliseconds later — measured at 634 of
            // 4376 main-thread samples on a cold launch, a second full walk for
            // nothing. Setting `liveChips` moves this key, so the handler runs
            // again the moment there is something true to publish.
            guard liveChips != nil else { return }
            chrome.chipOrder = chipLabels
        }
        // A rearrangement in Settings (prd §533) — see
        // `ShellChrome.chipOrderPulse` for why the strip is re-frozen rather
        // than reading the order live. `force`d past the coalescing window:
        // this is a deliberate act, not a lifecycle event, and coalescing it
        // against a foreground that happened a moment earlier would drop the
        // one refresh somebody is waiting for.
        .onChange(of: chrome.chipOrderPulse) { _, _ in
            withAnimation(DS.Motion.standard) { freezeChips(force: true) }
        }
        // Every folded room's scopes — see `ShellChrome.categoryVenues`.
        .onChange(of: categoryVenues, initial: true) { _, venues in
            chrome.categoryVenues = venues
        }
        // The folder opens on arrival (§591 amendment) — see
        // `ShellChrome.openFolder`. Keyed off `filter.source` itself so
        // EVERY way into a room opens its row: a chip tap, a swipe, a deep
        // link, the panel's All capsule. Only a re-tap of the chip you are
        // standing on closes it, and only until you leave.
        // Arriving in a room opens ITS folder (§591 amendment) — every route
        // counts: a venue pick, a swipe, a deep link, the composer. Only a
        // re-tap on an open folder closes it, and only until you leave.
        .onChange(of: filter.source, initial: true) { _, source in
            chrome.openFolder = BridgeCatalog.category(forSource: source)
                .map { ShellChrome.OpenFolder.category($0) }
        }
        // A scope taken while its own folder is shut re-opens it, or §357's
        // exit is behind a tap nobody knows to make.
        .onChange(of: chrome.personScope) { _, scope in
            guard scope != nil, let category = currentCategory else { return }
            chrome.openFolder = .category(category)
        }
        // Where each folded chip reopens (prd §351, generalizing 2026-08-10).
        // Keyed off `filter.source` itself rather than written inside
        // `go(to:)`, so EVERY route into a category room counts: a chip tap, a
        // swipe, a room's own switcher, and a deep link
        // (casberi://feed/source/Kalshi), which writes the filter directly and
        // never passes through `go`. `CategoryFold.remember` is a no-op for a
        // source that belongs to no catalog category, so this costs a
        // dictionary lookup on every source switch and nothing else.
        .onChange(of: filter.source, initial: true) { _, source in
            CategoryFold.remember(source)
            // A person scope belongs to ONE network, so it dies with the room
            // (prd §362) — unlike the wallet scope, which spans its category on
            // purpose. Carried into the next room it would match no row there and
            // paint an empty feed with nothing able to explain why. Here rather
            // than in `go(to:)` because a swipe and a deep link move the source
            // too, and a scope that survives one of the three doors is worse than
            // one that survives none.
            chrome.personScope = nil
            // Dies with the room like the person scope above, NOT spanning
            // its category the way the wallet scope deliberately does: a
            // vibenet devnet address matches no row in Peer, Safe or any
            // other Wallet-category venue, so carried across it would paint
            // an empty room with nothing able to explain why.
            chrome.vibenetScope = nil
            chrome.freshHandles = []
        }
        // A room asking to move to another room — the Markets switcher. See
        // `ShellChrome.sourceRequest` for why it takes this hop instead of
        // writing the filter itself.
        .onChange(of: chrome.sourceRequest) { _, request in
            guard let request else { return }
            chrome.sourceRequest = nil
            go(to: request)
            ChipMemory.visited(request)
        }
        // The keyboard walk stands down inside a pushed room (2026-07-31):
        // Settings and every bridge setup form are full of text fields, and a
        // menu item holding a bare Return or ↓ would take those keys from
        // them. This surface owns the stack, so it is the one honest reporter
        // of how deep it is. See `ShellChrome.canWalk`.
        .onChange(of: route.path.isEmpty, initial: true) { _, atRoot in
            chrome.walkInPushedRoom = !atRoot
        }
        // Re-sort the strip on the way back IN, never while you're in it
        // (2026-07-30, see `chipLabels`). A foreground is the one moment the
        // order can change without moving under a finger — and it's also when
        // a batch that landed while backgrounded should be reflected.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { freezeChips() }
        }
        // The Mac's foreground (2026-08-01): Catalyst never delivers the
        // scenePhase transition above (the scene is .active before the
        // observer attaches — see RootShell.handleActivation), so the strip
        // re-sorts on the AppKit focus-in instead. The extra fires a Mac's
        // focus flips produce are absorbed by `freezeChips(force:)`'s
        // coalescing window — they were free when this was a local sort, and
        // stopped being free when it became one store read per seat.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            if ProcessInfo.processInfo.isMacCatalystApp { freezeChips() }
        }
        // Connecting a live-room bridge (Kalshi, Polymarket) earns a chip with
        // nothing landed, so it changes the label set without changing the
        // corpus count the watcher above keys on. Without this the new chip
        // would wait for the next arrival or foreground — i.e. you'd come back
        // from connecting an exchange and find no room to browse its book from,
        // which is the whole point of connecting one (prd §234).
        .onChange(of: liveRoomChipCount) { _, _ in refreshLiveChips() }
        // A pin changes no corpus count, so it needs its own signal (see
        // `ShellChrome.pinPulse`). `refreshLiveChips`, never `freezeChips`:
        // the strip must not re-sort under the thumb that just pinned.
        .onChange(of: chrome.pinPulse) { _, _ in refreshLiveChips() }
    }

    /// Which edge the incoming room slides from — set by `go(to:)` BEFORE the
    /// source changes, so both halves of the transition read the same answer.
    @State private var slideEdge: Edge = .trailing
    /// The top band's measured height, so `RoomGear` floats just below it
    /// rather than on top of it. See `BandHeightKey`.
    @State private var bandHeight: CGFloat = 0

    /// The one door every source switch walks through (prd §265): chip taps and
    /// swipes both come here, so direction, the tag reset, and tap-learning
    /// cannot drift between them.
    private func go(to label: String) {
        // Picking a source means the WHOLE of that source — a kind filter never
        // survives the tap. Two changes from the old rule (2026-08-01), both
        // forced by the "× Links" chip's removal, which was the only way out:
        // it clears for EVERY label (a specific source used to "keep its own
        // tag", which silently emptied the room you swiped into), and it clears
        // BEFORE the same-source guard, so re-tapping the source already showing
        // is the one gesture that drops the filter — the chip's job, minus the
        // chip. The old rule pre-dates the tag being agent-set only.
        if filter.tag != "All" {
            withAnimation(DS.Motion.standard) { filter.tag = "All" }
        }
        // Resolve a folded chip label to the seat it opens (prd §351,
        // generalizing 2026-08-10). This is the ONE place a fold becomes a
        // real source, which is what keeps a category name out of
        // `filter.source` and therefore out of every query, shape, empty
        // state and deep link downstream. A chip that resolves to nothing
        // does nothing, rather than routing to a room that isn't there.
        let target: String
        if CategoryFold.isCategory(label) {
            guard let landing = CategoryFold.landing(category: label, present: categoryVenues[label] ?? [])
            else { return }
            target = landing
        } else {
            target = label
        }
        guard target != filter.source else { return }
        slideEdge = direction(from: filter.source, to: target)
        SwipeClock.step(to: target)
        // THE SLIDE GETS ITS FRAMES (PERF 2026-08-21, corrected 2026-09-01) —
        // see `swipeRowBudget` and `swipeBudgetSource`.
        //
        // ALL THREE WRITES IN ONE TRANSACTION, and that is a fix rather than
        // tidying. They were two: the bound was set first, on its own, so
        // SwiftUI ran a WHOLE EXTRA body pass of this surface with
        // `filter.source` still naming the room being LEFT — which rebuilt
        // that room's body and re-armed its `@Query`, on the main actor,
        // inside the frames the slide needs, for a room about to be thrown
        // away. Measured on a swipe between two rooms: one full outgoing
        // `FeedScreen` body build, removed by coalescing.
        //
        // The old comment's reasoning — "set BEFORE the source changes so the
        // incoming `init` already carries the bound" — is preserved exactly:
        // in the single body pass this now produces, the bound and the new
        // source land together, so the incoming room's very first `init`
        // still carries it.
        withAnimation(DS.Motion.standard) {
            swipeRowBudget = Self.swipeRowBudgetRows
            swipeBudgetSource = target
            swipeBudgetGeneration &+= 1
            filter.source = target
        }
    }

    /// A transient bound on the incoming room's query, for the length of the
    /// slide (PERF 2026-08-21, prd §434 ruling 2). See `FeedScreen.rowBudget`,
    /// which carries the full reasoning and the honesty argument.
    ///
    /// It lives HERE rather than inside `FeedScreen` because §265's transition
    /// is a REMOUNT and `@Query`'s descriptor is fixed at `init` — so the only
    /// place that can bound the incoming room's first fetch is the parent that
    /// builds it. That is also why it must be part of `FeedScreen`'s
    /// `Equatable`: clearing it is a parameter change, and a parameter change
    /// is the only thing that re-runs `init` and re-arms the query.
    @State private var swipeRowBudget: Int?

    /// WHICH room that bound belongs to (PERF 2026-09-01).
    ///
    /// The bound used to be a bare number applied to whatever room the surface
    /// was rendering, and a swipe still produces one body pass in which
    /// `filter.source` names the room being LEFT. So the outgoing room was
    /// re-initialised with a bounded descriptor and re-fetched — a predicated
    /// SwiftData fetch, on the main actor, mid-slide, for rows nobody will
    /// see. Since 2026-08-31 that fetch also materialises the heavy inline
    /// text, so it got more expensive rather than less.
    ///
    /// Named, it is inert in that pass: the outgoing screen is handed exactly
    /// the parameters it already had, `FeedScreen: Equatable` compares equal,
    /// and SwiftUI does not rebuild it. Measured on the same two swipes as the
    /// coalescing above: 425ms → 235ms and 246ms → 131ms, gesture to rows.
    ///
    /// Cleared with the bound, so the two can never disagree about which room
    /// is being entered.
    @State private var swipeBudgetSource: String?

    /// Which swipe the current budget belongs to, so a fast second swipe can
    /// never have the FIRST one's timer clear its bound out from under it.
    /// Bumped per step and captured by the release task — the guarded-timer
    /// shape this app uses wherever a later timer must not clear a newer
    /// value out from under itself.
    @State private var swipeBudgetGeneration = 0

    /// 150 rows — five of the feed's own 30-row windows.
    ///
    /// Not a tuning knob but an arithmetic one: the room windows at
    /// `windowRowTarget` and grows by that much per "Show older" tap, so this
    /// is the smallest bound that cannot change a single pixel of the first
    /// paint, with four spare windows nobody can open inside a slide.
    private static let swipeRowBudgetRows = 150

    /// Release the bound once the slide has had the main actor to itself.
    ///
    /// Keyed on the SOURCE, so it re-arms per room change and a superseded
    /// swipe's task is cancelled by SwiftUI rather than racing this one. The
    /// generation check is the second guard, for the case the cancellation
    /// lands after the sleep has already returned.
    private func releaseSwipeBudget() async {
        guard swipeRowBudget != nil else { return }
        let generation = swipeBudgetGeneration
        // Just past `DS.Motion.standard`'s own settle — long enough that the
        // full fetch lands after the last animated frame, short enough that the
        // head follows the room rather than trailing it.
        try? await Task.sleep(for: .milliseconds(360))
        guard !Task.isCancelled, swipeBudgetGeneration == generation else { return }
        swipeRowBudget = nil
        swipeBudgetSource = nil
    }

    /// Which edge the incoming room slides from.
    ///
    /// Two orders, because a fold gives a member source two different notions
    /// of "where it sits": inside the folded room the venues have no chip
    /// positions at all, so a switcher move reads its direction from the
    /// switcher's own order — otherwise every venue tap would slide the same
    /// way and the capsule's travel would contradict the room's.
    private func direction(from: String, to: String) -> Edge {
        // Against a switcher's DISPLAYED order (catalog), not the learned
        // order `categoryVenues` carries — the slide has to agree with the
        // capsule the finger just touched, or the room travels one way while
        // the selection fill travels the other. That agreement became visible
        // rather than theoretical with §357: the fill now really does travel
        // (its namespace survives the room change), so a disagreement here
        // would be two objects crossing in opposite directions on one screen.
        // Reachable for every folded category, not just Markets (prd §351
        // generalized what had been Markets-only here on 2026-08-10).
        if let category = BridgeCatalog.category(forSource: from),
           category == BridgeCatalog.category(forSource: to) {
            let present = Set(categoryVenues[category] ?? [])
            let shown = CategoryFold.scopes(category: category, present: present)
            if let a = shown.firstIndex(of: from), let b = shown.firstIndex(of: to) {
                return b >= a ? .trailing : .leading
            }
        }
        let labels = chipLabels
        let a = labels.firstIndex(of: CategoryFold.chipLabel(for: from, folded: labels)) ?? 0
        let b = labels.firstIndex(of: CategoryFold.chipLabel(for: to, folded: labels)) ?? a
        return b >= a ? .trailing : .leading
    }

    /// One step left or right in the strip's order. The swipe's whole job.
    private func step(_ delta: Int) {
        // Walks CHIPS, not sources (2026-08-10): the folded market seats are
        // one stop, so a swipe crosses the whole cluster in one step and moving
        // between venues is the switcher's job. Stepping through the members
        // instead would make a five-venue fold five swipes wide while showing
        // one chip, which is the strip lying about how far away things are.
        var labels = chipLabels
        // The room you are standing in may have no chip at all — a deep link
        // (casberi://feed/source/Gmail), a bridge connected but not yet synced,
        // or deleting the last row in the room you're in. It still has to be
        // somewhere in the walk, or the swipe silently dies exactly there and
        // the only way out is the strip. This is the guarantee the retired
        // `feedLabels` used to make for the pager's pages, kept.
        if !labels.contains(activeChip) { labels.append(activeChip) }
        guard let idx = labels.firstIndex(of: activeChip),
              labels.indices.contains(idx + delta) else { return }
        DSHaptic.selection()
        go(to: labels[idx + delta])
        ChipMemory.visited(filter.source)
    }


    private var surface: some View {
        // `@Environment` hands back the object, not a projection, so the two
        // places this body needs a real `Binding` — the stack's path and the
        // connect form — take one through a local `@Bindable` re-declaration
        // (the documented Observation pattern).
        @Bindable var route = route
        return NavigationStack(path: $route.path) {
            // The feeds are one surface and a swipe is a STEP, not a drag
            // (prd §265, 2026-08-01 — this replaced `TabView(.page)`).
            //
            // The pager carried a continuous scroll position, and for two weeks
            // of builds that position could rest BETWEEN two pages: the user's
            // recording showed a half-and-half frame held for ~0.8s, reported
            // as "swipes only go half way" across 220–225. Four measured cost
            // removals (§257–§264) each shaved the app's main-thread work and
            // none fixed it — the last, windowed rows, removed the single
            // largest cost in the app and the symptom survived it. Whatever
            // corrupts a `UICollectionView`'s mid-gesture offset under this
            // shell was never isolated; this removes the CLASS instead of the
            // instance. A discrete transition has no intermediate position to
            // strand at — the gesture ends, one full page slides in, done.
            //
            // What this trades away, stated: the page no longer tracks the
            // finger mid-drag, and only the ACTIVE room is mounted, so
            // switching away and back re-enters the room at its top (the
            // re-tap-a-chip pop already made that the going rate). What it
            // buys beyond the fix: the `nearActive`/`neighborsReady` machinery
            // is gone because there are no neighbour pages to pre-build, and a
            // re-render wave now touches ONE mounted FeedScreen, not every
            // room in the strip — the §258-era "23 page rebuilds per swipe"
            // measurement becomes structurally impossible.
            //
            // A chip tap and a swipe are still the same move: both walk
            // through `go(to:)`, which writes the SAME `filter.source` every
            // deep link (casberi://feed/source/X) already writes, so there is
            // still no second source of truth. `.id(filter.source)` is what
            // makes the switch a remove+insert pair the transition can
            // animate; the windowed rows (§264) are what make a fresh mount
            // cheap enough to pay at every switch.
            // No SwiftUI gesture here, and that is measured, not stylistic:
            // the first cut used `.simultaneousGesture(DragGesture)` and froze
            // vertical scrolling dead — the standing CLAUDE.md gotcha, which
            // the deck had already measured applies to simultaneous gestures
            // too. The swipe rides `PageSwipeCatcher` (a UIKit pan on the
            // List's own scroll view, mounted by FeedScreen), which hands its
            // one-step decision up through `chrome.pageStep` below.
            ZStack {
                FeedScreen(source: filter.source, isActive: true, nearActive: true,
                           // Only the room the swipe is going TO — see
                           // `swipeBudgetSource`.
                           rowBudget: swipeBudgetSource == filter.source ? swipeRowBudget : nil)
                    // See `FeedScreen: Equatable` — this is what stops a
                    // MainSurface render from rebuilding the whole feed
                    // (measured 15 body builds → 2).
                    .equatable()
                    .id(filter.source)
                    .transition(.asymmetric(
                        insertion: .move(edge: slideEdge),
                        removal: .move(edge: slideEdge == .trailing ? .leading : .trailing)))
            }
            // The swipe input, mounted ONCE at the shell — never inside the
            // transitioning subtree (see PageSwipeCatcher for the two designs
            // that died first). The gates are the walk's own modal flags: a
            // window-level recognizer must stand down when anything covers
            // the pager.
            .background {
                PageSwipeCatcher(
                    enabled: { !chrome.walkModalOpen && !chrome.walkSheetOpen
                               && !chrome.walkInPushedRoom },
                    step: { delta in step(delta) })
            }
            // Hands the room back its whole query once the slide is over.
            .task(id: filter.source) { await releaseSwipeBudget() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The strip FLOATS over the feed rather than sitting above it
            // (2026-07-20). It was a VStack sibling, which meant nothing ever
            // passed behind the chips — so the glass they wear blurred a flat
            // color and rendered indistinguishable from a solid fill, paying a
            // backdrop blur for nothing. `safeAreaInset` reserves the strip's
            // height at rest (rows still start below it, untouched) while letting
            // scrolled content travel UNDER it, which is the only thing that makes
            // the material read as glass. Pairs with each feed's `dsSoftScrollEdges()`:
            // the scroll edge dissolves content as it goes under, so rows melt into
            // the strip instead of colliding with it.
            // The fixed navigation strip — always in reach, never scrolls
            // away with content (the whole point of dropping the tab bar).
            // The avatar leads it now too (2026-07-20) — the system nav
            // bar it used to sit in alone is hidden below, so this strip
            // owns the top of the screen outright; the extra top padding
            // (was s2) is that vacated space becoming air, not bigger
            // chips (the 56pt Stories size is a 2026-07-10 ruling, not
            // being revisited here).
            //
            // On a regular-width surface the strip folds away here (see
            // `topInset`'s `showsRail` gate) and returns as the rail — same
            // view, same inset mechanism, one axis apart. The rail's own
            // inset is applied to the STACK rather than in here, because the
            // two differ on exactly one thing: this strip is allowed to
            // vanish into a pushed room and the rail is not.
            .safeAreaInset(edge: .bottom, spacing: 0) { bandInset }
            .safeAreaInset(edge: .top, spacing: 0) { demoBannerInset }
            // THE ROOM'S OWN SETTINGS DOOR (2026-08-21) — see `RoomGear` for
            // why a bare gear is legible here and why the room needed one.
            //
            // **It no longer chases the band (§591).** The offset below was
            // the band's MEASURED height, because the band owned the top of
            // the screen and an overlay does not inherit the safe area a
            // `.safeAreaInset` reserves — so without it the gear sat level
            // with the demo banner. The band is at the BOTTOM now, so that
            // measurement would push the gear a whole band's height down into
            // the feed to clear chrome that is no longer above it. A plain
            // step of air off the top edge is what is left; `bandHeight` is
            // still measured and still published, because `RoomGear` is not
            // its only reader.
            //
            // INSIDE the NavigationStack, like `topInset` and for the same
            // reason: a pushed room must cover it. A settings door floating over
            // a screen it does not configure is the dead control the honesty law
            // bans, wearing a live control's clothes.
            //
            // On the SHELL rather than on `FeedScreen`, so it survives a room
            // change instead of dying with the `.id()` subtree (§357). It reads
            // `filter.source`, which `go(to:)` has already resolved out of any
            // category label — never a fold label (§351).
            .overlay(alignment: .topTrailing) {
                RoomGear(source: filter.source)
                    .padding(.top, DS.Space.s2)
            }
            .onPreferenceChange(BandHeightKey.self) { bandHeight = $0 }
            // The detail pane (2026-07-25) — the iPad half of "a row tap
            // opens a thing". A trailing inset rather than an HStack sibling
            // so every modifier already hanging off the pager (the crown
            // background, the bloom overlay, the arrival watcher, the
            // navigation destinations) keeps applying to exactly what it
            // always did; the pane is simply reserved space beside it.
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if showsPane {
                    detailPane
                        .frame(width: PadLayout.paneWidth(for: surfaceWidth))
                }
            }
            // The rail's column, reserved (user ruling 2026-08-12) — see
            // `dsRailColumn` for why the `.safeAreaInset` that draws the rail
            // cannot do this itself. Applied AFTER both insets so the band and
            // the pane sit inside the reserved region too: the pane keeps its
            // own width against the window's trailing edge, and `topInset`
            // stops paying for the rail by hand (see there).
            .dsRailColumn(showsRail)
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
                    crownPour
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
                #if DEBUG
                // `-chipStats "Wallet:9,Photos:2"` seeds tap-learning counts
                // headlessly, then this logs the computed order so a chip
                // promotion verifies in one launch (seed Wallet high, watch
                // it lead the sources behind All).
                ChipMemory.seedFromLaunchArgs()
                // `-categoryOrder "Life,Wallet"` seeds a rearranged strip
                // headlessly (prd §533). Same position and same reason as the
                // seed above: it must land before the freeze it is meant to
                // decide.
                CategoryOrder.seedFromLaunchArgs()
                #endif
                // The session's order, taken once (see `chipLabels`). AFTER the
                // seed above, so `-chipStats` still decides what freezes —
                // which is also why this one is `force`ed past the coalescing
                // window in `freezeChips(force:)`.
                freezeChips(force: true)
                #if DEBUG
                NSLog("[Casberi] chipLabels: %@", chipLabels.joined(separator: ", "))
                // The category fold, reported from where it is actually
                // decided (prd §351, 2026-08-11, superseding the Markets-only
                // `marketsFold|` line this replaces) rather than re-derived in
                // `ProbeHooks` — which cannot reach `BridgeStore` anyway, and a
                // probe that recomputes an answer can only ever prove its own
                // copy of the rule. One line PER CATEGORY (the `-todayProbe`
                // truncation lesson) — an unfolded category has TWO causes
                // that look identical from outside (no member present, or the
                // catalog category renamed out from under `CategoryFold.members`),
                // so both are printed rather than just the verdict.
                for category in BridgeCatalog.categories {
                    let venues = categoryVenues[category.name] ?? []
                    NSLog("categoryFold| category=%@ folded=%@ venues=%d [%@] landing=%@ members=%d",
                          category.name,
                          chipLabels.contains(category.name) ? "YES" : "NO",
                          venues.count,
                          venues.joined(separator: ", "),
                          CategoryFold.landing(category: category.name, present: venues) ?? "none",
                          CategoryFold.members(of: category.name).count)
                }
                #endif
                // A door push that raced launch — casberi://settings arriving
                // before the first frame — used to get silently dropped by
                // the old item-based `navigationDestination(item:)` (audit
                // 2026-07-13: it only fires on a nil→value EDGE, and an early
                // set could land before the modifier was registered to see
                // it). `route.path` is read directly on every body
                // evaluation instead, so a push already sitting in it at
                // mount is rendered on the first frame with no re-landing
                // dance needed.
            }
            // Watches a COUNT, not `feedThings.count` (2026-07-31 perf): an
            // `onChange(of:)` value expression is evaluated on every body
            // pass, so asking it for the filtered count meant a full corpus
            // walk per pass — half of the 74 measured at launch. A
            // search-only source (Contacts) landing moves this count without
            // moving the filtered one; the diff below simply finds nothing
            // fresh and returns, which is the same outcome as never firing.
            //
            // `corpusRevision`, not `things.count`, since 2026-08-11 — the
            // raw count was neither free nor able to change past the query's
            // own 400-row bound. See `corpusRevision`.
            .onChange(of: corpusRevision) { _, _ in
                // One walk for the whole watcher — every derivation below
                // reads this binding rather than asking `feedThings` again.
                let surfaced = feedThings
                // A source may have arrived or emptied out; the strip's live
                // set is derived from the corpus, so it moves with it.
                refreshLiveChips()
                let ids = Set(surfaced.map(\.id))
                defer { seenIDs = ids }
                // nil = the query hasn't been baselined yet (cold mount).
                guard let seen = seenIDs else { return }
                let fresh = ids.subtracting(seen)
                // 1–12 fresh records is an arrival (one capture, one bridge
                // sync burst); more is a backfill (an import, the initial
                // populate) — a bob for a bulk import would be noise.
                guard !fresh.isEmpty, fresh.count <= 12 else { return }
                // The loudest voice of the batch: its newest member.
                guard let lead = surfaced.first(where: { fresh.contains($0.id) })
                else { return }
                // First-ever = nothing OLDER from this source survives AND
                // the source has never bloomed before (persistent — pruning
                // old things must not replay the connect celebration).
                let bloomedKey = "bloom.seen.\(lead.source)"
                let hasOlder = surfaced.contains {
                    $0.source == lead.source && !fresh.contains($0.id)
                }
                let firstEver = !hasOlder
                    && !UserDefaults.standard.bool(forKey: bloomedKey)
                // Bobbed and flipped on the CHIP that's actually showing (prd
                // §351, generalizing 2026-08-10): a folded seat has no circle
                // of its own, so keying the catch on the raw source would
                // silently drop every arrival celebration for the whole
                // cluster — the bloom fires against a chip that isn't in the
                // strip and nothing moves. The hue below still reads the real
                // source.
                chrome.chipCaught(CategoryFold.chipLabel(for: lead.source, folded: chipLabels),
                                  firstEver: firstEver)
                if firstEver {
                    UserDefaults.standard.set(true, forKey: bloomedKey)
                    // A source with no honest brand color to show blooms
                    // neutral, not blue (2026-08-10) — the same "unknown
                    // gets no invented hue" ruling `TokenHue` followed.
                    let hue = DS.washHue(for: lead.source) ?? DS.neutralBadge
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
            // The agent bar moved OFF MainSurface entirely (docs/agent-brief.md
            // ruling 6): it now rides RootShell's own ZStack, above EVERY
            // screen this app can push (Apps, Settings, a bridge setup form),
            // not just this one's root — the FAB used to stop at MainSurface's
            // edge on purpose; the bar deliberately doesn't.
            // Refresh delight (2026-07-14): every pull on this one surface
            // bumps chrome.refreshPulse — the berry rain falls over the
            // content and the avatar door spins (below). Decorative only;
            // hit-testing is off inside BerryRain.
            .overlay { BerryRain(trigger: chrome.refreshPulse, hue: chrome.refreshHue) }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // The nav bar itself is hidden now (2026-07-20) — nothing lives
            // in it anymore. The avatar (was the sole trailing toolbar item,
            // `TopDoors`) joined the catalogue door as a fixed leading chip
            // in `SourceChips` above; that strip owns the top of the screen
            // outright. First `.toolbar(.hidden, for:)` in this codebase —
            // there was nothing to hide FROM before this move.
            .toolbar(.hidden, for: .navigationBar)
            // One ordered path (see `HomeRoute.Node`) — Apps/Settings and
            // every bridge screen (Feed's Manage, an Apps tile's capsule, a
            // product page's Connect/Open) all push through this single
            // registration, so a bridge screen pushed from on top of Apps
            // genuinely nests under it and the native back chevron always
            // pops exactly one real frame.
            .navigationDestination(for: HomeRoute.Node.self) { node in
                // Every pushed room reserves the rail too, and it is the same
                // one line rather than a rule each screen has to remember: the
                // rail lives OUTSIDE this stack precisely so it survives a
                // push (see `showsRail`), which means Apps, Settings and every
                // bridge form are drawn under it exactly as the feed was.
                // They read as fine on a wide window for the same accidental
                // reason the feed did — `dsAdaptiveContentWidth` centres them
                // — and collide at the same widths.
                pushedRoom(node).dsRailColumn(showsRail)
            }
        }
        // The connect form, raised over wherever the person is (prd §218) —
        // mounted ONCE, on the stack itself, so it covers a pushed catalog or
        // product page too. Every Connect in the app routes through
        // `HomeRoute.openSetup`, so a tile, a peek preview and a product page
        // can't drift into three different presentations of one act.
        .sheet(item: $route.connectForm) { destination in
            // RE-INJECTED, and this is `rootPresented`'s rule reaching the one
            // presentation that never went through it (App Store review
            // 2.1(a) on the Mac build, crash reproduced 2026-08-18).
            //
            // A sheet is built in its OWN hosting controller, and the shell's
            // `.environment(...)` injections do not reach it here — so
            // `ConnectFormSheet`'s required `@Environment(BridgeStore.self)`
            // read a value that was not there and trapped at mount:
            // "No Observable object of type BridgeStore found", every time,
            // before a single frame of the form was drawn.
            //
            // It is NOT an Apple-bridge bug, which is what the report looked
            // like: `raisedByConnect` is true for every destination but the
            // wallet, so this fired for the FIRST Connect anyone tapped on any
            // setup bridge. The reviewer's happened to be the Apple Notes
            // story card.
            //
            // `RootShell.rootPresented` is the same three lines and cannot be
            // called from here (it is private to that view), so this mirrors
            // it deliberately — see its doc: "any new shell-wide environment
            // object gets added HERE, not to individual sheets", which now
            // means both places.
            ConnectFormSheet(destination: destination)
                .environment(store)
                .environment(chrome)
                .environment(\.locale, LanguageStore.shared.locale)
        }
        // The rail (2026-08-10) — see `body` and `railInset`. On the STACK,
        // deliberately, not inside its content closure like the `.top` strip
        // above: the strip is allowed to vanish into a pushed room and the
        // rail is not, and that one line of placement is the whole difference
        // between them.
        .safeAreaInset(edge: .leading, spacing: 0) { railInset }
        .tint(DS.tint)
    }
}
