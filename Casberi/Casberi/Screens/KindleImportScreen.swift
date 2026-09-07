import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Kindle, connected — by import of the device's own `My Clippings.txt`. Steps
/// happen on the Kindle and in Files; one button picks the file and highlights
/// land as notes. The ChatGPT/Day One import pattern.
struct KindleImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var importing = false
    @State private var result: BridgeProof?
    @State private var staleness: String?
    @State private var held = 0
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?


    var body: some View {
        AccountPage(
            name: "Kindle", seatID: "kindle", source: "Kindle",
            // An import has no live connection, so "is anything here" is the
            // only honest test of whether this seat is connected at all.
            state: AccountPageState.of(name: "Kindle", seatID: "kindle",
                                       connected: held > 0, store: store),
            mode: .oneTimeImport,
            teardown: {},
            sheet: $sheet,
            act: {
                ImportArchiveSection(
                    source: "Kindle",
                    steps: ["Plug your Kindle into \(DS.device)\(DS.isMac ? "" : " (or a Mac)") with its cable.",
                            "Open the Kindle's drive → documents → My Clippings.txt, and copy it to Files."],
                    pickTitle: "Choose My Clippings.txt",
                    pickIcon: "square.and.arrow.down",
                    alreadyImported: held > 0) { importing = true }
                BridgeSyncStatusRows(proof: result)
                // Kept: the upkeep line says an import can be re-run, it does
                // not say highlights arrive GROUPED BY BOOK, which is the
                // thing somebody is deciding about.
                DSSlabNote(text: "Highlights become findable notes, grouped by book.", plain: true)
            },
            more: {
                ImportUpkeepSection(source: "Kindle", held: held,
                                    staleness: staleness, plain: true) { gone in
                    reread()
                    result = .says(String(localized: "\(gone) removed"))
                }
            },
            keySheet: { EmptyView() }
        )
        .onAppear { reread() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.plainText, .text]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url) else {
            result = .failed(String(localized: "Couldn't read that file. Pick My Clippings.txt from your Kindle."))
            return
        }
        let summary = KindleImport.run(data: data, context: modelContext)
        if summary.failed {
            result = .failed(String(localized: "That file isn't a Kindle export. Pick My Clippings.txt from the Kindle's documents folder."))
            return
        }
        DSHaptic.success()
        reread()
        // The repair is REPORTED, never folded into "already here" (prd §366).
        // Every highlight imported before §366 kept only its first 80
        // characters, and this pass is the one thing that can give the rest
        // back — so a run that landed nothing new and restored three hundred
        // passages must not read as "nothing happened".
        let repaired = summary.healed > 0
            ? String(localized: " · \(summary.healed) restored in full")
            : ""
        result = .says(summary.imported > 0
            ? "\(summary.imported) highlights in\(summary.skipped > 0 ? " · \(summary.skipped) already here" : "")\(repaired)"
            : (summary.healed > 0
               ? String(localized: "\(summary.healed) highlights restored in full — they'd been stored clipped.")
               : "Nothing new — all \(summary.skipped) highlights were already here."))
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) highlights in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "kindle", name: "Kindle", proof: proof,
                                can: ["Imports the highlights you export.",
                                      "Read-only — nothing leaves \(DS.device)."])
    }
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "Kindle", context: modelContext)
        held = ImportRemoval.count(source: "Kindle", context: modelContext)
    }

}
