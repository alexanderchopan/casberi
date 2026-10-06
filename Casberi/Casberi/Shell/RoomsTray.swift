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
/// like the others, and "+N" opens a row in place as a folder of every app
/// and account; the pill that picked them in the title row is deleted. Glass on the floating layer is the design
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
    /// How many apps a row shows before its "+N" — two since §1094, so the
    /// category's own disc keeps its seat at 44 and the name keeps its room.
    static let appsShown = 2
    /// A category's run is a fixed four columns — its disc, two apps, "+N" —
    /// standing under the You row's last four, so every category's own disc
    /// sits in ONE column (prd §1122). Right-aligned runs put Markets' disc at
    /// the far edge and Testnets' in the middle.
    static let runSlots = 4
    static func runWidth(gap: CGFloat) -> CGFloat { CGFloat(runSlots) * icon + CGFloat(runSlots - 1) * gap }
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
    /// The row whose folder is open (a category, or `Self.youRowID`), one at
    /// a time; closing the tray shuts it.
    @State private var openFolder: String?
    static let youRowID = "you:row"
    @State private var dealt = false
    @State private var bounceTick = 0

    private var liftMotion: Animation { reduceMotion ? DS.Motion.glide : DS.Motion.folder }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
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
                    panel(screen: geo.size)
                        // Out of the face's corner and back into it (§932).
                        .transition(reduceMotion
                            ? .opacity
                            : .scale(scale: 0.06, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
            if !up { openFolder = nil }
        }
    }

    // MARK: - The card

    private func panel(screen: CGSize) -> some View {
        let width = min(screen.width * Self.widthShare, Self.maxWidth)
        let height = min(contentHeight, screen.height * Self.heightShare)
        let gap = Self.gap(inner: width - 2 * DS.Space.s4)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                youRow(gap: gap)
                if openFolder == Self.youRowID { folderGrid(youFolder) }
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    categoryRow(category, index: index + 1, gap: gap)
                    if openFolder == category { folderGrid(folder(for: category)) }
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
        .frame(width: width, height: max(height, 1))
        .dsGlass(cornerRadius: Self.radius)
        // Above the face, in its column: the menu grows out of the button
        // that raised it, as Messages' grows out of its plus.
        .padding(.leading, DSRoomChassis.inset)
        .padding(.bottom, DSDock.seatClearance)
        .accessibilityAddTraits(.isModal)
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
            Door(word: String(localized: "Notes"), glyph: notes ? "note.text" : "note",
                 lit: notes, key: Pinboard.room) { pick(Pinboard.room) },
            // Markets (prd §1123): its room once something is watched, else
            // the page where the first stock or token is added — the door
            // its Apps row opens — so the door is always drawn (§969).
            Door(word: String(localized: "Markets"), glyph: CategoryFold.glyph(for: Self.markets),
                 lit: markets, key: Self.markets) {
                if marketsHasRoom { pickCategory(Self.markets) } else { setup(Self.markets) }
            },
            // APPS AND SETTINGS ARE TWO DOORS AGAIN (prd §1111, reversing
            // §1050g): Apps is everything you can connect, what you have
            // marked; Settings is Casberi's own options and nothing else.
            // Places in You since prd §1129: the door lands, nothing pushes.
            Door(word: String(localized: "Apps"), glyph: ScopeTileGlyph.apps,
                 lit: place == .apps, key: HomeScope.Place.apps.source) { screen(.apps) },
            Door(word: String(localized: "Addresses"), glyph: "at",
                 lit: place == .addresses, key: HomeScope.Place.addresses.source) { screen(.addresses) },
            Door(word: String(localized: "Settings"), glyph: "gearshape",
                 lit: place == .settings, key: HomeScope.Place.settings.source) { screen(.casberi) },
        ]
    }

    /// A category's row (prd §1061, user: "what if the icon for the category
    /// is the first icon where the apps are now … that way if you touch that
    /// icon you go to the room"): its name, then a run of round icons — the
    /// category's own glyph on a plain disc first, then the two apps you (three
    /// until §1094) open most, then "+N" for the rest, so nobody reads two as all
    /// there is. The name, the category's disc and the "+N" land in the
    /// category's room on All; an app lands in the room scoped to it. The
    /// standing category fills its glyph; a broken app inside wears the
    /// attention hue on the category's glyph, and the label says it too.
    private func categoryRow(_ category: String, index: Int, gap: CGFloat) -> some View {
        let lit = standingCategory == category
        let needsYou = broken(category)
        let apps = rowApps(in: category)
        let shown = Array(apps.prefix(Self.appsShown))
        let folder = folder(for: category)
        let more = folder.items.count - shown.count
        return HStack(spacing: DS.Space.s3) {
            Button {
                pickCategory(category)
            } label: {
                Text(category)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityLabel(needsYou
                ? Text("\(category), needs your attention")
                : Text(category))
            .accessibilityAddTraits(lit ? .isSelected : [])
            HStack(spacing: gap) {
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
                .contentShape(Rectangle().inset(by: -Self.iconGap / 2))
                .accessibilityLabel(Text("All of \(category)"))
                // An app is a rounded square, a place a circle (prd §1122).
                ForEach(shown, id: \.name) { app in
                    Button {
                        pick(app.source ?? app.name)
                    } label: {
                        BridgeIcon(name: app.mark, size: Self.icon)
                    }
                    .buttonStyle(PressSpring())
                    .dsTapTarget()
                    .contentShape(Rectangle().inset(by: -Self.iconGap / 2))
                    .accessibilityLabel(Text(app.name))
                }
                folderKey(category, more: more, action: folder.action)
            }
            .frame(width: Self.runWidth(gap: gap), alignment: .leading)
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

    /// You: the app's own places on one row (prd §1061, user: "put home
    /// notes and settings in a row together and have a 'You' category
    /// again"). A disc per door — Home, Notes, Markets (§1123), Apps,
    /// Addresses, Settings — the glyphs in the brand pink (§976a), the standing door's
    /// disc white behind the same glyph (§1053).
    private func youRow(gap: CGFloat) -> some View {
        // **A ROW LIKE EVERY OTHER, AND A FOLDER (prd §1133, user: "should
        // the 'You' row also be a folder like wallet etc … b/c now we can do
        // that").** Its name (yours, else You), Home's disc where a
        // category's own stands, the two places you open most, and "+N" for
        // the folder of all six. One grammar for the whole tray.
        let doors = youDoors
        let home = doors[0]
        let shown = Array(rankedYouDoors(Array(doors.dropFirst())).prefix(Self.appsShown))
        let more = doors.count - 1 - shown.count
        return HStack(spacing: DS.Space.s3) {
            Button(action: home.act) {
                Text(verbatim: HomeScope.title)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityLabel(Text("You"))
            HStack(spacing: gap) {
                ForEach(Array(([home] + shown).enumerated()), id: \.offset) { _, door in
                    Button(action: door.act) {
                        roundIcon(door.glyph, ink: DS.brand,
                                  fill: door.lit ? Color.white : DS.surfaceRaised,
                                  bounces: door.lit)
                    }
                    .buttonStyle(PressSpring())
                    .dsTapTarget()
                    .contentShape(Rectangle().inset(by: -Self.iconGap / 2))
                    .accessibilityLabel(Text(door.word))
                    .accessibilityAddTraits(door.lit ? .isSelected : [])
                }
                folderKey(Self.youRowID, more: more, action: nil)
            }
            .frame(width: Self.runWidth(gap: gap), alignment: .leading)
        }
        .modifier(Dealt(on: dealt, index: 0, reduceMotion: reduceMotion))
    }

    /// You's places after Home, the ones you open most first (`ChipMemory`
    /// counts every landing), the tray's order after that.
    private func rankedYouDoors(_ doors: [Door]) -> [Door] {
        let weights = ChipMemory.snapshot()
        return doors.enumerated().sorted { a, b in
            let wa = ChipMemory.weight(for: a.element.key, counts: weights.counts, lastVisit: weights.lastVisit)
            let wb = ChipMemory.weight(for: b.element.key, counts: weights.counts, lastVisit: weights.lastVisit)
            return wa != wb ? wa > wb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: - Search (prd §1133)

    /// **ONE SEARCH, AT THE TOP OF THE TRAY (prd §1133, user: "i like the
    /// search tho").** §1015's field left with the full-width sheet it led;
    /// it returns as the door to Find, the composer that searches everything
    /// you keep, so the tray holds every way to move.
    private var searchField: some View {
        Button {
            DSHaptic.selection()
            close()
            chrome.openComposer()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "magnifyingglass")
                    .dsGlyph(.body)
                Text("Search")
                    .dsText(.body17)
                Spacer(minLength: 0)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.Space.s3)
            .frame(height: Self.searchHeight)
            .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .padding(.bottom, DS.Space.s2)
        .accessibilityLabel(Text("Search"))
        .modifier(Dealt(on: dealt, index: 0, reduceMotion: reduceMotion))
    }

    static let searchHeight: CGFloat = 40

    // MARK: - Folders (prd §1133)

    /// **A ROW OPENS LIKE A HOME SCREEN FOLDER (prd §1133, user: "B").**
    /// "+N" opens it in place: every app and account the category holds,
    /// each icon with its name under it, five across, the one showing
    /// ringed; the room's act (Follow a wallet, New account) first, as it
    /// led the deleted pill's list (§1107). The tray reads name-left,
    /// icons-right, and a folder is more icons, so the grammar holds.
    private struct Folder {
        var items: [FolderItem]
        var action: DSRoomAction?
    }

    private struct FolderItem: Identifiable {
        enum Face { case app(String), wallet(String), place(String) }
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

    /// You's folder: the six places, the one you stand in ringed.
    private var youFolder: Folder {
        Folder(items: youDoors.map { door in
            FolderItem(id: door.key, name: door.word, face: .place(door.glyph),
                       lit: door.lit, act: door.act)
        }, action: nil)
    }

    private static func face(_ slot: DSAccountSlot) -> FolderItem.Face {
        switch slot.faces.first {
        case .wallet(let address)?: .wallet(address)
        case .mark(_, let source)?, .avatar(_, let source)?: .app(source)
        case nil: slot.symbol.map { .place($0) } ?? .app(slot.name)
        }
    }

    /// The last slot of a row's run: "+N" opens the folder (a chevron closes
    /// it); with nothing hidden, the room's act stands there as a plus.
    @ViewBuilder
    private func folderKey(_ row: String, more: Int, action: DSRoomAction?) -> some View {
        if more > 0 {
            let open = openFolder == row
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { openFolder = open ? nil : row }
            } label: {
                Group {
                    if open {
                        Image(systemName: "chevron.up").dsGlyph(.body)
                    } else {
                        // Plain words, not a disc: a count is not a place.
                        Text(verbatim: "+\(more)").dsText(.body17)
                    }
                }
                .foregroundStyle(DS.textSecondary)
                .frame(width: Self.icon, height: Self.icon)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(open ? Text("Close folder") : Text("\(more) more"))
        } else if let action {
            Button {
                DSHaptic.selection()
                action.run()
            } label: {
                roundIcon(action.symbol, ink: DS.textPrimary, fill: DS.surfaceRaised, bounces: false)
            }
            .buttonStyle(PressSpring())
            .dsTapTarget()
            .accessibilityLabel(Text(action.title))
        }
    }

    private func folderGrid(_ folder: Folder) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.s1, alignment: .top),
                            count: Self.folderColumns)
        return LazyVGrid(columns: columns, spacing: DS.Space.s3) {
            if let action = folder.action {
                folderCell(name: action.title, face: .place(action.symbol), lit: false,
                           ink: DS.textPrimary, phrase: true) {
                    DSHaptic.selection()
                    action.run()
                }
            }
            ForEach(folder.items) { item in
                folderCell(name: item.name, face: item.face, lit: item.lit, ink: DS.brand) {
                    item.act()
                }
            }
        }
        .padding(.vertical, DS.Space.s3)
        .padding(.horizontal, DS.Space.s1)
        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.bottom, DS.Space.s2)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    static let folderColumns = 5

    private func folderCell(name: String, face: FolderItem.Face, lit: Bool, ink: Color,
                            phrase: Bool = false, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: DS.Space.s1) {
                Group {
                    switch face {
                    case .app(let mark):
                        BridgeIcon(name: mark, size: Self.icon)
                            .overlay {
                                if lit {
                                    RoundedRectangle(cornerRadius: Self.icon * 0.26, style: .continuous)
                                        .stroke(DS.brand, lineWidth: 2).padding(-3)
                                }
                            }
                    case .wallet(let address):
                        WalletFace(address: address, size: Self.icon, circular: true)
                            .overlay { if lit { Circle().stroke(DS.brand, lineWidth: 2).padding(-3) } }
                    case .place(let glyph):
                        roundIcon(glyph, ink: ink, fill: lit ? Color.white : DS.surfaceRaised, bounces: false)
                    }
                }
                .frame(width: Self.icon, height: Self.icon)
                // One line, as a Home Screen folder's names are: two lines
                // broke names mid-word ("MetaMas / k Card"). The act alone
                // takes two, being a phrase, not a name.
                Text(verbatim: name)
                    .dsText(.label12)
                    .foregroundStyle(lit ? DS.brandInk : DS.textSecondary)
                    .lineLimit(phrase ? 2 : 1)
                    .minimumScaleFactor(phrase ? 1 : 0.85)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(lit ? .isSelected : [])
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
