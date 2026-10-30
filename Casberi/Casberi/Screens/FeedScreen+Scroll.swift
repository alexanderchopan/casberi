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
        let all = HomeScope.feedCategories(chips: chrome.chipOrder)
        // THE PANE CARRIES DAY (prd §1403): beside a pane the Feed's Day
        // section — the week, the next thing, Needs you, the days — stands
        // under the Feed's box in the pane, and the list column lists the
        // rest; the pane's own instance draws Day and nothing else.
        switch roomBoxPlace {
        case .list: return all
        case .listWithoutBox: return all.filter { $0 != RoomAccounts.dayRoom }
        case .paneBox: return all.filter { $0 == RoomAccounts.dayRoom }
        }
    }

    /// **THE FEED'S ROW IS ITS CATEGORIES (prd §1328, user: "the fix isn't
    /// to close the gap its to add its row of stuff like the categories that
    /// are in the feed").** Day, Notes and the Wallet each stand a row under
    /// the box, so the Feed does too: its sections, in Feed order, on the
    /// strip their rows use. A tap lands on that section, as the pill's menu
    /// does (`feedJump`); nothing is ever lit, since the row jumps rather than
    /// narrows.
    @ViewBuilder
    var feedCategoryRow: some View {
        let tiles = scrollsCategories && !inSheet ? scrollCategories.map(FeedSectionTile.init) : []
        if tiles.count > 1 {
            Section {
                DSScopeTiles(sections: tiles + [.reorder], active: FeedSectionTile(name: ""),
                             scrollsColumns: true, verbs: [.reorder]) { picked in
                    DSHaptic.selection()
                    if picked.isReorder { feedSheet = .feedOrder; return }
                    chrome.feedJump = picked.name
                }
                .dsRoomTilesListRow()
            }
        }
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
    /// Day's apps stand in Day (prd §1343), which the catalogue files under
    /// Life. Asked once per source, never per row.
    @MainActor static func scrollCategory(ofSource source: String) -> String? {
        if RoomAccounts.host(ofSource: source)?.room == RoomAccounts.dayRoom { return RoomAccounts.dayRoom }
        guard let category = BridgeCatalog.category(forSource: source) else { return nil }
        return category == RoomAccounts.readingRoom ? RoomAccounts.mediaRoom : category
    }

    /// A section's identity in the Feed's list, apart from every other id
    /// (the contents' tiles are keyed by the same names).
    static let sectionPrefix = "feedSectionGroup:"
    static func sectionID(_ category: String) -> String { sectionPrefix + category }

    /// The id a section's name carries, so the tray can scroll to it.
    static func scrollAnchor(_ category: String) -> String { "feedSection:\(category)" }

    /// Each section's rows (prd §1343).
    func feedSectionRows(_ visible: [Thing], hiding shown: Set<UUID>) -> [String: [Thing]] {
        let live = visible.filter { $0.isLive && !shown.contains($0.id) }
        let sources = Set(live.map(\.source))
        // Each source's section once, not each row's (prd §1343): Day's apps
        // are Life's in the catalogue, and their rows stand in Day.
        var sectionOf: [String: String] = [:]
        for source in sources {
            sectionOf[source] = Self.scrollCategory(ofSource: source) ?? ""
        }
        // A note of yours, or an entry from an app you write in, stands in
        // Notes (prd §1347), whatever the app's category.
        // The Wallet's rows group under its name and no section draws them:
        // the Feed has no Wallet section (prd §1489).
        return Dictionary(grouping: live) {
            Pinboard.inRoom($0) ? HomeScope.notesSection : (sectionOf[$0.source] ?? "")
        }
    }

    /// What the Feed's own reads are keyed on (Day's rows, Notes' rows): any
    /// change to the corpus, on the Feed. Everywhere else `.idle`, so the
    /// task does nothing there.
    var feedSectionsKey: Corpus.Revision {
        guard source == "All" else { return .idle }
        return Corpus.revision(in: modelContext)
    }

    @ViewBuilder
    func feedScrollSections(_ visible: [Thing], hiding shown: Set<UUID>, nextEventID: UUID?) -> some View {
        let byCategory = feedSectionRows(visible, hiding: shown)
        ForEach(scrollCategories.map(Self.sectionID), id: \.self) { id in
            let category = String(id.dropFirst(Self.sectionPrefix.count))
            // Live again inside the closure: `List` may run it after a heal
            // deleted a row the body's own filter saw alive.
            scrollSection(category,
                          category == HomeScope.notesSection ? notesFeedRows.live : (byCategory[category] ?? []).live,
                          nextEventID: nextEventID)
        }
    }

    /// One category, on one panel (prd §1208d, user: "i think G is
    /// necessary now"): the name caps its top, every row of the section
    /// stands on the panel's fill, and an end cap rounds its foot.
    @ViewBuilder
    func scrollSection(_ category: String, _ things: [Thing], nextEventID: UUID?) -> some View {
        let _ = { memo.sectionCounts[category] = things.count }()
        let cap = sectionCaps[category] ?? Self.sectionFirstRows
        panelSection(category, glyph: CategoryFold.glyph(for: category), things: things,
                     choices: sectionChoices(category)) {
            let _ = { Self.sectionCapNow = (category, cap) }()
            categorySections(category, things, nextEventID: nextEventID)
            let _ = { Self.sectionCapNow = nil }()
        }
        // The title and the app's icon, no line under it (prd §1497).
        .environment(\.dsTitleOnly, true)
    }

    /// A named section on its panel (prd §1208d): the name caps the top,
    /// the rows stand on the panel's fill, an end cap rounds the foot. The
    /// Feed's categories and the Wallet's Home lists (prd §1219) both draw
    /// through this one template.
    @ViewBuilder
    func panelSection<Rows: View>(_ name: String, glyph: String, things: [Thing],
                                  choices: [SectionChoice] = [],
                                  @ViewBuilder rows: () -> Rows) -> some View {
        SectionPanelGroup(anchor: Self.scrollAnchor(name), lit: landedSection == name) {
            scrollHeader(name, glyph: glyph, things, choices: choices)
        } rows: {
            rows()
        }
        // Bare (prd §1382): the gaps stay, the fill goes.
        .environment(\.feedSectionPanelFilled, false)
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
        // Day reads its own rows (`dayFeedRows`): the Feed's list holds none
        // of what is ahead (prd §1343). Day's room on iPad and the Mac draws
        // this section over the room's own rows (prd §1344).
        case HomeScope.notesSection:
            notesFeedSection(things, nextEventID: nextEventID)
        case RoomAccounts.dayRoom:
            dayFeedSections(nextEventID: nextEventID,
                            rows: source == RoomAccounts.dayRoom ? things : nil)
                // The pane's rows (prd §1403): drawn there, never in a list
                // column beside one.
                .environment(\.dsPaneBoxRow, true)
        case RoomAccounts.lifeRoom:
            lifeRoomSections(things, nextEventID: nextEventID)
        case RoomAccounts.workRoom:
            // One row per object (prd §1079) on the Feed too: the Work
            // page's rows arrive folded, and folding twice changes nothing.
            workRoomSections(objectFolded(things), nextEventID: nextEventID, heroShown: true)
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
    private func scrollHeader(_ category: String, glyph: String, _ things: [Thing],
                              choices: [SectionChoice] = []) -> some View {
        let seen = NewSeen.shared.ids
        let fresh = newSince.map { since in
            things.filter { $0.isLive && $0.capturedAt > since && !seen.contains($0.id) }.count
        } ?? 0
        return SectionPanelName(name: category, glyph: glyph, choices: choices,
                                adds: sectionAdds(category)) {
            if fresh > 0 {
                HStack(spacing: DS.Space.s1) {
                    Circle().fill(DS.pickInk).frame(width: 7, height: 7)
                    Text("\(fresh) new")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(fresh)))
                }
                .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: fresh)
        // NO HANDOFF (prd §1386): the name scrolls under the pinned copy of
        // itself, as a List's section header does; nothing shrinks or fades.
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

    /// The pinned header's foot (prd §1386): a row whose bottom has passed it
    /// is under the header, out of sight (`NewDot` marks it seen there). The
    /// demo's band moves the header down, so the line moves with it (§1297).
    static var whereLine: CGFloat { topInset + pinnedHeaderHeight + DSDemoMark.screenClearance }

    /// Where the pinned header's top stands, which is where a section's own
    /// name stands when its row reaches the top. The pinned copy is drawn to
    /// the same measure as the name in the list (`SectionPanelName`'s air,
    /// its + kept as a hidden place), so the two coincide there and the
    /// handover cannot be seen: the name pins as it reaches this line, never
    /// earlier. Pinned at the header's foot, it left the name's lower half
    /// showing under its own copy wherever a scroll or a jump came to rest
    /// (two "Spending"s, two "Accounts", 2026-10-18).
    static var pinLine: CGFloat { topInset + DSDemoMark.screenClearance }

    /// The pinned header's height before it has measured itself: the name's
    /// air above (`s4`), one `heading24` line (28pt, prd §1496), its air
    /// below (`s2`).
    static let pinnedHeaderHeight: CGFloat = 51

    /// The window's top inset, read once: the overlay stands at the list's
    /// top, which is the safe area's.
    private static var topInset: CGFloat {
        if let cached = cachedTopInset { return cached }
        let top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top
        if let top, top > 0 { cachedTopInset = top; return top }
        return 59
    }
    private static var cachedTopInset: CGFloat?

    /// A name moved: the section you are in is the last whose name has
    /// reached the top. Written only when it changes, so a scroll costs one
    /// dictionary write per frame and a body pass per section crossed; the
    /// push below is the pinned header's own state and redraws it alone.
    private func noteSectionTop(_ category: String, _ y: CGFloat) {
        memo.sectionTops[category] = y
        let order = pillSections
        let line = Self.pinLine + 0.5
        let current = order.last { (memo.sectionTops[$0] ?? .infinity) <= line }
        // THE NEXT NAME PUSHES THE PINNED ONE OFF (prd §1386's "until the
        // next section's pushes it off", built): as the next section's name
        // rises into the header's height, the header rises with it, so the
        // two never overlap and the next one arrives exactly where its copy
        // takes over.
        var push: CGFloat = 0
        if let current, let i = order.firstIndex(of: current), i + 1 < order.count,
           let next = memo.sectionTops[order[i + 1]] {
            push = min(max(Self.pinLine + pinPush.height - next, 0), pinPush.height)
        }
        if abs(pinPush.offset - push) > 0.25 { pinPush.offset = push }
        guard feedSection != current else { return }
        // A section crossed is felt once (prd §1208l) — a change of place,
        // never a tap.
        if feedSection != nil, current != nil { DSHaptic.selection() }
        feedSection = current
    }

    /// **THE SECTION'S HEADER PINS (prd §1386, amends §1208d's pill).** Once
    /// a section's name has scrolled past, the same header — its pink glyph
    /// and its name at the rows' inset, on the page's ground — holds the top
    /// edge until the next section's pushes it off, as a List's section
    /// headers do. No capsule, no glass, no "Feed ·": nothing new stands at
    /// the top (§752), and the eye reads the header it already knows. A
    /// press still takes the page to its top (prd §1212), a hold still
    /// lists the sections (§1208l).
    @ViewBuilder
    func feedSectionPill(_ proxy: ScrollViewProxy) -> some View {
        Group {
            if !pillSections.isEmpty, let section = feedSection {
                // A press takes the Feed to its top (prd §1212); a hold lists
                // the sections in Feed order with today's counts, and a pick
                // scrolls there (prd §1208l). The Wallet's Home wears the same
                // pill over its lists (prd §1219).
                let wallet = shape == .wallet
                let adds = sectionAdds(section)
                // The list header's row, to its measure: the name's air above
                // and below (`SectionPanelName`) and its + — a full hit target
                // tall, which sets where the name sits — so the copy and the
                // name coincide at the top (`pinLine`), and the + still works
                // while its name is pinned.
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
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
                        HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                            Image(systemName: wallet ? Self.walletHomeGlyph(section) : CategoryFold.glyph(for: section))
                                .dsGlyph(.body)
                                .foregroundStyle(DS.brandInk)
                                .frame(width: DSRoomChassis.headGlyph)
                                .accessibilityHidden(true)
                            // No transition: the name changes where the list's
                            // own copy stands under it, and the push-off is the
                            // motion. An animated word here drew two names at once.
                            Text(verbatim: section)
                                .dsText(.heading24)
                                .foregroundStyle(DS.headInk)
                                .lineLimit(1)
                                .id(section)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    } primaryAction: {
                        DSHaptic.tap()
                        returnToRoomTop(proxy)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("Scrolls to the top. Hold for the sections."))
                    if !adds.isEmpty { SectionAddControl(name: section, adds: adds) }
                }
                .padding(.horizontal, DSRoomChassis.rowInset)
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // The page's own ground, running up under the status
                    // bar and fading out under the rows that pass beneath.
                    VStack(spacing: 0) {
                        DS.page
                        LinearGradient(colors: [DS.page, DS.page.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: DS.Space.s3)
                    }
                    .padding(.bottom, -DS.Space.s3)
                    .ignoresSafeArea(edges: .top)
                }
                .modifier(PinnedHeaderPushed(push: pinPush))
                .padding(.top, DSDemoMark.screenClearance)
                // It appears over the name it copies, at one measure, so it
                // simply is there: a fade or a slide drew the two apart.
                .transition(.identity)
            }
        }
        // The pill's own coming and going, and nothing else in the Feed: on
        // the List it animated every row that landed as a section changed.
        .animation(DS.Motion.standard, value: feedSection == nil)
    }

    /// More (prd §1208 item 4): ten more rows in place; the scroll goes on
    /// into the next category.
    func sectionMoreRow(_ category: String) -> some View {
        // The one More row (prd §1386, `DSMoreRow`): grey words and a
        // chevron at the rows' inset, never a disc, never centred.
        DSMoreRow(title: Text("More from \(category)")) {
            withAnimation(DS.Motion.standard) {
                sectionCaps[category] = (sectionCaps[category] ?? Self.sectionFirstRows) + Self.sectionMoreRows
            }
        }
        .feedRowBackground()
        .listRowInsets(.init(top: Self.rowAir,
                             leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir,
                             trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }

    /// The tray asked for a category (prd §1208 item 6): scroll its name to
    /// the top.
    /// ROOM UNDER THE LAST SECTION (user, 2026-10-10: the landing "is
    /// jarring and inconsistent"): without it the last sections cannot bring
    /// their names to the top, so a jump to them stopped lower than the rest
    /// and the pill named the section above. Air, not a footer.
    static let jumpRoomHeight: CGFloat = 380

    @ViewBuilder
    var jumpRoom: some View {
        Section {
            Color.clear
                .frame(height: Self.jumpRoomHeight)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
    }

    /// Instant landings it takes a lazily laid-out list to settle on a far
    /// section (measured: one stops short by the rows it had not met).
    static let landingPasses = 4

    func settleFeedJump(_ proxy: ScrollViewProxy) {
        // The Feed on screen takes the jump, never one mounted beside it.
        guard source == "All", isActive, let category = chrome.feedJump else { return }
        #if DEBUG
        NSLog("[Casberi] feedJump: %@", category)
        #endif
        chrome.feedJump = nil
        // **ONE LANDING, EVERY TIME (user, 2026-10-10: "it is jarring and
        // inconsistent").** An animated scroll travels to a position the list
        // has only ESTIMATED (rows off screen are not measured yet), and the
        // correction after it slid the page back the other way — up for one
        // section, down for the next. So the jump lands at once, as a section
        // index does (Contacts' letters), settles once more after layout, and
        // the brightening below is what the eye follows.
        Task { @MainActor in
            var instant = Transaction()
            instant.disablesAnimations = true
            // A far section lands on the list's estimate first; each pass
            // measures the rows it lands among, so a few settle it exactly.
            for pass in 0..<Self.landingPasses {
                try? await Task.sleep(for: .milliseconds(pass == 0 ? 60 : 70))
                withTransaction(instant) { proxy.scrollTo(Self.sectionID(category), anchor: .top) }
            }
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
extension EnvironmentValues {
    /// `SectionPanel`'s distance from the list's edge (prd §1320).
    @Entry var feedSectionPanelInset: CGFloat = DS.Space.s2
    /// Whether the panel draws its fill: nowhere, since prd §1393 (the
    /// Feed's and the Wallet's since §1382, Library's since §1383). The
    /// shape stays, so rows keep their column and the gaps their height;
    /// the only fills left are the Apps page's folders, which are not panels.
    @Entry var feedSectionPanelFilled: Bool = false
}

struct SectionPanel: View {
    enum Part { case top, middle, bottom }
    let part: Part
    /// Brightened once on landing (prd §1208l).
    var lit = false
    /// How far in from the list's edge the panel stands: the Feed's s2, or
    /// Sources' s4, where its own cards and box stand (prd §1320). Passed in,
    /// never read here: a row's background does not see the row's environment.
    var inset: CGFloat = DS.Space.s2
    /// Off on the Feed and the Wallet (prd §1382): the shape stays, so the
    /// rows keep their column and the gaps their height, and nothing fills it.
    /// Bare by default (prd §1393, then the account pages' caps, user,
    /// 2026-10-18: "all the connect and set up screens … still have gray
    /// cards"): a panel's name and its air say where it starts. The middle
    /// rows read `feedSectionPanelFilled` (false); the top and bottom caps
    /// took this default, so every connect screen kept its grey card.
    var filled = false

    var body: some View {
        let r = DS.Radius.widget
        UnevenRoundedRectangle(topLeadingRadius: part == .top ? r : 0,
                               bottomLeadingRadius: part == .bottom ? r : 0,
                               bottomTrailingRadius: part == .bottom ? r : 0,
                               topTrailingRadius: part == .top ? r : 0,
                               style: .continuous)
            .fill(filled ? (lit ? DS.fillFaint : Self.fill) : Color.clear)
            .padding(.horizontal, inset)
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
            .fill(DS.pickInk)
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
    /// **NEWEST (prd §1256, user: "i like the 'newest' card … build
    /// newest. it's great").** The glance tiles cut each category's newest
    /// to two lines in a square, and the sections under them showed the
    /// same things again (user: "hard to read b/c they cut off the feed
    /// item and harder to scan"). One card holds the newest few across every
    /// category as the Feed's rows, the box's thing left out; the sections
    /// skip them. A category is reached from the tray or its section's name.
    @ViewBuilder
    func newestCard(_ things: [Thing], nextEventID: UUID?) -> some View {
        if !things.isEmpty {
            panelSection(String(localized: "Newest"), glyph: "clock", things: things) {
                let positions = cardRunPositions(count: things.count, isBreaker: { _ in false })
                ForEach(Array(keyed(things).enumerated()), id: \.element.id) { i, item in
                    if let thing = item.live {
                        // The title and the app's icon, as every Feed row
                        // (prd §1497, user: "i don't like that the newest
                        // category shows the name of the app on supertext
                        // above"). The icon says where it came from, so the
                        // app's name and time over the title (§1256) went.
                        shapedListRow(thing, index: i, nextEventID: nextEventID, position: positions[i])
                    }
                }
            }
            .environment(\.dsTitleOnly, true)
        }
    }

    /// How many rows Newest holds.
    static let newestRows = 5

    /// The newest live things across the Feed's own categories, NEVER
    /// day-bound (prd §1399, user, past midnight: "or is it because it's
    /// midnight and its reset?" — "make Newest match the box"): the card is
    /// named Newest, not Today, so the five newest things are its answer at
    /// 00:05 as at 18:00, as the box always holds the newest thing (§1136i).
    /// The box's thing and the same news again are left out (prd §1208j);
    /// `elsewhere` names the categories that are their own place (§1331).
    /// `.isLive` before any read, the dead-Thing rule; one pass, a bounded
    /// top-N, never a sort of the whole set.
    ///
    /// ONE thing per app (prd §1581, user: "yes that is how it should be"),
    /// the sections' own rule (§1103): a busy app's newer thing takes its one
    /// slot, so no single app can fill the card.
    static func newestThings(_ visible: [Thing], lede: Thing?, elsewhere: Set<String>) -> [Thing] {
        let ledeID = lede.flatMap { $0.isLive ? $0.id : nil }
        let ledeTitle = lede.flatMap { $0.isLive ? TitleSeam.split($0.title).0 : nil }
        let now = Date.now
        var top: [Thing] = []
        top.reserveCapacity(newestRows + 1)
        for thing in visible {
            guard thing.isLive, thing.id != ledeID else { continue }
            let at = thing.capturedAt
            guard at <= now else { continue }
            if top.count == newestRows, let last = top.last, at <= last.capturedAt { continue }
            guard TitleSeam.split(thing.title).0 != ledeTitle,
                  !elsewhere.contains(BridgeCatalog.category(forSource: thing.source) ?? "") else { continue }
            if let same = top.firstIndex(where: { $0.source == thing.source }) {
                guard top[same].capturedAt < at else { continue }
                top.remove(at: same)
            }
            let i = top.firstIndex { $0.capturedAt < at } ?? top.count
            top.insert(thing, at: i)
            if top.count > newestRows { top.removeLast() }
        }
        return top
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

/// The glance frame's one height.
enum GlanceMetrics {
    static let height: CGFloat = 168
}

/// THE GLANCE TILE'S FRAME (prd §1208d, §1222): one height, the room's faint
/// fill, a press, a head of mark · category · when, then the words, then
/// "N new". What this app reaches draws a category in it (the Feed's and the
/// Wallet's tiles went with prd §1256 and §1257).
struct GlanceShell<Top: View, Mark: View, Words: View>: View {
    let category: String
    let when: String?
    var fresh: Int = 0
    let accessibility: Text
    let action: () -> Void
    @ViewBuilder let top: Top
    @ViewBuilder let mark: Mark
    @ViewBuilder let words: Words
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                top
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s2) {
                        mark
                        Text(verbatim: category)
                            .dsText(.label12)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.headInk)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let when {
                            Text(verbatim: when)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    words
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
                   minHeight: typeSize.isAccessibilitySize ? nil : GlanceMetrics.height,
                   maxHeight: typeSize.isAccessibilitySize ? nil : GlanceMetrics.height,
                   alignment: .topLeading)
            .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(accessibility)
        .accessibilityValue(fresh > 0 ? Text("\(fresh) new") : Text(verbatim: ""))
        .accessibilityHint(Text("Shows this section"))
    }
}

/// A section's name on its panel (prd §1208c, §1222): the category's glyph
/// and its name in the brand pink, then whatever the section says beside it.
struct SectionPanelName<Trailing: View>: View {
    let name: String
    let glyph: String
    /// **A SECTION'S NAME IS `heading24` (prd §1496, user: "would that mean
    /// dropping feed headers to 24?"; "i am now starting to feel the experience
    /// i wanted in the app from the very beginning, the stupid simple").** The
    /// ramp's own rung for a card's name; `heading28` was the lede's fit
    /// ladder borrowed, which put every Feed section a step over every other
    /// section in the app. The Wallet's doors stand on the same rung
    /// (`walletDoor`), so a Feed section and a Wallet door are one anatomy.
    ///
    /// **THE HEADER NAMES ITS CHOICES (prd §1251, user: "s4 is gorgeous").**
    /// In the Feed a section's tiles stand down and its header reads every
    /// choice at the title's own size, the picked one in the pink and the
    /// others grey ("Life Subscriptions"); a tap on a grey word switches.
    /// Empty: the plain name, as before.
    var choices: [SectionChoice] = []
    /// **EVERY SECTION ADDS FROM ITS HEADER (prd §1293).** A + at the end
    /// runs the category's own add, the act of its Sources count's plus
    /// (prd §1292); two acts open a menu of both. Empty: no +.
    var adds: [SectionAdd] = []
    var inset: CGFloat = DSRoomChassis.rowInset
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
            // One glyph column (user, 2026-10-23: "look how all this stuff has
            // different indentation on the headers"): a symbol drawn at its own
            // width put every title at a different x. Centered in a fixed
            // column, every section's name starts at one edge.
            Image(systemName: glyph)
                .dsGlyph(.body)
                .foregroundStyle(DS.brandInk)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            if choices.isEmpty {
                Text(verbatim: name)
                    .dsText(.heading24)
                    .foregroundStyle(DS.headInk)
                    .lineLimit(1)
            } else {
                FlowLayout(spacing: DS.Space.s3, lineSpacing: 0) {
                    ForEach(choices) { choice in
                        Button {
                            DSHaptic.selection()
                            withAnimation(DS.Motion.standard) { choice.pick() }
                        } label: {
                            Text(verbatim: choice.label)
                                .dsText(.heading24)
                                .foregroundStyle(choice.on ? DS.headInk : DS.textTertiary)
                                .lineLimit(1)
                        }
                        .buttonStyle(RowPress())
                        .accessibilityAddTraits(choice.on ? [.isSelected] : [])
                    }
                }
            }
            trailing
            Spacer(minLength: 0)
            if !adds.isEmpty { SectionAddControl(name: name, adds: adds) }
        }
        .accessibilityElement(children: choices.isEmpty && adds.isEmpty ? .combine : .contain)
        .accessibilityAddTraits(.isHeader)
        .padding(.leading, inset)
        .padding(.trailing, inset)
        .padding(.top, DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
    }
}

/// A section header's + (prd §1293): one add runs at once, two open a menu
/// of both. Drawn by the header in the list and by its pinned copy, so the +
/// works wherever the name stands (prd §1386).
struct SectionAddControl: View {
    let name: String
    let adds: [SectionAdd]

    var body: some View {
        if let only = adds.first, adds.count == 1 {
            Button {
                DSHaptic.selection()
                only.act()
            } label: { plus }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(verbatim: only.label))
        } else if !adds.isEmpty {
            Menu {
                SectionAddMenu(adds: adds)
            } label: { plus }
            .accessibilityLabel(Text("Add to \(name)"))
        }
    }

    /// The header's +, pink as every verb's plus, a full target tall and
    /// wide, on the name's baseline row.
    private var plus: some View {
        Image(systemName: "plus")
            .dsGlyph(.body, weight: .regular)
            .foregroundStyle(DS.brandInk)
            .frame(width: DS.Hit.min, height: DS.Hit.min)
            .contentShape(Rectangle())
    }
}

/// One add a section header offers (prd §1293): its verb and its act.
struct SectionAdd: Identifiable {
    var id: String { label }
    let label: String
    /// What the row follows, under its name in the menu (prd §1300).
    var detail: String? = nil
    /// Set apart from the rows above it by a divider.
    var apart = false
    /// The row's mark: an app's art by its catalogue name, else a glyph.
    var app: String? = nil
    var glyph: String? = nil
    let act: () -> Void
}

/// One row of a + menu (prd §1303): the app's mark, its name, and what it
/// follows under it — the Feed's sections and Sources' counts draw the same.
struct SectionAddMenu: View {
    let adds: [SectionAdd]

    var body: some View {
        ForEach(adds) { add in
            if add.apart { Divider() }
            // Two texts and an image straight in the label: a menu reads them
            // as title, subtitle and icon (a `Label` keeps one line only).
            Button { add.act() } label: {
                Text(verbatim: add.label)
                if let detail = add.detail { Text(verbatim: detail) }
                if let app = add.app {
                    BridgeIcon.menuMark(app)
                } else if let glyph = add.glyph {
                    Image(systemName: glyph)
                }
            }
        }
    }
}

/// One choice a section header names (prd §1251).
struct SectionChoice: Identifiable {
    let id: String
    let label: String
    let on: Bool
    let pick: () -> Void
}

extension FeedScreen {
    /// The choices a Feed section's header names: its category's filters,
    /// the first one spoken as the category itself ("Life", not "All"), no
    /// verbs (Social's Follow stays on Social's own screen).
    func sectionChoices(_ category: String) -> [SectionChoice] {
        switch category {
        // Life's one other choice was Subscriptions (prd §1293): its header
        // is the name alone. Nor Following (prd §1293), nor Work's Coming up or Social's To you
        // (prd §1296, user: "that way all the categories would be simpler"):
        // every row a section holds comes from what you follow, and the
        // header's + is its one act. Work and Social are their names alone;
        // their own screens keep the tiles.
        case RoomAccounts.mediaRoom:
            return MediaScope.allCases.filter { $0 != .subscriptions }.map { s in
                SectionChoice(id: s.rawValue, label: s == .all ? category : s.label,
                              on: chrome.mediaScope == s, pick: { chrome.mediaScope = s })
            }
        default:
            return []
        }
    }
}

extension FeedScreen {
    /// What a Feed section's + adds (prd §1293): since prd §1300 every
    /// catalogue app in the category that follows something by name
    /// (`FollowByName`), A–Z, connected or not; Social ends with the rest of
    /// its apps. A category with no such app draws no +.
    func sectionAdds(_ category: String) -> [SectionAdd] {
        var adds = FollowByName.doors(in: category).map { door in
            SectionAdd(label: door.app, detail: door.what, app: door.app) { followByName(door.app) }
        }
        // MORE SOCIAL APPS LEADS (prd §1303, user: "we don't or ever will
        // have that many bluesky users", then "do the social bluesky thing
        // too"): X, Instagram and TikTok follow nobody by name, so the first
        // row is Sources' Social card, where they connect; Bluesky and
        // Telegram stand under it.
        // **DAY ADDS FROM ITS HEADER (prd §1343, user: "each category header
        // has a + sign by it so we don't need 'new' and 'all'").** An event,
        // a reminder, an email, a subscription to track.
        // Then what Day follows by name — a calendar to subscribe to, now
        // that Calendar is Day's (prd §1347) — set apart under the makes.
        // THE WALLET'S SUBSCRIPTIONS ADDS FROM ITS HEADER (prd §1386): the
        // "+ Track a subscription" row that led its list is deleted; a list
        // with a head adds from its head.
        if shape == .wallet, category == Self.subscriptionsName {
            adds = [SectionAdd(label: SubscriptionWords.track, glyph: SubscriptionWords.planGlyph) {
                feedSheet = .subscriptionAdd
            }]
        }
        if category == RoomAccounts.dayRoom {
            var follows = adds
            if !follows.isEmpty { follows[0].apart = true }
            adds = dayMakes.map { make in
                SectionAdd(label: make.label, glyph: Self.dayMakeGlyph(make)) { makeInDay(make) }
            } + follows
        }
        // **NOTES WRITES FROM ITS HEADER (prd §1347, user: "the plus button
        // just opens notes, same way calendar plus button opens new").** A
        // note, or one spoken, as the Notes page's New and its hold do.
        if category == HomeScope.notesSection {
            adds = [
                SectionAdd(label: String(localized: "New note"), glyph: ScopeTileGlyph.new) { chrome.newNote += 1 },
                SectionAdd(label: String(localized: "Voice note"), glyph: "waveform") { chrome.newNoteByVoice() },
                // **EVERY NOTE, FROM THE FEED (2026-10-16, user: "maybe the
                // plus button should also offer an 'all notes' in its
                // menu").** The Notes page Library's folder opens, on All.
                SectionAdd(label: String(localized: "All notes"), apart: true, glyph: ScopeTileGlyph.all) {
                    chrome.notesScope = .all
                    chrome.notesFolder = nil
                    route.push(.notes)
                },
            ]
        }
        // **THE WALLET'S ACCOUNTS LIST ADDS FROM ITS HEADER (prd §1410):**
        // Follow an account, Connect an app. The Feed's Wallet section that
        // shared the menu is deleted (prd §1489, amending §1347).
        if category == Self.accountsName {
            adds = walletAccountAdds
        }
        // **EVERY + ENDS WITH ITS CATEGORY'S APPS (prd §1620, user, of Work's
        // six: "why those only and not all of them?"; "ok" to one last row).**
        // What you make and what you follow by name come first; the last row
        // opens the catalogue on the category's card, every app there,
        // connected or not. Social's row led (§1303) and now ends, as every
        // section's does.
        if let name = BridgeCatalog.categories.first(where: { $0.name == category })?.name {
            let count = BridgeCatalog.offers.filter { BridgeCatalog.category(of: $0) == name }.count
            // "More agent apps", never "agents apps": the category's noun.
            let noun = name.hasSuffix("s") ? String(name.dropLast()) : name
            adds.append(SectionAdd(label: String(localized: "More \(noun.lowercased()) apps"),
                                   detail: String(localized: "All \(count) in the catalogue"),
                                   apart: !adds.isEmpty,
                                   glyph: "square.grid.2x2") {
                route.openCategory = name
                route.present(.apps)
            })
        }
        return adds
    }

    /// What one of the + rows opens (prd §1300): the tray that app's follow
    /// already runs, on that app; an app that needs an account it doesn't
    /// have yet, or whose follow lives on its own page, opens its page.
    func followByName(_ app: String) {
        let connected = connectedSeatNames.contains(app)
        switch FollowByName.landing(for: app) {
        case .socialFollow:    feedSheet = .socialFollow
        case .reading:         feedSheet = .followingAdd(.reading)
        case .calendar:        feedSheet = .calendarSubscribe
        case .track(let room): feedSheet = .followingAdd(room, seat: app)
        case .github:
            if connected { feedSheet = .followingAdd(.work, seat: app) } else { watchOnGitHub() }
        case .mail:
            if connected { feedSheet = .mailSubscriptionAdd } else { openAppPage(app) }
        case .page:            openAppPage(app)
        }
    }

    func openAppPage(_ app: String) {
        if let destination = BridgeRouter.destination(forOffer: app) { route.openAccount(destination) }
    }

    #if DEBUG
    /// `-sectionAdd "<Category>[|<App>]"` — log what every Feed section's +
    /// lists (`sectionAdd| <Category> | <App> — <what>, …`), then take the
    /// named row of that category's +, because a moving list eats a
    /// simulator tap (prd §1300). Once per launch.
    func sectionAddProbe() {
        guard source == "All", !Self.sectionAddProbed,
              let raw = UserDefaults.standard.string(forKey: "sectionAdd") else { return }
        Self.sectionAddProbed = true
        for category in CategoryOrder.current {
            let adds = sectionAdds(category)
            NSLog("[Casberi] sectionAdd| %@ | %@", category,
                  adds.map { $0.label + ($0.detail.map { " — " + $0 } ?? "") }.joined(separator: ", "))
        }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let add = sectionAdds(parts[0]).first(where: { $0.label == parts[1] }) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            NSLog("[Casberi] sectionAdd: %@ → %@", parts[0], parts[1])
            add.act()
        }
    }
    #endif
}

extension SectionPanelName where Trailing == EmptyView {
    init(name: String, glyph: String, inset: CGFloat = DSRoomChassis.rowInset) {
        self.init(name: name, glyph: glyph, inset: inset) { EmptyView() }
    }
}

/// ONE SECTION, ON ONE PANEL (prd §1208d, §1222): a chapter's air, the name
/// capping the panel's top, the rows on its fill (each row's
/// `.feedRowBackground()` reads the environment), an end cap rounding the
/// foot. The Feed's categories, the Wallet's Home lists and What this app
/// reaches all stand in it. `anchor` gives the name an identity a `List`
/// knows before laying it out, so a jump can land on it off screen.
struct SectionPanelGroup<Header: View, Rows: View>: View {
    var anchor: String? = nil
    var lit = false
    @Environment(\.feedSectionPanelInset) private var panelInset
    @Environment(\.feedSectionPanelFilled) private var panelFilled
    @Environment(\.dsRoomBoxPlace) private var place
    @Environment(\.dsPaneBoxRow) private var paneRow
    @ViewBuilder let header: Header
    @ViewBuilder let rows: Rows

    @ViewBuilder
    var body: some View {
        // A panel stands where its rows stand (prd §1403): the list's in the
        // list column, the pane's in the pane.
        if (place == .paneBox && !paneRow) || (place == .listWithoutBox && paneRow) {
            EmptyView()
        } else {
            panel
        }
    }

    @ViewBuilder
    private var panel: some View {
        Section {
            ForEach([anchor ?? ""], id: \.self) { _ in
                // A chapter's air stands between panels, never inside one:
                // the one section gap (prd §1386), less the header's own top.
                Color.clear
                    .frame(height: DSRoomChassis.sectionGap - DS.Space.s4)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
                header
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(SectionPanel(part: .top, lit: lit, inset: panelInset, filled: panelFilled))
            }
        }
        Group {
            rows
        }
        .environment(\.feedSectionPanel, true)
        Section {
            // A bare panel has no foot (prd §1386): its air is the gap's.
            Color.clear
                .frame(height: panelFilled ? DS.Space.s4 : 0)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(SectionPanel(part: .bottom, inset: panelInset, filled: panelFilled))
                .accessibilityHidden(true)
        }
    }
}

/// **A THING SHEET'S NAMED BLOCK IS THE FEED'S SECTION (prd §1258, bare
/// since prd §1393, user: "we still have gray cards in places like on the
/// wallet thing sheets. they need to be removed from the app everywhere
/// except on the apps page where they are folders").** A pink glyph and the
/// name in the head ink, a figure trailing when the block has one, the rows
/// in the column under it, and no fill: the air between blocks is the seam,
/// as it is between the Feed's sections (§1382). Every titled block on every
/// sheet draws through this, so no sheet keeps a grey label over a loose list.
struct SheetCard<Content: View>: View {
    let name: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ONE QUIET WORD (prd §1396, user: "super clean and tidy and
            // minimal and like apple would do"): the group's name at the
            // 17pt head rung, no glyph — the pink on a sheet means a verb —
            // and 32pt of air above it (its s2 plus the s6 every caller
            // already leaves), so the groups read apart. Its rows carry
            // their own 44pt and stand with no air between them.
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: name)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if let trailing {
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: trailing)
                        .dsText(.heading17)
                        .monospacedDigit()
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Space.s1)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // No fill (prd §1393): the block's name and its air say where it
        // starts, as a section's do.
    }
}

/// Wraps a view that is already a block's rows in a `SheetCard` (prd §1258),
/// for a builder whose rows end in modifiers of their own.
struct SheetCardWrap: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        SheetCard(name: name) { content }
    }
}

