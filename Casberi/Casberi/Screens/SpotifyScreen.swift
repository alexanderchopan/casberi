import SwiftUI
import SwiftData

/// Spotify's setup — PKCE, entirely on this iPhone: one tap opens Spotify's
/// own sign-in page, the callback lands back on `casberi://spotify-auth`,
/// and liked songs sync right after. No server ever holds a secret.
struct SpotifyScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var recent: [Thing] = []
    @State private var flow: Task<Void, Never>?

    private func loadRecent() {
        recent = recentBridgeThings(source: "Spotify", context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Spotify")
            connectSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                PinToHomeButton(source: "Spotify", inSection: true)
                    .listRowSeparator(.hidden)
                RecentThingsSection(header: "Liked songs", things: recent)
                    .listRowSeparator(.hidden)
            }
            if SpotifyAuth.connected { removeSection.listRowSeparator(.hidden) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Spotify")
        .dsPageBackground()
        .navigationTitle("Spotify")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadRecent()
            if SpotifyAuth.connected { Task { await sync() } }
        }
        .onDisappear { flow?.cancel() }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            if SpotifyAuth.connected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(DS.confirm)
                    Text("Connected — liked songs land in your feed.")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            } else if connecting {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Spotify…")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            } else {
                Button(action: connect) {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "person.badge.key")
                            .font(.system(size: 17, weight: .medium))
                        Text("Connect Spotify")
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
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Checking your liked songs…"),
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Liked songs").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Sign-in happens on Spotify's own page — PKCE, no password in the app, no server ever holds a secret. Read-only.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var removeSection: some View {
        Section {
            Button("Disconnect", role: .destructive) {
                SpotifyAuth.disconnect()
                store.bridges.removeAll { $0.id == "spotify" }
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
            let ok = await SpotifyAuth.signIn()
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

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await SpotifyIngest.refresh(context: modelContext)
        syncing = false
        loadRecent()
        guard let added else {
            result = String(localized: "Couldn't read your liked songs — try again in a moment.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) new") : String(localized: "Connected — liked songs land as you save them.")
        let proof = added > 0 ? "\(added) new" : "Synced just now"
        if store.registerConnected(id: "spotify", name: "Spotify", proof: proof,
                                   can: ["Reads your liked songs.",
                                         "Read-only — never plays, adds, or removes."]) {
            DSHaptic.success()
        }
    }
}
