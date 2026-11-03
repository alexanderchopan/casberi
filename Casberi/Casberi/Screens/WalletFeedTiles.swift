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

/// **THE WALLET'S ONE ROW PITCH (prd §1482, user: "the spacing of text is
/// different on each screen in wallet").** Every list row on every Wallet
/// page — Home's doors, Your account's keys, Following's accounts, a threat,
/// a grant, a position, a token, a place — stands in one anatomy:
///
///     title     `body17`, its line `subhead12`, 2pt apart
///     head      `DSFeed.headHeight` (44) at least, the lead centred in it
///     air       `FeedScreen.rowAir` (4) above and below — a 52pt pitch
///     insets    `DSRoomChassis.rowInset` both sides
///
/// Before this the pages drew four pitches: a push row with no floor (30pt
/// with no line, 47 with one), the feed row's 52, a hand-drawn row's 55
/// (8pt padding, a 1pt gap) and Your account's 68 (a 60pt frame plus air),
/// and the groups inside one list row ended 15pt from the edge where every
/// other row ended 27. Read across screens that is the text column jogging
/// and the rhythm changing page to page, three fixes deep. A constant every
/// row must name is the fix a prose ruling never was (§160's lesson).
///
/// `rowInsets` is a list row of its own; `stackInsets` is a list row holding a
/// `VStack` of rows that each wear `walletRowPitch()`. `fill` and `pad` are
/// the balance card's, unchanged.
enum WalletCardStyle {
    static let fill = 0.82
    static let pad = DS.Space.s4
    /// A row of its own in the List: the air above and below is the row's.
    static var rowInsets: EdgeInsets {
        EdgeInsets(top: FeedScreen.rowAir, leading: DSRoomChassis.rowInset,
                   bottom: FeedScreen.rowAir, trailing: DSRoomChassis.rowInset)
    }
    /// A stack of rows in one List row: each row carries its own air.
    static var stackInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: DSRoomChassis.rowInset, bottom: 0, trailing: DSRoomChassis.rowInset)
    }
}

extension View {
    /// A Wallet list row of its own (prd §1482): the one insets, bare, no
    /// separator. The row inside is a template (`DSPushRow`, `DSFeedRow`,
    /// `DSMoreRow`, `DSToggleRow`) and already holds the 44pt head.
    func walletListRow() -> some View {
        self.listRowInsets(WalletCardStyle.rowInsets)
            .feedRowBackground()
            .listRowSeparator(.hidden)
    }

    /// A Wallet list row holding a stack of rows that each wear
    /// `walletRowPitch()` (prd §1482).
    func walletStackRow() -> some View {
        self.listRowInsets(WalletCardStyle.stackInsets)
            .feedRowBackground()
            .listRowSeparator(.hidden)
    }

