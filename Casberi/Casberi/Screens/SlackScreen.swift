import SwiftUI
import SwiftData

/// Slack's setup — PKCE, entirely on this iPhone: one tap opens Slack's own
/// sign-in page, the callback lands back on `casberi://slack-auth`, and
/// mentions of you sync right after. Unlike Spotify's identity-less PKCE
/// token, Slack's OAuth response hands over the workspace name honestly, so
/// this screen leads with "Connected to <workspace>" truthfully — the same
/// shape Dropbox's folder-path identity uses.
struct SlackScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var flow: Task<Void, Never>?

    /// The connection door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if SlackAuth.connected {
                BridgeConnectedState(
                    bridgeID: "slack",
                    name: "Slack",
                    identity: SlackAuth.teamName,
                    connectionNote: String(localized: "Signed in on this iPhone · search only, no server ever holds a secret"),
                    capabilitiesFallback: ["Looks up mentions of you.",
                                           "Read-only — never posts, reads files, or browses channels."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(name: "Slack")
                connectSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Slack")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Slack")
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Slack") {
                removeSection.listRowSeparator(.hidden)
            }
        }
        .onAppear {
            if SlackAuth.connected { Task { await sync() } }
        }
        .onDisappear { flow?.cancel() }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            if connecting {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Slack…")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            } else {
                // The screen's one verb, as the screen's one filled block
                // (prd §218) — it was a blue text row, which read as a link to
                // somewhere rather than the act itself.
                DSSlabButton(title: "Connect Slack",
                             systemImage: "at",
                             action: connect)
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Checking your mentions…"),
                                 result: result, resultIsError: resultIsError)
            DSSlabNote(text: "Sign-in happens on Slack's own page — PKCE, no password in the app, no server ever holds a secret. Search only: Casberi can look up your mentions and nothing else — it can't post, read files, or see channels it isn't asked about.")
        }
        .dsSlabSection()
    }

    private var removeSection: some View {
        Section {
            Button("Disconnect", role: .destructive) {
                SlackAuth.disconnect()
                store.bridges.removeAll { $0.id == "slack" }
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
            let ok = await SlackAuth.signIn()
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
        let added = await SlackIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            result = String(localized: "Couldn't check your mentions — try again in a moment.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) new" : "Synced just now"
        if store.registerConnected(id: "slack", name: "Slack", proof: proof,
                                   can: ["Looks up mentions of you.",
                                         "Read-only — never posts, reads files, or browses channels."]) {
            DSHaptic.success()
        }
    }
}
