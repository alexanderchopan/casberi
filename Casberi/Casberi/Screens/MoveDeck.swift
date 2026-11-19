import SwiftUI

/// **THE DECK (prd §1897–§1901).** Move's page is three bands at fixed
/// places: the sentence on the page, the facts under it, and the deck on
/// Home's panel, where the move is changed. The deck leads with the steps as
/// words; under them stands what the step on is asking (its rows, the keys);
/// the foot is the way back and one word, held to act.
enum MoveDeck {
    /// A step word's row, and the group words' row under it.
    static let stepsHeight: CGFloat = 44
    /// Between two step words.
    static let stepGap: CGFloat = 22
    /// Between two group words.
    static let groupGap: CGFloat = 20
    /// The deck's height under its steps: room for the keys and a top row.
    static let bodyHeight: CGFloat = 288
    /// One key of the keypad.
    static let keyHeight: CGFloat = 56
    /// The keypad's top row of sums.
    static let presetHeight: CGFloat = 44
    /// A row of a step's list.
    static let rowHeight: CGFloat = 48
    /// A row's lead: a mark, a face or a glyph.
    static let lead: CGFloat = 30
    /// Between a row's lead and its words.
    static let leadGap: CGFloat = 14
    /// How long the act's word is held before it acts (prd §1897 item 7).
    static let hold: Double = 0.5
    /// The foot's one word: the act, Done, a stage (prd §1897 item 7). Not
    /// the sentence's size, which only the flow names (prd §1501).
    static let footRung: DSTextStyle = .heading28
}

/// A step of the deck: its word, whether it is the one open, and its tap.
struct MoveDeckStep: Identifiable {
    let id: String
    let word: String
    var on = false
    let act: () -> Void
}

