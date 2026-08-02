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
    private static var chipCorpus: FetchDescriptor<Thing> {
        var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.propertiesToFetch = [\.id, \.source, \.capturedAt, \.title, \.tags]
        return d
    }
    @Environment(ShellChrome.self) private var chrome
    /// Read for the LIVE-room chips only (prd §234) — a connected Kalshi or
    /// Polymarket earns a chip with nothing landed yet, since its room's
    /// content is the live book rather than the corpus.
    @Environment(BridgeStore.self) private var store
    @Bindable private var filter = FeedFilter.shared
    @Bindable private var route = HomeRoute.shared
    /// Source moments (wallet new highs, token new highs, a Bitrefill refill,
    /// a quiet account posting again) — the data paths can't reach the
    /// corpus-arrival watcher that fires the release rain (some aren't things
    /// at all; others are a FACT about a thing, not its landing), so they
    /// enqueue here and this surface deals the same berry rain + toast
    /// (delight 2026-07-15, generalized 2026-07-21 — prd "surprise & delight
    /// in the source feeds").
    private let sourceMoments = SourceMoments.shared
    /// Anchors the doors' zoom transitions (each room grows from its door).
    @Namespace private var doorNS

    /// iPad (2026-07-25). `regular` alone decides the RAIL; the detail pane
    /// additionally needs real width (see `PadLayout.minWidthForPane`), so
    /// the shell measures itself rather than guessing from the idiom — an
    /// iPad mini in portrait and an iPad in Slide Over are both "iPad" and
    /// neither can hold two columns.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var surfaceWidth: CGFloat = 0
    @Bindable private var detail = PadDetailSelection.shared
    /// The rendered appearance, for the pane brief's own gain/loss accent —
    /// Mac follows the SYSTEM's mode (`RootShell`'s `.preferredColorScheme(nil)`
    /// under Catalyst), so the accent has to read the trait it actually got.
    @Environment(\.colorScheme) private var paneScheme

    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var showsPane: Bool { isRegular && surfaceWidth >= PadLayout.minWidthForPane }
    /// The rail is an iPad-regular-width answer specifically — a Mac window
    /// also reports `.regular` (Catalyst has no compact width in practice),
    /// but the horizontal strip is the one built for a wide/landscape-shaped
    /// surface (user ruling 2026-07-28), so Mac keeps it rather than
    /// silently inheriting the iPad rail rule. The detail pane (`showsPane`)
    /// is untouched — that's a width question, not an axis one.
    private var showsRail: Bool { isRegular && !ProcessInfo.processInfo.isMacCatalystApp }

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
        let live = liveChips ?? computedChipLabels
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
    private func freezeChips() {
        let live = computedChipLabels
        liveChips = live
        frozenChips = live
    }

    /// Refresh the live set WITHOUT re-freezing — a source arriving or leaving
    /// mid-session must be reflected (that's what earns a new room its head
    /// slot in `chipLabels`), but re-freezing here would slide the strip under
    /// a thumb, which is the one thing the freeze exists to prevent.
    private func refreshLiveChips() { liveChips = computedChipLabels }

    /// Chip order: All, then every source — most-recent-first is still the
    /// baseline (`things` is newest-first, so first appearance IS the newest
    /// thing per source), but a source you actually VISIT often (`ChipMemory`,
    /// amends §131, 2026-07-21) sorts ahead of it. `sorted` is stable, so a
    /// zero-weight tie keeps the recency order untouched — this only ever
    /// promotes a chip you use, never reorders the rest.
    private var computedChipLabels: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for thing in feedThings where seen.insert(thing.source).inserted {
            ordered.append(thing.source)
        }
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
        return ["All"] + learned
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
    // `DS.bleed`, one of five curated options, Casberi blue by default. The
    // trade is stated on purpose in §204: the pour stops being only Casberi's
    // and becomes theirs, with ours as the default. The wallet-face carve-out
    // (`pourHue`) is unchanged and still wins first; `DS.tint`, the pressable
    // signal at 157 other sites, does not move.
    //
    // It lives HERE, not on the feed pages, because the first cut lived on the
    // page and taught why that can't work (user screenshot, 2026-07-21): the
    // chip strip floats over the pager on a `safeAreaInset`, so a page-level
    // field stops at the page's edge and the strip zone stays flat black — a
    // hard seam exactly on the no-hairlines law. The shell owns the crown; the
    // field must too.
    private var crownPour: some View {
        let hue = chrome.pourHue ?? DS.bleed
        // Photo themes force the dark treatment (DS.themedPage's own rule);
        // only a true light page halves the dose — the same field that reads
        // as atmosphere on ink reads as a stain on white.
        let light = ThemeStore.shared.isLight && ThemeStore.shared.backgroundPhoto == nil
        return LinearGradient(stops: [
            .init(color: hue.opacity(light ? 0.16 : 0.30), location: 0),
            .init(color: hue.opacity(light ? 0.05 : 0.10), location: 0.5),
            .init(color: hue.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
            .frame(height: 500)
            .frame(maxHeight: .infinity, alignment: .top)
            // A scope switch re-tints the crown as one move with the switcher
            // capsule's slide — not a hard swap.
            .animation(DS.Motion.standard, value: chrome.pourHue)
    }

    /// The chip strip in whichever orientation this device wears it. One
    /// call site for the taps so the strip and the rail can never drift on
    /// what a chip actually DOES.
    private func sourceStrip(axis: Axis) -> some View {
        SourceChips(labels: chipLabels, active: filter.source,
                    axis: axis,
                    minimized: chrome.minimized,
                    onApps: { route.present(.apps) },
                    onSettings: { route.present(.settings) },
                    refreshSpin: chrome.refreshPulse,
                    zoomNS: doorNS) { label in
            if label == filter.source {
                // Re-tapping the chip you're already on pops back to
                // root (the old per-tab habit) instead of doing nothing.
                chrome.popHome += 1
                return
            }
            go(to: label)
            // Tap-learning (ChipMemory) counts an actual switch, not
            // the re-tap-to-pop branch above.
            ChipMemory.visited(label)
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
        .onChange(of: things.count) { _, _ in detail.pruneIfDead() }
    }

    /// The pane at rest — the DAY (2026-07-31), not a placeholder sentence.
    ///
    /// This is the largest single area the app shows at rest: up to 560pt of
    /// the widest column, for the whole session, previously holding a mark and
    /// the words "Pick something to open it here." A sentence that describes
    /// the layout is not content, and on a Mac window it is most of what you
    /// see. §249 already ruled that the agent's room leads with the day; the
    /// pane leads with the same line, which is what makes the desktop's extra
    /// width worth having rather than merely wide.
    ///
    /// It reads `chrome.paneBrief` — composed by the same `DayBrief` pass the
    /// whisper capsule uses, published ungated (see `ShellChrome.paneBrief`),
    /// so the pane and the capsule can never state different days. On a day
    /// with nothing to say it composes nil and the quiet mark stands, exactly
    /// as before: the honesty law forbids manufacturing a headline to fill a
    /// column.
    ///
    /// No berry inside the brief — §249's ruling ("i like our logo in the
    /// search / whisper bar, but not inside the daily brief itself"). The mark
    /// survives only in the nothing-to-say branch, where there is no brief for
    /// it to be inside of.
    private var paneRest: some View {
        VStack(spacing: DS.Space.s3) {
            if let brief = chrome.paneBrief {
                paneBriefCard(brief)
            } else {
                CasberiMark(size: 44)
                    .opacity(0.32)
                Text("Pick something to open.")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DS.Space.s6)
    }

    /// The day as the pane's lead. Tapping opens the real Today brief, routed
    /// through `chrome.askRequest` — the same door the whisper capsule, the
    /// bar's own tap and a typed "how's my day" all use (§132), so a fourth
    /// entry point can't drift into a fourth presentation of one screen.
    private func paneBriefCard(_ brief: DayBrief.Whisper) -> some View {
        Button {
            DSHaptic.tap()
            chrome.ask(TodayBrief.title)
            chrome.openComposer()
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(brief.title)
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                brief.detailText(scheme: paneScheme)
                    .dsText(.body17)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Open your day")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.tint)
                    .padding(.top, DS.Space.s1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(brief.title). \(brief.detail)")
        .accessibilityHint("Opens your day")
    }

    var body: some View {
        // On iPad the rail sits OUTSIDE the NavigationStack (2026-07-25), so
        // a pushed room — Apps, Settings, a bridge setup form — is inset
        // beside it rather than covering it. Primary navigation that
        // disappears the moment you use it is the phone's compromise, made
        // because a phone has no room to keep it; an iPad does. It is the
        // same argument ruling 6 already made for the agent bar.
        //
        // It carries the shell's field itself rather than relying on a
        // background behind the stack — an opaque UIKit backing means nothing
        // behind a NavigationStack ever shows through (the standing gotcha),
        // and the pour is the same top-anchored 500pt gradient on both sides,
        // so the two line up with no seam.
        HStack(spacing: 0) {
            if showsRail {
                sourceStrip(axis: .vertical)
                    .background {
                        ZStack(alignment: .top) {
                            DS.themedPage
                            crownPour
                        }
                        .ignoresSafeArea()
                    }
            }
            surface
        }
        // Measured on the WHOLE surface, not the stack beside the rail:
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
        .onChange(of: chipLabels, initial: true) { _, labels in
            chrome.chipOrder = labels
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
        // re-sorts on the AppKit focus-in instead. `freezeChips` is a pure
        // local sort, so the extra fires a Mac's focus flips produce are free.
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
    }

    /// Which edge the incoming room slides from — set by `go(to:)` BEFORE the
    /// source changes, so both halves of the transition read the same answer.
    @State private var slideEdge: Edge = .trailing

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
        guard label != filter.source else { return }
        let labels = feedLabels
        let from = labels.firstIndex(of: filter.source) ?? 0
        let to = labels.firstIndex(of: label) ?? from
        slideEdge = to >= from ? .trailing : .leading
        withAnimation(DS.Motion.standard) {
            filter.source = label
        }
    }

    /// One step left or right in the strip's order. The swipe's whole job.
    private func step(_ delta: Int) {
        let labels = feedLabels
        guard let idx = labels.firstIndex(of: filter.source),
              labels.indices.contains(idx + delta) else { return }
        DSHaptic.selection()
        go(to: labels[idx + delta])
        ChipMemory.visited(filter.source)
    }


    private var surface: some View {
        NavigationStack(path: $route.path) {
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
                FeedScreen(source: filter.source, isActive: true, nearActive: true)
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
            // On iPad it insets the LEADING edge instead as a vertical rail
            // (2026-07-25). Same view, same inset mechanism, one axis apart:
            // `safeAreaInset` reserves the rail's width so every feed page's
            // rows start beside it rather than under it, and the crown pour
            // painted by this surface's own background still runs behind it.
            .safeAreaInset(edge: .top, spacing: 0) {
                if !showsRail {
                    sourceStrip(axis: .horizontal)
                        // The s6 top padding replaces iPhone's hidden system
                        // nav bar with air. A Mac window already has a REAL
                        // title bar there — stacking a second s6 on top of
                        // it read as ~65pt of dead chrome before the strip
                        // even starts (Mac polish, 2026-07-28), so Mac gets
                        // only a small breathing gap instead.
                        // …and that vacated space is the first thing handed
                        // back when the strip folds (2026-07-30): air is what
                        // it was, and content is what it's for.
                        .padding(.top, ProcessInfo.processInfo.isMacCatalystApp || chrome.minimized
                                 ? DS.Space.s2 : DS.Space.s6)
                        .padding(.bottom, DS.Space.s2)
                }
            }
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
                #endif
                // The session's order, taken once (see `chipLabels`). AFTER the
                // seed above, so `-chipStats` still decides what freezes.
                freezeChips()
                #if DEBUG
                NSLog("[Casberi] chipLabels: %@", chipLabels.joined(separator: ", "))
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
            // Watches the RAW query count, not `feedThings.count` (2026-07-31
            // perf): an `onChange(of:)` value expression is evaluated on every
            // body pass, so asking it for the filtered count meant a full
            // corpus walk per pass — half of the 74 measured at launch. The
            // raw count is an O(1) read of an array already in hand. A
            // search-only source (Contacts) landing moves this count without
            // moving the filtered one; the diff below simply finds nothing
            // fresh and returns, which is the same outcome as never firing.
            .onChange(of: things.count) { _, _ in
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
                chrome.chipCaught(lead.source, firstEver: firstEver)
                // A repo you star shipping a MAJOR release (a clean x.0.0) is a
                // moment worth marking: the berry rain falls and a toast names
                // it. One celebration per arrival batch — the marker is stamped
                // at ingest (GitHubFeedFetch.isMajorRelease).
                if let major = surfaced.first(where: {
                    fresh.contains($0.id) && $0.source == "GitHub"
                        && $0.tags.contains(GitHubFeedFetch.majorReleaseTag)
                }) {
                    chrome.refreshPulse += 1
                    chrome.flash(String(localized: "\(major.title) is out 🎉"))
                }
                // A source crossing a round total of things is a quiet
                // count-up, said once (prd §36v, generalized per-source
                // 2026-07-21) — a fact the corpus can prove, never a streak.
                let sourceCount = surfaced.filter { $0.source == lead.source }.count
                ThingMilestones.check(source: lead.source, count: sourceCount, chrome: chrome)
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
            // A source moment landed (a wallet or token new high, a Bitrefill
            // refill, a quiet account posting again) — deal the same berry
            // rain + toast the starred-repo release uses, tinted to the
            // moment's own source hue when it names one, so every source's
            // celebration reads the same family in its own color. The line
            // names the moment.
            .onChange(of: sourceMoments.pulse) {
                let moments = sourceMoments.drain()
                guard !moments.isEmpty else { return }
                // Rain once for the whole batch (repeating the berry shower
                // per moment would read as spam, not delight); tinted to the
                // newest moment's hue. A queue (not a single slot) means a
                // moment fired while backgrounded survives here until this
                // drain runs on foreground.
                chrome.refreshHue = moments.last?.source.flatMap { DS.washHue(for: $0) }
                chrome.refreshPulse += 1
                // Toasts are one slot (ShellChrome.flash crossfades, never
                // stacks) — showing only `moments.last` silently dropped
                // every other moment in a busy pass (a widening blind spot
                // as more bridges gained moments, 2026-07-28). Walk the
                // batch oldest-first instead, each getting its own toast
                // window before the next replaces it, so a validator
                // proposing a block and a mention landing in the same
                // sweep both get said, not just whichever fired last.
                Task { @MainActor in
                    for (index, moment) in moments.enumerated() {
                        if index > 0 { try? await Task.sleep(for: .seconds(2.2)) }
                        chrome.flash(moment.text)
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
                switch node {
                case .apps:
                    AppsScreen()
                        .navigationTransition(.zoom(sourceID: "appsDoor", in: doorNS))
                case .settings:
                    SettingsScreen()
                        .navigationTransition(.zoom(sourceID: "settingsDoor", in: doorNS))
                case .bridge(let dest):
                    BridgeDestinationView(destination: dest)
                case .appDetail(let name):
                    if let offer = BridgeCatalog.offers.first(where: { $0.name == name }) {
                        AppDetailScreen(offer: offer)
                    }
                case .project(let name):
                    ProjectDetailScreen(projectName: name)
                }
            }
        }
        // The connect form, raised over wherever the person is (prd §218) —
        // mounted ONCE, on the stack itself, so it covers a pushed catalog or
        // product page too. Every Connect in the app routes through
        // `HomeRoute.openSetup`, so a tile, a peek preview and a product page
        // can't drift into three different presentations of one act.
        .sheet(item: $route.connectForm) { destination in
            ConnectFormSheet(destination: destination)
        }
        .tint(DS.tint)
    }
}
