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
            // **THE DIRECTORY (prd §690).** Every address you watch or have
            // named, as rows on this page — the accounts-door redesign made
            // each seat's page its directory and four devnet pages got that;
            // this one kept a door to the old book instead of absorbing it.
            rows: rows,
            onRemoveRow: forget,
            onOpenRow: { sheet = .card(id: $0) },
            cardSheet: { id in
                if id == "connect" {
                    AnyView(WalletConnectPickerSheet(shared: sharedAccounts) { added in
                        if added > 0 { openRoom() }
                    })
                } else if let entry = AddressBook.shared.entry(for: id) {
                    AnyView(AddressCard(entry: entry))
                } else {
                    AnyView(EmptyView())
                }
            },
            // The watch list is this seat's whole store, so a disconnect
            // clears it — see the type's own note on the exit this seat never
            // had. The address BOOK is untouched.
            teardown: {
                wallet.remove(at: IndexSet(wallet.addresses.indices))
            },
            disconnectNote: String(localized: "The names you filed stay."),
            sheet: $sheet,
            act: { actBlock },
            more: { moreBlock },
            keySheet: { EmptyView() }
        )
    }

    /// The act. The FIRST address while there is none; the book's door once
    /// there is, because watching a second through fifth is its job (§466).
    /// **ONE FORM, ALWAYS (prd §690).** This swapped the follow field for an
    /// "Address book" door the moment a first wallet was watched — so the one
    /// place a second wallet could be followed was a screen this page no
    /// longer owns. The field stays; the rows below it are the directory.
    @ViewBuilder private var actBlock: some View {
        WalletWatchField(
            onWatched: openRoom,
            showsPeekChip: true,
            onConnectFound: { accounts in
                sharedAccounts = accounts
                sheet = .card(id: "connect")
            })
    }

    /// Watched wallets first, then the addresses you have only named — §169's
    /// two tiers over one ledger, drawn as one list with the tier in the
    /// subline (user, 2026-09-11: "keep them as rows").
    private var rows: [AccountPageShape.Row] {
        let watchedKeys = Set(wallet.addresses.map { AddressBook.key(for: $0.address) })
        let watched = wallet.addresses.map { w in
            AccountPageShape.Row(
                id: AddressBook.key(for: w.address),
                title: w.label.isEmpty ? w.short : w.label,
                subline: w.short,
                weekCount: 0, hasNew: false, isYou: false, avatarURL: nil,
                faceAddress: w.address, watched: true)
        }
        let named = AddressBook.shared.all
            .filter { !watchedKeys.contains(AddressBook.key(for: $0.address)) }
            .map { e in
                AccountPageShape.Row(
                    id: AddressBook.key(for: e.address),
                    title: e.name,
                    subline: WalletStore.shortAddress(e.address),
                    weekCount: 0, hasNew: false, isYou: false, avatarURL: nil,
                    faceAddress: e.address, watched: false)
            }
        return watched + named
    }

    /// Removing a watched row stops watching; removing a named-only row
    /// forgets the name. One verb per tier, each the consequence that tier
    /// actually has.
    private func forget(_ id: String) {
        if let i = wallet.addresses.firstIndex(where: { AddressBook.key(for: $0.address) == id }) {
            wallet.remove(at: IndexSet(integer: i))
        } else if let entry = AddressBook.shared.entry(for: id) {
            AddressBook.shared.remove(entry.address)
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


    private var chainsSummary: String {
        let selected = WalletChainStore.selectable.filter { WalletChainStore.shared.isSelected($0.id) }
        if selected.count == WalletChainStore.selectable.count { return "All \(selected.count) chains" }
        let names = selected.map(\.name)
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }
}
