import SwiftUI
import SwiftData

/// The first screen, and it rides ON the demo (2026-09-05, user: "immediately
/// go from the intro page into the demo … the intro page doesn't even have a
/// button").
///
/// **Nothing precedes content any more.** A fresh install used to open on a
/// full-screen cover with two doors — "Try a demo" and "Connect my apps" —
/// and the feed stayed empty behind it until one of them was tapped. That
/// was already the honest version of every earlier onboarding (prd §217: the
/// demo is the only first tap that costs nothing), but it was still a choice
/// standing in front of the thing it was a choice about. Now the demo BEGINS
/// at first launch: `RootShell` marks the mode and pours the rows the moment
/// this cover mounts, and this cover is a translucent slab over the feed as it
/// fills — the mark, one sentence, the rain of everything that can land, and
/// no control at all.
///
/// **It leads into the demo by itself** (user, 2026-09-05: "why not make it
/// lead directly to the demo"). The first cut held for a tap on the argument
/// that a self-lifting cover cuts off a slow reader or holds a fast one; with
/// one sentence and a two-and-a-half-second fall that argument was thin, and
/// a caption teaching a tap nobody has to make was a control that only talks.
/// It lifts a beat after the last tile lands (`autoLift`); any tap or drag
/// skips ahead — a drag because the first thing most people do to a feed is
/// scroll it. VoiceOver gets the whole cover as one button whose label is the
/// sentence, for whoever wants it gone now.
///
/// **The buttons are gone, and where their jobs went.** "Try a demo" is what
/// happens by itself now. "Connect my apps" was the door for someone who
/// already knew what they wanted, and that person is one tap further away —
/// the standing demo banner (`DemoBanner`) carries Exit, which lands on their
/// own empty feed with the catalogue a chip away; someone who came knowing is
/// the one reader who can afford a tap.
///
/// **It is OPAQUE, and the pour starts when it LIFTS — both measured on a
/// simulator, 2026-09-05, after the first cut got both wrong.** That cut made
/// the scrim translucent so the demo could be seen pouring through it, and
/// began the pour under the cover on the argument that "the pour is the show".
/// On a device that is two defects:
///
///   • **The pour starves this screen.** Pouring the demo corpus is ~15s of
///     main-thread work at launch (measured: `launchPerf HEAVYBUILD` ×52,
///     `MainSurface.feedThings` 1.3s cumulative), and SwiftUI cannot complete
///     a layout pass while it runs — so the mark, the sentence and the tiles'
///     own `GeometryReader` never got a frame. The first screen of the app was
///     PURE BLACK for fifteen seconds, then everything arrived at once with
///     the fall already over. The tiles ride CoreAnimation and would have been
///     smooth; they never got laid out to be armed.
///   • **A live feed behind the copy is not a backdrop, it is a collision.**
///     The demo banner, the room card and the dock all read straight through
///     0.88 and fought the sentence for the same pixels.
///
/// So: this paints the page in full, and `DemoMode.begin` only MARKS the mode
/// here — `RootShell` pours once the cover is gone, which is where the pour
/// lived before and why it always looked right. `pourIfNeeded`'s own argument
/// (a feed watched filling reads as an app; found full, as a screenshot) is
/// unharmed: the rows still land in view, a moment later, on an idle main
/// thread.
struct IntroCover: View {
    /// Called once, on the gesture that lifts the cover. The caller owns what
    /// "started" means (`onboarded`, the filter reset).
    let onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    @State private var arrived = false
    /// False = the rain waits above the screen · true = it has fallen through.
    @State private var rainFell = false
    /// The Casberi mark's own arrival, after the rain has fallen past.
    @State private var markLanded = false
    /// One gesture, one exit — a tap and a drag can both land in one frame.
    @State private var leaving = false
    /// The tiles' layer has dealt: the first frame of this cover is on screen
    /// (`TileDropLayer.onFirstDeal`). The pour waits for this, not a timer —
    /// measured: a 0.6s timer started the pour 0.9s BEFORE the first paint,
    /// and the page stayed black until the pour let the main actor go.
    @State private var dealt = false

    // MARK: - The rain

