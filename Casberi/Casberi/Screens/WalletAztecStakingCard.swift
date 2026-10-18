import SwiftUI

/// AZTEC staked on Aztec mainnet, in Holdings' Positions (2026-10-12, prd
/// §1277, §1279): one row per sequencer the watched wallets can withdraw,
/// then one per token-sale vault still holding unstaked AZTEC.
///
/// A sibling of the perps and liquidity cards, not a row inside Lending:
/// nothing is borrowed. Amounts are AZTEC, never dollars (the locks rule,
/// `WalletComposition` rule 2). The line is the stake's state, then what it
/// has earned when that can be read; the state takes an ink only when it asks
/// something of you: "Ready to withdraw" (money waiting to be collected),
/// "Stopped" or "Missing attestations" (a sequencer that is not working).
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
                ForEach(book.vaults.filter { $0.held > 0 }, id: \.atp) { vault in
                    vaultRow(vault)
                }
            }
        }
    }

    private func row(_ stake: AztecStakeWire.Stake) -> some View {
        let needsYou = AztecStakeWire.needsYou(stake)
        return WalletRow(mark: .asset("Aztec", tint: needsYou ? DS.attention : DS.brandInk, atRisk: needsYou),
                         title: String(localized: "Sequencer \(WalletStore.shortAddress(stake.attester))"),
                         subtitleText: line(stake, needsYou: needsYou)) {
            WalletRowValue(value: WalletValue.token(stake.amount, "AZTEC"))
        }
    }

    private func line(_ stake: AztecStakeWire.Stake, needsYou: Bool) -> Text {
        let ink: Color = !needsYou ? DS.textTertiary
            : stake.status == .exiting ? DS.confirmInk : DS.attentionInk
        var out = Text(AztecStakeWire.state(stake)).foregroundStyle(ink)
        if let earned = AztecStakeWire.earned(stake) {
            out = out + Text(verbatim: " · ").foregroundStyle(DS.textTertiary)
                + Text(earned).foregroundStyle(DS.textTertiary)
        }
        return out
    }

    /// "Token vault …76d1" — "Locked", or what of it can be taken now; no
    /// line when that could not be read, never "Locked" in its place.
    private func vaultRow(_ vault: AztecStakeWire.Vault) -> some View {
        WalletRow(mark: .asset("Aztec", tint: DS.brandInk),
                  title: String(localized: "Token vault \(WalletStore.shortAddress(vault.atp))"),
                  subtitleText: vaultLine(vault)) {
            WalletRowValue(value: WalletValue.token(vault.held, "AZTEC"))
        }
    }

    private func vaultLine(_ vault: AztecStakeWire.Vault) -> Text? {
        guard let claimable = vault.claimable else { return nil }
        return claimable >= 0.01
            ? Text(String(localized: "\(AztecStakeWire.plain(claimable)) AZTEC claimable")).foregroundStyle(DS.confirmInk)
            : Text(String(localized: "Locked")).foregroundStyle(DS.textTertiary)
    }
}
