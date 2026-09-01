import SwiftUI

/// THE SEND CONSOLE, SHARED BY BOTH DEVNETS (prd §544, 2026-08-31).
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

// MARK: - The figure

/// The money, centred, with whatever the caller puts under it.
///
/// `dim` is the resting state — nothing typed yet — and it fades the figure AND
/// its unit together, because a bright "ETH" beside a grey "0" reads as a unit
/// that has been chosen for an amount that has not.
struct DevnetSendFigure<Subline: View>: View {
    let amount: String
    var dim: Bool = false
    @ViewBuilder var subline: () -> Subline

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Text(DevnetAmountInput.display(amount))
                .dsText(.price48)
                .foregroundStyle(dim ? DS.textTertiary : DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
                .animation(DS.Motion.standard, value: amount)
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
        VStack(spacing: DS.Space.s1) {
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
            // Comfortably past the 44pt floor: this is the control people tap
            // most in the room, and it is tapped in a hurry.
            .frame(height: 52)
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
                        .frame(width: 52, height: 52)
                        .opacity(configuration.isPressed ? 1 : 0)
                }
                // Reduce Motion keeps the STATE (the fill still appears — it is
                // the only feedback a key gives) and drops the animation.
                .animation(reduceMotion ? nil : DS.Motion.press, value: configuration.isPressed)
        }
    }
}

// MARK: - Who it goes to

/// The recipient as a row: a face and a name, or a stack of faces and an
/// invitation, and a forward chevron because that is where the tap goes.
///
/// **The chevron points RIGHT, not down.** An earlier cut pointed it down and
/// opened a bottom sheet from it, which is two idioms at once — a disclosure
/// says "onward", a chevron-down says "a menu drops here". This opens a picker
/// of people, which is a sheet, so the row is a disclosure.
struct DevnetSendToRow: View {
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
            HStack(spacing: DS.Space.s3) {
                Text(String(localized: "To"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)

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

                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(12, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
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
