import SwiftUI

/// **MOVE IS A RECEIPT OF CHIPS (prd §1931).** Every verb's page is its name,
/// then one line per thing it asks: a grey word in a fixed column and the
/// answer as a chip, the open one lit. Under the lines stands what the open
/// line asks (its list, the keys, the facts at Ready), and the foot. No
/// sentence while choosing, no panel, no steps track: the lines are the steps
/// and the summary at once.
///
/// **ONE RHYTHM (user, 2026-11-21: "why not use the exact same spacing"):**
/// every line, bar, section name and list row is `lineHeight` tall with `gap`
/// between them.
enum MoveReceipt {
    static let lineHeight: CGFloat = 44
    static let gap: CGFloat = 12
    static let labelWidth: CGFloat = 78
    static let chipHeight: CGFloat = 40
    static let chipMark: CGFloat = 28
}

/// One line of the receipt: its word in the label column, then what answers it.
struct MoveReceiptLine<Content: View>: View {
    let label: String
    var labelInk: Color = DS.textSecondary
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(verbatim: label)
                .dsText(.body17)
                .foregroundStyle(labelInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: MoveReceipt.labelWidth, alignment: .leading)
                .accessibilityHidden(label.isEmpty)
            HStack(alignment: .center, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Never wider than the page: a line that outgrows it scales down.
            .minimumScaleFactor(0.8)
        }
        .frame(height: MoveReceipt.lineHeight)
        .accessibilityElement(children: .contain)
    }
}

/// How a chip reads: answered, still to answer, the one open, or a warning.
enum MoveChipTone: Equatable {
    case answered, empty, open, warn, aztec, aztecOpen
}

/// The chip's face: a mark, its words, a caret while a figure is typed.
struct MoveChipLabel: View {
    let text: String
    var mark: MoveRowMark?
    /// A face of its own in place of a mark (a contact's).
    var face: AnyView?
    var tone: MoveChipTone = .answered
    var caret = false
    /// A quick amount on the Amount line: tighter at its sides.
    var compact = false
    var glyph: String?

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            if let face {
                face.frame(width: MoveReceipt.chipMark, height: MoveReceipt.chipMark)
            } else if let mark {
                MoveRowMark(token: mark.token, network: mark.network, brand: mark.brand, size: MoveReceipt.chipMark)
            } else if let glyph {
                Image(systemName: glyph).dsGlyph(.caption, weight: .semibold).accessibilityHidden(true)
            }
            Text(verbatim: text)
                .dsText(compact ? .fact15 : .heading17)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .contentTransition(.numericText())
                .layoutPriority(1)
            if caret {
                // A caret at the chip's own size: Move's blinks at the
                // sentence's and pushed the figure out of its chip.
                Capsule().fill(DS.pickInk).frame(width: 2, height: 18)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(ink)
        .padding(.leading, (mark != nil || face != nil) ? 6 : (compact ? 10 : 16))
        .padding(.trailing, compact ? 10 : 16)
        .frame(height: MoveReceipt.chipHeight)
        .background(fill, in: Capsule())
        .contentShape(Capsule())
        // The figure being typed is never cut to make room: the quick chips
        // beside it give way.
        .fixedSize(horizontal: caret || compact, vertical: false)
    }

    private var ink: Color {
        switch tone {
        case .answered: DS.textPrimary
        case .empty: DS.textSecondary
        case .open: DS.pickInk
        case .warn: DS.attentionInk
        case .aztec, .aztecOpen: DS.aztecInk
        }
    }

    private var fill: Color {
        switch tone {
        case .open, .aztecOpen: DS.fillStrong
        default: DS.fillFaint
        }
    }
}

/// A chip that is tapped.
struct MoveChip: View {
    let text: String
    var mark: MoveRowMark?
    var face: AnyView?
    var tone: MoveChipTone = .answered
    var caret = false
    var compact = false
    var glyph: String?
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
            DSHaptic.selection()
        } label: {
            MoveChipLabel(text: text, mark: mark, face: face, tone: tone, caret: caret, compact: compact, glyph: glyph)
        }
        .buttonStyle(PressSpring())
        .disabled(disabled)
        .accessibilityAddTraits(tone == .open || tone == .aztecOpen ? [.isSelected] : [])
    }
}

/// **THE OPEN CHIP IS THE SEARCH (prd §1931, user: "when you tap choose you
/// could be inside a search bar w/ the list already populated").** The chip
/// stretches across its line, the magnifier and the caller's field in it.
struct MoveChipField<Field: View>: View {
    @ViewBuilder let field: () -> Field

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            field()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: MoveReceipt.chipHeight, maxHeight: MoveReceipt.chipHeight, alignment: .leading)
        .background(DS.fillStrong, in: Capsule())
    }
}

/// **$ | TOKEN (prd §1931, user: "something that allows the amount to change
/// between dollars or tokens").** Two segments on one track at the end of
/// the Token line; the lit one is the unit typed in.
struct MoveUnitSwitch: View {
    let symbol: String
    let dollars: Bool
    var disabled = false
    let pick: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("$", on: dollars) { pick(true) }
            segment(symbol, on: !dollars) { pick(false) }
        }
        .padding(3)
        .frame(height: 36)
        .background(DS.fillFaint, in: Capsule())
        .fixedSize()
        .disabled(disabled)
        .animation(DS.Motion.standard, value: dollars)
    }

    private func segment(_ word: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button {
            act()
            DSHaptic.selection()
        } label: {
            Text(verbatim: word)
                .dsText(.fact15)
                .lineLimit(1)
                .foregroundStyle(on ? DS.textPrimary : DS.textSecondary)
                .padding(.horizontal, 10)
                .frame(minWidth: 36, minHeight: 30)
                .background { if on { Capsule().fill(DS.fillStrong) } }
                .dsTapTarget()
                .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(word == "$" ? Text("Dollars") : Text(verbatim: word))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
