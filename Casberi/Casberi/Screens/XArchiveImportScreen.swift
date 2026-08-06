import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The imported X things already in the corpus — newest first. A @Query so the
/// list updates live after an import and the fetch runs once per store change,
/// not twice per body pass.
private let xRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "X" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// X, connected — by import, the ChatGPT grade, because X has no free read of
/// any kind left (prd §280).
///
/// The folder pick and its two-level search are Instagram's, for Instagram's
/// reason: an archive scatters its categories across several files under
/// `data/`, and asking for each one would be several chances to pick wrong.
///
/// The note under the button names the BOOKMARKS GAP. That is the whole of why
/// it's there: bookmarks are the pile an X user would most expect to find in
/// this app, they have never been in the export, and a person who imports and
/// then can't find them would reasonably read that as a broken importer rather
/// than as a limit of what X hands over. Saying it before the tap is the
/// honesty rule, not hedging.
struct XArchiveImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var fetching = false
    @State private var pending = 0

    @Query(xRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "X")
            setupSection
            if pending > 0 { authorsSection }
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: recent.live)
                    .listRowSeparator(.hidden)
            }
        }
        .onAppear { pending = XArchiveImport.pendingFaceCount(context: modelContext) }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "X")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("X")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            runImport(url)
        }
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: "Open X settings", systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://x.com/settings/download_your_data") {
                        openURL(url)
                    }
                }
                // The wait is called out because it is genuinely long and
                // unlike every other importer here: X makes you re-enter your
                // password, then takes up to 24 hours. Someone who taps
                // "Choose folder" the same minute has nothing to pick, and
                // without this line that reads as the screen not working.
                BridgeStepLines(steps: [
                    "Tap Request archive and confirm your password.",
                    "X emails you when it's ready — usually within 24 hours.",
                    "Save the zip to Files and tap it once to unzip.",
                ], startingAt: 2)
                DSSlabButton(title: "Choose folder", systemImage: "folder") {
                    DSHaptic.tap()
                    importing = true
                }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                DSSlabNote(text: "One-time import — re-importing later adds only what's new. Your bookmarks can't come: X has never put them in the archive. Reposts are skipped — X stores them as someone else's words, cut short.")
            }
        }
        .dsSlabSection()
    }

    /// The second act (2026-08-05), TikTok's split for the same reason: the
    /// import above is instant and offline, this is one request per liked post.
    ///
    /// What it buys is narrower than TikTok's and worth stating plainly — a
    /// liked post already arrives wearing its own words, because `like.js`
    /// carries `fullText`. What the archive never carries is WHO WROTE IT, and
    /// without that the room can't answer whose posts you like, which is the
    /// one thing a decade of likes is actually shaped to say.
    private var authorsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: fetching ? "Finding authors…" : "Find authors for \(pending) likes",
                             systemImage: "person.crop.circle",
                             busy: fetching,
                             enabled: !fetching) {
                    DSHaptic.tap()
                    Task { await runFetch() }
                }
                DSSlabNote(text: "Your likes arrive with the post's words but no author — the archive only ever names the post. This asks X who wrote each one, so the room can show whose posts you like. No account, no key, and no rush: unlike the archive, the posts don't expire.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Run

    /// Synchronous on purpose. The security-scoped grant covers the picked
    /// folder for as long as access is held, and the importer reads several
    /// files from inside it — so the read must finish before the `defer`
    /// releases the grant, not be handed to a task that outlives it.
    private func runImport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = XArchiveImport.run(folder: url, context: modelContext)
        if summary.failed {
            result = String(localized: "Couldn't read that folder. Pick the folder you unzipped — the one containing data.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        pending = XArchiveImport.pendingFaceCount(context: modelContext)
        result = summary.imported > 0 ? landedLine(summary) : nothingNewLine(summary)
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
            result = String(localized: "Couldn't reach X — your likes are still here, so try finding their authors again later.")
            resultIsError = true
            return
        }
        resultIsError = false
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
        result = line
    }
}
