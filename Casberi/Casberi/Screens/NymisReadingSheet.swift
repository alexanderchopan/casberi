import SwiftUI

/// **WHAT NYMIS READ (prd §1701, §1701a, §1701b).** The subscription sheet's
/// anatomy: the app's art centred over the account's name, then one card,
/// "Nymis's reading": Nymis's summary in their words with the facts under it
/// as label/value rows (the scan's page, §1701b), or, when the page could
/// not be read, each finding's title over Nymis's explanation; then the
/// coverage line, Scan again, and See more on Nymis at the foot. No score,
/// no grade, no points (user, 2026-11-04).
struct NymisReadingSheet: View {
    let address: String
    let name: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

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
                if let summary = reading.summary {
                    Text(verbatim: summary)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, DS.Space.s3)
                    ForEach(reading.facts ?? [], id: \.self) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                            Text(verbatim: fact.label).dsText(.body17).foregroundStyle(DS.textPrimary)
                            Spacer(minLength: DS.Space.s2)
                            Text(verbatim: fact.value).dsText(.body17).foregroundStyle(DS.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, DS.Space.s2)
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    findings(reading)
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
                if let id = reading.scanID, let url = NymisScan.reportURL(scanID: id) {
                    DSDoorRow(icon: "safari", title: Text("See more on Nymis")) { openURL(url) }
                }
            }
        }
        .padding(DS.Space.s4)
    }

    /// The API's findings, when the scan's page could not be read.
    @ViewBuilder
    private func findings(_ reading: NymisScan.Reading) -> some View {
        if reading.findings.isEmpty {
            // Nymis: an empty list does not prove no exposure.
            Text("Nymis found nothing that gives this address away, which doesn't prove nothing does.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, DS.Space.s2)
        }
        ForEach(reading.findings, id: \.self) { finding in
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: finding.title).dsText(.body17).foregroundStyle(DS.textPrimary)
                if !finding.explanation.isEmpty {
                    Text(verbatim: finding.explanation).dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Space.s2)
            .accessibilityElement(children: .combine)
        }
    }
}
