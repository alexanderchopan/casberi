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
    /// A row of a step's list: the Wallet's 40pt pitch (§1482; user,
    /// 2026-11-26: "the denser rows are actually more easy to scan").
    static let rowHeight: CGFloat = DSFeed.headHeight + 2 * FeedScreen.rowAir
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
    /// An × at the line's end that takes it out: a payment Add another
    /// kept (prd §1952).
    var remove: (() -> Void)? = nil
    /// The open amount's unit, at the field's end (prd §1989).
    var accessory: AnyView? = nil
    /// The line under the open amount: what the figure means (prd §1989).
    var fieldNote: (text: String, ink: Color)? = nil
    /// Its answer is fixed (Tacit's one token): drawn as a chip that does
    /// not press, never one whose tap does nothing (prd §83).
    var fixed = false
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
                    HStack(spacing: DS.Space.s2) {
                        let typing = s.on && s.id == "amount"
                        MoveChip(text: s.value ?? (typing ? "0" : String(localized: "Choose")), mark: s.mark,
                                 tone: tone(s), caret: typing, glyph: s.glyph,
                                 disabled: disabled || s.fixed, placeholder: typing && !s.answered,
                                 accessory: typing ? s.accessory : nil, action: s.act)
                        if let remove = s.remove {
                            Spacer(minLength: 0)
                            Button {
                                remove()
                                DSHaptic.selection()
                            } label: {
                                Image(systemName: "xmark").dsGlyph(.caption, weight: .semibold)
                                    .foregroundStyle(DS.textSecondary)
                                    .frame(width: DS.Hit.min, height: DS.Hit.min, alignment: .trailing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressSpring())
                            .disabled(disabled)
                            .accessibilityLabel(Text("Remove"))
                        }
                    }
                }
                // **ONE NOTE UNDER A LINE (prd §1992):** a resting line's note
                // is the open field's caption, at its size and tucked under
                // it; the first sweep drew a full row at the page's edge.
                if s.on, s.id == "amount", let n = s.fieldNote {
                    MoveFieldNote(text: n.text, ink: n.ink)
                } else if let note = s.note {
                    MoveFieldNote(text: note, ink: s.aztec ? DS.aztecInk : DS.textSecondary)
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
    /// A second word beside back: Add another (prd §1952, as Send's §1931).
    var lead: AnyView? = nil
    /// A title that is a choice, Earn's Deposit · Withdraw (prd §1934), in
    /// the title's place; Earn drew the whole deck by hand for it (§1992).
    var header: AnyView? = nil
    @ViewBuilder let lines: () -> Lines
    @ViewBuilder let content: () -> Content
    @ViewBuilder let word: () -> Word

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                header
            } else {
                Text(verbatim: title)
                    .dsText(.heading34)
                    .foregroundStyle(titleInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            lines()
                .padding(.top, MoveReceipt.gap)
            ZStack(alignment: .bottom) {
                content()
                    .safeAreaPadding(.bottom, MoveDeck.footHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, MoveReceipt.gap)
                    .deckUnderFoot()
                MoveDeckFoot(backDisabled: backDisabled, back: back, lead: lead) { word() }
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

// MARK: - The deck's bodies, one set for every move (prd §1992)

/// **ONE BODY PER KIND, NEVER DRAWN BY HAND (prd §1992, user, 2026-11-26:
/// "how do we make sure ALL of our move confirmations, receipts, etc follow
/// same template. it seems like they drift").** What stands under a deck's
/// lines is keys, a scroll (a list or the receipt) or where the move stands,
/// each drawn here; `move-deck-audit.py` fails a deck page that draws its
/// own scroll, sentence or fact row.
struct MoveDeckKeys<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: MoveReceipt.gap) {
            Spacer(minLength: 0)
            content()
        }
        .transition(.opacity)
    }
}

/// A list or the receipt: one scroll, the same gap from the lines and the
/// same fade over the foot on every page.
struct MoveDeckScroll<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.s2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
        .transition(.opacity)
    }
}

/// **WHERE THE MOVE STANDS.** The sentence is drawn only when no lines
/// stand over it: with them, the lines say it, and a failure is one amber
/// line under them, as public Send's (2026-11-26, user: "is that send
/// sentence the same style our other sends are? … too close to the
/// selection rows").
struct MoveDeckStatus<Sentence: View, Content: View>: View {
    let linesStand: Bool
    @ViewBuilder let sentence: () -> Sentence
    @ViewBuilder let content: () -> Content

