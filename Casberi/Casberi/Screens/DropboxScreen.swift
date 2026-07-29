import SwiftUI
import SwiftData

/// Dropbox's setup — PKCE, entirely on this iPhone: one tap opens Dropbox's
/// own sign-in page, the callback lands back on `casberi://dropbox-auth`, and
/// the folder you name syncs right after. Read-only by grant
/// (`files.metadata.read` + `files.content.read`) — no server ever holds a
/// secret, and nothing outside the folder you named is ever read: no shared
/// links, no "shared with me". Same shape as `SpotifyScreen`, plus the one
/// extra move Files/Obsidian need too — naming what to watch.
struct DropboxScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var dropbox = DropboxStore.shared
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var flow: Task<Void, Never>?
    @State private var folderField = ""

    private var folderIdentity: String {
        dropbox.folderPath.isEmpty ? String(localized: "All of Dropbox") : dropbox.folderPath
    }

    /// The connection door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if DropboxAuth.connected {
                BridgeConnectedState(
                    bridgeID: "dropbox",
                    name: "Dropbox",
                    identity: folderIdentity,
                    connectionNote: String(localized: "Signed in on this iPhone · read-only key, never writes"),
                    capabilitiesFallback: ["Reads the folder you named.",
                                           "Read-only — never edits, shares, or deletes a file."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(name: "Dropbox")
                connectSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Dropbox")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Dropbox")
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Dropbox") {
                folderSection.listRowSeparator(.hidden)
                removeSection.listRowSeparator(.hidden)
            }
        }
        .onAppear {
            folderField = dropbox.folderPath
            if DropboxAuth.connected { Task { await sync() } }
        }
        .onDisappear { flow?.cancel() }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            if connecting {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Dropbox…")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            } else {
                // The screen's one verb, as the screen's one filled block
                // (prd §218) — it was a blue text row, which read as a link to
                // somewhere rather than the act itself.
                DSSlabButton(title: "Connect Dropbox",
                             systemImage: "person.badge.key",
                             action: connect)
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your Dropbox…"),
                                 result: result, resultIsError: resultIsError)
            DSSlabNote(text: "Sign-in happens on Dropbox's own page — PKCE, no password in the app, no server ever holds a secret. Reads only the folder you name — never shared links, never \u{201c}shared with me\u{201d}.")
        }
        .dsSlabSection()
    }

    private var folderSection: some View {
        Section {
            BridgeFieldRow(
                placeholder: "e.g. /Camera Uploads — blank for everything",
                text: $folderField,
                buttonLabel: "Save",
                action: saveFolder
            )
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your Dropbox…"),
                                 result: result, resultIsError: resultIsError)
            DSSlabNote(text: "Whatever's inside the folder you name lands in your feed — and only that folder. Changing it starts a fresh sync there.")
        }
        .dsSlabSection()
    }

    private var removeSection: some View {
        Section {
            Button("Disconnect", role: .destructive) {
                dropbox.disconnect()
                store.bridges.removeAll { $0.id == "dropbox" }
                result = String(localized: "Disconnected — your things stay.")
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

    private func connect() {
        guard flow == nil else { return }   // one flow at a time
        DSHaptic.tap()
        result = nil
        connecting = true
        flow = Task {
            defer { flow = nil }
            let ok = await DropboxAuth.signIn()
            guard !Task.isCancelled else { connecting = false; return }
            connecting = false
            if ok {
                DSHaptic.success()
                await sync()
            } else {
                result = String(localized: "Couldn't connect — tap Connect to try again.")
                resultIsError = true
            }
        }
    }

    private func saveFolder() {
        DSHaptic.tap()
        dropbox.setFolder(folderField)
        Task { await sync() }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await DropboxIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            result = String(localized: "Couldn't reach that folder — try again in a moment.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) new" : "Synced just now"
        if store.registerConnected(id: "dropbox", name: "Dropbox", proof: proof,
                                   can: ["Reads the folder you named.",
                                         "Read-only — never edits, shares, or deletes a file."]) {
            DSHaptic.success()
        }
    }
}
