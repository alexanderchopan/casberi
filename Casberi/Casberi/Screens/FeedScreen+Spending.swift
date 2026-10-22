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

    /// **TWO GROUPS, EACH ONE OF THE BOX'S ROWS (prd §1469, user: "you have
    /// places, but we could also have subscriptions").** Subscriptions first,
    /// newest charge first, each saying its day and what paid it; then every
    /// place, largest first, against the last window (§1468). No cap and no
    /// door: the tile is the page. Empty rows (§769) once the reading has
    /// landed on nothing.
    @ViewBuilder
    var walletSpendingPageSections: some View {
        let reading = SpendingReading.shared
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        if reading.page.places.isEmpty && reading.page.subscriptions.isEmpty {
            if reading.read { walletSkeletonRowsSection }
        } else {
            if !reading.page.subscriptions.isEmpty {
                walletCard(Self.subscriptionsName, glyph: ScopeTileGlyph.subscriptions) {
                    ForEach(reading.page.subscriptions, id: \.name) { plan in
                        spendingSubscriptionRow(plan, mask: mask)
                    }
                }
            }
            if !reading.page.places.isEmpty {
                walletCard(String(localized: "Places"), glyph: ScopeTileGlyph.spending) {
                    ForEach(reading.page.places, id: \.name) { place in
                        spendingPlaceRow(place, window: reading.window, mask: mask)
                    }
                }
            }
        }
    }

    /// A subscription's row (prd §1469): its newest charge's day and what
    /// paid it — "Oct 14 · Apple Card", "Oct 2 · tracked by you" — and what
    /// it cost this window. Never compared: one price compares to itself.
    func spendingSubscriptionRow(_ plan: Spending.Place, mask: String?) -> some View {
        SubscriptionRow(name: plan.name, line: Text(verbatim: Self.spendingSubscriptionLine(plan))) {
            Text(verbatim: mask ?? AppleWalletRoom.money(plan.usd, "USD"))
                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                  bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
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
