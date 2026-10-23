import SwiftUI

/// **THE CODE, READ ON OPEN (prd §1473).** A gift card bought from Move
/// lands as §103's receipt with nothing secret on it; this block, under the
/// receipt, reads the redemption from Bitrefill for the wallet that paid —
/// the account signs in if its session has lapsed — and offers the code as
/// a copy row, the PIN the same, the link as a door. Nothing is written to
/// the store, and a code is money, so the copy row is sensitive.
///
/// Drawn only for a purchase made here: the ref carries the x402 invoice id,
/// a UUID; the keyed seat's synced orders carry Bitrefill's own ids and
/// keep their codes out of the app on purpose (`BitrefillFetch.orderThing`).
struct BitrefillCodeRows: View {
    let thing: Thing
    @Environment(\.openURL) private var openURL
    @State private var redemption: BitrefillBuy.Redemption?
    @State private var reading = false
    @State private var note: String?

    private var invoiceID: String? {
        guard thing.source == "Bitrefill", let id = BitrefillBuy.orderID(ref: thing.sourceRef),
              UUID(uuidString: id) != nil else { return nil }
        return id
    }

    var body: some View {
        if thing.isLive, let invoiceID {
            VStack(alignment: .leading, spacing: 0) {
                if let r = redemption {
                    if let code = r.code { DSCopyRow(value: code, label: "Copy code") }
                    if let pin = r.pin { DSCopyRow(value: pin, label: "Copy PIN") }
                    if let link = r.link, let url = URL(string: link) {
                        DSDoorRow(icon: "arrow.up.right", title: Text("Redeem at \(thing.transferCounterparty ?? "the merchant")")) { openURL(url) }
                    }
                    if let text = r.instructions {
                        Text(verbatim: text)
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, DS.Space.s2)
                    }
                    if r.isEmpty, r.instructions == nil {
                        Text("Bitrefill is still delivering it")
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                    }
                } else {
                    DSDoorRow(icon: reading ? "hourglass" : "key.fill",
                              title: Text(reading ? "Reading from Bitrefill…" : "Show the code")) {
                        Task { await read(invoiceID) }
                    }
                    .disabled(reading)
                    if let note {
                        Text(verbatim: note)
                            .dsText(.body17)
                            .foregroundStyle(DS.attentionInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @MainActor
    private func read(_ invoiceID: String) async {
        guard let account = YourAccountKey.address ?? (BitrefillX402.sample ? "0x0" : nil) else {
            note = String(localized: "The account that paid is not on this iPhone")
            return
        }
        reading = true
        defer { reading = false }
        note = nil
        guard let standing = await BitrefillX402.standing(invoiceID: invoiceID, account: account) else {
            note = String(localized: "Bitrefill did not answer for this wallet")
            return
        }
        if standing.failed {
            note = String(localized: "Bitrefill could not deliver it and refunds the wallet that paid")
            return
        }
        withAnimation(DS.Motion.standard) {
            redemption = standing.redemption ?? .init(code: nil, pin: nil, link: nil, instructions: nil, expires: nil)
        }
    }
}