    /// A hand-drawn row's height inside a stack (prd §1482): the feed row's
    /// head, then the list's air above and below. Applied INSIDE a `Button`'s
    /// label, so the air is part of the hit.
    func walletRowPitch() -> some View {
        self.frame(minHeight: DSFeed.headHeight)
            .padding(.vertical, FeedScreen.rowAir)
    }
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
    /// Draw the Yours · Everything switch at the foot (prd §1526).
    var whose: Bool = false
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
    /// The moment this number was read, when it is NOT now (prd §825) — set
    /// from `WalletPortfolio.asOf`, so it is non-nil only where the wallet
    /// half of the total is a last-known reading standing in for chains that
    /// could not be reached. nil everywhere else, which is the normal case
    /// and draws nothing.
    var asOf: Date? = nil
    /// A chain the person FOLLOWS that this pass could not read (prd §827) —
    /// set from `WalletIngest.unreadableNetworks()`. §83: a total that silently
    /// omits a switched-on chain is a false number, and saying nothing is how
    /// "Robinhood shows nothing" survived three passes. nil is the normal case.
    var note: String? = nil
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
    /// **HOW THE NUMBER IS SPELLED (prd §683).** This crown is the shared Home
    /// of every wallet-family room — Wallet, Frames and Logos — and the
    /// spelling is the ONE piece of it that cannot be
    /// shared: the Wallet counts dollars, a devnet counts its own chain's ETH.
    /// Everything else (the caption, the odometer roll, the plot, the range
    /// chips, the scrub) is identical, which is why those rooms take this view
    /// now instead of each building a headline of their own.
    var format: (Double) -> String = { WalletValue.money($0) }
    /// The same spelling at full precision, for the CHANGE line under the
    /// number. Separate because the Wallet rounds its crown ("$33K") and never
    /// rounds the delta, and a devnet wants its own unit in both places —
    /// which is the bug Privacy's first conversion showed, reading "$0
    /// (+14.7%)" over a chain that has no dollars (prd §683).
    var exactFormat: (Double) -> String = { WalletValue.exactMoney($0) }
    /// **THE CHANGE IS SHORT (prd §920).** The number above carries the
    /// precision; the change under it carries the meaning, so a devnet's
    /// "▲ 1.0113 ETH (+860.3%)" is "+1.01 ETH · 30 days". nil takes
    /// `exactFormat`, which the Wallet's dollars already spell at two places.
    var changeFormat: ((Double) -> String)? = nil
    /// **THE CHANGE IS DATED (prd §920).** The window the move is measured
    /// over, as words — "30 days", or "since Aug 26" for the whole record —
    /// in the quiet ink after the figure. §483 took the chip's own word
    /// ("watched") off this line because it restated the control beneath;
    /// this is not that word, it is the window's span, and it is the ONE
    /// place the crown says how long a history the line draws. nil draws no
    /// window.
    var window: String? = nil
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
    /// The total last on screen this launch (prd §1587): a remount rolls
    /// from it instead of replaying the entrance.
    @MainActor static var lastShown: Double?
    @MainActor static var flashedPulse = 0
    /// The delta pill waits out the roll — a summary that lands with the thing
    /// it summarizes makes the eye choose, and it chooses wrong (2026-07-22).
    @State private var pillShown = false
    @State private var entered = false

