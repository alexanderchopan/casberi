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

    /// The id a section's name carries, so the tray can scroll to it.
    static func scrollAnchor(_ category: String) -> String { "feedSection:\(category)" }

    @ViewBuilder
    func feedScrollSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let byCategory = Dictionary(grouping: visible.filter(\.isLive)) {
            Self.scrollCategory(of: $0) ?? ""
        }
        ForEach(scrollCategories, id: \.self) { category in
            // Live again inside the closure: `List` may run it after a heal
            // deleted a row the body's own filter saw alive.
            scrollSection(category, (byCategory[category] ?? []).live, nextEventID: nextEventID)
        }
    }

    @ViewBuilder
    private func scrollSection(_ category: String, _ things: [Thing], nextEventID: UUID?) -> some View {
        Section { scrollHeader(category) }
        let cap = sectionCaps[category] ?? Self.sectionFirstRows
        let _ = { Self.sectionCapNow = (category, cap) }()
        categorySections(category, things, nextEventID: nextEventID)
        let _ = { Self.sectionCapNow = nil }()
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
            .padding(.top, DS.Space.s8 + DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
        .listRowBackground(Color.clear)
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
        chrome.feedJump = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(DS.Motion.standard) {
                proxy.scrollTo(Self.scrollAnchor(category), anchor: .top)
            }
        }
    }
}
