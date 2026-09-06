import SwiftUI
import SwiftData

/// ONE account page for every bridge (prd §639, 2026-09-06) — the chassis
/// `BridgeSetupPage` was, rebuilt to the anatomy the user ruled over four
/// mockups, and the first surface of the account-manager direction.
///
/// Top to bottom, all on the page background, no cards and no slab fills —
/// the only filled element is the input field:
///
/// 1. **Header**, centered and airy: the brand mark, the name as display
///    text, one state line with a dot ("Reading · 8m ago" in blue, "Not
///    connected", "Needs reconnecting · <reason>" in red), and a small
///    tertiary meta line when a fact is known.
/// 2. **The act field, always first** — "adding should always be first so a
///    user has a way to do what they want to do." Not connected: it IS the
///    connect form. Connected: the add/search field. Needs reconnecting:
///    "Paste a new token".
/// 3. **Plain rows** — Activity (opens the room), What it reaches (the hosts
///    and only the hosts), Your key (where it lives, never a character of
///    it), Notes (inline).
/// 4. **Who may read it** — reader marks, lit or dimmed, a caption.
/// 5. **Watching · N** — the account's own rows, active this week first,
///    then Quiet; ONE removal verb, "Remove".
/// 6. **Exits** — Pause reading, Disconnect.
///
/// The rejected variants are recorded in §639 so nobody restores them: cards
/// and slabs ("looks like a SaaS tool"), tabs, a Yours section, showing any
/// part of the token, privacy slogans on the reach row, and "room" as a word.
///
/// **The slot order is the chassis, not an audit.** §608 made the order a
/// property of each screen's body and audited it; here the adopter fills two
/// closures (`act`, `more`) and hands over data for the rest, so the order
/// cannot be got wrong by a screen at all. `scripts/account-page-selftest.sh`
/// guards what the type cannot: that every adopter says "Remove", that no
/// adopter draws a slab section, that the readers filter is wired at every
/// model hand-off.
struct AccountPage<Act: View, More: View, KeySheet: View>: View {
    /// The catalog name — mark, title, reach registry lookup.
    let name: String
    /// The BridgeStore seat id — notes, readers and the visit stamp key on it.
    let seatID: String
    /// The `Thing.source` this seat lands rows under. NOT the catalog name
    /// where the two differ (`RoomDoor`'s rule) — the Activity row opens it.
    let source: String
    let state: AccountPageShape.State
    /// The one sentence a not-connected page says (§315's budget) — the
    /// mode's consequence and the payoff. Drawn only while not connected.
    var intro: String? = nil
    /// HOW this seat connects — the §315 fact the chip on `BridgeSetupHeader`
    /// carried, and the one thing the state line cannot say: "Not connected"
    /// does not tell you whether you are about to paste a key, point at an
    /// export, or type a name. Drawn only while not connected, because once it
    /// is connected the answer is in the past and the state line is the news.
    /// A plain glyph and a word rather than the chip, since the page has no
    /// chips (the "You" pill is a fact about a person, not furniture).
    var mode: BridgeSetupMode? = nil
    /// A provider-reported expiry, when one exists. None does today.
    var keyExpires: Date? = nil
    /// Whether a "Your key" row is drawn at all — keyed bridges only.
    var keyed = false
    /// Whether this seat lands `Thing`s at all.
    ///
    /// FALSE for the rowless seats (§484's nine, and every agent key): a
    /// Venice key answers questions and stores nothing, an exchange reports a
    /// balance and lands no row. For those the Activity row would read "0
    /// today · 0 this week" about a seat that will never have a count — the
    /// §83 number-about-nothing, one row under a state line saying it is
    /// working — and "Who may read it" would offer to shut readers out of a
    /// corpus with nothing in it. Both are simply absent instead.
    var lands = true
    /// The rows under "Watching". The caller composes them from its own
    /// store; the chassis sorts and labels them.
    var rows: [AccountPageShape.Row] = []
    /// What is typed in the act field, so the roster below can answer the
    /// same keystrokes (§639 amendment — one bar, two jobs). The adopter owns
    /// the text because the field is its own; the chassis only reads it.
    var query: String = ""
    /// Removing a roster row, where removing one is a thing a person can do.
    /// NIL where it is not — a seat whose rows are its own apps or its own
    /// repositories has a roster to READ, and a swipe offering to remove one
    /// would be the §83 dead control with a destructive tint on it.
    var onRemoveRow: ((String) -> Void)? = nil
    /// Tap on a row — the person or repo profile where one exists. Rows
    /// with no destination are reads, not controls.
    var onOpenRow: ((String) -> Void)? = nil
    /// The disconnect's teardown — clears the bridge's own store, so the
    /// next foreground can't re-register the seat (`BridgeDisconnectSection`).
    var teardown: () -> Void
    var disconnectNote: String? = nil
    /// One presentation for the whole screen (the third-time-paid-for rule):
    /// the adopter owns the state so it can raise a profile from a row tap,
    /// and the chassis raises the reach and key sheets through the same door.
    @Binding var sheet: AccountPageSheet?
    @ViewBuilder var act: () -> Act
    /// Second acts that only exist once the first has happened (GitHub's
    /// feed picker, a starter-pack door). Drawn under the act field, on the
    /// page's own ground: the chassis applies `plainAccountRow()` to whatever
    /// comes back, so an adopter cannot hand back a row with a separator and
    /// system insets while every row around it has neither. An adopter that
    /// needs a filled shape here is drawing a slab §639 ruled out.
    @ViewBuilder var more: () -> More
    /// The "Your key" sheet's content — the paste field, from the adopter,
    /// because the verb that stores a key is the bridge's own.
    @ViewBuilder var keySheet: () -> KeySheet

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    @State private var today = 0
    @State private var week = 0
    @State private var note = ""
    /// Bumped by a reader toggle so the static `AccountReaders` read re-runs.
    @State private var readersTick = 0

