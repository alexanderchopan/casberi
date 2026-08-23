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

// `BookSort` retired here 2026-08-22 (prd §440) — the order, its labels and
// the sectioning that follows from it all live in `AddressBookShape.Order`
// now, which is Foundation-only and therefore harnessable. A sort that decides
// what a list looks like and can never be tested is exactly the shape of thing
// this project has stopped writing.

/// A resolved ENS/SNS name, tied to the draft that asked for it (prd §433).
private struct ResolvedDraft: Equatable {
    let input: String
    let address: String
}

// `BookBlock` retired here 2026-08-22 (prd §440). §433 made a group a SECTION
// of this list; §440 gives it a card in a strip and a screen of its own, so
// the list below is one alphabetical run of the whole book rather than an
// ungrouped block followed by one section per group. The reasoning §433 gave
// for killing the group FILTER stands untouched and is why the strip is a set
// of doors rather than a set of selections.

// `BookSheetRoute` retired here 2026-08-22 (prd §440) — merged into
// `AddressBookSheetRoute`, which the group screen needs too. Two enums naming
// the same three doors is two places for a fourth door to be added to only
// one of them.

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
    @State private var bookSheet: AddressBookSheetRoute?
    /// How the list orders itself. **A–Z by default since 2026-08-22
    /// (prd §440)**, reversing §433's recent-with-watched-first.
    ///
    /// That ruling existed for a stated reason — "a bulk paste of forty names
    /// could push all five of your watched wallets off the bottom of the
    /// screen, in the manager whose whole job is them" — and the watched shelf
    /// at the top of this screen now holds those five unconditionally,
    /// whatever the list does. The reason is spent, and A–Z with letter
    /// headings and a scrubber is how a person finds one row out of
    /// twenty-seven. Recent and Most active keep their places in the menu.
    @State private var bookSort: AddressBookShape.Order = .name
    /// Every entry's landed-activity count, keyed the book's way. CACHED
    /// (2026-08-01): this was a computed property running an unscoped corpus
    /// fetch plus a full walk, and `ordered` reads it — so with
    /// "Most active" selected it ran on every body evaluation, which means
    /// once per keystroke in the omnibox above it, on the main thread. Built
    /// on appear and after each sync instead; the corpus doesn't change
    /// between those without one of them firing.
    @State private var activity: [String: AddressActivity.Summary] = [:]
    /// Which of the book's addresses are connected (prd §295) — rebuilt on the
    /// same two beats as `activityCounts` above and for the same reason: it is
    /// a corpus fetch plus a walk, and the corpus doesn't change between an
    /// appear and a sync without one of them firing.
    @State private var connections: AddressConnections.Map?
    /// Which group card a dragged row is currently over (prd §440), by the
    /// book's own case-fold. Held so exactly one card can light up: a
    /// `dropDestination`'s own `isTargeted` is per-card and two adjacent cards
    /// can both report true mid-drag.
    @State private var dropTarget: String?
    /// The group card currently ABSORBING a dropped address (prd §441) — a
    /// one-shot, cleared on a timer, so the deck can take the new face rather
    /// than have it appear.
    @State private var absorbing: String?
    /// Which connected addresses this device has never drawn (prd §441). Held
    /// beside `connections` and computed in the same walk, so the card can draw
    /// its arrivals on the frame it first appears.
    @State private var newConnections: Set<String> = []
    /// THE STAR FLIGHT (prd §441) — the address whose face is in the air
    /// between its book row and its shelf slot, and how far along it is.
    ///
    /// §212 retired the footer that explained the star on the grounds that
    /// "tapping a star visibly drops the wallet into the shelf at the top of
    /// the same screen, which teaches it better than the sentence did" — and
    /// then the wallet simply appeared. `connectPromote` lifts the row and the
    /// slot scales in, two animations that don't know about each other. This
    /// is the sentence made true.
    @State private var flying: FlightingFace?
    @State private var flightProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The connected address being named, and the draft. Naming here is the
    /// same act as naming from a transfer's sheet — it rewrites every landed
    /// transfer carrying that address (`CounterpartyRetitle`).
    @State private var namingAddress: String?
    @State private var namingDraft = ""
    // `groupUnderEdit` / `renamingGroup` / `confirmDeleteGroup` retired here
    // 2026-08-22 (prd §440) — rename and delete act on a GROUP, and a group
    // now has a screen where it is the subject. They live on its toolbar.

    /// The row that was just starred, and a token to fire its lift once (prd
    /// §433). The app's own `connectPromote` grammar — written for an app
    /// taking its connected seat in the catalog shelf — and this is the same
    /// event one screen over: an address promoted from named to watched, which
    /// also re-sorts it to the top of its section. Without the lift the row
    /// simply teleports, which reads as the list glitching rather than as the
    /// thing you just did.
    @State private var promotedEntryID: String?
    @State private var promoteToken = 0
    // `closedGroups` retired here 2026-08-22 (prd §440) — a group is a card
    // you open onto its own screen now, so there is no folder on this page to
    // be shut. §433's reasoning for never persisting the open/closed state
    // ("a closed folder is a reading posture, not a preference") is what made
    // it cheap to delete.

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
    /// The ids that paste actually ADDED (prd §440), so the confirmation can
    /// offer to file them as a batch. Cleared with `bulkResult`, since an
    /// offer that outlives the sentence explaining it files a paste the person
    /// has stopped thinking about.
    @State private var bulkLanded: Set<String> = []
    /// True while the "file the whole paste under a NEW group" alert is up.
    @State private var filingBulkGroup = false
    /// Set when tapping a star would exceed the watch cap — an honest modal,
    /// since the roster's empty slots can't show "already full" from inside
    /// the list (2026-07-24).
    @State private var watchCapHit = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// WIDE LAYOUT (prd §440) — iPad and Mac Catalyst put the shelf and the
    /// spine side by side instead of stacked.
    ///
    /// Not decoration: on a phone the spine is the second thing you scroll to
    /// and the book is the third, which is the right order at 390 points. At
    /// 1,000 the same stack leaves the book below the fold on a screen with
    /// two thirds of its width empty, and this is the manager most likely to
    /// be open on the Mac — `verify-mac.sh` sweeps it every night.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query(walletRecentDescriptor) private var recent: [Thing]

    private let rosterFaceSize: CGFloat = DS.Face.shelf
    /// Sized so ALL FIVE slots fit a phone's width without scrolling (prd
    /// §442). §182's whole claim is that the cap is "structure you can see
    /// rather than copy you hit", and at 74 the fifth slot sat off the right
    /// edge — so a shelf reading "2 of 5" showed four, which is the one thing
    /// a picture of a cap must not do. 5 × 64 + 4 × 8 = 352 against the 360
    /// a 390pt screen leaves inside the page margin.
    private let rosterSlotWidth: CGFloat = 64
    /// The two label lines under a roster face, height-locked so a watched
    /// slot and an empty one line up. Named rather than written twice: the
    /// two call sites MUST agree or a half-full shelf steps.
    private let rosterLabelHeight: CGFloat = 28

    var body: some View {
        // ONE search per body pass (prd §441). `book.search` was reached four
        // times — the sections, the id map, the header's count and the
        // scrubber's overlay — each re-filtering the whole book. Fine at forty
        // rows and wrong at four hundred, and the fix is not a cache across
        // passes (the book is `@Observable`, so a pass only happens when
        // something really changed) but computing it ONCE within the pass and
        // threading it down.
        let entries = visibleEntries
        let sections = bookSections(entries)
        let searching = !draft.isEmpty
        // ONE scroll, four readings (prd §440): the way in, who you watch, how
        // they connect, and the record. Each is a different question — the
        // §435 fusion failed because it treated five renderings of one graph
        // as one drawing, and the answer is not one drawing, it is four
        // sections that don't repeat each other.
        return ScrollViewReader { proxy in
            List {
                inputSection
                statusSection
                if !searching {
                    if wide {
                        wideTopSection
                    } else {
                        watchingSection
                        spineSection
                    }
                    groupsSection
                }
                bookSection(entries: entries, sections: sections, searching: searching)
                if !searching { footSection }
                // Room for the floating agent bar (FeedScreen's own pattern) —
                // the Connection row was this screen's own worst example of the
                // bar eating its last row before this (found live, 2026-07-22).
                Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            // TIGHTENED (prd §442, seen on a device). A Section per letter is
            // what buys sticky headings and the scrubber's anchors, and under
            // `insetGrouped` it also buys a full section gap between every
            // one of them — so a book of twenty-six letters was twenty-six
            // gaps, about seven rows a screen where Contacts fits twelve. The
            // headings stay; the air between them goes.
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            .dsSoftScrollEdges()
            .dsScreenTitle("Addresses")
            // The A–Z scrubber, over the list's trailing edge (prd §440).
            // An OVERLAY rather than a row, because it has to stay put while
            // the thing it aims at scrolls underneath it.
            // THE FLIGHT (prd §441). An `overlayPreferenceValue` over the
            // whole List, so the face can cross between two sections of it —
            // a per-row overlay would be clipped by the row it came from.
            .overlayPreferenceValue(AddressFlightAnchors.self) { anchors in
                AddressFlightOverlay(flight: flying, anchors: anchors,
                                     progress: flightProgress)
            }
            .overlay(alignment: .trailing) {
                if bookSort.sections, !searching {
                    AddressIndexBar(letters: AddressBookShape.index(of: sections)) { letter in
                        withAnimation(DS.Motion.standard) {
                            proxy.scrollTo("letter:" + letter, anchor: .top)
                        }
                    }
                }
            }
        }
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
        // Naming a connected address (prd §295) — the spine card's one action.
        // Same alert grammar as the wallet rename above it, and the same
        // consequence: the name rides every transfer with this address, past
        // and future.
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
            case .move(let entry):
                AddressMoveSheet(entry: entry)
            case .newGroup:
                // Nothing to select any more (prd §433) — a new group is a new
                // CARD, already in the strip under its own name, so the
                // gesture that made it is finished when the sheet closes.
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
            if !new.isEmpty { bulkResult = nil; bulkLanded = [] }
        }
        .alert("File this paste", isPresented: $filingBulkGroup) {
            TextField("Name (e.g. Family, Cold)", text: $groupDraft)
            Button("Create") { fileBulk(under: groupDraft) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Files the \(bulkLanded.count) addresses you just added under a new group.")
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

    // MARK: - The way in (prd §440)

    /// The field, and the door beside it.
    ///
    /// **One field, two jobs, decided by what you typed.** Words filter the
    /// book below; an address, ENS or `.sol` arms the verbs and brings up the
    /// preview. That was already how the model worked — `book.search(draft)`
    /// and `addressPreview` have read the same string since §433 — and what
    /// §440 changes is that the field now SAYS so, and that everything which
    /// isn't the book folds away while you are searching it.
    ///
    /// **There is no `+`.** It could only ever duplicate this field, and it
    /// could not be the connect door either: connecting has a waiting state and
    /// can sprout a manual-pairing card under it, neither of which a nav-bar
    /// glyph has anywhere to put. Two doors, two shapes.
    @ViewBuilder
    private var inputSection: some View {
        Section {
            // Bound ONCE: `looksLikeBulk` tokenizes the whole draft, and this
            // is read several times below — otherwise that is five re-parses
            // of a forty-line paste per keystroke.
            let isBulk = isBulkDraft
            VStack(spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Search, or paste an address"),
                            text: $newAddress,
                            // A pasted LIST gets its own verb (2026-08-01).
                            // Naming, never watching — a paste of forty can't
                            // watch against a cap of five, and the notice
                            // below says so.
                            actionLabel: isBulk ? String(localized: "ADD ALL")
                                                : String(localized: "WATCH"),
                            focus: $addressFieldFocused,
                            // The verbs ARM only over a real address, so the
                            // field reads as a search box while you are
                            // searching with it — which is most of the time
                            // on a book of forty.
                            isArmed: isBulk || book.looksLikeAddress(draft),
                            // The lightweight second verb (§212): watching is
                            // capped at 5 and starts syncing; naming is
                            // neither. This is also the cap's own honest way
                            // out, since WATCH at the limit has to send you
                            // somewhere.
                            secondaryLabel: String(localized: "NAME"),
                            secondaryArmed: !isBulk && book.looksLikeAddress(draft),
                            secondaryAction: justName,
                            action: { isBulk ? addAll() : watch() })
                fieldNotice(isBulk: isBulk)
                // What you're about to add, before you add it (prd §433).
                // Keyed on the ADDRESS, not the draft: animating on the draft
                // would re-run this spring on every keystroke, and the moment
                // worth showing is the face arriving.
                addressPreview(isBulk: isBulk)
                    .animation(DS.Motion.standard, value: previewAddress)
                // The automatic way in. It STEPS ASIDE the moment you type
                // (prd §440): it is only relevant on an empty field, so
                // leaving it under the preview would stack two ways to add one
                // address on top of each other.
                if WalletConnectBridge.isAvailable, draft.isEmpty {
                    connectRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                // Nothing watched, nothing typed — one tap watches a famous
                // public wallet so the whole feature demos in three seconds.
                if wallet.addresses.isEmpty, draft.isEmpty {
                    peekChip
                }
            }
            .animation(DS.Motion.standard, value: draft.isEmpty)
        }
        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Who you watch (prd §440)

    /// The shelf, its caption, and the honest line under it.
    ///
    /// Unconditional now — §435 made it the sky's fallback, and the sky is
    /// gone. Every §182 ruling survives: a face for every wallet you watch, a
    /// dashed ring for every slot you don't, so the cap is a shape you can see
    /// filling rather than a sentence you hit.
    @ViewBuilder
    private var watchingSection: some View {
        Section {
            rosterSection
        } header: {
            sectionHeader(String(localized: "Watching"),
                          trailing: String(localized: "\(wallet.addresses.count) of \(WalletStore.watchLimit)"),
                          busy: syncing)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// True where there is room for two columns. Read once and passed down,
    /// so the two halves can never disagree about which layout they are in.
    private var wide: Bool { horizontalSizeClass == .regular }

    /// The shelf and the spine, side by side (prd §440).
    ///
    /// One Section rather than two, because the two columns have to share a
    /// row — as separate sections they would stack again whatever their own
    /// frames said. The shelf takes the narrower side: five faces have a
    /// natural width and the spine is the thing that benefits from the room.
    @ViewBuilder
    private var wideTopSection: some View {
        Section {
            HStack(alignment: .top, spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    sectionHeader(String(localized: "Watching"),
                                  trailing: String(localized: "\(wallet.addresses.count) of \(WalletStore.watchLimit)"),
                                  busy: syncing, inset: false)
                    rosterSection
                        // The shelf carries its own horizontal padding for the
                        // phone's edge-to-edge scroll; inside this row that
                        // padding is already spent.
                        .padding(.horizontal, -DS.Space.s4)
                }
                .frame(maxWidth: 300, alignment: .leading)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if connections != nil || wallet.addresses.count == 1 {
                        sectionHeader(String(localized: "How they connect"), inset: false)
                    }
                    wideSpine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// The spine's card WITHOUT its own Section wrapper — the wide layout
    /// supplies the row. Shares every empty-state ruling with `spineSection`
    /// by calling the same two branches; a second copy of that judgement is
    /// how one layout ends up honest and the other doesn't.
    @ViewBuilder
    private var wideSpine: some View {
        if let connections {
            AddressSpineCard(map: connections, newNodeIDs: newConnections) { node in
                DSHaptic.tap()
                namingAddress = node.address
                namingDraft = ""
            } onOpen: { node in
                bookSheet = .entry(book.entry(for: node.address)
                                   ?? AddressBook.Entry(address: node.address,
                                                        name: node.name,
                                                        addedAt: .now))
            }
            .onAppear { AddressConnectionsSeen.markSeen(newConnections) }
        } else if wallet.addresses.count == 1 {
            Text("Watch a second address to see how they connect.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - How they connect (prd §440)

    /// The spine, or the honest sentence that stands where it would be.
    ///
    /// **Both empty states are designed rather than left to fall out**, which
    /// is the correction §436–§438 kept paying for: the minimum corpus is the
    /// COMMON one here, and treating it as an edge case is what put a clump of
    /// faces on somebody's screen three times.
    ///
    /// - **Nothing watched**: no card at all. There is nothing to connect and
    ///   nothing to say about it; the shelf above is already the invitation.
    /// - **One wallet**: a line, not a card. A lone wallet has nothing to be
    ///   connected TO, and a card headed "Connected" over that fact reads as a
    ///   feature that is broken rather than one that isn't applicable yet.
    /// - **Two or more, nothing shared**: the card, stating none. That IS an
    ///   answer, and it is the one `AddressConnections.headline` exists for.
    @ViewBuilder
    private var spineSection: some View {
        if let connections {
            Section {
                AddressSpineCard(map: connections, newNodeIDs: newConnections) { node in
                    DSHaptic.tap()
                    namingAddress = node.address
                    namingDraft = ""
                } onOpen: { node in
                    bookSheet = .entry(book.entry(for: node.address)
                                       ?? AddressBook.Entry(address: node.address,
                                                            name: node.name,
                                                            addedAt: .now))
                }
                // Marked seen only once it has actually BEEN on screen
                // (§435's own lesson, kept): flagging at build time would make
                // a new connection new for as long as it took to compose the
                // view and never let it draw itself as new at all.
                .onAppear { AddressConnectionsSeen.markSeen(newConnections) }
            } header: {
                sectionHeader(String(localized: "How they connect"))
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if wallet.addresses.count == 1 {
            Section {
                Text("Watch a second address to see how they connect.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowInsets(EdgeInsets(top: DS.Space.s3, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Groups (prd §440)

    /// The strip — one card per group, plus the door that makes one.
    ///
    /// Horizontal, and a CARD rather than a chip, for two reasons that both
    /// come down to a group finally having somewhere to be: a card has room
    /// for the deck of faces that says WHO (which is the only thing a group of
    /// addresses is for), and a card is big enough to be a DROP TARGET, which
    /// is what makes dragging a row into a group the plainest way to file one.
    ///
    /// It renders only when a group exists, or when the book is big enough
    /// that filing is worth offering. A "New group" tile floating alone above
    /// a five-row book is a control for a problem nobody has yet.
    @ViewBuilder
    private var groupsSection: some View {
        let groups = book.groupNames
        if !groups.isEmpty || book.count >= Self.groupsOfferFloor {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s3) {
                        ForEach(Array(groups.enumerated()), id: \.element) { index, group in
                            groupCard(group)
                                .staggerIn(index: index, step: 0.04)
                        }
                        newGroupCard
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s1)
                }
            } header: {
                sectionHeader(String(localized: "Groups"))
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// A book smaller than this has nothing to organize — filing five
    /// addresses is busywork, and the strip would be one dashed tile.
    private static let groupsOfferFloor = 6

    private func groupCard(_ group: String) -> some View {
        // Per-card, but each card is one filtered pass over the book — the
        // sort inside `entries(inGroup:)` is what `AddressGroupScreen` and the
        // filing sheet had to hoist; here the DECK needs the entries
        // themselves (their marks), so the filter is the honest cost and four
        // cards is four passes, not four sorts of consequence at this size.
        let members = book.entries(inGroup: group)
        let key = AddressBook.key(forGroup: group)
        return AddressGroupCard(group: group,
                                members: members,
                                watched: members.filter(isWatched).count,
                                targeted: dropTarget == key,
                                absorbing: absorbing == key) {
            DSHaptic.selection()
            route.push(.addressGroup(group))
        }
        // **DROP TO FILE** (prd §440). The payload is the address string —
        // the row's own identity, not an index, so a list that re-sorts
        // mid-drag can't file the wrong one.
        .dropDestination(for: String.self) { items, _ in
            guard let address = items.first else { return false }
            book.addToGroup(group, address: address)
            DSHaptic.success()
            dropTarget = nil
            // THE DECK ABSORBS IT (prd §441). A one-shot flag rather than
            // anything derived from membership: the book is `@Observable`, so
            // the card has already re-rendered with the new face by the time
            // any diff could be taken. Cleared on a timer because there is no
            // completion to hang it on — the animation it drives lives inside
            // the card.
            absorbing = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                if absorbing == key { absorbing = nil }
            }
            return true
        } isTargeted: { over in
            // Exactly one card lights up. A `dropDestination`'s own targeting
            // is per-card, and two adjacent cards can both report true while a
            // finger sits between them.
            withAnimation(DS.Motion.press) {
                if over { dropTarget = key }
                else if dropTarget == key { dropTarget = nil }
            }
        }
    }

    private var newGroupCard: some View {
        Button {
            DSHaptic.tap()
            bookSheet = .newGroup
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .dsGlyph(18, weight: .regular)
                    .foregroundStyle(DS.textTertiary)
                Text("New group")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            .frame(width: 108, height: 96)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.textTertiary.opacity(0.28),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(PressSpring())
    }

    // MARK: - The foot

    /// The connection plumbing and the promise. Chains and teardown are the one
    /// thing here nobody revisits, so they sit after the list rather than
    /// between the verbs and the names.
    private var footSection: some View {
        Section {
            VStack(spacing: DS.Space.s4) {
                DSSlabDoor(title: "Connection", detail: chainsSummary) {
                    route.pushBridge(.walletConnection)
                }
                Text("Read-only — watching can never move funds.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Every section's head, spelled once — a word and, sometimes, a fact on
    /// the right. Sentence case, no letter-spacing, no eyebrow (§8).
    ///
    /// `busy` is passed rather than tested against the title: deciding whether
    /// to draw a spinner by comparing a localized string to another localized
    /// string works and is the kind of coupling that survives right up until
    /// somebody renames the section.
    ///
    /// `inset` exists because this is drawn in TWO positions — as a `List`
    /// section header, which sits outside the row's own insets, and inside the
    /// wide layout's row, which already has them. Negating the padding at the
    /// call site was the alternative and is how two layouts end up a few
    /// points apart with nothing saying why.
    private func sectionHeader(_ title: String, trailing: String? = nil,
                               busy: Bool = false, inset: Bool = true) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(title)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            if busy {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, inset ? DS.Space.s4 : 0)
        // The List already spaces its sections; this used to add a fourth
        // rung of air on top of that and was most of why the screen read as
        // half-empty on a phone.
        .padding(.top, DS.Space.s2)
    }

    // MARK: - The roster (prd §182)

    /// The watched wallets as a shelf of faces, plus their REAL empty slots up
    /// to the cap — a face for every wallet you're watching, a dashed ring for
    /// every slot you aren't. The cap stops being a sentence you hit and
    /// becomes a shape you can see filling: five faces means full, and no
    /// separate "limit reached" card has to say so.
    // The SKY retired here 2026-08-22 (prd §440). §435 replaced this shelf,
    // the connections card and the group decks with one drawing; §436, §437,
    // §438 and §439 each redrew it after a device showed it could not be read.
    // The arithmetic was harness-proven every time — the fault was that a
    // force-free layout has to answer a different geometric question for every
    // corpus shape, and this corpus is almost always the minimum one. The
    // reading survives in `AddressSpineCard`, which draws the same
    // `AddressConnections` map as two columns and a ribbon each.
    //
    // The SHELF below is unchanged and is now unconditional rather than the
    // sky's fallback: §182's faces, its real empty slots and its cap-as-a-shape
    // were never the thing that was wrong.

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
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
            // The shelf's own caption retired here 2026-08-22 (prd §440) — the
            // section header above it states "3 of 5" and carries the syncing
            // spinner, so this line was the same fact printed twice, eight
            // points apart. The total §212 also put here was struck out by
            // §435 and stays struck.
        }
    }

    /// One watched wallet's face — tap renames (the row's own tap-again
    /// grammar, unchanged from before the redesign), long-press offers Copy
    /// and Remove (the gesture the roster's card shape actually teaches,
    /// replacing the old swipe-to-remove a horizontal shelf can't perform).
    private func rosterSlot(_ addr: WalletStore.WatchedAddress) -> some View {
        VStack(spacing: 6) {
            WalletFace(address: addr.address, size: rosterFaceSize, circular: true)
                // The flight's landing point (prd §441). Keyed by the BOOK's
                // key for this address, which is what the row publishes too —
                // a watch may be stored under the spelling it was added with
                // ("vitalik.eth") while the book holds the resolved address, so
                // keying on the raw string would leave the two anchors unable
                // to find each other on exactly the wallets people name.
                .flightAnchor("slot:" + AddressBook.key(for: addr.address))
                // Hidden while its own face is still in the air, so the two
                // are never on screen at once.
                .opacity(flying?.id == AddressBook.key(for: addr.address)
                         && flightProgress < 0.92 ? 0 : 1)
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

    /// Every named address, watched or not — ALL of it, on this one list
    /// (2026-07-24). The old split (a roster for watched, a door to a separate
    /// screen for everyone else) was the actual "which page is this on"
    /// confusion; one list with a "Watching" star on the entries that are is
    /// the honest merge, not two views pretending to be one.
    ///
    /// Filtered by the field, then handed to `AddressBookShape` — which owns
    /// the ORDER and the SECTIONS and is Foundation-only, so every decision it
    /// makes is harness-proven. What stays here is only what needs the store:
    /// which entries match, and which of them are watched.
    private var visibleEntries: [AddressBook.Entry] {
        book.search(newAddress)
    }

    /// The rows, as the shape layer sees them.
    private func shapeRows(_ entries: [AddressBook.Entry]) -> [AddressBookShape.Row] {
        entries.map {
            AddressBookShape.Row(id: $0.id, name: $0.name, addedAt: $0.addedAt,
                                 watched: isWatched($0),
                                 activity: activity[$0.id]?.count ?? 0)
        }
    }

    /// The book, cut into the list's sections.
    ///
    /// **While SEARCHING the sectioning collapses**, whatever the sort says:
    /// putting four matches under three letter headings is noise, and the
    /// person is looking for one row rather than for where it files.
    private func bookSections(_ entries: [AddressBook.Entry]) -> [AddressBookShape.Section] {
        let rows = shapeRows(entries)
        guard !rows.isEmpty else { return [] }
        guard draft.isEmpty else {
            return [AddressBookShape.Section(
                letter: nil,
                ids: AddressBookShape.ordered(rows, order: .name).map(\.id))]
        }
        return AddressBookShape.sections(rows, order: bookSort)
    }

    // `entriesByID` retired 2026-08-22 (prd §441) — it re-ran the search to
    // build its dictionary, which was one of the four passes the body hoist
    // exists to remove. Built once inside `bookSection` from the array it is
    // already handed.

    /// Rebuilds the activity cache. Shares ONE definition of activity with the
    /// address card's own "Your history together" (`AddressActivity`) — they
    /// disagreed before, so a wallet whose activity was mostly Peer fills
    /// sorted as inactive while its card said "· 40".
    private func refreshActivityCounts() {
        refreshReadings()
    }

    /// The book's own summary (prd §295). Nil below two watched wallets — a
    /// connection can't exist there, so the card doesn't render rather than
    /// rendering empty.
    private func refreshConnections() {
        refreshReadings()
    }

    /// ONE corpus walk, both readings (2026-08-22, prd §441).
    ///
    /// These were two functions each running its own fetch plus its own full
    /// walk, called back to back in `onAppear` and again after every sync — on
    /// the main actor, over overlapping predicates, on the screen this app
    /// opens more than any other. `AddressConnections` reads Wallet things and
    /// `AddressActivity` reads Wallet + Peer + Privacy Pools, a superset, so
    /// the subset was being fetched twice for nothing.
    ///
    /// The two names above survive as thin forwards because they read
    /// differently at their call sites ("bring the counts up to date" vs
    /// "bring the connections up to date") and because a caller that wants
    /// only one of them still costs exactly one walk either way.
    private func refreshReadings() {
        let things = AddressActivity.relevant(in: modelContext)
        activity = AddressActivity.summaries(from: things)
        let map = AddressConnections.map(things: things)
        // WHAT'S NEW SINCE YOU LAST LOOKED (prd §441). Computed before the map
        // is published, so the card draws its dashed arrivals on the same
        // frame it first appears rather than a beat later.
        newConnections = AddressConnectionsSeen.unseen(in: map)
        connections = map
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

    // `groupHeader` / `toggleGroup` / `groupNote` retired here 2026-08-22
    // (prd §440) — a group is an `AddressGroupCard` in the strip and an
    // `AddressGroupScreen` behind it now, so its faces, its count and its two
    // verbs all live on the group rather than on a heading inside somebody
    // else's list. `skyNotes` went with the sky; the three word-facts it
    // carried are on `AddressSpineCard`, which is where they were before §435
    // moved them out.

    /// The book — one section per letter (prd §440).
    ///
    /// It was one section carrying whatever the group filter had left (§267),
    /// then an ungrouped block plus one section per group (§433). It is the
    /// whole book in alphabetical order now, because groups have a strip and a
    /// screen of their own and no longer need to borrow this list's structure.
    @ViewBuilder
    private func bookSection(entries: [AddressBook.Entry],
                             sections: [AddressBookShape.Section],
                             searching: Bool) -> some View {
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let colliding = book.collidingKeys
        // GROUP RESULTS lead the matches (prd §440) — typing "fam" should open
        // Family, not merely list the four addresses in it. §267's ruling is
        // that the omnibox is where a group becomes findable, and until now it
        // could only ever find a group's MEMBERS.
        let groupHits = searching ? book.matchingGroups(draft) : []
        if !groupHits.isEmpty {
            Section {
                ForEach(groupHits, id: \.self) { group in
                    groupResultRow(group)
                }
            } header: {
                sectionHeader(groupHits.count == 1
                              ? String(localized: "1 group")
                              : String(localized: "\(groupHits.count) groups"))
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        if sections.isEmpty {
            // The book rendered NOTHING when it was empty (2026-08-01), which
            // made two different states look identical: a book you haven't
            // started, and a search that missed.
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
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                Section {
                    ForEach(Array(section.ids.enumerated()), id: \.element) { row, id in
                        if let entry = byID[id] {
                            bookRow(entry, colliding: colliding.contains(id), row: row)
                        }
                    }
                } header: {
                    bookSectionHeader(section, isFirst: index == 0,
                                      count: entries.count, searching: searching)
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    /// A letter, or — on the first section — the list's own head.
    @ViewBuilder
    private func bookSectionHeader(_ section: AddressBookShape.Section,
                                   isFirst: Bool, count: Int,
                                   searching: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // The list's head rides the FIRST section whatever that section
            // is. It used to be gated on the block being the ungrouped one,
            // which quietly deleted the sort menu and "Copy all as text" for
            // anyone who had filed EVERY address into a group.
            if isFirst { bookListHeader(count: count, searching: searching) }
            if let letter = section.letter {
                Text(letter)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        // The scrubber aims at THIS — one anchor per lettered section, and
        // the head's own anchor for the unlettered case, so `scrollTo` never
        // has an id it can't find.
        .id("letter:" + (section.letter ?? "\u{0}all"))
    }

    /// The head of the list — its count and its sort (prd §212), a small gray
    /// label wearing the same anatomy the wallet feed's section labels use.
    ///
    /// The COUNT is the whole book's. The searching case states itself.
    private func bookListHeader(count: Int, searching: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(searching
                 ? String(localized: "\(count) matching")
                 : String(localized: "Saved · \(book.count)"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Picker("Sort by", selection: $bookSort) {
                    ForEach(AddressBookShape.Order.allCases, id: \.self) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                // The paste-out half of the round trip. The Data tray owns
                // BACKUP (it carries the book losslessly); this is the other
                // job — names into another app.
                Section {
                    Button {
                        DSPasteboard.copySensitive(book.exportText())
                        DSHaptic.success()
                    } label: {
                        Label("Copy all as text", systemImage: "doc.on.doc")
                    }
                }
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
                .foregroundStyle(bookSort == .name ? DS.textTertiary : DS.tint)
            }
            .accessibilityLabel(Text("Sort: \(bookSort.label)"))
        }
    }

    /// A group offered as a search result — the door §267 always meant the
    /// omnibox to be.
    private func groupResultRow(_ group: String) -> some View {
        let members = book.entries(inGroup: group)
        return Button {
            DSHaptic.selection()
            route.push(.addressGroup(group))
        } label: {
            HStack(spacing: DS.Space.s3) {
                HStack(spacing: -6) {
                    ForEach(members.prefix(3)) { entry in
                        AddressMark(entry: entry, size: DS.Face.row)
                            .overlay(Circle().strokeBorder(DS.page, lineWidth: 1.5))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(group)
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(members.count == 1 ? String(localized: "1 address")
                                            : String(localized: "\(members.count) addresses"))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .dsGlyph(12, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyBookLine: String {
        if !draft.isEmpty {
            return String(localized: "No name, address or group here matches “\(draft)”.")
        }
        return String(localized: "No names yet. Name an address and every transfer reads by that name.")
    }

    /// One row of the book — the shared anatomy, plus this list's three
    /// gestures.
    ///
    /// **Tap** opens the card. **Long-press** offers the verbs (§212's ruling
    /// that a write belongs behind a deliberate press, and the design law's
    /// own "swipe verbs are reads"). **Drag** files it into a group — and the
    /// swipe offers `Move…`, which opens the filing sheet rather than writing
    /// anything, so it stays a door and not a write.
    private func bookRow(_ entry: AddressBook.Entry, colliding: Bool, row: Int) -> some View {
        let groups = book.groupNames
        return Button {
            DSHaptic.selection()
            bookSheet = .entry(entry)
        } label: {
            AddressBookRow(entry: entry,
                           activity: activity[entry.id],
                           watched: isWatched(entry),
                           colliding: colliding,
                           // The flight's takeoff point — published by the MARK
                           // rather than the row, so the face leaves from where
                           // the face actually is.
                           markAnchor: "row:" + entry.id) {
                toggleWatch(entry, currentlyWatched: isWatched(entry))
            }
        }
        .buttonStyle(.plain)
        // The promotion, felt (prd §433) — reads `isTarget` at fire time, so
        // starring one row never lifts another.
        .connectPromote(isTarget: entry.id == promotedEntryID, token: promoteToken)
        // The entrance this list never had (prd §433). Capped so a long book's
        // tail isn't still arriving after the scroll; Reduce Motion is handled
        // inside `settleIn`.
        .settleIn(delay: Double(min(row, 8)) * 0.02)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        // **DRAG TO FILE** (prd §440) — the payload is the address itself, so
        // a list that re-sorts mid-drag can never file the wrong row.
        //
        // `draggable` and `contextMenu` coexist by UIKit's own arbitration: a
        // long press that MOVES becomes a drag, one that HOLDS opens the menu.
        // UNVERIFIED on a device — if it turns out to fight the menu, the
        // swipe and the address card are the two doors that don't depend on
        // it, which is why there are three.
        .draggable(entry.address) {
            AddressMark(entry: entry, size: DS.Face.list)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                DSHaptic.tap()
                bookSheet = .move(entry)
            } label: {
                Label("Move…", systemImage: "folder")
            }
            .tint(DS.tint)
        }
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
            launchFlight(entry)
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
    /// Sends the face across the gap (prd §441).
    ///
    /// Deferred by one runloop turn ON PURPOSE: the shelf slot does not exist
    /// until the write above has been observed and the body re-run, so
    /// publishing the flight in the same turn gives the overlay a `from`
    /// anchor and no `to` — which draws nothing at all and reads as the
    /// feature being absent rather than broken. Waiting one turn is what makes
    /// both endpoints real.
    ///
    /// The progress is animated in a SECOND turn after that, because a
    /// `withAnimation` in the same turn the view first appears has no prior
    /// value to interpolate from and lands finished.
    private func launchFlight(_ entry: AddressBook.Entry) {
        guard !reduceMotion else { return }
        flightProgress = 0
        flying = FlightingFace(id: entry.id, address: entry.address)
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.52, bounce: 0.12)) {
                flightProgress = 1
            } completion: {
                // Cleared only after the animation really ends — clearing on a
                // timer races a slow frame and leaves the face parked mid-air.
                flying = nil
                flightProgress = 0
            }
        }
    }

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
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                noticeLine("checkmark.circle.fill", DS.confirm, bulkResult)
                // FILE THE WHOLE PASTE (prd §440). One tap per group rather
                // than one per address, and it uses the book's own
                // `addToGroup(_:addresses:)`, which exists for exactly this
                // and had no caller that could reach it with a real batch.
                if !bulkLanded.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s2) {
                            ForEach(book.groupNames, id: \.self) { group in
                                fileAllChip(group)
                            }
                            Button {
                                DSHaptic.tap()
                                groupDraft = ""
                                filingBulkGroup = true
                            } label: {
                                chipLabel(String(localized: "New group…"), tinted: true)
                            }
                            .buttonStyle(PressSpring())
                        }
                    }
                }
            }
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
        let before = Set(book.all.map(\.id))
        let landed = book.addBulk(newAddress)
        newAddress = ""
        addressFieldFocused = false
        guard landed > 0 else { return }
        DSHaptic.success()
        bulkResult = String(localized: "\(landed) named.")
        // The addresses this paste just landed, held so the confirmation can
        // offer to FILE them (prd §440). A paste of forty is precisely when
        // somebody already has a group in mind — it is a batch that arrived
        // together and belongs together — and the alternative was forty
        // long-presses. `addBulk` reports a count and not the keys, so the
        // set is taken as the difference across the write: the ids the book
        // gained. That also means a re-paste of addresses already in the book
        // offers nothing, which is correct — nothing new arrived to file.
        bulkLanded = Set(book.all.map(\.id)).subtracting(before)
        // Every landed transfer brought in line with the whole book at once —
        // `applyCurrentName` per address would re-fetch the corpus per line.
        CounterpartyRetitle.applyBook(in: modelContext)
        // No `refreshActivityCounts()` here on purpose: the counts are derived
        // purely from the corpus, and a paste lands book entries, never things.
    }

    /// "All 5" when nothing's narrowed, else the selected names ("Ethereum,
    /// Base +3" past two) — the Connection door's own one-line fact.
    /// One "file the paste under this group" chip.
    private func fileAllChip(_ group: String) -> some View {
        Button {
            DSHaptic.tap()
            fileBulk(under: group)
        } label: {
            chipLabel(group, tinted: false)
        }
        .buttonStyle(PressSpring())
    }

    private func chipLabel(_ text: String, tinted: Bool) -> some View {
        Text(text)
            .dsText(.label12).fontWeight(.semibold)
            .foregroundStyle(tinted ? DS.tint : DS.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 7)
            .background(DS.fillFaint, in: Capsule())
    }

    /// Files everything the last paste landed under one group, in ONE write.
    ///
    /// `addToGroup(_:addresses:)`'s own reason for existing: `entries`' `didSet`
    /// persists the whole book, so filing forty addresses one at a time is
    /// forty encodes of the same dictionary.
    private func fileBulk(under group: String) {
        let addresses = book.all.filter { bulkLanded.contains($0.id) }.map(\.address)
        guard !addresses.isEmpty,
              book.addToGroup(group, addresses: addresses) != nil else { return }
        DSHaptic.success()
        bulkResult = String(localized: "\(addresses.count) filed under \(group).")
        bulkLanded = []
    }

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
    /// The automatic way in — a ROW, not a call to action (prd §442, seen on
    /// a device).
    ///
    /// It was a full-width filled `DSSlabButton`, which is right for a screen
    /// whose one job is to connect something and wrong here: §440 put this
    /// beside a field that is the primary way in, and the blue slab outshouted
    /// it — the loudest thing on the screen was the SECOND choice. It is the
    /// same weight as the Connection door at the foot now: a mark, a sentence,
    /// a chevron.
    ///
    /// The BUSY state keeps the spinner and the "tap to cancel" wording,
    /// because the wait is real and the person needs the way out (§83 — the
    /// proposal runs to a five-minute expiry, and somebody who chose not to
    /// approve must not find a stuck control).
    private var connectRow: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Button {
                DSHaptic.tap()
                if connecting { cancelConnect() } else { connectWallet() }
            } label: {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "wallet.pass.fill")
                        .dsGlyph(15, weight: .medium)
                        .foregroundStyle(DS.tint)
                        .frame(width: 34, height: 34)
                        .background(DS.tintDim, in: RoundedRectangle(
                            cornerRadius: DS.Radius.appIcon(34), style: .continuous))
                    Text(connecting ? "Waiting — tap to cancel" : "Connect a wallet app")
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if connecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .dsGlyph(12, weight: .semibold)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.surfaceRaised, in: RoundedRectangle(
                    cornerRadius: DS.Radius.card, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(connecting ? "Waiting for your wallet, tap to cancel"
                                                : "Connect a wallet app"))
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
                CopyAddressButton(address: uri.absoluteString, style: .inline)
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
