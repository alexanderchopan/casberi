import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Gemini, connected — by import, the same grade as ChatGPT and Claude. The
/// steps to get the export are stated plainly (they happen on Google's side;
/// there is no live read to offer), then one button picks `MyActivity.json`
/// and the history lands as chat things. Safe to re-run: prompts dedupe on
/// their timestamp + text.
struct GeminiImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var result: BridgeProof?
    @State private var staleness: String?
    @State private var held = 0
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?


    var body: some View {
        AccountPage(
            name: "Gemini", seatID: "gemini", source: "Gemini",
            // An import has no live connection, so "is anything here" is the
            // only honest test of whether this seat is connected at all.
            state: AccountPageState.of(name: "Gemini", seatID: "gemini",
                                       connected: held > 0, store: store),
            mode: .oneTimeImport,
            teardown: {},
            sheet: $sheet,
            act: { setupBlock },
            more: {
                ImportUpkeepSection(source: "Gemini", held: held,
                                    staleness: staleness, plain: true) { gone in
                    reread()
                    result = .says(String(localized: "\(gone) removed"))
                }
            },
            keySheet: { EmptyView() }
        )
        .onAppear { reread() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). The export happens on Google's side; the pick is the one
    /// thing this screen actually does, so it wears the filled slab.
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "Gemini", context: modelContext)
        held = ImportRemoval.count(source: "Gemini", context: modelContext)
    }

    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ImportArchiveSection(
                source: "Gemini",
                doorTitle: "Get your export",
                doorURL: URL(string: "https://takeout.google.com"),
                steps: ["Deselect all → My Activity → Gemini Apps",
                        "Multiple formats → JSON → Export",
                        "Google emails a link — unzip it in Files."],
                pickTitle: "Choose MyActivity.json",
                pickIcon: "square.and.arrow.down",
                alreadyImported: held > 0) { importing = true }
            BridgeSyncStatusRows(proof: result)
        }
    }


    // MARK: - Run

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url) else {
            result = .failed(String(localized: "Couldn't read that file. Pick MyActivity.json from the unzipped export."))
            return
        }
        let summary = GeminiImport.run(data: data, context: modelContext)
        if summary.failed {
            result = .failed(String(localized: "That file isn't a Gemini export. Pick MyActivity.json from your Takeout."))
            return
        }
        DSHaptic.success()
        reread()
        result = .says(summary.imported > 0
            ? "\(summary.imported) prompts in\(summary.skipped > 0 ? " · \(summary.skipped) already here" : "")"
            : "Nothing new — all \(summary.skipped) prompts were already here.")
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) prompts in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "gemini", name: "Gemini", proof: proof,
                                can: ["Imports the activity you export."])
    }
}
