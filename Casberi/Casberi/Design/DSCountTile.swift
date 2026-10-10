import SwiftUI

/// A COUNT THAT IS A FILTER (prd §1138): a figure over its word in a room's
/// box, pressed to list what it counts below. Sources' six kinds and the
/// Apps catalogue's categories wear it; the box never moves, only the list.
///
/// The tiles' own grammar (`DSScopeTiles`): the pick fills in tint with white
/// ink, an unpicked count draws no fill (a box of grey squares is the plate
/// §782 deleted), a count that wants you says so in its WORD's tone, never a
/// dot, and a zero is quieter than a figure. Becoming the pick crossfades on
/// the template's own clock (§966).
struct DSCountTile: View {
    /// Nil draws no figure: Markets' tiles are a glyph and a name only
    /// (user: "the categories w/ no numbers, just their glyph and name").
    let count: Int?
    let label: String
    /// A category's glyph over the figure (Apps); nil draws figure and word.
    var glyph: String? = nil
    let isOn: Bool
    var wants: Bool = false
    /// The figure and its word on one line (Settings' eight kinds, two
    /// across, prd §1166), so every word stands whole, as Reminders' and
    /// Passwords' grids draw theirs.
    var inline: Bool = false
    /// The widest figure in the box, inline only: every figure stands in a
    /// column that wide, right-aligned, so every word starts at one edge
    /// (user: "need to make indentation even", of "13 Apps" over "0 Cards").
    var widest: Int? = nil
    let action: () -> Void

    /// The lead column's floor, inline: a two-digit figure's width.
    static let leadFigure = 99

    /// THE INLINE PICK IS A WASH (prd §1198, user: "lets do A w/ the lighter
    /// tint"): the place tile under the box keeps the solid tint, so the box's
    /// pick steps down a level instead of competing with it. The ink is the
    /// Increase Contrast blue in dark and one notch deeper in light, ≥4.5:1 on
    /// the wash over the well in both (the shipped blue is 3.4:1 there).
    static let pickInk = Color.adaptive(dark: "#62a1ee", light: "#0f5bb8")

    /// The inline pick's corner, concentric with `DSCountGrid`'s well: the
    /// well's corner less the box's inset (§1198).
    static var cellRadius: CGFloat { DS.Radius.widget - DS.Space.s2 }

    /// One inline row's share of the well: 52pt for four rows on the phone.
    static func cellHeight(items: Int) -> CGFloat {
        let rows = CGFloat(max(1, (items + 1) / 2))
        return (DSRoomChassis.leadHeight - 2 * DS.Space.s2 - (rows - 1) * DS.Space.s1) / rows
    }

    /// Inline, the pick is concentric with the well (`cellRadius`); stacked
    /// keeps the sheet corner.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: inline ? Self.cellRadius : DS.Radius.sheet,
                         style: .continuous)
    }

    @Environment(\.dsCountCellHeight) private var cellHeight

    var body: some View {
        let zero = count == 0 && !isOn
        Button {
            DSHaptic.selection()
            action()
        } label: {
            if inline {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    // ONE lead column for figures and glyphs alike (prd
                    // §1180, user: "THE TEXT IN THESE SHOULD BE IN THE SAME
                    // PLACE … SAME SIZE same positions etc so its seamless"):
                    // as wide and as tall as a two-digit figure, so Settings'
                    // and Markets' words start at one edge on one baseline,
                    // and their rows are one height.
                    // The column is the unseen figure; what shows rides it,
                    // so the baseline is always the figure's.
                    Text(max(widest ?? 0, Self.leadFigure).formatted())
                        .dsText(.heading24).monospacedDigit().hidden()
                        .overlay(alignment: glyph == nil ? .trailing : .center) {
                        if let glyph {
                            // Markets' tiles: a glyph where Settings' figure stands.
                            Image(systemName: glyph)
                                .dsGlyph(.body, weight: .regular)
                                .foregroundStyle(isOn ? Self.pickInk : DS.textSecondary)
                        } else {
                            Text((count ?? 0).formatted())
                                .dsText(.heading24)
                                .monospacedDigit()
                                .foregroundStyle(isOn ? Self.pickInk : zero ? DS.textTertiary : DS.textPrimary)
                        }
                    }
                    Text(label)
                        .dsText(.body17)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isOn ? Self.pickInk : wants ? DS.attentionInk : DS.textPrimary)
                }
                // s2, not s3: the figure column leaves "Subscriptions" room to
                // stand whole beside a two-digit count. The row is the box's
                // share of the well (§1198), so a pick is ≥44pt and the grid
                // fills the well instead of floating in it.
                .padding(.horizontal, DS.Space.s2)
                .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .leading)
                .background { shape.fill(isOn ? DS.tintDim : Color.clear) }
                .animation(DS.Motion.standard, value: isOn)
                .contentShape(shape)
            } else {
            VStack(alignment: glyph == nil ? .leading : .center, spacing: 2) {
                if let glyph {
                    Image(systemName: glyph)
                        .dsGlyph(.body, weight: .regular)
                        .frame(height: 20)
                        .foregroundStyle(isOn ? Color.white : zero ? DS.textTertiary : DS.textSecondary)
                }
                if let count {
                    Text(count.formatted())
                        .dsText(glyph == nil ? .heading28 : .heading24)
                        .monospacedDigit()
                        .foregroundStyle(isOn ? Color.white : zero ? DS.textTertiary : DS.textPrimary)
                }
                Text(label)
                    .dsText(.label12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isOn ? Color.white : wants ? DS.attentionInk : DS.textSecondary)
            }
            .padding(.horizontal, glyph == nil ? DS.Space.s2 : 2)
            .padding(.vertical, DS.Space.s2)
            .frame(maxWidth: .infinity, alignment: glyph == nil ? .leading : .center)
            .background { shape.fill(isOn ? DS.tint : Color.clear) }
            .animation(DS.Motion.standard, value: isOn)
            .contentShape(shape)
            }
        }
        .buttonStyle(PressSpring())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// THE INLINE BOX (prd §1180): two across, one spacing, one inset, the
/// lead's height. Settings' kinds and Markets' categories both stand in it,
/// so moving between the two places nothing jumps.
///
/// THE ROWS FILL THE WELL (prd §1198, user: "lets do A"): one `s2` inset on
/// all four sides and the rows share what is left, where they had floated
/// with 39pt over and under them and a 37pt pick. The well is the same size;
/// only what stands in it moved.
struct DSCountGrid<Content: View>: View {
    /// How many counts stand in the box, two across, so the rows can share it.
    let items: Int
    /// Inside a box that is already a well (the Wallet's Security, prd
    /// §1221): the grid alone, never a well inside a well.
    var bare = false
    @ViewBuilder let content: Content

    var body: some View {
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s1, alignment: .leading), count: 2),
                             alignment: .leading, spacing: DS.Space.s1) {
            content
        }
        .environment(\.dsCountCellHeight, DSCountTile.cellHeight(items: items))
        if bare {
            grid.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            grid
                .padding(DS.Space.s2)
                .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadHeight,
                       maxHeight: DSRoomChassis.leadHeight, alignment: .top)
                .dsWell(cornerRadius: DS.Radius.widget)
        }
    }
}

extension EnvironmentValues {
    /// The inline count's row height, set by `DSCountGrid` (prd §1198).
    @Entry var dsCountCellHeight: CGFloat? = nil
}
