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
/// **A CATEGORY IS A TILE NOW — a glyph over its word (prd §662, 2026-09-09,
/// user: "with long words like 'shopping' etc, a user has to scroll further
/// to read the items and get to categories they may want").** The capsule's
/// own virtue was its cost: it grew to hold its word, so the strip's pitch
/// was set by its longest name. The tile is a fixed 56pt with the word at
/// `dockCaption10` under a 20pt SF Symbol (`CategoryFold.glyph(for:)`, each
/// chosen by the user from rendered options), so every category is one
/// width and five chips show before a scroll where three and a half did.
/// Glyph-only — the Mac dock's own grammar, the name on the scrub caption
/// — was mocked beside it and declined: it showed the same five, and the
/// word was judged owed to the reader ("we would need word for
/// accessibility"). The grammar below is therefore three shapes, not two: a
/// mark gets a circle, "All" keeps its circle as the strip's anchor, and a
/// category gets a tile. The capsule paragraph above stays as the record of
/// why the word is not inside a circle.
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
    /// The fold as a POSITION, 0…1 (2026-09-05, `ShellChrome.fold`): the rail
    /// never folds, so on the vertical axis this is a constant 0. Every size in
    /// this strip is read off `DSDock`'s fold form, so the chips and the bar
    /// beside them cannot be different sizes at any point of the travel.
    private var fold: CGFloat { axis == .horizontal ? chrome.fold : 0 }
    private var iconSize: CGFloat { DSDock.agentSize(fold: fold) }
    private var chipSize: CGFloat { DSDock.chipFrame(fold: fold) }
    /// The category TILE (prd §662, 2026-09-09): a glyph over its word in a
    /// FIXED width, the way a tab bar item is. Fixed so every category is the
    /// same width and the scroll is predictable — the capsule grew to hold its
    /// word, so "Shopping" (56pt of word plus 28pt of padding) set the pace.
    /// Measured on the phone's own numbers: the run of nine went from ~730pt
    /// to 585, and the strip shows five chips before a scroll where it showed
    /// three and a half. **52, from 56, the same evening** (user, on the
    /// simulator: "the icons are far apart from each other… make them a tiny
    /// bit closer so we can end up showing one more"): the tile IS the
    /// caption's bound — "Shopping" at `dockCaption10` is 47pt, so the longest
    /// word keeps 2.5pt of air a side and no word in the table shrinks — and
    /// at 52 with no gap the pitch is 57, which is what fits a FOURTH full
    /// tile beside "All" in the 238pt the strip has past it (65 fit 3.7).
    private static let tileWidth: CGFloat = 52
    /// A category's CELL — the tile's outer frame, derived from the strip's
    /// width (prd §662e, 2026-09-09, user: "apple app store uses five total,
    /// and for symmetry that is probably what people are used to", then "lets
    /// go with b"): FIVE items rest in the dock — the octopus, "All" and
    /// THREE tiles spread evenly across what is left, the way a tab bar's
    /// items are — and when the corpus has more than three categories the
    /// strip is laid out as three and a HALF cells, so the fourth tile peeks
    /// by half its cell and says there is more. Fewer than three spread to
    /// fill. A six-with-a-peek was mocked and did not fit this width (the
    /// tiles touched); four without a peek fitted and said nothing about the
    /// rest. Floor is `tileFloorCell` — a rail or a narrow width scrolls
    /// rather than shrinking the tile under its caption.
    private var categoryCell: CGFloat {
        guard axis == .horizontal, stripWidth > 0 else { return Self.tileFloorCell }
        let count = labels.filter(CategoryFold.isCategory).count
        guard count > 0 else { return Self.tileFloorCell }
        let cells = CGFloat(min(count, Self.restingTiles)) + (count > Self.restingTiles ? 0.5 : 0)
        // What is left past "All": the strip minus its resting inset and
        // every non-category chip laid out ahead of the tiles (All, and the
        // pinned room when present).
        let marks = CGFloat(labels.count - count)
        let available = stripWidth - stripInset - marks * (chipSize + Self.chipGap)
        return max(Self.tileFloorCell, (available / cells).rounded(.down))
    }
    /// Three tiles at rest — five items with the octopus and "All".
    private static let restingTiles = 3
    /// The narrowest cell: the tile plus its ring room, the §662d pitch.
    private static let tileFloorCell: CGFloat = 52 + 5
    /// The tile's corner — `DS.Radius.sheet`, a rounded rectangle rather than
    /// the capsule the word wore: a stadium 56 wide and 46 tall cuts the ends
    /// of the caption under its glyph.
    private static let tileRadius: CGFloat = DS.Radius.sheet
    /// The glyph, folding with the chip (46→40) so the caption keeps its seat
    /// under it at every point of the travel.
    private var glyphSize: CGFloat { DSDock.lerp(20, 16, fold) }

    /// ONE shape type for every chip, whatever the chip is (prd §662): a
    /// `RoundedRectangle` at half the height IS a circle, and at `tileRadius`
    /// it is the tile — so the fill that travels between chips, the standing
    /// ring, the attention ring and the hit region are all drawn from this
    /// call and can never disagree about a chip's outline. `outer` is the
    /// ring's frame (`chipSize`, the ring's room around the mark) rather than
    /// the mark's own, and the radius grows by the same inset so the two stay
    /// concentric.
    private func chipShape(tile: Bool, outer: Bool) -> RoundedRectangle {
        let inset = outer ? (chipSize - iconSize) / 2 : 0
        return tile
            ? RoundedRectangle(cornerRadius: Self.tileRadius + inset, style: .continuous)
            : RoundedRectangle(cornerRadius: iconSize / 2 + inset, style: .circular)
    }

    /// The gap between chips — ZERO since the tiles (prd §662/§662d); it was
    /// `s1` for an hour, `s2` for the capsules and `s3` for the circles.
    ///
    /// Every chip already carries 5pt of ring room a side (`chipSize` over
    /// `iconSize`), so the AIR between two tiles is that room alone: 10pt of
    /// slab between one tile's edge and the next, against 14 at `s1` and the
    /// 39-then-17 the bar's own seam had. Measured on the simulator, not
    /// arithmetic: a tile's pitch is 57 + 0, and the 238pt of strip past
    /// "All" shows FOUR full tiles where 65 showed three and a sliver; the
    /// capsules at their 10pt gap averaged ~81 and showed two and a half.
    private static let chipGap: CGFloat = 0

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

    // No `BridgeStore` here since prd §670 — the two leaves that need it
    // (`ChipAttentionRing`, `ChipSpokenLabel`) read it in their own bodies.
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
    /// The strip's viewport width, for `categoryCell` (prd §662e). STATE,
    /// unlike the rest of the viewport sample, because the cells are LAYOUT
    /// and must re-lay when it changes — which is a mount or a rotation,
    /// never a scroll frame: the write below is guarded on inequality.
    @State private var stripWidth: CGFloat = 0

    // MARK: - Chip frames

    /// Every chip's frame in the strip's CONTENT space, recorded as laid out.
    /// Content space, not the viewport's: these change when the strip folds
    /// or a folder opens, never when it scrolls — and since 2026-09-09 never
    /// under the wave either, which is a transform. A BOX, not state: a
    /// frame write must not re-run the strip (2026-09-06, user: "the dock
    /// sometimes becomes unresponsive" — when the wave was layout, each
    /// write re-ran the wave, which moved every frame, for as long as a
    /// finger was down).
    @State private var chipFrames = ChipFrameBox()
    private static let contentSpace = "dockStripContent"
    // MARK: - The open folder's width (spec 2026-09-05)

    /// The strip's viewport, tracked off the scroll: offset and width in
    /// content space. A plain box, not `@State`, so a scroll frame does not
    /// re-render the strip — only `stickyWord` below is state, and it is
    /// written only when it changes.
    @State private var viewport = ScrollViewportBox()
    /// A chip's centre in window space — the anchor a springing folder grows
    /// out of (`DockSpringRow`). Content-space frame, less the scroll, plus
    /// the strip's own window x.
    private func anchorX(for label: String) -> CGFloat? {
        chipFrames.frames[label].map { windowX(contentX: $0.midX) }
    }
    /// A content-space x in window space — the strip's own window x, plus the
    /// point, less the scroll.
    private func windowX(contentX: CGFloat) -> CGFloat {
        viewport.globalMinX + contentX - viewport.offset
    }

    /// THE MAGNIFICATION (2026-09-05; confined and made a transform
    /// 2026-09-09): the chip under a held-then-sliding finger (the scrub) or
    /// under a pointer stands tallest, its neighbours less, falling off with
    /// distance — the Mac dock's picture, which needs a STATIONARY strip and a
    /// finger moving over it. A plain scroll is the opposite: the strip moves
    /// with the finger and the same chip stays under it, so the wave under a
    /// scroll never visibly swept anything (user, 2026-09-09: "it doesn't
    /// really magnify like an apple dock on a mac does") while it re-laid out
    /// every chip per touch step, and a flick's parked magnifier rebuilt the
    /// strip once per frame for the length of every deceleration. Neither
    /// takes part now; a finger dragging the strip is a scroll and nothing
    /// else.
    ///
    /// The lift is a TRANSFORM (`scaleEffect`, anchored at the chip's foot so
    /// it rises out of the slab), never a size: the strip's content width is
    /// constant whatever the finger does, so the scroll never has its content
    /// size changed under a deceleration — which is what made it "not scroll
    /// properly". The layout form existed because a scale over a GLASS chip
    /// double-rendered; the chips are flat now (see `horizontalStrip`).
    /// `hoverX` is the POINTER, in the content `HStack`'s space, the frame
    /// the chips are recorded in. Off under Reduce Motion. **Pointer only
    /// since prd §662h (2026-09-09, user: "w/o a mouse like on a mac who is
    /// going to really scrub?" → "kill it")** — the finger's scrub, a hidden
    /// hold-then-slide nobody would find, is DELETED; the wave under a
    /// pointer on iPad and Mac IS the Mac dock's case and stays.
    @State private var hoverX: CGFloat?
    private static let waveReach: CGFloat = 1.4
    /// How far a pointer moves before the wave is re-laid under it (PERF
    /// 2026-09-08): the wave is a cosine over ~90pt, so 3pt is far
    /// below anything the eye resolves, and `DS.Motion.press` springs the
    /// chips between steps.
    private static let fingerStep: CGFloat = 3

    private func wave(for label: String) -> CGFloat {
        guard !reduceMotion, let frame = chipFrames.frames[label] else { return 1 }
        guard let x = hoverX else { return 1 }
        let pitch = categoryCell
        let d = abs(frame.midX - x) / (pitch * Self.waveReach)
        guard d < 1 else { return 1 }
        return 1 + DSDock.scrubLift * (0.5 + 0.5 * cos(d * .pi))
    }


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
                          : DSDock.agentSeat(fold: fold) - DSDock.slabInset
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
    /// Where a chip is fully GONE. On the phone that is the bar's trailing
    /// edge itself (2026-09-06, measured across 89 demo room shots): it used
    /// to be a ramp's width before it, so a chip whose leading edge sat under
    /// the octopus was still fully lit, and every room showed a sliver of the
    /// previous chip's word peeking out from under the bar ("Vi", "Me", "Ni").
    /// The ramp now runs from the bar's edge outward instead of ending at it.
    ///
    /// **At the bar's MARK, not its seat (2026-09-09, user: "there is way too
    /// much space between the octopus and All").** `headTrailingEdge` is the
    /// bar's seat — its mark plus the `seam` after it — and the first chip
    /// rests a whole `fadeRamp` past that, plus its own 5pt of ring room:
    /// measured on the simulator, 39pt of air between the octopus and "All"
    /// where chip-to-chip is 14. Vanishing at the mark's own edge keeps the
    /// 2026-09-06 property (nothing under the bar is lit, so no sliver of a
    /// word shows through its glass) and lets the ramp start `seam` earlier;
    /// with the ramp halved the air is 17.
    private var fadeClear: CGFloat {
        axis == .vertical ? headTrailingEdge - 8 : headTrailingEdge - DSDock.seam
    }
    /// 12, from 24 (2026-09-09): the ramp is also the air the first chip
    /// rests in, so every point of it is paid twice — once as the melt, once
    /// as the hole beside the bar. A chip is 56 wide; twelve points of travel
    /// is still a dissolve, not the hard line 2026-07-19 forbids.
    private static let fadeRamp: CGFloat = 12
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
        // The TRAILING melt's edge, in the viewport's own space (prd §662e):
        // the peeking tile has to dissolve into the slab's far end the way
        // the leading ones dissolve under the bar, or the cue that says
        // "there is more" reads as a tile someone cut in half. Zero until
        // the strip has measured itself, which disables the effect rather
        // than fading everything.
        let far = stripWidth
        // ScrollViewReader keeps the ACTIVE chip visible — a deep link
        // (casberi://feed/source/Zerion) can select a chip past the fold,
        // and a filter you can't see reads as no filter at all.
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // **FLAT CHIPS IN A GLASS SLAB (2026-09-09, user: "the nav bar
                // is still laggy and doesn't scroll properly. please fix,
                // radically").** Until today every chip was its own
                // `.interactive()` Liquid Glass element inside a
                // `GlassEffectContainer`, inside the dock's glass slab, inside
                // a scroll view — eleven live backdrop samples nested in a
                // twelfth, re-shaped on every fold tick and every wave step,
                // which is the one arrangement Apple's own guidance rules out
                // (glass on glass; glass on scrolling content). It was also
                // why the wave had to be LAYOUT (a scale over glass
                // double-rendered) and why the melt had to be a viewport MASK
                // (opacity never reached hoisted glass), each of which cost a
                // frame of its own. The slab is the glass; the chips are ink
                // on it, the way the Mac dock's icons and a tab bar's items
                // are. The active word's tint fill still travels
                // (`matchedGeometryEffect`), the melt is per chip again, and
                // nothing in this strip is rendered offscreen.
                //
                // A plain `HStack`: the fold caps the strip at eleven
                // categories, and an eager stack is one fewer thing between
                // `scrollTo` and a chip that has to be realized to be scrolled
                // to. (The `Section`/`pinnedViews` history is in git; keeping
                // an EMPTY `Section` once shipped the strip at zero height.)
                HStack(spacing: Self.chipGap) {
                    ForEach(scrollingLabels, id: \.self) { label in
                        chip(label)
                            // Where this chip is, for the scrub — see
                            // `chipFrames`. Layout is constant under the wave,
                            // so this fires on fold and folder changes only.
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(Self.contentSpace))
                            } action: { frame in
                                chipFrames.frames[label] = frame
                            }
                            // THE MELT, PER CHIP: solid until its leading edge
                            // reaches the bar's trailing edge (`clear`), then
                            // gone over `ramp` as it slides under the bar —
                            // the 2026-07-19 ruling ("disappear into it, not
                            // into a hard line"). `.scrollView` is the
                            // viewport's space. Evaluated by the render
                            // server, never a body pass.
                            .visualEffect { content, proxy in
                                let f = proxy.frame(in: .scrollView)
                                let lead = min(max((f.minX - clear) / ramp, 0), 1)
                                // Fades across the TILE'S OWN WIDTH, not over
                                // `ramp`: the peeking tile stands about half a
                                // cell past the edge, so a 12pt ramp put it at
                                // zero and the "there is more" cue drew
                                // nothing at all (measured on the simulator).
                                // Solid while fully inside, half-lit when half
                                // out, gone when past — which is the dimmed
                                // peek the mock was chosen from.
                                let trail = far > 0 && f.width > 0
                                    ? min(max((far - f.minX) / f.width, 0), 1)
                                    : 1
                                return content.opacity(Double(min(lead, trail)))
                            }
                    }
                }
                // The air between the bar and the first chip at rest — see
                // `stripInset`.
                .padding(.leading, contentLead)
                .padding(.trailing, DS.Space.s4)
                .coordinateSpace(name: Self.contentSpace)
                // A pointer over the strip — see `hoverX`. `.local` here IS
                // the content space named above.
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let p):
                        // Stepped like the finger (PERF 2026-09-08): a
                        // pointer reports every sub-point of travel.
                        guard abs((hoverX ?? -.infinity) - p.x) >= Self.fingerStep else { return }
                        withAnimation(DS.Motion.press) { hoverX = p.x }
                    case .ended:
                        withAnimation(DS.Motion.press) { hoverX = nil }
                    }
                }
                // NO FINGER GESTURE ON THIS CONTENT, and that is the ruling
                // that ends a week (prd §662h): the scrub — a hold, then a
                // slide that magnified the tiles under the finger — was a
                // hidden gesture on a screen with no pointer, cost three
                // passes of arbitration, never fired on a phone, and in its
                // last form froze this scroll dead (§662g). A flick scrolls,
                // a tap opens the folder, and nothing here claims a touch.
                // `MainSurface.topInset` measures this strip's NATURAL height
                // through a sibling `GeometryReader`; this pins the subtree to
                // its own ideal height before that measurement sees it (a lazy
                // stack once reported the whole proposed height, 2026-08-24).
                .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear {
                // Unconditional since §591: "All" is in this run now, so a
                // strip restored on All must scroll to it like any other room.
                proxy.scrollTo(active, anchor: .center)
            }
            // **A chip you TAPPED is not re-centred (prd §359, 2026-08-11)** —
            // the travelling fill needs the whole distance between two chips to
            // happen in. Every OTHER route (a deep link, a swipe step, a
            // restored filter) still re-centres: a selection you cannot see
            // reads as no selection at all.
            .onChange(of: active) { _, now in
                if tapped == now { tapped = nil; return }
                withAnimation(DS.Motion.standard) { proxy.scrollTo(now, anchor: .center) }
            }
            // The viewport, for `windowX` — a box write per sample, no state,
            // so a scroll frame never re-renders the strip.
            .onScrollGeometryChange(for: ScrollViewportSample.self) { geo in
                ScrollViewportSample(offset: geo.contentOffset.x, width: geo.containerSize.width)
            } action: { _, new in
                viewport.offset = new.offset
                viewport.width = new.width
                // The one viewport fact that IS layout (`categoryCell`) —
                // written only when it changes, so a scroll frame still
                // re-renders nothing.
                if stripWidth != new.width { stripWidth = new.width }
            }
            .onScrollPhaseChange { _, phase in
                // The strip's own motion, for `dockBusy` — a finger dragging
                // it, or a flick that outlives the finger.
                viewport.moving = phase != .idle
                publishDockBusy()
            }
            // The strip's own window x, so a chip's content-space frame can be
            // turned into the anchor a springing folder grows out of.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { x in
                viewport.globalMinX = x
            }
        }
    }

    /// `ShellChrome.dockBusy` from the one fact the strip holds about its own
    /// motion, written only when the answer changes (2026-09-09): its scroll
    /// phase — a finger dragging it, or its flick.
    private func publishDockBusy() {
        let busy = viewport.moving
        if chrome.dockBusy != busy { chrome.dockBusy = busy; GestureGate.set(dock: busy) }
    }

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
                            ? Text("Accounts, needs attention")
                            : Text("Accounts"))
        .dsTooltip(bridges.attentionCount > 0
                   ? String(localized: "Accounts, needs attention")
                   : String(localized: "Accounts"))
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
    ///
    /// **A FOLDER SPRINGS UP, THE CHIP NEVER MOVES (2026-09-05, the Mac-dock
    /// folder; see `DockSpringRow`).** For part of one evening a category
    /// opened IN PLACE — the chip grew to hold its venues. It spent width the
    /// row does not have, and the word that closes the folder had to be
    /// chased to a fixed seat to stay on screen. The chip is a word again;
    /// its venues rise above the dock out of this chip, and the fill stays on
    /// the word while they are up — "this folder", with the lit venue ringed
    /// in the row: "this venue".
    ///
    /// **A TILE, not a capsule, since prd §662 (2026-09-09)** — see the type
    /// doc. The glyph is `CategoryGlyph` (frozen size, fixed box, one bounce
    /// on arrival); the word is `dockCaption10`, the rung sized by this tile.
    /// `minimumScaleFactor` is a floor for the accessibility sizes only —
    /// at the default size no word in the table shrinks, so the strip draws
    /// ONE caption size, which is what §351 fought for.
    @ViewBuilder
    private func categoryTile(_ label: String) -> some View {
        let isOn = label == active
        VStack(spacing: 2) {
            CategoryGlyph(name: CategoryFold.glyph(for: label), size: glyphSize, isActive: isOn)
            Text(label)
                .dsText(.dockCaption10)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isOn ? .white : DS.textPrimary)
        // No inner padding: the tile's width IS the caption's bound (see
        // `tileWidth`), and 4pt a side inside 52 would put "Shopping" under
        // its floor.
        .frame(width: axis == .vertical ? Self.railChipWidth : Self.tileWidth, height: iconSize)
        .wordChipFill(active: isOn, ns: selectionNS,
                      shape: chipShape(tile: true, outer: false))
    }

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
        // The wave under a scrub or a pointer — a TRANSFORM applied at the
        // end of this chip (`scaleEffect`), never a size: see `wave(for:)`.
        let m = wave(for: label)
        // Through the catalog, not against the label: see `SourcesTray.cell`.
        // The strip and the tray it opens must agree about which seats are in
        // trouble, so this line and that one stay identical.
        let seat = BridgeCatalog.seatName(forSource: label)
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
        // Whether any of those seats is BROKEN is read in two leaves below
        // (`ChipAttentionRing`, `ChipSpokenLabel`), never here (prd §670): a
        // scan of `bridges.bridges` in this body made every bridge write —
        // two per sync that lands — rebuild all eleven chips.
        Button {
            DSHaptic.selection()
            // Marks this change as finger-initiated so the strip does not
            // re-centre under it — see the horizontal strip's `onChange`.
            tapped = label
            // Where a folder would spring from — published BEFORE the toggle,
            // so the row's first frame already knows its anchor.
            if let x = anchorX(for: label) { chrome.folderAnchorX = x }
            withAnimation(DS.Motion.folder) { onTap(label) }
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
                        .wordChipFill(active: isActive, ns: selectionNS,
                                      shape: chipShape(tile: false, outer: false))
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
                        categoryTile(label)
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
            //
            // **NOR DOES THE PINNED CHIP (user, 2026-09-06: "the pinned pin
            // flips when tapped… it looks like a glitch").** The word-chip
            // ruling directly above generalises rather than stopping at words:
            // the flip is an IDENTITY moment, and identity is what a BRAND MARK
            // has. The pinned room draws `pin.fill` — a generic SF Symbol the
            // system uses for the same verb everywhere — so there is no mark
            // turning to face you, just a symmetric glyph inverting through
            // itself. Its half-way frame is edge-on and near-invisible, which
            // is exactly why it reads as a flicker rather than a turn.
            // Reads `bloomTicks` in ITS OWN body (2026-09-09), not this one: an
            // arrival used to invalidate the whole strip, which is the "laggy
            // while the app loads in the background" every sweep's landings
            // produced. Same for the catch bob below.
            .modifier(ChipIdentityFlip(label: label, isActive: isActive,
                                       enabled: !isWord && label != Pinboard.room))
            // The catch bob — a thing landing from this source while the
            // person watches bumps its chip once, the flight's landing
            // generalized to bridge arrivals (delight 2026-07-13).
            .modifier(ChipCatchBob(label: label, reduceMotion: reduceMotion))
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
                    chipShape(tile: isCategory, outer: true)
                        .strokeBorder(DS.tint.opacity(0.55), lineWidth: 2)
                }
                if isActive, !isWord {
                    // The active ring is always tint now — the feed sits on the
                    // neutral ink page (user ruling 2026-07-18: full ink), so
                    // there's no source-hue field for a tint ring to melt into.
                    //
                    // The lean, the matched geometry and the Reduce Motion
                    // branch all moved into `ChipLean` (2026-09-06) — same
                    // group as the word chips' fill (prd §412b), same reason
                    // the offset sits INSIDE the match, and now the strip does
                    // not rebuild to draw it.
                    SelectionTravel(ns: selectionNS) {
                        chipShape(tile: false, outer: true)
                            .strokeBorder(DS.tint, lineWidth: 2.5)
                    }
                }
            }
            // DASHED, not merely orange (2026-07-21). "Selected" and "this
            // connection is broken" were the same 2.5pt ring in two hues —
            // indistinguishable to anyone who doesn't separate them by
            // color. The solid ring above belongs to selection alone; this
            // one is drawn only where no selection ring is (the `else` it
            // used to be). A leaf, so the bridge store is read there (§670).
            .overlay {
                ChipAttentionRing(seats: attentionSeats,
                                  shape: chipShape(tile: isCategory, outer: true),
                                  enabled: !(isActive && !isWord))
            }
            // A category's outer frame is its CELL (§662e) — the tile sits
            // centred in it, and the cell is what spreads across the strip.
            // On the rail the tile sizes to the rail and the cell is moot.
            .frame(width: isCategory ? (axis == .horizontal ? categoryCell : nil) : chipSize,
                   height: chipSize)
            // THE LIFT: the chip grows from its foot, so it rises out of the
            // slab the way a Mac dock icon does, and the tallest draws over
            // its neighbours rather than under the one laid out after it. A
            // transform on a flat chip — no layout, no glass to double-render.
            .scaleEffect(m, anchor: .bottom)
            .zIndex(Double(m))
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
            // `chipShape` since §662 — the same one call as every ring, so
            // the tile's hit region is the tile and the circle's is the
            // circle, with nothing to keep in step.
            .contentShape(chipShape(tile: isCategory, outer: true))
            .dsHover()
        }
        .buttonStyle(.plain)
        // The long-press peek (2026-08-14, prd §384): the room's head floats
        // up without navigating. "All" sits it out — its room is the whole
        // feed, and a peek that previews everything previews nothing.
        // **RAIL ONLY since 2026-09-05.** On the phone a press on the strip
        // is the scrub (`horizontalStrip`'s long-press-then-drag), which holds
        // for the same beat a context menu would and takes the touch — so the
        // peek could never fire there, and a modifier that never fires is left
        // off rather than left claiming. The rail has a pointer and no
        // scrub, and keeps it.
        .modifier(ChipPeekModifier(label: label, venues: venues,
                                   enabled: axis == .vertical && label != "All",
                                   onOpen: { onTap(label) }))
        // Names the mark on hover (Mac only, see `dsTooltip`) and to
        // VoiceOver — ONE string, computed ONCE, in a leaf (prd §670). It was
        // built twice per chip per body, `ListFormatter` and localized
        // lookups included, once for a modifier that is `self` on a phone.
        .modifier(ChipSpokenLabel(label: label, venues: venues, isActive: isActive))
        // Finger-driven, never idle: chips ease down as they leave the viewport
        // edges (Stories grammar). Under Reduce Motion only the fade remains.
        // Follows `axis` so the rail's chips ease at its TOP and BOTTOM edges,
        // which is where its own viewport ends.
        .modifier(ChipScrollEase(axis: axis, enabled: !pinned,
                                 reduceMotion: reduceMotion))
        .id(label)
        // The folder for VoiceOver (2026-09-06): the scrub and the wave are
        // pointer moves with no spoken form, so the spoken form is the tap's
        // — this says what it does, and the row that springs up is its own
        // labelled group (`DockFolderRow`).
        .accessibilityHint(isCategory ? Text("Shows its sources above the dock") : Text(""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Static, and called from `ChipSpokenLabel` alone (prd §670): the
    /// string depends on the bridge store, which the strip's body no longer
    /// reads.
    fileprivate static func chipAccessibilityLabel(_ label: String, venues: [String],
                                                   broken: Bool, isActive: Bool) -> String {
        // A folded chip's own face is its category's word — visible — but for
        // more than one member VoiceOver is the one place that still says
        // WHICH seats are behind it, spoken rather than drawn (prd §351,
        // generalizing what was Markets-only reasoning here).
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
    }
}

/// One catch bob: the chip springs up a touch and settles when its source
/// lands a thing while the person watches. Fires only for the arrived chip,
/// never loops, and sits out under Reduce Motion.
/// The identity flip's trigger, read in a leaf so a bloom re-runs one chip's
/// flip and not the strip (2026-09-09).
private struct ChipIdentityFlip: ViewModifier {
    let label: String
    let isActive: Bool
    let enabled: Bool
    @Environment(ShellChrome.self) private var chrome

    func body(content: Content) -> some View {
        content.coinFlip(trigger: "\(isActive)-\(chrome.bloomTicks[label] ?? 0)", enabled: enabled)
    }
}

private struct ChipCatchBob: ViewModifier {
    let label: String
    let reduceMotion: Bool
    @Environment(ShellChrome.self) private var chrome
    @State private var bob = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(bob ? 1.12 : 1)
            .onChange(of: chrome.arrivedTick) { _, _ in
                guard chrome.arrivedChip == label, !reduceMotion else { return }
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
/// THE SELECTION SHAPE'S LEAN, read where it is drawn (2026-09-06).
///
/// The fill and the ring both lean toward the chip a swipe is heading for, and
/// both used to take that offset as a value computed in `SourceChips`'s own
/// body — which made the strip observe `chrome.pageDragProgress` and rebuild
/// every chip on every touch move of a page turn. One leaf reads it now, so
/// the per-frame cost of the lean is the shape that leans.
///
/// Reduce Motion keeps its exact former shape: no offset AND no matched
/// geometry, since the travelling selection is off there entirely.
/// **THE ONE OBJECT THAT TRAVELS BETWEEN CHIPS, AND HOW (prd §667,
/// 2026-09-10, user: "the active indicator when i swipe moves forward and
/// then swings back. if i switch tabs it does too, like it goes past the
/// icon and comes back. it should either stay still until it moves to the
/// next one, or go directly to the next one and not overshoot").** This was
/// `ChipLean`: the fill leaned toward the neighbour by 40% of a pitch as the
/// room was dragged (`pageDragProgress`), then the landing zeroed the drag
/// while the matched geometry set off for the new chip — a forward move and
/// a swing back, on two curves. And the travel rode whatever animation the
/// change was made in — `DS.Motion.folder` on a tap, `standard` on a
/// landing — both springs with bounce, so it overshot the tile and settled
/// back. Now: nothing moves under a drag (the room is the thing moving; the
/// selection says where you ARE until you have arrived), and the travel is
/// pinned to `DS.Motion.glide`, a critically damped spring, whatever
/// transaction the change came in on. Reading no drag state here is also
/// one fewer body per touch move for every chip in the strip.
private struct SelectionTravel<S: View>: View {
    let ns: Namespace.ID
    @ViewBuilder var shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            shape
        } else {
            shape
                .matchedGeometryEffect(id: ChipSelection.id, in: ns)
                // ONLY a change that ARRIVED animated is re-pinned to the
                // glide (prd §670). The first cut of §667 rewrote EVERY
                // transaction reaching this shape — including the fold's
                // un-animated write on every scroll frame — so while the dock
                // folded, the fill and the ring were re-sprung 60–120 times a
                // second and trailed the tile they sit on by up to 0.28s. A
                // nil animation stays nil: the shape moves with its chip.
                .transaction { t in
                    if t.animation != nil { t.animation = DS.Motion.glide }
                }
        }
    }
}

/// The active word chip's tint fill — the ONE object that travels between
/// word chips (prd §358/§412b). Nothing else: an inactive word is ink on the
/// slab's glass since 2026-09-09 (see `horizontalStrip`), the way a tab bar's
/// unselected items are.
private struct WordChipFill: ViewModifier {
    let active: Bool
    let ns: Namespace.ID
    /// The chip's own outline (`SourceChips.chipShape`) — a circle under
    /// "All", the tile under a category (prd §662). One shape TYPE, so the
    /// travelling fill morphs its corner on the way rather than swapping
    /// shape mid-flight.
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        content.background {
            if active {
                SelectionTravel(ns: ns) {
                    shape.fill(DS.tint)
                }
            }
        }
    }
}

