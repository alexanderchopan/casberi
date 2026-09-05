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
    @State private var result: BridgeProof?
    @State private var flow: Task<Void, Never>?
    @State private var folderField = ""
    /// The last attempt was closed by hand. Kept apart from `result` because
    /// the status row speaks two voices — red for an error, green for a
    /// result — and a sign-in you dismissed is neither.
    @State private var cancelled = false

    private var folderIdentity: String {
        dropbox.folderPath.isEmpty ? String(localized: "All of Dropbox") : dropbox.folderPath
    }

    /// The connection door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        BridgeSetupPage(name: "Dropbox") {
            if DropboxAuth.connected {
                BridgeConnectedState(
                    bridgeID: "dropbox",
                    name: "Dropbox",
                    identity: folderIdentity,
                    // How it connected, and only that (audit, 2026-07-31): the
                    // note ended "· read-only key, never writes" two lines above
                    // the checklist that makes the same promise in full.
                    connectionNote: String(localized: "Signed in on \(DS.device)"),
                    capabilitiesFallback: ["Reads the folder you named.",
                                           "Read-only — never edits, shares, or deletes a file."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // The way back to your things (§460).
                RoomDoor(name: "Dropbox", source: "Dropbox")
                    .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(
                    name: "Dropbox",
                    mode: .signIn,
                    intro: "Sign in on Dropbox's own page and one folder you name keeps arriving — only that folder, never a shared link and never anything shared with you.")
                connectSection.listRowSeparator(.hidden)
            }
        }
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
                if cancelled {
                    Text("Sign-in cancelled — nothing was connected.")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your Dropbox…"),
                                 proof: result)
            DSSlabNote(text: "On Dropbox's own page — your password never enters this app.")
        }
        .dsSlabSection()
    }

    private var folderSection: some View {
        Section {
            // One slab holding the path and its verb (§190/§218) — this was
            // the last field-plus-side-pill on the screen, sitting in a stack
            // where everything else had already moved. `alwaysEnabled` because
            // an empty path is a real choice here, not a missing one: it means
            // all of Dropbox, which the placeholder promises and the old side
            // pill went dead on.
            DSSlabField(placeholder: String(localized: "e.g. /Camera Uploads — blank for everything"),
                        text: $folderField,
                        actionLabel: String(localized: "Save"),
                        alwaysEnabled: true,
                        action: saveFolder)
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your Dropbox…"),
                                 proof: result)
            DSSlabNote(text: "Changing the folder starts a fresh sync there.")
        }
        .dsSlabSection()
    }

    private var removeSection: some View {
        BridgeDisconnectSection(bridgeID: "dropbox", name: "Dropbox") {
            dropbox.disconnect()
        }
    }

    private func connect() {
        guard flow == nil else { return }   // one flow at a time
        DSHaptic.tap()
        result = nil
        cancelled = false
        connecting = true
        flow = Task {
            defer { flow = nil }
            let outcome = await DropboxAuth.signIn()
            guard !Task.isCancelled else { connecting = false; return }
            connecting = false
            switch outcome {
            case .ok:
                DSHaptic.success()
                await sync()
            // One sentence per outcome the flow can actually tell apart (audit
            // 2026-07-31). "Couldn't connect" said the same thing for a sheet
            // you closed, a phone with no signal, and an exchange Dropbox
            // turned down — and the next move differs for each.
            case .cancelled:
                cancelled = true
            case .declined:
                fail(String(localized: "You didn't approve it on Dropbox — nothing was connected."))
            case .cantOpen:
                fail(String(localized: "Couldn't open Dropbox's sign-in page — try again."))
            case .unreachable:
                fail(String(localized: "Couldn't reach Dropbox — check your connection."))
            case .refused:
                fail(String(localized: "Dropbox wouldn't finish the sign-in — tap Connect to start again."))
            }
        }
    }

    private func fail(_ message: String) {
        result = .failed(message)
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
            result = .failed(String(localized: "Couldn't reach that folder — try again in a moment."))
            return
        }
        result = .landed(added)
        let proof = added > 0
            ? String(localized: "\(added) new")
            : String(localized: "Synced just now")
        if store.registerConnected(id: "dropbox", name: "Dropbox", proof: proof,
                                   can: ["Reads the folder you named.",
                                         "Read-only — never edits, shares, or deletes a file."]) {
            DSHaptic.success()
        }
    }
}
