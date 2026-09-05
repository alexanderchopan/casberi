import SwiftUI

/// The Frames devnet, connected — chain 81410, the reference test network for
/// EIP-8141 frame transactions (prd §548).
///
/// **ONE ANATOMY WITH ITS THREE SIBLINGS (user, 2026-09-04).** Header, room
/// door, the accounts slab — paste field at the top, examples under it — the
/// screen's one sentence, the explorer, Disconnect. `DevnetAccounts.swift`
/// carries the whole argument; what differs here is the data.
///
/// **THE ACCOUNT ACT MOVED TO THE ROOM (2026-09-04).** This screen made the
/// key, on the measurement that a chain four days old holds 18 addresses and
/// so a pasted stranger shows almost nothing, making "create an account" the
/// common path. That measurement stands and the placement no longer follows
/// from it: §553 gives the room a permanent Send half, §594 moved vibenet's
/// four acts to Home for the same reason, and the faucet door left this screen
/// on 2026-09-01 because Top up already lives there — so keeping Create here
/// left ONE of a chain's three acts on the setup page, which is the split that
/// makes neither place read as the real one (§190). What remains is a row that
/// offers to WATCH the key once it exists, which is this screen's own verb.
///
/// **This screen is the CONNECT ACT and nothing else (prd §465).** It keeps
/// what you do ONCE — watch the first address, disconnect — and the room keeps
/// what you do repeatedly.
struct FramesScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    @Bindable private var watch = FramesWatch.shared
    @State private var keyAddress: String? = FramesKey.address()

    private static let mark = DS.brandHue(for: FramesIdentity.source) ?? DS.tint

    private var connected: Bool { watch.connected || keyAddress != nil }

    var body: some View {
        BridgeSetupPage(name: FramesIdentity.source, computedTitle: FramesIdentity.source) {
            BridgeSetupHeader(
                name: FramesIdentity.source,
                mode: .noAccount,
                // ACTION, not a re-pitch: you reach this from the product
                // page, which has just said what the chain is.
                intro: "Paste an address, or start with one that already has something to show.",
                connected: connected)

            if connected {
                RoomDoor(name: FramesIdentity.source, source: FramesIdentity.source)
                    .listRowSeparator(.hidden)
            }

            Section {
                DevnetAccountsSlab(
                    watch: watch,
                    tint: Self.mark,
                    examples: Self.examples,
                    // Offered only once the key exists — making one is the
                    // room's act now, so this is never a door onto a first
                    // step that is somewhere else.
                    mine: keyAddress,
                    mineDetail: String(localized: "The key that signs here"),
                    idleNote: watch.addresses.isEmpty
                        ? String(localized: "Nothing is watched yet.") : nil,
                    register: { FramesBridge.registerBridge(store: store) },
                    onWatched: watched)
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            if !watch.addresses.isEmpty {
                Section { DevnetWatchingSection(watch: watch) {
                    FramesBridge.registerBridge(store: store)
                } }
                .dsSlabSection()
                .listRowSeparator(.hidden)
            }

            // THE ONE GRAY SENTENCE (§315's budget), spent on the fact that
            // changes what somebody would DO rather than on the pitch: this
            // network says of itself that it may be reset without notice, so
            // an account here is not somewhere to keep anything.
            Section {
                DSSlabNote(text: String(localized: "Test ETH has no value, and the network may be reset without notice."))
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            DevnetExplorerRow(url: FramesIdentity.explorer)
                .listRowSeparator(.hidden)

            if connected {
                BridgeDisconnectSection(
                    bridgeID: FramesIdentity.seatID, name: FramesIdentity.source,
                    teardown: { FramesBridge.disconnect(store: store) }
                ).listRowSeparator(.hidden)
            }
        }
    }

    private static let examples = FramesExample.all

    /// **ONLY THE FIRST WATCH ROUTES**, so a second watch cannot yank the list
    /// out from under the thumb still using it.
    ///
    /// CLOSE, POP, ASK — `RoomDoor`'s order. This screen is RAISED as the
    /// connect sheet, so `route.path` is the stack behind it and a bare
    /// `sourceRequest` moves a room the form is still covering.
    private func watched(_ address: String) {
        guard watch.addresses.count == 1 else { return }
        route.closeConnectForm()
        route.path = []
        chrome.sourceRequest = FramesIdentity.source
    }
}

/// The addresses worth offering, and there are only two worth offering.
///
/// **Measured 2026-09-01 across the chain's whole history**: 5 type-`0x06`
/// transactions from 4 senders. These two are the only addresses that have
/// sent more than one thing, so they are the only ones whose room has more
/// than a single row in it. Everything else on this chain is a genesis
/// fixture or an address the faucet paid once.
///
/// A namespace rather than a type of its own since 2026-09-04 — the row shape
/// is `DevnetExample` now, shared with the three sibling devnets. The name
/// survives because `FeedScreen` reads this table to title a frame
/// transaction's counterparty.
enum FramesExample {
    static let all: [DevnetExample] = [
        DevnetExample(address: "0x80cfe5da326d0ab7a1d2ffc61745c57885dc2e32",
                      title: String(localized: "An address that sent twice"),
                      detail: String(localized: "Two frame transactions")),
        DevnetExample(address: "0x333ea8dfbb78bf478c52fd6e1a8aa659db873a0d",
                      title: String(localized: "A two-frame transfer"),
                      detail: String(localized: "A verify frame and a sender frame")),
    ]
}
