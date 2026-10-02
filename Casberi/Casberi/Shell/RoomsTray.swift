import SwiftUI

/// The rooms tray (prd §930; the Apple pass §932) — the phone's whole
/// navigation behind ONE button, the face.
///
/// **A floating glass menu since prd §1058** (user: "look how apple does
/// imessage in app tray … lets go back to glass and do it this way … today
/// our tray covers the entire width of the app and it looks weird"). It is
/// Messages' attachment menu: a rounded glass card above the face's corner,
/// about two thirds of the screen wide, one row per place — a round icon
/// and its name — scrolling when the list is longer than the card. The four
/// You rows (Home, Notes, Addresses, Settings) lead, then the categories in
/// the person's Dock order (§1050j). No grabber, no detents and no search
/// (§1015's field is deleted with the full-width sheet it led): a list this
/// short is read, not searched. Glass on the floating layer is the design
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

    /// A row's round icon — Messages' size for its menu.
    static let icon: CGFloat = 40
    static let rowHeight: CGFloat = 52
    /// The card's corner: Messages' menu, a continuous corner.
    static let radius: CGFloat = 32
    /// How much of the screen the card may take: two thirds across, capped,
    /// and three quarters down before it scrolls.
    static let widthShare: CGFloat = 0.7
    static let maxWidth: CGFloat = 300
    static let heightShare: CGFloat = 0.72
    /// The stagger between one row's arrival and the next.
    static let dealStep: Double = 0.02

    @State private var contentHeight: CGFloat = 0
    @State private var dealt = false
    @State private var bounceTick = 0

    private var liftMotion: Animation { reduceMotion ? DS.Motion.glide : DS.Motion.folder }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if chrome.roomsTray {
                    // The catcher: a tap anywhere else closes the menu — a
                    // real control, so it is a Button. Clear, as Messages'
                    // is: the card floats over the room, it does not dim it.
                    Button {
                        close()
                    } label: {
                        Color.black.opacity(0.001).ignoresSafeArea()
                    }
                    .buttonStyle(.plain)
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
        }
    }

    // MARK: - The card

    private func panel(screen: CGSize) -> some View {
        let width = min(screen.width * Self.widthShare, Self.maxWidth)
        let height = min(contentHeight, screen.height * Self.heightShare)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(youDoors.enumerated()), id: \.offset) { index, door in
                    self.door(door, index: index)
                }
                // The app's own places, then the categories: a breath
                // between them, never a header (Messages' menu has none).
                Color.clear.frame(height: DS.Space.s2)
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    categoryRow(category, index: index + youDoors.count)
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

    /// A category's row (prd §1058): its glyph in a round icon, its name.
    /// It lands in the category's room. The standing room fills its glyph
    /// (`glyph(for:lit:)`); a broken app inside wears the attention hue on
    /// the glyph, and the label says it too.
    private func categoryRow(_ category: String, index: Int) -> some View {
        let lit = standingCategory == category
        let needsYou = broken(category)
        return Button {
            pick(category)
        } label: {
            menuRow(icon: roundIcon(glyph(for: category, lit: lit),
                                    ink: needsYou ? DS.attention : DS.textPrimary,
                                    fill: lit ? DS.fillStrong : DS.surfaceRaised,
                                    bounces: lit),
                    word: category)
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(needsYou
            ? Text("\(category), needs your attention")
            : Text(category))
        .accessibilityAddTraits(lit ? .isSelected : [])
        .modifier(Dealt(on: dealt, index: index, reduceMotion: reduceMotion))
    }

    // MARK: - Pieces

    /// A row: the round icon, then the word — Messages' menu row, every
    /// row the same weight, no chevron.
    private func menuRow<Icon: View>(icon: Icon, word: String) -> some View {
        HStack(spacing: DS.Space.s4) {
            icon
            Text(word)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Self.rowHeight)
        .contentShape(Rectangle())
    }

    /// The round icon: a glyph on a charcoal disc, and the standing place's
    /// disc a step lighter, its glyph filled.
    private func roundIcon(_ glyph: String, ink: Color, fill: Color, bounces: Bool) -> some View {
        Circle()
            .fill(fill)
            .overlay(
                Image(systemName: glyph)
                    .dsGlyph(.body, weight: .medium)
                    .foregroundStyle(ink)
                    .symbolEffect(.bounce.up, value: bounces ? bounceTick : 0)
            )
            .frame(width: Self.icon, height: Self.icon)
            .animation(DS.Motion.standard, value: fill)
    }

    /// A You row: the app's own places, their glyphs in the brand pink
    /// (§976a); the standing one's disc turns white behind the same glyph
    /// (§1053, user: "maybe white with pink").
    private func door(_ door: Door, index: Int) -> some View {
        Button(action: door.act) {
            menuRow(icon: roundIcon(door.glyph, ink: DS.brand,
                                    fill: door.lit ? Color.white : DS.surfaceRaised,
                                    bounces: door.lit),
                    word: door.word)
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
        withAnimation(liftMotion) { chrome.roomsTray = false }
    }
}
