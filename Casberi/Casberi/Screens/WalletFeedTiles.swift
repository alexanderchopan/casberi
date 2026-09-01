import SwiftUI

/// The Wallet feed's head tiles (2026-07-20, the surface split): the reads
/// that used to be scattered across the manage screen and each wallet's detail
/// page, gathered where you actually look at them.
///
/// FLAT BY LAW, not by preference. These sit at the head of an eager screen,
/// and §gotchas' render-depth lesson (paid three times: 2026-07-10/13/15) says
/// anything there draws in one shallow body — never through the generic
/// `Widget`/`Row` path. Each tile below is a plain VStack of Text; no erasure,
/// no mount, no per-row environment.
///
/// Colour follows the ruling that came out of the mockups: hue belongs to
/// identity and alarm, never chrome. The balance's green is a REAL delta
/// (`TokenChartStyle.accent` already refuses to colour a flat change), the
/// warning glyph is the one `DS.attention` mark, and nothing else is tinted.

/// The wallet room's card recipe, in one place (prd §160, 2026-07-21) — every
/// card in this room is TRANSLUCENT so the crown pour (§159) travels under it
/// instead of being punched out. Shared by the balance card, the holdings
/// card, and the DeFi tiles below, because a room of cards at two different
/// opacities reads as a bug (caught on screen the moment Aave and Morpho
/// landed beside the two new cards).
///
/// **The recipe is THREE values now, not one (2026-08-22), for the reason the
/// paragraph above already gives.** It drifted anyway: the NFT shelf shipped
/// opaque (the brightest card in a room whose sharpest reading is a
/// liquidation axis), the flow band and the risk strip shipped on `fillFaint`
/// — which in light resolves to a ~3% black wash on a #f2f2f7 page, a card
/// DARKER than the page with no lift, and on a coloured page no card at all —
/// and the inner padding ran 14pt on three cards against 18pt on five, which
/// reads as the text column jogging sideways as the room scrolls. A prose
/// ruling could not stop that; a constant every card must name can.
///
/// `rowInsets` is the one that had TEN hand-written copies. Its top is s3
/// rather than the feed's usual s2 on purpose: two cards stop reading as two
/// objects once the space BETWEEN them is smaller than the space inside them,
/// and this room's cards carry 18pt of it. Bottom stays 0 — the top inset is
/// the whole gap, so a card's spacing can never depend on which card precedes.
enum WalletCardStyle {
    static let fill = 0.82
    static let pad = DS.Space.s4
    static let rowInsets = EdgeInsets(top: DS.Space.s3, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4)
}

// `WalletTile` (the caption-plus-chevron tile shell) retired here 2026-07-25
// with prd §212 — its only two users were the Aave and Morpho cards, and the
// whole point of the pass is that those reads are ROWS, not tiles. The room's
// shared anatomy now lives in `WalletRow.swift`.

