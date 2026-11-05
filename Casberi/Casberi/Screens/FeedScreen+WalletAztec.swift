import SwiftUI

/// **YOUR AZTEC ACCOUNT IN THE WALLET (prd §1700, §1700a).** Two places, both
/// shown only once the account has been used (§1700a item 2):
///   - Holdings › Private, after 0xBow's private balance: one row per thing the
///     account holds (Fee Juice, and each token an app taught the wallet), its
///     line saying private or public on Aztec with Aztec's mark (§1685). Two
///     private places on purpose, never merged (§1700 item 4).
///   - Your account, beside the Safe: the Aztec account and its address's tail.
/// Shield's USDC and WETH in dollars, counted once in the Wallet's total as
/// one Aztec block (`AztecAccountStore.walletHolding`); Fee Juice, and any
/// token without a price, as an amount only.
extension FeedScreen {

    /// How long a reading stands before showing the place reads again.
    static let aztecReadInterval: TimeInterval = 5 * 60

    @ViewBuilder
    var walletAztecRows: some View {
        let store = AztecAccountStore.shared
        // Yours and All only, as private money (prd §1590): the account is yours.
        if store.isShown, selectedSeat == nil, !walletOnFollowing, selectedWallet.map(YourAccountDemo.isYours) ?? true {
            let held = store.shown.holdings.filter(\.isHeld)
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            Group {
                if held.isEmpty {
                    aztecRow(title: String(localized: "Your Aztec account"),
                             line: store.shown.address.map { AddressTail.short($0) } ?? "",
                             figure: String(localized: "Nothing yet"), mark: nil, tone: DS.textSecondary)
                } else {
                    ForEach(held) { holding in
                        aztecRow(title: holding.name,
                                 line: (holding.privateUnits.flatMap { Decimal(string: $0) } ?? 0) > 0
                                     ? String(localized: "Private on Aztec") : String(localized: "Public on Aztec"),
                                 figure: mask ?? store.usd(holding).map(WalletValue.money) ?? Self.aztecFigure(holding),
                                 mark: holding.name, tone: DS.textPrimary)
                    }
                }
            }
            .task(id: store.shown.address) {
                _ = await store.walletHolding() // the rows' prices (the demo's are its own)
                // Never in the demo: its account is sample data, no engine runs.
                guard !DemoMode.isActive else { return }
                let stale = store.snapshot.readAt.map { Date().timeIntervalSince($0) > Self.aztecReadInterval } ?? true
                if stale, AztecProver.isAvailable {
                    await store.refresh()
                    _ = await store.walletHolding()
                }
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

    /// Your account's accounts (§1700a item 1): once the Aztec account has
    /// been used, the card lists both — the Safe, then Aztec — by their own
    /// names, the line under each saying how it works and its address's tail
    /// ("Public · …c8e01", "Private · …2b3c"; user, 2026-11-04: "do as you
    /// recommend"). Not "Public/Private account": 0xBow's private balance is a
    /// third private place, and Aztec can hold public balances too. Before
    /// Aztec is used the box above already names the Safe, so no list is drawn.
    @ViewBuilder
    func walletAccountList(safe: String) -> some View {
        let store = AztecAccountStore.shared
        if store.isShown, let aztec = store.shown.address {
            accountListRow(mark: "safe", title: String(localized: "Safe"),
                           line: String(localized: "Public · \(AddressTail.short(safe))"))
            accountListRow(mark: "aztec", title: String(localized: "Aztec"),
                           line: String(localized: "Private · \(AddressTail.short(aztec))"))
        }
    }

    /// The Holdings row's anatomy: the mark, the name over its line.
    private func accountListRow(mark: String, title: String, line: String) -> some View {
        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            ProtocolInlineMark(mark: mark)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(verbatim: line)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .walletRowPitch()
        .accessibilityElement(children: .combine)
        .walletStackRow()
    }
}
