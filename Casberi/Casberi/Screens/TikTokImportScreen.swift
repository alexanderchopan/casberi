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
            runImport(url)
        }
        .onAppear { pending = TikTokImport.pendingFaceCount(context: modelContext) }
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

    // MARK: - Run

    /// Synchronous on purpose. The security-scoped grant covers the pick for as
    /// long as access is held, and the importer reads the file from inside it —
    /// so the read must finish before the `defer` releases the grant, not be
    /// handed to a task that outlives it.
    private func runImport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = TikTokImport.run(file: url, context: modelContext)
        if summary.failed {
            result = String(localized: "Couldn't read that — pick the user_data_tiktok.json file, or the folder holding it. A TXT export can't be read.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        pending = TikTokImport.pendingFaceCount(context: modelContext)
        result = summary.imported > 0 ? landedLine(summary) : nothingNewLine(summary)

        let proof = summary.imported > 0 ? "\(summary.imported) in" : "Imported just now"
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
        // A miss is usually a video its creator deleted, which is worth saying
        // rather than reporting as a failure — the row is still a real thing
        // that was really saved.
        result = outcome.missed > 0
            ? "\(outcome.named) named · \(outcome.missed) gone from TikTok"
            : "\(outcome.named) named"
    }

    /// Names each category that actually landed rather than one total — the
    /// counts differ in KIND (captions are text, saves are links), and a single
    /// number would hide that the text half may be empty.
    private func landedLine(_ summary: TikTokImport.Summary) -> String {
        var parts: [String] = []
        if summary.posts > 0    { parts.append("\(summary.posts) posts") }
        if summary.comments > 0 { parts.append("\(summary.comments) comments") }
        if summary.saved > 0    { parts.append("\(summary.saved) saved") }
        if summary.liked > 0    { parts.append("\(summary.liked) liked") }
        let landed = parts.joined(separator: " · ")
        return summary.skipped > 0 ? "\(landed) · \(summary.skipped) already here" : landed
    }

    private func nothingNewLine(_ summary: TikTokImport.Summary) -> String {
        summary.skipped > 0
            ? "Nothing new — all \(summary.skipped) were already here."
            : "That export had nothing in it. Check you tapped Select all, and chose JSON."
    }
}
