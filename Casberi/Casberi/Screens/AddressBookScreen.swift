import SwiftUI
import SwiftData

/// A resolved ENS/SNS name, tied to the draft that asked for it (prd §433's
/// preview, arriving in the room with §462) — keyed so a slow answer for
/// "vitalik.eth" can never paint itself under a draft that has since become
/// something else.
private struct ResolvedBookDraft: Equatable {
    let input: String
    let address: String
}

/// The address book — everyone you have dealt with, as a room (prd §461).
///
/// **The boundary is OWNERSHIP, and that is what finally separated these two
/// screens** (user, 2026-08-24: "the setup screen only allows five wallets and
/// there is no concept of starring"). `WalletScreen` is the five addresses the
/// app READS — a roster of your own wallets, the way in, the chains, the
/// promise. This is everyone else: names, groups, how they connect, and your
/// history with each. Nothing here changes what the app fetches, which is why
/// there is no star on any row and no watch verb on the field.
///
/// **Why the earlier splits kept failing.** §440 gave this screen four sections
/// and §448 folded the watched shelf into the list — both correct about the
/// duplication and neither able to separate the two jobs, because "watched" was
/// modelled as an ATTRIBUTE of a person: any screen that showed it showed
/// people, and a screen showing people is a second address book. Making it
/// membership of a five-slot roster instead is what removes the crossing rather
/// than relocating it.
///
/// **What moved here, unchanged**: the omnibox (searching half), the spine card
/// and all three of its empty states (§440/§448), the groups strip with its drop
/// targets and its screens (§440), the A–Z list with its scrubber, sort menu and
/// recency sublines, and every gesture a row carried — tap to the card, swipe to
/// Move, drag to file, the context menu. `AddressBookShape` is untouched.
///
/// **What did not come**: the star and `toggleWatch` (deleted, not moved), the
/// watched section, the wallet rename alert, the connect row, the chains door
/// and the read-only promise. Those are the roster's, and they stayed.
struct AddressBookScreen: View {
    @Bindable private var book = AddressBook.shared
    /// Read ONLY to answer two questions this room cannot answer alone: which
    /// entries are the person's own wallets (so they can be left out — they are
    /// the other screen's subject), and how many are watched (the spine's empty
    /// states are facts about the roster, not about the book).
    @Bindable private var wallet = WalletStore.shared
    @Environment(HomeRoute.self) private var route
    @Environment(\.modelContext) private var modelContext
    /// For the sentence and the undo an unwatch owes (prd §511) —
    /// `WalletUnwatch.perform`.
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    /// How the list orders itself — A–Z by default (prd §440, unchanged).
    @State private var bookSort: AddressBookShape.Order = .name
    @State private var activity: [String: AddressActivity.Summary] = [:]
    /// Which population the strip is showing (prd §498). `@State`, so it dies
    /// with the screen — a filter is a lookup, not a preference, and one that
    /// outlived the visit would have somebody open their book to a list that
    /// is missing most of it with no memory of why.
    @State private var bookFilter: AddressBookShape.BookFilter = .all
    /// The off-chain half — contacts and watched social profiles, built for
    /// display and never written (see `AddressBookPeople`). Refreshed on the
    /// same pass as `activity`, so the screen keeps its ONE corpus walk.
    @State private var people: [AddressBook.Entry] = []
    @State private var dropTarget: String?
    @State private var absorbing: String?
    @State private var bookSheet: AddressBookSheetRoute?
    @State private var newGroupForEntry: AddressBook.Entry?
    @State private var groupDraft = ""
    @State private var bulkResult: String?
    @State private var bulkLanded: Set<String> = []
    @State private var filingBulkGroup = false
    /// What the typed draft resolves to, for the preview (prd §462).
    @State private var resolvedDraft: ResolvedBookDraft?
    /// THE SAVE ANSWERS (prd §462) — the whisper under the field, saying what
    /// the name just rewrote. Cleared the way `bulkResult` is: typing again
    /// retires it, because a result line that outlives what produced it starts
    /// describing the wrong thing.
    @State private var saveWhisper: String?
    /// The face the whisper carries — the flight's SOURCE, held apart from the
    /// whisper text so the overlay can aim without parsing a sentence.
    @State private var savedEntryID: String?
    @State private var savedAddress: String?
    /// The row the save should reveal: scrolled to, then lifted once.
    @State private var pendingReveal: String?
    /// THE LETTER THE SCRUB LANDED ON (2026-08-27, prd §502). Held for one beat
    /// after a pick so the heading can answer, then dropped. Nil is the resting
    /// state and the common one — this is not a selection, it is a reply.
    @State private var landedLetter: String?
    /// `connectPromote`'s pair — the grammar the star's retirement orphaned
    /// (§461); the row it lifts now is the one you just saved.
    @State private var promotedEntryID: String?
    @State private var promoteToken = 0
    /// The face in the air (§441's overlay, §444's filing grammar) — from the
    /// whisper's own face down into the filed row.
    @State private var flying: FlightingFace?
    @State private var flightProgress: CGFloat = 0
    /// The connect row's worded outcome (prd §462) — cleared the way the
    /// whisper is: typing again retires it.
    @State private var connectNote: String?

