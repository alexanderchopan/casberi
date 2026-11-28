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
    @Environment(ShellChrome.self) private var chrome
    @State private var amount = ""
    @State private var source: TacitShield.Source?
    /// Drawn inside Move, over Send's sentence (prd §1976), not as a sheet:
    /// its foot leads with Move's way back, and Done goes back to Move.
    var leave: (() -> Void)? = nil
    /// Opened from Earn: Earn · Deposit · Withdraw in the title's place (prd §2005).
    var header: AnyView? = nil

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
        }, header: header, lines: {
            if !sending { MoveReceiptSteps(steps: deckSteps) }
        }, content: {
            Group {
                if open == .amount, !sending {
                    MoveDeckKeys {
                        MoveQuickKeys(keys: MoveQuickKeys.shares.map { p in
                            let text = Self.maxText(held * Double(p) / 100)
                            return .share(p, on: amount == text) { amount = text }
                        })
                        MoveKeypad(text: $amount, places: 8, keyHeight: MoveSentence.bigKeyHeight, big: true)
                    }
                } else if open == .from, !sending {
                    deckList { fromChoices }
                } else if sending {
                    // **THE SHARED STEPS (2026-11-27, the Move review: Tacit
                    // drew its own rows):** the sentence and `PrivateStepRows`,
                    // as Railgun's and Aztec's sends draw theirs.
                    MoveDeckStatus(linesStand: false, sentence: { MovePhrase(sentenceWords) }) {
                        if let run = stepsRun { PrivateStepRows(run: run).transition(.opacity) }
                    }
                } else {
                    deckList { receipt }
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
        // The shared steps follow the shield's own (2026-11-27).
        .onChange(of: shield.step) { _, now in follow(now) }
        // In Move's tray the send goes behind it (prd §2003).
        .onAppear { shield.onAway = chrome.moveTray ? { chrome.moveTray = false } : nil }
        // Opens empty, as every Move page does: Max is a key (2026-11-27).
        .onAppear { shield.reset() }
        // The rate the receipt says (prd §2004), read once an hour.
        .task { await TacitAccount.shared.readChainYield() }
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
                                value: "TAC · Ethereum", mark: MoveRowMark(token: "TAC"), fixed: true) {})
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
        let body = content()
        return MoveDeckScroll { body }
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

    /// The receipt under the lines: the fee, what lands and when, as every
    /// private send's facts (`MoveDeckFacts`).
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            MoveDeckFacts(facts: [
                MoveDeckFacts.Fact(name: String(localized: "Fee"), value: feeWords),
                MoveDeckFacts.Fact(name: String(localized: "You get"), value: arrivesWords),
                MoveDeckFacts.Fact(name: String(localized: "Arrives"), value: String(localized: "In a minute")),
            ] + earnFacts)
            if case .failed(let why) = shield.step {
                // A failure in the attention ink, as every private send's.
                Text(verbatim: why).dsText(.body17).foregroundStyle(DS.attentionInk)
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

    /// **WHAT IT EARNS (prd §2004; user: "add the rate to tacit's make
    /// private sheet too").** What a share of the Tacit chain earned, as
    /// Olla's says it (§1970), and what a year of it would add to what
    /// arrives at that rate: figures, never a promise.
    private var earnFacts: [MoveDeckFacts.Fact] {
        guard let r = account.reading, let rate = account.earnRateOver(r), let pct = AaveLend.rateOnly(rate.apy) else { return [] }
        var out: [MoveDeckFacts.Fact] = [
            .init(name: String(localized: "Earned"), value: String(localized: "about \(pct) a year, last \(rate.days) days")),
            // How it comes back, as Aave's and Olla's say (prd §2005):
            // back to public lands in a few minutes (`TacitOutSheet`).
            .init(name: String(localized: "Take back"), value: String(localized: "any time, in a few minutes")),
        ]
        if let q = shield.quote, let arrives = TacitEngineWire.tac(q.arrives) {
            let year = NSDecimalNumber(decimal: arrives).doubleValue * rate.apy
            if year >= 0.0001 {
                let usd = account.tacPrice.map { LendMove.usd(year * $0) }
                out.append(.init(name: String(localized: "In a year"),
                                 value: usd.map { String(localized: "about \(Self.tacText(year)) (\($0)), at that rate") }
                                     ?? String(localized: "about \(Self.tacText(year)), at that rate")))
            }
        }
        return out
    }

    private var arrivesWords: String {
        guard let q = shield.quote, let arrives = TacitEngineWire.tac(q.arrives) else { return "—" }
        return Self.tacText(NSDecimalNumber(decimal: arrives).doubleValue)
    }

    /// All of it, never a hair more: rounded DOWN to the chain's eight
    /// places, no grouping, so the field parses back to at most what is held
    /// (Max wrote 4 significant digits rounded to nearest, and 1.7899 became
    /// 1.79: "More than it holds").
    /// Plain digits with a "." whatever the phone's locale (2026-11-27: a
    /// comma locale wrote "1,5", which the keys refuse to extend).
    static func maxText(_ held: Double) -> String {
        guard held > 0, var exact = Decimal(string: "\(held)") else { return "0" }
        var down = Decimal()
        NSDecimalRound(&down, &exact, 8, .down)
        return NSDecimalNumber(decimal: down).stringValue
    }

    static func tacText(_ v: Double) -> String {
        "\(v.formatted(.number.precision(.significantDigits(1...4)))) TAC"
    }

    // MARK: - Sending

    /// "1.5 TAC to Tacit", the sentence over the steps.
    private var sentenceWords: String {
        String(localized: "\(TacitAccountRows.amount(Double(shield.units) / 1e8)) TAC to Tacit")
    }

    /// Proved on this phone, the co-signer signs, Tacit takes it. Quiet: the
    /// shield says its own ending, never as Railgun's.
    @MainActor static var plan: PrivateSendSteps.Plan {
        PrivateSendSteps.Plan(steps: [
            .proving,
            .signing(onThisPhone: false),
            PrivateSendSteps.Step(key: .sent, running: String(localized: "Tacit is taking it"), done: String(localized: "Tacit took it")),
        ])
    }

    /// The run the steps draw, while this send goes.
    private var stepsRun: PrivateSendSteps.Run? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move, run.plan == Self.plan else { return nil }
        return run
    }

    /// The shield's step, told to the shared run.
    private func follow(_ step: TacitShield.Step) {
        let steps = PrivateSendSteps.shared
        switch step {
        case .proving:
            if stepsRun?.isRunning != true {
                steps.forget(.move)
                steps.begin(.move, plan: Self.plan, quiet: true)
            }
        case .signing: steps.mark(.signing)
        case .handing:
            steps.mark(.sent)
            // The co-signer has signed: nothing more asks you (prd §2003).
            if let onAway = shield.onAway, steps.sendAway(from: .tacitIn, landed: String(localized: "Made private on Tacit")) {
                onAway()
            }
        case .arriving, .landed: steps.finish()
        case .failed(let why): steps.fail(why)
        default: break
        }
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
            case .proving:
                MoveFootWord(word: String(localized: "Proving…"), ink: DS.textSecondary)
            case .signing:
                MoveFootWord(word: String(localized: "Waiting for your co-signer"), ink: DS.textSecondary)
            case .handing:
                MoveFootWord(word: String(localized: "Sending…"), ink: DS.textSecondary)
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
