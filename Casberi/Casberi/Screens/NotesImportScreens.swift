import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// The "Your notes" group's three screens (prd 55). Two are the ChatGPT
// import pattern (Day One's JSON, Apple Journal's export folder); the third
// is the share-path explainer — Apple Notes has no export and no API, so
// the honest screen teaches the one sanctioned route and opens Notes.

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
                intro: "Day One has no live connection — export your journal, bring it here, and every entry becomes searchable on the day you wrote it. Re-import any time for what's new.")
            // The third step was "Pick the .json inside below", above a button
            // titled "Choose your Day One .json" (§220, 2026-07-31).
            ImportStepsCard("Get your export", [
                "In Day One, open Settings → Import/Export → Export → JSON.",
                "Save the zip to Files and tap it once to unzip.",
            ])
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ImportPickRow(label: "Choose your Day One .json") { importing = true }
                    BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                    DSSlabNote(text: "Photos stay in the export for now.")
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
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url) else {
            result = String(localized: "Couldn't read that file. Pick the .json from the unzipped export.")
            resultIsError = true
            return
        }
        let summary = DayOneImport.run(data: data, context: modelContext)
        if summary.failed {
            result = String(localized: "That file isn't a Day One export. Pick the .json inside the unzipped folder.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = summary.imported > 0
            ? (summary.skipped > 0
               ? String(localized: "\(summary.imported) entries in · \(summary.skipped) already here")
               : String(localized: "\(summary.imported) entries in"))
            : String(localized: "Nothing new — all \(summary.skipped) entries were already here.")
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) entries in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "dayone", name: "Day One", proof: proof,
                                can: ["Imports the journal you export.",
                                      "Read-only — nothing leaves \(DS.device)."])
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
                intro: "Journal has no live connection — export it from Settings, bring it here, and every entry becomes searchable on the day you wrote it. Re-import any time for what's new.")
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
                    DSSlabNote(text: "Photos stay in the export for now.")
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
        result = summary.imported > 0
            ? (summary.skipped > 0
               ? String(localized: "\(summary.imported) entries in · \(summary.skipped) already here")
               : String(localized: "\(summary.imported) entries in"))
            : String(localized: "Nothing new — all \(summary.skipped) entries were already here.")
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) entries in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "journal", name: "Apple Journal", proof: proof,
                                can: ["Imports the journal you export.",
                                      "Read-only — nothing leaves \(DS.device)."])
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
                intro: "Apple offers no export and no read API for Notes, so there is nothing to connect. Share a note to Casberi and it lands in your feed, findable like everything else.")
            ImportStepsCard("How notes come in", [
                "Open a note in Apple Notes.",
                "Tap share, then Casberi.",
                "It lands in your feed as a note — findable like everything else.",
            ])
            Section {
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
            } footer: {
                // Where they land is step 3's job ("It lands in your feed as a
                // note"); this footer only has to say why one at a time
                // (2026-07-31).
                Text("Apple offers no export for Notes, so they arrive one at a time, as you share them.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
                intro: "Export your bookmarks from any browser, bring the file here, and they become findable links — folders become tags. Re-import any time for what's new.")
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
            ImportPickRow(label: "Reading List only (\(parsed.readingListCount))") {
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
