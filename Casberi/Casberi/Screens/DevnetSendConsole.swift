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
/// 1. ~~**A KEYPAD, NOT A KEYBOARD.**~~ **REVERSED by §548a, 2026-09-01** —
///    see `DevnetConsole` below for the arithmetic. §544's objection was that
///    the system keyboard "covers half the screen — including the crown, which
///    is the balance you are deciding against". True, and the answer it reached
///    for costs 176pt of a room that has 276, PERMANENTLY, whether anybody is
///    typing or not. The keyboard costs that only while you type, and what it
///    covers is answered by the subline this console already draws: "1.2345
///    available" is the SENDING ACCOUNT's balance, which governs this send more
///    exactly than the room-total crown ever did.
/// 2. **BARE DIGITS ON THE SURFACE — kept, and now the system's.** The
///    `.decimalPad` is the same twelve keys (1–9, a separator, 0, delete) drawn
///    at the system's own sizes, with its own haptics, its own key repeat and
///    its own accessibility, and it is what every other amount field on the
///    phone raises. The custom grid was a re-implementation of it that we then
///    had to pay rent on.
/// 3. **THE FIGURE IS CENTRED AND THE VERB IS ON THE BUTTON.** An earlier cut
///    put "Send" on the left of the figure as a row label, which reads as a
///    table row rather than a money moment. The word belongs where the tap is.
///
/// **The figure IS the field** (§548a). §544 banned a `TextField` on the
/// grounds that a second input is one to keep in sync — with the keypad gone
/// there is no second input: one `@State` string, one field bound to it, and
/// `DevnetAmountInput.sanitize` as the whole grammar, still pure, still
/// provable without a view.
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

    /// **THE WHOLE EDIT GRAMMAR, and it is a REFUSAL rather than a repair
    /// (§548a).** The keypad used to enforce these rules one key at a time —
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

// MARK: - The budget

/// **THE CONSOLE'S HEIGHT IS A SUM, AND THE SUM IS WRITTEN DOWN (prd §548 and
/// its §548a amendment, 2026-09-01).** User: *"it needs to fit all on the
/// screen so user doesn't have to scroll"*, then *"needs to fit where it is. we
/// can't make the slot shorter because it needs to be that same size on all the
/// other screens and wallets"*, then — reading the first pass's stated ceiling
/// — *"needs to come from below the slot… and maybe that means we can't have a
/// keypad"*.
///
/// **It does mean that, and the arithmetic is what says so.** The room's chrome
/// is fixed and measured off a 3× screenshot of the shipping build rather than
/// estimated (iPhone 16 Pro Max, 440×956pt, PNG scanned for its surface edges):
///
/// ```
///   safe area + source chips + venue rail   198
///   DSRoomChassis.visualSlot                210   ← untouchable: every scope
///   the fused rail slab                     111      and Wallet share it
///   the gaps                                 26
///   ────────────────────────────────────────────
///   the card's top edge                     545pt   (measured 544.7)
///   the card as §544 shipped it              601pt  → its bottom at 1146 of 956
/// ```
///
/// **NONE OF THOSE FOUR TERMS SCALES WITH SCREEN HEIGHT**, which is the fact
/// that decides this. The chrome is ~545pt on a 956pt phone and ~536 on an
/// 812pt one, so the room leaves 411pt on the largest iPhone and **276pt on a
/// 13 mini**. The first pass got the card from 601 to 394 by cutting everything
/// that was not the console — and 394 does not fit in 276, so on every phone
/// but the biggest it still scrolled. There was one term left worth 176pt.
///
/// **The keypad was 45% of the budget and it was PERMANENT.** It occupied that
/// space whether or not anybody was typing. The `.decimalPad` is the same
/// twelve keys, costs nothing at rest, and covers the room only while a finger
/// is on it — and a room the size of this one cannot afford a keypad that is
/// always there. So the console is now:
///
/// ```
///   card padding (s4 × 2)                    36
///   the recipient row                        44
///   gap                                      14
///   the figure and its subline               74
///   gap                                      14
///   the verb                                 50
///   ────────────────────────────────────────────
///                                           232pt
/// ```
///
/// **The budget is the SMALLEST phone, not the largest** — that is the whole
/// correction. 812pt (a 13 mini) less its 536pt of chrome is 276, less a 10pt
/// margin so the verb never sits on the glass → **266pt**. The sum is 232 and
/// `devnet-console-audit.py` re-adds it on every build, because the failure is
/// otherwise invisible: a card that overflows renders perfectly, every element
/// drawn correctly in the right order, and the ones past the fold simply
/// continue below it. The build is green, every other audit is green, and the
/// screen sweep photographs a Send button that is off the screen and certifies
/// it. A sum in a comment is a sum nobody re-adds.
///
/// **WHAT THE AIR BOUGHT BACK.** The first pass squeezed `cardPadding` to `s3`
/// and the block gaps to `s2` for 32pt it desperately needed. It does not need
/// them now, and a card in these rooms that insets differently from every other
/// card in these rooms is a difference with nothing behind it — both are back
/// on their normal rungs and the sum still clears the smallest phone by 34pt.
///
/// **WHAT IS NOT COMING BACK, and neither was a space saving.** The card head
/// (the button carries the verb — §544's own third ruling — and the sending
/// account is on the recipient row, which has two ends to name anyway) and the
/// standing footnote (§315: it changed nothing anyone would DO, and both halves
/// are still said where they are actionable). Nor the `price48` figure: §491
/// rules that one fixed box holds the crown OR a scope's figure and never both
/// stacked, and a second crown-rung figure one slab under the crown is that
/// fault arriving by a route the chassis cannot see.
///
/// **STATED CEILING.** An iPhone SE has a 20pt safe area and a 667pt screen, so
/// its chrome is ~506 and it leaves ~161pt — 232 does not fit, and no
/// arrangement of a recipient, a figure and a verb will. That phone needs a
/// smaller chrome or a different surface; it does not need a shorter row, and
/// nothing here should be traded away chasing it.
///
/// **REFUSED: making this adaptive.** A keypad where there is room and a
/// keyboard where there is not is two consoles, two sets of bugs and two things
/// to photograph, to save one screen size from a scroll it no longer has.
enum DevnetConsole {

