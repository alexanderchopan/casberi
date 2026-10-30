import SwiftUI

/// **SPENDING'S BOX (prd §1468, §1480): a statement, no plate.** The
/// window's total and the line against the last window to the same point
/// (Home's own words, §1201), the running line (§1480 item 14), then the
/// window's two words as slim text (§942). Recurring, The rest and Fees
/// became the doors under the tiles (§1480 item 5). Nothing is coloured (§83).
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
            // **THE THREE ROWS ARE DOORS NOW (prd §1480 item 5):**
            // Subscriptions, Places and Fees stand under the tiles, each
            // opening its page, so the box says the window and its total.
            //
            // **THE RUNNING LINE (prd §1480 item 14):** what the window had
            // spent by each day, ending on today at the total. It takes the
            // height the box leaves, as Home's line does (§1102), and the
            // charts' tint, never a state colour (§83). A window's first
            // day is one point, and draws no line.
            if reading.running.count > 1 {
                GeometryReader { geo in
                    TokenChartPlot(chart: TokenChart(closes: reading.running,
                                                     price: reading.total, change: 0),
                                   accent: DS.tint, height: geo.size.height, pulses: false,
                                   lineWidth: 2.6, fillOpacity: 0.22,
                                   endpointDot: true, fillsToLow: true)
                }
                .frame(minHeight: 0, maxHeight: .infinity)
                .layoutPriority(-1)
                .padding(.top, DS.Space.s3)
                .accessibilityElement()
                .accessibilityLabel(Text("Spending so far, day by day"))
            }
            HStack(spacing: DS.Space.s4) {
                // Yours · Everything leads the foot (prd §1526).
                WalletWhoseSwitch()
                DSRangeChips(ranges: Spending.Window.allCases, range: window,
                             label: Self.label, slim: true, onPick: onPick)
            }
            .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    /// The Fees door's line (prd §1476 item 3, §1480): "Not in the total",
    /// or "From Oct 23" while a send in the window carries no fee yet.
    static func feesLine(_ reading: Spending.Reading, mask: String?) -> String {
        guard mask == nil, let from = reading.feesFrom else { return String(localized: "Not in the total") }
        let day = from.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "From \(day) · not in the total")
    }

    static func label(_ window: Spending.Window) -> String {
        switch window {
        case .week:  return String(localized: "Week")
        case .month: return String(localized: "Month")
        }
    }
}
