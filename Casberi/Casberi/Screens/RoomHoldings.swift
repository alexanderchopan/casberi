import SwiftUI

/// **THE HOLDINGS SLOT, ONE TEMPLATE FOR EVERY WALLET-FAMILY ROOM (prd §688).**
///
/// §683 did this for Home and §686/§687 for Activity. Holdings had drifted
/// further than either: the Wallet and vibenet mapped TOKENS, Hegotá and the
/// Privacy devnet mapped ADDRESSES, and Hegotá Frames had no such scope at all
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

    /// Every token held across the reached accounts, deduplicated by contract
    /// and SUMMED — a room's "All" is the sum of what it watches, exactly as
    /// its crown's is. Stated once here so two rooms cannot sum it two ways.
    static func merged(_ perAccount: [[DevnetTokens.Holding]]) -> [DevnetTokens.Holding] {
        var byContract: [String: DevnetTokens.Holding] = [:]
        for holdings in perAccount {
            for token in holdings {
                if let seen = byContract[token.id] {
                    byContract[token.id] = DevnetTokens.Holding(
                        contract: seen.contract, symbol: seen.symbol,
                        decimals: seen.decimals, raw: seen.raw + token.raw)
                } else {
                    byContract[token.id] = token
                }
            }
        }
        return byContract.values.sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
    }

    /// The coin and the tokens as drawable cells.
    ///
    /// **The coin is a cell like any other.** It is the largest holding on
    /// nearly every account on these chains, and leaving it out would map the
    /// small change while Home stated the rest.
    ///
    /// A token that could not name itself keeps its short address rather than
    /// an invented name, and one whose decimals did not read shows no quantity
    /// rather than a wrong one — `DevnetTokens.Holding`'s own rules.
    /// **THE COIN'S UNIT IS THE ROOM'S; A TOKEN'S IS ITS OWN NAME.** The
    /// rooms hand in their coin cell already spelled — each chain says "test
    /// ETH" its own way — and the tokens are spelled here, without a unit,
    /// because the cell and the row both name the asset beside the number.
    /// Letting a room format its tokens too is what produced "8.4K ETH" next
    /// to the word PEPE.
    static func cells(coin: Cell?, tokens: [DevnetTokens.Holding]) -> [Cell] {
        var out: [Cell] = []
        if let coin { out.append(coin) }
        for token in tokens {
            out.append(Cell(name: token.symbol ?? WalletStore.shortAddress(token.contract),
                            amount: token.amount.map(DevnetTokens.quantity)
                                ?? String(localized: "amount couldn't be read"),
                            symbol: token.symbol ?? "",
                            quantity: token.amount))
        }
        return out
    }
}

/// The figure: even cells, names only.
struct RoomHoldingsFigure: View {
    let cells: [RoomHoldings.Cell]
    /// The scope: one account's name, or how many you follow — the crown's
    /// own caption, so the two tiles identify themselves identically.
    var caption: String? = nil
    var box: CGFloat = DSRoomChassis.figureSlot

    /// USD per unit by MAINNET symbol, read once per mount (prd §922) — a
    /// fetch belongs in `.task`, never in a body (build 525).
    @State private var prices: [String: Double] = [:]
    @State private var read = false

    private struct Valued {
        let cell: RoomHoldings.Cell
        let mainnet: String
        let usd: Double
    }

    private var valued: [Valued] {
        cells.compactMap { cell in
            guard let mainnet = MainnetPrices.mainnetSymbol(cell.symbol),
                  let price = prices[mainnet],
                  let quantity = cell.quantity, quantity > 0 else { return nil }
            return Valued(cell: cell, mainnet: mainnet, usd: price * quantity)
        }
    }

    var body: some View {
        let valued = valued
        let total = valued.reduce(0) { $0 + $1.usd }
        let pricedIDs = Set(valued.map(\.cell.id))
        let unpriced = cells.filter { !pricedIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            reading(total: total, priced: valued.count)
            if !valued.isEmpty {
                // **THE WALLET'S OWN PACK (§917), AT MAINNET PRICES.** Each
                // circle's area is its share of the valued total; the mark is
                // the mainnet namesake's, so vUSDC wears USDC's coin, and the
                // readout keeps the chain's own spelling.
                DSCirclePack(items: valued.map { v in
                    let pct = total > 0 ? Int((v.usd / total * 100).rounded()) : 0
                    return DSCirclePackItem(id: v.cell.id, share: v.usd,
                                            label: "\(v.cell.name), \(WalletValue.money(v.usd)), \(pct)%")
                }, mark: { item, diameter in
                    AssetMark(name: valued.first { $0.cell.id == item.id }?.mainnet.uppercased() ?? item.id,
                              size: diameter)
                }, readout: { item in
                    item.label.replacingOccurrences(of: ", ", with: " · ")
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !cells.isEmpty {
                // **NOTHING PRICED: EQUAL CIRCLES, THE SYMBOL IN EACH.** No
                // invented size — the monogram circle `AssetMark` already
                // draws for a symbol with no mark, one per asset, all alike.
                DSCirclePack(items: cells.map {
                    DSCirclePackItem(id: $0.id, share: 1, label: "\($0.name), \($0.amount)")
                }, mark: { item, diameter in
                    AssetMark(name: item.id, size: diameter)
                }, readout: { item in
                    item.label.replacingOccurrences(of: ", ", with: " · ")
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if read, !unpriced.isEmpty, !valued.isEmpty {
                // The ones the pack leaves out, named — never guessed (§83).
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

    /// The reading — the same three lines as the crown's: caption, figure,
    /// and the one honest word about the figure.
    @ViewBuilder
    /// One number, one caption (prd §936): the mainnet value, then how
    /// many assets and whose.
    private func reading(total: Double, priced: Int) -> some View {
        let assets = cells.count == 1 ? String(localized: "1 asset")
                                      : String(localized: "\(String(cells.count)) assets")
        return DSFigureReading(
            number: priced > 0 ? WalletValue.money(total) : String(cells.count),
            caption: [priced > 0 ? String(localized: "\(assets) at mainnet prices")
                      : read ? (cells.count == 1 ? String(localized: "asset, none on mainnet")
                                                 : String(localized: "assets, none on mainnet"))
                             : String(localized: "reading mainnet prices"),
                      caption].compactMap { $0 }.joined(separator: " · "))
    }

    private func unpricedLine(_ unpriced: [RoomHoldings.Cell]) -> String {
        if unpriced.count == 1, let one = unpriced.first {
            return String(localized: "\(one.name) isn't on mainnet, so it isn't priced")
        }
        return String(localized: "\(String(unpriced.count)) aren't on mainnet, so they aren't priced")
    }
}

/// The list: one row per asset, in the family's own grammar — the mark, the
/// name, the amount on the right. The same anatomy vibenet's Holdings list has
/// had since it shipped, which is what makes two rooms' Holdings read as one
/// screen rather than two.
struct RoomHoldingsRows: View {
    let cells: [RoomHoldings.Cell]

    var body: some View {
        ForEach(cells) { cell in
            WalletRow(mark: .symbol("circle.grid.2x2.fill", tint: DS.tint),
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
