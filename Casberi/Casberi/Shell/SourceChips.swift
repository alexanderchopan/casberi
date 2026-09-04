import SwiftUI

/// The shell's one navigation strip (2026-07-13, drastic restructure): the app
/// is a single scrolling surface, and this chip row IS how you move through it.
/// The tab bar is gone — All leads (the whole feed), then every source
/// most-recent-first. Tapping a chip swaps the surface under a fixed header,
/// so the strip never scrolls out of reach the way Feed's old in-list chip
/// row did. (The Pinned board that used to lead retired 2026-07-20,
/// docs/agent-brief.md rulings 11-12 — content-first, always.)
///
/// **"All" is PINNED, not merely first (2026-08-16).** It renders in the fixed
/// head beside the two doors and is filtered out of the scroll, so the way back
/// to the whole feed is on screen in every room, at every scroll offset. See
/// `horizontalStrip`'s head for the argument; the cost is stated there too.
///
/// TWO SHAPES, ONE GRAMMAR (2026-08-11, the design pass prd §351 called for
/// and its own ship deferred): **a mark gets a circle, a word gets a capsule.**
/// The fixed doors, "All" and the pinned room keep the 56pt Stories circle they
/// have worn since 2026-07-10 — they are marks, and they are the anchors the
/// strip's rhythm is measured from. A CATEGORY chip is a word, and a word does
/// not fit a circle: §351 shipped these as text inside "All"'s glass circle,
/// where each label independently shrank to fit (`minimumScaleFactor(0.55)`),
/// so one row rendered "Life" near full size beside a ~7pt "Shopping" — four
/// type sizes in a strip whose whole job is to be scanned, and worse again at
/// the 40pt minimized step. The capsule grows to hold its word instead, so
/// every category reads at the same 12pt.
///
/// **This does not reopen the icon-only ruling (2026-07-09, "labels made the
/// row scroll").** That ruling was about labelling every SOURCE — an unbounded
/// set, dozens of them on a full corpus. Categories are capped at eleven by
/// `BridgeCatalog.categories` and most corpora show five or six, which is the
/// whole reason the fold was worth doing; the objection that produced the
/// icon-only circle does not survive that change of scale. Per-source icon-only
/// chips are still the rule anywhere a source draws its own row.
///
/// The active chip wears the blue ink ring; a category whose members include a
/// broken connection wears a dashed orange one. Both rings are `Capsule`s now
/// rather than `Circle`s — a capsule in a square frame IS a circle, so the
/// circle chips are pixel-identical and the ONE ring that slides between chips
/// (`matchedGeometryEffect`) morphs between the two shapes instead of having to
/// swap shape mid-flight.
/// On iPad (regular width) the same strip turns 90° and becomes a fixed RAIL
/// down the leading edge (2026-07-25, user ruling) — same 56pt Stories
/// circles, same avatar-then-catalogue head, same rings, flips, catch bobs and
/// accessibility. It is ONE view with an `axis`, not two: every behaviour on a
/// chip (the sliding active ring, `ChipCatchBob`, the coin flip, the "All"
/// chip reporting its frame so the capture flight knows where to land) would
/// otherwise have to be kept in step across two copies, which is exactly how
/// the old Home/Feed split drifted.
struct SourceChips: View {
    /// The full ordered label list — "All", then real sources. Handed in whole
    /// even though "All" is pinned rather than scrolled: this order is what
    /// Mac's ⌘1–⌘9 is positional against (`scripts/mac-parity-audit.py` check
    /// 3), so the strip splits it for LAYOUT and never renumbers it.
    let labels: [String]
    let active: String
    /// `.horizontal` is the iPhone strip; `.vertical` is the iPad rail.
    /// The chip for the room you are STANDING IN, which since §591c is not
    /// always the lit one: `active` is the OPEN FOLDER (what you last selected)
    /// and this is where the feed actually is. They coincide unless you open
    /// one folder while standing in another.
    ///
    /// It exists so that divergence costs nothing: §357's rule is that a filter
    /// you are standing in must show you that you are standing in it, and a
    /// strip whose only mark went to the folder you were merely peeking into
    /// would break it. The standing chip keeps a tint ring.
    var standing: String = ""

    var axis: Axis = .horizontal
    /// The seats behind every folded category chip, in learned order, keyed by
    /// category name (prd §351, 2026-08-11 — generalizes what was
    /// `marketVenues`, a single array Markets alone ever filled).
    ///
    /// Passed in rather than read off `ShellChrome`, because the strip renders
    /// once BEFORE the shell's `onAppear` has published anything. The owner
    /// hands over a value with its own fallback (`MainSurface.chipSnapshot`), so
    /// the venues and the labels can never disagree with the chip beside them.
    ///
    /// Still needed with the landing mark gone (2026-08-11): a category chip's
    /// dashed attention ring answers for every seat behind it, and the tap
    /// resolves through this list.
    var categoryVenues: [String: [String]] = [:]
    /// Folded while the feed scrolls down (2026-07-30, `ShellChrome.minimized`).
    ///
    /// The strip does NOT leave — that ruling stands and is the whole reason
    /// the tab bar went ("always in reach, never scrolls away with content").
    /// It gets smaller: the chips step 56→48, while the two fixed
    /// doors at the head keep their exact size and position, so nothing you
    /// were already reaching for moves. iPad's rail sits it out — it folds a
    /// HEIGHT, and a vertical rail has height to spare.
    ///
    /// **The pinned "All" chip folds WITH the chips, not with the doors it now
    /// sits beside (2026-08-16).** It is a chip — the peer of every category
    /// word beside it — and holding it at 56 while they stepped to 48 would
    /// single it out for a reason that is an implementation detail of where it
    /// is drawn (§358's own finding, that treating one word chip differently
    /// from the others makes the odd one out read as inert). Its POSITION is
    /// still fixed, which is the half of the doors' rule that matters: it folds
    /// in place, and only the scroll inset past it moves.
    var minimized: Bool = false

    private var folds: Bool { minimized && axis == .horizontal }
    /// The chip's own icon; the doors beside it are deliberately fixed at 46.
    /// A capsule chip takes this as its HEIGHT, so every chip in the strip
    /// shares one vertical rhythm and nothing above or below this view — the
    /// leading-dissolve mask, the doors, the inset the shell reserves — has to
    /// know that some chips are now wider than they are tall.
    private var iconSize: CGFloat { folds ? 40 : 46 }
    /// The chip's outer slot, ring included. A capsule chip uses this for
    /// height only and takes its width from its own word.
    private var chipSize: CGFloat { folds ? 48 : 56 }
    /// The air inside a capsule, left and right of its content.
    private var capsulePadH: CGFloat { folds ? DS.Space.s2 : DS.Space.s3 }

    /// The gap between chips, tightened from `s3` (14) when category chips
    /// became capsules.
    ///
    /// A capsule carries its own edges, so it needs less air around it than a
    /// bare circle did — and the tightening buys back most of the on-screen
    /// chip count the wider shape costs. Arithmetic on the 12pt label rather
    /// than a device measurement: against the ~269pt of visible strip left by
    /// the two fixed doors, 56pt circles at a 14pt gap show ~3.8 chips, and
    /// capsules at this 10pt gap show ~3.3. At the old gap it was ~3.0.
    /// Re-measure on a device before trading it away.
    private static let chipGap: CGFloat = DS.Space.s2

    /// A capsule chip's fixed width on the iPad rail, which is a column of a
    /// FIXED width rather than a scroll of intrinsic ones — so a capsule there
    /// sizes to the rail instead of to its word, and every chip in the column
    /// stays the same width. Uniformity is what makes the type uniform here:
    /// the container bounds the longest word, so nothing else has to.
    private static let railChipWidth: CGFloat = PadLayout.railWidth - 2 * DS.Space.s2
    /// Opens the app catalogue (user 2026-07-17: its door moved OUT of the
    /// top-right cluster and INTO the head of this strip — "add a source"
    /// belongs with your sources).
    var onApps: () -> Void = {}
    /// Opens Settings — the avatar joined this strip too (2026-07-20,
    /// Stories-style: your own face leads, fixed, ahead of the catalogue
    /// door). The system nav bar it used to live in alone is hidden now.
    var onSettings: () -> Void = {}
    /// Pull-to-refresh spin, threaded through to the avatar exactly as it
    /// was when it lived in the toolbar.
    var refreshSpin: Int = 0
    /// The zoom anchor BOTH fixed doors grow out of — the catalogue's
    /// "appsDoor" transition and the avatar's "settingsDoor" transition
    /// share one namespace under different ids, same as before the move.
    var zoomNS: Namespace.ID? = nil
    let onTap: (String) -> Void

