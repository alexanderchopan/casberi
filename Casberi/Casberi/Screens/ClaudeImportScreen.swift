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
            stepsSection.listRowSeparator(.hidden)
            importSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                recentSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftTopEdge()
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { outcome in
            guard case .success(let url) = outcome else { return }
            runImport(url)
        }
    }

    // MARK: - Steps (the export happens on Anthropic's side — say so plainly)

    private var stepsSection: some View {
        Section {
            step(1, "In Claude, open Settings → Privacy → Export data.")
            step(2, "Anthropic emails a download link. Save the zip to Files and tap it once to unzip.")
            step(3, "Pick conversations.json below.")
        } header: {
            Text("Get your export").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text("\(n)")
                .dsText(.subhead13).fontWeight(.bold)
                .foregroundStyle(DS.tint)
                .frame(width: 16)
            Text(LocalizedStringKey(text))
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dsListCardRow()
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            Button {
                importing = true
            } label: {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.tint)
                        .frame(width: 28, height: 28)
                        .background(DS.tintDim,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.appIcon(28), style: .continuous))
                    Text("Choose conversations.json")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .dsListCardRow()
            BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
        } footer: {
            Text("One-time import — your chats become findable things. Re-importing later adds only what's new.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
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

    private func runImport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
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
