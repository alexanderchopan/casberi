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
    /// The in-flight device flow — one at a time, cancelled when the screen
    /// goes away (review 2026-07-08: double-taps raced two flows).
    @State private var flow: Task<Void, Never>?
    /// Bumped when the device code is copied — the copy button briefly reads
    /// "Copied" so the tap is acknowledged.
    @State private var codeCopied = false

    /// The connection door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if TwitchAuth.connected {
                // Connected (prd §186). No identity passed: the device flow
                // caches an opaque user id (`twitch.userid`), not a login
                // name, so naming the account here would mean a fetch made
                // purely to decorate a header (measured 2026-07-23).
                BridgeConnectedState(
                    bridgeID: "twitch",
                    name: "Twitch",
                    // How it connected, and only that (audit, 2026-07-31): the
                    // note ended "· reads who you follow" two lines above the
                    // checklist's "Reads channels you follow."
                    connectionNote: String(localized: "Approved on twitch.tv"),
                    capabilitiesFallback: ["Reads channels you follow.",
                                           "Read-only — never chats or follows."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(
                    name: "Twitch",
                    mode: .signIn,
                    intro: "Sign in on Twitch's own page and the channels you follow keep arriving — who's live, and what they streamed. Read-only: it can never chat, follow, or subscribe.")
                connectSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Twitch")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Twitch")
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Twitch") {
                connectSection.listRowSeparator(.hidden)
                removeSection.listRowSeparator(.hidden)
            }
        }
        .onAppear {
            if TwitchAuth.connected { Task { await sync() } }
        }
        .onDisappear { flow?.cancel() }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            if TwitchAuth.connected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(20, weight: .regular)
                        .foregroundStyle(DS.confirm)
                    Text("Connected — live follows land in your feed.")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            } else if waiting, let code {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    // The code is the whole moment — big, in a well with an
                    // explicit Copy button, so it plainly reads as "copy this
                    // and enter it on Twitch". GitHub's identical step learned
                    // this the hard way: a bare tap-to-copy went unnoticed
                    // (user, 2026-07-15), and this screen never got the fix
                    // (audit 2026-07-31).
                    HStack(spacing: DS.Space.s3) {
                        Text(code.userCode)
                            .dsText(.monoCode34)
                            .foregroundStyle(DS.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .settleIn()
                        Button(action: { copyCode(code.userCode) }) {
                            HStack(spacing: DS.Space.s1) {
                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                    .dsGlyph(13)
                                Text(codeCopied ? "Copied" : "Copy").dsText(.subhead13).fontWeight(.semibold)
                            }
                            .foregroundStyle(codeCopied ? DS.confirm : DS.tint)
                            .padding(.horizontal, DS.Space.s3)
                            .frame(height: 34)
                            .background(DS.gray100, in: Capsule(style: .continuous))
                            .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(DS.Space.s3)
                    .frame(maxWidth: .infinity)
                    .background(DS.surfaceWell, in: DSSlab.shape)
                    // The door, as this state's one filled block. It was a
                    // hand-painted capsule in Twitch purple: a primary control
                    // never sits on brand color, because two near-match colors
                    // read as a mistake (`bridgeSetupWash`'s standing rule).
                    // Gated on the URL actually being there (§83: no dead
                    // controls). `verificationURL` is optional, so an answer
                    // without `verification_uri` used to paint a full slab
                    // whose tap did nothing — the code well above still shows
                    // what to type, which is the honest fallback.
                    if let url = code.verificationURL {
                        // Verb over address, the 2026-08-14 anatomy — the same
                        // shape GitHub's device flow wears one screen over.
                        DSSlabButton(title: "Approve on Twitch",
                                     detail: "twitch.tv/activate",
                                     systemImage: "arrow.up.right") {
                            DSHaptic.tap()
                            openURL(url)
                        }
                    }
                    HStack(spacing: DS.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for your approval…")
                            .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    }
                }
                .padding(.vertical, DS.Space.s2)
                .dsListCardRow()
            } else if waiting {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Getting your code…")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            } else {
                // The screen's one verb, as the screen's one filled block
                // (prd §218) — it was a blue text row, which read as a link to
                // somewhere rather than the act itself.
                DSSlabButton(title: "Connect Twitch",
                             systemImage: "person.badge.key",
                             action: connect)
            }
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Checking who's live…"),
                                 result: result, resultIsError: resultIsError)
            DSSlabNote(text: "On Twitch's own page — a short code, no password. It can never chat, follow, or subscribe.")
        }
        .dsSlabSection()
    }

    private var removeSection: some View {
        Section {
            Button("Disconnect", role: .destructive) {
                TwitchAuth.disconnect()
                store.bridges.removeAll { $0.id == "twitch" }
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
        waiting = true
        flow = Task {
            defer { flow = nil }
            guard let fresh = await TwitchAuth.startDeviceFlow() else {
                waiting = false
                result = String(localized: "Couldn't reach Twitch — check your connection.")
                resultIsError = true
                return
            }
            guard !Task.isCancelled else { waiting = false; return }
            code = fresh
            let ok = await TwitchAuth.poll(fresh, attempts: 60)
            guard !Task.isCancelled else { waiting = false; code = nil; return }
            waiting = false
            code = nil
            if ok {
                DSHaptic.success()
                await sync()
            } else {
                result = String(localized: "That code wasn't approved in time — tap Connect for a fresh one.")
                resultIsError = true
            }
        }
    }

    private func copyCode(_ code: String) {
        DSPasteboard.copySensitive(code)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { codeCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(DS.Motion.standard) { codeCopied = false }
        }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await TwitchIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            result = String(localized: "Couldn't read your follows — try again in a moment.")
            resultIsError = true
            return
        }
        resultIsError = false
        // The family's own "nothing new" line (audit, 2026-07-31). This said
        // "Connected — follows land when they go live." directly beneath the row
        // that already says "Connected — live follows land in your feed."
        result = added > 0 ? String(localized: "\(added) live now") : String(localized: "Up to date")
        let proof = added > 0
            ? String(localized: "\(added) live now")
            : String(localized: "Synced just now")
        if store.registerConnected(id: "twitch", name: "Twitch", proof: proof,
                                   can: ["Reads channels you follow.",
                                         "Read-only — never chats or follows."]) {
            DSHaptic.success()
        }
    }
}
