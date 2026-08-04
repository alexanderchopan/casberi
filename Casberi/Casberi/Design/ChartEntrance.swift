import SwiftUI

/// The chart-entrance grammar (2026-08-03, prd §297) — one vocabulary for
/// "a drawing draws itself", so every visualization in the app arrives the
/// same way instead of however whoever built it happened to remember.
///
/// ## Why this file exists
///
/// An audit of the wallet room on 2026-08-03 found an exact split, and it was
/// not a taste split: **anything drawn by `TokenChartPlot` or the treemap drew
/// itself; everything hand-rolled out of `GeometryReader` + `Capsule`/`Path`
/// painted its final frame in one go.** The balance sparkline swept, its marks
/// landed, the treemap staggered — and beside them the flow band, the melt
/// bars, the risk axis, the range bar and the connections spine simply *were*,
/// with no arrival at all. The room read as two apps stacked.
///
/// The cause is mechanical rather than moral: the two animated families both
/// inherited their entrance from a shared component, and every hand-rolled
/// drawing had to remember one. So the fix is a shared component too — the
/// motion lives here, and a new visualization gets it by reaching for a
/// modifier rather than by re-deriving spring constants from a neighbour.
///
/// ## The rules the vocabulary encodes
///
/// - **A drawing reveals in the direction it means.** A line that accrues over
///   time wipes left to right; a bar that is a share of a whole grows from its
///   own base; a dot on a scale travels to its reading. Motion that runs
///   against the drawing's own axis is decoration, and decoration is what §129
///   spent the app's hue budget getting rid of.
/// - **One beat, then done.** Every animation here is a ONE-SHOT arrival,
///   guarded so a re-render (theme flip, Dynamic Type, a scroll back into
///   view within the same view's life) can't replay it. Nothing here loops —
///   looping motion claims live streaming, which the 2026-07-11 endpoint-pulse
///   ruling reserves for things that actually stream.
/// - **Reduce Motion renders the final frame immediately**, never a slower
///   version of the same move. Each entry point takes it as a NON-DEFAULTED
///   parameter rather than reading `@Environment` itself — not because a
///   modifier couldn't read it (it resolves in the caller's own environment
///   and cannot disagree), but because half these drawings sequence their own
///   beats too (`WalletFlowBand`, `UniswapRangeBar`, `WalletBalanceHeadline`)
///   and so hold the value anyway. Making it required means the compiler
///   objects at a call site that forgot, which for an accessibility guarantee
///   is worth one word per call. `MicroMotion`'s own modifiers read the
///   environment instead; that difference is this file's, deliberately.
/// - **These are appear-once animations, so plain SwiftUI is correct.** The
///   2026-07-28 `BerryRain` ruling — decorative motion during a refresh must
///   be CoreAnimation, because every ingest in this app is `@MainActor` and
///   starves a SwiftUI interpolation — is about motion that runs WHILE the
///   main thread is blocked. An entrance fires once, on appear, off the
///   refresh path.
enum ChartEntrance {
    /// How long a wipe takes to cross its drawing.
    static let wipe: Double = 0.85
    /// The beat before an entrance starts. Long enough that the card's own
    /// `RowEntrance` fade/slide has landed first, so the drawing arrives INTO
    /// a settled card rather than racing it.
    static let lead: Double = 0.18
    /// Between two staggered siblings — bars in a tray, dots on an axis,
    /// cells in a map. Measured against the treemap's own 0.06 so a mixed
    /// screen reads as one cadence.
    static let stagger: Double = 0.06

    /// Past this many siblings the stagger stops accumulating.
    ///
    /// `RowEntrance` learned this and this file did not, which is the kind of
    /// thing a shared component exists to carry: `WalletApprovalExposure.all`
    /// is UNCAPPED (unlike `AddressConnections.Map.nodes`, which prefixes), so
    /// a wallet with thirty live grants left its last row invisible for two
    /// seconds under a card whose own subhead reads "Start at the top".
    static let staggerCap = 12

    /// When the `index`-th sibling starts, in seconds.
    static func offset(index: Int, after delay: Double = lead) -> Double {
        delay + Double(min(index, staggerCap)) * stagger
    }

    /// A sibling arriving in a staggered set (a bar growing, a dot landing).
    static func arrive(index: Int, after delay: Double = lead) -> Animation {
        .spring(response: 0.5, dampingFraction: 0.86)
            .delay(offset(index: index, after: delay))
    }

    /// A single element popping into place — a face on a spine, a price dot
    /// finding its tick. Livelier than `arrive` because it has no siblings to
    /// stay in cadence with.
    static func land(after delay: Double) -> Animation {
        .spring(response: 0.4, dampingFraction: 0.62).delay(delay)
    }

    // MARK: The odometer arc
    //
    // A money total rolling from an anchor to now, then its delta pill landing
    // after. `GenMoneyHero` staged this in the Today brief on 2026-07-22 and
    // its own doc claimed the wallet room already shared the idiom — it didn't,
    // and when the room finally got it (§297) the constants were copied across
    // rather than shared, which is the exact drift this file exists to stop.
    // Both read these now.

