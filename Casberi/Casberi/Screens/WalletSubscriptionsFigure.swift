import SwiftUI

/// The Subscriptions tile's box (prd §1105, §1111): what the subscriptions
/// cost a month, one line, then the five weeks as a calendar with a face on
/// each renewal's day. It was Coming up's box (`WalletDueFigure`, §1078,
/// §1107), which also added up a month of bills and counted what waited on
/// you; those rows moved to Home with Coming up (§1111), and the bill
/// arithmetic went with them.
struct WalletSubscriptionsFigure: View {
    let subscriptions: [Subscriptions.Item]
    let monthly: Subscriptions.Total
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("\(mask ?? CardSpendRoom.money(monthly.monthly, code: "USD")) a month")
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // Tracking or stopping one rolls the sum to its new figure
                // (prd §1199).
                .contentTransition(.numericText(value: monthly.monthly))
                .animation(reduceMotion ? nil : DS.Motion.standard, value: monthly.monthly)
            line(mask: mask)
            Spacer(minLength: DS.Space.s1)
            WalletCalendar(marks: subscriptions.compactMap { item in
                item.next.map { .init(id: item.id, day: $0, face: item.name, attention: item.was != nil) }
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// One 12pt line: how many, what they cost a year, and any left out of
    /// the sum by name — never counted at zero (§1078).
    private func line(mask: String?) -> some View {
        var parts = [String(localized: "\(subscriptions.count) subscriptions")]
        if monthly.counted > 0 {
            parts.append(String(localized: "\(mask ?? CardSpendRoom.money(monthly.yearly, code: "USD")) a year"))
        }
        if !monthly.uncounted.isEmpty {
            parts.append(String(localized: "not counted: \(ListFormatter.localizedString(byJoining: monthly.uncounted))"))
        }
        return Text(verbatim: parts.joined(separator: " · "))
            .foregroundStyle(DS.textTertiary)
            .dsText(.subhead12)
            .lineLimit(1)
    }
}
