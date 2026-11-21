import SwiftUI

/// **THE DECK (prd §1897–§1901).** Move's page is three bands at fixed
/// places: the sentence on the page, the facts under it, and the deck on
/// Home's panel, where the move is changed. The deck leads with the steps as
/// words; under them stands what the step on is asking (its rows, the keys);
/// the foot is the way back and one word, held to act.
enum MoveDeck {
    /// A step word's row, and the group words' row under it.
    static let stepsHeight: CGFloat = 52
    /// The kinds' chips over the steps (`MoveDeckKinds`): one Chip's target.
    static let kindsHeight: CGFloat = DS.Hit.min
    /// Under the steps' track, before what the step asks (prd §1916's 16).
    static let stepsGap: CGFloat = DS.Space.s4
    /// The deck's height under its steps: room for the keys and a top row.
    /// **IT SCALES WITH THE PHONE (user, 2026-11-19: "the bottom tray could
    /// probably be taller … receive for example it should all be visible so
    /// no need to scroll"):** 37% of the screen, never under the 288pt a
    /// small phone keeps for its sentence and facts. One height for every
    /// verb and step, so the panel's edge never moves.
    /// **TALLER WITH THE RECEIPT IN IT (prd §1914, user, 2026-11-19: "should
    /// we make the deck be this high on all the move screens?"):** 45%, the
    /// sentence standing alone above it.
    static var bodyHeight: CGFloat { max(288, (UIScreen.main.bounds.height * 0.45).rounded()) }
    /// One key of the keypad: the keys share what the sums and the fade leave,
    /// so the taller deck's keys are taller too (user, 2026-11-19: "keyboard
    /// looks tiny here").
    /// **64 AT MOST, AT THE BOTTOM (prd §1916, user, 2026-11-19: "number pad
    /// too high"):** the keys stand over the foot, the room above them air.
    static var keyHeight: CGFloat { min(64, max(56, ((bodyHeight - presetHeight - DS.Space.s1 - fade) / 4).rounded(.down))) }
    /// How far a list fades into the foot (user, 2026-11-19: "the rows should
    /// fade into the bottom not have a hard clip").
    static let fade: CGFloat = 32
    /// The foot's row: the back chevron and the act's word.
    static var footHeight: CGFloat { stepsHeight + DS.Space.s2 }
    /// **THE LAST ROW CLEARS THE FOOT (user, of 1050's Send: "the private
    /// account token is clipped", "it can't clear the screen below it", "in
    /// for and from the bottom row doesn't clear the screen").** A deck list
    /// scrolls on by the foot and its fade, so at its end the last row
    /// stands above both, whole.
    static var listClearance: CGFloat { footHeight + fade }
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
    /// **20 SINCE THE THREE SIZES (prd §1916):** 30 for the sentence and the
    /// keys, 20 for the steps' act, 17 for everything else.
    static let footRung: DSTextStyle = .heading20
}

/// A step of the deck: its word, whether it is the one open, and its tap.
struct MoveDeckStep: Identifiable {
    let id: String
    let word: String
    var on = false
    /// Its question has an answer (prd §1904 item 1): white, where one still
    /// to answer stays grey.
    var answered = false
    /// What answers it, on the receipt's chip (prd §1931); nil asks "Choose".
    var value: String? = nil
    var mark: MoveRowMark? = nil
    /// Aztec's own ink (prd §1779).
    var aztec = false
    /// A glyph in the chip where there is no mark (Aztec's diamond).
    var glyph: String? = nil
    /// A line of its own under this one, with no word: Aztec's rule (§1924).
    var note: String? = nil
    let act: () -> Void
}

