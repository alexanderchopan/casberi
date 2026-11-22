import SwiftUI

/// **A MONEY PLATE'S ROWS (`MoneyPlate`).** Account's line anatomy — the
/// question grey in the fixed column, the answer where values start — except
/// the answer wraps, because these are the lines that explain where money
/// goes and must be read whole. One row per question, the same five on
/// every plate.
struct MoneyPlateRows: View {
    let facts: [MoneyPlate.Fact]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(facts) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: fact.label)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: AccountLines.labelWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        ForEach(Array(fact.lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line)
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