/// A category tile's glyph (prd §662) — an SF Symbol at a FROZEN size in a
/// fixed box, so the caption's seat under it never moves whichever symbol the
/// category wears (`laptopcomputer` is wide, `note.text` is tall) and never
/// moves with the text setting either: the strip's rhythm is fixed by design,
/// as the "All" chip says of the marks beside it. Frozen through `.font` on
/// purpose and not `dsGlyph`, which would grow it with the caption — the
/// design-ramp audit deliberately leaves a non-literal size alone.
///
/// Its ONE motion: a single bounce when the tile becomes the active one — the
/// beat the word chips lost when §359 removed their flip, because a spinning
/// word is not an identity moment; a glyph bouncing once is exactly what the
/// flip was for a mark. Nothing ambient (no breathe, no wiggle): the dock's
/// chrome never explains itself (§630). Leaving a chip bounces nothing —
/// `landTick` moves only on arrival — and under Reduce Motion it never moves.
/// Its own view so the tick invalidates this glyph and not the strip (the
/// 2026-09-09 lesson `ChipIdentityFlip` records).
private struct CategoryGlyph: View {
    let name: String
    let size: CGFloat
    let isActive: Bool
    @State private var landTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .frame(width: size + 6, height: size + 2)
            .symbolEffect(.bounce.up, value: landTick)
            .onChange(of: isActive) { _, on in
                if on, !reduceMotion { landTick += 1 }
            }
    }
}

