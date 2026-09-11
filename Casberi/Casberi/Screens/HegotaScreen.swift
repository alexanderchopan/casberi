import SwiftUI
import SwiftData

/// Ethrex Hegotá, on the account page — watch an address on the
/// frame-transaction devnet.
///
/// **ON `AccountPage` SINCE §639 (2026-09-06)**, with its three siblings. One
/// anatomy, and it is the chassis's now rather than four screens agreeing;
/// what differs here is the data.
///
/// **The worked examples are not decoration.** Measured on chain 2026-08-27:
/// only 11 addresses own coins and only a handful have ever sent on a non-zero
/// nonce — and, decisively, **no address does both**. A pasted address will
/// most often show Home and Activity and nothing else, which is a correct blank
/// that reads as a broken feature. So the page offers two, one for each half
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
struct HegotaScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @Bindable private var watch = HegotaWatch.shared
    @State private var keyAddress: String? = HegotaKey.address()

    /// The read that follows a watch, reported here rather than in a room
    /// nobody has been sent to (prd §618). Reached = the sweep stamped a new
    /// `readAt`; the demo reaches nothing and is not a failure.
    @State private var reader = DevnetReader(name: HegotaIdentity.source) {
        guard !DemoMode.isActive else { return true }
        let before = HegotaLiveState.shared.readAt
        await HegotaLiveState.shared.refresh()
        return HegotaLiveState.shared.readAt != before
    }

    /// The page's one bar (§639 amendment).
    @State private var typed = ""
    @State private var sheet: AccountPageSheet?
    @State private var roster = DevnetRosterReader(seatID: HegotaIdentity.seatID,
                                                   source: HegotaIdentity.source)

    private static let mark = DS.brandHue(for: HegotaIdentity.source) ?? DS.tint

    private var connected: Bool { watch.connected }

    var body: some View {
        AccountPage(
            name: HegotaIdentity.source, seatID: HegotaIdentity.seatID,
            source: HegotaIdentity.source,
            state: AccountPageState.of(name: HegotaIdentity.source,
                                       seatID: HegotaIdentity.seatID,
                                       connected: connected, store: store),
            mode: .noAccount,
            rows: roster.rows,
            query: typed,
            onRemoveRow: unwatch,
            teardown: { HegotaBridge.disconnect(store: store) },
            sheet: $sheet,
            act: {
                DevnetAccountsAct(
                    watch: watch,
                    tint: Self.mark,
                    examples: Self.examples,
                    // The key is MADE in the room (§553's Home tiles), never
                    // here — this row only offers to watch one that already
                    // exists, so it is never a second door onto a first act.
                    mine: keyAddress,
                    mineDetail: String(localized: "The key that signs here"),
                    peek: { await DevnetPeek.read($0, via: HegotaRPC.call(method:params:)) },
                    reader: reader,
                    register: { HegotaBridge.registerBridge(store: store) },
                    typed: $typed,
                    onWatched: { _ in readRows() })
            },
            more: {
                DSSlabNote(text: String(localized: "Test ETH has no value, and the network may be reset without notice."), plain: true)
                DevnetExplorerRow(url: HegotaIdentity.explorer, plain: true)
            },
            keySheet: { EmptyView() }
        )
        .onAppear { readRows() }
        .onChange(of: watch.addresses) { _, _ in readRows() }
    }

    private func readRows() {
        Task {
            await roster.refresh(watch: watch, context: modelContext,
                                 peek: { await DevnetPeek.read($0, via: HegotaRPC.call(method:params:)) })
        }
    }

    /// ONE verb, "Remove" (§639), replacing `DevnetWatchingSection`'s own.
    private func unwatch(_ address: String) {
        watch.remove(address)
        roster.forget(address)
        HegotaBridge.registerBridge(store: store)
        readRows()
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
                      title: String(localized: "An address holding UTXOs"),
                      detail: String(localized: "The vault's unspent pieces")),
        DevnetExample(address: "0x8943545177806ed17b9f23f0a21ee5948ecaa776",
                      title: String(localized: "An address sending in parallel"),
                      detail: String(localized: "Two named nonce keys")),
    ]

    // NO ROUTE ON A WATCH (prd §618, 2026-09-05). This screen used to land you
    // in the room on the first watch — the same tap that, on vibenet, the
    // 2026-08-28 ruling forbade ("they need to be able to select multiple
    // before going to the feed"), and that this seat's own harness records
    // being reported against ("when you select one of the addresses to watch
    // you can't select the other"). The Activity row is the way on; the read
    // starts here and reports here.
}
