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
    @State private var result: String?
    @State private var resultIsError = false

    /// The connection door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if obsidian.connected {
                // Connected (prd §186): the VAULT is the identity — this
                // screen was already closest to right, naming the folder it
                // reads; now the picker demotes behind the door with it.
                BridgeConnectedState(
                    bridgeID: "obsidian",
                    name: "Obsidian",
                    identity: obsidian.vaultName.isEmpty
                        ? String(localized: "Vault") : obsidian.vaultName,
                    // How it connected, and only that (audit, 2026-07-31): the
                    // note ended "· read-only, never modified" two lines above
                    // the checklist's "Read-only — never edits a note."
                    connectionNote: String(localized: "A folder on \(DS.device)"),
                    capabilitiesFallback: ["Reads the vault you picked.",
                                           "Read-only — never edits a note."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(name: "Obsidian")
                vaultSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Obsidian")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Obsidian")
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Obsidian") {
                vaultSection.listRowSeparator(.hidden)
                removeSection.listRowSeparator(.hidden)
            }
            // A SECOND `.fileImporter`, not a stray duplicate (same bug as
            // FilesScreen, 2026-07-29). "Change" lives inside this sheet's
            // own content, and a system document picker presents from
            // whichever view controller is FRONTMOST — with the sheet up,
            // that's this one, not the base List underneath it. The importer
            // attached down there (below) still owns the FIRST connect,
            // before any sheet exists to cover it; this one owns every
            // reconnect afterward. Same binding, same handler — only the
            // presenting context differs.
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder],
                          onCompletion: handlePick)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], onCompletion: handlePick)
        .onAppear {
            if obsidian.connected { Task { await sync() } }
        }
    }

    private func handlePick(_ outcome: Result<URL, Error>) {
        guard case .success(let url) = outcome else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if obsidian.setVault(url: url) {
            DSHaptic.tap()
            Task { await sync(justConnected: true) }
        } else {
            result = String(localized: "Couldn't keep access to that folder — try picking it again.")
            resultIsError = true
        }
    }

    private var vaultSection: some View {
        Section {
            if obsidian.connected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "folder")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DS.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(obsidian.vaultName.isEmpty ? "Vault" : obsidian.vaultName)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Text("Connected — notes sync when you visit or open the app.")
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
                // The screen's one verb, as the screen's one filled block
                // (prd §218) — it was a blue text row, which read as a link to
                // somewhere rather than the act itself.
                DSSlabButton(title: "Choose your vault folder",
                             systemImage: "folder.badge.plus") { picking = true }
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your notes…"),
                                 result: result, resultIsError: resultIsError)
            // Says what LANDS before what's safe — see `SteamScreen` (audit,
            // 2026-07-31). "beside everything else" left the same day: the
            // header three rows up is already "Your vault, beside your things".
            DSSlabNote(text: "Every note in the vault lands in your feed. A vault is a folder of Markdown — find it in Files (often iCloud Drive → Obsidian). Read-only: the vault is never changed.")
        }
        .dsSlabSection()
    }

    private var removeSection: some View {
        Section {
            Button("Disconnect vault", role: .destructive) {
                obsidian.disconnect()
                store.bridges.removeAll { $0.id == "obsidian" }
                result = String(localized: "Vault disconnected — your things stay.")
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
        let added = await ObsidianIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            if justConnected { obsidian.disconnect() }
            result = String(localized: "Couldn't read that folder — pick your vault again.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) notes in") : String(localized: "Up to date")
        let proof = added > 0
            ? String(localized: "\(added) notes in")
            : String(localized: "Synced just now")
        if store.registerConnected(id: "obsidian", name: "Obsidian", proof: proof,
                                   can: ["Reads the vault you picked.",
                                         "Read-only — never edits a note."]) {
            DSHaptic.success()
        }
    }
}
