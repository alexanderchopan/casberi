import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The Snapchat things already in the corpus — newest first, so an import's
/// result is visible on the screen that ran it.
private let snapchatRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Snapchat" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Snapchat, connected — by import of the account's own data export.
///
/// Two acts, not one, and the split is the honest part: picking the folder
/// lands the saved chats and the memories immediately (fast, local, offline),
/// while fetching the memories' actual pictures is its own button because it
/// is hundreds of network requests against links that die 7 days after
/// Snapchat generated the export. A single "Import" button would either hide
/// that cost or refuse to admit the deadline.
struct SnapchatImportScreen: View {
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

    @Query(snapchatRecentDescriptor) private var recent: [Thing]

    var body: some View {
        BridgeSetupPage(name: "Snapchat") {
            // "Only saved chats exist" earns the second sentence: it is the
            // limit most likely to read as a bug, because a Snapchat user's
            // mental model is that they had far more conversation than this.
            BridgeSetupHeader(
                name: "Snapchat",
                mode: .oneTimeImport,
                intro: "Snapchat has no live connection — request your export, bring it here, and keep your saved chats and memories for good. Only saved chats exist: Snapchat deletes the rest when it's viewed.",
                connected: held > 0)
            // The way back to what just landed (§460). Gated on the corpus,
            // not a connection flag: an import has no live connection, so
            // "has anything arrived" is the only honest test of whether
            // there is a room worth opening.
            if !recent.isEmpty {
                RoomDoor(name: "Snapchat", source: "Snapchat")
                    .listRowSeparator(.hidden)
            }
            pickSection
            if pending > 0 { picturesSection }
            if !recent.isEmpty {
                RecentThingsSection(header: "Imported", things: Array(recent.live))
                    .listRowSeparator(.hidden)
            }
            // Snapchat computed `held` and `staleness` on appear from the day
            // §310 landed and rendered NEITHER — so it was the one import room
            // with no way back out and no word about its own age, while its
            // three siblings had both. Found while restyling the family
            // (prd §314): a screen that reads state and never draws it looks
            // exactly like a screen that has nothing to say.
            ImportUpkeepSection(source: "Snapchat", held: held, staleness: staleness) { gone in
                reread()
                result = .says(String(localized: "\(gone) removed"))
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
        .onAppear { reread() }
    }

    /// No door, deliberately — Snapchat's My Data page could not be reached
    /// from the host this was written on, and a door to a URL nobody has
    /// verified is exactly the dead control §83 bans. The step names the
    /// address instead, as it always did. Give it a door once someone has
    /// loaded the page and confirmed it, and add the host to the reach audit's
    /// non-reach denylist in the same commit.
    ///
    /// The third step was "Pick the unzipped folder below", above a button
    /// titled "Choose the export folder" (§220, 2026-07-31).
    private var pickSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ImportArchiveSection(
                    source: "Snapchat",
                    steps: [
                        "At accounts.snapchat.com, open My Data and submit a request (pick JSON).",
                        "They email a link in a few hours — unzip it in Files.",
                    ],
                    pickTitle: "Choose folder",
                    alreadyImported: held > 0) { importing = true }
                BridgeSyncStatusRows(proof: result)
            }
        }
        .dsSlabSection()
    }

    /// One re-read of what this screen shows about the corpus — on appear,
    /// after an import and after a removal, so the three can never disagree.
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "Snapchat", context: modelContext)
        held = ImportRemoval.count(source: "Snapchat", context: modelContext)
        pending = SnapchatImport.pendingMediaCount(context: modelContext)
    }

    /// The second act. Only ever on screen when there is genuinely something
    /// waiting — an empty queue shows no button rather than a dead one.
    private var picturesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: fetching ? "Fetching pictures…" : "Fetch \(pending) pictures",
                             systemImage: "arrow.down.circle",
                             busy: fetching,
                             enabled: !fetching) {
                    DSHaptic.tap()
                    Task { await runFetch() }
                }
                DSSlabNote(text: "Memories arrive as links that Snapchat kills 7 days after the export. Photos are fetched; videos stay as dated entries.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Run

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = await SnapchatImport.run(folder: url, context: modelContext)
        if summary.failed {
            result = .failed(String(localized: "No Snapchat export in that folder — pick the unzipped folder (it holds chat_history.json)."))
            return
        }
        DSHaptic.success()
        // `held` is what collapses the archive block now, so re-read all three
        // rather than only the media queue.
        reread()

        var parts: [String] = []
        if summary.chats > 0 { parts.append(String(localized: "\(summary.chats) chats in")) }
        if summary.healed > 0 { parts.append(String(localized: "\(summary.healed) updated")) }
        if summary.memories > 0 { parts.append(String(localized: "\(summary.memories) memories in")) }
        if parts.isEmpty {
            parts.append(String(localized: "Nothing new — all \(summary.skipped) were already here"))
        } else if summary.skipped > 0 {
            parts.append(String(localized: "\(summary.skipped) already here"))
        }
        if summary.dropped > 0 {
            parts.append(String(localized: "\(summary.dropped) older not imported"))
        }
        result = .says(parts.joined(separator: " · "))

        let landed = summary.chats + summary.memories
        let proof = landed > 0
            ? String(localized: "\(landed) in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "snapchat", name: "Snapchat", proof: proof,
                                can: ["Imports the saved chats and memories you export.",
                                      "Read-only — nothing leaves \(DS.device)."])
    }

    private func runFetch() async {
        fetching = true
        defer { fetching = false }
        let outcome = await SnapchatImport.fetchMedia(context: modelContext)
        pending = SnapchatImport.pendingMediaCount(context: modelContext)

        if outcome.expired {
            result = .failed(String(localized: "Snapchat's download links have expired — request a fresh export and import it again."))
            return
        }
        DSHaptic.success()
        result = outcome.failed > 0 ? .says("\(outcome.fetched) pictures in · \(outcome.failed) couldn't be fetched") : .says("\(outcome.fetched) pictures in")
    }
}
