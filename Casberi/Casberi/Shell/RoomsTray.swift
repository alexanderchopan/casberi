import SwiftUI
import SwiftData

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
/// holds EVERY way to move: Search (the door to Find; its own capsule beside
/// the face on the phone since §1176), You is a row
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
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

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
    /// What the search reads beyond the tray's own names (prd §1171), read
    /// when the field is first focused, never in a body (§628): your notes
    /// and the phone's calendars.
    @State private var noteCorpus: [Thing] = []
    @State private var phoneCalendars: [PhoneCalendar] = []
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
                        // A PAGE'S GROUND ON THE PHONE (prd §1207 item 5): the
                        // tray rises onto solid black, full height, so it reads
                        // as a page you are on, not a menu over a blurred room;
                        // beside the rail it keeps the blur.
                        if railInset == 0 {
                            Color.black.ignoresSafeArea()
                        } else {
                            DSBackdropBlur().ignoresSafeArea()
                        }
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
                    // The search's own capsule beside the face (prd §1176):
                    // out of the face's side as the card comes out of its top.
                    if railInset == 0 {
                        searchCapsule(screen: geo.size)
                            .transition(reduceMotion
                                ? .opacity
                                : .scale(scale: 0.2, anchor: .leading).combined(with: .opacity))
                    }
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
            // `-traySearch "<words>"` types into the field (prd §1171): a
            // simctl-booted simulator draws no keyboard to type with.
            if let words = UserDefaults.standard.string(forKey: "traySearch") {
                await readKinds()
                query = words
                NSLog("[Casberi] traySearch: %@ | %d notes, %d holdings read", words, noteCorpus.count, holdings.count)
                for group in search(words) {
                    NSLog("[Casberi] traySearch| %@ | %@", group.title, group.hits.map(\.name).joined(separator: ", "))
                }
            }
        }
        #endif
        .onChange(of: chrome.roomsTray) { _, up in
            // Deal the rows in once the card has landed; under Reduce Motion
            // they are simply there.
            dealt = up
            if up && !reduceMotion { bounceTick += 1 }
            if !up { query = ""; searching = false; noteCorpus = []; holdings = [] }
        }
        .onChange(of: searching) { _, focused in
            if focused { Task { await readKinds() } }
        }
        // The search runs once the typing pauses, never in a body (prd
        // §1185), and again when the kinds it reads have landed.
        .task(id: query) { await runSearch() }
        .onChange(of: kindsRead) { _, _ in Task { await runSearch(pause: false) } }
    }

    // MARK: - The card

    private func panel(screen: CGSize, top safeTop: CGFloat = 0) -> some View {
        // The page's width on the phone (prd §1207 item 5): the room's own
        // column, edge to edge; beside the rail the menu's 330.
        let width = railInset > 0 ? min(screen.width * Self.widthShare, Self.maxWidth)
            : screen.width - 2 * DSRoomChassis.inset
        // Beside the rail the field leads the card, which then stands at its
        // full height while searching so the field stays above the keyboard
        // however few results there are (prd §1133e); it hangs from the top,
        // under the status bar and the demo's pill (§1133f). On the phone the
        // field is the capsule under the card (§1176), so the card hugs what
        // it holds and grows up from the capsule as results arrive.
        let railTopInset = railInset > 0 ? safeTop + DSDemoMark.screenClearance + Self.railTop : 0
        // Full height on the phone (prd §1207 item 5): everything above the
        // band, under the status bar; three quarters beside the rail.
        let full = railInset > 0
            ? (screen.height - railTopInset) * Self.heightShare
            : screen.height - safeTop - DSDock.seatClearance - DS.Space.s2
        let standsFull = railInset > 0 && (searching || !query.isEmpty)
        let height = (standsFull || railInset == 0) ? full : min(contentHeight, full)
        // Six to a line across the whole width on the phone, so a full
        // line reaches the card's far edge instead of stopping short.
        let gap = railInset > 0 ? Self.gap(inner: width - 2 * DS.Space.s4)
            : max(Self.iconGap, (width - 2 * DS.Space.s4 - CGFloat(Self.lineSlots) * Self.icon) / CGFloat(Self.lineSlots - 1))
        // **THREE CARDS, ONE SCROLL (prd §1203 item 6, user: "can they be
        // detached from each other … like how we have the search bar").**
        // You (your row, then Recent), the Wallet, and the categories each
        // stand on their own glass, the way the search capsule floats beside
        // the face, and the stack scrolls as one menu. A search's results are
        // one card under the field.
        return ScrollView {
            VStack(alignment: .leading, spacing: Self.cardGap) {
                if railInset > 0 { card { searchField } }
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    // NO YOU ROW AND NO NAME (prd §1207 item 5, user: "the
                    // tray can drop your name it's superfluous now and
                    // settings already has a place"): Recent alone leads
                    // (user: "it would only have recent"). Feed and Wallet
                    // are the walk's, Markets, Sources and Settings the Feed's
                    // tiles (user: "markets stays in feed"), and a note is ✎.
                    if hasRecent {
                        card { recentRow(gap: gap) }
                    }
                    if walletCard {
                        card { categoryRow(CategoryFold.walletCategory, index: 2, gap: gap, leads: false) }
                    }
                    if !feedCategories.isEmpty {
                        card {
                            ForEach(Array(feedCategories.enumerated()), id: \.element) { index, category in
                                categoryRow(category, index: index + 3, gap: gap)
                            }
                        }
                    }
                } else {
                    card { searchResults }
                }
            }
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
        // The stack's own corner clips a card scrolled under its edge to the
        // cards' shape, so nothing square shows past the glass.
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        // Above the face, in its column: the menu grows out of the button
        // that raised it, as Messages' grows out of its plus. Beside the
        // rail's face on the iPad and the Mac (§1133f), clear of the Mac's
        // window buttons.
        .padding(.leading, railInset > 0 ? railInset + DS.Space.s2 : DSRoomChassis.inset)
        .padding(.bottom, railInset > 0 ? 0 : DSDock.seatClearance)
        .padding(.top, railTopInset)
        .accessibilityAddTraits(.isModal)
    }

    /// Whether Recent has anything to show (prd §1136 item 8).
    private var hasRecent: Bool { !recentItems.isEmpty }

    /// One of the tray's cards: its rows on their own glass, the corner the
    /// whole card had (prd §1203 item 6).
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, DS.Space.s3)
            .padding(.horizontal, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsGlass(cornerRadius: Self.radius)
    }

    /// The air between two cards: the gap the search capsule keeps from the
    /// face beside it.
    static let cardGap: CGFloat = DS.Space.s2

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

    /// The categories' card: every row but the Wallet's, which has a card of
    /// its own (prd §1203 item 6).
    private var feedCategories: [String] {
        categories.filter { $0 != CategoryFold.walletCategory }
    }

    /// Whether the Wallet's card stands: it holds a connected seat.
    private var walletCard: Bool { categories.contains(CategoryFold.walletCategory) }

    /// Markets is a You door, not a category row (prd §1123, user: "it's only
    /// one app tile that is important but is part of a long catalogue list
    /// someone may not see it. it's also tied to things you have connected").
    /// It is Casberi's own index of the companies behind your apps, so it
    /// wears the pink of the app's own places. Since §1127 it is a place in
    /// Home, out of the swipe and the dock's order, like Notes.
    static let markets = HomeScope.markets

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
        "Testnets": "flask.fill",
        "Life":     "face.smiling",            // the filled one; the names run backwards
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
    /// build — the notes you write — behind a door
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
                     wallet: filter.source == CategoryFold.walletRoom && route.path.isEmpty,
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

    private func doors(home: Bool = false, wallet: Bool = false, notes: Bool = false,
                       markets: Bool = false, place: HomeScope.Place? = nil) -> [Door] {
        [
            Door(word: String(localized: "Feed"), glyph: home ? "tray.full.fill" : ScopeTileGlyph.feed,
                 lit: home, key: "All") { pick("All") },
            // You's four places, in the tiles' order (prd §1136 item 1):
            // Home, then A–Z. Apps and Addresses are filters inside Sources
            // now, the master list of everything you've connected.
            // Markets (prd §1123): its room once something is watched, else
            // the page where the first stock or token is added, so the door
            // is always drawn (§969).
            Door(word: String(localized: "Markets"), glyph: CategoryFold.glyph(for: Self.markets),
                 lit: markets, key: Self.markets) {
                // Always its room (prd §1167): Markets is no app to connect.
                pickCategory(Self.markets)
            },
            // The Notes tile's own glyph (`ScopeTileGlyph.notes`), lit or not: the
            // bare `note` read as an empty window (user, 2026-10-06), and the
            // white disc already says which place is standing.
            Door(word: String(localized: "Notes"), glyph: ScopeTileGlyph.notes,
                 lit: notes, key: Pinboard.room) { pick(Pinboard.room) },
            Door(word: String(localized: "Settings"), glyph: ScopeTileGlyph.settings,
                 lit: place == .settings || place == .apps || place == .addresses,
                 key: HomeScope.Place.settings.source) { screen(.casberi) },
            // The other pole (prd §1203) closes the row (user, 2026-10-08:
            // "move the wallet to the last position … feed markets notes
            // settings wallet"): the Feed's places in its tiles' order, then
            // the Wallet, where the swipe left lands and its card begins.
            Door(word: String(localized: "Wallet"), glyph: CategoryFold.glyph(for: CategoryFold.walletCategory),
                 lit: wallet, key: CategoryFold.walletRoom) { pickCategory(CategoryFold.walletCategory) },
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
    ///
    /// The Wallet's row draws no disc of its own (prd §1203 item 6): its door
    /// is the You row's, so the row is its name and its apps.
    private func categoryRow(_ category: String, index: Int, gap: CGFloat, leads: Bool = true) -> some View {
        let lit = standingCategory == category
        let needsYou = broken(category)
        let folder = folder(for: category)
        return wrapped(folder, gap: gap, leads: leads) {
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
            out.append(appItem(seat, id: "recent:" + seat.name, lit: false))
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

    // MARK: - Search (prd §1133)

    /// **ONE SEARCH (prd §1133, §1133e, user: "i like the search tho"; "fix
    /// 1").** It filters the tray as you type, as the App Library's does:
    /// every app, account, place and category whose name holds the words,
    /// each saying where it lives, and last a row that searches your THINGS
    /// for the same words in Find. It opened Find directly until §1133e,
    /// which found everything but the apps the tray had just grown to hold.
    ///
    /// **Where it stands (prd §1176, user: "should the fab search be on the
    /// bottom of the tray instead of the top so it is closer to someones
    /// fingers?").** On the phone it is its own glass capsule beside the face,
    /// at the face's height — iOS 26's search, a capsule at the bottom edge —
    /// because the card's top, where it led until §1176, is the farthest
    /// point from the corner the tray grows out of. Typing, the face is under
    /// the keyboard (§865), so the capsule takes the card's whole width just
    /// above it and the results read down from the card's top, as
    /// Spotlight's do. Beside the rail the face is at the TOP, so there the
    /// field still leads the card (`searchField`).
    private func searchCapsule(screen: CGSize) -> some View {
        // The bar reaches the page's far edge with the cards above it (prd
        // §1207 item 5).
        let width = screen.width - 2 * DSRoomChassis.inset
        let typing = chrome.keyboardUp
        // The room bar's slot (`DSScopeDock`), which fades while the tray
        // is up, so the search takes the bar's place (prd §1177).
        let beside = typing ? DSRoomChassis.inset : DSDock.agentSeat(minimized: false)
        // Typing, the unfolded seat's row, so the card above keeps its gap.
        let height = typing ? DSDock.agentSize(minimized: false) : DSDock.agentSize(fold: chrome.fold)
        let bottom = typing ? DSDock.agentBottomInset(minimized: false) : DSDock.agentBottomInset(fold: chrome.fold)
        return searchControl
            .padding(.horizontal, DS.Space.s4)
            .frame(width: max(DSRoomChassis.inset + width - beside, 1), height: height)
            .dsGlass(cornerRadius: height / 2)
            .padding(.leading, beside)
            .padding(.bottom, bottom)
            .animation(liftMotion, value: typing)
    }

    /// The field beside the rail: the card's first row, on a faint plate.
    private var searchField: some View {
        searchControl
            .padding(.horizontal, DS.Space.s3)
            .frame(height: Self.searchHeight)
            .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, DS.Space.s2)
            .modifier(Dealt(on: dealt, index: 0, reduceMotion: reduceMotion))
    }

    /// The glyph, the words and Clear — one field in either place.
    private var searchControl: some View {
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
    }

    /// One thing the search can land on.
    private struct Hit: Identifiable {
        let id: String
        /// The group it stands under (prd §1185): a category, Markets or You.
        let group: String
        let name: String
        /// Other words that find it: a ticker, a coin's other names, the
        /// company that makes an app ("meta" finds Muse).
        var aliases: [String] = []
        var tier: TraySearch.Tier = .name
        /// A sentence (a thing's title) matches at a word's start only.
        var anyWord = false
        /// Matched elsewhere already (a note Find's engine found by its words).
        var given: TraySearch.Match? = nil
        /// A line under the name.
        var line: String? = nil
        var trailing: Trailing? = nil
        /// The company a Markets row stands for, so its quote is read.
        var company: CompanyPacks.Company? = nil
        let mark: Mark
        let act: () -> Void
    }

    /// What a hit draws at its trailing edge.
    private enum Trailing {
        /// A word: Add, for an app you could connect.
        case word(String)
        /// A company's price and day move, drawn as they arrive.
        case quote(CompanyPacks.Listing)
        /// A figure you hold or pay, already through Hide balances.
        case money(String)
    }

    /// What a hit draws at its leading edge.
    private enum Mark {
        case face(FolderItem.Face)
        case glyph(String)
        case icon(String, symbol: String?)
        case asset(String)
        case dot(Color)
    }

    /// One group of results as the tray draws it.
    private struct Found: Identifiable {
        let id: String
        let title: String
        let glyph: String?
        let hits: [Hit]
    }

    /// The search's answer, set after a pause in the typing, never in a body
    /// (prd §1185): every keystroke rebuilt every hit and ran Find's engine
    /// over your notes inside `body`, on every render.
    @State private var results: [Found] = []
    /// The words `results` answers, so "nothing" is said only once the
    /// search for these words has run.
    @State private var resultsFor = ""
    /// What you hold, read with the other kinds when the field is focused.
    @State private var holdings: [WalletPortfolio.Position] = []
    /// Bumped when the kinds have been read, so a search typed before they
    /// landed runs again with them.
    @State private var kindsRead = 0

    /// How long the typing pauses before the search runs.
    static let searchPause = 140

    /// Search the words after the pause and keep the answer; a newer word
    /// cancels this one. Then read the quotes of the companies it shows.
    private func runSearch(pause: Bool = true) async {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else {
            results = []
            resultsFor = ""
            return
        }
        if pause {
            try? await Task.sleep(for: .milliseconds(Self.searchPause))
            guard !Task.isCancelled else { return }
        }
        let found = pivotFound(words) + search(words)
        results = found
        resultsFor = words
        let companies = found.flatMap(\.hits).compactMap(\.company)
        if !companies.isEmpty { await CompanyQuotes.shared.load(companies) }
    }

    /// The group the place you stand in leads with: your notes and You's
    /// places in You, Markets in Markets, a room in its category.
    private var standingGroup: String? {
        guard route.path.isEmpty, filter.source != "All" else { return nil }
        if HomeScope.isMarkets(filter.source) { return Self.markets }
        if HomeScope.contains(filter.source) { return TraySearch.you }
        return standingCategory
    }

    /// The company behind an app, as a word that finds the app ("meta" finds
    /// Muse and Instagram).
    private static func maker(_ app: String) -> [String] {
        CompanyPacks.makers[app].map { [$0.company] } ?? []
    }

    /// Everything the tray holds, as hits: You's places, each category and
    /// every app and account in it — the same items and the same acts the
    /// rows draw, so a hit lands where its icon would.
    private var nameHits: [Hit] {
        var hits = youDoors.map { door in
            Hit(id: "you:" + door.key, group: door.key == Self.markets ? Self.markets : TraySearch.you,
                name: door.word, mark: .face(.place(door.glyph)), act: door.act)
        }
        for category in categories {
            hits.append(Hit(id: "cat:" + category, group: category, name: category,
                            mark: .glyph(CategoryFold.glyph(for: category))) { pickCategory(category) })
            for item in folder(for: category).items {
                hits.append(Hit(id: category + ":" + item.id, group: category, name: item.name,
                                aliases: Self.maker(item.name), mark: .face(item.face), act: item.act))
            }
        }
        return hits
    }

    /// Settings' kinds, by name (prd §1171), each under the category it
    /// belongs to (§1185) and landing where Settings would open it; then
    /// every app you could add, under its own category.
    private var kindHits: [Hit] {
        var hits: [Hit] = []
        for cal in phoneCalendars {
            hits.append(Hit(id: "cal:" + cal.id, group: "Day", name: cal.title, line: cal.account,
                            mark: .dot(cal.color)) { landInSettings(.kind(.calendars)) })
        }
        for cal in CalendarSubscriptionStore.shared.calendars {
            hits.append(Hit(id: "calsub:" + cal.id.uuidString, group: "Day", name: cal.displayName,
                            mark: .glyph(ScopeTileGlyph.calendars)) { landInSettings(.kind(.calendars)) })
        }
        for room in Following.Room.allCases {
            let group = switch room {
            case .reading, .media: "Media"   // one category since prd §1204
            case .work:    "Work"
            }
            for item in FollowingReading.shared.items(for: room) {
                hits.append(Hit(id: "feed:\(room.rawValue):" + item.id, group: group, name: item.name,
                                line: item.seat, mark: .icon(item.seat, symbol: nil)) {
                    landInSettings(.sheet(.following(item.id, room)))
                })
            }
        }
        for item in MailSubscriptionsReading.shared.items {
            hits.append(Hit(id: "list:" + item.id, group: "Day", name: item.name, line: item.address,
                            mark: .icon(item.name, symbol: nil)) { landInSettings(.sheet(.mailList(item.id))) })
        }
        // People (prd §1136 item 3): they live in Settings, so the search
        // finds them by name and lands on them there.
        for contact in ContactIndexSources.contacts
            where !contact.isUnnamed && !ContactIndexSources.isYours(contact) {
            hits.append(Hit(id: "person:" + contact.id, group: TraySearch.you, name: contact.name,
                            mark: .face(.person(contact))) { landInSettings(.person(contact.name)) })
        }
        for item in SubscriptionsReading.shared.items {
            let figure = item.amount.map {
                BalancePrivacy.shared.value(CardSpendRoom.money($0, code: item.currency))
            }
            hits.append(Hit(id: "plan:" + item.id, group: CategoryFold.walletRoom, name: item.name,
                            aliases: Self.maker(item.name), tier: .money,
                            line: item.next.map { String(localized: "Renews \($0.formatted(.dateTime.month(.abbreviated).day()))") },
                            trailing: figure.map(Trailing.money),
                            mark: .icon(item.name, symbol: nil)) { landInSettings(.sheet(.subscription(item.id))) })
        }
        hits += addHits
        return hits
    }

    /// Every catalogue app you have not connected, under its category with
    /// Add at its edge, each opening the page its Connect stands on, as the
    /// catalogue's row does (prd §1171a, §1185). Markets is a place, never an
    /// app to add (§1167).
    private var addHits: [Hit] {
        let connected = Set(bridges.bridges.filter { $0.status != .paused }.map(\.name))
        return BridgeCatalog.offers
            .filter { !connected.contains($0.name) && BridgeCatalog.category(of: $0) != HomeScope.markets }
            .map { offer in
                let name = offer.name
                return Hit(id: "add:" + name, group: BridgeCatalog.category(of: offer), name: name,
                           aliases: Self.maker(name), tier: .add,
                           trailing: .word(String(localized: "Add")), mark: .face(.app(name))) {
                    DSHaptic.selection()
                    close()
                    route.openSetup(forOffer: name)
                }
            }
    }

    /// Your notes whose name holds the words as you type them ("pack" finds
    /// Packing list), then the ones Find's engine finds by their words
    /// (`Retriever.find`, as Notes' search tray did, prd §1099), as things.
    /// Values are read here, after the live check, so no row touches a
    /// deleted model.
    private func noteHits(_ words: String) -> [Hit] {
        let live = noteCorpus.live
        let named = live.filter { TraySearch.match($0.title, words, anyWord: true) != nil }
        let byName = Set(named.map(\.id))
        // Find's engine reads meaning as well as words, so under four letters
        // it finds what merely looks alike ("eth" found "something").
        let found = words.count < Self.wordsFloor ? []
            : Retriever.find(words, in: live).hits.filter { !byName.contains($0.id) }.prefix(TraySearch.thingCap)
        return (named.map { ($0, false) } + found.map { ($0, true) }).compactMap { thing, byWords in
            guard thing.isLive else { return nil }
            let id = thing.id
            let line = NotePreview.line(title: thing.title, content: thing.content,
                                        isVoice: thing.kind == .voice, isLocked: NoteLock.isLocked(thing))
                ?? thing.capturedAt.formatted(date: .abbreviated, time: .omitted)
            return Hit(id: "note:" + id.uuidString, group: TraySearch.you, name: thing.title,
                       tier: byWords ? .thing : .name, anyWord: true, given: byWords ? .word : nil, line: line,
                       mark: .icon(thing.source, symbol: BridgeIcon.noteSymbol(for: thing))) {
                openThing(id)
            }
        }
    }

    /// The companies behind every app whose name, ticker or app the words
    /// find (`MarketsIndex.matches`, Markets' own rule, prd §1082), with
    /// their quote at the edge. Only traded ones: an unlisted company has
    /// nothing to open.
    private func companyHits(_ words: String) -> [Hit] {
        // A coin you hold stands once, in Wallet, with what you hold.
        let held = Set(holdings.map { $0.symbol.uppercased() })
        return companyPool.filter { hit in
            guard let company = hit.company else { return false }
            if case .token = company.listing, let t = company.listing.ticker, held.contains(t.uppercased()) { return false }
            return MarketsIndex.matches(words, MarketsWatch.entry(company))
        }
    }

    /// Every traded company, as hits — the pool a typo reaches too.
    private var companyPool: [Hit] {
        let connected = Set(bridges.bridges.filter { $0.status != .paused }.map(\.name))
        return TokensScope.everyCompany.filter { $0.listing != .unlisted }.map { company in
            let ticker = company.listing.ticker
            let apps = MarketsIndex.appsLine(MarketsWatch.entry(company), connected: connected)
            let line = ([ticker].compactMap(\.self) + [apps.prefix(3).joined(separator: ", ")])
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return Hit(id: "company:" + company.name, group: Self.markets, name: company.name,
                       aliases: [ticker].compactMap(\.self) + company.seats, tier: .money,
                       line: line, trailing: .quote(company.listing), company: company,
                       mark: .icon(company.seats.first ?? company.name, symbol: nil)) {
                openCompany(company)
            }
        }
    }

    /// What you hold, one row a coin across every wallet (`WalletPortfolio`),
    /// its value at the edge through Hide balances; "ethereum" finds ETH.
    private var holdingHits: [Hit] {
        holdings.map { p in
            Hit(id: "hold:" + p.symbol, group: CategoryFold.walletRoom, name: p.symbol,
                aliases: TraySearch.aliases(forSymbol: p.symbol), tier: .money,
                line: p.holders.prefix(2).map(\.label).joined(separator: " · "),
                trailing: .money(WalletValue.money(p.usd)), mark: .asset(p.symbol)) {
                chrome.walletScope = nil
                chrome.walletSection = .holdings
                pick(CategoryFold.walletRoom)
            }
        }
    }

    /// Things you kept whose title has a word starting with the words — a
    /// transfer ("Sent 0.5 ETH"), a play, a mail — under the category of the
    /// app they came from, two a group at most (§1185). Read off the store by
    /// title alone, newest first; the rest of the words are Find's.
    private func thingHits(_ words: String) -> [Hit] {
        let q = TraySearch.normalized(words)
        guard q.count >= 2 else { return [] }
        let kept = NoteSheetSource.keptSource, watched = TokenWatch.source
        var seen = Set<UUID>()
        var out: [Hit] = []
        for term in [q] + TraySearch.otherNames(q) {
            var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.title.localizedStandardContains(term) },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = Self.thingFetch
            for thing in (try? context.fetch(d)) ?? []
                where thing.isLive && thing.source != kept && thing.source != watched {
                guard seen.insert(thing.id).inserted,
                      let group = BridgeCatalog.category(forSource: thing.source) else { continue }
                let id = thing.id
                let line = BridgeCatalog.seatName(forSource: thing.source) + " · "
                    + thing.capturedAt.formatted(.dateTime.month(.abbreviated).day())
                out.append(Hit(id: "thing:" + id.uuidString, group: group, name: thing.title,
                               tier: .thing, anyWord: true, line: line,
                               mark: .icon(thing.source, symbol: nil)) { openThing(id) })
            }
        }
        return out
    }

    /// The shortest words Find's engine searches your notes by.
    static let wordsFloor = 4

    /// How many things a word reads off the store before ranking.
    static let thingFetch = 40

    /// A pasted address: the wallet you watch, by its name, or Watch this
    /// wallet with the address already typed.
    private func addressHits(_ words: String) -> [Hit] {
        guard TraySearch.isEVMAddress(words) else { return [] }
        let short = WalletStore.shortAddress(words)
        if let entry = WalletStore.shared.addresses.first(where: { WalletWatch.sameAddress($0.address, words) }) {
            return [Hit(id: "addr:" + entry.address, group: CategoryFold.walletRoom,
                        name: entry.label.isEmpty ? short : entry.label, given: .exact,
                        line: entry.label.isEmpty ? nil : short, mark: .face(.wallet(entry.address))) {
                chrome.walletScope = entry.address
                pick(CategoryFold.walletRoom)
            }]
        }
        return [Hit(id: "watch:" + words, group: CategoryFold.walletRoom,
                    name: String(localized: "Watch this wallet"), tier: .add, given: .exact,
                    line: short, mark: .glyph("plus")) {
            chrome.searchDraft = words
            chrome.walletFollowPending = true
            pick(CategoryFold.walletRoom)
        }]
    }

    /// The tray closes, then Settings rises on what was found.
    /// GENERATIVE SEARCH LEADS (prd §1209): what the words could make a
    /// page of — a person, an app you have, a category, a span, the words —
    /// each a row that composes that page over the Feed.
    private func pivotFound(_ words: String) -> [Found] {
        let apps = bridges.bridges.filter { $0.status != .paused }.map(\.name)
        let offers = PivotCompose.resolve(words, apps: apps, categories: categories)
        guard !offers.isEmpty else { return [] }
        let hits = offers.map { q -> Hit in
            let mark: Mark = switch q.subject {
            case .person: .glyph("person")
            case .app(let name): .face(.app(name))
            case .category(let name): .glyph(CategoryFold.glyph(for: name))
            case .words, .span: .glyph("text.magnifyingglass")
            }
            return Hit(id: "pivot:" + q.id, group: Self.pivotGroup, name: q.offerTitle,
                       line: q.subject == .span ? nil : q.spanLabel, mark: mark) {
                DSHaptic.selection()
                close()
                // Over a sheet still closing, a second one is refused.
                if route.sheet != nil || !route.path.isEmpty {
                    route.path = []
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        chrome.pivot = q
                    }
                } else {
                    chrome.pivot = q
                }
            }
        }
        return [Found(id: Self.pivotGroup, title: String(localized: "Everything"),
                      glyph: "text.magnifyingglass", hits: hits)]
    }

    static let pivotGroup = "pivot"

    private func landInSettings(_ landing: SettingsLanding) {
        chrome.settingsLanding = landing
        screen(.casberi)
    }

    /// Open a thing's sheet or page.
    private func openThing(_ id: UUID) {
        close()
        if let url = URL(string: "casberi://thing/\(id.uuidString)") { openURL(url) }
    }

    /// A company you watch opens its own page; one you don't, its sheet in
    /// Markets (`FeedScreen.openCompany`, asked through the shell).
    private func openCompany(_ company: CompanyPacks.Company) {
        if let thing = MarketsWatch.watchedThing(company, context: context) {
            openThing(thing.id)
            return
        }
        chrome.marketsRequest = .company(company)
        pickCategory(Self.markets)
    }

    /// Read what the kinds need once the field is focused: notes, the
    /// phone's calendars, what you hold, and the readings Settings keeps.
    private func readKinds() async {
        let you = NoteSheetSource.keptSource
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == you },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 2_000
        noteCorpus = ((try? context.fetch(d)) ?? []).filter { $0.isLive && Pinboard.inRoom($0) }
        phoneCalendars = PhoneCalendar.readable(context)
        // The last reading of every wallet, never a fetch: the demo's own
        // fixture, else each wallet's stored sample (`WalletPortfolio`).
        let portfolio = DemoMode.isActive
            ? WalletPortfolio.demoFixture()
            : WalletPortfolio.from(groups: WalletIngest.lastKnownHoldingsByWallet())
        holdings = portfolio.positions.filter { $0.usd >= 1 }
        // People are found from the index's snapshot, which only Settings
        // and the book built; build it here so a person is found first time.
        _ = ContactIndexSources.rebuild(context: context)
        MailSubscriptionsReading.shared.refresh(context)
        for room in Following.Room.allCases { FollowingReading.shared.refresh(room, context: context) }
        await SubscriptionsReading.shared.refresh(context)
        kindsRead += 1
    }

    /// THE HITS FOR THE WORDS, BY CATEGORY (prd §1185, user: "if i search
    /// meta it could show it in markets, day (calendar if i had), agents and
    /// so on"). Every kind becomes candidates and `TraySearch` groups them:
    /// the place you stand in first, a group holding the exact name next,
    /// then You, Markets and the dock's order. When nothing matches, the
    /// names closest to the words, under "Closest to".
    private func search(_ words: String) -> [Found] {
        let hits = nameHits + kindHits + noteHits(words) + companyHits(words)
            + holdingHits + thingHits(words) + addressHits(words)
        let candidates = hits.enumerated().map { i, hit in
            TraySearch.Candidate(index: i, group: hit.group, name: hit.name, aliases: hit.aliases,
                                 tier: hit.tier, anyWord: hit.anyWord, given: hit.given)
        }
        let groups = TraySearch.groups(candidates, query: words, standing: standingGroup,
                                       dockOrder: CategoryOrder.current)
        if !groups.isEmpty {
            return groups.map { g in
                Found(id: g.name, title: g.name == TraySearch.you ? HomeScope.title : g.name,
                      glyph: g.name == TraySearch.you ? nil : CategoryFold.glyph(for: g.name),
                      hits: g.hits.map { said(hits[$0.index], for: words) })
            }
        }
        let pool = nameHits.filter { !$0.id.hasPrefix("cat:") } + addHits + companyPool
        let near = TraySearch.closest(words, among: pool.map(\.name))
        guard !near.isEmpty else { return [] }
        return [Found(id: "closest", title: String(localized: "Closest to “\(words)”"), glyph: nil,
                      hits: near.map { pool[$0] })]
    }

    /// An app found through its maker says so ("meta" finds Instagram,
    /// "Made by Meta"), or the row would not say why it is there.
    private func said(_ hit: Hit, for words: String) -> Hit {
        guard hit.line == nil, TraySearch.match(hit.name, words) == nil,
              let maker = Self.maker(hit.name).first,
              TraySearch.match(maker, words) != nil else { return hit }
        var out = hit
        out.line = String(localized: "Made by \(maker)")
        return out
    }

    @ViewBuilder
    private var searchResults: some View {
        let words = query.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(results) { group in
                HStack(spacing: DS.Space.s1) {
                    if let glyph = group.glyph {
                        Image(systemName: glyph).dsGlyph(.caption)
                    }
                    Text(verbatim: group.title).dsText(.label12)
                }
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s3)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                ForEach(group.hits) { hit in hitRow(hit) }
            }
            // Nothing, said once the search for these words has run: what
            // could look further — Markets' New for a word that could be a
            // ticker — then Find.
            if results.isEmpty, resultsFor == words {
                Text("Nothing you have is called “\(words)”.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s3)
                if TraySearch.looksLikeTicker(words) {
                    let ticker = TraySearch.normalized(words).uppercased()
                    hitRow(Hit(id: "lookup", group: Self.markets,
                               name: String(localized: "Look up “\(ticker)” in Markets"),
                               line: String(localized: "Stocks and coins you don’t watch yet"),
                               mark: .glyph(CategoryFold.glyph(for: Self.markets))) {
                        chrome.searchDraft = ticker
                        chrome.marketsRequest = .lookUp
                        pickCategory(Self.markets)
                    })
                }
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

    private func hitRow(_ hit: Hit) -> some View {
        Button(action: hit.act) {
            HStack(spacing: DS.Space.s3) {
                Group {
                    switch hit.mark {
                    case .face(let face):
                        itemFace(FolderItem(id: hit.id, name: hit.name, face: face, lit: false, act: hit.act))
                    case .glyph(let glyph):
                        roundIcon(glyph, ink: DS.textPrimary, fill: DS.surfaceRaised, bounces: false)
                    case .icon(let name, let symbol):
                        BridgeIcon(name: name, size: Self.icon, circular: true, symbol: symbol)
                    case .asset(let symbol):
                        AssetMark(name: symbol, size: Self.icon)
                    case .dot(let color):
                        Circle().fill(color).frame(width: 14, height: 14)
                    }
                }
                .frame(width: Self.icon, height: Self.icon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: hit.name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if let line = hit.line, !line.isEmpty {
                        Text(verbatim: line)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                trailing(hit.trailing)
            }
            .frame(minHeight: Self.resultHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityElement(children: .combine)
    }

    /// A hit's edge: Add, a figure, or a quote with its day's move.
    @ViewBuilder
    private func trailing(_ trailing: Trailing?) -> some View {
        switch trailing {
        case .word(let word):
            Text(verbatim: word)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        case .money(let figure):
            Text(verbatim: figure)
                .dsText(.price17)
                .monospacedDigit()
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
        case .quote(let listing):
            if let quote = CompanyQuotes.shared.quote(listing) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TokenChartStyle.priceText(quote.price))
                        .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let change = quote.change {
                        let flat = TokenChartStyle.isFlat(change)
                        Text(TokenChartStyle.changeText(change))
                            .dsText(.subhead12).fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(flat ? DS.textTertiary : (change > 0 ? DS.confirmInk : DS.destructiveInk))
                    }
                }
            }
        case nil:
            EmptyView()
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
        /// An app's account page, offered on a long press (prd §1159).
        var settings: (() -> Void)? = nil
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
                return appItem(seat, id: id, lit: scope == id)
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
            return appItem(seat, id: id, lit: lit)
        }
        return Folder(items: items, action: nil)
    }

    /// An app's icon: a tap lands in the room scoped to it, and a long press
    /// offers Open and Settings, its account page (prd §1159) — the page
    /// its row in Settings opens, reached from where the app is drawn.
    private func appItem(_ seat: RoomAccounts.Seat, id: String, lit: Bool) -> FolderItem {
        let bridgeID = bridges.bridges.first { $0.name == seat.name || $0.id == seat.source }?.id
            ?? BridgeRouter.id(forOffer: seat.name)
        let settings: (() -> Void)? = bridgeID.map { bridgeID in
            { accountPage(BridgeRouter.destination(forID: bridgeID)) }
        }
        return FolderItem(id: id, name: seat.name, face: .app(seat.mark), lit: lit, settings: settings) {
            pick(seat.source ?? seat.name)
        }
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
    private func wrapped<Name: View, Lead: View>(_ folder: Folder, gap: CGFloat, leads: Bool = true,
                                                  @ViewBuilder name: () -> Name,
                                                  @ViewBuilder lead: () -> Lead) -> some View {
        var cells: [RunCell] = leads ? [.lead] : []
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
            .contextMenu {
                if let settings = item.settings {
                    Button(action: item.act) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    Button(action: settings) {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
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

    /// Open a screen of its own — Apps, Addresses or Settings (§933, §1111).
    private func screen(_ door: HomeRoute.Node) {
        DSHaptic.selection()
        close()
        route.present(door)
    }

    /// Open an app's account page over where you stand (prd §1159), the way
    /// its connected row in Settings does (§1050f).
    private func accountPage(_ dest: BridgeRouter.Destination) {
        DSHaptic.selection()
        close()
        route.openAccount(dest)
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
