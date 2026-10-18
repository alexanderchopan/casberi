import SwiftUI

/// THE ROOM'S FRAME, ONE TEMPLATE (prd §1136f, user: "the box should never
/// move down!"; "everything should always be in the same place on every
/// screen!"; "you shouldn't be handrolling"; "it should be a template").
///
/// Every room and every place in You draws its top as three list rows — the
/// title, the box, the tiles — in a list styled once. Sources hand-rolled
/// the same three in a scroll view, matched to the feed by measurement, and
/// drifted by a few points the moment the title's length changed. Through
/// these the rows are the SAME rows, so the box and the tiles stand at one y
/// on every screen by construction, never by measurement.
/// **WHERE THE ROOM'S BOX DRAWS (prd §1403).** On the phone the box leads the
/// list (`.list`). Where the shell draws a pane the two parts take one column
/// each: the list column draws no box (`.listWithoutBox`: title, tiles,
/// sections, rows) and the pane at rest hosts the same room told to draw its
/// box alone (`.paneBox`). Every box template reads it; a row that is part of
/// the box says so (`feedRowBackground(box: true)`, or `dsPaneBoxRow` set on
/// a run of rows the pane carries — the Feed's Day section).
enum RoomBoxPlace { case list, listWithoutBox, paneBox }

extension EnvironmentValues {
    @Entry var dsRoomBoxPlace: RoomBoxPlace = .list
    /// The rows under this flag belong to the pane's box (prd §1403).
    @Entry var dsPaneBoxRow: Bool = false
}

/// The box's row (prd §1403): nothing where the pane holds the box, the box
/// itself in the pane. One modifier, so no caller spells the rule.
private struct RoomLeadListRow: ViewModifier {
    @Environment(\.dsRoomBoxPlace) private var place

    @ViewBuilder
    func body(content: Content) -> some View {
        if place == .listWithoutBox {
            EmptyView()
        } else {
            // Every box arrives with its room (prd §1379).
            content.roomBoxArrival()
                .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                     bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
                .feedRowBackground(box: true)
                .listRowSeparator(.hidden)
        }
    }
}

extension View {
    /// The list every room draws in.
    func dsRoomList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollIndicators(.hidden)
    }

    /// The title row: the room's name in the rows' column. The demo's pill
    /// reserves its band above it (prd §1005) — on a page, never in a sheet,
    /// which the pill does not cover (prd §1220).
    func dsRoomTitleListRow(inSheet: Bool = false) -> some View {
        listRowInsets(.init(top: DS.Space.s2 + (inSheet ? 0 : DSDemoMark.screenClearance),
                            leading: DSRoomChassis.inset,
                            bottom: 0, trailing: DSRoomChassis.inset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
    }

    /// The box's row: the lead at its one size (prd §760), the box's gap under
    /// it (prd §1102: an empty room's tiles stand where a full room's do).
    func dsRoomLeadListRow() -> some View { modifier(RoomLeadListRow()) }

    /// THE ROOM'S BOX OUTSIDE A LIST (prd §1179): a thing sheet's card at a
    /// room's one size — `leadBox` inside the head's well, in the rows'
    /// column — so a sheet's card and a room's box are the same box, never a
    /// second one drawn to match. What does not fit is clipped: the box never
    /// grows (§760), the rest of the sheet carries the overflow.
    ///
    /// `bleed`: the content fills the whole box to its corners — a video's
    /// frame, a picture (prd §1186) — the box's outer size and corner kept.
    @ViewBuilder
    func dsRoomBox(bleed: Bool = false) -> some View {
        if bleed {
            frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadHeight,
                  maxHeight: DSRoomChassis.leadHeight)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
                .padding(.horizontal, DSRoomChassis.inset)
        } else {
            frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
                  maxHeight: DSRoomChassis.leadBox, alignment: .topLeading)
                .clipped()
                .dsRoomHeadBlock()
                .padding(.horizontal, DSRoomChassis.inset)
        }
    }

    /// The tiles' row, straight under the box.
    func dsRoomTilesListRow() -> some View {
        // CENTERED BETWEEN THE BOX AND THE CARD BELOW (prd §1336, user: "they
        // are close to the top card more than the card below"): the next
        // section's own spacing already stands under the row.
        listRowInsets(.init(top: DS.Space.s3, leading: DSRoomChassis.inset,
                            bottom: DS.Space.s1, trailing: DSRoomChassis.inset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
    }
}

/// Whether a row stands inside one of the Feed's section panels (prd
/// §1208d): every room row's background reads this, so the same rows a room
/// draws bare stand on the panel inside the Feed's scroll.
private struct FeedSectionPanelKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var feedSectionPanel: Bool {
        get { self[FeedSectionPanelKey.self] }
        set { self[FeedSectionPanelKey.self] = newValue }
    }
}

/// A room row's background: bare, as every room's rows stand (prd §749),
/// or the section panel's fill inside the Feed's scroll (§1208d).
struct FeedRowBackground: ViewModifier {
    /// The row is the room's box, or part of it (prd §1403).
    var box: Bool = false
    /// The row holds parts for BOTH columns and gates them itself (the
    /// wallet family's chrome: the box and the tiles on one row).
    var splits: Bool = false
    @Environment(\.feedSectionPanel) private var panel
    @Environment(\.feedSectionPanelInset) private var panelInset
    @Environment(\.feedSectionPanelFilled) private var panelFilled
    @Environment(\.dsRoomBoxPlace) private var place
    @Environment(\.dsPaneBoxRow) private var paneRow

    @ViewBuilder
    func body(content: Content) -> some View {
        // WHERE THE BOX DRAWS (prd §1403): a box row stands in the pane and
        // not in the list beside it; every other row the other way round.
        let boxRow = box || paneRow
        if !splits, (place == .paneBox && !boxRow) || (place == .listWithoutBox && boxRow) {
            EmptyView()
        } else if panel {
            content.listRowBackground(SectionPanel(part: .middle, inset: panelInset, filled: panelFilled))
        } else {
            content.listRowBackground(Color.clear)
        }
    }
}

extension View {
    /// `.feedRowBackground()`, unless the row stands on a Feed
    /// section's panel (§1208d).
    /// `box`: the row is the room's box, or part of it (prd §1403) — drawn
    /// in the pane, never in a list column beside one.
    func feedRowBackground(box: Bool = false, splits: Bool = false) -> some View {
        modifier(FeedRowBackground(box: box, splits: splits))
    }
}

/// A row's own background, or the section panel's fill inside the Feed's
/// scroll (prd §1208d) — read on the row, where the environment is.
struct FeedRunBackground<Base: View>: ViewModifier {
    @Environment(\.feedSectionPanel) private var panel
    @Environment(\.feedSectionPanelInset) private var panelInset
    @Environment(\.feedSectionPanelFilled) private var panelFilled
    @Environment(\.dsRoomBoxPlace) private var place
    @Environment(\.dsPaneBoxRow) private var paneRow
    let base: Base

    @ViewBuilder
    func body(content: Content) -> some View {
        // The same rule as `FeedRowBackground` (prd §1403): a list row is the
        // list column's, a row the pane carries is the pane's.
        if (place == .paneBox && !paneRow) || (place == .listWithoutBox && paneRow) {
            EmptyView()
        } else if panel {
            content.listRowBackground(SectionPanel(part: .middle, inset: panelInset, filled: panelFilled))
        } else {
            content.listRowBackground(base)
        }
    }
}
