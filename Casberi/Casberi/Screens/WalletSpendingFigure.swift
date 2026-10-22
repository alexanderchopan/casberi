import SwiftUI

/// **SPENDING'S BOX (prd §1468, §1469): a statement, no plate.** The
/// window's total and the line against the last window to the same point
/// (Home's own words, §1201), then Recurring and The rest as two ROWS, the
/// word leading and the figure trailing (user: "that is a row not column") —
/// each the sum of one group under the tiles — then the window's two words
/// as slim text (§942). Nothing is coloured (§83) and nothing is a chart.
struct WalletSpendingFigure: View {
    let reading: Spending.Reading
    let window: Spending.Window
    let onPick: (Spending.Window) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: FeedScreen.spendingTotal(reading, window: window, mask: mask))
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText(value: reading.total))
                .animation(reduceMotion ? nil : DS.Motion.standard, value: reading.total)
            if let compare = FeedScreen.spendingCompare(reading, window: window, mask: mask) {
                Text(verbatim: compare)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            // Top-aligned, the parts a step apart: the box is one height on
            // every tile (§760), and air between them read as a gap, not a
            // layout (seen on the simulator).
            VStack(spacing: DS.Space.s2) {
                row(String(localized: "Recurring"), mask ?? AppleWalletRoom.money(reading.recurring, "USD"))
                row(restLine(mask), mask ?? AppleWalletRoom.money(reading.rest, "USD"))
            }
            .padding(.top, DS.Space.s3)
            DSRangeChips(ranges: Spending.Window.allCases, range: window,
                         label: Self.label, slim: true, onPick: onPick)
                .padding(.top, DS.Space.s2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    /// The word, then its figure at the trailing edge, standing on nothing
    /// (§782).
    private func row(_ word: String, _ figure: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: word)
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: figure)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .monospacedDigit().lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// "The rest · $2,450 in September": what the rest was last window, when
    /// there was one; the word alone under Hide balances.
    private func restLine(_ mask: String?) -> String {
        let word = String(localized: "The rest")
        guard mask == nil, let earlier = reading.earlierRest, earlier >= 0.005 else { return word }
        let money = AppleWalletRoom.money(earlier, "USD")
        switch window {
        case .month:
            return "\(word) · \(String(localized: "\(money) in \(FeedScreen.spendingLastWindow(window))"))"
        case .week:
            return "\(word) · \(String(localized: "\(money) last week"))"
        }
    }

    static func label(_ window: Spending.Window) -> String {
        switch window {
        case .week:  return String(localized: "Week")
        case .month: return String(localized: "Month")
        }
    }
}
