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
    func subline(activity: Int?) -> String {
        var parts = [short]
        if let activity, activity > 0 {
            parts.append(String(localized: "\(activity) together"))
        }
        // A Bitcoin address's "kind" is its script type (Legacy/P2SH/Native
        // SegWit/Taproot) — a different axis than `kind.label`'s who-vs-
        // machinery question, read straight off the encoding, free
        // (2026-07-27). `kind.label` stays nil for a Bitcoin address (there's
        // no `eth_getCode` to ask), so the two never collide.
        if let label = kind.label { parts.append(label) }
        else if let script = BitcoinAddress.scriptKind(address) { parts.append(script) }
        if let provenance { parts.append(provenance) }
        return parts.joined(separator: " · ")
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
        .buttonStyle(.plain)
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
                WalletFace(address: entry.address, size: size)
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
                        .dsGlyph(12)
                        .foregroundStyle(copied ? DS.confirm : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 9,
                                                                       style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    private var book = AddressBook.shared
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var addingGroup = false
    @State private var groupDraft = ""
    /// Bumped when a rename actually rewrote landed titles — the history rows
    /// stagger their cross-fade off it. See `rename(to:)`.
    @State private var renameCascade = 0

    init(entry: AddressBook.Entry) { self.entry = entry }

    /// Live, so a rename or a kind landing repaints the card.
    private var current: AddressBook.Entry { book.entry(for: entry.address) ?? entry }

    /// The corpus's own record of this address — counterparty transactions
    /// plus its own Peer/Pool activity (see `AddressActivity`), newest first.
    private var history: [Thing] {
        AddressActivity.history(for: entry.address, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.s3) {
                    AddressMark(entry: current, size: 64)
                        .padding(.top, DS.Space.s4)
                    // The NAME reveal (2026-08-01) — `AddressMark`'s kind
                    // turn-over (prd §171) applied to the other half of the
                    // question. An address added bare stands under its own
                    // short form; a beat later reverse ENS answers, or a typed
                    // `.eth` resolves and `reconcileAliases` re-keys the row,
                    // and the card learns what to call it while you're looking
                    // at it. Same transition as the mark beside it, so the two
                    // halves of "what is this" resolve in one visual language.
                    Text(current.name)
                        .dsText(.heading22).foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.center)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .id(current.name)
                        .animation(DS.Motion.standard, value: current.name)
                    Text(kindLine)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    bitcoinVintageLine

                    lookalikeWarning
                    groupRow
                    addressRow
                    historySection
                    explorerRow
                }
                .padding(DS.Space.s4)
            }
            .scrollIndicators(.hidden)
            .dsAdaptiveContentWidth()
            // This address's OWN weather (prd §171, 2026-07-22). §129 kept the
            // wash exactly where the source IS the subject — the app-detail
            // page, the bridge setup header, the token quick sheet — and a
            // person's card is that case precisely: the subject of this screen
            // is an identity, so the screen wears its color. A wallet pours in
            // its face tint (the same hue its identicon, its switcher chip and
            // its band in the combined sheet already carry, so Mom looks like
            // Mom everywhere); machinery pours in Casberi's own tint, because
            // a contract has no identity of its own to borrow.
            .background(alignment: .top) {
                LinearGradient(stops: [
                    .init(color: pourHue.opacity(0.26), location: 0),
                    .init(color: pourHue.opacity(0.08), location: 0.45),
                    .init(color: pourHue.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 320)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .dsPageBackground()
            .navigationTitle("Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rename") {
                        nameDraft = current.name
                        renaming = true
                    }.tint(DS.tint)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(DS.tint)
                }
            }
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
        }
        .presentationBackground(DS.surfaceSheet)
        .dsColorScheme()
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
            let amount = BitcoinBridge.formatAmount(sats: sats)
            if let since = BitcoinBridge.vintage(for: current.address) {
                Text("\(amount) · oldest piece from \(since.formatted(.dateTime.month(.wide).year()))")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(verbatim: amount)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
        }
    }

    private var kindLine: String {
        let kindWord = current.kind.label
            ?? BitcoinAddress.scriptKind(current.address)
            ?? String(localized: "Wallet")
        var parts: [String] = [kindWord]
        if let provenance = current.provenance { parts.append(provenance) }
        parts.append(String(localized: "named \(current.addedAt.formatted(.dateTime.month(.abbreviated).day()))"))
        return parts.joined(separator: " · ")
    }

    /// Naming, and the history catching up (2026-08-01).
    ///
    /// **The moment this card was missing.** A name isn't a label on one row —
    /// it rewrites every transaction you've ever had with this address, all at
    /// once, and that is the entire argument for naming anything. The card
    /// already had those transactions on screen and changed them silently, so
    /// the one thing worth seeing happened invisibly.
    ///
    /// `renameCascade` is bumped after the rewrite lands; the history rows key
    /// their animation off it and cross-fade a beat apart (see
    /// `historySection`), so the change reads as sweeping down the list rather
    /// than as a redraw. Nothing is claimed if nothing changed: a rename that
    /// rewrote no titles (a contract's approvals carry no counterparty clause)
    /// simply doesn't cascade.
    private func rename(to name: String) {
        book.setName(name, for: entry.address)
        let changed = CounterpartyRetitle.applyCurrentName(for: entry.address,
                                                           in: modelContext)
        DSHaptic.success()
        guard changed > 0 else { return }
        withAnimation(DS.Motion.standard) { renameCascade += 1 }
    }

    /// The address(es) already in this book that PRINT the same as this one
    /// (2026-08-01). Shown as a card rather than a glyph because here there is
    /// room to name the twin and show both addresses in full — which is the
    /// only form of this warning that lets someone actually resolve it.
    ///
    /// It says what the app knows and stops. It does NOT accuse either side of
    /// being the impostor: the book cannot know which one you meant, and a
    /// wrong accusation on a security notice is worse than none.
    @ViewBuilder
    private var lookalikeWarning: some View {
        let twins = book.lookalikes(of: current.address)
        if !twins.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .dsGlyph(13)
                        .foregroundStyle(DS.destructive)
                    Text("Another address looks just like this one")
                        .dsText(.body17).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                }
                Text("Same short form, different address. Copy carefully.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(twins) { twin in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(twin.name).dsText(.subhead13).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                        Text(twin.address)
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .monospaced()
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DS.Space.s3)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    /// Which groups this address is filed under, and the door to file it
    /// (2026-08-01). Always present: a card that only showed groups once you
    /// had them would leave the feature discoverable solely by long-pressing a
    /// row, which is where the verb lives but not where anyone looks first.
    private var groupRow: some View {
        let groups = current.groupNames
        return Menu {
            GroupMenuItems(entry: current, groups: book.groupNames) {
                groupDraft = ""
                addingGroup = true
            }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "folder")
                    .dsGlyph(13)
                    .foregroundStyle(DS.textTertiary)
                Text(groups.isEmpty ? String(localized: "Add to a group")
                                    : groups.joined(separator: ", "))
                    .dsText(.callout15)
                    .foregroundStyle(groups.isEmpty ? DS.textSecondary : DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .dsGlyph(10)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        .dsHover()
    }

    private var addressRow: some View {
        HStack(spacing: DS.Space.s3) {
            Text(current.address)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .monospaced()
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            CopyAddressButton(address: current.address, expanded: true)
        }
        .padding(DS.Space.s3)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    @ViewBuilder
    private var historySection: some View {
        let things = history
        if !things.isEmpty {
            let summary = HistorySummary(things)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Your history together · \(things.count)")
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let line = summaryLine(for: summary) {
                    Text(line)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(Array(things.prefix(6)).keyed.enumerated()), id: \.element.id) { i, row in
                    // Corollary 3 (build 176) — see `ThingRowKeying`.
                    if let thing = row.live {
                        HStack(spacing: DS.Space.s3) {
                            KindGlyph(kind: thing.kind, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(thing.title).dsText(.subhead13)
                                    .foregroundStyle(DS.textPrimary).lineLimit(1)
                                    // The rename cascade (see `rename(to:)`) —
                                    // each row picks up the new name a beat
                                    // after the one above it, so a name
                                    // visibly sweeps down your history with
                                    // this address instead of the list simply
                                    // being different afterwards.
                                    .contentTransition(.opacity)
                                    .animation(DS.Motion.standard.delay(Double(i) * 0.06),
                                               value: renameCascade)
                                Text(thing.capturedAt.formatted(.dateTime.month(.abbreviated).day()))
                                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        // The cascade (prd §171) — the app's own sheet grammar,
                        // which this card was missing: your history with someone
                        // arrives a beat at a time rather than as a slab.
                        .settleIn(delay: 0.05 + Double(i) * 0.04)
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
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                    .padding(.top, 2)
                }
            }
            .padding(DS.Space.s3)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
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
                return "\(sign)\(Self.formatAmount(abs(token.net))) \(token.symbol)"
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
                    Text(link.label).dsText(.callout15).foregroundStyle(DS.textSecondary)
                    Image(systemName: "arrow.up.right")
                        .dsGlyph(12)
                        .foregroundStyle(DS.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
            .dsHover()
        }
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

    var body: some View {
        List {
            // `.keyed` per the CLAUDE.md rule against keying a ForEach on a
            // derived array of raw `Thing` refs — see `ThingRowKeying.swift`.
            ForEach(history.keyed) { row in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = row.live {
                    HStack(spacing: DS.Space.s3) {
                        KindGlyph(kind: thing.kind, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(thing.title).dsText(.subhead13)
                                .foregroundStyle(DS.textPrimary).lineLimit(1)
                            Text(thing.capturedAt.formatted(.dateTime.month(.abbreviated).day().year()))
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
