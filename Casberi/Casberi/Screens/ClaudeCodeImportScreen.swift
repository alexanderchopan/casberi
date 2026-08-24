import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The imported Claude Code sessions already in the corpus — newest first. A
/// @Query so the list updates live after an import and the fetch runs once per
/// store change, not twice per body pass.
private let claudeCodeRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Claude Code" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Claude Code, connected — by import, and by a folder rather than a file.
///
/// The transcripts are already on this Mac: `~/.claude/projects` holds one
/// folder per project and one `.jsonl` per session. There is nothing to
/// request and nothing to wait for, which is why this screen has no door out
/// to anybody's settings page and no 24-hour warning — the whole tutorial is
/// "point at the folder". Picking either the `projects` directory or a single
/// project folder works, so the steps don't have to explain the difference.
///
/// Safe to re-run, and worth re-running: a session that gained turns since the
/// last import is updated in place rather than skipped.
struct ClaudeCodeImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: String?
    @State private var resultIsError = false

    @Query(claudeCodeRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Claude Code",
                mode: .oneTimeImport,
                intro: "Claude Code keeps every session as a file on this Mac — point at the folder and each one becomes searchable, whole.")
            // The way back to what just landed (§460). Gated on the corpus,
            // not a connection flag: an import has no live connection, so
            // "has anything arrived" is the only honest test of whether
            // there is a room worth opening.
            if !recent.isEmpty {
                RoomDoor(name: "Claude Code", source: "Claude Code")
                    .listRowSeparator(.hidden)
            }
            setupSection
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: recent.live)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Claude Code")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Claude Code")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    /// One verb and the two lines it takes to reach it. `~/.claude` is hidden
    /// in the Files picker, so the shortcut to reveal it is a step — without it
    /// the folder is unreachable from the one control this screen has, which
    /// would make the whole screen a dead end.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                BridgeStepLines(steps: ["Open Files and press Command-Shift-Period to show hidden folders.",
                                        "Pick .claude → projects, or one project folder."],
                                startingAt: 1)
                DSSlabButton(title: "Choose folder", systemImage: "folder") {
                    DSHaptic.tap()
                    importing = true
                }
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                DSSlabNote(text: "Re-import later and sessions that grew are updated, not duplicated.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Run

    /// The security-scoped grant covers the picked folder for as long as access
    /// is held, and the importer reads every transcript under it — so the read
    /// must finish before the `defer` releases the grant. Awaiting holds the
    /// grant across the suspension exactly as a synchronous read held it across
    /// the call, because `defer` fires when the function returns and not when
    /// it suspends (prd §310). What must never happen is handing the URL to a
    /// task that outlives this scope.
    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = await ClaudeCodeImport.run(folder: url, context: modelContext,
                                                 progress: { count in
            result = String(localized: "\(count) landed…")
            resultIsError = false
        })
        if summary.failed {
            result = String(localized: "No sessions in that folder. Pick .claude/projects, or one project folder inside it.")
            resultIsError = true
            return
        }
        resultIsError = false
        DSHaptic.success()
        result = summary.landed > 0 ? landedLine(summary) : nothingNewLine(summary)
        let proof = summary.landed > 0
            ? String(localized: "\(summary.landed) sessions in")
            : String(localized: "Imported just now")
        store.registerConnected(id: "claudecode", name: "Claude Code", proof: proof,
                                can: ["Imports the session transcripts you choose."])
    }

    /// New sessions and grown ones are counted apart, because they are
    /// different facts: one is history arriving, the other is history catching
    /// up, and a single total would hide a re-import that found nothing new but
    /// updated forty conversations.
    ///
    /// A CAPPED import says so here as well as in the return value — this is
    /// the one moment the person could still act on it, and without the clause
    /// a truncated import reads word for word like a complete one (§307).
    private func landedLine(_ summary: ClaudeCodeImport.Summary) -> String {
        var parts: [String] = []
        if summary.imported > 0 { parts.append("\(summary.imported) sessions") }
        if summary.healed > 0   { parts.append("\(summary.healed) updated") }
        if summary.projects > 0 { parts.append("\(summary.projects) projects") }
        var line = parts.joined(separator: " · ")
        if summary.skipped > 0 { line += " · \(summary.skipped) already here" }
        if summary.dropped > 0 { line += " · \(summary.dropped) older not imported" }
        return line
    }

    private func nothingNewLine(_ summary: ClaudeCodeImport.Summary) -> String {
        var line = summary.skipped > 0
            ? String(localized: "Nothing new — all \(summary.skipped) sessions were already here.")
            : String(localized: "No sessions in that folder.")
        if summary.dropped > 0 {
            line += String(localized: " \(summary.dropped) older not imported.")
        }
        return line
    }
}
