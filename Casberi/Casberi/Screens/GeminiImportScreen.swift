import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The imported Gemini prompts already in the corpus — newest first. A @Query
/// so the list updates live after an import and the fetch runs once per store
/// change, not twice per body pass.
private let geminiRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Gemini" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

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
    @State private var result: String?
    @State private var resultIsError = false

    @Query(geminiRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Gemini",
                mode: .oneTimeImport,
                intro: "Gemini has no live connection — take your activity out of Google Takeout, bring it here, and every prompt becomes searchable. Re-import any time for what's new.")
            setupSection
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: recent.live)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Gemini")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Gemini")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). The export happens on Google's side; the pick is the one
    /// thing this screen actually does, so it wears the filled slab.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // Verb over address, the 2026-08-14 anatomy.
                DSSlabButton(title: "Get your export",
                             detail: "takeout.google.com",
                             systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://takeout.google.com") { openURL(url) }
                }
                // The last step said "Pick MyActivity.json below" directly above
                // a button titled "Choose MyActivity.json", and the note said
                // "your prompts become findable things" directly below the
                // header's own "Import your chats, keep them findable" (§220's
                // finding, twice; 2026-07-31). The Takeout path stays whole —
                // nothing else on screen teaches it.
                // Unnumbered — the door did step one (ruling 2026-08-14).
                BridgeStepLines(steps: ["Tap Deselect all, then pick My Activity and set it to Gemini Apps only.",
                                     "Under Multiple formats, choose JSON for activity records, then Export.",
                                     "Google emails a link — unzip it in Files."], numbered: false)
                DSSlabButton(title: "Choose MyActivity.json", systemImage: "square.and.arrow.down") {
                    DSHaptic.tap()
                    importing = true
                }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
            }
        }
        .dsSlabSection()
    }


    // MARK: - Run

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url) else {
            result = String(localized: "Couldn't read that file. Pick MyActivity.json from the unzipped export.")
            resultIsError = true
            return
        }
        let summary = GeminiImport.run(data: data, context: modelContext)
        if summary.failed {
            result = String(localized: "That file isn't a Gemini export. Pick MyActivity.json from your Takeout.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = summary.imported > 0
            ? "\(summary.imported) prompts in\(summary.skipped > 0 ? " · \(summary.skipped) already here" : "")"
            : "Nothing new — all \(summary.skipped) prompts were already here."
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) prompts in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "gemini", name: "Gemini", proof: proof,
                                can: ["Imports the activity you export."])
    }
}
