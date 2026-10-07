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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
    }

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
                                .foregroundStyle(isOn ? Color.white : DS.textSecondary)
                        } else {
                            Text((count ?? 0).formatted())
                                .dsText(.heading24)
                                .monospacedDigit()
                                .foregroundStyle(isOn ? Color.white : zero ? DS.textTertiary : DS.textPrimary)
                        }
                    }
                    Text(label)
                        .dsText(.body17)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isOn ? Color.white : wants ? DS.attentionInk : DS.textPrimary)
                }
                // s2, not s3: the figure column leaves "Subscriptions" room to
                // stand whole beside a two-digit count.
                .padding(.horizontal, DS.Space.s2)
                .padding(.vertical, DS.Space.s1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { shape.fill(isOn ? DS.tint : Color.clear) }
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
/// lead box's height, rows centred. Settings' kinds and Markets' categories
/// both stand in it, so moving between the two places nothing jumps.
struct DSCountGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .leading), count: 2),
                  alignment: .leading, spacing: DS.Space.s1) {
            content
        }
        .padding(.horizontal, DS.Space.s2)
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
               maxHeight: DSRoomChassis.leadBox, alignment: .leading)
        .dsRoomHeadBlock()
    }
}
