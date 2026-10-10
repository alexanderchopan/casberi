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

    /// The sections the pill names (prd §1208d): the Feed's categories, or
    /// the Wallet Home's lists (prd §1219).
    var pillSections: [String] {
        if scrollsCategories { return scrollCategories }
        if shape == .wallet, (chrome.walletSection ?? .home) == .home { return Self.walletHomeNames }
        return []
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
    func feedScrollSections(_ visible: [Thing], hiding shown: Set<UUID>, nextEventID: UUID?) -> some View {
        let byCategory = Dictionary(grouping: visible.filter { $0.isLive && !shown.contains($0.id) }) {
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
        let _ = { memo.sectionCounts[category] = things.count }()
        let cap = sectionCaps[category] ?? Self.sectionFirstRows
        panelSection(category, glyph: CategoryFold.glyph(for: category), things: things) {
            let _ = { Self.sectionCapNow = (category, cap) }()
            categorySections(category, things, nextEventID: nextEventID)
            let _ = { Self.sectionCapNow = nil }()
        }
    }

    /// A named section on its panel (prd §1208d): the name caps the top,
    /// the rows stand on the panel's fill, an end cap rounds the foot. The
    /// Feed's categories and the Wallet's Home lists (prd §1219) both draw
    /// through this one template.
    @ViewBuilder
    func panelSection<Rows: View>(_ name: String, glyph: String, things: [Thing],
                                  @ViewBuilder rows: () -> Rows) -> some View {
        // A chapter's air stands between panels, never inside one. The name
        // carries an identity the list knows before it is laid out, so a
        // jump can land on a section still off screen.
        Section {
            ForEach([Self.scrollAnchor(name)], id: \.self) { _ in
                Color.clear
                    .frame(height: DS.Space.s6)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
                scrollHeader(name, glyph: glyph, things).listRowBackground(SectionPanel(part: .top, lit: landedSection == name))
            }
        }
        Group {
            rows()
        }
        .environment(\.feedSectionPanel, true)
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

    /// A section's name (prd §1208c, §1208l): a chapter's title in the pink
    /// every title wears, its category's glyph before it and what is new
    /// since your last visit after it (counting down as the dots fade).
    /// Nothing to press: the sections do not fold (§1208c), and nothing in
    /// the Feed opens a screen of its own (§1208a). As it reaches the top it
    /// shrinks into the pill that names where you are.
    private func scrollHeader(_ category: String, glyph: String, _ things: [Thing]) -> some View {
        let seen = NewSeen.shared.ids
        let fresh = newSince.map { since in
            things.filter { $0.isLive && $0.capturedAt > since && !seen.contains($0.id) }.count
        } ?? 0
        let calm = reduceMotion
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: glyph)
                .dsGlyph(.body)
                .foregroundStyle(DS.brandInk)
                .accessibilityHidden(true)
            Text(category)
                .dsText(.heading28)
                .foregroundStyle(DS.brandInk)
                .lineLimit(1)
            if fresh > 0 {
                HStack(spacing: DS.Space.s1) {
                    Circle().fill(DS.tint).frame(width: 7, height: 7)
                    Text("\(fresh) new")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(fresh)))
                }
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(DS.Motion.standard, value: fresh)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.leading, DSRoomChassis.rowInset)
        .padding(.trailing, DSRoomChassis.rowInset)
        .padding(.top, DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
        // THE HANDOFF (prd §1208l): tied to where the name stands, never a
        // timer — between a little under the line and the line it shrinks
        // toward the pill and fades; under Reduce Motion it only fades.
        .visualEffect { content, proxy in
            let y = proxy.frame(in: .global).minY
            let t = min(max((Self.whereLine + Self.handoffSpan - y) / Self.handoffSpan, 0), 1)
            return content
                .scaleEffect(calm ? 1 : 1 - 0.25 * t, anchor: .leading)
                .opacity(1 - t)
        }
        // Where you are (prd §1208d): each name reports where it stands,
        // so the pill above the scroll names the section you are in.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
            noteSectionTop(category, y)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    /// How far above the line a name starts handing off to the pill.
    static let handoffSpan: CGFloat = 56

    /// The line a section's name passes to become "where you are".
    static let whereLine: CGFloat = 150

    /// A name moved: the section you are in is the last whose name has
    /// passed the line. Written only when it changes, so a scroll costs one
    /// dictionary write per frame and a body pass per section crossed.
    private func noteSectionTop(_ category: String, _ y: CGFloat) {
        memo.sectionTops[category] = y
        let current = pillSections.last { (memo.sectionTops[$0] ?? .infinity) < Self.whereLine }
        guard feedSection != current else { return }
        // The word pushes in from the way you are going, and a section
        // crossed is felt once (prd §1208l) — a change of place, never a tap.
        let order = pillSections
        let from = feedSection.flatMap { order.firstIndex(of: $0) } ?? -1
        let to = current.flatMap { order.firstIndex(of: $0) } ?? -1
        feedSectionForward = to >= from
        if feedSection != nil, current != nil { DSHaptic.selection() }
        feedSection = current
    }

    /// THE TITLE SAYS WHERE YOU ARE (prd §1208d): once a section's name has
    /// scrolled past, a floating pill names it — "Feed · Social" — the way
    /// Music and Settings keep a page's name with you. A press takes the
    /// Feed back to its top (prd §1212), the way the status bar does.
    @ViewBuilder
    func feedSectionPill(_ proxy: ScrollViewProxy) -> some View {
        Group {
            if !pillSections.isEmpty, let section = feedSection {
                // A press takes the Feed to its top (prd §1212); a hold lists
                // the sections in Feed order with today's counts, and a pick
                // scrolls there (prd §1208l). The Wallet's Home wears the same
                // pill over its lists (prd §1219).
                let wallet = shape == .wallet
                Menu {
                    ForEach(pillSections, id: \.self) { category in
                        Button {
                            if wallet {
                                walletHomeJump(category)
                            } else {
                                chrome.feedJump = category
                                settleFeedJump(proxy)
                            }
                        } label: {
                            Label {
                                Text(verbatim: category)
                            } icon: {
                                Image(systemName: wallet ? Self.walletHomeGlyph(category) : CategoryFold.glyph(for: category))
                            }
                            if !wallet, let n = memo.sectionCounts[category], n > 0 {
                                Text("\(n) today")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: DS.Space.s1) {
                        (wallet ? Text("Wallet") : Text("Feed")).foregroundStyle(DS.textSecondary)
                        Text(verbatim: "·").foregroundStyle(DS.textTertiary)
                        Text(verbatim: section)
                            .foregroundStyle(DS.brandInk)
                            .id(section)
                            .transition(reduceMotion ? .opacity
                                        : .push(from: feedSectionForward ? .bottom : .top))
                            .animation(DS.Motion.standard, value: section)
                            .clipped()
                    }
                    .dsText(.heading17)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s2)
                    .dsGlass(cornerRadius: 999)
                    .contentShape(Capsule())
                } primaryAction: {
                    DSHaptic.tap()
                    returnToRoomTop(proxy)
                }
                .buttonStyle(PressSpring())
                .padding(.top, DSDemoMark.screenClearance + DS.Space.s1)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("Scrolls to the top. Hold for the sections."))
            }
        }
        // The pill's own coming and going, and nothing else in the Feed: on
        // the List it animated every row that landed as a section changed.
        .animation(DS.Motion.standard, value: feedSection == nil)
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
        // The Feed on screen takes the jump, never one mounted beside it.
        guard source == "All", isActive, let category = chrome.feedJump else { return }
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
            // LANDING (prd §1208l): the section you arrived at brightens once,
            // so the eye finds where it landed.
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(DS.Motion.standard) { landedSection = category }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.6)) { landedSection = nil }
        }
    }
}