    var body: some View {
        MoveDeckScroll(spacing: DS.Space.s3) {
            if !linesStand {
                MoveFlow { sentence() }
                    .moveHoldFill()
                    .allowsHitTesting(false)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content()
        }
    }
}

/// The receipt's facts, at the page's edge (prd §1897 item 1).
struct MoveDeckFacts: View {
    struct Fact {
        let name: String
        var value: String?
        var ink: Color = DS.textPrimary
    }
    let facts: [Fact]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(facts.indices, id: \.self) { i in
                MoveFactRow(name: facts[i].name, value: facts[i].value, valueInk: facts[i].ink, indented: false)
            }
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

/// **MOVE'S OWN KEYPAD (prd §1897 item 4).** Digits, the point and delete in
/// three centred columns, the sums as the first row; the figure is typed into
/// the sentence. Every key goes through one grammar, so a figure that cannot
/// be expressed is refused and the previous one stands.
struct MoveKeypad: View {
    @Binding var text: String
    /// The most places after the point: a dollar's two, a token's decimals.
    var places: Int = 2
    var disabled = false
    /// A key's height: the deck's, or less where the hero figure and its
    /// token row stand over the keys (prd §1917).
    var keyHeight: CGFloat = MoveDeck.keyHeight
    /// **BIG DIGITS (prd §1931, user: "definitely 1. big digits").**
    var big = false

    private static let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    /// **A REFUSED KEY KNOCKS (prd §1935):** a digit the figure cannot take
    /// (past the unit's places, a second point) shakes the key once.
    @State private var refused: String?
    @State private var knocks = 0

    var body: some View {
        // **THE KEYS FIT THE SHEET (user, 2026-11-26: "the keyboard doesn't
        // fit. we need to fix this"):** a sheet with one more line (Privacy
        // Pools' Network) pushed the bottom row under the foot. The keys take
        // their height where there is room and give it up, step by step, to
        // a finger's floor where there is not, on every sheet at once.
        // Each size a child of its own: a `ForEach` here is ONE subview and
        // the fit silently stops working (`lead-body-audit.py`).
        ViewThatFits(in: .vertical) {
            grid(keyHeight)
            grid(Self.fit(keyHeight, 0.88))
            grid(Self.fit(keyHeight, 0.76))
            grid(Self.fit(keyHeight, 0.66))
            grid(DS.Hit.min)
        }
    }

    /// A smaller key, never under a finger's 44pt.
    static func fit(_ h: CGFloat, _ f: CGFloat) -> CGFloat { max(DS.Hit.min, (h * f).rounded()) }

    private func grid(_ keyHeight: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Self.digits, id: \.self) { key($0, height: keyHeight) }
            key(".", height: keyHeight)
            key("0", height: keyHeight)
            key("\u{232B}", height: keyHeight)
        }
        .disabled(disabled)
    }

    private func key(_ label: String, height keyHeight: CGFloat) -> some View {
        let delete = label == "\u{232B}"
        return Button {
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
            .shake(on: refused == label ? knocks : 0)
        }
        .buttonStyle(PressSpring())
        // **HOLD DELETE TO CLEAR (prd §1935):** the hold wins over the key's
        // tap; a short press still deletes one.
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            guard !text.isEmpty, !disabled else { return }
            withAnimation(DS.Motion.standard) { text = "" }
            DSHaptic.snap()
        }, isEnabled: delete)
        .accessibilityLabel(Text(delete ? String(localized: "Delete") : label == "." ? String(localized: "Point") : label))
        .accessibilityHint(delete ? Text("Hold to clear") : Text(verbatim: ""))
    }

    private func tap(_ label: String) {
        if label == "\u{232B}" {
            guard !text.isEmpty else { return }
            DSHaptic.selection()
            text.removeLast()
            return
        }
        let next = Self.sanitize(text + label, previous: text, places: places)
        if next == text {
            // Refused: the figure stands, the key knocks, a soft buzz.
            refused = label
            knocks += 1
            DSHaptic.failure()
            return
        }
        DSHaptic.selection()
        text = next
    }

    /// The whole edit grammar (as the devnet send sheet's was): one point at
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
                // One word never breaks inside itself ("DoorDas / h", walked
                // 2026-11-21): it takes one line and shrinks a step to fit.
                let oneWord = !title.contains(" ")
                Text(verbatim: title)
                    .dsText(.fact15)
                    .foregroundStyle(picked ? DS.pickInk : titleInk)
                    .lineLimit(oneWord ? 1 : 2)
                    .minimumScaleFactor(oneWord ? 0.75 : 1)
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
    /// What it earns today ("4.8%"), after the network on its line (prd
    /// §1958): Earn's rows differ by rate, so the rate is on the choice.
    var rate: String?
    /// **WHERE IT GOES, NOT WHICH NETWORK (prd §1972):** Earn names the
    /// place ("Aave", "Olla") after the rate, and the network moves to the
    /// badge on the mark, so token, rate, place and balance fit one line.
    var place: String?
    /// The grey line in place of the network, when a side head already
    /// names it: the amount, as Holdings' rows (prd §1988).
    var line: String?
    var picked = false
    var dim = false
    /// **A DOOR, NOT A DEAD ROW (prd §2000):** where there is nothing to
    /// move, the trailing word says the way in ("Swap for it"), grey, and
    /// the row is that door.
    var door: String? = nil
    let act: () -> Void
}

