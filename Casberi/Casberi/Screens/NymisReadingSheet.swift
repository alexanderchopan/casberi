import SwiftUI

/// **WHAT NYMIS READ (prd §1701, §1701a, §1701c).** The subscription sheet's
/// anatomy: the app's art centred over the account's name, then one card,
/// "Nymis's reading": Nymis's two summaries in their words (what gives the
/// address away, then its money trail), or, until Nymis has written them,
/// each finding's title over Nymis's explanation; then the incomplete line, Scan again, and See more
/// on Nymis at the foot. A reading stored before §1701c keeps the page's
/// summary and label/value facts (§1701b). No score, no grade, no points
/// (user, 2026-11-04).
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
                if reading.overview != nil || reading.financial != nil {
                    ForEach([reading.overview, reading.financial].compactMap { $0 }, id: \.self) { text in
                        Text(verbatim: text)
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, DS.Space.s3)
                    }
                    // The summaries say what the findings say: the findings
                    // stand only while there is no summary (user, 2026-11-06).
                } else if let summary = reading.summary {
                    // A reading of the scan's page, stored before §1701c.
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
                    // Only when Nymis said incomplete (§1701c), in its words
                    // when it gave a sentence.
                    Group {
                        if let reason = reading.reason {
                            Text(verbatim: reason)
                        } else {
                            Text("Nymis couldn't read all of this address's activity, so some links may be missing.")
                        }
                    }
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

    /// Nymis's findings, each title over its explanation, while there is no
    /// summary. With none at all, the sheet says so.
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
