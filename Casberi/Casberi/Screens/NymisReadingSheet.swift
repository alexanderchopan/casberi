import SwiftUI

/// **WHAT NYMIS READ (prd §1701).** The subscription sheet's anatomy: the
/// app's art centred over the account's name, then one card, "Nymis's
/// reading": their summary in their words with the findings under it as
/// label/value rows, then the coverage line and Scan again. No score, no
/// grade, no points (user, 2026-11-04).
struct NymisReadingSheet: View {
    let address: String
    let name: String
    @Environment(\.dismiss) private var dismiss

    private var reading: NymisScan.Reading? { NymisScans.shared.reading(address) }

    var body: some View {
        ScrollView {
            if let reading { content(reading) }
        }
        .subscriptionSheet()
    }

    private func content(_ reading: NymisScan.Reading) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            VStack(spacing: DS.Space.s3) {
                BridgeIcon(name: "Nymis", size: DS.Face.art, circular: false)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
                Text(verbatim: name)
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(verbatim: String(localized: "Read by Nymis \(reading.scannedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"))
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s4)

            SheetCard(name: String(localized: "Nymis's reading")) {
                Text(verbatim: reading.summary)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DS.Space.s3)
                ForEach(reading.findings, id: \.self) { finding in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                        Text(verbatim: finding.label).dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: finding.value).dsText(.body17).foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, DS.Space.s2)
                    .accessibilityElement(children: .combine)
                }
                if reading.partial {
                    Text("Nymis couldn't read all of this address's activity, so some links may be missing.")
                        .dsText(.subhead12).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s2)
                }
            }

            SheetCard(name: String(localized: "More")) {
                DSDoorRow(icon: "arrow.clockwise", title: Text("Scan again")) {
                    NymisScans.shared.scan(address)
                    dismiss()
                }
            }
        }
        .padding(DS.Space.s4)
    }
}
