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

            bookDoorSection
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

    /// One row, one count, one chevron — a DOOR, never a list.
    ///
    /// It exists because the rail's own book slot is gated on the rail
    /// showing at all (`WalletScopeRail.shows` wants more than one wallet
    /// watched), so with nothing watched — the state a new person is in —
    /// the book would otherwise be unreachable.
    ///
    /// **The count is the whole ledger now (prd §466)**, not "everyone
    /// else": since the roster moved into the book, `book.count` is
    /// exactly what the room behind this door will list — the same
    /// "the count is what the room will list" rule §461 stated for the
    /// narrower count this door used to carry.
    private var bookDoorSection: some View {
        Section {
            DSSlabDoor(title: String(localized: "Address Book"),
                       detail: book.count == 1
                           ? String(localized: "1 name")
                           : String(localized: "\(book.count) names")) {
                DSHaptic.selection()
                route.push(.addressBook)
            }
        }
        .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

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
