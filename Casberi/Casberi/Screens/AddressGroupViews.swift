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
    /// How many of `members` are watched — passed in rather than computed,
    /// since only the screen knows the watch list and this is drawn once per
    /// group per body pass.
    let watched: Int
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
                            .overlay(Circle().strokeBorder(DS.surfaceRaised, lineWidth: 1.5))
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
            .background(DS.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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
    private var note: String {
        let count = members.count
        let head = count == 1 ? String(localized: "1 address")
                              : String(localized: "\(count) addresses")
        return watched == 0
            ? head + " · " + String(localized: "none watched")
            : head + " · " + String(localized: "\(watched) watched")
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
                        } label: { Label("Copy Address", systemImage: "doc.on.doc") }
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

    private var headerNote: String {
        let count = members.count
        let watched = members.filter(isWatched).count
        let head = count == 1 ? String(localized: "1 address")
                              : String(localized: "\(count) addresses")
        return watched == 0 ? head
                            : head + " · " + String(localized: "\(watched) watched")
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
    @State private var newGroup = false
    @State private var draft = ""

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
        return min(660, max(320, 190 + rows * 46))
    }

    var body: some View {
        DSTray(title: String(localized: "File under"), height: trayHeight) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Space.s3) {
                    AddressMark(entry: live, size: DS.Face.list)
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

                // Counted ONCE for the whole sheet: `entries(inGroup:)` sorts
                // the entire book, so asking it inside the row loop sorts it
                // once per group every body pass.
                let counts = book.groupCounts
                ForEach(book.groupNames, id: \.self) { name in
                    groupRow(name, count: counts[AddressBook.key(forGroup: name)] ?? 0)
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

    private func groupRow(_ name: String, count: Int) -> some View {
        let filed = live.isIn(name)
        return Button {
            DSHaptic.tap()
            if filed { book.removeFromGroup(name, address: live.address) }
            else { book.addToGroup(name, address: live.address) }
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
                Spacer(minLength: 0)
                Text("\(count)")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            .padding(.vertical, DS.Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(filed ? "Filed here" : "Not filed here"))
    }
}
