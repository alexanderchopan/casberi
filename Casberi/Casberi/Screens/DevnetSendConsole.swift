import SwiftUI

/// **THE DEVNET SEND SURFACE — A PANEL AND A SHEET (prd §553, 2026-09-01).**
///
/// §544 built a payment console and §552/§552a spent an entire session trying
/// to fit it under the room's chrome. That was the wrong problem. The chrome is
/// ~545pt on every iPhone and none of its four terms scales with screen height,
/// so the room leaves 411pt on the largest phone, 276 on a 13 mini and ~161 on
/// an SE — and §552a's own stated ceiling was that its 232pt console did not
/// fit the last of those and never would.
///
/// **The answer is that Home should not hold a form at all.** What Home holds
/// is the two things you can do; the form lives on a sheet, where it has the
/// whole screen and none of the chrome. Three things follow and each is a
/// ruling rather than a preference:
///
/// 1. **THE KEYPAD IS OURS AGAIN.** §552a replaced it with `.decimalPad`
///    because 176pt was 45% of a 232pt budget in a 276pt room — arithmetic,
///    and correct at the time. On a sheet that arithmetic is simply gone, and
///    what the system pad cost was the room's whole visual language: iOS
///    keyboard chrome under a screen built out of ink blocks and 64pt type.
///    §544's second ruling stands and is ours to keep: bare digits on the
///    surface, no key backgrounds, keys at `DS.Hit.min`.
/// 2. **BOTH VERBS ARE PERMANENT** (user, 2026-09-01: *"we want both buttons
///    persistent… user will always want one of those two options"*). So Home is
///    a SPLIT PANEL, not a state machine that swaps one verb for the other, and
///    not one verb with the other demoted to a chip.
/// 3. **THE INK IS WHAT MAKES IT BOLD** (user). One half is the room's card
///    surface and one half is the venue's own colour, and the sheet is
///    `DS.surfaceSheet` — which in dark is `#000000`, not the lighter grey an
///    elevated sheet would invent.
///
/// **WHY SEND IS THE TOP TILE, and it is measured rather than taste.** The
/// agent FAB is a 64pt disc 8pt from the right edge and 29pt up from the
/// bottom, floating over everything. It covers 64pt — 37% — of the BOTTOM tile
/// and none of the top one, and its notification dot is the same blue as the
/// Send tile. Blue on the bottom swallows that dot. So Send is above, Top up is
/// the ink half below, and the lockups sit bottom-LEFT where nothing reaches
/// them.
enum DevnetConsole {

    // MARK: - The panel

    /// The card's own inset, and the gap between the two halves.
    static let cardPadding = DS.Space.s4
    static let tileGap = DS.Space.s3

    /// Inside a tile: the mark, then the verb, hard against the bottom-left.
    ///
    /// **MEASURED, NOT CHOSEN (prd §553).** The room leaves 304pt below its
    /// section strip on a 390×844 phone — measured off a screenshot of this
    /// build, the same way §552 measured the chrome it could not move. Two
    /// tiles and a gap have to live inside that, so each tile is 146 and its
    /// contents are what fit:
    ///
    /// ```
    ///   padding (s3 × 2)                 24
    ///   the mark disc                    36
    ///   gap (s2)                          8
    ///   one line of price40 at 1.18×      48
    ///   ────────────────────────────────────
    ///                                   144pt   × 2 + a 12pt gap = 300 of 304
    /// ```
    ///
    /// The first cut used `s4`, `s3` and `DS.Hit.min` and came to 174 a tile —
    /// 348 for the pair, which overflowed by 44 and put "Top up" off the bottom
    /// of the screen. That is the §552 failure exactly, arriving one layout
    /// later: it renders perfectly and simply continues past the fold.
    static let tilePadding = DS.Space.s3
    static let markGap = DS.Space.s2

    /// The mark disc. Under `DS.Hit.min` deliberately — it is not a target, the
    /// whole tile is, and 146pt of tile is three times the hit floor.
    static let mark: CGFloat = 36

    /// **The floor a tile may not go under.** Two tiles plus the gap have to
    /// leave the 64pt verb its line and the mark its disc; below this the verb
    /// starts scaling and the panel stops being the thing it is. Asserted by
    /// `devnet-console-audit.py` APART from anything else, because a tile
    /// squeezed to fit one more element is exactly how this card lost its way
    /// the first time.
    static let tileFloor: CGFloat = 132

