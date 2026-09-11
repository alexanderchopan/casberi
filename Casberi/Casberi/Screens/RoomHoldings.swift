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
                                ?? String(localized: "amount couldn't be read")))
        }
        return out
    }
}

/// The figure: even cells, names only.
struct RoomHoldingsFigure: View {
    let cells: [RoomHoldings.Cell]
    var box: CGFloat = DSRoomChassis.figureSlot

    var body: some View {
        let drawn = Array(cells.prefix(UnitTreemap<EmptyView>.maxCells))
        if !drawn.isEmpty {
            UnitTreemap(count: drawn.count,
                        height: DSRoomChassis.crownLine(box: box, chrome: 24),
                        even: true,
                        cell: { i in tile(drawn[i], rank: i) },
                        readout: { i in "\(drawn[i].name) · \(drawn[i].amount)" })
        }
    }

    /// Hegotá's tile recipe, to the token — the name over the sheet under an
    /// ink wash, `s3` padding. Copied deliberately rather than re-invented:
    /// a treemap cell that differs between two rooms is the drift §683 spent
    /// itself removing.
    ///
    /// **The wash is by RANK, not by share.** With no price, "share of the
    /// total" is a comparison across units that does not exist; rank is what
    /// the order already claims and all it claims.
    @ViewBuilder private func tile(_ cell: RoomHoldings.Cell, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.name)
                .dsText(.callout15)
                .fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                DS.surfaceSheet
                DS.ink(magnitude: max(0, 1 - Double(rank) * 0.22))
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
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
                    .dsText(.price16)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}
