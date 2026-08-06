import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The TikTok things already in the corpus — newest first, so an import's
/// result is visible on the screen that ran it.
private let tiktokRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "TikTok" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

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
struct TikTokImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false
    /// How old this import is, and how much of it is here (2026-08-05,
    /// prd §310). Both read off the import RECEIPT and a count — no new field.
    @State private var staleness: String?
    @State private var held = 0
    @State private var removing = false
    @State private var confirmRemove = false
    @State private var fetching = false
    @State private var pending = 0

    @Query(tiktokRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "TikTok")
            // "JSON" is called out because the picker defaults to TXT, and a
            // TXT export parses into nothing here — a silent zero that reads
            // as a broken importer rather than as the wrong format (the
            // lesson §245 paid for with Instagram's HTML default).
            ImportStepsCard("Get your export", [
                "In TikTok, open Settings and privacy, then Account, then Download your data.",
                "Set the format to JSON — a TXT export can't be read. Tap Select all, then Request data.",
                "TikTok takes up to 4 days, then the link works for 4 days. Save the file to Files.",
            ])
            pickSection
            upkeepSection
            if pending > 0 { facesSection }
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: Array(recent.live))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "TikTok")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("TikTok")
        // Both, because the JSON download arrives sometimes as a bare file and
        // sometimes zipped around one — and which the person picks shouldn't be
        // something this screen has to explain.
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json, .folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
        .onAppear {
            staleness = ImportRemoval.stalenessLine(source: "TikTok", context: modelContext)
            held = ImportRemoval.count(source: "TikTok", context: modelContext)
            pending = TikTokImport.pendingFaceCount(context: modelContext)
        }
    }

    private var pickSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ImportPickRow(label: "Choose export") { importing = true }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                // The export's own split, stated plainly — the §245 rule. The
                // failure this prevents is a person importing their saves,
                // searching for the recipe they bookmarked, and finding
                // nothing because the words were never in the file.
                DSSlabNote(text: "One-time import — re-importing later adds only what's new. Your captions and comments become searchable text. Saved and liked videos arrive as links: TikTok's export has nobody else's captions in it.")
            }
        }
        .dsSlabSection()
    }

    /// The second act. Only ever on screen when there is genuinely something
    /// waiting — an empty queue shows no button rather than a dead one.
    private var facesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: fetching ? "Naming videos…" : "Name \(pending) videos",
                             systemImage: "arrow.down.circle",
                             busy: fetching,
                             enabled: !fetching) {
                    DSHaptic.tap()
                    Task { await runFetch() }
                }
                DSSlabNote(text: "Your saves arrive as bare links. This asks TikTok what each one is — the caption, who made it, the cover picture. No account, no key, and no rush: unlike the export, the videos don't expire.")
            }
        }
        .dsSlabSection()
    }


    /// How old this import is, and the way back out (2026-08-05, prd §310).
    ///
    /// Both halves exist because the caps moved. A room frozen six months ago
    /// reads exactly like a current one — there is no live read behind this
    /// seat and never will be, so the only remedy is a fresh export and the
    /// copy says so. And a decade landed in one tap needs a way back out that
    /// isn't "delete everything you own".
    ///
    /// The removal is DESTRUCTIVE and confirms first, naming the real number.
    /// It is also completely recoverable by repeating the import, which is
    /// what makes a plain confirm the right weight rather than a typed name.
    @ViewBuilder
    private var upkeepSection: some View {
        if staleness != nil || held > 0 {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if let staleness { DSSlabNote(text: staleness) }
                    if held > 0 {
                        DSSlabButton(title: removing
                                        ? String(localized: "Removing…")
                                        : String(localized: "Remove all \(held) imported things"),
                                     systemImage: "trash",
                                     busy: removing,
                                     enabled: !removing) {
                            DSHaptic.tap()
                            confirmRemove = true
                        }
                        DSSlabNote(text: "Removes only what came from TikTok. Everything else stays, and importing again brings it all back.")
                    }
                }
            }
            .dsSlabSection()
            .confirmationDialog("Remove all \(held) things from TikTok?",
                                isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove \(held) things", role: .destructive) {
                    Task { await runRemove() }
                }
                Button("Keep them", role: .cancel) { }
            } message: {
                Text("They came from an export, so importing again brings them back.")
            }
        }
    }

    private func runRemove() async {
        removing = true
        defer { removing = false }
        let gone = await ImportRemoval.removeAll(source: "TikTok", context: modelContext)
        held = ImportRemoval.count(source: "TikTok", context: modelContext)
        staleness = ImportRemoval.stalenessLine(source: "TikTok", context: modelContext)
        DSHaptic.success()
        resultIsError = false
        result = String(localized: "\(gone) removed")
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
            result = String(localized: "\(count) landed…")
            resultIsError = false
        })
        if summary.failed {
            result = String(localized: "Couldn't read that — pick the user_data_tiktok.json file, or the folder holding it. A TXT export can't be read.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        pending = TikTokImport.pendingFaceCount(context: modelContext)
        result = summary.imported > 0 ? landedLine(summary) : nothingNewLine(summary)

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
            result = String(localized: "Couldn't reach TikTok — the videos are still saved, so try naming them again later.")
            resultIsError = true
            return
        }
        resultIsError = false
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
        result = line
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
