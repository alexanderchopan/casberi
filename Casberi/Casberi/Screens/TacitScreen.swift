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
            mode: .signIn,
            lands: false,
            connectLine: coSigner.map { String(localized: "Your co-signer connects · \(AddressTail.short($0))") }
                ?? String(localized: "Your account needs a co-signer first"),
            teardown: { TacitAccount.shared.forget() },
            sheet: $sheet,
            act: { actBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
    }

    /// Your account's co-signer: the wallet that signs in to Tacit.
    private var coSigner: String? { YourAccountFacts.coSigners.first }

    /// **THE PAGE IS PRIVY'S (user, 2026-11-24, of a canvas, "Build A"):
    /// tiles under the name and nothing else.** A sentence under the tile
    /// raised a "Connect" card round it mid-page ("it has connect in the
    /// middle of the page is that how our others are? i don't think so");
    /// that the account is only read is said on its Wallet page.
    ///
    /// One tile, Connect, the word Tacit's own site uses (user: "their website
    /// is connect", "not sign in"). Here connecting is your co-signer's wallet signing Tacit's own message, so
    /// connecting and opening the account are one step (user, 2026-11-24, of
    /// a "Turn on" tile: "it's connect isn't it?", "shouldn't its connect
    /// screen look like however any other connect screen may look?").
    @ViewBuilder private var actBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if added {
                DSSlabButton(tile: .open, title: String(localized: "Open Tacit"),
                             detail: String(localized: "In your Wallet"),
                             systemImage: "arrow.up.forward.app") {
                    DSHaptic.tap()
                    chrome.sourceRequest = TacitAccount.name
                }
            } else {
                DSSlabButton(tile: .connect, title: String(localized: "Connect with your co-signer"),
                             detail: coSigner.map { AddressTail.short($0) } ?? String(localized: "Your account needs a co-signer first"),
                             systemImage: "link",
                             enabled: coSigner != nil || DemoMode.isActive, action: signIn)
            }
        }
    }

    /// Adds the app, lands on its Wallet page and asks your co-signer to
    /// open the account there, where the asking and the reading are shown.
    private func signIn() {
        DSHaptic.success()
        store.registerConnected(id: TacitAccount.seatID, name: TacitAccount.name,
                                proof: String(localized: "Read only"))
        chrome.sourceRequest = TacitAccount.name
        if let coSigner, !DemoMode.isActive {
            Task { await TacitAccount.shared.open(coSigner: coSigner) }
        }
    }
}
