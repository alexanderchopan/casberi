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
    @FocusState private var typing: Bool

    private var coSigner: String? { YourAccountFacts.coSigners.first }
    private var walletHeld: Double { account.reading?.publicTAC ?? 0 }
    private var accountHeld: Double { account.reading?.accountTAC ?? 0 }
    /// Where it comes from: your Casberi account first when it holds TAC
    /// (what Buy TAC buys), else your wallet; a choice only when both do.
    private var from: TacitShield.Source { source ?? (accountHeld > 0 ? .account : .wallet) }
    private var held: Double { from == .account ? accountHeld : walletHeld }
    private var tac: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sending {
                steps
            } else {
                form
            }
            Spacer(minLength: 0)
            foot
        }
        .padding(.horizontal, DSRoomChassis.rowInset)
        .padding(.top, DS.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPageBackground()
        .presentationDetents([.large])
        .task(id: amount) {
            // A quote follows the amount, a beat after the last keystroke.
            try? await Task.sleep(for: .milliseconds(500))
            guard !sending, let tac, tac > 0, tac <= held else { return }
            await shield.quote(tac: tac)
        }
        .onAppear {
            shield.reset()
            if amount.isEmpty, held > 0 { amount = TacitAccountRows.amount(held) }
        }
    }

    private var sending: Bool {
        switch shield.step {
        case .proving, .signing, .handing, .arriving, .landed: return true
        default: return false
        }
    }

    // MARK: - The form

    @ViewBuilder private var form: some View {
        Text("Send").dsText(.heading34).foregroundStyle(DS.textPrimary)
        Grid(alignment: .leading, horizontalSpacing: DS.Space.s4, verticalSpacing: DS.Space.s3) {
            GridRow {
                label("To")
                Chip(text: "Tacit", glyph: "lock.fill")
            }
            if walletHeld > 0, accountHeld > 0 {
                GridRow {
                    label("From")
                    HStack(spacing: DS.Space.s2) {
                        Button { pick(.account) } label: { Chip(text: "Casberi", selected: from == .account) }
                            .buttonStyle(PressSpring())
                        Button { pick(.wallet) } label: { Chip(text: String(localized: "Your wallet"), selected: from == .wallet) }
                            .buttonStyle(PressSpring())
                    }
                }
            }
            GridRow {
                label("Token")
                HStack(spacing: DS.Space.s2) {
                    AssetMark(name: "TAC", size: 24)
                    Text("TAC · Ethereum").dsText(.body17).foregroundStyle(DS.textPrimary)
                }
            }
            GridRow {
                label("Amount")
                HStack(spacing: DS.Space.s3) {
                    TextField("0", text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($typing)
                        .dsText(.body17)
                        .monospacedDigit()
                        .fixedSize()
                    Text("TAC").dsText(.body17).foregroundStyle(DS.textSecondary)
                    Button {
                        DSHaptic.selection()
                        amount = TacitAccountRows.amount(held)
                    } label: {
                        Text("Max").dsText(.body17).foregroundStyle(DS.pickInk)
                    }
                    .buttonStyle(RowPress())
                }
            }
            GridRow {
                label("Fee")
                Text(verbatim: feeWords).dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
            }
        }
        .padding(.top, DS.Space.s6)
        VStack(spacing: DS.Space.s2) {
            fact(String(localized: "You get"), arrivesWords)
            fact(String(localized: "Arrives"), String(localized: "In a minute"))
        }
        .padding(.top, DS.Space.s6)
        if case .failed(let why) = shield.step {
            Text(verbatim: why).dsText(.body17).foregroundStyle(DS.destructiveInk)
                .padding(.top, DS.Space.s4)
        }
    }

    private func pick(_ s: TacitShield.Source) {
        DSHaptic.selection()
        source = s
        amount = TacitAccountRows.amount(held)
    }

    /// From your wallet the leader's sweep fee is paid in TAC; from your
    /// Casberi account the send pays its own gas, as every send does.
    private var feeWords: String {
        if from == .account { return String(localized: "Network fee, as any send") }
        guard let q = shield.quote, let fee = TacitPermit.number(q.sweepFee) else { return "—" }
        return Self.tacText(NSDecimalNumber(decimal: fee / pow(Decimal(10), 18)).doubleValue)
    }

    private var arrivesWords: String {
        guard let q = shield.quote, let arrives = TacitEngineWire.tac(q.arrives) else { return "—" }
        return Self.tacText(NSDecimalNumber(decimal: arrives).doubleValue)
    }

    static func tacText(_ v: Double) -> String {
        "\(v.formatted(.number.precision(.significantDigits(1...4)))) TAC"
    }

    private func label(_ words: LocalizedStringKey) -> some View {
        Text(words).dsText(.body17).foregroundStyle(DS.textSecondary)
    }

    private func fact(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: name).dsText(.body17).foregroundStyle(DS.textSecondary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
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
            step(String(localized: "Proved"), state: provedState,
                 figure: shield.proveMs.map { "\(Int((Double($0) / 1000).rounded())) s" })
            step(String(localized: "Your wallet signs"), state: signState, figure: signFigure)
            step(String(localized: "Tacit takes it"), state: takeState, figure: nil)
        }
        .padding(.top, DS.Space.s6)
    }

    private enum StepState { case waiting, now, done }

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
        HStack {
            Spacer(minLength: 0)
            switch shield.step {
            case .ready:
                MoveHoldWord(word: DemoMode.isActive ? String(localized: "Not in the demo") : String(localized: "Hold to send"),
                             enabled: canSend) {
                    typing = false
                    guard let coSigner else { return }
                    Task { await shield.send(coSigner: coSigner, from: from) }
                }
            case .arriving, .landed:
                MoveFootWord(word: String(localized: "Done")) { dismiss() }
            case .failed:
                MoveFootWord(word: String(localized: "Try again")) {
                    shield.reset()
                    if let tac { Task { await shield.quote(tac: tac) } }
                }
            default:
                if !TacitEngine.shared.isOpen, !DemoMode.isActive, let coSigner, (tac ?? 0) > 0, (tac ?? 0) <= held {
                    // Closed, the account is opened here, then quoted: never a
                    // word that asks you to go and do it (§780c).
                    MoveFootWord(word: String(localized: "Open Tacit")) {
                        Task {
                            await account.open(coSigner: coSigner)
                            if let tac { await shield.quote(tac: tac) }
                        }
                    }
                } else {
                    MoveFootWord(word: footWaiting, ink: DS.textSecondary)
                }
            }
        }
        .frame(minHeight: 76)
        .padding(.bottom, DS.Space.s4)
    }

    private var canSend: Bool {
        guard !DemoMode.isActive, coSigner != nil, let tac, tac > 0, tac <= held, shield.quote != nil else { return false }
        return TacitEngine.shared.isOpen
    }

    private var footWaiting: String {
        guard let tac, tac > 0 else { return String(localized: "Type an amount") }
        if tac > held { return String(localized: "More than your wallet holds") }
        if account.phase == .connecting || account.phase == .signing || account.phase == .reading {
            return String(localized: "Opening Tacit")
        }
        return String(localized: "Reading the fee")
    }
}
