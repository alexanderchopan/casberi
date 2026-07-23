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
    @State private var recent: [Thing] = []

    private func loadRecent() {
        recent = recentBridgeThings(source: "Obsidian", context: modelContext)
    }

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
                    connectionNote: String(localized: "A folder on this iPhone · read-only, never modified"),
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
        .navigationTitle("Obsidian")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Obsidian") {
                vaultSection.listRowSeparator(.hidden)
                removeSection.listRowSeparator(.hidden)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { outcome in
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
        .onAppear {
            loadRecent()
            if obsidian.connected { Task { await sync() } }
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
                Button {
                    picking = true
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                        Text("Choose your vault folder")
                            .dsText(.body17).fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundStyle(DS.tint)
                    .padding(.vertical, DS.Space.s1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsListCardRow()
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your notes…"),
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Vault").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("A vault is a folder of Markdown — find it in Files (often iCloud Drive → Obsidian). Read-only: the vault is never changed.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
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
        loadRecent()
        guard let added else {
            if justConnected { obsidian.disconnect() }
            result = String(localized: "Couldn't read that folder — pick your vault again.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) notes in") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) notes in" : "Synced just now"
        if store.registerConnected(id: "obsidian", name: "Obsidian", proof: proof,
                                   can: ["Reads the vault you picked.",
                                         "Read-only — never edits a note."]) {
            DSHaptic.success()
        }
    }
}