    // MARK: - The sheet

    /// The face on the amount screen is the SAME RUNG as the face in the
    /// picker (user: *"the avatar silhouetted should be the same size it is on
    /// the picker"*). At two rungs apart it read as a label ABOUT who you
    /// picked rather than the person coming with you, which is the same rule
    /// that governs the silhouettes in the room's own bar.
    static let sheetFace = DS.Face.profile

    /// The plan strip's natural height — its own two `label12` lines plus the
    /// cell's padding. **Not a reserved slot**: the strip is drawn inside a
    /// `ViewThatFits`, so it takes this much where there is room and nothing
    /// where there is not. See the call site for why a reserved height was
    /// wrong.
    static let planStripHeight: CGFloat = 40

    /// One key. `DS.Hit.min` is the floor and this is deliberately above it:
    /// this is the control people tap most in the room, and in a hurry.
    static let key: CGFloat = 58

    /// The pressed circle, inset inside the key so two quick presses stay two
    /// marks rather than one smear.
    static let keyPress: CGFloat = 50

    static var keypad: CGFloat { key * 4 }
}

enum DevnetAmountInput {

    /// The most decimals any of these chains can express — a wei is 1e-18 ETH,
    /// so an 19th digit is not a small amount, it is an unrepresentable one.
    /// Both cards' `weiData` already refuse it; refusing it at the KEY means
    /// the figure on screen is never one the button will then reject, which is
    /// the difference between a control that guides and one that scolds.
    static let maxDecimals = 18

    /// A whole-part ceiling. Hegotá's faucet balances run into the billions, so
    /// this is deliberately generous — it exists to stop a stuck key producing
    /// a figure no layout can hold, not to express a business rule.
    static let maxWhole = 15




    // **BOTH GRAMMARS, BRIEFLY (prd §553).** `append`/`delete`/`display` above
    // are the retired console's, still called by `FramesSendCard`; `sanitize`
    // below is the live one — it holds a PASTE and a held delete to the same
    // rule a refused key already enforced, which per-key editing cannot do.
    // The pair goes when that card migrates.

    /// **THE WHOLE EDIT GRAMMAR, and it is a REFUSAL rather than a repair
    /// (§552a).** The keypad used to enforce these rules one key at a time —
    /// "a refused key simply does nothing and the figure does not lie" — and
    /// with the system pad the same rules have to hold against a change that
    /// may be a paste, a held delete or a locale separator. So a change that
    /// would make an amount the chain cannot express returns the PREVIOUS
    /// value: the field does not mangle what you typed into something else, it
    /// just does not accept it, which is exactly what a refused key did.
    ///
    /// Two things it repairs rather than refuses, because both are what every
    /// calculator on earth does and neither can produce a wrong number: a bare
    /// leading separator becomes "0.", and a digit typed against the lone
    /// placeholder "0" REPLACES it rather than making "07".
    static func sanitize(_ text: String, previous: String) -> String {
        if text.isEmpty { return "" }
        // A pasted "£12", a comma from a European keyboard, a stray letter:
        // refused whole. Stripping the bad characters instead would silently
        // turn "1,5" into "15", which is a wrong number rather than no number.
        guard text.allSatisfy({ $0.isNumber || $0 == "." }) else { return previous }
        guard text.filter({ $0 == "." }).count <= 1 else { return previous }

        var out = text
        if out.hasPrefix(".") { out = "0" + out }
        while out.count > 1, out.hasPrefix("0"),
              let second = out.dropFirst().first, second.isNumber {
            out.removeFirst()
        }

        let parts = out.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0])
        let frac = parts.count > 1 ? String(parts[1]) : ""
        guard whole.count <= maxWhole, frac.count <= maxDecimals else { return previous }
        return out
    }
}

// MARK: - The panel