    @Environment(BridgeStore.self) private var bridges
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ONE namespace the strip's selection travels in — the blue fill on a
    /// word chip and the ink ring on a mark chip are the SAME object wearing two
    /// forms (prd §412b, 2026-08-20).
    ///
    /// **This replaces two namespaces, and overturns the reasoning that split
    /// them.** That note said sharing one "would make each try to become the
    /// other" — true only if they shared a namespace AND an id, which they never
    /// did, so the split was load-bearing against a collision that could not
    /// happen. What it cost was real: the fill and the ring each had exactly one
    /// participant, so a switch from a word chip ("All", any category) to a MARK
    /// chip (the pinned room, an uncategorized source) had nothing to interpolate
    /// with — the fill faded out where it stood and the ring faded in where it
    /// landed. Two states blinking, at the one crossing the 2026-07-14 ruling
    /// ("selection is an object traveling, not two states blinking") did not
    /// reach.
    ///
    /// Sharing both is SAFE because the two are mutually exclusive by
    /// construction, not by luck: exactly one chip satisfies `label == active`,
    /// and within that chip `isWord` decides which form draws — a word chip
    /// renders the fill and no ring (`if isActive, !isWord`), a mark chip the
    /// ring and no fill (`wordChipFill` is reached only from the two word
    /// branches). So there is never more than one source in the group, which is
    /// the same guarantee the fill already relied on to travel between two word
    /// chips.
    ///
    /// It is also the pattern `WordChipFill`'s own note records as the measured
    /// winner: one id across two branches of one `if`, which interpolates, rather
    /// than a hoisted shape positioned from a preference, which teleports.
    @Namespace private var selectionNS
    /// The label the finger just touched — cleared by the `active` change it
    /// causes. See the horizontal strip's `onChange`: a tapped chip is provably
    /// on screen, so it is the one route that must NOT re-centre, or the
    /// travelling selection has nowhere to travel.
    @State private var tapped: String?
    /// The two fixed doors' glass union (2026-08-06) — see `dsGlassDoor`. Owned
    /// here rather than passed in, because the pair only exists in this strip.
    @Namespace private var doorGlassNS
    /// Last time the catalogue door actually opened — see `openApps()`.
    @State private var lastAppsOpen: TimeInterval = 0

    /// One value both doors key on, so the pair can't drift onto two different
    /// unions and quietly stop being one shape.
    private var doorsUnion: DSGlassUnion {
        DSGlassUnion(id: "stripDoors", namespace: doorGlassNS)
    }

    // Leading-dissolve geometry (user, 2026-07-19). On the PHONE the head is
    // now one chip — "All" at `s4`, `chipSize` wide — and the scrolling chips
    // pass beneath it, each melting out over `fadeRamp` as it arrives (see
    // `horizontalStrip`). `stripInset` sets the first chip to rest right where
    // the ramp ends, so nothing is dimmed at rest. Tune `fadeRamp` for a
    // softer/tighter melt.
    //
    // This comment used to describe THREE fixed marks — avatar, catalogue,
    // "All" — because that is what the head was from 2026-08-16 until the two
    // doors moved to the sources tray on 2026-08-24 (see `head`). The widths
    // below survive for the iPad RAIL, which still draws both doors.
    //
    // `iconGap` NARROWED s3→s2 the same day (user: "i think we could move the
    // avatar, apps, and all closer to each other"), and it is now the rail's
    // gap alone. Kept rather than reverted: the rail stacks the same marks
    // vertically and the tighter pitch reads better there too.
    //
    // `headTrailingEdge` and everything derived from it are computed from
    // these constants, so the melt's ramp follows any change for free —
    // nothing hardcodes a width.
    private static let avatarWidth: CGFloat = 46
    private static let catalogueWidth: CGFloat = 46
    private static let iconGap: CGFloat = DS.Space.s2
    /// Where the pinned head ENDS — on the phone that is the leading margin
    /// plus the "All" chip, and nothing else since the two doors moved to the
    /// sources tray (2026-08-24; see `head`). `avatarWidth`/`catalogueWidth`
    /// survive because the iPad RAIL still draws both — it has vertical room to
    /// spare, which is the same reason its own doc gives for having no fade
    /// mask — and `headDoors` sizes itself from them.
    ///
    /// Instance rather than `static` because `chipSize` folds with the strip
    /// (56→48): a static edge measured at the resting size would leave an 8pt
    /// dead band under the minimized chip where scrolling chips are melted out
    /// for no reason.
    private var headTrailingEdge: CGFloat {
        // **On the phone the "head" is the AGENT BAR, which is not this view
        // at all (§591).** It stands on `RootShell`'s layer in the dock's
        // leading seat, and this strip runs the FULL width underneath it — so
        // the melt is measured from where that bar ends (`DSDock.agentSeat`),
        // exactly as it used to be measured from where the pinned "All" ended.
        // Chips dissolve as they slide under the bar and are gone before its
        // edge, which is the 2026-07-19 ruling ("disappear into it, not into
        // a hard line") kept for a head that changed layers.
        //
        // The first cut instead PADDED this whole strip by the seat, so the
        // scroll view began beside the bar — and its clip edge drew as a flat
        // vertical line against the bar's round glass, with chips cut off
        // rather than melted (user: "it isn't hitting a flat hard line when it
        // goes behind the octopus. the octopus should be on the same row").
        // The RAIL still pins "All" and still measures past it.
        // `agentSeat` is measured from the WINDOW's edge and this is the
        // SCROLL VIEWPORT's space, which since §591d starts one `slabInset` in
        // — the chips scroll inside the glass bar rather than across the whole
        // screen. Without the subtraction every chip rests 15pt further right
        // than it should and the melt begins 15pt late.
        axis == .vertical ? DS.Space.s4 + chipSize
                          : DSDock.agentSeat - DSDock.slabInset
    }
    /// Where a chip has finished dissolving — fully gone by here.
    ///
    /// **On the phone this is measured so the RAMP happens UNDER the bar
    /// (§591d).** It was `headTrailingEdge - 8`, which put the fully-gone point
    /// 8pt inside the head and therefore the fully-OPAQUE point a whole
    /// `fadeRamp` beyond it — and since §591 made `headTrailingEdge` the agent
    /// bar's seat, that ramp became 24pt of empty air between the bar and the
    /// first chip. Measured on the simulator: a 34pt hole where chip-to-chip is
    /// 10, so the bar read as stranded off the end of its own row (user: "the
    /// octopus is falling off the dock").
    ///
    /// Subtracting the ramp instead puts the fully-gone point BEHIND the bar,
    /// so a chip is solid the instant it clears the bar's trailing edge and
    /// dissolves only while it is actually passing underneath — which is what
    /// the 2026-07-19 ruling asks for ("disappear into it, not into a hard
    /// line") and what the air was mistakenly paying for.
    private var fadeClear: CGFloat {
        axis == .vertical ? headTrailingEdge - 8 : headTrailingEdge - Self.fadeRamp
    }
    private static let fadeRamp: CGFloat = 24
    private var stripInset: CGFloat { fadeClear + Self.fadeRamp }
    /// The air between the pinned head's TRAILING edge and the first chip at
    /// rest. `stripInset` is the same resting position measured from the
    /// viewport's leading edge, which is what the strip needed while it began
    /// at x=0 and ran beneath an overlay; the head occupies real layout space
    /// now, so the padding that buys that position is the difference. Derived
    /// rather than spelled as a literal 16, so it stays correct if `fadeRamp`
    /// or the head's own metrics move.
    private var contentLead: CGFloat {
        // On the phone nothing in this view occupies the head's space any more
        // (§591) — the bar is on another layer — so the resting position is
        // the absolute `stripInset` from the viewport's own edge, as it was
        // when the strip ran beneath an overlay. The rail's head is real
        // layout, so the rail keeps the relative form.
        axis == .vertical ? stripInset - headTrailingEdge : stripInset
    }

    var body: some View {
        switch axis {
        case .horizontal: horizontalStrip
        case .vertical:   verticalRail
        }
    }

