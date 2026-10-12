import SwiftUI

/// AZTEC staked on Aztec mainnet, in Holdings' Positions (2026-10-12, prd
/// §1277): one row per sequencer the watched wallets can withdraw.
///
/// A sibling of the perps and liquidity cards, not a row inside Lending:
/// nothing is borrowed. The amount is AZTEC, never dollars (the locks rule,
/// `WalletComposition` rule 2). The line is the stake's state, and it takes
/// an ink only when it asks something of you: "Ready to withdraw" (money
/// waiting to be collected) or "Stopped" (a sequencer slashed below the
/// minimum, which can only exit).
///
/// FLAT BY LAW like its neighbours — a plain VStack of `WalletRow`s.
struct WalletAztecStakingCard: View {
    let book: AztecStaking.Book

    var body: some View {
        if !book.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(book.stakes, id: \.attester) { stake in
                    row(stake)
                }
            }
            .padding(.bottom, DS.Space.s4)
        }
    }

    private func row(_ stake: AztecStakeWire.Stake) -> some View {
        let needsYou = AztecStakeWire.needsYou(stake)
        return WalletRow(mark: .asset("Aztec", tint: needsYou ? DS.attention : DS.tint, atRisk: needsYou),
                         title: String(localized: "Sequencer \(WalletStore.shortAddress(stake.attester))"),
                         subtitleText: line(stake, needsYou: needsYou)) {
            WalletRowValue(value: WalletValue.token(stake.amount, "AZTEC"))
        }
    }

    private func line(_ stake: AztecStakeWire.Stake, needsYou: Bool) -> Text {
        let ink: Color = !needsYou ? DS.textTertiary
            : stake.status == .zombie ? DS.attentionInk : DS.confirmInk
        return Text(AztecStakeWire.state(stake)).foregroundStyle(ink)
    }
}
