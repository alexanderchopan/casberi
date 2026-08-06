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
struct InstagramImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    /// Off by default, and off is the safety property — see `ImportOptions`.
    /// Bound straight to the shared key rather than mirrored into local state,
    /// so the switch and the importer can never disagree.
    @AppStorage(ImportOptions.messagesStorageKey) private var includeMessages = false
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false
    /// How old this import is, and how much of it is here (2026-08-05,
    /// prd §310). Both read off the import RECEIPT and a count — no new field.
    @State private var staleness: String?
    @State private var held = 0
    @State private var removing = false
    @State private var confirmRemove = false

    @Query(instagramRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "Instagram")
            setupSection
            upkeepSection
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: recent.live)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Instagram")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .onAppear {
            staleness = ImportRemoval.stalenessLine(source: "Instagram", context: modelContext)
            held = ImportRemoval.count(source: "Instagram", context: modelContext)
        }
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
                DSSlabButton(title: "Open Instagram", systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://accountscenter.instagram.com/info_and_permissions/dyi/") {
                        openURL(url)
                    }
                }
                // "JSON" is called out because the default is HTML, and an HTML
                // export parses into nothing here — a silent zero that reads
                // as a broken importer rather than as the wrong format.
                BridgeStepLines(steps: [
                    "Choose Download or transfer information, then Some of your information.",
                    "Tick Saved, Likes, Posts and Comments, then Download to device.",
                    "Set Format to JSON — an HTML export can't be read. Instagram emails a link within about an hour.",
                    // "then pick the unzipped folder below" was the button
                    // beneath it read out loud (2026-07-31).
                    "Save the zip to Files and tap it once to unzip.",
                ], startingAt: 2)
                // ABOVE the pick on purpose: this is a decision to make before
                // the import runs, not a preference to discover afterwards.
                Toggle(ImportOptions.messagesTitle, isOn: $includeMessages)
                    .dsText(.body17)
                DSSlabNote(text: ImportOptions.messagesNote)
                DSSlabButton(title: "Choose folder", systemImage: "folder") {
                    DSHaptic.tap()
                    importing = true
                }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                DSSlabNote(text: "One-time import — re-importing later adds only what's new. Instagram's export lists your saves and likes by handle and link, with no words in them. Casberi opens each saved post's own public page afterwards to read its caption, a few at a time, so you can search what was in them. A post that's since been deleted or made private stays a link.")
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
                        DSSlabNote(text: "Removes only what came from Instagram. Everything else stays, and importing again brings it all back.")
                    }
                }
            }
            .dsSlabSection()
            .confirmationDialog("Remove all \(held) things from Instagram?",
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
        let gone = await ImportRemoval.removeAll(source: "Instagram", context: modelContext)
        held = ImportRemoval.count(source: "Instagram", context: modelContext)
        staleness = ImportRemoval.stalenessLine(source: "Instagram", context: modelContext)
        DSHaptic.success()
        resultIsError = false
        result = String(localized: "\(gone) removed")
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
            : "That export had nothing in it. Check you ticked Saved, Likes, Posts or Comments, and chose JSON."
    }
}