    /// The iPad rail. The two fixed doors sit at the HEAD, outside the scroll,
    /// exactly as they do horizontally — but there is no leading-fade mask
    /// here, because a rail has vertical room to spare and never has to run
    /// its chips underneath the doors to earn it. Chips below scroll on their
    /// own when a corpus grows past the rail's height.
    private var verticalRail: some View {
        VStack(spacing: Self.iconGap) {
            headDoors(.vertical)
            // Pinned here too, and for the same reason as on the phone — the
            // rail scrolls once a corpus outgrows its height, and `scrollTo`
            // below actively pushes "All" off the top whenever a chip further
            // down is active. One grammar on both axes.
            chip("All", pinned: true)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DS.Space.s1) {
                        ForEach(scrollingLabels, id: \.self) { label in
                            chip(label)
                        }
                    }
                    .padding(.vertical, DS.Space.s2)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onAppear {
                    if active != "All" { proxy.scrollTo(active, anchor: .center) }
                }
                .onChange(of: active) { _, now in
                    // "All" is not in this scroll any more, so asking for it is
                    // a silent no-op rather than a scroll — say so, rather than
                    // leaving a call that only looks like it does something.
                    guard now != "All" else { return }
                    withAnimation(DS.Motion.standard) { proxy.scrollTo(now, anchor: .center) }
                }
            }
        }
        .padding(.top, DS.Space.s2)
        .frame(width: PadLayout.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The horizontal strip. **The active word chip's fill is NOT built here —
    /// it lives in `WordChipFill`, per chip, and that file's own note is the
    /// authority on why** (prd §359).
    ///
    /// This doc used to describe a different implementation entirely: one
    /// capsule hoisted to the row, adopting whichever chip owned `id: active`
    /// via `matchedGeometryEffect(isSource: false)`, on the reasoning that a
    /// blob must be ONE piece of glass changing size rather than one handing off
    /// to another. **That cut was built, measured against the per-chip version
    /// at 60fps, and LOST — it teleported, because positioning the hoisted fill
    /// from an `anchorPreference` resolves on a later pass than the tap's own
    /// transaction.** It was reverted; the prose was not (2026-08-11).
    ///
    /// Corrected rather than deleted because of how it failed, which is the part
    /// worth keeping: it did not merely go stale, it read as instructions.
    /// It opened "why the earlier cuts could not have worked, stated plainly so
    /// nobody rebuilds them" and then described the per-chip background — the
    /// version that actually ships, right here, and won on measurement. Anyone
    /// following it would have deleted the working fill as an earlier cut, using
    /// this file's own words as the warrant. A doc that is merely out of date
    /// costs a reader a minute; one that confidently forbids the shipped design
    /// costs the next session the whole afternoon that chose it.
    ///
    /// The design argument in it was real and is preserved in `WordChipFill`,
    /// where it belongs — as a record of what was tried, not a claim about what
    /// runs.
    private var horizontalStrip: some View {
        // Captured as plain values for the per-chip melt below: `visualEffect`
        // takes an escaping closure, and handing it two `CGFloat`s keeps `self`
        // (and the whole View graph behind it) out of the capture.
        let clear = fadeClear
        let ramp = Self.fadeRamp
        // ScrollViewReader keeps the ACTIVE chip visible — a deep link
        // (casberi://feed/source/Zerion) can select a chip past the fold,
        // and a filter you can't see reads as no filter at all.
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // **THE HEAD IS INSIDE THE SCROLL (2026-08-24, user: "with the
                // all chip pinned, it's really hard to scroll through the other
                // categories").**
                //
                // It used to be a `ZStack` layer sitting ON TOP of this scroll,
                // and that is what made the strip hard to move: a `ScrollView`
                // only pans when the touch that starts the drag lands on the
                // scroll view itself, so every swipe beginning on the avatar,
                // the catalogue door or "All" — ~148pt of button at the LEADING
                // edge, which is exactly where a finger starts a swipe back
                // toward the earlier chips — hit a fixed layer and did nothing.
                // Scrolling FORWARD worked (you start on the right, over real
                // chips) and scrolling BACK did not, which is precisely the
                // asymmetry the report describes.
                //
                // A pinned section header is the same picture with the touch
                // problem gone: the head still never moves and never leaves the
                // screen — that was 2026-08-16's whole point and the two doors'
                // point since 2026-07-17, and nothing here weakens it — but it
                // now belongs to the scroll view, so a drag starting on it pans
                // like a drag starting anywhere else. A tap still taps: SwiftUI
                // cancels a button press that turns into a drag, which is the
                // ordinary button-inside-a-list behaviour and NOT the custom
                // recognizer arbitration this codebase has been burned by
                // (`BoardDragDriver`, the catalogue door's own three reports).
                //
                // `pinnedViews` requires a LAZY stack. Laziness buys nothing at
                // this scale — the fold caps the strip at eleven categories —
                // but it costs nothing either, and `scrollTo` below still
                // resolves because `ForEach`'s ids are known whether or not the
                // chip is realized.
                // **NO `Section`, NO `pinnedViews` SINCE §591.** Both existed for
                // exactly one thing: pinning "All" so it never scrolled away
                // while still belonging to the scroll view, which is what made
                // a drag starting on it pan like a drag starting anywhere else.
                // "All" scrolls now (see `scrollingLabels`) and the fixed
                // leading seat belongs to the agent, which is a view on another
                // layer entirely — so there is no header left to pin.
                //
                // **Keeping the empty `Section` was tried first and SHIPPED THE
                // STRIP AT ZERO HEIGHT.** A `Section` whose header draws
                // nothing still asks the lazy stack to lay out a pinned header,
                // and the `.fixedSize(vertical: true)` below — which exists to
                // force this subtree back to its own ideal height, see its own
                // note — then resolved that ideal to approximately nothing. The
                // band reserved a few points, the chips were never on screen at
                // all, and the app looked exactly like one whose source strip
                // had been deleted. Caught on the simulator, not by the build:
                // every static check was green.
                //
                // A plain `HStack` rather than a lazy one, for the reason the
                // laziness was only ever tolerated: `pinnedViews` REQUIRED a
                // lazy stack, and laziness buys nothing at this scale since the
                // fold caps the strip at eleven categories. Without the pin the
                // requirement is gone, and an eager stack is one fewer thing
                // between `scrollTo` and a chip that has to be realized to be
                // scrolled to.
                HStack(spacing: 0) {
                        // The active chip's fill is a real glass element that MORPHS
                        // from the old chip to the new (prd §359, user: "if the
                        // category chips and the source chips are controls why not
                        // use liquid glass for the transitions and active states").
                        // That morph is a property of the CONTAINER — a
                        // `glassEffectID` outside one is inert — so the row it
                        // travels along is the container, and it is the row rather
                        // than the whole strip because the fixed doors are a
                        // separate glass object that must never blend into a chip
                        // sliding under them.
                        DSGlassContainer(spacing: Self.chipGap) {
                            HStack(spacing: Self.chipGap) {
                                ForEach(scrollingLabels, id: \.self) { label in
                                    chip(label)
                                        // THE MELT, PER CHIP. The old
                                        // `.mask(leadingFade)` hung on the whole
                                        // ScrollView, which worked only while the
                                        // head was a separate layer above it —
                                        // with the head inside, that mask would
                                        // dissolve the head itself, i.e. erase the
                                        // very thing it exists to protect.
                                        //
                                        // Same geometry, read per chip instead of
                                        // painted once across the row: a chip is
                                        // solid until its leading edge reaches
                                        // `stripInset`, then ramps to nothing over
                                        // `fadeRamp`, and is fully gone 8pt before
                                        // it would show through the head's glass.
                                        // `.scrollView` is the VIEWPORT's space,
                                        // so `minX` is distance from the strip's
                                        // left edge and the head's own width is
                                        // what `clear` is measured from.
                                        //
                                        // The one honest difference: the mask
                                        // wiped a gradient ACROSS each chip, this
                                        // fades each chip whole. The 2026-07-19
                                        // ruling it answers to is "disappear into
                                        // it, not into a hard line on the source
                                        // chips" — no hard line either way, and
                                        // the dissolve still happens over the same
                                        // 24pt. Worth a look on a device.
                                        .visualEffect { content, proxy in
                                            let x = proxy.frame(in: .scrollView).minX
                                            return content.opacity(
                                                Double(min(max((x - clear) / ramp, 0), 1)))
                                        }
                                }
                            }
                        }
                        // The air between the head and the first chip at rest —
                        // what `stripInset` bought when the strip started at the
                        // viewport's edge and ran underneath an overlay. The head
                        // occupies real layout space now, so the same resting
                        // position is expressed relative to it.
                        .padding(.leading, contentLead)
                        .padding(.trailing, DS.Space.s4)
                }
                // **PINNED SECTION HEADERS UNDID THE STRIP'S OWN HEIGHT
                // (found 2026-08-24, hours after `LazyHStack`+`pinnedViews`
                // landed above).** `MainSurface.topInset` measures this
                // strip's NATURAL height through a sibling `GeometryReader`
                // (`BandHeightKey`) so the feed's `.safeAreaInset` can reserve
                // exactly that much air and no more. A `LazyHStack` carrying a
                // pinned `Section` header reports back something close to the
                // full PROPOSED height rather than its own rendered height —
                // measured live at up to 778pt on an ~874pt device, i.e. the
                // reservation ate the whole screen and the real feed rendered
                // one row peeking in at the very bottom edge, unscrollable
                // (the reservation, not the content, is what was frozen).
                // `.fixedSize(vertical: true)` forces this subtree back to its
                // own IDEAL height before `GeometryReader` ever sees it — the
                // standard fix for a Lazy stack lying to an outer measurement,
                // and cheap here since the strip's ideal height is a single
                // row regardless of how many chips it holds.
                .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear {
                // Unconditional since §591: "All" is in this run now, so a
                // strip restored on All must scroll to it like any other room.
                // It leads the order, so this is usually a no-op — but only
                // usually, and a selection you cannot see reads as no
                // selection at all.
                proxy.scrollTo(active, anchor: .center)
            }
            // **A chip you TAPPED is not re-centred (prd §359, 2026-08-11).**
            // This used to re-centre on every change, which quietly defeated
            // the travelling selection above it: the active chip was pulled
            // to the middle, so the fill never moved in SCREEN space and the
            // chips slid under it instead — measured at 6px of centroid
            // travel across a whole switch, which is why the glass morph
            // "doesn't look like a blob" no matter what material it is made
            // of. Skipping the scroll for a direct tap gives the morph the
            // whole distance between two chips to happen in.
            //
            // Every OTHER route still re-centres, and that is the rule this
            // preserves rather than an exception to it: a deep link
            // (casberi://feed/source/Zerion), a swipe step, or a restored
            // filter can name a chip past the fold, and a selection you
            // cannot see reads as no selection at all. A tap is the one case
            // where the chip is provably already on screen — your finger was
            // just on it.
            .onChange(of: active) { _, now in
                if tapped == now { tapped = nil; return }
                // The `guard now != "All"` that stood here is GONE (§591): it
                // was correct while "All" was pinned outside this scroll and
                // had no id to reach, and it is now the bug it was preventing
                // — going home by any route but a tap (a deep link, a swipe
                // step, the panel's All capsule) would leave the strip parked
                // wherever it was, with the lit chip off screen.
                withAnimation(DS.Motion.standard) { proxy.scrollTo(now, anchor: .center) }
            }
        }
    }
    // `head` was DELETED in §591 along with the `Section` that pinned it. It
    // drew "All" in the strip's fixed head; "All" scrolls now, and the fixed
    // leading seat belongs to the agent bar, which `MainSurface` reserves with
    // `DSDock.agentSeat` and `RootShell` stands in. There is nothing left for a
    // header to hold.

    /// The two fixed doors as ONE glass capsule (2026-08-06) — see
    /// `dsGlassDoor` for why they are one object.
    ///
    /// The container is required for the union to merge at all, and its spacing
    /// is 0 ON PURPOSE for the same reason the shell's bottom cluster passes 0:
    /// a non-zero spacing lets ANY two shapes inside bridge by proximity, which
    /// is a merge decided by a layout constant instead of by intent. The union
    /// says which pair fuses; the spacing says none fuse by accident.
    ///
    /// **RAIL-ONLY since 2026-08-24** — the phone strip no longer draws these
    /// (see `head`; they live in `SourcesOverlay`'s header now). The `.horizontal`
    /// arm is kept rather than deleted because the rail and the strip are ONE view
    /// with an `axis`, and a function that answers for only one axis is the shape
    /// that drifted when Home and Feed were two screens; it costs a switch case.
    ///
    /// The iPad keeps them for a spatial reason, not a nostalgic one: the rail has
    /// vertical room to spare — the same reason its own doc gives for having no
    /// fade mask — so the doors cost it nothing, and the tray is a phone surface
    /// (`SourcesOverlay` is explicit that a panel pinned to the bottom edge is a
    /// statement about a phone). Removing them there would strand Settings.
    @ViewBuilder
    private func headDoors(_ axis: Axis) -> some View {
        DSGlassContainer(spacing: 0) {
            switch axis {
            case .horizontal:
                HStack(spacing: Self.iconGap) {
                    avatarChip
                    catalogueChip
                }
            case .vertical:
                VStack(spacing: Self.iconGap) {
                    avatarChip
                    catalogueChip
                }
            }
        }
    }

    /// The avatar door — Settings. Stories-style: your own face leads the
    /// strip (2026-07-20), the same "add a source"-adjacent fixed placement
    /// the catalogue door already had. `AvatarChip` (`TopDoors.swift`) owns
    /// the actual door/bounce/spin — this just wires this screen's params.
    @ViewBuilder private var avatarChip: some View {
        AvatarChip(onSettings: onSettings, refreshSpin: refreshSpin,
                   pullTension: chrome.pullTension, zoomNS: zoomNS,
                   doorUnion: doorsUnion)
    }

    // `leadingFade` lived here and is DELETED (2026-08-24). It was the strip's
    // row-wide dissolve — transparent where the fixed head sat, a soft ramp back
    // to opaque just past it — hung on the ScrollView as a `.mask`. That worked
    // only while the head was a layer ABOVE the scroll; once the head moved
    // inside as a pinned header (see `horizontalStrip`), masking the ScrollView
    // would dissolve the head along with the chips. The same geometry is read
    // per chip now, off `fadeClear`/`fadeRamp`, which both halves still share.

    /// The app-catalogue door — the same `AppsDoor` grid glyph (and its
    /// attention state) it wore in the top-right, now the strip's first chip in
    /// the neutral circle Pinned/All share. The store still zooms out of it.
    @ViewBuilder private var catalogueChip: some View {
        Button {
            // A REAL action again (2026-07-26), not the no-op the
            // highPriorityGesture below was given sole ownership of: whichever
            // recognizer wins the press, the door opens. `openApps()`
            // coalesces, so the belt and the braces can never both fire.
            openApps()
        } label: {
            ZStack {
                if let zoomNS {
                    AppsDoor().matchedTransitionSource(id: "appsDoor", in: zoomNS)
                } else {
                    AppsDoor()
                }
            }
            .frame(width: 46, height: 46)
            // Glass on the NEUTRAL chips only (2026-07-20): this strip is
            // pinned chrome the feed scrolls under, so the doors and the "All"
            // chip wear the floating material. A source chip keeps its own app
            // icon — an icon IS content, and frosting one would only muddy a
            // mark the person recognizes.
            //
            // Joined to the avatar door beside it as one shape (2026-08-06) —
            // the sentence above finally true of both doors, not just this one.
            .dsGlassDoor(doorsUnion)
            // THE DOOR IS THE CIRCLE, not the glyph inside it (user, "you
            // press it and it doesn't respond, have to press it several
            // times", 2026-07-26 — the third report on this button). A
            // `.frame()` does not make its empty space hit-testable: the only
            // rendered content in here is a 21pt SF Symbol, so the press had
            // to land in roughly a 24×21pt box in the middle of a 46pt circle
            // that looks tappable everywhere. Near-center taps worked,
            // everything else fell through to the feed — which reads exactly
            // like a flaky button. A source chip never had this because
            // `BridgeIcon` fills its whole 46pt with a real image. Gesture
            // hit-testing reads the same shape, which is why last round's
            // `highPriorityGesture` couldn't fix it: the region was the bug,
            // not the arbitration.
            .contentShape(Circle())
            .dsHover()
        }
        .buttonStyle(.plain)
        // The door's glyph fills, colors and pulses when a bridge breaks —
        // all three cues are visual, so the label has to say it too.
        .accessibilityLabel(bridges.attentionCount > 0
                            ? Text("Apps, needs attention")
                            : Text("Apps"))
        .dsTooltip(bridges.attentionCount > 0
                   ? String(localized: "Apps, needs attention")
                   : String(localized: "Apps"))
        // This strip rides `.safeAreaInset(edge: .top)` on the paged feed
        // TabView (`MainSurface`) — a plain Button's own tap gesture there
        // competes with the TabView(.page)'s internal pan recognizer for the
        // first touch (Apple's documented safeAreaInset-button bug, forums
        // thread 725366) and can take several presses to win the
        // arbitration (reported 2026-07-24: "requires pressing several
        // times before opening"). `highPriorityGesture` wins immediately.
        // Kept as the belt beside the Button's own braces above — it was
        // never the whole story, but it costs nothing to keep winning.
        .highPriorityGesture(TapGesture().onEnded { openApps() })
    }

    /// One entry point for the door's two possible tap deliveries (the
    /// Button's action and the high-priority tap). `highPriorityGesture`
    /// failing the Button's own gesture is the documented behaviour, so in
    /// practice only one arrives — the 0.4s coalesce is what makes relying on
    /// that unnecessary, and keeps a double haptic impossible either way.
    private func openApps() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastAppsOpen > 0.4 else { return }
        lastAppsOpen = now
        DSHaptic.selection()
        onApps()
    }

    /// A folded category chip: its word at full size, in a capsule that grows
    /// to hold it.
    ///
    /// **A WORD ONLY — no brand mark rides in here (user ruling 2026-08-11).**
    /// The capsule briefly carried the landing seat's own logo ahead of the
    /// word, to answer a question the fold created: a category chip opens on
    /// its last-visited member (`CategoryFold.landing`), so tapping "Work"
    /// reaches GitHub or Stripe depending on state held in `UserDefaults` and
    /// drawn nowhere. In practice the strip read worse, not better — "honestly
    /// i think it just looks confusing for those logos to be in the category
    /// chips" — because a mark drawn only where it says something (a category
    /// with ≥2 present members, phone only) appears on some chips and not
    /// others, so the row loses the one grammar that made the fold legible:
    /// every source-bearing chip is a word.
    ///
    /// Nor does any single category get one as an exception (offered for
    /// Wallet, declined the same day): a lone marked chip in a row of words
    /// rebuilds exactly the inconsistency above, and the wallet glyph is
    /// ambiguous in a second way — it is also Apple Wallet's own seat mark, so
    /// it would read as that one app rather than the category. The colour the
    /// fold took back is a real cost, and the answer to it is somewhere other
    /// than the chips.
    /// **The word is TINT, not ink (user ruling 2026-08-11: "should we make the
    /// words in the category chips be blue? so they stand out… they are for
    /// navigation").** Tinted text is how iOS says "this is a control" — and
    /// with the fold, these words ARE the app's navigation, sitting in a strip
    /// that otherwise reads as content-coloured glass. `DS.tint` rather than a
    /// hardcoded blue for two reasons the design system states outright: it is
    /// the ONE accent (brief §8 principle 2) and it is routed through
    /// `ThemeStore`, so a tint swap carries the chips with it; and it is the
    /// only colour token that carries the Increase Contrast guarantee, which
    /// matters here precisely because this is a WORD and not a fill (the
    /// shipped blue measures 3.8:1 on the light well — fine for a fill, thin
    /// for a word — and steps to a measured ≥4.5:1 pair under that setting).
    ///
    /// **Selection is the FILL, at full strength with white text** (user,
    /// 2026-08-11: "why not make the active ring white?"). A white ring was the
    /// instinct and it cannot work in both themes — the ring straddles the chip's
    /// edge, so on the light page half of it lands on near-white and vanishes; it
    /// would be a cue that exists only in dark mode. What the question is really
    /// asking for is a stronger active state, and the fill is where to spend it:
    /// a solid accent on ONE chip is the accent doing its job, where a solid
    /// accent on all six was the objection that kept them dim in the first place.
    /// This is also the user's original ask ("blue with white text") applied
    /// where it is earned rather than everywhere.
    ///
    /// The ring STAYS, and is not redundant: it is the only active mark the
    /// strip's logo chips have (a brand mark can't take a tint fill without
    /// becoming unrecognisable), so removing it would leave a source chip with no
    /// selected state at all. On a word chip it now reads as an outline around an
    /// already-obvious fill, which is belt-and-braces rather than a second claim.
    ///
    /// Both fills ride ONE `matchedGeometryEffect`, so the strong fill TRAVELS
    /// from the old chip to the new exactly as the ring does — the 2026-07-14
    /// ruling ("selection is an object traveling, not two states blinking")
    /// applied to the cue that now carries the most weight.
    ///
    /// **A FILLED chip, not a tinted word on glass (user ruling 2026-08-11:
    /// "these being white really fade into the background", "they just don't
    /// even seem like buttons they seem like they are text inside to read",
    /// "they don't look separate").** The first cut of §355's tint ruling put
    /// blue words on `dsGlass`, and on the light theme's page that glass is
    /// within a few percent of the background it sits on — so the container did
    /// no work and what was left was floating words. Tinting the WORD says
    /// "this is a control" only if something already reads as a control to
    /// begin with; it cannot manufacture the affordance on its own.
    ///
    /// `DS.tintDim` (tint at 0.16 — the token's own documented job, "tint at
    /// rest-chip opacity") with INK text, which is the grammar
    /// `CategoryVenueSwitcher` already uses one tier down, chosen over a solid
    /// tint with white text for three reasons. A solid fill is the loudest
    /// statement this system can make and five or six of them held permanently
    /// at the top of every screen makes the one accent (brief §8 principle 2)
    /// stop pointing at anything. It would also erase selection: the active
    /// chip is named by a full-strength tint ring, which is invisible on a
    /// full-strength tint fill, whereas a 2.5pt solid ring over a 16% wash is
    /// plainly readable. And white-on-tint carries no contrast guarantee once
    /// `ThemeStore` swaps the accent, while ink-on-wash holds at every tint.
    ///
    /// The two tiers wearing one fill is deliberate rather than a collision:
    /// they never appear as peers (the strip floats on the page in circles and
    /// capsules under a ring system; the switcher is pills inside a glass bar),
    /// and a category chip and the room pill under it are the same spine —
    /// looking related is correct.
    @ViewBuilder
    private func categoryCapsule(_ label: String) -> some View {
        let isOn = label == active
        Text(label)
            .dsText(.label12)
            .fontWeight(.semibold)
            // `.white`, not `DS.textPrimary`: this sits on the accent, which is
            // a dark blue in BOTH themes — the same blue the composer's lede
            // card wears (one token, `DS.tint`, user 2026-08-16: "make them
            // same color as the blue we now use in the composer").
            .foregroundStyle(isOn ? .white : DS.textPrimary)
            .lineLimit(1)
            // Nothing to scale on the phone: the capsule is what gives, so
            // the word keeps its size all the way up the Dynamic Type ramp
            // and the strip simply scrolls further. On the rail the width
            // is fixed, so the word gives instead — the same trade "All"
            // makes inside its circle, and the reason this floor is 0.6
            // rather than the 0.55 that produced the sizes this pass is
            // fixing: here it applies to a 68pt box, not a 46pt circle.
            .minimumScaleFactor(axis == .vertical ? 0.6 : 1)
            .padding(.horizontal, capsulePadH)
            .frame(width: axis == .vertical ? Self.railChipWidth : nil, height: iconSize)
            .wordChipFill(cornerRadius: iconSize / 2, active: isOn, ns: selectionNS)
    }

    /// Everything the strip SCROLLS.
    ///
    /// **"All" SCROLLS on the phone since §591, and the reason is a budget.**
    /// The dock's fixed leading seat belongs to the agent now, and a phone
    /// strip cannot afford two fixed chips: measured, the head cost 112pt with
    /// the agent beside a pinned "All" against 56pt with the agent alone —
    /// which is one whole extra source visible at rest on a 393pt screen.
    /// The user's own framing (2026-09-03): *"if all and the agent button are
    /// fixed, then there is less room to scroll. we could make all scroll too
    /// that way only the agent button is fixed."*
    ///
    /// **What that costs, and what pays it back.** The 2026-08-16 ruling that
    /// pinned it said "All" is the way back to the whole feed, the one
    /// destination every other room needs a road to — and a road that can
    /// scroll off is a road you have to look for. Two things keep it: it still
    /// leads the order by construction, so it is the first thing the run shows
    /// and one flick away from anywhere in it; and the agent's own panel
    /// carries an All capsule in its header (§407), which is now the ALWAYS
    /// -present door, reachable in one tap from every room and from every
    /// pushed screen the strip does not survive into.
    ///
    /// The RAIL is untouched and still pins it (see the vertical branch): a
    /// rail has vertical room to spare, which is the same reason its own doc
    /// gives for having no fade mask, so it pays no budget for the pin.
    ///
    /// A FILTER, not a `dropFirst()`: `labels` is handed in by the owner and
    /// "All" leads it by construction today (`MainSurface.computedChips`), but
    /// an order that ever put it elsewhere would silently render it twice on
    /// the rail, and two chips claiming one selection is worse than either
    /// placement.
    private var scrollingLabels: [String] {
        axis == .vertical ? labels.filter { $0 != "All" } : labels
    }

    /// - Parameter pinned: this chip is drawn in the fixed head rather than in
    ///   the scroll, so it sits out the scroll-edge ease. Everything else about
    ///   it — the fill, the rings, the peek, the accessibility, the frame it
    ///   reports for the capture flight — is identical, which is the point of
    ///   pinning by re-using this function instead of writing a second chip.
    @ViewBuilder
    private func chip(_ label: String, pinned: Bool = false) -> some View {
        let isActive = label == active
        // Through the catalog, not against the label: see `SourcesTray.cell`.
        // The strip and the tray it opens must agree about which seats are in
        // trouble, so this line and that one stay identical.
        let seat = BridgeCatalog.offer(forSource: label)?.name ?? label
        let isCategory = CategoryFold.isCategory(label)
        /// The chips that are WORDS rather than marks — the categories and
        /// "All". `wordChipFill` and the flip both key off this, so the two can
        /// never disagree about which chips are words.
        let isWord = isCategory || label == "All"
        let venues = categoryVenues[label] ?? []
        // A folded CATEGORY chip answers for every seat behind it (prd §351,
        // generalizing the Markets-only reasoning this line used to carry):
        // with the members' own circles gone, a broken seat would otherwise
        // have no ring anywhere in the strip and the connection could sit dead
        // with nothing on any surface to say so. The DASHED attention ring is
        // exactly as legible on a category word as on a brand mark, and the
        // Sources Tray (or, for Markets, its own switcher) is one tap from
        // naming which seat it is.
        let attentionSeats: Set<String> = isCategory ? Set(venues) : [seat]
        let broken = bridges.bridges.contains {
            attentionSeats.contains($0.name) && $0.status == .attention
        }
        Button {
            DSHaptic.selection()
            // Marks this change as finger-initiated so the strip does not
            // re-centre under it — see the horizontal strip's `onChange`.
            tapped = label
            withAnimation(DS.Motion.standard) { onTap(label) }
        } label: {
            ZStack {
                switch label {
                case "All":
                    // The one WORD in a strip of fixed 46pt icon chips, so it
                    // has to live inside that circle at every text size —
                    // at accessibility sizes it grew past the glass and
                    // collided with the catalogue door beside it (measured at
                    // accessibility-extra-large, 2026-07-21). It still scales;
                    // it just stops at the circle instead of spilling over the
                    // door. The neighbouring chips are app icons, which don't
                    // scale at all, so the strip's rhythm is fixed by design.
                    // Tint, with the category words beside it (2026-08-11):
                    // "All" is a navigation word in a strip of navigation
                    // words, and leaving it ink while every other word went
                    // tint would read as one chip singled out for no reason.
                    // Its circle-not-capsule shape is the documented exception
                    // above; its COLOUR is not one.
                    // Semibold with the category words, never apart from them —
                    // see `categoryCapsule`. These two are the strip's only
                    // words, so a weight on one alone makes the other read as
                    // an inert label rather than a door.
                    Text("All").dsText(.label12)
                        .fontWeight(.semibold)
                        // The same ink rule as `categoryCapsule` — one
                        // convention across the strip's two word shapes.
                        .foregroundStyle(isActive ? .white : DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(Circle())
                        .wordChipFill(cornerRadius: iconSize / 2,
                                      active: isActive, ns: selectionNS)
                case Pinboard.room:
                    // The pinned room (2026-08-10) — see `PinnedChipMark`.
                    PinnedChipMark(size: iconSize)
                default:
                    // A category chip is a WORD, not a mark (prd §351,
                    // 2026-08-11, overturning the icon-only ruling of
                    // 2026-07-09/07-10 for exactly this case): every
                    // source-bearing chip is now a category, and a category
                    // has no brand to wear — Markets' own generic glyph,
                    // shipped hours earlier the same day, is retired by this
                    // same change rather than kept as a second synthetic-label
                    // treatment.
                    //
                    // It wears a CAPSULE, not "All"'s circle (design pass, see
                    // the type doc): the first cut inset the text's own box
                    // inside the circle to stop long names touching the curve
                    // ("hug the edges too much", 2026-08-11), which fixed the
                    // margin and made the real problem worse — the more room
                    // the inset took, the smaller `minimumScaleFactor` drove
                    // the glyphs, and the further the longest names drifted
                    // from the shortest. A container that grows has neither
                    // problem and needs neither knob.
                    if isCategory {
                        categoryCapsule(label)
                    } else {
                        // Reachable only for a label the catalog has never
                        // heard of (an uncategorized source) — every real
                        // catalog offer resolves to one of the ten categories,
                        // so this is a defensive fallback, not the common path
                        // it used to be.
                        BridgeIcon(name: label, size: iconSize, circular: true)
                    }
                }
            }
            // A capsule takes its width from its own word (or, on the rail,
            // from the rail) — height alone is shared with the circles.
            .frame(width: isCategory ? nil : iconSize, height: iconSize)
            // The identity flip (2026-07-14, user): the chip is where
            // switching sources actually happens, so it's the one true flip
            // moment — the Feed source header dropped its own animated icon
            // in favor of this one, rather than two competing for the same
            // delight. Keyed to isActive: the chip you're leaving flips away,
            // the one you're landing on flips in. A first-ever thing from
            // this source flips it too (the bloom's beat, same vocabulary).
            //
            // **WORD chips do not flip (user ruling 2026-08-11, §359: "on the
            // category chips — remove the flipping").** The flip is an IDENTITY
            // moment and identity is what a brand mark has: rotating a logo
            // reads as the mark turning to face you, while rotating the word
            // "Markets" is just text spinning, which is a different and much
            // cheaper effect wearing the same motion. It also collided with the
            // cue §358 had just made the primary one — the strong tint fill
            // TRAVELS between word chips, so the arriving chip was flipping
            // while the selection was sliding onto it, two animations claiming
            // the same beat. Applied to "All" as well as the categories,
            // because those two are the strip's only words and §358's own
            // finding was that treating one and not the other makes the odd one
            // out read as inert.
            .coinFlip(trigger: "\(isActive)-\(chrome.bloomTicks[label] ?? 0)",
                      enabled: !isWord)
            // The catch bob — a thing landing from this source while the
            // person watches bumps its chip once, the flight's landing
            // generalized to bridge arrivals (delight 2026-07-13).
            .modifier(ChipCatchBob(label: label,
                                   arrivedChip: chrome.arrivedChip,
                                   tick: chrome.arrivedTick,
                                   reduceMotion: reduceMotion))
            .padding(2.5)
            .overlay {
                // One ring, two exclusive states: tint = active (a single ring
                // that SLIDES from the old chip to the new — selection is an
                // object traveling, not two states blinking); orange = the
                // connection needs you (health lives where you live).
                // `Capsule(style: .circular)` for BOTH shapes, not `Circle()`
                // (2026-08-11): with a circular corner style a capsule in a
                // square frame is exactly a circle, so every circle chip is
                // pixel-identical to what it was, while the one ring that
                // SLIDES between chips can now travel between a circle and a
                // capsule as a single morphing shape. Two shapes would have
                // meant the ring swapping form mid-flight, which is the
                // blinking this ring exists to avoid.
                // **A WORD chip has no active ring (user ruling 2026-08-11,
                // §359: "we don't even need that active ring b/c the color
                // changes when you are in an active pill. that ring is getting
                // in the way sort of").** §358 gave the active word chip a solid
                // tint fill and white text, and once selection is stated that
                // loudly a ring is a second claim about the same fact. It was
                // also actively in the way, which the recorded transition shows
                // rather than implies: the ring travels on its own
                // `matchedGeometryEffect`, so mid-move it is a detached blue
                // circle sitting ON TOP of the neighbouring chip — the one
                // element on the strip that belongs to no chip at all.
                //
                // It stays for MARK chips, and that is the user's own reasoning
                // applied where it holds: the pinned room and any uncategorized
                // source draw a brand mark, which cannot take a tint fill
                // without becoming unrecognisable — nothing about them changes
                // colour, so removing the ring there would leave them with no
                // active state whatsoever.
                // **THE ROOM YOU ARE STANDING IN, when it is not the lit chip**
                // (§591c). `isActive` is the OPEN FOLDER now, so opening Social
                // while reading Kalshi lights Social and would leave nothing at
                // all saying where the feed actually is — §357's rule, one
                // surface over. A tint ring on the standing chip says it
                // without competing with the fill: the filled chip is what you
                // selected, the ringed one is where you are.
                //
                // Drawn on WORD chips too, unlike the active ring below, and
                // that is the point: a category is a word chip, and the
                // divergence this exists for can only happen between two
                // categories. It is deliberately OUTSIDE `selectionNS` — the
                // travelling selection is one object and this is a second,
                // stationary mark, so joining the group would make them fight
                // over the same geometry.
                // **NEVER ON "All"** (user, 2026-09-04: "why does All have a blue
                // circle around it?"). §357's rule is about a FILTER you are
                // standing in — it must show you that you are in it, and show
                // its exit. "All" is the ABSENCE of a filter and is itself the
                // exit, so a ring there states nothing and does it in the most
                // common arrangement there is: standing in All, opening a
                // folder to look inside. Two blue marks, one of them saying
                // "you have not filtered anything", competing with the chip you
                // just pressed.
                if !isActive, standing != "All", !standing.isEmpty, label == standing {
                    Capsule(style: .circular)
                        .strokeBorder(DS.tint.opacity(0.55), lineWidth: 2)
                }
                if isActive, !isWord {
                    // The active ring is always tint now — the feed sits on the
                    // neutral ink page (user ruling 2026-07-18: full ink), so
                    // there's no source-hue field for a tint ring to melt into.
                    let ring = Capsule(style: .circular)
                        .strokeBorder(DS.tint, lineWidth: 2.5)
                    if reduceMotion {
                        ring
                    } else {
                        // The SAME group as the word chips' fill (prd §412b) —
                        // see `selectionNS`. Crossing between a word and a mark
                        // used to fade, because each form was the only member of
                        // its own group; now the one blue object travels the gap
                        // and resolves into a ring on arrival.
                        ring.matchedGeometryEffect(id: ChipSelection.id, in: selectionNS)
                    }
                } else if broken {
                    // DASHED, not merely orange (2026-07-21). "Selected" and
                    // "this connection is broken" were the same 2.5pt ring in
                    // two hues — indistinguishable to anyone who doesn't
                    // separate them by color. The solid ring now belongs to
                    // selection alone.
                    Capsule(style: .circular)
                        .strokeBorder(DS.attention,
                                      style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                }
            }
            .frame(width: isCategory ? nil : chipSize, height: chipSize)
            // This chip is the travelling fill's SOURCE frame (prd §359) —
            // see `travellingFill`. Word chips only: a mark chip cannot take a
            // tint fill without becoming unrecognisable, so it keeps the ring
            // instead and is never a landing site.
            // The active fill lives in this chip's background when this chip
            // is the active one — see `wordChipFill`.
            // The capture flight lands on "All" — the record that shows every
            // capture in place, the same target the old Feed tab was.
            .background {
                if label == "All" {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { chrome.feedTabFrame = g.frame(in: .global) }
                            .onChange(of: g.frame(in: .global)) { _, f in chrome.feedTabFrame = f }
                    }
                }
            }
            // Same law as the catalogue door above: the chip is its own whole
            // shape. A source chip was already whole (`BridgeIcon` fills its
            // 46pt with a real image), but "All" is a 12pt word inside a 56pt
            // frame — without this its press had to land on the letters. Same
            // `Capsule(style: .circular)` as the ring, and for the same reason
            // it is one shape rather than two: the hit region has to be the
            // chip whatever shape the chip is, and a `Circle()` inside a
            // capsule's frame would leave the ends of every category chip
            // looking pressable and not being it — the exact 2026-07-26
            // "press it several times" bug, in a new shape.
            .contentShape(Capsule(style: .circular))
            .dsHover()
        }
        .buttonStyle(.plain)
        // The long-press peek (2026-08-14, prd §384): the room's head floats
        // up without navigating. "All" sits it out — its room is the whole
        // feed, and a peek that previews everything previews nothing.
        .modifier(ChipPeekModifier(label: label, venues: venues,
                                   enabled: label != "All",
                                   onOpen: { onTap(label) }))
        // Names the mark on hover, Mac only (2026-08-01) — see `dsTooltip`.
        // Same string the accessibility label uses, so the two can't drift on
        // what a broken connection is called.
        .dsTooltip(chipAccessibilityLabel(label, broken: broken, isActive: isActive))
        // Finger-driven, never idle: chips ease down as they leave the viewport
        // edges (Stories grammar). Under Reduce Motion only the fade remains.
        // Follows `axis` so the rail's chips ease at its TOP and BOTTOM edges,
        // which is where its own viewport ends.
        .modifier(ChipScrollEase(axis: axis, enabled: !pinned,
                                 reduceMotion: reduceMotion))
        .id(label)
        .accessibilityLabel(chipAccessibilityLabel(label, broken: broken, isActive: isActive))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func chipAccessibilityLabel(_ label: String, broken: Bool, isActive: Bool) -> String {
        // A folded chip's own face is its category's word — visible — but for
        // more than one member VoiceOver is the one place that still says
        // WHICH seats are behind it, spoken rather than drawn (prd §351,
        // generalizing what was Markets-only reasoning here).
        let venues = categoryVenues[label] ?? []
        guard CategoryFold.isCategory(label), venues.count > 1 else {
            return broken ? String(localized: "\(label), needs reconnecting") : label
        }
        let joined = ListFormatter.localizedString(byJoining: venues)
        // Where the chip OPENS, spoken — the landing mark's own fact, which is
        // drawn on the phone only and is just as true on the rail. Read from
        // `CategoryFold.landing` rather than from the drawn mark for exactly
        // that reason. Not said for the chip you are already standing in,
        // where the room itself is the answer and "opens on" would be a lie
        // about a tap you have already made.
        //
        // Nor said when the landing IS the category's own name (prd §354's
        // Wallet anchor, whose category name and anchor member are the same
        // word): "Wallet, opens on Wallet" is a sentence that reads as a bug
        // to the one person who cannot see the strip to check.
        if !isActive, let opens = CategoryFold.landing(category: label, present: venues), opens != label {
            return broken
                ? String(localized: "\(label), opens on \(opens): \(joined), needs reconnecting")
                : String(localized: "\(label), opens on \(opens): \(joined)")
        }
        return broken
            ? String(localized: "\(label): \(joined), needs reconnecting")
            : String(localized: "\(label): \(joined)")
    }
}

/// The strip's scroll-edge ease, lifted out of `chip` so the PINNED "All" can
/// decline it (2026-08-16).
///
/// Not merely redundant on a chip that never scrolls: `scrollTransition` binds
/// to the nearest enclosing scroll view, and the pinned chip's nearest one is
/// whatever the shell happens to put the strip inside. A modifier that is inert
/// today and dims a fixed chip the day the strip gains an ancestor scroll is
/// exactly the kind of thing nobody connects back to this line, so the chip
/// that cannot scroll simply does not ask.
private struct ChipScrollEase: ViewModifier {
    let axis: Axis
    let enabled: Bool
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.scrollTransition(.interactive, axis: axis) { content, phase in
                content
                    .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.88)
                    .opacity(phase.isIdentity ? 1 : 0.6)
            }
        } else {
            content
        }
    }
}

