import SwiftUI

/// The rooms tray (prd §930, 2026-09-26; the Apple pass is §932) — the phone's
/// whole navigation behind ONE button, the face.
///
/// **Why the strip left the band.** The dock's category tiles were a scroll
/// before a tap for any room past the fourth (user: "then it's only one
/// button that a person has to press in the nav, whereas now they have to
/// sort of scroll and stuff"). This tray puts every room one tap from the
/// face, as ONE LIST (prd §1053, Settings' and Mail's shape): four You rows
/// — Home (the All room), Notes, Addresses and Settings — each led by a
/// tile, then a Categories section of plain rows, each landing in its
/// category's room.
///
/// **A layer of `RootShell`'s stack, never a sheet (§394).** A sheet presents
/// in its own context and would cover the face; this sits UNDER the seat so
/// the same tap that opened it closes it (§705's toggle, one size up). The
/// three runtime lessons §394a paid for are all here: the environment is
/// handed in explicitly by the host (`rootPresented` plus the scene's route
/// and filter), the dismiss drag lives on the grabber rather than the panel
/// (the `ScrollView` would win the arbitration), and the drag reads `.global`
/// so the panel's own offset cannot slide out from under the finger.
///
/// **The Apple pass (§932).** Two detents — it opens at rest, a grabber drag
/// grows it, a drag down from grown collapses before it dismisses (the HIG's
/// medium detent, and §394a's three outcomes). The panel is SOLID black, the
/// sheets' `surfaceSheet` (prd §1014, supersedes §932's glass): a dense wall
/// of brand circles and grey headers lost contrast over a bright room, and
/// over a dark one glass already read as charcoal, so it bought nothing
/// (user: "we agreed glass isn't working here for contrast", "i suggest
/// going black"). A filled symbol says
/// SELECTED and nothing else (the HIG's own reading of the fill variant), so
/// the standing category and Home fill and tint, and the rest stay outline.
/// The panel grows out of the face's corner on the dock's own spring, the
/// rows deal in top to bottom and the standing glyph bounces once (the
/// picked source's flight to the room's head went with the marks, §1050l).
/// A category with a broken seat wears the attention colour on its
/// glyph and says so; a system Close appears at the accessibility text sizes,
/// where the face's ring is hard to read. Every name is a 44pt target.
///
/// **Every pick is `ShellChrome.sourceRequest`.** The strip's own tap ran
/// `go(to:)` inside `MainSurface`; this view stands above the stack and takes
/// the same hop every other room-to-room door takes, so a category label
/// resolves through `CategoryFold.landing` exactly as a chip tap did.
///
/// **A tile has no hold (prd §1033).** §1015 gave a mark one verb, Manage
/// account, and nobody finds a hold; since §1050f an app's settings open
/// from Apps, so a tile only lands you in a room.
///
/// **Search and the pinned row (prd §1015).** A search field leads the tray
/// as it leads Accounts; typing narrows the categories in place — a tile
/// stays when its name or an app inside matches — and nothing opens. The field and the You row are
/// pinned above the scroll, so Home, Notes and Settings are one tap away
/// however far the rooms scroll.
struct RoomsTray: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route
    @Environment(FeedFilter.self) private var filter
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The tray is ONE LIST (prd §1053, user: "i worry with the grid we
    /// look android", then "yes D"): the lead column every row's word starts
    /// after — a You door's tile, or the slot a category's bare glyph
    /// centres in.
    static let lead: CGFloat = 34
    /// A You row stands a little taller than a category's: they are the
    /// app's own places, and the tile needs the air.
    static let youRowHeight: CGFloat = 52
    static let rowHeight: CGFloat = 48
    /// The air above a section's header, so the gap is
    /// what divides one category from the next — no line, no card (§782,
    /// user: "you decide the optimal spacing").
    static let sectionGap: CGFloat = DS.Space.s6
    /// A grabber drag past this, down, collapses or closes; up, grows.
    static let detentDrag: CGFloat = 56
    /// The two detents, as shares of the screen: rest shows You and the first
    /// rooms; grown shows the whole roster. Neither exceeds the roster's
    /// natural height — a short roster is a short tray.
    // Three quarters at rest (user, 2026-09-26: "shouldn't the tray be higher?
    // like a 3/4 tray") — it opened at 0.58 and read as a half sheet.
    static let restShare: CGFloat = 0.75
    static let grownShare: CGFloat = 0.88
    /// The stagger between one mark's arrival and the next.
    static let dealStep: Double = 0.02

    @State private var drag: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var grown = false
    @State private var dealt = false
    @State private var bounceTick = 0
    /// The search (prd §1015): typing narrows the grid in place.
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// The pinned part's height — the search and the You row — so the
    /// tray's natural height counts it.
    @State private var headHeight: CGFloat = 0

    private var liftMotion: Animation { reduceMotion ? DS.Motion.glide : DS.Motion.folder }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                if chrome.roomsTray {
                    // The catcher: a dim the room reads through, and a tap on
                    // it closes the tray — a real control, so it is a Button.
                    Button {
                        close()
                    } label: {
                        DS.scrim.ignoresSafeArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close rooms"))
                    .transition(.opacity)
                    panel(screen: geo.size)
                        .offset(y: max(0, drag))
                        // Out of the face's corner and back into it (§932).
                        .transition(reduceMotion
                            ? .opacity
                            : .scale(scale: 0.06, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(chrome.roomsTray)
        .animation(liftMotion, value: chrome.roomsTray)
        #if DEBUG
        // `-openTray YES`: raise the tray at mount, no tap (prd §1008), so a
        // screenshot of it does not depend on a simulator tap landing.
        .task {
            guard UserDefaults.standard.bool(forKey: "openTray") else { return }
            try? await Task.sleep(for: .seconds(1))
            NSLog("[Casberi] openTray: raised")
            withAnimation(liftMotion) { chrome.roomsTray = true }
            // `-trayQuery "<text>"`: type into the search headlessly (§1015),
            // because a simctl-booted device shows no keyboard.
            if let q = UserDefaults.standard.string(forKey: "trayQuery"), !q.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                NSLog("[Casberi] trayQuery: %@", q)
                query = q
            }
        }
        #endif
        .onChange(of: searchFocused) { _, focused in
            if focused, !grown {
                withAnimation(DS.Motion.glide) { grown = true }
            }
        }
        .onChange(of: chrome.roomsTray) { _, up in
            // Deal the marks in once the panel has landed; under Reduce
            // Motion they are simply there.
            grown = false
            drag = 0
            query = ""
            searchFocused = false
            if reduceMotion {
                dealt = up
            } else {
                dealt = up
                if up { bounceTick += 1 }
            }
        }
    }

    // MARK: - The panel

    private func panel(screen: CGSize) -> some View {
        let natural = contentHeight + headHeight + Self.grabberHeight
        let rest = min(natural, screen.height * Self.restShare)
        let full = min(natural, screen.height * Self.grownShare)
        let height = grown ? full : rest
        let searching = !trimmedQuery.isEmpty
        let shown = searching ? searchHits : categories
        return VStack(spacing: 0) {
            grabber
            // The pinned part (prd §1015): the search. The You rows scroll
            // with the list since §1053 — four pinned rows would take half
            // the tray at rest.
            searchField
                .padding(.horizontal, DSRoomChassis.inset)
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s3)
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { headHeight = g.size.height }
                        .onChange(of: g.size.height) { _, h in headHeight = h }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if searching {
                        if shown.isEmpty {
                            DSFootnote(Text("No room matches \u{201C}\(trimmedQuery)\u{201D}"))
                        }
                    } else {
                        // The You rows, untitled: first place and the tile
                        // say they are the app's own (§1053, Settings' first
                        // block). They step aside while a query is up.
                        ForEach(Array(youDoors.enumerated()), id: \.offset) { index, door in
                            self.door(door, index: index)
                        }
                        Text("Categories")
                            .dsText(.heading20)
                            .foregroundStyle(DS.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, Self.sectionGap)
                            .padding(.bottom, DS.Space.s1)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element) { index, category in
                        categoryRow(category, index: index + youDoors.count)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, DSRoomChassis.inset)
                // Hits settle into place rather than snapping (§1015).
                .animation(DS.Motion.standard, value: trimmedQuery)
                // The face rides ABOVE this tray (it is the way out), so the
                // last row ends before its column — the same clearance every
                // pushed screen leaves (§829).
                .padding(.bottom, DSDock.seatClearance)
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { contentHeight = g.size.height }
                            .onChange(of: g.size.height) { _, h in contentHeight = h }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(height: max(height - Self.grabberHeight - headHeight, 1))
        }
        .frame(maxWidth: .infinity)
        // The bottom corners sit below the edge: the panel is one radius, and
        // only its top corners are meant to be seen. Solid, the sheets' black
        // (§1014) — never glass, which lost the marks' contrast.
        .padding(.bottom, DS.Radius.sheet)
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .offset(y: DS.Radius.sheet)
        .overlay(alignment: .topLeading) { closeDoor }
        // The container's bottom only: the keyboard's inset stays, so a
        // search's hits scroll above the keys (§1015).
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityAddTraits(.isModal)
        .animation(DS.Motion.glide, value: grown)
    }

    private static let grabberHeight: CGFloat = 24

    /// The one drag region (§394a): chrome that does not scroll. Three
    /// outcomes: up grows, down from grown collapses, down from rest closes.
    private var grabber: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(DS.fillStrong)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.grabberHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { drag = $0.translation.height }
                    .onEnded { value in
                        let travel = value.translation.height
                        if travel < -Self.detentDrag, !grown {
                            DSHaptic.selection()
                            grown = true
                            withAnimation(DS.Motion.glide) { drag = 0 }
                        } else if travel > Self.detentDrag, grown {
                            DSHaptic.selection()
                            grown = false
                            withAnimation(DS.Motion.glide) { drag = 0 }
                        } else if travel > Self.detentDrag {
                            close()
                        } else {
                            withAnimation(DS.Motion.glide) { drag = 0 }
                        }
                    }
            )
            .accessibilityLabel(Text("Close rooms"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { close() }
    }

    /// The system's Close, at the accessibility text sizes only: there the
    /// face's ring is small beside the words, and the HIG pairs a grabber
    /// with a Close.
    @ViewBuilder
    private var closeDoor: some View {
        if typeSize.isAccessibilitySize {
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .dsGlyph(.title)
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(PressSpring())
            .dsTapTarget(Circle())
            .accessibilityLabel(Text("Close"))
            .padding(.leading, DSRoomChassis.inset)
            .padding(.top, DS.Space.s2)
        }
    }

    // MARK: - Rows

    /// The categories on the dock, in the dock's own order (`CategoryOrder`,
    /// through the mirror `MainSurface` publishes for the Mac's ⌘1–9).
    ///
    /// A category is a row only while it holds a connected seat (prd §977,
    /// user: "it shouldn't be a category unless someone connects their notes
    /// apps"). Build 688 drew Notes with no marks: the Notes room's sentinel
    /// was the category's own name, so the fold made a category chip out of
    /// a room (§975). A row with no venues is that class, whatever string
    /// caused it, and this gate holds it off the tray.
    private var categories: [String] {
        chrome.chipOrder.filter {
            CategoryFold.isCategory($0) && !(chrome.categoryVenues[$0] ?? []).isEmpty
        }
    }

    /// The category the room you are standing in belongs to.
    private var standingCategory: String? {
        let label = CategoryFold.chipLabel(for: filter.source, folded: chrome.chipOrder)
        return CategoryFold.isCategory(label) ? label : nil
    }

    /// A category's glyph when it is the standing one: the fill variant, which
    /// the HIG reserves for selection. Categories whose glyph has no fill
    /// keep the one they have.
    private static let filledGlyphs: [String: String] = [
        "Wallet":   "creditcard.fill",
        "Agents":   "terminal.fill",
        "Media":    "play.circle.fill",
        "Social":   "bubble.left.and.bubble.right.fill",
        "Reading":  "book.fill",
        "Testnets": "flask.fill",
        "Life":     "face.smiling.inverse",
    ]

    private func glyph(for category: String, lit: Bool) -> String {
        lit ? (Self.filledGlyphs[category] ?? CategoryFold.glyph(for: category))
            : CategoryFold.glyph(for: category)
    }

    /// Whether one of the category's seats needs you — the same test the
    /// face's ring makes (`DoorAlarm`), read per tile so the tile can say which.
    private func broken(_ category: String) -> Bool {
        let names = Set(seats(in: category) + appNames(in: category))
        return bridges.bridges.contains { names.contains($0.name) && $0.status == .attention }
    }

    /// A category's seats, in the tray's order.
    private func seats(in category: String) -> [String] {
        CategoryFold.scopes(category: category,
                            present: Set(chrome.categoryVenues[category] ?? []))
    }

    // MARK: - Merged rooms (prd §1048b)

    /// The merged room a category opens, once it has absorbed apps — keyed
    /// on `RoomAccounts`, so each category turns over the day its room
    /// merges, and an unmerged one (Work, Day…) keeps today's tray exactly.
    private func mergedRoom(in category: String) -> String? {
        seats(in: category).first { RoomAccounts.mergedRooms.contains($0) }
    }

    /// The names of the apps a category holds: its seats, and for a merged
    /// room every app it folded in that is connected. A search finds the
    /// category by any of them (a search for Gnosis finds Wallet), and a
    /// broken one marks its tile. The tray draws no app marks since §1050l:
    /// a tile lands in its category, whose room scopes to each app.
    private func appNames(in category: String) -> [String] {
        let own = seats(in: category).map { BridgeCatalog.seatName(forSource: $0) }
        guard let room = mergedRoom(in: category) else { return own }
        let names = Set(bridges.bridges.filter { $0.status != .paused }.map(\.name))
        return own + RoomAccounts.connected(in: room, names: names).map(\.name)
    }

    // MARK: - Search (§1015)

    /// The field is Accounts' own (`DSSlabField`, the slab rung), at the top
    /// of the tray as it is at the top of Accounts (user ruling, 2026-07-23).
    private var searchField: some View {
        DSSlabField(placeholder: String(localized: "Search"),
                    text: $query, actionLabel: "",
                    focus: $searchFocused,
                    glyph: "magnifyingglass", clearable: true,
                    size: .slab, submitLabel: .search, action: {})
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// What the query leaves: the categories whose name, or the name of an
    /// app inside, has a WORD starting with it ("st" finds Stripe's category
    /// and App Store's, not Instagram's) — Spotlight's rule, accents and case
    /// aside.
    private var searchHits: [String] {
        let q = trimmedQuery
        func starts(_ name: String) -> Bool {
            name.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" })
                .contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
        }
        return categories.filter { starts($0) || appNames(in: $0).contains(where: starts) }
    }

    /// You: five doors, drawn as APP TILES in the brand pink (prd §976,
    /// user, 2026-09-28: "make the You buttons in the tray the same size as
    /// the app tiles and lets color them … maybe they all should be pink
    /// backgrounds"). They were glyphs on a faint disc, which read a size
    /// smaller than the solid brand circles beside them on the next rows
    /// even at the same 28pt — a tinted fill has no edge. Since §976a
    /// (user, after a side-by-side of four treatments: "do C") each door is
    /// a black circle with a brand-pink glyph, and the standing one (Home on
    /// the All feed, Notes in its room) fills pink with a white glyph — the
    /// fill says "you are here", so it needs no ring. The hue is §740's
    /// reading held: the app's own voice, on the one row that is entirely
    /// the app's. Manage's door is deleted (prd §958, user: "both of
    /// these buttons lead to sort of the same place"): Connect opens
    /// Accounts, and its `Connect | Manage` switcher is one tap from what
    /// Manage held.
    ///
    /// Notes is the second door, right after Home (prd §969): the room you
    /// build — the notes you write and everything you pin — behind a door
    /// that is ALWAYS drawn, because a door that appears only once something
    /// is in the room (§961's Pinned) is a door nobody can find the first
    /// time. An empty room draws its empty state (§769), not nothing.
    ///
    /// **Since §1012 the doors are a labelled row across the top, the share
    /// sheet's row of people** (user, choosing "1" of three: "how would apple
    /// design this"). They are the app's own places, not accounts, so they
    /// stand apart from the categories, larger, each with its word under it
    /// — five destinations nobody should have to recognise by glyph alone.
    private var youDoors: [Door] {
        doors(home: filter.source == "All" && route.path.isEmpty,
              notes: Pinboard.isPinnedRoom(filter.source) && route.path.isEmpty)
    }

    /// The You row's doors, in order.
    private struct Door {
        let word: String
        let glyph: String
        var lit = false
        let act: () -> Void
    }

    private func doors(home: Bool = false, notes: Bool = false) -> [Door] {
        [
            Door(word: String(localized: "Home"), glyph: home ? "house.fill" : "house",
                 lit: home) { pick("All") },
            Door(word: String(localized: "Notes"), glyph: notes ? "note.text" : "note",
                 lit: notes) { pick(Pinboard.room) },
            Door(word: String(localized: "Addresses"), glyph: "at") { screen(.addresses) },
            // ONE DOOR FOR SETTINGS (prd §1050g): Apps and Settings became one
            // list — Casberi's own settings pinned first, then every app.
            Door(word: String(localized: "Settings"), glyph: "gearshape") { screen(.apps) },
        ]
    }

    /// A category's row (prd §1053): its glyph bare in the lead column, in
    /// the page's own ink (§1050f), its word, the chevron. It lands in the
    /// category's room. The standing room says so with its filled glyph
    /// (`glyph(for:lit:)`); a broken app inside wears the attention hue on
    /// the glyph, and the label says it too.
    private func categoryRow(_ category: String, index: Int) -> some View {
        let lit = standingCategory == category
        let needsYou = broken(category)
        return Button {
            pick(category)
        } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: glyph(for: category, lit: lit))
                    .dsGlyph(.body)
                    .foregroundStyle(needsYou ? DS.attention : DS.textPrimary)
                    .symbolEffect(.bounce.up, value: lit ? bounceTick : 0)
                    .frame(width: Self.lead)
                Text(category)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                DSChevron()
            }
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(needsYou
            ? Text("\(category), needs your attention")
            : Text(category))
        .accessibilityAddTraits(lit ? .isSelected : [])
        .modifier(Dealt(on: dealt, index: index, reduceMotion: reduceMotion))
    }

    // MARK: - Pieces

    /// A You door's tile (prd §976a, §1050m, §1053): the app-icon squircle
    /// in the categories' charcoal (`surfaceRaised`) with the glyph in the
    /// brand pink, and the standing door turns WHITE behind the same pink
    /// glyph (user: a pink fill "is a bit overkill … maybe white with pink").
    /// Selection is the fill, so the door needs no ring.
    private func doorTile(_ glyph: String, lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.appIcon(Self.lead), style: .continuous)
        return shape
            .fill(lit ? Color.white : DS.surfaceRaised)
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: Self.lead * 0.5, weight: .semibold))
                    .foregroundStyle(DS.brand)
                    .symbolEffect(.bounce.up, value: lit ? bounceTick : 0)
            )
            .frame(width: Self.lead, height: Self.lead)
            .animation(DS.Motion.standard, value: lit)
    }

    /// A You row: the tile, then the word in the heavier rung — the two
    /// marks that it is primary — and no chevron (§1053).
    private func door(_ door: Door, index: Int) -> some View {
        Button(action: door.act) {
            HStack(spacing: DS.Space.s3) {
                doorTile(door.glyph, lit: door.lit)
                Text(door.word)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Self.youRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(door.word))
        .accessibilityAddTraits(door.lit ? .isSelected : [])
        .modifier(Dealt(on: dealt, index: index, reduceMotion: reduceMotion))
    }


    /// One mark's arrival in the cascade: fades and grows in, one step after
    /// the mark before it. Under Reduce Motion it is simply there.
    private struct Dealt: ViewModifier {
        let on: Bool
        let index: Int
        let reduceMotion: Bool
        func body(content: Content) -> some View {
            content
                .opacity(on || reduceMotion ? 1 : 0)
                .scaleEffect(on || reduceMotion ? 1 : 0.6)
                .animation(reduceMotion ? nil
                           : DS.Motion.standard.delay(Double(index) * RoomsTray.dealStep),
                           value: on)
        }
    }

    // MARK: - Acts

    /// Land in a room. A category label resolves through `CategoryFold.landing`
    /// inside `MainSurface`'s `sourceRequest` handler, the way a chip tap did.
    private func pick(_ target: String) {
        DSHaptic.selection()
        close()
        if !route.path.isEmpty { route.path = [] }
        chrome.lastChipTouch = Date.timeIntervalSinceReferenceDate
        chrome.sourceRequest = target
    }

    /// Open Accounts on Connect; its switcher holds Manage (§933, §958).
    /// Open a screen of its own — Settings or Addresses (§933).
    private func screen(_ door: HomeRoute.Node) {
        DSHaptic.selection()
        close()
        route.present(door)
    }

    private func close() {
        drag = 0
        withAnimation(liftMotion) { chrome.roomsTray = false }
    }
}
