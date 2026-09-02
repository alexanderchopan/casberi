import SwiftUI
import SwiftData

/// Groups, as a surface of their own (2026-08-22, prd §440) — the card in the
/// manager's strip, the screen behind a tap, and the sheet that files an
/// address.
///
/// **The fourth shape groups have had, and the first with a room.** A chip
/// that put the book in a mode (§266/§267), a folder section in the list
/// (§433), a constellation on the sky (§435), and now a card you open. The
/// three before it all shared one fault: a group had no place to BE. It was a
/// filter, or a heading, or a label floating over a drawing — never a thing
/// you could stand inside, rename from, or drag an address onto.
///
/// Nothing in the model changes. **A group is still a label on entries**
/// (`AddressBook`'s groups section): there is no group store, no ids, no empty
/// groups to manage. Creating one is filing the first address under it,
/// deleting one unlabels its members and keeps every address, and moving one
/// address between two groups is an unlabel plus a label.

// MARK: - The card

/// One group in the manager's strip — a deck of its faces, its name, and what
/// it holds.
///
/// **The faces are the point** (2026-08-01's ruling, kept): a number beside a
/// group name says how many are in it, which nobody wonders; the faces say
/// WHO, which is the only thing a group of addresses is for.
///
/// It is also a DROP TARGET, which is the reason this is a card and not a
/// chip — see `AddressBookGroupStrip`.
struct AddressGroupCard: View {
    let group: String
    let members: [AddressBook.Entry]
    var targeted = false
    /// True for one beat after a drop landed here (prd §441) — the deck TAKES
    /// the new face rather than having it appear. A one-shot from the screen,
    /// not derived from `members`: the book's own observation re-renders this
    /// card the instant the write lands, so by the time anything here could
    /// compare old and new membership the change is already drawn.
    var absorbing = false
    var onOpen: () -> Void

