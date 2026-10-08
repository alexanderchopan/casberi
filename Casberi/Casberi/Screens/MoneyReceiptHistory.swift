import SwiftUI

// The receipt's list under its tiles (prd §1181): the sheet's list, never
// its head, so its section names take the rooms' pink as every list does.

/// THE HISTORY AS ROWS (prd §1181, user, of the bars: "this is dumb"): the
/// last three with this party, each opening its own sheet, then the door to
/// all of them on the address card.
struct MoneyHistoryRows: View {
    let title: String
    let rows: [KeyedThing]
    let total: Int
    let doorWord: String?
    /// The header's trailing figure (a card spend: this month's total).
    var trailing: String? = nil
    /// A row's amount, trailing (prd §1182): a card spend's visits read as
    /// their day and what they cost, never the shop's name again.
    var amount: ((Thing) -> String?)? = nil
    var onOpen: (Thing) -> Void
    var onAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .dsText(amount == nil ? .heading17 : .heading20)
                    .foregroundStyle(amount == nil ? DS.textPrimary : DS.brandInk)
                Spacer(minLength: DS.Space.s2)
                if let trailing {
                    Text(verbatim: trailing)
                        .dsText(.heading17).monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                }
            }
            if rows.isEmpty {
                Text("Nothing before this one.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
            }
            ForEach(rows) { row in
                if let thing = row.live {
                    Button { onOpen(thing) } label: {
                        HStack(spacing: DS.Space.s3) {
                            if let amount {
                                Text(verbatim: thing.capturedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                    .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                                Spacer(minLength: DS.Space.s2)
                                Text(verbatim: amount(thing) ?? "")
                                    .dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
                            } else {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: thing.title)
                                        .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                                    Text(verbatim: thing.capturedAt.formatted(.dateTime.month(.abbreviated).day()))
                                        .dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
                                }
                                Spacer(minLength: DS.Space.s2)
                            }
                        }
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                }
            }
            if let doorWord, let onAll, total > rows.count {
                DSMoreLink(title: Text(verbatim: doorWord), action: onAll)
            }
        }
        .padding(.horizontal, DSRoomChassis.inset)
    }
}

/// THIS YEAR WITH THEM (prd §1181): what you sent and what they sent you,
/// each a total and a count, then the door to every transfer on the address
/// card — the history as two facts, not a list that repeats the name.
struct MoneyYearTotals: View {
    let name: String
    let sentUSD: Double
    let sentCount: Int
    let receivedUSD: Double
    let receivedCount: Int
    var onAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("This year with \(name)")
                .dsText(.heading20)
                .foregroundStyle(DS.brandInk)
            HStack(spacing: DS.Space.s2) {
                total(String(localized: "You sent"), sentUSD, sentCount, gain: false)
                total(String(localized: "\(name) sent you"), receivedUSD, receivedCount, gain: true)
            }
            if let onAll {
                DSMoreLink(title: Text("Every transfer with \(name)"), action: onAll)
            }
        }
        .padding(.horizontal, DSRoomChassis.inset)
    }

    private func total(_ label: String, _ usd: Double, _ count: Int, gain: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: label)
                .dsText(.label12).foregroundStyle(DS.textSecondary).lineLimit(1)
            Text(verbatim: usd.formatted(.currency(code: "USD")))
                .dsText(.heading20).monospacedDigit()
                .foregroundStyle(gain && usd > 0 ? DS.confirmInk : DS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(count == 1 ? String(localized: "1 transfer") : String(localized: "\(count) transfers"))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