    /// EVERY CONNECTABLE SEAT, derived (user, 2026-08-31: "why not have all
    /// 80+ or so that are in the app?"). Deriving it is also what retires the
    /// drift: `catalog-sync.sh` used to check every hand-written name still
    /// resolved to a real offer. A list read from the catalog cannot go stale.
    /// Apple's own seats keep their SF-symbol fallback — those icons are not
    /// legally bundlable — which `BridgeIcon` already handles per name.
    private static var marqueeApps: [String] {
        let all = BridgeCatalog.offers.filter(\.connectable).map(\.name)
        // The landers fall LAST, so "the last six" is a curated set rather
        // than whatever sits at the end of the catalog array. They come to
        // rest ON TOP of the heap, on its centred top row directly under the
        // sentence, and they are the last arrival, so the settling ends where
        // the eye already is. `catalog-sync.sh` checks each names a real offer.
        return all.filter { !landers.contains($0) } + landers.filter { all.contains($0) }
    }

    private static let landers = ["Photos", "Calendar", "Gmail",
                                  "GitHub", "Notion", "Wallet"]

    // MARK: - The pile
    //
    // EVERY TILE LANDS (user, 2026-09-01): the whole catalogue, at rest,
    // filling the space between the sentence and the floor. It OVERFLOWS on
    // purpose — the run is wider than the phone (`pileOverhang`), so the outer
    // column is cut by the screen edge; a pile that fits inside the margins
    // reads as a designed arrangement of exactly this many things, which is
    // the opposite of the claim. Nothing is lost to the crop: no tile is a
    // control, none is named, and the whole overlay is hidden from VoiceOver.
    //
    // The band is MEASURED, not a fraction: the copy above wraps differently
    // on every phone and type size, and the floor below is a caption in a
    // safe-area inset. Both edges are published as anchors and read back in
    // the overlay's own coordinate space; the fractions survive only as the
    // first-frame fallback, which the fall's own 0.7s delay means nobody sees.
    private static let pileOverlap: CGFloat = 6 / DS.Mark.tile
    private static let pileOverhangShare: CGFloat = 0.85
    /// The tile never shrinks past this — below it a brand mark stops being
    /// recognisable, which is the one thing the pile is for.
    private static let pileMinScale: CGFloat = 0.5
    private static let pileBandFallback: (top: CGFloat, bottom: CGFloat) = (0.50, 0.86)
    /// Deterministic per-tile jitter — no Math.random in a view body; the
    /// same fall replays identically (and the screen sweep sees one design).
    private static let jitter: [CGFloat] = [-4, 3, -2, 5, -5, 2, -3, 4]
    /// The release schedule: the first wave lets go at `releaseBase`, each row
    /// above it `rowWave` later, every tile spread ±`releaseSpread`/2 around
    /// its row, and the six landers a further `landerHold` behind everything.
    private static let releaseBase: Double = 0.7
    private static let rowWave: Double = 0.10
    private static let releaseSpread: Double = 0.18
    private static let landerHold: Double = 0.25
    /// The floor's reserved height — the two-button block's own footprint, kept
    /// so the pile's band is the one the fall was tuned against. See its use.
    private static let floorHeight: CGFloat = 96
    /// Seconds from appear to the cover lifting on its own — the fall's last
    /// landing (≈2.5s) plus a beat at rest.
    private static let autoLift: Double = 3.4

    /// How the heap is packed for a given screen and a given band.
    ///
    /// THE TILE SCALES DOWN BEFORE THE PILE CROSSES THE BAND (user,
    /// 2026-09-01, the SE reading). Measured against the band each phone
    /// produces: 17 Pro 44pt (13 × 8), 15 Pro 42pt, Pro Max 44pt (14 × 8),
    /// SE 26pt (19 × 6). At `pileMinScale` the tile stops shrinking and the
    /// ROWS start overlapping instead — a denser heap beats an unreadable
    /// mark — and `rowStride` is clamped to the room available, so the heap
    /// cannot cross into the sentence or the floor however extreme the type
    /// size.
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
            // overhang, so a whole tile hangs off each edge.
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
    /// THE FALL ORDER AND THE SLOT ORDER ARE DELIBERATELY UNRELATED (user,
    /// 2026-09-01: "the rain is too methodical"). Slots are dealt on a
    /// coprime stride — a permutation with no short cycle, so successive
    /// arrivals are nowhere near each other, and still deterministic. The six
    /// landers are held OUT of the deal: they keep the centred slots of the
    /// top row and keep falling last.
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
        // far from n/2 and n/3, so the deal does not settle into a rhythm of
        // its own; stepped down only if it shares a factor with this n.
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