/// A SECTION'S CARD OUTSIDE A LIST (prd §1227): `SectionPanelGroup`'s card for
/// a screen that is a plain stack (a tray), the same fill, radius and name.
struct SectionPanelCard<Content: View>: View {
    let name: String
    let glyph: String
    /// How far in the name and rows stand from the card's edge. A card that
    /// already stands in the room's column (Sources, prd §1253) takes the
    /// difference, so its rows land where the Feed's do on the screen.
    var inset: CGFloat = DSRoomChassis.rowInset
    /// Bare on Library's pages (prd §1383), as the Feed's panels are (§1382).
    @Environment(\.feedSectionPanelFilled) private var filled
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionPanelName(name: name, glyph: glyph, inset: inset)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                content
            }
            .padding(.horizontal, inset)
            .padding(.bottom, DS.Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(filled ? SectionPanel.fill : Color.clear,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }
}

/// One of the Feed's sections as a tile in its row (prd §1328): the
/// category's own glyph and name, in Feed order.
struct FeedSectionTile: DSTileScope {
    let name: String
    var id: String { name }
    var label: String { isReorder ? String(localized: "Reorder") : name }
    var summary: String {
        isReorder ? String(localized: "Reorder sections") : String(localized: "Go to \(name)")
    }
    var glyph: String { isReorder ? ScopeTileGlyph.reorder : CategoryFold.glyph(for: name) }
    static var keepsOrder: Bool { true }

    /// **THE FEED REORDERS FROM ITS OWN ROW (prd §1345, user: "users should
    /// be able to reorder their feed from the feed and not in settings";
    /// "re A: its discoverable").** The last tile, a verb.
    static let reorder = FeedSectionTile(name: "feedSection.reorder")
    var isReorder: Bool { name == Self.reorder.name }
}

/// The pinned header's push (prd §1386): how far the next section's name has
/// pushed it up, and its own height, which sets where the push begins. Its
/// own observable, read only by `PinnedHeaderPushed`, so a frame of push
/// redraws the header, never the Feed around it.
@MainActor @Observable final class PinnedHeaderPush {
    var offset: CGFloat = 0
    var height: CGFloat = FeedScreen.pinnedHeaderHeight
}

/// Rises with the push and reports the header's height.
struct PinnedHeaderPushed: ViewModifier {
    let push: PinnedHeaderPush

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                if abs(push.height - h) > 0.25 { push.height = h }
            }
            .offset(y: -push.offset)
    }
}