    /// The digits travelling. Heavier damping than `arrive`: a number that
    /// overshoots its own value reads as a glitch rather than as motion.
    static var roll: Animation { .spring(response: 0.55, dampingFraction: 0.86) }
    /// The delta pill, after the roll has settled — a summary that lands with
    /// the thing it summarizes makes the eye choose, and it chooses wrong.
    static var pillLand: Animation { .spring(response: 0.3, dampingFraction: 0.62) }
    /// When the roll starts, and when the pill follows it.
    static let rollStart: Double = 0.42
    static let pillStart: Double = 1.04
}

// MARK: - The wipe

/// A left-to-right reveal — the shape of "this accrued over time".
///
/// The same mask `WalletBalanceHeadline` and `GenMoneyHero` already use for
/// their sparklines, extracted so a diagram that isn't a `TokenChartPlot` can
/// wear it too. Masking rather than trimming on purpose: a wipe works over a
/// drawing of any composition (slabs, tapers, labels, a face), where `trim`
/// only works on a single stroked `Path`.
private struct ChartWipe: ViewModifier {
    var delay: Double
    var duration: Double
    let reduceMotion: Bool
    @State private var drawn: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * drawn)
                }
            }
            .onAppear {
                // One-shot: a re-render inside this view's own life must not
                // replay the arrival.
                guard drawn == 0 else { return }
                guard !reduceMotion else { drawn = 1; return }
                withAnimation(.easeOut(duration: duration).delay(delay)) { drawn = 1 }
            }
    }
}

// MARK: - The staggered arrival

/// Scale-settle plus fade, keyed to a position in a set — the treemap's own
/// cell entrance, available to anything with siblings that should land in an
/// order that means something (biggest first, nearest first, oldest first).
///
/// Close kin to `MicroMotion`'s `staggerIn`, and deliberately not merged with
/// it: that one is the ROW cadence (0.04, `DS.Motion.standard`) shared by the
/// feed and the bridge screens, this is the CHART cadence (0.06, a spring),
/// which is the beat the treemap and the marks already move at. Two vocabularies
/// on purpose — but only two, and each named for the family it serves.
private struct ChartArrival: ViewModifier {
    let index: Int
    var delay: Double
    let reduceMotion: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1 : 0.94)
            .opacity(on ? 1 : 0)
            .onAppear {
                guard !on else { return }
                guard !reduceMotion else { on = true; return }
                withAnimation(ChartEntrance.arrive(index: index, after: delay)) { on = true }
            }
    }
}

extension View {
    /// The drawing reveals itself left to right, once, on appear.
    func chartWipe(delay: Double = ChartEntrance.lead,
                   duration: Double = ChartEntrance.wipe,
                   reduceMotion: Bool) -> some View {
        modifier(ChartWipe(delay: delay, duration: duration, reduceMotion: reduceMotion))
    }

    /// This element lands as the `index`-th of a set — the stagger carries
    /// whatever order the caller sorted by, so the entrance narrates the
    /// ranking the drawing already made.
    func chartArrival(index: Int,
                      delay: Double = ChartEntrance.lead,
                      reduceMotion: Bool) -> some View {
        modifier(ChartArrival(index: index, delay: delay, reduceMotion: reduceMotion))
    }
}

// MARK: - The bar

/// A share of a whole, as a filled track — the room's one bar shape (moved
/// here from `WalletFeedTiles` 2026-08-03 so the composition trays, the strip's
/// own inline melt and anything later all draw the identical object).
///
/// A fill, never a rule: the design law's no-hairlines ban is about LINES that
/// divide, and this is a quantity with a length.
///
/// ## The melt
///
/// `melt` inverts the entrance, and the inversion IS the feature. An ordinary
/// share bar grows from nothing to its fraction — the shape of "here is how
/// much". A veAERO lock is the opposite fact: it *had* all its voting power and
/// is losing it, linearly, to zero at its end date. So a melt bar draws FULL
/// and then recedes to what's left, which is the only entrance that states the
/// mechanic rather than merely reporting its current value. The tray's own doc
/// records that a real measured lock read 12,977 AERO against 5,342 votes;
/// nothing in the app had ever shown that number *moving*, and the movement is
/// what makes it legible as decay rather than as a percentage.
///
/// A permanent lock passes `melt: false` at `fraction: 1` — it never decayed,
/// so it must never be drawn decaying.
struct ShareBar: View {
    let fraction: Double
    /// Position in a staggered set, so a tray of bars arrives in order.
    var index: Int = 0
    /// Draw full, then recede to `fraction` — see the type doc.
    var melt: Bool = false
    let reduceMotion: Bool

    @State private var entered = false

    /// Where the fill sits: at rest it's the real fraction, before the
    /// entrance it's whichever end this bar travels FROM.
    private var width: Double {
        entered ? min(max(fraction, 0), 1) : (melt ? 1 : 0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(DS.fillFaint)
                Capsule(style: .continuous)
                    .fill(DS.tint)
                    .frame(width: max(2, geo.size.width * width))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
        .onAppear {
            guard !entered else { return }
            guard !reduceMotion else { entered = true; return }
            withAnimation(travel) { entered = true }
        }
    }

    /// A grow rides the shared arrival cadence; a melt holds at full for a beat
    /// so the fall is legible AS a fall, then recedes slowly — decay is the
    /// slow fact, and a melt that snaps reads as a bar that was simply wrong.
    private var travel: Animation {
        melt ? .easeInOut(duration: 0.9)
                .delay(ChartEntrance.offset(index: index) + 0.25)
             : ChartEntrance.arrive(index: index)
    }
}
