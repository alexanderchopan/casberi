import SwiftUI

/// Base "vibenet", connected — watch a devnet address and see its
/// EIP-8130 keystore state: is it established, which actors can
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

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// The empty state's own fix: nobody arrives at a devnet already
    /// holding an address for it. Fetched once per screen visit, off
    /// `Keystore`'s `AccountCreated` — real accounts, not a demo prop.
    @State private var discovered: [VibenetDiscoveredAccount] = []
    @State private var discoveryLoading = false
    @State private var discoveryAttempted = false

    /// The naming alert — a text-entry alert needs `@State`, so it lives
    /// here rather than on the card the row belongs to. Non-nil is what
    /// drives the alert's `isPresented` binding.
    @State private var renamingAddress: String?
    @State private var renameText = ""

    /// R3.2 — a row's tap opens the detail sheet, keyed by the address
    /// itself (`String` is `Identifiable`, the `L2beatScreen`/
    /// `WalletbeatScreen` shape).
    @State private var opened: String?

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Base Vibenet",
                mode: .noAccount,
                // ACTION, not a re-pitch (R4.4). You reach this screen from
                // the product page, which just said what vibenet is and
                // what it reads — so an intro describing the same thing
                // again is the same information twice, one tap apart. The
                // mode chip already carries the cost ("No account"), and
                // the card's own provenance line names the commit under
                // every read. What is left for this sentence is the only
                // thing the pitch could not say: what to do here.
                intro: "Paste an account address, or watch one of the examples below.",
                connected: connected)

            // A DOOR, not a signpost (R4.5) — and it leads the connected page
            // rather than trailing the room card, which on a busy watch list
            // put it below the fold (§460). The pop-then-ask ordering this
            // screen used to spell out by hand now lives in `RoomDoor`, shared
            // with the sixteen screens that were still signposts.
            if connected {
                RoomDoor(name: "Base Vibenet", source: VibenetIdentity.source)
                    .listRowSeparator(.hidden)
            }

            watchSection.listRowSeparator(.hidden)

            // Only while the watch list is empty — the moment there's a
            // real card on screen, a list of strangers' addresses is
            // clutter, not help.
            if !connected {
                discoverySection.listRowSeparator(.hidden)
            }

            if connected {
                VibenetRoomCard(room: room, onRemove: unwatch, onRename: { address in
                    renameText = watch.name(for: address) ?? ""
                    renamingAddress = address
                }, onOpen: { address in
                    opened = address
                })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
            // Opening the screen doesn't connect — pasting an address does.
            // Only read when something's already watched: viewing isn't
            // consent to reach the chain.
            if connected { Task { await load() } }
            else if !discoveryAttempted { Task { await loadDiscovery() } }
        }
    }

    // MARK: - Sections

    /// Real, recently-created vibenet accounts, one tap to watch. This is
    /// STILL a read, not a connection — `AccountCreated` names no owner, so
    /// nothing about looking at this list is different from opening the
    /// setup screen at all; watching only happens on the explicit tap,
    /// exactly like pasting an address by hand.
    /// A fixed, always-available account to peek at — a fallback for the
    /// empty state's own fix, useful especially when live discovery can't
    /// reach the chain at all (the `Couldn't reach vibenet…` branch below,
    /// which otherwise leaves a new user with nothing to tap). Watched
    /// exactly like any pasted or discovered address; nothing about
    /// tapping it is different from typing it in by hand.
    private static let peekAddress = "0x777804FDCc280c082Db9788EAE5BEca0Fc2BeD9b"

    private var discoverySection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if discoveryLoading {
                    BridgeSyncStatusRows(
                        syncing: true, syncingLine: String(localized: "Looking for accounts on vibenet…"),
                        result: nil, resultIsError: false)
                } else if discovered.isEmpty {
                    if discoveryAttempted {
                        Text("Couldn't reach vibenet to find an account to suggest — paste an address above, peek at an example, or open the explorer to find one.")
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                    }
                } else {
                    Text(String(localized: "Recently created on vibenet"))
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                    ForEach(discovered) { account in
                        discoveryRow(address: account.address, subtitle: account.createdAt.map {
                            String(localized: "Created \($0.formatted(.relative(presentation: .named)))")
                        })
                    }
                }
                // Always offered, live discovery or not — a real address,
                // always watchable, so a new user is never stuck with
                // nothing to tap while waiting on (or after losing) a
                // network read.
                discoveryRow(address: Self.peekAddress, subtitle: String(localized: "Peek at an example account"))
            }
        }
        .dsSlabSection()
    }

    /// One row, shared by a discovered account and the fixed peek address —
    /// same face, same short-address line, same trailing "Watch" verb, so
    /// the peek option reads as one more real account rather than a
    /// visually distinct special case.
    private func discoveryRow(address: String, subtitle: String?) -> some View {
        Button {
            DSHaptic.tap()
            guard watch.add(address) else { return }
            VibenetBridge.registerBridge(store: store)
            Task { await load() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                WalletFace(address: address, size: 24, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(VibenetRoom.shortAddress(address))
                        .dsText(.label12).monospaced()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    // Omitted rather than guessed when the block-time
                    // lookup failed — the same rule `expiryLabel` follows
                    // for its own clock fact.
                    if let subtitle {
                        Text(subtitle)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                Text(String(localized: "Watch"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(Self.mark)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The typed address, trimmed once — kept separate from
    /// `watchTyped()`'s own trim so the preview below reads cleanly, not
    /// because the two must ever disagree.
    private var draft: String {
        addressField.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The address the preview is about, or nil while the field holds
    /// nothing that's already a valid one. Unlike `WalletScreen`'s own
    /// version, there is no name to resolve here — vibenet has no ENS/SNS
    /// registrar of its own (`VibenetWatch.isValidAddress`'s own doc: a
    /// pasted name that isn't already hex simply is not a vibenet
    /// address) — so this is a plain validity check, not a debounced
    /// network round-trip.
    private var previewAddress: String? {
        VibenetWatch.isValidAddress(draft) ? draft : nil
    }

    /// What the typed address resolves to, RIGHT NOW — `WalletScreen
    /// .addressPreview`'s own reasoning, mirrored: the setup screen's
    /// whole job is the moment between pasting an address and committing
    /// it, and until this it said nothing in that moment. The face costs
    /// NOTHING (`WalletFace`'s identicon is deterministic from the
    /// address, so this is the exact same face the row will wear, drawn
    /// a second early) and `watch.isWatching` is a plain array scan — no
    /// balance, no live chain read, and no name resolution (see
    /// `previewAddress`'s own doc for why vibenet has none to attempt):
    /// any of those would be a metered call fired on every keystroke, and
    /// a live fact about an account nobody has agreed to watch is a claim
    /// this screen hasn't earned yet.
    @ViewBuilder
    private var addressPreview: some View {
        if let address = previewAddress {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: address, size: 40, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(watch.name(for: address) ?? VibenetRoom.shortAddress(address))
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(watch.isWatching(address) ? String(localized: "Already watching")
                                                    : String(localized: "New address"))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s2)
            .padding(.horizontal, DS.Space.s3)
            .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

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

                // What you're about to watch, before you watch it — the
                // `WalletScreen.addressPreview` shape, so both setup
                // screens answer the same question the same way while
                // you're mid-paste. Keyed on `previewAddress` so the
                // spring runs when the FACE arrives, not on every
                // keystroke that doesn't yet resolve to one.
                addressPreview
                    .animation(DS.Motion.standard, value: previewAddress)

                // NO slab note here. It used to read "Read-only, no funds,
                // no signing. vibenet redeploys its contracts periodically,
                // so an address's own state can change day to day." — which
                // is the intro sentence above it again, all three claims,
                // in different words. §315's budget is one mode chip and one
                // intro; a second paragraph restating it is not fine print,
                // it is the same print twice.
                BridgeSyncStatusRows(
                    syncing: loading,
                    syncingLine: String(localized: "Reading vibenet…"),
                    result: addResult, resultIsError: addResultIsError)

                // A door to Base's own demo, not a paragraph about it —
                // §315's budget is one mode chip and one intro, so this
                // earns its place as a plain link rather than more prose.
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

    /// The empty state's own read — once per screen visit, never re-run by
    /// `load()` (which is about watched addresses, a different question).
    /// Silent on failure: `discovered` simply stays empty and the section
    /// says so, the same honest-nothing shape every other empty state here
    /// already uses.
    private func loadDiscovery() async {
        discoveryLoading = true
        defer { discoveryLoading = false; discoveryAttempted = true }
        guard let contracts = await VibenetConfig.current() else { return }
        discovered = await VibenetDiscovery.recentAccounts(keystore: contracts.keystore)
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
