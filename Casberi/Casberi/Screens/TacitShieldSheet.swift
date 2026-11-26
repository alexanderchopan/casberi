import SwiftUI

/// MAKE TAC PRIVATE, AS A SEND (prd §1971 item 20; the canvas "Make TAC
/// private, quieter", user: "Build it").
///
/// Send's own rows, every fact a row with a figure, no sentences: To Tacit,
/// Token TAC, Amount with Max, Fee; then You get and Arrives. Held, it turns
/// into three steps in place (Proved, Your wallet signs, Tacit takes it), and
/// the page's Private shows the deposit Arriving until the chain takes it.
struct TacitShieldSheet: View {
    @Bindable var shield = TacitShield.shared
    @Bindable var account = TacitAccount.shared
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var source: TacitShield.Source?
    /// Drawn inside Move, over Send's sentence (prd §1976), not as a sheet:
    /// its foot leads with Move's way back, and Done goes back to Move.
    var leave: (() -> Void)? = nil

    private var coSigner: String? { YourAccountFacts.coSigners.first }
    private var walletHeld: Double { account.reading?.publicTAC ?? 0 }
    private var accountHeld: Double { account.reading?.accountTAC ?? 0 }
    /// Where it comes from: your Casberi account first when it holds TAC
    /// (what Buy TAC buys), else your wallet; a choice only when both do.
    private var from: TacitShield.Source { source ?? (accountHeld > 0 ? .account : .wallet) }
    private var held: Double { from == .account ? accountHeld : walletHeld }
    private var tac: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    @Environment(\.moveBack) private var moveBack
    /// The step whose list or keys stand in the deck (prd §1931).
    @State private var open: Open? = .amount
    private enum Open { case amount, from }

    /// **MOVE'S DECK, AS RAILGUN'S (prd §1983, §1927):** To, From, Token and
    /// Amount as the sentence's chips, the amount on Move's own keys, then
    /// the receipt; while it goes, its steps.
    var body: some View {
        MoveReceiptDeck(title: String(localized: "Send"), inTray: true, backDisabled: busy, back: {
            withAnimation(DS.Motion.standard) {
                if let moveBack { moveBack() } else if let leave { leave() } else { dismiss() }
            }
        }, lines: {
            if !sending { MoveReceiptSteps(steps: deckSteps) }
        }, content: {
            Group {
                if open == .amount, !sending {
                    VStack(spacing: MoveReceipt.gap) {
                        Spacer(minLength: 0)
                        MoveQuickKeys(keys: [MoveQuickKeys.Key(id: "max", word: String(localized: "Max"),
                                                               on: amount == Self.maxText(held)) {
                            amount = Self.maxText(held)
                        }])
                        MoveKeypad(text: $amount, places: 8, keyHeight: MoveSentence.bigKeyHeight, big: true)
                    }
                    .transition(.opacity)
                } else if open == .from, !sending {
                    deckList { fromChoices }
                } else {
                    deckList { if sending { steps } else { receipt } }
                }
            }
        }, word: { foot })
        .animation(DS.Motion.standard, value: open)
        .task(id: amount) {
            // A quote follows the amount, a beat after the last keystroke.
            try? await Task.sleep(for: .milliseconds(500))
            guard !sending, let tac, tac > 0, tac <= held else { return }
            await shield.quote(tac: tac)
        }
        .onAppear {
            shield.reset()
            if amount.isEmpty, held > 0 { amount = Self.maxText(held) }
        }
    }

    private var busy: Bool {
        switch shield.step {
        case .proving, .signing, .handing: true
        default: false
        }
    }

    // MARK: - The deck

