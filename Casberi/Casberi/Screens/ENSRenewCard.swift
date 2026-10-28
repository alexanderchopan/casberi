import SwiftUI

/// The renew card on a followed name's sheet (2026-08-31, prd §540) — the
/// §112 preparing surface, drawn. `ApprovalPrepareCard`'s shape with one
/// difference that changes everything: **this one's transaction moves money.**
///
/// Everything here is a read or a hand-off. The price, the balance, the
/// allowance and the fee are read live; the two doors go to ENS's own app
/// (where the renewal actually happens) and to the pasteboard (the prepared
/// approval and renewal, for any wallet). Since ENSv2 the money is a
/// stablecoin (prd §1585).
/// No control on this card can spend anything, and the footer says so in the
/// same words the rest of the app uses.
///
/// Renders only once a quote has answered — no dead section, no spinner
/// theatre (`ApprovalPrepareCard`'s rule).
struct ENSRenewCard: View {
    let thing: Thing
    /// The term the person picked, and the quote for it. Held by the sheet so
    /// re-pricing a new term doesn't tear the card down and rebuild it.
    @Binding var term: ENSRenew.Term
    let quote: ENSRenewPrepare.Quote
    /// Whether a watched wallet holds this name — decides one sentence.
    let isYours: Bool
    /// Re-price after the term changes. The card never fetches itself.
    let onPickTerm: (ENSRenew.Term) -> Void

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(verbatim: standingLine)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            termPicker

            priceTable

            // THE ONE SENTENCE THIS CARD OWES THAT NO OTHER PREPARE SURFACE
            // DOES. Renewing is permissionless — measured, the controller has
            // no owner check — so this card really can renew a stranger's
            // name, and paying does not transfer it. Nobody should learn that
            // after signing.
            if let note = ENSRenew.ownershipNote(isYours: isYours) {
                Text(note)
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let url = URL(string: quote.ensURL) {
                DSDoorRow(icon: "arrow.up.right", label: "Renew on ENS") { openURL(url) }
            }
            if let json = quote.transactionJSON {
                DSDoorRow(icon: copied ? "checkmark" : "doc.on.doc",
                          label: copied ? "Copied"
                              : quote.needsApproval ? "Copy approval and renewal" : "Copy renewal transaction") {
                    copy(json)
                }
            }
        }
        // No well (prd §782): the block stands in the sheet's column.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Parts

    /// Why the card is here at all: the deadline, in the tense of the rung the
    /// name is actually on. Grace is the one worth spelling out — the name has
    /// already lapsed, and most people believe that means it is gone.
    private var standingLine: String {
        guard let reading = ENSState.reading(quote.name), let expiry = reading.expiry
        else { return quote.name }
        switch ENSName.stage(expiry: expiry, migrated: reading.isMigrated) {
        case .grace:
            guard let end = ENSName.graceEnd(expiry: expiry, migrated: reading.isMigrated) else { return quote.name }
            return String(localized: "Expired \(ENSName.dateWord(expiry)) — it can still be renewed until \(ENSName.dateWord(end)).")
        default:
            return String(localized: "Expires \(ENSName.dateWord(expiry)).")
        }
    }

    private var termPicker: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(ENSRenew.Term.allCases) { option in
                Button {
                    guard option != term else { return }
                    DSHaptic.tap()
                    term = option
                    onPickTerm(option)
                } label: {
                    Text(option.label)
                        .dsText(.subhead12)
                        .foregroundStyle(option == term ? DS.textPrimary : DS.textSecondary)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.vertical, DS.Space.s2)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .fill(option == term ? DS.fillStrong : DS.fillFaint))
                }
                .buttonStyle(PressSpring())
            }
        }
    }

    /// The price, exact: ENSv2 prices in dollars at a fixed ratio per token,
    /// so what is read here is what `renew` takes, with no "~" (§540's ETH
    /// price drifted; this one cannot). The fee is still an estimate.
    private var priceTable: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSpecTable {
                DSSpecRow(label: Text("Renewal"),
                          value: Text(verbatim: ENSRenew.tokenLine(quote.amount, quote.token)))
                if let fee = quote.feeLine {
                    DSSpecRow(label: Text("Network fee"), value: Text(verbatim: fee))
                }
            }
            DSFootnote(footnote)
        }
    }

    /// The one sentence under the price, and only the one that matters: a
    /// shortfall first, because that renewal would revert after the approval
    /// was paid for; then the approval, because it is a second signature
    /// somebody did not expect; else what it is paid in.
    private var footnote: Text {
        let symbol = quote.token.symbol
        if quote.covered == false {
            return Text("Your wallet holds less than this in USDC or DAI, so the renewal would fail.")
        }
        if quote.needsApproval {
            return Text("Paid in \(symbol). Your wallet first approves exactly this amount for ENS, then renews.")
        }
        return Text("Paid in \(symbol).")
    }

    // `doorRow` was HERE and is `DSDoorRow` (prd §560, 2026-09-01) — the third
    // of three private copies, and the one that had drifted: it painted the
    // whole row `DS.tint` and dropped the icon column, so the same door read
    // as a link here and as a row on the two sheets beside it.

    /// Copy + the brief acknowledgment, reset included — a button stuck on
    /// "Copied" reads as state it no longer has (`ApprovalPrepareCard`'s
    /// shape).
    private func copy(_ json: String) {
        DSPasteboard.copySensitive(json)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(DS.Motion.standard) { copied = false }
        }
    }
}

/// What stands in the card's place when there is no quote (prd §1573,
/// §1585): while it is read, when neither contract says the name is
/// renewable, or while `ENSRenew.prepares` is off. ENS's own app, where the
/// renewal happens. No deadline line — the sheet's title already says it
/// (measured on screen).
struct ENSRenewDoor: View {
    let thing: Thing
    let name: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        if let url = URL(string: "https://app.ens.domains/\(name)") {
            DSDoorRow(icon: "arrow.up.right", label: "Renew on ENS") { openURL(url) }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
