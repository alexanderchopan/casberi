import SwiftUI

/// **THE CO-SIGNER'S APPROVALS ARE ONE DOOR (prd §1861, user: "shouldn't we
/// be able to show ones a user has or let them check them for their
/// cosigner").**
///
/// The co-signer is a key in another wallet app. What it approved cannot
/// reach your account's money, only what that key's own address holds, and
/// that address can hold money (it is the way into Aztec, §1720). Permissions
/// read nothing of it unless you followed the address by hand.
///
/// **A door, not a list, because the list cannot be read.** Approvals are
/// read FORWARD from the day an address is first seen (`WalletApprovals`: a
/// cursor, never a backfill), so a list here would stand empty over grants
/// made years ago and read as "none". No keyless host gives the history
/// either (measured 2026-11-17: Blockscout refuses on Base and answers
/// nothing for a whole-chain owner query on Ethereum). Revoke.cash is the
/// complete record, and the place the co-signer's own wallet signs a revoke.
///
/// Nothing here signs (§112). Liveness: holds no `Thing`.
struct WalletCoSignerRows: View {
    /// The co-signer keys, as `YourAccountFacts.coSigners` last read them.
    let keys: [String]
    /// The wallet app holding each key, where a kept session names it. Read
    /// in `.task`, never in the body: it walks WalletConnect's sessions.
    @State private var wallets: [String: String] = [:]
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(keys, id: \.self) { key in row(key) }
        }
        .task(id: keys) {
            var found: [String: String] = [:]
            for key in keys {
                if let wallet = YourAccountSignerLink.walletHolding(key) { found[key] = wallet.name }
            }
            wallets = found
        }
    }

    /// The Wallet list's anatomy (prd §944): the mark, the wallet app's name
    /// over the key's tail (the tail alone when no session names the app),
    /// and the verb trailing with the mark of a door out of the app (§449).
    private func row(_ key: String) -> some View {
        let tail = AddressTail.short(key)
        let name = wallets[key]
        return Button {
            DSHaptic.tap()
            if let url = URL(string: WalletApprovals.revokeURL(address: key)) { openURL(url) }
        } label: {
            HStack(spacing: DS.Space.s3) {
                // The wallet app's mark once a session names it; until then
                // a key, never a disc lettered from an address's dots.
                if let name {
                    AssetMark(name: name, size: DS.Face.list)
                } else {
                    Image(systemName: "key")
                        .dsGlyph(.body)
                        .foregroundStyle(DS.brandInk)
                        .frame(width: DS.Face.list)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name ?? tail)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if name != nil {
                        Text(verbatim: tail)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: DS.Space.s2)
                DSPushRowTrail(fact: Text("Check approvals"), glyph: "arrow.up.right")
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Check approvals for co-signer \(name ?? tail) on Revoke.cash"))
    }
}

extension FeedScreen {
    /// Permissions' Co-signer group (prd §1861): on All, or with your account
    /// picked, once a co-signer stands. Under Approvals, which lists what
    /// your account and the wallets you follow let others spend.
    @ViewBuilder
    var walletCoSignerSection: some View {
        if let account = YourAccountDemo.shownAddress,
           chrome.walletScope == nil || WalletWatch.sameAddress(chrome.walletScope ?? "", account) {
            let keys = YourAccountFacts.coSigners.filter { ENS.isHexAddress($0) }
            if !keys.isEmpty {
                walletCard(String(localized: "Co-signer"), glyph: "person.badge.key", anchor: "coSigner") {
                    WalletCoSignerRows(keys: keys)
                        .walletStackRow()
                }
            }
        }
    }
}
