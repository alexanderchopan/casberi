import SwiftUI

/// **PRIVATE, IN HOLDINGS (prd §1547).** Under Tokens: a head naming what is
/// private and its total, one row per token and state off the notes Move to
/// private kept (`PrivateMoney.rows`) — "ETH, private", "ETH, moving in" with
/// the amber clock and "Waiting for approval", "ETH, not approved" — and the
/// verb, Move to private, as a pink word under them. Private is never the
/// default: nothing moves there unless you say so here.
///
/// Sepolia only for now; the verb draws in DEBUG builds only, whose testnet
/// sender sends it (`PrivateMove.available`), and the section stands only
/// where there is a verb or a note to show.
extension FeedScreen {

    @ViewBuilder
    var walletPrivateRows: some View {
        let store = PrivateMoneyStore.shared
        let rows = store.rows
        if selectedSeat == nil, PrivateMove.available || !rows.isEmpty {
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            Group {
                walletPrivateHead(total: rows.first { $0.kind == .held }.map {
                    mask ?? PrivateMoney.figure($0.amount, decimals: $0.decimals, symbol: $0.symbol)
                })
                .task(id: rows.map(\.id)) {
                    walletPrivateProbe()
                    await store.refresh()
                }
                ForEach(rows) { row in
                    walletPrivateRow(row, mask: mask)
                }
                if PrivateMove.available {
                    walletPrivateVerb
                }
            }
        }
    }

    /// The head: the door anatomy (`walletDoor`), with no page behind it, so
    /// it is a heading and not a control.
    private func walletPrivateHead(total: String?) -> some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .walletListRow()
    }

    /// One token in one state: the preview row's anatomy (`walletPreviewRow`),
    /// its state under the name where it is not plain private money.
    private func walletPrivateRow(_ row: PrivateMoney.Row, mask: String?) -> some View {
        let figure = mask ?? PrivateMoney.figure(row.amount, decimals: row.decimals, symbol: row.symbol)
        let (glyph, hue, state, stateInk): (String, Color, String?, Color) = switch row.kind {
        case .held: ("eye.slash", DS.brandInk, nil, DS.textSecondary)
        case .waiting: ("clock", DS.attention, String(localized: "Waiting for approval"), DS.attentionInk)
        case .refused: ("xmark.circle", DS.destructive, String(localized: "Not approved"), DS.destructiveInk)
        }
        return HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            Image(systemName: glyph)
                .dsGlyph(.body, weight: .regular)
                .foregroundStyle(hue)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                if let state {
                    Text(verbatim: state)
                        .dsText(.subhead12)
                        .foregroundStyle(stateInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            walletRowFigure(figure, tone: row.kind == .held ? DS.textPrimary : DS.textSecondary)
        }
        .walletRowPitch()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [row.title, state, figure].compactMap { $0 }.joined(separator: ". ")))
        .walletListRow()
    }

    /// Move to private: a word, pink, in the rows' column (Move's verbs are
    /// words, never a capsule).
    private var walletPrivateVerb: some View {
        Button {
            DSHaptic.selection()
            feedSheet = .movePrivate
        } label: {
            HStack(spacing: DSRoomChassis.headGap) {
                Color.clear.frame(width: DSRoomChassis.headGlyph, height: 1)
                Text("Move to private")
                    .dsText(.heading24)
                    .foregroundStyle(DS.pickInk)
                Spacer(minLength: 0)
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .walletListRow()
    }

    /// `-movePrivate YES` raises Move to private on Holdings, once a launch;
    /// `-privateMoneySample YES|clear` lays two sample notes first (DEBUG).
    private func walletPrivateProbe() {
        #if DEBUG
        guard !Self.movePrivateProbed, UserDefaults.standard.bool(forKey: "movePrivate") else { return }
        Self.movePrivateProbed = true
        NSLog("[Casberi] movePrivate: raised")
        feedSheet = .movePrivate
        #endif
    }
}
