import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// X, connected — by import, the ChatGPT grade, because X has no free read of
/// any kind left (prd §280).
///
/// The folder pick and its two-level search are Instagram's, for Instagram's
/// reason: an archive scatters its categories across several files under
/// `data/`, and asking for each one would be several chances to pick wrong.
///
/// The BOOKMARKS GAP is named in the footer, and that is the whole of why it's
/// there: bookmarks are the pile an X user would most expect to find in this
/// app, they have never been in the export, and a person who imports and then
/// can't find them would reasonably read that as a broken importer rather than
/// as a limit of what X hands over. Saying it before the tap is the honesty
/// rule, not hedging.
///
/// The SHAPE is `ImportSetupComponents`' (prd §314) — this screen is the one
/// that earned it, reported as *"three large buttons and tons of text"*. What
/// it had was two filled slabs before an import and four after, five separate
/// centered gray paragraphs, and a 24-hour wait rendered as though both halves
/// of it were happening at once. What it has now is one filled verb at a time
/// and one footer.
struct XArchiveImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var result: BridgeProof?
    /// How old this import is, and how much of it is here (2026-08-05,
    /// prd §310). Both read off the import RECEIPT and a count — no new field.
    @State private var staleness: String?
    @State private var held = 0
    @State private var fetching = false
    @State private var pending = 0
    /// The other half of the second act (2026-08-13, prd §375) — replies whose
    /// parent post we have a permalink for and no words.
    @State private var fetchingContext = false
    @State private var pendingContext = 0
    /// The SECOND door onto this seat (prd §701) — notifications read live
    /// through the person's OWN X session cookies, entirely separate from the
    /// archive above: connecting or disconnecting one never touches the other.
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
            // Connected if EITHER door is open (prd §701) — an import with no
            // live read, or live notifications with no archive yet, are both
            // real "this seat is doing something" states.
            state: AccountPageState.of(name: "X", seatID: "x",
                                       connected: held > 0 || liveConnected, store: store),
            // The bookmarks limit rides the intro rather than a footer point
            // (prd §315), and it is the one limit that earns the sentence's
            // second half: bookmarks are the pile an X user most expects this
            // seat to hold, and they are the one thing it can never have.
            // §701 amendment: the catalogue word is now "Connect" (the live
            // sign-in), not "Import" — the archive stays the second act, not
            // the first thing a person is offered (`catalog-mode-audit.py`).
            mode: .signIn,
            // The live-notifications sign-in (prd §701), raised through the
            // page's ONE presentation like every other seat-only screen here.
            cardSheet: { _ in
                AnyView(XLiveLoginSheet(onCaptured: {
                    liveConnected = true
                    Task { await syncLive() }
                }))
            },
            // Clears the LIVE half only — an imported archive's rows are
            // untouched, the "delete things vs. delete access" split every
            // other seat here follows (2026-07-13).
            // The row does the thing (prd §1464): X's sign-in rises as the
            // page opens, until the live read is connected.
            signIn: { sheet = .card(id: "xLive") },
            teardown: { XLiveAuth.clear() },
            sheet: $sheet,
            // TWO VERBS, live first (prd §794, user: "it should be clear about
            // live connections, that page should have a connect and an import
            // button"). Connect is the live read; Import opens the archive's
            // steps only when asked for.
            act: {
                liveBlock
                if pending > 0 || pendingContext > 0 { secondActBlock }
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
    /// `XLiveLoginSheet`, entirely apart from the archive. FIRST since §794:
    /// it is the one that keeps the room current, so the page says "live"
    /// before it says "archive". Connected, the slab becomes the fact.
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

    /// The second act (2026-08-05), TikTok's split for the same reason: the
    /// import above is instant and offline, each of these is one request per
    /// row. Two verbs since 2026-08-13, in ONE section under ONE sentence —
    /// they cost the same thing, they ask the same endpoint, and a section each
    /// would be two slabs and two notes on the screen §314 exists because of.
    ///
    /// What each buys is narrow and worth stating plainly. A liked post already
    /// arrives wearing its own words (`like.js` carries `fullText`); what the
    /// archive never carries is WHO WROTE IT. A reply already names its
    /// recipient; what it can never name is what they SAID — and a reply
    /// without that is a sentence answering nothing.
    ///
    /// Each button appears only while it has work, so a room that is entirely
    /// posts, or entirely replies to yourself (filled at import, for free),
    /// never offers a verb with nothing behind it.
    @ViewBuilder private var secondActBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if pending > 0 {
                DSSlabButton(title: fetching ? "Finding authors…" : "Find authors for \(pending) likes",
                             systemImage: "person.crop.circle",
                             busy: fetching,
                             enabled: !fetching && !fetchingContext) {
                    DSHaptic.tap()
                    Task { await runFetch() }
                }
            }
            if pendingContext > 0 {
                DSSlabButton(title: fetchingContext ? "Reading replies…" : "Show what \(pendingContext) replies answered",
                             systemImage: "arrowshape.turn.up.left",
                             busy: fetchingContext,
                             enabled: !fetching && !fetchingContext) {
                    DSHaptic.tap()
                    Task { await runContextFetch() }
                }
            }
            // This section's own sentence, and the screen's only one
            // outside the footer — it is the sole explanation of verbs
            // that cost network, so it stays beside them rather than
            // moving to the bottom with the fine print.
        }
    }

    /// One re-read of everything this screen shows about the corpus — called on
    /// appear, after an import and after a removal, so the three can never
    /// disagree about how much is here.
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "X", context: modelContext)
        held = ImportRemoval.count(source: "X", context: modelContext)
        pending = XArchiveImport.pendingFaceCount(context: modelContext)
        pendingContext = XArchiveImport.pendingContextCount(context: modelContext)
        liveConnected = XLiveAuth.connected
    }

    /// Runs the live-notifications read (prd §701) and reports it in the same
    /// four-outcome shape `runFetch`/`runContextFetch` already use on this
    /// screen — a refusal (stale cookies) reads differently from a plain
    /// "nothing new".
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
        // Registers the seat even when no archive has ever been imported —
        // the catalog tile and the dock chip both read `BridgeStore`, and a
        // live-only connection is a real one.
        let proof = added > 0 ? String(localized: "\(added) new") : String(localized: "Synced just now")
        if store.registerConnected(id: "x", name: "X", proof: proof,
                                   can: ["Reads your notifications live, with your own sign-in.",
                                         "Read-only — never posts, likes, or follows for you."]) {
            DSHaptic.success()
        }
    }

    // MARK: - Run

    /// Four outcomes, four sentences — the `-kalshiBookProbe` discipline on a
    /// screen: "couldn't reach X" and "every post we asked about is gone" are
    /// different facts and only one is worth retrying.
    private func runFetch() async {
        fetching = true
        defer { fetching = false }
        let outcome = await XArchiveImport.fetchFaces(context: modelContext)
        pending = XArchiveImport.pendingFaceCount(context: modelContext)

        if outcome.unreachable {
            result = .failed(String(localized: "Couldn't reach X — your likes are still here, so try finding their authors again later."))
            return
        }
        DSHaptic.success()
        var line = String(localized: "\(outcome.named) named")
        // GONE is its own clause, separate from a miss. They read alike and
        // they are not alike: a gone post is a fact X told us and one this app
        // now keeps, while a miss is an answer we couldn't parse.
        if outcome.gone > 0 {
            line += String(localized: " · \(outcome.gone) gone or private")
        }
        if outcome.missed > 0 {
            line += String(localized: " · \(outcome.missed) unreadable")
        }
        if pending > 0 { line += String(localized: " · \(pending) to go") }
        result = .says(line)
    }

    /// The reply pass, reported with `runFetch`'s discipline: four outcomes,
    /// four sentences, and GONE said separately from unreadable — a parent post
    /// that has been deleted is a fact about your archive worth knowing, while
    /// an unreadable answer is one to try again later.
    private func runContextFetch() async {
        fetchingContext = true
        defer { fetchingContext = false }
        let outcome = await XArchiveImport.fetchReplyContext(context: modelContext)
        pendingContext = XArchiveImport.pendingContextCount(context: modelContext)

        if outcome.unreachable {
            result = .failed(String(localized: "Couldn't reach X — your replies are still here, so try again later."))
            return
        }
        DSHaptic.success()
        var line = String(localized: "\(outcome.filled) replies now show what they answered")
        if outcome.gone > 0 {
            line += String(localized: " · \(outcome.gone) answered a post that's gone")
        }
        if outcome.missed > 0 {
            line += String(localized: " · \(outcome.missed) unreadable")
        }
        if pendingContext > 0 { line += String(localized: " · \(pendingContext) to go") }
        result = .says(line)
    }
}
