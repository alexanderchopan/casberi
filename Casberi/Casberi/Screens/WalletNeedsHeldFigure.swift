import SwiftUI

/// **NEEDS YOU'S BOX (prd §1669): what the asks hold up.** "Held up", the
/// figure (`NeedsYouHeld.Reading.headline`), how many and since when, then
/// one bar split by ask and a line per ask: what it waits on, and its dollars
/// or its quantity. Amber waits, red was refused (§1004). The asks with no
/// money are counted in the line, never in the bar.
struct WalletNeedsHeldFigure: View {
    let reading: NeedsYouHeld.Reading
    /// Every ask Needs you holds, for the box with no money to state.
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Three lines fit the box under the bar; the rest stay in the bar.
    private static let legendCap = 3

    var body: some View {
        if let figure = reading.headline(money: WalletValue.money) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Held up")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                Text(verbatim: figure)
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: line)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                bar
                    .padding(.top, DS.Space.s3)
                legend
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        } else {
            DSFigureReading(number: "\(count)", caption: String(localized: "waiting on you"))
        }
    }

    /// "since 9:35 AM", "in 3 · since Sat", then "and 2 more waiting".
    private var line: String {
        var words: [String] = []
        if reading.parts.count > 1 { words.append(String(localized: "in \(reading.parts.count)")) }
        if let oldest = reading.oldest { words.append(String(localized: "since \(Self.since(oldest))")) }
        if reading.others > 0 { words.append(String(localized: "and \(reading.others) more waiting")) }
        return words.joined(separator: " · ")
    }

    static func since(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return days < 7 ? date.formatted(.dateTime.weekday(.abbreviated))
                        : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func ink(_ part: NeedsYouHeld.Part) -> Color {
        part.refused ? DS.destructive : DS.attention
    }

    private var bar: some View {
        let weights = reading.weights
        let total = max(weights.reduce(0, +), .leastNonzeroMagnitude)
        let gap: CGFloat = 3
        return GeometryReader { geo in
            let room = geo.size.width - gap * CGFloat(max(reading.parts.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(Array(reading.parts.enumerated()), id: \.element.id) { index, part in
                    Capsule()
                        .fill(ink(part))
                        .frame(width: max(8, room * CGFloat(weights[index] / total)))
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(reading.parts.prefix(Self.legendCap)) { part in
                HStack(spacing: DS.Space.s2) {
                    Circle().fill(ink(part)).frame(width: 8, height: 8)
                    Text(verbatim: part.label)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: part.usd.map(WalletValue.payment) ?? part.figure)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .dsText(.subhead12)
            }
        }
        .padding(.top, DS.Space.s2)
    }
}
