import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Gemini, connected — TWO FACETS ON ONE SEAT (prd §871), the same grade as
/// ChatGPT and Claude.
///
/// **By import**: the steps to get the export are stated plainly (they happen
/// on Google's side; there is no live read to offer), then one button picks
/// `MyActivity.json` and the history lands as chat things. Safe to re-run:
/// prompts dedupe on their timestamp + text.
///
/// **By key**: a Google key, pasted on this page rather than in Settings.
/// See `keyConfigured` for why the two are one seat and not two.
struct GeminiImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var result: BridgeProof?
    @State private var staleness: String?
    @State private var held = 0
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?
    /// THE SEAT'S SECOND FACET — a Google key (prd §871).
    ///
    /// Gemini is one of the three providers that had no seat of its own: the
    /// catalog tile of this name is an importer, so a Google key could
    /// only be pasted in Settings → Your key, which was the one account in
    /// the app connected somewhere other than its own page. It is the same
    /// agent either way — `AgentConversationLanding.source(for:)` returns
    /// `AgentProvider.agent`, so a conversation had on this key lands in
    /// this room beside an imported one (§839), and `FeedScreen`'s
    /// `resolveRoomAgent` matches the same string, so the key alone earns
    /// the room's Chat tile.
    ///
    /// Mirrored rather than read in a body: `AgentKey.isConfigured` is a
    /// `SecItemCopyMatching` round trip to securityd, and a Keychain read in
    /// a body is what build 525 paid for (CLAUDE.md, prd §628).
    @State private var keyConfigured = AgentKey.isConfigured(.google)
    @State private var keyDraft = ""
    @State private var keyChecking = false
    @State private var keyResult: BridgeProof?


    var body: some View {
        AccountPage(
            name: "Gemini", seatID: "gemini", source: "Gemini",
            // An import has no live connection, so "is anything here" is the
            // only honest test of whether this seat is connected at all.
            state: AccountPageState.of(name: "Gemini", seatID: "gemini",
                                       connected: held > 0 || keyConfigured, store: store),
            mode: .oneTimeImport,
            keyed: keyConfigured,
            teardown: {
                // The seat's only removable half. An import's things are the
                // person's own and stay; `ImportUpkeepSection` is where they
                // go.
                AgentKey.clear(.google)
                keyConfigured = false
            },
            sheet: $sheet,
            act: { actBlock },
            more: {
                ImportUpkeepSection(source: "Gemini", held: held,
                                    staleness: staleness, plain: true) { gone in
                    reread()
                    result = .says(String(localized: "\(gone) removed"))
                }
            },
            keySheet: { keyBlock }
        )
        .onAppear { reread() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await runImport(url) }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). The export happens on Google's side; the pick is the one
    /// thing this screen actually does, so it wears the filled slab.
    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "Gemini", context: modelContext)
        held = ImportRemoval.count(source: "Gemini", context: modelContext)
    }

    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ImportArchiveSection(
                source: "Gemini",
                doorTitle: "Get your export",
                doorURL: URL(string: "https://takeout.google.com"),
                steps: ["Deselect all → My Activity → Gemini Apps",
                        "Multiple formats → JSON → Export",
                        "Google emails a link — unzip it in Files."],
                pickTitle: "Choose MyActivity.json",
                pickIcon: "square.and.arrow.down",
                alreadyImported: held > 0) { importing = true }
            BridgeSyncStatusRows(proof: result)
        }
    }


    // MARK: - Run

    private func runImport(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url) else {
            result = .failed(String(localized: "Couldn't read that file. Pick MyActivity.json from the unzipped export."))
            return
        }
        let summary = GeminiImport.run(data: data, context: modelContext)
        if summary.failed {
            result = .failed(String(localized: "That file isn't a Gemini export. Pick MyActivity.json from your Takeout."))
            return
        }
        DSHaptic.success()
        reread()
        result = .says(summary.imported > 0
            ? "\(summary.imported) prompts in\(summary.skipped > 0 ? " · \(summary.skipped) already here" : "")"
            : "Nothing new — all \(summary.skipped) prompts were already here.")
        let proof = summary.imported > 0
            ? String(localized: "\(summary.imported) prompts in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "gemini", name: "Gemini", proof: proof,
                                can: ["Imports the activity you export."])
    }

    /// The page's act — the import, then the key.
    ///
    /// Two facets in one column, and the key half changes shape rather than
    /// doubling: with no key it is the door onto the "Your key" sheet, which
    /// is where the field lives for every other keyed seat; with one saved
    /// the chassis draws that door as the `Your key` row, so what stands
    /// here instead is what the key is DOING — the same three rows
    /// `VeniceSetupScreen` draws, plus the librarian's switch where it is
    /// this key that would be spent.
    @ViewBuilder private var actBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            setupBlock
            if keyConfigured {
                AgentActiveStatusRow(provider: .google)
                AgentModelRow(provider: .google)
                AgentSpendRow(provider: .google)
                AgentLibrarianRow(provider: .google)
            } else {
                DSSlabDoor(title: "Add your Google key",
                           detail: String(localized: "Chat with Gemini here"),
                           systemImage: "key") { sheet = .key }
            }
        }
    }

    /// The "Your key" sheet — one block for a first key and for a
    /// replacement, the family's shape (`VeniceSetupScreen`).
    ///
    /// The door is the console ROOT, not the keys sub-path. Every path under
    /// it answers from a client-routed app, so a sub-path cannot be confirmed
    /// from here, and Grok's own rule applies: a wrong deep link is worse
    /// than the root.
    @ViewBuilder private var keyBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            BridgeSetupCard(steps: [], numbered: false) {
                DSSlabButton(title: "Get your API key",
                             detail: AgentProvider.google.console,
                             systemImage: "arrow.up.right",
                             url: URL(string: "https://\(AgentProvider.google.console)"))
            }
            DSSlabField(placeholder: AgentProvider.google.placeholder, text: $keyDraft,
                        actionLabel: keyChecking ? "Checking…" : (keyConfigured ? "Update" : "Connect"),
                        secure: true,
                        isArmed: !keyChecking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                        action: saveKey)
            BridgeSyncStatusRows(proof: keyResult)
            DSSlabNote(text: "Google bills you directly.", plain: true)
        }
    }

    /// Saves only after Google accepts the key — no dead key in the
    /// Keychain claiming a capability it cannot deliver (the honesty rule).
    private func saveKey() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        keyChecking = true
        keyResult = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.check(candidate, provider: .google)
            keyChecking = false
            guard outcome == .accepted else {
                // Four ways this can fail and four sentences for them
                // (`AgentKeyCheck`) — a rate limit, a blocked account and a
                // dropped connection are not the key.
                keyResult = .failed(outcome.line(for: .google))
                return
            }
            AgentKey.set(candidate, for: .google)
            keyConfigured = true
            keyDraft = ""
            DSHaptic.success()
            keyResult = .connected(String(localized: "Gemini answers on this key now."))
            store.registerConnected(id: "gemini", name: "Gemini",
                                    proof: String(localized: "Key in the Keychain"))
        }
    }
}
