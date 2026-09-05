import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The imported Claude chats already in the corpus — newest first. A @Query
/// so the list updates live after an import and the fetch runs once per store
/// change, not twice per body pass.
private let claudeRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Claude" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Claude, connected — by import (PRD S9's "import" grade). The steps to get
/// the export are stated plainly (they happen on Anthropic's side; there is no
/// live read to offer), then one button picks `conversations.json` and the
/// history lands as chat things. Safe to re-run: conversations dedupe on their
/// uuid.
struct ClaudeImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: BridgeProof?
    @State private var staleness: String?
    @State private var held = 0

    @Query(claudeRecentDescriptor) private var recent: [Thing]

    var body: some View {
        BridgeSetupPage(name: "Claude") {
            BridgeSetupHeader(
                name: "Claude",
                mode: .oneTimeImport,
                intro: "Claude has no live connection — export your conversations, bring them here, and every chat becomes searchable.",
                connected: held > 0)
            // The way back to what just landed (§460). Gated on the corpus,
            // not a connection flag: an import has no live connection, so
            // "has anything arrived" is the only honest test of whether
            // there is a room worth opening.
            if !recent.isEmpty {
                RoomDoor(name: "Claude", source: "Claude")
                    .listRowSeparator(.hidden)
            }
            setupSection
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: recent.live)
                    .listRowSeparator(.hidden)
            }
            ImportUpkeepSection(source: "Claude", held: held, staleness: staleness) { gone in
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
    /// 2026-07-25). The export happens on Anthropic's side; the pick is the one
    /// thing this screen actually does, so it wears the filled slab.
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "Claude", context: modelContext)
        held = ImportRemoval.count(source: "Claude", context: modelContext)
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ImportArchiveSection(
                    source: "Claude",
                    steps: ["In Claude, open Settings → Privacy → Export data.",
                            "Anthropic emails a link — unzip it in Files."],
                    pickTitle: "Choose conversations.json",
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
            result = .failed(String(localized: "Couldn't read that file. Pick conversations.json from the unzipped export."))
            return
        }
        let summary = ClaudeImport.run(data: data, context: modelContext)
        if summary.failed {
            result = .failed(String(localized: "That file isn't a Claude export. Pick conversations.json."))
            return
        }
        DSHaptic.success()
        reread()
        result = .says(summary.imported > 0
            ? (summary.skipped > 0
               ? String(localized: "\(summary.imported) chats in · \(summary.skipped) already here")
               : String(localized: "\(summary.imported) chats in"))
            : String(localized: "Nothing new — all \(summary.skipped) chats were already here."))
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) chats in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "claude", name: "Claude", proof: proof,
                                can: ["Imports the chats you export."])
    }
}
