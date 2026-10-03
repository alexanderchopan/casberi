import SwiftUI

/// The Cards tile's drawing in the Wallet's box (prd §1048, step 2): what every
/// card spent in the window, then each card's own line.
///
/// **IN DOLLARS WHEN EVERY CURRENCY HAS A RATE (prd §1078).** The headline is
/// one figure, the cards rank by dollars and each bar is a share of the
/// biggest card's dollars; a card that paid in euros still says what it paid
/// ("$134 · €123.20"), and the foot names the rate. Until the rate lands, or
/// when a currency has none, the figure keeps `CardSpendRoom`'s own words and
/// ranks by SPEND COUNT, because then the amounts share no unit.
struct WalletCardsFigure: View {
    let reading: WalletCards.Reading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rates: [String: Double] = [:]

    /// The figure is one box tall; four cards fill it.
    static let cardCap = 4

    var body: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let codes = WalletCards.codes(reading)
        Group {
            if let dollars = WalletCards.inDollars(reading, rates: rates) {
                dollarFigure(dollars, mask: mask)
            } else {
                countFigure(mask: mask)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Kraken's mid price, the rate the Wallet's total uses for cash. Asked
        // only when a card spent in something other than dollars.
        .task(id: codes) {
            guard !codes.isEmpty else { return }
            let fetched = await WalletCash.cachedRates(for: codes)
            if fetched != rates { rates = fetched }
        }
    }

    private func usd(_ value: Double) -> String {
        CardSpendRoom.money(value, code: "USD")
    }

    @ViewBuilder
    private func dollarFigure(_ dollars: WalletCards.InDollars, mask: String?) -> some View {
        let drawn = Array(dollars.cards.prefix(Self.cardCap))
        let top = drawn.first?.usd ?? 0
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("\(mask ?? usd(dollars.total)) on your cards in \(CardSpendRoom.windowDays) days")
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(Array(drawn.enumerated()), id: \.element.seat) { index, card in
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                            Text(card.seat)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            Text(line(card, mask: mask))
                                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        ShareBar(fraction: top > 0 ? min(1, card.usd / top) : 0,
                                 index: index,
                                 reduceMotion: reduceMotion)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
            if let foot = foot(dollars) {
                Text(foot)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    /// "$134 · €123.20 · 3 spends", or "$612 · 10 spends" for a dollar card.
    private func line(_ card: WalletCards.InDollars.Card, mask: String?) -> String {
        var parts = [mask ?? usd(card.usd)]
        if let native = card.native {
            parts.append(mask ?? CardSpendRoom.money(native.total, code: native.code))
        }
        parts.append(CardSpendRoom.spendsLabel(card.spends))
        return parts.joined(separator: " · ")
    }

    /// The rate first, then `CardSpendRoom`'s own foot (unpriced spends, an
    /// idle card).
    private func foot(_ dollars: WalletCards.InDollars) -> String? {
        var parts: [String] = []
        if !dollars.rates.isEmpty {
            let rates = dollars.rates.map { "\($0.code) at \(usd($0.rate))" }
            let list = ListFormatter.localizedString(byJoining: rates)
            parts.append(WalletCash.isSampleRate
                         ? String(localized: "\(list), a sample rate")
                         : String(localized: "\(list), Kraken's mid rate"))
        }
        if let room = CardSpendRoom.footnote(reading.all) { parts.append(room) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func countFigure(mask: String?) -> some View {
        let drawn = Array(reading.cards.prefix(Self.cardCap))
        let top = drawn.first?.room.lead?.spends ?? 0
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(CardSpendRoom.headline(reading.all, mask: mask))
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(Array(drawn.enumerated()), id: \.element.seat) { index, card in
                    if let lead = card.room.lead {
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                                Text(card.seat)
                                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: DS.Space.s2)
                                Text(CardSpendRoom.currencyLine(lead, mask: mask))
                                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                            ShareBar(fraction: CardSpendRoom.share(spends: lead.spends, of: top),
                                     index: index,
                                     reduceMotion: reduceMotion)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Spacer(minLength: 0)
            if let foot = CardSpendRoom.footnote(reading.all) {
                Text(foot)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
            }
        }
    }
}