/// The pinned room's chip face (2026-08-10) — a pin on the same glass circle
/// "All" wears.
///
/// **Why it needs its own case at all.** Every other chip in this strip resolves
/// through `BridgeIcon`, which looks a name up in the catalog — and the pinned
/// room is not in the catalog and never will be, because it is not a source.
/// So it fell through to the generic placeholder and shipped as an anonymous
/// grey square beside twenty real brand marks, which is exactly the one chip in
/// the row nobody could name.
///
/// **Why a glyph is right here, and why Markets' own glyph (2026-08-11,
/// `BridgeGlyph.symbol(for: "markets")`) doesn't need a case like this one.**
/// Markets resolves through the ordinary `BridgeIcon` path because it names a
/// real catalog entry — the same generic-glyph shape `default` already gives
/// "Wallet". The pinned room can't take that path at all (it isn't a source),
/// which is the actual reason it needs a bespoke case here. "All" already
/// occupies the same footing (a neutral word on glass), so the two non-source
/// rooms read as a pair rather than as one odd chip.
///
/// Drawn in the tint, unlike "All"'s ink: this is the one room whose contents
/// you chose, and the tint is what the app uses everywhere else to mean yours.
private struct PinnedChipMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "pin.fill")
            // Fixed against the circle, not the text size: the neighbouring
            // chips are app icons that don't scale at all, so a glyph that grew
            // would break the strip's rhythm — the same reason "All" stops at
            // its circle instead of spilling over the door beside it.
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(DS.tint)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .dsGlass(cornerRadius: size / 2)
    }
}

