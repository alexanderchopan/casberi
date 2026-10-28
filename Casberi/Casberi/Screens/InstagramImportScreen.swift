import SwiftUI
import SwiftData

/// Instagram, connected — by its live sign-in alone (prd §726): a sign-in
/// inside this app, through `InstagramLiveLoginSheet`, reads the person's own
/// notifications and saved posts with their own session cookies, and their
/// messages when they turn them on (§1244). `InstagramCaptions` reads a saved
/// post's caption and cover back off its public page.
///
/// The export import that gave this screen its name is deleted, steps, folder
/// pick and model together (prd §1577, §1579). Nobody had imported, so
/// nothing is kept for an old import.
struct InstagramImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    /// The live door (prd §726) — notifications and saves read through the
    /// person's OWN Instagram session.
    @State private var liveConnected = false
    @State private var liveSyncing = false
    @State private var liveResult: BridgeProof?
    /// The live messages read (prd §1244), off until turned on here.
    @AppStorage(LiveMessages.Seat.instagram.defaultsKey) private var readsMessages = false
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?


    var body: some View {
        AccountPage(
            name: "Instagram", seatID: "instagram", source: "Instagram",
            state: AccountPageState.of(name: "Instagram", seatID: "instagram",
                                       connected: liveConnected, store: store),
            mode: .signIn,
            // The live sign-in (prd §726), raised through the page's ONE
            // presentation like every other seat-only screen here.
            cardSheet: { _ in
                AnyView(InstagramLiveLoginSheet(onCaptured: {
                    liveConnected = true
                    Task { await syncLive() }
                }))
            },
            // Clears the session only — the rows it landed stay, the "delete
            // things vs. delete access" split every other seat here follows
            // (2026-07-13).
            teardown: { InstagramLiveAuth.clear() },
            sheet: $sheet,
            act: {
                liveBlock
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            reread()
            // The SWEEP's throttle, not X's read-on-every-appearance: Meta
            // flags a busy session and the flag lands on the person's real
            // account (prd §726). `dueForHeal` shares its stamp with the
            // sweep, so opening this page counts as the ten-minute read.
            if liveConnected, BridgeRefresh.dueForHeal("instagram.live") {
                Task { await syncLive() }
            }
        }
    }

    /// The live door (prd §726) — a sign-in inside this app, through
    /// `InstagramLiveLoginSheet`: the posts you saved as posts, and the likes,
    /// comments and follows as they happen.
    ///
    /// The note says the price before the tap, and the price here is not the
    /// app's: Meta may ask the person to confirm the sign-in in their own
    /// Instagram app, and a read Meta dislikes lands on THEIR account.
    @ViewBuilder private var liveBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if liveConnected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "bell.fill")
                        .dsGlyph(.body, weight: .medium)
                        .foregroundStyle(DS.brandInk)
                    Text(InstagramLiveAuth.username.map { "Live — signed in as @\($0)" }
                         ?? String(localized: "Live — your own account, signed in"))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                // Your direct messages (prd §1244): a decision, so a switch,
                // and off until you make it. Turning it off keeps what came.
                DSToggleRow(title: Text("Read your messages"),
                            detail: Text("Each conversation lands as one thing. Off keeps what came."),
                            isOn: $readsMessages)
                    .onChange(of: readsMessages) { _, on in
                        if on { Task { await syncLive() } }
                    }
            } else {
                DSSlabButton(tile: .signIn, title: "Connect",
                             detail: String(localized: "Live notifications and saves"),
                             systemImage: "bell.badge",
                             busy: false) { sheet = .card(id: "igLive") }
            }
            BridgeSyncStatusRows(syncing: liveSyncing,
                                syncingLine: String(localized: "Checking Instagram…"),
                                proof: liveResult)
            DSSlabNote(text: "Instagram may ask you to confirm it was you.", plain: true)
        }
    }

    private func reread() {
        liveConnected = InstagramLiveAuth.connected
    }

    /// Runs the live read (prd §726) and reports it in the page's four-outcome
    /// shape. A refusal clears the session inside `refresh` (§711: a refusal
    /// and only a refusal), so the block above falls back to its Connect slab
    /// on the re-read rather than saying "signed in" over a dead cookie.
    private func syncLive() async {
        guard !liveSyncing else { return }
        liveSyncing = true
        let added = await InstagramLive.refresh(context: modelContext)
        liveSyncing = false
        liveConnected = InstagramLiveAuth.connected
        guard let added else {
            liveResult = .failed(liveConnected
                ? String(localized: "Couldn't read Instagram — if it asked you to confirm a sign-in, open Instagram and confirm, then try again.")
                : String(localized: "Instagram signed this app out — tap Connect to sign in again."))
            return
        }
        liveResult = added > 0 ? .landed(added) : .upToDate
        // Registers the seat — the catalog tile and the dock chip both read
        // `BridgeStore`.
        let proof = added > 0 ? String(localized: "\(added) new") : String(localized: "Synced just now")
        if store.registerConnected(id: "instagram", name: "Instagram", proof: proof,
                                   can: ["Reads your notifications and saved posts, with your own sign-in.",
                                         "Read-only — never posts, likes, or follows for you."]) {
            DSHaptic.success()
        }
    }
}
