import SwiftUI

/// THE SEND CONSOLE, SHARED BY BOTH DEVNETS (prd §544, 2026-08-31; fitted to
/// the screen by §548, 2026-09-01).
///
/// §538 and §539 made sending the room's own Home scope in vibenet and Hegotá,
/// which was the right move and left the FORM untouched: two labelled wells and
/// a button, i.e. a web form drawn in SwiftUI. Reported across a design pass as
/// *"this looks terrible"*, *"these look vibecoded"*, and finally the question
/// that settled it — *"what would Apple do"*.
///
/// **The answer is Apple Cash's own composition, and the pieces here are it:**
/// the recipient as a plain row, the money GIANT and CENTRED, a keypad of bare
/// digits on the surface, and one button carrying the verb. Three things follow
/// from that and each is a decision rather than a style:
///
/// 1. **A KEYPAD, NOT A KEYBOARD.** The system keyboard covers half the screen
///    — including the crown, which is the balance you are deciding against —
///    and this form lives in a scrolling room where that is worse than usual.
///    A keypad keeps the whole room legible while you type, and it is the one
///    element on the screen that unmistakably says *press me*.
/// 2. **BARE DIGITS, NO KEY BACKGROUNDS.** A grid of filled circles inside a
///    filled card is boxes-inside-boxes; every iOS keypad Apple ships draws the
///    digit on the surface it sits on. The ONLY circle is the one under your
///    finger (`KeyStyle`), so the press is the whole feedback.
/// 3. **THE FIGURE IS CENTRED AND THE VERB IS ON THE BUTTON.** An earlier cut
///    put "Send" on the left of the figure as a row label, which reads as a
///    table row rather than a money moment. The word belongs where the tap is.
///
/// **What is deliberately NOT here.** No amount `TextField` at all — the
/// keypad is the only way in, so there is no second input to keep in sync and
/// no keyboard to dismiss. `DevnetAmountInput` is the whole edit vocabulary and
/// is pure, so the harness can prove it without a view.
///
/// The two rooms differ in exactly one place and it is a §83 rule rather than a
/// taste: **Hegotá sends ETH and only ETH, so its unit is a WORD; a vibenet
/// account can hold more, so its unit is a CONTROL.** A chip that opens a
/// one-item menu is the dead control §83 bans, which is why `unit` is a view
/// the caller supplies rather than a flag this file switches on.
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

    /// Append a key. Returns the amount UNCHANGED when the key would make an
    /// amount the chain cannot express — the keypad has no disabled state, so
    /// a refused key simply does nothing and the figure does not lie.
    static func append(_ key: String, to amount: String) -> String {
        if key == "." {
            guard !amount.contains(".") else { return amount }
            // A leading "." is a shape nothing downstream parses, so the zero
            // is written for you — the same courtesy every calculator gives.
            return amount.isEmpty ? "0." : amount + "."
        }
        guard key.count == 1, let c = key.first, c.isNumber else { return amount }

        if let dot = amount.firstIndex(of: ".") {
            let decimals = amount.distance(from: amount.index(after: dot), to: amount.endIndex)
            guard decimals < maxDecimals else { return amount }
        } else {
            // "0" alone is the placeholder, not a value — typing a digit
            // REPLACES it rather than making "07".
            if amount == "0" { return key }
            guard amount.count < maxWhole else { return amount }
        }
        return amount + key
    }

    /// Delete one character. An amount left as a bare "0." is legal and parses;
    /// emptying it entirely returns the placeholder state.
    static func delete(_ amount: String) -> String {
        var next = amount
        if !next.isEmpty { next.removeLast() }
        return next
    }

    /// What the figure SHOWS for a given amount — the placeholder is a real
    /// zero rather than an empty space, so the console never has a hole where
    /// its largest element belongs.
    static func display(_ amount: String) -> String {
        amount.isEmpty ? "0" : amount
    }
}

// MARK: - The budget