/// **THE STEPS AS THE RECEIPT'S LINES (prd §1931).** A private send's steps,
/// each its word and its answer as a chip, the open one lit.
struct MoveReceiptSteps: View {
    let steps: [MoveDeckStep]
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            ForEach(steps) { s in
                MoveReceiptLine(label: s.word) {
                    MoveChip(text: s.value ?? String(localized: "Choose"), mark: s.mark,
                             tone: tone(s), caret: s.on && s.id == "amount", glyph: s.glyph,
                             disabled: disabled, action: s.act)
                }
                if let note = s.note {
                    MoveReceiptLine(label: "") {
                        Text(verbatim: note).dsText(.body17)
                            .foregroundStyle(s.aztec ? DS.aztecInk : DS.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .animation(DS.Motion.standard, value: steps.map(\.on))
    }

    private func tone(_ s: MoveDeckStep) -> MoveChipTone {
        if s.aztec { return s.on ? .aztecOpen : .aztec }
        if s.on { return .open }
        return s.value == nil ? .empty : .answered
    }
}

/// **THE RECEIPT'S PAGE (prd §1931).** The verb's name, its lines, what the
/// open line asks down to the foot, and the foot. No panel.
struct MoveReceiptDeck<Lines: View, Content: View, Word: View>: View {
    let title: String
    var titleInk: Color = DS.textPrimary
    var inTray = false
    var backDisabled = false
    let back: () -> Void
    @ViewBuilder let lines: () -> Lines
    @ViewBuilder let content: () -> Content
    @ViewBuilder let word: () -> Word

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .dsText(.heading34)
                .foregroundStyle(titleInk)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            lines()
                .padding(.top, MoveReceipt.gap)
            ZStack(alignment: .bottom) {
                content()
                    .safeAreaPadding(.bottom, MoveDeck.footHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, MoveReceipt.gap)
                    .deckUnderFoot()
                MoveDeckFoot(backDisabled: backDisabled, back: back) { word() }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, MoveSentence.sideInset(inTray))
        .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
        .modifier(MoveFootClearance(inTray: inTray, intoBody: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            Group { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
                .padding(.horizontal, inTray ? -DS.Space.s4 : 0)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// **THE STEPS ARE SEGMENTS ON A TRACK (prd §1916, user, 2026-11-19, of
/// five mocked step titles: "i like C", then of C against a pill per step:
/// segments, since the verb's kinds are pills right above).** One dark track
/// the deck's width, a segment per step at equal widths, the open one on a
/// lighter fill that glides; an answered step white, one still to answer
/// grey. Every step is a wide target, and the row reads as one control,
/// apart from the kind chips over it.
struct MoveDeckSteps: View {
    let steps: [MoveDeckStep]
    var disabled = false
    @Namespace private var fill

    var body: some View {
        HStack(spacing: Self.inset) {
            ForEach(steps) { s in
                Button {
                    s.act()
                    DSHaptic.selection()
                } label: {
                    Text(verbatim: s.word)
                        .dsText(.heading17)
                        .foregroundStyle(ink(s))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if s.on && !disabled {
                                RoundedRectangle(cornerRadius: Self.segmentRadius, style: .continuous)
                                    .fill(DS.fillStrong)
                                    .matchedGeometryEffect(id: "on", in: fill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .disabled(disabled)
                .accessibilityAddTraits(s.on ? [.isSelected] : [])
            }
        }
        .padding(Self.inset)
        .frame(height: MoveDeck.stepsHeight)
        .background(DS.fillQuiet, in: RoundedRectangle(cornerRadius: Self.segmentRadius + Self.inset, style: .continuous))
        .animation(DS.Motion.glide, value: steps.map(\.on))
        .animation(DS.Motion.standard, value: steps.map(\.answered))
    }

    /// Between the track's edge and a segment, and between two segments.
    static let inset: CGFloat = 4
    static let segmentRadius: CGFloat = 10

    private func ink(_ s: MoveDeckStep) -> Color {
        if disabled { return DS.textSecondary }
        return s.on || s.answered ? DS.textPrimary : DS.textSecondary
    }
}

/// **AFTER THE HOLD THE TRACK IS WHERE IT IS (prd §1917).** The steps' own
/// track, its segments now the move's stages: one reached wears a tick and
/// the lighter fill, the one under way the pick's ink, the rest grey. Never
/// a control: nothing in it takes a touch.
struct MoveStageTrack: View {
    enum Phase: Equatable { case done, now, next }
    struct Segment: Identifiable {
        let id: Int
        let word: String
        let state: Phase
    }
    let segments: [Segment]

    var body: some View {
        HStack(spacing: MoveDeckSteps.inset) {
            ForEach(segments) { s in
                HStack(spacing: DS.Space.s1) {
                    if s.state == .done {
                        Image(systemName: "checkmark").dsGlyph(.caption, weight: .bold).accessibilityHidden(true)
                    }
                    Text(verbatim: s.word).dsText(.heading17).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(s.state == .next ? DS.textSecondary : DS.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    switch s.state {
                    case .done: RoundedRectangle(cornerRadius: MoveDeckSteps.segmentRadius, style: .continuous).fill(DS.fillStrong)
                    case .now: RoundedRectangle(cornerRadius: MoveDeckSteps.segmentRadius, style: .continuous).fill(DS.pickInk)
                    case .next: Color.clear
                    }
                }
            }
        }
        .padding(MoveDeckSteps.inset)
        .frame(height: MoveDeck.stepsHeight)
        .background(DS.fillQuiet, in: RoundedRectangle(cornerRadius: MoveDeckSteps.segmentRadius + MoveDeckSteps.inset, style: .continuous))
        .animation(DS.Motion.standard, value: segments.map(\.state))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: segments.first { $0.state == .now }?.word ?? segments.last?.word ?? ""))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// One kind of a verb: Swap or Sweep, Gift cards or Tokens, Earn or Take back.
struct MoveDeckKind: Identifiable {
    let id: String
    let word: String
    let glyph: String
    let picked: Bool
    let act: () -> Void
}

/// **A VERB'S KINDS ARE CHIPS OVER ITS STEPS (prd §1911, user, 2026-11-19:
/// "having Kind be one of the titles and choice options is too many extra
/// taps and just sounds weird", of three mocked ways: "c is clearest").**
/// The two kinds as `Chip`s, A–Z, the one on selected, always in view: one
/// tap switches, and no step is spent on it.
struct MoveDeckKinds: View {
    let kinds: [MoveDeckKind]
    var disabled = false

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(kinds.sorted { $0.word.localizedStandardCompare($1.word) == .orderedAscending }) { k in
                Button {
                    k.act()
                    DSHaptic.selection()
                } label: {
                    Chip(text: k.word, glyph: k.glyph, selected: k.picked)
                }
                .buttonStyle(PressSpring())
                .disabled(disabled)
                .accessibilityAddTraits(k.picked ? [.isSelected] : [])
            }
        }
        .frame(height: MoveDeck.kindsHeight, alignment: .leading)
        .animation(DS.Motion.standard, value: kinds.map(\.picked))
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
                    Text(verbatim: sub).dsText(.body17).foregroundStyle(subInk)
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
    /// A key's height: the deck's, or less where the hero figure and its
    /// token row stand over the keys (prd §1917).
    var keyHeight: CGFloat = MoveDeck.keyHeight
    /// **BIG DIGITS (prd §1931, user: "definitely 1. big digits").**
    var big = false

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
                        .dsText(.heading17)
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
                    Image(systemName: "delete.backward").dsGlyph(.feature, weight: big ? .medium : .regular)
                        .scaleEffect(big ? 1.2 : 1)
                } else if big {
                    Text(verbatim: label).dsText(.heading40).fontWeight(.semibold)
                } else {
                    // A key's figure is the sentence's (prd §1916).
                    Text(verbatim: label).dsText(MoveSentence.rung).fontWeight(.regular)
                }
            }
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, minHeight: keyHeight)
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
                    MoveHoldState.shared.held = false
                }
            } onPressingChanged: { pressing in
                guard enabled else { return }
                if pressing {
                    DSHaptic.selection()
                    withAnimation(.linear(duration: MoveDeck.hold)) { fill = 1 }
                    MoveHoldState.shared.held = true
                } else if !fired {
                    withAnimation(DS.Motion.standard) { fill = 0 }
                    MoveHoldState.shared.held = false
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
    /// A second word beside back: Add another (prd §1931).
    var lead: AnyView? = nil
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
            if let lead { lead }
            Spacer(minLength: DS.Space.s2)
            word()
        }
        .frame(minHeight: MoveDeck.footHeight)
    }
}

extension View {
    /// **LISTS GO UNDER THE FOOT (prd §1904 item 9, user: "i don't want the
    /// scrolling lists to feel like they hit a hard black wall at the
    /// bottom").** The body runs on under the foot, its scroll inset by the
    /// foot so the last row can rise above it, and fades out as it passes
    /// under the act's word: one surface to the panel's bottom, never a cut.
    func deckUnderFoot() -> some View {
        mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: MoveDeck.fade + MoveDeck.footHeight * 0.3)
                    Color.clear.frame(height: MoveDeck.footHeight * 0.7)
                }
            }
    }
}


/// **A CHOICE AT HOME'S APP-ICON SIZE (prd §1904 item 11, user: "i really
/// liked seeing the tokens as icons in horizontal rows … why not make them
/// the size of the app icons on home screen?").** Home's circle and column
/// (`DSHomeCircleMetrics`): the face, its name under it, a grey line under
/// that; five across, so a deck shows what a list of rows took a scroll for.
/// The pick wears a ring in the pick's ink; one left out is dimmed.
struct MoveDeckTile<Face: View>: View {
    let title: String
    var sub: String?
    var subInk: Color = DS.textSecondary
    var titleInk: Color = DS.textPrimary
    var picked = false
    var dim = false
    let act: () -> Void
    @ViewBuilder let face: () -> Face

    var body: some View {
        Button {
            act()
            DSHaptic.selection()
        } label: {
            VStack(spacing: DS.Space.s1) {
                face()
                    // Never clipped here: a token's network badge stands out
                    // past its circle (user, 2026-11-19: "badges don't show").
                    .frame(width: DSHomeCircleMetrics.face, height: DSHomeCircleMetrics.face)
                    .padding(3)
                    // Behind the face, so a network badge stands over the
                    // ring (user, 2026-11-19: "redline should go under badge").
                    .background(Circle().strokeBorder(DS.pickInk, lineWidth: 2).opacity(picked ? 1 : 0))
                    .accessibilityHidden(true)
                // **ONE CAPTION SIZE UNDER EVERY FACE (prd §1916):** 15, the
                // size at which "Coinbase" fits its column, so no name is
                // shrunk to fit while its neighbour is not.
                Text(verbatim: title)
                    .dsText(.fact15)
                    .foregroundStyle(picked ? DS.pickInk : titleInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    // Wraps inside its own column, never into a neighbour's.
                    .frame(width: DSHomeCircleMetrics.column)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub {
                    Text(verbatim: sub)
                        .dsText(.fact15)
                        .foregroundStyle(subInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }
            .frame(width: DSHomeCircleMetrics.column + DS.Space.s3)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .opacity(dim ? 0.4 : 1)
        }
        .buttonStyle(PressSpring())
        .disabled(dim)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }
}

/// One token a Move list offers: its symbol, the network it is on, what you
/// hold of it, and the pick.
struct MoveTokenChoice: Identifiable {
    let id: String
    let symbol: String
    /// The network's name, the title it stands under.
    let network: String
    /// The network's bundled mark (`MoveSentence.networkMark`), the badge on
    /// its face; nil draws none.
    var badge: String?
    /// The grey line under the symbol: dollars, else the amount.
    var sub: String?
    var subInk: Color = DS.textSecondary
    var picked = false
    var dim = false
    let act: () -> Void
}

/// A place the money is in (Your public account, Your private balance, Your
/// private account), its tokens under it.
struct MoveTokenPlace: Identifiable {
    let id: String
    /// Drawn only when the list holds more than one place or network.
    var title: String?
    var ink: Color = DS.textPrimary
    /// A line the place keeps under its title, whatever else is shown
    /// ("Aztec to Aztec only", prd §1898 item 4).
    var rule: String?
    let choices: [MoveTokenChoice]
}

/// **EVERY TOKEN LIST IN MOVE IS THIS ONE (prd §1910, user, 2026-11-19: "make
/// it consistent", "it shouldn't be hand rolled on any screen in move").** A
/// token and its network are one pick: each place under its title, each
/// token Home's own row (`TokenRowLabel`, prd §1917). No Move screen lays a
/// token list out by hand (`move-token-grid-audit.py`).
struct MoveTokenGrid: View {
    let places: [MoveTokenPlace]

    var body: some View {
        let shown = places.filter { !$0.choices.isEmpty }
        // **NO NETWORK TITLES (prd §1916):** a face's badge says its network,
        // so a place is one grid in the order its caller gives (by worth).
        // A place's title only where there are two places.
        let titled = shown.count > 1
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { n, place in
                if titled, let title = place.title {
                    // Home's side head (prd §1917): bold, a label.
                    Text(verbatim: title)
                        .dsText(.heading17)
                        .fontWeight(.bold)
                        .foregroundStyle(place.ink)
                        .padding(.top, n == 0 ? 0 : DS.Space.s4)
                        .frame(minHeight: DS.Hit.min, alignment: .bottomLeading)
                        .accessibilityAddTraits(.isHeader)
                }
                if let rule = place.rule {
                    Text(verbatim: rule).dsText(.body17).foregroundStyle(place.ink.opacity(0.75))
                }
                ForEach(place.choices) { c in
                    Button {
                        c.act()
                        DSHaptic.selection()
                    } label: {
                        Self.row(c)
                    }
                    .buttonStyle(RowPress())
                    .disabled(c.dim)
                    .opacity(c.dim ? 0.4 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: [String(localized: "\(c.symbol) on \(c.network)"), c.sub].compactMap { $0 }.joined(separator: ". ")))
                    .accessibilityAddTraits(c.picked ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    /// **HOME'S ROW, NOT A TILE (prd §1917, amending §1904 item 11 and
    /// §1910's tiles; user, 2026-11-20, of tiles against rows: "i liked that
    /// we had token horizontal rows but understand its probably better on
    /// vertical rows").** The network is a word under the symbol, never a
    /// badge three ETHs differ by; dollars trail in bold. A line that is not
    /// a figure (a seller, "Unlisted") joins the network's line.
    static func row(_ c: MoveTokenChoice) -> TokenRowLabel {
        let sub = c.sub ?? ""
        let figure = sub.first.map { $0 == "$" || $0.isNumber } ?? false
        let line = figure || sub.isEmpty ? c.network : "\(c.network) · \(sub)"
        return TokenRowLabel(symbol: c.symbol, line: line,
                             lineInk: !figure && !sub.isEmpty && c.subInk != DS.textSecondary ? c.subInk : DS.textSecondary,
                             figure: figure ? sub : nil, figureInk: c.subInk == DS.textSecondary ? DS.textPrimary : c.subInk,
                             picked: c.picked, grid: true,
                             flightKey: MoveFlight.key(symbol: c.symbol, network: c.network))
    }
}

/// Five across, Home's app row folded into rows (prd §1904 item 11).
struct MoveDeckGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: 5),
                  alignment: .leading, spacing: DS.Space.s4) {
            content()
        }
        .padding(.vertical, DS.Space.s3)
    }
}

/// The keys' caret in the sentence (prd §1904 item 3): the pick's ink, the
/// figure's height, blinking unless Reduce Motion is on.
struct MoveCaret: View {
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(DS.pickInk)
            .frame(width: 3, height: 34)
            .opacity(still || on ? 1 : 0.15)
            .accessibilityHidden(true)
            .task {
                guard !still else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    withAnimation(.easeInOut(duration: 0.18)) { on.toggle() }
                }
            }
    }
}


/// Whether the act's word is being held, for the sentence to fill with it
/// (prd §1904 item 6). One hold at a time: one Move page is up.
@MainActor @Observable final class MoveHoldState {
    static let shared = MoveHoldState()
    var held = false
}

/// **THE HOLD FILLS THE SENTENCE (prd §1904 item 6).** While the act is
/// held the sentence turns the pick's ink left to right, at the hold's own
/// pace; let go early and it drains. Reduce Motion fills it at once.
struct MoveHoldFill: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var fill: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                content
                    .colorMultiply(DS.pickInk)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in Rectangle().frame(width: geo.size.width * fill) }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onChange(of: MoveHoldState.shared.held) { _, held in
                if held {
                    withAnimation(still ? nil : .linear(duration: MoveDeck.hold)) { fill = 1 }
                } else {
                    withAnimation(DS.Motion.standard) { fill = 0 }
                }
            }
    }
}

extension View {
    func moveHoldFill() -> some View { modifier(MoveHoldFill()) }
}
