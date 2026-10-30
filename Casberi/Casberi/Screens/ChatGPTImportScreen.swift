import SwiftUI
import SwiftData

/// ChatGPT, connected by signing in on chatgpt.com (prd §1623), the way
/// §1619 connects Muse: OpenAI's own sign-in in the sheet, and ChatGPT
/// answers in the person's own ChatGPT (`ChatGPTWeb`). The OpenAI key of §871
/// and the export import are gone from this page (user, 2026-10-30: "update
/// the set up page so it doesn't show the stuff about exporting anymore").
/// A key already stored keeps answering until Disconnect; chats imported
/// before stay, and More still removes them.
struct ChatGPTImportScreen: View {
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
    @State private var connected = AgentKey.isConfigured(.openai)

    var body: some View {
        AccountPage(
            name: "ChatGPT", seatID: "gpt", source: "ChatGPT",
            state: AccountPageState.of(name: "ChatGPT", seatID: "gpt",
                                       connected: connected, store: store),
            mode: .signIn,
            lands: true,
            cardSheet: { id in
                guard id == "chatgptSignIn" else { return AnyView(EmptyView()) }
                return AnyView(WebSessionSignInSheet(seat: .chatgpt, onDone: finishSignIn))
            },
            tiles: connected ? [] : [
                AccountTile(id: "signIn", label: String(localized: "Sign in"),
                            glyph: "person.badge.key", act: startSignIn),
            ],
            signIn: startSignIn,
            teardown: {
                // Chats imported before are the person's own and stay;
                // `ImportUpkeepSection` is where they go.
                AgentKey.clear(.openai)
                connected = false
            },
            sheet: $sheet,
            act: {
                if connected {
                    AgentActiveStatusRow(provider: .openai)
                } else {
                    BridgeSyncStatusRows(proof: result)
                }
            },
            more: {
                if held > 0 {
                    ImportUpkeepSection(source: "ChatGPT", held: held,
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
        staleness = ImportRemoval.stalenessLine(source: "ChatGPT", context: modelContext)
        held = ImportRemoval.count(source: "ChatGPT", context: modelContext)
    }

    private func startSignIn() {
        DSHaptic.tap()
        result = nil
        sheet = .card(id: "chatgptSignIn")
    }

    /// chatgpt.com said the jar is signed in (`WebSession.verify`), and the
    /// sheet kept the mark: ChatGPT answers through the person's own chats.
    private func finishSignIn() {
        guard WebSession.signedIn(.chatgpt) else { return }
        AgentKey.activate(.openai)
        connected = true
        DSHaptic.success()
        result = .connected(String(localized: "pick ChatGPT when you ask."))
        store.registerConnected(id: "gpt", name: "ChatGPT",
                                proof: String(localized: "Signed in on chatgpt.com"),
                                can: ["Answers in your own ChatGPT — only when you ask.",
                                      "Sends only what you type, never what you keep."])
    }
}
