import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// TikTok, connected — by import of the account's own data export, because
/// TikTok has no other door (prd §279).
///
/// Two acts, not one, and the split is the honest part: picking the file lands
/// everything immediately and touches no network at all, while giving the saved
/// videos their real faces is its own button because it is one request per
/// video against TikTok's servers. A single "Import" button would hide that
/// cost.
///
/// The one thing this screen says that its Snapchat sibling cannot: the face
/// fetch is under NO deadline. Snapchat's media links die 7 days after the
/// export is built, and TikTok's export link dies in 4 — but the VIDEOS it
/// names don't expire, so a library imported today can be given its faces
/// whenever. That is the whole pitch of importing at all, and it belongs on the
/// screen rather than only in the ledger.
///
/// AMENDED 2026-09-14 (prd §731): a SECOND door, §726's Instagram one seat
/// over. A sign-in inside this app, through `TikTokLiveLoginSheet`, reads the
/// person's own Activity inbox — likes, comments, follows — with their own
/// session cookies. The doors are uncoupled: the seat reads connected when
/// EITHER is open, and disconnecting clears only the live session.
struct TikTokImportScreen: View {
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
    /// The live door (prd §731), apart from the export.
    @State private var liveConnected = false
    @State private var liveSyncing = false
    @State private var liveResult: BridgeProof?
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?


    var body: some View {
        AccountPage(
            name: "TikTok", seatID: "tiktok", source: "TikTok",
            // Connected if EITHER door is open (prd §731).
            state: AccountPageState.of(name: "TikTok", seatID: "tiktok",
                                       connected: held > 0 || liveConnected, store: store),
            mode: .signIn,
            cardSheet: { _ in
                AnyView(TikTokLiveLoginSheet(onCaptured: {
                    liveConnected = true
                    Task { await syncLive() }
                }))
            },
            // Clears the LIVE half only — imported rows are untouched.
            teardown: { TikTokLiveAuth.clear() },
            sheet: $sheet,
            act: {
                liveBlock
                pickBlock
                if pending > 0 { facesBlock }
            },
            more: {
                ImportUpkeepSection(source: "TikTok", held: held,
                                    staleness: staleness, plain: true) { gone in
                    reread()
                    result = .says(String(localized: "\(gone) removed"))
                }
            },
            keySheet: { EmptyView() }
        )
        // Both, because the JSON download arrives sometimes as a bare file and
        // sometimes zipped around one — and which the person picks shouldn't be
        // something this screen has to explain.
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json, .folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
        .onAppear {
            reread()
            // The sweep's throttle, shared: opening the page counts as the
            // ten-minute read rather than adding one.
            if liveConnected, BridgeRefresh.dueForHeal("tiktok.live") {
                Task { await syncLive() }
            }
        }
    }

