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

/// How the address book list orders itself — recency (the book's own default
/// order) is the honest baseline; name and activity are opt-in for a book big
/// enough that insertion order stops being useful.
private enum BookSort: CaseIterable, Hashable {
    case recent, name, mostActive

    var label: String {
        switch self {
        case .recent: String(localized: "Recent")
        case .name: String(localized: "Name")
        case .mostActive: String(localized: "Most active")
        }
    }
}

/// What the book is presenting — one address's card, or the door that makes a
/// group. See `WalletScreen.bookSheet` for why these share a slot.
private enum BookSheetRoute: Identifiable {
    case entry(AddressBook.Entry)
    case newGroup
    /// What a settled WalletConnect session handed over, on its way to the
    /// picker (2026-08-13, prd §376). Routed through this enum rather than
    /// hung off the view as a fourth `.sheet` for the reason the property
    /// below states at length.
    case connectPicker([WalletConnectBridge.ConnectedAccount])

    /// Spelled out rather than computed off the payload, so the two cases can
    /// never collide on an address whose key happens to read like a sentinel.
    var id: String {
        switch self {
        case .entry(let entry): "entry:\(entry.id)"
        case .newGroup: "newGroup"
        // Keyed by the addresses themselves: connecting the same wallet twice
        // is the same sheet, and a fresh identity would re-present it over
        // itself mid-dismiss.
        case .connectPicker(let accounts): "connect:" + accounts.map(\.address).joined(separator: ",")
        }
    }
}

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
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @State private var newAddress = ""
    @FocusState private var addressFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    /// Each watched wallet's total USD, keyed the address book's way (prd
    /// §212, 2026-07-25) — what the roster slots and the shelf note read. The
    /// same `topHoldingsByWallet` call `sync` already made and threw away.
    @State private var walletTotals: [String: Double] = [:]
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
    /// The address book (prd §169) — merged onto THIS page now (2026-07-24,
    /// user: "they should be on the same page too, the watched and the
    /// address book"). It used to be a door to a separate screen; the
    /// omnibox's own claim to already be the book's search field ("one
    /// input, not two") was only half true while the results it searched
    /// lived one page away. Same field, same list, no door.
    @Bindable private var book = AddressBook.shared
    /// The book's ONE presentation (2026-08-01) — the address card and the
    /// new-group sheet share a slot instead of hanging off this view as two
    /// more siblings. This screen already carries the two token sheets, and
    /// FeedScreen's lesson is on the record: sibling `.sheet` modifiers on one
    /// screen start silently self-dismissing each other's first tap. A route
    /// costs one enum and takes that whole class off the table.
    @State private var bookSheet: BookSheetRoute?
    /// How the list below the roster orders itself — recency by default,
    /// name or activity on request.
    @State private var bookSort: BookSort = .recent
    /// Every entry's landed-activity count, keyed the book's way. CACHED
    /// (2026-08-01): this was a computed property running an unscoped corpus
    /// fetch plus a full walk, and `sortedBookEntries` reads it — so with
    /// "Most active" selected it ran on every body evaluation, which means
    /// once per keystroke in the omnibox above it, on the main thread. Built
    /// on appear and after each sync instead; the corpus doesn't change
    /// between those without one of them firing.
    @State private var activityCounts: [String: Int] = [:]
    /// Which of the book's addresses are connected (prd §295) — rebuilt on the
    /// same two beats as `activityCounts` above and for the same reason: it is
    /// a corpus fetch plus a walk, and the corpus doesn't change between an
    /// appear and a sync without one of them firing.
    @State private var connections: AddressConnections.Map?
    /// The connected address being named, and the draft. Naming here is the
    /// same act as naming from a transfer's sheet — it rewrites every landed
    /// transfer carrying that address (`CounterpartyRetitle`).
    @State private var namingAddress: String?
    @State private var namingDraft = ""
    /// The group being viewed, or nil for the whole book (2026-08-01).
    @State private var selectedGroup: String?
    /// The entry a brand-new group is being created for — group creation only
    /// ever happens while filing something, because a group with no members
    /// doesn't exist in this model (see `AddressBook`'s groups section).
    @State private var newGroupForEntry: AddressBook.Entry?
    @State private var groupDraft = ""
    @State private var renamingGroup = false
    @State private var confirmDeleteGroup = false
    /// What a pasted list did — the one outcome the field can't state in
    /// place, since a bulk import lands rows rather than filling the roster.
    @State private var bulkResult: String?
    /// Set when tapping a star would exceed the watch cap — an honest modal,
    /// since the roster's empty slots can't show "already full" from inside
    /// the list (2026-07-24).
    @State private var watchCapHit = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Query(walletRecentDescriptor) private var recent: [Thing]

    private let rosterFaceSize: CGFloat = DS.Face.shelf
    private let rosterSlotWidth: CGFloat = 74
    /// The two label lines under a roster face, height-locked so a watched
    /// slot and an empty one line up. Named rather than written twice: the
    /// two call sites MUST agree or a half-full shelf steps.
    private let rosterLabelHeight: CGFloat = 28

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
            // Below the shelf: TWO verbs and one sentence (prd §212,
            // 2026-07-25). The page carried nine distinct blocks before this
            // — shelf, count, field, a "Just name it" text button, Connect,
            // the peek chip, the promise, a Connection door, status rows, and
            // then a headed address-book section with its own sort menu and a
            // two-sentence footer. Naming folded INTO the field as its second
            // verb; the Connection door moved to the foot of the page (it's
            // the last thing anyone touches, not the third); the footer
            // paragraph went entirely — the shelf visibly filling when you tap
            // a star teaches the star better than a sentence about it does.
            Section {
                // Bound ONCE: `looksLikeBulk` tokenizes the whole draft, and
                // this is read four times in the slab below plus once in the
                // notice — five re-parses of a forty-line paste per keystroke.
                let isBulk = isBulkDraft
                VStack(spacing: DS.Space.s2) {
                    DSSlabField(placeholder: String(localized: "Address, ENS, .sol"),
                                    text: $newAddress,
                                    // A pasted LIST gets its own verb (2026-08-01).
                                    // `addBulk` has always parsed "Mom, 0x9a2E…"
                                    // one-per-line, and nothing reached it: the
                                    // field read a multi-line paste as one token
                                    // and answered "that doesn't look like an
                                    // address". Naming, never watching — a paste
                                    // of forty can't watch against a cap of five,
                                    // and the notice below says so.
                                    actionLabel: isBulk ? String(localized: "ADD ALL")
                                                        : String(localized: "WATCH"),
                                    focus: $addressFieldFocused,
                                    // The lightweight second verb (2026-07-24,
                                    // moved inside the slab 2026-07-25) —
                                    // watching is capped at 5 and starts
                                    // syncing; naming isn't and does neither.
                                    // Armed only over a real, addable address,
                                    // so it's never a stray control over "mom"
                                    // or an empty field. This is also the cap's
                                    // own honest way out: the WATCH error at the
                                    // limit used to just SAY "name this address
                                    // instead" with nothing to tap.
                                    secondaryLabel: String(localized: "NAME"),
                                    secondaryArmed: !isBulk && book.looksLikeAddress(
                                        newAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
                                    secondaryAction: justName,
                                    action: { isBulk ? addAll() : watch() })
                    fieldNotice(isBulk: isBulk)
                    if WalletConnectBridge.isAvailable {
                        connectRow
                    }
                    // Nothing watched, nothing typed — one tap watches a famous
                    // public wallet so the whole feature demos in three seconds.
                    // Kept as a real control rather than demoted to placeholder
                    // text (the mock's suggestion): it only ever renders on an
                    // empty roster, so it costs nothing in the normal case, and
                    // turning a one-tap demo into a string you must type by hand
                    // is a real loss at exactly the moment a new person has the
                    // least patience.
                    if wallet.addresses.isEmpty {
                        peekChip
                    }
                    Text("Read-only — watching can never move funds.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Space.s1)
                }
            }
            .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            statusSection
            groupChipsSection
            bookSection
            connectionsSection
            // The connection plumbing, at the foot of the page — chains and
            // teardown are the one thing here nobody revisits, so it sits after
            // the list rather than between the verbs and the names.
            Section {
                DSSlabDoor(title: "Connection", detail: chainsSummary) {
                    route.pushBridge(.walletConnection)
                }
            }
            .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
        .dsScreenTitle("Wallet")
        // Ask the chain what the unnamed-kind entries are, a few at a time —
        // keyless, and only for entries that haven't been checked (prd §169).
        .task { await AddressKind.detectPending() }
        .alert("Name this wallet",
               isPresented: Binding(get: { renamingID != nil },
                                    set: { if !$0 { renamingID = nil } })) {
            TextField("Name (e.g. Main, Cold)", text: $renameDraft)
            Button("Save") {
                if let id = renamingID,
                   let address = wallet.addresses.first(where: { $0.id == id })?.address {
                    wallet.rename(id, to: renameDraft)
                    // History catches up here too — naming a wallet from the
                    // shelf is the same act as naming it from its card, and
                    // used to be the one door that left old titles behind.
                    CounterpartyRetitle.applyCurrentName(for: address, in: modelContext)
                    DSHaptic.success()
                }
                renamingID = nil
            }
            Button("Cancel", role: .cancel) { renamingID = nil }
        } message: {
            Text("A blank name shows the address instead.")
        }
        // Naming a connected address (prd §295) — the connections card's one
        // action. Same alert grammar as the wallet rename above it, and the
        // same consequence: the name rides every transfer with this address,
        // past and future.
        .alert("Name this address",
               isPresented: Binding(get: { namingAddress != nil },
                                    set: { if !$0 { namingAddress = nil } })) {
            TextField("Name (e.g. Mom)", text: $namingDraft)
            Button("Save") { nameConnected() }
            Button("Cancel", role: .cancel) { namingAddress = nil }
        } message: {
            Text("Your name for this address rides every transfer with it. A blank name clears it.")
        }
        .onAppear {
            refreshActivityCounts()
            refreshConnections()
            if !wallet.addresses.isEmpty {
                sync()
                Task { await wallet.loadAvatars() }
            }
        }
        // A group stops existing the moment its last member is unfiled — which
        // can happen from the address card, from a row's context menu, or by
        // removing the address itself, none of which know the book is being
        // filtered by it. Left alone, the filter would sit on a name no chip
        // shows and the list would read as empty for no visible reason. Only
        // the menu's own Delete cleared it before.
        //
        // This does re-walk the book once per body pass, which is the shape
        // §266 just took `historyCounts` apart for — but not the same cost:
        // that was an unscoped CORPUS fetch, this is a dictionary walk over a
        // list that stays scannable at fifty rows. It sits at screen level
        // rather than on the chips section, which already has `groupNames` in
        // hand, because that section doesn't render for an empty book — and
        // emptying the book is one of the ways a selected group stops existing.
        .onChange(of: book.groupNames) { _, groups in
            if let group = selectedGroup,
               !groups.contains(where: { AddressBook.sameGroup($0, group) }) {
                withAnimation(DS.Motion.standard) { selectedGroup = nil }
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
        .sheet(item: $bookSheet) { route in
            switch route {
            case .entry(let entry):
                AddressCard(entry: entry)
            case .newGroup:
                // Select what was just made: a group you created and then had
                // to go find is a filing cabinet, not a filing gesture.
                NewGroupSheet { group in
                    withAnimation(DS.Motion.standard) { selectedGroup = group }
                }
            case .connectPicker(let accounts):
                WalletConnectPickerSheet(shared: accounts) { added in
                    if added > 0 { sync() }
                }
            }
        }
        .alert("Watching \(WalletStore.watchLimit) already", isPresented: $watchCapHit) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Watching \(WalletStore.watchLimit) — the cap. Unwatch one first; its name stays in your book.")
        }
        // TYPING again retires the last paste's outcome — a result line that
        // outlives what produced it starts describing the wrong thing.
        // Gated on the field being non-empty, which is not fussiness: `addAll`
        // clears the field and THEN sets the result, both in one turn, so a
        // bare "field changed" test cleared the confirmation before it ever
        // drew and the paste looked like it did nothing.
        .onChange(of: newAddress) { _, new in
            if !new.isEmpty { bulkResult = nil }
        }
        .alert("New group",
               isPresented: Binding(get: { newGroupForEntry != nil },
                                    set: { if !$0 { newGroupForEntry = nil } })) {
            TextField("Name (e.g. Family, Cold)", text: $groupDraft)
            Button("Create") {
                if let entry = newGroupForEntry {
                    book.addToGroup(groupDraft, address: entry.address)
                    DSHaptic.success()
                }
                newGroupForEntry = nil
            }
            Button("Cancel", role: .cancel) { newGroupForEntry = nil }
        } message: {
            Text(newGroupForEntry.map { "Files \($0.name) under a new group." } ?? "")
        }
        .alert("Rename group", isPresented: $renamingGroup) {
            TextField("Name", text: $groupDraft)
            Button("Save") {
                if let group = selectedGroup {
                    book.renameGroup(group, to: groupDraft)
                    // Follow the group being viewed to its new name, or the
                    // filter would sit on a group that no longer exists and
                    // show an empty list.
                    selectedGroup = groupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    DSHaptic.success()
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete this group?", isPresented: $confirmDeleteGroup,
                            titleVisibility: .visible) {
            Button("Delete group", role: .destructive) {
                if let group = selectedGroup {
                    book.deleteGroup(group)
                    selectedGroup = nil
                    DSHaptic.tap()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The addresses and their names stay in your book — only the grouping goes.")
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
            // New transactions mean new counts — the sort and the rows both
            // read this, and a refresh that lands 12 things while the numbers
            // beside them stay put reads as stale.
            refreshActivityCounts()
            refreshConnections()
            // Keep what the read already cost us (prd §212) — the roster slots
            // and the shelf note draw off this. Groups with no address are the
            // combined one; it would double every total if counted.
            walletTotals = totals.reduce(into: [:]) { acc, group in
                guard let address = group.address else { return }
                acc[AddressBook.key(for: address)] = group.totalUSD
            }
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
            let proof = added > 0
            ? String(localized: "\(added) new")
            : String(localized: "Synced just now")
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
            // The shelf's own one line — how full it is, what it's worth, and
            // (while a read is in flight) that it's reading (prd §212,
            // 2026-07-25). The syncing state used to be a separate status
            // block below the verbs; a spinner belongs on the thing being
            // read, not in a row of its own.
            HStack(spacing: 5) {
                Text("\(wallet.addresses.count) of \(WalletStore.watchLimit) watched")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                if let total = watchedTotal {
                    Text("· \(WalletValue.money(total))")
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                }
                if syncing {
                    ProgressView().controlSize(.mini)
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
        .padding(.top, DS.Space.s2)
    }

    /// Everything watched, summed — nil until a holdings read has landed, so
    /// the line never claims a $0 portfolio it simply hasn't read yet.
    private var watchedTotal: Double? {
        let sum = walletTotals.values.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    /// One watched wallet's face — tap renames (the row's own tap-again
    /// grammar, unchanged from before the redesign), long-press offers Copy
    /// and Remove (the gesture the roster's card shape actually teaches,
    /// replacing the old swipe-to-remove a horizontal shelf can't perform).
    private func rosterSlot(_ addr: WalletStore.WatchedAddress) -> some View {
        VStack(spacing: 6) {
            WalletFace(address: addr.address, size: rosterFaceSize, circular: true)
            VStack(spacing: 0) {
                // Stays at `label12`, deliberately (considered and rejected
                // 2026-08-03). This is a CAPTION under a 60pt face, not a row
                // title: the face carries the identity and the words label it,
                // which is why every platform face shelf captions small. It
                // reads at the same size as the value beneath it because
                // weight and color carry that step — the ramp's own method.
                // Stepping it to `subhead13` to "match" the book row below
                // compares two different jobs, and at a 74pt slot it costs
                // about two characters of every name to truncation.
                Text(wallet.displayName(for: addr))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                // What it's WORTH, under the name (prd §212, 2026-07-25) — the
                // one fact the roster was missing, and the reason a shelf of
                // faces is worth looking at rather than just tapping. Falls
                // back to the short address until a holdings read lands, and
                // stays silent when the name IS the short address (printing it
                // twice reads as a stutter).
                if let usd = walletTotals[AddressBook.key(for: addr.address)], usd > 0 {
                    Text(WalletValue.money(usd))
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                } else if wallet.displayName(for: addr) != addr.short {
                    Text(addr.short)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(height: rosterLabelHeight, alignment: .top)
        }
        .frame(width: rosterSlotWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.tap()
            renameDraft = addr.label
            renamingID = addr.id
        }
        .dsTapCard()
        .contextMenu {
            Button {
                DSPasteboard.copySensitive(addr.address)
                DSHaptic.success()
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                if let i = wallet.addresses.firstIndex(where: { $0.id == addr.id }) {
                    let gone = wallet.addresses[i].address
                    wallet.remove(at: IndexSet(integer: i))
                    // Unwatching the last wallet drops the riding seats (§207).
                    store.reconcileWalletSeats()
                    // …and its rows leave with it (prd §286): every bridge
                    // that rides the watched wallets stamps `walletAddress`,
                    // so this reaches the transfers, approvals, Peer fills,
                    // pool deposits and card spends alike.
                    FollowPrune.removeWallet(
                        address: gone,
                        stillWatched: wallet.addresses.map(\.address),
                        context: modelContext)
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
                        .dsGlyph(16)
                        .foregroundStyle(DS.textTertiary)
                }
            // Sits in the NAME's slot, so it takes the name's rung — a filled
            // face and an empty one have to read as one shelf.
            Text("Watch").dsText(.label12).foregroundStyle(DS.textTertiary)
                .frame(height: rosterLabelHeight, alignment: .top)
        }
        .frame(width: rosterSlotWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.tap()
            addressFieldFocused = true
        }
        .dsTapCard()
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

    // MARK: - The address book (prd §169/§189, merged onto this page §202)

    /// Every named address, watched or not — ALL of it, on this one list now
    /// (2026-07-24). The old split (a roster for watched, a door to a
    /// separate screen for everyone else) was the actual "which page is
    /// this on" confusion; one list with a "Watching" mark on the entries
    /// that are is the honest merge, not two views pretending to be one.
    private var sortedBookEntries: [AddressBook.Entry] {
        var matched = book.search(newAddress)
        // The group filter narrows whatever the search returned, so typing
        // inside a group searches that group — one field, two narrowings, no
        // second input.
        if let selectedGroup { matched = matched.filter { $0.isIn(selectedGroup) } }
        switch bookSort {
        case .recent:
            return matched
        case .name:
            return matched.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .mostActive:
            return matched.sorted {
                (activityCounts[$0.id] ?? 0) > (activityCounts[$1.id] ?? 0)
            }
        }
    }

    /// Rebuilds the activity cache. Shares ONE definition of activity with the
    /// address card's own "Your history together" (`AddressActivity`) — they
    /// disagreed before, so a wallet whose activity was mostly Peer fills
    /// sorted as inactive while its card said "· 40".
    private func refreshActivityCounts() {
        activityCounts = AddressActivity.counts(in: modelContext)
    }

    /// The book's own summary (prd §295). Nil below two watched wallets — a
    /// connection can't exist there, so the card doesn't render rather than
    /// rendering empty.
    private func refreshConnections() {
        connections = AddressConnections.map(context: modelContext)
    }

    /// Names a connected address, then brings its landed transfers into line —
    /// the same pair the thing sheet's own naming flow runs, so a name given
    /// here and a name given there mean exactly the same thing afterwards.
    private func nameConnected() {
        guard let address = namingAddress else { return }
        namingAddress = nil
        AddressBook.shared.setName(namingDraft, for: address)
        _ = CounterpartyRetitle.applyCurrentName(for: address, in: modelContext)
        refreshActivityCounts()
        refreshConnections()
        DSHaptic.success()
    }

    /// Matched through the resolution cache, not by raw string (2026-07-25):
    /// a book entry holds the RESOLVED address while a watch may hold the
    /// spelling it was added under ("vitalik.eth"), so a plain compare left
    /// the star empty on a wallet that was plainly being watched.
    private func isWatched(_ entry: AddressBook.Entry) -> Bool {
        wallet.addresses.contains { wallet.scopeMatches(entry.address, scope: $0.address) }
    }

    /// The group filter (2026-08-01) — a scrolling row of chips above the list.
    ///
    /// AMENDED the same day (user: "I don't see how to create groups"). This
    /// rendered only once a group existed, on the argument that the feature
    /// should cost nothing until it's used. The cost it actually carried was
    /// the opposite one: with no groups there was no group UI anywhere on the
    /// screen, so the only doors in were a long-press on a row or a tap into an
    /// address card — both of which you have to already know about. A feature
    /// whose entire surface appears only after you've used it can't be found.
    ///
    /// So the row draws whenever the book holds anything, and when there are no
    /// groups it holds exactly one chip: the verb. Nothing to filter, nothing
    /// claiming a group exists — just the way in.
    @ViewBuilder
    private var groupChipsSection: some View {
        let groups = book.groupNames
        if book.count > 0 {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s2) {
                            // "All" is a filter, and a filter over one state
                            // isn't one — it appears with the groups it selects
                            // between.
                            if !groups.isEmpty {
                                groupChip(nil, label: String(localized: "All"))
                                ForEach(groups, id: \.self) { groupChip($0, label: $0) }
                            }
                            newGroupChip
                        }
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, 2)
                    }
                    if let selectedGroup { groupNote(selectedGroup) }
                }
            }
            .listRowInsets(EdgeInsets(top: DS.Space.s3, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// The verb, sitting in the row it fills. Tinted rather than gray, which is
    /// the whole difference between it and the chips beside it: those select,
    /// this one does something. No border — nothing in this app draws a line
    /// (design law), so the tint carries it alone.
    private var newGroupChip: some View {
        Button {
            DSHaptic.selection()
            bookSheet = .newGroup
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "folder.badge.plus")
                    .dsGlyph(12)
                Text("New group")
                    .dsText(.subhead13).fontWeight(.semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(DS.tint)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(DS.tintDim, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func groupChip(_ group: String?, label: String) -> some View {
        let selected = selectedGroup == group
        // A group's FACES, not its count (2026-08-01). A number beside a group
        // name says how many are in it, which nobody wonders; the faces say
        // WHO, which is the only thing a group of addresses is actually for —
        // and they're already drawn everywhere else, so "Family" starts
        // looking like your family. Through `AddressMark`, so the book's own
        // round-face-for-a-who / square-glyph-for-machinery rule holds inside
        // the chip too. "All" gets none: every face in the book is not a face.
        let faces = group.map { Array(book.entries(inGroup: $0).prefix(3)) } ?? []
        return Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { selectedGroup = group }
        } label: {
            HStack(spacing: DS.Space.s2) {
                if !faces.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(faces) { entry in
                            AddressMark(entry: entry, size: 18)
                                .overlay(
                                    Circle().strokeBorder(
                                        selected ? DS.tint : DS.surfaceWell, lineWidth: 1.5))
                        }
                    }
                }
                Text(label)
                    .dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(selected ? .white : DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(selected ? DS.tint : DS.fillFaint,
                        in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// What a group holds — and, when any of it is watched, what that part is
    /// worth. The value NEVER claims to be the group's: only watched wallets
    /// have their holdings read (naming is free, watching is the upgrade), so
    /// a group of forty named addresses with two watched can only honestly
    /// price those two, and the sentence says which.
    private func groupNote(_ group: String) -> some View {
        let entries = book.entries(inGroup: group)
        let watchedEntries = entries.filter(isWatched)
        let total = watchedEntries.reduce(into: 0.0) { sum, entry in
            sum += walletTotals[entry.id] ?? 0
        }
        var parts = [String(localized: "\(entries.count) addresses")]
        if watchedEntries.isEmpty {
            parts.append(String(localized: "none watched"))
        } else if total > 0 {
            parts.append(String(localized: "\(watchedEntries.count) watched worth \(WalletValue.money(total))"))
        } else {
            parts.append(String(localized: "\(watchedEntries.count) watched"))
        }
        return Text(parts.joined(separator: " · "))
            .dsText(.label12).foregroundStyle(DS.textTertiary)
            .monospacedDigit()
            .padding(.horizontal, DS.Space.s4)
    }

    /// The book's own summary (prd §295) — last card on the page, after the
    /// rows it describes and before the connection plumbing nobody revisits.
    ///
    /// It declines twice, quietly: no card at all below two watched wallets
    /// (`map` returns nil — a connection cannot exist), and one sentence when
    /// two or more are watched and nothing connects them. The second is a real
    /// answer and worth printing; the first is a question the person hasn't
    /// asked yet.
    @ViewBuilder
    private var connectionsSection: some View {
        if let connections {
            Section {
                AddressConnectionsCard(map: connections) { node in
                    // The LANDED spelling, not the folded key: `setName` and
                    // `CounterpartyRetitle` both fold it themselves, but
                    // `realName`'s auto-name test compares against the address
                    // it was handed, and a lowercased hex is not the form the
                    // book filed.
                    namingAddress = node.address
                    namingDraft = ""
                } onOpen: { node in
                    // Through the book's OWN sheet slot, so a connected address
                    // opens the identical card its row on the book opens — and
                    // so the card carries no presentation of its own (CLAUDE.md,
                    // "one screen, one `.sheet`").
                    //
                    // An address the book has never heard of gets an ephemeral
                    // entry rather than no door: `AddressCard` reads the book
                    // first and falls back to what it was handed, and Rename
                    // there files it for real. Refusing to open would shut the
                    // door on exactly the addresses this card exists to surface.
                    bookSheet = .entry(AddressBook.shared.entry(for: node.address)
                                        ?? AddressBook.Entry(address: node.address,
                                                             name: node.name,
                                                             addedAt: .now))
                }
            }
            .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var bookSection: some View {
        // All three computed ONCE per pass, not per row and not per read.
        // `sortedBookEntries` re-runs a search, a filter and a sort every time
        // it's touched, and it's touched three times here; `groupNames` walks
        // and sorts the whole book, and it lives inside the ROW's context menu,
        // so reading it there made a fifty-row book quadratic — the exact cost
        // `collidingKeys` was hoisted to avoid.
        let rows = sortedBookEntries
        let colliding = book.collidingKeys
        let groups = book.groupNames
        if !rows.isEmpty {
            Section {
                ForEach(rows) { entry in
                    Button {
                        DSHaptic.selection()
                        bookSheet = .entry(entry)
                    } label: {
                        bookRow(entry, colliding: colliding.contains(entry.id), groups: groups)
                    }
                    .buttonStyle(.plain)
                    // Removal lives in the row's context menu now (prd §212),
                    // beside Copy — the same gesture the roster slots above
                    // already teach, and one less grammar on the page. It also
                    // squares the row with the design law's own reading:
                    // swipe verbs are READS; a write belongs behind a
                    // deliberate press.
                    .listRowBackground(Color.clear)
                    // The insets go with the card — see the same note on
                    // `WalletHistoryScreen`. `WalletRow`'s own vertical
                    // padding carries the rhythm.
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
                }
            } header: {
                // The page's list, not a section on it (prd §212, 2026-07-25)
                // — a small gray label wearing its count and its sort, the
                // same anatomy the wallet feed's own section labels use.
                HStack(spacing: DS.Space.s2) {
                    // Wears the SCOPE, not always the book: inside a group the
                    // count that matters is the group's, and the chip above
                    // already says which group you're in.
                    Text("\(selectedGroup ?? String(localized: "Address book")) · \(rows.count)")
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Menu {
                        Picker("Sort by", selection: $bookSort) {
                            ForEach(BookSort.allCases, id: \.self) { sort in
                                Text(sort.label).tag(sort)
                            }
                        }
                        // The paste-out half of the round trip. The Data tray
                        // owns BACKUP (it carries the book losslessly now);
                        // this is the other job — names into another app — and
                        // it rides a menu that already existed rather than
                        // becoming a block on a page §212 fought to shorten.
                        Section {
                            Button {
                                DSPasteboard.copySensitive(book.exportText())
                                DSHaptic.success()
                            } label: {
                                Label("Copy all as text", systemImage: "doc.on.doc")
                            }
                        }
                        // Group management, all of it, in one place: the chip
                        // row carries the verb where you'd look for it, and
                        // this carries it where rename and delete already are.
                        Section {
                            Button {
                                bookSheet = .newGroup
                            } label: { Label("New group…", systemImage: "folder.badge.plus") }
                        }
                        if let group = selectedGroup {
                            Section(group) {
                                Button {
                                    groupDraft = group
                                    renamingGroup = true
                                } label: { Label("Rename group", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    confirmDeleteGroup = true
                                } label: { Label("Delete group", systemImage: "folder.badge.minus") }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(bookSort.label).dsText(.label12).fontWeight(.semibold)
                            Image(systemName: "arrow.up.arrow.down")
                                .dsGlyph(10, weight: .bold)
                        }
                        .foregroundStyle(bookSort == .recent ? DS.textTertiary : DS.tint)
                    }
                    .accessibilityLabel(Text("Sort: \(bookSort.label)"))
                }
            }
            // The footer paragraph retired here (prd §212). It taught the star
            // in two sentences — but tapping a star visibly drops the wallet
            // into the shelf at the top of the same screen, which teaches it
            // better than the sentence did, and "one gray sentence per screen"
            // (§190) was already spent on the read-only promise above.
            .listRowSeparator(.hidden)
        } else {
            // The book rendered NOTHING when it was empty (2026-08-01), which
            // made three different states look identical: a book you haven't
            // started, a search that missed, and a group you've emptied. The
            // free tier was invisible to a new person until something landed
            // in it by itself.
            Section {
                Text(emptyBookLine)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowInsets(EdgeInsets(top: DS.Space.s4, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// Which nothing this is.
    private var emptyBookLine: String {
        if !draft.isEmpty {
            return String(localized: "No name or address here matches “\(draft)”.")
        }
        if let selectedGroup {
            return String(localized: "Nothing in \(selectedGroup) yet — hold any address below and file it here.")
        }
        return String(localized: "No names yet. Name an address and every transfer reads by that name.")
    }

    private func bookRow(_ entry: AddressBook.Entry, colliding: Bool,
                         groups: [String]) -> some View {
        // The room's shared row anatomy (prd §212) — the book's own
        // `AddressMark` stays as the mark (it already encodes wallet vs
        // contract vs Safe, which no generic glyph would), and the star is the
        // one trailing control. Copy moved into the row's context menu: two
        // buttons competing for the trailing slot made the star, which is the
        // real verb here, look like one of a pair.
        HStack(spacing: DS.Space.s3) {
            AddressMark(entry: entry, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Space.s1) {
                    Text(entry.name).dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        // The name reveal (2026-08-01), the list's quieter
                        // form: a bare-added row renamed by reverse ENS
                        // cross-fades rather than snapping. Deliberately NOT
                        // the card's scale transition — a `.id()` swap inside
                        // a List row churns row identity, and `contentTransition`
                        // gets the same moment with none of that.
                        .contentTransition(.opacity)
                        .animation(DS.Motion.standard, value: entry.name)
                    // Two rows that PRINT the same (2026-08-01). The book is
                    // the only place that can see this, because it's the only
                    // place both addresses are written down — and the row is
                    // where it has to be said, since the truncation that hides
                    // the difference is right beside it.
                    if colliding {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .dsGlyph(11)
                            .foregroundStyle(DS.destructive)
                    }
                }
                Text(entry.subline(activity: activityCounts[entry.id]))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            starButton(for: entry)
        }
        .padding(.vertical, DS.Space.s2)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                DSPasteboard.copySensitive(entry.address)
                DSHaptic.success()
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            // Filing, where the thing being filed is (2026-08-01). A group is
            // a label on entries, so this menu IS the whole group model:
            // ticking a name files it, unticking unfiles it, and a group that
            // loses its last member simply stops existing.
            Menu {
                GroupMenuItems(entry: entry, groups: groups) {
                    groupDraft = ""
                    newGroupForEntry = entry
                }
            } label: {
                Label("Groups", systemImage: "folder")
            }
            Button(role: .destructive) {
                book.remove(entry.address)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// The one watch control (2026-07-24) — filled = watching (in the roster
    /// shelf and your feed), outline = named only. Tapping it is the whole
    /// promote/demote: a filled star adds the wallet to the roster above and
    /// starts its feed; an emptied one demotes it back to a plain name, which
    /// stays. Stops event propagation so tapping the star never also opens
    /// the card (the row's own tap).
    private func starButton(for entry: AddressBook.Entry) -> some View {
        let watched = isWatched(entry)
        return Button {
            toggleWatch(entry, currentlyWatched: watched)
        } label: {
            Image(systemName: watched ? "star.fill" : "star")
                .dsGlyph(17, weight: .medium)
                .foregroundStyle(watched ? DS.tint : DS.textTertiary)
                .frame(width: 32, height: 32)
                .dsTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(watched ? "Watching \(entry.name), tap to stop"
                                          : "Watch \(entry.name)"))
    }

    private func toggleWatch(_ entry: AddressBook.Entry, currentlyWatched: Bool) {
        DSHaptic.tap()
        if currentlyWatched {
            if let i = wallet.addresses.firstIndex(where: {
                wallet.scopeMatches(entry.address, scope: $0.address)
            }) {
                let gone = wallet.addresses[i].address
                wallet.remove(at: IndexSet(integer: i))
                // Its rows leave with it (prd §286) — same as the roster's
                // own Remove Wallet above.
                FollowPrune.removeWallet(
                    address: gone,
                    stillWatched: wallet.addresses.map(\.address),
                    context: modelContext)
            }
            return
        }
        switch wallet.outcome(ofAdding: entry.address, label: entry.name) {
        case .added:
            DSHaptic.success()
            sync()
        case .limitReached:
            watchCapHit = true
        case .alreadyWatching, .invalid:
            break
        }
    }

    /// Names the typed address WITHOUT watching it — unlimited, and the
    /// honest way out of the watch cap (2026-07-24). Falls back to the
    /// address's own short form exactly like a bare `addBulk` paste does, so
    /// the person can rename it from the list the moment it lands. The field
    /// slab's second verb since 2026-07-25 (prd §212); it was a floating text
    /// button on its own line before that.
    ///
    /// A typed ENS/SNS name keeps its own words as the name and RESOLVES in
    /// the background (2026-07-25): the row stands immediately either way, and
    /// when resolution lands the book re-keys it onto the address it stands
    /// for — so this row and the one a chain read lands for the same wallet
    /// are ONE row. A name that never resolves simply stays as typed: honest,
    /// and still the person's own record.
    private func justName() {
        DSHaptic.tap()
        let addr = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        newAddress = ""
        addressFieldFocused = false
        guard !addr.isEmpty else { return }
        let isName = SNS.looksLikeName(addr) || ENS.looksLikeName(addr)
        book.setName(isName ? addr : WalletStore.shortAddress(addr), for: addr)
        CounterpartyRetitle.applyCurrentName(for: addr, in: modelContext)
        guard isName else { return }
        Task {
            // `.sol` first, exactly like `watch()` — `ENS.looksLikeName` takes
            // ANY dotted string and would send a `.sol` name to the ENS
            // resolver, which answers with a null address rather than an error.
            let resolved = SNS.looksLikeName(addr)
                ? await SNS.resolve(addr) : await ENS.resolve(addr)
            guard let resolved else { return }
            await MainActor.run { wallet.noteResolution(addr, resolved: resolved) }
        }
    }

    // MARK: - What the field can tell you before you commit (2026-08-01)

    private var draft: String {
        newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A paste holding more than one address — see `AddressBook.looksLikeBulk`.
    private var isBulkDraft: Bool { book.looksLikeBulk(newAddress) }

    /// The one line under the field, when there's something worth saying about
    /// what's typed. Ordered by consequence: a lookalike is a security fact and
    /// outranks everything; a failed checksum is a typo about to become a
    /// watch; the bulk hint just explains an unfamiliar verb. Silent otherwise
    /// — a field that always has a line under it has no way to warn.
    @ViewBuilder
    private func fieldNotice(isBulk: Bool) -> some View {
        if let twin = book.lookalikes(of: draft).first {
            // The whole point of a named-address ledger, cashed in: the book
            // already holds the address you meant, so it can say which one
            // this ISN'T. Poisoning works precisely because every truncated
            // display in every wallet app hides the difference.
            noticeLine("exclamationmark.triangle.fill", DS.destructive,
                       String(localized: "Looks like \(twin.name) — but it's a different address. Check every character."))
        } else if AddressSafety.checksum(draft) == .failed {
            noticeLine("exclamationmark.triangle.fill", DS.destructive,
                       String(localized: "That address fails its own checksum — a character is wrong somewhere."))
        } else if isBulk {
            noticeLine("text.append", DS.textSecondary,
                       String(localized: "A list — ADD ALL names them. Watching stays capped at \(WalletStore.watchLimit)."))
        } else if let bulkResult {
            noticeLine("checkmark.circle.fill", DS.confirm, bulkResult)
        }
    }

    private func noticeLine(_ glyph: String, _ tone: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: glyph)
                .dsGlyph(12)
                .foregroundStyle(tone)
            Text(text)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s1)
        .transition(.opacity)
    }

    /// Names every address in a pasted list. Watching is untouched on purpose:
    /// the cap is five and a list is usually dozens, so this is the free tier
    /// doing exactly what it's for.
    private func addAll() {
        DSHaptic.tap()
        let landed = book.addBulk(newAddress)
        newAddress = ""
        addressFieldFocused = false
        guard landed > 0 else { return }
        DSHaptic.success()
        bulkResult = String(localized: "\(landed) named.")
        // Every landed transfer brought in line with the whole book at once —
        // `applyCurrentName` per address would re-fetch the corpus per line.
        CounterpartyRetitle.applyBook(in: modelContext)
        // No `refreshActivityCounts()` here on purpose: the counts are derived
        // purely from the corpus, and a paste lands book entries, never things.
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
                    .dsGlyph(12)
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
            DSSlabButton(title: connecting ? "Waiting — tap to cancel"
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
            Text("Not listed? Copy the link into your wallet's scan screen — it's still waiting.")
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
                // WalletConnect's own modal (2026-08-01) — the full wallet
                // directory with real icons and correct deep links. It replaced
                // a paste-the-link card that was the honest answer to "nothing
                // claimed `wc:`" and still a dead end for anyone with a wallet
                // on their home screen. See `connectViaModal`; the read-only
                // proposal is unchanged.
                //
                // Mac Catalyst can't link the SDK (see the import in
                // `WalletConnectBridge`), so it keeps the open-then-paste
                // route. That is not a lesser fallback there: the directory is
                // 496 PHONE apps opened by deep link, none of which a Mac has,
                // and pasting the URI into a phone's wallet is what a desktop
                // dapp asks for too. Everything the branch needs is still on
                // this screen — `openWalletApp`, `pairingURI`, the paste card.
                #if targetEnvironment(macCatalyst)
                outcome = .success(try await WalletConnectBridge.connect(
                    open: openWalletApp,
                    offerManualPairing: { url in
                        // Still the current handshake? A cancelled one must not
                        // paint its URI over a fresh attempt.
                        guard connectGeneration == generation else { return }
                        pairingURI = url
                    }))
                #else
                outcome = .success(try await WalletConnectBridge.connectViaModal())
                #endif
            } catch {
                outcome = .failure(error)
            }

            guard connectGeneration == generation, !Task.isCancelled else { return }

            switch outcome {
            case .success(.connected(let found)):
                pairingURI = nil
                showConnectPicker(found)
            case .success(.noWalletApp):
                // Only reachable now if no manual-pairing handler ran — the
                // screen always passes one, so this is the belt to that braces.
                resultIsError = true
                result = String(localized: "No wallet app on \(DS.device) — paste the address instead.")
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

    /// Hand what the settled session shared to the picker (2026-08-13, prd
    /// §376) — it does NOT watch anything itself.
    ///
    /// It used to. It looped `wallet.add` over every shared account and
    /// reported trouble only when EVERY add failed, which meant the watch cap
    /// ate the overflow in silence: watching three wallets and connecting one
    /// sharing four landed two, dropped two, and said nothing. That is the
    /// silent-truncation class §307/§309 named in the import rooms, and it was
    /// worse here, because nobody knows how many accounts their wallet chose
    /// to share — there is no number to notice was wrong.
    ///
    /// The sheet also names what it watches (reverse ENS) and offers the Safes
    /// those addresses currently sign on, both of which this path threw away.
    private func showConnectPicker(_ found: [WalletConnectBridge.ConnectedAccount]) {
        guard !found.isEmpty else {
            resultIsError = true
            result = String(localized: "Your wallet approved but shared no address — paste it instead.")
            return
        }
        resultIsError = false
        bookSheet = .connectPicker(found)
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
            // A legacy/P2SH Bitcoin address is base58-shaped too, the same
            // band Solana pubkeys occupy — check the checksum-verified kind
            // FIRST, or a pasted BTC address flips Solana on by mistake.
            if SNS.isAddress(input), !BitcoinAddress.isAddress(input) {
                WalletChainStore.shared.ensureEnabled("solana-mainnet")
            }
            addWatched(address: input, label: "")
        }
    }

    private func addWatched(address: String, label: String) {
        switch wallet.outcome(ofAdding: address, label: label) {
        case .added:
            // Watching is consent (prd §207): the wallet-riding seats (Peer,
            // Privacy Pools) are on the moment a wallet is — reflect that in
            // the catalog immediately, not only at the next foreground.
            store.reconcileWalletSeats()
        case .alreadyWatching:
            resultIsError = true
            result = String(localized: "Already watching that address.")
            return
        case .limitReached:
            // The cap, worded (prd §170) — the roster's empty slots already
            // said this before it was hit; this is the honest confirmation
            // for someone who tried anyway.
            resultIsError = true
            result = String(localized: "Watching \(WalletStore.watchLimit) — the cap. Unwatch one first, or name this address instead.")
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
