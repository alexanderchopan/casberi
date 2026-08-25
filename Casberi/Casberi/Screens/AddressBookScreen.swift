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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    /// How the list orders itself — A–Z by default (prd §440, unchanged).
    @State private var bookSort: AddressBookShape.Order = .name
    @State private var activity: [String: AddressActivity.Summary] = [:]
    @State private var connections: AddressConnections.Map?
    /// Whether `refreshReadings` has run even once (prd §448) — a nil map means
    /// two different things and only one of them is worth a sentence.
    @State private var hasWalked = false
    @State private var newConnections: Set<String> = []
    @State private var dropTarget: String?
    @State private var absorbing: String?
    @State private var bookSheet: AddressBookSheetRoute?
    @State private var namingAddress: String?
    @State private var namingDraft = ""
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
                inputSection
                if !searching {
                    spineSection
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
            .dsScreenTitle("Address Book")
            .overlay(alignment: .trailing) {
                if bookSort.sections, !searching {
                    AddressIndexBar(letters: AddressBookShape.index(of: sections)) { letter in
                        withAnimation(DS.Motion.standard) {
                            proxy.scrollTo("letter:" + letter, anchor: .top)
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
        // Naming a connected address (prd §295) — the spine card's one action.
        // The name rides every landed transfer with this address, past and
        // future.
        .alert("Name this address",
               isPresented: Binding(get: { namingAddress != nil },
                                    set: { if !$0 { namingAddress = nil } })) {
            TextField("Name (e.g. Mom)", text: $namingDraft)
            Button("Save") { nameConnected() }
            Button("Cancel", role: .cancel) { namingAddress = nil }
        } message: {
            Text("Your name for this address rides every transfer with it. A blank name clears it.")
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
            }
            .padding(.vertical, DS.Space.s2)
            .padding(.horizontal, DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    /// The one line under the preview's name — what the book already knows.
    /// No watch facts here, deliberately: this room cannot watch (§461), so a
    /// "already watching" clause would describe a verb the field doesn't have.
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

    private func chipLabel(_ text: String, tinted: Bool) -> some View {
        Text(text)
            .dsText(.label12).fontWeight(.semibold)
            .foregroundStyle(tinted ? DS.tint : DS.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 7)
            .background(DS.fillFaint, in: Capsule())
    }

    // MARK: - Connected (prd §440, trimmed §448)

    /// The spine, or the honest sentence that stands where it would be. All
    /// three empty states are §448's, unchanged — and all three are facts about
    /// the ROSTER, which is why this room reads `wallet` at all.
    @ViewBuilder
    private var spineSection: some View {
        if let connections, connections.connectedCount > 0 {
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
                .onAppear { AddressConnectionsSeen.markSeen(newConnections) }
            } header: {
                sectionHeader(String(localized: "Connected"))
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        // The empty line moved to the FOOT (prd §462) — see `quietFootSection`.
        // §448's ruling that stating none IS an answer stands; what changed is
        // WHERE it is said: a sentence about a drawing that doesn't exist yet
        // was one of two almost-empty blocks pushing the record halfway down
        // the screen.
    }

    /// What stands where the card would be. Nil means draw nothing at all.
    private var spineEmptyLine: String? {
        if wallet.addresses.count < 2 {
            return wallet.addresses.count == 1
                ? String(localized: "Watch a second address to see how they connect.")
                : nil
        }
        return hasWalked ? String(localized: "No shared addresses yet.") : nil
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
            spineEmptyLine,
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

    /// Everyone else — the person's own watched wallets are LEFT OUT, searching
    /// included (prd §461).
    ///
    /// This reverses §448's one exception ("the Watching section folds away the
    /// moment you type, so a search that also filtered them out would be a
    /// search that cannot find the wallets you watch"). That reasoning was
    /// right while both lived on one screen; with the roster on its own screen,
    /// a watched wallet appearing here would be the duplication §448 deleted the
    /// shelf for, one screen apart instead of one scroll. The search says so
    /// rather than answering nothing — see `emptyBookLine`.
    private func visibleEntries() -> [AddressBook.Entry] {
        book.search(query).filter { !isWatched($0) }
    }

    /// Matched through the resolution cache, not by raw string (2026-07-25): a
    /// book entry holds the RESOLVED address while a watch may hold the
    /// spelling it was added under ("vitalik.eth").
    private func isWatched(_ entry: AddressBook.Entry) -> Bool {
        wallet.addresses.contains { wallet.scopeMatches(entry.address, scope: $0.address) }
    }

    /// The rows, as the shape layer sees them.
    ///
    /// `watched` is FALSE for every row by construction now — the watched
    /// entries never reach this list. The field stays on `AddressBookShape.Row`
    /// rather than being deleted: it is what `.recent` orders by, it is proven
    /// by that harness's own fixtures, and the day a watched entry can appear
    /// here again the ordering is still right. Passing `isWatched` rather than
    /// a literal `false` keeps the two in step with no second rule to maintain.
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
                Text(letter)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .id("letter:" + (section.letter ?? "\u{0}all"))
    }

    /// The head of the list — its count and its sort (prd §212).
    ///
    /// It names what it LISTS (prd §448). "Everyone else" was true when the
    /// watched rows sat in a section above; it is true here for the same
    /// reason, one screen over — this book is everyone who is not one of your
    /// own five.
    private func bookListHeader(count: Int, searching: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(searching
                 ? String(localized: "\(count) matching")
                 : String(localized: "Everyone else · \(count)"))
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
            if let mine = book.search(query).first(where: { isWatched($0) }) {
                return String(localized: "\(mine.name) is one of your own wallets — it's on the Addresses screen.")
            }
            return String(localized: "No name, address or group here matches “\(draft)”.")
        }
        return String(localized: "No names yet. Name an address and every transfer reads by that name.")
    }

    /// One row of the book — the shared anatomy, plus this list's gestures.
    ///
    /// **Tap** opens the card. **Long-press** offers the verbs. **Drag** files
    /// it into a group, and the swipe's `Move…` opens the filing sheet rather
    /// than writing anything, so it stays a door (the design law's "swipe verbs
    /// are reads").
    ///
    /// **No star** (prd §461) — `AddressBookRow.onToggleWatch` is nil, which
    /// that view already treats as "draw no star at all". Watching is not a
    /// property of a person any more; it is membership of the roster on the
    /// Addresses screen.
    private func bookRow(_ entry: AddressBook.Entry, colliding: Bool, row: Int) -> some View {
        let groups = book.groupNames
        return Button {
            DSHaptic.selection()
            bookSheet = .entry(entry)
        } label: {
            AddressBookRow(entry: entry,
                           activity: activity[entry.id],
                           watched: false,
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
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
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

    /// Names a connected address, then brings its landed transfers into line —
    /// the same pair the thing sheet's own naming flow runs.
    private func nameConnected() {
        guard let address = namingAddress else { return }
        namingAddress = nil
        AddressBook.shared.setName(namingDraft, for: address)
        _ = CounterpartyRetitle.applyCurrentName(for: address, in: modelContext)
        refreshReadings()
        DSHaptic.success()
    }

    /// ONE corpus walk, both readings (prd §441) — `AddressActivity` reads
    /// Wallet + Peer + Privacy Pools things and `AddressConnections` reads a
    /// subset of them, so fetching twice was fetching the same rows twice.
    private func refreshReadings() {
        let things = AddressActivity.relevant(in: modelContext)
        activity = AddressActivity.summaries(from: things)
        let map = AddressConnections.map(things: things)
        // WHAT'S NEW SINCE YOU LAST LOOKED (prd §441) — computed before the map
        // is published, so the card draws its dashed arrivals on the same frame
        // it first appears rather than a beat later.
        newConnections = AddressConnectionsSeen.unseen(in: map)
        connections = map
        hasWalked = true
    }
}
