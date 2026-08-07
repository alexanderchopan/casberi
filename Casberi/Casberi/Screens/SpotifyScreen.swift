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
    @State private var flow: Task<Void, Never>?
    /// The last attempt was closed by hand. Kept apart from `result` because
    /// the status row speaks two voices — red for an error, green for a
    /// result — and a sign-in you dismissed is neither.
    @State private var cancelled = false

    /// The connection door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if SpotifyAuth.connected {
                // Connected (prd §186). NO identity passed on purpose: the
                // PKCE flow stores tokens only — no display name — so leading
                // with a name would mean inventing one or fetching /me just to
                // decorate a header. The bridge's own name over a true note
                // about how it's signed in is the honest lead (measured
                // 2026-07-23).
                BridgeConnectedState(
                    bridgeID: "spotify",
                    name: "Spotify",
                    connectionNote: String(localized: "Signed in on \(DS.device) · no server ever holds a secret"),
                    capabilitiesFallback: ["Reads your liked songs.",
                                           "Read-only — never plays, adds, or removes."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(
                    name: "Spotify",
                    mode: .signIn,
                    intro: "Sign in on Spotify's own page and what you save and listen to keeps arriving. Read-only: it can never play, queue, or change a playlist.")
                connectSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Spotify")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Spotify")
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Spotify") {
                connectSection.listRowSeparator(.hidden)
                removeSection.listRowSeparator(.hidden)
            }
        }
        .onAppear {
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
                // The screen's one verb, as the screen's one filled block
                // (prd §218) — it was a blue text row, which read as a link to
                // somewhere rather than the act itself.
                DSSlabButton(title: "Connect Spotify",
                             systemImage: "person.badge.key",
                             action: connect)
                if cancelled {
                    Text("Sign-in cancelled — nothing was connected.")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Checking your liked songs…"),
                                 result: result, resultIsError: resultIsError)
            DSSlabNote(text: "Sign-in happens on Spotify's own page — PKCE, no password in the app. Read-only.")
        }
        .dsSlabSection()
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
        cancelled = false
        connecting = true
        flow = Task {
            defer { flow = nil }
            let outcome = await SpotifyAuth.signIn()
            guard !Task.isCancelled else { connecting = false; return }
            connecting = false
            switch outcome {
            case .ok:
                DSHaptic.success()
                await sync()
            // One sentence per outcome the flow can actually tell apart (audit
            // 2026-07-31). "Couldn't connect" said the same thing for a sheet
            // you closed, a phone with no signal, and an exchange Spotify
            // turned down — and the next move differs for each.
            case .cancelled:
                cancelled = true
            case .declined:
                fail(String(localized: "You didn't approve it on Spotify — nothing was connected."))
            case .cantOpen:
                fail(String(localized: "Couldn't open Spotify's sign-in page — try again."))
            case .unreachable:
                fail(String(localized: "Couldn't reach Spotify — check your connection."))
            case .refused:
                fail(String(localized: "Spotify wouldn't finish the sign-in — tap Connect to start again."))
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
        let added = await SpotifyIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            result = String(localized: "Couldn't read your liked songs — try again in a moment.")
            resultIsError = true
            return
        }
        resultIsError = false
        // The family's own "nothing new" line (audit, 2026-07-31). This said
        // "Connected — liked songs land as you save them." directly beneath the
        // row that already says "Connected — liked songs land in your feed.",
        // so the connection sheet claimed the same thing twice in a row.
        result = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
        let proof = added > 0
            ? String(localized: "\(added) new")
            : String(localized: "Synced just now")
        if store.registerConnected(id: "spotify", name: "Spotify", proof: proof,
                                   can: ["Reads your liked songs.",
                                         "Read-only — never plays, adds, or removes."]) {
            DSHaptic.success()
        }
    }
}
