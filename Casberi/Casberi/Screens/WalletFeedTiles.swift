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

/// One tile's shell — the shared anatomy so the two never drift: caption row
/// with an optional glyph and a chevron, then the tile's own body.
private struct WalletTile<Content: View>: View {
    let caption: String
    var glyph: String? = nil
    var glyphTint: Color = DS.attention
    /// False when the tile IS the whole read — no door, no chevron (the
    /// honesty rule: a chevron promises more behind the tap).
    var showChevron = true
    @ViewBuilder var content: Content

    /// Flipped once on appear so the glyph bounces exactly one beat as the
    /// tile lands — attention paid, never nagged. `.symbolEffect` is the
    /// system's own vocabulary and honors Reduce Motion by itself.
    @State private var glyphBeat = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: 5) {
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(glyphTint)
                        .symbolEffect(.bounce, options: .nonRepeating, value: glyphBeat)
                        .onAppear {
                            // A breath after the tile's own entrance settles,
                            // so the beat reads as punctuation, not collision.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                glyphBeat = true
                            }
                        }
                }
                Text(caption)
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
            }
            content
        }
        // Stretch to the tallest sibling: two tiles side by side reading as
        // two different heights looked broken (user, 2026-07-20). The HStack
        // sizes to the taller one; this makes the shorter one fill it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.s3)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }
}

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

/// Worth a look — the security read, as its own CARD (2026-07-23, prd §196,
/// superseding §146's line). §146 demoted this to a line because a permanent
/// half-width card reserved prominent space for warnings that are usually
/// absent — still true, and still why this only renders at all when
/// `warnings` isn't empty. What changed is what fills the space once it DOES
/// render: a badge per warning KIND (its own tinted glyph + count, the same
/// glyphs `WalletWorthALookTray`'s section headers wear one tap away) reads
/// faster than the old run-on caption ("12 fake symbols · 3 delegations" as
/// one sentence) and gives the door somewhere to put real content instead of
/// text alone — the honest reason a line earns a card back.
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
/// `isMuted` addresses lets a person who's recognized the spam say so; muted
/// kinds drop out of both the icon color and the badge row entirely, so the
/// card can actually go quiet.
struct WalletWarningsLine: View {
    let warnings: [WalletWarning]
    let onOpen: () -> Void

    /// What the card actually shows — every kind when unmuted, only the
    /// actionable ones once the awareness pile is muted. Never severity
    /// alone; `isActionable` is the axis now.
    private var visible: [WalletWarning] {
        WalletAwareness.isMuted ? warnings.filter { $0.kind.isActionable } : warnings
    }