    private var deckSteps: [MoveDeckStep] {
        var out: [MoveDeckStep] = [
            MoveDeckStep(id: "to", word: String(localized: "To"), answered: true, value: "Tacit", glyph: "lock.fill") {
                if let leave { leave() }
            },
        ]
        if walletHeld > 0, accountHeld > 0 {
            out.append(MoveDeckStep(id: "from", word: String(localized: "From"), on: open == .from, answered: true,
                                    value: from == .account ? String(localized: "Your public account") : String(localized: "Co-signer")) { toggle(.from) })
        }
        out.append(MoveDeckStep(id: "token", word: String(localized: "Token"), answered: true,
                                value: "TAC · Ethereum", mark: MoveRowMark(token: "TAC")) {})
        out.append(MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: open == .amount, answered: !amount.isEmpty,
                                value: amount.isEmpty ? (open == .amount ? "0 TAC" : nil) : "\(amount) TAC",
                                fieldNote: MoveFieldNote.against(typed: amount, have: Self.maxText(held), symbol: "TAC")) { toggle(.amount) })
        return out
    }

    private func toggle(_ o: Open) {
        DSHaptic.selection()
        withAnimation(DS.Motion.standard) { open = open == o ? nil : o }
    }

    private func deckList<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView { content().padding(.vertical, DS.Space.s2) }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
            .transition(.opacity)
    }

    /// Where the TAC leaves from: your Casberi account or your co-signer.
    @ViewBuilder private var fromChoices: some View {
        fromRow(String(localized: "Your public account"), detail: TacitAccountRows.amount(accountHeld) + " TAC", picked: from == .account) { pick(.account) }
        fromRow(String(localized: "Co-signer"), detail: TacitAccountRows.amount(walletHeld) + " TAC", picked: from == .wallet) { pick(.wallet) }
    }

    private func fromRow(_ name: String, detail: String, picked: Bool, act: @escaping () -> Void) -> some View {
        Button {
            act()
            withAnimation(DS.Motion.standard) { open = .amount }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: name).dsText(.body17).foregroundStyle(picked ? DS.pickInk : DS.textPrimary)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: detail).dsText(.body17).monospacedDigit().foregroundStyle(DS.textSecondary)
                if picked { Image(systemName: "checkmark").dsGlyph(.body, weight: .semibold).foregroundStyle(DS.pickInk) }
            }
            .frame(minHeight: MoveDeck.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }

    /// The receipt under the lines: the fee, what lands and when.
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            MoveReceiptLine(label: String(localized: "Fee")) {
                Text(verbatim: feeWords).dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
            }
            MoveReceiptLine(label: String(localized: "You get")) {
                Text(verbatim: arrivesWords).dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
            }
            MoveReceiptLine(label: String(localized: "Arrives")) {
                Text("In a minute").dsText(.body17).foregroundStyle(DS.textPrimary)
            }
            if case .failed(let why) = shield.step {
                Text(verbatim: why).dsText(.body17).foregroundStyle(DS.destructiveInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sending: Bool {
        switch shield.step {
        case .proving, .signing, .handing, .arriving, .landed: return true
        default: return false
        }
    }

    private func pick(_ s: TacitShield.Source) {
        DSHaptic.selection()
        source = s
        amount = Self.maxText(held)
    }

    /// **FEE AND YOU GET AGREE (prd §1988 item 5).** Both ways prove the same
    /// deposit (`shieldProve`), and the chain takes its fee from its shares
    /// either way: `arrives` is the amount less `quote.fee`. So the Fee says
    /// that cut on both. From your wallet the leader's sweep fee is paid on
    /// top in TAC (the permit's value is the amount plus it), so it adds in;
    /// from your Casberi account there is no sweep, and the send pays its
    /// own gas, as every send does.
    private var feeWords: String {
        guard let q = shield.quote, let cut = TacitPermit.number(q.fee) else { return "—" }
        let chain = cut / pow(Decimal(10), 8)
        if from == .account {
            return String(localized: "\(Self.tacText(NSDecimalNumber(decimal: chain).doubleValue)) and the network fee")
        }
        guard let sweep = TacitPermit.number(q.sweepFee) else { return "—" }
        return Self.tacText(NSDecimalNumber(decimal: chain + sweep / pow(Decimal(10), 18)).doubleValue)
    }

    private var arrivesWords: String {
        guard let q = shield.quote, let arrives = TacitEngineWire.tac(q.arrives) else { return "—" }
        return Self.tacText(NSDecimalNumber(decimal: arrives).doubleValue)
    }

    /// All of it, never a hair more: rounded DOWN to the chain's eight
    /// places, no grouping, so the field parses back to at most what is held
    /// (Max wrote 4 significant digits rounded to nearest, and 1.7899 became
    /// 1.79: "More than it holds").
    static func maxText(_ held: Double) -> String {
        held.formatted(.number.grouping(.never).precision(.fractionLength(0...8)).rounded(rule: .down))
    }

    static func tacText(_ v: Double) -> String {
        "\(v.formatted(.number.precision(.significantDigits(1...4)))) TAC"
    }

    // MARK: - Sending

    @ViewBuilder private var steps: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "\(TacitAccountRows.amount(Double(shield.units) / 1e8)) TAC ").foregroundStyle(DS.textPrimary)
            Text("to ").foregroundStyle(DS.textPrimary)
            Text(verbatim: "Tacit").foregroundStyle(DS.pickInk)
        }
        .dsText(.heading34)
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            // While it proves, the seconds count, so a slow read is seen
            // moving, never a spinner alone.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                step(String(localized: "Proved"), state: provedState, figure: provedFigure(at: context.date))
            }
            step(String(localized: "Co-signer signs"), state: signState, figure: signFigure)
            step(String(localized: "Tacit takes it"), state: takeState, figure: nil)
        }
        .padding(.top, DS.Space.s6)
    }

    private enum StepState { case waiting, now, done }

    private func provedFigure(at now: Date) -> String? {
        if let since = shield.provingSince { return "\(Int(now.timeIntervalSince(since))) s" }
        return shield.proveMs.map { "\(Int((Double($0) / 1000).rounded())) s" }
    }

    private var provedState: StepState {
        if case .proving = shield.step { return .now }
        return .done
    }

    private var signState: StepState {
        switch shield.step {
        case .proving: return .waiting
        case .signing: return .now
        default: return .done
        }
    }

    private var takeState: StepState {
        switch shield.step {
        case .handing, .arriving: return .now
        case .landed: return .done
        default: return .waiting
        }
    }

    private var signFigure: String? {
        if case .signing(let done, let of) = shield.step, of > 1 { return String(localized: "\(done + 1) of \(of)") }
        return nil
    }

    private func step(_ words: String, state: StepState, figure: String?) -> some View {
        HStack(spacing: DS.Space.s3) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark").dsGlyph(.body, weight: .bold).foregroundStyle(DS.confirmInk)
                case .now: DSSpinner()
                case .waiting: Image(systemName: "circle").dsGlyph(.body, weight: .regular).foregroundStyle(DS.textTertiary)
                }
            }
            .frame(width: DSRoomChassis.headGlyph)
            Text(verbatim: words).dsText(.body17)
                .foregroundStyle(state == .waiting ? DS.textTertiary : DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            if let figure { Text(verbatim: figure).dsText(.body17).monospacedDigit().foregroundStyle(DS.textSecondary) }
        }
        .frame(minHeight: WalletCardStyle.ledgerHead)
    }

    // MARK: - The foot

    @ViewBuilder private var foot: some View {
        Group {
            switch shield.step {
            case .ready:
                MoveHoldWord(word: DemoMode.isActive ? String(localized: "Not in the demo") : String(localized: "Hold to send"),
                             enabled: canSend) {
                    guard let coSigner else { return }
                    Task { await shield.send(coSigner: coSigner, from: from) }
                }
            case .arriving, .landed:
                MoveFootWord(word: String(localized: "Done")) { if let leave { leave() } else { dismiss() } }
            case .failed:
                MoveFootWord(word: String(localized: "Try again")) {
                    shield.reset()
                    if let tac { Task { await shield.quote(tac: tac) } }
                }
            case .proving, .signing, .handing:
                // The steps above say where it is; the foot stays quiet.
                EmptyView()
            default:
                if !TacitEngine.shared.isOpen, !DemoMode.isActive, let coSigner, (tac ?? 0) > 0, (tac ?? 0) <= held {
                    // Closed, the account is opened here, then quoted: never a
                    // word that asks you to go and do it (§780c).
                    // Connect, Tacit's own word (prd §1971 item 12): your
                    // wallet signs, and the fee is read the moment the account
                    // is open, not after every balance is.
                    MoveFootWord(word: String(localized: "Connect")) {
                        Task { await account.open(coSigner: coSigner) }
                        Task {
                            for _ in 0..<360 where !TacitEngine.shared.isOpen {
                                try? await Task.sleep(for: .milliseconds(500))
                            }
                            if TacitEngine.shared.isOpen, let tac { await shield.quote(tac: tac) }
                        }
                    }
                } else {
                    MoveFootWord(word: footWaiting, ink: DS.textSecondary)
                }
            }
        }
    }

    private var canSend: Bool {
        guard !DemoMode.isActive, coSigner != nil, let tac, tac > 0, tac <= held, shield.quote != nil else { return false }
        return TacitEngine.shared.isOpen
    }

    private var footWaiting: String {
        guard let tac, tac > 0 else { return String(localized: "Type an amount") }
        if tac > held { return String(localized: "More than it holds") }
        switch account.phase {
        case .connecting: return String(localized: "Connecting")
        case .signing: return String(localized: "Co-signer signs")
        default: break
        }
        return String(localized: "Reading the fee")
    }
}
