import SwiftUI
import SwiftData

/// X, connected — by its live sign-in alone (prd §701): notifications, and
/// your messages when you turn them on (§1244), read with your own X session.
///
/// The archive import that gave this screen its name is deleted, steps,
/// folder pick and model together (prd §1577, §1579). Nobody had imported,
/// so nothing is kept for an old import.
struct XArchiveImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    /// The live door (prd §701) — notifications read through the person's OWN
    /// X session cookies.
    @State private var liveConnected = false
    @State private var liveSyncing = false
    @State private var liveResult: BridgeProof?
    /// The live messages read (prd §1244), off until turned on here.
    @AppStorage(LiveMessages.Seat.x.defaultsKey) private var readsMessages = false
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?


    var body: some View {
        AccountPage(
            name: "X", seatID: "x", source: "X",
            state: AccountPageState.of(name: "X", seatID: "x",
                                       connected: liveConnected, store: store),
            // The catalogue word is "Connect", the live sign-in
            // (`catalog-mode-audit.py`).
            mode: .signIn,
            // The live-notifications sign-in (prd §701), raised through the
            // page's ONE presentation like every other seat-only screen here.
            cardSheet: { _ in
                AnyView(XLiveLoginSheet(onCaptured: {
                    liveConnected = true
                    Task { await syncLive() }
                }))
            },
            // Clears the session only — the rows it landed stay, the "delete
            // things vs. delete access" split every other seat here follows
            // (2026-07-13).
            // The row does the thing (prd §1464): X's sign-in rises as the
            // page opens, until the live read is connected.
            signIn: { sheet = .card(id: "xLive") },
            teardown: { XLiveAuth.clear() },
            sheet: $sheet,
            act: {
                liveBlock
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            reread()
            if liveConnected { Task { await syncLive() } }
        }
    }

    /// The live door (prd §701) — a sign-in inside this app, through
    /// `XLiveLoginSheet`. Connected, the slab becomes the fact.
    @ViewBuilder private var liveBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if liveConnected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "bell.fill")
                        .dsGlyph(.body, weight: .medium)
                        .foregroundStyle(DS.brandInk)
                    Text("Live — notifications arrive as they happen")
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
                             detail: String(localized: "Live notifications"),
                             systemImage: "bell.badge",
                             busy: false) { sheet = .card(id: "xLive") }
            }
            BridgeSyncStatusRows(syncing: liveSyncing,
                                syncingLine: String(localized: "Checking your notifications…"),
                                proof: liveResult)
        }
    }

    private func reread() {
        liveConnected = XLiveAuth.connected
    }

    /// Runs the live-notifications read (prd §701) — a refusal (stale cookies)
    /// reads differently from a plain "nothing new".
    private func syncLive() async {
        guard !liveSyncing else { return }
        liveSyncing = true
        let added = await XLiveNotifications.refresh(context: modelContext)
        liveSyncing = false
        guard let added else {
            liveResult = .failed(String(localized: "Couldn't read your notifications — sign in again if this keeps happening."))
            return
        }
        liveResult = added > 0 ? .landed(added) : .upToDate
        // Registers the seat — the catalog tile and the dock chip both read
        // `BridgeStore`.
        let proof = added > 0 ? String(localized: "\(added) new") : String(localized: "Synced just now")
        if store.registerConnected(id: "x", name: "X", proof: proof,
                                   can: ["Reads your notifications live, with your own sign-in.",
                                         "Read-only — never posts, likes, or follows for you."]) {
            DSHaptic.success()
        }
    }
}
