import SwiftUI
import SwiftData
import UIKit

/// The address book's shared pieces (prd §169, 2026-07-21): the kind mark, the
/// copy button every row carries, the name-an-address sheet, and the address
/// card behind a tap.

extension AddressBook.Entry {
    /// "…44b1 · 12 together · Contract" — the address, how much you've
    /// dealt with it, and what it turned out to be, when each is known. A
    /// `.wallet` says nothing extra: a wallet is the unmarked case, and
    /// labelling it would put a word on every row that differentiates none.
    ///
    /// `activity` is how many landed things name this address (`AddressActivity`)
    /// — added 2026-08-01, and placed AHEAD of the kind on purpose. The kind is
    /// already drawn: `AddressMark` gives a wallet a round face and everything
    /// else a square glyph, which is the whole reason that mark exists. What
    /// the row could not say is the only fact that makes this a relationships
    /// list rather than a list of strings — how much you've actually dealt with
    /// them. It's also the "Most active" sort's evidence: that sort reordered
    /// rows with nothing on screen explaining why, which reads as arbitrary.
    ///
    /// The short form is dropped when the ROW'S OWN NAME already is it
    /// (2026-08-13). `WalletStore.add`/`addBulk`/`addToGroup` file a bare
    /// address under `shortAddress` so every watched wallet is findable in its
    /// own book — a display fallback, not a name — and this line then repeated
    /// it directly underneath, so an unnamed wallet read "…44b1 / …44b1 · 12
    /// together". Asked through `isAutoName` rather than `name == short`,
    /// which is that function's whole reason for existing: the tail-only
    /// ruling (2026-08-12) means books already on disk hold the legacy
    /// `0x9a2E…44b1` spelling, and an equality test would call those a name
    /// the person chose and keep printing both.
    ///
    /// When dropping it leaves NOTHING — an unnamed address with no history,
    /// no resolved kind and no provenance — the line is ABSENT (prd §461, seen
    /// on a device). It used to bring the short form back, which on a row whose
    /// NAME is already that short form printed the same string twice, one line
    /// under the other. That shape was masked while every such row also carried
    /// an activity clause; the roster passes `activity: nil` by §461's ruling
    /// that a setup screen draws no readings, so it became the common case on
    /// exactly the rows a new person sees first. So it returns nil now —
    /// `AddressCard.summaryLine`'s own "stays absent rather than printing an
    /// empty line", which this doc has named as the better answer since it was
    /// written and deferred as "worth doing, not worth entangling this with".
    ///
    /// Only that one shape goes absent: a row keeps its short form whenever the
    /// name is a real name, because there the address is the second fact rather
    /// than the same fact again.
    /// `activity` gained its DATE on 2026-08-22 (prd §440). "12 together"
    /// reads identically whether the last of those twelve was on Tuesday or
    /// in 2023, so the count alone could not separate a correspondent from a
    /// stranger — which is the distinction a book of forty is read for. The
    /// phrase is `AddressBookShape.lastPhrase`'s, stated only when there is a
    /// count to attach it to: a date with no dealings behind it would be
    /// describing something the count says didn't happen.
    func subline(activity: AddressActivity.Summary?) -> String? {
        var parts: [String] = []
        let autoNamed = WalletStore.isAutoName(name, for: address)
        if !autoNamed { parts.append(short) }
        if let activity, activity.count > 0 {
            parts.append(String(localized: "\(activity.count) together"))
            if let when = AddressBookShape.lastPhrase(activity.lastAt) {
                parts.append(when)
            }
        }
        // A Bitcoin address's "kind" is its script type (Legacy/P2SH/Native
        // SegWit/Taproot) — a different axis than `kind.label`'s who-vs-
        // machinery question, read straight off the encoding, free
        // (2026-07-27). `kind.label` stays nil for a Bitcoin address (there's
        // no `eth_getCode` to ask), so the two never collide.
        if let label = kind.label { parts.append(label) }
        else if let script = BitcoinAddress.scriptKind(address) { parts.append(script) }
        if let provenance { parts.append(provenance) }
        guard parts.isEmpty else { return parts.joined(separator: " · ") }
        // Nothing else to say. An auto-named row's own NAME is this string, so
        // returning it prints one fact twice; a real name makes it the second
        // fact and it stands.
        return autoNamed ? nil : short
    }
}

/// The filing menu's ITEMS — every group with a tick beside the ones this
/// address is already in, then "New group…".
///
/// Shared because both places you can file from need the identical list: the
/// book row's context menu and the address card's own group row. Only the
/// LABEL differs between them (a context-menu entry vs a card row), so the
/// label stays with each caller and the items live here once.
///
/// Creating a group stays a callback rather than an `.alert` attached here —
/// an alert can't be presented from inside `contextMenu` content, so the host
/// has to own it.
struct GroupMenuItems: View {
    let entry: AddressBook.Entry
    let groups: [String]
    var onNewGroup: () -> Void
    private var book = AddressBook.shared

    init(entry: AddressBook.Entry, groups: [String], onNewGroup: @escaping () -> Void) {
        self.entry = entry
        self.groups = groups
        self.onNewGroup = onNewGroup
    }

    var body: some View {
        ForEach(groups, id: \.self) { name in
            let inGroup = entry.isIn(name)
            Button {
                DSHaptic.tap()
                if inGroup { book.removeFromGroup(name, address: entry.address) }
                else { book.addToGroup(name, address: entry.address) }
            } label: {
                if inGroup { Label(name, systemImage: "checkmark") } else { Text(name) }
            }
        }
        Section {
            Button(action: onNewGroup) {
                Label("New group…", systemImage: "folder.badge.plus")
            }
        }
    }
}

/// Where a book row's tap can go (prd §440) — ONE presentation per screen.
///
/// A route rather than three `.sheet` modifiers, for the reason FeedScreen
/// learned the hard way and this file's own callers have re-learned twice:
/// sibling `.sheet`s on one screen start silently self-dismissing each other's
/// first tap. Shared between the manager and the group screen so both offer
/// the same three doors and neither grows a fourth of its own.
enum AddressBookSheetRoute: Identifiable {
    case entry(AddressBook.Entry)
    /// The filing sheet (prd §440).
    case move(AddressBook.Entry)
    case newGroup
    /// What a settled WalletConnect session handed over, on its way to the
    /// picker (2026-08-13, prd §376). Routed through this enum rather than
    /// hung off the manager as a fourth `.sheet` for the reason above.
    case connectPicker([WalletConnectBridge.ConnectedAccount])

    /// Spelled out rather than computed off the payload, so two cases can
    /// never collide on an address whose key happens to read like a sentinel.
    var id: String {
        switch self {
        case .entry(let e):  return "entry:" + e.id
        case .move(let e):   return "move:" + e.id
        case .newGroup:      return "newGroup"
        // Keyed by the addresses themselves: connecting the same wallet twice
        // is the same sheet, and a fresh identity would re-present it over
        // itself mid-dismiss.
        case .connectPicker(let a): return "connect:" + a.map(\.address).joined(separator: ",")
        }
    }
}

/// ONE row anatomy for the address book, wherever it is drawn (prd §440) —
/// the manager's list, a group's screen, a search result.
///
/// It exists because there were two: the manager built its own row inline and
/// the group sections drew a variant of it, so a change to the subline reached
/// one and not the other. The row is the app's most-repeated address surface;
/// two spellings of it is two books.
///
/// The star is OPTIONAL, and its absence is a real state rather than a
/// disabled control: inside a group the watch verb belongs on the address's
/// own card, and a star in a list that isn't the watch list would be a second
/// place to spend one of five slots from.
struct AddressBookRow: View {
    let entry: AddressBook.Entry
    let activity: AddressActivity.Summary?
    let watched: Bool
    /// Two entries whose SHORT forms print identically (2026-08-01). The book
    /// is the only place that can see this, because it is the only place both
    /// addresses are written down — and the row is where it has to be said,
    /// since the truncation that hides the difference is right beside it.
    let colliding: Bool
    // `markAnchor` retired here 2026-08-22 (prd §448) with the star flight.
    // §441 flew a face from this mark to a shelf slot because the shelf drew
    // the same wallet a second time; Watching is a section of this list now,
    // so starring MOVES this row rather than copying it, and there is no gap
    // left to cross. `OptionalFlightAnchor` below stays — §444's filing
    // flight (a move sheet's head into a group's deck) is a real crossing
    // between two surfaces and still uses it.
    /// nil draws no star at all — see the note above.
    var onToggleWatch: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            AddressMark(entry: entry, size: DS.Face.list)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Space.s1) {
                    Text(entry.name)
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        // The name reveal (2026-08-01), the list's quieter
                        // form: a bare-added row renamed by reverse ENS
                        // cross-fades rather than snapping. Deliberately NOT a
                        // `.id()` swap, which churns row identity inside a
                        // List; `contentTransition` gets the same moment with
                        // none of that.
                        .contentTransition(.opacity)
                        .animation(DS.Motion.standard, value: entry.name)
                    if colliding {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .dsGlyph(11)
                            .foregroundStyle(DS.destructive)
                    }
                }
                // RELATIONSHIP facts, never money (§435). Absent rather than
                // empty when there is nothing to say — see `subline`.
                if let line = entry.subline(activity: activity) {
                    Text(line)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            if let onToggleWatch {
                Button(action: onToggleWatch) {
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
        }
        .padding(.vertical, DS.Space.s2)
        .contentShape(Rectangle())
    }
}

