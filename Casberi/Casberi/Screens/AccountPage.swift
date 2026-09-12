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
///    "Paste a new token". **It draws ROWS, not slabs** (§640,
///    `Design/DSAccountAct.swift`): the door, the entry and the verb are the
///    same 56pt row anatomy as the facts below them.
/// 3. **Plain rows** — Activity (opens the room), Your key (where it lives,
///    never a character of it), **Notes** — an ENTRY ROW, the note itself
///    in the title column, inline and visible on the page, growing as it is
///    typed or pasted (prd §708; §640's filled box is gone, its reason —
///    "they may have an actual note to paste" — kept). **No "What it
///    reaches" row** (prd §702, user: "we already have 'what it reaches' in
///    settings") — the ONE registry is the privacy screen's, where a person
///    goes to ask that question about the whole app; the per-account copy
///    asked it again, once per account, on the page whose job is connecting.
///    **No "Who may read it"** (prd §708, user: "it is really confusing and
///    no one cares, we already in settings give receipts") — the marks
///    block, the caption and the sheet are deleted; the reader store and its
///    enforcement stand, defaulting to every reader, until they are retired.
/// 4. **Nothing on the page is boxed** (§708, user: the gray boxes "look
///    bolted on and vibe coded"). A row states a fact, a footer under it
///    explains it — the setup card, the notes box and the reader-marks block
///    were the three exceptions and are gone.
/// 5. **Watching · N** — the account's own rows, active this week first,
///    then Quiet; ONE removal verb, "Remove".
/// 6. **Exits** — Pause reading, Disconnect.
///
/// The rejected variants are recorded in §639 so nobody restores them: cards
/// and slabs ("looks like a SaaS tool"), tabs, a Yours section, showing any
/// part of the token, privacy slogans on a reach row, and "room" as a word.
///
/// **The slot order is the chassis, not an audit.** §608 made the order a
/// property of each screen's body and audited it; here the adopter fills two
/// closures (`act`, `more`) and hands over data for the rest, so the order
/// cannot be got wrong by a screen at all. `scripts/account-page-selftest.sh`
/// guards what the type cannot: that every adopter says "Remove", that no
/// adopter draws a slab section, that the readers filter is wired at every
/// model hand-off — the FILTER, which stands; its per-account control is
/// deleted (§708).
struct AccountPage<Act: View, More: View, KeySheet: View>: View {
    /// The catalog name — mark, title, reach registry lookup.
    let name: String
    /// The BridgeStore seat id — notes and the visit stamp key on it.
    let seatID: String
    /// The `Thing.source` this seat lands rows under. NOT the catalog name
    /// where the two differ (`RoomDoor`'s rule) — the Activity row opens it.
    let source: String
    let state: AccountPageShape.State
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
    /// working. ("Who may read it" carried the second half of this argument
    /// — it would have offered to shut readers out of a corpus with nothing
    /// in it — until §708 deleted that block outright; the flag now governs
    /// the Activity row alone.)
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
    /// An EXTRA menu item on a roster row, above Remove — for a verb only one
    /// seat has (Tokens' "Move to front", in the manual sort). `AnyView`
    /// rather than a fourth generic parameter, because a generic with no
    /// inferable default would force every one of the ~40 call sites to spell
    /// out a type they do not use.
    var rowMenu: ((String) -> AnyView)? = nil
    /// A SHEET only this seat can compose, raised through the page's ONE
    /// presentation (`.card`). L2BEAT's risk assessment and Walletbeat's
    /// review are screens of their own that no other seat has; a second
    /// `.sheet` modifier on this view is exactly what broke `FeedScreen`'s
    /// first tap once, so they come through the same door. `AnyView` for
    /// `rowMenu`'s reason.
    var cardSheet: ((String) -> AnyView)? = nil
    /// The disconnect's teardown — clears the bridge's own store, so the
    /// next foreground can't re-register the seat (`BridgeDisconnectSection`).
    var teardown: () -> Void
    var disconnectNote: String? = nil
    /// One presentation for the whole screen (the third-time-paid-for rule):
    /// the adopter owns the state so it can raise a profile from a row tap,
    /// and the chassis raises the key sheet through the same door.
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
    /// How far the roster's window has been opened, in `RowWindow` steps
    /// (prd §710).
    ///
    /// **EVERY ACCOUNT PAGE IS A `List` INSIDE A SHEET A FINGER CAN DRAG**
    /// (`MainSurface`'s one `.sheet(item: $route.connectForm)`), which is
    /// precisely build 539's watchdog one surface over: UIKit lays a sheet's
    /// hosting view out SYNCHRONOUSLY on every offset change, and SwiftUI
    /// resolves each row's index by a linear walk, so the update is
    /// O(rows × sections) per offset. §657 bounded the person room and left
    /// this chassis unbounded — and this page's own doc anticipates "forty
    /// repos or a hundred and forty accounts", while an OPML export drops
    /// hundreds of feeds into RSS's roster in one tap. Making the row cheaper
    /// raises the count at which it dies; not drawing the rows is the fix
    /// (`RowWindow`'s own ruling).
    @State private var windowSteps = 0
    /// THE DOOR OPENED IN-APP (prd §653). Sticky for the page's life: the
    /// paste the person came back to make is offered from the first return
    /// on, whether the sheet is down or parked at half height over the rows.
    @State private var doorOpened = false