    /// **THE LINE IS GREEN (prd §1259, user: "wallet balance line should be
    /// green. not red or our brand color").** The line draws the balance, not
    /// its direction, so it takes one ink whatever the window did; the signed
    /// figure under the number (`moveLine`) still states the direction in
    /// colour, so a loss is said once, in words.
    private var accent: Color {
        onColor ? .white : TokenChartStyle.accent(up: true, scheme: scheme)
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
            // Only the reading is a door — the chips below are
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
                    .buttonStyle(RowPress())
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
                //
                // NO FILL (prd §1005, user). The gradient wash was the audit's
                // plainest chart tell, and its area — running to zero — held
                // the line in the top tenth of the box, which is the "solid
                // slab" 2026-07-21 measured, at every height. The line alone
                // now takes the box's height for its own range.
                // **THE LINE TAKES WHAT IS LEFT, AT MOST `chartHeight` (prd
                // §1102, user: "also wallet sparkline").** `chartHeight` is a
                // budget counted for the caption and the total alone, so a
                // crown that also said "Couldn't price HyperEVM, Monad — not in
                // this total" ran its line out through the slot's clip. Read
                // the height the stack actually leaves, after every line above
                // and the chips below have theirs (`layoutPriority(-1)`).
                GeometryReader { geo in
                TokenChartPlot(chart: chart, accent: accent, height: geo.size.height, pulses: false,
                               // NO MARKS ON THE LINE (prd §1331, user: "dots
                               // are unnecessary"): no transaction marks, no
                               // ring on the newest. ONE dot says NOW (prd
                               // §1471, amending §1331 and §1005): the line
                               // ends on the latest reading, and a fill
                               // floored at the series' low falls under it
                               // as Stocks draws, so the line reads as the
                               // total said twice rather than a decoration.
                               lineWidth: 2.6, fillOpacity: 0.22,
                               endpointDot: true, fillsToLow: true,
                               // Scrub (2026-08-03, §297): a press-then-drag —
                               // or a resting cursor on the Mac — rolls the
                               // crown number to that sample. The sheet
                               // chart's own scrub, at the headline's dose.
                               cursorIndex: scrubIndex,
                               onScrub: { scrubIndex = $0 })
                }
                .frame(minHeight: 0, maxHeight: chartHeight)
                .layoutPriority(-1)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            // Past every edge by the end dot's radius, or the
                            // mask cuts the dot in half at rest (prd §1471).
                            Rectangle().frame(width: geo.size.width * drawn + 4)
                                .padding(.vertical, -4)
                        }
                    }
                    // Two entrances, two owners: `draw` owns the line's own
                    // mask and replays on a range switch; `enter` owns the
                    // number's roll and fires once ever.
                    // Back on screen after a refresh or a pick (prd §1587):
                    // the line stands drawn and the number rolls from what
                    // was there, never the first open's entrance again.
                    .onAppear { draw(settled: Self.lastShown != nil); enter() }
                    .onChange(of: chart.closes) { draw(redraw: true) }
                    .padding(.top, DS.Space.s1)
                if ranges.count > 1 || whose {
                    // Yours · Everything leads the foot (prd §1526), the
                    // window beside it: one row of choices, never a new one.
                    HStack(spacing: DS.Space.s4) {
                        if whose { WalletWhoseSwitch() }
                        if ranges.count > 1 { rangeChips }
                    }
                    .padding(.top, whose && ranges.count < 2 ? DS.Space.s2 : 0)
                }
            } else if whose {
                // **THE SWITCH NEVER WAITS ON THE LINE (prd §1591, user: "i
                // follow then it won't show my Yours balance").** A scope with
                // fewer than two readings draws no line; the switch rode inside
                // it, so a new Yours stood with no way back to All or Following.
                WalletWhoseSwitch()
                    .padding(.top, DS.Space.s2)
            }
        }
    }

    /// The reading itself — caption, total, delta, and why it moved. Rendered
    /// bare or inside a Button depending on whether there's anything behind a
    /// The caption's words — one `Text` when it describes the reading, two
    /// concatenated when it NAMES a wallet (prd §450).
    ///
    /// **Two inks, one weight (prd §782).** "Across your wallets" is chrome and
    /// stays tertiary; a wallet's NAME answers "which wallet?" and takes
    /// `textSecondary`, while the address tail beside it stays tertiary. A
    /// name carries no weight of its own (§764).
    ///
    /// `scaledFont` rather than `dsText`, because a concatenated `Text` needs
    /// `Text`'s own `.font(_:)` overload to stay `Text`-typed — the exact case
    /// that property exists for, so this is still the ramp and still Dynamic
    /// Type.
    private var captionText: Text {
        let name = Text(caption)
            .font(DSTextStyle.label12.scaledFont)
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
                    // the roll runs the way the money moved.
                    //
                    // **`stat24` since prd §551** (user: "on Wallet, Home,
                    // the balance is in such a large font, but on all the
                    // other screens … the title is smaller. we should be
                    // consistent"). It was `price64` while every OTHER scope
                    // of this same room drew its headline at `stat24`, so the
                    // scope strip — one control, one screen — moved the type
                    // two rungs each time it was used.
                    //
                    // The crown came DOWN to the headline rung rather than the
                    // headlines going up, and that direction was MEASURED —
                    // see `DSRoomSlot`, where the strings these rooms really
                    // draw are listed with their widths. It is still the
                    // biggest figure on its surface (nothing else on this
                    // card sets 24 bold), and still scales with Dynamic Type.
                    //
                    // **`price40` since prd §1471** (amending §551): the
                    // figure IS the surface, so it outranks the screen's
                    // name. §551's ask was one size across the room's scopes,
                    // and Holdings' and every lead's number already stand at
                    // `price40` (§766, `DSFigureReading`); the crown was the
                    // one figure left at the headline rung.
                    Text(format(displayed ?? 0))
                        .dsText(.price40).foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity
                                           : .numericText(value: displayed ?? 0))
                        .lineLimit(1).minimumScaleFactor(0.6)
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
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    if let note {
                        // The one thing the crown owes a reader whose money is
                        // not all here: which place it could not reach.
                        Text(note)
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                            .lineLimit(2)
                    }
                    if let asOf {
                        // WHEN it was read, in the same quiet ink, and only
                        // when that is not now (prd §825). §83: the crown may
                        // stand on a wallet's last reading while the chains
                        // are unreachable — it may not present that reading
                        // as current. Same phrase the stale treemap group's
                        // subline has used since 2026-07-17, so one dated
                        // number reads the same way wherever it is drawn.
                        Text("as of \(AccountPageShape.ago(asOf))")
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
        .frame(maxWidth: .infinity, alignment: .leading)
            // THE RAIN, WHERE THE MONEY LANDED (prd §501). Nothing new is
            // drawn: this is the shower a pull-to-refresh already deals.
            //
            // **IT RAINS WALLET TILES, not berries (prd §655, 2026-09-08 —
            // user: "the confetti is literally confetti and not app tiles …
            // Wallet should be app tiles of just the wallet icon").** §501
            // poured this in the receiving wallet's own face stop so the
            // moment could say WHICH account without a word, and §619 kept
            // the berries alive for exactly that. The ruling above overrides
            // it: EVERY shower in the app is the app's own tiles, and a
            // shower that is confetti anywhere is confetti everywhere in the
            // eye that sees it. The face colour is not lost — the crown
            // retints on the same beat (§159), and the wallet's row and rail
            // stop carry the stop at full strength — so what the rain gave
            // up is a second telling of something already on screen, and
            // what it gained is the one grammar.
            .onChange(of: arrivals.pulse) { _, _ in
                chrome.rain(sources: ["Wallet"])
                // **THE RAIN SAYS HOW MUCH AND WHERE (prd §1587):** "+250 USDC
                // · Savings". The amount stays out under Hide balances.
                // One flash per arrival, however many headlines watch it
                // (the page's, the pane's, the crown's).
                if let address = arrivals.address, Self.flashedPulse != arrivals.pulse {
                    Self.flashedPulse = arrivals.pulse
                    let name = WalletStore.shared.displayName(forWatched: address) ?? WalletStore.shortAddress(address)
                    let amount = BalancePrivacy.shared.withheld ? nil : arrivals.amount.map { "+" + $0 }
                    chrome.flash([amount ?? String(localized: "Money arrived"), name].joined(separator: " · "))
                }
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
        // **A FRACTION, NOT A PERCENT (2026-09-10).** `changeText` and
        // `isFlat` both multiply by 100, so `chart.change` is a fraction —
        // and this branch multiplied by 100 as well, which made every
        // SCRUBBED reading a hundred times its real move. Invisible at rest,
        // because the resting line takes `chart.change` untouched.
        let change = end == nil ? chart.change
            : (first == 0 ? 0 : (last - first) / abs(first))
        let delta = last - first
        // **A LINE THAT STARTS AT ZERO HAS NO PERCENTAGE (2026-09-10).** A
        // devnet account begins at nothing and is funded once, so the first
        // point really is 0 — and a ratio against it is undefined, which the
        // guard above rendered as `0`, i.e. the words "No change" over a
        // balance that had gone from nothing to a whole ETH. The delta is a
        // fact and draws; the percentage is not and does not.
        let ratioless = first == 0 && delta != 0
        // **A MOVE THAT PRINTS AS ZERO IS NO MOVE (prd §750, §83).** Shipped
        // in 589 on a watched roster: "0 ETH ▲ 0 ETH (+100.0%)" — a dust move
        // against a dust start, so the ratio was real arithmetic and the words
        // were a green arrow over nothing. The test is the formatted delta,
        // not a threshold, because what must not happen is a sign and a colour
        // beside a figure that reads 0.
        let roundsToZero = exactFormat(abs(delta)) == exactFormat(0)
        // §837's wipeout guard (a -99.9999% printed as "-100.0%") lived here
        // until prd §920 took the percentage off this line; the delta it
        // protected still draws, so the guard has nothing left to deny.
        let flat = roundsToZero || (!ratioless && TokenChartStyle.isFlat(change))
        let ink = flat ? DS.textSecondary
                       : TokenChartStyle.accent(change: ratioless ? (delta > 0 ? 1 : -1) : change,
                                                scheme: scheme)
        // **A SIGN, A SHORT FIGURE, THE WINDOW (prd §920).** The triangle
        // glyph and the percentage are gone: Stocks and Apple Card state a
        // move as a signed figure and the period it covers, and that is the
        // whole sentence. The wipeout guard (§837) is gone with the
        // percentage it guarded; `ratioless` still decides the sign, the flat
        // test still decides colour, and a true minus (U+2212) keeps the
        // digits aligned.
        let spell = changeFormat ?? exactFormat
        let signed = ((ratioless ? delta : change) >= 0 ? "+" : "\u{2212}") + spell(abs(delta))
        HStack(spacing: 5) {
            Text(flat ? String(localized: "Unchanged") : signed)
                .dsText(.body17)
                .foregroundStyle(ink)
                .monospacedDigit()
            if let window {
                Text(verbatim: "· \(window)")
                    .dsText(.body17)
                    .foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    /// The window chips — the token chart's own grammar, at the wallet's dose.
    /// Only drawn with a real choice to make (see `WalletRange.offered`).
    /// **LIFTED OUT (prd §686).** The Activity chart offers the same three
    /// windows over the same records, and a control drawn twice drifts — which
    /// is §683's finding one surface up. `DSRangeChips` owns the track, the
    /// concentric corner and the never-draw-a-lone-chip rule; this keeps only
    /// the spacing that belongs to the crown's own stack.
    private var rangeChips: some View {
        DSRangeChips(ranges: ranges, range: range, onPick: onPickRange)
            .padding(.top, DS.Space.s2)
    }

    private func draw(redraw: Bool = false, settled: Bool = false) {
        guard !reduceMotion, !settled else { drawn = 1; return }
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
        // Remounted in this launch (the box re-keys on its total, §1403): roll
        // from the figure that was on screen, the pill already there.
        if let was = Self.lastShown {
            let now = total ?? chart?.price
            Self.lastShown = now ?? was
            pillShown = true
            guard !reduceMotion, let now, was > 0, abs(now - was) / was > 0.001 else { rollLanded = true; return }
            rollAnchor = was
            withAnimation(DS.Motion.standard) { rollLanded = true }
            return
        }
        Self.lastShown = total ?? chart?.price
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
            .buttonStyle(PressSpring())
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
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            } else {
                WalletFace(address: entry.id, size: DS.Face.badge, circular: true)
            }
            Text(WalletValue.money(entry.value))
                .dsText(.label12)
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
    /// How far each borrowing protocol's closest position can fall before
    /// liquidation, by protocol name ("can fall 24%", prd §1107): Risk's
    /// sentence, on the row it is about, now that Risk is not a tile.
    var falls: [String: String] = [:]
    /// The health line a borrow notifies under (`DeFiRisk.alertLine`, prd
    /// §1090), offered from a borrowing row's long press.
    var lineMenu: (() -> AnyView)? = nil

    /// The shared liquidation margin, borrowed by every row: under this a
    /// position is worth worrying about, and the mark goes `DS.attention`
    /// while the subline says "at risk" in words — orange alone means
    /// nothing to anyone who doesn't know where the margin sits (the
    /// 2026-07-21 ruling, kept).
    private static let riskMargin: Double = 1.5

    var body: some View {
        if !aave.isEmpty || !morpho.isEmpty {
            // The group's name is the room's `DSGroupHeader` (prd §945); the
            // second headline ("1 position near its floor") is gone — the one
            // row that needs you says so in red.
            // **CLOSEST TO LIQUIDATION FIRST (prd §1107)**, the order Risk's
            // rows kept; a protocol with no debt follows, in the given order.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rowOrder, id: \.self) { name in
                    switch name {
                    case "Aave":  aaveRow
                    case "Spark": sparkRow
                    default:      morphoRow
                    }
                }
            }
        }
    }

    /// The rows that draw, the lowest health first; no debt (nil) last.
    private var rowOrder: [String] {
        var rows: [(String, Double?)] = []
        if !aavePositions.isEmpty { rows.append(("Aave", aavePositions.compactMap(\.healthFactor).min())) }
        if !sparkPositions.isEmpty { rows.append(("Spark", sparkPositions.compactMap(\.healthFactor).min())) }
        if !morpho.isEmpty { rows.append(("Morpho", morphoHealth)) }
        return rows.enumerated().sorted { a, b in
            switch (a.element.1, b.element.1) {
            case let (x?, y?): return x == y ? a.offset < b.offset : x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.offset < b.offset
            }
        }.map(\.element.0)
    }

    /// A borrowing row's long press: the health line it notifies under.
    @ViewBuilder
    private func withLineMenu<V: View>(_ row: V, borrowing: Bool) -> some View {
        if borrowing, let lineMenu {
            row.contextMenu { lineMenu() }
        } else {
            row
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
        return withLineMenu(
            WalletRow(mark: .asset(title, tint: atRisk ? DS.attention : DS.brandInk),
                      title: title,
                      subtitleText: Self.line(borrowing: borrowing, health: health, atRisk: atRisk,
                                              fall: borrowing ? falls[title] : nil)) {
                WalletRowValue(value: WalletValue.money(borrowing ? debt : collateral))
            },
            borrowing: borrowing)
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
    private var morphoRow: some View {
        let atRisk = (morphoHealth ?? .infinity) < Self.riskMargin
        let borrowing = morphoDebt > 0
        // Morpho's two faces differ in one word: borrowing says how far it
        // can fall, earning says it earns (prd §1338: one fact a row).
        let subtitle = borrowing
            ? Self.line(borrowing: true, health: morphoHealth, atRisk: atRisk, fall: falls["Morpho"])
            : Text("Earning").foregroundStyle(DS.textTertiary)
        return withLineMenu(
            WalletRow(mark: .asset("Morpho", tint: atRisk ? DS.attention : DS.brandInk),
                      title: "Morpho", subtitleText: subtitle) {
                WalletRowValue(value: WalletValue.money(borrowing ? morphoDebt : morphoDeposits))
            },
            borrowing: borrowing)
    }

    // MARK: - Sublines

    /// **ONE FACT A ROW (prd §1338, user: "don't need the subtext").** A
    /// borrow says how far it can fall ("can fall 24%", the distance that can
    /// act), its health where that is not known, red only at risk; a supply
    /// says so. The chain, the trend and "Borrowed · Health · …" went: the
    /// figure on the right is the debt, and the sheet carries the rest.
    private static func line(borrowing: Bool, health: Double?, atRisk: Bool, fall: String?) -> Text {
        guard borrowing else { return Text("Supplied").foregroundStyle(DS.textTertiary) }
        let ink = atRisk ? DS.destructiveInk : DS.textTertiary
        if let fall { return Text(fall).foregroundStyle(ink) }
        if let health {
            return Text(String(localized: "Health \(WalletIngest.format(health))")).foregroundStyle(ink)
        }
        return Text("Borrowed").foregroundStyle(DS.textTertiary)
    }
}


/// A wallet tray's height from its measured content (prd §784): the tray's
/// own padding, title and home-indicator allowance on top of what it draws,
/// capped, with the estimate standing in until the first measure lands.
enum WalletTraySize {
    static func height(content: CGFloat, title: CGFloat, cap: CGFloat, estimate: CGFloat) -> CGFloat {
        guard content > 0 else { return min(cap, estimate) }
        return min(cap, content + DS.Space.s6 + title + DS.Space.s4 + DS.Space.s6 + 34)
    }
}
