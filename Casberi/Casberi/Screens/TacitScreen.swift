import SwiftUI

/// TACIT IN THE CATALOGUE: ADD IT, THEN OPEN IT WITH YOUR CO-SIGNER.
///
/// Adding takes one tap and pastes nothing. What it adds is a page in the
/// Wallet (`WalletSection.tacit`, `TacitAccountRows`) that opens an account
/// you already have on Tacit, when your co-signer's wallet signs for it.
struct TacitScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @State private var sheet: AccountPageSheet?

    private var added: Bool { store.bridges.contains { $0.id == TacitAccount.seatID } }

    var body: some View {
        AccountPage(
            name: "Tacit", seatID: "tacit", source: "Tacit",
            state: AccountPageState.of(name: "Tacit", seatID: "tacit",
                                       connected: added, store: store),
            mode: .noAccount,
            lands: false,
            teardown: { TacitAccount.shared.forget() },
            sheet: $sheet,
            act: { actBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
    }

    @ViewBuilder private var actBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if added {
                DSSlabButton(title: String(localized: "Open Tacit"),
                             detail: String(localized: "In your Wallet"),
                             systemImage: "arrow.right") {
                    DSHaptic.tap()
                    chrome.sourceRequest = TacitAccount.name
                }
            } else {
                DSSlabButton(tile: .turnOn, title: String(localized: "Add"),
                             detail: String(localized: "Opens with your co-signer"),
                             systemImage: "plus", action: add)
            }
            DSFootnote("Casberi reads a Tacit account you already have. It cannot move its money.")
        }
    }

    private func add() {
        DSHaptic.success()
        store.registerConnected(id: TacitAccount.seatID, name: TacitAccount.name,
                                proof: String(localized: "Read only"))
        chrome.sourceRequest = TacitAccount.name
    }
}
