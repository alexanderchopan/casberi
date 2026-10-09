import SwiftUI

// THE FEED IS ONE SCROLL (prd §1208, §1208a; user: "what if the feed was one
// continuous scroll but each section still had their same ui of the card and
// row of four buttons", "this way instead of swiping a user can scroll").
//
// On the phone the Feed stacks every category under its own box and tiles,
// in the dock's order: the pink name (a press folds it), the category's own
// box and tiles — each room's own sections, reused, so a tile switches in
// place exactly as it does in the room — then five rows and More. Nothing
// stops the scroll; nothing in it opens a screen of its own. iPad and Mac
// keep the rail and the rooms.

extension FeedScreen {
    /// Rows a section shows before More, and how many More adds.
    static let sectionFirstRows = 5
    static let sectionMoreRows = 10

    /// The section being drawn and its cap, read by `groupedSections` while
    /// that section's own sections are built (synchronously, inside this
    /// body), so every room's existing day-grouped list draws capped without
    /// each room learning about the scroll.
    @MainActor static var sectionCapNow: (category: String, rows: Int)?

    /// Whether this screen is the stacked Feed: the phone's All page.
    var scrollsCategories: Bool {
        source == "All" && roomScopeInRoom && filter.tag == "All" && bridges.connectedCount > 0
    }

    /// The categories the Feed stacks: every one with a room, in the dock's
    /// order, the Wallet (its own place) and Testnets (the tray's) excepted.
    var scrollCategories: [String] {
        HomeScope.feedCategories(chips: chrome.chipOrder)
    }

    /// The section a thing stands in: its category, Reading's under Media
    /// (prd §1204), nil for anything with no category page (a note of yours).
    static func scrollCategory(of thing: Thing) -> String? {
        guard let category = BridgeCatalog.category(forSource: thing.source) else { return nil }
        return category == RoomAccounts.readingRoom ? RoomAccounts.mediaRoom : category
    }

    /// A section's identity in the Feed's list, apart from every other id
    /// (the contents' tiles are keyed by the same names).
    static let sectionPrefix = "feedSectionGroup:"
    static func sectionID(_ category: String) -> String { sectionPrefix + category }

    /// The id a section's name carries, so the tray can scroll to it.
    static func scrollAnchor(_ category: String) -> String { "feedSection:\(category)" }

