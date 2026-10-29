import SwiftUI

/// EVERYTHING THAT CAN ACT AS YOUR WALLETS, LISTED (prd §514, 2026-08-28).
///
/// **The gap this closes was a claim the code made and could not keep.**
/// `WalletPermissions.namesShown` says of the two holders a rung names: *"The
/// remainder is not hidden — the list below carries every holder."* That was
/// true of token grants, which `WalletApprovalExposureCard` lists in full, and
/// false of everything else: a Safe module and an EIP-7702 delegate were
/// COUNTED by the card and listed by nothing. Reported against
/// a real wallet whose Permissions scope drew *"6 · Can act as your wallet"*
/// over an empty page — six things with the most unbounded power in the scope,
/// four of them unreachable in the app at all.
///
/// **Nothing here signs and nothing here revokes** — §293's shape, and §112's
/// rule. A delegate row OPENS (prd §1594): its sheet says what it is, where
/// it is set, and offers the wallet app that set it, where it is undone. A
/// module row stays still: a module is removed by the Safe's own owners, and
/// a door with nowhere honest to land would be §83's dead control.
///
/// **No header.** The drawing directly above already says "Who can act for
/// you"; a second display line here is §447's two stacked headings, and it is
/// the same call `WalletNFTCollectionRows` made two scopes over. The
/// "Approvals" eyebrow on the card below is what separates the two halves.
///
/// Liveness: holds no `Thing` — every value here is a struct out of
/// `WalletPermissions`, so none of the SwiftData corollaries apply.
struct WalletActingPartiesRows: View {
    /// Already merged and already ordered by `WalletPermissionsSource` — the
    /// unbounded first, one row per thing however many of your wallets it acts
    /// for.
    let holders: [WalletPermissions.Holder]
    /// **FIVE ROWS, THEN ONE DOOR (prd §1408).** `cap` holds the list to that
    /// many until `open`; the door under the rows (`DSMoreRow`) calls `more`.
    /// Nil draws every row, for a caller with no fold.
    var cap: Int? = nil
    var open = false
    var more: (() -> Void)? = nil
    /// A delegate row's door (prd §1594), handed the holder's key — the
    /// delegate contract. Nil leaves every row still.
    var onOpen: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let all = WalletPermissions.actingHolders(holders)
        let folded = cap.map { all.count > $0 } ?? false
        let rows = (folded && !open) ? Array(all.prefix(cap ?? all.count)) : all
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, holder in
                    row(holder)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                if folded, let more {
                    DSMoreRow(title: open ? Text("Show fewer")
                                          : Text(verbatim: String(localized: "See all \(all.count)")),
                              opens: !open, action: more)
                }
            }
        }
    }

    /// **ONE ROW, THE WALLET LIST'S ANATOMY (prd §944).** Mark, name, and one
    /// line: the power's word — red only when it has no limit, the only red on
    /// the row — then whose wallet. A delegate opens its sheet (prd §1594),
    /// with no chevron, as every list row since §1272.
    @ViewBuilder
    private func row(_ holder: WalletPermissions.Holder) -> some View {
        if holder.power == .actsAsWallet, let onOpen {
            Button { onOpen(holder.key) } label: { rowBody(holder).contentShape(Rectangle()) }
                .buttonStyle(RowPress())
        } else {
            rowBody(holder)
        }
    }

    private func rowBody(_ holder: WalletPermissions.Holder) -> some View {
        HStack(spacing: DS.Space.s3) {
            AssetMark(name: holder.name, size: DS.Face.list)
            VStack(alignment: .leading, spacing: 2) {
                Text(holder.name)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                (Text(holder.power.short)
                    .foregroundStyle(holder.power.isUnbounded ? DS.attentionInk : DS.textTertiary)
                 + Text(" · \(detail(holder))").foregroundStyle(DS.textTertiary))
                    .dsText(.subhead12)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .walletRowPitch()
        .accessibilityElement(children: .combine)
    }

    /// "Main and …4f4f · No expiry" — whose wallet, after the power's word.
    ///
    /// **Naming the wallets is the other half of the report.** The same
    /// delegate on two of your addresses used to draw as two identical rows;
    /// merged, it is one row that has to say what it is one row FOR, or the
    /// merge has simply hidden a fact rather than tidied one.
    ///
    /// Every wallet is named, never "and 2 more": the list is capped by §170's
    /// five-wallet limit, so the longest this line can get is five names.
    private func detail(_ holder: WalletPermissions.Holder) -> String {
        let watched = WalletStore.shared.addresses
        let names = holder.accounts.map { WalletScopeRail.caption(for: $0, in: watched).name }
        let acts = names.isEmpty
            ? String(localized: "this account")
            : ListFormatter.localizedString(byJoining: names)
        guard let note = holder.note else { return acts }
        return "\(acts) · \(note)"
    }
}
