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
/// addresses are watched (paste to add, tap to rename, long-press to remove),
/// sees a live holdings treemap (top 5 by USD value), and sees what's landed
/// (recent onchain things from the corpus). Read-only, stated plainly:
/// watching an address can never trade or move funds. Both the holdings and
/// the activity are live from Alchemy, read on this iPhone — no server.
///
/// REBUILT 2026-07-22 (prd §182, user: "it still looks like a settings
/// feature and not like a pure wallet manager purposely built for adding the
/// addresses… give me three mockups"). The old shape was an insetGrouped List
/// of section cards — watching, add, chains, disconnect — at equal weight,
/// which is a settings page's grammar, not a manager's. This is
/// recommendation A (the roster) with B's omnibox grafted in: a shelf of the
/// watched wallets as faces — including their REAL empty slots up to the cap,
/// so the limit is structure you can see rather than copy you hit — one field
/// that both watches and searches the address book, and the connection
/// plumbing (chains, disconnect) demoted to a single door (`WalletConnectionScreen`,
/// amending §139: that ruling killed doors to READS, and configuration
/// nobody revisits isn't one).
struct WalletScreen: View {
    @Bindable private var wallet = WalletStore.shared
    @State private var newAddress = ""
    @FocusState private var addressFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    /// True when a non-error result still needs the person's eyes (the
    /// typo'd-address nudge). Everything else whispers — fine is silent.
    @State private var resultProminent = false
    /// The in-flight WalletConnect handshake — proposed, wallet opened, waiting
    /// on a human to approve over there (2026-07-16). Held as the Task rather
    /// than a Bool so a second tap can CANCEL it: the wait runs to the
    /// proposal's 5-minute expiry, and a person who opened their wallet, chose
    /// not to approve, and came back must not find a stuck button and no way
    /// out.
    @State private var connectTask: Task<Void, Never>?
    /// Bumped on every start and every cancel, so an in-flight handshake can
    /// tell whether it's still the CURRENT one.
    @State private var connectGeneration = 0
    /// The pairing URI, shown when nothing claimed `wc:` (2026-07-23) so it
    /// can be pasted into a wallet by hand. Non-nil means the handshake is
    /// still listening for that paste to be approved.
    @State private var pairingURI: URL?
    private var connecting: Bool { connectTask != nil }
    /// A tapped holdings cell: the token's thing sheet when watched, the
    /// quick chart sheet when not.
    @State private var openTokenThing: Thing?
    @State private var quickToken: TokenQuickRoute?
    /// Which wallet the rename alert is editing.
    @State private var renamingID: WalletStore.WatchedAddress.ID?
    @State private var renameDraft = ""
    /// The address book (prd §169) — the light tier beside the roster. The
    /// omnibox above IS its search field now (prd §182) — typing to watch
    /// something also narrows the book live, so there's one input, not two.
    @Bindable private var book = AddressBook.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Query(walletRecentDescriptor) private var recent: [Thing]

    private let rosterFaceSize: CGFloat = 60
    private let rosterSlotWidth: CGFloat = 74