/// One half is the venue's colour and one half is the room's own card surface —
/// which is `dsWidgetSurface`, the elevation ladder's raised rung, rather than a
/// colour spelled here. A tinted tile cannot take that modifier (it would paint
/// the sheet fill over the tint), so the two are one modifier with one branch
/// instead of two backgrounds that could drift apart.
private struct DevnetTileSurface: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        if let tint {
            content.background(tint, in: RoundedRectangle(cornerRadius: DS.Radius.widget,
                                                          style: .continuous))
        } else {
            content.dsWidgetSurface()
        }
    }
}

/// **HOME IS TWO VERBS, PERMANENTLY (prd §553).**
///
/// The blue half is the venue's own colour and the ink half is the room's card
/// surface, so the two are peers in size and not in weight — the colour is the
/// only thing saying which one the room is for.
///
/// Neither tile presents anything. Send hands upward to the screen's single
/// `.sheet` (a `.sheet` attached to a view inside a `List` row resolves to the
/// same presenting controller as the screen's own and half-opens then closes,
/// paid for three times already); Top up acts in place and reports on itself.
struct DevnetSendPanel: View {
    let tint: Color
    /// Nil where the room has nothing to top up WITH — vibenet's faucet is a
    /// payer that sponsors gas, not something an address can claim from, so
    /// offering a claim there would be the dead control §83 bans. That room
    /// draws the Send half alone rather than a button that cannot act.
    var topUp: TopUp? = nil
    let onSend: () -> Void

    /// What the ink half does, and what it is currently saying about itself.
    struct TopUp {
        var busy = false
        /// Only ever present when there is something to say. The rate limit and
        /// the failure read the SAME way on purpose: §525 rules the hourly
        /// refusal expected rather than a fault, and either way the next step
        /// is identical — tap it again.
        var note: String? = nil
        /// True where the verb leaves the app rather than acting in it, so the
        /// mark can say so instead of the tile lying about what happens next.
        var handsOff = false
        var action: () -> Void
    }

    var body: some View {
        VStack(spacing: DevnetConsole.tileGap) {
            tile(kind: .send)
            if topUp != nil { tile(kind: .topUp) }
        }
    }

    private enum Kind { case send, topUp }

    @ViewBuilder
    private func tile(kind: Kind) -> some View {
        let isSend = kind == .send
        Button {
            DSHaptic.tap()
            if isSend { onSend() } else { topUp?.action() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if !isSend, let note = topUp?.note {
                    Text(note)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                disc(isSend: isSend)
                Spacer().frame(height: DevnetConsole.markGap)
                Text(isSend ? String(localized: "Send") : String(localized: "Top up"))
                    .dsText(.price40)
                    .foregroundStyle(isSend ? .white : DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .padding(DevnetConsole.tilePadding)
            .frame(maxWidth: .infinity, minHeight: DevnetConsole.tileFloor, alignment: .leading)
            .modifier(DevnetTileSurface(tint: isSend ? tint : nil))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(!isSend && (topUp?.busy ?? false))
        .dsHover()
        .accessibilityLabel(Text(isSend ? String(localized: "Send")
                                        : String(localized: "Top up from the faucet")))
    }

    @ViewBuilder
    private func disc(isSend: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSend ? AnyShapeStyle(Color.white.opacity(0.22))
                             : AnyShapeStyle(DS.fillFaint))
                .frame(width: DevnetConsole.mark, height: DevnetConsole.mark)
            if !isSend, topUp?.busy == true {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: glyph(isSend: isSend))
                    .accessibilityHidden(true)
                    .dsGlyph(20, weight: .semibold)
                    .foregroundStyle(isSend ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
            }
        }
    }

    private func glyph(isSend: Bool) -> String {
        if isSend { return "arrow.up.right" }
        return (topUp?.handsOff ?? false) ? "arrow.up.forward.app" : "drop"
    }
}

// MARK: - Before there is an account

/// **THE SAME OBJECT SAYING A DIFFERENT VERB (prd §553).**
///
/// §552d gave the keyless room a sentence and a button because Home's whole
/// content was a gated card and gating it rendered the scope blank. This keeps
/// that fix and drops its explanation: the room says what it can do, at the
/// size it says everything else, and what a key IS belongs where the account
/// lives rather than under the button that makes one.
///
/// The copy is no longer a claim about the ROOM (user, 2026-09-01: *"not
/// necessarily true b/c user may be following account"*). You can be watching
/// plenty of addresses here; the only thing missing is a key on THIS phone, so
/// the verb says what it does and nothing else.
struct DevnetCreatePanel: View {
    let tint: Color
    /// Two lines by design — it is a two-word verb at the crown rung and the
    /// tile is as tall as the split panel it replaces.
    let title: String
    var busy = false
    let onCreate: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            onCreate()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(tint)
                        .frame(width: DevnetConsole.mark, height: DevnetConsole.mark)
                    if busy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "key")
                            .accessibilityHidden(true)
                            .dsGlyph(20, weight: .semibold)
                            .foregroundStyle(.white)
                    }
                }
                Spacer().frame(height: DevnetConsole.markGap)
                Text(title)
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DevnetConsole.tilePadding)
            .frame(maxWidth: .infinity, minHeight: DevnetConsole.tileFloor * 2, alignment: .leading)
            .modifier(DevnetTileSurface(tint: nil))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(busy)
        .dsHover()
    }
}