    /// The curtain, and then the pile. This computes WHERE each tile rests and
    /// WHEN it lets go; HOW it falls — real gravity, an upward bounce with an
    /// impact squash, on CoreAnimation — is `TileDrop`'s. Never hit-testable.
    private func rain(_ bounds: PileBounds) -> some View {
        GeometryReader { geo in
            let count = Self.marqueeApps.count
            let top = (bounds.copy.map { geo[$0].maxY }
                        ?? geo.size.height * Self.pileBandFallback.top) + DS.Space.s3
            let bottom = (bounds.floor.map { geo[$0].minY }
                        ?? geo.size.height * Self.pileBandFallback.bottom) - DS.Space.s2
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
            // and it is also the most looked-at, so it is centred on its own.
            let topRowFirst = (rows - 1) * cols
            let topRowCount = count - topRowFirst
            let slots = Self.pileSlots(count: count, cols: cols, rows: rows)

            let tiles: [TileDrop] = Self.marqueeApps.enumerated().map { i, name in
                let tilt = Double(Self.jitter[i % Self.jitter.count])
                // THE HEAP FILLS FROM THE BOTTOM UP, which puts the curated
                // six (which fall last) on the top row rather than in a corner.
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
                // RELEASE IN WAVES, LOWER ROWS FIRST — rows blur into each
                // other and arrivals overlap and swap; gravity does the
                // ordering, and the landers hold back a beat more.
                let spread = (Double((i * 37) % 17) / 16 - 0.5) * Self.releaseSpread
                let lander = Self.landers.contains(name) ? Self.landerHold : 0
                let release = Self.releaseBase + Double(row) * Self.rowWave + spread + lander
                return TileDrop(name: name,
                                rest: CGPoint(x: restX, y: restY),
                                size: pile.tile,
                                restTilt: tilt * 1.4,
                                drift: Self.jitter[(i + 3) % Self.jitter.count] * 0.6,
                                release: release,
                                // Upper rows in front, so the landers on the
                                // top row are never half-covered by a stranger
                                // that happened to arrive after them.
                                depth: Double(rows - row))
            }
            // Reduce Motion: no fall. The tiles are simply already in the
            // pile — the pile is the thing being said and the fall was only
            // ever how it got there.
            TileDropLayer(tiles: tiles, armed: rainFell, reduceMotion: reduceMotion,
                          onFirstDeal: { dealt = true },
                          // The fall's ending, felt once.
                          onSettled: { DSHaptic.lift() },
                          leaving: leaving,
                          onDroppedOut: { onStart() })
                // THE OUTER COLUMNS FADE (spec 2026-09-05): the run overhangs
                // both edges on purpose (`pileOverhangShare`), and a hard crop
                // there read as a layout cut off; a short ramp at each edge
                // makes the overflow read as the heap continuing past the
                // glass rather than stopping at it.
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.07),
                        .init(color: .black, location: 0.93),
                        .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // 103 brand tiles with no informational role — VoiceOver would read the
        // whole catalog aloud before reaching the sentence.
        .accessibilityHidden(true)
    }

    // MARK: - The cover

    /// The cover spoken as ONE label, composed from the three strings it
    /// draws rather than repeated as a fourth literal (2026-09-07). The
    /// headline changed with the inbox frame and the old label was a single
    /// baked sentence carrying the old words, which is exactly how a spoken
    /// form drifts from a drawn one. Every piece here is already in the
    /// catalog with all four translations, so composing costs nothing.
    private var coverSpoken: String {
        [String(localized: "One inbox for all your accounts."),
         String(localized: "Read it all together, or one app at a time. Ask your agents about any of it."),
         String(localized: "This is a demo.")].joined(separator: " ")
    }

