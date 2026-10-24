import SwiftUI
import SwiftData

/// The Wallet's Spending tile (prd §1468): the figure in the box and every
/// place under the tiles, over `SpendingReading`'s page reading. Home's
/// five-row list and its words stay in `FeedScreen+WalletHome.swift`.
extension FeedScreen {

    /// **SPENDING'S BOX (prd §1468).** The reading is the tile's own: the
    /// Subscriptions tile's items and the billers first, so the recurring
    /// half is what those already believe, then the charges. Nothing spent
    /// draws the scope's empty state once the reading has landed, and
    /// nothing before it, as Subscriptions does.
    @ViewBuilder
    var walletSpendingFigure: some View {
        let reading = SpendingReading.shared
        Group {
            if reading.page.places.isEmpty && reading.page.subscriptions.isEmpty {
                if !reading.read {
                    Color.clear
                } else if !reading.fed, wallet.addresses.isEmpty {
                    // **NOTHING COULD FEED IT YET (prd §1469, user: "a 'start
                    // here' kinda thing"):** Library's box (§1365), its three
                    // ways into this page, one row each — what a card
                    // charges, what you pay, what a wallet sends. No bank
                    // (user: "nobody will feel comfy adding their bank").
                    // The first one done gives the box back to the figure.
                    StartWaysIn(ways: [.card, .subscription, .wallet], rowHeight: DS.Hit.min + DS.Space.s3, inset: 0) {
                        startWay($0)
                    }
                } else {
                    // Fed, and nothing spent this window: the state, said.
                    WalletScopeEmptyFigure(section: .spending)
                }
            } else {
                WalletSpendingFigure(reading: reading.page, window: reading.window) { picked in
                    withAnimation(DS.Motion.standard) { SpendingReading.shared.pick(picked) }
                }
            }
        }
        .task(id: walletSpendingKey) {
            await SubscriptionsReading.shared.refresh(modelContext)
            await SpendingReading.shared.refresh(modelContext)
        }
    }

    /// A network's fees (prd §1476): how many transactions, then how it
    /// compares with the last window; under Hide balances the count alone.
    func spendingFeeRow(_ network: Spending.Place, window: Spending.Window, mask: String?) -> some View {
        SubscriptionRow(name: network.name,
                        line: Text(verbatim: Self.spendingFeeLine(network, window: window, mask: mask))) {
            Text(verbatim: mask ?? AppleWalletRoom.money(network.usd, "USD"))
                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .walletListRow()
    }

    static func spendingFeeLine(_ network: Spending.Place, window: Spending.Window,
                                now: Date = .now, mask: String?) -> String {
        let count = network.count == 1 ? String(localized: "One transaction")
                                       : String(localized: "\(network.count) transactions")
        guard mask == nil else { return count }
        guard let earlier = network.earlier, earlier > 0 else {
            return "\(count) · \(String(localized: "first time"))"
        }
        return "\(count) · \(spendingAgainst(network.usd, earlier: earlier, window: window, now: now, point: false))"
    }

    /// A subscription's row (prd §1469): its newest charge's day and what
    /// paid it — "Oct 14 · Apple Card", "Oct 2 · tracked by you" — and what
    /// it cost this window. Never compared: one price compares to itself.
    func spendingSubscriptionRow(_ plan: Spending.Place, mask: String?) -> some View {
        SubscriptionRow(name: plan.name, line: Text(verbatim: Self.spendingSubscriptionLine(plan))) {
            Text(verbatim: mask ?? AppleWalletRoom.money(plan.usd, "USD"))
                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .walletListRow()
    }

    static func spendingSubscriptionLine(_ plan: Spending.Place) -> String {
        var parts: [String] = []
        if let at = plan.lastAt { parts.append(at.formatted(.dateTime.month(.abbreviated).day())) }
        if let via = plan.via, !via.isEmpty {
            parts.append(via == Subscriptions.byYou ? String(localized: "tracked by you") : via)
        }
        if parts.isEmpty { parts.append(spendingTimes(plan.count)) }
        return parts.joined(separator: " · ")
    }
}