    private var seat: BridgeApp? { store.bridges.first { $0.id == seatID } }

    var body: some View {
        pageList
            // NOT scrolled to the act when the sheet drops to half. It was
            // tried both ways — `ScrollViewReader.scrollTo` and
            // `ScrollPosition.scrollTo(id:)` on a "room" row under the act —
            // and the request is accepted (`viewID` reads "room") while the
            // List does not move under a presented sheet, on the iOS 26
            // simulator. A finger scroll does; the room row below is what
            // gives it somewhere to go.
    }

    private var doorUp: Bool {
        if case .web = sheet { return true }
        return false
    }

    private var pageList: some View {
        List {
            header
            actSection
            // THE ROOM UNDER THE HALF SHEET (prd §653). A medium detent
            // covers the bottom half, and the act — the entry row the person
            // came back to paste into — lives there. While the door is up
            // this row holds the sheet's height under the act, so a scroll
            // can bring the act clear of the sheet, the rows below pushed
            // under it. Gone the moment the sheet is.
            //
            // PHONE ONLY, on the same condition the detents are real under
            // (`DSWebSheet.dsPageSheet`): where the system sizes sheets as
            // fixed pages — iPad — no detent is honoured and background
            // interaction never engages, so this row would be half a screen
            // of empty list inside a page nobody can touch, and removing it
            // on dismiss would jerk the offset.
            if doorUp, !DSSheetSize.sizesSheets {
                Color.clear
                    .containerRelativeFrame(.vertical) { height, _ in height / 2 }
                    .plainAccountRow()
            }
            more().dsAccountAct().plainAccountRow()
            factRows
            roster
            exits
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // THE PAGE'S OWN TOP (§524: every pour is ink). Its ORIGINAL reason
        // — that arriving from the product page's bold wash must not drop to a
        // bare gray form — expired with that page (§641); it stays because it
        // is now this page's own head, and §639's first cut left it off, which
        // made those three screens the only pages in the app with no top.
        .bridgeSetupWash(name: name)
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
            case .key:
                // THE HOST WRAPS THE SHEET, NOT ITS ROW. `AccountKeySheet`
                // renders what it is handed as a `List` row, so a host placed
                // inside it hung its own `.sheet` off a row — the shape
                // CLAUDE.md records as paid for three times (a presentation
                // attached inside a row resolves to the row's controller and
                // can tear itself down mid-transition). Outside, the modifier
                // lands on the key sheet's `NavigationStack`, which is the
                // same position this page's own `.sheet` occupies.
                AccountDoorHost { AccountKeySheet(name: name) { keySheet() } }
            case .profile(let profile):
                SocialProfileCard(profile: profile)
            case .thing(let id):
                AccountThingSheet(id: id)
            case .card(let id):
                cardSheet?(id)
            case .web(let url):
                DSWebSheet(url: url) { sheet = nil }
            }
        }
        .task(id: source) { await readCounts() }
        // A typed query is a new list, so it gets a new first screenful (prd
        // §710) — otherwise a window opened to 300 rows stays open once the
        // query clears, which is the bound gone by the back door. Guarded on
        // the value so a keystroke over an unopened window writes nothing.
        .onChange(of: query) { _, _ in if windowSteps != 0 { windowSteps = 0 } }
        .onAppear { note = AccountNotes.note(for: seatID) ?? "" }
        .onChange(of: note) { _, now in AccountNotes.set(now, for: seatID) }
        // The visit is stamped on the way OUT: the ring a row wears is "since
        // you last looked", and looking is only over once you leave.
        .onDisappear { AccountVisits.stamp(seatID) }
    }

    /// The in-app door (prd §653). Mac Catalyst has no Safari controller and
    /// a real browser window to leave open beside the app, so there every
    /// door stays the system action (`DSWebSheet`'s own reasoning).
    private var doorAction: OpenURLAction {
        OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return .systemAction }
            // THE RETURN LEG IS NOT THE SHEET'S (prd §653). Mac opens the door
            // in a real browser window beside the app, which is the platform
            // where the trip out works BEST — so the stamp is set on both
            // sides of this branch and only the presentation differs. Setting
            // it after the `#if` would have left the Mac's paste row dark
            // forever, and `mac-parity-audit.py` cannot see that class.
            doorOpened = true
            #if targetEnvironment(macCatalyst)
            return .systemAction
            #else
            sheet = .web(url)
            return .handled
            #endif
        }
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
        VStack(alignment: .leading, spacing: 0) {
            act()
        }
        // EVERY DOOR IN THE ACT OPENS BESIDE THE PAGE (prd §653). A slab that
        // carries its `url:` opens it through this environment, so a "Get
        // your API key" lands as the in-app Safari sheet — half or full
        // height, the rows beneath still live — instead of backgrounding the
        // app. Only web pages: an app scheme or a mailto: keeps the system
        // action. THE ACT ONLY, not the list: a feed tile in `more()` or a
        // "Renew on ENS" is a link to leave by, and catching it would also
        // light every paste row for a copy that was never a key. The key
        // sheet has its own host (`AccountDoorHost`) — a presented sheet does
        // not inherit this (verified in the simulator: the door there
        // opened real Safari until it got one).
        .environment(\.openURL, doorAction)
        .environment(\.accountDoorOpened, doorOpened)
        // THE ACT DRAWS ROWS, NOT SLABS (prd §640) — one environment flag, so
        // all 55 screens change with their call sites untouched. See
        // `Design/DSAccountAct.swift` for what each primitive becomes.
        .dsAccountAct()
        .padding(.vertical, DS.Space.s2)
        .plainAccountRow()
    }

    // MARK: - 3. Plain rows

    @ViewBuilder private var factRows: some View {
        // Activity — the way to the room. NOT DRAWN UNTIL THERE IS A SEAT
        // (prd §641, the ruling that deleted the product page): it used to
        // draw "—" with no chevron on the dark page, which is a read that
        // says nothing, on the screen with the least room — the same defect
        // §640b removed one row over when it pulled the notes box off a
        // page with no account. Absent entirely for a
        // seat that lands nothing (see `lands`).
        if lands, state.connected {
            AccountFactRow(glyph: "clock",
                           title: String(localized: "Activity"),
                           fact: AccountPageShape.activityFact(today: today, week: week,
                                                               connected: true),
                           opens: true,
                           action: openRoom)
        }
        if keyed, state.connected {
            AccountFactRow(glyph: "key",
                           title: String(localized: "Your key"),
                           fact: AccountPageShape.keyFact(device: DS.device, expires: keyExpires),
                           opens: true,
                           action: { sheet = .key })
        }
        // NOT BEFORE THERE IS AN ACCOUNT (prd §640b, user: "why would we have
        // a notes field before connected, that doesn't make sense"). A note is
        // a fact about a seat you have; drawn on a page with no seat it is a
        // form field asking you to annotate nothing, above the act that would
        // create the thing to annotate.
        if state.connected { notesRow }
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

    /// NOTES IS AN ENTRY ROW (prd §708) — the disc, then the note itself in
    /// the title column, no fill. §640 drew a caption over a filled box so a
    /// person could paste a real note; the box was the last gray shape on a
    /// page whose rule is that nothing is boxed (user: "they look bolted on
    /// and vibe coded"), and the user ruled the note stays INLINE — *"someone
    /// may want to come back to this page and see it, not have to click
    /// another time"*. So it is the same row as every entry on this page:
    /// one line standing empty ("Add a note"), growing to ten as it is typed
    /// or pasted, the text always on the page.
    private var notesRow: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            AccountFactRow.disc("note.text")
                .frame(height: AccountFactRow.height)
            TextField(String(localized: "Add a note"), text: $note, axis: .vertical)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.tint)
                .lineLimit(1...10)
                .textInputAutocapitalization(.sentences)
                .frame(minHeight: AccountFactRow.height)
        }
        .plainAccountRow()
    }

    // MARK: - 5. Watching

    @ViewBuilder private var roster: some View {
        // Filtered FIRST, then split: under a query the halves are the
        // matches' own, so "Quiet" never counts rows the person cannot see.
        let shown = AccountPageShape.matches(rows, query: query)
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        // **TWO TIERS WHEN A ROSTER HAS THEM (prd §690).** A directory that
        // lists what you follow AND what you have only named splits by that,
        // and its header counts only the followed; every other roster keeps
        // the active/quiet split by activity, untouched.
        let tiered = shown.contains { !$0.watched }
        let (active, quiet) = tiered
            ? (shown.filter(\.watched), shown.filter { !$0.watched })
            : AccountPageShape.split(shown)
        // BOUNDED (prd §710) — windowed in DRAW ORDER, then split back, so
        // the first screenful is the rows a person came to see (active this
        // week, or followed) and the tail is what gets held back. Slicing each
        // half against its own budget would draw two screenfuls, and slicing
        // only the quiet half would leave a seat with 300 active rows
        // unbounded, which is RSS's own shape after an OPML import.
        let window = RowWindow.slice(active + quiet, steps: windowSteps)
        let drawnActive = Array(window.shown.prefix(active.count))
        let drawnQuiet = Array(window.shown.dropFirst(active.count))
        if !shown.isEmpty {
            // The HEADER COUNTS ARE TOTALS, never the window's (§83: a number
            // about nothing). "Watching · 312" over thirty rows is the honest
            // reading — the rows below it are a window, and the opener says
            // so; a count that shrank to the window would hide the 282.
            Text(searching ? AccountPageShape.yoursLabel(shown.count)
                           : AccountPageShape.watchingLabel(rows.filter(\.watched).count))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .padding(.top, DS.Space.s3)
                .plainAccountRow()
            ForEach(drawnActive) { row in rosterRow(row) }
            if !drawnQuiet.isEmpty {
                if !active.isEmpty || tiered {
                    Text(tiered ? AccountPageShape.namedLabel(quiet.count)
                                : AccountPageShape.quietLabel(quiet.count))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .padding(.top, DS.Space.s2)
                        .plainAccountRow()
                }
                ForEach(drawnQuiet) { row in rosterRow(row) }
            }
            if window.more { opener }
        }
    }

    /// A TAP, never an appearance trigger — `PersonRoomScreen`'s own note
    /// records the measurement: `List` realizes rows ahead of the viewport, so
    /// growing on `.onAppear` re-renders, appears again and runs away.
    private var opener: some View {
        Button {
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) { windowSteps += 1 }
        } label: {
            Text("Show more")
                .dsText(.subhead13)
                .foregroundStyle(DS.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plainAccountRow()
    }

    @ViewBuilder
    private func rosterRow(_ row: AccountPageShape.Row) -> some View {
        let line = AccountRosterRow(
            row: row, fallbackIcon: name,
            subline: state.needsReconnecting ? AccountPageShape.pausedSubline : row.subline,
            open: onOpenRow.map { open in { open(row.id) } })
        // ONE swipe and ONE menu, with conditional CONTENTS rather than two
        // shapes of row: a swipe has no Mac-mouse equivalent, so the harness
        // counts the two and demands they match, and a second pair of
        // modifiers on a second branch reads to that count as a swipe with no
        // mirror. A row with nothing to remove simply offers no swipe action.
        if onRemoveRow != nil || rowMenu != nil {
            line
                .swipeActions(edge: .trailing) {
                    if let remove = onRemoveRow {
                        Button(role: .destructive) {
                            remove(row.id)
                            DSHaptic.tap()
                        } label: { Label("Remove", systemImage: "minus.circle") }
                    }
                }
                // A swipe has no Mac-mouse equivalent — right-click mirrors it.
                .contextMenu {
                    rowMenu?(row.id)
                    if let remove = onRemoveRow {
                        Button(role: .destructive) {
                            remove(row.id)
                            DSHaptic.tap()
                        } label: { Label("Remove", systemImage: "minus.circle") }
                    }
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
    case key
    case profile(SocialProfile)
    case thing(id: UUID)
    /// A screen only the adopting seat can compose, keyed by whatever it
    /// names its own rows with (`AccountPage.cardSheet`).
    case card(id: String)
    /// A provider's page, opened beside the rows (prd §653, `DSWebSheet`).
    case web(URL)
    var id: String {
        switch self {
        case .key: "key"
        case .profile(let p): "profile:\(p.id)"
        case .thing(let id): "thing:\(id.uuidString)"
        case .card(let id): "card:\(id)"
        case .web(let url): "web:\(url.absoluteString)"
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

    /// The leading disc — `DSActRow`'s, so a fact row and an act row cannot
    /// drift apart (prd §640; they stand in one column).
    static func disc(_ glyph: String) -> some View { DSActRow.disc(glyph) }
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
                } else if let address = row.faceAddress {
                    // An address IS a face in this app (§690).
                    WalletFace(address: address, size: DS.Face.list, circular: true)
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

// MARK: - The roster's week

/// This week's rows per watched thing, and whether any of them arrived since
/// the page was last looked at (prd §639).
///
/// Every seat with a roster wants the same two numbers and was writing the
/// same fetch to get them — group the source's last seven days by whatever
/// field the bridge stamps the watched identity into, and compare each row's
/// clock to `AccountVisits`. Written eight times it drifts eight ways; here it
/// is one function with the traps already paid for:
///
/// * a `#Predicate` never touches an array-typed attribute (`tags.contains`
///   compiles and then crashes inside CoreData mid-fetch — CLAUDE.md's own
///   rule), so `key` runs in Swift, after the fetch;
/// * the fetch is BOUNDED, because a source with a year of rows is a scroll
///   away from any account page;
/// * `.filter(\.isLive)` at the boundary, since this hands values onward and
///   a foreground heal deletes rows while the page is open (corollary 4).
///
/// Call it from `onAppear` or a `.task`, never from a body or a computed
/// property a body reads (prd §628).
@MainActor
enum AccountWeek {
    static func counts(source: String, seatID: String, context: ModelContext,
                       limit: Int = 2000,
                       key: (Thing) -> String?) -> [String: (week: Int, new: Bool)] {
        let since = Date.now.addingTimeInterval(-7 * 86_400)
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source && $0.capturedAt >= since })
        descriptor.fetchLimit = limit
        let things = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        let lastLooked = AccountVisits.lastLooked(seatID)
        var book: [String: (week: Int, new: Bool)] = [:]
        for thing in things {
            guard let raw = key(thing) else { continue }
            let id = raw.lowercased()
            guard !id.isEmpty else { continue }
            let was = book[id] ?? (0, false)
            book[id] = (was.week + 1,
                        was.new || (lastLooked.map { thing.capturedAt > $0 } ?? false))
        }
        return book
    }
}

// MARK: - Sheets

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
                    // The same block the act slot draws, so the same grammar
                    // (prd §640) — this sheet IS where a key is replaced, and
                    // it is the screen the report arrived on.
                    .dsAccountAct()
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