    private var seat: BridgeApp? { store.bridges.first { $0.id == seatID } }
    private var hosts: [String] { AccountReach.hosts(for: name) }

    var body: some View {
        List {
            header
            actSection
            more().plainAccountRow()
            factRows
            readers
            roster
            exits
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        // The header IS the title — a nav title would say the name twice,
        // one line apart. Kept inline so a raised form's dismiss and a pushed
        // room's chevron still have a bar to sit in.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { which in
            switch which {
            case .reach:
                AccountReachSheet(name: name, hosts: hosts)
            case .key:
                AccountKeySheet(name: name) { keySheet() }
            case .profile(let profile):
                SocialProfileCard(profile: profile)
            case .thing(let id):
                AccountThingSheet(id: id)
            }
        }
        .task(id: source) { await readCounts() }
        .onAppear { note = AccountNotes.note(for: seatID) ?? "" }
        // The visit is stamped on the way OUT: the ring a row wears is "since
        // you last looked", and looking is only over once you leave.
        .onDisappear { AccountVisits.stamp(seatID) }
    }

    // MARK: - 1. Header

    private var header: some View {
        VStack(spacing: DS.Space.s2) {
            BridgeIcon(name: name, size: DS.Mark.account)
                .settleIn()
            Text(name)
                .dsText(.heading34).foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            HStack(spacing: DS.Space.s2) {
                Circle().fill(stateTone).frame(width: 8, height: 8)
                Text(AccountPageShape.stateLine(state))
                    .dsText(.subhead13).fontWeight(.medium)
                    .foregroundStyle(stateTone)
            }
            .accessibilityElement(children: .combine)
            if let meta = metaLine {
                Text(meta)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if !state.connected, let mode {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: mode.glyph).dsGlyph(12)
                    Text(mode.label).dsText(.label12)
                }
                .foregroundStyle(DS.textTertiary)
                .accessibilityElement(children: .combine)
            }
            if !state.connected, let intro {
                Text(LocalizedStringKey(intro))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .plainAccountRow()
    }

    private var stateTone: Color {
        switch state {
        case .reading:           DS.tint
        case .needsReconnecting: DS.attention
        case .notConnected, .paused: DS.textTertiary
        }
    }

    /// Only facts the app HOLDS. No bridge records the day it connected, so
    /// the line leads with the last successful read (`BridgeHealth`); a run
    /// of refusals says how long the activity has been missing.
    private var metaLine: String? {
        guard state.connected else { return nil }
        let record = BridgeHealth.record(for: name)
        return AccountPageShape.metaLine(
            connectedAt: nil, keyExpires: keyExpires,
            lastRead: record?.lastOK, missingSince: record?.authFailedAt)
    }

    // MARK: - 2. The act field

    private var actSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            act()
        }
        .padding(.vertical, DS.Space.s2)
        .plainAccountRow()
    }

    // MARK: - 3. Plain rows

    @ViewBuilder private var factRows: some View {
        // Activity — the way to the room. Not connected: a fact of "—" and
        // no door, because there is no room to open yet. Absent entirely for
        // a seat that lands nothing (see `lands`).
        if lands {
            AccountFactRow(glyph: "clock",
                           title: String(localized: "Activity"),
                           fact: AccountPageShape.activityFact(today: today, week: week,
                                                               connected: state.connected),
                           opens: state.connected,
                           action: state.connected ? openRoom : nil)
        }
        AccountFactRow(glyph: "network",
                       title: String(localized: "What it reaches"),
                       fact: AccountPageShape.reachFact(hosts: hosts),
                       opens: !hosts.isEmpty,
                       action: hosts.isEmpty ? nil : { sheet = .reach })
        if keyed, state.connected {
            AccountFactRow(glyph: "key",
                           title: String(localized: "Your key"),
                           fact: AccountPageShape.keyFact(device: DS.device, expires: keyExpires),
                           opens: true,
                           action: { sheet = .key })
        }
        notesRow
    }

    /// CLOSE THE SHEET, THEN POP, THEN ASK — `RoomDoor`'s three writes in
    /// `RoomDoor`'s order, for `RoomDoor`'s reasons (a connect screen is
    /// raised as often as it is pushed, and the stack is BEHIND the sheet).
    private func openRoom() {
        DSHaptic.tap()
        route.closeConnectForm()
        route.path = []
        chrome.sourceRequest = source
    }

    private var notesRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            AccountFactRow.disc("note.text")
            Text("Notes")
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            TextField(String(localized: "Add a note"), text: $note, axis: .vertical)
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit { AccountNotes.set(note, for: seatID) }
                .onChange(of: note) { _, now in AccountNotes.set(now, for: seatID) }
        }
        .frame(minHeight: AccountFactRow.height)
        .plainAccountRow()
    }

    // MARK: - 4. Who may read it

    @ViewBuilder private var readers: some View {
        if lands { readersBlock }
    }

    private var readersBlock: some View {
        let available = AccountReaders.available()
        let denied = AccountReaders.denied(seat: seatID)
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Who may read it")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            if !available.isEmpty {
                HStack(spacing: DS.Space.s3) {
                    ForEach(available) { reader in
                        AccountReaderMark(reader: reader,
                                          lit: state.connected && !denied.contains(reader.id),
                                          enabled: state.connected) {
                            let now = denied.contains(reader.id)
                            AccountReaders.setMayRead(reader.id, now, seat: seatID, source: source)
                            DSHaptic.selection()
                            readersTick += 1
                        }
                    }
                }
            }
            Text(AccountReaders.caption(available: available, denied: denied,
                                        connected: state.connected))
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // `readersTick` is otherwise unread — mutating it re-runs this body,
        // which re-reads the static, non-observable store above.
        .id(readersTick)
        .padding(.vertical, DS.Space.s3)
        .plainAccountRow()
    }

    // MARK: - 5. Watching

    @ViewBuilder private var roster: some View {
        // Filtered FIRST, then split: under a query the halves are the
        // matches' own, so "Quiet" never counts rows the person cannot see.
        let shown = AccountPageShape.matches(rows, query: query)
        let (active, quiet) = AccountPageShape.split(shown)
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        if !shown.isEmpty {
            Text(searching ? AccountPageShape.yoursLabel(shown.count)
                           : AccountPageShape.watchingLabel(rows.count))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .padding(.top, DS.Space.s3)
                .plainAccountRow()
            ForEach(active) { row in rosterRow(row) }
            if !quiet.isEmpty {
                if !active.isEmpty {
                    Text(AccountPageShape.quietLabel(quiet.count))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .padding(.top, DS.Space.s2)
                        .plainAccountRow()
                }
                ForEach(quiet) { row in rosterRow(row) }
            }
        }
    }

    @ViewBuilder
    private func rosterRow(_ row: AccountPageShape.Row) -> some View {
        let line = AccountRosterRow(
            row: row, fallbackIcon: name,
            subline: state.needsReconnecting ? AccountPageShape.pausedSubline : row.subline,
            open: onOpenRow.map { open in { open(row.id) } })
        if let remove = onRemoveRow {
            line
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        remove(row.id)
                        DSHaptic.tap()
                    } label: { Label("Remove", systemImage: "minus.circle") }
                }
                // A swipe has no Mac-mouse equivalent — right-click mirrors it.
                .contextMenu {
                    Button(role: .destructive) {
                        remove(row.id)
                        DSHaptic.tap()
                    } label: { Label("Remove", systemImage: "minus.circle") }
                }
                .plainAccountRow()
        } else {
            line.plainAccountRow()
        }
    }

    // MARK: - 6. Exits

    @ViewBuilder private var exits: some View {
        if state.connected {
            Button {
                store.togglePause(seatID)
                DSHaptic.tap()
            } label: {
                Text(seat?.status == .paused
                     ? String(localized: "Resume reading")
                     : String(localized: "Pause reading · keeps everything"))
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: AccountFactRow.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, DS.Space.s4)
            .plainAccountRow()
            BridgeDisconnectSection(bridgeID: seatID, name: source,
                                    teardown: teardown, note: disconnectNote, plain: true)
                .plainAccountRow()
        }
    }

    // MARK: - Counts

    /// A fetch belongs in `.task`, never in a body (prd §628).
    private func readCounts() async {
        let source = self.source
        let dayStart = Calendar.current.startOfDay(for: .now)
        let weekStart = Date.now.addingTimeInterval(-7 * 86_400)
        let dayD = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && $0.capturedAt >= dayStart })
        let weekD = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && $0.capturedAt >= weekStart })
        today = (try? modelContext.fetchCount(dayD)) ?? 0
        week = (try? modelContext.fetchCount(weekD)) ?? 0
    }
}

