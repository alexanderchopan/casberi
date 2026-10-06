import SwiftUI
import SwiftData

/// Threads' account page (prd §1131): one door, a sign-in inside this app
/// through `ThreadsLiveLoginSheet`. What lands: your Activity — likes,
/// replies, mentions, follows — as it happens. There is no export act:
/// Threads' own data download is not this seat's, and the live read is the
/// whole of it.
struct ThreadsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connected = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Threads", seatID: "threads", source: ThreadsLiveFeed.source,
            state: AccountPageState.of(name: "Threads", seatID: "threads",
                                       connected: connected, store: store),
            mode: .signIn,
            cardSheet: { _ in
                AnyView(ThreadsLiveLoginSheet(onCaptured: {
                    connected = true
                    Task { await sync() }
                }))
            },
            // Clears the session only; every notice already landed stays.
            teardown: { ThreadsLiveAuth.clear() },
            sheet: $sheet,
            act: { liveBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            connected = ThreadsLiveAuth.connected
            // The sweep's ten-minute throttle, shared: opening this page counts
            // as the read, never a second one (Meta flags a busy session).
            if connected, BridgeRefresh.dueForHeal("threads.live") {
                Task { await sync() }
            }
        }
    }

    /// The note says the price before the tap, and the price is not the app's:
    /// Meta may ask the person to confirm the sign-in in their own app.
    @ViewBuilder private var liveBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if connected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "bell.fill")
                        .dsGlyph(.body, weight: .medium)
                        .foregroundStyle(DS.tint)
                    Text(ThreadsLiveAuth.username.map { String(localized: "Signed in as @\($0)") }
                         ?? String(localized: "Signed in"))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            } else {
                DSSlabButton(title: "Connect",
                             detail: String(localized: "Likes, replies and follows"),
                             systemImage: "bell.badge",
                             busy: false) { sheet = .card(id: "threadsLive") }
            }
            BridgeSyncStatusRows(syncing: syncing,
                                syncingLine: String(localized: "Checking Threads…"),
                                proof: result,
                                retry: connected ? retrySync : nil)
            DSSlabNote(text: "You sign in with Instagram. Meta may ask you to confirm it was you.", plain: true)
        }
    }

    private func retrySync() { Task { await sync() } }

    /// Runs the read and reports it in the page's four-outcome shape. A
    /// refusal clears the session inside `refresh` (§711), so the block falls
    /// back to Connect rather than saying "signed in" over a dead cookie.
    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await ThreadsLive.refresh(context: modelContext)
        syncing = false
        connected = ThreadsLiveAuth.connected
        guard let added else {
            switch ThreadsLive.lastFailure {
            case .throttled?:
                result = .says(String(localized: "Threads asked us to slow down — it reads again in a few minutes."))
            case .refused?, .noSession?:
                result = .failed(String(localized: "Threads signed this app out — tap Connect to sign in again."))
            default:
                result = .failed(String(localized: "Couldn't read Threads — if it asked you to confirm a sign-in, open Instagram and confirm, then try again."))
            }
            return
        }
        result = added > 0 ? .landed(added) : .upToDate
        let proof = added > 0 ? String(localized: "\(added) new") : String(localized: "Synced just now")
        if store.registerConnected(id: "threads", name: "Threads", proof: proof,
                                   can: ["Reads your Threads activity, with your own sign-in.",
                                         "Read-only — never posts, likes, follows or marks anything seen."]) {
            DSHaptic.success()
        }
    }
}