    var body: some View {
        if !visible.isEmpty {
            let hasLiquidation = visible.contains { $0.kind == .liquidation }
            let hasActionable = visible.contains { $0.kind.isActionable }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    HStack(spacing: DS.Space.s2) {
                        // Red only for the one genuinely time-sensitive thing
                        // (a position about to liquidate); orange for
                        // anything else actionable; a plain info mark when
                        // all that's left unmuted is the aware pile — spam
                        // alone earns no alarm color at all.
                        Image(systemName: hasLiquidation || hasActionable
                              ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(hasLiquidation ? DS.destructive
                                             : hasActionable ? DS.attention : DS.textSecondary)
                            .accessibilityHidden(true)
                        Text("Worth a look")
                            .dsText(.callout15).foregroundStyle(DS.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                    }
                    badges
                }
                .padding(DS.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    private var badges: some View {
        // Wraps rather than scrolls: today's typical 1–2 active kinds never
        // need it, and a wallet with every kind active (5) still fits two
        // short rows in the balance card's own width before truncating.
        FlowLayout(spacing: DS.Space.s2) {
            ForEach(WalletWatch.breakdown(visible), id: \.kind) { entry in
                let hot = entry.kind == .liquidation
                let actionable = entry.kind.isActionable
                HStack(spacing: 6) {
                    Image(systemName: entry.kind.glyph)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hot ? DS.destructive : actionable ? DS.attention : DS.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill((hot ? DS.destructive : actionable ? DS.attention : DS.textTertiary)
                                .opacity(0.16)))
                    Text("\(entry.count)")
                        .dsText(.callout15).fontWeight(.semibold).foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                    Text(entry.kind.label(entry.count))
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                .padding(.leading, 3).padding(.trailing, 10).padding(.vertical, 3)
                .background(Capsule().fill(DS.surfaceWell))
            }
        }
    }
}

/// DeFi — Aave collateral, debt, and health factor, moved up from the wallet
/// detail page (2026-07-20). The treemap says what you HOLD; only this can say
/// what you OWE, which is why it earns a seat beside it rather than staying two
/// taps down. A wallet with no position renders nothing.
///
/// The health factor is the one number here that carries state: `DS.attention`
/// under Aave's 1.5 margin, plain ink above it. Below 1.0 risks liquidation —
/// but that case has already filed a critical warning in the tile above, so
/// this stays a reading, not a second alarm.
struct WalletDeFiTile: View {
    let positions: [WalletDeFi.Position]

    private var collateral: Double { positions.reduce(0) { $0 + $1.totalCollateralUSD } }
    private var debt: Double { positions.reduce(0) { $0 + $1.totalDebtUSD } }
    /// The riskiest health factor across positions — nil when nothing is
    /// borrowed anywhere (Aave's no-debt sentinel), which is not a zero.
    private var health: Double? { positions.compactMap(\.healthFactor).min() }

    private var caption: String {
        guard positions.count == 1, let p = positions.first else {
            return String(localized: "DeFi · Aave")
        }
        let chain = WalletIngest.displayName(forNetwork: p.network) ?? p.network
        return String(localized: "DeFi · Aave on \(chain)")
    }

    var body: some View {
        // No door on purpose: collateral, debt, and health ARE the whole
        // in-app read (acting on a position happens on Aave, not here), and
        // a chevron would promise a page that doesn't exist.
        WalletTile(caption: caption, showChevron: false) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                stat(String(localized: "Collateral"),
                     TokenStats.compact(collateral), tint: DS.textPrimary)
                stat(String(localized: "Debt"),
                     TokenStats.compact(debt), tint: DS.textPrimary)
                // The label says "at risk" when the number is (2026-07-21):
                // orange alone meant nothing to anyone who doesn't know where
                // Aave's margin sits, and this is the one stat here that is
                // about losing money.
                stat((health ?? .infinity) < 1.5
                        ? String(localized: "Health · at risk") : String(localized: "Health"),
                     health.map { WalletIngest.format($0) } ?? String(localized: "No debt"),
                     tint: (health ?? .infinity) < 1.5 ? DS.attention : DS.textPrimary)
            }
            .padding(.top, DS.Space.s1)
        }
    }

    private func stat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
            Text(value).dsText(.price16).foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// DeFi — the Morpho book (2026-07-21), the Aave tile's sibling. Morpho has
/// two faces the tile adapts between: BORROWING (isolated markets with
/// collateral, debt, and a per-market health factor — the Aave layout
/// verbatim, worst market leading) and EARNING (vault deposits — one
/// Deposits stat, "No debt" where health would be). A wallet with neither
/// renders nothing.
struct WalletMorphoTile: View {
    let book: MorphoDeFi.Book

    /// Vault deposits + market-side lending, the earn total.
    private var deposits: Double {
        book.vaults.reduce(0) { $0 + $1.usd }
            + book.positions.reduce(0) { $0 + $1.supplyUSD }
    }
    private var collateral: Double { book.positions.reduce(0) { $0 + ($1.collateralUSD ?? 0) } }
    private var debt: Double { book.positions.reduce(0) { $0 + $1.borrowUSD } }
    /// The riskiest market — Morpho markets are isolated, so the worst one
    /// is the one that liquidates first; nil when nothing is borrowed.
    private var health: Double? { book.positions.compactMap(\.healthFactor).min() }

    private var caption: String {
        let markets = book.positions.count + book.vaults.count
        guard markets == 1,
              let network = book.positions.first?.network ?? book.vaults.first?.network,
              let chain = WalletIngest.displayName(forNetwork: network) else {
            return String(localized: "DeFi · Morpho")
        }
        return String(localized: "DeFi · Morpho on \(chain)")
    }

    var body: some View {
        // No door, same reason as the Aave tile: these numbers ARE the whole
        // in-app read; acting on a position happens on Morpho, not here.
        WalletTile(caption: caption, showChevron: false) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                if debt > 0 {
                    // Borrowing face — the Aave layout. Collateral can be
                    // unpriced on Morpho (measured); deposits stand in only
                    // when there's genuinely no priced collateral to state.
                    if collateral > 0 {
                        stat(String(localized: "Collateral"),
                             TokenStats.compact(collateral), tint: DS.textPrimary)
                    } else if deposits > 0 {
                        stat(String(localized: "Deposits"),
                             TokenStats.compact(deposits), tint: DS.textPrimary)
                    }
                    stat(String(localized: "Debt"),
                         TokenStats.compact(debt), tint: DS.textPrimary)
                    stat((health ?? .infinity) < 1.5
                            ? String(localized: "Health · at risk") : String(localized: "Health"),
                         health.map { WalletIngest.format($0) } ?? String(localized: "No debt"),
                         tint: (health ?? .infinity) < 1.5 ? DS.attention : DS.textPrimary)
                } else {
                    // Earning face — deposits, and an honest "No debt".
                    stat(String(localized: "Deposits"),
                         TokenStats.compact(deposits), tint: DS.textPrimary)
                    stat(String(localized: "Debt"),
                         String(localized: "None"), tint: DS.textPrimary)
                }
            }
            .padding(.top, DS.Space.s1)
        }
    }

    private func stat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
            Text(value).dsText(.price16).foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var liquidation: [WalletWarning] { warnings.filter { $0.kind == .liquidation } }
    private var delegations: [WalletWarning] { warnings.filter { $0.kind == .delegation } }
    private var safeSignatures: [WalletWarning] { warnings.filter { $0.kind == .safe } }

    /// The type-sections inside "Worth doing", each dropped when empty.
    private var actionableSectionIDs: [String] {
        var ids: [String] = []
        if !liquidation.isEmpty { ids.append("position") }
        if !activeApprovals.isEmpty { ids.append("approvals") }
        if !delegations.isEmpty { ids.append("delegations") }
        if !safeSignatures.isEmpty { ids.append("safe") }
        return ids
    }
    private var hasActionable: Bool { !actionableSectionIDs.isEmpty }
    private var actionableRowCount: Int {
        liquidation.count + activeApprovals.count + delegations.count + safeSignatures.count
    }

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

    /// The tray's own ceiling — past this the content scrolls.
    private static let maxTrayHeight: CGFloat = 620
    /// One-line row now (2026-07-23) — no subtitle, no leading glyph.
    private static let rowHeight: CGFloat = 46
    /// A section header carries a glyph, a count, and its own one-line
    /// explainer beneath, so it's taller than a bare row.
    private static let headerHeight: CGFloat = 58

    /// What the content WOULD be with nothing clipped — the honest measure
    /// the overflow gate reads, before the cap flattens it. Reads
    /// `awareExpanded`, so the sheet visibly grows when the spam pile is
    /// opened and settles back when it's closed, both capped at
    /// `maxTrayHeight`.
    private var uncappedHeight: CGFloat {
        var h: CGFloat = 150
        if hasActionable {
            h += 46 // the "Worth doing" group label + its explainer line
            h += CGFloat(actionableRowCount) * Self.rowHeight
                + CGFloat(actionableSectionIDs.count) * Self.headerHeight
        }
        if !flagged.isEmpty {
            h += 30 + Self.headerHeight // the "Just so you know" label + the boxed summary row
            if awareExpanded { h += CGFloat(flagged.count) * Self.rowHeight + 40 }
        }
        return h
    }

    /// Chips exist to save a SCROLL, so the gate is overflow — not a
    /// taxonomy count (2026-07-23, superseding the old `> 3 sections`
    /// rule; kept unchanged by the Act/Aware split). The bar shows when the
    /// content actually overflows the sheet AND there's more than one
    /// group to jump between (jumping within a lone group is a no-op) —
    /// which in practice now means "the spam pile is expanded and long",
    /// since a short, spam-free 'Worth doing' rarely overflows on its own.
    private var showsJumpBar: Bool {
        superSectionIDs.count > 1 && uncappedHeight > Self.maxTrayHeight
    }

    private var trayHeight: CGFloat {
        min(Self.maxTrayHeight, uncappedHeight + (showsJumpBar ? 44 : 0))
    }

    var body: some View {
        NavigationStack(path: $path) {
        DSTray(title: String(localized: "Worth a look"), height: trayHeight, ink: true) {
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
                                VStack(alignment: .leading, spacing: DS.Space.s4) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: DS.Space.s2) {
                                            Text("Worth doing")
                                                .dsText(.label12).fontWeight(.semibold)
                                                .foregroundStyle(DS.attention)
                                            Text("\(actionableRowCount)")
                                                .dsText(.label12).foregroundStyle(DS.textSecondary)
                                                .monospacedDigit()
                                        }
                                        Text("You can still change how these turn out.")
                                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                    }
                                    .padding(.horizontal, 3)
                                    if !liquidation.isEmpty {
                                        section(id: "position", title: String(localized: "Position risk"),
                                               symbol: "chart.line.downtrend.xyaxis", critical: true,
                                               count: liquidation.count,
                                               explainer: String(localized: "Could be liquidated if prices move against you."),
                                               bulkAction: nil) {
                                            ForEach(liquidation) { inertRow($0) }
                                        }
                                    }
                                    if !activeApprovals.isEmpty {
                                        let bulk = bulkRevoke(addresses: activeApprovals.map(\.walletAddress))
                                        section(id: "approvals", title: String(localized: "Approvals"),
                                               symbol: "key.fill", critical: false,
                                               count: activeApprovals.count,
                                               explainer: String(localized: "Contracts you've allowed to move tokens from your wallet."),
                                               bulkAction: bulk) {
                                            ForEach(activeApprovals) { approvalRow($0, showsOwnLink: bulk == nil) }
                                        }
                                    }
                                    if !delegations.isEmpty {
                                        let bulk = bulkRevoke(addresses: delegations.map(\.address))
                                        section(id: "delegations", title: String(localized: "Delegations"),
                                               symbol: "arrow.triangle.branch", critical: false,
                                               count: delegations.count,
                                               explainer: String(localized: "Voting power you've handed to another address."),
                                               bulkAction: bulk) {
                                            ForEach(delegations) { delegationRow($0, showsOwnLink: bulk == nil) }
                                        }
                                    }
                                    if !safeSignatures.isEmpty {
                                        section(id: "safe", title: String(localized: "Safe signatures"),
                                               symbol: "signature", critical: false,
                                               count: safeSignatures.count,
                                               explainer: String(localized: "Waiting for you to sign in the Safe app."),
                                               bulkAction: nil) {
                                            ForEach(safeSignatures) { inertRow($0) }
                                        }
                                    }
                                }
                                .id("act")
                            }
                            if !flagged.isEmpty { awareSection }
                        }
                        .padding(.bottom, DS.Space.s2)
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
                .presentationDetents([.height(trayHeight)])
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

    // MARK: - Section shell (Worth doing's type-sections)

    @ViewBuilder
    private func section<Rows: View>(id: String, title: String, symbol: String, critical: Bool,
                                     count: Int, explainer: String,
                                     bulkAction: (label: String, url: URL)?,
                                     @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(critical ? DS.destructive : DS.attention)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill((critical ? DS.destructive : DS.attention).opacity(0.16)))
                // The count rides the header now (2026-07-23), not the rows —
                // the rows are one line each and carry only what DIFFERS
                // between them; the shared count and the shared "why" live
                // up here so a dozen flagged transfers stop repeating one
                // sentence a dozen times.
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: DS.Space.s2) {
                        Text(title).dsText(.callout15).foregroundStyle(DS.textPrimary)
                        Text("\(count)")
                            .dsText(.label12).foregroundStyle(DS.textSecondary)
                            .monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(DS.surfaceWell))
                    }
                    Text(explainer)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if let bulkAction {
                    Button {
                        DSHaptic.selection()
                        openURL(bulkAction.url)
                    } label: {
                        HStack(spacing: 3) {
                            Text(bulkAction.label)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .dsText(.subhead13).foregroundStyle(DS.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 3)
            // Bare, not boxed (prd §173: lists are air, parcels are for the
            // reads) — these rows are a content stream you scroll and
            // consume, the same category feed rows and catalog shelves
            // already shed their cards from; the header above is doing the
            // grouping, same as a day header, so a card underneath it would
            // be a second container saying the same thing twice.
            VStack(spacing: 0) { rows() }
        }
        .id(id)
    }

    /// A single bulk Revoke.cash link when every address in the section
    /// agrees — nil the moment two wallets are mixed in, since one link can
    /// only ever point at one wallet's page (review, 2026-07-23: the mock
    /// this shipped from drew one header link unconditionally, which would
    /// have quietly hidden a second wallet's approvals behind a URL that
    /// never mentions it).
    private func bulkRevoke(addresses: [String?]) -> (label: String, url: URL)? {
        let known = addresses.compactMap { $0 }
        guard known.count == addresses.count, let first = known.first,
              known.allSatisfy({ WalletWatch.sameAddress($0, first) }),
              WalletApprovals.canServe(first),
              let url = URL(string: WalletApprovals.revokeURL(address: first))
        else { return nil }
        return (String(localized: "Revoke.cash"), url)
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
                    ForEach(flagged) { flaggedRow($0) }
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

    // MARK: - Rows

    /// What sits at a row's trailing edge — the only thing that varies
    /// between the four row kinds now that everything else is one shared
    /// one-line shape (2026-07-23). No leading glyph on any of them: the
    /// section header carries the one glyph for the whole kind, so twelve
    /// flagged transfers stop stamping the same mark twelve times.
    private enum RowTrailing {
        case none
        case detail(String)   // a distinct spec (a health factor), muted
        case revoke           // "Revoke.cash ↗"
        case chevron          // opens the thing sheet
    }

    /// Every row is this one shape: a single title line carrying only what
    /// DIFFERS between rows (an amount, a wallet, a spender), and one
    /// trailing element. The shared "why" that used to repeat on every
    /// subtitle now lives once in the section header's explainer.
    @ViewBuilder
    private func row(_ primary: String, trailing: RowTrailing, tap: (() -> Void)?) -> some View {
        let content = HStack(spacing: DS.Space.s3) {
            Text(primary).dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: DS.Space.s2)
            switch trailing {
            case .none:
                EmptyView()
            case .detail(let text):
                Text(text).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(1).monospacedDigit()
            case .revoke:
                HStack(spacing: 3) {
                    Text("Revoke.cash").dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .frame(height: Self.rowHeight)
        .padding(.horizontal, 3)
        .contentShape(Rectangle())
        if let tap {
            Button { tap() } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Position-risk and Safe rows: the whole in-app read, no control —
    /// acting on Aave happens on Aave, signing happens in the Safe app. The
    /// subtitle (a health factor, a chain) is the one distinct spec, so it
    /// rides the trailing edge instead of a dropped second line.
    private func inertRow(_ w: WalletWarning) -> some View {
        row(w.title, trailing: w.subtitle.map(RowTrailing.detail) ?? .none, tap: nil)
    }

    /// `showsOwnLink` is false whenever the section header already carries a
    /// bulk Revoke.cash link covering this row's wallet — otherwise every
    /// row in a same-wallet section repeats the link the header just showed.
    /// The row stays tappable when a link exists; only the trailing element
    /// (and the disabled dead-tap case) change.
    private func delegationRow(_ w: WalletWarning, showsOwnLink: Bool) -> some View {
        let action = w.address.flatMap { address -> URL? in
            guard WalletApprovals.canServe(address) else { return nil }
            return URL(string: WalletApprovals.revokeURL(address: address))
        }
        return row(w.title,
                   trailing: (action != nil && showsOwnLink) ? .revoke : .none,
                   tap: action.map { url in { DSHaptic.selection(); openURL(url) } })
    }

    /// An approval thing already carries its own Revoke.cash page as
    /// `content` (`WalletApprovals`' own field). `showsOwnLink` is the same
    /// header-already-covers-it suppression `delegationRow` uses.
    private func approvalRow(_ thing: Thing, showsOwnLink: Bool) -> some View {
        let action = URL(string: thing.content)
        return row(thing.title,
                   trailing: (action != nil && showsOwnLink) ? .revoke : .none,
                   tap: action.map { url in { DSHaptic.selection(); openURL(url) } })
    }

    /// A flagged transfer — its title (the amount, wearing the confusable
    /// symbol as its own tell) is the differentiator; WHY it's flagged is the
    /// section explainer's job now, not a repeated subtitle. Taps into its
    /// sheet, which still states the specific poisoning/spoof verdict.
    private func flaggedRow(_ thing: Thing) -> some View {
        row(thing.title, trailing: .chevron) {
            DSHaptic.selection()
            path.append(thing)
        }
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
