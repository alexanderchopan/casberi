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
/// Wallet holds two accounts or fourteen. A `You` row leads with the five
/// doors the face used to open on its own: Home (the All room), Connect,
/// Manage, Addresses and Settings.
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
    /// The air between marks and between wrapped lines.
    static let markGap: CGFloat = DS.Space.s3
    /// A grabber drag past this, down, collapses or closes; up, grows.
    static let detentDrag: CGFloat = 56
    /// The two detents, as shares of the screen: rest shows You and the first
    /// rooms; grown shows the whole roster. Neither exceeds the roster's
    /// natural height — a short roster is a short tray.
    static let restShare: CGFloat = 0.58
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
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    youRow
                    ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                        categoryRow(category, index: index)
                    }
                    if chrome.chipOrder.contains(Pinboard.room) {
                        pinnedRow
                    }
                }
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

    /// You: the five doors the face opened on its own until §930, as bare
    /// glyph circles the way the source marks are bare brand circles. Home
    /// fills when you are standing in it; the rest are outlines.
    private var youRow: some View {
        let home = filter.source == "All" && route.path.isEmpty
        return HStack(alignment: .top, spacing: DS.Space.s3) {
            rowName(glyph: "person.crop.circle", word: String(localized: "You"),
                    lit: false, broken: false)
            FlowLayout(spacing: Self.markGap) {
                door(String(localized: "Home"), glyph: home ? "house.fill" : "house",
                     lit: home, index: 0) { pick("All") }
                door(String(localized: "Connect"), glyph: "square.grid.2x2", index: 1) { accounts(.connect) }
                door(String(localized: "Manage"), glyph: "slider.horizontal.3", index: 2) { accounts(.manage) }
                door(String(localized: "Addresses"), glyph: "at", index: 3) { accounts(.addresses) }
                door(String(localized: "Settings"), glyph: "gearshape", index: 4) { accounts(.settings) }
            }
            .padding(.top, (DS.Hit.min - Self.mark) / 2)
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
            .padding(.top, (DS.Hit.min - Self.mark) / 2)
        }
    }

    /// Pinned keeps the row it had on the dock — a list you built by hand.
    private var pinnedRow: some View {
        Button {
            pick(Pinboard.room)
        } label: {
            rowName(glyph: "pin.fill", word: String(localized: "Pinned"),
                    lit: filter.source == Pinboard.room, broken: false)
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("Pinned"))
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

    private func door(_ word: String, glyph: String, lit: Bool = false, index: Int,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            disc(glyph, lit: lit, broken: false)
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

    /// Open Accounts on one of its sections (prd §796's one screen).
    private func accounts(_ section: HomeRoute.AccountsSection) {
        DSHaptic.selection()
        close()
        route.openAccounts = section
        route.present(.apps)
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
