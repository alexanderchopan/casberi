import SwiftUI
import SwiftData

/// Files' setup — one move: point at any folder. The picker grants it, files
/// land, and the screen shows which folder is connected and what arrived.
/// Local files only; nothing leaves the iPhone. Same shape as
/// `ObsidianScreen`, generalized past a vault of Markdown to any folder.
struct FilesScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var files = FilesStore.shared
    @State private var picking = false
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false

    /// The connection door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if files.connected {
                BridgeConnectedState(
                    bridgeID: "files",
                    name: "Files",
                    identity: files.folderName.isEmpty
                        ? String(localized: "Folder") : files.folderName,
                    connectionNote: String(localized: "A folder on this iPhone · read-only, never modified"),
                    capabilitiesFallback: ["Reads the folder you picked.",
                                           "Read-only — never edits a file."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(name: "Files")
                folderSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Files")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Files")
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Files") {
                folderSection.listRowSeparator(.hidden)
                removeSection.listRowSeparator(.hidden)
            }
            // A SECOND `.fileImporter`, not a stray duplicate (bug report,
            // 2026-07-29: "the button to choose a folder isn't interacting").
            // "Change" lives inside this sheet's own content, and a system
            // document picker presents from whichever view controller is
            // FRONTMOST — with the sheet up, that's this one, not the base
            // List underneath it. The importer attached down there (below)
            // still owns the FIRST connect, before any sheet exists to cover
            // it; this one owns every reconnect afterward. Same binding, same
            // handler — only the presenting context differs.
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder],
                          onCompletion: handlePick)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], onCompletion: handlePick)
        .onAppear {
            if files.connected { Task { await sync() } }
        }
    }

    private func handlePick(_ outcome: Result<URL, Error>) {
        guard case .success(let url) = outcome else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if files.setFolder(url: url) {
            DSHaptic.tap()
            Task { await sync(justConnected: true) }
        } else {
            result = String(localized: "Couldn't keep access to that folder — try picking it again.")
            resultIsError = true
        }
    }

    private var folderSection: some View {
        Section {
            if files.connected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "icloud")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DS.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(files.folderName.isEmpty ? "Folder" : files.folderName)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Text("Connected — files sync when you visit or open the app.")
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    }
                    Spacer()
                    Button("Change") { picking = true }
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.tint)
                        .buttonStyle(.plain)
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            } else {
                DSSlabButton(title: "Choose a folder",
                             systemImage: "folder.badge.plus") { picking = true }
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your files…"),
                                 result: result, resultIsError: resultIsError)
            DSSlabNote(text: "Any folder Files can reach — often iCloud Drive. Read-only: the folder is never changed.")
        }
        .dsSlabSection()
    }

    private var removeSection: some View {
        Section {
            Button("Disconnect folder", role: .destructive) {
                files.disconnect()
                store.bridges.removeAll { $0.id == "files" }
                result = String(localized: "Folder disconnected — your things stay.")
                resultIsError = false
                DSHaptic.tap()
            }
            .dsText(.callout15)
            .dsListCardRow()
        } footer: {
            Text("Disconnecting stops syncing. What already landed stays yours.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await FilesIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            if justConnected { files.disconnect() }
            result = String(localized: "Couldn't read that folder — pick it again.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) files in") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) files in" : "Synced just now"
        if store.registerConnected(id: "files", name: "Files", proof: proof,
                                   can: ["Reads the folder you picked.",
                                         "Read-only — never edits a file."]) {
            DSHaptic.success()
        }
        // Thumbnails/OCR right away, not on the next app foreground — the
        // ONLY other caller (BridgeRefresh) runs off a scenePhase change, so
        // without this a person who connects and stays in the app sees every
        // image sit there as a bare filename indefinitely (bug report,
        // 2026-07-29: "it's still not showing images" — the enrichment code
        // was correct, nothing ever called it in this flow). Unconditional,
        // not gated on `added` — reopening this screen re-syncs an
        // already-connected folder (`onAppear` below) and should still catch
        // up a backlog `heal` didn't finish last time, even when nothing NEW
        // landed. `heal` itself no-ops fast when there's nothing to do.
        // Fire-and-forget: this screen's own `result` line already reported
        // the sync; heal updates rows in place as it lands.
        Task { _ = await FilesIngest.heal(context: modelContext) }
    }
}
