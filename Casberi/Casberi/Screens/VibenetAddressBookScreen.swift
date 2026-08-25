import SwiftUI

/// The vibenet address book (prd §465, 2026-08-24) — the accounts you
/// watch on Base's devnet, and every verb that manages them.
///
/// **Why this screen exists.** Reported: *"the set up screens need to feel
/// like they are only for set up."* `VibenetScreen` had become the connect
/// page AND the roster AND the rename/remove surface, which is the same
/// complaint §461 answered on the Wallet side, one seat over. The split
/// here is the ruling Alexander gave after it: **setup keeps what you do
/// once (the first address, the disconnect); the room keeps what you do
/// repeatedly.** So the roster moved here, one tap from the room it
/// describes — reachable from the vibenet face rail's book slot and from
/// the setup page's own door.
///
/// **What it deliberately does NOT copy from Wallet's book.** That one has
/// TWO tiers — five WATCHED addresses and an unlimited ledger of NAMES —
/// because on mainnet a watch costs a metered Zerion read on every
/// foreground and a name costs nothing. Vibenet reads a keyless devnet
/// RPC: watching is free, so there is no expensive tier to separate out.
/// One list, no cap counter, no "Everyone else" section, and no
/// `WalletStore.watchLimit` analog to state — a limit with no cost behind
/// it is a control that protects nothing (§83's shape).
///
/// **The structure is copied, never the type** (`AddressBookScreen`'s own
/// ruling): these hold different things under the same word, and
/// parameterising one screen by source is how the two start owing each
/// other behaviour neither wants.
struct VibenetAddressBookScreen: View {
    @Environment(BridgeStore.self) private var store
    @Bindable private var watch = VibenetWatch.shared

    @State private var room = VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false)
    @State private var loading = false
    /// An address watched (or unwatched) while a read is mid-flight
    /// requeues it — the `GeckoTerminal`/`Stocktwits` lesson, so the new
    /// address lands now rather than at the next visit.
    @State private var loadPending = false

    /// The naming alert — a text-entry alert needs `@State`, so it lives
    /// here rather than on the card the row belongs to. Non-nil is what
    /// drives the alert's `isPresented` binding.
    @State private var renamingAddress: String?
    @State private var renameText = ""

    /// A row's tap opens the detail sheet, keyed by the address itself
    /// (`String` is `Identifiable`, the `L2beatScreen`/`WalletbeatScreen`
    /// shape).
    @State private var opened: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    private var connected: Bool { watch.connected }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    VibenetWatchField(onWatched: { Task { await load() } }, syncing: loading)

                    // A door to Base's own demo, not a paragraph about it —
                    // it earns its place as a plain link rather than prose.
                    Link(destination: URL(string: "https://chain.base.org/demos/account")!) {
                        HStack(spacing: 3) {
                            Text(String(localized: "More Base Vibenet demos"))
                            Image(systemName: "arrow.up.right")
                        }
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(Self.mark)
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            // Only while nothing is watched — the moment there's a real
            // card on screen, a list of strangers' addresses is clutter,
            // not help.
            if !connected {
                Section {
                    VibenetDiscoverySection(onWatched: { Task { await load() } })
                }
                .dsSlabSection()
                .listRowSeparator(.hidden)
            }

            if connected {
                // THE MANAGING MODE. `onOpen` non-nil is what makes
                // `VibenetRoomCard` draw every watched account as a full
                // navigable row, uncapped, each with the context menu that
                // renames and stops watching — see that type's own header
                // doc. The feed room passes nil and gets the stat block
                // instead, which is the shape Alexander ruled for it
                // ("N accounts and balance, then the keys, then the
                // events") and which this screen must not disturb.
                VibenetRoomCard(room: room, onRemove: unwatch, onRename: { address in
                    renameText = watch.name(for: address) ?? ""
                    renamingAddress = address
                }, onOpen: { address in
                    opened = address
                })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

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
        .dsScreenTitle("Address Book")
        .sheet(item: $opened) { address in
            VibenetAccountSheet(address: address, room: room, onRemove: unwatch)
        }
        .alert(
            String(localized: "Name this account"),
            isPresented: Binding(
                get: { renamingAddress != nil },
                set: { if !$0 { renamingAddress = nil } })
        ) {
            TextField(String(localized: "Name"), text: $renameText)
            Button(String(localized: "Save")) {
                if let address = renamingAddress { watch.setName(renameText, for: address) }
                renamingAddress = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { renamingAddress = nil }
        }
        .onAppear {
            if connected { Task { await load() } }
        }
    }

    // MARK: - Actions

    /// Removing the LAST watched account disconnects the seat, so the chip
    /// goes with it — a connected seat holding no addresses is a room that
    /// can never say anything. `VibenetScreen` relies on this too: it is
    /// the only teardown besides the explicit Disconnect.
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
