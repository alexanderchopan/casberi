import SwiftUI

/// The rooms tray (prd §930, 2026-09-26; the Apple pass is §932) — the phone's
/// whole navigation behind ONE button, the face.
///
/// **Why the strip left the band.** The dock's category tiles were a scroll
/// before a tap for any room past the fourth (user: "then it's only one
/// button that a person has to press in the nav, whereas now they have to
/// sort of scroll and stuff"). This tray puts every room one tap from the
/// face: a row per category, its name at the left and its connected sources
/// beside it as bare brand circles, wrapping inside the column when a category
/// is crowded — so the first line of every row is the same shape whether
/// Wallet holds two accounts or fourteen. A `You` row leads with four doors:
/// Home (the All room), Connect, Addresses and Settings. Manage is not a door
/// (prd §958): Connect lands on the same screen, whose switcher reaches it.
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
/// marks deal in left to right, the standing glyph bounces once, and a picked
/// source FLIES to the room's head (`RoomPickFlight`, the capture flight
/// reversed). A category with a broken seat wears the attention colour on its
/// glyph and says so; a system Close appears at the accessibility text sizes,
/// where the face's ring is hard to read. Every name is a 44pt target.
///
/// **Every pick is `ShellChrome.sourceRequest`.** The strip's own tap ran
/// `go(to:)` inside `MainSurface`; this view stands above the stack and takes
/// the same hop every other room-to-room door takes, so a category label
/// resolves through `CategoryFold.landing` exactly as a chip tap did.
///
/// **Press and slide (prd §1002).** Hold anywhere in the roster for
/// `scrubArm`, then slide: the door, category or source under the finger
/// lifts with a selection tick, its row's name column says what it is, and
/// letting go lands there — the dock's press-and-slide (§621), brought into
/// the tray that replaced the strip. Letting go over nothing picks nothing.
/// The scroll is off while a scrub is armed, and a hold released without
/// moving is left to the Button under it, so a slow tap still taps.
struct RoomsTray: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route
    @Environment(FeedFilter.self) private var filter
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Every button in the tray is the FACE's size (prd §1013, user: "we
    /// should just use that size or the size of the fab and the You tiles,
    /// not something else in between", then "lets go with h with all the
    /// buttons at 46"): the five You doors and every account mark.
    static let mark: CGFloat = DSDock.agentSize(minimized: false)
    /// Five columns across the tray (prd §1013: "5 and 5"), shared by the You
    /// doors and every section's marks, so the tray is one grid top to bottom.
    static let marksPerLine = 5
    /// The first column's centre, from the tray's inset: the column the face
    /// and every room's row icons centre on (`rowLeadCentre`, prd §1014,
    /// user: "we need the axis to align here … so it is cohesive? yes the
    /// face would cover one but so what?"). The fifth column mirrors it.
    static let axis: CGFloat = DSRoomChassis.rowLeadCentre - DSRoomChassis.inset
    /// A header glyph's slot, so every category's glyph centres on `axis`
    /// whatever its own width.
    static let glyphSlot: CGFloat = 24
    /// The air under a line of marks, before the next line.
    static let lineAir: CGFloat = DS.Space.s4 + DS.Space.s1
    /// The air above a section's header: more than `lineAir`, so the gap is
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
    /// Recent's seats, read when the tray rises — never from a body (§628).
    @State private var recent: [String] = []
    @State private var contentHeight: CGFloat = 0
    @State private var grown = false
    @State private var dealt = false
    @State private var bounceTick = 0
    /// Where every pickable thing stands, in window space: the flight's
    /// start and the scrub's hit test. Layout, not state — a reference the
    /// body never observes, so a scroll's frame writes re-render nothing.
    @State private var frames = TrayFrames()
    /// The thing under a scrubbing finger, and whether a scrub is armed.
    @State private var hot: ScrubTarget?
    @State private var scrubbing = false
    /// A scrub that moved owns its release: the Button the finger started on
    /// must not also fire when it lifts there.
    @State private var swallowTap = false

    /// How long a hold arms the scrub — the chart scrub's clock is 0.15, but
    /// here a hold that short would steal every slow tap on a mark.
    static let scrubArm: Double = 0.3
    /// How far a mark lifts under the finger.
    static let hotScale: CGFloat = 1.2

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
        }
        #endif
        // Every room landed in, from anywhere, is the newest on Recent — a
        // connected seat only, never a category, All or the notes room.
        .onChange(of: filter.source) { _, source in
            if connectedSeats.contains(source) { RecentRooms.record(source) }
        }
        .onChange(of: chrome.roomsTray) { _, up in
            if up { recent = RecentRooms.list }
            // Deal the marks in once the panel has landed; under Reduce
            // Motion they are simply there.
            grown = false
            drag = 0
            hot = nil
            scrubbing = false
            swallowTap = false
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
        let natural = contentHeight + Self.grabberHeight
        let rest = min(natural, screen.height * Self.restShare)
        let full = min(natural, screen.height * Self.grownShare)
        // A header's glyph centres on the axis its first mark stands on.
        let headInset = Self.axis - Self.glyphSlot / 2
        let recent = recentShown
        let height = grown ? full : rest
        return VStack(spacing: 0) {
            grabber
            ScrollView {
                VStack(alignment: .leading, spacing: Self.sectionGap) {
                    youRow
                    if !recent.isEmpty {
                        recentSection(recent, headInset: headInset)
                    }
                    ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                        categoryRow(category, index: index, headInset: headInset)
                    }
                }
                // One grid across the tray between its insets (§1013): the
                // You doors and every section's marks share five columns.
                .padding(.horizontal, DSRoomChassis.inset)
                .padding(.top, DS.Space.s3)
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
                .simultaneousGesture(scrub)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(scrubbing)
            // The visible window: a row scrolled out of it keeps its last
            // frame, and a finger over the grabber must not pick it.
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { frames.viewport = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in frames.viewport = f }
                }
            }
            .frame(height: max(height - Self.grabberHeight, 1))
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
        .ignoresSafeArea(edges: .bottom)
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

    /// Every connected seat the tray draws in a category.
    private var connectedSeats: Set<String> {
        Set(chrome.categoryVenues.values.joined())
    }

    /// Recent, as drawn: seats still connected, at most one line.
    private var recentShown: [String] {
        let seats = connectedSeats
        return Array(recent.filter { seats.contains($0) }.prefix(Self.marksPerLine))
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
        "Shopping": "cart.fill",
    ]

    private func glyph(for category: String, lit: Bool) -> String {
        lit ? (Self.filledGlyphs[category] ?? CategoryFold.glyph(for: category))
            : CategoryFold.glyph(for: category)
    }

    /// Whether one of the category's seats needs you — the same test the
    /// face's ring makes (`DoorAlarm`), read per row so the row can say which.
    private func broken(_ present: [String]) -> Bool {
        let seats = Set(present)
        return bridges.bridges.contains { seats.contains($0.name) && $0.status == .attention }
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
    /// The row spans the tray between its insets, one equal column a door.
    private var youRow: some View {
        let home = filter.source == "All" && route.path.isEmpty
        let notes = Pinboard.isPinnedRoom(filter.source) && route.path.isEmpty
        return MarkGrid(columns: Self.marksPerLine, edge: Self.axis, lineAir: Self.lineAir) {
            ForEach(Array(doors(home: home, notes: notes).enumerated()), id: \.offset) { index, door in
                self.door(door, index: index)
            }
        }
    }

    /// The You row's doors, in order — one list, so a tap and a scrub
    /// release run the same act.
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
            // "Accounts", the screen it opens (§1012): Connect is one half of
            // that screen's switcher, and a verb in a row of places.
            Door(word: String(localized: "Accounts"), glyph: "square.grid.2x2") { connect() },
            Door(word: String(localized: "Addresses"), glyph: "at") { screen(.addresses) },
            Door(word: String(localized: "Settings"), glyph: "gearshape") { screen(.settings) },
        ]
    }

    /// A category: its header above, its marks under it on the tray's five
    /// columns (prd §1013). The header opens the category's room.
    private func categoryRow(_ category: String, index: Int, headInset: CGFloat) -> some View {
        let present = CategoryFold.scopes(category: category,
                                          present: Set(chrome.categoryVenues[category] ?? []))
        let lit = standingCategory == category
        let needsYou = broken(present)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                tapped { pick(category) }
            } label: {
                header(glyph: glyph(for: category, lit: lit),
                       word: scrubWord(in: present) ?? category,
                       lit: lit, broken: needsYou, opens: true,
                       hot: hot == .category(category))
            }
            .buttonStyle(RowPress())
            .padding(.leading, headInset)
            .scrubFrame(.category(category), in: frames)
            .accessibilityLabel(needsYou
                ? Text("\(category), needs your attention")
                : Text(category))
            .accessibilityAddTraits(lit ? .isSelected : [])
            MarkGrid(columns: Self.marksPerLine, edge: Self.axis, lineAir: Self.lineAir) {
                ForEach(Array(present.enumerated()), id: \.element) { slot, venue in
                    markButton(venue, key: .source(venue))
                        .modifier(Dealt(on: dealt, index: index + slot, reduceMotion: reduceMotion))
                }
            }
        }
    }

    /// Recent (prd §1013): the rooms you opened last, newest first, on one
    /// line. Not a room, so its header opens nothing. Drawn only once there
    /// is something in it — a section of nothing is not a section.
    private func recentSection(_ recent: [String], headInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(glyph: "clock", word: scrubWord(in: recent, recent: true) ?? String(localized: "Recent"),
                   lit: false, broken: false, opens: false)
                .padding(.leading, headInset)
                .accessibilityAddTraits(.isHeader)
            MarkGrid(columns: Self.marksPerLine, edge: Self.axis, lineAir: Self.lineAir) {
                ForEach(Array(recent.enumerated()), id: \.element) { slot, venue in
                    markButton(venue, key: .recent(venue))
                        .modifier(Dealt(on: dealt, index: slot, reduceMotion: reduceMotion))
                }
            }
        }
    }

    /// One account's mark: tap lands in its room, and the mark flies to the
    /// room's head (§932). `key` tells a Recent mark from the same seat's
    /// mark in its category, so the scrub and the flight find the one touched.
    private func markButton(_ venue: String, key: ScrubTarget) -> some View {
        Button {
            tapped { pick(venue, flying: true, from: key) }
        } label: {
            BridgeIcon(name: venue, size: Self.mark, circular: true)
                .modifier(Lifted(on: hot == key, reduceMotion: reduceMotion))
                .overlay {
                    if filter.source == venue {
                        Circle()
                            .strokeBorder(DS.tint, lineWidth: 1.5)
                            .padding(-2)
                    }
                }
        }
        .buttonStyle(PressSpring())
        .dsTapTarget(Circle())
        .accessibilityLabel(Text(BridgeCatalog.seatName(forSource: venue)))
        .accessibilityAddTraits(filter.source == venue ? .isSelected : [])
        // Where this mark stands, for the flight and the scrub.
        .scrubFrame(key, in: frames)
    }

    // MARK: - Pieces

    /// A section's header (prd §1013): the category's glyph bare, the way
    /// the dock draws it — no disc (user: "use plain not disc for the header
    /// icons just like we have in our docks") — then the word and, for a
    /// room, the chevron. It labels its marks, so it sits in the secondary
    /// ink and steps back; a pill or a card here would be a third pill and a
    /// plate (§746, §782). Tint says selected; the attention colour says a
    /// seat inside needs you (the label says it too).
    private func header(glyph: String, word: String, lit: Bool, broken: Bool,
                        opens: Bool, hot: Bool = false) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: glyph)
                .dsGlyph(.subhead, weight: .medium)
                .frame(width: Self.glyphSlot)
                .foregroundStyle(broken ? DS.attention : (lit ? DS.tint : DS.textSecondary))
                .symbolEffect(.bounce.up, value: lit ? bounceTick : 0)
                .modifier(Lifted(on: hot, reduceMotion: reduceMotion))
            Text(word)
                .dsText(.heading17)
                .foregroundStyle(lit ? DS.tint : DS.textSecondary)
                .lineLimit(1)
            if opens { DSChevron() }
        }
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    /// A You door (prd §976a): a circle in the room head's charcoal
    /// (`surfaceRaised`, §1014 — black on the black tray had no edge) with
    /// the glyph in the brand pink, and the standing door FILLS — the pink
    /// tile, white glyph and
    /// the top sheen `BridgeIcon` gives a seat with no art. Selection is the
    /// fill, so the door needs no ring.
    private func doorTile(_ glyph: String, lit: Bool) -> some View {
        Circle()
            .fill(lit ? DS.brand : DS.surfaceRaised)
            .overlay {
                if lit {
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.16), .clear],
                                                 startPoint: .top, endPoint: .center))
                }
            }
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: Self.mark * 0.43, weight: .semibold))
                    .foregroundStyle(lit ? Color.white : DS.brand)
                    .symbolEffect(.bounce.up, value: lit ? bounceTick : 0)
            )
            .frame(width: Self.mark, height: Self.mark)
            .animation(DS.Motion.standard, value: lit)
    }

    private func door(_ door: Door, index: Int) -> some View {
        Button {
            tapped(door.act)
        } label: {
            VStack(spacing: DS.Space.s2) {
                doorTile(door.glyph, lit: door.lit)
                    .modifier(Lifted(on: hot == .door(index), reduceMotion: reduceMotion))
                Text(door.word)
                    .dsText(.label12)
                    .foregroundStyle(door.lit ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: Self.mark)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(door.word))
        .accessibilityAddTraits(door.lit ? .isSelected : [])
        .scrubFrame(.door(index), in: frames)
        .modifier(Dealt(on: dealt, index: index, reduceMotion: reduceMotion))
    }

    /// The thing under a scrubbing finger lifts; under Reduce Motion it does
    /// not move, and the name column carries the pick alone.
    private struct Lifted: ViewModifier {
        let on: Bool
        let reduceMotion: Bool
        func body(content: Content) -> some View {
            content
                .scaleEffect(on && !reduceMotion ? RoomsTray.hotScale : 1)
                .animation(DS.Motion.press, value: on)
        }
    }

    // MARK: - Press and slide (§1002)

    /// What a row's name column says while the finger is on one of its
    /// marks: the source's seat name in its category row. Nil when the
    /// finger is elsewhere. A You door carries its own word (§1012).
    private func scrubWord(in present: [String], recent: Bool = false) -> String? {
        switch hot {
        case .source(let venue)? where !recent && present.contains(venue),
             .recent(let venue)? where recent:
            return BridgeCatalog.seatName(forSource: venue)
        default:
            return nil
        }
    }

    /// Hold, then slide. The hold arms it (scroll off, a lift tick); the
    /// first move takes the release from the Button underneath; each new
    /// thing under the finger ticks; letting go lands on it.
    private var scrub: some Gesture {
        LongPressGesture(minimumDuration: Self.scrubArm)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !scrubbing {
                    scrubbing = true
                    DSHaptic.lift()
                }
                guard let point = drag?.location else { return }
                swallowTap = true
                let target = frames.target(at: point)
                if target != hot {
                    hot = target
                    if target != nil { DSHaptic.selection() }
                }
            }
            .onEnded { _ in
                let target = hot
                hot = nil
                scrubbing = false
                #if DEBUG
                NSLog("trayScrub: %@", target.map { "\($0)" } ?? "none")
                #endif
                if let target {
                    perform(target)
                } else if swallowTap {
                    // Let go over nothing: nothing is picked, and the next
                    // tap is a tap again.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        swallowTap = false
                    }
                }
            }
    }

    private func perform(_ target: ScrubTarget) {
        switch target {
        case .door(let i):
            let all = doors()
            if all.indices.contains(i) { all[i].act() }
        case .category(let category):
            pick(category)
        case .source(let venue):
            pick(venue, flying: true, from: .source(venue))
        case .recent(let venue):
            pick(venue, flying: true, from: .recent(venue))
        }
    }

    /// A Button's act, unless a scrub already answered this release.
    private func tapped(_ act: () -> Void) {
        guard !swallowTap else { return }
        act()
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
    /// A source mark also FLIES to the room's head as the tray drops (§932).
    private func pick(_ target: String, flying: Bool = false, from key: ScrubTarget? = nil) {
        DSHaptic.selection()
        if flying, !reduceMotion, let key, let from = frames.map[key], from != .zero {
            chrome.roomPick = ShellChrome.RoomPick(source: target, from: from)
        }
        close()
        if !route.path.isEmpty { route.path = [] }
        chrome.lastChipTouch = Date.timeIntervalSinceReferenceDate
        chrome.sourceRequest = target
    }

    /// Open Accounts on Connect; its switcher holds Manage (§933, §958).
    private func connect() {
        DSHaptic.selection()
        close()
        route.openConnect = true
        route.present(.apps)
    }

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

/// A pickable thing in the tray: a You door by position, a category by its
/// label, a source by its seat — in its category, or on the Recent line.
enum ScrubTarget: Hashable {
    case door(Int)
    case category(String)
    case source(String)
    case recent(String)
}

/// The tray's layout, in window space (§1002). A class held in `@State` and
/// never observed, so writing a frame on every scroll step re-renders
/// nothing — `ShellChrome.pagerFrame`'s rule, layout is not state.
final class TrayFrames {
    var map: [ScrubTarget: CGRect] = [:]
    var viewport: CGRect = .zero

    /// The thing whose 44pt target holds the point, inside the visible
    /// window only.
    func target(at point: CGPoint) -> ScrubTarget? {
        guard viewport == .zero || viewport.contains(point) else { return nil }
        return map.first { $0.value.contains(point) }?.key
    }
}

private extension View {
    /// Record where a pickable thing stands, and forget it when it goes.
    func scrubFrame(_ target: ScrubTarget, in frames: TrayFrames) -> some View {
        background {
            GeometryReader { g in
                Color.clear
                    .onAppear { frames.map[target] = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in frames.map[target] = f }
                    .onDisappear { frames.map[target] = nil }
            }
        }
    }
}

/// A picked source's mark on its way to the room's head (§932) — the capture
/// flight run the other way: a `BridgeIcon` leaves the tray where the finger
/// was and lands where the room's name is about to say it. Hosted on
/// `RootShell`'s stack beside `CaptureFlight`, above the tray, under nothing.
/// Reduce Motion skips it whole.
struct RoomPickFlight: View {
    let pick: ShellChrome.RoomPick
    let target: CGRect
    var onDone: () -> Void
    @State private var flown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let start = CGPoint(x: pick.from.midX - origin.x, y: pick.from.midY - origin.y)
            let end = target == .zero
                ? start
                : CGPoint(x: target.minX - origin.x + DS.Face.rowCircle / 2,
                          y: target.midY - origin.y)
            // Lifts at the tray mark's size and lands at the head's (§1008).
            BridgeIcon(name: pick.source, size: RoomsTray.mark, circular: true)
                .scaleEffect(flown ? 0.6 * DS.Face.rowCircle / RoomsTray.mark : 1)
                .opacity(flown ? 0 : 1)
                .position(flown ? end : start)
                .onAppear {
                    guard !reduceMotion else { onDone(); return }
                    withAnimation(DS.Motion.standard) { flown = true }
                    Task {
                        try? await Task.sleep(for: .milliseconds(Int(DS.Motion.duration * 1000) + 50))
                        onDone()
                    }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The tray's marks, a fixed number to a line (prd §1013, §1014): the first
/// column's centre stands `edge` in from the leading side and the last one's
/// `edge` in from the trailing side, the rest spread evenly between — the You
/// doors and every section share these columns, so the tray is one grid and
/// its first column is the face's own axis. Each subview is placed by its
/// centre; a line steps the tallest subview plus `lineAir`.
struct MarkGrid: Layout {
    let columns: Int
    let edge: CGFloat
    let lineAir: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(columns) * DS.Hit.min
        guard !subviews.isEmpty else { return CGSize(width: width, height: 0) }
        let target = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? DS.Hit.min
        let lines = (subviews.count + columns - 1) / columns
        return CGSize(width: width, height: CGFloat(lines) * target + CGFloat(lines - 1) * lineAir)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let pitch = (bounds.width - 2 * edge) / CGFloat(max(columns - 1, 1))
        let target = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? DS.Hit.min
        for (i, view) in subviews.enumerated() {
            let x = bounds.minX + edge + CGFloat(i % columns) * pitch
            let y = bounds.minY + target / 2 + CGFloat(i / columns) * (target + lineAir)
            view.place(at: CGPoint(x: x, y: y), anchor: .center, proposal: .unspecified)
        }
    }
}
