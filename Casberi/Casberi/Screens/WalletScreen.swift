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

/// A resolved ENS/SNS name, tied to the draft that asked for it (prd §433).
private struct ResolvedDraft: Equatable {
    let input: String
    let address: String
}

/// One block of the book's list (prd §433, 2026-08-21) — the ungrouped
/// addresses, or one group.
///
/// Groups used to be a FILTER: a chip row above the list, a selection, and the
/// list narrowing in place. Three things were wrong with that and all three
/// read as "half thought out". The row occupied the chrome whether or not you
/// used groups (with none, it held a lone "New group" verb and nothing to
/// filter); selecting a chip put the whole book into a mode with no visible
/// exit but another chip; and a group's own verbs — rename, delete — lived
/// inside the SORT menu, which is not where anybody looks for them.
///
/// So a group is a SECTION now. It exists on the page exactly when it exists
/// in the book, it carries its own faces and its own menu, and there is no
/// state to be in. Every header's count matches the rows beneath it exactly —
/// which the filter could never promise, since it counted the book and showed
/// a slice.
///
/// An address filed under two groups draws under both, deliberately: it IS in
/// both, and picking one to hide it from would make a group's own count lie.
/// The ungrouped block is the only one that excludes by membership.
private struct BookBlock: Identifiable {
    /// nil for the ungrouped block.
    let group: String?
    let rows: [AddressBook.Entry]
    var id: String { group ?? "\u{0}ungrouped" }
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
    /// fetch plus a full walk, and `ordered` reads it — so with
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
    /// The same reading, laid out (prd §435). Held rather than computed per
    /// body pass for the reason `connections` is: it is a corpus fetch plus a
    /// walk, and it is read by a `GeometryReader` that re-evaluates on every
    /// scroll.
    @State private var sky: AddressSky.Sky?
    /// The connected address being named, and the draft. Naming here is the
    /// same act as naming from a transfer's sheet — it rewrites every landed
    /// transfer carrying that address (`CounterpartyRetitle`).
    @State private var namingAddress: String?
    @State private var namingDraft = ""
    /// The group a rename or delete is aimed at (prd §433, 2026-08-21). This
    /// was `selectedGroup` — a FILTER, set by a chip row above the list, which
    /// put the book into a mode and put the group's own verbs two levels down
    /// inside the Sort menu. Groups are sections of the list now, so there is
    /// nothing to select; what's left is which one a menu is acting on.
    @State private var groupUnderEdit: String?
    /// The row that was just starred, and a token to fire its lift once (prd
    /// §433). The app's own `connectPromote` grammar — written for an app
    /// taking its connected seat in the catalog shelf — and this is the same
    /// event one screen over: an address promoted from named to watched, which
    /// also re-sorts it to the top of its section. Without the lift the row
    /// simply teleports, which reads as the list glitching rather than as the
    /// thing you just did.
    @State private var promotedEntryID: String?
    @State private var promoteToken = 0
    /// Which group folders are SHUT (prd §433), by the book's own case-fold.
    ///
    /// Held for the visit rather than persisted, deliberately. A closed folder
    /// is a reading posture — "I'm looking at something else right now" — not
    /// a preference about the book, and a manager that opens with three of its
    /// four groups shut because of a tap last Tuesday hides addresses from the
    /// person who came to find one. Closed by choice, open by default, every
    /// time the screen opens.
    @State private var closedGroups: Set<String> = []
    /// What the typed ENS/SNS name resolved to, keyed by the input that asked.
    /// Keyed rather than bare so a slow answer for "vitalik.eth" can never
    /// paint itself under a draft that has since become something else — the
    /// preview's whole value is that it describes what is in the field NOW.
    @State private var resolvedDraft: ResolvedDraft?
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
            skySection
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
                    // What you're about to add, before you add it (prd §433).
                    // Keyed on the ADDRESS, not the draft: animating on the
                    // draft would re-run this spring on every keystroke, and
                    // the moment worth showing is the face arriving.
                    addressPreview(isBulk: isBulk)
                        .animation(DS.Motion.standard, value: previewAddress)
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
            bookSection
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
        // Re-keyed on every draft, so SwiftUI cancels the last lookup before
        // starting the next — which is what makes the debounce inside actually
        // debounce rather than queue.
        .task(id: draft) { await resolvePreview() }
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
        // A group that stops existing takes any menu aimed at it with it
        // (prd §433). This used to clear a FILTER — a group could be unfiled
        // from the address card, from a row's context menu, or by removing the
        // address itself, none of which knew the list was scoped to it, so the
        // book read as empty for no visible reason. The filter is gone; what
        // survives is the smaller version of the same hazard, an open rename
        // or delete pointed at a name the book no longer has.
        .onChange(of: book.groupNames) { _, groups in
            if let group = groupUnderEdit,
               !groups.contains(where: { AddressBook.sameGroup($0, group) }) {
                groupUnderEdit = nil
                renamingGroup = false
                confirmDeleteGroup = false
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
                // Nothing to select any more (prd §433) — a new group is a new
                // SECTION, already in the list under its own name, so the
                // gesture that made it is finished when the sheet closes. It
                // was a chip selection before, because the group was only
                // visible while it was the one being filtered to.
                NewGroupSheet { _ in }
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
                if let group = groupUnderEdit {
                    book.renameGroup(group, to: groupDraft)
                    DSHaptic.success()
                }
                groupUnderEdit = nil
            }
            Button("Cancel", role: .cancel) { groupUnderEdit = nil }
        }
        // The title stays a LITERAL so it localizes; the group's own name
        // rides the message below, which is a `Text` and localizes too. A
        // runtime-interpolated title takes the non-localized `String` overload
        // and ships English to every other language.
        .confirmationDialog("Delete this group?",
                            isPresented: $confirmDeleteGroup,
                            titleVisibility: .visible) {
            Button("Delete group", role: .destructive) {
                if let group = groupUnderEdit {
                    book.deleteGroup(group)
                    DSHaptic.tap()
                }
                groupUnderEdit = nil
            }
            Button("Cancel", role: .cancel) { groupUnderEdit = nil }
        } message: {
            Text(groupUnderEdit.map {
                String(localized: "Deleting “\($0)” keeps every address and every name in your book — only the grouping goes.")
            } ?? String(localized: "The addresses and their names stay in your book — only the grouping goes."))
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
            // The per-wallet totals this read produces are DELIBERATELY not
            // kept (prd §435) — no surface on this screen draws a figure any
            // more. `totals` is still read because the sentence below needs to
            // tell "nothing has landed yet" apart from "nothing is there", and
            // that question is about whether the chain answered at all.
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
    // MARK: - The sky (prd §435)

    /// Your onchain world as one picture — the drawing, then the one line that
    /// says how full it is.
    ///
    /// It REPLACES three sections rather than adding a fourth: the roster
    /// shelf, the connections spine and the group face decks were three
    /// renderings of one graph, which is why this screen read as a settings
    /// page however its sections were ordered. See `AddressSky`.
    ///
    /// **The shelf is still here and is the honest fallback.** Below two
    /// watched wallets there is no graph to draw — a lone wallet has nothing
    /// to be connected TO — so the sky declines and the shelf takes the slot,
    /// which is also exactly the state a new person is in. The empty slots, the
    /// cap-as-a-shape and every §182 ruling survive intact for that case.
    @ViewBuilder
    private var skySection: some View {
        if let sky {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                AddressSkyView(sky: sky) { body in
                    bookSheet = .entry(book.entry(for: body.address)
                                        ?? AddressBook.Entry(address: body.address,
                                                             name: body.name,
                                                             addedAt: .now))
                } onPickSlot: {
                    addressFieldFocused = true
                }
                // A drawing needs a stated height — `GeometryReader` inside a
                // List row would otherwise collapse to nothing. Square, so the
                // ring is a ring at every width.
                .frame(height: skyHeight)
                skyCaption
                skyNotes
            }
            .padding(.top, DS.Space.s2)
            // Marked seen only once it has actually BEEN on screen (see
            // `AddressSkySource.markSeen`) — flagging at build time would
            // make a new connection new for as long as it took to compose the
            // view and never let it draw itself as new at all.
            .onAppear {
                AddressSkySource.markSeen(sky.connectedBodies.map(\.id))
            }
        } else if wallet.addresses.isEmpty {
            // Nothing watched at all — the sky's own empty state (prd §437),
            // not the shelf. See `AddressSkyEmptyView`: at ZERO the shelf is a
            // row of five dashed circles, which is a picture of the cap shown
            // to somebody who has not yet met the feature. At ONE it is an
            // honest part-filled shelf, so that case still falls through.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                AddressSkyEmptyView { addressFieldFocused = true }
                    .frame(height: skyHeight)
                skyCaption
            }
            .padding(.top, DS.Space.s2)
        } else {
            rosterSection
        }
    }

    /// Tall enough for the ring plus the captions the view hangs under each
    /// body, capped so a big iPad column doesn't hand the sky half the screen.
    ///
    /// 400 AND NOT 340, and the 60 is not padding (prd §437). `AddressSky`'s
    /// body diameters are the `DS.Face` ramp over the FIELD — 56/340 and
    /// 36/340 — but the field is this height minus `AddressSkyView`'s 30pt
    /// inset on each side, so at 340 the drawing had 280 and every clearance
    /// the layout and its harness argue about was computed in units a fifth
    /// too generous. Nothing was visibly broken and nothing could be: the
    /// assertions all passed, in the wrong units. Raising this to 400 makes
    /// the field the 340 those numbers have always described. Tied to both by
    /// a drift guard in `address-sky-selftest.sh`.
    private var skyHeight: CGFloat { 400 }

    /// How full the sky is. The CAP is said here rather than drawn, which is
    /// the one §182 ruling this pass amends: a dashed ring per unused watch
    /// works in a row and does not work in a map, where three of them orbiting
    /// beside two real wallets read as three unnamed accounts. One invitation
    /// is drawn; the arithmetic is a sentence. No figure — see §435.
    private var skyCaption: some View {
        HStack(spacing: 5) {
            Text("\(wallet.addresses.count) of \(WalletStore.watchLimit) watched")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            // "8 connected" — every address the corpus can prove reaches two
            // or more of your wallets, drawn or behind the cap (the note
            // below the drawing names the undrawn tail). The §435 amendment
            // paired this with the book's own size ("6 of 27 connected") so
            // completeness could be read off the caption, and the pairing was
            // WRONG, not merely unluckily sized: a connected address is a
            // COUNTERPARTY read off landed transfers, in the book or not, so
            // the book's length is not this count's denominator — the first
            // device to draw the sky printed "8 of 5 connected" (2026-08-22,
            // prd §436). The book states its own size on its section header
            // just below, and the completeness the amendment wanted is the
            // "N more not drawn" note's job, where it is true.
            if let connections, connections.connectedCount > 0 {
                Text("· \(connections.connectedCount) connected")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            if syncing {
                ProgressView().controlSize(.mini)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, DS.Space.s4)
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s3) {
                    ForEach(Array(wallet.addresses.enumerated()), id: \.element.id) { index, addr in
                        rosterSlot(addr)
                            // The shelf ARRIVES (prd §433) — faces settling
                            // one after another, the same entrance grammar the
                            // book rows below just gained and every feed row
                            // has always had. This screen is opened more than
                            // any other in Wallet and, until now, snapped into
                            // existence fully formed.
                            .staggerIn(index: index, step: 0.05)
                            // The face LANDS in the shelf (prd §433,
                            // 2026-08-21). §212 already leaned on this moment
                            // in prose — it retired the footer that explained
                            // the star, on the grounds that "tapping a star
                            // visibly drops the wallet into the shelf at the
                            // top of the same screen, which teaches it better
                            // than the sentence did" — and then the wallet
                            // simply appeared, with no drop to see. This is
                            // that sentence made true: a slot arrives from
                            // slightly below and settles, so a star tapped
                            // eight rows down has a visible consequence.
                            .transition(.scale(scale: 0.6, anchor: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 14)))
                    }
                    if wallet.canWatchMore {
                        ForEach(0..<(WalletStore.watchLimit - wallet.addresses.count), id: \.self) { _ in
                            emptyRosterSlot
                        }
                    }
                }
                .animation(DS.Motion.standard, value: wallet.addresses.count)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s1)
            }
            // The shelf's own one line — how full it is and, while a read is
            // in flight, that it's reading (prd §212, 2026-07-25; the total it
            // also carried was struck out by §435 — see `skySection`).
            HStack(spacing: 5) {
                Text("\(wallet.addresses.count) of \(WalletStore.watchLimit) watched")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                if syncing {
                    ProgressView().controlSize(.mini)
                        .padding(.leading, 2)
                }
            }
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
                // NO FIGURE HERE (user ruling, 2026-08-21, prd §435: "we do not
                // want balances showing with addresses, we have that
                // elsewhere"). §212 put each wallet's USD total under its face,
                // which made the manager a second balance sheet beside the
                // feed's crown card — the one place that reading belongs. The
                // slot says who it is and nothing about what it holds.
                if wallet.displayName(for: addr) != addr.short {
                    Text(addr.short)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(height: rosterLabelHeight, alignment: .top)
        }
        .frame(width: rosterSlotWidth)
        .contentShape(Rectangle())
        // ONE FACE, ONE MEANING (prd §433, 2026-08-21). This face tapped to
        // RENAME while the identical face in the book row below it, in the
        // shell's scope rail, and in the balance card's chips all did
        // something else — so the same picture of the same wallet meant three
        // different verbs depending on how far down the screen it was. It
        // opens the address card now, exactly like its row: the card is where
        // the whole address lives, and it carries Rename itself (with the
        // history cascade this alert never had). The alert stays for the
        // context menu below, which is where a rename belongs — a deliberate
        // press, not the primary tap on a portrait.
        .onTapGesture {
            DSHaptic.selection()
            bookSheet = .entry(book.entry(for: addr.address)
                                ?? AddressBook.Entry(address: addr.address,
                                                     name: wallet.displayName(for: addr),
                                                     addedAt: .now))
        }
        .dsTapCard()
        .contextMenu {
            Button {
                DSHaptic.tap()
                renameDraft = addr.label
                renamingID = addr.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
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
    /// One sort, applied everywhere the book is drawn.
    ///
    /// WATCHED FIRST, but only under the default order (prd §433, 2026-08-21).
    /// The book's own baseline is insertion recency, which meant a bulk paste
    /// of forty names could push all five of your watched wallets off the
    /// bottom of the screen — in the manager whose whole job is them. Starring
    /// an address is the person's own statement that it matters more than the
    /// rest, so honouring it in the default order invents nothing.
    ///
    /// It deliberately does NOT survive an explicit sort: picking "Name" and
    /// getting a watched bucket first is the app overriding a choice that was
    /// just made, and "Most active" already has its evidence printed on every
    /// row. A stated order stays the order.
    private func ordered(_ entries: [AddressBook.Entry]) -> [AddressBook.Entry] {
        switch bookSort {
        case .recent:
            // Stable: `book.all` is already newest-first, and a partition
            // preserves that within each half.
            let watched = entries.filter(isWatched)
            guard !watched.isEmpty else { return entries }
            let watchedIDs = Set(watched.map(\.id))
            return watched + entries.filter { !watchedIDs.contains($0.id) }
        case .name:
            return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .mostActive:
            return entries.sorted {
                (activityCounts[$0.id] ?? 0) > (activityCounts[$1.id] ?? 0)
            }
        }
    }

    /// The book, partitioned into the list's sections (prd §433).
    ///
    /// Ungrouped leads, then one block per group. That order is not
    /// alphabetical accident: in the ordinary book the ungrouped block is
    /// where your own watched wallets live — nobody files their own cold
    /// wallet under "Family" — so leading with it is what keeps them above the
    /// fold. A group whose members are all filtered out by the search simply
    /// doesn't render.
    ///
    /// While SEARCHING, the partition collapses to one flat block: sectioning
    /// four matches under three headers is noise, and the person is looking
    /// for one row, not for where it's filed.
    private var bookBlocks: [BookBlock] {
        let matched = book.search(newAddress)
        guard draft.isEmpty else {
            return matched.isEmpty ? [] : [BookBlock(group: nil, rows: ordered(matched))]
        }
        var blocks: [BookBlock] = []
        let ungrouped = matched.filter { $0.groupNames.isEmpty }
        if !ungrouped.isEmpty {
            blocks.append(BookBlock(group: nil, rows: ordered(ungrouped)))
        }
        for group in book.groupNames {
            let rows = matched.filter { $0.isIn(group) }
            guard !rows.isEmpty else { continue }
            blocks.append(BookBlock(group: group, rows: ordered(rows)))
        }
        return blocks
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
        sky = AddressSkySource.sky(context: modelContext)
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

    // MARK: - A group, as a section of the list (prd §433, 2026-08-21)

    /// A group's own header — its faces, its name, what it holds, and the
    /// hinge it opens on.
    ///
    /// This replaces the chip that used to select it. The faces are the same
    /// ones the chip carried and for the same reason (2026-08-01): a number
    /// beside a group name says how many are in it, which nobody wonders,
    /// while the faces say WHO — the only thing a group of addresses is for.
    /// What they gain here is room to behave like a stack of photographs
    /// rather than three 18pt marks squeezed into a capsule beside a word.
    ///
    /// A GROUP OPENS AND CLOSES, and that is what makes it a folder rather than
    /// a heading (prd §433). Closed, the faces TIGHTEN into a deck and the
    /// group is one row; open, they FAN APART and its addresses are underneath.
    /// The fan is the whole idea in one gesture — the same faces, held together
    /// or spread out — and it costs a book of 27 across four groups about four
    /// taps to survey instead of a scroll. Closed is never the default: a book
    /// is a list you read, and a screen that opens with everything shut hides
    /// its own contents to look tidy.
    ///
    /// The group's VERBS live here too, in a menu on the header itself. They
    /// were inside the Sort menu before, which is a place you go to change an
    /// order — so renaming "Famly" meant selecting its chip, opening a control
    /// labelled with the current sort, and finding a section named after the
    /// group. Now they're on the group.
    ///
    /// Handed the block's OWN rows rather than re-reading `entries(inGroup:)`,
    /// which sorts the whole book and then filters it — once per group, once
    /// per body pass. They are the same set by construction: a group header
    /// only renders when nothing is typed, and with an empty draft `bookBlocks`
    /// hands each group its complete membership.
    private func groupHeader(_ group: String, entries: [AddressBook.Entry]) -> some View {
        let open = !closedGroups.contains(AddressBook.key(forGroup: group))
        return HStack(spacing: DS.Space.s2) {
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { toggleGroup(group) }
            } label: {
                HStack(spacing: DS.Space.s2) {
                    if !entries.isEmpty {
                        // The deck. `spacing` is the fan: closed they overlap
                        // almost entirely, open they stand apart. Negative
                        // spacing means the FIRST face is on top, which is the
                        // right way round for a stack you're looking down at.
                        HStack(spacing: open ? -5 : -13) {
                            ForEach(entries.prefix(3)) { entry in
                                AddressMark(entry: entry, size: DS.Face.badge)
                                    // The face's own separation, since nothing
                                    // in this app draws a line: each mark
                                    // punches the page colour out from under
                                    // the one behind it.
                                    .overlay(Circle().strokeBorder(DS.surfaceWell,
                                                                   lineWidth: 1.5))
                            }
                        }
                        // A closed deck leans, the way a stack of cards does.
                        // Two degrees — enough to read as held rather than
                        // aligned, not enough to look broken.
                        .rotationEffect(.degrees(open ? 0 : -3))
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group)
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Text(groupNote(group, entries: entries))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .dsGlyph(10, weight: .bold)
                        .foregroundStyle(DS.textTertiary)
                        .rotationEffect(.degrees(open ? 0 : -90))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(open ? "\(group), open" : "\(group), closed"))
            .accessibilityHint(Text(open ? "Closes this group" : "Opens this group"))
            Menu {
                Button {
                    groupDraft = group
                    groupUnderEdit = group
                    renamingGroup = true
                } label: { Label("Rename group", systemImage: "pencil") }
                Button(role: .destructive) {
                    groupUnderEdit = group
                    confirmDeleteGroup = true
                } label: { Label("Delete group", systemImage: "folder.badge.minus") }
            } label: {
                Image(systemName: "ellipsis")
                    .dsGlyph(13, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Manage \(group)"))
        }
    }

    /// Opens or closes a group. Folded through `AddressBook.key(forGroup:)`,
    /// the same fold `sameGroup` uses, so "family" and "Family" are one
    /// folder — matching the book's own model, where they are one group.
    private func toggleGroup(_ group: String) {
        let key = AddressBook.key(forGroup: group)
        if closedGroups.contains(key) { closedGroups.remove(key) }
        else { closedGroups.insert(key) }
    }

    /// What a group holds — how many addresses, how many of them you watch.
    ///
    /// It used to price the watched part ("2 watched worth $8,900"), which
    /// §435 struck out with every other figure on this screen (user ruling,
    /// 2026-08-21). A group is a set of people; how much they are worth is not
    /// a fact about the set, and the feed's crown owns the money reading.
    private func groupNote(_ group: String, entries: [AddressBook.Entry]) -> String {
        let watchedCount = entries.filter(isWatched).count
        var parts = [String(localized: "\(entries.count) addresses")]
        parts.append(watchedCount == 0
                     ? String(localized: "none watched")
                     : String(localized: "\(watchedCount) watched"))
        return parts.joined(separator: " · ")
    }

    /// THE THREE FACTS THE PICTURE CANNOT DRAW (prd §435).
    ///
    /// `AddressConnectionsCard` — the two-column spine §295 built and §433
    /// promoted above the book — is DELETED, not demoted: the sky and the card
    /// decline on the identical condition (fewer than two watched wallets), so
    /// keeping it would have meant two drawings of one reading on one screen,
    /// which is the exact fault this pass exists to fix.
    ///
    /// What the card said in WORDS survives here, because none of it is
    /// drawable and all of it is load-bearing:
    ///
    /// - **the undrawn tail, NAMED** — `nodeLimit` cuts by first-dealt order,
    ///   so the undrawn set is by construction the NEWEST connections; a
    ///   relationship formed today can never enter the picture, and a bare "2
    ///   more" was its only trace (2026-08-20's own ruling, kept verbatim);
    /// - **a watched wallet nothing reaches**, said rather than drawn as an
    ///   empty node — an absence reads better as a sentence;
    /// - **the first unnamed connection**, over EVERY connection rather than
    ///   the drawn prefix, which is the card's one action and the reason
    ///   `firstUnnamed` is stored rather than computed off `nodes`.
    @ViewBuilder
    private var skyNotes: some View {
        if let connections, !connections.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if connections.hiddenCount > 0 {
                    skyNote(String(localized: "\(connections.hiddenCount) more not drawn: \(connections.hiddenNames.joined(separator: ", "))"))
                }
                if !connections.untouchedWalletNames.isEmpty {
                    skyNote(String(localized: "Nothing connects to \(connections.untouchedWalletNames.joined(separator: ", ")) yet."))
                }
                if let unnamed = connections.firstUnnamed {
                    Button {
                        DSHaptic.tap()
                        namingAddress = unnamed.address
                        namingDraft = ""
                    } label: {
                        Text("Name \(unnamed.name)")
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(DS.tint)
                    }
                    .buttonStyle(PressSpring())
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
    }

    private func skyNote(_ text: String) -> some View {
        Text(text)
            .dsText(.label12).foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The book — one section per block (prd §433, 2026-08-21).
    ///
    /// It was ONE section carrying whatever the group filter had left. Now the
    /// ungrouped addresses lead, each group follows as its own labelled shelf,
    /// and the head of the list keeps the count and the sort exactly as §212
    /// placed them.
    @ViewBuilder
    private var bookSection: some View {
        // Computed ONCE per pass, not per row and not per section.
        // `bookBlocks` re-runs a search, a partition and a sort every time it's
        // touched; `groupNames` walks and sorts the whole book and lives inside
        // the ROW's context menu, so reading it there made a fifty-row book
        // quadratic — the exact cost `collidingKeys` was hoisted to avoid.
        let blocks = bookBlocks
        let colliding = book.collidingKeys
        let groups = book.groupNames
        if blocks.isEmpty {
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
        } else {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                Section {
                    // A closed folder shows no rows — the header alone. The
                    // ungrouped block has no folder and is never closed.
                    ForEach(Array(visibleRows(of: block).enumerated()),
                            id: \.element.id) { row, entry in
                        Button {
                            DSHaptic.selection()
                            bookSheet = .entry(entry)
                        } label: {
                            bookRow(entry, colliding: colliding.contains(entry.id),
                                    groups: groups)
                        }
                        .buttonStyle(.plain)
                        // The promotion, felt (prd §433) — see
                        // `promotedEntryID`. Reads `isTarget` at fire time, so
                        // starring one row never lifts another.
                        .connectPromote(isTarget: entry.id == promotedEntryID,
                                        token: promoteToken)
                        // The entrance this list never had (prd §433). Every
                        // other list in the app arrives; `AddressConnectionsCard`
                        // even says so in its own header ("the Wallet manager
                        // doesn't use RowEntrance, so it didn't inherit the fade
                        // every feed card gets"). Capped so a long book's tail
                        // isn't still arriving after the scroll, and Reduce
                        // Motion is handled inside `settleIn`.
                        .settleIn(delay: Double(min(row, 8)) * 0.02)
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
                    // The list's own head rides the FIRST section whatever
                    // that section is. It used to be gated on the block being
                    // the ungrouped one, which quietly deleted the sort menu,
                    // "Copy all as text" and "New group…" for anyone who had
                    // filed EVERY address into a group — the whole head, gone,
                    // because the block it was pinned to wasn't there.
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        if index == 0 { bookListHeader(count: block.rows.count) }
                        if let group = block.group {
                            groupHeader(group, entries: block.rows)
                        }
                    }
                }
                // The footer paragraph retired here (prd §212). It taught the star
                // in two sentences — but tapping a star visibly drops the wallet
                // into the shelf at the top of the same screen, which teaches it
                // better than the sentence did, and "one gray sentence per screen"
                // (§190) was already spent on the read-only promise above.
                .listRowSeparator(.hidden)
            }
        }
    }

    /// What a block actually draws — nothing when its folder is shut.
    ///
    /// The rows are DROPPED rather than hidden, so a closed group costs the
    /// List no cells at all; on a book with four groups that is most of the
    /// screen's row count. A search re-opens everything by construction: the
    /// searching case returns one ungrouped block, which has no folder.
    private func visibleRows(of block: BookBlock) -> [AddressBook.Entry] {
        guard let group = block.group else { return block.rows }
        return closedGroups.contains(AddressBook.key(forGroup: group)) ? [] : block.rows
    }

    /// The head of the list — its count and its sort (prd §212, 2026-07-25),
    /// a small gray label wearing the same anatomy the wallet feed's own
    /// section labels use.
    ///
    /// The COUNT is the whole book's, not this block's, and that is the
    /// correction §433 made: it used to read the scope, which under the group
    /// filter meant the head of a 27-address book could say "Family · 4". Now
    /// the head says how big your book is and each group says how big it is,
    /// which is two facts instead of one fact wearing two meanings. The
    /// searching case is the exception and states itself.
    private func bookListHeader(count: Int) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(draft.isEmpty
                 ? String(localized: "Address book · \(book.count)")
                 : String(localized: "\(count) matching"))
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
                // The one group verb with nowhere else to be. Rename and
                // delete moved onto the group's own header (prd §433) — they
                // act on a group, so they belong on it — but CREATING one has
                // no header to sit on until it exists, which is the same
                // discovery problem §266's amendment solved with a chip. It
                // keeps its door here and in every row's Groups menu.
                Section {
                    Button {
                        bookSheet = .newGroup
                    } label: { Label("New group…", systemImage: "folder.badge.plus") }
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

    /// Which nothing this is. The emptied-group case retired with the filter
    /// (prd §433) — a group with no members no longer has a section to be
    /// empty in, because it no longer exists in the book at all.
    private var emptyBookLine: String {
        if !draft.isEmpty {
            return String(localized: "No name or address here matches “\(draft)”.")
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
                // RELATIONSHIP facts, never money (prd §435). §433 briefly put
                // a watched wallet's total in front of this line; the ruling
                // the same day struck every figure off this screen, so the
                // subline is back to what it has always been best at — how
                // much you have dealt, what the address turned out to be,
                // where it came from.
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
                .dsSymbolSwap(watched)
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
                // Animated, so the shelf face leaves the way it arrived and
                // the row walks back down its section instead of jumping
                // (prd §433). Unwatching re-sorts too — the default order puts
                // watched first — so an un-animated demotion is the same
                // teleport the promotion had.
                withAnimation(DS.Motion.standard) {
                    wallet.remove(at: IndexSet(integer: i))
                }
                // Its rows leave with it (prd §286) — same as the roster's
                // own Remove Wallet above.
                FollowPrune.removeWallet(
                    address: gone,
                    stillWatched: wallet.addresses.map(\.address),
                    context: modelContext)
            }
            return
        }
        // Wrapped so the shelf slot arrives and the row walks up to the
        // watched half of its section, rather than both snapping into place
        // (prd §433). `promotedEntryID` is set FIRST so the row already knows
        // it is the target when the token bumps.
        promotedEntryID = entry.id
        let outcome = withAnimation(DS.Motion.standard) {
            wallet.outcome(ofAdding: entry.address, label: entry.name)
        }
        switch outcome {
        case .added:
            DSHaptic.success()
            promoteToken &+= 1
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

    // MARK: - The preview (prd §433, 2026-08-21)

    /// What the typed address resolves to, RIGHT NOW: its face, its name, and
    /// the one thing the book already knows about it.
    ///
    /// The setup screen's whole job is the moment between pasting an address
    /// and committing it, and until this it said nothing in that moment — you
    /// typed a 42-character string and pressed a verb, and the first proof the
    /// app had understood anything was a row appearing afterwards. The face is
    /// the proof, and it costs NOTHING: `WalletFace`'s identicon is
    /// deterministic from the address, so this is literally the same face the
    /// row will wear, drawn a second early. No balance is shown and none is
    /// read — that would be a metered call fired on every keystroke, and a
    /// figure here would be a claim about a wallet nobody has agreed to watch.
    ///
    /// It stands DOWN for a bulk paste (there is no one face to draw) and for a
    /// lookalike or a failed checksum, where the notice above is telling you to
    /// stop and a portrait underneath it is an invitation.
    @ViewBuilder
    private func addressPreview(isBulk: Bool) -> some View {
        if !isBulk, !draft.isEmpty, !draftIsUnsafe {
            if let address = previewAddress {
                let known = book.entry(for: address)
                HStack(spacing: DS.Space.s3) {
                    // `list`, not `row`: this is the same portrait the book
                    // rows below draw, and choosing whether this is the
                    // address you meant is the whole point of the moment.
                    WalletFace(address: address, size: DS.Face.list, circular: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(known?.name ?? draft)
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(previewFact(address: address, known: known))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Space.s2)
                .padding(.horizontal, DS.Space.s3)
                .background(DS.fillFaint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else if resolving {
                // A name being looked up is the one case worth a waiting tell:
                // the answer is a real network read, and silence here reads as
                // "it didn't recognise that".
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.mini)
                    Text("Looking up \(draft)…")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Space.s1)
            }
        }
    }

    /// The address the preview is about — what was typed when it's already an
    /// address, otherwise whatever the resolver answered FOR THIS DRAFT.
    private var previewAddress: String? {
        if book.looksLikeAddress(draft) { return draft }
        if let resolvedDraft, resolvedDraft.input == draft { return resolvedDraft.address }
        return nil
    }

    private var resolving: Bool {
        (SNS.looksLikeName(draft) || ENS.looksLikeName(draft)) && previewAddress == nil
    }

    /// A destructive notice is on screen — see `fieldNotice`.
    private var draftIsUnsafe: Bool {
        !book.lookalikes(of: draft).isEmpty || AddressSafety.checksum(draft) == .failed
    }

    /// The one line under the name. Ordered by what changes what you'd do:
    /// already watching (the verb would do nothing), already named (the verb
    /// would rename), then what it IS. A name that resolved says so with the
    /// address it resolved to — that is the app showing its working, and the
    /// most reassuring thing it can say before you commit.
    private func previewFact(address: String, known: AddressBook.Entry?) -> String {
        if let known, isWatched(known) { return String(localized: "Already watching") }
        var parts: [String] = []
        if address != draft { parts.append(WalletStore.shortAddress(address)) }
        if known != nil { parts.append(String(localized: "already in your book")) }
        if let label = known?.kind.label { parts.append(label) }
        else if let script = BitcoinAddress.scriptKind(address) { parts.append(script) }
        return parts.isEmpty
            ? String(localized: "New address")
            : parts.joined(separator: " · ")
    }

    /// Resolves a typed ENS/SNS name for the preview, debounced.
    ///
    /// Debounced because this fires per keystroke and "vitalik.eth" is nine
    /// prefixes that each look like a name; the pause is what makes it one
    /// request instead of nine. Nothing is watched, nothing is named, nothing
    /// is written — the answer only ever paints a face.
    private func resolvePreview() async {
        let asked = draft
        guard SNS.looksLikeName(asked) || ENS.looksLikeName(asked) else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        // `.sol` first, exactly like `watch()` — `ENS.looksLikeName` takes ANY
        // dotted string and would send a `.sol` name to the ENS resolver,
        // which answers with a null address rather than an error.
        let hit = SNS.looksLikeName(asked)
            ? await SNS.resolve(asked) : await ENS.resolve(asked)
        guard !Task.isCancelled, let hit else { return }
        withAnimation(DS.Motion.standard) {
            resolvedDraft = ResolvedDraft(input: asked, address: hit)
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
        .buttonStyle(PressSpring())
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