    var body: some View {
        ZStack {
            // OPAQUE. See the type's own note: a live feed behind this is a
            // collision, not a backdrop.
            DS.page.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    // THE MARK LANDS LAST, ABOVE THE TEXT (user, 2026-08-31).
                    // Two voids, two arrivals: the rain settles UNDER the copy
                    // and fills the middle, this fills the top. It arrives at
                    // 2.4s, while the heap's top row is still settling under
                    // it — deliberately not after the last tile.
                    // PRESENT FROM THE FIRST FRAME (2026-09-05, measured on
                    // a simulator). The mark used to land at 2.4s on a spring
                    // and the copy faded up at 0.1s — both SwiftUI animations,
                    // interpolated on the main actor, and a first launch is
                    // exactly when that actor is busiest: the sentence stayed
                    // at opacity zero for as long as the launch work ran, so
                    // the first screen of the app was a black page with tiles
                    // falling onto nothing. The tiles survived because they
                    // ride CoreAnimation (`TileDrop`). The words are static
                    // now; the rain is the entrance.
                    // 56, not 120 (spec 2026-09-05): at 120 the mark was
                    // orphaned in the top-left corner with the sentence a
                    // long way beneath it; the tiles are the brand moment
                    // here, and the mark is a signature on the copy.
                    CasberiMark(size: 56)
                        .padding(.bottom, DS.Space.s3)
                        .accessibilityHidden(true)
                    // THE INBOX FRAME (user ruling 2026-09-06, prd §643) —
                    // the same sentence the empty feed leads with
                    // (`FeedScreen.emptyInvitation`), said HERE because this
                    // is the screen everyone reads and that one is reached
                    // only by someone who left the demo. It replaced
                    // "Everything you need, in one place.", which named no
                    // noun and fit a notes app, a launcher or a bank equally.
                    // Both strings were already in the catalog, so the swap
                    // carried no translation debt.
                    Text("One inbox for all your accounts.")
                        .dsText(.heading34)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Read it all together, or one app at a time. Ask your agents about any of it.")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s2)
                }
                // A fixed seat, not "whatever is above the heap" (spec
                // 2026-09-05): the copy block starts a tenth of the way
                // down, so the mark, the sentence and the heap share one
                // vertical rhythm on every phone.
                .padding(.top, DS.Space.s8)
                // The pile's ceiling. Published rather than guessed: this
                // block is a 120pt mark plus two paragraphs that wrap
                // differently on every phone and every type size.
                .anchorPreference(key: PileBoundsKey.self, value: .bounds) {
                    PileBounds(copy: $0)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dsAdaptiveContentWidth()
        }
        // THE FLOOR IS A SAFE-AREA INSET, not the last row of the copy stack
        // (2026-09-05, measured). Inside the stack its anchor resolved against
        // a `Spacer`-stretched frame and the heap was measured to a band that
        // ran past it — tiles landed over the caption and off the bottom edge.
        // An inset is the shape the pile's floor has always been, and it is
        // the device's business as much as ours.
        .safeAreaInset(edge: .bottom) {
            // **THE FLOOR: NO WORDS, THE DOORS' OWN FOOTPRINT, AND IT NEVER
            // MOVES** (2026-09-05, measured on a simulator against the mock).
            //
            // No words, because the cover lifts BY ITSELF once the fall has
            // settled (user: "why even make the loading screen be 'tap
            // anywhere to start'? … why not make it lead directly to the
            // demo") — a caption teaching a tap the person never has to make
            // would be a control that only talks (§83). A tap or a drag still
            // skips ahead for whoever is done early.
            //
            // The footprint is kept, because `TileDrop` chooses one gravity
            // per deal so the LONGEST drop takes `longestFall` — the fall's
            // whole character is a function of the band this floor closes,
            // and that band was tuned against the two-button block this seat
            // replaces (≈96pt). A 36pt caption made the band taller, the heap
            // lower, every drop longer, and `g` different, which read as the
            // wrong fall rather than as a moved caption.
            //
            // And it never animates: the engine REPLAYS the deal if the layout
            // moves before the first release (0.7s), and the first cut's
            // caption faded up with a 10pt offset from 0.5s — across that
            // release, restarting the fall in mid-air ("fast and jittery").
            Color.clear
                .frame(height: Self.floorHeight)
                .anchorPreference(key: PileBoundsKey.self, value: .bounds) {
                    PileBounds(floor: $0)
                }
        }
        // The rain is never torn down while the cover stands: the tiles ARE
        // the pile filling the middle of the screen.
        .overlayPreferenceValue(PileBoundsKey.self) { bounds in
            rain(bounds)
        }
        .contentShape(Rectangle())
        .onTapGesture { start() }
        // The first scroll leaves the cover, not the rows under it.
        .gesture(DragGesture(minimumDistance: 24).onChanged { _ in start() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(coverSpoken))
        // What activating DOES, not how — VoiceOver already says how on each
        // platform, and "double-tap" would be wrong under a pointer.
        .accessibilityHint(Text("Starts the demo now"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { start() }
        .onAppear {
            arrived = true
            rainFell = true
            markLanded = true
        }
        // THE DEMO IS CLAIMED, POURED UNDER THIS COVER, AND THE COVER LIFTS
        // WHEN BOTH THE FALL AND THE POUR ARE DONE (2026-09-05, third cut,
        // each step measured on a simulator):
        //   • `begin` only marks the mode and the seats — cheap, no fetching.
        //   • The pour is ~10s of main-thread work. Started at mount it
        //     starved the cover's first layout (a black page); started at the
        //     lift it revealed an EMPTY feed saying "Nothing here yet" that
        //     then filled for ten seconds, which is worse than either
        //     reading. So it starts one beat after mount — after the tiles'
        //     layer has had its first layout pass and dealt, since a dealt
        //     fall rides CoreAnimation and is untouched by anything the main
        //     actor does afterwards — and runs under an opaque, static page.
        //   • The cover lifts when the pour has returned AND at least
        //     `autoLift` has passed since mount, so the heap is seen at rest
        //     and the feed behind it is full when it appears. A tap or drag
        //     still skips ahead (the pour continues under the feed).
        //     `pourIfNeeded`'s "watched filling" argument is spent knowingly:
        //     ten seconds of an empty room is not a feed filling.
        // Guarded on `isActive` so a kill and relaunch mid-intro does not
        // re-mark a demo already running; `pourIfNeeded` is its own no-op when
        // nothing is pending.
        .task {
            if !DemoMode.isActive { DemoMode.begin(store: store) }
            let mounted = Date.timeIntervalSinceReferenceDate
            // Wait for the first painted frame (the tiles' first deal), then
            // one more beat so the commit that carried it is on screen; a
            // ceiling so a layer that never deals (Reduce Motion places the
            // tiles at rest and still deals — but belt and braces) cannot
            // hold the demo forever.
            var waited = 0
            while !dealt && waited < 40 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            try? await Task.sleep(for: .milliseconds(250))
            await DemoMode.pourIfNeeded(context: modelContext)
            // "Returned" is not "landed": another caller may hold the pour
            // (`pourIfNeeded` yields at once to it), and the feed's own
            // query takes a beat to show the rows after the last insert.
            var settling = 0
            while DemoMode.pourOutstanding && settling < 600 {
                try? await Task.sleep(for: .milliseconds(50))
                settling += 1
            }
            try? await Task.sleep(for: .milliseconds(400))
            let hold = reduceMotion ? 2.0 : Self.autoLift
            let remaining = hold - (Date.timeIntervalSinceReferenceDate - mounted)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            start()
        }
        #if DEBUG
        // `-howItWorksCTA <s>` lifts the cover after a delay — the same hook
        // name the old greeting's CTA answered to, so every launch recipe
        // that used it still lands in the demo.
        .onAppear {
            let delay = UserDefaults.standard.double(forKey: "howItWorksCTA")
            guard delay > 0 else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                NSLog("howItWorksCTA: fired (demo)")
                start()
            }
        }
        #endif
    }

    /// The lift is the rain REVERSED (spec 2026-09-05): the heap falls off
    /// the bottom edge under the gravity it arrived by, and the page lifts
    /// once the last tile has left (`onDroppedOut` → `onStart`). Under Reduce
    /// Motion the tiles are simply removed and the page lifts at once.
    private func start() {
        guard !leaving else { return }
        DSHaptic.tap()
        leaving = true
    }
}

/// Where the pile may rest, measured rather than assumed: the bottom of the
/// copy block and the top of the floor caption, published as anchors so the
/// rain — which lives in a full-screen overlay of its own — can resolve both
/// in its OWN coordinate space (`AddressFlight`'s pattern, prd §441).
///
/// `reduce` MERGES per edge rather than letting the later sibling replace the
/// whole value — the naive `value = nextValue()` drops whichever edge SwiftUI
/// happens to visit first.
private struct PileBounds {
    var copy: Anchor<CGRect>?
    var floor: Anchor<CGRect>?
}

private struct PileBoundsKey: PreferenceKey {
    static var defaultValue: PileBounds { PileBounds() }
    static func reduce(value: inout PileBounds, nextValue: () -> PileBounds) {
        let next = nextValue()
        if let copy = next.copy { value.copy = copy }
        if let floor = next.floor { value.floor = floor }
    }
}

private extension View {
    /// The copy's entrance — sections fade up in order, one curve.
    func arrive(_ on: Bool, delay: Double) -> some View {
        modifier(ArriveEntrance(on: on, delay: delay))
    }
}

/// A ViewModifier rather than a bare `View` extension so it can read the
/// environment: under Reduce Motion the rise is dropped and the section is
/// simply present.
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
