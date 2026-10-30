import SwiftUI

/// **LICENSES, ONE ROW PER LIBRARY (user, 2026-10-30, of the canvas's A: "ya
/// a").** `Resources/Licenses.md` stays the one text the app ships, split at
/// its `# ` lines (prd §1508): the lines before the first name are Casberi's
/// own, each named section is a library, and the Apache License's own text is
/// a section the libraries under it share, never a row.
enum Licenses {
    struct Section {
        let name: String?
        let text: AttributedString
    }

    /// The shared license text Coinbase's SDK and Yttrium point at ("below").
    static let apacheName = "Apache License, Version 2.0"

    /// Each library's second line: its license, then who holds it. A section
    /// with no line here draws its name alone (`licenses-audit.py` fails one).
    static let lines: [String: String] = [
        "Coinbase Wallet Mobile SDK": "Apache 2.0 · Coinbase",
        "ERC-7730 clear-signing registry": "Public domain · Ethereum Foundation",
        "Privacy Pools engine": "MIT and GPL 3 · 0xbow, iden3, wevm",
        "QRCode": "MIT · Darren Ford",
        "Reown Swift SDK": "WalletConnect Community License · Reown",
        "swift-qrcode-generator": "MIT · Project Nayuki, fwcd",
        "SwiftImageReadWrite": "MIT · Darren Ford",
        "Yttrium": "Apache 2.0 · Reown",
    ]

    /// The libraries under Apache 2.0, whose page carries its text after
    /// their own notice.
    static let underApache: Set<String> = ["Coinbase Wallet Mobile SDK", "Yttrium"]

    static let source = URL(string: "https://github.com/alexanderchopan/casberi")!
    /// The GPL as the repository holds it, the README's section 7
    /// permission for Reown's SDK beside it.
    static let gpl = URL(string: "https://github.com/alexanderchopan/casberi/blob/main/LICENSE")!

    /// The words verbatim (inline markdown only, so Reown's bold stays bold
    /// and nothing is reflowed). Read on appear, never in a body (§628).
    static func sections() -> [Section] {
        guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return ("\n" + raw).components(separatedBy: "\n# ").compactMap { chunk in
            let lines = chunk.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let lead = chunk.hasPrefix("\n")
            let name = lead ? nil : lines.first.map { String($0) }
            let body = (lead ? chunk : lines.count > 1 ? String(lines[1]) : "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            let text = (try? AttributedString(markdown: body, options: options)) ?? AttributedString(body)
            return Section(name: name, text: text)
        }
    }

    /// The rows: every named section but the shared Apache text, A–Z.
    static func libraries(_ sections: [Section]) -> [String] {
        sections.compactMap(\.name).filter { $0 != apacheName }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// One library's license, pushed from Licenses ("Licenses · QRCode"): its
/// notice verbatim, the Apache text after it where it points there, and Copy.
struct LicensePage: View {
    let name: String
    @Environment(HomeRoute.self) private var route
    @State private var texts: [AttributedString] = []

    var body: some View {
        DSTray(title: name, height: 700) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .dsText(.reading17)
                        .foregroundStyle(DS.textSecondary)
                        .textSelection(.enabled)
                }
                if !texts.isEmpty {
                    DSCopyRow(value: texts.map { String($0.characters) }.joined(separator: "\n\n"),
                              label: "Copy the license", sensitive: false)
                }
            }
            .padding(.bottom, DS.Space.s6)
        }
        .environment(\.dsInPane, true)
        .environment(\.dsTitleBack, DSTitleBack(word: String(localized: "Licenses"), action: { route.goBack() }))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            let sections = Licenses.sections()
            var out = sections.filter { $0.name == name }.map(\.text)
            if Licenses.underApache.contains(name) {
                out += sections.filter { $0.name == Licenses.apacheName }.map(\.text)
            }
            texts = out
        }
    }
}
