import SwiftUI
import SwiftData

/// Spotify's setup. Unlike every other sign-in seat, this one does NOT open an
/// OAuth page against a registered app — the first seat did that and Spotify's
/// development-mode clampdown made it 403 for everyone. This one opens Spotify's
/// own web-player login inside a `WKWebView` we control (`SpotifyLoginWebView`),
/// harvests that session, and reads the web player's endpoints as the person.
/// No developer standing, no per-user allowlist. What lands: your recently
/// played tracks. Read-only — it can never play, queue, or change anything.
struct SpotifyScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    /// The last attempt was closed by hand — neither a result nor an error, so
    /// it's kept apart from `result` (which the status row paints green/red).
    @State private var cancelled = false
    @State private var showLogin = false

    /// The page's one presentation (`AccountPage.sheet`). The login web view
    /// rises through its own `fullScreenCover`, so the two never collide.
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Spotify", seatID: "spotify", source: "Spotify",
            state: AccountPageState.of(name: "Spotify", seatID: "spotify",
                                       connected: SpotifyAuth.connected, store: store),
            mode: .signIn,
            teardown: { SpotifyAuth.disconnect() },
            sheet: $sheet,
            act: {
                if SpotifyAuth.connected {
                    connectedBlock
                } else {
                    connectBlock
                }
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .fullScreenCover(isPresented: $showLogin) {
            SpotifyLoginWebView(onCredentials: harvested)
        }
        .onAppear {
            if SpotifyAuth.connected { Task { await sync() } }
        }
    }

    @ViewBuilder private var connectBlock: some View {
        if connecting {
            HStack(spacing: DS.Space.s2) {
                ProgressView().controlSize(.small)
                Text("Reading your Spotify…")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s1)
        } else {
            DSSlabButton(title: "Connect Spotify",
                         systemImage: "person.badge.key",
                         action: { DSHaptic.tap(); cancelled = false; result = nil; showLogin = true })
            if cancelled {
                Text("Sign-in cancelled — nothing was connected.")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Reading your Spotify…"),
                             proof: result)
        DSSlabNote(text: "On Spotify's own page — your password never enters this app.", plain: true)
    }

    @ViewBuilder private var connectedBlock: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "music.note")
                .dsGlyph(17, weight: .medium)
                .foregroundStyle(DS.tint)
            Text(SpotifyAuth.load()?.username.map { String(localized: "Signed in as \($0)") }
                 ?? String(localized: "Signed in"))
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Reading your Spotify…"),
                             proof: result)
        DSSlabNote(text: "Your recently played tracks land in your feed. Read-only — never plays or changes anything.", plain: true)
    }

    /// The web view handed back a session. Store it, confirm it works, sync.
    private func harvested(_ creds: SpotifyAuth.Credentials) {
        SpotifyAuth.save(creds)
        connecting = true
        Task {
            let ok = await SpotifyAuth.validate()
            connecting = false
            guard ok else {
                SpotifyAuth.disconnect()
                result = .failed(String(localized: "That sign-in didn't take — tap Connect to try again."))
                return
            }
            DSHaptic.success()
            await sync()
        }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await SpotifyIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            result = .failed(String(localized: "Couldn't reach Spotify — try again in a moment."))
            return
        }
        result = .landed(added)
        let proof = added > 0
            ? String(localized: "\(added) new")
            : String(localized: "Synced just now")
        if store.registerConnected(id: "spotify", name: "Spotify", proof: proof,
                                   can: ["Reads what you recently played.",
                                         "Read-only — never plays, queues, or changes anything."]) {
            DSHaptic.success()
        }
    }
}
