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
struct InstagramImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false

    @Query(instagramRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            setupSection
            if !recent.isEmpty {
                recentSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Instagram")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            runImport(url)
        }
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: "Open Instagram's download page", systemImage: "arrow.up.right") {
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
                    "Save the zip to Files and tap it once to unzip, then pick the unzipped folder below.",
                ], startingAt: 2)
                DSSlabButton(title: "Choose your export folder", systemImage: "folder") {
                    DSHaptic.tap()
                    importing = true
                }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                DSSlabNote(text: "One-time import — re-importing later adds only what's new. Your captions and comments land as text you can search. Saves and likes land as links named for who posted them: Instagram's export doesn't include other people's captions or pictures, so nothing here can.")
            }
        }
        .dsSlabSection()
    }

    private var recentSection: some View {
        Section {
            ForEach(recent) { thing in
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if !thing.content.isEmpty {
                        Text(thing.content)
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                .dsListCardRow()
            }
        } header: {
            Text("Imported").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    // MARK: - Run

    /// Synchronous on purpose. The security-scoped grant covers the picked
    /// folder for as long as access is held, and the importer reads several
    /// files from inside it — so the read must finish before the `defer`
    /// releases the grant, not be handed to a task that outlives it.
    private func runImport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = InstagramImport.run(folder: url, context: modelContext)
        if summary.failed {
            result = String(localized: "Couldn't read that folder. Pick the folder you unzipped — the one containing your_instagram_activity.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = summary.imported > 0 ? landedLine(summary) : nothingNewLine(summary)
        let proof = summary.imported > 0 ? "\(summary.imported) in" : "Imported just now"
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
        let landed = parts.joined(separator: " · ")
        return summary.skipped > 0 ? "\(landed) · \(summary.skipped) already here" : landed
    }

    private func nothingNewLine(_ summary: InstagramImport.Summary) -> String {
        summary.skipped > 0
            ? "Nothing new — all \(summary.skipped) were already here."
            : "That export had nothing in it. Check you ticked Saved, Likes, Posts or Comments, and chose JSON."
    }
}