/// **THE CONSOLE'S HEIGHT IS A SUM, AND THE SUM IS WRITTEN DOWN (prd §548,
/// 2026-09-01).** User: *"it needs to fit all on the screen so user doesn't
/// have to scroll"*, then, when offered a shorter figure slot: *"needs to fit
/// where it is. we can't make the slot shorter because it needs to be that
/// same size on all the other screens and wallets"*.
///
/// So the room's chrome is FIXED and the console is what gives. Measured off a
/// screenshot of the shipping build rather than estimated (iPhone 16 Pro Max,
/// 440×956pt, a 3× PNG scanned for its surface edges):
///
/// ```
///   safe area + source chips + venue rail   198
///   DSRoomChassis.visualSlot                210   ← untouchable: every scope
///   the fused rail slab                     111      and Wallet share it
///   the gaps                                 26
///   ────────────────────────────────────────────
///   the card's top edge                     545pt   (measured 544.7)
///   the card as it shipped                  601pt   → bottom at 1146 of 956
/// ```
///
/// Everything from the keypad's fourth row down — `. 0 ⌫`, the Send button and
/// the footnote under it — was off the screen, on the one surface in this app
/// whose entire content is a control you are meant to complete in one go.
///
/// **The budget, derived rather than chosen**: 956 − 545 = 411pt to the glass,
/// less an 11pt margin so the button never sits ON the edge → **400pt**. The
/// sum below comes to 394 and `devnet-console-audit.py` fails the build if it
/// ever exceeds the budget, because the failure is otherwise invisible — a card
/// that overflows renders perfectly and simply continues below the fold.
///
/// **WHAT IS NOT NEGOTIABLE, and it is the one number here that is a rule
/// rather than a taste:** `keyHeight` is `DS.Hit.min`. The keypad is 45% of
/// this budget and is therefore the obvious place to find another 40pt; it is
/// also the control people tap most in the room, in a hurry, and shrinking a
/// key below 44pt buys screen by making the thing you came for harder to hit.
/// The audit asserts the floor separately from the sum for exactly that reason.
///
/// **STATED CEILING, because a budget that quietly fails on smaller hardware is
/// worse than one that says so.** The chrome above is ~545pt on EVERY iPhone —
/// none of its four terms scales with screen height — so the room leaves 411pt
/// on a 956pt phone, 307pt on an 852pt one and 267pt on a 812pt one. 394 does
/// not fit in 307. On anything below ~950pt this console is shorter than it was
/// and still scrolls, and the only remaining slack is in the room's chrome,
/// which §548 rules out. Do not "fix" that by taking it out of `keyHeight`.
enum DevnetConsole {

    /// The card's own inset. `s3` rather than the `s4` every other card in
    /// these rooms carries: this card's content is a control rather than a
    /// reading, and a control's frame is the tightest thing on the page.
    static let cardPadding = DS.Space.s3

    /// Between the console's four blocks. One value, so the sum is a sum.
    static let blockGap = DS.Space.s2

    /// The recipient row — the hit floor exactly, never less.
    static let recipientRow = DS.Hit.min

    /// What one line of `price40` really draws.
    ///
    /// **NOT the ramp's `lineHeight`, which is a `lineSpacing` and says nothing
    /// about a single line** — a face draws about 1.2× its point size, so 40pt
    /// of Figtree is ~48. Both font-derived terms here are ROUNDED UP for that
    /// reason: an over-stated term makes the budget stricter than the glass, an
    /// under-stated one makes the budget a lie. The audit's job is to catch a
    /// structural addition — another row, a wider gap, a second button — not to
    /// certify text metrics to the point, which only a device can do.
    ///
    /// **It was `price48` and the drop is a correction, not a saving that
    /// happens to look fine.** §491 ruled that ONE FIXED BOX HOLDS THE CROWN
    /// OR THE SCOPE'S FIGURE, never both stacked — and this card drew a second
    /// 64pt figure one slab below a 64pt crown, which is that fault arriving
    /// by a route the chassis could not see. `price40` is the next rung, still
    /// the largest thing in the card by 15pt, and it is no longer a second
    /// claim on the same screen's hero.
    static let figureLine: CGFloat = 48

    /// Figure → its subline. The tightest rung on the ramp: they are one
    /// reading, not two.
    static let figureGap = DS.Space.s1