/// Making a group from the BOOK rather than from one address (2026-08-01,
/// amending prd §266).
///
/// §266 shipped creation as a per-address verb only, and the reasoning held:
/// filing something is what brings a group into being, so the door lived where
/// the thing being filed was. Nothing here changes that model — this sheet
/// still cannot make an empty group. What it fixes is DISCOVERY. The chips row
/// renders only once a group exists, so a book with none showed no trace of the
/// feature anywhere, and the only ways in were a long-press on a row or a tap
/// into an address card: "we just shipped some Wallet features improving the
/// address book, but I don't see how to create groups" (user, 2026-08-01).
///
/// So the gesture inverts — name it, then pick who's in it, in one pass. That
/// is also the shape the job actually has: a group is several addresses you
/// already have in mind, and filing them one long-press at a time is the same
/// work spread over N gestures with no way to see the set coming together.
///
/// Two honesty details worth keeping. Typing a name the book already uses
/// (case-folded) ADDS to that group rather than making a second one wearing the
/// same word — `AddressBook.canonicalGroupName` has always done this, and the
/// sheet says so in place instead of letting the outcome surprise you. And the
/// button states which of the two requirements is still missing, rather than
/// sitting inert with nothing to say.
struct NewGroupSheet: View {
    /// Handed the spelling the book actually filed under, so the caller can
    /// select the chip it just made. See `AddressBook.addToGroup(_:addresses:)`.
    var onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private var book = AddressBook.shared

    @State private var name = ""
    @State private var filter = ""
    @State private var picked: Set<String> = []

    init(onCreate: @escaping (String) -> Void) {
        self.onCreate = onCreate
    }

