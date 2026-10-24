import SwiftUI

// The receipt's list under its tiles (prd §1181): the sheet's list, never
// its head, so its section names take the rooms' pink as every list does.

/// THE HISTORY AS ROWS (prd §1181, user, of the bars: "this is dumb"): the
/// last three with this party, each opening its own sheet. The door to all
/// of them is `MoneyYearTotals`', on the address card.
struct MoneyHistoryRows: View {
    let title: String
    let rows: [KeyedThing]
    /// The header's trailing figure (a card spend: this month's total).
    var trailing: String? = nil
    /// A row's amount, trailing (prd §1182): a card spend's visits read as
    /// their day and what they cost, never the shop's name again.
    var amount: ((Thing) -> String?)? = nil
    /// The door to every one of them (prd §1396): a More row under the last.
    var onAll: (() -> Void)? = nil
    var onOpen: (Thing) -> Void

    var body: some View {
        // NOTHING BEFORE THIS ONE DRAWS NOTHING (prd §1332, the user of the
        // Safe sheet's "At Everyday — Nothing before this one."): a card that
        // only says it is empty is a section with nothing to show.
        if !rows.isEmpty {
            card
        }
    }

    /// A list row's height (prd §1396): the name over its day, 60pt, as the
    /// feed's rows stand (§1017).
    static let rowHeight: CGFloat = DS.Hit.min + DS.Space.s4

    private var card: some View {
        // A list's name on the Feed's card (prd §1258), its figure trailing.
        SheetCard(name: title, trailing: trailing) {
            ForEach(rows) { row in
                if let thing = row.live {
                    Button { onOpen(thing) } label: {
                        HStack(spacing: DS.Space.s3) {
                            if let amount {
                                Text(verbatim: FeedScreen.dayWord(thing.capturedAt))
                                    .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                                Spacer(minLength: DS.Space.s2)
                                Text(verbatim: amount(thing) ?? "")
                                    .dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
                            } else if let trade = SwapStage(thing) {
                                swapRow(trade, at: thing.capturedAt)
                            } else {
                                // THE NAME OVER ITS DAY, THE FIGURE OVER ITS UNIT
                                // (prd §1396, user: "all this truncation looks
                                // like shit"): two short lines each side, one
                                // baseline, nothing cut.
                                VStack(alignment: .leading, spacing: 1) {
                                    // The thing alone (§915's seam): under "More from
                                    // Boards of Canada" a row never says the artist again.
                                    Text(verbatim: TitleSeam.split(thing.title).name)
                                        .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                                    // The one day word (prd §1359).
                                    Text(verbatim: FeedScreen.dayWord(thing.capturedAt))
                                        .dsText(.label12).foregroundStyle(DS.textSecondary).lineLimit(1)
                                }
                                Spacer(minLength: DS.Space.s2)
                                if let figure = Self.figure(thing) {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(verbatim: figure.number)
                                            .dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
                                            .lineLimit(1)
                                        if let unit = figure.unit {
                                            Text(verbatim: unit)
                                                .dsText(.label12).foregroundStyle(DS.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                        .frame(minHeight: Self.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                }
            }
            if let onAll {
                DSMoreRow(title: Text("Every transfer"), action: onAll)
            }
        }
        .padding(.horizontal, DSRoomChassis.inset)
    }

    /// A transfer's signed figure and its unit, off the bridge's own stamped
    /// amount; nil where the row stamped none.
    static func figure(_ thing: Thing) -> (number: String, unit: String?)? {
        guard let amount = WalletValue.transferAmount(thing), !amount.isEmpty else { return nil }
        let parts = MoneyReceipt.split(amount)
        let bare = parts.number.trimmingCharacters(in: CharacterSet(charactersIn: "+-−"))
        guard !bare.isEmpty else { return nil }
        let sign = thing.transferDirection == "received" ? "+" : "−"
        return (sign + bare, parts.unit)
    }

    /// A trade as a trade (prd §1373): its two marks, "MUSEGOD for MAG7",
    /// the day under it, what came in trailing over its unit. Nothing
    /// truncates: a figure steps down a size.
    @ViewBuilder
    private func swapRow(_ trade: SwapStage, at day: Date) -> some View {
        let out = MoneyReceipt.split(trade.outAmount), into = MoneyReceipt.split(trade.inAmount)
        let outName = out.unit ?? trade.outAmount, inName = into.unit ?? trade.inAmount
        ZStack(alignment: .topLeading) {
            AssetMark(name: outName, size: 34)
                .mask(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                        Circle().frame(width: 38, height: 38).offset(x: 14, y: 4)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
            AssetMark(name: inName, size: 34).offset(x: 16, y: 6)
        }
        .frame(width: 50, height: 40, alignment: .topLeading)
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: String(localized: "\(outName) for \(inName)"))
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text(verbatim: FeedScreen.dayWord(day))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 1) {
            Text(verbatim: "+" + (into.number.isEmpty ? trade.inAmount : into.number))
                .dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let unit = into.unit {
                Text(verbatim: unit)
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