    /// The live door (prd §731) — likes, comments and follows as they happen,
    /// which no export can carry. First, because it is the news.
    @ViewBuilder private var liveBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if liveConnected {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "bell.fill")
                        .dsGlyph(17, weight: .medium)
                        .foregroundStyle(DS.tint)
                    Text(TikTokLiveAuth.username.map { "Signed in as @\($0)" }
                         ?? String(localized: "Live — your own account, signed in"))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            } else {
                DSSlabButton(title: "Connect your account",
                             systemImage: "bell.badge",
                             busy: false) { sheet = .card(id: "tiktokLive") }
            }
            BridgeSyncStatusRows(syncing: liveSyncing,
                                syncingLine: String(localized: "Checking TikTok…"),
                                proof: liveResult)
            DSSlabNote(text: "TikTok may ask you to confirm it was you.", plain: true)
        }
    }

    /// Runs the live read (prd §731). A refusal clears the session inside
    /// `refresh`, so the re-read below falls back to Connect.
    private func syncLive() async {
        guard !liveSyncing else { return }
        liveSyncing = true
        let added = await TikTokLive.refresh(context: modelContext)
        liveSyncing = false
        liveConnected = TikTokLiveAuth.connected
        guard let added else {
            liveResult = .failed(liveConnected
                ? String(localized: "Couldn't read TikTok — try again in a few minutes.")
                : String(localized: "TikTok signed this app out — tap Connect to sign in again."))
            return
        }
        liveResult = added > 0 ? .landed(added) : .upToDate
        let proof = added > 0 ? String(localized: "\(added) new") : String(localized: "Synced just now")
        if store.registerConnected(id: "tiktok", name: "TikTok", proof: proof,
                                   can: ["Reads your likes, comments and follows, with your own sign-in.",
                                         "Read-only — never posts, likes, or follows for you."]) {
            DSHaptic.success()
        }
    }

    /// No door: TikTok's export is requested inside TikTok's own app, not at a
    /// URL — so the steps number from 1 and the pick is the permanent verb.
    /// The block still collapses once something has been imported (prd §314).
    @ViewBuilder private var pickBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ImportArchiveSection(
                source: "TikTok",
                // "JSON" is called out because the picker defaults to TXT,
                // and a TXT export parses into nothing here — a silent zero
                // that reads as a broken importer rather than as the wrong
                // format (the lesson §245 paid for with Instagram's HTML
                // default).
                steps: [
                    "Settings and privacy → Account → Download",
                    "Format JSON, Select all, Request data",
                    "Ready in up to 4 days — save it to Files",
                ],
                pickTitle: "Choose export",
                pickIcon: "square.and.arrow.down",
                alreadyImported: held > 0) { importing = true }
            BridgeSyncStatusRows(proof: result)
        }
    }

    /// One re-read of what this screen shows about the corpus — on appear,
    /// after an import and after a removal, so the three can never disagree.
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "TikTok", context: modelContext)
        held = ImportRemoval.count(source: "TikTok", context: modelContext)
        pending = TikTokImport.pendingFaceCount(context: modelContext)
        liveConnected = TikTokLiveAuth.connected
    }

    /// The second act. Only ever on screen when there is genuinely something
    /// waiting — an empty queue shows no button rather than a dead one.
    @ViewBuilder private var facesBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabButton(title: fetching ? "Naming videos…" : "Name \(pending) videos",
                         systemImage: "arrow.down.circle",
                         busy: fetching,
                         enabled: !fetching) {
                DSHaptic.tap()
                Task { await runFetch() }
            }
        }
    }


    // MARK: - Run

    /// The security-scoped grant covers the pick for as long as access is
    /// held, and the importer reads the file from inside it — so the read must
    /// finish before the `defer` releases the grant.
    ///
    /// That used to mean this had to be SYNCHRONOUS. It doesn't (2026-08-05,
    /// prd §310): awaiting holds the grant across the suspension exactly as a
    /// synchronous read held it across the call, because `defer` fires when the
    /// function returns and not when it suspends. Handing the URL to a task
    /// that outlives this scope is still forbidden, and still the reason the
    /// await is here rather than detached.
    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = await TikTokImport.run(file: url, context: modelContext,
                                                 progress: { count in
            // A running count in the status row the receipt will replace — a
            // large archive lands in chunks now (prd §310), and without this
            // the stretch between the tap and the receipt says nothing at all.
            result = .says(String(localized: "\(count) landed…"))
        })
        if summary.failed {
            result = .failed(String(localized: "Couldn't read that — pick the user_data_tiktok.json file, or the folder holding it. A TXT export can't be read."))
            return
        }
        DSHaptic.success()
        // `held` is what collapses the archive block now, so re-read all three
        // rather than only the face queue.
        reread()
        result = summary.imported > 0 ? .says(landedLine(summary)) : .says(nothingNewLine(summary))

        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) in")
            : String(localized: "Imported just now")
        store.registerConnected(id: "tiktok", name: "TikTok", proof: proof,
                                can: ["Imports the export you choose.",
                                      "Read-only — nothing leaves \(DS.device) but the videos' own names."])
    }

    private func runFetch() async {
        fetching = true
        defer { fetching = false }
        let outcome = await TikTokImport.fetchFaces(context: modelContext)
        pending = TikTokImport.pendingFaceCount(context: modelContext)

        if outcome.unreachable {
            result = .failed(String(localized: "Couldn't reach TikTok — the videos are still saved, so try naming them again later."))
            return
        }
        DSHaptic.success()
        // "Gone" was a GUESS until 2026-08-05 (prd §309): every failure arrived
        // as one nil, so this line called any miss "gone from TikTok" without
        // ever having been told that. It is a measured fact now — TikTok
        // answered 404/410/403 — and a miss is separately an answer we could
        // not read, which is a different thing and says so.
        var line = String(localized: "\(outcome.named) named")
        if outcome.gone > 0 {
            line += String(localized: " · \(outcome.gone) gone or private")
        }
        if outcome.missed > 0 {
            line += String(localized: " · \(outcome.missed) unreadable")
        }
        result = .says(line)
    }

    /// Names each category that actually landed rather than one total — the
    /// counts differ in KIND (captions are text, saves are links), and a single
    /// number would hide that the text half may be empty.
    private func landedLine(_ summary: TikTokImport.Summary) -> String {
        var parts: [String] = []
        if summary.posts > 0    { parts.append(String(localized: "\(summary.posts) posts")) }
        if summary.comments > 0 { parts.append(String(localized: "\(summary.comments) comments")) }
        if summary.saved > 0    { parts.append(String(localized: "\(summary.saved) saved")) }
        if summary.liked > 0    { parts.append(String(localized: "\(summary.liked) liked")) }
        var landed = parts.joined(separator: " · ")
        if summary.skipped > 0 {
            landed += String(localized: " · \(summary.skipped) already here")
        }
        if summary.dropped > 0 {
            landed += String(localized: " · \(summary.dropped) older not imported")
        }
        return landed
    }

    private func nothingNewLine(_ summary: TikTokImport.Summary) -> String {
        summary.skipped > 0
            ? String(localized: "Nothing new — all \(summary.skipped) were already here.")
            : "That export had nothing in it. Check you tapped Select all, and chose JSON."
    }
}
