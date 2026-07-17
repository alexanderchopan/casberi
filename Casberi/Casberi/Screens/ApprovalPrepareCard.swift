import SwiftUI

/// The approval thing's prepare card (prd §112) — the preparing surface drawn
/// as UI. Everything on it is a read or a hand-off: the grant's LIVE state,
/// the fee a revoke would cost, and two doors out (Revoke.cash, where the
/// signing lives; the prepared transaction on the pasteboard, for any wallet).
/// No control here can move funds — the footer says so in the same words the
/// Wallet screen already uses. Renders only once the check answered (no dead
/// section, no spinner theater — the replies section's rule).
struct ApprovalPrepareCard: View {
    let thing: Thing
    let check: WalletPrepare.Check
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if check.active {
                Text(verbatim: statusLine)
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let fee = check.feeLine {
                    feeRow(fee)
                }
                // The door is built from the thing's own fields (owner +
                // chain), never read off `content` — a door labelled
                // Revoke.cash must only ever open Revoke.cash.
                if let url = URL(string: check.revokeURL) {
                    doorRow(icon: "arrow.up.right", label: "Revoke on Revoke.cash") {
                        openURL(url)
                    }
                }
                if let json = check.transactionJSON {
                    doorRow(icon: copied ? "checkmark" : "doc.on.doc",
                            label: copied ? "Copied" : "Copy revoke transaction") {
                        copy(json)
                    }
                }
                Text("A transaction you sign there — never in Casberi.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            } else {
                // The closed loop, from reads alone: the person revoked in
                // their wallet or on Revoke.cash, and the chain now says so.
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.confirm)
                    Text("No longer active — this approval has been revoked.")
                        .dsText(.callout15).foregroundStyle(DS.confirm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    /// Copy + the brief "Copied" acknowledgment — TokenSetupScreen's
    /// `copyCode` shape, reset included (a button stuck on "Copied" forever
    /// reads as state it no longer has).
    private func copy(_ json: String) {
        UIPasteboard.general.string = json
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(DS.Motion.standard) { copied = false }
        }
    }

    /// "Still active — Uniswap can still spend this token" — the spender named
    /// only when honestly known, the title's own rule.
    private var statusLine: String {
        let cp = thing.counterpartyAddress ?? ""
        let spender = WalletIngest.knownLabel(for: cp) ?? WalletStore.shortAddress(cp)
        return check.forAll
            ? String(localized: "Still active — \(spender) can still manage this collection")
            : String(localized: "Still active — \(spender) can still spend this token")
    }

    private func feeRow(_ fee: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Fee to revoke")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .frame(width: 110, alignment: .leading)
            Text(verbatim: fee)
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func doorRow(icon: String, label: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