    @ViewBuilder
    func feedScrollSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let byCategory = Dictionary(grouping: visible.filter(\.isLive)) {
            Self.scrollCategory(of: $0) ?? ""
        }
        ForEach(scrollCategories.map(Self.sectionID), id: \.self) { id in
            let category = String(id.dropFirst(Self.sectionPrefix.count))
            // Live again inside the closure: `List` may run it after a heal
            // deleted a row the body's own filter saw alive.
            scrollSection(category, (byCategory[category] ?? []).live, nextEventID: nextEventID)
        }
    }

    /// One category, on one panel (prd §1208d, user: "i think G is
    /// necessary now"): the name caps its top, every row of the section
    /// stands on the panel's fill, and an end cap rounds its foot.
    @ViewBuilder
    private func scrollSection(_ category: String, _ things: [Thing], nextEventID: UUID?) -> some View {
        // A chapter's air stands between panels, never inside one.
        Section {
            Color.clear
                .frame(height: DS.Space.s6)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
            scrollHeader(category).listRowBackground(SectionPanel(part: .top))
        }
        let cap = sectionCaps[category] ?? Self.sectionFirstRows
        let _ = { Self.sectionCapNow = (category, cap) }()
        Group {
            categorySections(category, things, nextEventID: nextEventID)
        }
        .environment(\.feedSectionPanel, true)
        let _ = { Self.sectionCapNow = nil }()
        Section {
            Color.clear
                .frame(height: DS.Space.s4)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(SectionPanel(part: .bottom))
                .accessibilityHidden(true)
        }
    }

    /// Each category's own sections — the room's tiles and list — as its
    /// page draws them, WITHOUT the newest thing's cover (prd §1208c, user:
    /// "in most places its just waste of space"): `heroShown` is the rooms'
    /// own word for "the box is taken", so their covers stand down and the
    /// newest thing stays a row. A box that says more than the newest thing
    /// stays — Day's timeline, a Subscriptions or Coming up figure.
    @ViewBuilder
    private func categorySections(_ category: String, _ things: [Thing], nextEventID: UUID?) -> some View {
        switch category {
        case RoomAccounts.dayRoom:
            dayRoomSections(things, nextEventID: nextEventID, heroShown: false)
        case RoomAccounts.workRoom:
            workRoomSections(things, nextEventID: nextEventID, heroShown: true)
        case RoomAccounts.mediaRoom:
            mediaRoomSections(things, nextEventID: nextEventID, heroShown: true)
        case RoomAccounts.socialRoom:
            socialRoomSections(things, nextEventID: nextEventID, heroShown: true)
        default:
            groupedSections(chronoDays(things), nextEventID: nextEventID)
        }
    }

    /// A section's name (prd §1208c): a chapter's title — heading28 in the
    /// pink every title wears, with a chapter's air above it — and nothing
    /// to press: the sections do not fold (§1208c retires §1208a's fold).
    private func scrollHeader(_ category: String) -> some View {
        Text(category)
            .dsText(.heading28)
            .foregroundStyle(DS.brandInk)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .id(Self.scrollAnchor(category))
            .padding(.leading, DSRoomChassis.rowInset)
            .padding(.trailing, DSRoomChassis.rowInset)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
            // Where you are (prd §1208d): each name reports where it stands,
            // so the pill above the scroll names the section you are in.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
                noteSectionTop(category, y)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }

    /// The line a section's name passes to become "where you are".
    static let whereLine: CGFloat = 150

    /// A name moved: the section you are in is the last whose name has
    /// passed the line. Written only when it changes, so a scroll costs one
    /// dictionary write per frame and a body pass per section crossed.
    private func noteSectionTop(_ category: String, _ y: CGFloat) {
        memo.sectionTops[category] = y
        let current = scrollCategories.last { (memo.sectionTops[$0] ?? .infinity) < Self.whereLine }
        if feedSection != current { feedSection = current }
    }

    /// THE TITLE SAYS WHERE YOU ARE (prd §1208d): once a section's name has
    /// scrolled past, a floating pill names it — "Feed · Social" — the way
    /// Music and Settings keep a page's name with you. A press takes the
    /// Feed back to its top (prd §1212), the way the status bar does.
    @ViewBuilder
    func feedSectionPill(_ proxy: ScrollViewProxy) -> some View {
        if scrollsCategories, let section = feedSection {
            Button {
                DSHaptic.tap()
                returnToRoomTop(proxy)
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Text("Feed").foregroundStyle(DS.textSecondary)
                    Text(verbatim: "·").foregroundStyle(DS.textTertiary)
                    Text(verbatim: section).foregroundStyle(DS.brandInk)
                }
                .dsText(.heading17)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s2)
                .dsGlass(cornerRadius: 999)
                .contentShape(Capsule())
            }
            .buttonStyle(PressSpring())
            .padding(.top, DSDemoMark.screenClearance + DS.Space.s1)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Scrolls to the top"))
        }
    }

    /// More (prd §1208 item 4): ten more rows in place; the scroll goes on
    /// into the next category.
    func sectionMoreRow(_ category: String) -> some View {
        Button {
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) {
                sectionCaps[category] = (sectionCaps[category] ?? Self.sectionFirstRows) + Self.sectionMoreRows
            }
        } label: {
            DSPushRowLabel(title: Text("More from \(category)"), fact: nil,
                           tint: DS.tint, opens: false) {
                DSGlyphLead(glyph: "arrow.down", tint: DS.tint)
            }
            .padding(.vertical, DS.Space.s2)
            .frame(minHeight: DS.Hit.min)
        }
        .buttonStyle(RowPress())
        .feedRowBackground()
        .listRowInsets(.init(top: Self.rowAir,
                             leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir,
                             trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    /// The tray asked for a category (prd §1208 item 6): scroll its name to
    /// the top.
    func settleFeedJump(_ proxy: ScrollViewProxy) {
        guard source == "All", let category = chrome.feedJump else { return }
        #if DEBUG
        NSLog("[Casberi] feedJump: %@", category)
        #endif
        chrome.feedJump = nil
        // Twice: once the list has its rows, and again once a list still
        // laying out its sections above has settled (a cold landing).
        Task { @MainActor in
            // The section's own identity first — the list knows it before
            // the section's rows are laid out — then its name, exactly.
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(DS.Motion.standard) { proxy.scrollTo(Self.sectionID(category), anchor: .top) }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(DS.Motion.standard) { proxy.scrollTo(Self.scrollAnchor(category), anchor: .top) }
        }
    }
}

/// A section's panel (prd §1208d, amends §782 for the Feed's sections only):
/// the room's fill, inset to the box's column, its top and foot rounded at
/// the widget radius so a category reads as one object.
struct SectionPanel: View {
    enum Part { case top, middle, bottom }
    let part: Part

    var body: some View {
        let r = DS.Radius.widget
        UnevenRoundedRectangle(topLeadingRadius: part == .top ? r : 0,
                               bottomLeadingRadius: part == .bottom ? r : 0,
                               bottomTrailingRadius: part == .bottom ? r : 0,
                               topTrailingRadius: part == .top ? r : 0,
                               style: .continuous)
            .fill(Self.fill)
            .padding(.horizontal, DS.Space.s2)
    }

    /// A shade under the boxes and tiles (theirs is `fillFaint`), so they
    /// keep their own wells on the panel.
    static let fill = Color.adaptive(dark: "#111113", light: "#F2F2F7")
}

/// NEW SINCE YOU LOOKED (prd §1208d, user: "only if scrolling past it
/// removes the dot"): a dot by a row that came after you last left, gone
/// once the row has scrolled past the top, for the rest of the visit.
struct NewDot: View {
    let id: UUID
    @State private var gone: Bool
    /// What scrolled past this visit; a later visit's line moves anyway.
    @MainActor static var seen: Set<UUID> = []

    init(id: UUID) {
        self.id = id
        _gone = State(initialValue: NewDot.seen.contains(id))
    }

    var body: some View {
        Circle()
            .fill(DS.tint)
            .frame(width: 8, height: 8)
            .opacity(gone ? 0 : 1)
            .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < FeedScreen.whereLine - 40 } action: { past in
                guard past, !gone else { return }
                NewDot.seen.insert(id)
                withAnimation(DS.Motion.standard) { gone = true }
            }
            .accessibilityLabel(Text("New"))
            .accessibilityHidden(gone)
    }
}