    var body: some View {
        DSTray(title: "New group", height: 660, ink: true) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Deleting a group never deletes an address.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                nameField
                if let existing = matchingGroup {
                    note(String(localized: "You already have “\(existing)” — these get added to it."))
                }
                cover
                if book.count > 8 { filterField }
                list
                createButton
            }
        }
    }

    /// THE GROUP'S COVER, FORMING AS YOU BUILD IT (2026-08-22, prd §444).
    ///
    /// This sheet asks for two things — a name and a set — and until now the
    /// set existed only as ticks scattered down a scrolling list, so the thing
    /// being made was never visible as a thing. Every group in the app is drawn
    /// as a deck of its members' faces (`AddressGroupCard`, and since §444 the
    /// filing sheet's own rows); this is that same deck, assembling.
    ///
    /// It is not a preview of a screen elsewhere, it IS the object: a face
    /// joining the deck is the tick you just made, which is why the deck grows
    /// from the leading edge and the button below it counts the same set.
    ///
    /// Absent until the first pick, deliberately — an empty deck above an
    /// untouched list is a frame around nothing, and the row's own well
    /// (which exists so a flight has somewhere to land) has no equivalent job
    /// here.
    @ViewBuilder
    private var cover: some View {
        let chosen = pickedEntries
        if !chosen.isEmpty {
            HStack(spacing: -8) {
                ForEach(chosen.prefix(Self.coverFaces)) { entry in
                    AddressMark(entry: entry, size: DS.Face.list)
                        // `AddressGroupCard`'s deck, spelled the same way — one
                        // deck across the app. Nothing here draws a line, so a
                        // mark punches the sheet colour out from under the one
                        // behind it.
                        .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 2))
                        // A face JOINING grows into the deck; the ones already
                        // in it hold still.
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                if chosen.count > Self.coverFaces {
                    Text("+\(chosen.count - Self.coverFaces)")
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .padding(.leading, DS.Space.s3)
                }
                Spacer(minLength: 0)
            }
            .frame(height: DS.Face.list)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("^[\(chosen.count) address](inflect: true) picked"))
        }
    }

    /// How many faces the cover shows before it starts counting. Five, because
    /// that is where a leading-anchored deck at `DS.Face.list` stops fitting
    /// beside its own tally inside the tray's margins.
    private static let coverFaces = 5

    /// The picked entries in the BOOK's order, not tap order — the deck must
    /// match the group it is about to make, and a group has no memory of which
    /// address you ticked first.
    private var pickedEntries: [AddressBook.Entry] {
        book.all.filter { picked.contains($0.id) }
    }

    private func note(_ text: String) -> some View {
        Text(text).dsText(.subhead13).foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var nameField: some View {
        TextField("Name (e.g. Family, Cold)", text: $name)
            .dsText(.body17)
            .foregroundStyle(DS.textPrimary)
            .submitLabel(.done)
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: 44)
            .background(DS.surfaceWell,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    /// Only for a book big enough to need it — a filter above six rows is
    /// furniture, and this sheet already asks for two things.
    private var filterField: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(14, weight: .medium)
                .foregroundStyle(DS.textTertiary)
            TextField("Filter your addresses", text: $filter)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(minHeight: 44)
        .background(DS.surfaceWell,
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.s2) {
                ForEach(rows) { entry in row(entry) }
            }
            .padding(.vertical, DS.Space.s1)
            if rows.isEmpty {
                note(book.count == 0
                     ? String(localized: "Your book is empty — name an address first, then it can go in a group.")
                     : String(localized: "Nothing here matches “\(filter)”."))
                    .padding(.top, DS.Space.s2)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private func row(_ entry: AddressBook.Entry) -> some View {
        let on = picked.contains(entry.id)
        return Button {
            DSHaptic.tap()
            // One animation for the tick AND the cover above it: they are the
            // same event, and two `withAnimation`s would let the face land
            // before or after the checkmark it belongs to.
            withAnimation(DS.Motion.bubble) {
                if on { picked.remove(entry.id) } else { picked.insert(entry.id) }
            }
        } label: {
            HStack(spacing: DS.Space.s3) {
                AddressMark(entry: entry, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).dsText(.heading17)
                        .foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text(entry.short).dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary).monospaced().lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .dsGlyph(16, weight: .bold)
                    .foregroundStyle(DS.tint)
                    .opacity(on ? 1 : 0)
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? DS.tintDim : DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(DSTileButtonStyle())
        .dsHover()
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// Says which requirement is still open rather than going inert — and
    /// swaps its own FILL when it does, since `.disabled` dims a label and not
    /// a background a button painted itself (honesty rule, prd §83).
    private var createButton: some View {
        let ready = !trimmedName.isEmpty && !picked.isEmpty
        return Button {
            create()
        } label: {
            Text(buttonLabel)
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(ready ? .white : DS.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(ready ? DS.tint : DS.gray100,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                 style: .continuous))
        }
        .buttonStyle(PressSpring())
        .armedPop(ready)
        .disabled(!ready)
    }

    private var buttonLabel: String {
        if trimmedName.isEmpty { return String(localized: "Name the group") }
        if picked.isEmpty { return String(localized: "Pick who's in it") }
        return String(localized: "Create with \(picked.count)")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The group this name would join rather than create, if any.
    private var matchingGroup: String? {
        let typed = trimmedName
        guard !typed.isEmpty else { return nil }
        return book.groupNames.first { AddressBook.sameGroup($0, typed) }
    }

    private var rows: [AddressBook.Entry] {
        let all = book.all
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q) || $0.address.lowercased().contains(q)
        }
    }

    private func create() {
        // Off `book.all` rather than the filtered `rows`, or narrowing the
        // filter after picking would drop members already chosen.
        let addresses = book.all.filter { picked.contains($0.id) }.map(\.address)
        guard let group = book.addToGroup(trimmedName, addresses: addresses) else { return }
        DSHaptic.success()
        onCreate(group)
        dismiss()
    }
}

/// What an address IS, as a mark. A wallet is a WHO — it wears the same
/// identicon face the watched wallets and transfer stages use, so the same
/// address looks the same everywhere. Everything else is machinery and wears a
/// square glyph, which is what lets a fifty-row book separate people from
/// contracts with no grouping UI at all.
struct AddressMark: View {
    let entry: AddressBook.Entry
    var size: CGFloat = DS.Face.list

    var body: some View {
        Group {
            if let glyph = entry.kind.glyph {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: glyph)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                    }
            } else {
                // CIRCULAR (prd §433, 2026-08-21). This view's own header has
                // said "a wallet is a WHO … everything else is machinery and
                // wears a square glyph" since §169, and the roster shelf drew
                // it that way — but every OTHER use of this mark took
                // `WalletFace`'s squircle default, so in the list a wallet and
                // a contract were both rounded rectangles and the whole
                // round-vs-square rule came down to colour-vs-gray. The face
                // is now the same shape wherever an address is a person: the
                // shelf, the book row, the group deck, the address card, the
                // preview under the field. §362's ruling, one screen down —
                // "the best way to make it simple is things being the same."
                WalletFace(address: entry.address, size: size, circular: true)
            }
        }
        // The kind reveal (prd §171, 2026-07-22). Detection lands
        // asynchronously — `eth_getCode` answers a beat after the row is on
        // screen — and the mark used to hard-swap from face to square glyph.
        // Now it turns over: the app worked out WHAT this address is while you
        // were looking at it, and that's a real moment, so it gets shown.
        // Keyed on the kind so nothing replays on a scroll or a rename.
        .transition(.scale(scale: 0.82).combined(with: .opacity))
        .id(entry.kind)
        .animation(DS.Motion.standard, value: entry.kind)
    }
}

/// Copy — the book's most-used verb, so it rides every row instead of hiding
/// one level down. States the outcome in place (the app's own "a control says
/// what happens, then says it happened" grammar) rather than firing a toast
/// from a list row.
struct CopyAddressButton: View {
    /// How the verb is drawn. Three shapes because it appears in three kinds
    /// of place, and the middle one is not a variant of either neighbour.
    enum Style {
        /// A bare glyph on a faint square — a row's trailing affordance.
        case compact
        /// The word alone, no ground. For a control that already sits inside
        /// a filled container (`WalletScreen.manualPairingCard`), where a
        /// second fill would nest two grounds.
        case inline
        /// Glyph and word in a capsule — the address card's own copy pill
        /// (prd §446), which stands alone under the address with nothing
        /// behind it to borrow a shape from.
        case pill
    }

    let address: String
    var style: Style = .compact
    /// The pill's ink. Every caller takes the app tint now — the address card
    /// used to hand in that address's own hue so the pill, the `See all` link
    /// and the verb bar wore one identity, and that went with the pour
    /// (2026-08-22). Kept as a parameter rather than hard-wired: it is a
    /// reusable control, and the next caller may have a real reason.
    var tint: Color = DS.tint
    @State private var copied = false

    var body: some View {
        Button {
            DSPasteboard.copySensitive(address)
            DSHaptic.success()
            withAnimation(DS.Motion.standard) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(DS.Motion.standard) { copied = false }
            }
        } label: {
            Group {
                switch style {
                case .inline:
                    Text(copied ? "Copied" : "Copy")
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(copied ? DS.confirm : tint)
                case .pill:
                    HStack(spacing: DS.Space.s2) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .dsSymbolSwap(copied)
                            .dsGlyph(12, weight: .semibold)
                        Text(copied ? "Copied" : "Copy")
                            .dsText(.subhead13).fontWeight(.semibold)
                    }
                    .foregroundStyle(copied ? DS.confirm : tint)
                    .padding(.leading, DS.Space.s3)
                    .padding(.trailing, DS.Space.s3 + 2)
                    .padding(.vertical, 7)
                    .background(DS.fillFaint, in: Capsule(style: .continuous))
                    .dsTapTarget(Capsule(style: .continuous))
                case .compact:
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .dsSymbolSwap(copied)
                        .dsGlyph(12)
                        .foregroundStyle(copied ? DS.confirm : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 9,
                                                                       style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .accessibilityLabel(copied ? "Address copied" : "Copy address")
        // The compact form is a bare glyph, so the tooltip names the verb
        // and its object; the worded forms say less.
        .dsTooltip(copied ? String(localized: "Address copied")
                          : String(localized: "Copy address"))
    }
}

/// The address's chunks, wrapped and CENTRED (prd §446).
///
/// `FlowLayout` (`ThingSheetView`) is leading-aligned and takes one spacing for
/// both axes; an address block needs its rows centred under the name and a
/// tight row gap against a wide column gap, so this is its own layout rather
/// than a parameter added to that one — the two answer different questions and
/// a shared one would grow a mode switch nobody reads.
///
/// It must WRAP and never truncate: this is the one screen where a hidden
/// character is a different address.
private struct AddressChunkFlow: Layout {
    var columnSpacing: CGFloat
    var rowSpacing: CGFloat

    private struct Run { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func runs(_ subviews: Subviews, width: CGFloat) -> [Run] {
        var out: [Run] = []
        var run = Run()
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let added = run.indices.isEmpty ? size.width : run.width + columnSpacing + size.width
            if added > width, !run.indices.isEmpty {
                out.append(run)
                run = Run()
                run.indices = [i]; run.width = size.width; run.height = size.height
            } else {
                run.indices.append(i)
                run.width = added
                run.height = max(run.height, size.height)
            }
        }
        if !run.indices.isEmpty { out.append(run) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = runs(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, max(widest, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let rows = runs(subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                  proposal: .unspecified)
                x += size.width + columnSpacing
            }
            y += row.height + rowSpacing
        }
    }
}

/// The address card (prd §169) — one address, everything the app honestly
/// knows about it: its name, what it is, the address itself with Copy, and
/// your own history together, pulled from the corpus. Purely informational —
/// watching lives solely on the book row's own star (prd §202), so the same
/// setting isn't a control in two places at once.
///
/// The history section is what makes this Casberi's rather than a contacts
/// app: landed transfers already carry `counterpartyAddress`, so the card can
/// show the relationship the corpus already recorded — without one extra
/// request.
/// Everything the corpus knows about one address, newest first — the shared
/// rule behind both the card's six-row preview and its "See all" screen, so
/// the two can never show different sets. Two kinds of belonging:
///   • a Wallet transaction where this address was the COUNTERPARTY (the
///     original "your history together" — someone you transacted with), and
///   • a Peer fill or Privacy Pools deposit MADE BY this address (prd §207):
///     those seats ride the watched wallets and have no separate home, so a
///     watched wallet's own fills and deposits live on its address-book card.
/// `walletAddress` is the owner both bridges stamp on every thing they land.
// What belongs to an address now lives in `AddressActivity` (2026-08-01), so
// the Wallet manager's "Most active" sort, this card's own count, and the
// name-this-address nudge can no longer disagree about what activity means —
// they did, and the sort was the one that was wrong.

struct AddressCard: View {
    let entry: AddressBook.Entry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    // `bridges` retired here 2026-08-24 (prd §461) — it existed for one line,
    // `reconcileWalletSeats()` inside `toggleWatch`, and this card no longer
    // watches anything. An unread `@Environment` is harmless but it is also a
    // standing claim that this sheet needs the catalog store, which it does not.
    private var book = AddressBook.shared
    /// Naming happens IN PLACE now (prd §444) — see `nameField`.
    @State private var editingName = false
    @FocusState private var nameFocused: Bool
    @State private var nameDraft = ""
    @State private var addingGroup = false
    @State private var groupDraft = ""
    /// Bumped when a rename actually rewrote landed titles — the history rows
    /// stagger their cross-fade off it. See `rename(to:)`.
    @State private var renameCascade = 0
    /// What this address can move right now (prd §372). nil until the read
    /// answers — the section simply isn't there yet, rather than claiming a
    /// zero it hasn't earned.
    @State private var exposure: WalletApprovalExposure?

    init(entry: AddressBook.Entry) { self.entry = entry }

    /// Live, so a rename or a kind landing repaints the card.
    private var current: AddressBook.Entry { book.entry(for: entry.address) ?? entry }

    /// Whether the book actually HOLDS this address (2026-08-20).
    ///
    /// The card can be opened for one it doesn't: the connections card's nodes
    /// became doors (prd §295 follow-up), and a connected address nobody has
    /// ever named is precisely the one worth opening — so the entry handed in
    /// may be ephemeral, invented for the trip. Everything here still reads
    /// correctly off it; the only line that would LIE is `addedAt`, which
    /// would print "named today" about an address that was never named.
    private var isInBook: Bool { book.entry(for: entry.address) != nil }

    /// The corpus's own record of this address — counterparty transactions
    /// plus its own Peer/Pool activity (see `AddressActivity`), newest first.
    private var history: [Thing] {
        AddressActivity.history(for: entry.address, in: modelContext)
    }

    /// How far the sheet has been scrolled, for the header/nav hand-off below.
    /// Zero until the first geometry callback, so a sheet that never scrolls
    /// never shows a title.
    @State private var scrolled: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                // ONE fetch per body pass (2026-08-22, prd §444). `history` is
                // a computed property that walks the corpus, and it had two
                // readers before this pass and would have had three after —
                // the §441 cost, one screen down, arriving the same way it did
                // there. A `let` in the builder rather than `@State`, so no
                // reader can ever be handed an array older than this pass.
                let things = history
                VStack(spacing: 0) {
                    identityHeader
                    lookalikeBand
                    spine(things)
                    nameNudge
                    // Room for the pinned verb bar. `DS.Hit.min` plus the
                    // bar's own padding — spelled from the token so the two
                    // cannot drift apart.
                    Color.clear.frame(height: bottomBarShown ? DS.Hit.min + 46 : DS.Space.s4)
                }
            }
            .scrollIndicators(.hidden)
            .dsAdaptiveContentWidth()
            // The name hands off to the nav title as the header leaves
            // (2026-08-22, prd §443). The subject of this sheet is an
            // identity, and until now it left the screen entirely the moment
            // you started reading the history that belongs to it. 96 is where
            // the 76pt face has cleared the bar; the fade is over the last 24
            // so the two never both read as the title.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, new in
                guard abs(scrolled - new) > 1 else { return }
                scrolled = new
            }
            .dsPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(current.name)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .opacity(titleReveal)
                        .accessibilityHidden(titleReveal < 0.5)
                }
                ToolbarItem(placement: .topBarLeading) { overflowMenu }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(DS.tint)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .alert("New group", isPresented: $addingGroup) {
                TextField("Name (e.g. Family, Cold)", text: $groupDraft)
                Button("Create") {
                    book.addToGroup(groupDraft, address: entry.address)
                    DSHaptic.success()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Files \(current.name) under a new group.")
            }
            .task { await AddressKind.detect(entry.address) }
            .task {
                exposure = await WalletApprovalExposure.forSpender(entry.address,
                                                                   context: modelContext)
            }
        }
        .presentationBackground(DS.surfaceSheet)
        .dsColorScheme()
        // Declared HERE rather than at its call sites (2026-08-20): this
        // card is presented from the thing sheet's face tap AND the wallet
        // book, both inside a `switch`, so a call-site size would have to
        // be written twice and could drift.
        .dsPageSheet()
    }

    /// 0 while the face is still on screen, 1 once it has cleared the bar.
    private var titleReveal: Double {
        min(1, max(0, (scrolled - 72) / 24))
    }

    // MARK: - Identity

    /// The face, the name, what it is, the address, and the groups it is filed
    /// under — everything answering "who is this", in one field wearing this
    /// address's own colour (prd §443).
    ///
    /// **There is no pour here any more (2026-08-22, user ruling).** It was the
    /// §171/§435 recipe, and on a device it drew a hard black line across the
    /// top of the sheet: the gradient `ignoresSafeArea()`, but a sheet's own
    /// chrome above it does not, so the wash stopped at the grabber instead of
    /// running to the edge. Offered the choice between making it cover the
    /// whole sheet and dropping the colour, the ruling was to drop it — "i'd
    /// rather just do that".
    ///
    /// The identity colour itself STAYS, on the face, the copy pill and the
    /// group chips: §444's face is made OF the address, so its hue is the
    /// address's own identity rather than decoration. What went is the wash
    /// behind them. Note this screen is a SHEET, which is why it diverges from
    /// the app-detail page and the token quick sheet, where the pour has the
    /// full page to run into.
    private var identityHeader: some View {
        VStack(spacing: 0) {
            // THE FACE IS MADE OF THE ADDRESS (prd §444) — see `AddressReveal`.
            AddressMark(entry: current, size: DS.Face.profile)
                .addressFaceReveal(hue: pourHue, isFace: current.kind.glyph == nil)
            nameField
                .padding(.top, DS.Space.s3)
            Text(kindLine)
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .padding(.top, 1)
            bitcoinVintageLine
            addressBlock
                .padding(.top, DS.Space.s2)
            copyPill
                .padding(.top, DS.Space.s3)
            groupChips
                .padding(.top, DS.Space.s2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s4)
    }

    /// Rename, and the door out of the book — the two verbs that are not this
    /// screen's decision (prd §443).
    ///
    /// Rename used to be a top-LEADING toolbar button, which is where iOS puts
    /// Back and Cancel; a destructive-looking position for the one control
    /// that rewrites every title you have with this address. An overflow menu
    /// is where a profile's secondary verbs live.
    private var overflowMenu: some View {
        Menu {
            Button { beginRename() } label: { Label("Rename", systemImage: "pencil") }
            // §446's watch row is GONE (prd §461) — see the retirement note at
            // `isWatching`. It was here because the pinned bar could only carry
            // one verb; the reason it is not here now is that this card carries
            // no watch decision at all.
            // THE DOOR OUT (prd §446). It was a settings-shaped row in a card
            // at the foot of the sheet, drawn at the weight the security
            // notice above it wore; a link into somebody else's website is a
            // secondary verb, and this is the menu those live in.
            if let link = explorerLink {
                let url = link.url
                Button {
                    DSHaptic.tap()
                    openURL(url)
                } label: { Label(link.label, systemImage: "arrow.up.right") }
            }
            if isInBook {
                Button(role: .destructive) {
                    rename(to: "")
                } label: { Label("Remove from book", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .dsGlyph(15)
                .foregroundStyle(DS.textPrimary)
                .frame(width: 32, height: 32)
                .background(DS.fillStrong, in: Circle())
                .dsTapTarget(Circle())
        }
        .accessibilityLabel(Text("More"))
    }

    /// THE NAME, EDITED WHERE IT STANDS (2026-08-22, prd §444).
    ///
    /// **Why the alert had to go.** Naming is the act this card exists for —
    /// `rename(to:)`'s own header says a name "rewrites every transaction
    /// you've ever had with this address, all at once, and that is the entire
    /// argument for naming anything", and §441 built the cascade that shows it
    /// sweeping down the history. An `.alert` covers the card while you type,
    /// so the cascade ran under a dimmed screen behind a dialog and was over
    /// by the time the dialog dismissed. The one moment the card was built
    /// around could not be watched from the card.
    ///
    /// Committing on BLUR as well as on submit, because a sheet has a dozen
    /// ways to leave a field and losing a typed name to any of them is the
    /// worse failure. `commitName` is idempotent for exactly that reason —
    /// submit drops focus, so both paths fire on every hardware return.
    ///
    /// The pencil appears only while the name is a PLACEHOLDER the app minted
    /// (`WalletStore.isAutoName` — `…44b1`, not something anybody typed),
    /// which is precisely when naming is the thing to do. Once it carries a
    /// real name the invitation would be chrome on the hero, and the labelled
    /// verb still lives in the overflow menu.
    @ViewBuilder
    private var nameField: some View {
        if editingName {
            VStack(spacing: DS.Space.s2) {
                TextField("Name", text: $nameDraft)
                    .dsText(.heading28)
                    .foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .padding(.horizontal, DS.Space.s3)
                    .frame(minHeight: DS.Hit.min)
                    .background(DS.surfaceWell,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                     style: .continuous))
                    .padding(.horizontal, DS.Space.s4)
                // The one consequence a field cannot state by its shape. It
                // sat in the alert's message; without a container to carry it
                // the field has to, and only while the field is open.
                Text("A blank name removes it from your book.")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            .onAppear {
                // One turn later: a `@FocusState` set in the same turn the
                // field first appears is read before the field exists to take
                // it, and the keyboard silently never rises.
                DispatchQueue.main.async { nameFocused = true }
            }
            .onChange(of: nameFocused) { _, focused in
                if !focused { commitName() }
            }
        } else {
            Button { beginRename() } label: {
                HStack(spacing: DS.Space.s2) {
                    Text(current.name)
                        .dsText(.heading28).foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.center)
                        // The NAME reveal (2026-08-01) — `AddressMark`'s kind
                        // turn-over (prd §171) applied to the other half of the
                        // question. An address added bare stands under its own
                        // short form; a beat later reverse ENS answers, or a
                        // typed `.eth` resolves and `reconcileAliases` re-keys
                        // the row, and the card learns what to call it while
                        // you are looking at it.
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .id(current.name)
                        .animation(DS.Motion.standard, value: current.name)
                    if unnamed {
                        Image(systemName: "pencil")
                            .dsGlyph(13)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                .contentShape(Rectangle())
                .dsTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(current.name))
            .accessibilityHint(Text("Rename this address"))
        }
    }

    /// Whether this address is still standing under a name the app minted for
    /// it rather than one anybody chose. `isAutoName` and never a comparison
    /// against `shortAddress` — books written before the tail-only ruling hold
    /// the old spelling, and that function is the only thing that knows both.
    private var unnamed: Bool {
        WalletStore.isAutoName(current.name, for: current.address)
    }

    private func beginRename() {
        nameDraft = current.name
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { editingName = true }
    }

    /// Idempotent on purpose — submit drops focus, so both the `onSubmit` and
    /// the `onChange` fire for one hardware return.
    private func commitName() {
        guard editingName else { return }
        withAnimation(DS.Motion.standard) { editingName = false }
        nameFocused = false
        let typed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != current.name else { return }
        rename(to: typed)
    }

    /// THE ADDRESS, WHOLE (2026-08-22, prd §446).
    ///
    /// **It was a middle-truncated capsule and that could never work here.**
    /// `truncationMode(.middle)` at 390pt cannot show forty-two characters, so
    /// the one screen that exists to tell two look-alike addresses apart was
    /// hiding precisely the characters they differ in — the same objection
    /// `lookalikeBand` prints both addresses in full to answer.
    ///
    /// So it wraps instead: ten groups of four, centred, every character
    /// present. The groups are what make it readable — forty-two unbroken
    /// characters is a wall, and a person checking an address checks it in
    /// chunks whether the app offers them or not.
    ///
    /// The first and last group sit one ramp step brighter because they are
    /// the ones every other surface shows (`WalletStore.shortAddress`), so the
    /// eye can find its footing before reading the middle.
    private var addressBlock: some View {
        let chunks = AddressSpine.chunks(current.address)
        return AddressChunkFlow(columnSpacing: DS.Space.s2, rowSpacing: 1) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                Text(verbatim: chunk)
                    .dsText(.mono13)
                    .foregroundStyle(index == 0 || index == chunks.count - 1
                                     ? DS.textSecondary : DS.textTertiary)
                    // Ends first, middle after — `AddressEndsFirst`'s reading,
                    // rebuilt per chunk because a horizontal mask over a
                    // WRAPPING container would uncover the middle of each line
                    // rather than the ends of the address.
                    .addressChunkReveal(index: index, count: chunks.count)
            }
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, DS.Space.s4)
        // One string to VoiceOver: reading it as ten labels puts a pause every
        // four characters, which on this screen is a different address.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(current.address))
    }

    /// Copy — the pill under the address, in the app tint.
    ///
    /// It used to take this address's own hue, along with `See all` and the
    /// verb bar, so the whole card read as one identity. That went with the
    /// pour (2026-08-22, user ruling): a control in a per-address colour is a
    /// control whose colour means nothing you can act on, and the same purple
    /// on a CTA read as a brand nobody chose. The identity colour stays where
    /// it IS the identity — the face and its ring.
    private var copyPill: some View {
        CopyAddressButton(address: current.address, style: .pill, tint: DS.tint)
    }

    /// Which groups this address is filed under, as chips beside its name
    /// (2026-08-22, prd §443).
    ///
    /// It was a full-width menu card down among the settings-shaped rows, and
    /// that is the wrong reading of what a group IS: "Family" is a fact about
    /// who this address is to you, the same kind of fact as its name and its
    /// face, not a preference you set. So it rides with the identity, and the
    /// trailing `+` opens the very same `GroupMenuItems` menu the card row
    /// opened — no verb was moved or lost.
    ///
    /// Always present, empty included: a control that only appears once you
    /// already have groups leaves the feature discoverable solely by
    /// long-pressing a row in the list behind this sheet.
    private var groupChips: some View {
        let groups = current.groupNames
        return Menu {
            GroupMenuItems(entry: current, groups: book.groupNames) {
                groupDraft = ""
                addingGroup = true
            }
        } label: {
            HStack(spacing: DS.Space.s1 + 2) {
                ForEach(groups, id: \.self) { name in
                    Text(name)
                        .dsText(.label12).foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.vertical, 6)
                        .background(DS.fillFaint, in: Capsule(style: .continuous))
                }
                if groups.isEmpty {
                    Text("Add to a group")
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.vertical, 6)
                        .background(DS.fillFaint, in: Capsule(style: .continuous))
                } else {
                    Image(systemName: "plus")
                        .dsGlyph(10)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(DS.fillFaint, in: Circle())
                }
            }
            .contentShape(Rectangle())
            .dsTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(groups.isEmpty ? "Add to a group"
                                                : "Groups: \(groups.joined(separator: ", "))"))
    }

    /// A wallet is a who and owns a hue; a contract or a Safe is machinery and
    /// borrows the app's. Mirrors the mark's own round-vs-square rule, so the
    /// card's color says the same thing its face does.
    ///
    /// A SMART ACCOUNT sits with the whos (2026-08-03, prd §294) — it's
    /// somebody's wallet that happens to be made of code, and it keeps its
    /// identicon face for exactly that reason (see `AddressBook.Kind.glyph`).
    /// Colour has to agree with the face, or the card would say two things.
    ///
    /// **The name is now historical.** There is no pour on this sheet since
    /// 2026-08-22, and no control takes this colour either — only the face and
    /// the ring that draws it, which is the one place the colour is the
    /// address's identity rather than decoration.
    private var pourHue: Color {
        switch current.kind {
        case .wallet, .unknown, .smartAccount: return WalletFace.tint(for: current.address)
        case .contract, .safe:  return DS.tint
        }
    }

    /// A Bitcoin address's balance and the age of its oldest unspent piece
    /// (2026-07-27) — the one fact this app can state about a Bitcoin
    /// holding that it structurally cannot state about any other asset it
    /// reads. An ETH balance is a single number with no history inside it; a
    /// Bitcoin balance is a pile of individually dated UTXOs, so "how long
    /// have you held this" is answerable here and nowhere else.
    ///
    /// A standing line, never a moment: it moves DOWN when a spend consumes
    /// the oldest piece, and celebrating that would be exactly the kind of
    /// congratulation §218's floor ruling forbids. Renders nothing at all
    /// until the sweep has actually cached both facts — an address card that
    /// has never synced says nothing rather than guessing.
    @ViewBuilder
    private var bitcoinVintageLine: some View {
        if BitcoinAddress.isAddress(current.address),
           let sats = BitcoinBridge.cachedBalanceSats(for: current.address), sats > 0 {
            // A BTC balance is a balance (prd §374). The vintage beside it is
            // not — "oldest piece from March 2017" says when, not how much,
            // and it is the whole point of the line.
            let amount = BalancePrivacy.shared.value(BitcoinBridge.formatAmount(sats: sats))
            if let since = BitcoinBridge.vintage(for: current.address) {
                Text("\(amount) · oldest piece from \(since.formatted(.dateTime.month(.wide).year()))")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.s4)
            } else {
                Text(verbatim: amount)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
        }
    }

    /// What it is, and where it came from — the naming DATE has moved to the
    /// details list (prd §443). It was the weakest of the three facts and it
    /// sat last, which reads as the punchline of the line introducing the
    /// person. An address reached through a door rather than through the book
    /// still says so here, because that one changes what the screen can claim.
    private var kindLine: String {
        let kindWord = current.kind.label
            ?? BitcoinAddress.scriptKind(current.address)
            ?? String(localized: "Wallet")
        var parts: [String] = [kindWord]
        if let provenance = current.provenance { parts.append(provenance) }
        if !isInBook { parts.append(String(localized: "not in your book")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Trouble

    /// The address(es) already in this book that PRINT the same as this one
    /// (2026-08-01), as a FIELD rather than a card (prd §443), with the
    /// comparison MADE rather than asked for (2026-08-22, prd §444).
    ///
    /// A card is a container of information and this is a CONDITION of the
    /// screen, so it takes the full width and its own ground — the one thing
    /// on the sheet that cannot be mistaken for another widget in the stack.
    /// Both addresses print in full and un-truncated, which is the only form
    /// of this warning anyone can act on.
    ///
    /// **§444: it used to end on "compare every character before you copy",
    /// which is the app handing back the one job it is better at.** Forty-two
    /// characters is past what anybody checks honestly, and the check people
    /// actually perform — glance at the ends — is precisely the one a
    /// poisoning address is BUILT to survive. So `AddressDiff` finds where the
    /// two part, the shared head and the shared tail dim because they are the
    /// parts that cannot help, and the first character that differs wears a
    /// marker. For the poisoning shape that is character 3, so telling them
    /// apart costs one glance instead of forty-two.
    ///
    /// It says what the app knows and stops. It does NOT accuse either side of
    /// being the impostor: the book cannot know which one you meant, and a
    /// wrong accusation on a security notice is worse than none. The marker is
    /// therefore the same on both addresses — it points at a POSITION, never at
    /// a culprit.
    @ViewBuilder
    private var lookalikeBand: some View {
        let twins = book.lookalikes(of: current.address)
        if !twins.isEmpty {
            let fold = foldsCase(twins.map(\.address))
            let mine = AddressDiff.combined(current.address, against: twins.map(\.address),
                                            foldCase: fold)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .dsGlyph(14)
                        .foregroundStyle(DS.destructive)
                    Text("Another address looks just like this one")
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                }
                Text(partingLine(mine, twins: twins.count))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    diffRow(String(localized: "This one"), current.address, mine)
                    ForEach(twins) { twin in
                        diffRow(twin.name, twin.address,
                                AddressDiff.compare(twin.address, with: current.address,
                                                    foldCase: fold))
                    }
                }
                .padding(.top, DS.Space.s1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .background(DS.destructive.opacity(0.16))
        }
    }

    /// One labelled address, drawn as its diff runs.
    ///
    /// The runs are `AddressDiff`'s, never this view's — the comparison is
    /// harness-proven and a second spelling of it here is a second answer.
    /// Concatenated into ONE `Text` so the characters flow and wrap as a single
    /// string: an `HStack` of runs would let the line break between them and
    /// put a space where the address has none, which on this screen is a
    /// different address.
    private func diffRow(_ label: String, _ address: String,
                         _ comparison: AddressDiff.Comparison) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            AddressDiff.segments(of: address, comparison: comparison)
                .reduce(Text(verbatim: "")) { acc, segment in
                    acc + inked(segment)
                }
                .dsText(.mono13)
                .fixedSize(horizontal: false, vertical: true)
                // The whole address, read out as one string. Splitting it into
                // runs for VoiceOver would read the marker as a pause in the
                // middle of an address.
                .accessibilityLabel(Text(address))
        }
    }

    /// A run's ink. Shared characters recede, the parting character is the
    /// only thing carrying colour, and everything after it is ordinary text.
    ///
    /// The marker is `DS.destructive` because the band is, and because the
    /// alternative — the address's own hue — would give the two look-alikes
    /// two different markers and imply the colours mean something about which
    /// is which.
    private func inked(_ segment: AddressDiff.Segment) -> Text {
        switch segment.run {
        case .shared:
            return Text(verbatim: segment.text).foregroundStyle(DS.textTertiary)
        case .pivot:
            return Text(verbatim: segment.text)
                .foregroundStyle(DS.destructive)
                .fontWeight(.bold)
        case .differing:
            return Text(verbatim: segment.text).foregroundStyle(DS.textPrimary)
        }
    }

    /// The sentence over the two addresses — the fact, then where to look.
    ///
    /// Nil-safe on the pivot rather than force-unwrapped: two entries the book
    /// calls look-alikes cannot be character-identical, and the screen this
    /// runs on is the one where a crash is least acceptable, so the impossible
    /// case gets the old sentence rather than a trap.
    /// Several twins get the general sentence, not a number. `combined` takes
    /// the EARLIEST parting across them while each twin row is marked from its
    /// own pairwise comparison, so naming one character would point at a
    /// position some of the visible markers do not occupy — the sentence and
    /// the ink disagreeing on the one screen whose entire job is telling you
    /// exactly where to look.
    private func partingLine(_ comparison: AddressDiff.Comparison,
                             twins: Int) -> String {
        guard twins == 1, let position = comparison.pivotPosition else {
            return String(localized: "Same short form, different address. The first character that differs is marked below.")
        }
        return String(localized: "Same short form, different address. They first differ at character \(position), marked below.")
    }

    /// Whether a case difference between these addresses is a difference at
    /// all (prd §444).
    ///
    /// EIP-55 encodes a checksum in the CASE of a hex address's letters, so one
    /// address legitimately prints `0xAbC…` here and `0xabc…` there — comparing
    /// those raw marks character 3 on two spellings of the SAME money. Base58
    /// (Solana, Bitcoin) is the reverse: case is the value, and folding it
    /// hides a real difference.
    ///
    /// EVERY side must be hex, not just this one: one base58 twin in the set
    /// and the fold would erase the case differences it carries. The test is
    /// `ENS.isHexAddress`, the app's own, so this can never drift from what
    /// `AddressSafety` means by a hex address.
    private func foldsCase(_ others: [String]) -> Bool {
        ENS.isHexAddress(current.address) && others.allSatisfy(ENS.isHexAddress)
    }

    // MARK: - The spine

    /// ONE DATED SPINE (2026-08-22, prd §446) — see `AddressSpine`.
    ///
    /// It replaces `lede` / `reachedWallets` / `historySection` / `detailsList`,
    /// which were four treatments of one shape: a dated fact about this
    /// address. The standing permission is simply the newest event, so it no
    /// longer has to WIN a ranking against the relationship — an address that
    /// can move your tokens right now *and* has twelve transactions with you
    /// now shows both, which the old `lede` could not.
    ///
    /// The rail is STRUCTURAL and not a divider: it connects the dots down one
    /// column, which is why §8's no-hairlines law is intact — nothing here
    /// separates two sections, it joins one sequence.
    ///
    /// **No `Thing` reaches this view tree.** `spineEvents` reduces every row
    /// to value types at the boundary, so the whole SwiftData liveness corollary
    /// chain (1–6) is answered by construction rather than by six guards.
    @ViewBuilder
    private func spine(_ things: [Thing]) -> some View {
        let events = spineEvents(things)
        if !events.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    spineEvent(event, index: index, isLast: index == events.count - 1)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4 + 4)
        }
    }

    /// One event: the rail column, then what it says.
    ///
    /// The rail column takes the row's full height (`maxHeight: .infinity`) so
    /// the line runs from this dot to the next one whatever the content does —
    /// a fixed length would leave a gap under a two-line caption and overshoot
    /// a one-line one, which reads as the spine being broken.
    private func spineEvent(_ event: AddressSpine.Event,
                            index: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dotInk(event))
                    .frame(width: 9, height: 9)
                    .padding(.top, dotDrop(event))
                if !isLast {
                    Rectangle()
                        .fill(DS.fillLine)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            spineContent(event)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, isLast ? 0 : gapBelow(event))
        }
        .fixedSize(horizontal: false, vertical: true)
        // A beat at a time down the spine (prd §171), the cascade the history
        // rows already wore — the spine is longer, so it keeps the same rate
        // rather than compressing.
        .settleIn(delay: 0.05 + Double(index) * 0.04)
    }

    /// The dot's ink says what KIND of event this is, and only that. `attention`
    /// is the one colour on the spine and it is STATE, not identity — the
    /// address's own hue belongs to the face, the copy pill and the verb bar
    /// (prd §443's colour division).
    private func dotInk(_ event: AddressSpine.Event) -> Color {
        switch event {
        case .standing:            return DS.attention
        case .transfer:            return DS.textSecondary
        case .fold, .root:         return DS.textTertiary
        }
    }

    /// Where the dot sits against the first line of its content — optical, and
    /// different per event because the first line is a different rung.
    private func dotDrop(_ event: AddressSpine.Event) -> CGFloat {
        if case .standing = event { return 5 }
        return 6
    }

    private func gapBelow(_ event: AddressSpine.Event) -> CGFloat {
        if case .standing = event { return DS.Space.s6 }
        return DS.Space.s4
    }

    @ViewBuilder
    private func spineContent(_ event: AddressSpine.Event) -> some View {
        switch event {
        case .standing(let standing):  standingContent(standing)
        case .transfer(let transfer):  transferContent(transfer)
        case .fold(let line, let total): foldContent(line: line, total: total)
        case .root(let eyebrow, let sentence): rootContent(eyebrow: eyebrow,
                                                           sentence: sentence)
        }
    }

    /// WHAT THIS ADDRESS CAN MOVE RIGHT NOW (prd §372), as the head of the
    /// spine rather than a card competing with the relationship (prd §446).
    ///
    /// Four states and three of them are absences that must not be confused:
    /// the read hasn't answered (`nil` — no event at all, since we cannot claim
    /// an exposure we have not read), it answered with no live grants (no
    /// event: an address that can move nothing is the overwhelmingly common
    /// case and a green "nothing to worry about" panel on every contact is
    /// chrome), it answered with grants nobody could price (the caption, no
    /// figure), and it answered with a real figure.
    ///
    /// Every number is §292's and none is recomputed here, so this card and the
    /// approvals card can never state the same grant two ways.
    private func standingContent(_ standing: AddressSpine.Standing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Standing · now")
                .dsText(.label12).foregroundStyle(DS.attention)
            if let figure = standing.figure {
                Text(figure)
                    .dsText(.stat24).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .padding(.top, DS.Space.s1)
            }
            Text(standing.caption)
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)
        }
        .accessibilityElement(children: .combine)
    }

    /// One transfer. The verb leads and the stamped amount trails, per
    /// `AddressHistoryRow` — and the amount is UNSIGNED here (prd §446): the
    /// verb is eight points to its left saying `Sent`, so a `−` beside it
    /// states direction twice, and it wears no state colour because green on
    /// an inbound transfer congratulates you for being paid back and
    /// congratulates you identically for being dusted (§443).
    private func transferContent(_ transfer: AddressSpine.Transfer) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(transfer.lead)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                    // The rename cascade (see `rename(to:)`) — each event picks
                    // up the new name a beat after the one above it.
                    .contentTransition(.opacity)
                    .animation(DS.Motion.standard.delay(Double(transfer.cascadeStep) * 0.06),
                               value: renameCascade)
                Text(AddressSpine.meta(transfer.date, walletName: transfer.walletName))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: DS.Space.s2)
            if let amount = transfer.amount {
                Text(amount)
                    .dsText(.mono13).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// What the preview hid, and the door to all of it.
    private func foldContent(line: String, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(line)
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            Spacer(minLength: DS.Space.s2)
            NavigationLink {
                AddressHistoryScreen(entry: current)
            } label: {
                Text("See all \(total)")
                    .dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(DS.tint)
                    .contentShape(Rectangle())
                    .dsTapTarget()
            }
            .buttonStyle(.plain)
            .dsHover()
        }
    }

    /// The oldest thing the app honestly knows — where the relationship starts.
    private func rootContent(eyebrow: String, sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            Text(sentence)
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Building the spine

    /// Every event, off the ONE fetch the body already made.
    ///
    /// `.isLive` at this boundary and nowhere below it: the reduction hands
    /// back value types, so no `Thing` survives into the view tree and there is
    /// nothing downstream for a delete to invalidate.
    private func spineEvents(_ things: [Thing]) -> [AddressSpine.Event] {
        let live = things.filter(\.isLive)
        let names = walletNames()
        let subject = AddressBook.key(for: current.address)
        let hidden = BalancePrivacy.shared.hidden
        let transfers = live.enumerated().map { index, thing -> AddressSpine.Transfer in
            let parts = AddressHistoryRow.parts(direction: thing.transferDirection,
                                                amount: thing.transferAmount,
                                                fallbackTitle: WalletValue.title(thing),
                                                hidden: hidden,
                                                mask: BalancePrivacy.mask)
            return AddressSpine.Transfer(id: thing.id.uuidString,
                                         date: thing.capturedAt,
                                         lead: parts.lead,
                                         amount: parts.amount,
                                         walletName: sideOfMine(thing, subject: subject,
                                                                names: names),
                                         cascadeStep: index)
        }
        return AddressSpine.events(standing: standing(),
                                   transfers: transfers,
                                   total: transfers.count,
                                   root: root(transfers))
    }

    /// Your watched wallets by identity key — built ONCE per pass rather than
    /// searched per row, since a hundred-row history would otherwise walk the
    /// watch list a hundred times to answer the same five questions.
    ///
    /// **Empty below two watched wallets**, which is `AddressConnections`' own
    /// floor and §444's: with one wallet every counterparty reaches it by
    /// definition, so naming it on every line states a fact that is true of
    /// every address in the book and says nothing about this one.
    private func walletNames() -> [String: String] {
        let watched = WalletStore.shared.addresses
        guard watched.count > 1 else { return [:] }
        var map: [String: String] = [:]
        for wallet in watched {
            map[AddressBook.key(for: wallet.address)] =
                wallet.label.isEmpty ? wallet.short : wallet.label
        }
        return map
    }

    /// Which of YOUR wallets was on the other side of this row.
    ///
    /// Only `Wallet` rows count: Peer and Privacy Pools stamp `walletAddress`
    /// with the SUBJECT's own address (see `AddressActivity.key`), so counting
    /// those would caption a fill with the name of the address you are looking
    /// at. A self-transfer is dropped for the reason `walletLegs` always
    /// dropped it — a wallet that transferred to itself is not somebody it
    /// dealt with.
    private func sideOfMine(_ thing: Thing, subject: String,
                            names: [String: String]) -> String? {
        guard !names.isEmpty, thing.source == "Wallet",
              let owner = thing.walletAddress, !owner.isEmpty else { return nil }
        let key = AddressBook.key(for: owner)
        guard key != subject else { return nil }
        return names[key]
    }

    /// The standing permission, or nothing.
    ///
    /// The figure is `WalletValue.exactMoney` — the §374-gated formatter — and
    /// it is applied HERE rather than inside `AddressSpine` precisely so
    /// `hide-balances-audit.py` can see the gate at the call site.
    private func standing() -> AddressSpine.Standing? {
        guard let exposure, !exposure.isEmpty else { return nil }
        let grants = exposure.all.map {
            (stateLine: $0.stateLine, granted: $0.grantedAt, priced: $0.usd != nil)
        }
        return AddressSpine.Standing(
            figure: exposure.priced.isEmpty ? nil : WalletValue.exactMoney(exposure.total),
            caption: AddressSpine.standingCaption(grants))
    }

    /// Where the relationship starts.
    ///
    /// A named entry roots on the day you named it; an entry still standing
    /// under a placeholder the app minted roots on the day it turned up. An
    /// address reached through a door and never added (the connections card's
    /// nodes became doors, §295 follow-up) has no `addedAt` worth printing —
    /// it would say "named today" about an address nobody named — so it roots
    /// on its history or on nothing at all.
    private func root(_ transfers: [AddressSpine.Transfer]) -> AddressSpine.Root {
        if isInBook, !unnamed { return .named(at: current.addedAt,
                                              provenance: current.provenance) }
        if let oldest = transfers.last {
            return .appeared(at: oldest.date, walletName: oldest.walletName)
        }
        if isInBook { return .unnamed(at: current.addedAt) }
        return .none
    }

    // MARK: - The invitation

    /// WHY NAMING IS WORTH DOING, said where it applies (prd §446).
    ///
    /// `rename(to:)`'s own header has said for a year that a name "rewrites
    /// every transaction you've ever had with this address, all at once, and
    /// that is the entire argument for naming anything" — and the card never
    /// once said it to the person standing on it. It appears only while the
    /// address is still wearing a placeholder, which is exactly when the
    /// argument is live; once it carries a real name this would be a panel
    /// explaining a decision already made.
    @ViewBuilder
    private var nameNudge: some View {
        if unnamed, !editingName {
            VStack(alignment: .leading, spacing: 2) {
                Text("Give them a name")
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                Text("It rewrites every transaction you have with this address, everywhere in the app.")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s6)
            .settleIn(delay: 0.14)
        }
    }

    // MARK: - The door out

    /// The door out, per family (2026-08-01). It used to be Etherscan or
    /// nothing — the refusal was right (a Solana address on Etherscan is a
    /// dead link) but the conclusion wasn't: the fix for a wrong explorer is
    /// the right explorer. Each family gets the one that can actually serve it,
    /// and an address belonging to none still gets no door.
    ///
    /// Bitcoin is checked BEFORE Solana: a legacy/P2SH Bitcoin address is
    /// base58-shaped too and occupies the same band `SNS.isAddress` accepts —
    /// the same ordering trap the manager's own `watch()` pays for.
    private var explorerLink: (label: String, url: URL)? {
        let address = current.address
        // Ethereum routes through the chain table `WalletIngest` already
        // owns, so the host lives in exactly one place (`WalletSafety` reads
        // it the same way) rather than being spelled again here.
        if ENS.isHexAddress(address),
           let string = WalletIngest.explorerAddressURL(forNetwork: "eth-mainnet",
                                                        address: address),
           let url = URL(string: string) {
            return (String(localized: "View on Etherscan"), url)
        }
        if BitcoinAddress.isAddress(address),
           let url = URL(string: "https://mempool.space/address/\(address)") {
            return (String(localized: "View on mempool.space"), url)
        }
        // Solana is spelled out rather than routed through the chain table:
        // Solscan's address pages are `/account/`, so the table's `/tx/` →
        // `/address/` rewrite would build a dead link.
        if SNS.isAddress(address),
           let url = URL(string: "https://solscan.io/account/\(address)") {
            return (String(localized: "View on Solscan"), url)
        }
        return nil
    }

    // MARK: - The verb

    // `watchPillShown` retired here 2026-08-24 (prd §461) with the watch verb
    // itself. It answered "does this address have a watch decision at all",
    // which is a question this card no longer asks: watching is membership of
    // the roster on `WalletScreen`, not a property of a person, and a card in
    // the book is a reading surface — the one thing it must not do is change
    // what the app fetches.

    /// Whether the pinned bar is drawn at all.
    ///
    /// Naming is available for EVERY kind, including machinery: a contract you
    /// deal with is worth calling "Uniswap router", and `rename` rewrites its
    /// landed titles exactly the same way. So the bar is now exactly the naming
    /// verb, and it is drawn precisely when there is a name missing.
    private var bottomBarShown: Bool {
        if editingName { return false }
        return unnamed
    }

    /// THE VERB THIS SCREEN NEVER HAD (prd §435), PINNED (prd §443), and
    /// ANSWERING THE SCREEN'S OWN STATE (prd §446).
    ///
    /// The address card is where you decide what an address is to you — it
    /// carries the name, the groups, the live approvals, the whole history —
    /// and §435 finally gave it the one decision that changes anything. It
    /// then put that decision mid-scroll, so by the time the history had
    /// finished making the case for watching, the verb was off screen. A
    /// pinned bar keeps it at thumb height for the whole argument.
    ///
    /// **§446 gave the bar a second verb, because the most common card in the
    /// book is one where watching is not the thing to do.** An address that
    /// turned up in a transfer yesterday, has no name and has nothing to
    /// report is the overwhelmingly common case; the watch list is capped at
    /// five, so four out of five of these will never take that verb, while
    /// naming is free, immediate, and rewrites every row you have with them.
    /// So an unnamed address's bar names it and watching moves to the overflow
    /// menu — one verb in one place, never the same setting in two.
    ///
    /// It is not drawn AT ALL while the name field is open: the field IS the
    /// verb then, and a bar under the keyboard repeating it is the dead
    /// control §83 bans wearing a full-width tint.
    ///
    /// Three watch states and no dead control (§83). Watching offers to stop;
    /// not-watching offers to start; at the cap it says so plainly and stays
    /// inert rather than raising an alert that repeats a fact it could have
    /// printed. A CONTRACT gets no watch bar: `WalletStore` can technically
    /// watch one, but a contract has no holdings and no feed of its own, so
    /// offering it would be an invitation to spend one of five slots on
    /// nothing.
    ///
    /// It wears the APP TINT, like every other call to action in the app.
    /// It used to wear the address's own hue on the reasoning that at this
    /// size a tinted button IS the person; the ruling that removed the pour
    /// took that with it (2026-08-22). A per-address colour on a control says
    /// nothing a person can act on, and at full width it read as a brand.
    @ViewBuilder
    private var bottomBar: some View {
        if bottomBarShown {
            barButton(String(localized: "Name this address"), filled: true,
                      enabled: true,
                      accessibility: String(localized: "Name this address")) {
                beginRename()
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s2)
            // INK, not glass (2026-08-22, user ruling). `.ultraThinMaterial`
            // over a dark sheet renders as a lighter grey slab, so the bar
            // announced itself with a hard edge against the black above it —
            // §8's no-lines law broken by a material rather than by a stroke.
            // The page's own ink separates it from nothing, which is the
            // point: the bar is part of the sheet, not a layer over it.
            .background(DS.themedPage)
        }
    }

    // `watchBarButton` retired here 2026-08-24 (prd §461). §443 pinned the
    // watch verb at thumb height so the history could make its case for it, and
    // §446 gave the bar a second verb because most cards are ones where naming
    // is the thing to do. Both readings survive; the verb does not. Watching is
    // the roster's membership now, so this card's bar is the naming verb alone
    // — which is why `barButton`'s `filled`/`enabled` parameters have one caller
    // and are kept anyway: they are the shape's own contract, not a switch this
    // file happens to use twice.
    /// The bar's one shape.
    private func barButton(_ label: String, filled: Bool, enabled: Bool,
                           accessibility: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .dsText(.heading17)
                .foregroundStyle(filled ? .white : DS.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: DS.Hit.min + 6)
                .background(filled ? AnyShapeStyle(DS.tint) : AnyShapeStyle(DS.fillFaint),
                            in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(!enabled)
        .accessibilityLabel(Text(accessibility))
    }

    // `isWatching` / `watchMenuItem` / `toggleWatch` retired here 2026-08-24
    // (prd §461). The whole watch decision left this card with the star: a book
    // entry is somebody you have dealt with, and what the app READS is the
    // five-slot roster on `WalletScreen`. Nothing on a reading surface changes
    // what gets fetched any more, which is the property that finally separated
    // these two screens rather than relocating the crossing.

    /// Naming, and the history catching up (2026-08-01).
    ///
    /// **The moment this card was missing.** A name isn't a label on one row —
    /// it rewrites every transaction you've ever had with this address, all at
    /// once, and that is the entire argument for naming anything. The card
    /// already had those transactions on screen and changed them silently, so
    /// the one thing worth seeing happened invisibly.
    ///
    /// `renameCascade` is bumped after the rewrite lands; the history rows
    /// stagger their cross-fade off it (see `historyRow`), so the change reads
    /// as sweeping down the list rather than as a redraw. Nothing is claimed
    /// if nothing changed: a rename that rewrote no titles simply doesn't
    /// cascade — which since §443 includes every row the card split, since a
    /// split row has no counterparty clause left to rewrite.
    private func rename(to name: String) {
        book.setName(name, for: entry.address)
        let changed = CounterpartyRetitle.applyCurrentName(for: entry.address,
                                                           in: modelContext)
        DSHaptic.success()
        guard changed > 0 else { return }
        withAnimation(DS.Motion.standard) { renameCascade += 1 }
    }
}

/// The whole of an address's history — the "See all" drill-down from the
/// card's own six-row preview (`AddressCard.historySection`). Same fetch, no
/// cap; a push, not a sheet, since it's a closer look at data the card
/// already showed a slice of, not a new top-level surface.
struct AddressHistoryScreen: View {
    let entry: AddressBook.Entry
    @Environment(\.modelContext) private var modelContext

    private var history: [Thing] {
        AddressActivity.history(for: entry.address, in: modelContext)
    }

    /// The history in month buckets, newest first — headers the CARD
    /// deliberately does not draw (2026-08-22, prd §443).
    ///
    /// The card's six rows each carry their own date in the trailing slot, so
    /// a header there would say it twice; at two hundred rows a header is the
    /// only thing that makes the list scannable, so this is not an
    /// inconsistency between the two surfaces but the same rule answered at
    /// two different lengths.
    ///
    /// `.live` at the boundary, per corollary 4 — this hands arrays onward.
    private var months: [(key: Date, rows: [Thing])] {
        var order: [Date] = []
        var buckets: [Date: [Thing]] = [:]
        let calendar = Calendar.current
        for thing in history where thing.isLive {
            let month = calendar.date(from: calendar.dateComponents([.year, .month],
                                                                    from: thing.capturedAt))
                ?? thing.capturedAt
            if buckets[month] == nil { order.append(month) }
            buckets[month, default: []].append(thing)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(months, id: \.key) { month in
                Section {
                    // `.keyed` per the CLAUDE.md rule against keying a ForEach
                    // on a derived array of raw `Thing` refs — see
                    // `ThingRowKeying.swift`.
                    ForEach(month.rows.keyed) { row in
                        // Corollary 3 (build 176) — see `ThingRowKeying`.
                        if let thing = row.live {
                            HStack(spacing: DS.Space.s3) {
                                KindGlyph(kind: thing.kind, size: 26)
                                // The FULL title here, counterparty clause and
                                // all — unlike the card, this screen is not
                                // itself the counterparty, and it is where
                                // §441's rename cascade keeps a stage.
                                Text(WalletValue.title(thing)).dsText(.subhead13)
                                    .foregroundStyle(DS.textPrimary).lineLimit(2)
                                Spacer(minLength: DS.Space.s2)
                                Text(thing.capturedAt.formatted(.dateTime.month(.abbreviated).day()))
                                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } header: {
                    Text(month.key.formatted(.dateTime.month(.wide).year()))
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .textCase(nil)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// Publishes a flight anchor only when there is one to publish (prd §441).
///
/// Shared with the filing sheet since §444, where the head's key is derived
/// from the flight in progress and is therefore nil most of the time.
///
/// A modifier rather than an `if` in the view body: branching there would give
/// the mark two different identities depending on whether the screen it is on
/// has a shelf, which churns the row on every re-render.
struct OptionalFlightAnchor: ViewModifier {
    let key: String?
    func body(content: Content) -> some View {
        if let key { content.flightAnchor(key) } else { content }
    }
}
