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
    /// A chip's face or mark: the ramp's row tier (prd §1941), never a
    /// number of its own.
    static let chipMark: CGFloat = DS.Face.row
}

// MARK: - The pick flies (prd §1933)

private struct MoveFlightKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
/// Where a line's pick lights: its place in the receipt, and how many lines
/// the hold reads (prd §1933).
private struct MoveHoldSlotKey: EnvironmentKey { static let defaultValue: (index: Int, count: Int)? = nil }

extension EnvironmentValues {
    /// **THE PICK FLIES INTO ITS CHIP (prd §1933):** Move's namespace, so a
    /// token row's mark and the Token chip are one thing moving.
    var moveFlight: Namespace.ID? {
        get { self[MoveFlightKey.self] }
        set { self[MoveFlightKey.self] = newValue }
    }
    var moveHoldSlot: (index: Int, count: Int)? {
        get { self[MoveHoldSlotKey.self] }
        set { self[MoveHoldSlotKey.self] = newValue }
    }
}

extension View {
    /// Matched by position only: the chip travels from the row's mark to its
    /// line, never stretched through the mark's size.
    @ViewBuilder func moveFlight(_ key: String?, in ns: Namespace.ID?) -> some View {
        if let key, let ns {
            matchedGeometryEffect(id: key, in: ns, properties: .position)
        } else {
            self
        }
    }
}

enum MoveFlight {
    /// One token on one network: the key its row and its chip share.
    static func key(symbol: String, network: String) -> String { "flight|\(symbol)|\(network)" }
}

/// **THE TITLE IS THE TYPE (prd §1934, user: "agree on 2").** A verb with
/// two kinds names both at the title's size, the one you are in white and
/// the other grey; a tap on the grey one switches. No Type line under it.
struct MoveKindTitle: View {
    struct Kind: Identifiable {
        let id: String
        let word: String
        let on: Bool
        let pick: () -> Void
    }
    let kinds: [Kind]
    var disabled = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            ForEach(kinds) { k in
                Button {
                    guard !k.on else { return }
                    k.pick()
                    DSHaptic.selection()
                } label: {
                    Text(verbatim: k.word)
                        .dsText(.heading34)
                        .foregroundStyle(k.on ? DS.textPrimary : DS.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .accessibilityAddTraits(k.on ? [.isSelected, .isHeader] : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(disabled)
        .animation(DS.Motion.standard, value: kinds.map(\.on))
    }
}

/// One line of the receipt: its word in the label column, then what answers it.
struct MoveReceiptLine<Content: View>: View {
    let label: String
    var labelInk: Color = DS.textSecondary
    @ViewBuilder let content: () -> Content

    @Environment(\.moveHoldSlot) private var slot
    @Environment(\.accessibilityReduceMotion) private var still
    /// **THE HOLD READS THE RECEIPT (prd §1933):** while the act is held
    /// each line's word turns white in turn, top to bottom, at the hold's
    /// pace; let go and they go back.
    @State private var lit = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(verbatim: label)
                .dsText(.body17)
                .foregroundStyle(lit ? DS.textPrimary : labelInk)
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
        .task(id: slot == nil ? false : MoveHoldState.shared.held) {
            guard let slot else { return }
            guard MoveHoldState.shared.held else {
                withAnimation(DS.Motion.standard) { lit = false }
                return
            }
            let at = MoveDeck.hold * Double(min(slot.index, slot.count - 1) + 1) / Double(slot.count + 1)
            try? await Task.sleep(for: .seconds(still ? 0 : at))
            guard !Task.isCancelled, MoveHoldState.shared.held else { return }
            withAnimation(.easeOut(duration: 0.15)) { lit = true }
        }
    }
}

/// **THE STATUS SAYS WHERE IT IS, IN PLACE (prd §1933):** one word that
/// turns into the next (Signing, Sending, On its way), never a row of chips.
struct MoveStatusLine: View {
    let word: String
    var ink: Color = DS.textPrimary

    var body: some View {
        MoveReceiptLine(label: String(localized: "Status")) {
            Text(verbatim: word)
                .dsText(.body17)
                .foregroundStyle(ink)
                .contentTransition(.interpolate)
                .padding(.leading, 16)
                .animation(DS.Motion.standard, value: word)
        }
        .accessibilityElement(children: .combine)
    }
}

/// How a chip reads: answered, still to answer, the one open, or a warning.
enum MoveChipTone: Equatable {
    case answered, empty, open, warn, aztec, aztecOpen, done
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
    /// A glyph after the words: Details' chevron.
    var trail: String?

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
                Capsule().fill(tone == .warn ? DS.attentionInk : DS.pickInk).frame(width: 2, height: 18)
                    .accessibilityHidden(true)
            }
            if let trail {
                Image(systemName: trail).dsGlyph(.caption, weight: .semibold).accessibilityHidden(true)
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
        case .answered, .done: DS.textPrimary
        case .empty: DS.textSecondary
        case .open: DS.pickInk
        case .warn: DS.attentionInk
        case .aztec, .aztecOpen: DS.aztecInk
        }
    }

