import SwiftUI

/// The rooms tray (prd §930, 2026-09-26) — the phone's whole navigation behind
/// ONE button, the face.
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
/// **Every pick is `ShellChrome.sourceRequest`.** The strip's own tap ran
/// `go(to:)` inside `MainSurface`; this view stands above the stack and takes
/// the same hop every other room-to-room door takes, so a category label
/// resolves through `CategoryFold.landing` exactly as a chip tap did.
struct RoomsTray: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route
    @Environment(FeedFilter.self) private var filter

    /// The name column: fixed, so every row's marks start on the same line
    /// and a crowded category wraps inside its own column, never under the
    /// name (user: "it looks bad there").
    static let nameColumn: CGFloat = 118
    /// A mark's size — the row circle, on the face ramp.
    static let mark: CGFloat = DS.Face.rowCircle
    /// The air between marks and between wrapped lines.
    static let markGap: CGFloat = DS.Space.s3
    /// A downward drag on the grabber past this closes the tray.
    static let dismissDrag: CGFloat = 56
    /// The panel never covers more of the screen than this — the room stays
    /// visible behind it, which is what makes it a tray and not a screen.
    static let heightShare: CGFloat = 0.88

    @State private var drag: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

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
                    panel(cap: geo.size.height * Self.heightShare)
                        .offset(y: max(0, drag))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(chrome.roomsTray)
        .animation(DS.Motion.standard, value: chrome.roomsTray)
    }

    // MARK: - The panel

    private func panel(cap: CGFloat) -> some View {
        VStack(spacing: 0) {
            grabber
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    youRow
                    ForEach(categories, id: \.self) { category in
                        categoryRow(category)
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
            // Natural height, ceilinged — a short roster is a short tray.
            .frame(height: min(cap - Self.grabberHeight, max(contentHeight, 1)))
        }
        .frame(maxWidth: .infinity)
        .background(
            DS.surfaceSheet,
            in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet,
                                       topTrailingRadius: DS.Radius.sheet)
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityAddTraits(.isModal)
    }

    private static let grabberHeight: CGFloat = 24

    /// The one drag region (§394a): chrome that does not scroll.
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
                        if value.translation.height > Self.dismissDrag {
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

    /// You: the five doors the face opened on its own until §930, as bare
    /// glyph circles the way the source marks are bare brand circles.
    private var youRow: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            rowName(glyph: "person.crop.circle", word: String(localized: "You"), lit: false)
            FlowLayout(spacing: Self.markGap) {
                door(String(localized: "Home"), glyph: "house.fill",
                     lit: filter.source == "All") { pick("All") }
                door(String(localized: "Connect"), glyph: "square.grid.2x2") { accounts(.connect) }
                door(String(localized: "Manage"), glyph: "slider.horizontal.3") { accounts(.manage) }
                door(String(localized: "Addresses"), glyph: "at") { accounts(.addresses) }
                door(String(localized: "Settings"), glyph: "gearshape.fill") { accounts(.settings) }
            }
        }
    }

    private func categoryRow(_ category: String) -> some View {
        let present = CategoryFold.scopes(category: category,
                                          present: Set(chrome.categoryVenues[category] ?? []))
        let lit = standingCategory == category
        return HStack(alignment: .top, spacing: DS.Space.s3) {
            Button {
                pick(category)
            } label: {
                rowName(glyph: CategoryFold.glyph(for: category), word: category, lit: lit)
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(category))
            .accessibilityAddTraits(lit ? .isSelected : [])
            FlowLayout(spacing: Self.markGap) {
                ForEach(present, id: \.self) { venue in
                    Button {
                        pick(venue)
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
                }
            }
        }
    }

    /// Pinned keeps the row it had on the dock — a list you built by hand.
    private var pinnedRow: some View {
        Button {
            pick(Pinboard.room)
        } label: {
            rowName(glyph: "pin.fill", word: String(localized: "Pinned"),
                    lit: filter.source == Pinboard.room)
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("Pinned"))
    }

    // MARK: - Pieces

    /// A row's name: its glyph disc, then the word, in the fixed column.
    private func rowName(glyph: String, word: String, lit: Bool) -> some View {
        HStack(spacing: DS.Space.s3) {
            disc(glyph, lit: lit)
            Text(word)
                .dsText(.heading17)
                .foregroundStyle(lit ? DS.tint : DS.textPrimary)
                .lineLimit(1)
        }
        .frame(width: Self.nameColumn, alignment: .leading)
    }

    /// A glyph in a circle, the size of a mark, so a door and a source share
    /// one row height.
    private func disc(_ glyph: String, lit: Bool) -> some View {
        ZStack {
            Circle().fill(lit ? DS.tintDim : DS.fillFaint)
            Image(systemName: glyph)
                .dsGlyph(.subhead, weight: .medium)
                .foregroundStyle(lit ? DS.tint : DS.textPrimary)
        }
        .frame(width: Self.mark, height: Self.mark)
    }

    private func door(_ word: String, glyph: String, lit: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            disc(glyph, lit: lit)
        }
        .buttonStyle(PressSpring())
        .dsTapTarget(Circle())
        .accessibilityLabel(Text(word))
        .accessibilityAddTraits(lit ? .isSelected : [])
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

    /// Open Accounts on one of its sections (prd §796's one screen).
    private func accounts(_ section: HomeRoute.AccountsSection) {
        DSHaptic.selection()
        close()
        route.openAccounts = section
        route.present(.apps)
    }

    private func close() {
        drag = 0
        withAnimation(DS.Motion.standard) { chrome.roomsTray = false }
    }
}
