import SwiftUI

/// Orders held on zFi's boards, in Holdings' Positions (2026-10-12, prd
/// §1281): one row per order — a fixed-price sell, a falling-price auction or
/// a rising bid — marked by its two assets.
///
/// A sibling of the Aztec staking card: the escrow is the trailing figure, in
/// its own units, never dollars (an escrow comes back whole on a cancel; a
/// fill's price was never quoted here). The line is where the order stands;
/// it takes the confirm ink only when the order has stopped filling with the
/// escrow still on the board — money waiting for you to take it back.
///
/// FLAT BY LAW like its neighbours — a plain VStack of `WalletRow`s.
struct WalletZFiOrdersCard: View {
    let book: ZFiOrders.Book

    var body: some View {
        if !book.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(book.orders, id: \.key) { order in
                    row(order)
                }
            }
        }
    }

    private func row(_ order: ZFiWire.Order) -> some View {
        let needsYou = ZFiWire.needsYou(order)
        return WalletRow(mark: .pair(ZFiWire.symbol(order.escrowToken, book.tokens),
                                     ZFiWire.symbol(order.otherToken, book.tokens)),
                         title: ZFiWire.title(order, book.tokens),
                         subtitleText: Text(ZFiWire.state(order, book.tokens))
                            .foregroundStyle(needsYou ? DS.confirmInk : DS.textTertiary)) {
            if let held = escrow(order) {
                WalletRowValue(value: held)
            }
        }
    }

    /// The escrow: an amount through the balance mask, or the NFT on sale.
    private func escrow(_ order: ZFiWire.Order) -> String? {
        let symbol = ZFiWire.symbol(order.escrowToken, book.tokens)
        if order.escrowIsNFT { return "\(symbol) #\(order.id)" }
        return ZFiWire.amount(order.escrowRaw, order.escrowToken, book.tokens).map { WalletValue.token($0, symbol) }
    }
}
