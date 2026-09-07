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

    /// Which folder this reads, in words — an empty path is a real choice
    /// here and means all of Dropbox, so it is named rather than left blank.
    private var folderIdentity: String {
        dropbox.folderPath.isEmpty ? String(localized: "All of Dropbox") : dropbox.folderPath
    }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Dropbox", seatID: "dropbox", source: "Dropbox",
            state: AccountPageState.of(name: "Dropbox", seatID: "dropbox",
                                       connected: DropboxAuth.connected, store: store),
            intro: "One folder you name — only that folder, never a shared link or anything shared with you.",
            mode: .signIn,
            teardown: { dropbox.disconnect() },
            sheet: $sheet,
            act: {
                // Connected, the act is the FOLDER: which one this reads, and
                // changing it. Not connected, it is the sign-in.
                if DropboxAuth.connected {
                    folderBlock
                } else {
                    connectBlock
                }
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            folderField = dropbox.folderPath
            if DropboxAuth.connected { Task { await sync() } }
        }
        .onDisappear { flow?.cancel() }
    }


    @ViewBuilder private var connectBlock: some View {
        if connecting {
            HStack(spacing: DS.Space.s2) {
                ProgressView().controlSize(.small)
                Text("Waiting for Dropbox…")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s1)
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
        DSSlabNote(text: "On Dropbox's own page — your password never enters this app.", plain: true)
    }

    @ViewBuilder private var folderBlock: some View {
        // WHICH FOLDER, in the page's own left-aligned voice — the identity
        // `BridgeConnectedState` used to carry in a card.
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "folder")
                .dsGlyph(17, weight: .medium)
                .foregroundStyle(DS.tint)
            Text(folderIdentity)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
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
        DSSlabNote(text: "Changing the folder starts a fresh sync there.", plain: true)
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
