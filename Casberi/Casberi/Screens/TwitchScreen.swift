import SwiftUI
import SwiftData

/// Twitch's setup — the device-code flow made visible: one tap fetches a
/// short code, the person approves it on twitch.tv/activate (link opens with
/// the code prefilled), and the screen confirms the moment Twitch does.
/// After that, followed channels' live streams land in the feed.
struct TwitchScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var code: TwitchAuth.DeviceCode?
    @State private var waiting = false
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var recent: [Thing] = []

    private func loadRecent() {
        recent = recentBridgeThings(source: "Twitch", context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Twitch")
            connectSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                RecentThingsSection(header: "Live lately", things: recent)
                    .listRowSeparator(.hidden)
            }
            if TwitchAuth.connected { removeSection.listRowSeparator(.hidden) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Twitch")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadRecent()
            if TwitchAuth.connected { Task { await sync() } }
        }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            if TwitchAuth.connected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(DS.confirm)
                    Text("Connected — live follows land in your feed.")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                }
                .padding(.vertical, DS.Space.s1)
                .listRowBackground(DS.surfaceSheet)
            } else if let code, waiting {
                // The code, big — the person approves it on Twitch's side.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text(code.userCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.textPrimary)
                        .frame(maxWidth: .infinity)
                        .settleIn()
                    Button {
                        if let url = code.verificationURL { openURL(url) }
                    } label: {
                        Text("Approve on twitch.tv/activate")
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(BridgeGlyph.color(for: "Twitch"),
                                        in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: DS.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for your approval…")
                            .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    }
                }
                .padding(.vertical, DS.Space.s2)
                .listRowBackground(DS.surfaceSheet)
            } else {
                Button(action: connect) {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "person.badge.key")
                            .font(.system(size: 17, weight: .medium))
                        Text("Connect Twitch")
                            .dsText(.body17).fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundStyle(DS.tint)
                    .padding(.vertical, DS.Space.s1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(DS.surfaceSheet)
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: "Checking who's live…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Your follows").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Sign-in happens on Twitch's own page — a short code, no password in the app. Read-only: it can never chat, follow, or subscribe.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var removeSection: some View {
        Section {
            Button("Disconnect", role: .destructive) {
                TwitchAuth.disconnect()
                store.bridges.removeAll { $0.id == "twitch" }
                result = "Disconnected — your things stay."
                resultIsError = false
                DSHaptic.tap()
            }
            .dsText(.callout15)
            .listRowBackground(DS.surfaceSheet)
        } footer: {
            Text("Disconnecting stops syncing. What already landed stays yours.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private func connect() {
        DSHaptic.tap()
        result = nil
        Task {
            guard let fresh = await TwitchAuth.startDeviceFlow() else {
                result = "Couldn't reach Twitch — check your connection."
                resultIsError = true
                return
            }
            code = fresh
            waiting = true
            let ok = await TwitchAuth.poll(fresh, attempts: 60)
            waiting = false
            code = nil
            if ok {
                DSHaptic.success()
                await sync(justConnected: true)
            } else {
                result = "That code wasn't approved in time — tap Connect for a fresh one."
                resultIsError = true
            }
        }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await TwitchIngest.refresh(context: modelContext)
        syncing = false
        loadRecent()
        guard let added else {
            result = "Couldn't read your follows — try again in a moment."
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? "\(added) live now" : "Connected — follows land when they go live."
        let proof = added > 0 ? "\(added) live now" : "Synced just now"
        if store.registerConnected(id: "twitch", name: "Twitch", proof: proof,
                                   can: ["Reads channels you follow.",
                                         "Read-only — never chats or follows."]) {
            DSHaptic.success()
        }
        _ = justConnected
    }
}