    var body: some View {
        // ONE search per body pass (prd §441) — threaded down rather than
        // re-run by the sections, the id map, the header and the scrubber.
        let searching = !draft.isEmpty
        let entries = visibleEntries()
        let sections = bookSections(entries)
        return ScrollViewReader { proxy in
            List {
                // THE ROSTER (prd §466) — your own five wallets, moved WHOLE
                // off `WalletScreen`. Ahead of the naming field: this is the
                // repeatedly-visited half of the book, and the book's own
                // §461 doc already put "your own wallets" first in its list
                // of what belongs here.
                // THE FILTER STRIP LEADS (prd §498, seen on a device). It was
                // below the roster and the field, which on a real book put it
                // under the fold — a control for the list you cannot see while
                // deciding to use it. It is the first thing now, because it
                // governs everything under it.
                //
                // Deliberately NOT inside the search fold: narrowing a search
                // by population is the combination the two controls exist to
                // make, and a strip that vanished the moment you typed would
                // take that away exactly when a long book needs it most.
                filterSection
                // THE FIELD SITS DIRECTLY UNDER THE STRIP (user ruling,
                // 2026-08-28, with a screenshot: *"the search address or
                // connect wallet should always be at the top below the filter
                // chips … but not at the bottom of the screen"*).
                //
                // It used to follow the roster, on the reasoning quoted below
                // that the roster is the repeatedly-visited half. That holds
                // for a book with one or two wallets and fails for a real one:
                // the roster is as tall as the number of wallets you watch, so
                // at six it pushed the field — the only way to SEARCH a book of
                // 171 people, and the only door to a new address — off the
                // bottom of the screen. A control whose position depends on how
                // much data sits above it is one you have to go looking for.
                //
                // Above the roster rather than below it, because both of the
                // things this row does (find somebody, add somebody) are about
                // the whole book, not about the five wallets.
                inputSection
                // THE ROSTER BLOCK IS GONE (prd §511). The five addresses this
                // app reads are ordinary rows in the list below now, found
                // through the `Watching` chip — see `WalletWatching.swift` for
                // the whole argument. What survives is the chain read's own
                // status, which is not a row and has nowhere to file itself in
                // a lettered list.
                //
                // It is NOT gated on the filter the way the block was: a block
                // of wallets sitting above a list that just promised to hide
                // them read as a broken strip, but "reading onchain activity"
                // is true whichever chip is lit.
                if !searching { WalletWatchSyncSection() }
                if !searching {
                    // The Connected spine LEFT this screen (user ruling,
                    // 2026-08-27, with a screenshot of it: "please remove this
                    // from the address book"). §295's arithmetic survives in
                    // `AddressConnections` and `-connectionsProbe`; the DRAWING
                    // is gone — see prd §497.
                    groupsSection
                }
                bookSection(entries: entries, sections: sections, searching: searching)
                if !searching { quietFootSection(entries: entries) }
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
            .dsScreenTitle("Address book")
            .overlay(alignment: .trailing) {
                if bookSort.sections, !searching {
                    AddressIndexBar(letters: AddressBookShape.index(of: sections)) { letter in
                        withAnimation(DS.Motion.standard) {
                            proxy.scrollTo("letter:" + letter, anchor: .top)
                        }
                        // THE LANDING ANSWERS (prd §502). The bubble tracks the
                        // finger and the list jumps, and until now the place you
                        // arrived said nothing — so a scrub that moved the list
                        // and a scrub that moved it somewhere else looked the
                        // same. The heading you land on replies once.
                        //
                        // Set unanimated and cleared WITH animation: the arrival
                        // should be there the instant the scroll lands (a lit
                        // letter fading in after the list has settled is a
                        // second event), and the fade back is the part that
                        // wants to be gentle.
                        landedLetter = letter
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                            guard landedLetter == letter else { return }
                            withAnimation(DS.Motion.standard) { landedLetter = nil }
                        }
                    }
                }
            }
            // THE SAVE ANSWERS (prd §462): scroll to the row the save filed,
            // then lift it and send the whisper's face down into it. The scroll
            // goes first — a flight to an off-screen anchor draws nothing, and
            // the lift on a row nobody can see marks nothing.
            .onChange(of: pendingReveal) { _, id in
                guard let id else { return }
                withAnimation(DS.Motion.standard) {
                    proxy.scrollTo("row:" + id, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    promotedEntryID = id
                    promoteToken &+= 1
                    launchFlight(to: id)
                    pendingReveal = nil
                }
            }
            // One overlay over the whole List, so the face can cross from the
            // whisper into any letter section (§444's shape).
            .overlayPreferenceValue(AddressFlightAnchors.self) { anchors in
                AddressFlightOverlay(flight: flying, anchors: anchors,
                                     progress: flightProgress,
                                     fromKey: "save:", toKey: "row:",
                                     fromSize: DS.Face.row,
                                     toSize: DS.Face.list)
            }
        }
        .task { await AddressKind.detectPending() }
        // Re-keyed on every draft, so SwiftUI cancels the last lookup before
        // starting the next — which is what makes the debounce inside actually
        // debounce rather than queue.
        .task(id: draft) { await resolvePreview() }
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
        // ONE presentation for the whole room (FeedScreen's lesson, kept from
        // `WalletScreen`): sibling `.sheet` modifiers on one screen start
        // silently self-dismissing each other's first tap.
        .sheet(item: $bookSheet) { route in
            switch route {
            case .entry(let entry):
                AddressCard(entry: entry)
            case .move(let entry):
                AddressMoveSheet(entry: entry)
            case .newGroup:
                NewGroupSheet { _ in }
            case .connectPicker(let accounts):
                // NAME mode (prd §462): the picker saves names, never watches
                // — the §461 boundary, kept on the richer door too.
                WalletConnectPickerSheet(shared: accounts, mode: .name) { added in
                    if added > 0 { refreshReadings() }
                }
            }
        }
        .onChange(of: query) { _, new in
            if !new.isEmpty {
                bulkResult = nil; bulkLanded = []
                // Typing again retires the whisper too — same rule, same reason.
                saveWhisper = nil; savedAddress = nil; savedEntryID = nil
                connectNote = nil
            }
        }
        .onAppear { refreshReadings() }
    }

    // MARK: - The way in

    /// The field, searching-only.
    ///
    /// **The WATCH verb is gone** (prd §461). It was the field's primary action
    /// and it changed what the app reads — the one thing this room may not do.
    /// A single address SAVES a name; a pasted list names all of them, which is
    /// the free tier doing exactly what it is for and is why the cap never
    /// enters this screen's copy.
    @ViewBuilder
    private var inputSection: some View {
        Section {
            let isBulk = book.looksLikeBulk(query)
            VStack(spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Search, or paste an address"),
                            text: $query,
                            actionLabel: isBulk ? String(localized: "Add all")
                                                : String(localized: "Save"),
                            focus: $fieldFocused,
                            isArmed: isBulk || book.looksLikeAddress(draft)
                                     || previewAddress != nil,
                            action: { isBulk ? addAll() : justName() })
                fieldNotice(isBulk: isBulk)
                // What you're about to save, before you save it (§433's
                // preview, in the room since §462): the face is the proof the
                // app understood the paste, and it is literally the same face
                // the row will wear — WalletFace is deterministic from the
                // address, so this costs nothing. Keyed on the ADDRESS so the
                // spring plays when the face arrives, not on every keystroke.
                addressPreview(isBulk: isBulk)
                    .animation(DS.Motion.standard, value: previewAddress)
                // A PASTED LIST FORMS A DECK (prd §502) — the same proof the
                // single preview gives, for the paste that most needs it.
                bulkDeck(isBulk: isBulk)
                saveWhisperLine
                // The richer way in (prd §462): a wallet app shares its
                // accounts and §376's picker goes and finds the Safes they
                // sign on — which is DISCOVERY, and discovery is this room's
                // business. Same row as the roster's, different verb behind
                // it: the picker opens in `.name` mode, so nothing here can
                // change what the app fetches (§461). Steps aside while you
                // type, like the roster's own (§440's reasoning).
                if WalletConnectBridge.isAvailable, draft.isEmpty {
                    ConnectWalletRow(onFound: { bookSheet = .connectPicker($0) },
                                     onNote: { message, _ in
                                         withAnimation(DS.Motion.standard) {
                                             connectNote = message
                                         }
                                     })
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let connectNote {
                    noticeLine("exclamationmark.circle", DS.textSecondary, connectNote)
                }
            }
            .animation(DS.Motion.standard, value: draft.isEmpty)
        }
        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// The one line under the field. Ordered by consequence: a lookalike is a
    /// security fact, a failed checksum is a typo about to become a name, the
    /// bulk hint explains an unfamiliar verb. Silent otherwise.
    @ViewBuilder
    private func fieldNotice(isBulk: Bool) -> some View {
        if let twin = book.lookalikes(of: draft).first {
            noticeLine("exclamationmark.triangle.fill", DS.destructive,
                       String(localized: "Looks like \(twin.name) — but it's a different address. Check every character."))
        } else if AddressSafety.checksum(draft) == .failed {
            noticeLine("exclamationmark.triangle.fill", DS.destructive,
                       String(localized: "That address fails its own checksum — a character is wrong somewhere."))
        } else if isBulk {
            noticeLine("text.append", DS.textSecondary,
                       String(localized: "A list — Add all names every address in it."))
        } else if let bulkResult {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                noticeLine("checkmark.circle.fill", DS.confirm, bulkResult)
                // FILE THE WHOLE PASTE (prd §440) — one tap per group rather
                // than one per address.
                if !bulkLanded.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s2) {
                            ForEach(book.groupNames, id: \.self) { group in
                                Button {
                                    DSHaptic.tap()
                                    fileBulk(under: group)
                                } label: {
                                    chipLabel(group, tinted: false)
                                }
                                .buttonStyle(PressSpring())
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

    // MARK: - The preview and the whisper (prd §462)

    /// The address the preview is about — what was typed when it's already an
    /// address, otherwise whatever the resolver answered FOR THIS DRAFT.
    private var previewAddress: String? {
        if book.looksLikeAddress(draft) { return draft }
        if let resolvedDraft, resolvedDraft.input == draft { return resolvedDraft.address }
        return nil
    }

    /// A destructive notice is on screen — the preview stands down for it: the
    /// notice is telling you to stop, and a portrait underneath it is an
    /// invitation.
    private var draftIsUnsafe: Bool {
        !book.lookalikes(of: draft).isEmpty || AddressSafety.checksum(draft) == .failed
    }

    @ViewBuilder
    private func addressPreview(isBulk: Bool) -> some View {
        if !isBulk, !draft.isEmpty, !draftIsUnsafe, let address = previewAddress {
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
                // THE WATCH VERB, on the preview of what it would watch
                // (prd §498, the one-field ruling). It sits here rather than
                // on the field because the field's action is Save and a
                // control cannot mean two things — and because this is the
                // only place that can say WHICH address is about to be read,
                // which for a paste that resolved from an ENS name is not the
                // text you typed. Absent when the cap is full or the address
                // is already watched: §83, rather than a button that explains
                // itself after the tap.
                if isWatchedAddress(address) {
                    // A FACT, not a control (prd §511). The capsule was simply
                    // absent here, which is right under §83 for a button that
                    // cannot act — but absence answers nothing, and the two
                    // reasons for it are different: this address is already one
                    // of your five, or all five are spoken for. The header
                    // saying "5 of 5" is four hundred points up a scrolled list.
                    previewFactPill(String(localized: "Watching"))
                } else if !wallet.canWatchMore {
                    previewFactPill(String(localized: "Watching \(WalletStore.watchLimit) of \(WalletStore.watchLimit)"))
                } else {
                    Button {
                        watchPreview(address)
                    } label: {
                        Text("Watch")
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Space.s3)
                            .padding(.vertical, 7)
                            .background(DS.tint, in: Capsule())
                    }
                    .buttonStyle(PressSpring())
                    .dsHover()
                }
            }
            .padding(.vertical, DS.Space.s2)
            .padding(.horizontal, DS.Space.s3)
            .dsWell()
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    /// A stated reason where the Watch capsule would have been. Deliberately
    /// not a disabled button: a disabled control invites a tap and then
    /// explains itself, which is the §83 shape this replaces rather than joins.
    private func previewFactPill(_ text: String) -> some View {
        Text(text)
            .dsText(.label12).fontWeight(.semibold)
            .foregroundStyle(DS.textTertiary)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 7)
            .background(DS.fillFaint, in: Capsule())
            .monospacedDigit()
    }

    /// Whether the preview's address is already one of the watched five —
    /// through the resolution cache, not a raw compare, for `isWatched`'s own
    /// stated reason (a watch may stand under "vitalik.eth").
    private func isWatchedAddress(_ address: String) -> Bool {
        wallet.addresses.contains { wallet.scopeMatches(address, scope: $0.address) }
    }

    /// Starts watching the previewed address, and names it if the person
    /// typed a name to reach it.
    ///
    /// The RESOLVED address is what is watched, never the typed text —
    /// `previewAddress` has already done the ENS/SNS lookup, so watching what
    /// it resolved is what makes the row that appears the same identity the
    /// preview just showed (§212's names-are-not-identities rule).
    private func watchPreview(_ address: String) {
        DSHaptic.tap()
        // A typed NAME becomes the label, so a wallet watched as
        // "vitalik.eth" stands under that rather than under its own hex.
        let label = (address == draft) ? "" : draft
        _ = WalletStore.shared.add(address, label: label)
        query = ""
        fieldFocused = false
        refreshReadings()
    }

    /// Starts watching a row that is ALREADY in the book (2026-08-29, prd
    /// §511) — the direction §498's single omnibox could not reach, because
    /// `previewAddress` only fires for an address or a resolvable name, so
    /// typing a contact's NAME surfaced their row and offered nothing.
    ///
    /// A PLACEHOLDER name is not carried across as a roster label: it would pin
    /// `…44b1` as a word somebody chose, and defeat the fold on the way back
    /// out.
    private func watchEntry(_ entry: AddressBook.Entry) {
        let placeholder = WalletStore.isAutoName(entry.name, for: entry.address)
        if WalletStore.shared.add(entry.address, label: placeholder ? "" : entry.name) {
            DSHaptic.success()
            refreshReadings()
        }
    }

    /// THE DECK A PASTED LIST MAKES (2026-08-27, prd §502).
    ///
    /// A single paste has shown its face since §462 — "the proof the app
    /// understood the paste" — and a paste of forty showed a sentence. So the
    /// one place the free tier does its most impressive work was also the one
    /// place it said the least about what it had read.
    ///
    /// **It is a READING, not a landing.** Nothing is written and nothing is
    /// resolved: `bulkAddresses` shares `addBulk`'s tokenizer, so the deck holds
    /// exactly the addresses the write will land, in the order it will land
    /// them — but a `.eth` in the list is carried as typed, so a face here is a
    /// face of the TEXT. The count says "read" for that reason, and the whisper
    /// under it still says "named" once the write has happened.
    ///
    /// **Five faces, then a count.** A fan of forty is a smear, and the deck's
    /// job is to say "a list, understood", which five says as well as forty.
    /// The tail is COUNTED rather than dropped (§300's rule for a folded tail).
    ///
    /// The removal transition is the deal: `addAll` clears the field, so the
    /// deck leaves downward toward the rows arriving under it. That is one
    /// transition rather than a second animation to keep in step with the
    /// list's own.
    @ViewBuilder
    private func bulkDeck(isBulk: Bool) -> some View {
        let addresses = isBulk && !draftIsUnsafe ? book.bulkAddresses(draft) : []
        if addresses.count >= 2 {
            HStack(spacing: DS.Space.s3) {
                HStack(spacing: -12) {
                    ForEach(Array(addresses.prefix(AddressDeck.shown).enumerated()),
                            id: \.offset) { index, address in
                        WalletFace(address: address, size: DS.Face.list, circular: true)
                            // Each face punches the page out from under the one
                            // behind it — the group deck's own separation, since
                            // nothing in this app draws a line.
                            .overlay(Circle().strokeBorder(DS.page, lineWidth: 2))
                            .rotationEffect(.degrees(AddressDeck.tilt(index)))
                            .staggerIn(index: index, step: 0.05)
                    }
                }
                Text(AddressDeck.line(count: addresses.count))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s2)
            .padding(.horizontal, DS.Space.s3)
            .dsWell()
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                removal: .opacity.combined(with: .move(edge: .bottom))))
            .animation(DS.Motion.standard, value: addresses.count)
        }
    }

    /// The one line under the preview's name — what the book already knows.
    ///
    /// No watch facts in THIS line: since §498 the room does watch, and since
    /// §511 it states the two reasons it can't — but both of those belong on
    /// the trailing pill, where the verb they are standing in for would be.
    /// Saying it here as well is §366's read-it-twice.
    private func previewFact(address: String, known: AddressBook.Entry?) -> String {
        var parts: [String] = []
        if address != draft { parts.append(WalletStore.shortAddress(address)) }
        if known != nil { parts.append(String(localized: "already in your book")) }
        if let label = known?.kind.label { parts.append(label) }
        else if let script = BitcoinAddress.scriptKind(address) { parts.append(script) }
        return parts.isEmpty
            ? String(localized: "New address")
            : parts.joined(separator: " · ")
    }

    /// Resolves a typed ENS/SNS name for the preview, debounced — nine
    /// prefixes of "vitalik.eth" each look like a name, and the pause is what
    /// makes them one request. Nothing is saved, nothing is written.
    private func resolvePreview() async {
        let asked = draft
        guard SNS.looksLikeName(asked) || ENS.looksLikeName(asked) else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        // `.sol` first — `ENS.looksLikeName` takes ANY dotted string and would
        // send a `.sol` name to the ENS resolver, which answers with a null
        // address rather than an error.
        let hit = SNS.looksLikeName(asked)
            ? await SNS.resolve(asked) : await ENS.resolve(asked)
        guard !Task.isCancelled, let hit else { return }
        withAnimation(DS.Motion.standard) {
            resolvedDraft = ResolvedBookDraft(input: asked, address: hit)
        }
    }

    /// THE WHISPER (prd §462) — what the save just did, said once. Its face is
    /// the flight's source: the same identity travels from "saved" down into
    /// the row it filed under, so the two ends of the arc are one object.
    @ViewBuilder
    private var saveWhisperLine: some View {
        if let saveWhisper, let savedAddress, let savedEntryID {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                WalletFace(address: savedAddress, size: DS.Face.row, circular: true)
                    .flightAnchor("save:" + savedEntryID)
                Text(saveWhisper)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s1)
            .transition(.opacity)
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

    // MARK: - The filter strip (prd §498)

    /// One quiet capsule row — All, then whichever populations the book
    /// actually holds. Single select; tapping the active chip returns to All,
    /// which is the chip strip's own re-tap grammar everywhere else in the app.
    ///
    /// **No cards, no segmented control** (user ruling, 2026-08-27: *"not like
    /// apple b/c theirs is kinda wonky, and no cards"*). It reuses the same
    /// capsule the groups strip below already draws, so the screen has ONE
    /// chip shape rather than a second one that merely looks similar.
    ///
    /// It draws only when there is a real choice to make: a book of nothing
    /// but wallets gets All and Wallets, which is one chip pretending to be a
    /// control, so the strip stands down below two narrowing options.
    @ViewBuilder
    private var filterSection: some View {
        let filters = AddressBookShape.availableFilters(kinds: presentKinds,
                                                        watching: watchedCount)
        if filters.filter(\.narrows).count >= 2 {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(filters, id: \.self) { filter in
                            Button {
                                DSHaptic.selection()
                                withAnimation(DS.Motion.standard) {
                                    // A re-tap clears, so the strip never
                                    // needs a separate way back to All.
                                    bookFilter = (bookFilter == filter) ? .all : filter
                                }
                            } label: {
                                // THE WATCHING CHIP CARRIES THE CAP (prd §511)
                                // — "Watching 3/5". Deleting the pinned block
                                // deleted the only place the app ever said how
                                // many of the five are spent, and a limit
                                // nobody is told about is one you discover by
                                // being refused.
                                chipLabel(filter == .watching
                                          ? AddressBookShape.watchingLabel(watchedCount,
                                                                           limit: WalletStore.watchLimit)
                                          : filter.label,
                                          tinted: bookFilter == filter,
                                          selected: bookFilter == filter)
                            }
                            .buttonStyle(.plain)
                            .dsHover()
                            .accessibilityAddTraits(bookFilter == filter ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s1)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func chipLabel(_ text: String, tinted: Bool) -> some View {
        chipLabel(text, tinted: tinted, selected: false)
    }

    /// `selected` fills the capsule with the tint rather than merely tinting
    /// the word — selection on this strip has to survive being read at a
    /// glance beside four unselected neighbours, and tinted 12pt type alone
    /// does not (§204's own lesson about a bare word in a colour ramp).
    /// White on the tint in both themes, for the reason the source strip's
    /// active word chip already gives: the accent is a dark blue either way.
    private func chipLabel(_ text: String, tinted: Bool, selected: Bool) -> some View {
        Text(text)
            .dsText(.label12).fontWeight(.semibold)
            .foregroundStyle(selected ? .white : (tinted ? DS.tint : DS.textSecondary))
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 7)
            .background(selected ? AnyShapeStyle(DS.tint) : AnyShapeStyle(DS.fillFaint),
                        in: Capsule())
    }

    // MARK: - Groups (prd §440)

    /// The strip — one card per group, plus the door that makes one.
    ///
    /// **Only once a group EXISTS (prd §462).** It rendered from
    /// `groupsOfferFloor` up, which on a book with no groups was a header over
    /// one lonely dashed card — §440's own words for that shape are "a control
    /// for a problem nobody has yet". The doors that CREATE the first group
    /// survive it everywhere they already were (the sort menu's "New group…",
    /// every row's long-press, the card's chips), and the quiet foot names the
    /// nearest one. §267's discoverability ruling is why the foot says it out
    /// loud rather than trusting the menu alone.
    @ViewBuilder
    private var groupsSection: some View {
        let groups = book.groupNames
        if !groups.isEmpty {
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

    /// A book smaller than this has nothing to organize — the quiet foot's
    /// filing hint waits for it (the strip itself now waits for a real group,
    /// prd §462).
    private static let groupsOfferFloor = 6

    /// THE QUIET FOOT (prd §462) — the zeroes, said once, after the record.
    ///
    /// Two almost-empty blocks used to lead this screen: the spine's honest
    /// "No shared addresses yet." floating alone, and a Groups header over one
    /// dashed New-group card. Neither has content, and together they pushed
    /// the record halfway down. Both facts survive — §448's "stating none IS
    /// an answer" and §267's "creation must be findable" — as ONE tertiary
    /// sentence below the book, where an empty state reads as standing room
    /// rather than as the screen's subject.
    @ViewBuilder
    private func quietFootSection(entries: [AddressBook.Entry]) -> some View {
        let parts: [String] = [
            book.groupNames.isEmpty && entries.count >= Self.groupsOfferFloor
                ? String(localized: "Groups arrive with your first filing — long-press any row.")
                : nil,
        ].compactMap { $0 }
        if !parts.isEmpty {
            Section {
                Text(parts.joined(separator: " "))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func groupCard(_ group: String) -> some View {
        let members = book.entries(inGroup: group)
        let key = AddressBook.key(forGroup: group)
        return AddressGroupCard(group: group,
                                members: members,
                                targeted: dropTarget == key,
                                absorbing: absorbing == key) {
            DSHaptic.selection()
            route.push(.addressGroup(group))
        }
        // **DROP TO FILE** (prd §440) — the payload is the address string, so a
        // list that re-sorts mid-drag can never file the wrong row.
        .dropDestination(for: String.self) { items, _ in
            guard let address = items.first else { return false }
            book.addToGroup(group, address: address)
            DSHaptic.success()
            dropTarget = nil
            absorbing = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                if absorbing == key { absorbing = nil }
            }
            return true
        } isTargeted: { over in
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

    /// Every section's head, spelled once (§8 — sentence case, no eyebrow).
    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
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
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    // MARK: - The record

    private var draft: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// EVERYONE, watched included (prd §511) — reversing §461's exclusion, and
    /// restoring §448's original reading of the same question.
    ///
    /// §461 left the watched five out because they had a block of their own
    /// above, so a row appearing in both was the duplication §448 had just
    /// deleted a shelf for. With the block gone there is no second place for
    /// them to be, and excluding them here would mean the book cannot find the
    /// addresses you care most about — which is exactly what §448 said before
    /// the split, in its own words: "a search that also filtered them out would
    /// be a search that cannot find the wallets you watch."
    /// The rows the list draws — the ledger's own entries plus the off-chain
    /// half, searched, then narrowed by the chip (prd §498).
    ///
    /// The chip narrows LAST, after search, which is what makes the two
    /// compose: typing "uma" with Social selected asks "which of my social
    /// people is Uma", and either control alone still answers what it always
    /// did. `settledFilter` runs here rather than at the tap so a filter whose
    /// population disappeared underneath it cannot strand the screen on an
    /// empty list.
    private func visibleEntries() -> [AddressBook.Entry] {
        let owned = book.search(query)
        let q = draft.lowercased()
        // Contacts and social rows carry only a name and a provenance — no
        // address, no groups, no note — so they are matched on what they have
        // rather than run through `book.search`, which asks about fields these
        // structurally cannot fill.
        let others = q.isEmpty ? people : people.filter {
            $0.name.lowercased().contains(q)
                || ($0.provenance?.lowercased().contains(q) ?? false)
        }
        // ONE PERSON, EVERY IDENTITY (prd §498) — a named address and the
        // social accounts of the same name fold into one row carrying every
        // block. The book entry is always the base, so nothing persisted can
        // be shadowed by a name match.
        let merged = AddressBookPeople.fold(book: owned, people: others)
        let settled = settledFilter
        guard settled.narrows else { return merged }
        // `watched` travels beside `kind`, never inside it — §461's ruling in
        // the type system (see `BookFilter.matches`).
        return merged.filter { settled.matches(kind: $0.kind.rawValue, watched: isWatched($0)) }
    }

    /// How many of the five are spent — the Watching chip's own population, and
    /// the number its label carries. Computed off `WalletStore` rather than off
    /// the book, because the roster is the authority on its own membership and a
    /// watch can stand under a spelling the book re-keyed (2026-07-25).
    private var watchedCount: Int { wallet.addresses.count }

    /// The filter actually in force. Spelled once (prd §511): three readers had
    /// their own `settledFilter` call, and a fourth arriving with a different
    /// argument list is how a chip starts filtering a list nobody else agrees
    /// is filtered.
    private var settledFilter: AddressBookShape.BookFilter {
        AddressBookShape.settledFilter(bookFilter, kinds: presentKinds,
                                       watching: watchedCount)
    }

    /// Every kind the book can currently offer a chip for — the LEDGER's own
    /// census (unsorted, see `AddressBook.kindsPresent`) plus the off-chain
    /// rows. Deliberately computed before search, so typing does not make
    /// chips appear and vanish under the thumb.
    private var presentKinds: [String] {
        Array(book.kindsPresent) + people.map(\.kind.rawValue)
    }

    /// Matched through the resolution cache, not by raw string (2026-07-25): a
    /// book entry holds the RESOLVED address while a watch may hold the
    /// spelling it was added under ("vitalik.eth").
    private func isWatched(_ entry: AddressBook.Entry) -> Bool {
        wallet.addresses.contains { wallet.scopeMatches(entry.address, scope: $0.address) }
    }

    /// The rows, as the shape layer sees them.
    ///
    /// `watched` is REAL again (prd §511) — the watched entries are rows of
    /// this list now, so `.recent`'s hoist of them is live rather than dormant,
    /// and the Watching chip filters on the same answer. §461 left this reading
    /// `isWatched` rather than a literal `false` precisely so that the day a
    /// watched entry could appear here again the ordering would already be
    /// right; this is that day, and the line did not have to change.
    private func shapeRows(_ entries: [AddressBook.Entry]) -> [AddressBookShape.Row] {
        entries.map {
            AddressBookShape.Row(id: $0.id, name: $0.name, addedAt: $0.addedAt,
                                 watched: isWatched($0),
                                 activity: activity[$0.id]?.count ?? 0)
        }
    }

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

    @ViewBuilder
    private func bookSection(entries: [AddressBook.Entry],
                             sections: [AddressBookShape.Section],
                             searching: Bool) -> some View {
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let colliding = book.collidingKeys
        // GROUP RESULTS lead the matches (prd §440) — typing "fam" should open
        // Family, not merely list the four addresses in it.
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
            if isFirst { bookListHeader(count: count, searching: searching) }
            if let letter = section.letter {
                // The reply is the TINT and a hair of travel toward the strip
                // that sent you here — never a size change, which would move
                // the rows under it on a list that has just finished moving.
                Text(letter)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(landedLetter == letter ? DS.tint : DS.textSecondary)
                    .offset(x: landedLetter == letter ? 3 : 0)
            }
        }
        .id("letter:" + (section.letter ?? "\u{0}all"))
    }

    /// The head of the list — its count and its sort (prd §212).
    ///
    /// It names what it LISTS (prd §448), and since §511 what it lists is
    /// EVERYONE: "Everyone else" was true only while the watched five sat in a
    /// block above, and that block is gone.
    ///
    /// Under a narrowing chip it says the count and NOT the population's name,
    /// because the lit chip two rows up is already the name — saying it twice
    /// is §366's read-it-twice, and the Watching chip's own label carries a cap
    /// this head has no business repeating.
    private func bookListHeader(count: Int, searching: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(searching
                 ? String(localized: "\(count) matching")
                 : settledFilter.narrows
                   ? String(localized: "\(count) shown")
                   : String(localized: "Everyone · \(count)"))
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

    /// The empty line, and its third case is the cost of leaving the roster out
    /// (prd §461): a search for "Main" finds nothing here, and answering
    /// "nothing matches" about a wallet the person plainly has is the §83 lie.
    /// It names the screen that does hold it instead.
    private var emptyBookLine: String {
        if !draft.isEmpty {
            // §461's "it's on the Addresses screen" line is DELETED, not
            // reworded (prd §511): the watched five are rows of this list now,
            // so a search that matches one finds it, and a sentence sending
            // somebody to another screen for a row that is right here is worse
            // than no sentence.
            return String(localized: "No name, address or group here matches “\(draft)”.")
        }
        return String(localized: "No names yet. Name an address and every transfer reads by that name.")
    }

    /// One row of the book — the shared anatomy, plus this list's gestures.
    ///
    /// **Tap** opens the card. **Long-press** offers the verbs. **Drag** files
    /// it into a group, and the swipe's `Move…` opens the filing sheet rather
    /// than writing anything, so that verb stays a door (the design law's
    /// "swipe verbs are reads").
    ///
    /// The swipe's OTHER verb is destructive and there is exactly one of it per
    /// row — `Stop watching`, `Unfollow`, or `Remove from book`, chosen by
    /// which population the row belongs to (2026-08-29). §212 is kept by
    /// `allowsFullSwipe: false`: the gesture reveals the button, it never
    /// commits it.
    ///
    /// **Still no star** (prd §461, unchanged by §511) —
    /// `AddressBookRow.onToggleWatch` is nil, which that view treats as "draw
    /// no star at all". The watched five are rows of this list now, and a row
    /// says it is watched with an INERT mark: a star is a control, and a
    /// control on every row is precisely what §461 deleted. The verb lives in
    /// the swipe, the menu and the card.
    private func bookRow(_ entry: AddressBook.Entry, colliding: Bool, row: Int) -> some View {
        let groups = book.groupNames
        let watched = isWatched(entry)
        // The social half's own verb (prd §511) — see `SocialUnfollow`. Empty
        // for every persisted row and for Twitch, which keeps no local roster.
        let following = AddressBookPeople.unfollowable(entry)
        return Button {
            DSHaptic.selection()
            bookSheet = .entry(entry)
        } label: {
            AddressBookRow(entry: entry,
                           activity: activity[entry.id],
                           watched: watched,
                           colliding: colliding)
        }
        .buttonStyle(.plain)
        // The save's landing (prd §462): a STABLE id (deliberately not the
        // §444-banned `.id(name)` churn — this one never changes for a row),
        // the flight's destination anchor, and the lift that marks the row the
        // save just filed. `connectPromote` reads `isTarget` at fire time, so
        // saving one row never lifts another.
        .id("row:" + entry.id)
        // The anchor is a face-sized rect over the row's leading edge — where
        // `AddressBookRow` draws its mark — so the flight lands ON the face
        // rather than at the row's geometric middle. A clear overlay rather
        // than a modifier inside the row: the row is the shared anatomy and
        // only this list flies into it.
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: DS.Face.list, height: DS.Face.list)
                .flightAnchor("row:" + entry.id)
        }
        .connectPromote(isTarget: entry.id == promotedEntryID, token: promoteToken)
        .settleIn(delay: Double(min(row, 8)) * 0.02)
        // THE FILTER NARROWS, IT DOES NOT REPLACE (2026-08-27, prd §502). The
        // strip is the one control that reshapes the whole list, and a chip
        // tap swapped one set of rows for another — which reads as being handed
        // a different book rather than as this one being narrowed. Rows leave
        // toward the leading edge and come back from it, so the population that
        // went is visibly the population that returns.
        //
        // Plain opacity while SEARCHING, deliberately: a search rewrites the
        // list on every keystroke, and a lateral slide per character is the
        // same motion spent on something that is not a decision.
        .transition(draft.isEmpty
                    ? .opacity.combined(with: .move(edge: .leading))
                    : .opacity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
        .draggable(entry.address) {
            AddressMark(entry: entry, size: DS.Face.list)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // STOPPING A WATCH IS A WRITE, so it never gets a full swipe (§212)
            // — it prunes this wallet's landed rows and, in the folded case,
            // the book entry with them.
            if watched {
                Button(role: .destructive) {
                    WalletUnwatch.perform(entry, context: modelContext, chrome: chrome)
                } label: {
                    Label("Stop watching", systemImage: "eye.slash")
                }
            } else if !following.isEmpty {
                Button(role: .destructive) {
                    SocialUnfollow.perform(entry, context: modelContext, chrome: chrome)
                } label: {
                    Label("Unfollow", systemImage: "person.badge.minus")
                }
            } else {
                // ONE DESTRUCTIVE VERB PER ROW, and this is the third of them
                // (2026-08-29, user: "why do the address book items have a
                // swipe to move but not to remove"). A plain named row — not
                // watched, not followed — had a swipe carrying `Move…` alone, so
                // the gesture read as a move-only affordance while the two
                // populations either side of it both carried a destructive verb
                // right there. The name's own verb now sits where they sit.
                //
                // THE THREE ARMS ARE MUTUALLY EXCLUSIVE on purpose, which is
                // §511's "one consequence, one word" as a shape: a swipe
                // offering two destructive buttons asks the reader to pick
                // between two outcomes inside a gesture already committed to
                // one, which is the two-Removes confusion that ruling deleted.
                // `following` is empty for every persisted row, so this arm is
                // exactly the set `book.remove` can act on — an ephemeral
                // social row is not in the book, and offering to remove it is
                // the §83 dead control.
                //
                // NOT offered for a watched address, the same gate the menu
                // uses and for the menu's own reason (§511): `WalletStore.add`
                // guarantees every watched wallet is also a book entry, so
                // removing the name under a live watch leaves a wallet the app
                // reads and cannot name, and the next sync files it again under
                // a placeholder — a verb that undoes itself. Stop watching
                // first; the fold takes the placeholder with it.
                //
                // Still no full swipe (§212): the gesture REVEALS the button,
                // it never commits it.
                Button(role: .destructive) {
                    book.remove(entry.address)
                } label: {
                    Label("Remove from book", systemImage: "trash")
                }
            }
            Button {
                DSHaptic.tap()
                bookSheet = .move(entry)
            } label: {
                Label("Move…", systemImage: "folder")
            }
            .tint(DS.tint)
        }
        .contextMenu {
            // ONE CONSEQUENCE, ONE WORD (prd §511). This menu's destructive row
            // says "Remove from book" and means the name; the watch verb says
            // "Stop watching" and means the reading. Both spelled the same
            // everywhere — the bare "Remove" for two different outcomes is what
            // made unwatching read as a delete that had failed.
            if watched {
                Button(role: .destructive) {
                    WalletUnwatch.perform(entry, context: modelContext, chrome: chrome)
                } label: {
                    Label("Stop watching", systemImage: "eye.slash")
                }
            } else if wallet.canWatchMore, !entry.kind.isMonogram {
                // Absent, never disabled, when the roster is full or the row is
                // a contact with no chain to read (§83). The Watching chip's
                // own label says how many of the five are spent.
                Button {
                    watchEntry(entry)
                } label: { Label("Watch", systemImage: "eye") }
            }
            // A SOCIAL ROW'S ONE VERB (prd §511). Until this landed the book
            // listed everyone a starter pack had just followed and offered
            // nothing to do about any of them, because every write door is shut
            // for an ephemeral row by construction.
            if !following.isEmpty {
                Button(role: .destructive) {
                    SocialUnfollow.perform(entry, context: modelContext, chrome: chrome)
                } label: { Label("Unfollow", systemImage: "person.badge.minus") }
            }
            Button {
                DSPasteboard.copySensitive(entry.address)
                DSHaptic.success()
            } label: {
                Label("Copy address", systemImage: "doc.on.doc")
            }
            Menu {
                GroupMenuItems(entry: entry, groups: groups) {
                    groupDraft = ""
                    newGroupForEntry = entry
                }
            } label: {
                Label("Groups", systemImage: "folder")
            }
            // NOT OFFERED FOR A WATCHED ADDRESS (prd §511): `WalletStore.add`
            // guarantees every watched wallet is also a book entry, so removing
            // the entry under a live watch leaves a wallet the app reads and
            // cannot name — and the next sync files it again under a
            // placeholder, which is a verb that undoes itself. Stop watching
            // first; the fold takes the placeholder with it.
            //
            // "Remove from book", NEVER the bare "Remove" — the watch verb
            // above says "Stop watching" and means something else, and the
            // card's own menu has said this since §446. One consequence, one
            // spelling, everywhere.
            if !watched {
                Button(role: .destructive) {
                    book.remove(entry.address)
                } label: {
                    Label("Remove from book", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Writes

    /// Names the typed address. Watching is not offered here at all (prd §461).
    ///
    /// A typed ENS/SNS name keeps its own words as the name and RESOLVES in the
    /// background (2026-07-25), so the row stands immediately either way and the
    /// book re-keys it onto the address it stands for when the answer lands.
    private func justName() {
        DSHaptic.tap()
        let addr = draft
        // The preview already resolved a typed name? Save the ADDRESS it
        // stands for, so the row's face and the flight's are the same identity
        // from the first frame.
        let target = previewAddress ?? addr
        query = ""
        fieldFocused = false
        resolvedDraft = nil
        guard !addr.isEmpty else { return }
        let isName = SNS.looksLikeName(addr) || ENS.looksLikeName(addr)
        let name = isName ? addr : WalletStore.shortAddress(target)
        book.setName(name, for: target)
        // THE SAVE ANSWERS (prd §462). `applyCurrentName` has always returned
        // how many landed transfers it rewrote, and every caller discarded it —
        // the one fact that shows what naming IS, thrown away at the moment it
        // happens. Zero rewrites says just "Saved." — a count of nothing is
        // not stated (§83).
        let rewrote = CounterpartyRetitle.applyCurrentName(for: target, in: modelContext)
        DSHaptic.success()
        if let entry = book.entry(for: target) {
            withAnimation(DS.Motion.standard) {
                saveWhisper = rewrote > 0
                    ? String(localized: "Saved — \(rewrote) transfers now read \(entry.name).")
                    : String(localized: "Saved.")
                savedAddress = entry.address
                savedEntryID = entry.id
            }
            // One turn later, so the re-sorted list has been observed and the
            // new row exists to be scrolled to (§441's deferred-launch lesson).
            DispatchQueue.main.async { pendingReveal = entry.id }
        }
        guard isName, previewAddress == nil else { return }
        Task {
            // `.sol` first: `ENS.looksLikeName` takes ANY dotted string and
            // would send a `.sol` name to the ENS resolver, which answers with
            // a null address rather than an error.
            let resolved = SNS.looksLikeName(addr)
                ? await SNS.resolve(addr) : await ENS.resolve(addr)
            guard let resolved else { return }
            await MainActor.run { wallet.noteResolution(addr, resolved: resolved) }
        }
    }

    /// The whisper's face, down into the filed row (prd §462) — §444's filing
    /// grammar, run from the field. Deferred one turn by the caller; a missing
    /// anchor draws nothing, silently, which is the safe failure here (the
    /// scroll and the lift have already answered).
    private func launchFlight(to id: String) {
        guard let savedAddress, UIAccessibility.isReduceMotionEnabled == false else { return }
        flightProgress = 0
        flying = FlightingFace(id: id, address: savedAddress,
                               glyph: book.entry(for: savedAddress)?.kind.glyph)
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.48, bounce: 0.14)) {
                flightProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                guard flying?.id == id else { return }
                flying = nil
                flightProgress = 0
            }
        }
    }

    /// Names every address in a pasted list.
    private func addAll() {
        DSHaptic.tap()
        let before = Set(book.all.map(\.id))
        let landed = book.addBulk(query)
        query = ""
        fieldFocused = false
        guard landed > 0 else { return }
        DSHaptic.success()
        bulkResult = String(localized: "\(landed) named.")
        // The ids the book GAINED, taken as the difference across the write —
        // so a re-paste of addresses already in the book offers nothing to file,
        // which is correct: nothing new arrived.
        bulkLanded = Set(book.all.map(\.id)).subtracting(before)
        // Every landed transfer brought in line with the whole book at once —
        // `applyCurrentName` per address would re-fetch the corpus per line.
        CounterpartyRetitle.applyBook(in: modelContext)
    }

    /// Files everything the last paste landed under one group, in ONE write.
    private func fileBulk(under group: String) {
        let addresses = book.all.filter { bulkLanded.contains($0.id) }.map(\.address)
        guard !addresses.isEmpty,
              book.addToGroup(group, addresses: addresses) != nil else { return }
        DSHaptic.success()
        bulkResult = String(localized: "\(addresses.count) filed under \(group).")
        bulkLanded = []
    }

    /// ONE corpus walk (prd §441; the Connected spine that shared this walk
    /// left the screen 2026-08-27, prd §497, so `AddressActivity` is its only
    /// reader now).
    private func refreshReadings() {
        let things = AddressActivity.relevant(in: modelContext)
        activity = AddressActivity.summaries(from: things)
        // The off-chain half (prd §498). Its own scoped fetch rather than a
        // filter over `things`: that walk is Wallet/Peer/Privacy-Pools rows by
        // construction and holds no contact, so filtering it would answer
        // empty forever — the dead-registry shape §313 paid for twice.
        people = AddressBookPeople.rows(in: modelContext,
                                        excluding: Set(book.all.map(\.id)))
    }
}
