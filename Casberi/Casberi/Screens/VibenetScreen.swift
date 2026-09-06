import SwiftUI
import SwiftData

/// Base "vibenet", on the account page — watch a devnet address and see its
/// EIP-8130 keystore state: is it established, which actors can act for
/// it, is it locked.
///
/// **ON `AccountPage` SINCE §639 (2026-09-06.)** Reported of the seats still
/// on the old chassis: *"these others that are already connected still look
/// like connect pages, they shouldn't."* They did, and the reason was
/// structural rather than cosmetic — a connect screen leads with the pitch and
/// ends with the act, so a seat that has been reading for a month opened on a
/// re-introduction to itself. The account page opens on the mark, the name and
/// what the seat is doing right now; the act field is one row down whether you
/// are connecting or adding a ninth address.
///
/// **ONE ANATOMY WITH ITS THREE SIBLINGS (user, 2026-09-04)** — and it is the
/// chassis's now, not four screens agreeing. What is still this file's:
/// vibenet's own examples, its RPC, and the live discovery list, which is the
/// one thing none of the other three has.
///
/// **CONNECTING IS PICKING SEVERAL, AND IT NEVER ROUTES BY ITSELF (user
/// ruling, 2026-08-28).** Watching an address never takes the list away and
/// never leaves the page; the way to the room is the Activity row, which is a
/// tap of yours. Nothing here composes a room and then navigates: the read
/// still happens (see `reader`) so the room is warm when you knock.
///
/// **§465 IS AMENDED, NOT IGNORED.** That ruling — setup keeps what you do
/// ONCE, the room keeps what you do repeatedly — kept the roster off this
/// screen. There is no setup screen any more: the page a connected seat opens
/// IS its account, and "Watching · N" is the chassis's, on every seat. The
/// room's face rail keeps its own rename and its own picking.
///
/// Unlike Peer or Privacy Pools this seat owns its own addresses rather
/// than riding the watched wallets: a devnet account is not one of your
/// wallets, and vibenet is not a live network. That is also why there is
/// no cap — reads here are keyless and free, so there is no expensive tier
/// to ration.
struct VibenetScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @Bindable private var watch = VibenetWatch.shared
    private var connected: Bool { watch.connected }

    /// The page's one bar (§639 amendment): what is typed adds an address and
    /// filters the roster below at the same time.
    @State private var typed = ""
    @State private var sheet: AccountPageSheet?
    @State private var roster = DevnetRosterReader(seatID: VibenetIdentity.seatID,
                                                   source: VibenetIdentity.source)

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
        AccountPage(
            name: VibenetIdentity.source, seatID: VibenetIdentity.seatID,
            source: VibenetIdentity.source,
            state: AccountPageState.of(name: VibenetIdentity.source,
                                       seatID: VibenetIdentity.seatID,
                                       connected: connected, store: store),
            // ACTION, not a re-pitch (R4.4). You reach this screen from the
            // product page, which just said what vibenet is and what it reads.
            // What is left for this sentence is the only thing the pitch could
            // not say: what to do here, and that it is not a one-shot.
            intro: "Paste an address, or start with one that already has something to show. Watch as many as you like.",
            mode: .noAccount,
            rows: roster.rows,
            query: typed,
            onRemoveRow: unwatch,
            teardown: { VibenetBridge.disconnect(store: store) },
            sheet: $sheet,
            act: {
                DevnetAccountsAct(
                    watch: watch,
                    tint: Self.mark,
                    examples: Self.examples,
                    peek: { await DevnetPeek.read($0, via: VibenetChain.call(method:params:)) },
                    reader: reader,
                    register: { VibenetBridge.registerBridge(store: store) },
                    typed: $typed,
                    onWatched: { _ in readRows() })
            },
            more: {
                // The live half — real accounts created on the chain, which no
                // fixed list can carry. It answers a different question ("who
                // is using this today") and can fail on its own without taking
                // the examples above down with it.
                VibenetDiscoverySection(onWatched: {
                    reader.kick()
                    readRows()
                }, tint: Self.mark)
                DSSlabNote(text: String(localized: "Test ETH has no value, and the network may be reset without notice."), plain: true)
                DevnetExplorerRow(url: VibenetExplorer.base, plain: true)
            },
            keySheet: { EmptyView() }
        )
        .onAppear { readRows() }
        .onChange(of: watch.addresses) { _, _ in readRows() }
    }

    private func readRows() {
        Task {
            await roster.refresh(watch: watch, context: modelContext,
                                 peek: { await DevnetPeek.read($0, via: VibenetChain.call(method:params:)) })
        }
    }

    /// ONE verb, "Remove" (§639). Unwatching leaves the rows it already landed
    /// — dropping a source's things is the Disconnect dialog's own choice, and
    /// making it here would be a second, quieter answer to the same question.
    private func unwatch(_ address: String) {
        watch.remove(address)
        roster.forget(address)
        VibenetBridge.registerBridge(store: store)
        readRows()
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