    private var fill: Color {
        switch tone {
        case .open, .aztecOpen: DS.fillStrong
        // **DONE, THE CHIPS GO FLAT (prd §1932):** the answers stay where
        // they were, their fills drain, and the page reads as a receipt.
        case .done: .clear
        default: DS.fillFaint
        }
    }
}

/// A fact on the receipt: its word in the label column, its value where a
/// chip's words start (prd §1932).
struct MoveReceiptFact: View {
    let label: String
    let value: String
    var ink: Color = DS.textPrimary
    var marks: AnyView? = nil

    var body: some View {
        MoveReceiptLine(label: label) {
            HStack(spacing: DS.Space.s2) {
                if let marks { marks }
                Text(verbatim: value)
                    .dsText(.body17)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
            }
            .padding(.leading, 16)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A sentence on the receipt with no word of its own (a warning, a credit):
/// where the chips' words start, wrapping, at least a line tall (prd §1932).
struct MoveReceiptNote: View {
    let text: String
    var ink: Color = DS.textSecondary
    var marks: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            Color.clear.frame(width: MoveReceipt.labelWidth + 16 - DS.Space.s2, height: 1)
            if let marks { marks }
            Text(verbatim: text)
                .dsText(.body17)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: MoveReceipt.lineHeight, alignment: .leading)
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
    var trail: String?
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
            DSHaptic.selection()
        } label: {
            MoveChipLabel(text: text, mark: mark, face: face, tone: tone, caret: caret, compact: compact, glyph: glyph, trail: trail)
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

/// **THE QUICK AMOUNTS ARE THE KEYPAD'S TOP ROW (prd §1932, user picked
/// 2b):** three equal chips over the keys, the Amount line keeping the
/// figure alone, so a long figure never pushes the page.
struct MoveQuickKeys: View {
    struct Key: Identifiable {
        let id: String
        let word: String
        var on = false
        let act: () -> Void
    }
    let keys: [Key]
    var disabled = false
    /// The lit key's ink: the pick's, or Aztec's own (prd §1779).
    var onInk: Color = DS.pickInk

    var body: some View {
        HStack(spacing: MoveReceipt.gap) {
            ForEach(keys) { k in
                Button {
                    k.act()
                    DSHaptic.selection()
                } label: {
                    Text(verbatim: k.word)
                        .dsText(.heading17)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(k.on ? onInk : DS.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: MoveReceipt.lineHeight)
                        .background(k.on ? DS.fillStrong : DS.fillFaint, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressSpring())
                .accessibilityAddTraits(k.on ? [.isSelected] : [])
            }
        }
        .disabled(disabled)
        .animation(DS.Motion.standard, value: keys.map(\.on))
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
