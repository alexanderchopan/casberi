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
                    // Reading draws as Holdings' does (prd §1587).
                    WalletScopeEmptyFigure(section: .spending, reading: true)
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
        // The account the search tray picked, or All (prd §1524); set before
        // the read so its first page is already that account's.
        .onChange(of: walletSpendingScope, initial: true) { _, scope in
            SpendingReading.shared.narrow(scope)
        }
        .task(id: walletSpendingKey) {
            await SubscriptionsReading.shared.refresh(modelContext)
            await SpendingReading.shared.refresh(modelContext)
        }
    }

    /// **WHOSE SPENDING (prd §1524):** the app or the wallet the search tray
    /// picked, else All. An app is the sources its rows land under, empty
    /// for one that spends nothing (Spending dims there); a wallet is every
    /// spelling it is followed by.
    var walletSpendingScope: Spending.Scope {
        if let seat = selectedSeat {
            return .app(Set(SpendingReading.sources.filter(seat.owns)))
        }
        // One wallet, or every wallet you follow (prd §1536): each by every
        // spelling it is followed by.
        if let addresses = selectedWallet.map({ [$0] }) ?? walletFollowingOnly {
            var forms: Set<String> = []
            for address in addresses {
                forms.insert(address.lowercased())
                if let hex = wallet.resolvedForm(of: address) { forms.insert(hex.lowercased()) }
            }
            return .wallet(forms)
        }
        return .all
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

    /// **A ROUND-UP'S BUY (prd §1523):** the token it bought, its day and
    /// network, and the dollars it took. The buy the count starts from says
    /// so: buys before the mark was kept are not counted (§83).
    func spendingRoundUpRow(_ buy: Spending.RoundUp, mask: String?) -> some View {
        SubscriptionRow(name: buy.bought.symbol,
                        line: Text(verbatim: Self.spendingRoundUpLine(buy, from: SpendingReading.shared.page.roundUpsFrom))) {
            Text(verbatim: mask ?? AppleWalletRoom.money(buy.usd, "USD"))
                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .walletListRow()
    }

    static func spendingRoundUpLine(_ buy: Spending.RoundUp, from: Date?) -> String {
        var parts = [buy.at.formatted(.dateTime.month(.abbreviated).day()),
                     String(localized: "on \(buy.bought.network)")]
        if let from, from == buy.at { parts.append(String(localized: "first counted")) }
        return parts.joined(separator: " · ")
    }

    /// The change counted and not yet bought (prd §1523): what it buys, and
    /// at what.
    func spendingRoundUpWaitingRow(_ usd: Double, mask: String?) -> some View {
        let setting = RoundUps.setting
        let at = AppleWalletRoom.money((Double(RoundUps.buyAt) ?? 5_000_000) / pow(10, Double(RoundUps.dollarDecimals)), "USD")
        return SubscriptionRow(name: String(localized: "Waiting"),
                               line: Text(verbatim: String(localized: "Buys \(setting.target.symbol) at \(at)"))) {
            Text(verbatim: mask ?? AppleWalletRoom.money(usd, "USD"))
                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .walletListRow()
    }

    /// The Round-ups door's word while nothing is bought this window:
    /// "$2.60 waiting"; under Hide balances "Waiting".
    static func spendingRoundUpWaiting(_ usd: Double, mask: String?) -> String {
        guard mask == nil else { return String(localized: "Waiting") }
        return String(localized: "\(AppleWalletRoom.money(usd, "USD")) waiting")
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
