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

    /// A MENU tile's floor (2026-09-04). Lower than `tileFloor` because the
    /// verb inside it is `stat24` rather than `price40` and there are two rows
    /// of these rather than one — re-added by `devnet-console-audit.py` check 1
    /// against the same room allowance, so the grid cannot quietly grow past
    /// the budget the split panel was measured into.
    static let menuTileFloor: CGFloat = 104

    // MARK: - The sheet

    /// The face on the amount screen is the SAME RUNG as the face in the
    /// picker (user: *"the avatar silhouetted should be the same size it is on
    /// the picker"*). At two rungs apart it read as a label ABOUT who you
    /// picked rather than the person coming with you, which is the same rule
    /// that governs the silhouettes in the room's own bar.
    static let sheetFace = DS.Face.profile

    /// **THE LEG LIST'S FACE AND ROW** (prd §571).
    ///
    /// Until this ruling every row in the stitch list was `sheetFace + s4` —
    /// 91pt, the height a 76pt profile face needs — and drew a 36pt `Face.list`
    /// inside it, so a row built for a hero face carried a list face and read
    /// hollow. `Face.shelf` is the rung for a face that is one of SEVERAL
    /// (`DS.Face.shelf`'s own words), which is what every row here is; the row
    /// is that face plus one `s4`, which is the same arithmetic the old one
    /// used and the same shell for head, leg and add (user, 2026-09-01: *"the
    /// add frame card should be same size as the others"*).
    static let legFace = DS.Face.shelf
    static let legRow = DS.Face.shelf + DS.Space.s4

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
    /// **ALL THREE DEVNETS CLAIM IN PLACE NOW (prd §553b, 2026-09-01)**, so
    /// nothing passes nil here today. It stays optional rather than required
    /// because the reason it was optional is still a real state: a room whose
    /// chain runs no faucet must draw the Send half alone rather than a button
    /// that cannot act (§83). What changed is that vibenet turned out not to be
    /// such a room — its faucet was reachable all along, one `curl` from the
    /// page this tile used to open.
    var topUp: TopUp? = nil
    let onSend: () -> Void

    /// **THE ROOM'S OTHER ACTS (2026-09-04, user ruling).**
    ///
    /// *"folks testing won't want to just send, the others are just as
    /// important"* — which is the premise the two-tile panel was built without.
    /// On a devnet the person here came to make an account or authorize a key
    /// at least as often as to move money, so Create and Authorize are not
    /// supporting verbs, they are peers.
    ///
    /// Empty for Hegotá and Frames, which keep the split panel exactly as it
    /// was — this is a room's decision about its own acts, not a new default.
    var extras: [Act] = []

    /// One act beyond Send and Top up. No busy or note state, deliberately:
    /// both of those open a sheet that owns its own progress, where Top up
    /// completes in place and has to say so.
    struct Act: Identifiable {
        let id: String
        let title: String
        let glyph: String
        let act: () -> Void
        init(id: String, title: String, glyph: String, act: @escaping () -> Void) {
            self.id = id; self.title = title; self.glyph = glyph; self.act = act
        }
    }

    /// How many acts this panel is carrying.
    private var actCount: Int { 1 + (topUp == nil ? 0 : 1) + extras.count }

    /// **§559 DECIDES THE LAYOUT, and it is a scope rather than a taste.**
    ///
    /// That ruling: *"Two verbs is the ceiling, and the second is the ink half.
    /// Three is a menu, and a hero verb among peers is just shouting."* So the
    /// panel does not offer a style — it reads its own act count and takes the
    /// grammar §559 already assigned to it. Two acts keep the crown rung and
    /// the tinted Send; three or more become a menu, where nothing wears the
    /// head rung and nothing takes the tint fill.
    ///
    /// Encoding the rule as the switch means a room that grows a third act
    /// cannot accidentally keep shouting, and one that loses back down to two
    /// gets its hero back with no edit.
    private var isMenu: Bool { actCount > 2 }

    /// What the ink half does, and what it is currently saying about itself.
    struct TopUp {
        var busy = false
        /// Only ever present when there is something to say. The rate limit and
        /// the failure read the SAME way on purpose: §525 rules the hourly
        /// refusal expected rather than a fault, and either way the next step
        /// is identical — tap it again.
        var note: String? = nil
        var action: () -> Void
    }

    var body: some View {
        if isMenu {
            // TWO COLUMNS, not a stack. Four full-width tiles at the stacked
            // height is most of a screen, and the room's crown and rail sit
            // above them — the same budget `devnet-console-audit.py` check 1
            // guards, which is why the grid halves the width rather than
            // lengthening the scroll.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DevnetConsole.tileGap),
                                GridItem(.flexible(), spacing: DevnetConsole.tileGap)],
                      spacing: DevnetConsole.tileGap) {
                tile(kind: .send)
                if topUp != nil { tile(kind: .topUp) }
                ForEach(extras) { extra in tile(kind: .extra(extra)) }
            }
        } else {
            VStack(spacing: DevnetConsole.tileGap) {
                tile(kind: .send)
                if topUp != nil { tile(kind: .topUp) }
            }
        }
    }

    private enum Kind {
        case send, topUp
        case extra(Act)
    }

    @ViewBuilder
    private func tile(kind: Kind) -> some View {
        let isSend: Bool = { if case .send = kind { return true }; return false }()
        let isTopUp: Bool = { if case .topUp = kind { return true }; return false }()
        // **THE TINT FILL IS THE MENU'S ONE CASUALTY, and §559 is why.** A hero
        // among peers is shouting, so in a menu no tile takes the fill — the
        // room keeps its colour on every DISC instead, which says whose room
        // this is without saying which act it is for.
        let filled = isSend && !isMenu
        Button {
            DSHaptic.tap()
            switch kind {
            case .send:  onSend()
            case .topUp: topUp?.action()
            case .extra(let extra): extra.act()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if isTopUp, let note = topUp?.note {
                    Text(note)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                disc(kind: kind, filled: filled)
                Spacer().frame(height: DevnetConsole.markGap)
                Text(label(kind))
                    // `price40` is the crown rung and belongs to a surface that
                    // exists to do ONE thing (§559). In a menu the verb drops to
                    // `stat24` — which is also what lets a two-word act like
                    // "Authorize a key" set at half width without shrinking to
                    // fit, the failure `devnet-console-audit.py` check 2 exists
                    // to catch in the SPLIT panel and must not be confused with
                    // this.
                    .dsText(isMenu ? .stat24 : .price40)
                    .foregroundStyle(filled ? .white : DS.textPrimary)
                    // A menu label wraps rather than shrinks: two short lines
                    // read, a scaled-down one just looks broken beside its
                    // neighbour.
                    .lineLimit(isMenu ? 2 : 1)
                    .minimumScaleFactor(isMenu ? 1 : 0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DevnetConsole.tilePadding)
            .frame(maxWidth: .infinity,
                   minHeight: isMenu ? DevnetConsole.menuTileFloor : DevnetConsole.tileFloor,
                   alignment: .leading)
            .modifier(DevnetTileSurface(tint: filled ? tint : nil))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(isTopUp && (topUp?.busy ?? false))
        .dsHover()
        .accessibilityLabel(Text(isTopUp ? String(localized: "Top up from the faucet")
                                         : label(kind)))
    }

    private func label(_ kind: Kind) -> String {
        switch kind {
        case .send:  return String(localized: "Send")
        case .topUp: return String(localized: "Top up")
        case .extra(let extra): return extra.title
        }
    }

    @ViewBuilder
    private func disc(kind: Kind, filled: Bool) -> some View {
        let isTopUp: Bool = { if case .topUp = kind { return true }; return false }()
        ZStack {
            Circle()
                .fill(filled ? AnyShapeStyle(Color.white.opacity(0.22))
                             : AnyShapeStyle(DS.fillFaint))
                .frame(width: DevnetConsole.mark, height: DevnetConsole.mark)
            if isTopUp, topUp?.busy == true {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: glyph(kind))
                    .accessibilityHidden(true)
                    .dsGlyph(20, weight: .semibold)
                    .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
            }
        }
    }

    /// **THE DROP IS UNCONDITIONAL AGAIN (prd §553b).** §553's amendment gave
    /// this an outward-arrow branch for a `handsOff` tile, which vibenet was
    /// the only room ever to set and no longer does — a flag with one possible
    /// value is a branch that cannot happen, so both are gone. A tile that
    /// LEAVES the app should say so again if one ever returns.
    private func glyph(_ kind: Kind) -> String {
        switch kind {
        case .send:  return "arrow.up.right"
        case .topUp: return "drop"
        case .extra(let extra): return extra.glyph
        }
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

/// ONE LEG OF A STITCHED TRANSACTION, as the sheet holds it.
///
/// `id` is a `UUID` and deliberately not derived from the contents: two legs
/// sending the same amount to the same address is a perfectly ordinary thing
/// to build, and a content-derived id collapses them into one row that then
/// animates and deletes wrongly.
struct DevnetSendLeg: Identifiable, Equatable {
    let id = UUID()
    var address: String
    var amount: String
}

/// **WHAT TURNS THE SHEET INTO A BUILDER.** Nil for every venue whose send is
/// one act, which is vibenet and Hegotá — they get byte-identical behaviour to
/// before, and that is the whole reason this is a parameter rather than a
/// rewrite of the two screens they share.
struct DevnetStitch {
    /// The head row's words, or **nil for a venue with no built leg at all
    /// (2026-09-04)**.
    ///
    /// Frames' VERIFY frame is BUILT, never chosen, so it is drawn as a row you
    /// cannot tap rather than left out — leaving it out is what makes somebody
    /// ask whether they were supposed to add it. A vibenet batch has no such
    /// prefix: every row in its list is a call somebody wrote, so a head row
    /// there would be a picture of nothing, which is the opposite failure and
    /// just as misleading.
    let headName: String?
    let headDetail: String?
    /// **WHETHER ALL-OR-NOTHING IS A DECISION OR A PROPERTY OF THE CHAIN
    /// (2026-09-04).**
    ///
    /// It was three `String`s and a `Toggle`, which was right while Frames was
    /// the only venue that stitched. vibenet batches CALLS INSIDE ONE
    /// TRANSACTION — one nonce, one signature, one revert — so there is no OFF
    /// state to reach, and a toggle offering one would be the dead control §83
    /// bans, wired to a property rather than to a choice.
    ///
    /// An enum rather than three optionals so the invalid states — a title with
    /// no OFF sentence, a control described but not offered — cannot be built.
    enum Atomicity: Equatable {
        /// The chain lets you choose, and **BOTH states need describing**: off
        /// is Frames' default and is behaviour no other send in this app has,
        /// so a control that only describes ON leaves the dangerous state
        /// unexplained.
        case chosen(title: String, on: String, off: String)
        /// The chain decided. One sentence, no control, and the sentence is
        /// still REQUIRED: "these send together" is not obvious from a list,
        /// and leaving it out makes somebody wonder whether the legs are
        /// separate transactions they will be asked to approve one by one.
        case inherent(String)

        /// What the transaction will actually do, which for `.inherent` is not
        /// the sheet's toggle to decide. Read by the sender and by the preview,
        /// so a venue can never draw one shape and send another.
        var isAlwaysAtomic: Bool {
            if case .inherent = self { return true }
            return false
        }
    }
    let atomicity: Atomicity
    /// A ceiling, and the sentence for reaching it. The chain bounds the
    /// verify prefix, so a long batch is refused by the node with a message
    /// naming no remedy — better to stop before the signature.
    let maxLegs: Int
    let atCapacity: String
    /// Returns nil on success, or the sentence to show on failure.
    let send: ([DevnetSendLeg], Bool, VibenetAdvanced) async -> String?
    /// **WHAT THIS BATCH WILL LOOK LIKE ONCE IT HAS RUN**, drawn by the venue
    /// in the venue's own idiom, above the list.
    ///
    /// Optional and closure-shaped rather than a view this file builds,
    /// because the whole value of it is that it is the SAME drawing the room
    /// uses to show what happened — compose in the shape you will read the
    /// result in. A generic preview invented here would be a second drawing of
    /// the same thing, which is the drift `roomFigure`'s own guard exists for.
    var preview: ((_ legs: [DevnetSendLeg], _ atomic: Bool) -> AnyView)? = nil

    /// **WHICH LEGS ARE JOINED TO THE ONE BELOW THEM**, one `Bool` per leg in
    /// order, so the list can draw the tie the strip draws (prd §571).
    ///
    /// The venue answers, because the rule is the venue's: on Frames the join
    /// is `flags` bit 2 and the LAST payload frame never carries it, which the
    /// node enforces by refusing the transaction outright. **The venue must
    /// answer it by asking its own ENCODER rather than by re-spelling the
    /// rule here** — a second spelling is how a screen ends up promising a
    /// shape the signer does not produce, which is the fault this whole
    /// parameter list is arranged to prevent.
    ///
    /// Nil for a venue that cannot join anything, and the list then draws no
    /// ties at all rather than a decorative chain.
    var joins: ((_ legs: [DevnetSendLeg], _ atomic: Bool) -> [Bool])? = nil
}

/// **THE THREE ADVANCED FIELDS, AS A SHEET (2026-09-04).**
///
/// `Fields` has carried `nonceKey`, `validAfter`/`validBefore` and `metadata`
/// since §523 and nothing ever wrote one. They are the explorer's "Advanced
/// Transactions" card, and the ruling that put four tiles on Home is the same
/// one that says they belong on screen: *"folks testing won't want to just
/// send"* — on a devnet the person here is a developer, so a field they can set
/// is the product rather than a distraction from it.
///
/// **BEHIND A ROW, NOT ON THE FORM.** An ordinary send must not grow three
/// controls it will never use; §554's word budget and §563's "a screen standing
/// in front of its own answer" both point the same way. The row states the
/// current setting rather than the word "Advanced" alone, so a window left set
/// from a previous send cannot be invisible.
///
/// **EVERY VALUE HERE IS SIGNED OVER**, which is why the sheet says so once and
/// why `VibenetAdvanced.refusal` runs before the Face ID rather than after:
/// a window that has closed produces a perfectly valid signature over a
/// transaction the chain will never accept.
struct DevnetAdvancedSheet: View {
    @Binding var advanced: VibenetAdvanced
    let tint: Color
    @Environment(\.dismiss) private var dismiss

    /// Held as text so a half-typed number is not a value — the amount field's
    /// own rule, one sheet over.
    @State private var channelText = ""
    @State private var note = ""
    @State private var hasWindow = false
    @State private var opensAt = Date()
    @State private var closesAt = Date().addingTimeInterval(3600)

    var body: some View {
        DSTray(title: String(localized: "Advanced"), height: 520) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    channel
                    window
                    metadata
                    // ONE sentence for the whole sheet, not one per field —
                    // it is the same fact three times over and §554's budget
                    // is spent on saying it well once.
                    Text(String(localized: "All three are signed with the transaction. The chain enforces the window; the note is public and permanent."))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s6)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: load)
        .onDisappear(perform: commit)
    }

    private var channel: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            caption(String(localized: "Nonce channel"))
            TextField("0", text: $channelText)
                .keyboardType(.numberPad)
                .dsText(.heading17)
                .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s3)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.fillFaint))
            Text(String(localized: "Sends in different channels don't queue behind each other."))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var window: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Toggle(isOn: $hasWindow) {
                Text(String(localized: "Only valid for a window"))
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
            }
            .tint(tint)
            if hasWindow {
                DatePicker(String(localized: "From"), selection: $opensAt)
                    .dsText(.callout15)
                DatePicker(String(localized: "Until"), selection: $closesAt)
                    .dsText(.callout15)
                // The refusal the chain would make, said HERE rather than after
                // a Face ID — the sheet's whole reason for validating early.
                if let why = draft.refusal(now: UInt64(Date().timeIntervalSince1970)) {
                    Text(why)
                        .dsText(.label12).foregroundStyle(DS.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            caption(String(localized: "Note on chain"))
            TextField(String(localized: "Optional"), text: $note, axis: .vertical)
                .lineLimit(1...3)
                .dsText(.callout15)
                .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s3)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.fillFaint))
        }
    }

    private func caption(_ t: String) -> some View {
        Text(t).dsText(.label12).foregroundStyle(DS.textTertiary)
    }

    /// What the fields currently say, as the value that would be sent.
    private var draft: VibenetAdvanced {
        VibenetAdvanced(
            nonceKey: UInt64(channelText) ?? 0,
            validAfter: hasWindow ? UInt64(opensAt.timeIntervalSince1970) : 0,
            validBefore: hasWindow ? UInt64(closesAt.timeIntervalSince1970) : 0,
            // UTF-8 and capped at the byte level, because the cap is on the
            // BYTES that ride the transaction and a character count would let a
            // note of emoji through at four times the size.
            metadata: Data(note.utf8.prefix(VibenetAdvanced.metadataCap)))
    }

    private func load() {
        channelText = advanced.nonceKey == 0 ? "" : String(advanced.nonceKey)
        note = String(decoding: advanced.metadata, as: UTF8.self)
        hasWindow = advanced.validAfter > 0 || advanced.validBefore > 0
        if advanced.validAfter > 0 { opensAt = Date(timeIntervalSince1970: TimeInterval(advanced.validAfter)) }
        if advanced.validBefore > 0 { closesAt = Date(timeIntervalSince1970: TimeInterval(advanced.validBefore)) }
    }

    /// **COMMITTED ON DISMISS, NOT PER KEYSTROKE.** A binding written on every
    /// character makes a half-typed channel ("1" on the way to "12") a real
    /// value the send would use if the sheet were swiped away mid-edit.
    private func commit() { advanced = draft }
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
    let perform: (String, String, VibenetAdvanced) async -> String?
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

    /// **NON-NIL MAKES THIS A BUILDER** (prd §548 sixth follow-up). The amount
    /// screen then ADDS a leg instead of sending, and a third screen lists what
    /// has been built. Nil leaves every existing venue exactly as it was.
    var stitch: DevnetStitch? = nil

    /// **THE ADVANCED FIELDS, FOR A VENUE WHOSE ENVELOPE CARRIES THEM
    /// (2026-09-04).** False for Hegotá and Frames, whose transactions have no
    /// nonce channel, validity window or metadata to set — a row there would be
    /// the dead control §83 bans.
    ///
    /// The VALUE travels through `perform`/`stitch.send`, which take it as a
    /// parameter rather than reading it from shared state: a value written in
    /// one place and read in another is a race, and this one would sign a
    /// transaction with somebody's half-typed window. The two venues that
    /// ignore it name the parameter `_`, which is the compiler recording that
    /// they were asked.
    var advancedSupported: Bool = false


    @Environment(\.dismiss) private var dismiss
    @Environment(ShellChrome.self) private var chrome

    @State private var destination = ""
    @State private var amount = ""
    @State private var query = ""
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var searching: Bool

    /// The stitched legs, in the order they will run.
    @State private var legs: [DevnetSendLeg] = []
    /// **OFF BY DEFAULT, because the chain is off by default.** Defaulting it
    /// on would be kinder and would misrepresent what the transaction does
    /// unless the person changed it — and the point of the control is that
    /// this chain's answer is the unusual one.
    @State private var atomicChoice = false
    @State private var advanced = VibenetAdvanced.default
    @State private var showingAdvanced = false

    /// What this send will DO. For a venue whose batch is atomic by
    /// construction the toggle is never drawn and never read — deriving it here
    /// rather than seeding `atomicChoice` to true means there is no state a
    /// future edit could flip out from under the chain's own rule.
    private var atomic: Bool {
        (stitch?.atomicity.isAlwaysAtomic ?? false) || atomicChoice
    }
    /// Whether the who/amount pair is currently being walked to add a leg.
    /// Starts true so a builder opens on the picker rather than on an empty
    /// list, which is a screen with nothing on it but a button.
    @State private var addingLeg = true

    private var picked: Bool { !destination.isEmpty }

    private enum Screen { case who, amount, legs }

    /// **ONE PLACE DECIDES WHICH SCREEN IS UP**, so a builder and a one-act
    /// send cannot drift into two different navigation rules.
    private var screen: Screen {
        guard stitch != nil else { return picked ? .amount : .who }
        guard addingLeg else { return .legs }
        return picked ? .amount : .who
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch screen {
            case .who:    whoScreen
            case .amount: amountScreen
            case .legs:   legsScreen
            }
        }
        .padding(.horizontal, DevnetConsole.cardPadding)
        .padding(.bottom, DevnetConsole.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.surfaceSheet)
        .animation(DS.Motion.standard, value: picked)
        .animation(DS.Motion.standard, value: addingLeg)
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
            // **A WAY BACK TO WHAT YOU HAVE ALREADY BUILT.** Without it,
            // reaching the picker from the list is a one-way door: the only
            // exits are adding a leg you may not want or cancelling the whole
            // transaction. Absent for a one-act send, where this screen IS the
            // start and a back control would point at nothing.
            if !legs.isEmpty {
                Button {
                    DSHaptic.selection()
                    query = ""
                    addingLeg = false
                } label: {
                    Image(systemName: "chevron.left")
                        .accessibilityHidden(true)
                        .dsGlyph(18, weight: .semibold)
                        .foregroundStyle(DS.textPrimary)
                        .frame(width: DS.Hit.min, height: DS.Hit.min, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text(String(localized: "Back to the frames")))
                .dsHover()
                .padding(.bottom, -DS.Space.s2)
            }
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
            if stitch != nil { addLeg() } else { act() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: stitch == nil ? "arrow.up.right" : "plus")
                    .dsGlyph(15, weight: .semibold)
                // **THE BUTTON NAMES WHAT IT DOES, and in a builder that is
                // not sending.** "Send" on a screen that appends a leg is the
                // §83 fake status in the one place it would cost money: you
                // would tap it believing the transaction had gone.
                Text(stitch == nil
                     ? (armed ? String(localized: "Send \(amount) \(unit)")
                              : String(localized: "Send"))
                     : (armed ? String(localized: "Add \(amount) \(unit)")
                              : String(localized: "Add")))
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

    // MARK: The legs

    private func addLeg() {
        legs.append(DevnetSendLeg(address: destination, amount: amount))
        destination = ""
        amount = ""
        query = ""
        errorText = nil
        addingLeg = false
    }

    /// **THE SUM IS `Decimal`, NEVER `Double`.** A typed amount carries up to
    /// 18 decimal places and `Double` holds ~15 significant digits, so a plain
    /// sum silently rounds — on the one line that tells somebody how much is
    /// about to leave. `Decimal` is 38 digits and exact for a handful of legs.
    /// The wei conversion at send time still goes through
    /// `DevnetSendParse.weiData`, which is string arithmetic throughout; this
    /// figure is for reading, and never for signing.
    private var total: String? {
        guard !legs.isEmpty else { return nil }
        var sum = Decimal(0)
        for leg in legs {
            guard let d = Decimal(string: leg.amount, locale: Locale(identifier: "en_US_POSIX"))
            else { return nil }
            sum += d
        }
        var text = "\(sum)"
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    private var atCapacity: Bool { legs.count >= (stitch?.maxLegs ?? .max) }

    private var legsScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let stitch {
                // **NO LABEL, AND NO STRIP UP HERE** (prd §571). "What will
                // run" was a caption on a list that captions itself, and the
                // strip has moved into the tile that sends it — this screen
                // had TWO saturated blocks, the strip and the button, which is
                // precisely what stops a hero tile reading (`hero-tint-audit`,
                // §563 item 4). What the label bought was air above the rows,
                // and the air stays.
                //
                // Asked from the encoder, never re-derived: `joins` reaches
                // the venue's own builder, so the tie this list draws and the
                // tie the strip draws are the same fact.
                let joins = stitch.joins?(legs, atomic) ?? []

                ScrollView {
                    VStack(spacing: DS.Space.s2) {
                        if let name = stitch.headName, let detail = stitch.headDetail {
                            headRow(name: name, detail: detail)
                        }
                        ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                            legRow(leg, joinsNext: index < joins.count && joins[index])
                        }
                        if atCapacity {
                            Text(stitch.atCapacity)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, DS.Space.s1)
                        } else {
                            addRow
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // `s6`, not `s4`: with the label gone the first row sat hard
                // against the sheet's own top corner (seen on the simulator).
                // The air this buys is free — the list is top-anchored and the
                // pool below it is the grammar's, not a shortage.
                .padding(.top, DS.Space.s6)
                .animation(DS.Motion.standard, value: atomic)

                atomicRow(stitch)
                advancedRow

                if let errorText {
                    Text(errorText)
                        .dsText(.label12)
                        .foregroundStyle(DS.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, DS.Space.s2)
                }

                sendAll
            }
        }
    }

    /// **THE ROWS ARE ONE SIZE** (user, 2026-09-01: "the add frame card should
    /// be same size as the others"). Every row here — the fixed head, a leg,
    /// and the add control — is built from `rowShell`, so the add control
    /// cannot drift into a thinner dashed strip that reads as a hint rather
    /// than as the next item in the list.
    ///
    /// **`dash` CARRIES ONE MEANING PER COLOUR** (prd §571). Both outlined
    /// rows used to be the same neutral dash while meaning two different
    /// things — the head is a row you did not add and cannot remove, the add
    /// row is a row that is not there yet — so the treatment that separates
    /// them from a real leg said nothing about which was which. Neutral is
    /// "not yours"; the venue's tint is "not yet, and one tap makes it".
    private func rowShell<Content: View>(dash: Color?,
                                         @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: DevnetConsole.legRow)
            .padding(.horizontal, DS.Space.s4)
            .background {
                let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                if let dash {
                    shape.strokeBorder(dash, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                } else {
                    shape.fill(DS.gray100)
                }
            }
            // **THE WHOLE ROW IS THE TARGET.** Found on the simulator, not by
            // reading: a dashed row has a STROKE and no fill, so SwiftUI
            // hit-tests the glyph and the words and nothing between them —
            // "Add a frame" ignored every tap past the end of its own label
            // while looking completely live. The §83 dead control, except it
            // is only dead in the half of itself nobody would think to avoid.
            .contentShape(Rectangle())
    }

    private func headRow(name: String, detail: String) -> some View {
        rowShell(dash: DS.textTertiary.opacity(0.28)) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "checkmark.seal")
                    .accessibilityHidden(true)
                    .dsGlyph(22, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
                    .frame(width: DevnetConsole.legFace, height: DevnetConsole.legFace)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                    Text(detail)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// **THE FIGURE IS THE ROW'S CROWN** (prd §571), and the name is its
    /// label — the two-tier rule at row scale, and the reverse of what shipped.
    /// This is the list somebody reads to check what is about to leave, and on
    /// it the AMOUNT was `callout15` in `textSecondary` while the NAME — very
    /// often an address-book label somebody typed, or a shortened hex stub —
    /// was bold and primary. That is §563's inversion one surface down: the
    /// thing you are here to check was the quietest thing in the row.
    ///
    /// **The "Send" subline is gone.** Every row in this list sends; a word
    /// that is true of all of them distinguishes none of them, which is the
    /// same finding as the Activity chart's "4 of them are frame…" (§554).
    private func legRow(_ leg: DevnetSendLeg, joinsNext: Bool) -> some View {
        rowShell(dash: nil) {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: leg.address, size: DevnetConsole.legFace, circular: true)
                Text(name(for: leg.address))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                // **THE FIGURE NEVER TRUNCATES, AND WEARS NO UNIT.** Seen on
                // the simulator: a long name squeezed "0.001 test ETH" to
                // "0.001 test…", which is an amount rendered as an unfinished
                // word on the list somebody checks before signing. The unit is
                // the same for every leg and is named once on the button that
                // sends them, so repeating it per row buys only the width that
                // broke the number. `layoutPriority` settles the rest: the
                // name is the part that may be abbreviated, because a face
                // sits beside it and the address is recoverable.
                Text(leg.amount)
                    .dsText(.stat24)
                    .monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                // **REMOVE IS A BUTTON, NOT A SWIPE.** A swipe here would be
                // the only swipe in this sheet, and the list is short enough
                // that a hidden gesture is a control nobody finds.
                Button {
                    DSHaptic.selection()
                    legs.removeAll { $0.id == leg.id }
                    if legs.isEmpty { addingLeg = true }
                } label: {
                    // **OUTLINED, NOT FILLED.** With the figure now at
                    // `stat24` a filled disc beside it is the second-loudest
                    // thing in the row, and it is the one control here nobody
                    // came to use.
                    Image(systemName: "minus.circle")
                        .accessibilityHidden(true)
                        .dsGlyph(20, weight: .regular)
                        .foregroundStyle(DS.textTertiary)
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text(String(localized: "Remove this frame")))
                .dsHover()
            }
        }
        // **THE TIE, WHERE YOU READ THE LIST** (prd §571). The strip draws
        // all-or-nothing as a tie between two adjacent cells because atomicity
        // is a RELATIONSHIP between two frames and every other encoding makes
        // it a property of one of them. That drawing sat at the top of the
        // screen (and now sits in the tile), so the list itself — the thing
        // somebody actually reads leg by leg — was byte-identical in both
        // states of the control. This is the strip's own encoding rotated a
        // quarter turn: a bar bridging the gap between two joined rows.
        //
        // On the face's axis rather than the row's centre, so it reads as a
        // chain running down the list. It bridges exactly `s2`, which is the
        // stack's own gap, so joined rows touch and independent ones do not.
        //
        // It can only ever draw a join the run declares: `joinsNext` comes
        // from the venue's encoder, so the last leg never ties (the node
        // refuses that flag outright) and the head row never ties (a VERIFY
        // frame's flags are `0x03` and carry no join bit).
        .overlay(alignment: .bottomLeading) {
            Capsule()
                .fill(tint)
                // 4pt, not 3: measured on the simulator, a 3pt bar bridging an
                // 8pt gap reads as a speck rather than a link.
                .frame(width: 4, height: joinsNext ? DS.Space.s2 : 0)
                .opacity(joinsNext ? 1 : 0)
                .offset(x: DS.Space.s4 + DevnetConsole.legFace / 2 - 2, y: DS.Space.s2)
                .accessibilityHidden(true)
        }
    }

    private var addRow: some View {
        Button {
            DSHaptic.tap()
            addingLeg = true
        } label: {
            rowShell(dash: tint.opacity(0.45)) {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                        .dsGlyph(22, weight: .semibold)
                        .foregroundStyle(tint)
                        .frame(width: DevnetConsole.legFace, height: DevnetConsole.legFace)
                    Text(String(localized: "Add a frame"))
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(PressSpring())
        .dsHover()
    }

    /// **THE DOOR ONTO THE ADVANCED FIELDS, and it STATES its setting.**
    ///
    /// A row reading only "Advanced" makes a window left set from a previous
    /// send invisible — which on a field the chain enforces is the §83 fake
    /// status, since the next send would simply be refused with no clue why. So
    /// the trailing text is the value, and "Default" is a real answer rather
    /// than an empty slot.
    ///
    /// Quiet by construction: a `label12` row under the commit's own controls,
    /// no fill, no disc. An ordinary send should be able to not notice it.
    @ViewBuilder
    private var advancedRow: some View {
        if advancedSupported {
            Button {
                DSHaptic.tap()
                showingAdvanced = true
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Text(String(localized: "Advanced"))
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    Text(advancedSummary)
                        .dsText(.label12)
                        .foregroundStyle(advanced.isDefault ? DS.textTertiary : tint)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .dsGlyph(11, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                }
                .padding(.vertical, DS.Space.s3)
                .padding(.horizontal, DS.Space.s1)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .dsHover()
            .sheet(isPresented: $showingAdvanced) {
                DevnetAdvancedSheet(advanced: $advanced, tint: tint)
            }
        }
    }

    /// What the row says on its right. Named parts, joined — never a count,
    /// because "2 set" tells you something is on and not which thing.
    private var advancedSummary: String {
        var parts: [String] = []
        if advanced.nonceKey != 0 { parts.append(String(localized: "channel \(advanced.nonceKey)")) }
        if advanced.validAfter > 0 || advanced.validBefore > 0 {
            parts.append(String(localized: "timed"))
        }
        if !advanced.metadata.isEmpty { parts.append(String(localized: "note")) }
        return parts.isEmpty ? String(localized: "Default") : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func atomicRow(_ stitch: DevnetStitch) -> some View {
        switch stitch.atomicity {
        case let .chosen(title, on, off):
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                    Text(atomicChoice ? on : off)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Space.s2)
                Toggle("", isOn: $atomicChoice)
                    .labelsHidden()
                    .tint(tint)
            }
            .modifier(DevnetAtomicRowChrome(animatesOn: atomicChoice))
        // **A FACT, IN THE TERTIARY TIER, WITH NO CONTROL BESIDE IT.** Not a
        // disabled toggle showing ON: a control that cannot move is the dead
        // control §83 bans, and one pinned to ON reads as a setting somebody
        // chose rather than as how the chain works. Left-aligned and plain, so
        // the eye goes to the list and the commit tile rather than to a switch
        // that is not there.
        case let .inherent(sentence):
            HStack {
                Text(sentence)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .modifier(DevnetAtomicRowChrome(animatesOn: false))
        }
    }

    /// The padding both arms share, lifted so the two can never drift apart in
    /// the space they claim — which on a sheet this tight is visible.
    private struct DevnetAtomicRowChrome: ViewModifier {
        let animatesOn: Bool
        func body(content: Content) -> some View {
            // **NO WELL** (prd §571). A well raises a control off the page,
            // and this one sits directly above the tile it changes with
            // nothing between them — the container was drawing a boundary
            // where the relationship is the point. What the well bought was
            // separation from the rows above, which the gap now gives for free.
            content
                .padding(.vertical, DS.Space.s4)
                .padding(.horizontal, DS.Space.s1)
                .animation(DS.Motion.standard, value: animatesOn)
        }
    }

    /// **THE COMMIT IS THE HERO TILE** (prd §571, §559's grammar).
    ///
    /// It was a 50pt capsule with its verb at `callout15` — smaller than the
    /// figures in the list above it — on a sheet whose whole reason is this one
    /// act. `DSActVerb` puts the verb at `price40` hard against the bottom-left
    /// with the disc above it, which is the same tile the room's Home panel
    /// opened this sheet from, so the two are recognisably one act rather than
    /// two spellings of it.
    ///
    /// **NAMES THE TOTAL, NOT THE COUNT** — §538's ruling on the one-act send,
    /// unchanged: the tile moves money, so it says how much, and the count is
    /// the one thing already visible in the list above it. The unit rides the
    /// `price16` slot beside the verb's baseline rather than inside it, which
    /// is the amount screen's own lockup.
    ///
    /// `disabled` is `legs.isEmpty` and NOT `!armedAll`: a busy tile keeps its
    /// fill and spins in the disc, because it is acting rather than refusing.
    private var sendAll: some View {
        DSActVerb(title: total.map { String(localized: "Send \($0)") }
                         ?? String(localized: "Send"),
                  unit: total == nil ? nil : unit,
                  glyph: "arrow.up.right",
                  tint: tint,
                  busy: busy,
                  disabled: legs.isEmpty,
                  accessory: stitchPreview,
                  act: actAll)
            .armedPop(armedAll)
            .animation(DS.Motion.standard, value: armedAll)
    }

    /// **THE STRIP, IN THE TILE IT SENDS.** The venue's own drawing of this
    /// batch, moved off the top of the screen (prd §571): the sheet was
    /// carrying two saturated blocks and a hero tile only reads while its fill
    /// is the one saturated block on the surface. Drawn on the tint in
    /// `Palette.onTint`, it is the SAME `FramesSequenceStrip` the room uses to
    /// show what a transaction did — so you compose in the shape you will read
    /// the result in, and the toggle's own picture now moves under your thumb.
    ///
    /// **Still absent below two legs**, on the reasoning that shipped with it:
    /// a one-leg strip is a picture of a line. The tile then draws the disc
    /// and air, which is `DSActVerb`'s ordinary look everywhere else.
    private var stitchPreview: AnyView? {
        guard let preview = stitch?.preview, legs.count > 1 else { return nil }
        return AnyView(preview(legs, atomic)
            .frame(height: 14)
            .animation(DS.Motion.standard, value: atomic))
    }

    private var armedAll: Bool { !busy && !legs.isEmpty }

    private func name(for address: String) -> String {
        candidates.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }?.name
            ?? WalletStore.shortAddress(address)
    }

    private func actAll() {
        guard let stitch else { return }
        busy = true
        errorText = nil
        let built = legs
        let allOrNothing = atomic
        Task { @MainActor in
            let failure = await stitch.send(built, allOrNothing, advanced)
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

    /// **THE ENDING MIRRORS TOP UP** (prd §553): the sheet goes, it rains, and
    /// the crown moves — up there, down here. No receipt screen; the row lands
    /// in Activity, one chip away in the bar the sheet is covering.
    private func act() {
        let to = destination
        let spending = amount
        busy = true
        errorText = nil
        Task { @MainActor in
            let failure = await perform(to, spending, advanced)
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
