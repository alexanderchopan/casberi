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
            if reading.page.places.isEmpty {
                if reading.read {
                    WalletScopeEmptyFigure(section: .spending)
                } else {
                    Color.clear
                }
            } else {
                WalletSpendingFigure(reading: reading.page, window: reading.window) { picked in
                    withAnimation(DS.Motion.standard) { SpendingReading.shared.pick(picked) }
                }
            }
        }
        .task(id: walletSpendingKey) {
            await SubscriptionsReading.shared.refresh(modelContext)
            BillersSource.read(context: modelContext)
            await SpendingReading.shared.refresh(modelContext)
        }
    }

    /// **EVERY PLACE, LARGEST FIRST (prd §1468)**, each row against the last
    /// window. No cap and no door: the tile is the page. Empty rows (§769)
    /// once the reading has landed on nothing.
    @ViewBuilder
    var walletSpendingPageSections: some View {
        let reading = SpendingReading.shared
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        if reading.page.places.isEmpty {
            if reading.read { walletSkeletonRowsSection }
        } else {
            Section {
                ForEach(reading.page.places, id: \.name) { place in
                    spendingPlaceRow(place, window: reading.window, mask: mask)
                }
            }
        }
    }
}
