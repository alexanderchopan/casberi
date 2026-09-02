import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// The "Your notes" group's three screens (prd 55). Two are the ChatGPT
// import pattern (Day One's JSON, Apple Journal's export folder); the third
// is the share-path explainer — Apple Notes has no export and no API, so
// the honest screen teaches the one sanctioned route and opens Notes.

/// What one journal import really did, in one line (prd §398, 2026-08-17).
///
/// Three numbers, and the third is why this exists: `dropped` is history the
/// cap REFUSED, and until this date both importers applied a 500-entry cap and
/// said nothing about it — so a fifteen-year journal read "412 entries in" and
/// looked complete. It is named apart from `skipped` because they are opposite
/// facts: "already here" is a re-import working, "not imported" is a run that
/// left the oldest years on disk.
///
/// Shared by both screens rather than written twice: the two importers have the
/// same `Summary` and the same cap, so a divergence here could only ever be a
/// mistake. Mirrors `XArchiveImportScreen`'s wording exactly — the person
/// reading it may have imported both.
func journalImportReceipt(_ summary: DayOneImport.Summary) -> String {
    guard summary.imported > 0 else {
        return summary.dropped > 0
            ? String(localized: "Nothing new — all \(summary.skipped) entries were already here · \(summary.dropped) older not imported")
            : String(localized: "Nothing new — all \(summary.skipped) entries were already here.")
    }
    var line = String(localized: "\(summary.imported) entries in")
    if summary.skipped > 0 {
        line += String(localized: " · \(summary.skipped) already here")
    }
    if summary.dropped > 0 {
        line += String(localized: " · \(summary.dropped) older not imported")
    }
    return line
}

/// Lift the topic terms off what just landed, so the room's "What you write
/// about" map is there when they walk into it rather than a few foregrounds
/// later (`XArchiveImportScreen`'s pass, prd §398).
///
/// Bounded, and `BridgeRefresh` carries the rest on later opens — which is the
/// half that matters for these two rooms, since a re-import skips every entry
/// already deduped and so can never reach the years imported before this
/// existed.
@MainActor
func journalHealTopics(source: String, landed: Int, context: ModelContext) {
    guard landed > 0 else { return }
    Task { @MainActor in
        _ = await ScreenshotTopics.healTopics(source: source, context: context, limit: 400)
    }
}

/// Day One, connected — by import. Steps happen in Day One's own settings;
/// one button picks the export's .json and entries land as notes.
struct DayOneImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false

    @Query(dayOneRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Day One",
                mode: .oneTimeImport,
                intro: "Day One has no live connection — export your journal, bring it here, and every entry becomes searchable on the day you wrote it.")
            // The way back to what just landed (§460). Gated on the corpus:
            // an import has no live connection to gate on.
            if !recent.isEmpty {
                RoomDoor(name: "Day One", source: "Day One")
                    .listRowSeparator(.hidden)
            }
            // The third step was "Pick the .json inside below", above a button
            // titled "Choose your Day One .json" (§220, 2026-07-31).
            ImportStepsCard("Get your export", [
                "In Day One, open Settings → Import/Export → Export → JSON.",
                "Save the zip to Files and tap it once to unzip.",
            ])
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ImportPickRow(label: "Choose your Day One export") { importing = true }
                    BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                    // The one fine print that changes what somebody DOES
                    // (§315): the folder and the .json both import, and only the
                    // folder can reach `photos/`.
                    DSSlabNote(text: "Pick the folder, not the .json, to bring your photos too.")
                }
            }
            .dsSlabSection()
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: Array(recent))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Day One")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Day One")
        // FOLDER OR FILE since 2026-08-17 (prd §398). The `.json` alone still
        // works and still imports every entry — but a scoped grant on a file
        // cannot read the `photos/` directory beside it, so the folder is the
        // only pick that can bring the pictures. Accepting both means nobody's
        // existing habit breaks and the better pick is the one the row names.
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json, .folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        // The folder is the media root when they picked one. For a `.json` pick
        // the parent is passed anyway and simply fails to read — every path in
        // `ImportMedia` yields nil rather than throwing, so the entries land
        // exactly as they did before and no branch is needed for the difference.
        let root = isFolder ? url : url.deletingLastPathComponent()
        guard let json = isFolder ? DayOneImport.findJSON(inFolder: url) : url,
              let data = await SecurityScopedFileReader.readData(at: json) else {
            result = String(localized: "Couldn't read that. Pick the unzipped export folder, or the .json inside it.")
            resultIsError = true
            return
        }
        let summary = await DayOneImport.run(data: data, context: modelContext, exportRoot: root)
        if summary.failed {
            result = String(localized: "That file isn't a Day One export. Pick the .json inside the unzipped folder.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = journalImportReceipt(summary)
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) entries in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "dayone", name: "Day One", proof: proof,
                                can: ["Imports the journal you export.",
                                      "Read-only — nothing leaves \(DS.device)."])
        journalHealTopics(source: "Day One", landed: summary.imported, context: modelContext)
    }
}

