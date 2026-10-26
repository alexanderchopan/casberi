import SwiftUI

/// **PRIVATE, IN HOLDINGS (prd §1547).** Under Tokens, Holdings only SHOWS
/// what is private: a head naming it with its total, then one row per token,
/// state and network off the notes Move to private kept (`PrivateMoney.rows`)
/// — "ETH, private" over its network ("Sepolia"; the ruling's "<rate>% on
/// Aave" once a pool earns, not built: Sepolia has no Aave), "ETH, moving in" with the amber clock and
/// "Waiting for approval", "ETH, not approved". The Tokens rows above are
/// public balances only; the box counts approved private money as one
/// Private block, and the total counts it once (`PrivateMoneyStore.walletHolding`). No verb here: the act is Move's
/// (`MovePrivateSentence`), and every row is its door, opening Move already
/// on "to private". Private is never the default.
///
/// Sepolia only for now. The section stands where there is a note to show,
/// or, in a DEBUG build whose test sender can move (`PrivateMove.available`),
/// as the head alone — the door with nothing behind it yet.
extension FeedScreen {

    @ViewBuilder
    var walletPrivateRows: some View {
        let store = PrivateMoneyStore.shared
        let rows = store.rows
        if selectedSeat == nil, PrivateMove.available || !rows.isEmpty {
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            Group {
                walletPrivateHead(total: mask ?? walletPrivateTotal(rows, prices: store.prices))
                    .task(id: rows.map(\.id)) {
                        await store.refresh()
                        await store.readPrices()
                    }
                ForEach(rows) { row in
                    walletPrivateRow(row, mask: mask, prices: store.prices)
                }
            }
        }
    }

    /// The section's total: the private dollars, as the box counts them; with
    /// none to count (test money, §949), one token's quantity, else nothing.
    private func walletPrivateTotal(_ rows: [PrivateMoney.Row], prices: [String: Double]) -> String? {
        let held = rows.filter { $0.kind == .held }
        let usd = held.compactMap { PrivateMoney.rowUSD($0, prices: prices) }
        if !usd.isEmpty { return WalletValue.money(usd.reduce(0, +)) }
        guard held.count == 1, let only = held.first else { return nil }
        return PrivateMoney.figure(only.amount, decimals: only.decimals, symbol: only.symbol)
    }

    /// Opens Move on its private sentence (prd §1547).
    private func walletOpenPrivate() {
        DSHaptic.selection()
        chrome.moveToPrivate = true
        chrome.moveTray = true
    }

    /// The head: the door anatomy (`walletDoor`), whose page is Move's
    /// private sentence.
    private func walletPrivateHead(total: String?) -> some View {
        Button { walletOpenPrivate() } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                Image(systemName: "eye.slash")
                    .dsGlyph(.body)
                    .foregroundStyle(DS.brandInk)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                Text("Private")
                    .dsText(.heading24)
                    .foregroundStyle(DS.headInk)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if let total {
                    Text(verbatim: total)
                        .dsText(.stat24)
                        .monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                }
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityLabel(Text(verbatim: [String(localized: "Private"), total].compactMap { $0 }.joined(separator: ". ")))
        .accessibilityHint(Text("Opens Move to private"))
        .walletListRow()
    }

    /// One token in one state on one network: the preview row's anatomy
    /// (`walletPreviewRow`) with a line under the name — the network for
    /// private money, the state for the rest.
    private func walletPrivateRow(_ row: PrivateMoney.Row, mask: String?, prices: [String: Double]) -> some View {
        let figure = mask ?? PrivateMoney.rowUSD(row, prices: prices).map(WalletValue.money)
            ?? PrivateMoney.figure(row.amount, decimals: row.decimals, symbol: row.symbol)
        let (glyph, hue, state, stateInk): (String?, Color, String, Color) = switch row.kind {
        case .held: (nil, DS.textSecondary, PrivateMoney.network(row.chainId), DS.textSecondary)
        case .waiting: ("clock", DS.attention, String(localized: "Waiting for approval"), DS.attentionInk)
        case .refused: ("xmark.circle", DS.destructive, String(localized: "Not approved"), DS.destructiveInk)
        }
        return Button { walletOpenPrivate() } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Group {
                    if let glyph {
                        Image(systemName: glyph)
                            .dsGlyph(.body, weight: .regular)
                            .foregroundStyle(hue)
                    } else {
                        AssetMark(name: row.symbol, size: DS.Mark.badge)
                    }
                }
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.title)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Text(verbatim: state)
                        .dsText(.subhead12)
                        .foregroundStyle(stateInk)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                walletRowFigure(figure, tone: row.kind == .held ? DS.textPrimary : DS.textSecondary)
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [row.title, state, figure].joined(separator: ". ")))
        .accessibilityHint(Text("Opens Move to private"))
        .walletListRow()
    }
}