/// The dashed "needs reconnecting" ring, read where it is drawn (prd §670,
/// 2026-09-10). `bridges.bridges` is written twice by every sync that lands
/// (status, then status line), and reading it in `SourceChips`'s body made
/// each write rebuild the whole strip — §660 moved the bloom and the catch
/// bob to leaves for the same reason and left this scan in place. One leaf
/// per chip now; a bridge write re-runs eleven of these and nothing else.
private struct ChipAttentionRing: View {
    let seats: Set<String>
    let shape: RoundedRectangle
    /// False where a selection ring is drawn instead — the `else` this was.
    let enabled: Bool
    @Environment(BridgeStore.self) private var bridges

    var body: some View {
        if enabled, bridges.bridges.contains(where: { seats.contains($0.name) && $0.status == .attention }) {
            shape.strokeBorder(DS.attention,
                               style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
        }
    }
}

/// The chip's spoken name — the tooltip and the accessibility label, ONE
/// string built ONCE (prd §670). Same string for both so they cannot drift
/// on what a broken connection is called; a leaf so the bridge store it
/// depends on is read here, not by the strip.
private struct ChipSpokenLabel: ViewModifier {
    let label: String
    let venues: [String]
    let isActive: Bool
    @Environment(BridgeStore.self) private var bridges

