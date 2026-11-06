import SwiftUI

/// **WHAT NYMIS READ (prd §1701, §1701a, §1701c, §1701d).** The subscription sheet's
/// anatomy: the app's art centred over the account's name, then one card,
/// "Nymis's reading": Nymis's two summaries in their words (what gives the
/// address away, then its money trail), or, until Nymis has written them,
/// each finding's title over Nymis's explanation; Nymis's facts as
/// label/value rows with the selected related addresses under theirs
/// (§1701d); then the incomplete line, Scan again, and See more
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
                // Nymis's summaries in their words, or a stored page
                // reading's (§1701b).
                let paragraphs = reading.overview == nil && reading.financial == nil
                    ? [reading.summary].compactMap { $0 }
                    : [reading.overview, reading.financial].compactMap { $0 }
                ForEach(paragraphs, id: \.self) { text in
                    Text(verbatim: text)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, DS.Space.s3)
                }
                // Nymis's facts (§1701d), the selected related addresses under
                // their row.
                ForEach(reading.facts ?? [], id: \.self) { fact in
                    factRow(fact.label, fact.value)
                    if fact.kind == "related" {
                        ForEach(reading.related ?? [], id: \.self) { peer in
                            factRow(peer.name ?? AddressTail.short(peer.address), Self.relatedLine(peer), inset: true)
                        }
                    }
                }
                // The summaries say what the findings say: the findings
                // stand only while there is no summary (user, 2026-11-06).
                if paragraphs.isEmpty {
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

    /// One label/value row; a related address stands in from the label.
    private func factRow(_ label: String, _ value: String?, inset: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text(verbatim: label).dsText(.body17).foregroundStyle(DS.textPrimary)
                .padding(.leading, inset ? DS.Space.s4 : 0)
            Spacer(minLength: DS.Space.s2)
            if let value {
                Text(verbatim: value).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, DS.Space.s2)
        .accessibilityElement(children: .combine)
    }

    /// "Polymarket · 21 transfers": where the address has a profile, and the
    /// transfers Nymis saw between the two. Nil when Nymis gave neither.
    static func relatedLine(_ peer: NymisScan.Related) -> String? {
        let transfers = peer.transfers.map {
            $0 == 1 ? String(localized: "1 transfer") : String(localized: "\($0) transfers")
        }
        let parts = [peer.platform, transfers].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Nymis's findings, each title over its explanation, while there is no
    /// summary. With no finding and no fact, the sheet says so.
    @ViewBuilder
    private func findings(_ reading: NymisScan.Reading) -> some View {
        if reading.findings.isEmpty, (reading.facts ?? []).isEmpty {
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
