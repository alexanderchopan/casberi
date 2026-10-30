import SwiftUI
import SwiftData

/// Muse, connected by signing in on muse.ai (prd §1619), the way Beeper
/// connects it: Meta's own email-or-phone code on Muse's own page
/// (`WebSessionSignInSheet`), and Muse answers in the person's own Muse chat
/// (`MuseWeb`). No key: the Model API key this page took since §854 is gone
/// from it (user, 2026-10-30: "i don't think we need 'Your key' any more").
/// A key already stored keeps answering until Disconnect clears it.
///
/// `lands: true` since §839: an answer lands its conversation as a chat
/// thing, so this seat has a room and an Activity count.

struct MuseSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.meta)

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Muse", seatID: "muse", source: "Muse",
            state: AccountPageState.of(name: "Muse", seatID: "muse",
                                       connected: configured, store: store),
            mode: .signIn,
            lands: true,
            cardSheet: { id in
                guard id == "museSignIn" else { return AnyView(EmptyView()) }
                return AnyView(WebSessionSignInSheet(seat: .muse, onDone: finishSignIn))
            },
            tiles: configured ? [] : [
                AccountTile(id: "signIn", label: String(localized: "Sign in"),
                            glyph: "person.badge.key", act: startSignIn),
            ],
            signIn: startSignIn,
            teardown: {
                AgentKey.clear(.meta)
                configured = false
            },
            sheet: $sheet,
            act: {
                if configured {
                    AgentActiveStatusRow(provider: .meta)
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
        sheet = .card(id: "museSignIn")
    }

    /// muse.ai said the jar is signed in (`WebSession.verify`), and the sheet
    /// kept the mark: the seat answers through Muse's own chat from now on.
    private func finishSignIn() {
        guard WebSession.signedIn(.muse) else { return }
        AgentKey.activate(.meta)
        configured = true
        DSHaptic.success()
        result = .connected(String(localized: "pick Muse when you ask."))
        store.registerConnected(id: "muse", name: "Muse",
                                proof: String(localized: "Signed in on muse.ai"),
                                can: ["Answers in your Muse chat — only when you ask.",
                                      "Sends only what you type, never what you keep."])
    }
}
