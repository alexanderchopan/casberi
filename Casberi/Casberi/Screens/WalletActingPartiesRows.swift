import SwiftUI

/// EVERYTHING THAT CAN ACT AS YOUR WALLETS, LISTED (prd §514, 2026-08-28).
///
/// **The gap this closes was a claim the code made and could not keep.**
/// `WalletPermissions.namesShown` says of the two holders a rung names: *"The
/// remainder is not hidden — the list below carries every holder."* That was
/// true of token grants, which `WalletApprovalExposureCard` lists in full, and
/// false of everything else: a Safe module, an EIP-7702 delegate and an Altana
/// credential were COUNTED by the card and listed by nothing. Reported against
/// a real wallet whose Permissions scope drew *"6 · Can act as your wallet"*
/// over an empty page — six things with the most unbounded power in the scope,
/// four of them unreachable in the app at all.
///
/// **A list, not a control** — §293's shape, and §112's rule: nothing here
/// signs and nothing here revokes. A row carries no chevron because there is
/// no honest destination: a delegate is undone by re-delegating from the
/// wallet app that set it, and a module by the Safe's own owners. A door that
/// looked live and landed on a block explorer would be §83's dead control
/// wearing a chevron.
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
    /// The raw read, for the two ceilings a holder list structurally cannot
    /// state: an account whose modules cannot be enumerated has NO holders to
    /// show, so an empty list is exactly what a silent ceiling looks like.
    let acting: [WalletActingParties.Account]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rows = WalletPermissions.actingHolders(holders)
        if !rows.isEmpty || !ceilings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, holder in
                    row(holder)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                ForEach(ceilings, id: \.self) { note in
                    Text(note)
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s2)
                }
            }
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.bottom, DS.Space.s4)
        }
    }

    private func row(_ holder: WalletPermissions.Holder) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            // The same mark the approvals rows wear, so the two halves of this
            // scope read as one list. `AssetMark` invents no hue for a name it
            // does not bundle — a delegate contract usually resolves to a
            // monogram, which is the honest drawing for a name we cannot
            // illustrate.
            AssetMark(name: holder.name, size: 26)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(holder.name)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                // The rung's own sentence, so a row and the count above it can
                // never describe the same holder differently.
                Text(holder.power.phrase)
                    .dsText(.subhead13)
                    .foregroundStyle(holder.power.isUnbounded ? DS.attention : DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail(holder))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s2)
        .accessibilityElement(children: .combine)
    }

    /// "Acts for Main and …4f4f · No expiry".
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
            ? String(localized: "Acts for this wallet")
            : String(localized: "Acts for \(ListFormatter.localizedString(byJoining: names))")
        guard let note = holder.note else { return acts }
        return "\(acts) · \(note)"
    }

    /// What this scope CANNOT see, said out loud (§293's ceiling rule: a
    /// surface that listed nothing and looked complete is worse than one that
    /// says it cannot look).
    ///
    /// Counted rather than named per account, because the reason is the same
    /// for every one of them and five copies of one sentence is not five
    /// facts.
    private var ceilings: [String] {
        var out: [String] = []
        let unreadable = acting.filter(\.modulesUnreadable).count
        if unreadable == 1 {
            out.append(String(localized: "One of your accounts is a smart account whose installed modules can't be listed — this app can see that it is one, not what is in it."))
        } else if unreadable > 1 {
            out.append(String(localized: "\(unreadable) of your accounts are smart accounts whose installed modules can't be listed — this app can see that they are, not what is in them."))
        }
        if acting.contains(where: \.keystorePartial) {
            out.append(String(localized: "One account holds more keys than a single pass reads, so this list is a floor."))
        }
        return out
    }
}
