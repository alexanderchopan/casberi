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
    @State private var result: BridgeProof?

    /// The connection door, open (prd §186).

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Files", seatID: "files", source: "Files",
            state: AccountPageState.of(name: "Files", seatID: "files",
                                       connected: files.connected, store: store),
            intro: "Documents searchable by their text, images by what they say. Nothing leaves this \(DS.device).",
            mode: .onThisDevice,
            teardown: { files.disconnect() },
            sheet: $sheet,
            act: { folderBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        // ONE `.fileImporter` now, and that is the §639 dividend. It used to
        // need two — one on the base List and a second inside the Connection
        // sheet — because a system document picker presents from whichever
        // view controller is FRONTMOST, and "Change" lived inside that sheet
        // (bug report, 2026-07-29: "the button to choose a folder isn't
        // interacting"). The sheet is gone: the picker is the act slot in both
        // states, so there is only ever one presenting context.
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], onCompletion: handlePick)
        .onAppear {
            if files.connected { Task { await sync() } }
        }
    }


    @ViewBuilder private var folderBlock: some View {
        if files.connected {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "icloud")
                    .dsGlyph(17, weight: .medium)
                    .foregroundStyle(DS.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(files.folderName.isEmpty ? "Folder" : files.folderName)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    // NOT "Connected —": the state line under the name says
                    // that once, in the page's own voice (§639).
                    Text("Files sync when you visit or open the app.")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Button("Change") { picking = true }
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.tint)
                    .buttonStyle(.plain)
            }
            .padding(.vertical, DS.Space.s1)
        } else {
            DSSlabButton(title: "Choose a folder",
                         systemImage: "folder.badge.plus") { picking = true }
        }
        BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your files…"),
                             proof: result)
        // Says what LANDS before what's safe — see `SteamScreen` (audit,
        // 2026-07-31). "findable by name" left the same day: the header
        // three rows up is already the offer's "Any folder, findable".
        // Names no app: there is no Files on Mac (it's Finder), and this
        // bridge is one screen whose whole subject is a folder picker,
        // so the sentence says what you can choose rather than which
        // app would show it to you.
        DSSlabNote(text: "Any folder you can choose — often iCloud Drive. The folder is never changed.", plain: true)
    }


    /// The picker's outcome. Survived the §639 migration only as a call
    /// site — the body's `.fileImporter` still named it while the section
    /// that carried it was deleted with the old chassis.
    private func handlePick(_ outcome: Result<URL, Error>) {
        guard case .success(let url) = outcome else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if files.setFolder(url: url) {
            DSHaptic.tap()
            Task { await sync(justConnected: true) }
        } else {
            result = .failed(String(localized: "Couldn't keep access to that folder — try picking it again."))
        }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await FilesIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            if justConnected { files.disconnect() }
            result = .failed(String(localized: "Couldn't read that folder — pick it again."))
            return
        }
        result = .landed(added, noun: "files")
        let proof = added > 0
            ? String(localized: "\(added) files in")
            : String(localized: "Synced just now")
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
