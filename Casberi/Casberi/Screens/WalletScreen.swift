import SwiftUI
import SwiftData

/// A resolved ENS/SNS name, tied to the draft that asked for it (prd §433).
private struct ResolvedDraft: Equatable {
    let input: String
    let address: String
}

/// The five addresses this app reads — and nothing else (prd §461).
///
/// **The boundary is OWNERSHIP** (user, 2026-08-24: "the setup screen only
/// allows five wallets and there is no concept of starring"). This screen is
/// the roster: your own wallets, the two ways to add one, the chains reached
/// and the read-only promise. Everyone ELSE — every name, every group, how they
/// connect, your history with each — is `AddressBookScreen`, a room reached from
/// the wallet rail's own door and from the row at the foot of this list.
///
/// **Why the earlier splits kept failing, recorded because it took four.** §182
/// made this a roster with the book merged in; §433 gave groups folder sections;
/// §440 gave it four sections; §448 folded the watched shelf into the book. Each
/// was right about the duplication it removed and none of them separated the two
/// jobs, because "watched" was modelled as an ATTRIBUTE of a person — so any
/// screen that showed it showed people, and a screen showing people is a second
/// address book. Making it MEMBERSHIP of a five-slot roster is what removes the
/// crossing instead of relocating it, and it is what deletes the star: there is
/// no per-person toggle anywhere in the app any more, and therefore nothing on a
/// reading surface that can change what the app fetches.
///
/// **What that costs, stated.** Promoting a book contact to a watched wallet is
/// no longer one tap from its row — you paste or connect it here. That is the
/// ruling rather than an oversight: the five feed the crown balance ("Across
/// your wallets"), which is a claim about wallets you own, and a one-tap star on
/// a stranger's row is how somebody else's money ends up inside your total.
struct WalletScreen: View {
    @Bindable private var wallet = WalletStore.shared
    /// Read for two things only: the preview's "already in your book" line, and
    /// the entry a roster row draws (a wallet watched before it was ever named
    /// has no entry of its own, so one is synthesised). The book's own LIST is
    /// not here — see `AddressBookScreen`.
    @Bindable private var book = AddressBook.shared
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var newAddress = ""
    @FocusState private var addressFieldFocused: Bool
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
    /// Which wallet the rename alert is editing.
    @State private var renamingID: WalletStore.WatchedAddress.ID?
    @State private var renameDraft = ""
    /// This screen's ONE presentation — the connect picker (FeedScreen's
    /// lesson: sibling `.sheet` modifiers on one screen start silently
    /// self-dismissing each other's first tap). It shares
    /// `AddressBookSheetRoute` with the book room rather than declaring a
    /// second enum for one case; the other three cases are unreachable here and
    /// are answered rather than left to a runtime surprise.
    @State private var sheetRoute: AddressBookSheetRoute?
    /// Set when a watch would exceed the cap — an honest modal, since the
    /// roster cannot show "already full" from inside itself (2026-07-24).
    @State private var watchCapHit = false
    /// What the typed ENS/SNS name resolved to, keyed by the input that asked.
    /// Keyed rather than bare so a slow answer for "vitalik.eth" can never
    /// paint itself under a draft that has since become something else.
    @State private var resolvedDraft: ResolvedDraft?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            roomDoorSection
            inputSection
            statusSection
            rosterSection
            bookDoorSection
            footSection
            // Room for the floating agent bar (FeedScreen's own pattern) — the
            // Connection row was this screen's own worst example of the bar
            // eating its last row before this (found live, 2026-07-22).
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
        .dsScreenTitle("Addresses")
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
                    // roster is the same act as naming it from its card, and
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
        .alert("Watching \(WalletStore.watchLimit) already", isPresented: $watchCapHit) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Watching \(WalletStore.watchLimit) — the cap. Remove one first; its name stays in your book.")
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .connectPicker(let accounts):
                WalletConnectPickerSheet(shared: accounts) { added in
                    if added > 0 { sync() }
                }
            case .entry(let entry):
                AddressCard(entry: entry)
            case .move(let entry):
                AddressMoveSheet(entry: entry)
            case .newGroup:
                NewGroupSheet { _ in }
            }
        }
        .onAppear {
            if !wallet.addresses.isEmpty {
                sync()
                Task { await wallet.loadAvatars() }
            }
        }
    }

    // MARK: - The way onward (prd §460)

    /// `RoomDoor`, the same control every other connect page carries — identity,
    /// then the way onward, then the details. It was the one screen in the
    /// catalog's largest family without one, because it is not a
    /// `BridgeSetupHeader` screen and §460 swept those.
    private var roomDoorSection: some View {
        RoomDoor(name: "Wallet", source: "Wallet")
    }

    // MARK: - The way in

    /// The field, and the door beside it.
    ///
    /// **One address, one verb** (prd §461). It was an omnibox: it searched the
    /// book, named without watching, and took a pasted LIST of forty. All three
    /// of those are the book's, and they went with it — what is left is the one
    /// act this screen exists for. `isArmed` still gates on the draft looking
    /// like an address, so an empty field is not a live button.
    @ViewBuilder
    private var inputSection: some View {
        Section {
            VStack(spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Paste an address, or an ENS name"),
                            text: $newAddress,
                            actionLabel: String(localized: "Watch"),
                            focus: $addressFieldFocused,
                            isArmed: book.looksLikeAddress(draft)
                                     || SNS.looksLikeName(draft)
                                     || ENS.looksLikeName(draft),
                            action: watch)
                fieldNotice
                // What you're about to add, before you add it (prd §433). Keyed
                // on the ADDRESS, not the draft: animating on the draft would
                // re-run this spring on every keystroke, and the moment worth
                // showing is the face arriving.
                addressPreview
                    .animation(DS.Motion.standard, value: previewAddress)
                // The automatic way in. It STEPS ASIDE the moment you type
                // (prd §440): it is only relevant on an empty field, so leaving
                // it under the preview would stack two ways to add one address
                // on top of each other.
                if WalletConnectBridge.isAvailable, draft.isEmpty, wallet.canWatchMore {
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

    /// The one line under the field, when there's something worth saying about
    /// what's typed. Ordered by consequence: a lookalike is a security fact and
    /// outranks everything; a failed checksum is a typo about to become a watch.
    /// Silent otherwise — a field that always has a line under it has no way to
    /// warn.
    @ViewBuilder
    private var fieldNotice: some View {
        if let twin = book.lookalikes(of: draft).first {
            // The whole point of a named-address ledger, cashed in: the book
            // already holds the address you meant, so it can say which one this
            // ISN'T. Poisoning works precisely because every truncated display
            // in every wallet app hides the difference.
            noticeLine("exclamationmark.triangle.fill", DS.destructive,
                       String(localized: "Looks like \(twin.name) — but it's a different address. Check every character."))
        } else if AddressSafety.checksum(draft) == .failed {
            noticeLine("exclamationmark.triangle.fill", DS.destructive,
                       String(localized: "That address fails its own checksum — a character is wrong somewhere."))
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

    // MARK: - The roster (prd §461)

    /// Your own wallets, in the order you added them — not A–Z, because five
    /// rows don't need finding and the order you added them is the order you
    /// think of them in.
    ///
    /// **No star** (prd §461). The row's anatomy is `AddressBookRow` with
    /// `onToggleWatch` nil, which that view already treats as "draw no star at
    /// all", and `activity` nil, which drops the recency phrase — a reading,
    /// and this screen draws none. Membership is the thing itself here, so the
    /// verb that changes it is Remove, on the swipe and in the menu, where a
    /// destructive act belongs.
    ///
    /// **Tap renames.** It used to open the address card, which is a room's
    /// worth of readings hanging off the setup screen; renaming is the one thing
    /// somebody comes to a roster row to do.
    @ViewBuilder
    private var rosterSection: some View {
        let watched = watchedEntries
        if !watched.isEmpty {
            Section {
                ForEach(Array(watched.enumerated()), id: \.element.id) { index, entry in
                    rosterRow(entry, row: index)
                }
            } header: {
                sectionHeader(String(localized: "Your wallets"),
                              trailing: String(localized: "\(wallet.addresses.count) of \(WalletStore.watchLimit)"),
                              busy: syncing)
            }
            .listRowSeparator(.hidden)
        }
    }

    /// The watched entries. An address watched before it was ever named has no
    /// book entry of its own to draw, so one is synthesised.
    ///
    /// DEDUPED BY ENTRY (prd §448): two watches can resolve to one book entry —
    /// a name and the address it stands for — and `AddressBook.Entry.id` is the
    /// address's own key, so both would land in the `ForEach` under the same id.
    /// A duplicate id is the SwiftUI reuse trap this codebase already has a
    /// crash report for. `WalletStore.outcome(ofAdding:)` should refuse the
    /// second watch through `scopeMatches` — this is the belt, one line, on a
    /// list of at most five.
    private var watchedEntries: [AddressBook.Entry] {
        var seen: Set<String> = []
        return wallet.addresses.compactMap { addr in
            let entry = book.entry(for: addr.address)
                ?? AddressBook.Entry(address: addr.address,
                                     name: wallet.displayName(for: addr),
                                     addedAt: .now)
            return seen.insert(entry.id).inserted ? entry : nil
        }
    }

    private func rosterRow(_ entry: AddressBook.Entry, row: Int) -> some View {
        let colliding = book.collidingKeys.contains(entry.id)
        return Button {
            DSHaptic.selection()
            beginRename(entry)
        } label: {
            AddressBookRow(entry: entry,
                           // `activity` nil on purpose — see `rosterSection`.
                           activity: nil,
                           watched: true,
                           colliding: colliding)
        }
        .buttonStyle(.plain)
        .settleIn(delay: Double(min(row, 4)) * 0.02)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                remove(entry)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
        .contextMenu {
            Button {
                DSHaptic.tap()
                beginRename(entry)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                DSPasteboard.copySensitive(entry.address)
                DSHaptic.success()
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                remove(entry)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
    }

    private func beginRename(_ entry: AddressBook.Entry) {
        guard let watch = wallet.addresses.first(where: {
            wallet.scopeMatches(entry.address, scope: $0.address)
        }) else { return }
        // An auto-name is the short address standing in for a name nobody gave
        // (`WalletStore.add` files one so a bare paste has something to draw),
        // so the field opens EMPTY rather than pre-filled with `…44b1` — which
        // reads as a name you chose and would have to be deleted first.
        renameDraft = WalletStore.isAutoName(watch.label, for: watch.address) ? "" : watch.label
        renamingID = watch.id
    }

    /// Stop reading an address. Its NAME stays in the book — removing a wallet
    /// from the roster is not forgetting who it is, and the copy on the cap
    /// alert says so.
    private func remove(_ entry: AddressBook.Entry) {
        guard let i = wallet.addresses.firstIndex(where: {
            wallet.scopeMatches(entry.address, scope: $0.address)
        }) else { return }
        let gone = wallet.addresses[i].address
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) {
            wallet.remove(at: IndexSet(integer: i))
        }
        // Its rows leave with it (prd §286).
        FollowPrune.removeWallet(address: gone,
                                 stillWatched: wallet.addresses.map(\.address),
                                 context: modelContext)
    }

    // MARK: - The door to everyone else (prd §461)

    /// One row, one count, one chevron — a DOOR, never a list.
    ///
    /// It exists because the rail's own book slot is gated on the rail showing
    /// at all (`WalletScopeRail.shows` wants more than one wallet watched), so
    /// with nothing watched — the state a new person is in — the book would
    /// otherwise be unreachable. The minimum corpus is the common one here, and
    /// treating it as an edge case is what §436–§438 kept paying for.
    /// Everyone the book holds who is not one of your own five — the same set
    /// `AddressBookScreen.visibleEntries()` lists, spelled the same way, so the
    /// door and the room can never state different numbers.
    private var otherNames: Int {
        book.all.reduce(into: 0) { total, entry in
            if !isWatched(entry) { total += 1 }
        }
    }

    private var bookDoorSection: some View {
        Section {
            // THE COUNT IS WHAT THE ROOM WILL LIST (prd §461, seen on a device).
            // `book.count` is the whole ledger, which includes an entry for
            // every wallet on this very screen — so the door read "6 names"
            // over a room whose own head said "Everyone else · 4". A door that
            // disagrees with the room behind it is §83's fake status in its
            // quietest form: nothing looks broken, the number is just wrong.
            DSSlabDoor(title: String(localized: "Address Book"),
                       detail: otherNames == 1
                           ? String(localized: "1 name")
                           : String(localized: "\(otherNames) names")) {
                DSHaptic.selection()
                route.push(.addressBook)
            }
        }
        .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - The foot

    /// The connection plumbing and the promise. Chains and teardown are the one
    /// thing here nobody revisits, so they sit last.
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
        .listRowInsets(EdgeInsets(top: DS.Space.s3, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Every section's head, spelled once — a word and, sometimes, a fact on
    /// the right. Sentence case, no letter-spacing, no eyebrow (§8).
    private func sectionHeader(_ title: String, trailing: String? = nil,
                               busy: Bool = false) -> some View {
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
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    /// What just happened — the spinner while chains are read, then the outcome
    /// line. A status row only when something needs eyes: an error, the
    /// typo'd-address nudge, or the very first sync. The happy path stays silent
    /// — a green "connected" card read as noise dressed as news.
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

    // MARK: - What the field can tell you before you commit (2026-08-01)

    private var draft: String {
        newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the typed address resolves to, RIGHT NOW: its face, its name, and
    /// the one thing the book already knows about it.
    ///
    /// The face costs NOTHING: `WalletFace`'s identicon is deterministic from
    /// the address, so this is literally the same face the row will wear, drawn
    /// a second early. No balance is shown and none is read — that would be a
    /// metered call fired on every keystroke, and a figure here would be a claim
    /// about a wallet nobody has agreed to watch.
    ///
    /// It stands DOWN for a lookalike or a failed checksum, where the notice
    /// above is telling you to stop and a portrait underneath it is an
    /// invitation.
    @ViewBuilder
    private var addressPreview: some View {
        if !draft.isEmpty, !draftIsUnsafe {
            if let address = previewAddress {
                let known = book.entry(for: address)
                HStack(spacing: DS.Space.s3) {
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
    /// already watching (the verb would do nothing), already named (the name
    /// comes with it), then what it IS. A name that resolved says so with the
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

    /// Matched through the resolution cache, not by raw string (2026-07-25): a
    /// book entry holds the RESOLVED address while a watch may hold the spelling
    /// it was added under ("vitalik.eth").
    private func isWatched(_ entry: AddressBook.Entry) -> Bool {
        wallet.addresses.contains { wallet.scopeMatches(entry.address, scope: $0.address) }
    }

    /// Resolves a typed ENS/SNS name for the preview, debounced.
    ///
    /// Debounced because this fires per keystroke and "vitalik.eth" is nine
    /// prefixes that each look like a name; the pause is what makes it one
    /// request instead of nine. Nothing is watched, nothing is named, nothing is
    /// written — the answer only ever paints a face.
    private func resolvePreview() async {
        let asked = draft
        guard SNS.looksLikeName(asked) || ENS.looksLikeName(asked) else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        // `.sol` first, exactly like `watch()` — `ENS.looksLikeName` takes ANY
        // dotted string and would send a `.sol` name to the ENS resolver, which
        // answers with a null address rather than an error.
        let hit = SNS.looksLikeName(asked)
            ? await SNS.resolve(asked) : await ENS.resolve(asked)
        guard !Task.isCancelled, let hit else { return }
        withAnimation(DS.Motion.standard) {
            resolvedDraft = ResolvedDraft(input: asked, address: hit)
        }
    }

    // MARK: - Reading the chain

    /// Reads the chain and lands new transactions — the plumbing screen's one
    /// job on appear.
    private func sync() {
        guard !syncing else { return }
        syncing = true
        Task {
            let added = await WalletIngest.refresh(context: modelContext)
            let totals = await WalletIngest.topHoldingsByWallet()
            syncing = false
            // The per-wallet totals this read produces are DELIBERATELY not kept
            // (prd §435) — no surface on this screen draws a figure. `totals` is
            // still read because the sentence below needs to tell "nothing has
            // landed yet" apart from "nothing is there", and that question is
            // about whether the chain answered at all.
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

    private func watch() {
        let input = draft
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
            // A legacy/P2SH Bitcoin address is base58-shaped too, the same band
            // Solana pubkeys occupy — check the checksum-verified kind FIRST, or
            // a pasted BTC address flips Solana on by mistake.
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
            // Privacy Pools) are on the moment a wallet is — reflect that in the
            // catalog immediately, not only at the next foreground.
            store.reconcileWalletSeats()
        case .alreadyWatching:
            resultIsError = true
            result = String(localized: "Already watching that address.")
            return
        case .limitReached:
            watchCapHit = true
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

    // MARK: - Connecting a wallet app

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

    /// The automatic way in — a ROW, not a call to action (prd §442, seen on a
    /// device).
    ///
    /// It was a full-width filled `DSSlabButton`, which is right for a screen
    /// whose one job is to connect something and wrong here: §440 put this beside
    /// a field that is the primary way in, and the blue slab outshouted it — the
    /// loudest thing on the screen was the SECOND choice. It is the same weight
    /// as the Connection door at the foot now: a mark, a sentence, a chevron.
    ///
    /// The BUSY state keeps the spinner and the "tap to cancel" wording, because
    /// the wait is real and the person needs the way out (§83 — the proposal runs
    /// to a five-minute expiry, and somebody who chose not to approve must not
    /// find a stuck control).
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
            // No app claimed `wc:` — the URI, to paste into the wallet directly.
            // The handshake is still listening while this shows.
            if let uri = pairingURI {
                manualPairingCard(uri)
            }
        }
    }

    /// The paste-it-yourself route (2026-07-23). A wallet that registers only a
    /// universal link never claims `wc:`, so `canOpenURL` reads false on a device
    /// that HAS a wallet — this is the way through, not an error, and the
    /// approval it leads to is the same one the direct open would get.
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
                // directory with real icons and correct deep links.
                //
                // Mac Catalyst can't link the SDK (see the import in
                // `WalletConnectBridge`), so it keeps the open-then-paste route.
                // That is not a lesser fallback there: the directory is 496
                // PHONE apps opened by deep link, none of which a Mac has, and
                // pasting the URI into a phone's wallet is what a desktop dapp
                // asks for too.
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
                // Which wait actually expired decides the words: if the URI was
                // on screen, the person was pasting, and telling them "approve it
                // in your wallet" describes a tap they never had.
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

    /// Hand what the settled session shared to the picker (2026-08-13, prd §376)
    /// — it does NOT watch anything itself.
    ///
    /// It used to. It looped `wallet.add` over every shared account and reported
    /// trouble only when EVERY add failed, which meant the watch cap ate the
    /// overflow in silence: watching three wallets and connecting one sharing
    /// four landed two, dropped two, and said nothing. That is the
    /// silent-truncation class §307/§309 named in the import rooms, and it was
    /// worse here, because nobody knows how many accounts their wallet chose to
    /// share — there is no number to notice was wrong.
    private func showConnectPicker(_ found: [WalletConnectBridge.ConnectedAccount]) {
        guard !found.isEmpty else {
            resultIsError = true
            result = String(localized: "Your wallet approved but shared no address — paste it instead.")
            return
        }
        resultIsError = false
        sheetRoute = .connectPicker(found)
    }
}
