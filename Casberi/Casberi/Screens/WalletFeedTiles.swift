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
        .dsWidgetSurface()
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
            Button { onOpen?() } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)

            if let chart {
                // Taller, heavier, and ending on a solid dot (prd §157) — the
                // line is the total said a second way, so it carries weight
                // like the total does.
                TokenChartPlot(chart: chart, accent: accent, height: 52, pulses: false,
                               lineWidth: 2.4, fillOpacity: 0.30, endpointDot: true,
                               marks: marks,
                               onTapMark: marks.isEmpty ? nil : { onOpenMark($0.id) })
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

/// Worth a look — the security read, as a quiet inline LINE (prd §146,
/// 2026-07-21), not a standing card. Warnings are usually absent, and a
/// permanent half-width card was reserving prominent space for the exception;
/// demoted to a line, it whispers when clear-of-course and only speaks up with
/// its own attention glyph when something's actually there. Leads with the
/// standard warning glyph (red when any warning is critical), then the words
/// and the top warnings' summary ("1 delegation · 1 flagged transfer"); the
/// whole line opens the tray. Which address, on which chain, is what the tray
/// behind the tap is for (user, 2026-07-20: a 0x in a line is detail).
struct WalletWarningsLine: View {
    let warnings: [WalletWarning]
    let onOpen: () -> Void

    var body: some View {
        let critical = warnings.contains { $0.severity == .critical }
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s2) {
                // The GLYPH carries severity too, not just its hue — the
                // pattern `warningRow` below already uses.
                Image(systemName: critical ? "exclamationmark.triangle.fill"
                                           : "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(critical ? DS.destructive : DS.attention)
                    .accessibilityHidden(true)
                Text(critical ? "Needs attention" : "Worth a look")
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .layoutPriority(1)
                Text(WalletWatch.summary(warnings))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                     "$\(WalletIngest.format(collateral))", tint: DS.textPrimary)
                stat(String(localized: "Debt"),
                     "$\(WalletIngest.format(debt))", tint: DS.textPrimary)
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
                             "$\(WalletIngest.format(collateral))", tint: DS.textPrimary)
                    } else if deposits > 0 {
                        stat(String(localized: "Deposits"),
                             "$\(WalletIngest.format(deposits))", tint: DS.textPrimary)
                    }
                    stat(String(localized: "Debt"),
                         "$\(WalletIngest.format(debt))", tint: DS.textPrimary)
                    stat((health ?? .infinity) < 1.5
                            ? String(localized: "Health · at risk") : String(localized: "Health"),
                         health.map { WalletIngest.format($0) } ?? String(localized: "No debt"),
                         tint: (health ?? .infinity) < 1.5 ? DS.attention : DS.textPrimary)
                } else {
                    // Earning face — deposits, and an honest "No debt".
                    stat(String(localized: "Deposits"),
                         "$\(WalletIngest.format(deposits))", tint: DS.textPrimary)
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
/// the row itself — a flagged transfer opens its sheet, a delegation opens
/// that wallet's Revoke.cash page directly (the exact door the wallet screen
/// offers, minus the detour). Safe and liquidation rows carry no control:
/// signing happens in the Safe app and acting on Aave happens on Aave, and
/// the row already says everything this app can honestly say.
struct WalletWorthALookTray: View {
    let warnings: [WalletWarning]
    /// The flagged transfers behind a poisoning warning — each becomes its
    /// own row with a door to its sheet, instead of one dead aggregate line.
    let flagged: [Thing]
    let onOpenThing: (Thing) -> Void
    @Environment(\.openURL) private var openURL

    private var listed: [WalletWarning] { warnings.filter { $0.kind != .poisoning } }
    private var rowCount: Int { listed.count + flagged.count }

    var body: some View {
        DSTray(title: String(localized: "Worth a look"),
               height: min(620, CGFloat(150 + rowCount * 64))) {
            ScrollView {
                VStack(spacing: DS.Space.s1) {
                    ForEach(listed) { w in
                        warningRow(w)
                    }
                    ForEach(flagged) { thing in
                        flaggedRow(thing)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The one real action a delegation warning has: that wallet's Revoke.cash
    /// page — the same URL the wallet screen's Approvals row opens.
    private func revokeAction(_ w: WalletWarning) -> URL? {
        guard w.kind == .delegation, let address = w.address,
              WalletApprovals.canServe(address) else { return nil }
        return URL(string: WalletApprovals.revokeURL(address: address))
    }

    @ViewBuilder
    private func warningRow(_ w: WalletWarning) -> some View {
        let action = revokeAction(w)
        Button {
            if let action {
                DSHaptic.selection()
                openURL(action)
            }
        } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: w.severity == .critical
                      ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(w.severity == .critical ? DS.destructive : DS.attention)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.title).dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle = w.subtitle {
                        Text(subtitle).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if action != nil {
                    Text("Revoke.cash").dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.vertical, DS.Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func flaggedRow(_ thing: Thing) -> some View {
        Button {
            DSHaptic.selection()
            onOpenThing(thing)
        } label: {
            HStack(spacing: DS.Space.s3) {
                KindGlyph(kind: thing.kind, size: 28)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.destructive)
                            .padding(3)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title).dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("Looks like address poisoning — don't copy this address")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s2)
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