private let dayOneRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Day One" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Apple Journal, connected — by import of Journal's own export
/// (iOS 18+): profile button → Export produces a zip of per-entry pages.
struct JournalImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false

    @Query(journalRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Apple Journal",
                mode: .oneTimeImport,
                intro: "Journal has no live connection — export it from Settings, bring it here, and every entry becomes searchable on the day you wrote it.")
            // The way back to what just landed (§460). Gated on the corpus:
            // an import has no live connection to gate on.
            if !recent.isEmpty {
                RoomDoor(name: "Apple Journal", source: "Apple Journal")
                    .listRowSeparator(.hidden)
            }
            // The third step was "Pick the unzipped folder below", above a
            // button titled "Choose the export folder" (§220, 2026-07-31).
            ImportStepsCard("Get your export", [
                "In Journal, tap your profile picture → Export Journal.",
                "Save the zip to Files and tap it once to unzip.",
            ])
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ImportPickRow(label: "Choose the export folder") { importing = true }
                    BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                    // The note that sat here ("Photos stay in the export for
                    // now") is DELETED rather than reworded: it stopped being
                    // true when §398 landed the pictures, and unlike Day One's
                    // there is no choice left for fine print to govern — this
                    // screen only ever picks the folder.
                    
                }
            }
            .dsSlabSection()
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: Array(recent))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Apple Journal")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Apple Journal")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let summary = await JournalImport.run(folder: url, context: modelContext)
        if summary.failed {
            result = String(localized: "No journal pages in that folder — pick the unzipped export (it holds an Entries folder).")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = journalImportReceipt(summary)
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) entries in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "journal", name: "Apple Journal", proof: proof,
                                can: ["Imports the journal you export.",
                                      "Read-only — nothing leaves \(DS.device)."])
        journalHealTopics(source: "Apple Journal", landed: summary.imported, context: modelContext)
    }
}

private let journalRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Apple Journal" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Apple Notes — the share-path explainer, not a bridge (prd 55). Apple
/// offers no export and no read API for Notes, so there is nothing to
/// connect and this screen never registers a seat or claims a status. It
/// teaches the one sanctioned route and opens Notes; shared notes land as
/// your captures.
struct NotesShareScreen: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Apple Notes",
                mode: .onThisDevice,
                intro: "Apple offers no export and no read API for Notes, so there is nothing to connect. Share a note and it lands in your feed, findable like everything else.")
            ImportStepsCard("How notes come in", [
                "Open a note in Apple Notes.",
                "Tap share, then Casberi.",
                "It lands in your feed as a note — findable like everything else.",
            ])
            Section {
                // Gated 2026-08-14 (App Store review 2.1(a) on the Mac
                // build). Nothing claims `mobilenotes` on Mac Catalyst, so
                // this was a row that did nothing when clicked — the same
                // defect the review named, on the setup screen for the one
                // bridge whose whole instruction is "go to Notes".
                if HandOffState.installedSchemes.contains("mobilenotes") {
                    Button {
                        if let url = URL(string: "mobilenotes://") { openURL(url) }
                    } label: {
                        HStack(spacing: DS.Space.s3) {
                            // The list row's own chrome already says this is
                            // tappable — the chip previews no state, so it's
                            // neutral (`IconChip`, 2026-08-10, was tint).
                            IconChip(tone: DS.neutralBadge, size: 28, style: .wash) {
                                Image(systemName: "arrow.up.right").dsGlyph(15, weight: .regular)
                            }
                            Text("Open Notes")
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .dsListCardRow()
                }
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Apple Notes")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Apple Notes")
    }
}

