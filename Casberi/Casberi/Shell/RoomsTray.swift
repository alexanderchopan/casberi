import SwiftUI

/// The rooms tray (prd §930; the Apple pass §932) — the phone's whole
/// navigation behind ONE button, the face.
///
/// **A floating glass menu since prd §1058** (user: "look how apple does
/// imessage in app tray … lets go back to glass and do it this way … today
/// our tray covers the entire width of the app and it looks weird"). It is
/// Messages' attachment menu: a rounded glass card above the face's corner,
/// about two thirds of the screen wide, scrolling when the list is longer
/// than the card. Since §1061 a row is a name and a run of icons (an app's
/// a rounded square since §1122, in columns under a blurred room):
/// You's four doors (Home, Notes, Addresses, Settings) lead, then each
/// category in the person's Dock order (§1050j) — its own disc, its two
/// most-opened apps, "+N". No grabber and no detents. Since prd §1133 it
/// holds EVERY way to move: Search leads it (the door to Find), You is a row
/// like the others, and every row shows all its apps and accounts, wrapping
/// under its name (§1133b); the pill that picked them in the title row is
/// deleted. Glass on the floating layer is the design
/// law's own place for it; §1014's solid black answered a dense wall of
/// marks, which the tray no longer draws (§1050l).
///
/// **A layer of `RootShell`'s stack, never a sheet (§394):** it sits UNDER
/// the face so the tap that opened it closes it, and a tap anywhere else
/// closes it too. It grows out of the face's corner on the dock's spring and
/// the rows deal in top to bottom. A filled glyph says SELECTED and nothing
/// else; a category with a broken seat wears the attention colour on its
/// glyph and says so. **Every pick is `ShellChrome.sourceRequest`**, the hop
/// every room-to-room door takes.
struct RoomsTray: View {
    /// The rail's width where the shell draws one (iPad, Mac), else 0. With a
    /// rail the face stands at its top, so the card opens beside it from the
    /// top-left corner (prd §1133f); on the phone it grows out of the face's
    /// corner at the bottom.
    var railInset: CGFloat = 0
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route
    @Environment(FeedFilter.self) private var filter
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A row's round icons: the category's own and its apps', one size —
    /// the touch floor since prd §1094 (users: "the menu buttons are super
    /// duper small"; they were `DS.Face.row`, 30). Not the face button's 56:
    /// five discs at 56 are wider than the card, and the face stands
    /// beside the card, so a disc its size would read as a second one.
    static let icon: CGFloat = DS.Face.tray
    /// The gap between icons: 6, and less on a phone too narrow for the You
    /// row's six doors at 6 (prd §1123). The category runs take the same gap,
    /// so their columns stay under the You row's last four.
    static let iconGap: CGFloat = 6
    static let youDoorCount = 6
    static func gap(inner: CGFloat) -> CGFloat {
        let fit = (inner - CGFloat(youDoorCount) * icon) / CGFloat(youDoorCount - 1)
        return max(2, min(iconGap, fit))
    }
    /// A category's run is a fixed four columns — its disc, two apps, "+N" —
    /// standing under the You row's last four, so every category's own disc
    /// sits in ONE column (prd §1122). Right-aligned runs put Markets' disc at
    /// the far edge and Testnets' in the middle.
    /// A row's name line: the touch floor tall, its word sitting at the
    /// bottom, over its icons (prd §1133c).
    static let nameHeight: CGFloat = DS.Hit.min
    /// 60 since prd §1094a (user: "create some space between the rows so it
    /// doesn't look so cramped"): 16pt between a row's 44pt discs and the
    /// next, and ten rows before the card scrolls on a 17 Pro.
    static let rowHeight: CGFloat = 60
    /// The card's corner: Messages' menu, a continuous corner.
    static let radius: CGFloat = 32
    /// How much of the screen the card may take: 330 wide since §1123 (320
    /// since §1094), exactly the You row's six 44pt doors at a 6pt gap inside
    /// the card's 18pt sides — most of a 375pt phone, where the gap gives a
    /// point, and four fifths of a 402pt one — and three quarters down before
    /// it scrolls.
    static let widthShare: CGFloat = 0.86
    static let maxWidth: CGFloat = 330
    static let heightShare: CGFloat = 0.72
    /// The stagger between one row's arrival and the next.
    static let dealStep: Double = 0.02

