import SwiftUI

/// A DELEGATION, OPENED FROM PERMISSIONS (prd §1594, user: "how would someone
/// be able to know what they delegated to … and how would they be able to
/// revoke the delegation").
///
/// The money sheet's anatomy (§1394, §1396), composed from its parts rather
/// than `MoneySheetHead`, which reads a `MoneyReceipt` this has none of: the
/// delegate's face and name centred, what it can do as the figure, the
/// networks under it, the state only when there is one to say; then the
/// tiles; then Details.
///
/// **Revoke is a door, never a signature.** Only the account's own key can
/// undo an EIP-7702 delegation (a new authorization pointing at nothing), and
/// Casberi holds no key for a wallet it watches; your own account is a Safe,
/// which carries no delegation. So Revoke opens the wallet app that set it,
/// where it is undone, and is drawn only while that app is on this phone
/// (§83). An unknown contract has no app to name, so its sheet says what to
/// do instead, in the one sentence it carries (§748's money line).
struct WalletDelegationSheet: View {
    let delegation: WalletDelegation

    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                head
                    .padding(.top, DS.Space.s6)
                    .settleIn(delay: 0.06)
                DSScopeTiles(sections: tiles, active: SheetTile.none, verbs: Set(tiles),
                             bare: true, centered: true) { pick($0) }
                    .padding(.horizontal, DSRoomChassis.inset)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DSRoomChassis.leadGap)
                    .settleIn(delay: 0.08)
                if delegation.isUnknown {
                    Text("If you didn’t sign this, move your money to a new account.")
                        .dsText(.body17)
                        .foregroundStyle(DS.destructiveInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DSRoomChassis.leadInset)
                        .padding(.top, DS.Space.s4)
                }
                SheetCard(name: String(localized: "Details")) {
                    ForEach(facts, id: \.label) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                            Text(verbatim: fact.label).dsText(.body17).foregroundStyle(DS.textPrimary)
                            Spacer(minLength: DS.Space.s2)
                            Text(verbatim: fact.value).dsText(.body17).foregroundStyle(DS.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, DS.Space.s2)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, DS.Space.s6)
                .padding(.bottom, DS.Space.s6)
            }
        }
        .subscriptionSheet()
        // A copy wears a checkmark for a beat, as the thing sheet's does.
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            copied = false
        }
    }

    // MARK: The head

    private var head: some View {
        VStack(spacing: 0) {
            VStack(spacing: DS.Space.s3) {
                AssetMark(name: delegation.name ?? "", size: DS.Face.sheet)
                Text(verbatim: delegation.name ?? AddressTail.short(delegation.delegate))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Text(verbatim: WalletPermissions.Power.actsAsWallet.short)
                .dsText(.heading24)
                .foregroundStyle(delegation.isUnknown ? DS.destructiveInk : DS.attentionInk)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.top, DS.Space.s2)
            Text(verbatim: networks)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .padding(.top, DS.Space.s1)
            if delegation.isUnknown {
                Text("Unknown")
                    .dsText(.heading17)
                    .foregroundStyle(DS.destructiveInk)
                    .padding(.top, DS.Space.s2)
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var networks: String {
        delegation.networks
            .map { WalletIngest.displayName(forNetwork: $0) ?? $0 }
            .joined(separator: " · ")
    }

    // MARK: The tiles

    private var appURL: URL? {
        guard let app = delegation.app,
              HandOffState.installedSchemes.contains(app.scheme) else { return nil }
        return URL(string: "\(app.scheme)://")
    }

    private var explorerURL: URL? {
        delegation.networks.first
            .flatMap { WalletIngest.explorerAddressURL(forNetwork: $0, address: delegation.delegate) }
            .flatMap(URL.init(string:))
    }

    private var tiles: [SheetTile] {
        var out: [SheetTile] = []
        if appURL != nil {
            out.append(SheetTile(id: "revoke", label: String(localized: "Revoke"), glyph: ScopeTileGlyph.open))
        }
        if explorerURL != nil {
            out.append(SheetTile(id: "explorer", label: String(localized: "Explorer"), glyph: ScopeTileGlyph.open))
        }
        out.append(SheetTile(id: "copy", label: String(localized: "Copy"), glyph: copied ? "checkmark" : "doc.on.doc"))
        return out
    }

    private func pick(_ tile: SheetTile) {
        switch tile.id {
        case "revoke": appURL.map { UIApplication.shared.open($0) }
        case "explorer": explorerURL.map { UIApplication.shared.open($0) }
        case "copy":
            DSPasteboard.copy(delegation.delegate)
            copied = true
        default: break
        }
    }

    // MARK: Details

    private var facts: [(label: String, value: String)] {
        let watched = WalletStore.shared.addresses
        let names = delegation.accounts.map { WalletScopeRail.caption(for: $0, in: watched).name }
        return [
            (String(localized: "Status"), String(localized: "Active")),
            (delegation.accounts.count > 1 ? String(localized: "Accounts") : String(localized: "Account"),
             ListFormatter.localizedString(byJoining: names)),
            (String(localized: "Contract"), AddressTail.short(delegation.delegate)),
        ]
    }
}
