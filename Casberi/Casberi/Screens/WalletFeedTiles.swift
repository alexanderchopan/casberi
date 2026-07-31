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
enum WalletCardStyle {
    static let fill = 0.82
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
    /// "Across your wallets" on the combined view, "Balance" scoped.
    var caption: String = String(localized: "Balance")
    /// "Mostly ETH · +$310" — WHY the line moved, from the same per-token
    /// snapshots the combined sheet's "What moved" reads. nil when the record
    /// can't attribute the move yet.
    var mover: String? = nil
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
    var onOpenMark: (UUID) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The sparkline's draw-on: 0 → 1 sweeps a mask left to right, so the
    /// line draws itself the way the value accrued — time, moving. Reset
    /// whenever the data itself changes (a scope switch is a new line, and
    /// a new line deserves its own draw).
    @State private var drawn: CGFloat = 0

    private var accent: Color {
        TokenChartStyle.accent(change: chart?.change ?? 0, scheme: scheme)
    }

    /// The number in the headline seat: the live total when the holdings read
    /// has landed, else the last sampled value. nil renders nothing at all —
    /// the caller's own guard, kept here too so this view can't paint a $0
    /// portfolio it doesn't know about.
    private var displayed: Double? { total ?? chart?.price }

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
            if let onOpen {
                Button(action: onOpen) {
                    reading.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                reading
            }

            if let chart {
                // Taller, heavier, and ending on a solid dot (prd §157) — the
                // line is the total said a second way, so it carries weight
                // like the total does.
                // Body in the STROKE, not the fill (measured on screen
                // 2026-07-21): a portfolio line is nearly flat most weeks, so
                // it hugs the top of its box and a 0.30 fill under it paints a
                // solid slab rather than a glow. 2.6pt of line reads as
                // confidence; a heavy fill just reads as a rectangle.
                TokenChartPlot(chart: chart, accent: accent, height: 52, pulses: false,
                               lineWidth: 2.6, fillOpacity: 0.16, endpointDot: true,
                               marks: marks,
                               onTapMark: marks.isEmpty ? nil : { onOpenMark($0.id) },
                               // Wait out the draw-on below, then land (§171).
                               markDelay: 0.95)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * drawn)
                        }
                    }
                    .onAppear { draw() }
                    .onChange(of: chart.closes) { draw(redraw: true) }
                    .padding(.top, DS.Space.s1)
                if ranges.count > 1 { rangeChips }
            } else {
                // No line yet — say why, rather than leaving the number
                // hanging over empty space. The total above it is already
                // real; this is only about the SHAPE not existing yet.
                Text("The line starts once a second reading lands.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    /// The reading itself — caption, total, delta, and why it moved. Rendered
    /// bare or inside a Button depending on whether there's anything behind a
    /// tap; identical either way.
    private var reading: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(spacing: 5) {
                        // Quieter than it was (prd §157): hierarchy is the GAP
                        // between the loud thing and the quiet one, and a
                        // secondary-ink caption over a 48pt total left the two
                        // arguing. The caption steps back so the number can
                        // step forward.
                        Text(caption)
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                        // The door — only where a breakdown exists (the multi-
                        // wallet "All" view). A chevron promises more behind
                        // the tap.
                        if onOpen != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                        // The app's money voice ($19.9K), not a token price — this is
                        // a portfolio total, and `TokenStats.compact` is what the
                        // combined sheet and the wallet row sublines already speak.
                        // The digits ROLL between values (a scope switch re-keys the
                        // number, and $20K odometer-rolling to $4.2K says "same
                        // instrument, new reading"). Direction rides the value, so
                        // the roll runs the way the money moved. `price40` is the
                        // sanctioned big-money rung (prd §102), so it scales with
                        // Dynamic Type like everything else.
                        Text(TokenStats.compact(displayed ?? 0))
                            .dsText(.price48).foregroundStyle(DS.textPrimary)
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity
                                               : .numericText(value: displayed ?? 0))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        // The window the delta is measured over, named — the
                        // record's own span ("watched") or a calendar window
                        // it actually covers. Nothing to measure yet, no pill.
                        if let chart {
                            TokenDeltaPill(change: chart.change,
                                           label: range.deltaLabel, compact: true)
                        }
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
                    Text(r.rawValue)
                        .dsText(.label12)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(r == range ? DS.textPrimary : DS.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(r == range ? DS.fillFaint : .clear,
                                    in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private func draw(redraw: Bool = false) {
        guard !reduceMotion else { drawn = 1; return }
        if redraw { drawn = 0 }
        withAnimation(.easeOut(duration: 0.8).delay(redraw ? 0.05 : 0.25)) { drawn = 1 }
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
                    .background(DS.fillFaint,
                                in: RoundedRectangle(cornerRadius: DS.Radius.widget,
                                                     style: .continuous))
            }
            .buttonStyle(.plain)
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

    var body: some View {
        if !composition.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                WalletSectionLabel(title: String(localized: "In protocols"))
                if composition.hasDeposited {
                    line(title: String(localized: "Deposited"),
                         places: composition.depositedPlaces,
                         value: TokenStats.compact(composition.deposited),
                         onOpen: onOpenDeposits)
                }
                if composition.hasLocked {
                    line(title: String(localized: "Locked"),
                         places: composition.lockedPlaces,
                         value: lockedValue,
                         onOpen: onOpenLocks)
                }
                if composition.hasOwed {
                    // The minus is spelled, never implied by color: red here
                    // would claim urgency the room spends color on elsewhere
                    // (a liquidation, an active approval), and a debt you
                    // opened on purpose isn't an alarm.
                    line(title: String(localized: "Owed"),
                         places: composition.owedPlaces,
                         value: "−" + TokenStats.compact(composition.owed),
                         onOpen: nil)
                }
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget,
                                             style: .continuous))
        }
    }

    /// "12,977 AERO · 340 HYPE" — the locked total per UNIT. Individual locks
    /// live in the tray; here they merge, because a sum of AERO is still AERO
    /// (a sum of end dates would be nothing, which is why the tray exists).
    private var lockedValue: String {
        composition.lockedTotals
            .map { "\(WalletIngest.format($0.amount)) \($0.symbol)" }
            .joined(separator: " · ")
    }

    /// `callout15`, not `WalletRow`'s `rowTitle17`: these sit INSIDE the
    /// balance card under a 48pt number, and a row-weight title here would
    /// argue with the crown instead of supporting it. Same reasoning that
    /// stepped the headline's own caption back (prd §157).
    @ViewBuilder
    private func line(title: String, places: [String], value: String,
                      onOpen: (() -> Void)?) -> some View {
        if let onOpen {
            Button(action: onOpen) {
                lineBody(title: title, places: places, value: value, door: true)
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
                            .font(.system(size: 9, weight: .semibold))
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
            Text(value)
                .dsText(.price16).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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

    var body: some View {
        DSTray(title: String(localized: "Deposited"),
               height: min(560, CGFloat(170 + composition.deposits.count * 64))) {
            ScrollView {
                VStack(spacing: DS.Space.s1) {
                    ForEach(composition.deposits) { deposit in
                        row(deposit)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ deposit: WalletComposition.Deposit) -> some View {
        let total = composition.deposited
        let share = total > 0 ? deposit.usd / total : 0
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                Text(deposit.place)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(TokenStats.compact(deposit.usd))
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                if total > 0 {
                    Text("\(Int((share * 100).rounded()))%")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .monospacedDigit()
                }
            }
            ShareBar(fraction: share, tint: DS.tint)
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

    var body: some View {
        DSTray(title: String(localized: "Locked"),
               height: min(560, CGFloat(170 + composition.locks.count * 74))) {
            ScrollView {
                VStack(spacing: DS.Space.s1) {
                    ForEach(composition.locks) { lock in
                        row(lock)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ lock: WalletComposition.Lock) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                Text("\(WalletIngest.format(lock.amount)) \(lock.symbol)")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(lock.place)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            if let remaining = lock.remaining {
                ShareBar(fraction: remaining, tint: DS.tint)
            } else if lock.isPermanent {
                ShareBar(fraction: 1, tint: DS.tint)
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
                "\(WalletIngest.format(power)) votes left · \(Int((remaining * 100).rounded()))%"))
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
            .background(DS.surfaceSheet,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .dsHover()
    }
}

/// A share of a whole, as a filled track — the room's one bar shape, used by
/// both composition trays. A fill, never a rule: the design law's no-hairlines
/// ban is about LINES that divide, and this is a quantity with a length.
private struct ShareBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(DS.fillFaint)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
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
struct WalletFaceChips: View {
    struct Entry: Identifiable {
        let id: String        // the address — stable, value-typed
        let value: Double
        let change: Double
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

    private func chip(_ entry: Entry) -> some View {
        Button {
            DSHaptic.selection()
            onPick(entry.id)
        } label: {
            HStack(spacing: 6) {
                WalletFace(address: entry.id, size: 20, circular: true)
                Text(TokenStats.compact(entry.value))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                Text(TokenChartStyle.changeText(entry.change))
                    .dsText(.label12)
                    .foregroundStyle(TokenChartStyle.accent(change: entry.change, scheme: scheme))
                    .monospacedDigit()
            }
            .padding(.leading, 4).padding(.trailing, DS.Space.s3).padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(DS.fillFaint))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
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

    var body: some View {
        if !aave.isEmpty || !morpho.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                WalletSectionLabel(title: String(localized: "Lending"))
                    .padding(.bottom, 2)
                if !aavePositions.isEmpty { aaveRow }
                if !sparkPositions.isEmpty { sparkRow }
                if !morpho.isEmpty { morphoRow }
            }
            .padding(DS.Space.s4)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    // MARK: - Aave / Spark (same shape, one row each, filtered by protocol)

    private var aavePositions: [WalletDeFi.Position] { aave.filter { $0.protocolName == "Aave" } }
    private var sparkPositions: [WalletDeFi.Position] { aave.filter { $0.protocolName == "Spark" } }

    private func lendingRow(_ positions: [WalletDeFi.Position], title: String, monogram: String) -> some View {
        let collateral = positions.reduce(0) { $0 + $1.totalCollateralUSD }
        let debt = positions.reduce(0) { $0 + $1.totalDebtUSD }
        // The riskiest health factor across positions — nil when nothing is
        // borrowed anywhere (the protocol's no-debt sentinel), which is not
        // a zero.
        let health = positions.compactMap(\.healthFactor).min()
        let atRisk = (health ?? .infinity) < Self.riskMargin
        let borrowing = debt > 0
        return WalletRow(mark: .monogram(monogram, tint: atRisk ? DS.attention : DS.tint),
                         title: title,
                         subtitle: Self.line(health: health, atRisk: atRisk,
                                             chains: positions.map(\.network))) {
            WalletRowValue(value: TokenStats.compact(borrowing ? debt : collateral),
                           caption: borrowing ? String(localized: "borrowed")
                                              : String(localized: "supplied"))
        }
    }

    private var aaveRow: some View {
        lendingRow(aavePositions, title: "Aave", monogram: "AA")
    }

    private var sparkRow: some View {
        lendingRow(sparkPositions, title: "Spark", monogram: "SP")
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
        return WalletRow(mark: .monogram("MO", tint: atRisk ? DS.attention : DS.tint),
                         title: "Morpho", subtitle: subtitle) {
            WalletRowValue(value: TokenStats.compact(borrowing ? morphoDebt : morphoDeposits),
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


/// The concentration read (2026-07-21, prd §155) — "ETH is 62% of everything",
/// a quiet line under the treemap. Portfolio-level by nature: it says nothing
/// about any one holding and everything about the shape of the whole, which is
/// exactly the read the combined view exists to give. One computed sentence,
/// no card, no color — risk posture at a glance, never advice.
///
/// With more than one wallet it's also the door to the full allocation: the
/// treemap says WHAT you hold, this says how much of it is one thing, and the
/// tray behind it says WHERE each position actually sits.
struct WalletConcentrationLine: View {
    let portfolio: WalletPortfolio
    /// nil with a single wallet — there's no "where" to open, and a chevron
    /// would promise a page that says the same thing twice.
    let onOpen: (() -> Void)?

    var body: some View {
        if let line = portfolio.concentrationLine {
            Button { onOpen?() } label: {
                HStack(spacing: 5) {
                    Text(line)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    if onOpen != nil {
                        Text("Where it's held")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
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
                Text(position.symbol)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(TokenStats.compact(position.usd))
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
                        WalletFace(address: holder.address, size: 16)
                        Text(holder.label)
                            .dsText(.label12).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Text(TokenStats.compact(holder.usd))
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
    /// active (`WalletApprovals.activeApprovals`) — each becomes its own row
    /// with a door to that wallet's Revoke.cash page.
    let activeApprovals: [Thing]
    @Environment(\.openURL) private var openURL
    @State private var jumpTarget: String?
    /// Mirrors `WalletAwareness.isMuted` locally so toggling redraws THIS
    /// tray immediately; the plain UserDefaults flag underneath is what the
    /// feed card re-reads fresh the next time it's built.
    @State private var muted = WalletAwareness.isMuted
    /// Collapsed by default (2026-07-24) — spam you can't act on doesn't
    /// deserve the same standing scroll real estate the actionable rows
    /// get. Expands in place; the sheet's own height grows to fit since
    /// `trayHeight` reads this same state.
    @State private var awareExpanded = false
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
            case .liquidation(let w): "liquidation:\(w.id)"
            case .approval(let id, _): "approval:\(id)"
            case .delegation(let w): "delegation:\(w.id)"
            case .safe(let w): "safe:\(w.id)"
            }
        }
    }

    private var actionRows: [ActionRow] {
        liquidation.map(ActionRow.liquidation)
            + activeApprovals.map { ActionRow.approval(id: $0.id.uuidString, thing: $0) }
            + delegations.map(ActionRow.delegation)
            + safeSignatures.map(ActionRow.safe)
    }

    private var hasActionable: Bool { !actionRows.isEmpty }
    private var actionableRowCount: Int { actionRows.count }

    /// The two jump targets — "act" and "aware" — each dropped when empty.
    /// The jump bar (only shown once there's real ground to cover) is built
    /// off this same list, so the two can never disagree about what's on
    /// screen.
    private var superSectionIDs: [String] {
        var ids: [String] = []
        if hasActionable { ids.append("act") }
        if !flagged.isEmpty { ids.append("aware") }
        return ids
    }

    /// The tray's own ceiling — past this the content scrolls within the
    /// natural-height detent below. Raised from 620 (2026-07-24, user: "it
    /// could be taller") — the tray also now offers `.large` as a second
    /// detent (see `trayDetents`) so a long pile can be dragged open past
    /// even this, but the natural-height detent still caps here first.
    private static let maxTrayHeight: CGFloat = 720
    /// A "Worth doing" row carries an icon, a wrapping title, a subtitle
    /// line (2026-07-24) and, since 2026-07-31, its own card padding — so it
    /// prices well above the bare one-line rows the aware pile still uses.
    /// First-frame guess only; `contentHeight` measures the truth one pass
    /// later (see `estimatedContentHeight`).
    private static let actionRowHeight: CGFloat = 66 + 2 * DS.Space.s3
    /// The aware pile's expanded rows stay bare one-liners — spam doesn't
    /// need the same per-row weight the actionable rows earn.
    private static let rowHeight: CGFloat = 46
    /// A section header carries a glyph, a count, and its own one-line
    /// explainer beneath, so it's taller than a bare row.
    private static let headerHeight: CGFloat = 58

    /// The FIRST-FRAME guess only, and only for the content — what the rows
    /// are probably worth before anything has actually been laid out, so the
    /// sheet opens near its final size instead of animating up from nothing.
    /// `contentHeight` (measured) replaces it on the very next pass, and
    /// that swap is the fix (2026-07-26) for the whole class of bug this
    /// guess kept producing: it prices every actionable row at a flat
    /// `actionRowHeight`, but a real one carries a WRAPPING title
    /// ("vitalik.eth delegates to 0x5a7f…6f6d on Ethereum" is two lines
    /// beside a Revoke pill, not one), and no arithmetic here can know how
    /// many lines a string takes at the user's type size. Understating three
    /// delegation rows is what pushed the "Just so you know" line below the
    /// fold (user, 2026-07-26: "spam transfers is below the fold and
    /// shouldn't be"). The per-row and per-group `VStack` spacings the
    /// earlier version also omitted ARE counted here now, so the opening
    /// frame is close even before the measurement lands.
    private var estimatedContentHeight: CGFloat {
        var h: CGFloat = 0
        if hasActionable {
            h += 46 + DS.Space.s4 // the "Worth doing" group label + its explainer line
            h += CGFloat(actionableRowCount) * Self.actionRowHeight
            h += CGFloat(actionableRowCount - 1) * DS.Space.s2
        }
        if hasActionable && !flagged.isEmpty { h += DS.Space.s6 }
        if !flagged.isEmpty {
            // The "Just so you know" label + the boxed summary row.
            h += 30 + Self.headerHeight
            if awareExpanded { h += CGFloat(flagged.count) * Self.rowHeight + 40 }
        }
        return h + DS.Space.s2 // the content VStack's own bottom padding
    }

    /// Everything the sheet spends before the scrolling content gets a
    /// point: `DSTray`'s top padding, its heading, the gap beneath it, its
    /// bottom padding, and the home-indicator inset — which the detent
    /// height INCLUDES but the content can never draw into, and which the
    /// old estimate left out entirely. Over-allowing it on a device without
    /// one costs a little dead space; under-allowing it hides a row, and
    /// only one of those is a bug.
    private var chromeHeight: CGFloat {
        DS.Space.s6 + trayTitleHeight + DS.Space.s4 + DS.Space.s6 + Self.homeIndicatorAllowance
    }
    private static let homeIndicatorAllowance: CGFloat = 34

    /// What the tray WOULD be with nothing clipped — the honest measure the
    /// overflow gate reads, before the cap flattens it. Reads
    /// `awareExpanded` (through the measured content), so the sheet visibly
    /// grows when the spam pile is opened and settles back when it's closed,
    /// both capped at `maxTrayHeight`.
    private var uncappedHeight: CGFloat {
        (contentHeight > 0 ? contentHeight : estimatedContentHeight) + chromeHeight
    }

    /// Chips exist to save a SCROLL, so the gate is overflow — not a
    /// taxonomy count (2026-07-23, superseding the old `> 3 sections`
    /// rule; kept unchanged by the Act/Aware split). The bar shows when the
    /// content actually overflows the sheet AND there's more than one
    /// group to jump between (jumping within a lone group is a no-op) —
    /// which in practice now means "the spam pile is expanded and long",
    /// since a short, spam-free 'Worth doing' rarely overflows on its own.
    /// Overflow is the MEASURED overflow now, so the bar shows when there
    /// really is more here than fits, not when the guess said so.
    private var showsJumpBar: Bool {
        superSectionIDs.count > 1 && uncappedHeight > Self.maxTrayHeight
    }

    /// The jump bar costs its own height plus the gap to the content below.
    private static let jumpBarHeight: CGFloat = 44

    private var trayHeight: CGFloat {
        min(Self.maxTrayHeight,
            uncappedHeight + (showsJumpBar ? Self.jumpBarHeight + DS.Space.s3 : 0))
    }

    /// Resizable now (2026-07-24, user: "it could be taller") — opens at its
    /// natural `trayHeight` but can be dragged up to `.large` when the
    /// content (especially the expanded "Just so you know" pile) runs long,
    /// instead of hard-clipping at `maxTrayHeight` with no way out but the
    /// jump bar.
    private var trayDetents: Set<PresentationDetent> {
        [.height(trayHeight), .large]
    }

    var body: some View {
        NavigationStack(path: $path) {
        DSTray(title: String(localized: "Worth a look"), height: trayHeight, ink: true, detents: trayDetents) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if showsJumpBar { jumpBar }
                    ScrollView {
                        // Explicit maxHeight is load-bearing here, not
                        // decoration: nesting this ScrollView one level
                        // deeper than the tray's usual `DSTray { ScrollView
                        // {...} }` shape (to fit the jump bar above it) meant
                        // it no longer inherited DSTray's implicit "fill the
                        // sheet's remaining height" sizing — without this the
                        // whole VStack just sized to its natural (taller than
                        // the sheet) height and silently clipped instead of
                        // scrolling (caught on-device: rows past the fold
                        // were simply unreachable, no visible bug in a
                        // screenshot of the top of the tray alone).
                        VStack(alignment: .leading, spacing: DS.Space.s6) {
                            if hasActionable {
                                // Rows carry their own padding now that each
                                // wears a surface, so the gap between them
                                // steps down from s4 to s2 — the card edges
                                // are doing the separating the air used to.
                                VStack(alignment: .leading, spacing: DS.Space.s2) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: DS.Space.s2) {
                                            // Secondary, not `DS.attention`
                                            // (2026-07-31): this is a LABEL,
                                            // not a warning. Orange here put
                                            // a third tint in a sheet that
                                            // already spends red on a live
                                            // liquidation and blue on the
                                            // doors, and since every row
                                            // under it is actionable by
                                            // definition, the color wasn't
                                            // discriminating anything — it
                                            // just tinted the section and
                                            // competed with the one row that
                                            // had earned a color.
                                            Text("Worth doing")
                                                .dsText(.label12).fontWeight(.semibold)
                                                .foregroundStyle(DS.textSecondary)
                                            Text("\(actionableRowCount)")
                                                .dsText(.label12).foregroundStyle(DS.textSecondary)
                                                .monospacedDigit()
                                        }
                                        Text("You can still change how these turn out.")
                                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                    }
                                    .padding(.horizontal, 3)
                                    // A flat list now (2026-07-24, matching
                                    // the approved mockup) — no Position
                                    // risk/Approvals/Delegations/Safe
                                    // sub-headers; each row states its own
                                    // whole fact and carries its own icon
                                    // and, where one exists, its own
                                    // Revoke.cash button. ONE ForEach over
                                    // the unified `actionRows`, not four
                                    // sibling conditionals — see that
                                    // property's doc comment.
                                    ForEach(actionRows) { item in
                                        switch item {
                                        case .liquidation(let w): liquidationRow(w)
                                        case .approval(_, let t): approvalActionRow(t)
                                        case .delegation(let w): delegationRow(w)
                                        case .safe(let w): safeRow(w)
                                        }
                                    }
                                }
                                .id("act")
                            }
                            if !flagged.isEmpty { awareSection }
                        }
                        .padding(.bottom, DS.Space.s2)
                        // The content's REAL height, which is what the tray
                        // sizes itself to (see `uncappedHeight`). A
                        // ScrollView never constrains its content
                        // vertically, so this is the natural, unclipped
                        // height AND it doesn't move when the sheet does —
                        // dragging the tray to `.large` and back leaves it
                        // untouched, so feeding it back into the detent
                        // can't chase its own tail. Measuring the scroll
                        // VIEWPORT instead would: a viewport reports
                        // whatever height the sheet currently happens to
                        // have, mid-drag included. Declared INSIDE
                        // `scrollTargetLayout()` so that stays the outermost
                        // modifier on the content, where `scrollPosition`
                        // below expects to find it.
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                            contentHeight = h
                        }
                        .scrollTargetLayout()
                    }
                    // `scrollPosition`, not `ScrollViewReader.scrollTo`
                    // (2026-07-23): scrollTo silently no-oped on device — the
                    // chip lit (its own tap state) and the list never moved
                    // (user: "nothing is happening when i click the chips").
                    // The position binding is the API AppsScreen's category
                    // rail already ships on, and it's honest in BOTH
                    // directions for free: tap a chip to scroll, or scroll
                    // and watch the right chip light up.
                    .scrollPosition(id: $jumpTarget, anchor: .top)
                    .scrollIndicators(.hidden)
                }
                .frame(maxHeight: .infinity, alignment: .top)
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
                .dsInk()
        }
        }
    }

    // MARK: - Jump bar

    /// Two chips now, not five (2026-07-24) — "Worth doing" and "Just so
    /// you know", matching the Act/Aware split above. A tap scrolls to the
    /// group and lights its chip — nothing hides — and because the chips
    /// share the ScrollView's own `scrollPosition` binding, scrolling by
    /// hand lights the right chip too. Anatomy (2026-07-23, user: "channel
    /// Cash App"): severity dot + bold word + muted count, in a chunky
    /// capsule. The aware chip's dot grays out once muted, echoing the
    /// section's own state.
    private var jumpBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.Space.s2) {
                ForEach(superSectionIDs, id: \.self) { id in
                    jumpChip(id)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func jumpChip(_ id: String) -> some View {
        let active = jumpTarget == id || (jumpTarget == nil && id == superSectionIDs.first)
        let hasLiquidation = !liquidation.isEmpty
        let dotColor: Color = id == "act"
            ? (hasLiquidation ? DS.destructive : DS.attention)
            : (muted ? DS.textTertiary : DS.attention)
        return Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { jumpTarget = id }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(id == "act" ? String(localized: "Worth doing") : String(localized: "Just so you know"))
                    .dsText(.subhead13).fontWeight(.semibold)
                Text("\(id == "act" ? actionableRowCount : flagged.count)")
                    .dsText(.subhead13).fontWeight(.semibold)
                    .monospacedDigit()
                    .opacity(0.45)
            }
            .foregroundStyle(active ? DS.surfaceSheet : DS.textPrimary)
            .padding(.horizontal, DS.Space.s4 - 2).padding(.vertical, 9)
            .background(Capsule().fill(active ? DS.textPrimary : DS.surfaceWell))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Just so you know (the aware pile, collapsed + mutable)

    /// The awareness section — one collapsed line by default, count-led
    /// ("15 spam transfers · nothing to do"), expanding in place to list
    /// each flagged transfer with a door to its sheet. Boxed on a well
    /// background (2026-07-24, matching the mockup's "aware-line" treatment)
    /// so it reads as a quiet, self-contained pile rather than another bare
    /// list row — the visual cue that this is the one group that ISN'T a
    /// stream of individually-worth-reading items. Never destructive red,
    /// muted or not: this is spam you can recognize, not a live risk (that
    /// read is reserved for "Worth doing"). Muting stops it badging the
    /// feed card (`WalletWarningsLine`) without hiding it here — the tray
    /// still shows you what you muted, it just stops shouting about it
    /// elsewhere.
    private var awareSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Just so you know")
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 3)
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { awareExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "photo.badge.exclamationmark.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(DS.surfaceSheet))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(flagged.count == 1
                             ? String(localized: "1 spam transfer")
                             : String(localized: "\(flagged.count) spam transfers"))
                            .dsText(.callout15).fontWeight(.medium).foregroundStyle(DS.textPrimary)
                        Text(muted
                             ? String(localized: "Muted — won't badge your feed")
                             : String(localized: "Fake tokens sent to you — nothing to do"))
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: awareExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
                .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                        .fill(DS.surfaceWell))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if awareExpanded {
                VStack(spacing: 0) {
                    // Corollary 3 (build 176) — see `ThingRowKeying`.
                    ForEach(flagged.keyed) { row in
                        if let thing = row.live { flaggedRow(thing) }
                    }
                }
                Button {
                    DSHaptic.tap()
                    muted.toggle()
                    WalletAwareness.isMuted = muted
                } label: {
                    Text(muted ? String(localized: "Unmute")
                               : String(localized: "Mute — stop badging my feed"))
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.tint)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 3)
                .padding(.top, DS.Space.s1)
            }
        }
        .id("aware")
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
    private func actionRow(icon: String, hot: Bool, title: String, subtitle: String?,
                           door: (label: String, url: URL)?) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
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
                    openURL(door.url)
                } label: {
                    HStack(spacing: 3) {
                        Text(door.label)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s3).padding(.vertical, 7)
                    .background(Capsule().fill(DS.tint.opacity(0.16)))
                }
                .buttonStyle(.plain)
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
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    private func liquidationRow(_ w: WalletWarning) -> some View {
        actionRow(icon: "chart.line.downtrend.xyaxis", hot: true, title: w.title,
                  subtitle: w.subtitle, door: door(w))
    }

    /// An approval thing already carries its own Revoke.cash page as
    /// `content` (`WalletApprovals`' own field); its chain (not otherwise
    /// tracked as a dedicated field) is read back out of `sourceRef`.
    private func approvalActionRow(_ thing: Thing) -> some View {
        actionRow(icon: "key.fill", hot: false, title: thing.title,
                  subtitle: approvalChain(thing),
                  door: URL(string: thing.content).map { (String(localized: "Revoke"), $0) })
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
    private func door(_ w: WalletWarning) -> (label: String, url: URL)? {
        guard let action = w.action, let url = URL(string: action.url) else { return nil }
        return (action.label, url)
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

    /// A flagged transfer — its title (the amount, wearing the confusable
    /// symbol as its own tell) is the differentiator; WHY it's flagged is the
    /// aware pile's own explainer's job, not a repeated subtitle. Taps into
    /// its sheet, which still states the specific poisoning/spoof verdict.
    private func flaggedRow(_ thing: Thing) -> some View {
        Button {
            DSHaptic.selection()
            path.append(thing)
        } label: {
            HStack(spacing: DS.Space.s3) {
                Text(thing.title).dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(DS.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
