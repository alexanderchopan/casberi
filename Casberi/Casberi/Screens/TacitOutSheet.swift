import SwiftUI

/// **BACK TO PUBLIC (prd §1977).** Tacit's other Send, drawn inside Move as
/// Make private is (`TacitShieldSheet`): private TAC on the Tacit chain back to
/// your Casberi account or your co-signer. To, Token, Amount with Max, Fee,
/// then three steps: Proved on this phone, Tacit takes it, Collected by your
/// account with Face ID. TAC owed from an earlier try leads with Collect.
struct TacitOutSheet: View {
    @Bindable var out = TacitOut.shared
    @Bindable var account = TacitAccount.shared
    var leave: () -> Void
    @State private var amount = ""
    @State private var toCoSigner = false
    @FocusState private var typing: Bool

    private var coSigner: String? { YourAccountFacts.coSigners.first }
    private var yourAccount: String? { YourAccountKey.address }
    private var to: String? { toCoSigner ? coSigner : yourAccount }
    private var held: Double { account.reading?.privateTAC ?? 0 }
    /// What can go: held, and no more than the quote's most once read.
    private var most: Double {
        guard let m = out.quote.flatMap({ TacitEngineWire.tac($0.most) }) else { return held }
        return min(held, NSDecimalNumber(decimal: m).doubleValue)
    }
    private var tac: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sending { steps } else { form }
            Spacer(minLength: 0)
            foot
        }
        // Move's own inset and top, as its sentences stand.
        .padding(.horizontal, MoveSentence.sideInset(true))
        .padding(.top, DS.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPageBackground()
        .task(id: amount) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !sending, let tac, tac > 0, tac <= held else { return }
            await out.quote(tac: tac)
        }
        .task(id: to) {
            if let to { await out.readOwed(to) }
        }
        .onAppear {
            out.reset()
            if amount.isEmpty, held > 0 { amount = TacitShieldSheet.maxText(held) }
        }
    }

    private var sending: Bool {
        switch out.step {
        case .proving, .handing, .landing, .collecting, .done: return true
        default: return false
        }
    }

    // MARK: - The form

    @ViewBuilder private var form: some View {
        Text("Send").dsText(.heading34).foregroundStyle(DS.textPrimary)
        VStack(alignment: .leading, spacing: 0) {
            row("From") { Chip(text: "Tacit", glyph: "lock.fill") }
            row("To") {
                HStack(spacing: DS.Space.s2) {
                    Button { pick(false) } label: { Chip(text: "Casberi", selected: !toCoSigner) }
                        .buttonStyle(PressSpring())
                    if coSigner != nil {
                        Button { pick(true) } label: { Chip(text: String(localized: "Co-signer"), selected: toCoSigner) }
                            .buttonStyle(PressSpring())
                    }
                }
            }
            row("Token") {
                HStack(spacing: DS.Space.s2) {
                    AssetMark(name: "TAC", size: 24)
                    Text("TAC · Ethereum").dsText(.body17).foregroundStyle(DS.textPrimary)
                }
            }
            row("Amount") {
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
                        amount = TacitShieldSheet.maxText(most)
                    } label: {
                        Text("Max").dsText(.body17).foregroundStyle(DS.pickInk)
                    }
                    .buttonStyle(RowPress())
                }
            }
            row("Fee") { Text(verbatim: feeWords).dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary) }
            row("Arrives") { Text("In a few minutes").dsText(.body17).foregroundStyle(DS.textPrimary) }
        }
        .padding(.top, DS.Space.s6)
        if case .failed(let why) = out.step {
            Text(verbatim: why).dsText(.body17).foregroundStyle(DS.destructiveInk)
                .padding(.top, DS.Space.s4)
        }
    }

    private func pick(_ coSignerPicked: Bool) {
        DSHaptic.selection()
        toCoSigner = coSignerPicked
    }

    private var feeWords: String {
        guard let q = out.quote, let fee = TacitEngineWire.tac(q.fee) else { return "—" }
        let text = TacitShieldSheet.tacText(NSDecimalNumber(decimal: fee).doubleValue)
        return String(localized: "\(text) and network fee")
    }

    private func row<V: View>(_ name: LocalizedStringKey, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            Text(name).dsText(.body17).foregroundStyle(DS.textSecondary)
                .frame(width: 92, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
        .frame(minHeight: DSFeed.headHeight + 2 * DS.Space.s2)
    }

    // MARK: - Sending

    @ViewBuilder private var steps: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "\(TacitAccountRows.amount(Double(out.units) / 1e8)) TAC ").foregroundStyle(DS.textPrimary)
            Text("to ").foregroundStyle(DS.textPrimary)
            Text(verbatim: toCoSigner ? String(localized: "Co-signer") : "Casberi").foregroundStyle(DS.pickInk)
        }
        .dsText(.heading34)
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                step(String(localized: "Proved"), state: state(for: 0),
                     figure: out.provingSince.map { "\(Int(context.date.timeIntervalSince($0))) s" })
            }
            step(String(localized: "Tacit takes it"), state: state(for: 1), figure: nil)
            step(String(localized: "Collected"), state: state(for: 2), figure: nil)
        }
        .padding(.top, DS.Space.s6)
        // **SAY WHERE IT LANDED (user, 2026-11-25: "it said success but i
        // can't tell if it worked or not").** The amount paid out and the
        // place, and what that place now holds.
        if case .done = out.step, let paid = out.paidTAC {
            let place = toCoSigner ? String(localized: "your co-signer") : String(localized: "your Casberi account")
            let now = toCoSigner ? account.reading?.publicTAC : account.reading?.accountTAC
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("\(TacitAccountRows.amount(paid)) TAC is in \(place)")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                if let now {
                    Text("It holds \(TacitAccountRows.amount(now)) TAC now")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            }
            .padding(.top, DS.Space.s6)
        }
    }

    private enum StepState { case waiting, now, done }

    private func state(for index: Int) -> StepState {
        let at: Int
        switch out.step {
        case .proving: at = 0
        case .handing, .landing: at = 1
        case .collecting: at = 2
        case .done: at = 3
        default: at = 0
        }
        return index < at ? .done : index == at ? .now : .waiting
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
            MoveBackCard()
            Spacer(minLength: 0)
            switch out.step {
            case .ready:
                MoveHoldWord(word: DemoMode.isActive ? String(localized: "Not in the demo") : String(localized: "Hold to send"),
                             enabled: canSend) {
                    typing = false
                    guard let to else { return }
                    Task { await out.send(to: to) }
                }
            case .done:
                MoveFootWord(word: String(localized: "Done")) { out.finish(); leave() }
            case .failed:
                // After a withdrawal was handed, never a second one from here:
                // Collect, which reads what is owed again.
                if out.owedWei > 0 || out.handed {
                    MoveFootWord(word: String(localized: "Collect")) { Task { await out.collectOwed() } }
                } else {
                    MoveFootWord(word: String(localized: "Try again")) {
                        out.reset()
                        if let tac { Task { await out.quote(tac: tac) } }
                    }
                }
            case .proving, .handing, .landing, .collecting:
                EmptyView()
            default:
                if out.owedWei > 0 {
                    // Owed from an earlier try: collected before anything new.
                    MoveFootWord(word: String(localized: "Collect")) { Task { await out.collectOwed() } }
                } else if !TacitEngine.shared.isOpen, !DemoMode.isActive, let coSigner {
                    MoveFootWord(word: String(localized: "Connect")) {
                        Task { await account.open(coSigner: coSigner) }
                        Task {
                            for _ in 0..<360 where !TacitEngine.shared.isOpen {
                                try? await Task.sleep(for: .milliseconds(500))
                            }
                            if TacitEngine.shared.isOpen, let tac { await out.quote(tac: tac) }
                        }
                    }
                } else {
                    MoveFootWord(word: footWaiting, ink: DS.textSecondary)
                }
            }
        }
        .frame(minHeight: MoveDeck.footHeight)
        .padding(.bottom, DS.Space.s4)
    }

    private var canSend: Bool {
        guard !DemoMode.isActive, to != nil, yourAccount != nil, let tac, tac > 0, tac <= most,
              out.quote != nil else { return false }
        return TacitEngine.shared.isOpen
    }

    private var footWaiting: String {
        if DemoMode.isActive { return String(localized: "Not in the demo") }
        guard let tac, tac > 0 else { return String(localized: "Type an amount") }
        if tac > most { return String(localized: "More than it holds") }
        return String(localized: "Reading the fee")
    }
}