/// One catch bob: the chip springs up a touch and settles when its source
/// lands a thing while the person watches. Fires only for the arrived chip,
/// never loops, and sits out under Reduce Motion.
private struct ChipCatchBob: ViewModifier {
    let label: String
    let arrivedChip: String?
    let tick: Int
    let reduceMotion: Bool
    @State private var bob = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(bob ? 1.12 : 1)
            .onChange(of: tick) { _, _ in
                guard arrivedChip == label, !reduceMotion else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { bob = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { bob = false }
                }
            }
    }
}

/// The strip's WORD chips — "All" and every folded category capsule — wear one
/// fill, spelled once (prd §358, 2026-08-11).
///
/// **Why a fill at all.** §355 made these words tint on `dsGlass`, and on the
/// light theme that glass sits within a few percent of the page behind it, so
/// the container did no work: what shipped read as blue words lying on the
/// background rather than controls (user, seeing it rendered — "these being
/// white really fade into the background", "they just don't even seem like
/// buttons they seem like they are text inside to read"). A tinted WORD can say
/// "this is a control" only when something already reads as one; it cannot
/// manufacture the affordance by itself.
///
/// **Why `tintDim` and not a solid tint.** See `SourceChips.categoryCapsule` for
/// the full argument — briefly: a solid accent on five or six permanent chips
/// stops the one accent pointing at anything, it would hide the active chip's
/// full-strength tint ring inside a full-strength tint fill, and white-on-tint
/// loses its contrast guarantee the moment `ThemeStore` swaps the accent.
///
/// **Both themes, and they are NOT the same problem.** `themedTint` is already
/// two colours — `#1366cd` on light, `#62a1ee` on dark — so `tintDim` is a wash
/// of the tint that theme actually uses, and ink text is `DS.textPrimary`, which
/// is near-black on light and near-white on dark. Dark mode was never the broken
/// case: there `dsGlass` is a LIGHT translucent film over a dark page, so it
/// already separated, and the wash only warms it. Light mode is what this fixes.
/// The glass stays under the wash in both, so the material still blurs what
/// travels beneath the strip — this adds a coat, it does not replace one.
private struct WordChipFill: ViewModifier {
    let cornerRadius: CGFloat
    let active: Bool
    let ns: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The chip's resting wash is the GLASS's own tint rather than a flat
    /// capsule stacked under the material, so it refracts with the glass
    /// instead of sitting behind it as paint. The ACTIVE chip additionally
    /// carries the one travelling fill.
    ///
    /// **ONE shared `matchedGeometryEffect` id on a per-chip background — the
    /// canonical sliding-indicator pattern, and the thing four fancier cuts
    /// replaced without ever beating.** `glassEffectID` is inert on a shape with
    /// no `glassEffect`; a `GlassEffectContainer` has nothing to merge when the
    /// fill exists in only one chip at a time; and hoisting the fill out to the
    /// strip and positioning it from an `anchorPreference` teleported, because
    /// preferences resolve on a later pass than the tap's transaction. Recorded
    /// at 60fps and frame-stepped each time. This is the version that has a
    /// single view moving between two branches inside one animation.
    ///
    /// **The strongest argument AGAINST this version, kept because it is the one
    /// that will be made again.** A per-chip background means that at no instant
    /// does a single shape span the gap between two chips — so there is nothing
    /// for the system to stretch, and the blob everyone pictures (the iOS tab
    /// bar, Control Center) is one piece of glass CHANGING SIZE rather than one
    /// handing off to another. It is a good argument. It lost to a measurement:
    /// the hoisted single capsule it prescribes was built and frame-stepped
    /// beside this, and teleported for the `anchorPreference` reason above,
    /// while `matchedGeometryEffect` across two branches of one `if` does
    /// interpolate the frame and does cross the gap. **The reasoning predicts
    /// the wrong winner, which is exactly why it is written down here instead of
    /// being left to sound convincing again in six weeks.** If you rebuild the
    /// hoisted version, record 60fps and frame-step it before believing it.
    /// THE RESTING GLASS IS GONE (2026-08-15, user-approved mock: "when not
    /// selected not have a background") — an unselected word chip is bare
    /// gradient type on the crown, and only the ACTIVE chip carries a
    /// surface: the travelling blob, now glass-material rather than the
    /// solid tint, per the same mock. Everything the long note above
    /// records about HOW the blob travels is unchanged — one
    /// matchedGeometryEffect id on a per-chip background, measured against
    /// every fancier cut — only its paint changed.
    /// RESTORED to the blue-blob-and-glass form after a one-night experiment
    /// (2026-08-15/16). The bare-gradient-words cut — approved from a mock,
    /// built, and judged on device within the hour — lost twice: with
    /// `.ultraThinMaterial` + `dsGlassBlob` the active chip rendered as an
    /// EMPTY dark capsule (iOS 26 hoists glass above app content, so the
    /// blob sat OVER its own word), and with the words bare the user's
    /// verdict was "the blue chips worked better than these words … it's too
    /// hard to see". The tint fill + glassBlob below is the form that
    /// shipped for weeks and was never the complaint; `DS.chipGradient`
    /// stays in the token file as the experiment's record.
    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    // `.circular`, not `.continuous` (prd §412b). The ring this
                    // now hands off to has always been spelled `.circular`, on
                    // that overlay's own recorded reasoning: "with a circular
                    // corner style a capsule in a square frame is exactly a
                    // circle, so every circle chip is pixel-identical". The fill
                    // never got the same correction, so on "All" — a word in a
                    // SQUARE frame, clipped to a `Circle()` — the blob drew as a
                    // subtly flattened squircle inside a true circle, and on a
                    // category capsule its ends were squircled where the ring's
                    // were semicircular. One style across both forms is also what
                    // lets the shared group morph between them without a shape
                    // swap mid-flight.
                    let fill = Capsule(style: .circular)
                        .fill(DS.tint)
                        .dsGlassBlob()
                    if reduceMotion {
                        fill
                    } else {
                        fill.matchedGeometryEffect(id: ChipSelection.id, in: ns)
                    }
                }
            }
            // **THE RESTING CAPSULE IS NEUTRAL, THE ACTIVE ONE IS BLUE
            // (prd §572).** The glass carried `tint: DS.tint`, so every chip
            // in the strip wore a blue wash at rest and the strip was the
            // loudest tinted region on the screen with nothing happening —
            // four or five blues stacked under a sixth, the solid active one.
            // One blue per surface is what makes the active chip read.
            //
            // **THIS IS NOT THE STATE THE 2026-08-16 RULING REJECTED.** That
            // day reversed a mock whose unselected chips had NO BACKGROUND AT
            // ALL — "it's too hard to see", then "revert and make them same
            // color as the blue we now use" — and the fix for an invisible
            // chip is a chip you can see, which is what the glass capsule
            // still is. What goes is only the BLUE in it: the material, the
            // shape, the size, the words and the travelling active fill are
            // all untouched, so a resting chip is still a visible button.
            .dsGlass(cornerRadius: cornerRadius)
    }
}

/// The one matched-geometry group the strip's selection lives in (prd §412b).
///
/// A shared constant rather than two string literals in two files' worth of
/// scroll distance apart: the fill and the ring only hand off if their ids match
/// EXACTLY, and a typo would not fail the build — it would silently restore the
/// fade this fixes, which is the failure mode nobody re-checks for.
private enum ChipSelection {
    static let id = "chipSelection"
}

extension View {
    /// One fill for both word chips, so the circle and the capsule can never
    /// drift apart the way their COLOUR did before §358 (the "All" chip had to
    /// be corrected into line with the categories twice).
    func wordChipFill(cornerRadius: CGFloat, active: Bool, ns: Namespace.ID) -> some View {
        modifier(WordChipFill(cornerRadius: cornerRadius, active: active, ns: ns))
    }
}