    /// The subline — one line of `label12` plus the Max chip's own 3pt padding
    /// above and below it, rounded up like the two terms above. The CHIP is
    /// what sets this row's height, so the chip is what is written down, and
    /// both cards pin the row to this value so the sum holds even where there
    /// is no balance to state and no chip to draw.
    static let sublineRow: CGFloat = 22

    static let keyRows = 4

    /// **The floor, and the whole reason the audit checks it apart from the
    /// sum.** `DS.Hit.min`, never a literal — if the ramp's floor ever moves,
    /// the keypad moves with it rather than quietly keeping an old number.
    static let keyHeight = DS.Hit.min

    /// The pressed circle, deliberately SMALLER than the key it sits in.
    ///
    /// The rows are adjacent now (no gap — that is 12pt the budget could not
    /// spare), so a circle at the full key height would be tangent to its
    /// neighbours and two quick presses would read as one blob. Inset by 2pt
    /// top and bottom, the press stays a discrete mark at typing speed.
    static let pressDiameter: CGFloat = 40

    /// One line of `callout15` (a 17pt face at 1.2×), and the verb's own
    /// vertical padding — `s2` rather than the `s3` it carried, which is 8pt
    /// the budget could not spare on a control that is already 41pt tall.
    static let verbLine: CGFloat = 22
    static let verbPad = DS.Space.s2

    static var figureBlock: CGFloat { figureLine + figureGap + sublineRow }
    static var keypad: CGFloat { CGFloat(keyRows) * keyHeight }
    static var verb: CGFloat { verbLine + 2 * verbPad }

    /// What the console costs, top edge to bottom edge, with nothing typed and
    /// nothing wrong. An error line appears BELOW the verb and is deliberately
    /// outside this sum: it exists only when there is something to say, and
    /// scrolling to read why a send was refused is a fair trade for never
    /// scrolling to reach the button.
    static var height: CGFloat {
        2 * cardPadding + recipientRow + 3 * blockGap + figureBlock + keypad + verb
    }

    /// 956 (the measured screen) − 545 (the measured chrome) − 11 (a margin, so
    /// the verb never sits on the glass).
    static let budget: CGFloat = 400
}

// MARK: - The figure

/// The money, centred, with its unit beside it and whatever the caller puts
/// under it.
///
/// `dim` is the resting state — nothing typed yet — and it fades the figure AND
/// its unit together, because a bright "ETH" beside a grey "0" reads as a unit
/// that has been chosen for an amount that has not.
///
/// **THE UNIT SITS BESIDE THE FIGURE, NOT UNDER IT (prd §548).** It used to
/// lead the subline, which cost a whole line of the budget to say a word that
/// belongs to the number: "0.5" and "ETH" are one reading and are now set as
/// one, on the last text baseline so the word rides the figure's feet however
/// the figure scales. What is left under it is the only thing that is genuinely
/// a second reading — what you HOLD, and the tap that spends all of it.
struct DevnetSendFigure<Unit: View, Subline: View>: View {
    let amount: String
    var dim: Bool = false
    @ViewBuilder var unit: () -> Unit
    @ViewBuilder var subline: () -> Subline

