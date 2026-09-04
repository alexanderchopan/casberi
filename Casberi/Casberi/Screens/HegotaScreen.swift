import SwiftUI

/// Ethrex Hegotá, connected — watch an address on the frame-transaction devnet.
///
/// **ONE ANATOMY WITH ITS THREE SIBLINGS (user, 2026-09-04).** Header, room
/// door, the accounts slab — paste field at the top, examples under it — the
/// screen's one sentence, the explorer, Disconnect. `DevnetAccounts.swift`
/// carries the whole argument; what differs here is the data.
///
/// **The worked examples are not decoration.** Measured on chain 2026-08-27:
/// only 11 addresses own coins and only a handful have ever sent on a non-zero
/// nonce — and, decisively, **no address does both**. A pasted address will
/// most often show Home and Activity and nothing else, which is a correct blank
/// that reads as a broken feature. So the screen offers two, one for each half
/// of the room, and says what each will show rather than presenting them as
/// interchangeable. They survive the connect: they are the room's only two
/// halves and nobody on this chain has both, so watching one and losing the
/// other would leave you permanently unable to see half the room (reported
/// from a device, 2026-08-27).
///
/// **THE FAUCET DOOR IS GONE (2026-09-04, §548's follow-up applied here).**
/// It shipped as a `DSSlabDoor` reading "Get test ETH" — the same verb the
/// room's own Home tile performs in place since §553, which is two controls
/// for one consequence (§190/§83: neither then reads as the real one). Frames
/// lost its copy of exactly this door on 2026-09-01 for exactly this reason
/// and Hegotá's was left behind; the ruling was one screen wide and the
/// mistake was leaving it that way.
///
/// **This screen is the CONNECT ACT and nothing else (prd §465).** It keeps
/// what you do ONCE — the first address, the disconnect — and the room keeps
/// what you do repeatedly.
struct HegotaScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    @Bindable private var watch = HegotaWatch.shared
    @State private var keyAddress: String? = HegotaKey.address()

    private static let mark = DS.brandHue(for: HegotaIdentity.source) ?? DS.tint

    private var connected: Bool { watch.connected }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: HegotaIdentity.source,
                mode: .noAccount,
                // ACTION, not a re-pitch: you reach this from the product page,
                // which has just said what Hegotá is. The mode chip carries the
                // cost. What is left is what to do here.
                intro: "Paste an address, or start with one that already has something to show.",
                connected: connected)

            if connected {
                RoomDoor(name: HegotaIdentity.source, source: HegotaIdentity.source)
                    .listRowSeparator(.hidden)
            }

            Section {
                DevnetAccountsSlab(
                    watch: watch,
                    tint: Self.mark,
                    examples: Self.examples,
                    // The key is MADE in the room (§553's Home tiles), never
                    // here — this row only offers to watch one that already
                    // exists, so it is never a second door onto a first act.
                    mine: keyAddress,
                    mineDetail: String(localized: "The key that signs here"),
                    idleNote: watch.addresses.isEmpty
                        ? String(localized: "Nothing is watched yet.") : nil,
                    register: { HegotaBridge.registerBridge(store: store) },
                    onWatched: watched)
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            if !watch.addresses.isEmpty {
                Section { DevnetWatchingSection(watch: watch) {
                    HegotaBridge.registerBridge(store: store)
                } }
                .dsSlabSection()
                .listRowSeparator(.hidden)
            }

            Section {
                DSSlabNote(text: String(localized: "Test ETH has no value, and the network may be reset without notice."))
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            DevnetExplorerRow(url: HegotaIdentity.explorer)
                .listRowSeparator(.hidden)

            if connected {
                BridgeDisconnectSection(
                    bridgeID: HegotaIdentity.seatID, name: HegotaIdentity.source,
                    teardown: { HegotaBridge.disconnect(store: store) }
                ).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: HegotaIdentity.source)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(HegotaIdentity.source)
    }

    /// The two worked examples, measured rather than picked.
    ///
    /// **`0x8b54b456…` holds the most coins on the chain (7 unspent across 10
    /// moves)** — seven discs is a real drawing where three is thin — and
    /// **`0x8943545177…` is the only address that has sent on two different
    /// non-zero nonce keys**, `0xbeef01` and `0x1234`, which is what makes its
    /// Nonces scope show more than one row. Measured 2026-08-27; if the chain
    /// moves on, these become ordinary addresses rather than broken ones, which
    /// is why the copy says what they showed rather than promising what they
    /// will.
    private static let examples: [DevnetExample] = [
        DevnetExample(address: "0x8b54b45663b4af65d51d7f98c20f533965e0a013",
                      title: String(localized: "An address holding coins"),
                      detail: String(localized: "The vault's unspent pieces")),
        DevnetExample(address: "0x8943545177806ed17b9f23f0a21ee5948ecaa776",
                      title: String(localized: "An address sending in parallel"),
                      detail: String(localized: "Two named nonce keys")),
    ]

    /// **ONLY THE FIRST WATCH ROUTES**, so a second watch tapped a moment later
    /// cannot yank the list out from under the thumb still using it.
    ///
    /// CLOSE, POP, ASK — `RoomDoor`'s order. This screen is RAISED as the
    /// connect sheet, so `route.path` is the stack behind it and `sourceRequest`
    /// alone moves a room the form is still covering. Nil-write when nothing is
    /// raised.
    private func watched(_ address: String) {
        // READ IT NOW. The room reads for itself on appear too, but starting
        // here means the sweep is usually done by the time the room draws.
        Task { await HegotaLiveState.shared.refresh() }
        guard watch.addresses.count == 1 else { return }
        route.closeConnectForm()
        route.path = []
        chrome.sourceRequest = HegotaIdentity.source
    }
}
