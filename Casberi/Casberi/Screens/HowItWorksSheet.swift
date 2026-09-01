import SwiftUI

/// "How it works" (2026-07-11) — the one persistent place that explains the
/// model, for a new person after the retiring coach lines are gone. Re-ruled
/// 2026-07-16: the evergreen abstractions ("Keep tabs", "Make it yours") left
/// a real tester not knowing what to do — now it teaches the ONE loop that
/// matters, as three numbered steps: connect → one feed → ask. Still no
/// gesture-by-gesture manual; it names the catalog's place and glyph because
/// that door is the whole game. Reached from the Settings tile to revisit any
/// time, and wired into the onboarding tail so a new person meets it once.
///
/// Redesigned 2026-07-16 (user: "more visually stunning, large proportions"):
/// each step is a full-width card wearing its numeral GIANT — SF Rounded
/// heavy, bleeding off the card's top-right corner — with a big glyph chip
/// and the title at the heading-22 tier. The numeral is information (the
/// sequence), not decoration; its hue is the step's identity, same as the
/// glyph chip it echoes. Step 1 carries a settled strip of real app icons,
/// slightly uneven like the onboarding rain — the same brands, come to
/// rest. Cards arrive staggered, the old connect screen's entrance.
///
/// Re-ruled 2026-07-16 (user): the connect screen DIED — this page IS
/// onboarding now, one screen. Its rain moved here: in the onboarding tail
/// every connectable app's tile falls down the screen — a curtain of
/// everything that can land. Since 2026-09-01 nothing falls past the bottom:
/// all 103 come to rest as one packed, overflowing heap filling the band
/// between the sentence and the doors, so the claim survives the fall
/// instead of leaving with it. Connecting
/// happens where it always really happened: in the catalog, which the one
/// door forward opens (the arc: apps rain down → the three steps → the
/// catalog where those apps live); from Settings there is no rain and the
/// plain Done remains.
/// Naming (user, 2026-07-16): user-facing copy never says "store" for this
/// surface — it's "the catalog" ("store" reads as a place you pay).
/// Text literals auto-localize (LocalizedStringKey).
struct HowItWorksSheet: View {
    /// Set by the onboarding tail; nil from Settings, where the toolbar Done
    /// is the exit and there is no rain. Non-nil means "this is someone's first
    /// run", which is what gates the rain, the CTA, and the fork below.
    ///
    /// The CTA used to be "Browse the catalog" and land in a wall of ~40 apps
    /// (prd §217, 2026-07-25), then "Try it" landing on the fork. It is
    /// **"Try a demo"** now and it lands in a furnished app.
    ///
    /// The article is INDEFINITE (user, 2026-08-29). "The demo" presupposes a
    /// specific artifact the reader is assumed to know about, on the first
    /// screen they have ever seen — the one place nothing can be assumed. The
    /// ambiguity this does NOT resolve is the word "demo" itself, which can
    /// still be read as a canned tour somebody has to sit through rather than
    /// as sample data they can look around in; that was weighed and the
    /// shorter label kept, so if this CTA ever measures as under-tapped, the
    /// lever to try is naming the OUTCOME ("Try it with sample data") rather
    /// than adjusting the article again.
    ///
    /// The reasoning that moved it (2026-08-07): every previous CTA handed
    /// someone a DECISION as their first act — which of forty apps, or which
    /// of three sources — and each of those decisions costs something real (a
    /// permission, an address, a handle) at the exact moment the person still
    /// does not know what the app is. The demo costs nothing and answers that
    /// question directly, so it is the only honest first tap. The fork is not
    /// deleted outright (2026-08-31): the catalogue is its answer,
    /// where "which of your own sources?" is a question the person now has.
    ///
    /// The secondary link below the CTA is the other half of that ruling —
    /// someone who already knows they want this must not be made to sit
    /// through a demo first. Primary/secondary rather than two equal buttons,
    /// because the fork's own "pick-one, not do-any" grammar applies here too.
    ///
    /// A non-nil node is where to land after the cover lifts; nil means the
    /// feed, which is right whenever the tap already produced something to see.
    var onStart: ((HomeRoute.Node?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var enteringDemo = false
    @State private var arrived = false
    /// False = the rain waits above the screen · true = it has fallen through.
    @State private var rainFell = false
    /// The Casberi mark's own arrival, after the rain has fallen past.
    @State private var markLanded = false
    /// Pushes the fork. Kept as local navigation inside this sheet's own stack
    /// so the greeting stays on the back chevron — a first run should be
    /// reversible.

    private struct Point: Identifiable {
        let glyph: String
        let hue: Color
        let title: LocalizedStringKey
        let line: LocalizedStringKey
        var id: String { glyph }
    }

    // Three numbered steps (user, 2026-07-20, prd §134 — down from four when
    // the app changed under them): a new person must leave knowing exactly
    // (1) that connecting apps — in the catalog — fills the feed by itself,
    // (2) that it is ONE feed the source chips narrow, (3) that the agent's
    // ask bar answers questions about anything they've saved.
    // The old separate "Open the catalog" step folded into step 1: the
    // catalog is WHERE you connect, not its own act. Step 1 wears the REAL
    // Apps-door glyph (TopDoors' square.grid.2x2) so they recognize it in
    // the shell later; step 3 wears the agent bar's sparkles the same way.
    // (History: step 3 was "Pin your favorites" until prd §131 retired
    // pinning on 2026-07-20; the "+ button" wording died when the FAB became
    // the agent's "Ask your things" bar in the same redesign.)
    //
    // **"top left" DELETED from step 1 (2026-08-24)** — the catalogue door
    // moved out of the chip strip's head and into the sources tray, so that
    // sentence sent a brand-new person to an empty corner. Directions in copy
    // are the most perishable thing an onboarding screen can hold: they go
    // stale silently, they go stale on the ONE screen whose whole job is to be
    // believed, and nothing in a build or a screen sweep can see it. So the
    // step names the DOOR (its glyph is right there beside the words, and it
    // is the same mark the shell draws) and never the corner. Steps 2 and 3
    // already worked this way — "the chips up top", "the bar at the bottom" —
    // and both survive because a strip and a bar are regions, not coordinates.
    // The titles carry no "1." prefix — the giant numeral IS the number.
    // TEXT ONLY (user, 2026-08-31: "hyper minimal and bold … it still feels
    // like a lot to read"). Every glyph, strip and subtitle this block ever
    // carried is deleted — three bold lines are the whole explanation, and
    // each one names the region it teaches in its own words.
    private let points: [Point] = [
        Point(glyph: "square.grid.2x2.fill", hue: .blue,
              title: "Connect your apps",
              line: ""),
        Point(glyph: "line.3.horizontal.decrease.circle.fill", hue: .pink,
              title: "One feed, or many",
              line: ""),
        Point(glyph: "sparkles", hue: .purple,
              title: "Ask your agents",
              line: ""),
    ]

    // MARK: - The onboarding rain (moved here 2026-07-16 when the connect
    // screen died). A hand-curated subset of the catalog — every name MUST
    // resolve to a real BridgeCatalog offer (catalog-sync.sh checks this
    // array by name). The last six are Apple's bridges as symbol tiles
    // (their icons are legally unbundlable).
    /// EVERY CONNECTABLE SEAT, derived (user, 2026-08-31: "why not have all
    /// 80+ or so that are in the app?"). There was no good reason — 249 brand
    /// marks are bundled against 103 connectable offers, so the only limit was
    /// that this was a HAND LIST of thirty.
    ///
    /// Deriving it is also what retires the drift: `catalog-sync.sh` had to
    /// check every hand-written name still resolved to a real offer, because a
    /// renamed or retired seat left a dead tile here. A list read from the
    /// catalog cannot go stale.
    ///
    /// Apple's own seats keep their SF-symbol fallback — those icons are not
    /// legally bundlable — which `BridgeIcon` already handles per name.
    private static var marqueeApps: [String] {
        let all = BridgeCatalog.offers.filter(\.connectable).map(\.name)
        // The landers fall LAST, so "the last six" is a curated set rather
        // than whatever sits at the end of the catalog array (user,
        // 2026-08-31: "what if the last six are weird ones"). It would have
        // been — that order is authoring order, and a seat added tomorrow
        // would silently take the best slot from Photos.
        //
        // These six are the ones somebody recognises without reading. They
        // used to be the only ones that stopped; now everything stops, and
        // falling last still buys them the two things worth having — they
        // come to rest ON TOP of the heap, on its centred top row directly
        // under the sentence, and they are the last arrival, so the settling
        // ends where the eye already is. `catalog-sync.sh` checks each still
        // names a real offer.
        return all.filter { !landers.contains($0) } + landers.filter { all.contains($0) }
    }

    private static let landers = ["Photos", "Calendar", "Gmail",
                                  "GitHub", "Notion", "Wallet"]

    // MARK: - The pile
    //
    // EVERY TILE LANDS (user, 2026-09-01: "have all of the icons fill up the
    // gap between Everything and Try a demo … they all sit there jampacked and
    // overflowing"). Until now six of the 103 stopped on a shelf and the other
    // 97 fell off the bottom — so the screen's one wordless claim, that THIS
    // MUCH can land here, was made by the tiles that LEFT, and was legible
    // only for the second and a half they were in flight. The pile makes it
    // standing still: the whole catalogue, at rest, filling the space between
    // the sentence and the doors.
    //
    // It OVERFLOWS on purpose. The run is deliberately wider than the phone
    // (`pileOverhang`), so the outer column is cut by the screen edge — a pile
    // that fits inside the margins reads as a designed arrangement of exactly
    // this many things, which is the opposite of the claim. Nothing is lost to
    // the crop: no tile is a control, none is named, and the whole overlay is
    // already hidden from VoiceOver.
    //
    // The band is MEASURED, not a fraction (the shelf it replaces used one).
    // The copy above it wraps to two or three lines depending on the phone and
    // the type size, and the doors below sit in a safe-area inset — so the gap
    // being filled is not a constant share of any screen, and a fraction that
    // balances on a 17 Pro puts the top row through the sentence on an SE. Both
    // edges are published as anchors and read back in the overlay's own
    // coordinate space; the fractions survive only as the first-frame fallback,
    // which the fall's own 0.7s delay means nobody ever sees.
    /// The tile OVERLAPS its neighbour by this share of its own width, which
    /// is what makes a heap rather than a mesh. Scaled with the tile so the
    /// packing looks the same at every size.
    private static let pileOverlap: CGFloat = 6 / DS.Mark.tile
    private static let pileOverhangShare: CGFloat = 0.85
    /// The tile never shrinks past this — below it a brand mark stops being
    /// recognisable, which is the one thing the pile is for.
    private static let pileMinScale: CGFloat = 0.5
    private static let pileBandFallback: (top: CGFloat, bottom: CGFloat) = (0.50, 0.86)
    /// Deterministic per-tile jitter — no Math.random in a view body; the
    /// same fall replays identically (and the screen sweep sees one design).
    private static let jitter: [CGFloat] = [-4, 3, -2, 5, -5, 2, -3, 4]

    /// How the heap is packed for a given screen and a given band.
    ///
    /// **THE TILE SCALES DOWN BEFORE THE PILE CROSSES THE BAND** (user,
    /// 2026-09-01: "for iPhone SE what do we do about the fact that the top
    /// row covers some of the text?"). At a fixed 44pt the heap is 310pt tall,
    /// which fits a 17 Pro's ~313pt gap almost exactly and overruns an SE's
    /// ~145pt by more than double — so the top row sat on the last line of the
    /// sentence.
    ///
    /// The alternative on the table was letting the surplus rows spill off the
    /// TOP edge, matching the deliberate crop at the sides. It is refused, and
    /// the reason is that the two edges are not alike: there is nothing at the
    /// left and right margins to lose, and the top of this screen is the mark
    /// and the one sentence the screen exists to say. A crop over words does
    /// not read as overflow, it reads as a broken layout — on the first screen
    /// anybody sees, which is the worst place to be doubted. So the band is
    /// hard and the tile gives way.
    ///
    /// Measured against the band each phone actually produces: 17 Pro 44pt
    /// (13 × 8), 15 Pro 42pt, Pro Max 44pt (14 × 8), SE **26pt (19 × 6)** — a
    /// small screen gets a finer, denser mosaic, which is more jampacked, not
    /// less. Shrinking also buys columns, so the row count falls faster than
    /// the tile does.
    ///
    /// One rung below that, stated rather than hoped for: at `pileMinScale`
    /// the tile stops shrinking and the ROWS start overlapping instead — a
    /// denser heap beats an unreadable mark. That rung is also what makes the
    /// band a HARD edge rather than a target, since `rowStride` is clamped to
    /// the room available, so the heap cannot cross into the sentence or the
    /// doors however extreme the type size. The one exception is arithmetic
    /// rather than design: a band shorter than a single tile overruns it by
    /// the difference, half above and half below, and there is no arrangement
    /// of one tile that does not.
    private struct PileLayout {
        var tile: CGFloat
        var cols: Int
        var rows: Int
        var colStride: CGFloat
        var rowStride: CGFloat
    }

    private static func pileLayout(count: Int, width: CGFloat, band: CGFloat) -> PileLayout {
        var scale: CGFloat = 1
        // Bounded: the loop must terminate on a zero or negative band too.
        for _ in 0..<64 {
            let tile = DS.Mark.tile * scale
            let colStride = tile * (1 - pileOverlap)
            // CEIL, not floor: the run must be at least the screen plus the
            // overhang, so a whole tile hangs off each edge. Rounding down
            // lets the run land a few points INSIDE the margins on some
            // widths, which draws a tidy centred grid — the exact reading
            // this is meant to refuse.
            let cols = max(1, Int(ceil((width + tile * pileOverhangShare * 2) / colStride)))
            let rows = max(1, Int(ceil(Double(count) / Double(cols))))
            let height = CGFloat(rows - 1) * colStride + tile
            if height <= band || scale <= pileMinScale {
                let room = max(0, band - tile)
                let rowStride = rows > 1 ? min(colStride, room / CGFloat(rows - 1)) : colStride
                return PileLayout(tile: tile, cols: cols, rows: rows,
                                  colStride: colStride, rowStride: rowStride)
            }
            scale -= 0.02
        }
        let tile = DS.Mark.tile * pileMinScale
        let colStride = tile * (1 - pileOverlap)
        return PileLayout(tile: tile, cols: 1, rows: count,
                          colStride: colStride, rowStride: colStride)
    }

    /// Which resting slot the i-th FALLING tile takes.
    ///
    /// **THE FALL ORDER AND THE SLOT ORDER ARE DELIBERATELY UNRELATED** (user,
    /// 2026-09-01: "the rain is too methodical … it rains in lines that layer
    /// on top of each other"). They used to be the same number — tile `i` took
    /// slot `i` — so two tiles 22ms apart landed in ADJACENT COLUMNS OF THE
    /// SAME ROW, and the heap assembled as a line being drawn left to right,
    /// once per row, eight times over. Every tile fell correctly and the whole
    /// thing read as a machine stacking boxes. Jitter could never have fixed
    /// it: the regularity was in the ORDER, not in the positions.
    ///
    /// The slots are dealt on a coprime stride instead — a permutation, so
    /// every slot is still used exactly once, and one with no short cycle, so
    /// successive arrivals are nowhere near each other. Still deterministic
    /// (no `Math.random` in a view body): the fall replays identically and the
    /// screen sweep sees one design.
    ///
    /// The six landers are held OUT of the deal. They keep the centred slots
    /// of the top row and keep falling last, so what the permutation scatters
    /// is only the anonymous 97 — the one piece of order worth keeping is the
    /// one somebody can actually read.
    private static func pileSlots(count: Int, cols: Int, rows: Int) -> [Int] {
        let landing = min(landers.count, count)
        let topFirst = (rows - 1) * cols
        let topCount = count - topFirst
        let landStart = topFirst + max(0, (topCount - landing) / 2)
        let reserved = Set(landStart..<min(count, landStart + landing))
        let free = (0..<count).filter { !reserved.contains($0) }
        let n = free.count
        guard n > 0 else { return Array(0..<count) }

        // Any stride coprime with `n` walks every residue exactly once. 37 is
        // the first choice because it is far from n/2 and from n/3, so the
        // deal does not settle into a visible rhythm of its own; it is stepped
        // down only if it happens to share a factor with this particular n.
        var stride = min(37, max(1, n - 1))
        while stride > 1 && gcd(stride, n) != 1 { stride -= 1 }

        var slots = [Int](repeating: 0, count: count)
        var k = 0
        for i in 0..<n {
            slots[i] = free[k]
            k = (k + stride) % n
        }
        for (offset, slot) in reserved.sorted().enumerated() where n + offset < count {
            slots[n + offset] = slot
        }
        return slots
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    /// The curtain, and then the pile. Every marquee tile falls from above the
    /// screen, tumbles, and comes to rest in the measured band between the
    /// sentence and the doors — packed tight enough to overlap, wide enough to
    /// be cut by both screen edges. Gravity is an ease-IN into a small spring:
    /// tiles accelerate and then settle, they don't glide and they don't snap.
    /// Never hit-testable.
    private func rain(_ bounds: PileBounds) -> some View {
        GeometryReader { geo in
            let count = Self.marqueeApps.count
            // The band. A missing anchor means the first frame, before the
            // preference has travelled — the fractions answer for that one
            // frame and the 0.7s fall delay means it is never seen.
            let top = (bounds.copy.map { geo[$0].maxY }
                        ?? geo.size.height * Self.pileBandFallback.top) + DS.Space.s3
            let bottom = (bounds.doors.map { geo[$0].minY }
                        ?? geo.size.height * Self.pileBandFallback.bottom) - DS.Space.s2
            // The tile shrinks until the whole heap fits the band — see
            // `pileLayout`, and the SE reading that forced it.
            let pile = Self.pileLayout(count: count,
                                       width: geo.size.width,
                                       band: bottom - top)
            let cols = pile.cols
            let rows = pile.rows
            let originX = geo.size.width / 2
                - CGFloat(cols - 1) * pile.colStride / 2
            let originY = (top + bottom) / 2
                - CGFloat(rows - 1) * pile.rowStride / 2
            // The top row is the short one (103 tiles never divide evenly),
            // and it is also the most looked-at, so it is centred on its own
            // rather than left-aligned against a run it cannot fill.
            let topRowFirst = (rows - 1) * cols
            let topRowCount = count - topRowFirst
            let slots = Self.pileSlots(count: count, cols: cols, rows: rows)

            ForEach(Array(Self.marqueeApps.enumerated()), id: \.element) { i, name in
                // Golden-ratio spread — deterministic, evenly scattered
                // columns without a visible grid.
                let frac = (Double(i) * 0.381966).truncatingRemainder(dividingBy: 1)
                let x = DS.Space.s4 + CGFloat(frac) * (geo.size.width - DS.Space.s4 * 2)
                let tilt = Double(Self.jitter[i % Self.jitter.count])
                // THE HEAP FILLS FROM THE BOTTOM UP, which is what a heap
                // does, and what puts the curated six (which fall last — see
                // `marqueeApps`) on the top row rather than in a corner.
                let slot = slots[i]
                let row = rows - 1 - slot / cols
                let col = slot % cols
                // Every other row is offset half a column: bricks, not a mesh.
                let brick = row % 2 == 0 ? 0 : pile.colStride / 2
                let centring = slot >= topRowFirst
                    ? CGFloat(cols - topRowCount) * pile.colStride / 2 : 0
                let restX = originX + CGFloat(col) * pile.colStride + brick + centring
                    + Self.jitter[(i + 5) % Self.jitter.count] * 0.5
                let restY = originY + CGFloat(row) * pile.rowStride
                    + Self.jitter[(i + 2) % Self.jitter.count] * 0.4
                // Hoisted out of the modifier: inline, the arithmetic pushed
                // that one expression past the type-checker's budget.
                let fallDelay: Double = 0.7 + Double(i) * 0.019
                    + Double(Self.jitter[(i + 1) % Self.jitter.count]) * 0.012
                let fallDuration: Double = 0.58
                    + Double(Self.jitter[(i + 6) % Self.jitter.count]) * 0.012
                BridgeIcon(name: name, size: pile.tile)
                    // Big in flight, pile-sized at rest — a scale, not two
                    // sizes, so the shrink is part of the landing rather than
                    // a layout change mid-fall. The falling size is pinned to
                    // `DS.Mark.hero` rather than to the pile's tile, so the
                    // curtain reads the same on a phone whose heap ended up
                    // half the size.
                    .scaleEffect(rainFell ? 1 : DS.Mark.hero / pile.tile)
                    .rotationEffect(.degrees(rainFell ? tilt * 1.4 : tilt * 0.5))
                    .position(x: rainFell ? restX
                                          : x + Self.jitter[(i + 3) % Self.jitter.count],
                              y: rainFell ? restY : -120)
                    // The base delay clears the cover's own presentation —
                    // start the rain while the cover is still fading in and
                    // half the fall is spent invisible (measured 2026-07-16).
                    // Reduce Motion (2026-07-21): no fall. The tiles are
                    // simply already in the pile — nothing is lost, because
                    // the pile is now the thing being said and the fall was
                    // only ever how it got there.
                    // A HEAP DOES NOT SHINGLE IN FALL ORDER. Layering by row
                    // keeps the overlap consistent — upper rows in front, so
                    // the landers on the top row are never half-covered by a
                    // stranger that happened to arrive after them, which is
                    // what a fall-order z did once the deal was permuted.
                    .zIndex(Double(rows - row))
                    // Neither the gap between arrivals nor the length of a
                    // fall is constant: a fixed 22ms stagger over a fixed
                    // 0.62s fall is a metronome, and reads as one even when
                    // every tile is going somewhere different. The jitter is
                    // small enough that the curtain still sweeps downward and
                    // large enough that arrivals overlap and swap.
                    .animation(reduceMotion ? nil
                                            : .spring(duration: fallDuration, bounce: 0.26)
                                                .delay(fallDelay),
                               value: rainFell)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // 103 brand tiles with no informational role — VoiceOver would read the
        // whole catalog aloud before reaching the sentence.
        .accessibilityHidden(true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    // The header is the display tier — 34-heavy SF Rounded,
                    // the Home cover's voice; this is the first screen a
                    // new person meets.
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        // "What you can do", not "How it works" (user,
                        // 2026-08-29: "how do we not say 'how it works' twice
                        // … maybe 'what you can do'"). Two reasons, and the
                        // second is the one that generalises.
                        //
                        // (1) It matches what it heads. All three steps are
                        // phrased as things YOU DO — "Connect your apps",
                        // "Ask anything" — so the old label named a mechanism
                        // over content that reads as actions.
                        // (2) It stopped being a heading and became a LABEL.
                        // Once the steps are one block, the header sits
                        // directly on top of the thing it names and the two
                        // say the same word; the Settings row that opens this
                        // sheet said it a third time. One name for the screen,
                        // used in both places (`AccountScreen`'s row moved with
                        // it), rather than a heading echoing its own section.
                        //
                        // The small tension, recorded rather than argued away:
                        // §528 made these read as one SEQUENCE and this labels
                        // them as a list of capabilities. The numerals still
                        // carry the order, so it is a tension and not a
                        // contradiction — and the falling-icon rain gives this
                        // screen an identity the fork can never be mistaken for
                        // in its first seconds regardless.
                        // The LABEL is quiet and the STATEMENTS are the
                        // screen (user, 2026-08-31: "shouldn't they be spread
                        // out more? larger?"). Three 24pt lines in a slab used
                        // a tenth of the screen and read as a list; §532's own
                        // move — extreme proportions, fewer sizes further
                        // apart — runs the hierarchy the other way: a caption
                        // names the screen, and each capability stands at the
                        // head rung with the screen's height divided between
                        // them. The slab is gone; a box around everything on
                        // an otherwise empty screen was holding the lines
                        // together when the whole screen is what holds them.
                        // ONE SCREEN, TWO DOORS (user, 2026-08-31: "we
                        // need to do better and have ONE screen somehow",
                        // then "the fork is already there" — its three arms
                        // are what the CATALOGUE offers, so they belong there
                        // as discover cards and not on a screen of their own).
                        //
                        // What went: the three numbered steps, then the three
                        // bold statements that replaced them, then the fork
                        // this pushed to. Each rewrite made the screen tidier
                        // and none made it SHORTER — it explained the app to
                        // somebody who had not seen it yet, which is work the
                        // demo does in ten seconds and prose never does.
                        //
                        // What stays is the rain (the best thing here, and the
                        // only explanation that needs no reading), one
                        // sentence, and the two things a person can actually
                        // do next.
                        // THE MARK LANDS LAST, ABOVE THE TEXT (user,
                        // 2026-08-31: "the octopus lands last above the text
                        // and fills that void too"). Two voids, two arrivals:
                        // the rain settles UNDER the copy and fills the middle,
                        // this fills the top. It arrives at 2.4s, after the
                        // curtain has passed the middle of the screen and
                        // while the heap's top row is still settling under it
                        // — deliberately not after the last tile (~3.6s),
                        // which would leave the top of the first screen
                        // anybody sees empty for the better part of four
                        // seconds. The rain is an overlay, so a falling tile
                        // passes IN FRONT of the mark, which is the curtain
                        // reading; at rest nothing reaches it, because the
                        // pile's band starts below this whole block.
                        CasberiMark(size: 120)
                            .scaleEffect(markLanded ? 1 : 0.7)
                            .opacity(markLanded ? 1 : 0)
                            .animation(reduceMotion ? nil
                                                    : .spring(duration: 0.55, bounce: 0.3)
                                                        .delay(2.4),
                                       value: markLanded)
                            .padding(.bottom, DS.Space.s4)
                            .accessibilityHidden(true)
                        Text("Everything you need, in one place.")
                            .dsText(.heading34)
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        // Says what "one feed, or many" never did (user: "isn't
                        // clear that you can view as one feed, or separately as
                        // many"). The agent is named in the same breath rather
                        // than taking a line of its own.
                        Text("Read it all together, or one app at a time. Ask your agents about any of it.")
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, DS.Space.s2)
                    }
                    .padding(.top, DS.Space.s2)
                    .arrive(arrived, delay: 0.1)
                    // The pile's ceiling. Published rather than guessed: this
                    // block is a 120pt mark plus two paragraphs that wrap
                    // differently on every phone and every type size.
                    .anchorPreference(key: PileBoundsKey.self, value: .bounds) {
                        PileBounds(copy: $0)
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // From Settings the sheet keeps its plain exit; in the
                // onboarding tail the catalog CTA below is the only door
                // forward (one door, the connect screen's rule).
                if onStart == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .tint(DS.tint)
                    }
                }
            }
            }
            .safeAreaInset(edge: .bottom) {
                if onStart != nil {
                    VStack(spacing: DS.Space.s1) {
                    Button {
                        DSHaptic.success()
                        enterDemo()
                    } label: {
                        Text("Try a demo")
                            .dsText(.body17)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            // Floating chrome — glass is the floating layer's
                            // law. The glass lives INSIDE the label so the
                            // Button owns the whole hit region: interactive
                            // glass (iOS 26 `.interactive()`) applied OUTSIDE a
                            // button intercepts touches for its own press
                            // deformation and intermittently eats the tap —
                            // the user saw it as "takes several taps"
                            // (2026-07-17). Matches BridgeDetailScreen's
                            // Reconnect button, the pattern that works.
                            .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(enteringDemo)

                    // The door for someone who already knows. Text, not a
                    // second button: two equal buttons is a decision, and the
                    // whole point of the change above is that the first tap
                    // shouldn't be one.
                    // Straight to the CATALOGUE (2026-08-31). It used to push
                    // a fork asking which of three things to start with —
                    // files, a wallet, or all the apps — and all three are
                    // what the catalogue already lists, so the question was a
                    // screen standing in front of its own answer.
                    Button {
                        DSHaptic.tap()
                        onStart?(.apps)
                    } label: {
                        Text("Connect my apps")
                            .dsText(.callout15)
                            .foregroundStyle(DS.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s2)
                    // The pile's floor. A safe-area inset, so its height is
                    // the device's business as much as ours.
                    .anchorPreference(key: PileBoundsKey.self, value: .bounds) {
                        PileBounds(doors: $0)
                    }
                }
            }
        // The rain falls only in the onboarding tail — from Settings this is
        // a reference page, and a second rain would be a fake first time.
        // It is never torn down: the tiles ARE the pile filling the middle of
        // the screen, so removing the overlay would empty it.
        .overlayPreferenceValue(PileBoundsKey.self) { bounds in
            if onStart != nil { rain(bounds) }
        }
        .tint(DS.tint)
        .onAppear {
            if reduceMotion { arrived = true }
            else { withAnimation(DS.Motion.standard) { arrived = true } }
            guard onStart != nil else { return }
            rainFell = true
            markLanded = true
            // Last tile: 0.7 base + 103 × 0.019 stagger + ~0.6 spring ≈ 3.3s.
            // The stagger is tight so the heap builds in about three seconds
            // rather than six; the mark lands at 2.4s, over a pile whose top
            // row is still settling under it.
        }
        #if DEBUG
        // `-howItWorksCTA <s>` fires the onboarding-tail CTA after a delay.
        // It now enters the DEMO rather than pushing the fork — pass
        // `-startPick <arm>` with `-demoCTA NO` to walk the own-things route.
        .onAppear {
            let delay = UserDefaults.standard.double(forKey: "howItWorksCTA")
            guard delay > 0, onStart != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                let ownThings = UserDefaults.standard.object(forKey: "demoCTA") != nil
                    && !UserDefaults.standard.bool(forKey: "demoCTA")
                NSLog("howItWorksCTA: fired (%@)", ownThings ? "catalog" : "demo")
                if ownThings { onStart?(.apps) } else { enterDemo() }
            }
        }
        #endif
    }

    /// Claim the demo, then lift the cover IMMEDIATELY.
    ///
    /// The rows are deliberately not landed here — `DemoMode.begin` only marks
    /// the mode and the seats, and `RootShell` pours the rows once this cover
    /// is out of the way. Seeding first would hand someone a finished feed,
    /// which reads as a screenshot; pouring after lets them watch it fill,
    /// which is the whole argument for the demo existing.
    private func enterDemo() {
        guard !enteringDemo, let onStart else { return }
        enteringDemo = true
        DemoMode.begin(store: store)
        onStart(nil)
    }

    // MARK: - One step, writ large

    /// A full-width card: the numeral huge and bleeding off the top-right
    /// corner (clipped by the card), the glyph in a big tinted chip, the
    /// title at heading-22. The numeral duplicates the reading order for
    /// sighted users only, so it hides from accessibility.
    /// One step, as a row inside the shared block (prd §528).
    ///
    /// **The giant corner numeral is GONE, and its own doc is why it could
    /// go.** It read: "The numeral is information (the sequence), not
    /// decoration" — true while the steps were three separate cards, where
    /// nothing else said they were ordered. Inside one block, top-to-bottom
    /// says it, so a 148pt numeral bleeding off each card's corner became the
    /// most decorative thing on the screen while still claiming to be
    /// information. The number survives at reading size in the leading slot,
    /// where it does the same job in a tenth of the space — and where it is
    /// also what stops this block being mistaken for the fork's answers.
    ///
    /// That deletion takes three fiddly workarounds with it: the numeral had to
    /// be an `overlay` rather than a ZStack sibling (as a sibling its 148pt set
    /// a height FLOOR on every card, padding cards 2 and 3 with ~200pt of dead
    /// space), the card needed a `clipShape` to crop the bleed, and every title
    /// carried a `.padding(.trailing, DS.Space.s6)` so its last word would not
    /// collide with the numeral. None of it is needed now.
    private func stepRow(_ index: Int, _ point: Point) -> some View {
        Text(point.title)
            .dsText(.heading22)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s3)
    }
}

/// Where the pile may rest, measured rather than assumed: the bottom of the
/// copy block and the top of the doors, published as anchors so the rain —
/// which lives in a full-screen overlay of its own — can resolve both in its
/// OWN coordinate space (`AddressFlight`'s pattern, prd §441).
///
/// The two edges come from two different subtrees (the scroll content, and a
/// `safeAreaInset`), so `reduce` MERGES per edge rather than letting the later
/// sibling replace the whole value — the naive `value = nextValue()` drops
/// whichever edge SwiftUI happens to visit first, and the pile then hangs off
/// a fallback fraction on every phone while looking merely a little low. A
/// nil edge is the first frame only, and the fall's 0.7s delay covers it.
private struct PileBounds {
    var copy: Anchor<CGRect>?
    var doors: Anchor<CGRect>?
}

private struct PileBoundsKey: PreferenceKey {
    static var defaultValue: PileBounds { PileBounds() }
    static func reduce(value: inout PileBounds, nextValue: () -> PileBounds) {
        let next = nextValue()
        if let copy = next.copy { value.copy = copy }
        if let doors = next.doors { value.doors = doors }
    }
}

private extension View {
    /// The steps' entrance — sections fade up in order, one curve.
    func arrive(_ on: Bool, delay: Double) -> some View {
        modifier(ArriveEntrance(on: on, delay: delay))
    }
}

/// A ViewModifier rather than a bare `View` extension so it can read the
/// environment: under Reduce Motion the rise is dropped and the section is
/// simply present (no fade-from-offset, which is the part that reads as
/// movement).
private struct ArriveEntrance: ViewModifier {
    let on: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on || reduceMotion ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : DS.Motion.standard.delay(delay), value: on)
    }
}
