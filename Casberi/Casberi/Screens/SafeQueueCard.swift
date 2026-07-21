import SwiftUI

/// A Safe multisig thing's live queue card (2026-07-20) — the same shape as
/// `ApprovalPrepareCard`: a read-only recheck, rendered only once it's
/// answered (no spinner theater). No door out (the Safe web app's per-chain
/// URL prefix couldn't be verified for every chain — see `SafeBridge`'s doc
/// comment); the footer says signing lives in the person's own Safe app,
/// never here.
struct SafeQueueCard: View {
    let check: SafeBridge.Check

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            switch check.status {
            case .pending(let have, let required):
                Text(verbatim: statusLine(have: have, required: required))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                progressRow(have: have, required: required)
            case .resolved:
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.confirm)
                    Text("No longer pending — executed or replaced.")
                        .dsText(.callout15).foregroundStyle(DS.confirm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Signatures happen in your Safe app — never in Casberi.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func statusLine(have: Int, required: Int) -> String {
        required > 0
            ? "\(have) of \(required) signatures collected"
            : "\(have) signature(s) collected"
    }

    private func progressRow(have: Int, required: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Signatures")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .frame(width: 110, alignment: .leading)
            Text(verbatim: required > 0 ? "\(have)/\(required)" : "\(have)")
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }
}
