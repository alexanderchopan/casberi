import SwiftUI

/// Base "vibenet", connected — watch a devnet address and see its
/// EIP-8130 keystore state: is it established, which actors can act for
/// it, is it locked.
///
/// **This screen is the CONNECT ACT and nothing else (prd §465,
/// 2026-08-24).** Reported: *"the set up screens need to feel like they
/// are only for set up."* It used to be the connect page AND the roster
/// AND the rename/remove surface — §461's complaint on the Wallet side,
/// one seat over. The ruling that settled it: **setup keeps what you do
/// ONCE — the first address, the disconnect — and the room keeps what you
/// do repeatedly.** So the roster, the renames and the removes moved to
/// `VibenetAddressBookScreen`, reachable from the room's own face rail and
/// from the door below.
///
/// **Watching the first address lands you in the room**, because that
/// paste IS the connection: there is nothing left to configure here, and
/// leaving somebody on a setup page after they connected is what made this
/// screen grow a roster in the first place. Only the FIRST one routes — a
/// second watch, tapped from the discovery list a moment later, must not
/// yank the list out from under the thumb that is still using it.
///
/// Unlike Peer or Privacy Pools this seat owns its own addresses rather
/// than riding the watched wallets: a devnet account is not one of your
/// wallets, and vibenet is not a live network. That is also why there is
/// no cap — reads here are keyless and free, so there is no expensive tier
/// to ration (`VibenetAddressBookScreen`'s own doc carries the full
/// argument).
struct VibenetScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    @Bindable private var watch = VibenetWatch.shared
    private var connected: Bool { watch.connected }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Base Vibenet",
                mode: .noAccount,
                // ACTION, not a re-pitch (R4.4). You reach this screen from
                // the product page, which just said what vibenet is and
                // what it reads — so an intro describing the same thing
                // again is the same information twice, one tap apart. The
                // mode chip already carries the cost ("No account"). What
                // is left for this sentence is the only thing the pitch
                // could not say: what to do here.
                intro: "Paste an account address, or watch one of the examples below.",
                connected: connected)

            // A DOOR, not a signpost (R4.5) — and it leads the connected
            // page rather than trailing anything, which on a busy watch
            // list put it below the fold (§460).
            if connected {
                RoomDoor(name: "Base Vibenet", source: VibenetIdentity.source)
                    .listRowSeparator(.hidden)
            }

            // THE FIRST ADDRESS, and only while there is no first address.
            // Once the seat is connected the field lives in the book, with
            // the list it adds to — two fields writing one list, a tap
            // apart, is the duplication this split exists to end.
            if !connected {
                Section {
                    VibenetWatchField(onWatched: openRoom)
                }
                .dsSlabSection()
                .listRowSeparator(.hidden)

                Section {
                    VibenetDiscoverySection(onWatched: openRoom)
                }
                .dsSlabSection()
                .listRowSeparator(.hidden)
            }

            if connected {
                bookDoorSection

                BridgeDisconnectSection(
                    bridgeID: VibenetIdentity.seatID, name: VibenetIdentity.source,
                    teardown: { VibenetBridge.disconnect(store: store) }
                ).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Base Vibenet")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Base Vibenet")
    }

    /// The door to the roster. Two slots, never one joined string — the
    /// count is what the screen behind it will LIST, so the two can never
    /// disagree (§461's own lesson, where a door read "6 names" over a room
    /// whose head said "Everyone else · 4").
    private var bookDoorSection: some View {
        Section {
            DSSlabDoor(title: String(localized: "Address Book"),
                       detail: watch.addresses.count == 1
                           ? String(localized: "1 account")
                           : String(localized: "\(watch.addresses.count) accounts")) {
                DSHaptic.selection()
                route.push(.vibenetAddressBook)
            }
        }
        .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Land in the room the address just made real. `RoomDoor`'s own move,
    /// spelled here because this one fires from a watch rather than a tap:
    /// POP FIRST — `sourceRequest` is read by `MainSurface`, which sits
    /// behind this pushed stack, so asking before popping changes the room
    /// nobody is looking at.
    private func openRoom() {
        route.path = []
        chrome.sourceRequest = VibenetIdentity.source
    }
}
