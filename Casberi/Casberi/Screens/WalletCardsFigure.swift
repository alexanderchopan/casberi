import SwiftUI

/// The Cards tile's drawing in the Wallet's box (prd §1048, step 2): what every
/// card spent in the window, then each card's own line, ranked by spends.
///
/// The words are `CardSpendRoom`'s own (`headline`, `currencyLine`), so the
/// Cards tile and a card's old room can never word the same money two ways.
/// Each card's bar is its share of the busiest card's SPEND COUNT, never of an
/// amount, because the cards can settle in different currencies and the app
/// will not invent a rate between them.
struct WalletCardsFigure: View {
    let reading: WalletCards.Reading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The figure is one box tall; four cards fill it.
    static let cardCap = 4

    var body: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
