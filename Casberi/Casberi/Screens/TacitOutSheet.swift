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
    /// Another Tacit account (prd §1982): a private send, not back to public.
    var payTo: String? = nil
    /// The amount Again fills in (prd §1983).
    var startAmount: String? = nil
    /// Opened from Earn: Earn · Deposit · Withdraw in the title's place (prd §2005).
    var header: AnyView? = nil
    @State private var amount = ""
    /// $ | TAC (`TacitDollars`).
    @State private var inDollars = false
    @State private var dollars = ""
    @State private var toCoSigner = false
    /// The Tacit address being named after a send (prd §1983).
    @State private var saving: String?
    @State private var savingName = ""

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

    @Environment(\.moveBack) private var moveBack
    @Environment(ShellChrome.self) private var chrome
    /// The step whose list or keys stand in the deck (prd §1931).
    @State private var open: Open? = .amount
    private enum Open { case amount, to }

    /// **MOVE'S DECK, AS RAILGUN'S (prd §1983, §1927):** the lines are the
    /// sentence's words as chips, the amount on Move's own keys, then the
    /// receipt; while it goes, its steps; at the end, where it landed.
    var body: some View {
        MoveReceiptDeck(title: String(localized: "Send"), inTray: true, backDisabled: out.inFlight, back: {
            withAnimation(DS.Motion.standard) { moveBack?() ?? leave() }
        }, header: header, lines: {
            if !sending { MoveReceiptSteps(steps: deckSteps) }
        }, content: {
            Group {
                if open == .amount, !sending {
                    MoveDeckKeys {
                        MoveQuickKeys(keys: MoveQuickKeys.shares.map { p in
                            let text = TacitShieldSheet.maxText(most * Double(p) / 100)
                            return .share(p, on: amount == text) { inDollars = false; amount = text }
                        })
                        MoveKeypad(text: inDollars ? Binding(get: { dollars }, set: { dollars = $0; amount = TacitDollars.tac(fromUSD: $0) }) : $amount,
                                   places: inDollars ? 2 : 8, keyHeight: MoveSentence.bigKeyHeight, big: true)
                    }
                } else if open == .to, !sending {
                    deckList { toChoices }
                } else if sending {
                    // **THE SHARED STEPS (2026-11-27, the Move review: Tacit
                    // drew its own rows):** the sentence and `PrivateStepRows`,
                    // as Railgun's and Aztec's sends draw theirs; the finish
                    // under them.
                    MoveDeckStatus(linesStand: false, sentence: { MovePhrase(sentenceWords) }) {
                        if let run = stepsRun { PrivateStepRows(run: run).transition(.opacity) }
                        finish
                    }
                } else {
                    deckList { receipt }
                }
            }
        }, word: { foot })
        .animation(DS.Motion.standard, value: open)
        .alert("Save this Tacit address", isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } })) {
            TextField("Name", text: $savingName)
            Button("Save") {
                if let address = saving, !savingName.trimmingCharacters(in: .whitespaces).isEmpty {
                    AddressBook.shared.setName(savingName, for: address, networks: ["tacit"])
                    DSHaptic.success()
                }
                saving = nil
            }
            Button("Cancel", role: .cancel) { saving = nil }
        } message: {
            Text(verbatim: saving.map { AddressTail.short($0) } ?? "")
        }
        // **THE SCAN STARTS WITH THE SHEET (2026-11-27, user: "it says
        // reading the fee, which takes a while, a long while").** A quote
        // scans the chain for your notes first; the engine keeps what it
        // scanned, so one scan while you type makes your own quote quick.
        .task {
            guard TacitEngine.shared.isOpen, out.quote == nil, !DemoMode.isActive else { return }
            let t = Date()
            _ = try? await (payTo == nil ? TacitEngine.shared.outQuote(units: 1) : TacitEngine.shared.payQuote(units: 1))
            NSLog("tacitOut| scanned ahead in %.1f s", Date().timeIntervalSince(t))
        }
        .task(id: amount) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !sending, let tac, tac > 0, tac <= held else { return }
            await out.quote(tac: tac)
        }
        .task(id: to) {
            if let to { await out.readOwed(to) }
        }
        // The shared steps follow the send's own (2026-11-27).
        .onChange(of: out.step) { _, now in follow(now) }
        // The rate Withdraw says (prd §2005), read once an hour.
        .task { if payTo == nil { await TacitAccount.shared.readChainYield() } }
        // In Move's tray the send goes behind it (prd §2003).
        .onAppear { out.onAway = chrome.moveTray ? { chrome.moveTray = false } : nil }
        .onAppear {
            out.payTo = payTo
            out.reset()
            // Again fills its amount; otherwise it opens empty, as every Move
            // page does: Max is a key (2026-11-27).
            if amount.isEmpty, let startAmount { amount = startAmount }
        }
    }

    private var sending: Bool {
        switch out.step {
        case .proving, .handing, .landing, .collecting, .done: return true
        default: return false
        }
    }

    // MARK: - The deck

    private var deckSteps: [MoveDeckStep] {
        let mark = MoveRowMark(token: "TAC")
        var out: [MoveDeckStep] = [
            MoveDeckStep(id: "from", word: String(localized: "From"), answered: true, value: "Tacit", glyph: "lock.fill") { leave() },
        ]
        if let payTo {
            // A saved name keeps its tail, to check by (as Railgun's §1965a).
            let name = AddressBook.shared.name(for: payTo).map { "\($0) · \(AddressTail.short(payTo))" } ?? AddressTail.short(payTo)
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), answered: true, value: name) { leave() })
        } else {
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), on: open == .to, answered: true,
                                    value: toCoSigner ? String(localized: "Co-signer") : String(localized: "Your public account")) { toggle(.to) })
        }
        out.append(MoveDeckStep(id: "token", word: String(localized: "Token"), answered: true,
                                value: payTo == nil ? "TAC · Ethereum" : "TAC · Tacit chain", mark: mark, fixed: true) {})
        out.append(MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: open == .amount, answered: !amount.isEmpty,
                                value: TacitDollars.value(amount: amount, dollars: dollars, inDollars: inDollars, typing: open == .amount),
                                accessory: TacitDollars.price == nil ? nil : AnyView(MoveUnitSwitch(symbol: "TAC", dollars: inDollars) { on in
                                    withAnimation(DS.Motion.standard) {
                                        inDollars = on
                                        if on { dollars = TacitDollars.usd(fromTAC: amount) }
                                    }
                                }),
                                fieldNote: TacitDollars.note(amount: amount, have: TacitShieldSheet.maxText(most), inDollars: inDollars)) { toggle(.amount) })
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

    /// Where back to public lands: your Casberi account or your co-signer.
    @ViewBuilder private var toChoices: some View {
        // Named as Move names it everywhere (prd §1986 item 3).
        toRow(String(localized: "Your public account"), picked: !toCoSigner) { pick(false) }
        if coSigner != nil {
            toRow(String(localized: "Co-signer"), picked: toCoSigner) { pick(true) }
        }
    }

    private func toRow(_ name: String, picked: Bool, act: @escaping () -> Void) -> some View {
        Button {
            act()
            withAnimation(DS.Motion.standard) { open = .amount }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: name).dsText(.body17).foregroundStyle(picked ? DS.pickInk : DS.textPrimary)
                Spacer(minLength: DS.Space.s2)
                if picked { Image(systemName: "checkmark").dsGlyph(.body, weight: .semibold).foregroundStyle(DS.pickInk) }
            }
            .frame(minHeight: MoveDeck.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }

    /// **WHAT IT EARNED, WITHDRAWING (prd §2005), as Aave's and Olla's say
    /// it:** the TAC the Tacit chain's fees added to your shares since this
    /// phone first knew the rate, and the rate it earns.
    private var earnFacts: [MoveDeckFacts.Fact] {
        guard let r = account.reading else { return [] }
        var out: [MoveDeckFacts.Fact] = []
        if let earned = r.earnedTAC, earned >= 0.0001, let since = r.earnedSince {
            let usd = account.tacPrice.map { LendMove.usd(earned * $0) }
            let day = since.formatted(.dateTime.month(.abbreviated).day())
            let tac = "\(TacitAccountRows.amount(earned)) TAC"
            out.append(.init(name: String(localized: "Earned"),
                             value: usd.map { String(localized: "\(tac) (\($0)) since \(day)") } ?? String(localized: "\(tac) since \(day)")))
        }
        if let rate = account.earnRateOver(r), let pct = AaveLend.rateOnly(rate.apy) {
            out.append(.init(name: String(localized: "Earns"), value: String(localized: "about \(pct) a year, last \(rate.days) days")))
        }
        return out
    }

    /// The receipt under the lines: Tacit's fee and when it lands, as every
    /// private send's facts (`MoveDeckFacts`).
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            MoveDeckFacts(facts: [
                MoveDeckFacts.Fact(name: String(localized: "Fee"), value: feeWords),
                MoveDeckFacts.Fact(name: String(localized: "Arrives"),
                                   value: payTo == nil ? String(localized: "In a few minutes") : String(localized: "In about a minute")),
            ] + (payTo == nil ? earnFacts : []))
            // **HOW HIDDEN, WHERE YOU SEND (prd §1983, as Privacy Pools'
            // §1738):** the notes on the Tacit chain at the last reading, the
            // crowd this send's note is one of. It advises, never blocks.
            if let notes = account.reading?.chainNotes {
                Text("Hidden among \(notes.formatted()) notes on the Tacit chain")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .failed(let why) = out.step {
                // A failure in the attention ink, as every private send's.
                Text(verbatim: why).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pick(_ coSignerPicked: Bool) {
        DSHaptic.selection()
        toCoSigner = coSignerPicked
    }

    private var feeWords: String {
        guard let q = out.quote, let fee = TacitEngineWire.tac(q.fee) else { return "—" }
        let text = TacitShieldSheet.tacText(NSDecimalNumber(decimal: fee).doubleValue)
        // A pay stays on the Tacit chain: no Ethereum fee.
        return payTo == nil ? String(localized: "\(text) and the network fee") : text
    }

    // MARK: - Sending

    /// "1.5 TAC to your public account", the sentence over the steps.
    private var sentenceWords: String {
        let place = payTo.map { AddressTail.short($0) } ?? (toCoSigner ? String(localized: "Co-signer") : String(localized: "your public account"))
        return String(localized: "\(TacitAccountRows.amount(Double(out.units) / 1e8)) TAC to \(place)")
    }

    /// Proved on this phone, Tacit takes it, then (back to public) your
    /// account collects it. Quiet: the send says its own ending.
    @MainActor static func plan(collects: Bool) -> PrivateSendSteps.Plan {
        var steps: [PrivateSendSteps.Step] = [
            .proving,
            PrivateSendSteps.Step(key: .sent, running: String(localized: "Tacit is taking it"), done: String(localized: "Tacit took it")),
        ]
        if collects {
            steps.append(PrivateSendSteps.Step(key: .signing, running: String(localized: "Claiming"), done: String(localized: "Claimed")))
        }
        return PrivateSendSteps.Plan(steps: steps)
    }

    /// The run the steps draw, while this send goes.
    private var stepsRun: PrivateSendSteps.Run? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move, run.plan == Self.plan(collects: payTo == nil) else { return nil }
        return run
    }

    /// The send's step, told to the shared run.
    private func follow(_ step: TacitOut.Step) {
        let steps = PrivateSendSteps.shared
        switch step {
        case .proving:
            if stepsRun?.isRunning != true {
                steps.forget(.move)
                steps.begin(.move, plan: Self.plan(collects: payTo == nil), quiet: true)
                // Proving needs nobody (prd §2003): the capsule says the rest.
                if let onAway = out.onAway,
                   steps.sendAway(from: .tacitOut, landed: payTo == nil ? String(localized: "Back in your account") : String(localized: "Sent from Tacit")) {
                    onAway()
                }
            }
        case .handing, .landing: steps.mark(.sent)
        case .collecting: steps.mark(.signing)
        case .done: steps.finish()
        case .failed(let why): steps.fail(why)
        default: break
        }
    }

    @ViewBuilder private var finish: some View {
        // **SAY WHERE IT LANDED (user, 2026-11-25: "it said success but i
        // can't tell if it worked or not").** The amount paid out and the
        // place, and what that place now holds.
        if case .done = out.step, let paid = out.paidTAC, let payTo {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // One finish for every private move (prd §1990).
                PrivateFinishLines(headline: PrivateFinish.headline("\(TacitAccountRows.amount(paid)) TAC",
                                                                    to: .theirPrivate(PrivateFinish.who(payTo))))
                    .onAppear { chrome.rain(sources: ["Wallet"]) }
                // **SAVE WHO YOU PAID (prd §1983, as Railgun's §1965):** one
                // field, the address under it; the book files it as Tacit's.
                if AddressBook.shared.name(for: payTo) == nil {
                    Button {
                        savingName = ""
                        saving = payTo
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            Text("Save \(AddressTail.short(payTo))").dsText(.heading17).foregroundStyle(DS.pickInk)
                            Spacer(minLength: DS.Space.s2)
                        }
                        .frame(minHeight: DSFeed.headHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.Space.s6)
        } else if case .done = out.step, let paid = out.paidTAC {
            let place = toCoSigner ? String(localized: "your co-signer") : String(localized: "your public account")
            let now = toCoSigner ? account.reading?.publicTAC : account.reading?.accountTAC
            // Sent, not yet seen: on its way, never "is in" (prd §1988).
            PrivateFinishLines(headline: PrivateFinish.headline("\(TacitAccountRows.amount(paid)) TAC",
                                                                to: toCoSigner ? .yours(place) : .yourPublic,
                                                                onItsWay: out.paidPending),
                               note: out.paidPending ? nil : now.map { String(localized: "It holds \(TacitAccountRows.amount($0)) TAC now") })
                .onAppear { chrome.rain(sources: ["Wallet"]) }
            .padding(.top, DS.Space.s6)
        }
    }

    // MARK: - The foot

    @ViewBuilder private var foot: some View {
        Group {
            switch out.step {
            case .ready:
                MoveHoldWord(word: DemoMode.isActive ? String(localized: "Not in the demo") : String(localized: "Hold to send"),
                             enabled: canSend) {
                    guard let to else { return }
                    Task { await out.send(to: to) }
                }
            case .done:
                MoveFootWord(word: String(localized: "Done")) { out.finish(); leave() }
            case .failed:
                // After a withdrawal was handed, never a second one from here:
                // Collect, which reads what is owed again.
                if payTo == nil, out.owedWei > 0 || out.handed {
                    MoveFootWord(word: String(localized: "Claim")) { Task { await out.collectOwed() } }
                } else {
                    MoveFootWord(word: String(localized: "Try again")) {
                        out.reset()
                        if let tac { Task { await out.quote(tac: tac) } }
                    }
                }
            case .proving:
                MoveFootWord(word: String(localized: "Proving…"), ink: DS.textSecondary)
            case .handing, .landing:
                MoveFootWord(word: String(localized: "Sending…"), ink: DS.textSecondary)
            case .collecting:
                MoveFootWord(word: String(localized: "Claiming…"), ink: DS.textSecondary)
            default:
                if payTo == nil, out.owedWei > 0 {
                    // Owed from an earlier try: collected before anything new.
                    MoveFootWord(word: String(localized: "Claim")) { Task { await out.collectOwed() } }
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
