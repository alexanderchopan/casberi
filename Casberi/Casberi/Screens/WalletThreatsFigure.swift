import SwiftUI

/// **THREATS' BOX (prd §1633): this month against the last, week by week.**
/// "5 in October", then whether that is more or fewer than September and how
/// many came this week, over one bar a week for twelve weeks. The bars take
/// the charts' tint (§1385); this week's bar is red while it holds a threat
/// you have not opened. An empty week draws a stub, so a quiet stretch reads
/// as quiet rather than missing (§769).
struct WalletThreatsFigure: View {
    let trend: ThreatTrend
    /// Whether this week holds a threat not yet opened (`ThreatsSeen`).
    let unseenThisWeek: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: "\(trend.thisMonth)")
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Text(verbatim: String(localized: "in \(Self.monthName(offset: 0))"))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            line
                .dsText(.body17)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            bars
                .padding(.top, DS.Space.s3)
            axis
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    static func monthName(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .month, value: offset, to: .now) ?? .now
        return date.formatted(.dateTime.month(.wide))
    }

    /// "Up from 2 in September · 3 this week". Up is amber, down green: the
    /// one word that says which way it went (§1004).
    private var line: Text {
        let last = Self.monthName(offset: -1)
        var text: Text
        switch trend.compare {
        case .up(let from):
            text = Text(verbatim: String(localized: "Up from \(from) in \(last)")).foregroundStyle(DS.attentionInk)
        case .down(let from):
            text = Text(verbatim: String(localized: "Down from \(from) in \(last)")).foregroundStyle(DS.confirmInk)
        case .same:
            text = Text(verbatim: String(localized: "As many as \(last)")).foregroundStyle(DS.textSecondary)
        case .firstSince:
            text = Text(verbatim: String(localized: "None in \(last)")).foregroundStyle(DS.textSecondary)
        case .quiet:
            text = Text(verbatim: String(localized: "None in \(last) either")).foregroundStyle(DS.textSecondary)
        }
        if trend.thisWeek > 0 {
            text = text + Text(verbatim: " · ").foregroundStyle(DS.textTertiary)
                + Text(verbatim: String(localized: "\(trend.thisWeek) this week")).foregroundStyle(DS.textSecondary)
        }
        return text
    }

    private var bars: some View {
        let peak = max(trend.weeks.max() ?? 0, 1)
        let lastIndex = trend.weeks.count - 1
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(trend.weeks.enumerated()), id: \.offset) { index, n in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(n == 0 ? DS.fillFaint
                              : index == lastIndex && unseenThisWeek ? DS.destructive
                              : DS.tint)
                        .frame(height: n == 0 ? 3 : max(6, geo.size.height * CGFloat(n) / CGFloat(peak)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(minHeight: 24, maxHeight: 72)
        .accessibilityElement()
        .accessibilityLabel(Text("Threats each week, the last twelve weeks"))
        .accessibilityValue(Text(verbatim: trend.weeks.map(String.init).joined(separator: ", ")))
    }

    private var axis: some View {
        let labels = trend.monthLabels()
        return HStack(spacing: 6) {
            // Each name hangs off its bar's leading edge and may run over the
            // next bars (months turn four bars apart); on the last bar it
            // ends at the bar's trailing edge instead, inside the box.
            ForEach(trend.weeks.indices, id: \.self) { index in
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 17, maxHeight: 17)
                    .overlay(alignment: index == trend.weeks.count - 1 ? .trailing : .leading) {
                        Text(verbatim: labels[index] ?? "")
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textTertiary)
                            .fixedSize()
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
