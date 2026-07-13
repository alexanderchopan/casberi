import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Kindle, connected — by import of the device's own `My Clippings.txt`. Steps
/// happen on the Kindle and in Files; one button picks the file and highlights
/// land as notes. The ChatGPT/Day One import pattern.
struct KindleImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false

    @Query(kindleRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "Kindle")
            ImportStepsCard("Get your highlights", [
                "Plug your Kindle into this iPhone (or a Mac) with its cable.",
                "Open the Kindle's drive → documents → My Clippings.txt, and copy it to Files.",
                "Pick that file below.",
            ])
            Section {
                ImportPickRow(label: "Choose My Clippings.txt") { importing = true }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
            } footer: {
                Text("One-time import — highlights become findable notes, grouped by book. Re-importing adds only what's new. (Amazon offers no live read.)")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            .listRowSeparator(.hidden)
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: Array(recent))
                    .listRowSeparator(.hidden)
                PinToHomeButton(source: "Kindle", inSection: true)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Kindle")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.plainText, .text]) { outcome in
            guard case .success(let url) = outcome else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                result = String(localized: "Couldn't read that file. Pick My Clippings.txt from your Kindle.")
                resultIsError = true
                return
            }
            let summary = KindleImport.run(data: data, context: modelContext)
            if summary.failed {
                result = String(localized: "That file isn't a Kindle export. Pick My Clippings.txt from the Kindle's documents folder.")
                resultIsError = true
                return
            }
            resultIsError = false
            DSHaptic.success()
            result = summary.imported > 0
                ? "\(summary.imported) highlights in\(summary.skipped > 0 ? " · \(summary.skipped) already here" : "")"
                : "Nothing new — all \(summary.skipped) highlights were already here."
            let proof = summary.imported > 0 ? "\(summary.imported) highlights in" : "Synced just now"
            store.registerConnected(id: "kindle", name: "Kindle", proof: proof,
                                    can: ["Imports the highlights you export.",
                                          "Read-only — nothing leaves this iPhone."])
        }
    }
}

private let kindleRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Kindle" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()