/// Balance — the portfolio number, its sparkline, and the honest delta, as the
/// Wallet feed's DISPLAY HEADLINE (prd §146, 2026-07-21). The combined read is
/// the app's crown feature (user, 2026-07-20: "the combined wallet state is
/// our best feature"), so it stops living in a half-width tile and takes the
/// room's headline voice — set on the page (no card), the number at the
/// sanctioned `price40` money rung, its delta beside it, the sparkline running
/// full-width underneath as a whisper. Nothing renders until two aligned
/// samples exist (`TokenChart.from` guards it), so a freshly-watched wallet
/// shows no headline rather than a flat line.
struct WalletBalanceHeadline: View {
    /// The live total from the holdings read — the most current number the app
    /// knows, and the ONLY one on a first run (2026-07-21, prd §155). The line
    /// below is sampled at most every four hours, so before this the crown
    /// number simply didn't exist for the first four hours of watching: the
    /// headline waited on a chart that waits on a second sample. The total is
    /// real from the first holdings read; it leads, and the line joins it when
    /// there's a line to draw.
    let total: Double?
    /// The sampled line for the chosen window — nil until two samples fall
    /// inside it.
    let chart: TokenChart?
    /// Transactions that landed inside the window (prd §155) — punctuation on
    /// the line, each one a door to its own sheet.
    var marks: [TokenChartMark] = []
    /// "Across your wallets" on the combined view; scoped, the WALLET'S OWN NAME
    /// (prd §450) — which is why the rail above it no longer captions its faces.
    var caption: String = String(localized: "Balance")
    /// The scoped wallet's address, when `caption` is naming one rather than
    /// describing the reading (prd §450). Draws its face at `DS.Face.badge` —
    /// the ramp's own "a mark beside dense inline text" tier — before the words,
    /// which is what ties the ringed face in the rail above to the name here.
    /// nil on the combined view, where there is no one face to draw.
    var captionAddress: String? = nil
    /// The address tail beside the name ("…4f4f"), in the quieter ink. Kept
    /// apart from `caption` rather than pre-joined into it so the two can be
    /// weighted differently — the name is the identity, the tail is the proof —
    /// and so a wallet with no name at all can spend the whole line on its
    /// address instead of repeating it.
    var captionDetail: String? = nil
    /// Whether an empty `caption` collapses instead of reserving its row.
    ///
    /// The caption is normally always present, so its `HStack` could hold the
    /// layout unconditionally. The wallet room's unscoped Home has no caption
    /// at all now (prd §483 — the rail's lit "All" says it), and an empty
    /// `Text` still draws a line box, so without this the room shows a gap
    /// where the words used to be.
    var hidesEmptyCaption: Bool = false
    /// "Mostly ETH · +$310" — WHY the line moved, from the same per-token
    /// snapshots the combined sheet's "What moved" reads. nil when the record
    /// can't attribute the move yet.
    /// WHY it moved, in the quietest ink on the screen.
    ///
    /// Nil in the wallet room since 2026-08-26 (prd §483, *"remove … 'mostly
    /// eth'"*): it was a third line under a figure that already had two, and
    /// the Holdings scope one tap away answers the same question properly.
    /// Kept as a parameter because the token rooms still use it.
    var mover: String? = nil
    /// Whether the LINE is drawn.
    ///
    /// False in the wallet room's non-Home scopes (prd §483), where another
    /// visual takes the line's place directly below — so the crown keeps its
    /// figure, its move line and its range, and gives up only the plot and the
    /// range chips.
    ///
    /// **It suppresses the DRAWING, never the chart itself, and that
    /// distinction cost a build.** Passing `chart: nil` instead read as "no
    /// reading has landed": the total falls back to `chart?.price` when the
    /// portfolio read is unavailable — which is every demo and every offline
    /// launch — so the crown showed **$0** in every scope but Home, under a
    /// sentence explaining that the line had not started yet. Both were true of
    /// the parameter and neither was true of the wallet.
    var drawsChart: Bool = true
    /// Whether the FIGURE and its move line draw.
    ///
    /// False in the wallet room's non-Home scopes (prd §483, user: *"on
    /// activity, we don't need the value, just show the sankey"*). Every scope
    /// owns one drawing; on Home that drawing is the balance and its line, and
    /// elsewhere the balance would be a second, louder answer sitting on top of
    /// the one you actually asked for.
    ///
    /// The total is one tap away on Home in every case, so nothing is lost that
    /// is not immediately recoverable — and the room stops claiming a figure
    /// belongs to a treemap or a flow band that does not produce it.
    var drawsReading: Bool = true
    /// How tall the line draws.
    ///
    /// Shorter in the wallet room than the 120 it shipped at (user ruling, prd
    /// §483: *"ideally the three transactions would show without user having to
    /// scroll. we should shorten the area we devote to sparkline"*). The line's
    /// job on Home is to say which way and roughly how far, and it does that at
    /// 96 as well as at 120 — the 24pt buys a third transaction row above the
    /// fold, which is the thing the room is actually opened for.
    var chartHeight: CGFloat = 120
    /// The windows this history can honestly answer; fewer than two draws no
    /// chips (a lone chip is a dead control).
    var ranges: [WalletRange] = []
    var range: WalletRange = .watched
    var onPickRange: (WalletRange) -> Void = { _ in }
    /// nil = no door: with one wallet (or scoped to one) the number has no
    /// further breakdown to show — the treemap below IS the composition, so a
    /// chevron here would open nothing new. Only the multi-wallet "All" view
    /// gets the combined-breakdown sheet behind it.
    let onOpen: (() -> Void)?
    /// Drawn on a SATURATED card rather than the room's ink (2026-08-15, the
    /// wallet's half of the bright-card pass). The whole text ramp is handled
    /// by the caller pinning `colorScheme` — every token here is adaptive — so
    /// what this flag owns is the two things a scheme flip cannot fix.
    ///
    /// **The line goes white, and direction moves to the pill.** The plot's
    /// accent is the state colour, and on a saturated ground the DOWN case
    /// fails: system red on the app tint measures about 1.35:1, so a losing
    /// day would draw a line nobody can see — the failure would appear only on
    /// the days that matter most, and a rising day would look fine in every
    /// screenshot. White holds on any hue in the table, and the delta pill
    /// beside the number still states the direction in colour, so nothing is
    /// lost but the redundancy.
    var onColor: Bool = false
    var onOpenMark: (UUID) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ShellChrome.self) private var chrome
    /// MONEY THAT REALLY ARRIVED (prd §501) — the room's half of the fence.
    ///
    /// **Observed with `onChange` and never on appear, which IS fence 4.** A
    /// pulse raised while this room was closed reaches nobody and is not
    /// replayed: the rain is a moment, and a moment you were not there for is
    /// missed rather than owed. Doing it this way means "a sync you are
    /// present for" needs no scene-phase test anywhere — the only view that
    /// can react is one that is on screen.
    ///
    /// It lives on the crown rather than on the room because the crown is the
    /// one view present in every wallet scope, and because the rain's hue is
    /// the receiving wallet's own face stop, which is this file's vocabulary.
    @State private var arrivals = WalletArrival.shared
    /// The sparkline's draw-on: 0 → 1 sweeps a mask left to right, so the
    /// line draws itself the way the value accrued — time, moving. Reset
    /// whenever the data itself changes (a scope switch is a new line, and
    /// a new line deserves its own draw).
    @State private var drawn: CGFloat = 0
    /// Mac hover-scrub (delight, 2026-08-03): the sample under the cursor.
    /// While set, the crown number ROLLS to that sample (the same
    /// `numericText` roll a scope switch already plays) and the plot draws
    /// the scrub cursor; leaving rolls it back to the live total. Written by
    /// the Mac's hover AND (2026-08-03, prd §297) by a press-then-drag on the
    /// phone — the sheet chart's own touch scrub, brought to the room's
    /// headline. It was Mac-only for two days, which meant this plumbing sat on
    /// every device and answered only a cursor.
    @State private var scrubIndex: Int?
    /// The crown number's odometer roll (prd §297) — `GenMoneyHero`'s entrance
    /// arriving in the room the hero was modelled on.
    ///
    /// The anchor is held rather than the destination, and `rollLanded` says
    /// which one to show. That way the roll can never PIN the number: the
    /// instant it lands, `displayed` reads the live total again, so a holdings
    /// read arriving mid-entrance reaches the screen on its own. (Holding the
    /// destination instead needed a fourth timer to clear it, which is how the
    /// first cut of this got an unstructured `Task` that outlived its view.)
    @State private var rollAnchor: Double?
    @State private var rollLanded = false
    /// The delta pill waits out the roll — a summary that lands with the thing
    /// it summarizes makes the eye choose, and it chooses wrong (2026-07-22).
    @State private var pillShown = false
    @State private var entered = false

    private var accent: Color {
        onColor ? .white
                : TokenChartStyle.accent(change: chart?.change ?? 0, scheme: scheme)
    }

    /// The number in the headline seat: the live total when the holdings read
    /// has landed, else the last sampled value. nil renders nothing at all —
    /// the caller's own guard, kept here too so this view can't paint a $0
    /// portfolio it doesn't know about. A Mac cursor scrubbing the line
    /// temporarily shows the hovered sample instead — one number, one place,
    /// the sheet chart's own rule.
    private var displayed: Double? {
        if let scrubIndex, let chart, chart.closes.indices.contains(scrubIndex) {
            return chart.closes[scrubIndex]
        }
        if !rollLanded, let rollAnchor { return rollAnchor }
        return total ?? chart?.price
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            // Only the reading is a door — the chips and the marks below are
            // their own controls, so the tappable region stops at the number.
            //
            // A door-less reading is NOT a disabled button (fixed 2026-07-21,
            // caught on screen): `.disabled` dims a plain button's whole label,
            // so with one wallet watched — no breakdown, no door — the crown
            // number rendered grey instead of white, and the room's loudest
            // element was its faintest. The honesty corollary the design law
            // already states for backgrounds, applied to ink: when there's no
            // action, don't render a control at all.
            if drawsReading {
                if let onOpen {
                    Button(action: onOpen) {
                        reading.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    reading
                }
            }

            if let chart, drawsChart {
                // Taller, heavier, and ending on a solid dot (prd §157) — the
                // line is the total said a second way, so it carries weight
                // like the total does.
                // Body in the STROKE, not the fill (measured on screen
                // 2026-07-21): a portfolio line is nearly flat most weeks, so
                // it hugs the top of its box and a 0.30 fill under it paints a
                // solid slab rather than a glow. 2.6pt of line reads as
                // confidence; a heavy fill just reads as a rectangle.
                // THE CHART IS THE ROOM'S BIGGEST ELEMENT (2026-08-16, the
                // Apple redraw): 52 → 170. For Stocks the chart IS the
                // product, and this room had its best asset drawn as a
                // garnish under the number. The fill rises with it (0.16 →
                // 0.24): the 2026-07-21 note below measured a heavy fill as a
                // "solid slab" — true at 52pt, where a nearly-flat portfolio
                // line hugs the top of its box; at 170 there is real height
                // beneath the line for a gradient to fall through, which is
                // the shape Stocks draws and the reason the taller plot needs
                // it (a 170pt box with a hairline of fill reads as empty).
                //
                // 170 → 120 (2026-08-18, user ruling): the height is spent
                // BUYING the room's newest transactions a place above the
                // fold (`FeedScreen.walletTodaySection`). The chart is still
                // the room's biggest element and every reason above survives
                // at 120 — a nearly-flat line still has real height under it
                // for the fill to fall through, which was the only thing 52
                // could not give. What it can no longer be is the whole first
                // screen: a wallet's transactions sat behind ten standing
                // cards, and the fix is a shorter hero rather than a folded
                // room (Options A and B, both declined).
                TokenChartPlot(chart: chart, accent: accent, height: chartHeight, pulses: false,
                               lineWidth: 2.6, fillOpacity: 0.24, endpointDot: true,
                               marks: marks,
                               onTapMark: marks.isEmpty ? nil : { onOpenMark($0.id) },
                               // Wait out the draw-on below, then land (§171).
                               markDelay: 0.95,
                               // Scrub (2026-08-03, §297): a press-then-drag —
                               // or a resting cursor on the Mac — rolls the
                               // crown number to that sample. The sheet
                               // chart's own scrub, at the headline's dose.
                               cursorIndex: scrubIndex,
                               onScrub: { scrubIndex = $0 })
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * drawn)
                        }
                    }
                    // Two entrances, two owners: `draw` owns the line's own
                    // mask and replays on a range switch; `enter` owns the
                    // number's roll and fires once ever.
                    .onAppear { draw(); enter() }
                    .onChange(of: chart.closes) { draw(redraw: true) }
                    .padding(.top, DS.Space.s1)
                if ranges.count > 1 { rangeChips }
            } else if chart == nil {
                // No line yet — say why, rather than leaving the number
                // hanging over empty space. The total above it is already
                // real; this is only about the SHAPE not existing yet.
                //
                // `chart == nil` rather than `else`: a scope that deliberately
                // hands its slot to another drawing has a chart and simply is
                // not showing it, so explaining an absence there would describe
                // a line that exists.
                Text("The line starts once a second reading lands.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    /// The reading itself — caption, total, delta, and why it moved. Rendered
    /// bare or inside a Button depending on whether there's anything behind a
    /// The caption's words — one `Text` when it describes the reading, two
    /// concatenated when it NAMES a wallet (prd §450).
    ///
    /// **Two weights, and §157's ruling survives both.** That note says the
    /// caption "steps back so the number can step forward", and it is right
    /// about a label: "Across your wallets" is chrome and stays tertiary. A
    /// NAME is not chrome — it is the answer to "which wallet am I looking
    /// at?", and at tertiary it would be the faintest thing about the wallet it
    /// identifies. So the name takes semibold at `textSecondary`, one step up
    /// and still a long way under a 48pt total, while the address tail beside
    /// it stays tertiary. The gap the ruling protects is between the number and
    /// this line, and it is intact.
    ///
    /// `scaledFont` rather than `dsText`, because a concatenated `Text` needs
    /// `Text`'s own `.font(_:)` overload to stay `Text`-typed — the exact case
    /// that property exists for, so this is still the ramp and still Dynamic
    /// Type.
    private var captionText: Text {
        let name = Text(caption)
            .font(DSTextStyle.label12.scaledFont)
            .fontWeight(captionAddress == nil ? .medium : .semibold)
            .foregroundStyle(captionAddress == nil ? DS.textTertiary : DS.textSecondary)
        guard let captionDetail else { return name }
        return name + Text(verbatim: " · \(captionDetail)")
            .font(DSTextStyle.label12.scaledFont)
            .foregroundStyle(DS.textTertiary)
    }

    /// tap; identical either way.
    private var reading: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
                    if !(hidesEmptyCaption && caption.isEmpty && captionAddress == nil) {
                    HStack(spacing: 5) {
                        // The scoped wallet's own face, at the ramp's badge
                        // tier (prd §450). The rail above rings the picked
                        // face and says nothing else; this is what carries
                        // that identity down to the name, so the two read as
                        // one answer rather than as a ring and a coincidence.
                        if let captionAddress {
                            WalletFace(address: captionAddress,
                                       size: DS.Face.badge, circular: true)
                        }
                        captionText
                            .lineLimit(1)
                        // The door — only where a breakdown exists (the multi-
                        // wallet "All" view). A chevron promises more behind
                        // the tap.
                        if onOpen != nil {
                            Image(systemName: "chevron.right")
                                .dsGlyph(10)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    }
                    // The app's money voice ($19.9K), not a token price — this is
                    // a portfolio total, and `WalletValue.money` is what the
                    // combined sheet and the wallet row sublines already speak
                    // (`TokenStats.compact` behind the §374 privacy gate; a
                    // view never calls that formatter directly).
                    // The digits ROLL between values (a scope switch re-keys the
                    // number, and $20K odometer-rolling to $4.2K says "same
                    // instrument, new reading"). Direction rides the value, so
                    // the roll runs the way the money moved. `price48` is the
                    // ramp's crown rung — the biggest figure on its surface —
                    // so it scales with Dynamic Type like everything else.
                    // (This comment said `price40` while the line below drew
                    // `price48`; corrected 2026-08-28. The rung named in prd
                    // §102 is price40, and §157 added price48 above it for
                    // exactly this number.)
                    Text(WalletValue.money(displayed ?? 0))
                        .dsText(.price48).foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity
                                           : .numericText(value: displayed ?? 0))
                        // **0.9, not 0.6 (prd §548c).** §491 set vibenet's
                        // floor here after its crown rendered at about 55% of
                        // this one; the cause was named as the floor and then
                        // fixed on one side only, leaving THIS crown free to
                        // shrink to 38pt on a long total while declaring the
                        // same rung. `WalletValue.money` abbreviates ($31K),
                        // so the string is short by construction and the tight
                        // floor costs nothing — and a crown that silently
                        // renders two rungs down is not the crown rung,
                        // whatever the source says.
                        .lineLimit(1).minimumScaleFactor(0.9)
                        // HOLD TO PEEK (prd §501) — nothing at all unless
                        // balances are hidden; see `HoldToPeek`.
                        .holdToPeek()
                    // DIRECTION AS A SENTENCE, not a pill (2026-08-16, the
                    // Apple redraw). Apple Card and Stocks both state the move
                    // in words under the figure — and the sentence carries what
                    // the pill structurally could not: the DOLLARS as well as
                    // the percent. The dollar move is last-minus-first over the
                    // very series the line draws, so the words and the curve
                    // can never disagree; the window name it is measured over
                    // stays, in the quiet ink. §83 holds through
                    // `TokenChartStyle.isFlat`: a move that rounds to nothing
                    // gets no arrow, no colour and no claim.
                    if let chart {
                        moveLine(chart, upTo: scrubIndex)
                            .opacity(pillShown ? 1 : 0)
                    }
                    if let mover {
                        // WHY it moved, in the quietest ink on the screen: the
                        // headline states the reading, this states its cause.
                        Text(mover)
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
        .frame(maxWidth: .infinity, alignment: .leading)
            // THE RAIN, WHERE THE MONEY LANDED (prd §501). Nothing new is
            // drawn: this is the shower a pull-to-refresh already deals,
            // poured in the receiving wallet's own face stop so the moment
            // says WHICH account without a word.
            .onChange(of: arrivals.pulse) { _, _ in
                guard let address = arrivals.address else { return }
                chrome.refreshHue = WalletFace.tint(for: address)
                chrome.refreshPulse += 1
            }
    }

    /// "▲ $224.51 (1.8%) today" — the move stated the way Apple states it.
    ///
    /// The dollars come from the plotted series (last − first), never from a
    /// second source: the line is what the reader is looking at, so any other
    /// derivation could contradict it on screen. Gated through
    /// `WalletValue.exactMoney`, so §374 hides the figure here exactly as it
    /// hides the total above — a privacy control that covered the crown and
    /// left the delta legible would be no control at all.
    ///
    /// **WHILE SCRUBBING IT DESCRIBES THE SCRUBBED SAMPLE (prd §501).** The
    /// scrub has rolled the figure above to a past reading since §297, and
    /// this line went on stating the whole window's move — so a finger halfway
    /// down the line put a number from Tuesday over a sentence about today,
    /// one line apart. Two readings of two different moments, both true, and
    /// nothing on screen saying they were not the same one.
    ///
    /// The scrubbed form is the move from the window's FIRST sample to the one
    /// under the finger, which is the same measurement the resting line makes
    /// with a different end point — so no second derivation exists to disagree
    /// with the first, and it needs no data the plot does not already hold.
    /// Percent is recomputed from the same pair for the same reason.
    @ViewBuilder
    private func moveLine(_ chart: TokenChart, upTo scrub: Int? = nil) -> some View {
        let end = scrub.map { min(max($0, 0), chart.closes.count - 1) }
        let first = chart.closes.first ?? 0
        let last = end.map { chart.closes[$0] } ?? (chart.closes.last ?? 0)
        // The scrubbed percent, or the chart's own when at rest — never
        // recomputed at rest, so the resting line is byte-identical to what
        // it has always drawn.
        let change = end == nil ? chart.change
            : (first == 0 ? 0 : (last - first) / abs(first) * 100)
        let flat = TokenChartStyle.isFlat(change)
        let delta = last - first
        let ink = flat ? DS.textSecondary
                       : TokenChartStyle.accent(change: change, scheme: scheme)
        HStack(spacing: 5) {
            if !flat {
                Image(systemName: change >= 0 ? "arrowtriangle.up.fill"
                                              : "arrowtriangle.down.fill")
                    .dsGlyph(9)
                    .foregroundStyle(ink)
            }
            Text(flat
                 ? String(localized: "No change")
                 : "\(WalletValue.exactMoney(abs(delta))) (\(TokenChartStyle.changeText(change)))")
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(ink)
                .monospacedDigit()
            // THE WINDOW WORD IS GONE (user ruling, prd §483: *"remove
            // 'watched'"*). It named the range the delta was measured over —
            // true, and the range chips directly below already say it, so the
            // line was spending its width restating the control beneath it.
            Spacer(minLength: 0)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    /// The window chips — the token chart's own grammar, at the wallet's dose.
    /// Only drawn with a real choice to make (see `WalletRange.offered`).
    private var rangeChips: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach(ranges, id: \.self) { r in
                Button {
                    guard r != range else { return }
                    DSHaptic.tap()
                    onPickRange(r)
                } label: {
                    // STOCKS' SEGMENTED BOX (2026-08-16, the Apple redraw) —
                    // the chips share one recessed track and the selected one
                    // is a raised tile inside it, rather than a lone capsule
                    // floating in space. It also retires the white-pill
                    // variant this control carried for one day: there is no
                    // saturated ground left under it to need one.
                    Text(r.rawValue)
                        .dsText(.label12)
                        .fontWeight(r == range ? .semibold : .regular)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(r == range ? DS.textPrimary : DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        // Concentric with the track below (prd §412): the
                        // segment's corner is the track's minus the 3pt inset,
                        // so the gap around it stays even through the bend
                        // rather than swelling at each corner. Was the literal
                        // 7 — the same arithmetic, done once by hand and with
                        // nothing tying it to the track it belongs to.
                        .background(r == range ? DS.fillStrong : .clear,
                                    in: RoundedRectangle(
                                        cornerRadius: DS.Radius.nested(
                                            parent: DS.Radius.card, inset: 3),
                                        style: .continuous))
                }
                .buttonStyle(PressSpring())
            }
        }
        .padding(3)
        .dsWell()
        .padding(.top, DS.Space.s2)
    }

    private func draw(redraw: Bool = false) {
        guard !reduceMotion else { drawn = 1; return }
        if redraw { drawn = 0 }
        withAnimation(.easeOut(duration: 0.8).delay(redraw ? 0.05 : 0.25)) { drawn = 1 }
    }

    /// The room's headline gets the brief's own arc (prd §297): the line draws,
    /// the total rolls from where the window STARTED to what it is now, then
    /// the pill lands. `GenMoneyHero` has staged exactly this since 2026-07-22
    /// — inside the Today brief, which most people never open — while the
    /// wallet room, whose number this actually is, drew its line and left the
    /// total sitting there already arrived.
    ///
    /// The anchor is the window's own first sample, so the roll says the true
    /// thing: this is what it was when this line began, and this is what it is.
    /// A window with nothing to travel (one sample, a flat week, no chart at
    /// all) rolls nothing and simply lands its pill — the honest static case,
    /// same guard `fireEntrance` keeps.
    private func enter() {
        guard !entered else { return }
        entered = true
        let anchor = chart?.closes.first
        guard !reduceMotion, let anchor, let now = total ?? chart?.price,
              anchor > 0, abs(now - anchor) / anchor > 0.001
        else {
            rollLanded = true
            withAnimation(DS.Motion.standard.delay(0.35)) { pillShown = true }
            return
        }
        // Both beats are issued NOW as delayed animations — no timer, nothing
        // to cancel, and nothing capturing this view past its own life. The
        // same staging `WalletFlowBand` and `UniswapRangeBar` use.
        rollAnchor = anchor
        withAnimation(ChartEntrance.roll.delay(ChartEntrance.rollStart)) { rollLanded = true }
        withAnimation(ChartEntrance.pillLand.delay(ChartEntrance.pillStart)) { pillShown = true }
    }
}

/// Worth a look — the security read, as a STRIP inside the balance card's own
/// bottom edge (prd §212, 2026-07-25, superseding §196's card and §146's line
/// before it).
///
/// The ledger here is a pendulum: §146 made it a line because a permanent
/// half-width card reserved prominent space for warnings usually absent; §196
/// gave the card back because a badge row per kind reads faster than a run-on
/// caption and needed somewhere to live. Both were arguing about the same
/// missing thing — WHERE it belongs. It belongs to the balance: "what's it
/// worth" and "is it okay" are the two questions one glance asks, and they
/// were being answered by two separate parcels of equal weight.
///
/// So the badges retire and their counts come back as words on one subline —
/// `WalletWatch.summary` is the SAME shared per-kind tally the badges read, so
/// nothing is lost but the capsules. It renders only when `warnings` isn't
/// empty (§146's floor, still right), and its whole surface is a faint fill
/// inside the card, not a card of its own.
///
/// Title is always "Worth a look" (user, 2026-07-23: "we don't know if it
/// needs attention, do we?") — the old critical-only "Needs attention" wording
/// claimed an urgency nothing here actually tracks (no push, no countdown; a
/// spoofed transfer already happened and isn't getting worse by the time you
/// open the feed).
///
/// COLOR IS SPENT ON WHAT'S ACTIONABLE NOW (2026-07-24, the Act/Aware
/// reframe) — not on raw severity. Severity alone made a wallet's routine
/// spam (poisoning, spoofed symbols — already happened, nothing to do) wear
/// the same red as a live approval that can still drain it, so a whale
/// wallet's permanent dozen airdrops crying-wolfed the card red forever.
/// `isMuted` lets a person who's recognized the spam say so; muted kinds drop
/// out of both the mark's color and the subline entirely, so it can go quiet.
struct WalletWarningsStrip: View {
    let warnings: [WalletWarning]
    let onOpen: () -> Void

    /// What the strip actually shows — every kind when unmuted, only the
    /// actionable ones once the awareness pile is muted. Never severity
    /// alone; `isActionable` is the axis now.
    private var visible: [WalletWarning] {
        WalletAwareness.isMuted ? warnings.filter { $0.kind.isActionable } : warnings
    }

    var body: some View {
        if !visible.isEmpty {
            let hasLiquidation = visible.contains { $0.kind == .liquidation }
            let hasActionable = visible.contains { $0.kind.isActionable }
            // Red only for the one genuinely time-sensitive thing (a position
            // about to liquidate); orange for anything else actionable; plain
            // secondary ink when all that's left unmuted is the aware pile —
            // spam alone earns no alarm color at all.
            let tint: Color = hasLiquidation ? DS.destructive
                : hasActionable ? DS.attention : DS.textSecondary
            Button(action: onOpen) {
                WalletRow(mark: .symbol(hasLiquidation || hasActionable
                                        ? "exclamationmark.triangle.fill" : "info.circle.fill",
                                        tint: tint),
                          title: String(localized: "Worth a look"),
                          subtitle: WalletWatch.summary(visible))
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, 2)
                    .dsWell(cornerRadius: DS.Radius.widget)
            }
            .buttonStyle(PressSpring())
        }
    }
}

/// IN PROTOCOLS — the money the crown number doesn't count, inside the
/// balance card (prd §240, 2026-07-31).
///
/// The reasoning for a composition rather than a bigger total lives on
/// `WalletComposition`; this is only its shape. Three things it does on
/// purpose:
///
/// - **It states, it doesn't relate.** No "not counted above", no "+". The
///   holdings read falls back from Zerion to Alchemy on a bad day, and
///   Alchemy hands back aTokens as plain tokens, so any claim about what the
///   crown does or doesn't include would go false exactly when the network is
///   worst. Rows that merely state a fact stay true on every path.
/// - **Locked wears its own unit.** "12,977 AERO", never a dollar — pricing a
///   four-year lock at spot is the accounting opinion the whole ruling
///   refused, so the strip declines to have one.
/// - **A chevron only where something is behind it** (2026-07-31). Deposited
///   and Locked open trays; Owed does not, and that asymmetry is the honest
///   shape rather than an inconsistency. The Lending card further down the
///   room already states health per protocol, so a debt tray would be prd
///   §208's exact mistake — a door onto a page that repeats the card beneath
///   it. Deposited and Locked have no such card for Hyperliquid or Aerodrome,
///   which until this pass had no seat anywhere in the app. Same conditional
///   door `WalletBalanceHeadline` already keeps for its own number.
///
/// It sits under the face chips rather than above them: the chips decompose
/// the number they sit beneath, so they stay welded to it, and this is a
/// different register — not "whose is that number" but "what else is there".
struct WalletCompositionStrip: View {
    let composition: WalletComposition
    /// Both nil-able so this view stays usable as a pure read wherever a
    /// caller has nowhere to route (the honesty rule's own corollary: don't
    /// render a control that opens nothing).
    var onOpenDeposits: (() -> Void)? = nil
    var onOpenLocks: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The section's ONE READING (2026-08-15, wallet cohesion pass): the
    /// deposited money when any exists, else the locked units in their own
    /// native voice — never Owed, because a debt in display type is an alarm
    /// this row already refuses to raise ("a debt you opened on purpose isn't
    /// an alarm", the minus-sign note below). The promoted row DROPS its
    /// trailing value so the figure is said once (§213's tally rule): the row
    /// keeps its places and its door, the reading carries the number.
    private var reading: (text: String, promotes: String)? {
        if composition.hasDeposited {
            return (WalletValue.money(composition.deposited), "Deposited")
        }
        if composition.hasLocked { return (lockedValue, "Locked") }
        return nil
    }

    /// The borrowed share of what is deposited, 0…1, or nil when there is
    /// nothing to take a share OF.
    ///
    /// Clamped at 1 because the two figures come from different protocol
    /// reads and a debt read that lands while its collateral read didn't
    /// would otherwise draw a bar past the end of its own track.
    private var borrowedShare: Double? {
        guard composition.hasOwed, composition.deposited > 0 else { return nil }
        return min(1, composition.owed / composition.deposited)
    }

    var body: some View {
        if !composition.isEmpty {
            // **COLUMNS ON A BASELINE — deposits up, debt down** (user pick of
            // three, prd §493). It replaced a figure and a list of places,
            // which was *"more words than graphics"* over a list that says the
            // same places again one scroll below.
            //
            // The baseline is what earns it: every other shape states debt as
            // ONE total, and a total cannot say WHICH place is levered. Here a
            // column's tail below the line is that protocol's own borrowing,
            // so "Aave is carrying most of it" is read rather than computed.
            //
            // Locked stands apart as an OUTLINE with no height claim — §240
            // rule 2, locked money is never priced, so drawing it to scale on
            // a dollar axis would put a made-up number on the chart.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(WalletValue.money(composition.deposited))
                        .dsText(.stat24).foregroundStyle(DS.textPrimary)
                        .monospacedDigit().lineLimit(1).fixedSize()
                    Text(subtitle)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                GeometryReader { geo in
                    columns(width: geo.size.width)
                }
                .frame(height: Self.chartHeight)
                .padding(.top, DS.Space.s2)
            }
            .padding(.horizontal, DSRoomChassis.inset)
            // One spoken sentence — a row of columns reads as nothing (§299).
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(spoken))
        }
    }

    /// "at work · $2,100 borrowed" — what the figure beside it does not say.
    /// The borrowed clause is DROPPED when there is none rather than reading
    /// "$0 borrowed", which is a card apologising for being fine.
    private var subtitle: String {
        guard composition.hasOwed else { return String(localized: "at work") }
        return String(localized: "at work · \(WalletValue.money(composition.owed)) borrowed")
    }

    /// The chart's own height inside the fixed slot, leaving the figure its
    /// line and the labels theirs.
    private static let chartHeight: CGFloat = 150
    /// Where the zero line sits within that height — deposits above, debt
    /// below. Not centred: most wallets borrow far less than they deposit, so
    /// an even split wastes half the chart on a tail that never reaches it.
    private static let baseline: CGFloat = 96
    /// How far below the line a debt tail may reach. Capped rather than sharing
    /// the deposit scale outright, so the label strip has a fixed home and a
    /// wallet borrowing nearly all of its deposit cannot push the names off the
    /// bottom of the slot.
    private static let debtSpan: CGFloat = 32
    /// How many places the chart draws before folding. Four columns at 402pt
    /// leave each about 72pt, which is the width a name needs.
    private static let columnCap = 4

    /// One column per place: deposited above the line, borrowed below it.
    ///
    /// **Both halves scale against the DEPOSIT maximum**, never their own — a
    /// debt sized against the largest debt would draw a wallet's only small
    /// borrowing as tall as its largest deposit, which is the opposite of the
    /// reading. One axis, so the two halves are comparable.
    @ViewBuilder
    private func columns(width: CGFloat) -> some View {
        let places = Array(composition.deposits.prefix(Self.columnCap))
        let owedBy = Dictionary(composition.debts.map { ($0.place, $0.usd) },
                                uniquingKeysWith: +)
        let peak = max(1, places.map(\.usd).max() ?? 1)
        let hasLocks = composition.hasLocked
        let slots = places.count + (hasLocks ? 1 : 0)
        let step = width / CGFloat(max(1, slots))
        let barWidth = max(18, step - DS.Space.s3)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(DS.fillLine)
                .frame(height: 1)
                .offset(y: Self.baseline)
            // **EVERY LABEL ON ONE BASELINE, whether its column has debt or
            // not.** They hung off the bottom of each column at first, so a
            // place with a debt tail carried its name ~20pt lower than a place
            // without one — four names at two heights, which reads as two rows
            // of labels rather than one axis. The label strip is its own layer
            // pinned under the deepest possible tail.
            ForEach(Array(places.enumerated()), id: \.element.id) { index, deposit in
                let up = max(4, CGFloat(deposit.usd / peak) * (Self.baseline - 16))
                let owed = owedBy[deposit.place] ?? 0
                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.tint.opacity(1 - Double(index) * 0.18))
                        .frame(width: barWidth, height: up)
                    if owed > 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.attention.opacity(0.85))
                            .frame(width: barWidth,
                                   height: max(3, CGFloat(owed / peak) * Self.debtSpan))
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, Self.baseline - up)
                .offset(x: CGFloat(index) * step)
            }
            // **LOCKED IS A MARK, NOT A COLUMN** (§240 rule 2: locked money is
            // never priced). Drawn at the baseline as a small dashed square
            // rather than a full-height outline — at column height it read as a
            // fifth bar you could compare to the others, which is the one thing
            // an unpriced holding must not invite.
            if hasLocks {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(DS.fillStrong,
                                  style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                    .frame(width: min(barWidth, 26), height: 26)
                    .padding(.top, Self.baseline - 26)
                    .offset(x: CGFloat(places.count) * step)
            }
            // The names, one strip, one height.
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(places.enumerated()), id: \.element.id) { _, deposit in
                    Text(deposit.place)
                        .dsText(.label11).foregroundStyle(DS.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: barWidth, alignment: .leading)
                        .frame(width: step, alignment: .leading)
                }
                if hasLocks {
                    Text(String(localized: "Locked"))
                        .dsText(.label11).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .frame(width: step, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Self.baseline + Self.debtSpan + DS.Space.s2)
        }
    }

    /// The chart as one sentence, in the order it draws.
    private var spoken: String {
        let owedBy = Dictionary(composition.debts.map { ($0.place, $0.usd) },
                                uniquingKeysWith: +)
        let listed = composition.deposits.prefix(Self.columnCap).map { deposit -> String in
            let owed = owedBy[deposit.place] ?? 0
            return owed > 0
                ? String(localized: "\(deposit.place), \(WalletValue.money(deposit.usd)), \(WalletValue.money(owed)) borrowed")
                : String(localized: "\(deposit.place), \(WalletValue.money(deposit.usd))")
        }.joined(separator: "; ")
        return String(localized: "\(WalletValue.money(composition.deposited)) at work. \(listed).")
    }


    /// A section label, optionally a door.
    @ViewBuilder
    private func eyebrow(_ title: String, onOpen: (() -> Void)? = nil) -> some View {
        let line = HStack(spacing: 4) {
            Text(title)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .dsGlyph(9)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        if let onOpen {
            Button(action: onOpen) { line.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            line
        }
    }

    /// One place: what it is on the left, how much on the right. `callout15`
    /// under a 40pt figure for `line`'s old reason — a row-weight title here
    /// would argue with the figure instead of supporting it.
    @ViewBuilder
    private func placeRow(_ title: String, _ value: String,
                          onOpen: (() -> Void)? = nil) -> some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(title)
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Text(value)
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .dsGlyph(9)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, 3)
        if let onOpen {
            Button(action: onOpen) { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    /// "12,977 AERO · 340 HYPE" — the locked total per UNIT. Individual locks
    /// live in the tray; here they merge, because a sum of AERO is still AERO
    /// (a sum of end dates would be nothing, which is why the tray exists).
    private var lockedValue: String {
        composition.lockedTotals
            .map { WalletValue.token($0.amount, $0.symbol) }
            .joined(separator: " · ")
    }

    /// `callout15`, not `WalletRow`'s `heading17`: these sit INSIDE the
    /// balance card under a 48pt number, and a row-weight title here would
    /// argue with the crown instead of supporting it. Same reasoning that
    /// stepped the headline's own caption back (prd §157).
    @ViewBuilder
    private func line(title: String, places: [String], value: String,
                      onOpen: (() -> Void)?, melt: Double? = nil) -> some View {
        if let onOpen {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    lineBody(title: title, places: places, value: value, door: true)
                    if let melt {
                        ShareBar(fraction: melt, melt: true, reduceMotion: reduceMotion)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            lineBody(title: title, places: places, value: value, door: false)
        }
    }

    private func lineBody(title: String, places: [String], value: String,
                          door: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if door {
                        Image(systemName: "chevron.right")
                            .dsGlyph(9)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                if !places.isEmpty {
                    // WHERE it is, in the quietest ink — the same job the
                    // headline's mover line does for the number above.
                    Text(places.joined(separator: " · "))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            // Empty when the reading above already carries this row's figure
            // — the row keeps its title, places and door, and says the number
            // zero more times.
            if !value.isEmpty {
                Text(value)
                    .dsText(.price16).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

/// What's behind "Deposited" (2026-07-31) — one row per protocol, and its
/// share of the deposited total as a bar.
///
/// For Aave, Morpho and Uniswap this is a shortcut to detail the room already
/// carries further down. For HYPERLIQUID it is the only view of the account
/// that exists anywhere in the app, which is what earns the door: the strip
/// states a number that, for two of its five contributors, nothing else on any
/// screen explains.
///
/// Rows are TERMINAL, per the Worth-a-look ruling (2026-07-20, "you can't have
/// worth a look pull up a sheet that then says to go look somewhere else").
/// Acting on a position happens on Aave or Hyperliquid; there is no second hop
/// from here, so no row carries a chevron.
struct WalletDepositsTray: View {
    let composition: WalletComposition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSTray(title: String(localized: "Deposited"),
               height: min(560, CGFloat(206 + composition.deposits.count * 64))) {
            ScrollView {
                VStack(spacing: DS.Space.s1) {
                    // The tray's one figure, first (2026-08-15, wallet
                    // cohesion pass — the money receipt sheet's grammar,
                    // reading before rows). The rows then explain a number
                    // already stated instead of asking the reader to sum.
                    //
                    // `stat24`, not `heading28` (2026-08-28) — the same
                    // correction the locked tray below takes. `heading28` is
                    // the LEDE rung, sized for a SENTENCE, and a tray figure
                    // wearing it sat between `stat24` and `price40` matching
                    // neither, two taps from the crown at `price48`. The
                    // wallet's own composition strip a few hundred lines up
                    // has always drawn its figures at `stat24`.
                    Text(WalletValue.money(composition.deposited))
                        .dsText(.stat24).foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, DS.Space.s2)
                    // Enumerated for the entrance stagger only — the rows
                    // arrive in the order the model already sorted them, so
                    // the biggest deposit's bar grows first.
                    ForEach(Array(composition.deposits.enumerated()), id: \.element.id) { index, deposit in
                        row(deposit, index: index)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ deposit: WalletComposition.Deposit, index: Int) -> some View {
        let total = composition.deposited
        let share = total > 0 ? deposit.usd / total : 0
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                // The protocol's own mark (2026-08-04) — this tray names five
                // venues the app ships logos for and drew none of them.
                AssetMark(name: deposit.place, size: 22)
                Text(deposit.place)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(WalletValue.money(deposit.usd))
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                if total > 0 {
                    Text("\(Int((share * 100).rounded()))%")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .monospacedDigit()
                }
            }
            ShareBar(fraction: share, index: index, reduceMotion: reduceMotion)
        }
        .dsCompositionRow()
    }
}

/// What's behind "Locked" (2026-07-31) — the MELT.
///
/// A lock is time-shaped, not value-shaped, so this is the one place in the
/// wallet room that draws a position as a clock rather than an amount. veAERO
/// voting power decays linearly to zero at the lock's end, and the app already
/// reads both halves of that fact per veNFT: `locked().amount` and
/// `balanceOfNFT`. A real measured lock read 12,977 AERO against 5,342 votes —
/// about 41% of its power left on a 2028 end. Nothing in the app has ever
/// shown that, and no amount alone can.
///
/// Three honesty rules the bar keeps:
///
/// - **No dollars, anywhere.** Same rule as the strip: pricing an illiquid
///   lock at spot is the accounting opinion prd §240 refused.
/// - **A permanent lock gets a full bar and no date**, because it has no end
///   by definition — never a bar drawn at some invented fraction.
/// - **Staked HYPE gets NO bar.** It doesn't decay; it sits until its unlock.
///   Drawing it a melt would invent a mechanic Hyperliquid doesn't have, so a
///   HYPE row states its amount and its unlock date and stops.
struct WalletLocksTray: View {
    let composition: WalletComposition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSTray(title: String(localized: "Locked"),
               height: min(560, CGFloat(206 + composition.locks.count * 74))) {
            ScrollView {
                VStack(spacing: DS.Space.s1) {
                    // The tray's one figure, first — in NATIVE units, the
                    // strip's own no-dollars rule ("pricing an illiquid lock
                    // at spot is the accounting opinion §240 refused").
                    Text(composition.lockedTotals
                            .map { WalletValue.token($0.amount, $0.symbol) }
                            .joined(separator: " · "))
                        .dsText(.stat24).foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, DS.Space.s2)
                    ForEach(Array(composition.locks.enumerated()), id: \.element.id) { index, lock in
                        row(lock, index: index)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ lock: WalletComposition.Lock, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                // The locked TOKEN, not the venue: the venue is already on
                // this row's trailing edge, and AERO and HYPE are what the
                // amount beside it counts.
                AssetMark(name: lock.symbol, size: 22)
                Text(WalletValue.token(lock.amount, lock.symbol))
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(lock.place)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            if let remaining = lock.remaining {
                // THE MELT (2026-08-03, prd §297): the bar draws full, then
                // recedes to what's left. A lock's fact is that it HAD all its
                // power and is losing it — the only entrance that states the
                // mechanic instead of reporting a percentage.
                ShareBar(fraction: remaining, index: index, melt: true,
                         reduceMotion: reduceMotion)
            } else if lock.isPermanent {
                // Never melts, so it never draws melting — it grows like any
                // other full bar and stops (the tray's own third honesty rule).
                ShareBar(fraction: 1, index: index, reduceMotion: reduceMotion)
            }
            Text(subline(lock))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
        }
        .dsCompositionRow()
    }

    /// The whole state of the lock in one sentence — power left, then when it
    /// ends. Each clause drops out rather than guessing: a lock with no power
    /// read states only its date, and a lock with no date states only its
    /// power.
    private func subline(_ lock: WalletComposition.Lock) -> String {
        var parts: [String] = []
        if lock.isPermanent {
            parts.append(String(localized: "Permanent · never decays"))
        } else if let remaining = lock.remaining, let power = lock.power {
            parts.append(String(localized:
                // The vote weight is an AMOUNT and is gated; the percentage
                // beside it is a proportion of this lock's own maximum, which
                // says how far it has melted and nothing about how much is in
                // it — §374 hides amounts, not shapes.
                "\(WalletValue.number(power)) votes left · \(Int((remaining * 100).rounded()))%"))
        }
        if let until = lock.until {
            // Month and day, never a bare weekday — the Aerodrome date-format
            // bug (2026-07-30): a weekday alone is ambiguous for a date days
            // out, and read as if the end preceded the start.
            parts.append(String(localized: "Ends \(until.formatted(.dateTime.month().day().year()))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// The row surface both composition trays wear.
///
/// NOT `dsListCardRow()`, which every tray in this room reaches for by habit:
/// that modifier applies `listRowBackground`, a List-scoped modifier, and
/// `DSTray`'s content is a plain `VStack` — so inside a tray it silently
/// paints nothing (audited 2026-07-31, prd §241). The hover effect it also
/// carries does work, which is why the no-op went unnoticed.
private extension View {
    func dsCompositionRow() -> some View {
        padding(DS.Space.s3)
            .dsInkFill(cornerRadius: DS.Radius.widget)
            .dsHover()
    }
}

// `ShareBar` moved to `Design/ChartEntrance.swift` on 2026-08-03 (prd §297),
// where it grew its entrance — and its melt. It was private here while its only
// two users were the trays below; the composition strip's own inline melt now
// needs it too, and a bar shape that draws itself belongs with the rest of the
// grammar rather than beside the tiles that happened to want it first.

/// The per-wallet split, as CHIPS inside the balance card (prd §212,
/// 2026-07-25). It was a card of its own until this pass — a face, a name, a
/// total, an 80pt sparkline and a delta pill per wallet — which is a lot of
/// parcel for a question the combined number raises in passing ("fine, but
/// whose?").
///
/// What survives is what a glance actually reads off that card: whose, how
/// much, which way. The 80pt line doesn't survive, deliberately — at that
/// width it was decoration, and tapping a chip scopes the WHOLE feed to that
/// wallet, where the same line is drawn at full width as the room's headline.
/// So the read isn't lost, it's one tap away and bigger.
/// VENUES JOIN THE STRIP (2026-07-31). The crown number above has merged
/// connected exchange balances and staked-validator ETH since §163, but this
/// strip only ever decomposed watched wallets — so a setup whose main holding
/// sits on Coinbase read as a number with chips beneath it that quietly
/// accounted for a fraction of it. A venue chip differs in two ways, both
/// forced by what's true of a venue rather than chosen for looks: it wears its
/// NAME instead of a face (there's no address to derive one from), and it
/// carries NO delta (the value line is recorded per watched wallet, so a venue
/// has no history to difference — and a 0% pill would be a claim, not a
/// blank). It also isn't a button: the feed scopes by wallet address, so
/// tapping a venue could only ever do nothing (the dead-control rule).
struct WalletFaceChips: View {
    struct Entry: Identifiable {
        let id: String        // the address (or venue id) — stable, value-typed
        let value: Double
        /// nil where no honest delta exists — a venue with no recorded line.
        let change: Double?
        /// nil for a watched wallet, whose address IS its face; the venue's
        /// display name otherwise.
        var venueLabel: String? = nil
    }

    let entries: [Entry]
    let onPick: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Scrolls rather than wraps: the watch cap is 5, and five chips
        // wrapping to two rows inside the balance card would rebuild the
        // second parcel this replaced.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(entries) { entry in
                    chip(entry)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func chip(_ entry: Entry) -> some View {
        if entry.venueLabel == nil {
            Button {
                DSHaptic.selection()
                onPick(entry.id)
            } label: {
                capsule(entry)
            }
            .buttonStyle(.plain)
        } else {
            // A read, not a door — see the type's own note on why a venue
            // chip can't be tappable.
            capsule(entry)
        }
    }

    private func capsule(_ entry: Entry) -> some View {
        HStack(spacing: 6) {
            if let venue = entry.venueLabel {
                Text(venue)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            } else {
                WalletFace(address: entry.id, size: DS.Face.badge, circular: true)
            }
            Text(WalletValue.money(entry.value))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
            if let change = entry.change {
                Text(TokenChartStyle.changeText(change))
                    .dsText(.label12)
                    .foregroundStyle(TokenChartStyle.accent(change: change, scheme: scheme))
                    .monospacedDigit()
            }
        }
        // A face sits tight to the leading edge; a word needs the same gutter
        // as the trailing edge or the capsule reads lopsided.
        .padding(.leading, entry.venueLabel == nil ? 4 : DS.Space.s3)
        .padding(.trailing, DS.Space.s3).padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(DS.fillFaint))
        .contentShape(Capsule(style: .continuous))
    }
}

/// LENDING — Aave, Spark and Morpho, in ONE card as rows (prd §212,
/// 2026-07-25; Spark joined 2026-07-30).
///
/// They used to be two full cards, each with its own caption ("DeFi · Aave on
/// Base") and its own three-stat layout — the clearest case in the room of a
/// component picking its container. Aave and Morpho were never two subjects;
/// they're two providers of one subject, and a wallet that uses both got two
/// identical parcels arguing for the same attention as the balance above them.
/// Spark rides `WalletDeFi.positions` beside Aave (same type, a `protocolName`
/// field distinguishes them) rather than a third full card for the same
/// reason.
///
/// The stats survive, re-ranked. What a lending position is actually asking
/// you is "how much, and is it safe" — so the money leads on the trailing edge
/// and the health factor rides the subline where it can be read as a sentence
/// ("Health 1.82 · Base"). Collateral moves behind the row rather than
/// disappearing: it's the denominator of the health factor, which is already
/// stated, so printing it a second time was the stat that earned its seat
/// least.
///
/// Still no chevron on any row — acting on a position happens on Aave, Spark
/// or Morpho, never in here, and a chevron promises a page that doesn't
/// exist. The card renders only when at least one provider has something to
/// say.
struct WalletLendingCard: View {
    /// Both Aave and Spark positions — `protocolName` tells them apart.
    let aave: [WalletDeFi.Position]
    let morpho: MorphoDeFi.Book

    /// The shared liquidation margin, borrowed by every row: under this a
    /// position is worth worrying about, and the mark goes `DS.attention`
    /// while the subline says "at risk" in words — orange alone means
    /// nothing to anyone who doesn't know where the margin sits (the
    /// 2026-07-21 ruling, kept).
    private static let riskMargin: Double = 1.5

    /// The section's ONE READING (2026-08-15, the wallet cohesion pass —
    /// every wallet section leads with its figure in the display voice, the
    /// brief's "3 late" grammar; the approvals card has had this shape since
    /// §292 and was the model). Ranked by what a lender actually needs first:
    /// a position near its floor beats a health figure beats a supplied
    /// total. The health shown is the WORST across every protocol on the
    /// card — the same `min` each row already takes, one level up — because a
    /// reading that averaged would hide exactly the position the margin rule
    /// exists to surface. Attention ink only on the at-risk form: orange on a
    /// healthy 2.1 would spend the room's alarm colour on good news.
    private var reading: (text: String, risk: Bool) {
        let healths = aave.compactMap(\.healthFactor)
            + morpho.positions.compactMap(\.healthFactor)
        let atRisk = healths.filter { $0 < Self.riskMargin }.count
        if atRisk > 0 {
            return (atRisk == 1
                    ? String(localized: "1 position near its floor")
                    : String(localized: "\(atRisk) positions near their floor"), true)
        }
        if let worst = healths.min() {
            return (String(localized: "Health \(String(format: "%.1f", worst))"), false)
        }
        let supplied = aave.reduce(0) { $0 + $1.totalCollateralUSD } + morphoDeposits
        return (String(localized: "\(WalletValue.money(supplied)) supplied"), false)
    }

    var body: some View {
        if !aave.isEmpty || !morpho.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                WalletSectionLabel(title: String(localized: "Lending"))
                let r = reading
                Text(r.text)
                    .dsText(.heading22)
                    .foregroundStyle(r.risk ? DS.attention : DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
                if !aavePositions.isEmpty { aaveRow }
                if !sparkPositions.isEmpty { sparkRow }
                if !morpho.isEmpty { morphoRow }
            }
            // Headers, no card — the Lending block, taking the same ruling as
            // its three siblings (prd §493; see `WalletPerpsCard` for the
            // reasoning in full).
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.bottom, DS.Space.s4)
        }
    }

    // MARK: - Aave / Spark (same shape, one row each, filtered by protocol)

    private var aavePositions: [WalletDeFi.Position] { aave.filter { $0.protocolName == "Aave" } }
    private var sparkPositions: [WalletDeFi.Position] { aave.filter { $0.protocolName == "Spark" } }

    private func lendingRow(_ positions: [WalletDeFi.Position], title: String) -> some View {
        let collateral = positions.reduce(0) { $0 + $1.totalCollateralUSD }
        let debt = positions.reduce(0) { $0 + $1.totalDebtUSD }
        // The riskiest health factor across positions — nil when nothing is
        // borrowed anywhere (the protocol's no-debt sentinel), which is not
        // a zero.
        let health = positions.compactMap(\.healthFactor).min()
        let atRisk = (health ?? .infinity) < Self.riskMargin
        let borrowing = debt > 0
        // The protocol's own mark — Aave ships one, Spark doesn't, and the
        // fallback says so honestly rather than inventing artwork.
        return WalletRow(mark: .asset(title, tint: atRisk ? DS.attention : DS.tint,
                                      atRisk: atRisk),
                         title: title,
                         subtitle: Self.line(health: health, atRisk: atRisk,
                                             chains: positions.map(\.network))) {
            WalletRowValue(value: WalletValue.money(borrowing ? debt : collateral),
                           caption: borrowing ? String(localized: "borrowed")
                                              : String(localized: "supplied"))
        }
    }

    private var aaveRow: some View {
        lendingRow(aavePositions, title: "Aave")
    }

    private var sparkRow: some View {
        lendingRow(sparkPositions, title: "Spark")
    }

    // MARK: - Morpho

    /// Vault deposits + market-side lending, the earn total.
    private var morphoDeposits: Double {
        morpho.vaults.reduce(0) { $0 + $1.usd }
            + morpho.positions.reduce(0) { $0 + $1.supplyUSD }
    }
    private var morphoDebt: Double { morpho.positions.reduce(0) { $0 + $1.borrowUSD } }
    /// The riskiest market — Morpho markets are isolated, so the worst one is
    /// the one that liquidates first; nil when nothing is borrowed.
    private var morphoHealth: Double? { morpho.positions.compactMap(\.healthFactor).min() }
    /// The position BEHIND `morphoHealth` — needed to key the trajectory
    /// lookup (per market, not per chain), since two isolated positions on
    /// the same chain can be drifting in different directions.
    private var worstMorphoPosition: MorphoDeFi.Position? {
        morpho.positions.filter { $0.healthFactor != nil }
            .min { $0.healthFactor! < $1.healthFactor! }
    }

    private var morphoRow: some View {
        let atRisk = (morphoHealth ?? .infinity) < Self.riskMargin
        let borrowing = morphoDebt > 0
        // Morpho's two faces still differ, they just differ in one line now:
        // BORROWING states its health, EARNING states how many places the
        // money sits (isolated markets and vaults are Morpho's whole shape,
        // and "2 vaults" is the fact a single Deposits number can't carry).
        let trend = worstMorphoPosition.flatMap {
            MorphoDeFi.hfTrend(network: $0.network, address: $0.address, marketLabel: $0.marketLabel)
        }
        let subtitle = borrowing
            ? Self.line(health: morphoHealth, atRisk: atRisk,
                        chains: morpho.positions.map(\.network), trend: trend)
            : Self.earning(vaults: morpho.vaults.count, markets: morpho.positions.count)
        return WalletRow(mark: .asset("Morpho", tint: atRisk ? DS.attention : DS.tint,
                                      atRisk: atRisk),
                         title: "Morpho", subtitle: subtitle) {
            WalletRowValue(value: WalletValue.money(borrowing ? morphoDebt : morphoDeposits),
                           caption: borrowing ? String(localized: "borrowed")
                                              : String(localized: "deposits"))
        }
    }

    // MARK: - Sublines

    /// "Health 1.82 · Base · drifting down for 4 days" — the reading, then
    /// where it lives, then which way it's moving. A position with no debt
    /// says so instead of printing a sentinel, a book spread across chains
    /// names none rather than picking one arbitrarily, and `trend` (Morpho
    /// only — Aave/Spark are one account-wide number, not per-market, so
    /// there's no single position to trend) is silent until there's a real
    /// day of history to read a direction from.
    private static func line(health: Double?, atRisk: Bool, chains: [String],
                             trend: String? = nil) -> String {
        var parts: [String] = []
        if let health {
            parts.append(atRisk
                ? String(localized: "Health \(WalletIngest.format(health)) · at risk")
                : String(localized: "Health \(WalletIngest.format(health))"))
        } else {
            parts.append(String(localized: "No debt"))
        }
        let unique = Set(chains)
        if unique.count == 1, let network = unique.first,
           let chain = WalletIngest.displayName(forNetwork: network) {
            parts.append(chain)
        }
        if let trend { parts.append(trend) }
        return parts.joined(separator: " · ")
    }

    private static func earning(vaults: Int, markets: Int) -> String {
        let places = vaults + markets
        guard places > 0 else { return String(localized: "Earning") }
        return places == 1 ? String(localized: "Earning · 1 position")
                           : String(localized: "Earning · \(places) positions")
    }
}


/// The door to the full allocation (2026-07-21, prd §155) — the treemap shows
/// the top six positions; this opens all of them, and says which wallet holds
/// each. **Was `WalletConcentrationLine`**, renamed 2026-08-20 (prd §417) when
/// the reading it used to carry was promoted out of it.
///
/// **It says "All 13" now, not "Where it's held" (2026-08-22, prd §447), and
/// the count is not decoration — it is the one clause rescued from the map's
/// deleted subline.** "$19.9K across 13 tokens in 3 wallets" said three things
/// and two of them were already on screen (the money is the crown, the wallet
/// count is the face chips under it); the token count was the only fact it
/// alone carried, and a count belongs on the control that opens all of them
/// rather than in a caption. It also states the gap the map cannot: six cells
/// drawn, thirteen held. The tray behind it is still titled "Where it's held",
/// so the destination keeps its full name — this is a door label, and the door
/// sits beside a line about the book's shape, which is what makes the bare
/// "All 13" read unambiguously.
///
/// **Gated on the token COUNT, not on the concentration read it used to gate
/// on.** That old gate was a proxy for "there's a real book here", and it is
/// the wrong proxy for a label that names a number: `concentrationShort` also
/// nils when the top share rounds to 100%, so a two-position book where one
/// holding is 99.6% would hide a door that "All 2" would open perfectly well.
/// A door naming a count is honest exactly when that count is worth opening.
///
/// Nothing renders with a single wallet (`onOpen` nil): there is no "where" to
/// open when every position sits in the same place.
struct WalletAllocationDoor: View {
    let portfolio: WalletPortfolio
    /// nil with a single wallet — see above.
    let onOpen: (() -> Void)?

    var body: some View {
        if let onOpen, portfolio.tokenCount > 1 {
            Button(action: onOpen) {
                // No trailing `Spacer` (2026-08-22): this used to be a row of
                // its own and now shares one with `shapeLine`, so it must HUG
                // its content and let the caller's own spacer push it trailing.
                // A spacer here would eat the row and shove the shape line off
                // the leading edge.
                HStack(spacing: 5) {
                    Text("All \(portfolio.tokenCount)")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .dsGlyph(10)
                        .foregroundStyle(DS.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The full allocation (2026-07-21) — every position the combined portfolio
/// holds, and which wallets hold it. The answer to the question the combined
/// treemap raises by merging: "fine, but whose ETH is that?"
///
/// The old per-wallet maps answered it by never merging in the first place;
/// this answers it on demand, in one place, for every position rather than
/// only the five the map had room for.
struct WalletAllocationTray: View {
    let portfolio: WalletPortfolio

    /// Enough to be the whole answer for a normal book without becoming a
    /// ledger — beyond this the tail is dust the treemap already floors out.
    private var listed: [WalletPortfolio.Position] { Array(portfolio.positions.prefix(12)) }

    var body: some View {
        DSTray(title: String(localized: "Where it's held"),
               height: min(620, CGFloat(150 + listed.count * 62))) {
            ScrollView {
                VStack(spacing: DS.Space.s1) {
                    ForEach(listed) { position in
                        row(position)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ position: WalletPortfolio.Position) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                // The same coin mark the treemap above draws — this tray IS
                // that treemap's list form, and it wore no artwork at all.
                AssetMark(name: position.symbol, size: 22)
                Text(position.symbol)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(WalletValue.money(position.usd))
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                if portfolio.totalUSD > 0 {
                    Text("\(Int((position.usd / portfolio.totalUSD * 100).rounded()))%")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .monospacedDigit()
                }
            }
            // The faces carry the identity here, the same tint the switcher
            // and the stacked hero use — a wallet is a color in this app.
            HStack(spacing: DS.Space.s3) {
                ForEach(position.holders) { holder in
                    HStack(spacing: 5) {
                        WalletFace(address: holder.address, size: DS.Face.badge)
                        Text(holder.label)
                            .dsText(.label12).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Text(WalletValue.money(holder.usd))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .dsListCardRow()
    }
}

/// The page behind the Worth-a-look tile — and the LAST page (2026-07-20,
/// same-day correction; user: "you can't have worth a look pull up a sheet
/// that then says to go look somewhere else"). The first cut routed rows to
/// the wallet's screen, whose only added value was a Revoke.cash button —
/// tile → tray → page → external, two hops too many. Rows are TERMINAL now:
/// each states the whole fact, and where one real action exists it sits on
/// the row itself — a flagged transfer opens its sheet, a delegation or
/// approval opens that wallet's Revoke.cash page directly (the exact door
/// the wallet screen offers, minus the detour). Safe and liquidation rows
/// carry no control: signing happens in the Safe app and acting on Aave
/// happens on Aave, and the row already says everything this app can
/// honestly say.
///
/// ACT VS AWARE (2026-07-24, superseding §196's type split), the fix for a
/// sharper problem than "one undifferentiated wall": §196 sectioned by
/// TYPE, but colored by raw SEVERITY, and severity had the wrong axis —
/// poisoning and spoofed-symbol transfers already happened (spam; nothing
/// to do about them) yet wore the loudest "critical" red, while a LIVE
/// approval that can still drain the wallet sat in quiet "notice" orange.
/// At real scale (a wallet with dozens of airdrops) the tray cried wolf in
/// permanent red and buried the one thing worth a decision. Two groups now:
/// **Worth doing** (`Kind.isActionable` — liquidation, approvals,
/// delegations, Safe signatures; each still its own type-section beneath,
/// unchanged from §196) leads, small and stated in decision terms; **Just
/// so you know** (poisoning + spoofed symbols — exactly the existing
/// `flagged` list) collapses to one line by default and can be MUTED, so a
/// recognized pattern can stop badging the feed red forever. Jump chips
/// (kept per the user's own ask) now target these two groups, not five
/// type-sections — "Worth doing" rarely runs long enough to need internal
/// navigation once spam isn't diluting it.
struct WalletWorthALookTray: View {
    let warnings: [WalletWarning]
    /// The flagged transfers behind a poisoning/spoofed-symbol warning — the
    /// whole "Just so you know" pile. Each becomes its own row with a door
    /// to its sheet when expanded, instead of one dead aggregate line.
    let flagged: [Thing]
    /// The approval/Permit2-grant things whose live on-chain state is still
    /// active (`WalletApprovals.activeApprovals`). Enumerated as rows ONLY
    /// when the Approvals card can't take the job — see `actionRows`.
    let activeApprovals: [Thing]
    /// The room's own approvals reading (prd §292). Held so the walk row can
    /// quote `WalletApprovalExposure.headline` VERBATIM rather than compose a
    /// second sentence about the same grants — two files describing one set is
    /// how the sheet and the card start disagreeing.
    var exposure = WalletApprovalExposure()
    /// Dismiss this sheet and scroll the room to the Approvals card. Nil when
    /// the caller has no such card on screen, and then the approvals fall back
    /// to being enumerated here — the honesty rule's own corollary, the same
    /// one `WalletCompositionStrip`'s two optional doors keep: never render a
    /// control that opens nothing.
    var onWalkToApprovals: (() -> Void)?
    /// The same, for the Lending card.
    var onWalkToLending: (() -> Void)?
    @Environment(\.openURL) private var openURL
    /// Mirrors `WalletAwareness.isMuted` locally so toggling redraws THIS
    /// tray immediately; the plain UserDefaults flag underneath is what the
    /// feed card re-reads fresh the next time it's built.
    @State private var muted = WalletAwareness.isMuted
    /// Collapsed by default (2026-07-24) — spam you can't act on doesn't
    /// deserve the same standing scroll real estate the actionable rows
    /// get. Expands in place; the sheet's own height grows to fit since
    /// `trayHeight` reads this same state.
    ///
    /// EXCEPT when there is nothing actionable at all (prd §449), where it
    /// opens expanded: the strip you tapped to get here already told you the
    /// count, so a modal whose entire content is that same count restated and
    /// a chevron asks for a second tap to say anything new. Held as an
    /// OVERRIDE rather than seeded in an initialiser so the default tracks
    /// `hasActionable` on every body pass — a live read that lands the run's
    /// first approval while the sheet is open must not leave the pile stuck
    /// open underneath it.
    @State private var awareExpandedOverride: Bool?
    private var awareExpanded: Bool { awareExpandedOverride ?? !hasActionable }
    /// A flagged transfer PUSHES within this same sheet now (2026-07-23,
    /// second fix to prd §196) rather than presenting `ThingSheetView` as a
    /// second, sibling `.sheet` — the first fix already solved "can't get
    /// back to the list" by nesting the thing sheet under the tray, but a
    /// nested `.sheet(item:)` still shows as a card visibly stacked on top
    /// of this one, and dismissing it is a second swipe-down through a
    /// second piece of sheet chrome (user, 2026-07-23: "i don't like how
    /// one tray leads to another on the way back. it should be the same
    /// sheet with a back button"). `NavigationStack(path:)` +
    /// `navigationDestination(for:)` is the exact shape `SocialPostSheet`
    /// already uses for the identical problem (a sheet whose rows open a
    /// detail read, walked as deep as it goes, one back chevron unwinding
    /// it) — one sheet, one piece of chrome, the tray's own scroll position
    /// preserved underneath exactly as before.
    @State private var path: [Thing] = []
    /// The scrolling content's REAL height, measured once it lays out — the
    /// tray's own height is derived from this rather than guessed (see
    /// `estimatedContentHeight` for why the guess couldn't hold). Zero until
    /// the first layout pass, which is the only time the estimate is used.
    @State private var contentHeight: CGFloat = 0
    /// The tray's heading scales with Dynamic Type, so the chrome allowance
    /// around the content has to as well.
    @ScaledMetric(relativeTo: .title2) private var trayTitleHeight: CGFloat = 28

    private var liquidation: [WalletWarning] { warnings.filter { $0.kind == .liquidation } }
    private var delegations: [WalletWarning] { warnings.filter { $0.kind == .delegation } }
    private var safeSignatures: [WalletWarning] { warnings.filter { $0.kind == .safe } }

    /// "Worth doing" is a FLAT list now (2026-07-24) — no Position
    /// risk/Approvals/Delegations/Safe sub-headers underneath it. Each row
    /// carries its own icon and states its own whole fact, matching the
    /// approved mockup; the one shared "Worth doing" header above is doing
    /// all the grouping these four kinds need.
    ///
    /// Built as ONE array behind ONE `ForEach` (below) rather than four
    /// sequential `if !x.isEmpty { ForEach(...) }` blocks stacked in the
    /// same ViewBuilder — four sibling conditionals each nest their own
    /// `_ConditionalContent` wrapper type, compounding the already-tight
    /// first-render view-tree depth this app has hit before (see the
    /// "Coming up card" stack-overflow lesson elsewhere in this codebase).
    /// One `ForEach` over a unified enum keeps that flat regardless of how
    /// many of the four kinds are actually present.
    private enum ActionRow: Identifiable {
        /// A kind the ROOM already states better, standing in for its whole
        /// group: one row carrying that card's own headline and a pill that
        /// walks to it (prd §449). `id` is the destination, so there can only
        /// ever be one walk row per card.
        case walk(id: String, icon: String, hot: Bool, title: String,
                  subtitle: String?, label: String)
        case liquidation(WalletWarning)
        // The approval carries its id as a STORED value captured at
        // construction (2026-07-24 crash fix) — reading `t.id` lazily in the
        // `id` getter reached into the SwiftData model during ForEach diffing,
        // and a reconciliation/CloudKit delete of that approval Thing then
        // trapped. WalletWarning is a value struct, so its `id` is safe.
        case approval(id: String, thing: Thing)
        case delegation(WalletWarning)
        case safe(WalletWarning)

        var id: String {
            switch self {
            case .walk(let id, _, _, _, _, _): "walk:\(id)"
            case .liquidation(let w): "liquidation:\(w.id)"
            case .approval(let id, _): "approval:\(id)"
            case .delegation(let w): "delegation:\(w.id)"
            case .safe(let w): "safe:\(w.id)"
            }
        }
    }

    /// The order is unchanged from §241 — liquidation, approvals,
    /// delegations, Safe — and only the SHAPE of the first two moved (prd
    /// §449). Both now have a card in this same room that ranks them by
    /// something (dollars at stake, distance to liquidation) where this list
    /// ranked them by nothing, so re-listing them here is prd §208's own ban
    /// on a door onto a page that repeats the card beneath it. Each collapses
    /// to ONE walk row; delegations and Safe signatures keep their full rows,
    /// because this sheet is their only home in the wallet room.
    ///
    /// Each collapse is GATED ON ITS DESTINATION EXISTING and falls back to
    /// the old enumeration otherwise, so nothing can go missing: a pill with
    /// nowhere to land would be the dead control §83 bans, and a group silently
    /// dropped instead would be worse.
    private var actionRows: [ActionRow] {
        var out: [ActionRow] = []
        if let lead = liquidationLead, onWalkToLending != nil {
            out.append(.walk(id: "lending", icon: "chart.line.downtrend.xyaxis", hot: true,
                             title: lead.title, subtitle: lead.subtitle,
                             label: String(localized: "Lending")))
        } else {
            out += liquidation.map(ActionRow.liquidation)
        }
        // `priced`, not `isEmpty`: `headline` counts PRICED spenders and sums
        // PRICED grants, so an exposure that is all-unpriced would quote it as
        // "0 spenders can move $0" — a reassurance, over live grants, on the
        // row that earned it least. That case keeps the enumerated rows, which
        // state each grant without claiming to price it.
        if !exposure.priced.isEmpty, onWalkToApprovals != nil {
            out.append(.walk(id: "approvals", icon: "key.fill", hot: false,
                             title: WalletApprovalExposure.headline(
                                 spenders: exposure.spenderCount, total: exposure.total),
                             subtitle: nil,
                             label: String(localized: "Approvals")))
        } else {
            // `.live` at the boundary (corollary 4): `activeApprovals` is a
            // held `[Thing]`, and every read below — the id captured here, the
            // title, the granted date — is a stored-property read that traps
            // on a model a foreground heal tombstoned after this array was
            // handed over.
            out += activeApprovals.live.map { ActionRow.approval(id: $0.id.uuidString, thing: $0) }
        }
        out += delegations.map(ActionRow.delegation)
        out += safeSignatures.map(ActionRow.safe)
        return out
    }

    /// What the liquidation walk row says. ONE at-risk position speaks in its
    /// own warning's words; several are counted in `WalletWarning.Kind`'s own
    /// vocabulary — the identical construction `WalletWatch.summary` uses for
    /// the strip that opened this sheet, so the two can't word it differently.
    /// Plain interpolation, never `String(localized:)`, which GROUPS an Int
    /// and would print a count as a quantity (the §375 year bug).
    private var liquidationLead: (title: String, subtitle: String?)? {
        guard let first = liquidation.first else { return nil }
        guard liquidation.count > 1 else { return (first.title, first.subtitle) }
        return ("\(liquidation.count) \(WalletWarning.Kind.liquidation.label(liquidation.count))", nil)
    }

    private var hasActionable: Bool { !actionRows.isEmpty }
    private var actionableRowCount: Int { actionRows.count }

    /// The tray's own ceiling — past this the content scrolls within the
    /// natural-height detent below. Raised from 620 (2026-07-24, user: "it
    /// could be taller") — the tray also offers `.large` as a second detent
    /// (see `trayDetents`) so a long pile can be dragged open past even this,
    /// but the natural-height detent still caps here first.
    private static let maxTrayHeight: CGFloat = 720
    /// The aware pile's expanded rows stay bare one-liners — spam doesn't
    /// need the same per-row weight the actionable rows earn.
    private static let rowHeight: CGFloat = 46

    /// The first-frame floor, and DELIBERATELY NOT AN ESTIMATE (prd §449).
    ///
    /// A ~45-line arithmetic guess used to live here, pricing every row at a
    /// flat constant — and its own doc records why it could never hold: an
    /// actionable row carries a WRAPPING title, and no arithmetic here can
    /// know how many lines a string takes at the reader's type size. It was
    /// alive for exactly one frame, it was wrong on every wallet with a
    /// delegation, and being wrong pushed the pile below the fold (user,
    /// 2026-07-26). `contentHeight` measures the truth on the next pass, so
    /// what the first frame needs is not a better guess but a floor small
    /// enough to grow OUT of rather than shrink back from — growing reads as
    /// the sheet settling, shrinking reads as it snatching content away.
    private static let openingHeight: CGFloat = 260

    /// Everything the sheet spends before the scrolling content gets a
    /// point: `DSTray`'s top padding, its heading, the gap beneath it, its
    /// bottom padding, and the home-indicator inset — which the detent
    /// height INCLUDES but the content can never draw into. Over-allowing it
    /// on a device without one costs a little dead space; under-allowing it
    /// hides a row, and only one of those is a bug.
    private var chromeHeight: CGFloat {
        DS.Space.s6 + trayTitleHeight + DS.Space.s4 + DS.Space.s6 + Self.homeIndicatorAllowance
    }
    private static let homeIndicatorAllowance: CGFloat = 34

    /// Reads `awareExpanded` through the measured content, so the sheet
    /// visibly grows when the pile is opened and settles back when it's
    /// closed, both capped at `maxTrayHeight`.
    private var trayHeight: CGFloat {
        let content = contentHeight > 0 ? contentHeight + chromeHeight : Self.openingHeight
        return min(Self.maxTrayHeight, content)
    }

    private var trayDetents: Set<PresentationDetent> {
        [.height(trayHeight), .large]
    }

    var body: some View {
        NavigationStack(path: $path) {
        DSTray(title: String(localized: "Worth a look"), height: trayHeight, ink: true, detents: trayDetents) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        // NO SECTION LABEL and no explainer line (prd §449).
                        // "Worth doing", its count, and "These are still
                        // yours to change." sat directly under a sheet
                        // titled "Worth a look" — the title said three more
                        // times, the count for a third time (the strip you
                        // tapped said it, and four countable rows say it
                        // again). Every row under here is actionable by
                        // definition, so the label discriminated nothing.
                        //
                        // Rows carry their own padding since each wears a
                        // surface, so the gap between them is s2 — the card
                        // edges do the separating the air used to.
                        if hasActionable {
                            VStack(alignment: .leading, spacing: DS.Space.s2) {
                                // A flat list (2026-07-24) — no Position
                                // risk/Approvals/Delegations/Safe
                                // sub-headers; each row states its own whole
                                // fact and carries its own icon and, where
                                // one exists, its own door. ONE ForEach over
                                // the unified `actionRows`, not sibling
                                // conditionals — see that property's doc.
                                ForEach(actionRows) { item in
                                    switch item {
                                    case .walk(let id, let icon, let hot, let title,
                                               let subtitle, let label):
                                        walkRow(id: id, icon: icon, hot: hot, title: title,
                                                subtitle: subtitle, label: label)
                                    case .liquidation(let w): liquidationRow(w)
                                    case .approval(_, let t): approvalActionRow(t)
                                    case .delegation(let w): delegationRow(w)
                                    case .safe(let w): safeRow(w)
                                    }
                                }
                            }
                        }
                        if !flagged.isEmpty { awareSection }
                    }
                    .padding(.bottom, DS.Space.s2)
                    // The content's REAL height, which is what the tray
                    // sizes itself to (see `trayHeight`). A ScrollView never
                    // constrains its content vertically, so this is the
                    // natural, unclipped height AND it doesn't move when the
                    // sheet does — dragging the tray to `.large` and back
                    // leaves it untouched, so feeding it back into the detent
                    // can't chase its own tail. Measuring the scroll VIEWPORT
                    // instead would: a viewport reports whatever height the
                    // sheet currently happens to have, mid-drag included.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        contentHeight = h
                    }
                }
                .scrollIndicators(.hidden)
        }
        // Pure ink, matching the detail sheet it pushes to (2026-07-24,
        // user: "worth a look screen is not same color as the thing sheet
        // and needs to be"). The NavigationStack wrapping this tray is the
        // real root passed to `.sheet` here (not the `DSTray(ink:)` nested
        // one level inside it), so it needs `dsInk()` applied again at this
        // outer level too — the same "wins the preference race" reasoning
        // `dsInk()` documents.
        .dsInk()
        .navigationDestination(for: Thing.self) { thing in
            // `.presentationDetents` is a preference DSTray declares on
            // itself, which stops applying once the stack pushes past it —
            // observed on-device as the sheet visibly SHRINKING on push
            // (user, 2026-07-23: "why not just keep it on a sheet the same
            // size so it is smoother"). Pinning the identical `trayHeight`
            // here keeps the frame constant across the push; the thing
            // sheet already scrolls its own content, so it isn't cramped
            // by inheriting the list's height instead of its usual near-
            // full-screen default. Same loss hits `presentationBackground`/
            // `colorScheme` (2026-07-24, user: "the wallet worth a look
            // details tray is not ink colored") — `ThingSheetView` already
            // declares its own `Color.black` + `.dark` internally, but that
            // stops taking effect once pushed past DSTray's own declared
            // preferences too, so it's pinned again here, right beside the
            // detents fix.
            ThingSheetView(thing: thing, onBack: { path.removeLast() })
                .presentationDetents(trayDetents)
                .dsSizedSheet(trayHeight)
                .dsInk()
        }
        }
    }

    // MARK: - Just so you know (the aware pile, collapsed + mutable)

    /// The awareness section — one line by default, expanding in place to
    /// list each flagged transfer with a door to its sheet. Never destructive
    /// red, muted or not: this is spam you can recognize, not a live risk
    /// (that read is reserved for the actionable rows). Muting stops it
    /// badging the feed card (`WalletWarningsStrip`) without hiding it here —
    /// the tray still shows you what you muted, it just stops shouting about
    /// it elsewhere.
    ///
    /// ## It LIFTS; it does not recess (prd §449)
    ///
    /// It was boxed on `DS.surfaceWell` from 2026-07-24 to read as a quiet,
    /// self-contained pile. `surfaceWell` is `#080809` and this sheet is INK,
    /// `#000000` — a 1.02:1 step, which is not a quiet recess but an invisible
    /// one. The token's own doc says it "dips toward the page", and on an ink
    /// page there is nothing darker than the page to dip toward. So the pile
    /// lifts on `DS.fillFaint` instead — the same fill `WalletWarningsStrip`
    /// wears on the balance card, which makes the surface you tapped and the
    /// pile you land on visibly the same object.
    ///
    /// ## The label is gone, and the sentence is said once
    ///
    /// "Just so you know" sat above a row reading "15 spam transfers" /
    /// "Transfers you didn't make — nothing to do": a label, a noun, and the
    /// same noun again in other words. The row now carries
    /// `WalletWarnings`' OWN title for this pile verbatim, so the feed badge
    /// and this tray can never describe it differently, with "Nothing to do"
    /// as the whole subline.
    ///
    /// `awareTitle` derives from what is actually IN the pile, never a fixed
    /// sentence (2026-08-13). It was fixed once and was wrong for the
    /// commonest case: "Fake tokens sent to you" describes a junk AIRDROP,
    /// which `WalletIngest`'s received-side filter drops at ingest and which
    /// therefore can never appear here. What is here, most of the time, is the
    /// opposite direction — `"spam"` is `WalletSafety.isFakeOutboundTransfer`,
    /// a spam contract's own `Transfer(you → attacker)` fiction. The pile is
    /// MIXED, so no single direction is safe to assert: a poisoning transfer
    /// really was received, a spoofed symbol goes either way, and an outbound
    /// fiction never happened at all.
    private var awareTitle: String {
        let spam = flagged.contains { $0.hasSecurityFlag("spam") }
        let poisoning = flagged.contains { $0.hasSecurityFlag("poisoning") }
        let symbol = flagged.contains { $0.hasSecurityFlag("symbol") }
        let n = flagged.count
        switch (spam, poisoning, symbol) {
        case (true, false, false):
            return n == 1 ? String(localized: "1 transfer you didn't make")
                          : String(localized: "\(n) transfers you didn't make")
        case (false, true, false):
            return n == 1 ? String(localized: "1 lookalike address")
                          : String(localized: "\(n) lookalike addresses")
        case (false, false, true):
            return n == 1 ? String(localized: "1 fake token symbol")
                          : String(localized: "\(n) fake token symbols")
        default:
            return n == 1 ? String(localized: "1 transfer that isn't what it looks like")
                          : String(localized: "\(n) transfers that aren't what they look like")
        }
    }

    private var awareSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s3) {
                Button {
                    DSHaptic.selection()
                    withAnimation(DS.Motion.standard) { awareExpandedOverride = !awareExpanded }
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "photo.badge.exclamationmark.fill")
                            .dsGlyph(13)
                            .foregroundStyle(DS.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(DS.fillLine))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(awareTitle)
                                .dsText(.callout15).fontWeight(.medium)
                                .foregroundStyle(DS.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(muted ? String(localized: "Muted — won't badge your feed")
                                       : String(localized: "Nothing to do"))
                                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                // Mute sits ON the row it governs (prd §449). It is this
                // section's only verb, and it used to live BELOW the expanded
                // list — so the one thing you could do about the pile was
                // reachable only after opening the pile, and invisible in the
                // state (collapsed) the section is designed to sit in.
                Button {
                    DSHaptic.tap()
                    muted.toggle()
                    WalletAwareness.isMuted = muted
                } label: {
                    Text(muted ? String(localized: "Unmute") : String(localized: "Mute"))
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.tint)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                Image(systemName: awareExpanded ? "chevron.up" : "chevron.down")
                    .dsGlyph(11)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s3)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                    .fill(DS.fillFaint))

            if awareExpanded {
                VStack(spacing: 0) {
                    // Corollary 3 (build 176) — see `ThingRowKeying`.
                    ForEach(flagged.keyed) { row in
                        if let thing = row.live { flaggedRow(thing) }
                    }
                }
            }
        }
    }

    // MARK: - "Worth doing" rows

    /// The shared shape every actionable row wears (2026-07-24, matching the
    /// approved mockup): a leading icon square colored by urgency (red only
    /// for a live liquidation, orange for everything else actionable), a
    /// title that WRAPS — no `lineLimit`, unlike the aware pile's bare rows
    /// below — since "Uniswap can spend unlimited USDC" is worth reading in
    /// full, not clipped, and an optional subtitle stating the one spec that
    /// differs (a chain, a health factor). The door, when one exists, is its
    /// own tappable pill on the trailing edge — the row itself carries no
    /// dead tap target when there's nothing to open.
    ///
    /// EVERY actionable kind carries one now (2026-07-31, prd §241): Revoke
    /// for an approval or delegation, "Open Aave"/"Open Morpho" for a
    /// liquidation, "Open Safe" for a pending queue. The app still performs
    /// none of them itself (prd §112, untouched) — but a row that names
    /// somewhere and then won't take you there was the sentence "Sign in the
    /// Safe app" doing the work of a button. The label always names the
    /// DESTINATION, never an outcome, because travel is the only thing this
    /// pill can honestly promise.
    /// - Parameter door: the pill. `leaves` is what the arrow says — `↗` for
    ///   a destination outside the app (Revoke.cash, the Safe app, a protocol)
    ///   and `↑` for one inside it, which is the room's own card this sheet
    ///   just handed the subject back to (prd §449). Every pill here was `↗`
    ///   until walk rows existed, so the glyph carried no information; now it
    ///   answers the one question a reader has before tapping — am I leaving?
    private func actionRow(icon: String, hot: Bool, title: String, subtitle: String?,
                           door: (label: String, leaves: Bool, act: () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: icon)
                .dsGlyph(13)
                .foregroundStyle(hot ? DS.destructive : DS.attention)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill((hot ? DS.destructive : DS.attention).opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsText(.body17).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            if let door {
                Button {
                    DSHaptic.selection()
                    door.act()
                } label: {
                    HStack(spacing: 3) {
                        Text(door.label)
                        Image(systemName: door.leaves ? "arrow.up.right" : "arrow.up")
                            .dsGlyph(9, weight: .bold)
                    }
                    .dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s3).padding(.vertical, 7)
                    .background(Capsule().fill(DS.tint.opacity(0.16)))
                }
                .buttonStyle(PressSpring())
            }
        }
        // A REAL SURFACE per row (2026-07-31, prd §241 variant A). These were
        // the only rows in the wallet room without one — bare vertical
        // padding on the ink page — and since a title WRAPS here (the one
        // place in the room where it does), two consecutive rows ran together
        // with nothing between them. The design law bans hairlines, so
        // separation has to come from tone, which is exactly what the
        // elevation ladder is for: the row steps UP to `surfaceSheet` while
        // the aware pile below stays recessed on `surfaceWell`, and the two
        // groups read as different kinds of thing without a single line.
        //
        // Note this is a real background, NOT `dsListCardRow()`: that applies
        // `listRowBackground`, which is a List-scoped modifier and silently
        // does nothing inside `DSTray`'s plain VStack (see the tray audit
        // note in prd §241).
        .padding(DS.Space.s3)
        .dsInkFill(cornerRadius: DS.Radius.widget)
    }

    /// A group the ROOM states better, standing in for itself (prd §449).
    ///
    /// It wears the SAME anatomy as every other row here — icon, title,
    /// subtitle, pill — and differs only in what the pill promises: the label
    /// names a card in this room rather than a website, and the arrow points
    /// up rather than out. Its TITLE is that card's own headline, passed in
    /// from `actionRows` where it is quoted verbatim, so this file never
    /// composes a second sentence about a set another file already describes.
    private func walkRow(id: String, icon: String, hot: Bool, title: String,
                         subtitle: String?, label: String) -> some View {
        actionRow(icon: icon, hot: hot, title: title, subtitle: subtitle,
                  door: (label, false, {
                      if id == "approvals" { onWalkToApprovals?() } else { onWalkToLending?() }
                  }))
    }

    private func liquidationRow(_ w: WalletWarning) -> some View {
        actionRow(icon: "chart.line.downtrend.xyaxis", hot: true, title: w.title,
                  subtitle: Self.subline([whose(watched: w.address), w.subtitle]),
                  door: door(w))
    }

    /// An approval thing already carries its own Revoke.cash page as
    /// `content` (`WalletApprovals`' own field); its chain (not otherwise
    /// tracked as a dedicated field) is read back out of `sourceRef`.
    ///
    /// The subline is the row's whole context, in decision order: WHOSE wallet
    /// is exposed, where, and since when.
    private func approvalActionRow(_ thing: Thing) -> some View {
        actionRow(icon: "key.fill", hot: false, title: WalletValue.title(thing),
                  subtitle: Self.subline([whose(stored: thing.walletAddress),
                                          approvalChain(thing),
                                          Self.grantedLine(thing)]),
                  door: URL(string: thing.content).map { url in
                      (String(localized: "Revoke"), true, { openURL(url) })
                  })
    }

    /// "Granted Mar 2024" — the fact that turns a live approval from a notice
    /// into a decision (2026-07-31). A forgotten two-year-old unlimited grant
    /// is precisely what Revoke.cash exists for; one made this morning is
    /// probably you, and the row reads differently for each.
    ///
    /// Month and year, never a weekday or a bare month: the year is what
    /// carries "this is old", and the app has already paid once for a
    /// date format that left a reader guessing which one was meant
    /// (Aerodrome's vote window, 2026-07-30).
    ///
    /// Silent when unknown. `grantedAt` is set only from a real block
    /// timestamp, so nil here means "we never read the block", not "it's
    /// new" — and an approval that landed before the field existed carries
    /// nil forever. Saying nothing is the only honest reading of that.
    private static func grantedLine(_ thing: Thing) -> String? {
        guard thing.isLive, let granted = thing.grantedAt else { return nil }
        return String(localized:
            "Granted \(granted.formatted(.dateTime.month(.abbreviated).year()))")
    }

    /// Whose wallet a row is about — stated only when more than one is
    /// watched (prd §241's own recorded follow-up). With a single wallet
    /// there is nothing to disambiguate, the same guard the feed's source
    /// header already keeps.
    ///
    /// Only two of the four actionable kinds get it, and the asymmetry is the
    /// point rather than an oversight: a delegation's title already opens with
    /// the wallet's label ("vitalik.eth delegates to …") and a Safe row's
    /// reads "… on vitalik.eth's Safe", so prefixing those would print the
    /// same name twice in one row. An approval names only the spender and a
    /// liquidation only the protocol — those are the rows where "which of my
    /// wallets is exposed" goes unanswered, and it's the fact you need BEFORE
    /// tapping Revoke, since that page asks you to connect the wallet in
    /// question.
    private var namesWallet: Bool { WalletStore.shared.addresses.count > 1 }

    /// A landed thing's wallet — stamped as the RESOLVED hex, so it goes
    /// through the store's scope matching rather than a raw compare.
    private func whose(stored address: String?) -> String? {
        guard namesWallet else { return nil }
        return WalletStore.shared.displayName(forStored: address)
    }

    /// A warning's wallet — carried in the WATCHED spelling, the other form.
    private func whose(watched address: String?) -> String? {
        guard namesWallet else { return nil }
        return WalletStore.shared.displayName(forWatched: address)
    }

    /// The row's subline, dropping whatever isn't known — so a missing fact
    /// costs a phrase, never a stray separator.
    private static func subline(_ parts: [String?]) -> String? {
        let kept = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }

    /// The title already states the whole fact ("X delegates to Y on
    /// Ethereum") — no subtitle, since the model's `subtitle` field just
    /// repeats the delegate target the title already names in full.
    private func delegationRow(_ w: WalletWarning) -> some View {
        actionRow(icon: "arrow.triangle.branch", hot: false, title: w.title,
                  subtitle: nil, door: door(w))
    }

    private func safeRow(_ w: WalletWarning) -> some View {
        // The subtitle no longer has to carry the instruction the row can now
        // perform — with a door present it states WHERE, and the pill takes
        // you. Without one (a queue spanning Safes) the old sentence is still
        // the honest thing to say.
        actionRow(icon: "signature", hot: false, title: w.title,
                  subtitle: w.action == nil ? String(localized: "Sign in the Safe app") : nil,
                  door: door(w))
    }

    /// A warning's own door, built where the facts are (`WalletWarning.Action`)
    /// rather than reverse-engineered from a title here.
    private func door(_ w: WalletWarning) -> (label: String, leaves: Bool, act: () -> Void)? {
        guard let action = w.action, let url = URL(string: action.url) else { return nil }
        return (action.label, true, { openURL(url) })
    }

    /// Pulls the chain an approval landed on out of its `sourceRef`
    /// ("wallet:approval:<network>:…" / "wallet:permit2:<network>:…", set by
    /// `WalletApprovals`) — the one per-row spec the mockup shows that
    /// isn't already a dedicated `Thing` field.
    private func approvalChain(_ thing: Thing) -> String? {
        guard let ref = thing.sourceRef else { return nil }
        let parts = ref.split(separator: ":")
        guard parts.count > 2 else { return nil }
        let network = String(parts[2])
        return WalletIngest.displayName(forNetwork: network) ?? network.capitalized
    }

    // MARK: - Aware-pile rows (bare, one line — spam doesn't earn more)

    /// A flagged transfer, WITHOUT ITS VERB (prd §449).
    ///
    /// It used to draw `WalletValue.title(thing)` — "Sent 4,242 USDT" — and
    /// inside a pile headed "transfers you didn't make" that sentence is the
    /// one doing the confusing. It is also not wrong: for a `"spam"` row the
    /// chain really does claim you sent it, and contradicting that claim is
    /// the flag's whole purpose. So the fix is neither to keep the verb nor
    /// to flip it to "Received" (a second false claim, and false for a
    /// different subset — the pile is mixed). The DIRECTION belongs to the
    /// pile's own line, said once; the row carries what tells one row from
    /// another: the amount, wearing the confusable symbol as its own tell,
    /// and when it landed.
    ///
    /// Through `WalletValue.transferAmount`, so §374's mask reaches it — the
    /// unit survives, which is what keeps a hidden row still able to say the
    /// symbol was a lookalike. A row landed before that field existed has its
    /// number only inside its title, so it falls back to the baked title
    /// whole; that is `WalletValue.title`'s own stated limit, not a new one.
    ///
    /// Taps into its sheet, which still states the specific poisoning/spoof
    /// verdict.
    private func flaggedRow(_ thing: Thing) -> some View {
        Button {
            DSHaptic.selection()
            path.append(thing)
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text(WalletValue.transferAmount(thing) ?? WalletValue.title(thing))
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                Text(LiveTimeText.short(thing.capturedAt))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .dsGlyph(12)
                    .foregroundStyle(DS.textTertiary)
            }
            .frame(height: Self.rowHeight)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The stream's door: five rows above, everything behind this (2026-07-20).
/// One centered phrase carrying its own count — the first cut scattered blue
/// text, a gray number, and a chevron across the row's full width, which read
/// as three strays rather than one door (user: "this looks like crap"). The
/// centered single-verb form is the app's own terminal-action grammar
/// ("Stop watching this wallet", "Disconnect Wallet").
struct WalletSeeAllRow: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        // No card, no slab (user, twice: "this looks like crap / still looks
        // bad") — a quiet inline door floating on the page itself, sized like
        // the section labels around it. The stream above it is the content;
        // this is just where it continues.
        Button(action: onOpen) {
            HStack(spacing: 5) {
                Text("See all \(count) transactions")
                    .dsText(.callout15).fontWeight(.semibold)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .dsGlyph(11)
            }
            .foregroundStyle(DS.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