    @State private var contentHeight: CGFloat = 0
    /// What the tray's search holds (prd §1133e); cleared when it closes.
    @State private var query = ""
    @FocusState private var searching: Bool
    @State private var dealt = false
    @State private var bounceTick = 0

    private var liftMotion: Animation { reduceMotion ? DS.Motion.glide : DS.Motion.folder }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: corner) {
                if chrome.roomsTray {
                    // The catcher: a tap anywhere else closes the menu — a
                    // real control, so it is a Button. It BLURS the room, as
                    // Messages' plus menu does (prd §1122, amending §1058's
                    // clear catcher): the room's box stood out past the card's
                    // edge and its pink ink bled through the glass.
                    Button {
                        close()
                    } label: {
                        DSBackdropBlur().ignoresSafeArea()
                    }
                    .buttonStyle(.plain)
                    // …and a SWIPE anywhere else closes it too (2026-10-03,
                    // user: "trays get stuck … not easy to swipe down or
                    // dismiss"). The drag cancelled the Button's tap, so a
                    // swipe — the gesture every other tray answers — did
                    // nothing at all. Messages' menu closes on either.
                    .highPriorityGesture(DragGesture(minimumDistance: 12).onEnded { _ in close() })
                    .accessibilityLabel(Text("Close rooms"))
                    .transition(.opacity)
                    panel(screen: geo.size, top: geo.safeAreaInsets.top)
                        // Out of the face's corner and back into it (§932).
                        .transition(reduceMotion
                            ? .opacity
                            : .scale(scale: 0.06, anchor: railInset > 0 ? .topLeading : .bottomLeading)
                                .combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
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
        }
        #endif
        .onChange(of: chrome.roomsTray) { _, up in
            // Deal the rows in once the card has landed; under Reduce Motion
            // they are simply there.
            dealt = up
            if up && !reduceMotion { bounceTick += 1 }
            if !up { query = ""; searching = false }
        }
    }

    // MARK: - The card

    private func panel(screen: CGSize, top safeTop: CGFloat = 0) -> some View {
        let width = min(screen.width * Self.widthShare, Self.maxWidth)
        // Searching, the card stands at its full height, so its field stays
        // above the keyboard however few results there are (prd §1133e).
        // Beside the rail the card hangs from the top, under the status bar
        // and the demo's pill (§1133f).
        let railTopInset = railInset > 0 ? safeTop + DSDemoMark.screenClearance + Self.railTop : 0
        let full = (screen.height - railTopInset) * Self.heightShare
        let height = (searching || !query.isEmpty) ? full : min(contentHeight, full)
        let gap = Self.gap(inner: width - 2 * DS.Space.s4)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    youRow(gap: gap)
                    recentRow(gap: gap)
                    ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                        categoryRow(category, index: index + 2, gap: gap)
                    }
                } else {
                    searchResults
                }
            }
            .padding(.vertical, DS.Space.s3)
            .padding(.horizontal, DS.Space.s4)
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { contentHeight = g.size.height }
                        .onChange(of: g.size.height) { _, h in contentHeight = h }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .frame(width: width, height: max(height, 1))
        .dsGlass(cornerRadius: Self.radius)
        // Above the face, in its column: the menu grows out of the button
        // that raised it, as Messages' grows out of its plus. Beside the
        // rail's face on the iPad and the Mac (§1133f), clear of the Mac's
        // window buttons.
        .padding(.leading, railInset > 0 ? railInset + DS.Space.s2 : DSRoomChassis.inset)
        .padding(.bottom, railInset > 0 ? 0 : DSDock.seatClearance)
        .padding(.top, railTopInset)
        .accessibilityAddTraits(.isModal)
    }

    /// Where the card stands: by the face's corner.
    private var corner: Alignment { railInset > 0 ? .topLeading : .bottomLeading }

    /// The card's top beside the rail's face: under the Mac's window buttons
    /// (the rail clears them by `s8`), a step down on the iPad.
    static var railTop: CGFloat {
        ProcessInfo.processInfo.isMacCatalystApp ? DS.Space.s8 + DS.Space.s2 : DS.Space.s4
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
            $0 != Self.markets
                && CategoryFold.isCategory($0) && !(chrome.categoryVenues[$0] ?? []).isEmpty
        }
    }

    /// Markets is a You door, not a category row (prd §1123, user: "it's only
    /// one app tile that is important but is part of a long catalogue list
    /// someone may not see it. it's also tied to things you have connected").
    /// It is Casberi's own index of the companies behind your apps, so it
    /// wears the pink of the app's own places. Since §1127 it is a place in
    /// Home, out of the swipe and the dock's order, like Notes.
    static let markets = HomeScope.markets

    /// Whether Markets has a room yet — it does once something is watched.
    private var marketsHasRoom: Bool {
        !(chrome.categoryVenues[Self.markets] ?? []).isEmpty
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
        let place = route.path.isEmpty ? HomeScope.Place(source: filter.source) : nil
        return doors(home: filter.source == "All" && route.path.isEmpty,
                     notes: Pinboard.isPinnedRoom(filter.source) && route.path.isEmpty,
                     markets: HomeScope.isMarkets(filter.source) && route.path.isEmpty,
                     place: place)
    }

    /// The You row's doors, in order.
    private struct Door {
        let word: String
        let glyph: String
        var lit = false
        /// What `ChipMemory` counts a landing on this place as.
        var key: String = ""
        let act: () -> Void
    }

    private func doors(home: Bool = false, notes: Bool = false, markets: Bool = false,
                       place: HomeScope.Place? = nil) -> [Door] {
        [
            Door(word: String(localized: "Home"), glyph: home ? "house.fill" : "house",
                 lit: home, key: "All") { pick("All") },
            // You's four places, in the tiles' order (prd §1136 item 1):
            // Home, then A–Z. Apps and Addresses are filters inside Sources
            // now, the master list of everything you've connected.
            // Markets (prd §1123): its room once something is watched, else
            // the page where the first stock or token is added, so the door
            // is always drawn (§969).
            Door(word: String(localized: "Markets"), glyph: CategoryFold.glyph(for: Self.markets),
                 lit: markets, key: Self.markets) {
                if marketsHasRoom { pickCategory(Self.markets) } else { setup(Self.markets) }
            },
            Door(word: String(localized: "Notes"), glyph: notes ? "note.text" : "note",
                 lit: notes, key: Pinboard.room) { pick(Pinboard.room) },
            Door(word: String(localized: "Sources"), glyph: ScopeTileGlyph.sources,
                 lit: place == .settings || place == .apps || place == .addresses,
                 key: HomeScope.Place.settings.source) { screen(.casberi) },
        ]
    }

    /// A category's row (prd §1061, user: "what if the icon for the category
    /// is the first icon where the apps are now … that way if you touch that
    /// icon you go to the room"): its name on its own line, then a run of
    /// icons — the category's own glyph on a plain disc first, then EVERY app
    /// and account in it, six to a line (prd §1133b, §1133c, user: "i think
    /// we have to go back to tray and display all the apps"; the "+N" folder
    /// repeated the row's icons and had to be opened every time). The name and the disc land in the category's room on All;
    /// an icon lands in the room scoped to it, the one showing ringed. The
    /// standing category fills its glyph; a broken app inside wears the
    /// attention hue on the category's glyph, and the label says it too.
    private func categoryRow(_ category: String, index: Int, gap: CGFloat) -> some View {
        let lit = standingCategory == category
        let needsYou = broken(category)
        let folder = folder(for: category)
        return wrapped(folder, gap: gap) {
            Button {
                pickCategory(category)
            } label: {
                Text(category)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: Self.nameHeight, alignment: .bottomLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityLabel(needsYou
                ? Text("\(category), needs your attention")
                : Text(category))
            .accessibilityAddTraits(lit ? .isSelected : [])
        } lead: {
            Button {
                pickCategory(category)
            } label: {
                roundIcon(glyph(for: category, lit: lit),
                          ink: needsYou ? DS.attention : DS.textPrimary,
                          fill: lit ? DS.fillStrong : DS.surfaceRaised,
                          bounces: lit)
            }
            .buttonStyle(PressSpring())
            .dsTapTarget()
            .accessibilityLabel(Text("All of \(category)"))
        }
        .modifier(Dealt(on: dealt, index: index, reduceMotion: reduceMotion))
    }

    /// The apps a row shows: a merged room's connected apps, the ones you
    /// open most first (`ChipMemory`, which counts every tray pick), the
    /// room's own A–Z after that. A category that is not one room shows its
    /// rooms; one whose only room is itself (Markets, Social) shows none.
    private func rowApps(in category: String) -> [RoomAccounts.Seat] {
        let seats: [RoomAccounts.Seat]
        if let room = mergedRoom(in: category) {
            let names = Set(bridges.bridges.filter { $0.status != .paused }.map(\.name))
            seats = RoomAccounts.connected(in: room, names: names).filter(chrome.seatShows)
        } else {
            seats = self.seats(in: category).filter { $0 != category }.map {
                RoomAccounts.Seat(name: $0, source: $0, holder: nil, group: "",
                                  mark: BridgeCatalog.seatName(forSource: $0))
            }
        }
        let weights = ChipMemory.snapshot()
        let ranked = seats.enumerated().sorted { a, b in
            let wa = ChipMemory.weight(for: a.element.source ?? a.element.name,
                                       counts: weights.counts, lastVisit: weights.lastVisit)
            let wb = ChipMemory.weight(for: b.element.source ?? b.element.name,
                                       counts: weights.counts, lastVisit: weights.lastVisit)
            return wa != wb ? wa > wb : a.offset < b.offset
        }
        return ranked.map(\.element)
    }

    /// RECENT (prd §1136 item 8): the apps you went to last, newest first,
    /// one line of six under You. Never a You door — those are one tap
    /// already — only what sits deeper: an app inside a category. Read off
    /// `ChipMemory`'s visit stamps, the same record that ranks a row's apps.
    private var recentItems: [FolderItem] {
        let names = Set(bridges.bridges.filter { $0.status != .paused }.map(\.name))
        var seen = Set<String>()
        var out: [FolderItem] = []
        for key in ChipMemory.recent() {
            guard !HomeScope.contains(key), key != Self.markets,
                  let host = RoomAccounts.host(ofSource: key),
                  RoomAccounts.connected(in: host.room, names: names).contains(where: { $0.name == host.seat.name }),
                  seen.insert(host.seat.name).inserted else { continue }
            let seat = host.seat
            out.append(FolderItem(id: "recent:" + seat.name, name: seat.name, face: .app(seat.mark), lit: false) {
                pick(seat.source ?? seat.name)
            })
            if out.count == Self.lineSlots { break }
        }
        return out
    }

    @ViewBuilder
    private func recentRow(gap: CGFloat) -> some View {
        let items = recentItems
        if let first = items.first {
            wrapped(Folder(items: Array(items.dropFirst()), action: nil), gap: gap) {
                Text("Recent")
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: Self.nameHeight, alignment: .bottomLeading)
                    .accessibilityAddTraits(.isHeader)
            } lead: {
                Button(action: first.act) { itemFace(first) }
                    .buttonStyle(PressSpring())
                    .dsTapTarget()
                    .accessibilityLabel(Text(verbatim: first.name))
            }
            .modifier(Dealt(on: dealt, index: 1, reduceMotion: reduceMotion))
        }
    }

    /// You: the app's own places on one row (prd §1061, user: "put home
    /// notes and settings in a row together and have a 'You' category
    /// again"). A disc per door — Home, Notes, Markets (§1123), Apps,
    /// Addresses, Settings — the glyphs in the brand pink (§976a), the standing door's
    /// disc white behind the same glyph (§1053).
    private func youRow(gap: CGFloat) -> some View {
        // **A ROW LIKE EVERY OTHER (prd §1133, §1133c).** Your name, else You
        // (`HomeScope.title`, the screen title's word; §1133d: the name line
        // runs the card's width now, so the truncation §1133a answered is
        // gone), then Home's disc where a category's own stands and the other
        // five places, one line of six.
        let doors = youDoors
        let home = doors[0]
        let rest = Folder(items: doors.dropFirst().map { door in
            FolderItem(id: door.key, name: door.word, face: .place(door.glyph),
                       lit: door.lit, act: door.act)
        }, action: nil)
        return wrapped(rest, gap: gap) {
            Button(action: home.act) {
                Text(verbatim: HomeScope.title)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: Self.nameHeight, alignment: .bottomLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
        } lead: {
            Button(action: home.act) {
                roundIcon(home.glyph, ink: DS.brand,
                          fill: home.lit ? Color.white : DS.surfaceRaised,
                          bounces: home.lit)
            }
            .buttonStyle(PressSpring())
            .dsTapTarget()
            .accessibilityLabel(Text(home.word))
            .accessibilityAddTraits(home.lit ? .isSelected : [])
        }
        .modifier(Dealt(on: dealt, index: 0, reduceMotion: reduceMotion))
    }

    // MARK: - Search (prd §1133)

    /// **ONE SEARCH, AT THE TOP OF THE TRAY (prd §1133, §1133e, user: "i
    /// like the search tho"; "fix 1").** It filters the tray as you type, as
    /// the App Library's does: every app, account, place and category whose
    /// name holds the words, each saying where it lives, and last a row that
    /// searches your THINGS for the same words in Find. It opened Find
    /// directly until §1133e, which found everything but the apps the tray
    /// had just grown to hold.
    private var searchField: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(.body)
                .foregroundStyle(DS.textSecondary)
            TextField(String(localized: "Search"), text: $query)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { searchThings() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(.body)
                        .foregroundStyle(DS.textTertiary)
                }
                .buttonStyle(PressSpring())
                .dsTapTarget()
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: Self.searchHeight)
        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, DS.Space.s2)
        .modifier(Dealt(on: dealt, index: 0, reduceMotion: reduceMotion))
    }

    /// One thing the search can land on.
    private struct Hit: Identifiable {
        let id: String
        let name: String
        /// Where it lives ("Wallet", "You"), nil for a category itself.
        let place: String?
        let face: FolderItem.Face?
        let glyph: String?
        let act: () -> Void
    }

    /// Everything the tray holds, as hits: You's places, each category and
    /// every app and account in it — the same items and the same acts the
    /// rows draw, so a hit lands where its icon would.
    private var allHits: [Hit] {
        var hits = youDoors.map { door in
            Hit(id: "you:" + door.key, name: door.word, place: String(localized: "You"),
                face: .place(door.glyph), glyph: nil, act: door.act)
        }
        for category in categories {
            hits.append(Hit(id: "cat:" + category, name: category, place: nil, face: nil,
                            glyph: CategoryFold.glyph(for: category)) { pickCategory(category) })
            for item in folder(for: category).items {
                hits.append(Hit(id: category + ":" + item.id, name: item.name, place: category,
                                face: item.face, glyph: nil, act: item.act))
            }
        }
        // People (prd §1136 item 3): they live in Sources now, so the
        // search finds them by name and lands on them there. The index is
        // the snapshot Settings and the book build; a person not yet indexed
        // is found once either has been opened.
        for contact in ContactIndexSources.contacts
            where !contact.isUnnamed && !ContactIndexSources.isYours(contact) {
            hits.append(Hit(id: "person:" + contact.id, name: contact.name,
                            place: String(localized: "People"), face: .person(contact), glyph: nil) {
                chrome.settingsPeopleQuery = contact.name
                screen(.casberi)
            })
        }
        return hits
    }

    @ViewBuilder
    private var searchResults: some View {
        let words = query.trimmingCharacters(in: .whitespaces)
        // A name that STARTS with the words first ("co": Coinbase before
        // Acorns), then any word in it, then anywhere; the tray's order within.
        let hits = allHits.enumerated()
            .compactMap { i, hit -> (Int, Int, Hit)? in
                guard hit.name.localizedStandardContains(words) else { return nil }
                let name = hit.name.lowercased(), w = words.lowercased()
                let rank = name.hasPrefix(w) ? 0 : name.contains(" " + w) ? 1 : 2
                return (rank, i, hit)
            }
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map(\.2)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hits) { hit in
                Button(action: hit.act) {
                    HStack(spacing: DS.Space.s3) {
                        Group {
                            if let face = hit.face {
                                itemFace(FolderItem(id: hit.id, name: hit.name, face: face,
                                                    lit: false, act: hit.act))
                            } else if let glyph = hit.glyph {
                                roundIcon(glyph, ink: DS.textPrimary, fill: DS.surfaceRaised, bounces: false)
                            }
                        }
                        .frame(width: Self.icon, height: Self.icon)
                        Text(verbatim: hit.name)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        if let place = hit.place {
                            Text(verbatim: place)
                                .dsText(.body17)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minHeight: Self.resultHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(hit.place.map { Text(verbatim: "\(hit.name), \($0)") }
                                    ?? Text(verbatim: hit.name))
            }
            // Your things, through Find: the one search over everything kept.
            Button(action: searchThings) {
                HStack(spacing: DS.Space.s3) {
                    roundIcon("magnifyingglass", ink: DS.textPrimary, fill: DS.surfaceRaised, bounces: false)
                    Text("Search your things for “\(words)”")
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Self.resultHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
        }
    }

    static let resultHeight: CGFloat = 56

    /// Hand the words to Find and close the tray.
    private func searchThings() {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return }
        DSHaptic.selection()
        close()
        chrome.openFind(words)
    }

    static let searchHeight: CGFloat = 40

    // MARK: - A row's items (prd §1133, §1133b)

    /// Everything a row holds, all drawn (the "+N" folder that opened them
    /// is deleted, §1133b): every app and account, and the room's act.
    private struct Folder {
        var items: [FolderItem]
        var action: DSRoomAction?
    }

    private struct FolderItem: Identifiable {
        enum Face { case app(String), wallet(String), place(String), person(Contact) }
        let id: String
        let name: String
        let face: Face
        let lit: Bool
        let act: () -> Void
    }

    /// What a category's folder holds. The Wallet's is read off the store,
    /// so it is whole from any room: your addresses, then its apps, and
    /// Follow a wallet. A room standing on screen that publishes its
    /// accounts (a devnet's) shows those; otherwise a category's apps.
    private func folder(for category: String) -> Folder {
        let standing = standingCategory == category
        let room = mergedRoom(in: category)
        if room == CategoryFold.walletRoom {
            let scope = standing ? chrome.walletScope : nil
            let addresses = WalletStore.shared.addresses.map { addr in
                FolderItem(id: addr.address,
                           name: addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label,
                           face: .wallet(addr.address),
                           lit: scope?.caseInsensitiveCompare(addr.address) == .orderedSame) {
                    chrome.walletScope = addr.address
                    pick(CategoryFold.walletRoom)
                }
            }
            let apps = rowApps(in: category).map { seat in
                let id = RoomAccounts.scopeID(seat)
                return FolderItem(id: id, name: seat.name, face: .app(seat.mark), lit: scope == id) {
                    pick(seat.source ?? seat.name)
                }
            }
            let follow = DSRoomAction(title: String(localized: "Follow a wallet"), symbol: "plus") {
                chrome.walletFollowPending = true
                pick(CategoryFold.walletRoom)
            }
            return Folder(items: addresses + apps, action: follow)
        }
        if standing, let rail = chrome.accountRail,
           rail.source == filter.source || filter.source == RoomAccounts.testnetsRoom {
            let items = rail.slots.filter { !$0.id.isEmpty }.map { slot in
                FolderItem(id: slot.id, name: slot.name, face: Self.face(slot),
                           lit: slot.isShowing(rail.scope)) {
                    DSHaptic.selection()
                    close()
                    rail.onPick(slot.id)
                }
            }
            let action = rail.action.map { act in
                DSRoomAction(title: act.title, symbol: act.symbol) { close(); act.run() }
            }
            return Folder(items: items, action: action)
        }
        let scope = room.flatMap { chrome.mergedScope[$0] }
        let items = rowApps(in: category).map { seat in
            let id = RoomAccounts.scopeID(seat)
            let lit = standing && (room != nil ? scope == id : filter.source == seat.source)
            return FolderItem(id: id, name: seat.name, face: .app(seat.mark), lit: lit) {
                pick(seat.source ?? seat.name)
            }
        }
        return Folder(items: items, action: nil)
    }

    private static func face(_ slot: DSAccountSlot) -> FolderItem.Face {
        switch slot.faces.first {
        case .wallet(let address)?: .wallet(address)
        case .mark(_, let source)?, .avatar(_, let source)?: .app(source)
        case nil: slot.symbol.map { .place($0) } ?? .app(slot.name)
        }
    }

    /// A row: its name on a line of its own, and under it a run of icons —
    /// its lead (the category's disc, or Home's), the room's act (Follow a
    /// wallet, New account) next, never last (§1107: "it shouldn't go at the
    /// bottom b/c someone may have tons of things there"), then every item,
    /// the one showing ringed in pink, six to a line at the card's full width
    /// (prd §1133c, user: "each category starts on the line below the
    /// category, so You's six tiles all fit on one row"). The App Library's
    /// grammar: a name, then its icons in one grid; every line the same six
    /// columns, You's places on one line, a long category simply running on.
    private func wrapped<Name: View, Lead: View>(_ folder: Folder, gap: CGFloat,
                                                  @ViewBuilder name: () -> Name,
                                                  @ViewBuilder lead: () -> Lead) -> some View {
        var cells: [RunCell] = [.lead]
        if let action = folder.action { cells.append(.action(action)) }
        cells += folder.items.map(RunCell.item)
        let lines = stride(from: 0, to: cells.count, by: Self.lineSlots).map {
            Array(cells[$0 ..< min($0 + Self.lineSlots, cells.count)])
        }
        let leadView = lead()
        return VStack(alignment: .leading, spacing: 0) {
            name()
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: gap) {
                    ForEach(line) { cell in runCell(cell, lead: leadView) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Self.lineGap / 2)
            }
        }
    }

    /// The space between two lines of icons: 16, the gap §1094a put between
    /// one row's discs and the next.
    static let lineGap: CGFloat = rowHeight - icon

    /// One place in a run.
    private enum RunCell: Identifiable {
        case lead
        case action(DSRoomAction)
        case item(FolderItem)
        var id: String {
            switch self {
            case .lead: "lead"
            case .action: "action"
            case .item(let item): "item:" + item.id
            }
        }
    }

    /// A full line under the name holds six: You's row, the width the card
    /// is sized for.
    static let lineSlots = youDoorCount

    @ViewBuilder
    private func runCell<Lead: View>(_ cell: RunCell, lead: Lead) -> some View {
        switch cell {
        case .lead:
            lead
        case .action(let action):
            Button {
                DSHaptic.selection()
                action.run()
            } label: {
                roundIcon(action.symbol, ink: DS.textPrimary, fill: DS.surfaceRaised, bounces: false)
            }
            .buttonStyle(PressSpring())
            .dsTapTarget()
            .accessibilityLabel(Text(action.title))
        case .item(let item):
            Button(action: item.act) {
                itemFace(item)
            }
            .buttonStyle(PressSpring())
            .dsTapTarget()
            .accessibilityLabel(Text(verbatim: item.name))
            .accessibilityAddTraits(item.lit ? .isSelected : [])
        }
    }

    /// An item's icon: an app a rounded square, an address or a place a
    /// circle (§1122), the one showing ringed in pink.
    @ViewBuilder
    private func itemFace(_ item: FolderItem) -> some View {
        switch item.face {
        case .app(let mark):
            BridgeIcon(name: mark, size: Self.icon)
                .overlay {
                    if item.lit {
                        RoundedRectangle(cornerRadius: Self.icon * 0.26, style: .continuous)
                            .stroke(DS.brand, lineWidth: 2).padding(-3)
                    }
                }
        case .wallet(let address):
            WalletFace(address: address, size: Self.icon, circular: true)
                .overlay { if item.lit { Circle().stroke(DS.brand, lineWidth: 2).padding(-3) } }
        case .place(let glyph):
            roundIcon(glyph, ink: DS.brand, fill: item.lit ? Color.white : DS.surfaceRaised,
                      bounces: item.lit)
        case .person(let contact):
            ContactFace(contact: contact, size: Self.icon)
        }
    }

    // MARK: - Pieces

    /// The round icon: a glyph on a plain disc, and the standing place's
    /// disc a step lighter, its glyph filled.
    private func roundIcon(_ glyph: String, ink: Color, fill: Color, bounces: Bool) -> some View {
        Circle()
            .fill(fill)
            .overlay(
                Image(systemName: glyph)
                    .dsGlyph(.title, weight: .medium)
                    .foregroundStyle(ink)
                    .symbolEffect(.bounce.up, value: bounces ? bounceTick : 0)
            )
            .frame(width: Self.icon, height: Self.icon)
            .animation(DS.Motion.standard, value: fill)
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

    /// Open an app's page to start it — Markets before anything is watched.
    private func setup(_ offer: String) {
        DSHaptic.selection()
        close()
        route.openSetup(forOffer: offer)
    }

    /// Open a screen of its own — Apps, Addresses or Settings (§933, §1111).
    private func screen(_ door: HomeRoute.Node) {
        DSHaptic.selection()
        close()
        route.present(door)
    }

    /// Land in a category's room on All: its name, its disc and its "+N"
    /// say the whole category, so a pick an app made earlier is dropped.
    private func pickCategory(_ category: String) {
        if let room = mergedRoom(in: category) {
            if room == CategoryFold.walletRoom {
                chrome.walletScope = nil
            } else {
                chrome.mergedScope[room] = nil
            }
        }
        pick(category)
    }

    private func close() {
        withAnimation(liftMotion) { chrome.roomsTray = false }
    }
}