    func body(content: Content) -> some View {
        let seat = BridgeCatalog.seatName(forSource: label)
        let seats: Set<String> = CategoryFold.isCategory(label) ? Set(venues) : [seat]
        let broken = bridges.bridges.contains { seats.contains($0.name) && $0.status == .attention }
        let spoken = SourceChips.chipAccessibilityLabel(label, venues: venues,
                                                        broken: broken, isActive: isActive)
        content
            .dsTooltip(spoken)
            .accessibilityLabel(spoken)
    }
}

private enum ChipSelection {
    static let id = "chipSelection"
    /// The ring that travels BETWEEN VENUES inside an open folder — a group of
    /// its own, since the chip's fill stays lit around it.
    static let venueID = "venueSelection"
}

extension View {
    /// One fill for both word chips, so the circle and the capsule can never
    /// drift apart the way their COLOUR did before §358.
    func wordChipFill(active: Bool, ns: Namespace.ID,
                      shape: RoundedRectangle) -> some View {
        modifier(WordChipFill(active: active, ns: ns, shape: shape))
    }
}

/// The strip's viewport as a plain box — see `SourceChips.viewport`.
final class ScrollViewportBox {
    var offset: CGFloat = 0
    var width: CGFloat = 0
    var globalMinX: CGFloat = 0
    /// The strip's scroll is not idle (a drag, or a flick still running).
    var moving = false
}

struct ScrollViewportSample: Equatable {
    var offset: CGFloat
    var width: CGFloat
}

/// Every chip's frame in the strip's content space — see `SourceChips.chipFrames`.
final class ChipFrameBox {
    var frames: [String: CGRect] = [:]
}