/// Bookmarks, connected — by import of the SAME file Safari and Chrome both
/// write (prd §224). Reading List rides along as a folder inside a Safari
/// export, so once a file's parsed, a real Reading List folder earns its
/// own scoped button beside "All bookmarks" — a Chrome export simply never
/// shows one, no dead promise. Two phases on purpose (unlike Day One/
/// Journal's one-shot run): parsing never writes, so picking a scope after
/// the fact costs nothing extra, and picking the other scope later (dedupe
/// on URL) never doubles a row.
struct BookmarksImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var parsed: BookmarksImport.Parsed?
    @State private var result: String?
    @State private var resultIsError = false

    @Query(bookmarksRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Bookmarks",
                mode: .oneTimeImport,
                intro: "Export your bookmarks from any browser, bring the file here, and they become findable links — folders become tags.")
            // The way back to what just landed (§460). Gated on the corpus:
            // an import has no live connection to gate on.
            if !recent.isEmpty {
                RoomDoor(name: "Bookmarks", source: "Bookmarks")
                    .listRowSeparator(.hidden)
            }
            ImportStepsCard("Get your export", [
                "Chrome: chrome://bookmarks → ⋮ → Export bookmarks.",
                "Safari (Mac): File → Export Bookmarks…",
                // "then pick it below" was the button beneath it read out loud
                // (§220, 2026-07-31).
                "Save it to Files.",
            ])
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    pickRows
                    BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                }
            }
            .dsSlabSection()
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: Array(recent))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Bookmarks")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Bookmarks")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.html]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runParse(url) }
        }
    }

    private func runParse(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url),
              let p = BookmarksImport.parse(data: data), !p.entries.isEmpty else {
            result = String(localized: "That file isn't a bookmarks export. Pick the exported .html file.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = nil
        parsed = p
    }

    @ViewBuilder
    private var pickRows: some View {
        if let parsed, parsed.readingListCount > 0 {
            ImportPickRow(label: "Reading list only (\(parsed.readingListCount))") {
                importScope(parsed.entries.filter(\.isReadingList))
            }
            ImportPickRow(label: "All bookmarks (\(parsed.entries.count))") {
                importScope(parsed.entries)
            }
        } else if let parsed {
            ImportPickRow(label: "Import \(parsed.entries.count) bookmarks") {
                importScope(parsed.entries)
            }
        } else {
            ImportPickRow(label: "Choose your bookmarks export") { importing = true }
        }
    }

    private func importScope(_ entries: [BookmarksImport.Entry]) {
        let summary = BookmarksImport.land(entries, context: modelContext)
        if summary.failed {
            resultIsError = true
            result = String(localized: "Couldn't save those bookmarks.")
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = summary.imported > 0
            ? "\(summary.imported) bookmarks in\(summary.skipped > 0 ? " · \(summary.skipped) already here" : "")"
            : "Nothing new — all \(summary.skipped) bookmarks were already here."
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) bookmarks in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "bookmarks", name: "Bookmarks", proof: proof,
                                can: ["Imports the bookmarks you export.",
                                      "Read-only — nothing leaves \(DS.device)."])
    }
}

private let bookmarksRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Bookmarks" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

// MARK: - Shared rows (the import-screen grammar, extracted from ChatGPT's)

/// The numbered how-to card — every step in ONE list row (a VStack), so no
/// inter-row separator can be drawn between them. A Section of separate rows
/// leaks a hairline that survives row-level .listRowSeparator(.hidden) (SwiftUI
/// won't suppress the first separator after a section header). Design law: no
/// hairlines, zero exceptions.
/// The steps, plain (prd §218, 2026-07-25) — the card and its gray "Get your
/// export" label went with the rest of the setup-screen furniture. The steps
/// themselves are untouched: §186's ruling that they stay whole and visible
/// is why this is a de-furnishing, not a disclosure.
///
/// The `header` argument is kept and ignored on purpose: every call site
/// passes the same "Get your export", and removing the parameter would churn
/// six screens to delete one word each.
struct ImportStepsCard: View {
    let steps: [String]
    init(_ header: String, _ steps: [String]) { self.steps = steps }

    var body: some View {
        Section {
            BridgeStepLines(steps: steps, startingAt: 1)
        }
        .dsSlabSection()
    }
}

/// The pick, as the screen's one filled block — an import screen does exactly
/// one thing, and it should look like it (prd §218). It used to be a tinted
/// glyph beside plain body text, which read as a list row.
struct ImportPickRow: View {
    let label: String
    let action: () -> Void

    var body: some View {
        DSSlabButton(title: label, systemImage: "square.and.arrow.down") {
            DSHaptic.tap()
            action()
        }
    }
}