/// The screen's one presentation.
///
/// **`.thing` carries an ID, never a `Thing`** (the liveness class, corollary
/// 4): a roster row on a watch-list seat IS a thing — a watched ticker, a
/// followed package — and holding the model across a presentation is how a
/// sheet opens onto a row a foreground heal deleted underneath it. The sheet
/// re-reads it, and draws nothing if it has gone.
enum AccountPageSheet: Identifiable {
    case reach
    case key
    case profile(SocialProfile)
    case thing(id: UUID)
    var id: String {
        switch self {
        case .reach: "reach"
        case .key: "key"
        case .profile(let p): "profile:\(p.id)"
        case .thing(let id): "thing:\(id.uuidString)"
        }
    }
}

/// A roster row's own thing sheet, resolved from its id at present time.
/// Nothing is drawn for a thing that has gone — see `AccountPageSheet`.
private struct AccountThingSheet: View {
    let id: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var thing: Thing?

    var body: some View {
        Group {
            if let thing, thing.isLive {
                ThingSheetView(thing: thing)
            }
        }
        .task {
            var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            thing = (try? modelContext.fetch(descriptor))?.first
        }
    }
}

/// The state a seat is in, from what the app holds: the vault or store says
/// whether it is connected at all; `BridgeStore` says paused or attention;
/// `BridgeHealth` says whether a key was refused and when it last read. One
/// derivation, so every adopter's dot agrees with the catalog row's.
enum AccountPageState {
    static func of(name: String, seatID: String, connected: Bool,
                   store: BridgeStore) -> AccountPageShape.State {
        guard connected else { return .notConnected }
        let seat = store.bridges.first { $0.id == seatID }
        if seat?.status == .paused { return .paused }
        if BridgeHealth.needsReconnect(name) != nil {
            return .needsReconnecting(reason: String(localized: "key refused"))
        }
        if seat?.status == .attention {
            return .needsReconnecting(reason: seat?.statusLine ?? "")
        }
        return .reading(lastRead: BridgeHealth.record(for: name)?.lastOK)
    }
}

