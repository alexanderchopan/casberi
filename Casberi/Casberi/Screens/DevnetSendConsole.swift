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
    // MARK: - The sheet

    /// The face on the amount screen is the SAME RUNG as the face in the
    /// picker (user: *"the avatar silhouetted should be the same size it is on
    /// the picker"*). At two rungs apart it read as a label ABOUT who you
    /// picked rather than the person coming with you, which is the same rule
    /// that governs the silhouettes in the room's own bar.
    static let sheetFace = DS.Face.profile

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
    // are the retired console's; `sanitize`
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
                        .dsGlyph(.title, weight: .regular)
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
struct DevnetSendSheet: View {
    /// What this room is, for the picker's own footnote.
    let venue: String
    /// The seat this room IS — `Bridge.name` / `Thing.source`, which is what
    /// `BridgeIcon` resolves and what the send's shower rains one tile of (prd
    /// §655). Distinct from `venue`, which is the shortened word a person
    /// reads; a tile needs the catalog spelling or it falls back to a blank
    /// glyph.
    let seat: String
    let tint: Color
    /// The word beside the figure. A WORD and never a chip while the venue
    /// moves only its native coin, since a control would open a one-item menu
    /// — the dead control §83 bans.
    let unit: String
    let candidates: [(address: String, name: String?)]
    /// What the sending account holds, already formatted. Nil when the sweep
    /// could not reach the chain — a failed read and a real zero must not look
    /// alike (§83), so the line is absent rather than claiming nothing is held.
    let heldLine: String?
    /// Nil where filling the whole balance is a guaranteed failure — where the
    /// sender pays its own gas, an amount equal to the balance cannot pay for
    /// itself.
    let maxAmount: String?
    let isValidAddress: (String) -> Bool
    let isValidAmount: (String) -> Bool
    /// Returns nil on success, or the sentence to show on failure.
    let perform: (String, String) async -> String?

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
            DSSlabField(placeholder: "Paste an address, or search", text: $query,
                        actionLabel: "", focus: $searching, glyph: "magnifyingglass",
                        size: .compact, submitLabel: .done,
                        paste: { query = $0 }) {
                if let pastedAddress { destination = pastedAddress }
            }

            if let pastedAddress {
                Button {
                    DSHaptic.tap()
                    destination = pastedAddress
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        WalletFace(address: pastedAddress, size: DS.Face.list, circular: true)
                        Text(WalletStore.shortAddress(pastedAddress))
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                        Spacer(minLength: DS.Space.s2)
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                            .dsGlyph(.subhead, weight: .semibold)
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
                    .dsText(.label12)
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
                    .dsGlyph(.body, weight: .semibold)
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
                unitLabel
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
                        // A WORD in the venue's ink, not a washed capsule
                        // (prd §746): it sits inside the amount field's own
                        // line, where a row would have nowhere to stand.
                        Text(String(localized: "Max"))
                            .dsText(.label12)
                            .foregroundStyle(tint)
                            .dsTapTarget()
                    }
                    .buttonStyle(PressSpring())
                    .dsHover()
                }
            }
            .frame(height: DS.Space.s6)
            .padding(.top, DS.Space.s1)

            Spacer(minLength: DS.Space.s4)

            DevnetKeypad(amount: $amount, tint: tint)

            if let errorText {
                Text(errorText)
                    .dsText(.label12)
                    .foregroundStyle(DS.destructiveInk)
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
        !busy && isValidAddress(destination) && amountIsValid
    }

    private var amountIsValid: Bool { isValidAmount(amount) }

    private var unitLabel: some View {
        Text(unit)
            .dsText(.price17)
            .foregroundStyle(amount.isEmpty ? DS.textTertiary : DS.textSecondary)
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
                Image(systemName: "arrow.up.right")
                    .dsGlyph(.subhead, weight: .semibold)
                Text(armed ? "\(String(localized: "Send")) \(amount) \(unit)"
                           : String(localized: "Send"))
                if busy { DSSpinner(size: .mini, onFill: true) }
            }
            .dsText(.body17)
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
            chrome.rain(sources: [seat])
            dismiss()
        }
    }
}