/// **THE STEPS AS WORDS (prd §1897 item 2).** One row at the left edge, the
/// step on white and the rest grey: every part of the act stays in view, and
/// any word opens its step.
struct MoveDeckSteps: View {
    let steps: [MoveDeckStep]
    var disabled = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: MoveDeck.stepGap) {
                ForEach(steps) { s in
                    Button {
                        s.act()
                        DSHaptic.selection()
                    } label: {
                        Text(verbatim: s.word)
                            .dsText(.heading17)
                            .foregroundStyle(s.on && !disabled ? DS.textPrimary : DS.textSecondary)
                            .frame(minHeight: MoveDeck.stepsHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .disabled(disabled)
                    .accessibilityAddTraits(s.on ? [.isSelected] : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(height: MoveDeck.stepsHeight)
        .animation(DS.Motion.standard, value: steps.map(\.on))
    }
}

/// **GROUP WORDS (prd §1897 item 6, §1898 item 2).** A smaller row under the
/// steps that picks which group of a list shows: Merchant's categories,
/// To's Recent · Private · Addresses.
struct MoveDeckGroups: View {
    let words: [String]
    let picked: String?
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: MoveDeck.groupGap) {
                ForEach(words, id: \.self) { w in
                    Button {
                        pick(w)
                        DSHaptic.selection()
                    } label: {
                        Text(verbatim: w)
                            .dsText(.fact15)
                            .foregroundStyle(w == picked ? DS.textPrimary : DS.textSecondary)
                            .frame(minHeight: MoveDeck.stepsHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .accessibilityAddTraits(w == picked ? [.isSelected] : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: MoveDeck.stepsHeight)
    }
}

/// **ONE ROW FOR EVERY LIST (prd §1899 item 1).** A lead in its column, the
/// name over a grey line, the figure trailing. A row that cannot be picked is
/// dimmed and takes no tap.
struct MoveDeckRowLabel<Lead: View>: View {
    let name: String
    var sub: String?
    var subInk: Color = DS.textSecondary
    var trailing: String?
    var nameInk: Color = DS.textPrimary
    var picked = false
    /// A list's row keeps the deck's pitch; Receive's places and doors keep
    /// one even gap instead (prd §1901 item 4).
    var minHeight: CGFloat = MoveDeck.rowHeight
    @ViewBuilder let lead: () -> Lead

    var body: some View {
        HStack(alignment: .center, spacing: MoveDeck.leadGap) {
            lead()
                .frame(width: MoveDeck.lead, height: MoveDeck.lead)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name).dsText(.heading17).foregroundStyle(picked ? DS.pickInk : nameInk)
                    .lineLimit(1)
                if let sub {
                    Text(verbatim: sub).dsText(.fact15).foregroundStyle(subInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.s2)
            if let trailing {
                Text(verbatim: trailing).dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }
}

/// A sum on the keypad's top row.
struct MoveKeypadPreset: Identifiable {
    let id: String
    let title: String
    /// It can be covered: a sum over what you have is dimmed (prd §1898 item 6).
    var enabled = true
    var picked = false
    let act: () -> Void
}

/// **MOVE'S OWN KEYPAD (prd §1897 item 4).** Digits, the point and delete in
/// three centred columns, the sums as the first row; the figure is typed into
/// the sentence. Every key goes through one grammar, so a figure that cannot
/// be expressed is refused and the previous one stands.
struct MoveKeypad: View {
    @Binding var text: String
    var presets: [MoveKeypadPreset] = []
    /// The most places after the point: a dollar's two, a token's decimals.
    var places: Int = 2
    var disabled = false

    private static let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(presets) { p in
                Button {
                    p.act()
                    DSHaptic.selection()
                } label: {
                    Text(verbatim: p.title)
                        .dsText(.heading20)
                        .foregroundStyle(p.picked ? DS.pickInk : DS.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: MoveDeck.presetHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .disabled(!p.enabled || disabled)
                .opacity(p.enabled ? 1 : 0.4)
            }
            // The top row keeps the keys' three columns: two sums leave the
            // third place empty, never a digit in it.
            ForEach(0..<((3 - presets.count % 3) % 3), id: \.self) { _ in
                Color.clear.frame(height: MoveDeck.presetHeight)
            }
            ForEach(Self.digits, id: \.self) { key($0) }
            key(".")
            key("0")
            key("\u{232B}")
        }
        .disabled(disabled)
    }

    private func key(_ label: String) -> some View {
        let delete = label == "\u{232B}"
        return Button {
            DSHaptic.selection()
            tap(label)
        } label: {
            Group {
                if delete {
                    Image(systemName: "delete.backward").dsGlyph(.title, weight: .regular)
                } else {
                    Text(verbatim: label).dsText(MoveDeck.footRung).fontWeight(.regular)
                }
            }
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, minHeight: MoveDeck.keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(delete ? String(localized: "Delete") : label == "." ? String(localized: "Point") : label))
    }

    private func tap(_ label: String) {
        if label == "\u{232B}" {
            if !text.isEmpty { text.removeLast() }
            return
        }
        text = Self.sanitize(text + label, previous: text, places: places)
    }

    /// The whole edit grammar (as `DevnetAmountInput.sanitize`): one point at
    /// most, a bare point becomes "0.", a digit typed on a lone "0" replaces
    /// it, and no more places than the unit holds.
    static func sanitize(_ text: String, previous: String, places: Int) -> String {
        guard !text.isEmpty else { return "" }
        guard text.allSatisfy({ $0.isNumber || $0 == "." }), text.filter({ $0 == "." }).count <= 1 else { return previous }
        var out = text
        if out.hasPrefix(".") { out = "0" + out }
        while out.count > 1, out.hasPrefix("0"), let second = out.dropFirst().first, second.isNumber { out.removeFirst() }
        let parts = out.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts[0]
        let frac = parts.count > 1 ? parts[1] : ""
        guard whole.count <= 15, frac.count <= places else { return previous }
        return out
    }
}

/// **HOLD TO ACT (prd §1897 item 7).** The foot's one word at the right of the
/// back chevron. Held, it fills from the left in the act's ink; let go early
/// and it empties; full, it acts. VoiceOver acts at once.
struct MoveHoldWord: View {
    let word: String
    var ink: Color = DS.pickInk
    var enabled = true
    var hint: Text = Text("Hold to confirm")
    let action: () -> Void

    @State private var fill: CGFloat = 0
    @State private var fired = false

    var body: some View {
        Text(verbatim: word)
            .dsText(MoveDeck.footRung)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(enabled ? DS.textPrimary : DS.textTertiary)
            .overlay(alignment: .leading) {
                Text(verbatim: word)
                    .dsText(MoveDeck.footRung)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(ink)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * fill)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: MoveDeck.hold, maximumDistance: 40) {
                guard enabled else { return }
                fired = true
                DSHaptic.success()
                action()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    fill = 0
                    fired = false
                }
            } onPressingChanged: { pressing in
                guard enabled else { return }
                if pressing {
                    DSHaptic.selection()
                    withAnimation(.linear(duration: MoveDeck.hold)) { fill = 1 }
                } else if !fired {
                    withAnimation(DS.Motion.standard) { fill = 0 }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: word))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint)
            .accessibilityAction { if enabled { action() } }
    }
}

/// A word in the foot that is not held: Done, Copy address, a step still to
/// choose, or the stage the act is in.
struct MoveFootWord: View {
    let word: String
    var ink: Color = DS.pickInk
    var glyph: String?
    var action: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: DS.Space.s2) {
            if let glyph {
                Image(systemName: glyph).dsGlyph(.title, weight: .semibold).foregroundStyle(ink)
                    .accessibilityHidden(true)
            }
            Text(verbatim: word)
                .dsText(MoveDeck.footRung)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.interpolate)
                .foregroundStyle(glyph == nil ? ink : DS.textPrimary)
        }
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
        if let action {
            Button {
                action()
                DSHaptic.selection()
            } label: { label }
            .buttonStyle(PressSpring())
        } else {
            label.accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// **THE FOOT (prd §1897 item 7).** The back chevron at the left edge, one
/// word at the right: nothing else, and no slab.
struct MoveDeckFoot<Word: View>: View {
    var backDisabled = false
    let back: (() -> Void)?
    @ViewBuilder let word: () -> Word

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            if let back {
                Button {
                    back()
                    DSHaptic.selection()
                } label: {
                    Image(systemName: "chevron.left").dsGlyph(.title, weight: .bold)
                        .foregroundStyle(backDisabled ? DS.textTertiary : DS.textPrimary)
                        .frame(width: DS.Hit.min, height: DS.Hit.min, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .disabled(backDisabled)
                .accessibilityLabel(Text("Back to the list"))
            }
            Spacer(minLength: DS.Space.s2)
            word()
        }
        .frame(minHeight: MoveDeck.stepsHeight + DS.Space.s2)
    }
}
