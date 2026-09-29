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
/// medium detent, and §394a's three outcomes). Liquid Glass, not a plate:
/// this surface is nothing but controls, and the HIG's materials page puts
/// controls on glass so the room reads through. A filled symbol says
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
struct RoomsTray: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route
    @Environment(FeedFilter.self) private var filter
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The name column: fixed, so every row's marks start on the same line
    /// and a crowded category wraps inside its own column, never under the
    /// name (user: "it looks bad there").
    static let nameColumn: CGFloat = 118
    /// A mark's size — the row circle, on the face ramp.
    static let mark: CGFloat = DS.Face.rowCircle
    /// The air between marks' TAP AREAS and between wrapped lines: none.
    /// Five across on a 402pt phone (user: "is there anyway we can get five
    /// tiles on a line so the you section is all on one line?"): 402 − 2 × 16
    /// inset − 118 name − 12 = 240 for the marks, five 44pt targets take 220,
    /// and a 4pt gap (236) wrapped the fifth on rounding. The circles draw at
    /// 28pt inside their targets, so the eye sees 16pt of air between them,
    /// the same across and down. The name column stays 118 — "Shopping" needs
    /// it.
    static let markGap: CGFloat = 0
    /// The air between one category and the next: none. Every row stands on
    /// the 44pt floor, so a category starts where a wrapped line of marks
    /// would — one pitch down and across, and a category with more marks
    /// than fit grows a line of its own (user, 2026-09-27: "without the
    /// extra spacing between sections. let it be dynamic if a row is added
    /// then a row is created but otherwise tighten the categories"). It was
    /// `DS.Space.s6`, 24pt on top of the 16pt the targets already leave.
    static let rowGap: CGFloat = 0
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
    @State private var markFrames: [String: CGRect] = [:]

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
                    panel(screen: geo.size.height)
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
        .onChange(of: chrome.roomsTray) { _, up in
            // Deal the marks in once the panel has landed; under Reduce
            // Motion they are simply there.
            grown = false
            drag = 0
            if reduceMotion {
                dealt = up
            } else {
                dealt = up
                if up { bounceTick += 1 }
            }
        }
    }

    // MARK: - The panel

    private func panel(screen: CGFloat) -> some View {
        let natural = contentHeight + Self.grabberHeight
        let rest = min(natural, screen * Self.restShare)
        let full = min(natural, screen * Self.grownShare)
        let height = grown ? full : rest
        return VStack(spacing: 0) {
            grabber
            ScrollView {
                VStack(alignment: .leading, spacing: Self.rowGap) {
                    youRow
                    ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                        categoryRow(category, index: index)
                    }
                }
                // The row discs centre on the column the face and every
                // room's row icons share (user, 2026-09-26: "should we move
                // the categories or their icons inset more so it is also
                // aligned w/ the fab and row icons on main pages").
                .padding(.leading, DSRoomChassis.rowLeadCentre - Self.mark / 2)
                .padding(.trailing, DSRoomChassis.inset)
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
            }
            .scrollIndicators(.hidden)
            .frame(height: max(height - Self.grabberHeight, 1))
        }
        .frame(maxWidth: .infinity)
        // The bottom corners sit below the edge: the panel is glass with one
        // radius, and only its top corners are meant to be seen.
        .padding(.bottom, DS.Radius.sheet)
        .dsGlass(cornerRadius: DS.Radius.sheet)
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
    private var categories: [String] {
        chrome.chipOrder.filter { CategoryFold.isCategory($0) }
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
    /// even at the same 28pt — a tinted fill has no edge. Now each door is
    /// `BridgeIcon`'s own fallback recipe (brand fill, white glyph, a whisper
    /// of top sheen) in `DS.brand`: the row of the app's own doors wears the
    /// app's own mark colour, the way every other row's marks wear their
    /// brands. That is §740's reading of the hue — the app identifying
    /// itself, never decorating somebody else's words — on the one row that
    /// is entirely the app's. The standing door (Home on the All feed, Notes
    /// in its room) wears the fill glyph variant and the SAME tint ring a
    /// standing source mark wears, so "you are here" is one vocabulary down
    /// the whole tray. Manage's door is deleted (prd §958, user: "both of
    /// these buttons lead to sort of the same place"): Connect opens
    /// Accounts, and its `Connect | Manage` switcher is one tap from what
    /// Manage held.
    ///
    /// Notes is the second door, right after Home (prd §969): the room you
    /// build — the notes you write and everything you pin — behind a door
    /// that is ALWAYS drawn, because a door that appears only once something
    /// is in the room (§961's Pinned) is a door nobody can find the first
    /// time. An empty room draws its empty state (§769), not nothing.
    private var youRow: some View {
        let home = filter.source == "All" && route.path.isEmpty
        let notes = Pinboard.isPinnedRoom(filter.source) && route.path.isEmpty
        return HStack(alignment: .top, spacing: DS.Space.s3) {
            // The face the button wears — your photo or the octopus — never
            // the empty contact glyph.
            HStack(spacing: DS.Space.s3) {
                YouFace(size: Self.mark)
                Text(String(localized: "You"))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: Self.nameColumn, alignment: .leading)
            .frame(minHeight: DS.Hit.min)
            FlowLayout(spacing: Self.markGap) {
                door(String(localized: "Home"), glyph: home ? "house.fill" : "house",
                     lit: home, index: 0) { pick("All") }
                door(String(localized: "Notes"), glyph: notes ? "note.text" : "note",
                     lit: notes, index: 1) { pick(Pinboard.room) }
                door(String(localized: "Connect"), glyph: "square.grid.2x2", index: 2) { connect() }
                door(String(localized: "Addresses"), glyph: "at", index: 3) { screen(.addresses) }
                door(String(localized: "Settings"), glyph: "gearshape", index: 4) { screen(.settings) }
            }
        }
    }

    private func categoryRow(_ category: String, index: Int) -> some View {
        let present = CategoryFold.scopes(category: category,
                                          present: Set(chrome.categoryVenues[category] ?? []))
        let lit = standingCategory == category
        let needsYou = broken(present)
        return HStack(alignment: .top, spacing: DS.Space.s3) {
            Button {
                pick(category)
            } label: {
                rowName(glyph: glyph(for: category, lit: lit), word: category,
                        lit: lit, broken: needsYou)
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(needsYou
                ? Text("\(category), needs your attention")
                : Text(category))
            .accessibilityAddTraits(lit ? .isSelected : [])
            FlowLayout(spacing: Self.markGap) {
                ForEach(Array(present.enumerated()), id: \.element) { slot, venue in
                    Button {
                        pick(venue, flying: true)
                    } label: {
                        BridgeIcon(name: venue, size: Self.mark, circular: true)
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
                    // Where this mark stands, for the flight it starts.
                    .background {
                        GeometryReader { g in
                            Color.clear
                                .onAppear { markFrames[venue] = g.frame(in: .global) }
                                .onChange(of: g.frame(in: .global)) { _, f in markFrames[venue] = f }
                        }
                    }
                    .modifier(Dealt(on: dealt, index: index + slot, reduceMotion: reduceMotion))
                }
            }
        }
    }

    // MARK: - Pieces

    /// A row's name: its glyph disc, then the word, in the fixed column, on
    /// the 44pt floor every control stands on.
    private func rowName(glyph: String, word: String, lit: Bool, broken: Bool) -> some View {
        HStack(spacing: DS.Space.s3) {
            disc(glyph, lit: lit, broken: broken)
                .symbolEffect(.bounce.up, value: lit ? bounceTick : 0)
            Text(word)
                .dsText(.heading17)
                .foregroundStyle(lit ? DS.tint : DS.textPrimary)
                .lineLimit(1)
        }
        .frame(width: Self.nameColumn, alignment: .leading)
        .frame(minHeight: DS.Hit.min)
    }

    /// A glyph in a circle, the size of a mark, so a door and a source share
    /// one row height. Tint says selected; the attention colour says a seat
    /// inside needs you (never the only channel: the row's label says it too).
    private func disc(_ glyph: String, lit: Bool, broken: Bool) -> some View {
        ZStack {
            Circle().fill(lit ? DS.tintDim : DS.fillFaint)
            Image(systemName: glyph)
                .dsGlyph(.subhead, weight: .medium)
                .foregroundStyle(broken ? DS.attention : (lit ? DS.tint : DS.textPrimary))
        }
        .frame(width: Self.mark, height: Self.mark)
    }

    /// A You door: a brand-pink tile the size of a source mark. The glyph
    /// sits at `BridgeIcon`'s fallback scale (0.54) so a door and the app
    /// tiles beside it are one drawing; the ring is the source marks' own.
    private func doorTile(_ glyph: String, lit: Bool) -> some View {
        Circle()
            .fill(DS.brand)
            .overlay(
                Circle().fill(LinearGradient(colors: [.white.opacity(0.16), .clear],
                                             startPoint: .top, endPoint: .center))
            )
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: Self.mark * 0.54, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce.up, value: lit ? bounceTick : 0)
            )
            .overlay {
                if lit {
                    Circle()
                        .strokeBorder(DS.tint, lineWidth: 1.5)
                        .padding(-2)
                }
            }
            .frame(width: Self.mark, height: Self.mark)
    }

    private func door(_ word: String, glyph: String, lit: Bool = false, index: Int,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            doorTile(glyph, lit: lit)
        }
        .buttonStyle(PressSpring())
        .dsTapTarget(Circle())
        .accessibilityLabel(Text(word))
        .accessibilityAddTraits(lit ? .isSelected : [])
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
    /// A source mark also FLIES to the room's head as the tray drops (§932).
    private func pick(_ target: String, flying: Bool = false) {
        DSHaptic.selection()
        if flying, !reduceMotion, let from = markFrames[target], from != .zero {
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
            BridgeIcon(name: pick.source, size: DS.Face.rowCircle, circular: true)
                .scaleEffect(flown ? 0.6 : 1)
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
