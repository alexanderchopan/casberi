import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The imported Instagram things already in the corpus — newest first. A
/// @Query so the list updates live after an import and the fetch runs once per
/// store change, not twice per body pass.
private let instagramRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Instagram" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

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
struct InstagramImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false
    /// How old this import is, and how much of it is here (2026-08-05,
    /// prd §310). Both read off the import RECEIPT and a count — no new field.
    @State private var staleness: String?
    @State private var held = 0

    @Query(instagramRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Instagram",
                mode: .oneTimeImport,
                intro: "Instagram has no live connection — download your export, bring it here, and search your captions, comments, saves and likes. Saved posts get their words and cover picture back from Instagram's own public pages.")
            // The way back to what just landed (§460). Gated on the corpus,
            // not a connection flag: an import has no live connection, so
            // "has anything arrived" is the only honest test of whether
            // there is a room worth opening.
            if !recent.isEmpty {
                RoomDoor(name: "Instagram", source: "Instagram")
                    .listRowSeparator(.hidden)
            }
            setupSection
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: recent.live)
                    .listRowSeparator(.hidden)
            }
            ImportUpkeepSection(source: "Instagram", held: held, staleness: staleness) { gone in
                reread()
                resultIsError = false
                result = String(localized: "\(gone) removed")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Instagram")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .onAppear { reread() }
        .dsScreenTitle("Instagram")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ImportArchiveSection(
                    source: "Instagram",
                    doorTitle: "Open Instagram",
                    doorURL: URL(string: "https://accountscenter.instagram.com/info_and_permissions/dyi/"),
                    // JSON is called out because the default is HTML, and an
                    // HTML export parses into nothing here. The REASON for that
                    // ("an HTML export can't be read") left the step in the §315
                    // pass and lives in `nothingNewLine` — the moment it can
                    // actually be acted on. A step says what to do; an error
                    // says why it didn't work.
                    steps: [
                        "Choose Download or transfer information, then Some of your information.",
                        "Tick Saved, Likes, Posts, Stories, Reels and Comments.",
                        "Set Format to JSON, not HTML, then Download to device.",
                        // "then pick the unzipped folder below" was the button
                        // beneath it read out loud (2026-07-31).
                        "They email a link in about an hour — unzip it in Files.",
                    ],
                    pickTitle: "Choose folder",
                    alreadyImported: held > 0,
                    showsMessagesToggle: true) { importing = true }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
            }
        }
        .dsSlabSection()
    }

    /// One re-read of what this screen shows about the corpus — on appear,
    /// after an import and after a removal, so the three can never disagree.
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "Instagram", context: modelContext)
        held = ImportRemoval.count(source: "Instagram", context: modelContext)
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

        let summary = await InstagramImport.run(folder: url, context: modelContext,
                                                 progress: { count in
            // A running count in the status row the receipt will replace — a
            // large archive lands in chunks now (prd §310), and without this
            // the stretch between the tap and the receipt says nothing at all.
            result = String(localized: "\(count) landed…")
            resultIsError = false
        })
        if summary.failed {
            result = String(localized: "Couldn't read that folder. Pick the folder you unzipped — the one containing your_instagram_activity.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        // `held` is what collapses the archive block now, so a screen that
        // didn't re-read it would leave the tutorial open after a successful
        // import until the next visit.
        reread()
        result = summary.imported > 0 ? landedLine(summary) : nothingNewLine(summary)
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) in")
            : String(localized: "Imported just now")
        store.registerConnected(id: "instagram", name: "Instagram", proof: proof,
                                can: ["Imports the export you choose."])
        // Lift the topic terms off what just landed, so the room's "What you
        // write about" map is there when they walk into it rather than a few
        // foregrounds later. Detached from the scoped-folder read above (it
        // touches only the store), and bounded — `BridgeRefresh` carries the
        // rest on later opens.
        if summary.posts + summary.comments > 0 {
            Task { @MainActor in
                _ = await ScreenshotTopics.healTopics(source: "Instagram",
                                                      context: modelContext, limit: 400)
            }
        }
    }

    /// Names each category that actually landed rather than one total — the
    /// counts differ in KIND (captions are text, saves are links), and a
    /// single number would hide that the text half may be empty.
    private func landedLine(_ summary: InstagramImport.Summary) -> String {
        var parts: [String] = []
        if summary.posts > 0    { parts.append("\(summary.posts) posts") }
        // The wordless half, named apart (2026-08-18, prd §389). A subset of
        // `posts`, never added to it — an export that is mostly photographs
        // otherwise reports one number that reads as captions.
        if summary.photos > 0   { parts.append("\(summary.photos) photos") }
        if summary.comments > 0 { parts.append("\(summary.comments) comments") }
        if summary.saved > 0    { parts.append("\(summary.saved) saved") }
        if summary.liked > 0    { parts.append("\(summary.liked) liked") }
        var landed = parts.joined(separator: " · ")
        if summary.skipped > 0 { landed += " · \(summary.skipped) already here" }
        // A capped import says so on the screen that ran it — this is the one
        // moment the person could still act on it (prd §309).
        if summary.dropped > 0 { landed += " · \(summary.dropped) older not imported" }
        return landed
    }

    private func nothingNewLine(_ summary: InstagramImport.Summary) -> String {
        summary.skipped > 0
            ? "Nothing new — all \(summary.skipped) were already here."
            : "That export had nothing in it. Check you ticked Saved, Likes, Posts, Stories, Reels or Comments — and chose JSON, not HTML, which can't be read."
    }
}
