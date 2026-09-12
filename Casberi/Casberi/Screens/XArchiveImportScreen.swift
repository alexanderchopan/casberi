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
    @State private var importing = false
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
            mode: .oneTimeImport,
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
            teardown: { XLiveAuth.clear() },
            sheet: $sheet,
            act: {
                archiveBlock
                liveBlock
                if pending > 0 || pendingContext > 0 { secondActBlock }
            },
            more: {
                ImportUpkeepSection(source: "X", held: held,
                                    staleness: staleness, plain: true) { gone in
                    reread()
                    result = .says(String(localized: "\(gone) removed"))
                }
            },
            keySheet: { EmptyView() }
        )
        .onAppear {
            reread()
            if liveConnected { Task { await syncLive() } }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    /// The live-notifications door (prd §701) — a sign-in inside this app,
    /// through `XLiveLoginSheet`, entirely apart from the archive above. Read
    /// live, so it is offered whether or not an archive has ever been picked.
    @ViewBuilder private var liveBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if liveConnected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "bell.fill")
                        .dsGlyph(17, weight: .medium)
                        .foregroundStyle(DS.tint)
                    Text("Live notifications — your own account, signed in")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            } else {
                DSSlabButton(title: "Get live notifications",
                             systemImage: "bell.badge",
                             busy: false) { sheet = .card(id: "xLive") }
            }
            BridgeSyncStatusRows(syncing: liveSyncing,
                                syncingLine: String(localized: "Checking your notifications…"),
                                proof: liveResult)
            DSSlabNote(text: "Sign in with your own X account, in this app. Read-only, and only for the account you sign into — it never touches your archive above.", plain: true)
        }
    }

    /// The wait is the reason this screen stages itself at all: X makes you
    /// re-enter your password and then takes up to 24 hours. Someone who taps
    /// "Choose folder" the same minute has nothing to pick.
    @ViewBuilder private var archiveBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ImportArchiveSection(
                source: "X",
                doorTitle: "Open X settings",
                doorURL: URL(string: "https://x.com/settings/download_your_data"),
                steps: [
                    "Tap Request archive and confirm your password.",
                    "Ready within about 24 hours",
                    "Save the zip to Files and tap it once to unzip.",
                ],
                pickTitle: "Choose folder",
                alreadyImported: held > 0,
                showsMessagesToggle: true) { importing = true }
            BridgeSyncStatusRows(proof: result)
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
            DSSlabNote(text: "Your archive names the post, not the person, and your reply, not the one it answered. This asks X for both.", plain: true)
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

    /// The security-scoped grant covers the picked folder for as long as
    /// access is held, and the importer reads several files from inside it — so
    /// the read must finish before the `defer` releases the grant.
    ///
    /// That used to mean this had to be SYNCHRONOUS. It doesn't (2026-08-05,
    /// prd §310): awaiting here holds the grant across the suspension exactly
    /// as a synchronous read held it across the call, because `defer` fires
    /// when the function returns and not when it suspends. What must never
    /// happen is handing the URL to a task that outlives this scope — which is
    /// still true, and still the reason the await is here rather than detached.
    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = await XArchiveImport.run(folder: url, context: modelContext,
                                                 progress: { count in
            // A running count in the status row the receipt will replace — a
            // large archive lands in chunks now (prd §310), and without this
            // the stretch between the tap and the receipt says nothing at all.
            result = .says(String(localized: "\(count) landed…"))
        })
        if summary.failed {
            result = .failed(String(localized: "Couldn't read that folder. Pick the folder you unzipped — the one containing data."))
            return
        }
        DSHaptic.success()
        // The whole screen's corpus reading, not just the face queue — `held`
        // is what collapses the archive block now, so a screen that only
        // refreshed `pending` would leave the tutorial open after a successful
        // import until the next visit.
        reread()
        result = summary.imported > 0 ? .says(landedLine(summary)) : .says(nothingNewLine(summary))
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) in")
            : String(localized: "Imported just now")
        store.registerConnected(id: "x", name: "X", proof: proof,
                                can: ["Imports the archive you choose."])
        // Lift the topic terms off what just landed, so the room's "What you
        // write about" map is there when they walk into it rather than a few
        // foregrounds later. Detached from the scoped-folder read above (it
        // touches only the store), and bounded — `BridgeRefresh` carries the
        // rest on later opens.
        if summary.posts + summary.replies > 0 {
            Task { @MainActor in
                _ = await ScreenshotTopics.healTopics(source: "X",
                                                      context: modelContext, limit: 400)
            }
        }
    }

    /// Names each category that actually landed rather than one total — posts
    /// and replies are your words while likes are someone else's, and a single
    /// number would hide that one half may be empty. Skipped reposts are said
    /// out loud for the same reason: a count that silently shrank would read as
    /// rows going missing.
    private func landedLine(_ summary: XArchiveImport.Summary) -> String {
        var parts: [String] = []
        if summary.posts > 0   { parts.append("\(summary.posts) posts") }
        if summary.replies > 0 { parts.append("\(summary.replies) replies") }
        if summary.liked > 0   { parts.append("\(summary.liked) liked") }
        // The categories nothing had ever read (2026-08-18, prd §396). Apps
        // get their own clause rather than folding into the total, because
        // nobody expects an archive to hold them at all — a person who reads
        // "11 connected apps" has learnt something before opening the room.
        if summary.apps > 0      { parts.append("\(summary.apps) connected apps") }
        if summary.community > 0 { parts.append("\(summary.community) from Communities") }
        var line = parts.joined(separator: " · ")
        if summary.skipped > 0  { line += " · \(summary.skipped) already here" }
        if summary.retweets > 0 { line += " · \(summary.retweets) reposts skipped" }
        // A capped archive says so on the screen that ran it, not only in the
        // receipt. Without it a truncated import and a complete one read
        // identically here, and this is the one moment the person could still
        // do something about it.
        if summary.dropped > 0 {
            line += " · \(summary.dropped) older not imported"
        }
        // The repairs say so (2026-08-13). A long post that arrived whole and
        // one that arrived clipped both count as one post, so without this the
        // person has no way to tell that the thing they'd most notice losing
        // came down intact — and, on a RE-import over a room landed before
        // this, no way to see that anything happened at all.
        if summary.longform > 0 {
            line += " · \(summary.longform) long posts in full"
        }
        // Videos say so for the same reason the long posts do: before
        // 2026-08-18 every one of them landed as a row saying "Photo" with
        // nothing in it, so on a RE-import over an older room this number is
        // the only sign the frames came down at all.
        if summary.videos > 0 {
            line += " · \(summary.videos) videos with a frame"
        }
        return line
    }

    private func nothingNewLine(_ summary: XArchiveImport.Summary) -> String {
        summary.skipped > 0
            ? "Nothing new — all \(summary.skipped) were already here."
            : "That archive had no posts or likes in it."
    }

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
