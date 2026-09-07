import SwiftUI
import SwiftData

/// The FIRST wallet (prd §466, 2026-08-24) — and nothing repeated.
///
/// **This screen is the connect act, matching Vibenet's own split a few
/// commits earlier.** §461 drew the ownership boundary right — this screen
/// is your own wallets, the book is everyone else — but left the setup
/// screen still doing the everyday work: rename, remove, watch a second
/// address, read the sync status. §466 finishes the move: **setup is what
/// you do ONCE; the book is what you do REPEATEDLY.** The roster, the
/// rename alert, the removes and the ongoing sync status moved WHOLE into
/// `WalletRosterSection`, which now lives inside `AddressBookScreen` — the
/// book is where names are filed, so it is also where the roster feeding
/// those names belongs.
///
/// **ON `AccountPage` SINCE §639 (2026-09-06)**, with every other seat. Two
/// things follow, and both are deliberate:
///
/// * **The roster stays EMPTY here.** §466's split is not reversed by the
///   chassis having a "Watching · N": those rows are the book's, and drawing
///   them here too would put one list on two pages with one Remove between
///   them. The act slot is the first address while there is none, and the
///   book's own door once there is — which is where the second through fifth
///   are added.
/// * **This seat gains a Disconnect it never had.** Every other seat could be
///   stopped from its own page and this one could not, so the only way to
///   stop watching was to remove five addresses one at a time in the book.
///   The chassis's exit clears the watch list, which is this seat's whole
///   store; the address BOOK is untouched, because a name you filed is not a
///   wallet you watch (§461's boundary, in the one place it is destructive).
///
/// **Watching the first address lands you in the room.** There is nothing
/// left to configure here once it exists — leaving somebody on a setup page
/// after they connected is what made this screen grow a roster in the
/// first place.
///
/// **Still your five, still no star** (prd §461's own ruling, unchanged):
/// membership of a five-slot roster, never an attribute a reading surface
/// can toggle.
struct WalletScreen: View {
    @Bindable private var wallet = WalletStore.shared
    @Bindable private var book = AddressBook.shared
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @Environment(ShellChrome.self) private var chrome
    /// The page's one presentation (`AccountPage.sheet`) — the connect
    /// picker rides `.card`, which is what that case exists for.
    @State private var sheet: AccountPageSheet?
    /// The accounts a connected wallet app shared, held for the picker the
    /// `.card` sheet raises. Not part of the id: the id is a stable string
    /// the sheet is keyed on, and this is the payload it draws.
    @State private var sharedAccounts: [WalletConnectBridge.ConnectedAccount] = []

    var body: some View {
        AccountPage(
            name: "Wallet", seatID: "wallet", source: "Wallet",
            state: AccountPageState.of(name: "Wallet", seatID: "wallet",
                                       connected: !wallet.addresses.isEmpty, store: store),
            // **THE INTRO FOLLOWS THE FIELD (2026-08-31).** It said "paste an
            // address or ENS name below" unconditionally, while
            // `WalletWatchField` draws only while nothing is watched — so for
            // everybody past their first address the sentence named a control
            // that is not on the screen. §83's dead control in words rather
            // than in pixels, and worse than a dead button: a button that does
            // nothing is at least visible, and this sent people hunting for a
            // field that had moved (§466 — the roster, and watching a second
            // through fifth, is the address book's job now).
            //
            // Drawn only while NOT connected now (the chassis's rule), so the
            // second branch is gone with the condition that produced it: the
            // book's own door in the act slot says where to add a second, and
            // the state line says whether anything is being read.
            mode: .noAccount,
            // The connect picker, through the page's ONE presentation.
            cardSheet: { _ in
                AnyView(WalletConnectPickerSheet(shared: sharedAccounts) { added in
                    if added > 0 { openRoom() }
                })
            },
            // The watch list is this seat's whole store, so a disconnect
            // clears it — see the type's own note on the exit this seat never
            // had. The address BOOK is untouched.
            teardown: {
                wallet.remove(at: IndexSet(wallet.addresses.indices))
            },
            disconnectNote: String(localized: "The names you filed in the address book stay."),
            sheet: $sheet,
            act: { actBlock },
            more: { moreBlock },
            keySheet: { EmptyView() }
        )
    }

    /// The act. The FIRST address while there is none; the book's door once
    /// there is, because watching a second through fifth is its job (§466).
    @ViewBuilder private var actBlock: some View {
        if wallet.addresses.isEmpty {
            WalletWatchField(
                onWatched: openRoom,
                showsPeekChip: true,
                onConnectFound: { accounts in
                    sharedAccounts = accounts
                    sheet = .card(id: "connect")
                })
        } else {
            DSSlabDoor(title: "Address book", detail: bookSummary,
                       systemImage: "person.text.rectangle") {
                route.push(.addressBook)
            }
        }
    }

    /// The connection plumbing and the promise. Chains and the read-only
    /// sentence sit under the act, as they always have.
    @ViewBuilder private var moreBlock: some View {
        DSSlabDoor(title: "Connection", detail: chainsSummary,
                   systemImage: "network") {
            route.pushBridge(.walletConnection)
        }
        DSSlabNote(text: String(localized: "Read-only — watching can never move funds."),
                   plain: true)
    }

    /// Land in the room the first address just made real (`RoomDoor`'s own
    /// move, spelled here because it fires from a watch rather than a tap).
    /// POP FIRST — `sourceRequest` is read by `MainSurface`, which sits
    /// behind this pushed stack.
    private func openRoom() {
        route.path = []
        chrome.sourceRequest = "Wallet"
    }

    private var bookSummary: String {
        switch book.count {
        case 0: return String(localized: "Nothing named yet")
        case 1: return String(localized: "1 named")
        default: return String(localized: "\(book.count) named")
        }
    }

    private var chainsSummary: String {
        let selected = WalletChainStore.selectable.filter { WalletChainStore.shared.isSelected($0.id) }
        if selected.count == WalletChainStore.selectable.count { return "All \(selected.count) chains" }
        let names = selected.map(\.name)
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }
}
