import SwiftUI

/// **YOUR AZTEC ACCOUNT IN THE WALLET (prd §1700, §1700a).** Two places, both
/// shown only once the account has been used (§1700a item 2):
///   - Holdings › Private, after 0xBow's private balance: one row per thing the
///     account holds (Fee Juice, and each token an app taught the wallet), its
///     line saying private or public on Aztec with Aztec's mark (§1685). Two
///     private places on purpose, never merged (§1700 item 4).
///   - Your account, beside the Safe: the Aztec account and its address's tail.
/// Amounts only: no dollar figure and nothing in the totals until a price is
/// read for what Aztec holds (a later step), so nothing here claims a worth.
extension FeedScreen {

    /// How long a reading stands before showing the place reads again.
    static let aztecReadInterval: TimeInterval = 5 * 60

    @ViewBuilder
    var walletAztecRows: some View {
        let store = AztecAccountStore.shared
        // Yours and All only, as private money (prd §1590): the account is yours.
        if store.isShown, selectedSeat == nil, !walletOnFollowing, selectedWallet.map(YourAccountDemo.isYours) ?? true {
            let held = store.snapshot.holdings.filter(\.isHeld)
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            Group {
                if held.isEmpty {
                    aztecRow(title: String(localized: "Your Aztec account"),
                             line: store.snapshot.address.map { AddressTail.short($0) } ?? "",
                             figure: String(localized: "Nothing yet"), mark: nil, tone: DS.textSecondary)
                } else {
                    ForEach(held) { holding in
                        aztecRow(title: holding.name,
                                 line: (holding.privateUnits.flatMap { Decimal(string: $0) } ?? 0) > 0
                                     ? String(localized: "Private on Aztec") : String(localized: "Public on Aztec"),
                                 figure: mask ?? Self.aztecFigure(holding),
                                 mark: holding.name, tone: DS.textPrimary)
                    }
                }
            }
            .task(id: store.snapshot.address) {
                let stale = store.snapshot.readAt.map { Date().timeIntervalSince($0) > Self.aztecReadInterval } ?? true
                if stale, AztecProver.isAvailable { await store.refresh() }
            }
        }
    }

    /// The amount, or the token's name alone when its decimals are unknown —
    /// never a guessed number.
    static func aztecFigure(_ holding: AztecAccountStore.Holding) -> String {
        guard let decimals = holding.decimals else { return holding.name }
        let units = [holding.privateUnits, holding.publicUnits]
            .compactMap { $0.flatMap { Decimal(string: $0) } }.reduce(0, +)
        return PrivateMoney.figure("\(units)", decimals: decimals, symbol: holding.name)
    }

    /// Holdings' row anatomy (`walletPrivateRow`), with no act: nothing opens
    /// until Aztec has its sends (§1700 step 4), so it is not a button.
    private func aztecRow(title: String, line: String, figure: String, mark: String?, tone: Color) -> some View {
        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            Group {
                if let mark { AssetMark(name: mark, size: DS.Mark.badge) } else { ProtocolInlineMark(mark: "aztec") }
            }
            .frame(width: DSRoomChassis.headGlyph)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                HStack(spacing: DS.Space.s1) {
                    // The holder's mark before the line (§1685), unless the
                    // row's lead is already Aztec's own mark.
                    if mark != nil { ProtocolInlineMark(mark: "aztec") }
                    Text(verbatim: line)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            walletRowFigure(figure, tone: tone)
        }
        .walletRowPitch()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [title, line, figure].joined(separator: ". ")))
        .walletListRow()
    }

    /// Your account's second account (§1700a item 1): the Aztec account beside
    /// the Safe, once used, its address's tail on the right.
    @ViewBuilder
    var walletAztecAccountRow: some View {
        let store = AztecAccountStore.shared
        if store.isShown, let address = store.snapshot.address {
            HStack(spacing: DSRoomChassis.headGap) {
                ProtocolInlineMark(mark: "aztec")
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                Text("Aztec account")
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: AddressTail.short(address))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
            }
            .walletRowPitch()
            .accessibilityElement(children: .combine)
            .walletStackRow()
        }
    }
}
