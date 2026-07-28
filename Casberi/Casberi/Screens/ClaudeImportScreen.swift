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
    @State private var result: String?
    @State private var resultIsError = false

    @Query(claudeRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            setupSection
            if !recent.isEmpty {
                recentSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Claude")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). The export happens on Anthropic's side; the pick is the one
    /// thing this screen actually does, so it wears the filled slab.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                BridgeStepLines(steps: ["In Claude, open Settings → Privacy → Export data.",
                                     "Anthropic emails a download link. Save the zip to Files and tap it once to unzip.",
                                     "Pick conversations.json below."], startingAt: 1)
                DSSlabButton(title: "Choose conversations.json", systemImage: "square.and.arrow.down") {
                    DSHaptic.tap()
                    importing = true
                }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                DSSlabNote(text: "One-time import — your chats become findable things. Re-importing later adds only what's new.")
            }
        }
        .dsSlabSection()
    }

    private var recentSection: some View {
        Section {
            ForEach(recent) { thing in
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if !thing.content.isEmpty {
                        Text(thing.content)
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                .dsListCardRow()
            }
        } header: {
            Text("Imported").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
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
        let summary = ClaudeImport.run(data: data, context: modelContext)
        if summary.failed {
            result = String(localized: "That file isn't a Claude export. Pick conversations.json.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = summary.imported > 0
            ? "\(summary.imported) chats in\(summary.skipped > 0 ? " · \(summary.skipped) already here" : "")"
            : "Nothing new — all \(summary.skipped) chats were already here."
        let proof = summary.imported > 0 ? "\(summary.imported) chats in" : "Synced just now"
        store.registerConnected(id: "claude", name: "Claude", proof: proof,
                                can: ["Imports the chats you export."])
    }
}