// MARK: - Rows

/// A plain row on the page background — no card, no separator, the page's
/// own margins.
private struct PlainAccountRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
    }
}

extension View {
    func plainAccountRow() -> some View { modifier(PlainAccountRow()) }
}

/// disc glyph · heading17 title · trailing subhead13 fact · chevron only if
/// it opens a screen. 56pt, no background. A row with no action is a READ,
/// drawn without a button so nothing on it can be mistaken for a control.
struct AccountFactRow: View {
    static let height: CGFloat = 56
    let glyph: String
    let title: String
    let fact: String
    var opens = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button {
                DSHaptic.tap()
                action()
            } label: { line }
            .buttonStyle(.plain)
            .plainAccountRow()
        } else {
            line.plainAccountRow()
        }
    }

    private var line: some View {
        HStack(spacing: DS.Space.s3) {
            Self.disc(glyph)
            Text(title)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Text(fact)
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            if opens {
                Image(systemName: "chevron.right")
                    .dsGlyph(12)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .frame(minHeight: Self.height)
        .contentShape(Rectangle())
    }

    /// The leading disc: a glyph on the well fill, the mark grammar every
    /// settings row in the app already uses.
    static func disc(_ glyph: String) -> some View {
        Image(systemName: glyph)
            .dsGlyph(14, weight: .medium)
            .foregroundStyle(DS.textSecondary)
            .frame(width: 32, height: 32)
            .background(DS.surfaceWell, in: Circle())
    }
}

/// One reader's mark — a brand tile, or the on-device glyph tile. Lit = may
/// read; dimmed (28%) = may not. Tap toggles.
struct AccountReaderMark: View {
    let reader: AccountReaders.Reader
    let lit: Bool
    let enabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Group {
                if let mark = reader.mark {
                    BridgeIcon(name: mark, size: DS.Face.list, circular: true)
                } else {
                    Image(systemName: "sparkles")
                        .dsGlyph(18, weight: .medium)
                        .foregroundStyle(DS.textPrimary)
                        .frame(width: DS.Face.list, height: DS.Face.list)
                        .background(DS.surfaceWell, in: Circle())
                }
            }
            .opacity(lit ? 1 : 0.28)
            .animation(DS.Motion.standard, value: lit)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(reader.name))
        .accessibilityValue(Text(lit ? String(localized: "May read") : String(localized: "May not read")))
        .accessibilityAddTraits(.isToggle)
    }
}

