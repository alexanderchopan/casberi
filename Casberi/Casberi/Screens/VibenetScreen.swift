import SwiftUI

/// Base "vibenet", connected — watch a devnet address and see its
/// EIP-8130 account-abstraction state: is it established, which actors can
/// act for it, is it locked. No account, no key — a plain `0x` address,
/// read straight off vibenet's own keyless RPC. Nothing here lands as a
/// `Thing`: unlike Peer or Privacy Pools, a devnet test account has no story
/// for the corpus, so this screen IS the whole feature, the way
/// `SafeScreen` draws `SafeSigner`'s standing directly rather than through
/// the feed.
struct VibenetScreen: View {
    @Environment(BridgeStore.self) private var store
    @State private var addressField = ""
    @FocusState private var fieldFocused: Bool
    @State private var addResult: String?
    @State private var addResultIsError = false

    @State private var room = VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false)
    @State private var loading = false
    /// An address watched (or unwatched) while a read is mid-flight requeues
    /// it — the `GeckoTerminal`/`Stocktwits` lesson, so the new address
    /// lands now rather than at the next visit.
    @State private var loadPending = false

    @Bindable private var watch = VibenetWatch.shared
    private var connected: Bool { watch.connected }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Base Vibenet",
                mode: .noAccount,
                intro: "An experimental Base devnet with no real funds — this only ever reads a watched address's account-abstraction state. vibenet's contracts redeploy often, so every read names the exact commit it saw.",
                connected: connected)

            watchSection.listRowSeparator(.hidden)

            if connected {
                VibenetRoomCard(room: room, onRemove: unwatch)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ChipLiveNote(name: "Base Vibenet", verb: "for the accounts you watch.")
                    .listRowSeparator(.hidden)
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
        .onAppear {
            // Opening the screen doesn't connect — pasting an address does.
            // Only read when something's already watched: viewing isn't
            // consent to reach the chain.
            if connected { Task { await load() } }
        }
    }

    // MARK: - Sections

    private var watchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(
                    placeholder: String(localized: "0x… devnet address"),
                    text: $addressField,
                    actionLabel: String(localized: "Watch"),
                    focus: $fieldFocused,
                    isArmed: VibenetWatch.isValidAddress(addressField.trimmingCharacters(in: .whitespacesAndNewlines)),
                    action: watchTyped)

                BridgeSyncStatusRows(
                    syncing: loading,
                    syncingLine: String(localized: "Reading vibenet…"),
                    result: addResult, resultIsError: addResultIsError)

                DSSlabNote(text: "Read-only, no funds, no signing. vibenet redeploys its contracts periodically, so an address's own state can change day to day.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Actions

    private func watchTyped() {
        let address = addressField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VibenetWatch.isValidAddress(address) else {
            addResult = String(localized: "That doesn't look like a devnet address — it needs to be 0x followed by 40 hex characters.")
            addResultIsError = true
            return
        }
        DSHaptic.tap()
        guard watch.add(address) else {
            addResult = String(localized: "Already watching that address.")
            addResultIsError = false
            addressField = ""
            return
        }
        addressField = ""
        addResult = nil
        VibenetBridge.registerBridge(store: store)
        Task { await load() }
    }

    private func unwatch(_ address: String) {
        DSHaptic.tap()
        watch.remove(address)
        if watch.connected {
            VibenetBridge.registerBridge(store: store)
            Task { await load() }
        } else {
            VibenetBridge.disconnect(store: store)
            room = VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false)
        }
    }

    /// Reads every watched address and composes the card; the seat's proof
    /// line carries the count.
    private func load() async {
        if loading { loadPending = true; return }
        loading = true
        defer { loading = false }
        repeat {
            loadPending = false
            let composed = await VibenetRoomSource.compose()
            room = composed
            guard watch.connected else { return }
            VibenetBridge.registerBridge(store: store)
        } while loadPending && watch.connected
    }
}
