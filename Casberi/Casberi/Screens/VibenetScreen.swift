import SwiftUI

/// Base "vibenet", connected — watch a devnet address and see its
/// EIP-8130 keystore state: is it established, which actors can act for
/// it, is it locked.
///
/// **ONE ANATOMY WITH ITS THREE SIBLINGS (user, 2026-09-04).** Header, room
/// door, the accounts slab — paste field at the top, examples under it — the
/// live discovery list, the screen's one sentence, the explorer, Disconnect.
/// `DevnetAccounts.swift` carries the whole argument. Vibenet is the seat the
/// shared row was taken FROM: its face rows with a `Watch` / `✓ Watching`
/// state were the best of the four, and the other three now wear them.
///
/// **This screen is the CONNECT ACT and nothing else (prd §465,
/// 2026-08-24).** Reported: *"the set up screens need to feel like they
/// are only for set up."* It used to be the connect page AND the roster
/// AND the rename/remove surface — §461's complaint on the Wallet side,
/// one seat over. The ruling that settled it: **setup keeps what you do
/// ONCE — the first address, the disconnect — and the room keeps what you
/// do repeatedly.** So the roster, the renames and the removes live on the
/// room's own face rail. That half stands: there is still no roster here,
/// no rename and no remove — and it is why vibenet alone carries no
/// `DevnetWatchingSection`, the one place the four seats still differ.
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
/// last thing you touched. Nothing here composes a room and then navigates:
/// the read still happens (see `readSoon`) so the room is warm when you
/// knock, but the knock is the door's.
///
/// Unlike Peer or Privacy Pools this seat owns its own addresses rather
/// than riding the watched wallets: a devnet account is not one of your
/// wallets, and vibenet is not a live network. That is also why there is
/// no cap — reads here are keyless and free, so there is no expensive tier
/// to ration.
struct VibenetScreen: View {
    @Environment(BridgeStore.self) private var store

    @Bindable private var watch = VibenetWatch.shared
    private var connected: Bool { watch.connected }

    private static let mark = DS.brandHue(for: VibenetIdentity.source) ?? DS.tint

    /// The read that follows a watch (prd §618) — the `readSoon` loop this
    /// screen carried since 2026-08-28, lifted into `DevnetReader` so the
    /// other three seats share it. `compose` returns WITHOUT saving when the
    /// config is unreachable, so the snapshot stays nil and the room would
    /// draw the blank page the loop exists to stop; unreachable is said here,
    /// where the person is.
    @State private var reader = DevnetReader(name: VibenetIdentity.source) {
        (await VibenetRoomSource.compose()).configReached
    }

    var body: some View {
        BridgeSetupPage(name: VibenetIdentity.source, computedTitle: VibenetIdentity.source) {
            BridgeSetupHeader(
                name: VibenetIdentity.source,
                mode: .noAccount,
                // ACTION, not a re-pitch (R4.4). You reach this screen from
                // the product page, which just said what vibenet is and
                // what it reads — so an intro describing the same thing
                // again is the same information twice, one tap apart. The
                // mode chip already carries the cost ("No account"). What
                // is left for this sentence is the only thing the pitch
                // could not say: what to do here — and, since 2026-08-28,
                // that it is not a one-shot.
                //
                // ONE SENTENCE, FOUR SEATS (prd §618). The four devnets said
                // this three different ways; the second clause is what used
                // to be vibenet's alone, and it belongs to all four now that
                // none of them routes to the room on a watch.
                intro: "Paste an address, or start with one that already has something to show. Watch as many as you like.",
                connected: connected)

            // THE DOOR LEADS (R4.5, §460) — and since the 2026-08-28 ruling it
            // is also the only way from here to the room, which is why it must
            // stay at the top rather than trailing the list it competes with
            // for the thumb.
            if connected {
                RoomDoor(name: VibenetIdentity.source, source: VibenetIdentity.source)
                    .listRowSeparator(.hidden)
            }

            // NOT gated on `connected` (user ruling, 2026-08-28 — see this
            // type's own header doc). A connect page whose answer to "I watched
            // one" is to remove the list is a connect page that can only ever
            // connect one thing.
            Section {
                DevnetAccountsSlab(
                    watch: watch,
                    tint: Self.mark,
                    examples: Self.examples,
                    peek: { await DevnetPeek.read($0, via: VibenetChain.call(method:params:)) },
                    reader: reader,
                    register: { VibenetBridge.registerBridge(store: store) })
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            // The live half — real accounts created on the chain, which no
            // fixed list can carry. Its own section because it answers a
            // different question ("who is using this today") and can fail on
            // its own without taking the examples above down with it.
            Section {
                VibenetDiscoverySection(onWatched: { reader.kick() }, tint: Self.mark)
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            Section {
                DSSlabNote(text: String(localized: "Test ETH has no value, and the network may be reset without notice."))
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            DevnetExplorerRow(url: VibenetExplorer.base)
                .listRowSeparator(.hidden)

            if connected {
                BridgeDisconnectSection(
                    bridgeID: VibenetIdentity.seatID, name: VibenetIdentity.source,
                    teardown: { VibenetBridge.disconnect(store: store) }
                ).listRowSeparator(.hidden)
            }
        }
    }

    /// A fixed, always-available account to peek at — the fallback for when
    /// live discovery cannot reach the chain at all, which otherwise leaves a
    /// new user with nothing to tap. Watched exactly like any pasted or
    /// discovered address; nothing about tapping it is different from typing
    /// it in by hand.
    private static let examples: [DevnetExample] = [
        DevnetExample(address: "0x777804FDCc280c082Db9788EAE5BEca0Fc2BeD9b",
                      title: String(localized: "An established account"),
                      detail: String(localized: "Its keys and what they may do")),
    ]
}
