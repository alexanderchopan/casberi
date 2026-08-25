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

    /// **SEEDED FROM THE LAST SAVED READ, not from an empty room (prd §472).**
    ///
    /// It began as `VibenetRoom.compose(items: [], … configReached: false)`,
    /// and `VibenetRoom.headline` tests `configReached` FIRST — so the first
    /// frame of the screen built to be your roster read **"Couldn't read
    /// vibenet's current contracts"**, every open, before a single request
    /// had been made. §83's fake status, on frame one, on the one screen that
    /// exists to list what you watch.
    ///
    /// `VibenetRoomSource.card()` is the synchronous snapshot the feed's own
    /// head has drawn from since §467 (`VibenetState`, UserDefaults) — this
    /// screen simply never asked for it. A snapshot is only ever saved after a
    /// read that reached the chain, so a seeded card is honest by
    /// construction, and the provenance note under it already says how old it
    /// is ("read 3h ago", §468).
    @State private var room: VibenetRoom
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

    /// Whether the discovery list is open. `@State`, so it shuts again when
    /// you leave — it is a lookup, not a preference, and a list of strangers'
    /// addresses left open forever is the clutter the old rule was protecting
    /// against.
    @State private var showDiscovery = false

    /// The address whose removal would take the whole seat with it — non-nil
    /// is what raises the confirm. See `unwatch`.
    @State private var removingLast: String?

    /// A row's tap opens the detail sheet, keyed by the address itself
    /// (`String` is `Identifiable`, the `L2beatScreen`/`WalletbeatScreen`
    /// shape).
    @State private var opened: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// `@MainActor` because `VibenetRoomSource.card()` is — it consults
    /// `DemoMode`. Every construction of this screen is from a `View` body,
    /// which is already main-actor, so the annotation costs nothing.
    @MainActor
    init() {
        _room = State(initialValue: VibenetRoomSource.card()
            ?? VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false))
    }

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

            // **OPEN BY DEFAULT WHILE NOTHING IS WATCHED; A DOOR AFTERWARDS
            // (prd §472).** The old rule was "only while nothing is watched",
            // on the reasoning that once a real card is on screen a list of
            // strangers' addresses is clutter rather than help. That is right
            // for the SETUP page, which `VibenetScreen` still keeps it on —
            // and wrong here: §465 gave this screen the acts you do
            // REPEATEDLY, and finding another account to watch is the most
            // repeatable one there is. Vanishing forever after the first watch
            // left the only way to a second account being to type forty hex
            // characters by hand.
            //
            // Collapsed rather than merely moved down, because the original
            // reasoning still holds about the SPACE: shut, it is one row.
            // `VibenetDiscoverySection` loads on appear, so nothing is fetched
            // until somebody opens it.
            if !connected || showDiscovery {
                Section {
                    VibenetDiscoverySection(onWatched: { Task { await load() } })
                }
                .dsSlabSection()
                .listRowSeparator(.hidden)
            } else {
                // **A TEXT BUTTON, NOT A SLAB (2026-08-25, prd §476).**
                // Reported: *"in address book the 'find another account' is
                // designed poorly."* It was a `DSSlabDoor` on a clear row —
                // a full-width slab floating between the watch field's own
                // slab section and the roster card, belonging to neither and
                // matching nothing else on the screen.
                //
                // This screen already has the right pattern for a quiet
                // secondary verb, three rows up: the "More Base Vibenet
                // demos ↗" link under the watch field. Same rung, same
                // weight, same tint — so the screen has ONE way of saying
                // "here is something else you can do" instead of two.
                Section {
                    Button {
                        DSHaptic.selection()
                        withAnimation(DS.Motion.standard) { showDiscovery = true }
                    } label: {
                        HStack(spacing: 3) {
                            Text(String(localized: "Find another account"))
                            Image(systemName: "chevron.down")
                                .dsGlyph(9, weight: .semibold)
                        }
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(Self.mark)
                        .lineLimit(1)
                        .fixedSize()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // …and on the FIRST-EVER open, where there is no snapshot to seed
            // from, the card is withheld entirely while the read is in flight
            // rather than drawn over an empty room — the same false failure by
            // another route. `VibenetWatchField` above is already saying
            // "Reading vibenet…", so the screen is not silent, and the moment
            // the read lands this becomes the real roster or the card's own
            // honest failure headline.
            if connected, !room.items.isEmpty || !loading {
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
        // A PULL RE-READS (prd §472). This screen is nothing but a live read
        // of a devnet, and its only read was `onAppear` — so a lock that
        // opened, a key that was revoked or a balance that moved while you sat
        // here needed you to leave the screen and come back. The room behind
        // it has had a pull since it shipped; the screen that lists the same
        // accounts did not.
        .refreshable { await load() }
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Address Book")
        .sheet(item: $opened) { address in
            VibenetAccountSheet(address: address, room: room, onRemove: unwatch)
        }
        .confirmationDialog(
            String(localized: "Stop watching your last account?"),
            isPresented: Binding(get: { removingLast != nil },
                                 set: { if !$0 { removingLast = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Stop watching"), role: .destructive) {
                if let address = removingLast { commitUnwatch(address) }
                removingLast = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { removingLast = nil }
        } message: {
            // What actually happens, in the words of the things it happens to
            // — never "this cannot be undone", which is true of most taps and
            // tells you nothing about this one.
            Text(String(localized: "It's the only account you watch, so vibenet disconnects: the chip leaves the source strip, and the names you gave your accounts are forgotten."))
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
    ///
    /// **AND THAT IS WHY THE LAST ONE ASKS (prd §472).** Every other unwatch
    /// removes a row; this one tears down the seat, drops the chip out of the
    /// source strip, forgets the room snapshot and the seen-keys ledger, and
    /// leaves the person on a screen whose subject has just ceased to exist —
    /// all from one tap of a context-menu item sitting where "remove this row"
    /// sat a moment ago. Two different acts should not share one gesture with
    /// no warning between them. The ordinary case is untouched and stays
    /// immediate: a confirm on every removal would be the dialog nobody reads.
    private func unwatch(_ address: String) {
        guard watch.addresses.count > 1 else {
            removingLast = address
            return
        }
        commitUnwatch(address)
    }

    /// The removal itself, past whatever asking was owed.
    private func commitUnwatch(_ address: String) {
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
