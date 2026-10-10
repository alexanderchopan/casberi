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
    func dsRoomLeadListRow() -> some View {
        listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                            bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
    }

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
        listRowInsets(.init(top: 0, leading: DSRoomChassis.inset,
                            bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
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
    @Environment(\.feedSectionPanel) private var panel

    func body(content: Content) -> some View {
        if panel {
            content.listRowBackground(SectionPanel(part: .middle))
        } else {
            content.listRowBackground(Color.clear)
        }
    }
}

extension View {
    /// `.feedRowBackground()`, unless the row stands on a Feed
    /// section's panel (§1208d).
    func feedRowBackground() -> some View { modifier(FeedRowBackground()) }
}

/// A row's own background, or the section panel's fill inside the Feed's
/// scroll (prd §1208d) — read on the row, where the environment is.
struct FeedRunBackground<Base: View>: ViewModifier {
    @Environment(\.feedSectionPanel) private var panel
    let base: Base

    func body(content: Content) -> some View {
        if panel {
            content.listRowBackground(SectionPanel(part: .middle))
        } else {
            content.listRowBackground(base)
        }
    }
}