/// A place the money is in (Your public account, Your private balance, Your
/// private account), its tokens under it.
struct MoveTokenPlace: Identifiable {
    let id: String
    /// Drawn only when the list holds more than one place or network.
    var title: String?
    /// **PUBLIC OR PRIVATE (prd §1985), as Home and Holdings group money:**
    /// the group's word stands once above its places, each place's name
    /// under it in grey, as Holdings' Tacit or Privacy Pools.
    var group: String?
    var ink: Color = DS.textPrimary
    /// A line the place keeps under its title, whatever else is shown
    /// ("Aztec to Aztec only", prd §1898 item 4).
    var rule: String?
    let choices: [MoveTokenChoice]
    /// "3 more pools": the rest of a long place, shown on a tap (prd §2000).
    var more: (words: String, act: () -> Void)? = nil
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
        // **ONE FLIGHT KEY, ONE ROW (2026-11-25, user: "some of the tokens
        // are also not showing").** ETH on Ethereum stands under your public
        // account AND under Privacy Pools; two marks under one matched key
        // hid one of them. The first row with a key keeps the flight.
        var seen = Set<String>()
        let flies: Set<String> = Set(shown.flatMap(\.choices).compactMap { c in
            seen.insert(MoveFlight.key(symbol: c.symbol, network: c.network)).inserted ? c.id : nil
        })
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { n, place in
                let grouped = shown.contains { $0.group != nil }
                // Home's side head (prd §1917): bold, a label; the group's
                // word when places are grouped (prd §1985), else the place's.
                let head: (String, Color)? = !titled ? nil
                    : grouped ? place.group.flatMap { g in n == 0 || shown[n - 1].group != g ? (g, DS.textPrimary) : nil }
                    : place.title.map { ($0, place.ink) }
                if let head {
                    Text(verbatim: head.0)
                        .dsText(.heading17)
                        .fontWeight(.bold)
                        .foregroundStyle(head.1)
                        .padding(.top, n == 0 ? 0 : DS.Space.s4)
                        .frame(minHeight: DS.Hit.min, alignment: .bottomLeading)
                        .accessibilityAddTraits(.isHeader)
                }
                if titled, grouped, let title = place.title {
                    // A place under its group: Holdings' grey side head.
                    Text(verbatim: title)
                        .dsText(.body17)
                        .foregroundStyle(place.ink == DS.textPrimary ? DS.textSecondary : place.ink)
                        // Room over and under it, so it never touches the
                        // rows (2026-11-27, user, of Earn's "Tacit farms" line:
                        // "the text is touching need some space").
                        .padding(.top, DS.Space.s3)
                        .padding(.bottom, DS.Space.s2)
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
                        Self.row(c, flies: flies.contains(c.id))
                    }
                    .buttonStyle(RowPress())
                    .disabled(c.dim)
                    .opacity(c.dim ? 0.4 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: [String(localized: "\(c.symbol) on \(c.network)"), c.sub, c.rate.map { String(localized: "Earns \($0) today") }, c.place].compactMap { $0 }.joined(separator: ". ")))
                    .accessibilityAddTraits(c.picked ? [.isButton, .isSelected] : .isButton)
                }
                if let more = place.more {
                    Button {
                        withAnimation(DS.Motion.standard) { more.act() }
                        DSHaptic.selection()
                    } label: {
                        Text(verbatim: more.words).dsText(.body17).foregroundStyle(DS.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, MoveReceipt.labelWidth)
                            .walletRowPitch()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
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
    static func row(_ c: MoveTokenChoice, flies: Bool = true) -> TokenRowLabel {
        let sub = c.sub ?? ""
        let figure = sub.first.map { $0 == "$" || $0.isNumber } ?? false
        let line = c.line ?? (c.place != nil ? [c.rate, c.place].compactMap { $0 }.joined(separator: " · ")
            : [figure || sub.isEmpty ? c.network : "\(c.network) · \(sub)", c.rate].compactMap { $0 }.joined(separator: " · "))
        return TokenRowLabel(symbol: c.symbol, line: line,
                             lineInk: !figure && !sub.isEmpty && c.subInk != DS.textSecondary ? c.subInk : DS.textSecondary,
                             figure: figure ? sub : c.door,
                             figureInk: !figure && c.door != nil ? DS.textSecondary : c.subInk == DS.textSecondary ? DS.textPrimary : c.subInk,
                             picked: c.picked, grid: true, badge: c.place != nil ? c.badge : nil,
                             flightKey: flies ? MoveFlight.key(symbol: c.symbol, network: c.network) : nil)
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
    var ink: Color = DS.pickInk
    /// The sentence's, or the field's smaller one (prd §1989).
    var width: CGFloat = 3
    var height: CGFloat = 34
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(ink)
            .frame(width: width, height: height)
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