/// A section's panel (prd §1208d, amends §782 for the Feed's sections only):
/// the room's fill, inset to the box's column, its top and foot rounded at
/// the widget radius so a category reads as one object.
struct SectionPanel: View {
    enum Part { case top, middle, bottom }
    let part: Part
    /// Brightened once on landing (prd §1208l).
    var lit = false

    var body: some View {
        let r = DS.Radius.widget
        UnevenRoundedRectangle(topLeadingRadius: part == .top ? r : 0,
                               bottomLeadingRadius: part == .bottom ? r : 0,
                               bottomTrailingRadius: part == .bottom ? r : 0,
                               topTrailingRadius: part == .top ? r : 0,
                               style: .continuous)
            .fill(lit ? DS.fillFaint : Self.fill)
            .padding(.horizontal, DS.Space.s2)
    }

    /// A shade under the boxes and tiles (theirs is `fillFaint`), so they
    /// keep their own wells on the panel.
    static let fill = Color.adaptive(dark: "#111113", light: "#F2F2F7")
}

/// NEW SINCE YOU LOOKED (prd §1208d, user: "only if scrolling past it
/// removes the dot"): a dot by a row that came after you last left, gone
/// once the row has scrolled past the top, for the rest of the visit.
/// What scrolled past this visit, observed, so a section's "N new" counts
/// down as its dots fade (prd §1208l); a later visit's line moves anyway.
@MainActor @Observable final class NewSeen {
    static let shared = NewSeen()
    var ids: Set<UUID> = []
}