    var body: some View {
        VStack(spacing: DevnetConsole.figureGap) {
            HStack(alignment: .lastTextBaseline, spacing: DS.Space.s2) {
                Text(DevnetAmountInput.display(amount))
                    .dsText(.price40)
                    .foregroundStyle(dim ? DS.textTertiary : DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .animation(DS.Motion.standard, value: amount)
                unit()
            }
            subline()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The keypad

/// Bare digits, and the only circle is the one under your finger.
struct DevnetSendKeypad: View {
    @Binding var amount: String
    /// The venue's own accent — Base blue on vibenet, `DS.tint` on Hegotá — so
    /// a pressed key agrees with the active chip in the strip above.
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rows: [[String]] = [
        ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "\u{232B}"]
    ]

    var body: some View {
        // **NO ROW SPACING (prd §548).** It was `s1`, which is 12pt across the
        // four rows and 12pt the console did not have. Adjacent rows are what
        // every system passcode keypad already does; the press circle is inset
        // instead, so nothing touches at the moment it matters.
        VStack(spacing: 0) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        let isDelete = key == "\u{232B}"
        Button {
            // SELECTION, not `tap()` — a keypad fires many times in a row and
            // the heavier haptic reads as a stutter at typing speed.
            DSHaptic.selection()
            amount = isDelete
                ? DevnetAmountInput.delete(amount)
                : DevnetAmountInput.append(key, to: amount)
        } label: {
            Group {
                if isDelete {
                    Image(systemName: "delete.backward")
                        .dsGlyph(22, weight: .regular)
                        .foregroundStyle(DS.textSecondary)
                } else {
                    Text(key)
                        .dsText(.heading28)
                        .fontWeight(.regular)
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            // **THE HIT FLOOR, AND NOT A POINT LESS.** This is the control
            // people tap most in the room and they tap it in a hurry, so when
            // §548 went looking for height the keypad was the biggest block on
            // the screen and the one place it was refused. Read from
            // `DevnetConsole` rather than spelled, so the height in the budget
            // and the height on the glass are one number.
            .frame(height: DevnetConsole.keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyStyle(tint: tint, reduceMotion: reduceMotion))
        .accessibilityLabel(isDelete ? Text("Delete") : Text(key))
        .dsHover()
    }

    /// The press IS the key's whole appearance — no resting fill at all, so
    /// twelve keys read as one keypad rather than twelve buttons.
    private struct KeyStyle: ButtonStyle {
        let tint: Color
        let reduceMotion: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background {
                    Circle()
                        .fill(tint)
                        .frame(width: DevnetConsole.pressDiameter,
                               height: DevnetConsole.pressDiameter)
                        .opacity(configuration.isPressed ? 1 : 0)
                }
                // Reduce Motion keeps the STATE (the fill still appears — it is
                // the only feedback a key gives) and drops the animation.
                .animation(reduceMotion ? nil : DS.Motion.press, value: configuration.isPressed)
        }
    }
}

// MARK: - The verb

/// The one button, shared by both rooms (prd §548).
///
/// It was written out twice, identically, in two cards — and the moment the
/// console's height became a SUM that had to hold, two copies of the control
/// carrying 45 of its points became a way for the sum to quietly stop being
/// true. One component, one height, and `devnet-console-audit.py` checks both
/// cards use it rather than a button of their own.
///
/// **The title NAMES THE AMOUNT** once there is one (§538): this sits at the
/// bottom of a card in a scrolling room, so the figure it is about can be off
/// screen — and "Send" alone, on a control that moves money, is the weakest
/// thing it could say at the moment it is tapped.
struct DevnetSendVerb: View {
    let title: String
    let armed: Bool
    let busy: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right").dsGlyph(13, weight: .semibold)
                Text(title)
                if busy { ProgressView().controlSize(.mini) }
            }
            .dsText(.callout15).fontWeight(.semibold)
            .foregroundStyle(armed ? .white : DS.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DevnetConsole.verbPad)
            .background(armed ? AnyShapeStyle(tint) : AnyShapeStyle(DS.gray200),
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(!armed)
        .armedPop(armed)
        .animation(DS.Motion.standard, value: armed)
        .dsHover()
    }
}

// MARK: - Who it goes to

/// The route as one row: where it leaves from, where it lands, and a forward
/// chevron because that is where the tap goes.
///
/// **THE SENDER LIVES HERE NOW (prd §548).** It used to be the trailing half of
/// a card head — a mark disc, the word "Send" and the account name — which cost
/// 46pt to say something the button below already says and something this row
/// can carry for nothing. A send has two ends; a row with both of them on it is
/// the money grammar, and the tap still changes the only end that can change.
///
/// **The chevron points RIGHT, not down.** An earlier cut pointed it down and
/// opened a bottom sheet from it, which is two idioms at once — a disclosure
/// says "onward", a chevron-down says "a menu drops here". This opens a picker
/// of people, which is a sheet, so the row is a disclosure.
struct DevnetSendToRow: View {
    /// The account this send leaves from, and what the room calls it. Optional
    /// so the row keeps its old "To …" reading where there is no second end to
    /// name — never a face over a blank, which would be a sender we invented.
    var from: String? = nil
    var fromName: String? = nil
    /// The chosen address, or nil for the resting state.
    let address: String?
    /// What to call it — the room's own resolution, never re-derived here.
    let name: String?
    /// Up to three known addresses, previewed as faces when nothing is chosen:
    /// it says "there are people in here" where a plus sign says nothing.
    let preview: [String]
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            DSHaptic.selection()
            onTap()
        }) {
            HStack(spacing: DS.Space.s2) {
                if let from {
                    WalletFace(address: from, size: DS.Face.row, circular: true)
                    Text(fromName ?? WalletStore.shortAddress(from))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                        .dsGlyph(11, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                } else {
                    Text(String(localized: "To"))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }

                if let address {
                    WalletFace(address: address, size: DS.Face.row, circular: true)
                    Text(name ?? WalletStore.shortAddress(address))
                        .dsText(.callout15)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                } else {
                    if !preview.isEmpty {
                        HStack(spacing: -9) {
                            ForEach(preview.prefix(3), id: \.self) { candidate in
                                WalletFace(address: candidate, size: DS.Face.row, circular: true)
                                    // The knockout is the CARD's own colour, so
                                    // overlapping faces read as a stack rather
                                    // than as one smudged shape. Ink since §542.
                                    .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 2))
                            }
                        }
                    }
                    Text(String(localized: "Choose who"))
                        .dsText(.callout15)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Space.s1)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(12, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
            .frame(height: DevnetConsole.recipientRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(String(localized: "Choose who to send to")))
        .dsHover()
    }
}

// MARK: - The picker

/// Every address this devnet already knows, as faces you tap — plus Paste,
/// which is the last cell rather than a control of its own.
///
/// A TRAY, deliberately, where the asset menu is not: this is a list of PEOPLE
/// and can be any length, which is what a sheet is for.
struct DevnetSendPicker: View {
    let title: String
    /// Address → display name, in the room's own order.
    let candidates: [(address: String, name: String?)]
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: DS.Space.s4)]
    }

