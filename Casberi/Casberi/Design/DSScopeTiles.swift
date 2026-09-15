import SwiftUI

/// A scope that can stand as a TILE: its word, with a glyph over it (prd §752).
/// A refinement rather than a new requirement on `DSSectionScope`, because the
/// directory screens and the person room scope with that protocol too and draw
/// words only.
protocol DSTileScope: DSSectionScope {
    /// An SF Symbol name. One table for the whole wallet family
    /// (`ScopeTileGlyph`), so a scope called Activity wears the same glyph in
    /// every room.
    var glyph: String { get }
}

/// THE SCOPES AS TILES — under the head on Home and under the figure in every
/// section, so the grid is one control in one place on every page (prd §752,
/// 2026-09-15, user: "i don't want the app to have controls at the top of the
/// screen anywhere", then, between a strip and buttons, "the buttons seem more
/// utile").
///
/// Replaces `DSScopeHeader`, which put a back chevron and a sideways-scrolling
/// row of 22pt words at the top of the screen. Two things about that strip were
/// wrong, and a tile grid answers both:
///
/// - **Where it sat.** Top of the screen. The chrome now draws this BELOW the
///   scope's figure, where §547's bar sat: figure, tiles, list.
/// - **What it hid.** Wallet has eight scopes, and a strip scrolled to
///   Permissions pushed Activity and Holdings off the leading edge with no sign
///   they were there. Four columns show all eight at once; no room in the family
///   has more than eight, so this is never more than two rows.
///
/// **Home is a tile, and there is no back chevron.** Leaving a scope and moving
/// sideways are one act on a grid that shows both, so one control does both.
///
/// **The tile is the dock's category tile** — a 20pt glyph over the
/// `dockCaption10` word, 52pt tall, the tint fill on the pick — so a scope reads
/// as the same kind of thing as the folder that opened the room. A short last
/// row is left-aligned, and every column is the same width in every room.
///
/// **Flat, never raised** (§752b). The first build gave each tile
/// `dsWidgetSurface` — the big cards' sheet fill, a 150pt pour and an 18pt
/// shadow — and eight of them side by side smeared into dark columns on the
/// device. A tile is a control on the page, like the dock's, so it takes one
/// flat `surfaceRaised` fill and nothing else.
///
/// **A room with one scope draws no grid** (§83): a single tile is a control
/// that offers nothing.
///
/// **It scrolls away with the page.** Pinning was tried in §495 and a plain
/// `List` section header does not hold a row-less section on screen; a scope
/// list is short in most rooms, so the cost is a flick back up.
struct DSScopeTiles<Scope: DSTileScope>: View {

    /// Every scope, Home first, in the room's own order.
    let sections: [Scope]
    let active: Scope
    var attention: Set<Scope> = []
    let onPick: (Scope) -> Void

    private static var columns: Int { 4 }
    /// Frozen, like the dock's `CategoryGlyph`, so a wide symbol and a tall one
    /// seat the word at the same height.
    private static var glyphSize: CGFloat { 20 }
    private static var tileHeight: CGFloat { 52 }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
    }

    var body: some View {
        if sections.count > 1 {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2),
                                     count: Self.columns),
                      alignment: .leading,
                      spacing: DS.Space.s2) {
                ForEach(sections) { section in
                    tile(section)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ section: Scope) -> some View {
        let isOn = section == active
        let wants = attention.contains(section)
        Button {
            guard !isOn else { return }
            DSHaptic.selection()
            onPick(section)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: section.glyph)
                    .font(.system(size: Self.glyphSize, weight: .medium))
                    .frame(width: Self.glyphSize + 6, height: Self.glyphSize + 2)
                Text(section.label)
                    .dsText(.dockCaption10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Color.white : DS.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
            .background { shape.fill(isOn ? DS.tint : DS.surfaceRaised) }
            // The dot the strip and the rows carry, at the tile's corner: the
            // same 6pt mark saying the same thing.
            .overlay(alignment: .topTrailing) {
                if wants {
                    Circle()
                        .fill(DS.attention)
                        .frame(width: DS.Space.s2 - 4, height: DS.Space.s2 - 4)
                        .padding(DS.Space.s2)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .dsHover()
        .accessibilityLabel(wants
                            ? Text("\(section.label), \(section.summary), needs you")
                            : Text("\(section.label), \(section.summary)"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .dsTooltip(section.summary)
    }
}