struct NewDot: View {
    let id: UUID
    @State private var gone: Bool

    init(id: UUID) {
        self.id = id
        _gone = State(initialValue: NewSeen.shared.ids.contains(id))
    }

    var body: some View {
        Circle()
            .fill(DS.tint)
            .frame(width: 8, height: 8)
            .opacity(gone ? 0 : 1)
            .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < FeedScreen.whereLine - 40 } action: { past in
                guard past, !gone else { return }
                NewSeen.shared.ids.insert(id)
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
    func contentsGrid(_ specs: [GlanceSpec], onPick: ((String) -> Void)? = nil) -> some View {
        if !specs.isEmpty {
            Section {
                GlanceGrid {
                    ForEach(specs, id: \.category) { spec in
                        GlanceTile(category: spec.category, fresh: Self.fresh(spec.things, since: newSince),
                                   newest: spec.newest, next: spec.next,
                                   pictured: spec.pictured, cast: spec.cast) {
                            DSHaptic.selection()
                            if let onPick { onPick(spec.category) } else { chrome.sourceRequest = spec.category }
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

    /// One glance tile, decided once so the grid and the sections under it
    /// agree on what the tile showed (prd §1208l).
    struct GlanceSpec {
        let category: String
        let things: [Thing]
        let newest: Thing
        /// Drawn under the newest only on a tile with no picture or faces.
        let next: Thing?
        let pictured: Thing?
        let cast: ThingCastRoll?
    }

    /// The tiles (prd §1208d, §1208j, §1208k): two across, one per category
    /// with something today, in the dock's order, the box's category first
    /// with what comes after the box's thing.
    static func glanceSpecs(_ groups: [(String, [FeedRow])], lede: Thing?) -> [GlanceSpec] {
        let lists: [(String, [Thing])] = groups.compactMap { label, rows in
            let things = rows.compactMap { row -> Thing? in
                if case .single(let item) = row.kind { return item.live }
                return nil
            }
            return things.isEmpty ? nil : (label, things)
        }
        // ONLY THE BOX HOLDS THE NEWEST (prd §1208j); the same news twice
        // (an alarm that fired again) is the box's too.
        let ledeID = lede.flatMap { $0.isLive ? $0.id : nil }
        let leadCategory = lede.flatMap { $0.isLive ? scrollCategory(of: $0) : nil }
        let ledeTitle = lede.flatMap { $0.isLive ? TitleSeam.split($0.title).0 : nil }
        let tiles: [(String, [Thing])] = lists.compactMap { label, things in
            guard label == leadCategory else { return (label, things) }
            let rest = things.filter { $0.id != ledeID && TitleSeam.split($0.title).0 != ledeTitle }
            return rest.isEmpty ? nil : (label, rest)
        }
        let ordered = tiles.filter { $0.0 == leadCategory } + tiles.filter { $0.0 != leadCategory }
        return ordered.map { label, things in
            // The picture is the newest one that has a picture today (user:
            // "people like seeing the newest image"); the line stays newest.
            let pictured = things.first { StoredPixels.probe($0) != nil }
            let cast = label == RoomAccounts.socialRoom ? Self.cast(of: things) : nil
            let next = (pictured == nil && cast == nil) ? things.dropFirst().first : nil
            return GlanceSpec(category: label, things: things, newest: things[0], next: next,
                              pictured: pictured, cast: cast)
        }
    }

    /// SECTIONS SKIP WHAT THE TILES SHOWED (prd §1208l, user: "Sections skip
    /// what tiles showed"): the box's thing, the same news again, and each
    /// tile's line or two, so nothing is read twice going down the Feed.
    static func glanceShown(_ specs: [GlanceSpec], lede: Thing?) -> Set<UUID> {
        var out = Set<UUID>()
        if let lede, lede.isLive { out.insert(lede.id) }
        for spec in specs {
            if spec.newest.isLive { out.insert(spec.newest.id) }
            if let next = spec.next, next.isLive { out.insert(next.id) }
        }
        return out
    }
}

extension FeedScreen {
    /// How many of a tile's things came since your last visit (prd §1208k).
    static func fresh(_ things: [Thing], since: Date?) -> Int {
        guard let since else { return 0 }
        return things.filter { $0.isLive && $0.capturedAt > since }.count
    }

    /// The people in a category's things today, by handle, newest first:
    /// two or more, or nobody (one face is the app's mark's job).
    static func cast(of things: [Thing]) -> ThingCastRoll? {
        var seen = Set<String>()
        var members: [ThingCastMember] = []
        for thing in things where thing.isLive {
            guard let handle = thing.authorHandle?.trimmingCharacters(in: .whitespaces),
                  !handle.isEmpty, seen.insert(handle.lowercased()).inserted else { continue }
            members.append(ThingCastMember(handle: handle, avatarURL: thing.authorAvatarURL))
        }
        guard members.count >= 2 else { return nil }
        return ThingCastRoll(members: Array(members.prefix(ThingCast.memberCap)),
                             total: members.count, when: .now)
    }
}

/// Two across; one across at the accessibility text sizes, where a square
/// cannot hold the words (prd §1208l).
struct GlanceGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2),
                                 count: typeSize.isAccessibilitySize ? 1 : 2),
                  spacing: DS.Space.s2, content: content)
    }
}

/// One category at a glance (prd §1208d, §1208e, §1208k): a tile with a
/// picture leads with it; a tile without one gives the tile to the words —
/// the newest thing, then the one before it in grey. The head says how many
/// came since your last visit and when the newest is; money leads with its
/// figure; Social shows who. The whole tile jumps to the section.
struct GlanceTile: View {
    let category: String
    /// How many came since your last visit; nothing is said at zero.
    let fresh: Int
    let newest: Thing
    /// The thing before the newest, under it in grey when there is room.
    var next: Thing? = nil
    /// Today's newest thing in the category with a picture, if any.
    var pictured: Thing? = nil
    /// The people in today's Social things, when there are two or more.
    var cast: ThingCastRoll? = nil
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    static let artHeight: CGFloat = 72
    /// Every tile one height, so the grid's rows line up whatever the words.
    static let height: CGFloat = 168

    var body: some View {
        let picture = pictured.flatMap { $0.isLive ? $0 : nil }.flatMap { shot in
            StoredPixels.probe(shot).map { (shot, $0) }
        }
        let title = newest.isLive ? newest.title : ""
        let money = MoneyClause.split(title)
        let follower = next.flatMap { $0.isLive ? $0.title : nil }
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
                        // When the newest is: an age, or how soon an event
                        // starts.
                        Text(verbatim: LiveTimeText.short(moment))
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    if picture == nil, let cast {
                        DSLeadCast(roll: cast, source: newest.isLive ? newest.source : "", size: DS.Face.badge)
                            .padding(.vertical, DS.Space.s1)
                    }
                    if let money {
                        // Money leads with its figure, the name under it.
                        Text(verbatim: money.amount)
                            .dsText(.heading24)
                            .monospacedDigit()
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(verbatim: money.title)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text(verbatim: title)
                            .dsText(.body17)
                            .fontWeight(.medium)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil
                                       : picture != nil ? 2 : (cast != nil || follower != nil ? 2 : 4))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if picture == nil, cast == nil, let follower, !follower.isEmpty {
                        Text(verbatim: follower)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(2)
                            .padding(.top, DS.Space.s1)
                    }
                }
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s3)
                Spacer(minLength: 0)
                if fresh > 0 {
                    Text("\(fresh) new")
                        .dsText(.label12)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.bottom, DS.Space.s3)
                }
            }
            // A square, until the words need more (the accessibility sizes).
            .frame(maxWidth: .infinity,
                   minHeight: typeSize.isAccessibilitySize ? nil : Self.height,
                   maxHeight: typeSize.isAccessibilitySize ? nil : Self.height,
                   alignment: .topLeading)
            .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(verbatim: "\(category). \(title)"))
        .accessibilityValue(fresh > 0 ? Text("\(fresh) new") : Text(verbatim: ""))
        .accessibilityHint(Text("Shows this section"))
    }

    /// The moment the newest is about: an event's start (`capturedAt`), a
    /// reminder's due date, else when it came.
    private var moment: Date {
        guard newest.isLive else { return .now }
        return newest.kind == .event ? newest.capturedAt : (newest.dueAt ?? newest.capturedAt)
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