// MARK: - The keypad

/// **OURS AGAIN, AND THE REASON IT LEFT NO LONGER APPLIES (prd §553).**
///
/// §552a swapped it for `.decimalPad` on arithmetic that was correct for a
/// CARD: 176pt of a 232pt console in a 276pt room. On a sheet there is no such
/// budget, and what the system pad cost was the room's whole visual language.
///
/// §544's second ruling, kept: bare digits on the surface, no key backgrounds.
/// The pressed circle is inset inside the key so two quick presses stay two
/// marks. Every edit goes through `DevnetAmountInput.sanitize`, so a key that
/// would make an amount the chain cannot express simply does nothing — the
/// figure on screen is never one the button will then reject.
struct DevnetKeypad: View {
    @Binding var amount: String
    let tint: Color

    @State private var pressed: String?

    private static let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"],
                                           ["7", "8", "9"], [".", "0", "\u{232B}"]]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { key(_: $0) }
                }
            }
        }
    }

    @ViewBuilder
    private func key(_ label: String) -> some View {
        let isDelete = label == "\u{232B}"
        Button {
            DSHaptic.selection()
            tap(label)
        } label: {
            ZStack {
                Circle()
                    .fill(pressed == label ? AnyShapeStyle(DS.fillFaint) : AnyShapeStyle(Color.clear))
                    .frame(width: DevnetConsole.keyPress, height: DevnetConsole.keyPress)
                if isDelete {
                    Image(systemName: "delete.backward")
                        .accessibilityHidden(true)
                        .dsGlyph(24, weight: .regular)
                        .foregroundStyle(DS.textPrimary)
                } else {
                    Text(label)
                        .dsText(.stat24)
                        .fontWeight(.regular)
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: DevnetConsole.key)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isDelete ? String(localized: "Delete") : label))
    }

    private func tap(_ label: String) {
        pressed = label
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            if pressed == label { pressed = nil }
        }
        if label == "\u{232B}" {
            guard !amount.isEmpty else { return }
            amount = String(amount.dropLast())
            return
        }
        // The whole grammar lives in one place, so a key and a paste are held
        // to the same rule: a change that cannot be expressed is REFUSED and
        // the previous value stands.
        amount = DevnetAmountInput.sanitize(amount + label, previous: amount)
    }
}

// MARK: - The sheet

