import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Instagram, connected — by import, the ChatGPT grade, because a personal
/// Instagram account has no API at all (prd §245).
///
/// This screen picks a FOLDER rather than a file, which is the one way it
/// diverges from its siblings: an Instagram export scatters saves, likes,
/// posts and comments across four different files, and asking for four picks
/// would be four chances to pick the wrong one.
///
/// The note under the button states the export's own split — captions and
/// comments arrive as text, saves and likes arrive as named links — because
/// the alternative is a person importing their saves and finding rows that
/// don't say what the post said. That is the honesty rule, not hedging.
///
/// AMENDED 2026-08-02 (`InstagramCaptions`, prd §245 amendment). Those rows no
/// longer STAY wordless: the caption is public on the post's own page, so a
/// paced background pass reads it back. The note had to change with the
/// behaviour and gained two obligations rather than losing one — it says the
/// app will open those pages (a network act the person is entitled to know
/// about before tapping Import, and disclosed in `NetworkReach` besides), and
/// it says a deleted or private post stays a link, because the failure has to
/// be named where the promise is made.
///
/// AMENDED AGAIN 2026-08-18 (prd §389). Two of the export's own categories the
/// steps never told anybody to tick — Stories and Reels — are read now, so the
/// tick list names them; and the saved rows get their COVER PICTURE back beside
/// their words, which is why the intro says a picture is fetched as well as a
/// caption. The reach is the same one `NetworkReach` already discloses, one
/// entry widened rather than a new act to explain.
///
/// SHAPE: `ImportSetupComponents`' (prd §314) — the staged block X earned. The
/// wait here is about an hour rather than a day, but the structure is the same
/// and so was the clutter.
///
/// AMENDED 2026-09-13 (prd §726): a SECOND door, X's §701 one seat over. A
/// sign-in inside this app, through `InstagramLiveLoginSheet`, reads the
/// person's own notifications and saved posts with their own session cookies —
/// and fills the export's pointers with the posts themselves. The two doors are
/// uncoupled: connecting or disconnecting the live half never touches an
/// imported row, and the seat reads connected when EITHER is open. The
/// catalogue word is "Connect" now (`mode: .signIn`, `catalog-mode-audit.py`);
/// the export stays the second act, for the years the live read cannot reach.
struct InstagramImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var result: BridgeProof?
    /// How old this import is, and how much of it is here (2026-08-05,
    /// prd §310). Both read off the import RECEIPT and a count — no new field.
    @State private var staleness: String?
    @State private var held = 0
    /// The SECOND door onto this seat (prd §726) — notifications and saves
    /// read live through the person's OWN Instagram session, entirely separate
    /// from the export above.
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
            // Connected if EITHER door is open (prd §726) — an import with no
            // live read, or a live sign-in with no export yet, are both real
            // "this seat is doing something" states.
            state: AccountPageState.of(name: "Instagram", seatID: "instagram",
                                       connected: held > 0 || liveConnected, store: store),
            mode: .signIn,
            // The live sign-in (prd §726), raised through the page's ONE
            // presentation like every other seat-only screen here.
            cardSheet: { _ in
                AnyView(InstagramLiveLoginSheet(onCaptured: {
                    liveConnected = true
                    Task { await syncLive() }
                }))
            },
            // Clears the LIVE half only — an imported export's rows are
            // untouched, the "delete things vs. delete access" split every
            // other seat here follows (2026-07-13).
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
    /// `InstagramLiveLoginSheet`, apart from the export below. First, because
    /// it is the door that reads what the export cannot: the posts you saved
    /// as posts, and the likes, comments and follows as they happen.
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

    /// One re-read of what this screen shows about the corpus — on appear,
    /// after an import and after a removal, so the three can never disagree.
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "Instagram", context: modelContext)
        held = ImportRemoval.count(source: "Instagram", context: modelContext)
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
        // Registers the seat even when no export has ever been imported —
        // the catalog tile and the dock chip both read `BridgeStore`, and a
        // live-only connection is a real one.
        let proof = added > 0 ? String(localized: "\(added) new") : String(localized: "Synced just now")
        if store.registerConnected(id: "instagram", name: "Instagram", proof: proof,
                                   can: ["Reads your notifications and saved posts, with your own sign-in.",
                                         "Read-only — never posts, likes, or follows for you."]) {
            DSHaptic.success()
        }
    }

    // MARK: - Run

}