    /// The card's own inset — `s4`, the same as every other card in these
    /// rooms. It was squeezed to `s3` while the keypad was in the budget; a
    /// card that insets differently from its neighbours for no reason anyone
    /// can see is a difference worth undoing the moment the reason goes.
    static let cardPadding = DS.Space.s4

    /// Between the console's three blocks. One value, so the sum is a sum.
    static let blockGap = DS.Space.s3

    /// The recipient row — the hit floor exactly, never less.
    static let recipientRow = DS.Hit.min

    /// What one line of `price40` really draws.
    ///
    /// **NOT the ramp's `lineHeight`, which is a `lineSpacing` and says nothing
    /// about a single line** — a face draws about 1.2× its point size, so 40pt
    /// of Figtree is ~48. Every font-derived term here is ROUNDED UP for that
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
    /// above and below it, rounded up like every term above. The CHIP is what
    /// sets this row's height, so the chip is what is written down, and both
    /// cards pin the row to this value so the sum holds even where there is no
    /// balance to state and no chip to draw.
    static let sublineRow: CGFloat = 22

    /// One line of `callout15` (a 17pt face at 1.2×), and the verb's own
    /// vertical padding.
    static let verbLine: CGFloat = 22
    static let verbPad = DS.Space.s3

    static var figureBlock: CGFloat { figureLine + figureGap + sublineRow }
    static var verb: CGFloat { verbLine + 2 * verbPad }

    /// What the console costs, top edge to bottom edge, with nothing typed and
    /// nothing wrong. Two things are deliberately outside it. The `.decimalPad`
    /// — it costs nothing at rest, which is the entire §548a argument, and what
    /// it covers while raised is the room's problem rather than the card's. And
    /// the error line, which appears BELOW the verb only when there is
    /// something to say: scrolling to read why a send was refused is a fair
    /// trade for never scrolling to reach the button.
    static var height: CGFloat {
        2 * cardPadding + recipientRow + 2 * blockGap + figureBlock + verb
    }