    var body: some View {
        DSTray(title: title, height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: DS.Space.s4) {
                    ForEach(candidates, id: \.address) { candidate in
                        cell(candidate.address, candidate.name)
                    }
                    pasteCell
                }
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Two rows of faces plus the tray's own chrome, floored so a devnet with
    /// one known address still opens as a tray rather than a sliver.
    private var trayHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(candidates.count + 1) / 3.0)))
        return min(220 + CGFloat(min(rows, 3)) * 104, 620)
    }

    private func cell(_ address: String, _ name: String?) -> some View {
        Button {
            DSHaptic.tap()
            onPick(address)
            dismiss()
        } label: {
            VStack(spacing: DS.Space.s2) {
                WalletFace(address: address, size: DS.Face.shelf, circular: true)
                // §483: with one uniform mark the rail MUST caption its faces,
                // or six accounts are six identical silhouettes.
                Text(name ?? WalletStore.shortAddress(address))
                    .dsText(.label12)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .dsHover()
    }

    /// Offered ONLY when the pasteboard really holds text — `hasStrings` asks
    /// the system without bringing anything into this process, so it raises no
    /// paste banner and reads nothing. A cell that pastes nothing is the dead
    /// control §83 bans.
    @ViewBuilder
    private var pasteCell: some View {
        if UIPasteboard.general.hasStrings {
            Button {
                DSHaptic.tap()
                let pasted = (UIPasteboard.general.string ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !pasted.isEmpty { onPick(pasted) }
                dismiss()
            } label: {
                VStack(spacing: DS.Space.s2) {
                    ZStack {
                        Circle().fill(DS.fillFaint)
                            .frame(width: DS.Face.shelf, height: DS.Face.shelf)
                        Image(systemName: "doc.on.clipboard")
                            .accessibilityHidden(true)
                            .dsGlyph(20, weight: .regular)
                            .foregroundStyle(DS.textSecondary)
                    }
                    Text(String(localized: "Paste"))
                        .dsText(.label12)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .dsHover()
        }
    }
}
