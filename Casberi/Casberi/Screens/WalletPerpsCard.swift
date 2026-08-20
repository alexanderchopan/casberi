import SwiftUI

/// Hyperliquid perps — the wallet room's fourth live-state card (2026-07-31),
/// beside `WalletLendingCard` and `WalletLiquidityCard`.
///
/// A SIBLING card, and specifically NOT a third row inside Lending. Prd §212's
/// reasoning ("Aave and Morpho were never two subjects, they're two providers
/// of one") is exactly what rules it out here: a perp is not lending. Nothing
/// is supplied, nothing is borrowed, there is no health factor and no
/// collateral ratio — filing it under a card headed "Lending" would make the
/// label wrong to buy one fewer surface. `WalletLiquidityCard` already settled
/// this shape for the same reason a month earlier: different subject, own card.
///
/// The gap it closes: `HyperliquidDeFi.syncPositions` has computed a
/// liquidation-proximity crossing since 2026-07-30 and lands an alert when a
/// position crosses into the margin — but that alert is a landed thing in the
/// stream, so it scrolls away, and the LIVE state behind it had no seat on any
/// screen. Prd §240 gave Hyperliquid its first seat in the composition strip,
/// which states amounts and deliberately makes no claim about risk. So the one
/// question a leveraged position actually asks — how close am I — was
/// answerable only by catching a row as it went past.
///
/// The margin is `HyperliquidDeFi.riskProximity`, read from the sweep rather
/// than redeclared: a card calling a position safe while the sweep has already
/// alerted on it is precisely the disagreement the honesty rule bans.
///
/// FLAT BY LAW like its neighbours — a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).
struct WalletPerpsCard: View {
    let book: HyperliquidDeFi.Book

    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                WalletSectionLabel(title: String(localized: "Perps"))
                // THE READING (2026-08-20, prd §417) — see
                // `WalletLiquidityCard.reading` for the ruling. This card went
                // from an 11pt label straight to rows, so the fact it is
                // already SORTED by (its own doc's words) "nearest to
                // liquidation" was information only a reader who knew the sort
                // order could use. Now it says so.
                Text(reading.text)
                    .dsText(.heading22)
                    .foregroundStyle(reading.risk ? DS.attention : DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
                // `Position` is a plain value type (never a `Thing`), keyed on
                // its own identity. The key spans the ACCOUNT as well as the
                // coin: a sub-account can hold its own BTC position alongside
                // the main one, and keying on the coin alone would collide
                // them (the reused-id `ForEach` trap this app has paid for).
                ForEach(shown, id: \.key) { position in
                    positionRow(position)
                }
            }
            .padding(DS.Space.s4)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    /// The card's spoken verdict (prd §417), naming the position `shown`
    /// already ranks first.
    ///
    /// **Says nothing about profit**, deliberately: this card has never shown
    /// PnL and the reading is not the place to start, since an unrealized
    /// number stated in the largest type on the card reads as money you have.
    /// It says the same thing the sort does — what is closest to being taken
    /// from you — and falls back to a plain count when no position carries a
    /// liquidation price, which is a real state (`liquidationProximity` is nil
    /// for an unlevered position) and not a failure.
    private var reading: (text: String, risk: Bool) {
        guard let worst = shown.first else { return ("", false) }
        let side = worst.isLong ? String(localized: "long") : String(localized: "short")
        guard let proximity = worst.liquidationProximity else {
            return (shown.count == 1
                    ? String(localized: "One position open")
                    : String(localized: "\(shown.count) positions open"), false)
        }
        let pct = Int((proximity * 100).rounded())
        return (String(localized: "\(worst.coin) \(side) is \(pct)% from liquidation"),
                worst.isNearLiquidation)
    }

    /// Real positions only, riskiest first.
    ///
    /// The floor is `WalletIngest.holdingFloor`, the same dust line the
    /// treemap and Morpho draw — and here it is load-bearing rather than
    /// tidy: a measured wallet held 0.00001 BTC ($0.65 notional) carrying a
    /// `liquidationPx` of 8.3 BILLION, which computes to a position
    /// astronomically "far from liquidation" and would sit in this card
    /// forever saying nothing true about anything.
    private var shown: [HyperliquidDeFi.Position] {
        book.positions
            .filter { $0.positionValue >= WalletIngest.holdingFloor }
            .sorted {
                // Nearest to liquidation leads — the same "worst first"
                // instinct the Lending card's health factor and the Liquidity
                // card's out-of-range both follow. A position with no
                // liquidation price sorts as infinitely far, never as zero.
                let a = $0.liquidationProximity ?? .infinity
                let b = $1.liquidationProximity ?? .infinity
                if a != b { return a < b }
                return $0.positionValue > $1.positionValue
            }
    }

    private func positionRow(_ position: HyperliquidDeFi.Position) -> some View {
        // The COIN's mark, not the venue's (2026-08-04): every row here is
        // Hyperliquid, so a repeated venue mark names what the card already
        // is and says nothing about which position you're looking at — the
        // exact reasoning that retired `WalletLiquidityCard`'s "UN" monogram.
        WalletRow(mark: .asset(position.coin,
                               tint: position.isNearLiquidation ? DS.attention : DS.tint,
                               atRisk: position.isNearLiquidation),
                  title: Self.title(position),
                  subtitle: Self.line(position)) {
            // Notional leads on the trailing edge, the Lending card's own
            // ranking ("how much" beats every other stat). Unrealized PnL is
            // deliberately absent: it re-prices every second, so a card that
            // showed it would be wrong between reads far more often than it
            // was right, and the subject of this card is whether the position
            // survives — not what it is worth this instant.
            WalletRowValue(value: WalletValue.money(position.positionValue),
                           caption: String(localized: "notional"))
        }
    }

    /// "BTC long" — the coin and the side, which is the whole identity of a
    /// perp position.
    private static func title(_ position: HyperliquidDeFi.Position) -> String {
        position.isLong
            ? String(localized: "\(position.coin) long")
            : String(localized: "\(position.coin) short")
    }

    /// "10× cross · 12% from liquidation · Trading sub" — the leverage, how
    /// much room is left, and which account it sits in, in the
    /// `WalletLendingCard.line` shape.
    ///
    /// The distance is stated for EVERY position, not only the risky ones:
    /// "38% from liquidation" is the reassurance half of the same fact, and a
    /// number that appeared only in danger would make its absence the alarm.
    /// A position whose liquidation price the API withholds says nothing
    /// rather than guessing — there is no honest number to print there.
    private static func line(_ position: HyperliquidDeFi.Position) -> String {
        var parts: [String] = []
        parts.append(String(localized: "\(position.leverageX)× \(position.leverageType)"))
        if let proximity = position.liquidationProximity {
            let pct = Int((proximity * 100).rounded())
            parts.append(String(localized: "\(pct)% from liquidation"))
        }
        // Only a sub-account earns a name — the main account is the default
        // and saying so on every row would be noise.
        if let label = position.accountLabel, !label.isEmpty {
            parts.append(label)
        }
        return parts.joined(separator: " · ")
    }
}

private extension HyperliquidDeFi.Position {
    /// Value-typed `ForEach` identity — the account included, since one wallet
    /// can hold the same coin in its main account and a sub-account at once.
    var key: String { "\(account.lowercased()):\(coin):\(isLong)" }
}
