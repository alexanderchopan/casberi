import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The Snapchat things already in the corpus — newest first, so an import's
/// result is visible on the screen that ran it.
private let snapchatRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Snapchat" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Snapchat, connected — by import of the account's own data export.
///
/// Two acts, not one, and the split is the honest part: picking the folder
/// lands the saved chats and the memories immediately (fast, local, offline),
/// while fetching the memories' actual pictures is its own button because it
/// is hundreds of network requests against links that die 7 days after
/// Snapchat generated the export. A single "Import" button would either hide
/// that cost or refuse to admit the deadline.
struct SnapchatImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var fetching = false
    @State private var pending = 0

    @Query(snapchatRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "Snapchat")
            // The third step was "Pick the unzipped folder below", above a
            // button titled "Choose the export folder" (§220, 2026-07-31).
            ImportStepsCard("Get your export", [
                "At accounts.snapchat.com, open My Data and submit a request (pick JSON).",
                "Snapchat emails a link within a few hours. Save the zip to Files and tap it once to unzip.",
            ])
            pickSection
            if pending > 0 { picturesSection }
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: Array(recent.live))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Snapchat")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Snapchat")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
        .onAppear { pending = SnapchatImport.pendingMediaCount(context: modelContext) }
    }

    private var pickSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ImportPickRow(label: "Choose the export folder") { importing = true }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                DSSlabNote(text: "One-time import — your saved chats become searchable, your memories land on the day you took them. Only saved chats exist: Snapchat deletes everything else when it's viewed. Re-importing adds what's new and keeps a conversation up to date.")
            }
        }
        .dsSlabSection()
    }

    /// The second act. Only ever on screen when there is genuinely something
    /// waiting — an empty queue shows no button rather than a dead one.
    private var picturesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: fetching ? "Fetching pictures…" : "Fetch \(pending) pictures",
                             systemImage: "arrow.down.circle",
                             busy: fetching,
                             enabled: !fetching) {
                    DSHaptic.tap()
                    Task { await runFetch() }
                }
                DSSlabNote(text: "Your memories arrive as links, not pictures, and Snapchat's links stop working 7 days after it builds the export. Videos stay as dated entries — only photos are fetched.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Run

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = await SnapchatImport.run(folder: url, context: modelContext)
        if summary.failed {
            result = String(localized: "No Snapchat export in that folder — pick the unzipped folder (it holds chat_history.json).")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        pending = SnapchatImport.pendingMediaCount(context: modelContext)

        var parts: [String] = []
        if summary.chats > 0 { parts.append("\(summary.chats) chats in") }
        if summary.healed > 0 { parts.append("\(summary.healed) updated") }
        if summary.memories > 0 { parts.append("\(summary.memories) memories in") }
        if parts.isEmpty {
            parts.append("Nothing new — all \(summary.skipped) were already here")
        } else if summary.skipped > 0 {
            parts.append("\(summary.skipped) already here")
        }
        result = parts.joined(separator: " · ")

        let landed = summary.chats + summary.memories
        let proof = landed > 0 ? "\(landed) in" : "Synced just now"
        store.registerConnected(id: "snapchat", name: "Snapchat", proof: proof,
                                can: ["Imports the saved chats and memories you export.",
                                      "Read-only — nothing leaves \(DS.device)."])
    }

    private func runFetch() async {
        fetching = true
        defer { fetching = false }
        let outcome = await SnapchatImport.fetchMedia(context: modelContext)
        pending = SnapchatImport.pendingMediaCount(context: modelContext)

        if outcome.expired {
            result = String(localized: "Snapchat's download links have expired — request a fresh export and import it again.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = outcome.failed > 0
            ? "\(outcome.fetched) pictures in · \(outcome.failed) couldn't be fetched"
            : "\(outcome.fetched) pictures in"
    }
}
