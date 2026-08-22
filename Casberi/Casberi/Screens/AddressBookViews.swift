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
    /// no resolved kind and no provenance — the short form comes back rather
    /// than the line going empty. That case really has nothing else to say,
    /// and it is the one shape this fix does not improve: it is the behaviour
    /// that shipped, not a regression, and it resolves itself the moment the
    /// address gains a transaction or `AddressKind` answers. Absent would be
    /// better (`AddressCard.summaryLine`'s "stays absent rather than printing
    /// an empty line") and needs the caller to handle a nil, which is a change
    /// in a file another pass is currently rewriting — worth doing, not worth
    /// entangling this with.
    /// `activity` gained its DATE on 2026-08-22 (prd §440). "12 together"
    /// reads identically whether the last of those twelve was on Tuesday or
    /// in 2023, so the count alone could not separate a correspondent from a
    /// stranger — which is the distinction a book of forty is read for. The
    /// phrase is `AddressBookShape.lastPhrase`'s, stated only when there is a
    /// count to attach it to: a date with no dealings behind it would be
    /// describing something the count says didn't happen.
    func subline(activity: AddressActivity.Summary?) -> String {
        var parts: [String] = []
        if !WalletStore.isAutoName(name, for: address) { parts.append(short) }
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
        return parts.isEmpty ? short : parts.joined(separator: " · ")
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
    /// Publishes the MARK's frame as a star-flight endpoint (prd §441). nil
    /// where there is no flight to launch — the group screen's rows.
    var markAnchor: String?
    /// nil draws no star at all — see the note above.
    var onToggleWatch: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            AddressMark(entry: entry, size: DS.Face.list)
                .modifier(OptionalFlightAnchor(key: markAnchor))
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
                // RELATIONSHIP facts, never money (§435).
                Text(entry.subline(activity: activity))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
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
        DSTray(title: "New group", height: 660) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Deleting a group never deletes an address.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                nameField
                if let existing = matchingGroup {
                    note(String(localized: "You already have “\(existing)” — these get added to it."))
                }
                if book.count > 8 { filterField }
                list
                createButton
            }
        }
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
            withAnimation(DS.Motion.standard) {
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
                .frame(height: 48)
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
    let address: String
    var expanded = false
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
                if expanded {
                    Text(copied ? "Copied" : "Copy")
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(copied ? DS.confirm : DS.tint)
                } else {
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
        // and its object; the expanded form's own word ("Copy") says less.
        .dsTooltip(copied ? String(localized: "Address copied")
                          : String(localized: "Copy address"))
    }
}

/// One address's aggregate stats — count, span, and per-token net flow, built
/// once from the card's own `history` array (already the COMPLETE matching
/// set; the card's six-row list is a display slice of it, not a fetch limit).
struct HistorySummary {
    let count: Int
    let firstDate: Date?
    let lastDate: Date?
    /// Native-unit net flow, largest magnitude first. No USD figure: `Thing`
    /// carries no per-transaction USD field — only a portfolio-level snapshot
    /// exists (`WalletStore.ValueSample`) — so inventing one here would be
    /// exactly the fabricated status the honesty rule forbids.
    let netByToken: [(symbol: String, net: Double)]

    init(_ things: [Thing]) {
        count = things.count
        let dates = things.map(\.capturedAt)
        firstDate = dates.min()
        lastDate = dates.max()
        var sums: [String: Double] = [:]
        var order: [String] = []
        for thing in things {
            guard let amountText = thing.transferAmount,
                  let (magnitude, symbol) = Self.parse(amountText) else { continue }
            let signed = thing.transferDirection == "sent" ? -magnitude : magnitude
            if sums[symbol] == nil { order.append(symbol) }
            sums[symbol, default: 0] += signed
        }
        netByToken = order.map { ($0, sums[$0] ?? 0) }.sorted { abs($0.net) > abs($1.net) }
    }

