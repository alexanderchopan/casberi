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
    @State private var result: BridgeProof?
    @State private var staleness: String?
    @State private var held = 0

    @Query(geminiRecentDescriptor) private var recent: [Thing]

    var body: some View {
        BridgeSetupPage(name: "Gemini") {
            BridgeSetupHeader(
                name: "Gemini",
                mode: .oneTimeImport,
                intro: "Gemini has no live connection — take your activity out of Google Takeout, bring it here, and every prompt becomes searchable.",
                connected: held > 0)
            // The way back to what just landed (§460). Gated on the corpus,
            // not a connection flag: an import has no live connection, so
            // "has anything arrived" is the only honest test of whether
            // there is a room worth opening.
            if !recent.isEmpty {
                RoomDoor(name: "Gemini", source: "Gemini")
                    .listRowSeparator(.hidden)
            }
            setupSection
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: recent.live)
                    .listRowSeparator(.hidden)
            }
            ImportUpkeepSection(source: "Gemini", held: held, staleness: staleness) { gone in
                reread()
                result = .says(String(localized: "\(gone) removed"))
            }
        }
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

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ImportArchiveSection(
                    source: "Gemini",
                    doorTitle: "Get your export",
                    doorURL: URL(string: "https://takeout.google.com"),
                    steps: ["Tap Deselect all, then pick My Activity and set it to Gemini Apps only.",
                            "Under Multiple formats, choose JSON for activity records, then Export.",
                            "Google emails a link — unzip it in Files."],
                    pickTitle: "Choose MyActivity.json",
                    pickIcon: "square.and.arrow.down",
                    alreadyImported: held > 0) { importing = true }
                BridgeSyncStatusRows(proof: result)
            }
        }
        .dsSlabSection()
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
