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
    @State private var amount = ""
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
        }, lines: {
            if !sending { MoveReceiptSteps(steps: deckSteps) }
        }, content: {
            Group {
                if open == .amount, !sending {
                    MoveDeckKeys {
                        MoveQuickKeys(keys: MoveQuickKeys.shares.map { p in
                            let text = TacitShieldSheet.maxText(most * Double(p) / 100)
                            return .share(p, on: amount == text) { amount = text }
                        })
                        MoveKeypad(text: $amount, places: 8, keyHeight: MoveSentence.bigKeyHeight, big: true)
                    }
                } else if open == .to, !sending {
                    deckList { toChoices }
                } else {
                    deckList { if sending { steps } else { receipt } }
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
        .task(id: amount) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !sending, let tac, tac > 0, tac <= held else { return }
            await out.quote(tac: tac)
        }
        .task(id: to) {
            if let to { await out.readOwed(to) }
        }
        .onAppear {
            out.payTo = payTo
            out.reset()
            if amount.isEmpty, let startAmount { amount = startAmount }
            if amount.isEmpty, held > 0 { amount = TacitShieldSheet.maxText(held) }
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
                                value: payTo == nil ? "TAC · Ethereum" : "TAC · Tacit chain", mark: mark) {})
        out.append(MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: open == .amount, answered: !amount.isEmpty,
                                value: amount.isEmpty ? (open == .amount ? "0 TAC" : nil) : "\(amount) TAC",
                                fieldNote: MoveFieldNote.against(typed: amount, have: TacitShieldSheet.maxText(most), symbol: "TAC")) { toggle(.amount) })
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

    /// The receipt under the lines: Tacit's fee and when it lands.
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            MoveReceiptLine(label: String(localized: "Fee")) {
                Text(verbatim: feeWords).dsText(.body17).monospacedDigit().foregroundStyle(DS.textPrimary)
            }
            MoveReceiptLine(label: String(localized: "Arrives")) {
                Text(payTo == nil ? "In a few minutes" : "In about a minute").dsText(.body17).foregroundStyle(DS.textPrimary)
            }
            // **HOW HIDDEN, WHERE YOU SEND (prd §1983, as Privacy Pools'
            // §1738):** the notes on the Tacit chain at the last reading, the
            // crowd this send's note is one of. It advises, never blocks.
            if let notes = account.reading?.chainNotes {
                Text("Hidden among \(notes.formatted()) notes on the Tacit chain")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .failed(let why) = out.step {
                Text(verbatim: why).dsText(.body17).foregroundStyle(DS.destructiveInk)
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
        return payTo == nil ? String(localized: "\(text) and network fee") : text
    }

    // MARK: - Sending

    @ViewBuilder private var steps: some View {
        // One sentence, so a long place wraps as words do (prd §1986 item 3).
        (Text(verbatim: "\(TacitAccountRows.amount(Double(out.units) / 1e8)) TAC ").foregroundStyle(DS.textPrimary)
            + Text("to ").foregroundStyle(DS.textPrimary)
            + Text(verbatim: payTo.map { AddressTail.short($0) } ?? (toCoSigner ? String(localized: "Co-signer") : String(localized: "your public account"))).foregroundStyle(DS.pickInk))
        .dsText(.heading34)
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                step(String(localized: "Proved"), state: state(for: 0),
                     figure: out.provingSince.map { "\(Int(context.date.timeIntervalSince($0))) s" })
            }
            step(String(localized: "Tacit takes it"), state: state(for: 1), figure: nil)
            if payTo == nil {
                step(String(localized: "Collected"), state: state(for: 2), figure: nil)
            }
        }
        .padding(.top, DS.Space.s6)
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

    private enum StepState { case waiting, now, done }

    private func state(for index: Int) -> StepState {
        let at: Int
        switch out.step {
        case .proving: at = 0
        case .handing, .landing: at = 1
        case .collecting: at = 2
        case .done: at = payTo == nil ? 3 : 2
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
                if payTo == nil, out.owedWei > 0 {
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
