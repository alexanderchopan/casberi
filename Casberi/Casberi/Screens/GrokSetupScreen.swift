import SwiftUI
import SwiftData

/// Grok, connected by signing in on grok.com (prd §1626), as ChatGPT and
/// Claude are (§1623, §1624): xAI's own sign-in in the sheet, and Grok answers
/// in the person's own Grok (`GrokWeb`). Grok's own site, never X. The xAI
/// key this page took since §242 is gone from it; a key already stored keeps
/// answering until Disconnect.

struct GrokSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.grok)

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Grok", seatID: "grok", source: "Grok",
            state: AccountPageState.of(name: "Grok", seatID: "grok",
                                       connected: configured, store: store),
            mode: .signIn,
            lands: true,
            cardSheet: { id in
                guard id == "grokSignIn" else { return AnyView(EmptyView()) }
                return AnyView(WebSessionSignInSheet(seat: .grok, onDone: finishSignIn))
            },
            tiles: configured ? [] : [
                AccountTile(id: "signIn", label: String(localized: "Sign in"),
                            glyph: "person.badge.key", act: startSignIn),
            ],
            signIn: startSignIn,
            teardown: {
                AgentKey.clear(.grok)
                configured = false
            },
            sheet: $sheet,
            act: {
                if configured {
                    AgentActiveStatusRow(provider: .grok)
                } else {
                    BridgeSyncStatusRows(proof: result)
                }
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
    }

    private func startSignIn() {
        DSHaptic.tap()
        result = nil
        sheet = .card(id: "grokSignIn")
    }

    /// grok.com said the jar is signed in (`WebSession.verify`), and the sheet
    /// kept the mark: the seat answers through Grok's own chats from now on.
    private func finishSignIn() {
        guard WebSession.signedIn(.grok) else { return }
        AgentKey.activate(.grok)
        configured = true
        DSHaptic.success()
        result = .connected(String(localized: "pick Grok when you ask."))
        store.registerConnected(id: "grok", name: "Grok",
                                proof: String(localized: "Signed in on grok.com"),
                                can: ["Answers in your own Grok — only when you ask.",
                                      "Sends only what you type, never what you keep."])
    }
}