    var body: some View {
        List {
            // The roster leads (prd §182) — identity first, no header, no
            // card: faces on the page, the way the crown balance leads the
            // Wallet feed. One shape whether zero or five are watched, so the
            // screen never has to choose between an "empty state" and a
            // "connected state" — it's just how full the shelf is today.
            rosterSection
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            // Below the shelf: four slabs and one sentence (prd §189). Every
            // block is the same height and radius, so the area reads as a
            // rhythm rather than the six-shape collage it was.
            Section {
                VStack(spacing: DS.Space.s2) {
                    DSSlabField(placeholder: String(localized: "Address, ENS, .sol"),
                                    text: $newAddress,
                                    actionLabel: String(localized: "WATCH"),
                                    focus: $addressFieldFocused, action: watch)
                    if WalletConnectBridge.isAvailable {
                        connectRow
                    }
                    // Nothing watched, nothing typed — one tap watches a famous
                    // public wallet so the whole feature demos in three seconds.
                    if wallet.addresses.isEmpty {
                        peekChip
                    }
                    // The one sentence. The two that used to sit beside it —
                    // where activity is read, and what naming costs — moved to
                    // the doors that own them (Connection, Address book).
                    Text("Read-only — watching can never move funds.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Space.s1)
                    DSSlabDoor(title: "Address book", detail: bookSummary) {
                        HomeRoute.shared.pushBridge(.addressBook)
                    }
                    .padding(.top, DS.Space.s2)
                    DSSlabDoor(title: "Connection", detail: chainsSummary) {
                        HomeRoute.shared.pushBridge(.walletConnection)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            statusSection
            // Room for the floating agent bar (FeedScreen's own pattern) — the
            // Connection row was the manager's own worst example of the bar
            // eating its last row before this (found live, 2026-07-22).
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.large)
        // Ask the chain what the unnamed-kind entries are, a few at a time —
        // keyless, and only for entries that haven't been checked (prd §169).
        .task { await AddressKind.detectPending() }
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
        .onAppear {
            if !wallet.addresses.isEmpty {
                sync()
                Task { await wallet.loadAvatars() }
            }
        }
        // A tapped holdings cell (2026-07-14): the token's own chart — its
        // thing sheet when watched, the quick sheet when it's just held.
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
    }

    /// Reads the chain and lands new transactions — the plumbing screen's one
    /// job on appear.
    private func sync() {
        guard !syncing else { return }
        syncing = true
        Task {
            let added = await WalletIngest.refresh(context: modelContext)
            let totals = await WalletIngest.topHoldingsByWallet()
            syncing = false
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

    // MARK: - The roster (prd §182)

    /// The watched wallets as a shelf of faces, plus their REAL empty slots up
    /// to the cap — a face for every wallet you're watching, a dashed ring for
    /// every slot you aren't. The cap stops being a sentence you hit and
    /// becomes a shape you can see filling: five faces means full, and no
    /// separate "limit reached" card has to say so.
    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s3) {
                    ForEach(wallet.addresses) { addr in
                        rosterSlot(addr)
                    }
                    if wallet.canWatchMore {
                        ForEach(0..<(WalletStore.watchLimit - wallet.addresses.count), id: \.self) { _ in
                            emptyRosterSlot
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s1)
            }
            Text("\(wallet.addresses.count) of \(WalletStore.watchLimit) watched")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .padding(.horizontal, DS.Space.s4)
        }
        .padding(.top, DS.Space.s2)
    }

    /// One watched wallet's face — tap renames (the row's own tap-again
    /// grammar, unchanged from before the redesign), long-press offers Copy
    /// and Remove (the gesture the roster's card shape actually teaches,
    /// replacing the old swipe-to-remove a horizontal shelf can't perform).
    private func rosterSlot(_ addr: WalletStore.WatchedAddress) -> some View {
        VStack(spacing: 6) {
            WalletFace(address: addr.address, size: rosterFaceSize, circular: true)
            VStack(spacing: 0) {
                Text(wallet.displayName(for: addr))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                // The address only when the name isn't already showing it —
                // an unnamed wallet's "name" IS its short address, and
                // printing it twice reads as a stutter.
                if wallet.displayName(for: addr) != addr.short {
                    Text(addr.short)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(height: 28, alignment: .top)
        }
        .frame(width: rosterSlotWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.tap()
            renameDraft = addr.label
            renamingID = addr.id
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = addr.address
                DSHaptic.success()
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                if let i = wallet.addresses.firstIndex(where: { $0.id == addr.id }) {
                    wallet.remove(at: IndexSet(integer: i))
                }
            } label: {
                Label("Remove Wallet", systemImage: "trash")
            }
        }
    }

    /// An open slot — a dashed RING, matching the roster's circular faces
    /// (prd §182), so a row of watched faces and unwatched slots reads as ONE
    /// shelf. Tapping one focuses the omnibox directly below it — the honest
    /// door, since the slot itself can't watch anything without an address.
    private var emptyRosterSlot: some View {
        VStack(spacing: 6) {
            Circle()
                .strokeBorder(DS.textTertiary.opacity(0.35),
                             style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: rosterFaceSize, height: rosterFaceSize)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
            Text("Watch").dsText(.label12).foregroundStyle(DS.textTertiary)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: rosterSlotWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.tap()
            addressFieldFocused = true
        }
    }

    /// What just happened — the spinner while chains are read, then the
    /// outcome line. A status row only when something needs eyes: an error,
    /// the typo'd-address nudge, or the very first sync. The happy path stays
    /// silent — a green "connected" card read as noise dressed as news.
    @ViewBuilder
    private var statusSection: some View {
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

    // MARK: - The address book door (prd §169/§189)

    /// The book's own count, for the door that now stands in front of it —
    /// the fact that makes the door honest rather than a place things hide.
    /// Watched wallets are excluded the way the book itself excludes them:
    /// they have the roster above, and counting them twice would make one
    /// book read as two.
    private var bookSummary: String {
        let watched = Set(wallet.addresses.map { AddressBook.key(for: $0.address) })
        let n = book.all.filter { !watched.contains($0.id) }.count
        if n == 0 { return String(localized: "Name one") }
        return n == 1 ? String(localized: "1 name") : String(localized: "\(n) names")
    }


    /// "All 5" when nothing's narrowed, else the selected names ("Ethereum,
    /// Base +3" past two) — the Connection door's own one-line fact.
    private var chainsSummary: String {
        let selected = WalletChainStore.selectable.filter { WalletChainStore.shared.isSelected($0.id) }
        if selected.count == WalletChainStore.selectable.count { return "All \(selected.count) chains" }
        let names = selected.map(\.name)
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }

    private var peekChip: some View {
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

    /// Connect — a real BUTTON (user, 2026-07-23: "it should be a button not a
    /// link"). It read as a link before: a link glyph, body text on a plain
    /// row, no fill. Connecting a wallet is the screen's second real verb
    /// beside the omnibox's Watch, so it wears the same filled capsule that
    /// verb does, and the explanatory line sits UNDER the button rather than
    /// inside it — a button says what it does in as few words as it can.
    private var connectRow: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabButton(title: connecting ? "Waiting for your wallet — tap to cancel"
                                               : "Connect a wallet app",
                             systemImage: "wallet.pass.fill",
                             busy: connecting) {
                DSHaptic.tap()
                if connecting { cancelConnect() } else { connectWallet() }
            }
            // "Hands over the address — read-only, never signs" retired here
            // (prd §189): it said the same thing as the screen's one sentence
            // two lines below it, and a button with a caption is two blocks
            // where the slab rhythm wants one.
            //
            // No app claimed `wc:` — the URI, to paste into the wallet
            // directly. The handshake is still listening while this shows.
            if let uri = pairingURI {
                manualPairingCard(uri)
            }
        }
    }

    /// The paste-it-yourself route (2026-07-23). A wallet that registers only
    /// a universal link never claims `wc:`, so `canOpenURL` reads false on a
    /// device that HAS a wallet — this is the way through, not an error, and
    /// the approval it leads to is the same one the direct open would get.
    private func manualPairingCard(_ uri: URL) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("No app answered the tap. Copy this and paste it in your wallet's scan or “connect with link” screen — it's still waiting.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s2) {
                Text(uri.absoluteString)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                CopyAddressButton(address: uri.absoluteString, expanded: true)
            }
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .padding(.top, DS.Space.s1)
    }

    private func cancelConnect() {
        connectGeneration &+= 1   // orphans the in-flight task before it unwinds
        connectTask?.cancel()
        connectTask = nil
        result = nil
        pairingURI = nil
    }

    private func connectWallet() {
        result = nil
        pairingURI = nil
        connectGeneration &+= 1
        let generation = connectGeneration
        connectTask = Task { @MainActor in
            defer { if connectGeneration == generation { connectTask = nil } }

            let outcome: Result<WalletConnectBridge.ConnectOutcome, Error>
            do {
                outcome = .success(try await WalletConnectBridge.connect(
                    open: openWalletApp,
                    offerManualPairing: { url in
                        // Still the current handshake? A cancelled one must not
                        // paint its URI over a fresh attempt.
                        guard connectGeneration == generation else { return }
                        pairingURI = url
                    }))
            } catch {
                outcome = .failure(error)
            }

            guard connectGeneration == generation, !Task.isCancelled else { return }

            switch outcome {
            case .success(.connected(let found)):
                pairingURI = nil
                watchConnected(found)
            case .success(.noWalletApp):
                // Only reachable now if no manual-pairing handler ran — the
                // screen always passes one, so this is the belt to that braces.
                resultIsError = true
                result = String(localized: "No wallet app on this iPhone — paste the address instead.")
            case .success(.timedOut):
                resultIsError = true
                // Which wait actually expired decides the words: if the URI
                // was on screen, the person was pasting, and telling them
                // "approve it in your wallet" describes a tap they never had.
                result = pairingURI == nil
                    ? String(localized: "Nothing came back from your wallet — approve the request there, or paste the address instead.")
                    : String(localized: "The connection link expired — tap Connect for a fresh one.")
                pairingURI = nil
            case .failure(WalletConnectBridge.ConnectError.tearDownFailed):
                resultIsError = true
                result = String(localized: "Connected, but the session wouldn't close — open your wallet and disconnect Casberi. Nothing was watched.")
            case .failure(WalletConnectBridge.ConnectError.keychainUnavailable(let status)):
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
    /// several accounts at once; all of them are addresses the person chose
    /// to give us, so all of them are watched rather than silently taking the
    /// first.
    private func watchConnected(_ found: [WalletConnectBridge.ConnectedAccount]) {
        var addedAny = false
        for account in found {
            if let network = account.requiredNetworkID {
                WalletChainStore.shared.ensureEnabled(network)
            }
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
        if SNS.looksLikeName(input) {
            Task {
                guard let address = await SNS.resolve(input) else {
                    resultIsError = true
                    result = String(localized: "Couldn't resolve \(input) — check the name, or paste the address.")
                    return
                }
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
        switch wallet.outcome(ofAdding: address, label: label) {
        case .added:
            break
        case .alreadyWatching:
            resultIsError = true
            result = String(localized: "Already watching that address.")
            return
        case .limitReached:
            // The cap, worded (prd §170) — the roster's empty slots already
            // said this before it was hit; this is the honest confirmation
            // for someone who tried anyway.
            resultIsError = true
            result = String(localized: "You're watching \(WalletStore.watchLimit) wallets — the limit for now. Stop watching one first, or name this address instead.")
            return
        case .invalid:
            resultIsError = true
            result = String(localized: "That doesn't look like an address.")
            return
        }
        newAddress = ""
        addressFieldFocused = false
        resultIsError = false
        DSHaptic.success()
        sync()
    }

    /// Which watched wallet a landed transaction came from, when more than
    /// one is watched — falls back to nil rather than guessing.
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
