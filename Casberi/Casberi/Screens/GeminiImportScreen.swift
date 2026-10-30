import SwiftUI
import SwiftData

/// Gemini, connected by signing in on gemini.google.com (prd §1627), as
/// ChatGPT is (§1623): Google's own sign-in in the sheet, which holds inside
/// the app's web view (measured), and Gemini answers in the person's own
/// Gemini (`GeminiWeb`). The Google key of §871 and the Takeout import are
/// gone from this page, as they went from ChatGPT's. A key already stored
/// keeps answering until Disconnect; prompts imported before stay, and More
/// still removes them.
struct GeminiImportScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var result: BridgeProof?
    @State private var staleness: String?
    @State private var held = 0
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?
    /// Mirrored rather than read in a body: `AgentKey.isConfigured` is a
    /// `SecItemCopyMatching` round trip, and a Keychain read in a body is
    /// what build 525 paid for (prd §628).
    @State private var connected = AgentKey.isConfigured(.google)

    var body: some View {
        AccountPage(
            name: "Gemini", seatID: "gemini", source: "Gemini",
            state: AccountPageState.of(name: "Gemini", seatID: "gemini",
                                       connected: connected, store: store),
            mode: .signIn,
            lands: true,
            cardSheet: { id in
                guard id == "geminiSignIn" else { return AnyView(EmptyView()) }
                return AnyView(WebSessionSignInSheet(seat: .gemini, onDone: finishSignIn))
            },
            tiles: connected ? [] : [
                AccountTile(id: "signIn", label: String(localized: "Sign in"),
                            glyph: "person.badge.key", act: startSignIn),
            ],
            signIn: startSignIn,
            teardown: {
                // Chats imported before are the person's own and stay;
                // `ImportUpkeepSection` is where they go.
                AgentKey.clear(.google)
                connected = false
            },
            sheet: $sheet,
            act: {
                if connected {
                    AgentActiveStatusRow(provider: .google)
                } else {
                    BridgeSyncStatusRows(proof: result)
                }
            },
            more: {
                if held > 0 {
                    ImportUpkeepSection(source: "Gemini", held: held,
                                        staleness: staleness, plain: true) { gone in
                        reread()
                        result = .says(String(localized: "\(gone) removed"))
                    }
                }
            },
            keySheet: { EmptyView() }
        )
        .onAppear { reread() }
    }

    private func reread() {
        staleness = ImportRemoval.stalenessLine(source: "Gemini", context: modelContext)
        held = ImportRemoval.count(source: "Gemini", context: modelContext)
    }

    private func startSignIn() {
        DSHaptic.tap()
        result = nil
        sheet = .card(id: "geminiSignIn")
    }

    /// gemini.google.com said the jar is signed in (`WebSession.verify`), and
    /// the sheet kept the mark: Gemini answers through the person's own chats.
    private func finishSignIn() {
        guard WebSession.signedIn(.gemini) else { return }
        AgentKey.activate(.google)
        connected = true
        DSHaptic.success()
        result = .connected(String(localized: "pick Gemini when you ask."))
        store.registerConnected(id: "gemini", name: "Gemini",
                                proof: String(localized: "Signed in on gemini.google.com"),
                                can: ["Answers in your own Gemini — only when you ask.",
                                      "Sends only what you type, never what you keep."])
    }
}
