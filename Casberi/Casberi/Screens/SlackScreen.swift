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
    /// The last attempt was closed by hand. Kept apart from `result` because
    /// the status row speaks two voices — red for an error, green for a
    /// result — and a sign-in you dismissed is neither.
    @State private var cancelled = false

    /// The connection door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if SlackAuth.connected {
                BridgeConnectedState(
                    bridgeID: "slack",
                    name: "Slack",
                    identity: SlackAuth.teamName,
                    connectionNote: String(localized: "Signed in on \(DS.device) · search only, no server ever holds a secret"),
                    capabilitiesFallback: ["Looks up mentions of you.",
                                           "Read-only — never posts, reads files, or browses channels."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // The way back to your things (§460).
                RoomDoor(name: "Slack", source: "Slack")
                    .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(
                    name: "Slack",
                    mode: .signIn,
                    intro: "Sign in on Slack's own page and mentions of you keep arriving. Only messages that name you — never a channel's whole history, and it can never post.")
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
                if cancelled {
                    Text("Sign-in cancelled — nothing was connected.")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Checking your mentions…"),
                                 result: result, resultIsError: resultIsError)
            // Says what LANDS before what's safe (audit, 2026-07-31) — this
            // named PKCE, the missing password, the absent server and the
            // search-only scope, and never once said what a mention becomes
            // once it's here. The scope's own clause then said "Casberi can
            // look up your mentions and nothing else", which is the first
            // sentence again; the SCOPE (prd §192) is what it's there for, and
            // that survives whole.
            DSSlabNote(text: "On Slack's own page — no password ever touches the app.")
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
            let outcome = await SlackAuth.signIn()
            guard !Task.isCancelled else { connecting = false; return }
            connecting = false
            switch outcome {
            case .ok:
                DSHaptic.success()
                await sync()
            // One sentence per outcome the flow can actually tell apart (audit
            // 2026-07-31). "Couldn't connect" said the same thing for a sheet
            // you closed, a phone with no signal, and an exchange Slack turned
            // down — and the next move differs for each.
            case .cancelled:
                cancelled = true
            case .declined:
                fail(String(localized: "You didn't approve it in Slack — nothing was connected."))
            case .cantOpen:
                fail(String(localized: "Couldn't open Slack's sign-in page — try again."))
            case .unreachable:
                fail(String(localized: "Couldn't reach Slack — check your connection."))
            case .refused:
                fail(String(localized: "Slack wouldn't finish the sign-in — tap Connect to start again."))
            }
        }
    }

    private func fail(_ message: String) {
        result = message
        resultIsError = true
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
        let proof = added > 0
            ? String(localized: "\(added) new")
            : String(localized: "Synced just now")
        if store.registerConnected(id: "slack", name: "Slack", proof: proof,
                                   can: ["Looks up mentions of you.",
                                         "Read-only — never posts, reads files, or browses channels."]) {
            DSHaptic.success()
        }
    }
}
