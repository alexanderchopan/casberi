import SwiftUI
import SwiftData

/// Obsidian's setup — one move: point at the vault folder. The picker grants
/// the folder, notes land, and the screen shows which vault is connected and
/// what arrived. Local files only; nothing leaves the iPhone.
struct ObsidianScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var obsidian = ObsidianStore.shared
    @State private var picking = false
    @State private var syncing = false
    @State private var result: BridgeProof?

    /// The connection door, open (prd §186).

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Obsidian", seatID: "obsidian", source: "Obsidian",
            state: AccountPageState.of(name: "Obsidian", seatID: "obsidian",
                                       connected: obsidian.connected, store: store),
            intro: "Your notes, searchable alongside everything else. Nothing here edits or writes a note back.",
            mode: .onThisDevice,
            teardown: { obsidian.disconnect() },
            sheet: $sheet,
            act: { vaultBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        // ONE `.fileImporter` now, and that is the §639 dividend — see
        // `FilesScreen`, which carried the identical pair for the identical
        // reason. The Connection sheet is gone, so there is only ever one
        // presenting context for the picker.
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], onCompletion: handlePick)
        .onAppear {
            if obsidian.connected { Task { await sync() } }
        }
    }


    @ViewBuilder private var vaultBlock: some View {
        if obsidian.connected {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "folder")
                    .dsGlyph(17, weight: .medium)
                    .foregroundStyle(DS.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(obsidian.vaultName.isEmpty ? "Vault" : obsidian.vaultName)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    // NOT "Connected —": the state line under the name says
                    // that once, in the page's own voice (§639).
                    Text("Notes sync when you visit or open the app.")
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
            // The screen's one verb, as the screen's one filled block
            // (prd §218) — it was a blue text row, which read as a link to
            // somewhere rather than the act itself.
            DSSlabButton(title: "Choose your vault folder",
                         systemImage: "folder.badge.plus") { picking = true }
        }
        BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your notes…"),
                             proof: result)
        // Says what LANDS before what's safe — see `SteamScreen` (audit,
        // 2026-07-31). "beside everything else" left the same day: the
        // header three rows up is already "Your vault, beside your things".
        // What lands, then what's safe — `SteamScreen`'s ordering (audit,
        // 2026-07-31). The edit/delete sentence is here rather than in the
        // intro because it changes what someone would DO: it is the answer
        // to "will this go stale?", and before 2026-08-06 the honest
        // answer was yes.
        DSSlabNote(text: "A vault is a folder of Markdown — usually iCloud Drive → Obsidian.", plain: true)
    }


    /// The picker's outcome. Like Files', it survived the §639 migration
    /// only as a call site — the section that carried it went with the old
    /// chassis while the body's `.fileImporter` kept naming it.
    private func handlePick(_ outcome: Result<URL, Error>) {
        guard case .success(let url) = outcome else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if obsidian.setVault(url: url) {
            DSHaptic.tap()
            Task { await sync(justConnected: true) }
        } else {
            result = .failed(String(localized: "Couldn't keep access to that folder — try picking it again."))
        }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await ObsidianIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            if justConnected { obsidian.disconnect() }
            result = .failed(String(localized: "Couldn't read that folder — pick your vault again."))
            return
        }
        result = .landed(added, noun: "notes")
        let proof = added > 0
            ? String(localized: "\(added) notes in")
            : String(localized: "Synced just now")
        if store.registerConnected(id: "obsidian", name: "Obsidian", proof: proof,
                                   can: ["Reads the vault you picked.",
                                         "Keeps up with edits, and drops notes you delete.",
                                         "Read-only — never edits a note."]) {
            DSHaptic.success()
        }
    }
}
