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
    /// Bumped when the credentials are cleared from anywhere, purely to
    /// re-evaluate this body — `SpotifyAuth.connected` reads the Keychain and
    /// is not observable, so without a `@State` change nothing repaints. Read
    /// in `body` for exactly that reason; a value nobody reads is a value
    /// SwiftUI is free to ignore.
    @State private var authGeneration = 0

    var body: some View {
        // Reading `authGeneration` is what ties the notification above to this
        // body's re-evaluation. It must not be optimised away.
        let _ = authGeneration
        return List {
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
                // The way back to your things (§460).
                RoomDoor(name: "Spotify", source: "Spotify")
                    .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(
                    name: "Spotify",
                    mode: .signIn,
                    // "what you save and listen to" promised a second half
                    // that does not exist: the only scope asked for is
                    // `user-library-read` and the only endpoint read is
                    // `/me/tracks`, so listening history never arrives (§83).
                    intro: "Sign in on Spotify's own page and the songs you like keep arriving. Read-only: it can never play, queue, or change a playlist.")
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
        // `SpotifyAuth.connected` is a plain static reading the Keychain, so
        // nothing invalidates this body when the credentials are cleared by
        // somebody else — and since 2026-09-02 there IS somebody else: the
        // foreground sweep runs `SpotifyIngest.refresh` too. Its slots land
        // ~1.8–8.8s after activation, so opening this screen in that window
        // gives the screen's own `sync()` an `.alreadyRunning`, which by
        // design says nothing, while the sweep discovers the sign-in is dead
        // and deletes it. The result was a green "Connected — liked songs land
        // in your feed." over a credential that no longer existed, with no
        // sentence at all — the exact screen this branch exists to end,
        // reached by the branch's own new caller.
        //
        // Bumping `@State` is the whole fix: it re-runs the body, which
        // re-reads the Keychain and offers Connect. Posted for ANY caller, so
        // it holds however the clearing was reached.
        .onReceive(NotificationCenter.default.publisher(for: SpotifyAuth.credentialsCleared)) { _ in
            authGeneration &+= 1
            // Only speak if the screen has nothing else to say — a sentence
            // this screen's own read already produced is the better one, and
            // the sweep must never overwrite it.
            if result == nil {
                fail(String(localized: "Spotify's sign-in has expired — tap Connect to sign in again."))
            }
        }
        .onDisappear { flow?.cancel() }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            if SpotifyAuth.connected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(20, weight: .regular)
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
            DSSlabNote(text: "On Spotify's own page — PKCE, no password in the app. Read-only.")
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
        let outcome = await SpotifyIngest.refresh(context: modelContext)
        syncing = false
        // One sentence per outcome the read can actually tell apart — the
        // rule the connect half of this screen has followed since the
        // 2026-07-31 audit, and which the read half never did: it said
        // "Couldn't read your liked songs — try again in a moment" for all
        // six, advice that is true of `.busy` alone and can never work for a
        // retired sign-in, a refusal, or a shape that moved.
        let added: Int
        switch outcome {
        case .landed(let n):
            added = n
        case .notConnected:
            fail(String(localized: "Not connected — tap Connect to sign in with Spotify."))
            return
        case .signInExpired:
            // `SpotifyAuth` has already cleared the dead credentials, so the
            // screen behind this sentence now offers Connect rather than
            // showing a green check over a connection Spotify has retired.
            fail(String(localized: "Spotify's sign-in has expired — tap Connect to sign in again."))
            return
        case .busy:
            fail(String(localized: "Spotify is busy right now — try again in a moment."))
            return
        case .refused(let status, _):
            // 403 is the one refusal a person CANNOT act on, and it is the one
            // that actually happens (measured against a real account
            // 2026-09-02): Spotify blocks an app in development mode whose
            // owner has no Premium subscription, and blocks any account not on
            // that app's five-name allowlist. Both answer a BARE 403 to every
            // endpoint, `/v1/me` included, which needs no scope at all — so
            // the token is fine, the grant is fine, and signing in again
            // re-mints a credential that is refused identically.
            //
            // "tap Connect to sign in again" for that is the advice-that-can-
            // never-work this whole screen was rewritten to remove (§579),
            // pointing at the screen's own button. It says the true thing
            // instead, and deliberately does not name development mode or
            // Premium: that is the DEVELOPER's problem with their dashboard,
            // and nothing the person reading this owns or can change.
            if status == 403 {
                fail(String(localized: "Spotify isn't letting this app read your library — signing in again won't change it."))
            } else {
                fail(String(localized: "Spotify wouldn't share your liked songs — tap Connect to sign in again."))
            }
            return
        case .unreachable:
            fail(String(localized: "Couldn't reach Spotify — check your connection."))
            return
        case .unreadable:
            fail(String(localized: "Spotify answered with something this version can't read."))
            return
        case .alreadyRunning:
            // The sweep is mid-read. Say nothing rather than overwrite the
            // last real result with a verdict this call didn't reach — but the
            // sweep may be about to clear the credentials underneath us, which
            // is what `credentialsCleared` below is for.
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
