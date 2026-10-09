import SwiftUI

/// **THE HOLDINGS SLOT, ONE TEMPLATE FOR EVERY WALLET-FAMILY ROOM (prd §688).**
///
/// §683 did this for Home and §686/§687 for Activity. Holdings had drifted
/// further than either: the Wallet and vibenet mapped TOKENS, Hegotá and the
/// Privacy devnet mapped ADDRESSES, and a third devnet had no such scope at all
/// — three answers to one question, plus an absence.
///
/// **Holdings' job is the SPLIT, and where nothing splits it is not the slot**
/// (user, 2026-09-11: *"i don't want to force fit something that belongs in its
/// own slot"*). Two of those address maps were answering a question the
/// **Accounts** scope already owns in both rooms, word for word — *"the
/// addresses you watch, and what each holds"*. What Holdings adds is the split
/// by ASSET, which is what the Wallet and vibenet were doing all along.
///
/// So an account holding only the chain's own coin draws **no map**: one cell
/// at 100% is the bar §610 removed, and the scope says what it would hold
/// instead (§611).
///
///   figure: even cells, the asset's name ⟶ list: mark, name, amount
///
/// **Even cells, and that is a correctness point rather than a preference**
/// (user: *"treemap should all be the same size and fill the slot"*). There is
/// no price on a devnet, so a `DAI` balance and a `YDS` balance are not on one
/// scale; a larger tile would claim a comparison the data cannot support.
/// **And the amount is not in the cell** (*"i'm not sure we need the amount
/// inside the tree since the list has the balances"*) — §680's ruling one slot
/// over: the row states it exactly, so the cell restating it is the figure
/// repeating its own list.
enum RoomHoldings {

    /// One asset. The chain's own coin first, then its tokens.
    struct Cell: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let amount: String
        /// The asset's symbol as the chain spells it ("vUSDC", "test ETH") —
        /// what `MainnetPrices.mainnetSymbol` reads to value it (prd §922).
        var symbol: String = ""
        /// The quantity as a number, in the asset's own unit; nil where the
        /// chain could not say (an unread decimals), which prices nothing.
        var quantity: Double? = nil
    }
}

/// The figure: even cells, names only.
struct RoomHoldingsFigure: View {
    let cells: [RoomHoldings.Cell]
    var box: CGFloat = DSRoomChassis.figureSlot

    @State private var prices: [String: Double] = [:]
    @State private var read = false

    /// **THE WALLET'S TREEMAP, OVER TEST MONEY (prd §949).** The number is how
    /// many assets, never a dollar total: mainnet prices over a devnet's test
    /// supply read "$2.6B" for 993 million test ETH. The prices still SIZE the
    /// tiles — a share of a devnet balance at mainnet weights — and a pressed
    /// tile reads the token's own quantity. A token with no mainnet price is
    /// in the list and the count, and not sized; with none priced at all,
    /// every tile is the same size, which says "how many", not "how much".
    var body: some View {
        let priced: [(cell: RoomHoldings.Cell, mainnet: String, usd: Double)] = cells.compactMap { cell in
            guard let mainnet = MainnetPrices.mainnetSymbol(cell.symbol),
                  let price = prices[mainnet],
                  let quantity = cell.quantity, quantity > 0 else { return nil }
            return (cell, mainnet, price * quantity)
        }
        let holdings: [HoldingsTreemap.Holding] = priced.isEmpty
            ? cells.map { .init(id: $0.symbol.isEmpty ? $0.name : $0.symbol, usd: 1, route: nil, display: $0.amount) }
            : priced.map { .init(id: $0.mainnet.uppercased(), usd: $0.usd, route: nil, display: $0.cell.amount) }
        let unpriced = priced.isEmpty ? [] : cells.filter { c in !priced.contains { $0.cell.id == c.id } }
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HoldingsTreemap(total: String(cells.count),
                            caption: cells.count == 1 ? String(localized: "asset")
                                                      : String(localized: "assets"),
                            holdings: holdings,
                            showsShares: !priced.isEmpty)
            if read, !unpriced.isEmpty {
                Text(unpricedLine(unpriced))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: cells.map(\.symbol).joined(separator: "|")) {
            prices = await MainnetPrices.prices(for: cells.map(\.symbol))
            read = true
        }
    }

    private func unpricedLine(_ unpriced: [RoomHoldings.Cell]) -> String {
        if unpriced.count == 1, let one = unpriced.first {
            return String(localized: "\(one.name) isn't on mainnet, so it isn't sized")
        }
        return String(localized: "\(String(unpriced.count)) aren't on mainnet, so they aren't sized")
    }
}

struct RoomHoldingsRows: View {
    let cells: [RoomHoldings.Cell]

    var body: some View {
        // The token's own mark, as the Wallet's Holdings rows wear (prd §949);
        // the amount pinned to the trailing edge.
        ForEach(cells) { cell in
            WalletRow(mark: .asset(cell.symbol.isEmpty ? cell.name : cell.symbol,
                                   tint: DS.tint, atRisk: false),
                      title: cell.name,
                      subtitleText: nil) {
                Text(cell.amount)
                    .dsText(.price17)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}
