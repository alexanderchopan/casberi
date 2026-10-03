import SwiftUI

/// Coming up's box when something is due or waiting (prd §1078): what the
/// next thirty days' bills add up to, how many things wait on you, then the
/// runway of every date ahead. `WalletDue` holds the arithmetic and the words.
struct WalletDueFigure: View {
    let bills: [WalletDue.Bill]
    let waiting: Int
    let dates: [Date]
    /// The first item, which leads when no bill has an amount.
    let next: Thing?

    @State private var rates: [String: Double] = [:]

    var body: some View {
        let reading = WalletDue.compose(bills: bills, waiting: waiting, rates: rates)
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let codes = Set(bills.compactMap(\.currency)).subtracting(["USD"])
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if reading.hasFigure {
                Text("\(mask ?? CardSpendRoom.money(reading.total, code: "USD")) due in \(WalletDue.windowDays) days")
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            } else if let next {
                Text(next.title)
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
            }
            if let line = WalletDue.waitingLine(reading.waiting) {
                Text(line)
                    .dsText(.heading17)
                    .foregroundStyle(DS.attentionInk)
            } else if !reading.hasFigure, let next, let due = FeedScreen.dueLine(next) {
                Text(due)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
            WalletRunwayRail(dates: dates)
            if let line = WalletDue.uncountedLine(reading.uncounted) {
                Text(line)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .task(id: codes) {
            guard !codes.isEmpty else { return }
            let fetched = await WalletCash.cachedRates(for: codes)
            if fetched != rates { rates = fetched }
        }
    }
}
