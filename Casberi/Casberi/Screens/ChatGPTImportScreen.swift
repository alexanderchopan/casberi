import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// ChatGPT, connected — by import. The steps to get the export are stated
/// plainly (they happen on OpenAI's side; there is no live read to offer),
/// then one button picks `conversations.json` and the history lands as chat
/// things. Safe to re-run: conversations dedupe on their id.
struct ChatGPTImportScreen: View {
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
            name: "ChatGPT", seatID: "gpt", source: "ChatGPT",
            // An import has no live connection, so "is anything here" is the
            // only honest test of whether this seat is connected at all.
            state: AccountPageState.of(name: "ChatGPT", seatID: "gpt",
                                       connected: held > 0, store: store),
            mode: .oneTimeImport,
            teardown: {},
            sheet: $sheet,
            act: { setupBlock },
            more: {
                ImportUpkeepSection(source: "ChatGPT", held: held,
                                    staleness: staleness, plain: true) { gone in
                    reread()
                    result = .says(String(localized: "\(gone) removed"))
                }
            },
            keySheet: { EmptyView() }
        )
        .onAppear { reread() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). The export happens on OpenAI's side; the pick is the one
    /// thing this screen actually does, so it wears the filled slab.
    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ImportArchiveSection(
                source: "ChatGPT",
                steps: ["In ChatGPT, open Settings → Data controls → Export data.",
                        "OpenAI emails a link — unzip it in Files."],
                pickTitle: "Choose conversations.json",
                pickIcon: "square.and.arrow.down",
                alreadyImported: held > 0) { importing = true }
            BridgeSyncStatusRows(proof: result)
            // "One-time import — re-importing later adds only what's new."
            // moved out rather than being reworded: `ImportUpkeepSection`'s
            // own footer already says an import can be run again and what
            // that brings back, and §315 gives this screen one sentence.
        }
    }

    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "ChatGPT", context: modelContext)
        held = ImportRemoval.count(source: "ChatGPT", context: modelContext)
    }

    // MARK: - Run

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url) else {
            result = .failed(String(localized: "Couldn't read that file. Pick conversations.json from the unzipped export."))
            return
        }
        let summary = ChatGPTImport.run(data: data, context: modelContext)
        if summary.failed {
            result = .failed(String(localized: "That file isn't a ChatGPT export. Pick conversations.json."))
            return
        }
        DSHaptic.success()
        reread()
        result = .says(summary.imported > 0
            ? (summary.skipped > 0
               ? String(localized: "\(summary.imported) chats in · \(summary.skipped) already here")
               : String(localized: "\(summary.imported) chats in"))
            : String(localized: "Nothing new — all \(summary.skipped) chats were already here."))
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) chats in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "gpt", name: "ChatGPT", proof: proof,
                                can: ["Imports the chats you export."])
    }
}
