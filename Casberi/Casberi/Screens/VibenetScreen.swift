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
/// from the door below. That half stands: there is still no roster here,
/// no rename and no remove.
///
/// **CONNECTING IS PICKING SEVERAL, AND IT NEVER ROUTES BY ITSELF (user
/// ruling, 2026-08-28).** §465 also had this screen hide its field and its
/// discovery list the instant `connected` flipped, and shove you into the
/// room on the first watch — "watching the first address IS the
/// connection". Reported: *"after you follow one address you can't choose
/// any of the others… they need to be able to select multiple before going
/// to the feed."* And that is what the screen did: one tap on a list of
/// five devnet accounts took the other four away and left the page.
///
/// So the field and the list STAY for the whole visit, every row says
/// whether you have already taken it, and going to the room is a tap on
/// the `RoomDoor` above them — an act of yours, not a consequence of the
/// last thing you touched. Two consequences worth keeping straight:
///
/// * The book also has a paste field, which §465 called duplication worth
///   ending. It is not the same act any more — this one is "which accounts
///   am I connecting", that one is "manage the list I already have" — and
///   the alternative, discovered here, is a connect page that answers its
///   own list by deleting it.
/// * Nothing here composes a room and then navigates. The read still
///   happens (see `readSoon`) so the room is warm when you knock, but the
///   knock is the door's.
///
/// Unlike Peer or Privacy Pools this seat owns its own addresses rather
/// than riding the watched wallets: a devnet account is not one of your
/// wallets, and vibenet is not a live network. That is also why there is
/// no cap — reads here are keyless and free, so there is no expensive tier
/// to ration (`VibenetAddressBookScreen`'s own doc carries the full
/// argument).
struct VibenetScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route

    @Bindable private var watch = VibenetWatch.shared
    private var connected: Bool { watch.connected }

    /// A chain read is in flight. Shown, never blocking: the point of this
    /// screen is that you keep picking while it runs.
    @State private var reading = false
    /// Another watch landed while a read was running — the address book's
    /// own `loadPending` shape, and it is what makes picking four accounts
    /// in four seconds end with one read that saw all four rather than a
    /// snapshot that stopped at whichever tap won the race.
    @State private var readPending = false
    /// Set when a read could not reach vibenet at all. The accounts ARE
    /// watched (the list is written before any of this), so this says what
    /// happened rather than pretending the watch failed.
    @State private var readError: String?

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
                // could not say: what to do here — and, since 2026-08-28,
                // that it is not a one-shot.
                intro: "Paste an account address, or watch any of the examples below. Add as many as you like.",
                connected: connected)

            // THE DOOR LEADS (R4.5, §460) — and since the ruling above it is
            // also the only way from here to the room, which is why it must
            // stay at the top rather than trailing the list it competes with
            // for the thumb.
            if connected {
                RoomDoor(name: "Base Vibenet", source: VibenetIdentity.source)
                    .listRowSeparator(.hidden)
            }

            // NOT gated on `connected` any more (user ruling, 2026-08-28 —
            // see this type's own header doc). A connect page whose answer to
            // "I watched one" is to remove the list is a connect page that can
            // only ever connect one thing.
            Section {
                VibenetWatchField(onWatched: watched, syncing: reading,
                                  idleNote: readError)
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            Section {
                VibenetDiscoverySection(onWatched: watched)
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

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
    /// whose head said "Everyone else · 4"). It doubles as this screen's
    /// only tally of what you have picked so far, which is why it is a
    /// count and not a roster: the roster is what §465 moved.
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

    /// An address was just watched, from either control. Registers the seat
    /// and warms the room. **It does not navigate** — see the header doc.
    private func watched() {
        // The seat is registered by the controls themselves (see
        // `VibenetDiscoverySection.discoveryRow`), so all this screen owes a
        // watch is the read.
        readSoon()
    }

    /// **THE WATCH READS THE CHAIN (2026-08-28).** Watching only wrote the
    /// address to the list; nothing read vibenet, and the room composes off
    /// `VibenetState.saved` (the snapshot, never a live read —
    /// `VibenetRoomSource.card`'s own R4.1 reason). So a freshly watched
    /// account had no snapshot to compose from, and the room drew NOTHING
    /// over it until some later foreground sweep happened to run
    /// `VibenetRoomSource.compose()` for its own reasons — reported as *"it
    /// also says it's not connected after i do connect it"*.
    ///
    /// Serialized rather than one read per tap: picking four accounts in
    /// four seconds should cost one read that saw four addresses, not four
    /// racing reads whose last writer decides the snapshot.
    private func readSoon() {
        if reading { readPending = true; return }
        reading = true
        Task {
            defer { reading = false }
            repeat {
                readPending = false
                let room = await VibenetRoomSource.compose()
                // `compose` returns early WITHOUT saving when the config is
                // unreachable, so the snapshot is still nil and the room
                // would draw the blank page this whole fix exists to stop.
                // Say so here, where the person is.
                readError = room.configReached
                    ? nil
                    : String(localized: "Couldn't reach vibenet just now. Your accounts are watched — the room fills in as soon as a read lands.")
            } while readPending && watch.connected
        }
    }
}