    /// "0.9962 ETH" → (0.9962, "ETH") — the only shape `transferAmount`
    /// carries (a formatted display string, not a numeric+symbol pair).
    /// Unparseable strings return nil and are excluded from the net line
    /// without suppressing the count — a parse miss must never hide the rest
    /// of the summary.
    private static func parse(_ text: String) -> (Double, String)? {
        let parts = text.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        return (value, String(parts[1]))
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
    @Environment(BridgeStore.self) private var bridges
    private var book = AddressBook.shared
    @State private var renaming = false
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
                VStack(spacing: 0) {
                    identityHeader
                    lookalikeBand
                    lede
                    historySection
                    detailsList
                    // Room for the pinned verb bar. `DS.Hit.min` plus the
                    // bar's own padding — spelled from the token so the two
                    // cannot drift apart.
                    Color.clear.frame(height: watchPillShown ? DS.Hit.min + 46 : DS.Space.s4)
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
            .safeAreaInset(edge: .bottom, spacing: 0) { watchBar }
            .alert("Name this address", isPresented: $renaming) {
                TextField("Name", text: $nameDraft)
                Button("Save") { rename(to: nameDraft) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A blank name removes it from your book.")
            }
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
    /// The pour is EXACTLY the §171/§435 recipe and deliberately unchanged: it
    /// is the app's §129 idiom (a screen whose subject IS the thing wears its
    /// colour), shared with the app-detail page, the bridge setup header, the
    /// token quick sheet and the money receipt card. Deepening it into a
    /// coloured header BAND was tried and rejected — a wash belongs to the
    /// page, a band belongs to a different app.
    private var identityHeader: some View {
        VStack(spacing: 0) {
            AddressMark(entry: current, size: DS.Face.profile)
            Text(current.name)
                .dsText(.heading28).foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                // The NAME reveal (2026-08-01) — `AddressMark`'s kind
                // turn-over (prd §171) applied to the other half of the
                // question. An address added bare stands under its own short
                // form; a beat later reverse ENS answers, or a typed `.eth`
                // resolves and `reconcileAliases` re-keys the row, and the
                // card learns what to call it while you are looking at it.
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .id(current.name)
                .animation(DS.Motion.standard, value: current.name)
                .padding(.top, DS.Space.s3)
            Text(kindLine)
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .padding(.top, 1)
            bitcoinVintageLine
            addressChip
                .padding(.top, DS.Space.s3)
            groupChips
                .padding(.top, DS.Space.s2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s4)
        .background(alignment: .top) {
            LinearGradient(stops: [
                .init(color: pourHue.opacity(0.40), location: 0),
                .init(color: pourHue.opacity(0.12), location: 0.45),
                .init(color: pourHue.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
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
            Button {
                nameDraft = current.name
                renaming = true
            } label: { Label("Rename", systemImage: "pencil") }
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

    /// The address, as one chip under the name (prd §435).
    ///
    /// **It still shows every character**, middle-truncated rather than
    /// clipped, because the one screen that exists to tell two look-alike
    /// addresses apart cannot be the screen that hides their difference —
    /// `lookalikeBand` below prints both in full for exactly that reason.
    private var addressChip: some View {
        HStack(spacing: DS.Space.s2) {
            Text(current.address)
                .dsText(.mono13).foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            CopyAddressButton(address: current.address, expanded: true)
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
        .background(DS.fillFaint, in: Capsule(style: .continuous))
        .padding(.horizontal, DS.Space.s4)
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
    /// (2026-08-01), as a FIELD rather than a card (prd §443).
    ///
    /// A card is a container of information and this is a CONDITION of the
    /// screen, so it takes the full width and its own ground — the one thing
    /// on the sheet that cannot be mistaken for another widget in the stack.
    /// Both addresses print in full and un-truncated, which is the only form
    /// of this warning anyone can act on.
    ///
    /// It says what the app knows and stops. It does NOT accuse either side of
    /// being the impostor: the book cannot know which one you meant, and a
    /// wrong accusation on a security notice is worse than none.
    @ViewBuilder
    private var lookalikeBand: some View {
        let twins = book.lookalikes(of: current.address)
        if !twins.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .dsGlyph(14)
                        .foregroundStyle(DS.destructive)
                    Text("Another address looks just like this one")
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                }
                Text("Same short form, different address. Compare every character before you copy.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("This one")
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                        Text(current.address)
                            .dsText(.mono13).foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(twins) { twin in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(twin.name)
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                            Text(twin.address)
                                .dsText(.mono13).foregroundStyle(DS.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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

    // MARK: - The lede

    /// The one reading this screen leads with — RANKED, never stacked
    /// (2026-08-22, prd §443).
    ///
    /// A standing permission outranks a record: an address that can move your
    /// tokens right now is the sentence that has to be read first, and the
    /// count of what you have done together steps down to its own section
    /// header. Displaced, never dropped. It is the same ordering by
    /// consequence every room head in the app already uses
    /// (`sourceHead` → `topicMap` → `leaderboard`), and it is why these are
    /// one `@ViewBuilder` rather than two independent sections that would
    /// otherwise both claim the top of the page.
    @ViewBuilder
    private var lede: some View {
        if let exposure, !exposure.isEmpty {
            exposureLede(exposure)
        } else {
            relationshipLede
        }
    }

    /// WHAT THIS ADDRESS CAN MOVE RIGHT NOW (2026-08-13, prd §372), as the
    /// page's lede rather than a card in the stack (prd §443).
    ///
    /// Four states, and three of them are absences that must not be confused:
    /// the read hasn't answered (`nil` — the relationship leads, since we
    /// cannot claim an exposure we have not read), it answered and there are
    /// no live grants (the relationship leads: an address that can move
    /// nothing is the overwhelmingly common case and a green
    /// "nothing to worry about" panel on every contact is chrome), it answered
    /// with grants nobody could price (rows and the footnote, no figure —
    /// `unpricedNote` carries this), and it answered with a real figure.
    ///
    /// §292 owns every number here and none is recomputed: `stateLine`,
    /// `money`, `unpricedNote` and the priced-first row order all come from
    /// the shared type, so this card and the approvals card can never state
    /// the same grant two ways.
    ///
    /// The headline is deliberately NOT `WalletApprovalExposure.headline`,
    /// which counts spenders ("3 spenders can move $8,924") — there is exactly
    /// one spender here and it is the hero at the top of the screen, so
    /// counting it would print "1 spender" under its own name.
    @ViewBuilder
    private func exposureLede(_ exposure: WalletApprovalExposure) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s1 + 2) {
                Image(systemName: "lock.open.fill")
                    .dsGlyph(12)
                    .foregroundStyle(DS.attention)
                Text("They can move your tokens right now")
                    .dsText(.label12).foregroundStyle(DS.attention)
            }
            // Only when something could actually be priced. A total of $0
            // printed over unpriceable grants is the "never 0 standing in
            // for unknown" rule the arithmetic already keeps.
            if !exposure.priced.isEmpty {
                Text(WalletValue.exactMoney(exposure.total))
                    .dsText(.stat24).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .padding(.top, DS.Space.s1)
            }
            if let note = exposure.unpricedNote {
                Text(note)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
            VStack(spacing: 0) {
                ForEach(exposure.all) { grant in
                    HStack(spacing: DS.Space.s3) {
                        Text(grant.stateLine)
                            .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        // An unpriceable grant says so rather than showing a
                        // blank, which reads as nothing at stake.
                        Text(grant.usd.map(WalletValue.exactMoney)
                             ?? String(localized: "not priced"))
                            .dsText(.subhead13)
                            .foregroundStyle(grant.usd == nil ? DS.textTertiary : DS.textSecondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, DS.Space.s3 + 2)
                    .padding(.vertical, DS.Space.s3)
                }
            }
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
            .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4 + 5)
        .settleIn(delay: 0.05)
    }

    /// How much you two have dealt, and over how long — the one reading this
    /// screen owns and no other surface in the app states (prd §443).
    ///
    /// **It is not a balance and §435 is intact.** That ruling struck every
    /// USD total off the manager because the Wallet feed's crown card owns the
    /// money reading once; this is a COUNT of the corpus's own rows plus the
    /// native-unit net the summary already computed, neither of which is a
    /// holding and neither of which is stated anywhere else.
    ///
    /// The empty case is a sentence, not a zero. "0 transactions" at
    /// `stat24` is a zero dressed as a reading, and the state is the most
    /// common one there is — the moment right after you name an address, which
    /// is usually the moment right before you watch it. Silently omitting the
    /// section (what shipped) reads as the screen being broken; one quiet line
    /// says the app looked.
    @ViewBuilder
    private var relationshipLede: some View {
        let things = history
        VStack(alignment: .leading, spacing: 0) {
            if things.isEmpty {
                VStack(spacing: 2) {
                    Text("No history together yet")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    Text("Transfers between your wallets and this address will show here.")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            } else {
                let summary = HistorySummary(things)
                Text("Your history together")
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                Text("^[\(things.count) transaction](inflect: true)")
                    .dsText(.stat24).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .padding(.top, DS.Space.s1)
                if let line = summaryLine(for: summary) {
                    Text(line)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .padding(.top, 1)
                }
                // HOW FAR BACK YOU TWO GO (2026-08-20, prd §417). The rows
                // below are newest-first and answer WHAT; they are silent on
                // span, so a monthly habit and a single touch in 2024 read
                // identically until you reach the last row — and the card only
                // ever shows six. The rail is the journal room's span reading
                // (§398) applied to an address.
                //
                // Every dot the same size, no colour, no rate: the
                // `AddressConnections` factual-only ruling, on the screen where
                // you decide whether to trust somebody. It draws the WHOLE
                // history, not the six rows shown, or the strip would describe
                // the preview instead of the relationship.
                WalletRunwayRail(dates: things.compactMap { $0.isLive ? $0.capturedAt : nil },
                                 sense: .behind)
                    .padding(.top, DS.Space.s3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4 + 5)
    }

    /// "since Mar 3 · net −0.80 ETH" — the two facts a count alone can't say.
    /// Only the fields that resolved to something real appear; a summary
    /// with nothing to add stays absent rather than printing an empty line.
    private func summaryLine(for summary: HistorySummary) -> String? {
        var parts: [String] = []
        if let first = summary.firstDate {
            parts.append(String(localized: "since \(first.formatted(.dateTime.month(.abbreviated).day()))"))
        }
        if !summary.netByToken.isEmpty {
            let shown = summary.netByToken.prefix(2).map { token -> String in
                let sign = token.net < 0 ? "−" : "+"
                // The SIGN survives the mask, the figure doesn't: which way the
                // relationship ran is not a balance, and dropping it would
                // leave "net •••• ETH" saying less than the row above already
                // says (prd §374).
                return BalancePrivacy.shared.hidden
                    ? "\(sign)\(BalancePrivacy.mask) \(token.symbol)"
                    : "\(sign)\(Self.formatAmount(abs(token.net))) \(token.symbol)"
            }
            var netText = "net " + shown.joined(separator: ", ")
            let remaining = summary.netByToken.count - 2
            if remaining > 0 {
                netText += " " + String(localized: "+\(remaining) more")
            }
            parts.append(netText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func formatAmount(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }

    // MARK: - The record

    /// Your history with this address, as a LIST rather than a card
    /// (2026-08-22, prd §443).
    ///
    /// Three things changed and each has its own reason. The rows are
    /// full-width and uncontained — a record is a list, and wrapping a list in
    /// a rounded rectangle makes it a widget ABOUT a list. The verb leads and
    /// the stamped amount trails (see `AddressHistoryRow`, which owns that
    /// split and is harness-proven), so direction reads down one edge instead
    /// of being buried mid-sentence at six horizontal positions. And there are
    /// no month headers: every row now carries its own date in the trailing
    /// slot, so a header would state it twice. The "See all" screen keeps its
    /// headers — at two hundred rows they earn their place.
    ///
    /// When the relationship is empty this draws nothing at all: the lede
    /// above has already said so in a sentence, and a second empty section
    /// under it would say it twice.
    @ViewBuilder
    private var historySection: some View {
        let things = history
        if !things.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(Array(things.prefix(6)).keyed.enumerated()), id: \.element.id) { i, row in
                    // Corollary 3 (build 176) — see `ThingRowKeying`.
                    if let thing = row.live {
                        historyRow(thing, index: i)
                    }
                }
                if things.count > 6 {
                    NavigationLink {
                        AddressHistoryScreen(entry: current)
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            Text("See all \(things.count)")
                                .dsText(.subhead13).fontWeight(.semibold)
                                .foregroundStyle(DS.tint)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .dsGlyph(11)
                                .foregroundStyle(DS.textTertiary)
                        }
                        .contentShape(Rectangle())
                        .dsTapTarget()
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                    .padding(.top, DS.Space.s3)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4 + 9)
        }
    }

    /// One row. The amount wears the plain text ramp and NO state colour —
    /// green on an inbound transfer congratulates you for being paid back and
    /// congratulates you identically for being dusted by a stranger. On this
    /// screen direction is a fact, not a verdict (prd §443).
    private func historyRow(_ thing: Thing, index: Int) -> some View {
        let parts = AddressHistoryRow.parts(direction: thing.transferDirection,
                                            amount: thing.transferAmount,
                                            fallbackTitle: WalletValue.title(thing),
                                            hidden: BalancePrivacy.shared.hidden,
                                            mask: BalancePrivacy.mask)
        return HStack(alignment: .top, spacing: DS.Space.s3) {
            KindGlyph(kind: thing.kind, size: 26)
            Text(parts.lead)
                .dsText(.subhead13)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                // The rename cascade (see `rename(to:)`) — each row picks up
                // the new name a beat after the one above it. It still runs
                // for every row that keeps a full sentence; a split row has no
                // counterparty left in it to sweep, which is the stated cost
                // of the split.
                .contentTransition(.opacity)
                .animation(DS.Motion.standard.delay(Double(index) * 0.06),
                           value: renameCascade)
            Spacer(minLength: DS.Space.s2)
            VStack(alignment: .trailing, spacing: 1) {
                if let amount = parts.amount {
                    Text(amount)
                        .dsText(.mono13)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Text(thing.capturedAt.formatted(.dateTime.month(.abbreviated).day()))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, 9)
        // The cascade (prd §171) — the app's own sheet grammar: your history
        // with someone arrives a beat at a time rather than as a slab.
        .settleIn(delay: 0.05 + Double(index) * 0.04)
    }

    // MARK: - Details

    /// The settings-shaped facts, in ONE list with the rows touching
    /// (2026-08-22, prd §443) — where they were two separately shadowed cards
    /// each holding a single row, drawn at exactly the weight the security
    /// notice above them wears.
    private var detailsList: some View {
        VStack(spacing: 0) {
            if isInBook {
                HStack(spacing: DS.Space.s3) {
                    Text("Named").dsText(.callout15).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: 0)
                    Text(current.addedAt.formatted(.dateTime.month(.abbreviated).day()))
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                }
                .padding(.horizontal, DS.Space.s3 + 2)
                .padding(.vertical, DS.Space.s3 + 1)
            }
            explorerRow
        }
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4 + 9)
    }

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

    @ViewBuilder
    private var explorerRow: some View {
        if let link = explorerLink {
            let url = link.url
            Button {
                DSHaptic.tap()
                openURL(url)
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Text(link.label).dsText(.callout15).foregroundStyle(DS.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .dsGlyph(12)
                        .foregroundStyle(DS.textTertiary)
                }
                .padding(.horizontal, DS.Space.s3 + 2)
                .padding(.vertical, DS.Space.s3 + 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
        }
    }

    // MARK: - The verb

    /// Whether this address has a watch decision at all — a CONTRACT does not
    /// (see `watchBar`), so the bar is not drawn and the sheet simply ends.
    private var watchPillShown: Bool {
        switch current.kind {
        case .contract, .safe:                 return false
        case .wallet, .unknown, .smartAccount: return true
        }
    }

    /// THE VERB THIS SCREEN NEVER HAD (prd §435), now PINNED (prd §443).
    ///
    /// The address card is where you decide what an address is to you — it
    /// carries the name, the groups, the live approvals, the whole history —
    /// and §435 finally gave it the one decision that changes anything. It
    /// then put that decision mid-scroll, so by the time the history had
    /// finished making the case for watching, the verb was off screen. A
    /// pinned bar keeps it at thumb height for the whole argument.
    ///
    /// Three states and no dead control (§83). Watching offers to stop;
    /// not-watching offers to start; at the cap it says so plainly and stays
    /// inert rather than raising an alert that repeats a fact it could have
    /// printed. A CONTRACT gets no bar at all: `WalletStore` can technically
    /// watch one, but a contract has no holdings and no feed of its own, so
    /// offering it would be an invitation to spend one of five slots on
    /// nothing — and an empty bar hovering over the sheet would be the dead
    /// control twice over.
    ///
    /// It wears the address's OWN hue, the same one the pour behind it and the
    /// face above it carry, because at this size a tinted button IS the
    /// person. Machinery would borrow the app tint — see `pourHue` — which is
    /// exactly why machinery doesn't get one.
    @ViewBuilder
    private var watchBar: some View {
        if watchPillShown {
            let store = WalletStore.shared
            let watching = store.addresses.contains {
                store.scopeMatches(current.address, scope: $0.address)
            }
            let full = !watching && !store.canWatchMore
            Button {
                toggleWatch(watching: watching)
            } label: {
                Text(watching ? String(localized: "Watching")
                     : full ? String(localized: "Watching \(WalletStore.watchLimit) already")
                     : String(localized: "Watch \(current.name)"))
                    .dsText(.heading17)
                    .foregroundStyle(watching || full ? DS.textSecondary : .white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.Hit.min + 6)
                    .background(watching || full ? AnyShapeStyle(DS.fillFaint)
                                                 : AnyShapeStyle(pourHue),
                                in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(PressSpring())
            .disabled(full)
            .accessibilityLabel(Text(watching ? "Watching \(current.name), tap to stop"
                                              : "Watch \(current.name)"))
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s2)
            // Glass, and no hairline above it — §8's no-lines law has zero
            // exceptions, so the bar is separated from the record by its own
            // material and nothing else.
            .background(.ultraThinMaterial)
        }
    }

    /// Start or stop watching, with the same consequences the book row's star
    /// has always carried — the wallet-riding seats reconciled on the way in
    /// (§207) and this address's landed rows pruned on the way out (§286).
    /// Written once here rather than shared with `WalletScreen.toggleWatch`
    /// because that one also drives the row's promote animation and its cap
    /// alert, neither of which exists on a sheet.
    private func toggleWatch(watching: Bool) {
        DSHaptic.tap()
        let store = WalletStore.shared
        if watching {
            guard let i = store.addresses.firstIndex(where: {
                store.scopeMatches(current.address, scope: $0.address)
            }) else { return }
            let gone = store.addresses[i].address
            withAnimation(DS.Motion.standard) { store.remove(at: IndexSet(integer: i)) }
            FollowPrune.removeWallet(address: gone,
                                     stillWatched: store.addresses.map(\.address),
                                     context: modelContext)
            return
        }
        if case .added = store.outcome(ofAdding: current.address, label: current.name) {
            DSHaptic.success()
            // Watching is consent (§207) — the wallet-riding seats are on the
            // moment a wallet is. `BridgeStore` is an environment object rather
            // than a singleton, so this sheet asks for it by name.
            bridges.reconcileWalletSeats()
        }
    }

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
/// A modifier rather than an `if` in the view body: branching there would give
/// the mark two different identities depending on whether the screen it is on
/// has a shelf, which churns the row on every re-render.
private struct OptionalFlightAnchor: ViewModifier {
    let key: String?
    func body(content: Content) -> some View {
        if let key { content.flightAnchor(key) } else { content }
    }
}
