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
    let count: Int
    let label: String
    /// A category's glyph over the figure (Apps); nil draws figure and word.
    var glyph: String? = nil
    let isOn: Bool
    var wants: Bool = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
    }

    var body: some View {
        let zero = count == 0 && !isOn
        Button {
            DSHaptic.selection()
            action()
        } label: {
            VStack(alignment: glyph == nil ? .leading : .center, spacing: 2) {
                if let glyph {
                    Image(systemName: glyph)
                        .dsGlyph(.body, weight: .regular)
                        .frame(height: 20)
                        .foregroundStyle(isOn ? Color.white : zero ? DS.textTertiary : DS.textSecondary)
                }
                Text(count.formatted())
                    .dsText(glyph == nil ? .heading28 : .heading24)
                    .monospacedDigit()
                    .foregroundStyle(isOn ? Color.white : zero ? DS.textTertiary : DS.textPrimary)
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
        .buttonStyle(PressSpring())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