extension FeedScreen {
    /// The contents as tiles (prd §1208d): two across, one per category with
    /// something today, in the dock's order.
    @ViewBuilder
    func contentsGrid(_ groups: [(String, [FeedRow])], lede: Thing?) -> some View {
        let lists: [(String, [Thing])] = groups.compactMap { label, rows in
            let things = rows.compactMap { row -> Thing? in
                if case .single(let item) = row.kind { return item.live }
                return nil
            }
            return things.isEmpty ? nil : (label, things)
        }
        // ONLY THE BOX HOLDS THE NEWEST, AND EVERY TILE IS A SQUARE (prd
        // §1208j, user: "it should be in a square", "only the one on top
        // should be in the card"): the box's category leads the grid with
        // its next thing, so nothing shows twice; a category whose one thing
        // is the box's draws no tile.
        let ledeID = lede.flatMap { $0.isLive ? $0.id : nil }
        let leadCategory = lede.flatMap { $0.isLive ? Self.scrollCategory(of: $0) : nil }
        // The same news twice (an alarm that fired again) is the box's too.
        let ledeTitle = lede.flatMap { $0.isLive ? TitleSeam.split($0.title).0 : nil }
        let tiles: [(String, Int, [Thing])] = lists.compactMap { label, things in
            guard label == leadCategory else { return (label, things.count, things) }
            let rest = things.filter { $0.id != ledeID && TitleSeam.split($0.title).0 != ledeTitle }
            return rest.isEmpty ? nil : (label, things.count, rest)
        }
        let ordered = tiles.filter { $0.0 == leadCategory } + tiles.filter { $0.0 != leadCategory }
        if !ordered.isEmpty {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s2),
                                    GridItem(.flexible(), spacing: DS.Space.s2)],
                          spacing: DS.Space.s2) {
                    ForEach(ordered, id: \.0) { label, count, things in
                        // The picture is the newest one that has a picture
                        // today (user: "people like seeing the newest
                        // image"); the line stays newest.
                        GlanceTile(category: label, count: count, newest: things[0],
                                   pictured: things.first { StoredPixels.probe($0) != nil }) {
                            DSHaptic.selection()
                            chrome.sourceRequest = label
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                          bottom: 0, trailing: DSRoomChassis.inset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
        }
    }
}

/// One category at a glance (prd §1208d, §1208e): a tile with a picture
/// leads with it over two lines; a tile without one gives the whole tile to
/// the words — its app's mark beside the category, up to four lines — so
/// more of the notification fits. The whole tile jumps to the section.
struct GlanceTile: View {
    let category: String
    let count: Int
    let newest: Thing
    /// Today's newest thing in the category with a picture, if any.
    var pictured: Thing? = nil
    let action: () -> Void

    static let artHeight: CGFloat = 72
    /// Every tile one height, so the grid's rows line up whatever the words.
    static let height: CGFloat = 168

    var body: some View {
        let picture = pictured.flatMap { $0.isLive ? $0 : nil }.flatMap { shot in
            StoredPixels.probe(shot).map { (shot, $0) }
        }
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                if let (shot, size) = picture {
                    // PINNED TO THE BAND (prd §1208i): a filled picture
                    // reports its filled size, and `maxWidth: .infinity`
                    // never caps it — a wide strip widened the whole tile
                    // past its column, over its neighbour and off the screen.
                    GeometryReader { geo in
                        StoredPicture(shot, size: size) { image in
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(height: Self.artHeight)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s2) {
                        if picture == nil { mark }
                        Text(verbatim: category)
                            .dsText(.label12)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.brandInk)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: "\(count)")
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                    }
                    Text(verbatim: newest.isLive ? newest.title : "")
                        .dsText(.body17)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(picture == nil ? 4 : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity,
                   minHeight: Self.height, maxHeight: Self.height,
                   alignment: .topLeading)
            .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(verbatim: "\(category), \(count). \(newest.isLive ? newest.title : "")"))
        .accessibilityHint(Text("Shows this section"))
    }

    /// The newest thing's app, else — a source with no mark of its own — the
    /// category's glyph, never a name drawn as a mark.
    @ViewBuilder
    private var mark: some View {
        let source = newest.isLive ? newest.source : ""
        if BridgeCatalog.category(forSource: source) != nil {
            BridgeIcon(name: source, size: DS.Mark.badge)
                .frame(width: DS.Mark.badge, height: DS.Mark.badge)
        } else {
            Image(systemName: CategoryFold.glyph(for: category))
                .dsGlyph(.caption)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Mark.badge, height: DS.Mark.badge)
        }
    }
}