/// face · name · subline, a ring when it produced things since you last
/// looked, a "You" pill on the person's own account, NO trailing timestamp.
struct AccountRosterRow: View {
    let row: AccountPageShape.Row
    let fallbackIcon: String
    let subline: String
    var open: (() -> Void)? = nil

    var body: some View {
        if let open {
            Button {
                DSHaptic.tap()
                open()
            } label: { line }
            .buttonStyle(.plain)
        } else {
            line
        }
    }

    private var line: some View {
        HStack(spacing: DS.Space.s3) {
            Group {
                if let avatar = row.avatarURL, !avatar.isEmpty {
                    RemoteThumb(urlString: avatar, size: DS.Face.list,
                                fallback: fallbackIcon, circular: true)
                } else {
                    BridgeIcon(name: fallbackIcon, size: DS.Face.list, circular: true)
                }
            }
            .overlay {
                if row.hasNew {
                    Circle().strokeBorder(DS.tint, lineWidth: 2)
                        .padding(-2)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Space.s2) {
                    Text(row.title)
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if row.isYou {
                        Chip(text: String(localized: "You"), style: .tint)
                    }
                }
                Text(subline)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: AccountFactRow.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(row.hasNew ? String(localized: "New since you last looked") : ""))
    }
}

// MARK: - The reach lookup

/// What a seat reaches, read out of the ONE registry (`NetworkReach`) — the
/// hosts under the service that wears the catalog name, plus any endpoint
/// that names this bridge as its owner. Nothing here is typed twice.
enum AccountReach {
    static func endpoints(for name: String) -> [NetworkReach.Endpoint] {
        NetworkReach.endpoints.filter { endpoint in
            if endpoint.service == name { return true }
            if case .whenConnected(let bridge) = endpoint.reach { return bridge == name }
            return false
        }
    }

    static func hosts(for name: String) -> [String] {
        var seen = Set<String>()
        return endpoints(for: name).flatMap(\.hosts).filter { $0.contains(".") && seen.insert($0).inserted }
    }
}

// MARK: - Sheets

/// The reach row's screen: this account's registry entries and the receipts
/// for exactly its hosts — the receipts screen, filtered. The purpose
/// sentence is the registry's own; the counts are the ledger's.
struct AccountReachSheet: View {
    let name: String
    let hosts: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var receipts: [NetworkLedger.Entry] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(AccountReach.endpoints(for: name)) { endpoint in
                    Text(endpoint.purpose)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, DS.Space.s2)
                        .plainAccountRow()
                }
                ForEach(hosts, id: \.self) { host in
                    HStack(spacing: DS.Space.s3) {
                        AccountFactRow.disc("network")
                        Text(host)
                            .dsText(.heading17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: DS.Space.s2)
                        Text(receiptLine(host))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: AccountFactRow.height)
                    .plainAccountRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dsPageBackground()
            .dsScreenTitle(String(localized: "What \(name) reaches"))
            .dsSheetDismiss { dismiss() }
            .onAppear { receipts = NetworkLedger.shared.snapshot() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }

    /// "12 calls · 8m ago" from the ledger, or "no calls this week" — the
    /// honest empty, since the ledger keeps seven days.
    private func receiptLine(_ host: String) -> String {
        let needle = host.lowercased()
        let matching = receipts.filter {
            let h = $0.host.lowercased()
            return h == needle || h.hasSuffix("." + needle)
        }
        let count = matching.reduce(0) { $0 + $1.count }
        guard count > 0, let last = matching.map(\.last).max() else {
            return String(localized: "no calls this week")
        }
        return String(localized: "\(count) calls · \(AccountPageShape.ago(last))")
    }
}

/// The "Your key" sheet — the adopter's own paste field, in a sheet that says
/// where the key goes and nothing about the key it replaces.
struct AccountKeySheet<Content: View>: View {
    let name: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                content()
                    .padding(.vertical, DS.Space.s2)
                    .plainAccountRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dsPageBackground()
            .dsScreenTitle(String(localized: "Your \(name) key"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}