/// **WHO, THEN HOW MUCH (prd §553).**
///
/// Two screens inside one sheet rather than two sheets: the amount needs the
/// whole surface for a 64pt figure and a keypad, and the picker needs it for
/// faces at `DS.Face.profile`. Sharing one presentation keeps the back gesture,
/// the grabber and the detent in one place.
///
/// **The face is the same rung on both screens** (user: *"the avatar
/// silhouetted should be the same size it is on the picker"*). Two rungs apart
/// it reads as a label ABOUT the person rather than the person you picked
/// coming with you — the same rule that governs the room's own face bar.
///
/// **ONE FIELD PASTES AND SEARCHES.** Typing filters the faces; a pasted
/// address falls straight through when it validates. There is no second
/// control, and no separate Paste button that would be dead whenever the
/// pasteboard holds nothing.
///
/// **THE SET IS THIS DEVNET'S OWN ADDRESSES.** A social handle is never offered
/// in the first place rather than accepted and refused later — the rule is
/// enforced where it can be explained.
/// ONE STEP A SEND WILL RUN, for a venue whose transaction has parts.
///
/// **Data, not a view, and that is the whole of the design.** The strip has to
/// be computed from the destination and amount, which live as `@State` inside
/// the sheet — so the caller cannot build the view, and a `@ViewBuilder` slot
/// would mean a generic parameter on a struct with twelve stored properties
/// and an inference break at both existing call sites. A venue hands over a
/// pure function of two strings instead, and the sheet draws it.
///
/// Empty for every venue but the Frames devnet, where a send is not one act:
/// it becomes a VERIFY frame that authorises and a SENDER frame that moves the
/// value, and without the first the transaction has no payer and is invalid.
/// WHAT YOUR SEND BECOMES — the steps, drawn between the figure and the
/// keypad.
///
/// A READING, never a control: there is no way to edit a step, add one or
/// change its order. That is a transaction builder and a different product.
/// This says what the tap will do, on the one chain where that is not obvious.
struct DevnetSendPlanStrip: View {
    let steps: [DevnetSendStep]

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.name)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                    Text(step.detail)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
                .lineLimit(1)
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s2)
                .background(DS.gray100,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                if index < steps.count - 1 {
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                        .dsGlyph(10, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DevnetSendStep: Equatable, Identifiable {
    let name: String
    let detail: String
    var id: String { name + "|" + detail }
}

struct DevnetSendSheet: View {
    /// What this room is, for the picker's own footnote.
    let venue: String
    let tint: Color
    /// The word beside the figure. A WORD and never a chip: both devnets move
    /// native ETH and only that (`VibenetSend.sendValue` takes a `valueWei` and
    /// nothing else), so a control here would open a one-item menu — the dead
    /// control §83 bans. It becomes a control the day a bridge can move a
    /// token, and not before.
    let unit: String
    let candidates: [(address: String, name: String?)]
    /// What the sending account holds, already formatted. Nil when the sweep
    /// could not reach the chain — a failed read and a real zero must not look
    /// alike (§83), so the line is absent rather than claiming nothing is held.
    let heldLine: String?
    /// Nil where filling the whole balance is a guaranteed failure — on Hegotá
    /// the sender pays its own gas, so an amount equal to the balance cannot
    /// pay for itself.
    let maxAmount: String?
    let isValidAddress: (String) -> Bool
    let isValidAmount: (String) -> Bool
    /// Returns nil on success, or the sentence to show on failure.
    let perform: (String, String) async -> String?
    /// **What this send BECOMES, if the venue has anything to say.** Given the
    /// destination and amount currently entered, return the steps the
    /// transaction will run. Nil for every venue whose send is one act.
    ///
    /// Drawn ABOVE the keypad rather than below it, deliberately: the space
    /// under the pad is where the thumb travels between the last digit and the
    /// commit, so a strip there is read on the way past rather than looked at
    /// — and a claim about what the transaction becomes belongs beside the
    /// amount it describes, not adjacent to the button that fires it.
    var plan: ((_ destination: String, _ amount: String) -> [DevnetSendStep])? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(ShellChrome.self) private var chrome

    @State private var destination = ""
    @State private var amount = ""
    @State private var query = ""
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var searching: Bool

    private var picked: Bool { !destination.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if picked { amountScreen } else { whoScreen }
        }
        .padding(.horizontal, DevnetConsole.cardPadding)
        .padding(.bottom, DevnetConsole.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.surfaceSheet)
        .animation(DS.Motion.standard, value: picked)
    }

    // MARK: Who

    private var matches: [(address: String, name: String?)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.address.lowercased().contains(q) || ($0.name ?? "").lowercased().contains(q)
        }
    }

    /// A typed string that is itself an address is offered as its own row, so
    /// pasting one needs no second gesture — the field IS the paste target.
    private var pastedAddress: String? {
        let s = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(s) else { return nil }
        return s
    }

    private var whoScreen: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "magnifyingglass")
                    .accessibilityHidden(true)
                    .dsGlyph(16, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
                TextField("", text: $query,
                          prompt: Text(String(localized: "Paste an address, or search"))
                            .foregroundStyle(DS.textTertiary))
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searching)
                    .submitLabel(.done)
                    .onSubmit { if let pastedAddress { destination = pastedAddress } }
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(height: DS.Hit.min + DS.Space.s2)
            .dsWell(cornerRadius: DS.Radius.control)

            if let pastedAddress {
                Button {
                    DSHaptic.tap()
                    destination = pastedAddress
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        WalletFace(address: pastedAddress, size: DS.Face.list, circular: true)
                        Text(WalletStore.shortAddress(pastedAddress))
                            .dsText(.body17).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                        Spacer(minLength: DS.Space.s2)
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                            .dsGlyph(14, weight: .semibold)
                            .foregroundStyle(tint)
                    }
                    .frame(height: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DevnetConsole.sheetFace + DS.Space.s4),
                                             spacing: DS.Space.s6)],
                          spacing: DS.Space.s6) {
                    ForEach(matches, id: \.address) { candidate in
                        faceCell(candidate.address, candidate.name)
                    }
                }
                .padding(.top, DS.Space.s1)
            }
            .scrollIndicators(.hidden)

            Text(String(localized: "\(venue) addresses from your book."))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Space.s4)
    }

    private func faceCell(_ address: String, _ name: String?) -> some View {
        Button {
            DSHaptic.tap()
            destination = address
        } label: {
            VStack(spacing: DS.Space.s2) {
                WalletFace(address: address, size: DevnetConsole.sheetFace, circular: true)
                Text(name ?? WalletStore.shortAddress(address))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .dsHover()
    }

    // MARK: How much

    /// One left edge, top to bottom: face, name, figure, keypad, button. The
    /// back control is its own row above them rather than a chevron the face
    /// has to sit beside, which is what lets the column start at one indent and
    /// stay there.
    private var amountScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                DSHaptic.selection()
                destination = ""
                amount = ""
                errorText = nil
            } label: {
                Image(systemName: "chevron.left")
                    .accessibilityHidden(true)
                    .dsGlyph(18, weight: .semibold)
                    .foregroundStyle(DS.textPrimary)
                    .frame(width: DS.Hit.min, height: DS.Hit.min, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(String(localized: "Choose someone else")))
            .dsHover()

            WalletFace(address: destination, size: DevnetConsole.sheetFace, circular: true)
                .padding(.top, DS.Space.s2)

            Text(recipientName)
                .dsText(.stat24)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .padding(.top, DS.Space.s3)

            HStack(alignment: .lastTextBaseline, spacing: DS.Space.s2) {
                Text(amount.isEmpty ? "0" : amount)
                    .dsText(.price40)
                    .foregroundStyle(amount.isEmpty ? DS.textTertiary : DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(unit)
                    .dsText(.price16)
                    .foregroundStyle(amount.isEmpty ? DS.textTertiary : DS.textSecondary)
            }
            .padding(.top, DS.Space.s4)

            HStack(spacing: DS.Space.s2) {
                if let heldLine {
                    Text(heldLine)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
                if let maxAmount, !maxAmount.isEmpty {
                    Button {
                        DSHaptic.selection()
                        amount = DevnetAmountInput.sanitize(maxAmount, previous: amount)
                    } label: {
                        Text(String(localized: "Max"))
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(tint)
                            .padding(.horizontal, DS.Space.s2)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(PressSpring())
                    .dsHover()
                }
            }
            .frame(height: DS.Space.s6)
            .padding(.top, DS.Space.s1)

            Spacer(minLength: DS.Space.s4)

            // **FIXED HEIGHT, so the `Spacer` collapses around it rather than
            // the strip being squeezed off.** Slack is not a budget: there is
            // ~96pt of it on an 844pt phone, ~64 on an 812 and none on a 736,
            // where the keypad starts pushing. A reading that silently
            // disappears on small phones is the same class as a card that
            // overflows and simply continues past the fold — which renders
            // perfectly and is what `devnet-console-audit.py` exists for. Its
            // height is a term in that audit's sum.
            if let plan {
                let steps = plan(destination, amount)
                if !steps.isEmpty {
                    // **`ViewThatFits`, NOT a fixed height** (prd §548). The
                    // first cut reserved 40pt and added it to this file's own
                    // budget — then the arithmetic said the amount screen has
                    // NEGATIVE slack on a 736pt phone before the strip exists
                    // at all, using §553's own measured terms. Whether that is
                    // real depends on how the sheet's top inset scales, which
                    // was measured on an 844 and is not knowable from here.
                    //
                    // So the strip does not assert a number it cannot verify.
                    // It draws where there is room and steps aside where there
                    // is not, which is correct on every phone without anyone
                    // having to know the geometry. The alternative — a
                    // reserved height on a screen with no `ScrollView` — pushes
                    // the commit button off the bottom, drawn correctly and
                    // invisible, which is the panel bug this file exists for.
                    //
                    // Stepping aside is honest here because the strip is an
                    // EXPLANATION, not a safety control: the transaction is
                    // identical without it. A control would have to shrink the
                    // screen instead.
                    ViewThatFits(in: .vertical) {
                        VStack(spacing: 0) {
                            DevnetSendPlanStrip(steps: steps)
                            Spacer(minLength: DS.Space.s3)
                        }
                        EmptyView()
                    }
                    .fixedSize(horizontal: false, vertical: false)
                }
            }

            DevnetKeypad(amount: $amount, tint: tint)

            if let errorText {
                Text(errorText)
                    .dsText(.label12)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Space.s2)
            }

            commit
        }
    }

    private var recipientName: String {
        candidates.first { $0.address.caseInsensitiveCompare(destination) == .orderedSame }?.name
            ?? WalletStore.shortAddress(destination)
    }

    private var armed: Bool {
        !busy && isValidAddress(destination) && isValidAmount(amount)
    }

    /// **THE BUTTON NAMES THE AMOUNT** once there is one (§538): it moves money
    /// and "Send" alone is the weakest thing it could say at the moment it is
    /// tapped.
    private var commit: some View {
        Button {
            DSHaptic.tap()
            act()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "arrow.up.right").dsGlyph(15, weight: .semibold)
                Text(armed ? String(localized: "Send \(amount) \(unit)")
                           : String(localized: "Send"))
                if busy { ProgressView().controlSize(.mini).tint(.white) }
            }
            .dsText(.callout15).fontWeight(.semibold)
            .foregroundStyle(armed ? .white : DS.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s4)
            .background(armed ? AnyShapeStyle(tint) : AnyShapeStyle(DS.fillFaint),
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(!armed)
        .armedPop(armed)
        .animation(DS.Motion.standard, value: armed)
        .dsHover()
    }

    /// **THE ENDING MIRRORS TOP UP** (prd §553): the sheet goes, it rains, and
    /// the crown moves — up there, down here. No receipt screen; the row lands
    /// in Activity, one chip away in the bar the sheet is covering.
    private func act() {
        let to = destination
        let spending = amount
        busy = true
        errorText = nil
        Task { @MainActor in
            let failure = await perform(to, spending)
            busy = false
            if let failure {
                errorText = failure
                return
            }
            DSHaptic.success()
            chrome.refreshHue = tint
            chrome.refreshPulse &+= 1
            dismiss()
        }
    }
}

// MARK: - Parsing, once

/// **ONE PARSER, BOTH ROOMS (prd §553).** Each send card carried a private copy
/// of these two, byte-identical, which is how a sheet shared by two rooms
/// quietly starts accepting different amounts in each.
enum DevnetSendParse {

    static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 42, s.hasPrefix("0x") else { return false }
        return s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// A typed decimal ETH amount to minimal big-endian wei bytes — string
    /// arithmetic throughout, never `Double`: Hegotá's own faucet balances run
    /// into the billions of ETH, well past `Double`'s exact-integer range.
    static func weiData(from text: String) -> Data? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        let frac = parts.count == 2 ? String(parts[1]) : ""
        guard whole.allSatisfy(\.isNumber), frac.allSatisfy(\.isNumber), frac.count <= 18
        else { return nil }
        let combined = whole + frac + String(repeating: "0", count: 18 - frac.count)
        guard let word = SafeABI.word(uint256: combined) else { return nil }
        let trimmed = word.drop(while: { $0 == 0 })
        guard !trimmed.isEmpty else { return nil }
        return Data(trimmed)
    }
}
