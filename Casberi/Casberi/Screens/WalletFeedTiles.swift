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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: 5) {
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(glyphTint)
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

/// Balance — the portfolio number, its sparkline, and the honest delta.
/// Nothing renders until two aligned samples exist (`TokenChart.from` guards
/// it), so a freshly-watched wallet shows no tile rather than a flat line.
struct WalletBalanceTile: View {
    let chart: TokenChart
    /// nil = no door: with one wallet (or scoped to one) the number has no
    /// further breakdown to show — the treemap below IS the composition, so a
    /// chevron here would open nothing new. Only the multi-wallet "All" view
    /// gets the combined-breakdown sheet behind it.
    let onOpen: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { TokenChartStyle.accent(change: chart.change, scheme: scheme) }

    var body: some View {
        Button { onOpen?() } label: {
            WalletTile(caption: String(localized: "Balance"),
                       showChevron: onOpen != nil) {
                // The app's money voice ($19.9K), not a token price — this is a
                // portfolio total, and `TokenStats.compact` is what the combined
                // sheet and the wallet row sublines already speak. Raw
                // `priceText` printed "$19866.64" here, which is a coin quote.
                Text(TokenStats.compact(chart.price))
                    .dsText(.stat24).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                TokenChartPlot(chart: chart, accent: accent, height: 26, pulses: false)
                // "watched" — the honest window. The samples start when the
                // wallet was first watched, so naming any calendar period
                // ("this week") would claim a range the data may not cover.
                TokenDeltaPill(change: chart.change, label: "watched", compact: true)
            }
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
    }
}

/// Worth a look — the security read, moved off the manage screen.
///
/// Leads with the top warning's OWN WORDS, not a count (user, 2026-07-20:
/// a bare number is a mystery box). The tail says how many more, quietly.
/// Yellow appears exactly once, as the standard warning glyph — the system's
/// vocabulary, nothing invented.
struct WalletWarningsTile: View {
    let warnings: [WalletWarning]
    let onOpen: () -> Void

    var body: some View {
        let critical = warnings.contains { $0.severity == .critical }
        Button(action: onOpen) {
            WalletTile(caption: String(localized: "Worth a look"),
                       glyph: "exclamationmark.triangle.fill",
                       glyphTint: critical ? DS.destructive : DS.attention) {
                // The COUNT leads, in the same rounded money voice the balance
                // beside it uses, so the two tiles read as a matched pair. The
                // subline says what kind — "1 delegation · 1 flagged transfer".
                // Which address, on which chain, is what the page behind the
                // tap is for (user, 2026-07-20: a 0x in a tile is detail).
                Text(warnings.count == 1
                     ? String(localized: "1 item")
                     : String(localized: "\(warnings.count) items"))
                    .dsText(.stat24).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(WalletWatch.summary(warnings))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                stat(String(localized: "Health"),
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
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// The page behind the Worth-a-look tile (2026-07-20) — the tile summarizes
/// by count and kind; this tray IS the items. Every row that has somewhere
/// real to go wears a door: a flagged transfer opens its own sheet, a Safe or
/// delegation warning opens the owning wallet's screen (where the Revoke.cash
/// door and delegate identity live). A liquidation row states chain + health
/// factor and carries no chevron — acting on an Aave position happens on
/// Aave, and the row already says everything this app can honestly say.
struct WalletWorthALookTray: View {
    let warnings: [WalletWarning]
    /// The flagged transfers behind a poisoning warning — each becomes its
    /// own row with a door to its sheet, instead of one dead aggregate line.
    let flagged: [Thing]
    let onOpenWallet: (String) -> Void
    let onOpenThing: (Thing) -> Void

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

    @ViewBuilder
    private func warningRow(_ w: WalletWarning) -> some View {
        let hasDoor = w.address != nil && (w.kind == .safe || w.kind == .delegation)
        Button {
            if let address = w.address, hasDoor {
                DSHaptic.selection()
                onOpenWallet(address)
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
                if hasDoor {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.vertical, DS.Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasDoor)
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
/// Names its own count so the door says what's behind it rather than "more".
struct WalletSeeAllRow: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s2) {
                Text("See all transactions")
                    .dsText(.body17).foregroundStyle(DS.tint)
                Spacer(minLength: 0)
                Text("\(count)")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
