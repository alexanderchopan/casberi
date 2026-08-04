import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The imported ChatGPT chats already in the corpus — newest first. A @Query
/// so the list updates live after an import and the fetch runs once per store
/// change, not twice per body pass.
private let chatgptRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "ChatGPT" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// ChatGPT, connected — by import. The steps to get the export are stated
/// plainly (they happen on OpenAI's side; there is no live read to offer),
/// then one button picks `conversations.json` and the history lands as chat
/// things. Safe to re-run: conversations dedupe on their id.
struct ChatGPTImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false

    @Query(chatgptRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "ChatGPT")
            setupSection
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: recent.live)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "ChatGPT")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("ChatGPT")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). The export happens on OpenAI's side; the pick is the one
    /// thing this screen actually does, so it wears the filled slab.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // The last step said "Pick conversations.json below" directly
                // above a button titled "Choose conversations.json", and the
                // note said "your chats become findable things" directly below
                // the header's own "Import your chats, keep them findable"
                // (§220's finding, twice; 2026-07-31).
                BridgeStepLines(steps: ["In ChatGPT, open Settings → Data controls → Export data.",
                                     "OpenAI emails a download link. Save the zip to Files and tap it once to unzip."], startingAt: 1)
                DSSlabButton(title: "Choose conversations.json", systemImage: "square.and.arrow.down") {
                    DSHaptic.tap()
                    importing = true
                }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                DSSlabNote(text: "One-time import — re-importing later adds only what's new.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Run

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url) else {
            result = String(localized: "Couldn't read that file. Pick conversations.json from the unzipped export.")
            resultIsError = true
            return
        }
        let summary = ChatGPTImport.run(data: data, context: modelContext)
        if summary.failed {
            result = String(localized: "That file isn't a ChatGPT export. Pick conversations.json.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = summary.imported > 0
            ? (summary.skipped > 0
               ? String(localized: "\(summary.imported) chats in · \(summary.skipped) already here")
               : String(localized: "\(summary.imported) chats in"))
            : String(localized: "Nothing new — all \(summary.skipped) chats were already here.")
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) chats in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "gpt", name: "ChatGPT", proof: proof,
                                can: ["Imports the chats you export."])
    }
}
