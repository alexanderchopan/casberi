import SwiftUI
import SwiftData

/// The wallet things already in the corpus — newest first. A @Query so the
/// list updates live and the fetch runs once per store change, not twice per
/// body pass.
private let walletRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Wallet" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Wallet, connected — the wallet's home in Casberi. The person manages WHICH
/// addresses are watched (paste to add, swipe to remove, drag to reorder — the
/// first address leads), sees a live holdings treemap (top 5 by USD value), and
/// sees what's landed (recent onchain things from the corpus). Read-only,
/// stated plainly: watching an address can never trade or move funds. Both the
/// holdings and the activity are live from Alchemy, read on this iPhone — no
/// server.
struct WalletScreen: View {
    @Bindable private var wallet = WalletStore.shared
    /// Which chains are read (2026-07-15) — the person can narrow the five to
    /// the ones they care about; toggling re-syncs.
    @Bindable private var chainStore = WalletChainStore.shared
    @State private var newAddress = ""
    @FocusState private var addressFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    /// The combined "bundle" treemap across every watched wallet (2026-07-15) —
    /// shown alongside the per-wallet charts when more than one is watched.
    /// The combined "Across your wallets" sheet — the full decomposed read
    /// (the combined line, then each wallet's own line in its face's color).
    @State private var result: String?
    @State private var resultIsError = false
    /// True when a non-error result still needs the person's eyes (the
    /// typo'd-address nudge). Everything else whispers in Watching's header
    /// — fine is silent (redesign 2026-07-20).
    @State private var resultProminent = false
    /// The in-flight WalletConnect handshake — proposed, wallet opened, waiting
    /// on a human to approve over there (2026-07-16). Held as the Task rather
    /// than a Bool so a second tap can CANCEL it: the wait runs to the
    /// proposal's 5-minute expiry, and a person who opened their wallet, chose
    /// not to approve, and came back must not find a stuck button and no way
    /// out. Separate from `syncing` — that one means "reading chains", this one
    /// means "waiting on your wallet", and collapsing them puts the wrong line
    /// on screen.
    @State private var connectTask: Task<Void, Never>?
    /// Bumped on every start and every cancel, so an in-flight handshake can
    /// tell whether it's still the CURRENT one. Cancellation only lands at the
    /// next suspension point — a cancelled handshake sitting in the relay
    /// round-trip can take a second to unwind — so without this, "cancel, then
    /// tap Connect again" lets the dying task's cleanup clear the new task's
    /// handle and write the new task's outcome.
    @State private var connectGeneration = 0
    private var connecting: Bool { connectTask != nil }
    /// A tapped holdings cell: the token's thing sheet when watched, the
    /// quick chart sheet when not.
    @State private var openTokenThing: Thing?
    @State private var quickToken: TokenQuickRoute?
    /// Which wallet the rename alert is editing (2026-07-20, the door purge:
    /// manage is ONE page now — the per-wallet screen is deleted, so the row's
    /// tap went back to being the rename prompt it was before the collapse).
    @State private var renamingID: WalletStore.WatchedAddress.ID?
    @State private var renameDraft = ""
    /// Whether the Chains row is expanded (2026-07-15) — collapsed by
    /// default to a one-line summary ("Ethereum, Base +3"); a set-once
    /// setting doesn't deserve six full-height rows every visit.
    @State private var chainsExpanded = false
    @State private var confirmDisconnect = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    /// The one swipe lesson, shared across every screen that pins by swipe
    /// (2026-07-11) — whichever screen a person meets the gesture on first
    /// retires it everywhere.
    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    @Query(walletRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            // Empty state: the add field and the vitalik chip ARE the
            // screen — nothing to lead with yet. Connected state: the
            // watched wallets and their approvals lead (prd §104), value
            // views and activity follow, admin (add / chains) at the bottom.
            if wallet.addresses.isEmpty {
                addSection.listRowSeparator(.hidden)
                footerSection.listRowSeparator(.hidden)
                // The empty state reports too (2026-07-16). This section used
                // to exist only in the connected branch below, so with nothing
                // watched yet every outcome was set and then silently dropped
                // — a mistyped ENS name answered with nothing at all, in the
                // exact state where a first-time typo is likeliest. Found while
                // wiring Connect, whose "no wallet app" line vanished the same
                // way.
                statusSection
            } else {
                // THIS SCREEN IS THE PLUMBING (2026-07-20, the surface split —
                // user: "isn't that supposed to be for just the app
                // connection?"). It answers one question: what am I watching,
                // and how? Warnings, the combined value bundle, and the recent
                // transactions all moved to the Wallet FEED, where you look at
                // them; per-wallet holdings/DeFi/safety stay one row down in
                // the feed's tiles and tray. What's left is watching, adding, chains,
                // and disconnecting — a connection screen, like every other
                // bridge's.
                watchingSection.listRowSeparator(.hidden)
                // Three cards, one idiom (user, 2026-07-20: "it looks like a
                // bunch of stuff mashed together") — watching, add, admin.
                // Status WHISPERS in Watching's header when all is well and
                // becomes a row only for errors and the typo'd-address nudge.
                addSection.listRowSeparator(.hidden)
                adminSection.listRowSeparator(.hidden)
                statusSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftTopEdge()
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.large)
        .alert("Name this wallet",
               isPresented: Binding(get: { renamingID != nil },
                                    set: { if !$0 { renamingID = nil } })) {
            TextField("Name (e.g. Main, Cold)", text: $renameDraft)
            Button("Save") {
                if let id = renamingID {
                    wallet.rename(id, to: renameDraft)
                    DSHaptic.success()
                }
                renamingID = nil
            }
            Button("Cancel", role: .cancel) { renamingID = nil }
        } message: {
            Text("A blank name shows the address instead.")
        }
        .toolbar {
            // Reorder/remove live behind Edit — drag to sort, red-minus to drop.
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(DS.textPrimary) }
        }
        .onAppear {
            if !wallet.addresses.isEmpty {
                sync()
                Task { await wallet.loadAvatars() }
            }
        }
        // A tapped holdings cell (2026-07-14): the token's own chart — its
        // thing sheet when watched, the quick sheet when it's just held.
        // ("@wallet" — the native-coin fallback — is a no-op here: this IS
        // the Wallet screen.)
        .environment(\.genProjectTap) { name in
            guard let route = TokenQuickRoute.from(sentinel: name) else { return }
            if let thing = route.watchedThing(in: modelContext) {
                openTokenThing = thing
            } else {
                quickToken = route
            }
        }
        .sheet(item: $openTokenThing) { thing in
            ThingSheetView(thing: thing)
        }
        .sheet(item: $quickToken) { route in
            TokenQuickSheet(route: route)
        }
        // A Watching row's whole tap target (2026-07-20) — the per-wallet
        // screen carries everything that used to be a top-level section
        // (approvals, gas, DeFi, Safe) plus renaming, scoped to just this
        // wallet. Local push, matching `AppsScreen`'s own catalog-tile
        // idiom — no shell-level route needed for a destination reached
        // from exactly one place.
    }

    /// Reads the chain and lands new transactions — the plumbing screen's one
    /// job on appear. RESTORED 2026-07-20: the surface split's block cuts
    /// accidentally deleted this member, and the `sync()` call in onAppear
    /// kept compiling by resolving to POSIX `sync(2)` — two green builds were
    /// flushing disk buffers instead of reading chains, with no compiler
    /// diagnostic to catch it. The fan-out the old body did for the warnings
    /// band and portfolio bundle lives in `WalletWatch.liveState` (the feed's
    /// tiles) now; what belongs here is landing, the honest status line, and
    /// the seat registration.
    private func sync() {
        guard !syncing else { return }
        syncing = true
        Task {
            let added = await WalletIngest.refresh(context: modelContext)
            // Holdings, only as a BOOLEAN — the typo'd-address nudge below
            // needs "nothing found anywhere", and the coalesced holdings
            // cache makes the read cheap. Never displayed here: the reads
            // live on the feed (user ruling, 2026-07-20).
            let totals = await WalletIngest.topHoldingsByWallet()
            syncing = false
            // A bridge only registers "connected" once it actually reached
            // the chain — a bad key or offline device must never claim
            // success (review 2026-07-08).
            guard let added else {
                result = String(localized: "Couldn't reach the chain — check your connection.")
                resultIsError = true
                return
            }
            resultIsError = false
            let nothingFound = added == 0 && totals.allSatisfy { $0.totalUSD < 1 }
            if added > 0 {
                result = String(localized: "\(added) new")
                resultProminent = false
            } else if nothingFound && wallet.addresses.count == 1 {
                result = String(localized: "No activity found on your chains yet — double-check the address, or give it a moment.")
                resultProminent = true
            } else {
                result = String(localized: "Connected — watching for activity.")
                resultProminent = false
            }
            let proof = added > 0 ? "\(added) new" : "Synced just now"
            if store.registerConnected(id: "wallet", name: "Wallet", proof: proof,
                                       can: ["Reads your wallet's activity.",
                                             "Read-only — never trades or moves funds."]) {
                DSHaptic.success()
            }
        }
    }

    // MARK: - Watching (add / remove / sort / pin)

    /// Each watched address carries its own pin now (ruling 2026-07-09): a
    /// wallet's holdings show on Home and Feed only when THAT wallet is
    /// pinned — watching more than one is usually two different purposes
    /// (main vs. cold), and a shared switch couldn't say which one it meant.
    /// Pin lives on the swipe alone now (2026-07-11) — the row briefly also
    /// carried an inline toggle, but a second control for the exact same
    /// verb read as two different actions rather than one (user: "confusing
    /// which is which"); the row shows its pin state passively instead
    /// (Feed's grammar), and the swipe hint nudge covers discoverability.
    private var watchingSection: some View {
        Section {
            ForEach(wallet.addresses) { addr in
                // Tap = rename (an alert, not a door — user, 2026-07-20: "the
                // manage screen should really be one page with no doors").
                // The per-wallet screen this row used to push is deleted: its
                // remove lived on the swipe already, and its safety facts are
                // the Worth-a-look tray's rows whenever they're true — every
                // delegation and pending Safe queue IS a warning there, so
                // the page held nothing the feed doesn't state better.
                Button {
                    DSHaptic.tap()
                    renameDraft = addr.label
                    renamingID = addr.id
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        // The wallet's face (2026-07-15): its ENS avatar when it
                        // published one, else a deterministic identicon — so
                        // watching three wallets no longer means three identical
                        // blue icons.
                        WalletFace(address: addr.address, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addr.label.isEmpty ? addr.short : addr.label)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            // The address, always — identity, not a read
                            // (user, 2026-07-20: the value subline and
                            // sparkline these rows carried were holdings on
                            // the plumbing screen; the feed's Balance tile is
                            // where value lives now).
                            if !addr.label.isEmpty {
                                Text(addr.short).dsText(.subhead13)
                                    .foregroundStyle(DS.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsListCardRow()
                .modifier(SwipeHintNudge(active: addr.id == hintAddressID) { swipeCoachDone = true })
                // Pin retired with the board (2026-07-20) — Remove is now the
                // swipe group's ONLY action. `allowsFullSwipe` was true when
                // a full swipe meant Pin (Feed's own reversible grammar); left
                // true here it would let a full swipe delete a watched wallet
                // by accident, so it drops to false now that Remove is all
                // that's left.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        if let i = wallet.addresses.firstIndex(where: { $0.id == addr.id }) {
                            wallet.remove(at: IndexSet(integer: i))
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            .onDelete { wallet.remove(at: $0) }
            .onMove { wallet.move(from: $0, to: $1) }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Watching").dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
                // Sync state at whisper weight — the same voice the feed's
                // source pill uses. Trouble gets a real row (statusSection);
                // fine gets four quiet letters here.
                Text(quietStatus).dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            }
        } footer: {
            Text("Tap to rename · swipe to remove")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Chains (2026-07-15)

    /// Which chains to read across every watched wallet — collapsed to a
    /// one-line summary by default (2026-07-15: six full-height checkmark
    /// rows was a lot of ceremony for a set-once setting); tap to expand
    /// into the GeckoTerminal/OpenSea checklist idiom. Default all-on;
    /// toggling narrows the reads and re-syncs. Never lets the last chain
    /// off (the store guards it).
    /// The plumbing card (redesign 2026-07-20): Chains and Disconnect share
    /// one surface at the bottom — settings, not the point — under the one
    /// footer that states the read-only promise. Disconnect keeps
    /// `BridgeDisconnectSection`'s exact keep-or-purge dialog; the shared
    /// component couldn't merge into this card (a Section is a card in
    /// insetGrouped), so the wallet carries its own copy of the same verbs.
    private var adminSection: some View {
        Section {
            Button {
                DSHaptic.tap()
                withAnimation(.easeInOut(duration: 0.2)) { chainsExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.s3) {
                    Text("Chains")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                    Text(chainsSummary)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    Image(systemName: chainsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsListCardRow()
            if chainsExpanded {
                ForEach(WalletChainStore.selectable, id: \.id) { chain in
                    Button {
                        toggleChain(chain.id)
                    } label: {
                        HStack(spacing: DS.Space.s3) {
                            Text(chain.name)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                            Spacer()
                            if chainStore.isSelected(chain.id) {
                                Image(systemName: "checkmark")
                                    .dsText(.body17).foregroundStyle(DS.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dsListCardRow()
                }
            }
            Button(role: .destructive) { confirmDisconnect = true } label: {
                Text("Disconnect Wallet")
                    .dsText(.body17)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .dsListCardRow()
            .confirmationDialog("Disconnect Wallet?", isPresented: $confirmDisconnect,
                                titleVisibility: .visible) {
                Button("Keep its things") { disconnectWallet(purge: false) }
                Button("Remove its things too", role: .destructive) { disconnectWallet(purge: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Stops new Wallet things from landing. What already landed stays yours unless you remove it.")
            }
        } footer: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if chainsExpanded {
                    Text("Read each watched wallet across these chains only — turn off the ones you don't use.")
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                }
                Text("Read-only — watching can never trade or move funds. Activity is public, read across chains directly on this iPhone.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
        }
    }

    private func disconnectWallet(purge: Bool) {
        if purge {
            let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
            let doomed = all.filter { $0.source == "Wallet" }
            SpotlightIndex.remove(ids: doomed.map(\.id))
            for thing in doomed { modelContext.delete(thing) }
            modelContext.saveHonestly()
        }
        // Clear the store first so a refresh racing the dismiss can't re-add
        // the seat, then drop the seat itself (BridgeDisconnectSection's own
        // ordering, kept verbatim).
        WalletStore.shared.addresses = []
        store.remove("wallet")
        DSHaptic.tap()
        dismiss()
    }

    /// "All 5" when nothing's narrowed, else the selected names ("Ethereum,
    /// Base +3" past two) — the collapsed row's one-line fact.
    private var chainsSummary: String {
        let selected = WalletChainStore.selectable.filter { chainStore.isSelected($0.id) }
        if selected.count == WalletChainStore.selectable.count { return "All \(selected.count)" }
        let names = selected.map(\.name)
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }

    private func toggleChain(_ id: String) {
        DSHaptic.tap()
        chainStore.toggle(id)
        // Re-read holdings and activity over the new chain set, and rebuild the
        // value lines the dropped chain may have fed.
        sync()
    }

    /// The row that plays the swipe demo — the first watched address, once
    /// ever, retiring the moment any screen's demo (or a real swipe) does.
    private var hintAddressID: WalletStore.WatchedAddress.ID? {
        guard !swipeCoachDone else { return nil }
        return wallet.addresses.first?.id
    }

    /// What just happened — the spinner while chains are read, then the outcome
    /// line. Rendered in BOTH the empty and connected states; see the note at
    /// the call site.
    @ViewBuilder
    private var statusSection: some View {
        // A status ROW only when something needs eyes: an error, the
        // typo'd-address nudge, or the empty screen's connect flow (where
        // there's no Watching header to whisper in). The connected screen's
        // happy path whispers in `quietStatus` instead — the green
        // "connected" card read as noise dressed as news.
        if wallet.addresses.isEmpty || resultIsError || resultProminent {
            if syncing || result != nil {
                Section {
                    BridgeSyncStatusRows(syncing: syncing,
                                         syncingLine: String(localized: "Reading onchain activity…"),
                                         result: result, resultIsError: resultIsError)
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    /// The Watching header's trailing whisper — sync state at label weight.
    private var quietStatus: String {
        if syncing { return String(localized: "Syncing…") }
        guard result != nil, !resultIsError, !resultProminent else { return "" }
        return String(localized: "Synced just now")
    }

    private var addSection: some View {
        Section {
            // The weights flip with state (redesign 2026-07-20): on the EMPTY
            // screen, adding IS the page, so Connect leads in full prominence
            // (the fast path — a wallet hands its address over instead of
            // someone copying 42 hex characters; ruling 2026-07-16). On the
            // CONNECTED screen adding is a side errand: the universal paste
            // field leads and Connect becomes a quiet row in the same card —
            // the blue slab outranked everything on a page it wasn't the
            // point of. Both states: absent entirely when no project id is
            // configured (a control that can't work doesn't appear).
            if wallet.addresses.isEmpty, WalletConnectBridge.isAvailable { connectRow }
            BridgeFieldRow(placeholder: "Address (0x…, ENS, or .sol)", text: $newAddress,
                           buttonLabel: "Watch", keyboard: .default,
                           focus: $addressFieldFocused, action: watch)
            if !wallet.addresses.isEmpty, WalletConnectBridge.isAvailable { connectQuietRow }
            // Nothing watched yet, nothing on the clipboard — one tap watches
            // a famous public wallet so the whole feature (holdings, activity,
            // faces, charts) demos in three seconds. Watch-only makes peeking
            // at vitalik.eth entirely legitimate; the chip retires the moment
            // any address is watched.
            if wallet.addresses.isEmpty {
                Button {
                    DSHaptic.tap()
                    newAddress = "vitalik.eth"
                    watch()
                } label: {
                    HStack(spacing: DS.Space.s1) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Peek at vitalik.eth")
                            .dsText(.subhead13).fontWeight(.medium)
                    }
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s2)
                    .background(DS.tint.opacity(0.12), in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: DS.Space.s1, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        } header: {
            // "Add a wallet", not "Watch an address": with Connect leading the
            // section, the header has to name both ways in — connecting hands
            // an address over, it doesn't type one.
            Text("Add a wallet").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            if wallet.addresses.isEmpty {
                Text(WalletConnectBridge.isAvailable
                     ? "Connect your wallet to hand its address over, or paste any address, ENS, or .sol name — holdings and activity land in your feed. Connecting asks for nothing but the address."
                     : "Paste a wallet address, an ENS name, or a .sol name — its holdings and activity land in your feed.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
        }
    }

    /// The connected screen's Connect — a row in the add card, not a slab.
    /// Same action, same cancel-while-waiting contract as `connectRow`; only
    /// the weight changes with the state around it.
    private var connectQuietRow: some View {
        Button {
            DSHaptic.tap()
            if connecting { cancelConnect() } else { connectWallet() }
        } label: {
            HStack(spacing: DS.Space.s3) {
                if connecting {
                    ProgressView().controlSize(.small).tint(DS.textSecondary)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(connecting ? "Waiting for your wallet — tap to cancel"
                                    : "Connect a wallet app")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    if !connecting {
                        Text("Hands over the address — read-only, never signs")
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .animation(DS.Motion.standard, value: connecting)
        }
        .buttonStyle(.plain)
        .dsListCardRow()
    }

    /// "Connect wallet" — one tap, then approve in the wallet that opens; while
    /// waiting, the same button cancels.
    ///
    /// Never disabled, so there's no disabled background to get wrong (prd
    /// §83): waiting is a state you can leave, not a state that locks the
    /// screen. The label says so rather than leaving "tap again to cancel" as
    /// folklore — a control whose only exit is invisible is a dead control
    /// wearing a spinner.
    private var connectRow: some View {
        Button {
            DSHaptic.tap()
            if connecting { cancelConnect() } else { connectWallet() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                if connecting {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "wallet.bifold")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(connecting ? "Waiting for your wallet — cancel" : "Connect wallet")
                    .dsText(.callout15).fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(DS.tint, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .animation(DS.Motion.standard, value: connecting)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: DS.Space.s1, leading: DS.Space.s4,
                                  bottom: DS.Space.s2, trailing: DS.Space.s4))
    }

    private func cancelConnect() {
        connectGeneration &+= 1   // orphans the in-flight task before it unwinds
        connectTask?.cancel()
        connectTask = nil
        result = nil
    }

    private func connectWallet() {
        result = nil
        connectGeneration &+= 1
        let generation = connectGeneration
        connectTask = Task { @MainActor in
            // Only clear the handle if it's still OURS — a task orphaned by a
            // cancel or by a newer tap must not clear the current one's.
            defer { if connectGeneration == generation { connectTask = nil } }

            let outcome: Result<WalletConnectBridge.ConnectOutcome, Error>
            do {
                outcome = .success(try await WalletConnectBridge.connect(open: openWalletApp))
            } catch {
                outcome = .failure(error)
            }

            // One staleness gate over BOTH arms. A cancelled or superseded
            // handshake says nothing at all: the person cancelled it, they
            // know, and every line below would be a lie about a handshake
            // they already abandoned — cancellation surfaces as `.timedOut`
            // ("nothing came back from your wallet"), and a cancel landing
            // mid-teardown surfaces as `.tearDownFailed`, which would accuse
            // their wallet of holding a session open.
            guard connectGeneration == generation, !Task.isCancelled else { return }

            switch outcome {
            case .success(.connected(let found)):
                watchConnected(found)
            case .success(.noWalletApp):
                resultIsError = true
                result = String(localized: "No wallet app on this iPhone — paste the address instead.")
            case .success(.timedOut):
                resultIsError = true
                result = String(localized: "Nothing came back from your wallet — approve the request there, or paste the address instead.")
            case .failure(WalletConnectBridge.ConnectError.tearDownFailed):
                // The one failure this whole design exists to catch, so it says
                // so out loud instead of quietly watching the address: a
                // session survived the read, and until it's gone the screen's
                // read-only promise is false.
                resultIsError = true
                result = String(localized: "Connected, but the session wouldn't close — open your wallet and disconnect Casberi. Nothing was watched.")
            case .failure(WalletConnectBridge.ConnectError.keychainUnavailable(let status)):
                // The keychain preflight failed — the handshake never started
                // (the SDK would have crashed on this exact write). The code
                // rides along because it's the one fact that diagnoses this
                // from a screenshot.
                resultIsError = true
                result = String(localized: "This device's keychain refused the handshake (code \(status)) — paste the address instead.")
            case .failure:
                resultIsError = true
                result = String(localized: "Couldn't reach your wallet — paste the address instead.")
            }
        }
    }

    /// Hand the `wc:` URI to whichever wallet claims the scheme, and report
    /// whether one actually did.
    ///
    /// `canOpenURL` FIRST, and it — not the open's own result — is what the
    /// answer rests on. Measured 2026-07-16, both ways of asking afterwards
    /// lie: `UIApplication.open`'s completion and SwiftUI's `openURL` each
    /// reported success for a `wc:` URI that no installed app claimed, while
    /// LaunchServices failed it a beat later in its own daemon
    /// (`LSApplicationWorkspaceErrorDomain Code=115`, visible only in the
    /// device log). Believing that Bool left the screen waiting five minutes
    /// on a wallet that never opened. `canOpenURL` is synchronous, asks the
    /// installed-app registry directly, and needs exactly one
    /// `LSApplicationQueriesSchemes` entry — `wc`, which every WalletConnect
    /// wallet registers — so it does not rot as wallets come and go.
    ///
    /// The open still happens and its result is still ANDed in: a false there
    /// is rare but real (a wallet mid-uninstall), and this is a path where
    /// claiming more than we know is the whole thing we're avoiding.
    @MainActor
    private func openWalletApp(_ url: URL) async -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { opened in
                continuation.resume(returning: opened)
            }
        }
    }

    /// Watch whatever the settled session handed over. A wallet may share
    /// several accounts at once; all of them are addresses the person chose to
    /// give us, so all of them are watched rather than silently taking the
    /// first. Labels stay empty — the wallet sends a raw account, and the row
    /// is renameable.
    private func watchConnected(_ found: [WalletConnectBridge.ConnectedAccount]) {
        var addedAny = false
        for account in found {
            // A Solana wallet can only be read on Solana; adding one with that
            // chain switched off would watch an address that can never show
            // anything. Same rule the paste path applies to a `.sol` name —
            // except the family is read off the session here rather than
            // sniffed from the address, and the account names the chain it
            // needs rather than this screen restating the id.
            if let network = account.requiredNetworkID {
                WalletChainStore.shared.ensureEnabled(network)
            }
            // `add` returns false on a duplicate — kept in the body rather
            // than a `where` clause, which would hide the mutation.
            if wallet.add(account.address, label: "") { addedAny = true }
        }
        guard addedAny else {
            resultIsError = true
            result = found.isEmpty
                ? String(localized: "Your wallet approved but shared no address — paste it instead.")
                : String(localized: "Already watching that address.")
            return
        }
        resultIsError = false
        DSHaptic.success()
        sync()
    }

    private func watch() {
        let input = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        // A name (vitalik.eth, toly.sol) resolves to an address — the address is
        // what the APIs read; the name rides along as the row's label. `.sol` is
        // tried FIRST: `ENS.looksLikeName` takes any dotted string, so it would
        // otherwise send toly.sol to the ENS resolver, which answers with a null
        // address rather than an error.
        if SNS.looksLikeName(input) {
            Task {
                guard let address = await SNS.resolve(input) else {
                    resultIsError = true
                    result = String(localized: "Couldn't resolve \(input) — check the name, or paste the address.")
                    return
                }
                // A Solana wallet can only be read on Solana; adding one with
                // that chain switched off would watch an address that can never
                // show anything.
                WalletChainStore.shared.ensureEnabled("solana-mainnet")
                addWatched(address: address, label: input)
            }
        } else if ENS.looksLikeName(input) {
            Task {
                guard let hex = await ENS.resolve(input) else {
                    resultIsError = true
                    result = String(localized: "Couldn't resolve \(input) — check the name or paste a 0x address.")
                    return
                }
                addWatched(address: hex, label: input)
            }
        } else {
            if SNS.isAddress(input) { WalletChainStore.shared.ensureEnabled("solana-mainnet") }
            addWatched(address: input, label: "")
        }
    }

    private func addWatched(address: String, label: String) {
        guard wallet.add(address, label: label) else {
            resultIsError = true
            result = String(localized: "Already watching that address.")
            return
        }
        newAddress = ""
        addressFieldFocused = false
        resultIsError = false
        DSHaptic.success()
        sync()
    }

    private var footerSection: some View {
        Section {
        } footer: {
            Text("Read-only — watching can never trade or move funds. Activity is public, read across chains directly on this iPhone.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
        }
    }

    /// Which watched wallet a landed transaction came from, when more than
    /// one is watched — falls back to nil (the explorer link shows instead)
    /// rather than guessing.
    private func walletLabel(_ thing: Thing) -> String? {
        wallet.label(forAddress: thing.walletAddress)
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