    /// **THE SMALLEST PHONE, NOT THE LARGEST.** 812pt (a 13 mini) less its
    /// ~536pt of fixed chrome is 276, less a 10pt margin so the verb never sits
    /// on the glass. Budgeting against the 956pt device is what let the first
    /// pass land a 394pt console that fitted exactly one screen size.
    static let budget: CGFloat = 266
}

// MARK: - The figure

/// **THE MONEY IS THE FIELD (§548a).** Centred, with its unit beside it and
/// whatever the caller puts under it.
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
///
/// **`fixedSize` is load-bearing.** A `TextField` in an `HStack` takes every
/// point offered, which would pin the unit to the far right of the card with a
/// gulf between them; hugging its content keeps the pair centred as one object
/// and lets it grow rightward as you type, which is the Apple Cash behaviour.
/// The prompt is what gives an empty field its width, so the placeholder is a
/// real "0" rather than a hole where the largest element belongs.
///
/// **STATED CEILING:** the keypad's figure carried `minimumScaleFactor(0.4)`
/// and a `TextField` cannot — so an amount past ~10 whole digits will run its
/// line rather than shrink to fit on a narrow phone. `maxWhole` exists to stop
/// a stuck key producing a figure no layout can hold and still does; what is
/// lost is the graceful shrink between the two. Worth re-eyeballing on a device
/// with a faucet-sized Hegotá balance typed in full.
struct DevnetSendFigure<Unit: View, Subline: View>: View {
    @Binding var amount: String
    var focus: FocusState<Bool>.Binding
    /// The venue's own accent — the caret is the one place this control says
    /// which chain you are spending on while you type.
    let tint: Color
    var dim: Bool = false
    @ViewBuilder var unit: () -> Unit
    @ViewBuilder var subline: () -> Subline

    var body: some View {
        VStack(spacing: DevnetConsole.figureGap) {
            HStack(alignment: .lastTextBaseline, spacing: DS.Space.s2) {
                TextField("", text: $amount,
                          prompt: Text(verbatim: "0").foregroundStyle(DS.textTertiary))
                    .dsText(.price40)
                    .foregroundStyle(dim ? DS.textTertiary : DS.textPrimary)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .lineLimit(1)
                    .fixedSize()
                    .tint(tint)
                    .focused(focus)
                    .accessibilityLabel(Text(String(localized: "Amount")))
                    .onChange(of: amount) { previous, next in
                        let clean = DevnetAmountInput.sanitize(next, previous: previous)
                        if clean != next { amount = clean }
                    }
                unit()
            }
            subline()
        }
        .frame(maxWidth: .infinity)
        // **A BIG TARGET, AND A DECLARED CONTAINER.** At rest the field is only
        // as wide as its "0", which is a tiny thing to hit for the one control
        // this card exists to fill in, so a tap anywhere in the block focuses
        // it. `.contain` is what keeps that honest for VoiceOver: the block is
        // declared a CONTAINER whose children stay individually reachable — the
        // labelled field, the unit, the balance — rather than an untraited tap
        // surface, which is a gesture no screen reader can find (the
        // accessibility audit's own check 2, which caught exactly this).
        .accessibilityElement(children: .contain)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
}

/// **THE ONE WAY DOWN, and it is not optional (§548a).**
///
/// `.decimalPad` HAS NO RETURN KEY. Without a keyboard toolbar there is
/// literally no key that dismisses it, and a tap outside is unreliable inside a
/// scrolling `List` — so a field raised without this is a keyboard somebody
/// cannot put away, over a Send button it is covering. The audit checks both
/// cards carry it.
struct DevnetAmountToolbar: ViewModifier {
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "Done")) {
                    DSHaptic.selection()
                    focus.wrappedValue = false
                }
                .fontWeight(.semibold)
            }
        }
    }
}

extension View {
    func devnetAmountToolbar(_ focus: FocusState<Bool>.Binding) -> some View {
        modifier(DevnetAmountToolbar(focus: focus))
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
