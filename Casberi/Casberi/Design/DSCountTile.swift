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
    /// A figure that is not a count ("$2", "Off", prd §1462): drawn in the
    /// count's place, in its ink; `count` then only says zero or not.
    var figure: String? = nil
    /// Figure over word, centered (Security's nine, prd §1462): the Health
    /// shape, three across.
    var centered: Bool = false
    /// A category's glyph over the figure (Apps); nil draws figure and word.
    var glyph: String? = nil
    let isOn: Bool
    var wants: Bool = false
    /// **THE WASH SAYS THE STATE (prd §1463):** nothing for a zero, orange
    /// for what waits on you, red for a threat, green for what is on — the
    /// three inks' meanings (§1004) as Markets' tiles wear a move (§1391): a
    /// wash and an edge, never a plate (§782). Inline too: Security's six,
    /// two across with no account on the phone, drew its threats orange.
    enum Tone { case none, wants, threat, on }
    var tone: Tone = .none
    /// The figure and its word on one line (Settings' eight kinds, two
    /// across, prd §1166), so every word stands whole, as Reminders' and
    /// Passwords' grids draw theirs.
    var inline: Bool = false
    /// The widest figure in the box, inline only: every figure stands in a
    /// column that wide, right-aligned, so every word starts at one edge
    /// (user: "need to make indentation even", of "13 Apps" over "0 Cards").
    var widest: Int? = nil
    /// ADD FROM WHERE YOU LAND (prd §1292): a plus at the count's trailing
    /// edge runs that kind's own add, so the page behind the count is not a
    /// step on the way to it. Inline only; nil draws none. `addLabel` is the
    /// kind's verb ("Track a subscription"), said to VoiceOver and the tests.
    var add: (() -> Void)? = nil
    var addLabel: String? = nil
    /// A plus that lists its kind's apps (prd §1300), as a Feed section's
    /// does: a menu of rows, each its app over what it follows.
    var addMenu: [SectionAdd] = []
    /// A count with no add in a box where others have one keeps the plus's
    /// column empty (prd §1390), so every count ends at one edge.
    var reservesPlus: Bool = false
    let action: () -> Void

    /// How far the plus's 44pt target reaches over the tile (prd §1292):
    /// up to the glyph's own side margin, so the plus takes a 31pt column,
    /// its target stays `DS.Hit.min` wide, and "Subscriptions" stands whole
    /// beside it on the phone (measured shrunk at 8, 2026-10-15; user: "we've
    /// debated if we should say 'Subs' … i'm not sure").
    static let plusOverlap: CGFloat = 13

    /// The lead column's floor, inline: a two-digit figure's width.
    static let leadFigure = 99

    // The pick wears `DS.pickInk` (prd §1385): it was a blue wash of its own
    // (§1198, "the lighter tint") while the tab pick beside it was pink.

    /// The inline pick's corner, concentric with `DSCountGrid`'s well: the
    /// well's corner less the box's inset (§1198).
    static var cellRadius: CGFloat { DS.Radius.widget - DS.Space.s2 }

    /// One inline row's share of the well: 52pt for four rows on the phone.
    static func cellHeight(items: Int, columns: Int = 2) -> CGFloat {
        let rows = CGFloat(max(1, (items + columns - 1) / columns))
        return (DSRoomChassis.leadHeight - 2 * DS.Space.s2 - (rows - 1) * DS.Space.s1) / rows
    }

    /// Inline, the pick is concentric with the well (`cellRadius`); stacked
    /// keeps the sheet corner.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: inline ? Self.cellRadius : DS.Radius.sheet,
                         style: .continuous)
    }

    @Environment(\.dsCountCellHeight) private var cellHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// EVERY COUNT ROLLS TO ITS VALUE (prd §1379, closing §1199's "Settings'
    /// counts do not roll yet"): the crown's roll, keyed on the count itself so
    /// a store landing late rolls whether or not its caller animated. Under
    /// Reduce Motion the digits change in place.
    private var countRoll: ContentTransition {
        reduceMotion ? .identity : .numericText(value: Double(count ?? 0))
    }
    private var countAnimation: Animation? {
        reduceMotion ? nil : ChartEntrance.roll
    }

    var body: some View {
        if inline, add != nil || !addMenu.isEmpty {
            // Two buttons side by side, never one inside the other: the
            // word opens the list, the plus adds to it.
            // The plus is a full 44pt target that overlaps the tile's last
            // `plusOverlap` points, where the glyph's own side margin is, so
            // the word keeps its room (prd §1292).
            HStack(spacing: -Self.plusOverlap) {
                tile
                if addMenu.isEmpty, let add {
                    Button(action: add) { plus }
                        .buttonStyle(PressSpring())
                        .accessibilityLabel(Text(addLabel ?? label))
                } else {
                    Menu {
                        SectionAddMenu(adds: addMenu)
                    } label: { plus }
                    .accessibilityLabel(Text(addLabel ?? label))
                }
            }
        } else if inline, reservesPlus {
            HStack(spacing: -Self.plusOverlap) {
                tile
                Color.clear.frame(width: DS.Hit.min, height: 1)
            }
        } else {
            tile
        }
    }

    private var plus: some View {
        Image(systemName: "plus")
            .dsGlyph(.body, weight: .regular)
            // Pink, as every verb row's plus is (prd §1265).
            .foregroundStyle(DS.brandInk)
            // The glyph stands at its target's trailing side, so the word
            // the target overlaps never touches it ("Subscriptions+", the
            // 2026-10-17 nightly); the 44pt target is unchanged.
            .padding(.trailing, DS.Space.s2)
            .frame(width: DS.Hit.min, height: max(cellHeight ?? DS.Hit.min, DS.Hit.min),
                   alignment: .trailing)
            .contentShape(Rectangle())
    }

    /// The state's hue; nil draws no wash.
    private var hue: Color? {
        guard centered || inline, !isOn else { return nil }
        switch tone {
        case .none: return nil
        case .wants: return DS.attention
        case .threat: return DS.destructive
        case .on: return DS.confirm
        }
    }

    private func figureInk(zero: Bool) -> Color {
        if isOn { return DS.pickInk }
        if centered, tone == .on { return DS.confirmInk }
        return zero ? DS.textTertiary : DS.textPrimary
    }

    private var wordInk: Color {
        if isOn { return DS.pickInk }
        if centered || inline {
            switch tone {
            case .wants: return DS.attentionInk
            case .threat: return DS.destructiveInk
            case .on, .none: return wants ? DS.attentionInk : DS.textSecondary
            }
        }
        return wants ? DS.attentionInk : DS.textSecondary
    }

    @ViewBuilder private var tile: some View {
        let zero = count == 0 && !isOn
        Button {
            DSHaptic.selection()
            action()
        } label: {
            if inline {
                // The name's room comes out of the gaps, not its type: all
                // eight words stand at 17pt (prd §1588, "Subscriptions"
                // shrank beside its count and plus on the phone).
                HStack(alignment: .firstTextBaseline, spacing: glyph == nil ? DS.Space.s1 : DS.Space.s2) {
                    if let glyph {
                        // Markets' tiles: the glyph leads, in the column a
                        // two-digit figure took (prd §1180), so its words
                        // start where Settings' did.
                        Text(Self.leadFigure.formatted())
                            .dsText(.heading24).monospacedDigit().hidden()
                            .overlay {
                                Image(systemName: glyph)
                                    .dsGlyph(.body, weight: .regular)
                                    // Pink, as every glyph is (prd §1252, §1266).
                                    .foregroundStyle(isOn ? DS.pickInk : DS.brandInk)
                            }
                        Text(label)
                            .dsText(.body17)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isOn ? DS.pickInk : wants ? DS.attentionInk : DS.textPrimary)
                    } else {
                        // **THE NAME LEADS, THE COUNT TRAILS (prd §1390, user:
                        // "B looked cleaner").** The row the first-run box
                        // already drew (a name, a grey value, the plus), with
                        // the count where the value stood: the name is what
                        // you scan, the count the fact beside it, and the
                        // counts and pluses end at one edge. The figure that
                        // led in bold read as a report card.
                        Text(label)
                            .dsText(.body17)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(tone == .none ? (isOn ? DS.pickInk : wants ? DS.attentionInk : DS.textPrimary) : wordInk)
                            .layoutPriority(1)
                        Spacer(minLength: DS.Space.s1)
                        Text((count ?? 0).formatted())
                            .dsText(.body17)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            // Never squeezed by the name beside it.
                            .lineLimit(1)
                            .fixedSize()
                            .contentTransition(countRoll)
                            .animation(countAnimation, value: count)
                            .foregroundStyle(isOn ? DS.pickInk : zero ? DS.textTertiary : DS.textSecondary)
                    }
                }
                // s2, not s3: the figure column leaves "Subscriptions" room to
                // stand whole beside a two-digit count. The row is the box's
                // share of the well (§1198), so a pick is ≥44pt and the grid
                // fills the well instead of floating in it.
                // With a plus beside it the plus's own width is the gap, so
                // "Subscriptions" keeps its room (prd §1292).
                // A reserved slot is the plus's own width too (user, 2026-10-17:
                // "why is 13 not aligned w the other numbers"): the pad stays
                // only where nothing stands beside the count.
                .padding(.leading, DS.Space.s1)
                .padding(.trailing, add == nil && addMenu.isEmpty && !reservesPlus ? DS.Space.s2 : 0)
                .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .leading)
                // The state's wash and edge (prd §1463), Security's only: no
                // other inline box passes a tone.
                .background(shape.fill(hue?.opacity(0.14) ?? Color.clear))
                .overlay { if let hue { shape.strokeBorder(hue.opacity(0.6), lineWidth: 1.5) } }
                // No backing (prd §1268, user: "no backing"): the pick says
                // itself in the tint of its figure and word.
                .animation(DS.Motion.standard, value: isOn)
                .contentShape(shape)
            } else {
            VStack(alignment: glyph == nil && !centered ? .leading : .center, spacing: 2) {
                if let glyph {
                    Image(systemName: glyph)
                        .dsGlyph(.body, weight: .regular)
                        .frame(height: 20)
                        .foregroundStyle(isOn ? DS.pickInk : zero ? DS.textTertiary : DS.brandInk)
                }
                if let figure {
                    Text(verbatim: figure)
                        .dsText(.heading28)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(figureInk(zero: zero))
                } else if let count {
                    Text(count.formatted())
                        .dsText(glyph == nil ? .heading28 : .heading24)
                        .monospacedDigit()
                        .contentTransition(countRoll)
                        .animation(countAnimation, value: count)
                        .foregroundStyle(figureInk(zero: zero))
                }
                Text(label)
                    .dsText(.label12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(wordInk)
            }
            .padding(.horizontal, glyph == nil && !centered ? DS.Space.s2 : 2)
            .padding(.vertical, DS.Space.s2)
            .frame(maxWidth: .infinity, minHeight: centered ? cellHeight : nil,
                   alignment: glyph == nil && !centered ? .leading : .center)
            // The wash and its edge (prd §1463), Markets' 12pt corner (§1391).
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hue?.opacity(0.14) ?? Color.clear))
            .overlay {
                if let hue {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(hue.opacity(0.6), lineWidth: 1.5)
                }
            }
            // No backing (prd §1268): the pick's ink says it.
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
    /// Across: two (Settings, Markets), three for Security's nine (prd §1462).
    var columns: Int = 2
    /// Inside a box that is already a well (the Wallet's Security, prd
    /// §1221): the grid alone, never a well inside a well.
    var bare = false
    @ViewBuilder let content: Content

    var body: some View {
        // The gutter is s3, not s1 (prd §1388): the left column's + stood
        // against the right column's figure ("Mail lists +24").
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3, alignment: .leading), count: columns),
                             alignment: .leading, spacing: DS.Space.s1) {
            content
        }
        .environment(\.dsCountCellHeight, DSCountTile.cellHeight(items: items, columns: columns))
        if bare {
            grid.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            grid
                .padding(DS.Space.s2)
                .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadHeight,
                       maxHeight: DSRoomChassis.leadHeight, alignment: .top)
                // The box, without its well (prd §1381).
        }
    }
}

extension EnvironmentValues {
    /// The inline count's row height, set by `DSCountGrid` (prd §1198).
    @Entry var dsCountCellHeight: CGFloat? = nil
}
