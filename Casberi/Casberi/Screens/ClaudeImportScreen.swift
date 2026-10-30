import SwiftUI
import SwiftData

/// Claude, connected by signing in on claude.ai (prd §1624), as ChatGPT is
/// (§1623): claude.ai's own sign-in in the sheet, and Claude answers in the
/// person's own Claude (`ClaudeWeb`). The Anthropic key of §871 and the
/// export import are gone from this page, as they went from ChatGPT's. A key
/// already stored keeps answering until Disconnect; chats imported before
/// stay, and More still removes them.
struct ClaudeImportScreen: View {
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
    @State private var connected = AgentKey.isConfigured(.anthropic)

    var body: some View {
        AccountPage(
            name: "Claude", seatID: "claude", source: "Claude",
            state: AccountPageState.of(name: "Claude", seatID: "claude",
                                       connected: connected, store: store),
            mode: .signIn,
            lands: true,
            cardSheet: { id in
                guard id == "claudeSignIn" else { return AnyView(EmptyView()) }
                return AnyView(WebSessionSignInSheet(seat: .claude, onDone: finishSignIn))
            },
            tiles: connected ? [] : [
                AccountTile(id: "signIn", label: String(localized: "Sign in"),
                            glyph: "person.badge.key", act: startSignIn),
            ],
            signIn: startSignIn,
            teardown: {
                // Chats imported before are the person's own and stay;
                // `ImportUpkeepSection` is where they go.
                AgentKey.clear(.anthropic)
                connected = false
            },
            sheet: $sheet,
            act: {
                if connected {
                    AgentActiveStatusRow(provider: .anthropic)
                } else {
                    BridgeSyncStatusRows(proof: result)
                }
            },
            more: {
                if held > 0 {
                    ImportUpkeepSection(source: "Claude", held: held,
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
        staleness = ImportRemoval.stalenessLine(source: "Claude", context: modelContext)
        held = ImportRemoval.count(source: "Claude", context: modelContext)
    }

    private func startSignIn() {
        DSHaptic.tap()
        result = nil
        sheet = .card(id: "claudeSignIn")
    }

    /// claude.ai said the jar is signed in (`WebSession.verify`), and the
    /// sheet kept the mark: Claude answers through the person's own chats.
    private func finishSignIn() {
        guard WebSession.signedIn(.claude) else { return }
        AgentKey.activate(.anthropic)
        connected = true
        DSHaptic.success()
        result = .connected(String(localized: "pick Claude when you ask."))
        store.registerConnected(id: "claude", name: "Claude",
                                proof: String(localized: "Signed in on claude.ai"),
                                can: ["Answers in your own Claude — only when you ask.",
                                      "Sends only what you type, never what you keep."])
    }
}
