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
    @Environment(HomeRoute.self) private var route
    @Environment(ShellChrome.self) private var chrome
    /// This screen's ONE presentation (`FeedScreen`'s single-presentation
    /// rule) — only `.connectPicker` is reachable here now; the other three
    /// `AddressBookSheetRoute` cases are the book's.
    @State private var sheetRoute: AddressBookSheetRoute?

    var body: some View {
        List {
            // A short header — the family-wide pass that put every "type
            // something to watch it" screen (Vibenet, Hegota, RSS, Tokens,
            // Stocktwits, …) on one shape: identity + mode chip + one action
            // sentence, THEN the acts. Wallet had none at all (prd §185/§466's
            // "the omnibox is the screen's first act"); the identity row
            // comes back here too, ahead of the door and the field it used to
            // open directly on.
            BridgeSetupHeader(
                name: "Wallet",
                mode: .noAccount,
                // **THE INTRO FOLLOWS THE FIELD (2026-08-31).** It said
                // "paste an address or ENS name below" unconditionally, while
                // `WalletWatchField` draws only while nothing is watched — so
                // for everybody past their first address the sentence named a
                // control that is not on the screen. §83's dead control in
                // words rather than in pixels, and worse than a dead button:
                // a button that does nothing is at least visible, and this
                // sent people hunting for a field that had moved (§466 — the
                // roster, and watching a second through fifth, is the address
                // book's job now).
                //
                // The second branch points at the door directly below it, so
                // "below" resolves in both states.
                intro: wallet.addresses.isEmpty
                    ? String(localized: "Paste an address or ENS name below, or connect a wallet app. Watch up to five.")
                    : String(localized: "Watching \(wallet.addresses.count) of \(WalletStore.watchLimit). Add, rename or stop watching in the address book below."),
                connected: !wallet.addresses.isEmpty)

            // A DOOR, not a signpost (R4.5) — only once there is a room to
            // open. Matches Vibenet: a "View feed" button over an empty room
            // is a control that opens nothing worth seeing (§83).
            if !wallet.addresses.isEmpty {
                RoomDoor(name: "Wallet", source: "Wallet")
                    .listRowSeparator(.hidden)
            }

            // THE FIRST ADDRESS, and only while there is none. Once watched,
            // watching a second through fifth is the book's own roster
            // section's job.
            if wallet.addresses.isEmpty {
                Section {
                    WalletWatchField(
                        onWatched: openRoom,
                        showsPeekChip: true,
                        onConnectFound: { sheetRoute = .connectPicker($0) })
                }
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            footSection

            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Addresses")
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .connectPicker(let accounts):
                WalletConnectPickerSheet(shared: accounts) { added in
                    if added > 0 { openRoom() }
                }
            case .entry, .move, .newGroup:
                EmptyView()
            }
        }
    }

    /// Land in the room the first address just made real (`RoomDoor`'s own
    /// move, spelled here because it fires from a watch rather than a tap).
    /// POP FIRST — `sourceRequest` is read by `MainSurface`, which sits
    /// behind this pushed stack.
    private func openRoom() {
        route.path = []
        chrome.sourceRequest = "Wallet"
    }

    // MARK: - The door to everyone else (prd §461/§466)


    // MARK: - The foot

    /// The connection plumbing and the promise. Chains and teardown are the
    /// one thing here nobody revisits, so they sit last.
    private var footSection: some View {
        Section {
            VStack(spacing: DS.Space.s4) {
                DSSlabDoor(title: "Connection", detail: chainsSummary) {
                    route.pushBridge(.walletConnection)
                }
                Text("Read-only — watching can never move funds.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .listRowInsets(EdgeInsets(top: DS.Space.s3, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var chainsSummary: String {
        let selected = WalletChainStore.selectable.filter { WalletChainStore.shared.isSelected($0.id) }
        if selected.count == WalletChainStore.selectable.count { return "All \(selected.count) chains" }
        let names = selected.map(\.name)
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }
}
