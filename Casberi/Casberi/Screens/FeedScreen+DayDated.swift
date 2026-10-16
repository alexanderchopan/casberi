import SwiftUI

// DAY IS WHAT'S COMING, FROM EVERY APP AND THE WALLET (prd §1327 item 3):
// Coming up's rows for what the app computes rather than stores — a plan's
// renewal with its price, a card's payment date with what it owes — each
// under its day, after that day's things, its line naming the place first
// (§1329 item 4), opening what it opens in its own place. The entries are
// read in Coming up's `.task` (`loadDayComingUp`), never in a body (§628).
extension FeedScreen {

    /// "Wallet · Subscription", "Wallet · Card": where the entry is from.
    static func dayDatedPlace(_ place: DayDated.Place) -> String {
        switch place {
        case .subscription: return String(localized: "Wallet · Subscription")
        case .card:         return String(localized: "Wallet · Card")
        }
    }

    /// The line: the place, a price rise in the Wallet's own words when its
    /// reading saw one, then what the day is and what pays it.
    static func dayDatedLine(_ entry: DayDated.Entry, mask: String?) -> Text {
        var rest: [String] = []
        switch entry.word {
        case .renews:     break
        case .nextCharge: rest.append(String(localized: "Next charge"))
        case .due:        rest.append(String(localized: "Payment due"))
        }
        if let pays = entry.paysWith { rest.append(pays) }
        let place = Text(verbatim: dayDatedPlace(entry.place))
        let tail = rest.isEmpty ? Text(verbatim: "") : Text(verbatim: " · " + rest.joined(separator: " · "))
        guard let was = entry.was else { return place + tail }
        let rise = Text("Price rise · was \(mask ?? CardSpendRoom.money(was, code: entry.currency))")
            .foregroundStyle(DS.attentionInk).fontWeight(.semibold)
        return place + Text(verbatim: " · ") + rise + tail
    }

    /// One computed entry, in its place's own anatomy: a plan as the
    /// Subscriptions row, a card as the Wallet's Cards row. The figure is the
    /// charge or what is owed, withheld under Hide balances.
    @ViewBuilder
    func dayDatedRow(_ entry: DayDated.Entry) -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let line = Self.dayDatedLine(entry, mask: mask)
        Button {
            switch entry.opens {
            case .plan(let id):
                feedSheet = .subscription(id)
            case .card(let app):
                openOutsideSheet { route.openSetup(forOffer: BridgeCatalog.seatName(forSource: app)) }
            }
        } label: {
            Group {
                switch entry.opens {
                case .plan:
                    SubscriptionRow(name: FeedScreen.shownName(entry.name), line: line) {
                        dayDatedFigure(entry, mask: mask)
                    }
                case .card(let app):
                    DSFeedRow(name: entry.name, line: line) {
                        BridgeIcon(name: BridgeCatalog.seatName(forSource: app), size: DS.Face.row,
                                   circular: true)
                    } trailing: {
                        dayDatedFigure(entry, mask: mask)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                  bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    /// A plan held for nothing says Free, never masked (§1164); a figure the
    /// reading did not say draws nothing.
    @ViewBuilder
    private func dayDatedFigure(_ entry: DayDated.Entry, mask: String?) -> some View {
        if entry.place == .subscription, entry.amount == 0 {
            Text(verbatim: SubscriptionWords.free)
                .dsText(.price17).foregroundStyle(DS.textSecondary)
        } else if let amount = entry.amount {
            Text(verbatim: mask ?? CardSpendRoom.money(amount, code: entry.currency))
                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
    }
}