    private static let deckFace: CGFloat = 26

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: -6) {
                    ForEach(members.prefix(4)) { entry in
                        AddressMark(entry: entry, size: Self.deckFace)
                            // The face's own separation, since nothing in this
                            // app draws a line: each mark punches the card
                            // colour out from under the one behind it.
                            .overlay(Circle().strokeBorder(DS.inkGround, lineWidth: 1.5))
                            // A face joining the deck GROWS into it. Scoped to
                            // the mark rather than the deck so the ones already
                            // there hold still and only the newcomer moves.
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                    if members.isEmpty {
                        Circle().fill(DS.fillFaint)
                            .frame(width: Self.deckFace, height: Self.deckFace)
                    }
                }
                // …and the whole stack takes the weight of it, once. A spring
                // on `absorbing` rather than a keyframed pulse: the flag falls
                // back to false on its own, so the return trip is the same
                // spring played backwards and there is no second animation to
                // keep in step with the first.
                .scaleEffect(absorbing ? 1.08 : 1, anchor: .leading)
                .animation(DS.Motion.bubble, value: absorbing)
                .animation(DS.Motion.standard, value: members.map(\.id))
                VStack(alignment: .leading, spacing: 1) {
                    Text(group)
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(targeted ? String(localized: "Drop to file here") : note)
                        .dsText(.label12)
                        .foregroundStyle(targeted ? DS.tint : DS.textTertiary)
                        .fontWeight(targeted ? .semibold : .medium)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)
            .padding(DS.Space.s3)
            // INK, NOT THE GRAY (prd §542) — and the pour is what keeps it
            // a card rather than a hole: the page under it is `#000` on the
            // default theme, so an ink fill alone would erase the deck.
            .background(alignment: .top) {
                LinearGradient(colors: [DS.pourInk, DS.pourInk.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(DS.inkGround)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .shadow(color: DS.raisedShadow, radius: 10, y: 2)
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(DS.tint, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("\(group), \(note)"))
        .accessibilityHint(Text("Opens this group"))
    }

    /// What a group holds — how many addresses, how many of them you watch.
    ///
    /// It used to price the watched part ("2 watched worth $8,900"), which
    /// §435 struck out with every other figure on this screen. A group is a
    /// set of people; how much they are worth is not a fact about the set, and
    /// the feed's crown owns the money reading.
    /// The count, and nothing else (2026-08-22, user ruling: "don't say
    /// n watched — it's just extra text we don't need").
    ///
    /// It read "3 addresses · none watched", which failed twice at once. It
    /// was REDUNDANT — the deck above it already draws the members, and
    /// whether a group's members are watched is a fact about the WATCHING
    /// section at the top of the same screen, not about the group. And it
    /// did not FIT: at 150pt in `label12` the clause clipped to
    /// "3 addresses · none wat…", the same truncation the watched shelf was
    /// deleted for on this pass.
    private var note: String {
        members.count == 1 ? String(localized: "1 address")
                           : String(localized: "\(members.count) addresses")
    }
}

// MARK: - The screen

/// One group, opened (prd §440).
///
/// Reached from its card in the manager's strip and from a search result. It
/// is a plain list of the group's members with the group's own verbs on it —
/// which is the whole reason a group needed a screen: rename and delete act on
/// a GROUP, so they belong somewhere the group is the subject, not buried in a
/// menu on a heading in somebody else's list.
///
/// **Unfile is the swipe here and Remove is not.** Inside a group, the verb
/// nobody wants by accident is deleting the address from the book entirely, so
/// the destructive-looking slot does the reversible thing (take it out of this
/// group; the address and its name stay) and removal keeps its place in the
/// row's context menu, where §212 put it.
struct AddressGroupScreen: View {
    let group: String

    @Bindable private var book = AddressBook.shared
    @Bindable private var wallet = WalletStore.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var activity: [String: AddressActivity.Summary] = [:]
    @State private var sheet: AddressBookSheetRoute?
    @State private var renaming = false
    @State private var confirmDelete = false
    @State private var draft = ""

    /// The group's members, A–Z through the shape layer.
    ///
    /// `entries(inGroup:)` is read ONCE and re-joined through a dictionary.
    /// `AddressBook.all` re-sorts the whole book on every call, so the obvious
    /// `compactMap { book.all.first { … } }` sorts it once per member — six
    /// full sorts of a forty-address book, on every body pass, to answer a
    /// question the array in hand already answers.
    private var members: [AddressBook.Entry] {
        let entries = book.entries(inGroup: group)
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = entries.map { entry in
            AddressBookShape.Row(id: entry.id, name: entry.name, addedAt: entry.addedAt,
                                 watched: isWatched(entry),
                                 activity: activity[entry.id]?.count ?? 0)
        }
        return AddressBookShape.ordered(rows, order: .name).compactMap { byID[$0.id] }
    }

    var body: some View {
        List {
            Section {
                ForEach(members) { entry in
                    Button {
                        DSHaptic.selection()
                        sheet = .entry(entry)
                    } label: {
                        AddressBookRow(entry: entry,
                                       activity: activity[entry.id],
                                       watched: isWatched(entry),
                                       colliding: false,
                                       onToggleWatch: nil)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
                    .swipeActions(edge: .trailing) {
                        Button {
                            DSHaptic.tap()
                            book.removeFromGroup(group, address: entry.address)
                        } label: {
                            Label("Unfile", systemImage: "folder.badge.minus")
                        }
                        .tint(DS.neutralBadge)
                    }
                    .contextMenu {
                        Button {
                            DSPasteboard.copySensitive(entry.address)
                            DSHaptic.success()
                        } label: { Label("Copy address", systemImage: "doc.on.doc") }
                        Button {
                            DSHaptic.tap()
                            sheet = .move(entry)
                        } label: { Label("Move…", systemImage: "folder") }
                        Button(role: .destructive) {
                            book.remove(entry.address)
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            } header: {
                Text(headerNote)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(group)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        draft = group
                        renaming = true
                    } label: { Label("Rename group", systemImage: "pencil") }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: { Label("Delete group", systemImage: "folder.badge.minus") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("Manage \(group)"))
            }
        }
        .onAppear { activity = AddressActivity.summaries(in: modelContext) }
        // A group that stops existing takes its own screen with it — otherwise
        // deleting from in here leaves you standing in a room that no longer
        // has a door.
        .onChange(of: book.groupNames) { _, groups in
            if !groups.contains(where: { AddressBook.sameGroup($0, group) }) { dismiss() }
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .entry(let entry): AddressCard(entry: entry)
            case .move(let entry):  AddressMoveSheet(entry: entry)
            case .newGroup:         NewGroupSheet { _ in }
            // A WalletConnect handshake can only start on the manager, which
            // owns the connect row — so this arm is unreachable here rather
            // than unhandled. Stated as an empty view rather than folded into
            // a `default:`, so adding a real case to the route still breaks
            // this switch and makes somebody decide.
            case .connectPicker:    EmptyView()
            }
        }
        .alert("Rename group", isPresented: $renaming) {
            TextField("Name", text: $draft)
            Button("Save") {
                book.renameGroup(group, to: draft)
                DSHaptic.success()
                // Renaming ONTO an existing group merges, so this screen's own
                // group may no longer exist under this name. `onChange` above
                // catches that and pops.
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete this group?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete group", role: .destructive) {
                book.deleteGroup(group)
                DSHaptic.tap()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deleting “\(group)” keeps every address and every name in your book — only the grouping goes.")
        }
    }

    /// The count, and nothing else — `AddressGroupCard.note`'s ruling, on the
    /// screen the card opens onto (2026-08-22, prd §448). The two are read one
    /// tap apart, so a clause dropped from one and kept on the other reads as
    /// the screen disagreeing with the card you came from; and the stars are
    /// on the rows right below this line, which is where "which of these am I
    /// watching" is answered without anybody counting for you.
    private var headerNote: String {
        members.count == 1 ? String(localized: "1 address")
                           : String(localized: "\(members.count) addresses")
    }

    private func isWatched(_ entry: AddressBook.Entry) -> Bool {
        wallet.addresses.contains { wallet.scopeMatches(entry.address, scope: $0.address) }
    }
}

// MARK: - The move sheet

/// Filing an address, as one deliberate act (prd §440).
///
/// **This replaces a long-press → Groups → tick list**, which is where filing
/// has lived since §266. The menu was correct about the model and wrong about
/// discovery: a person who has never opened a context menu on a row has no way
/// to learn that groups exist, and the tick list gave no room to say what a
/// group already holds.
///
/// **It ticks rather than picks, and that is the model showing through.** An
/// entry's `groups` is an array — an address can be in Family and in Cold at
/// once — so a single-select "move" would have to invent a rule for which
/// membership it destroys. Moving is untick-one-tick-another, which the sheet
/// says out loud in its one gray line.
struct AddressMoveSheet: View {
    let entry: AddressBook.Entry

    @Bindable private var book = AddressBook.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newGroup = false
    @State private var draft = ""
    /// The face in the air, and how far along it is (prd §444).
    @State private var flying: FlightingFace?
    @State private var flightProgress: CGFloat = 0
    /// The group key that took a face one beat ago — see `AddressGroupCard`,
    /// whose deck does the same thing when a row is dropped on it.
    @State private var absorbing: String?

    /// The size a face draws at in a row's deck. Named rather than spelled at
    /// both ends, because it is also where the flight LANDS: a flight that
    /// shrinks to a different number than the deck draws arrives as a face
    /// popping to its real size on touchdown.
    static let deckFace: CGFloat = DS.Face.row
    /// How many faces a deck shows before it starts counting.
    private static let deckLimit = 3

    /// Read back off the book every pass rather than captured, so a tick
    /// reflects the write immediately — `entry` is a value handed in when the
    /// sheet opened and does not update itself.
    private var live: AddressBook.Entry { book.entry(for: entry.address) ?? entry }

    /// Sized to what it actually holds, floored and capped. A tray of five
    /// groups that reserves room for twenty is a sheet of empty space, and one
    /// sized to twenty groups on a book that has three is the same fault
    /// upside down.
    private var trayHeight: CGFloat {
        let rows = CGFloat(book.groupNames.count + 1)   // + "New group…"
        return min(660, max(320, 190 + rows * 52))
    }

    var body: some View {
        DSTray(title: String(localized: "File under"), height: trayHeight, ink: true) {
            VStack(alignment: .leading, spacing: 0) {
                head
                // Counted ONCE for the whole sheet: both of these walk the book,
                // and asking them inside the row loop walks it once per group
                // every body pass.
                let counts = book.groupCounts
                let members = book.groupMembers(limit: Self.deckLimit)
                ForEach(book.groupNames, id: \.self) { name in
                    let key = AddressBook.key(forGroup: name)
                    groupRow(name, count: counts[key] ?? 0, members: members[key] ?? [])
                }

                Button {
                    draft = ""
                    newGroup = true
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "plus")
                            .dsGlyph(17, weight: .regular)
                            .foregroundStyle(DS.tint)
                            .frame(width: 22)
                        Text("New group…")
                            .dsText(.body17).foregroundStyle(DS.tint)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, DS.Space.s3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("An address can sit in more than one group. Untick one and tick another to move it.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s2)
            }
        }
        // THE FILING FLIGHT (prd §444). The star flight's own apparatus, run in
        // the opposite direction: §441 gave starring a face that crosses the
        // gap and left filing — the other thing you do to an address, from a
        // sheet built for nothing else — with a checkmark appearing as its
        // entire feedback. One overlay over the whole tray, so the face can
        // cross from the head into any row.
        .overlayPreferenceValue(AddressFlightAnchors.self) { anchors in
            AddressFlightOverlay(flight: flying, anchors: anchors,
                                 progress: flightProgress,
                                 fromKey: "head:", toKey: "group:",
                                 fromSize: DS.Face.list,
                                 toSize: AddressMoveSheet.deckFace)
        }
        .alert("New group", isPresented: $newGroup) {
            TextField("Name (e.g. Family, Cold)", text: $draft)
            Button("Create") {
                book.addToGroup(draft, address: live.address)
                DSHaptic.success()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Files \(live.name) under a new group.")
        }
    }

    /// Who is being filed. Its face is the one that flies, so it publishes an
    /// anchor under whichever group is currently taking it.
    ///
    /// **The two ends of one flight have to share an id**, and here they cannot
    /// be the same thing: the destination changes per tap while the subject is
    /// a single view. So the flight is keyed on the GROUP and the head answers
    /// to that key — which is also what lets one overlay serve every row.
    private var head: some View {
        HStack(spacing: DS.Space.s3) {
            AddressMark(entry: live, size: DS.Face.list)
                .modifier(OptionalFlightAnchor(key: flying.map { "head:" + $0.id }))
            VStack(alignment: .leading, spacing: 0) {
                Text(live.name)
                    .dsText(.heading22).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(live.short)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, DS.Space.s4)
    }

    private func groupRow(_ name: String, count: Int,
                          members: [AddressBook.Entry]) -> some View {
        let filed = live.isIn(name)
        return Button {
            toggle(name, filed: filed)
        } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "checkmark")
                    .dsGlyph(15, weight: .semibold)
                    .foregroundStyle(DS.tint)
                    .opacity(filed ? 1 : 0)
                    .frame(width: 22)
                Text(name)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                deck(members, name: name)
                Text("\(count)")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            .padding(.vertical, DS.Space.s2 + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(filed ? "Filed here" : "Not filed here"))
    }

    /// WHO IS ALREADY IN THIS GROUP (prd §444).
    ///
    /// The row was a checkmark, a word and a tally — three things, none of
    /// which names a single person, on the screen where the question is "which
    /// of my piles does this belong on". A group is its members, so the row
    /// wears them.
    ///
    /// An EMPTY group still draws a well, and that is not a placeholder for
    /// tidiness: it is where a filed face lands, so the flight always has
    /// somewhere to arrive, and it says "nobody in here yet" in the same
    /// gesture. Without it a brand-new group is the one row the flight cannot
    /// aim at — which is precisely the row you have just made in order to file
    /// something into it.
    private func deck(_ members: [AddressBook.Entry], name: String) -> some View {
        HStack(spacing: -6) {
            ForEach(members) { member in
                AddressMark(entry: member, size: Self.deckFace)
                    // `AddressGroupCard`'s own deck, spelled the same way —
                    // one deck across the app, or the strip on the manager and
                    // the rows in here are two different objects claiming to
                    // be the same group. Nothing in this app draws a line, so
                    // each mark punches the sheet colour out from under the one
                    // behind it.
                    .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 1.5))
                    // A face joining GROWS into the deck; the ones already
                    // there hold still.
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if members.isEmpty {
                // An empty group still draws its well, and not for tidiness:
                // it is where a filed face LANDS, so the flight always has
                // somewhere to arrive. Without it a brand-new group is the one
                // row the flight cannot aim at — which is precisely the row you
                // just made in order to file something into it.
                Circle().fill(DS.fillFaint)
                    .frame(width: Self.deckFace, height: Self.deckFace)
            }
        }
        .flightAnchor("group:" + AddressBook.key(forGroup: name))
        .animation(DS.Motion.standard, value: members.map(\.id))
        // The deck TAKES the hit, exactly as `AddressGroupCard`'s does when a
        // row is dropped onto it — one flag falling back to nil, never a
        // keyframed pulse.
        .scaleEffect(absorbing == AddressBook.key(forGroup: name) ? 1.1 : 1,
                     anchor: .trailing)
        .animation(DS.Motion.bubble, value: absorbing)
        .accessibilityHidden(true)
    }

    /// File or unfile, and send the face if it is a filing.
    ///
    /// Unfiling gets no flight: there is nowhere for a face to go, and running
    /// the arc backwards would say the address came OUT of a group and into
    /// the head, which is not what the head is.
    private func toggle(_ name: String, filed: Bool) {
        if filed {
            DSHaptic.tap()
            book.removeFromGroup(name, address: live.address)
            return
        }
        DSHaptic.success()
        book.addToGroup(name, address: live.address)
        launchFlight(into: AddressBook.key(forGroup: name))
    }

    /// Sends the face across the tray.
    ///
    /// Deferred by one runloop turn ON PURPOSE — `WalletScreen.launchFlight`'s
    /// own lesson: the destination deck does not exist in its final form until
    /// the write above has been observed and the body re-run, so publishing in
    /// the same turn can give the overlay a `from` anchor and no `to`, which
    /// draws nothing at all and reads as the feature being absent. The head's
    /// anchor is published in that same re-run, since its key is derived from
    /// `flying`.
    private func launchFlight(into key: String) {
        guard !reduceMotion else {
            // The deck still takes the hit — the face simply does not travel.
            absorb(key)
            return
        }
        flightProgress = 0
        flying = FlightingFace(id: key, address: live.address, glyph: live.kind.glyph)
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.48, bounce: 0.14)) {
                flightProgress = 1
            } completion: {
                // Cleared only after the animation really ends — clearing on a
                // timer races a slow frame and leaves the face parked mid-air.
                //
                // **And only if this flight is still the one in the air.** The
                // footer under these rows says an address can sit in several
                // groups, so filing two of them in quick succession is the
                // ordinary use of this sheet, not an edge — and an
                // unconditional clear here is a FINISHED flight erasing the
                // one that replaced it, which lands as a face vanishing
                // halfway across the tray. `withAnimation`'s completion fires
                // for an interrupted animation too, so the guard is on the
                // identity of the flight and never on the timing.
                guard flying?.id == key else { return }
                flying = nil
                flightProgress = 0
                absorb(key)
            }
        }
    }

    /// The deck's one-beat weight, and the same "still mine?" guard: a second
    /// filing must not have its absorb cut short by the first one's timer.
    private func absorb(_ key: String) {
        absorbing = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard absorbing == key else { return }
            absorbing = nil
        }
    }
}
