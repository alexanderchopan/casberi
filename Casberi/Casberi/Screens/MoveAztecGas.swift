import SwiftUI

/// **SEND TO YOUR AZTEC ACCOUNT (prd §1700e).** Picked from Send's
/// recipients ("Your Aztec account"); its own sentence, as Lend's and a fresh
/// Receive's are. Three things it can carry:
///   - USDC or WETH through Shield (`ShieldBridge`): the line says where your
///     account stands with Shield (its public eligibility) before anything is
///     asked; then Shield's signed limit (signing in with the Safe), the Safe's
///     deposit, and the private claim on Aztec minutes later.
///   - AZTEC as gas through Aztec's own Fee Juice portal (`AztecGas`), open
///     and unchecked; gas pays for transactions and cannot be sent on.
/// And back out (prd §1700b): USDC or WETH from your Aztec account to your
/// account on Ethereum through Shield (`ShieldBridge.exit`), proved here; an
/// hour or more later Aztec's proof is on Ethereum and Finish withdraws it.
struct MoveAztecGasSentence<Head: View>: View {
    var inTray = false
    var leave: () -> Void = {}
    @ViewBuilder let head: () -> Head

    enum Stage: Equatable { case ready, working(String), sent, failed(String) }

    enum Carry: String, CaseIterable { case usdc = "USDC", weth = "WETH", gas = "AZTEC" }

    @State private var out = false
    @State private var carry: Carry = .usdc
    /// An exit Aztec's proof has reached Ethereum with, ready to finish.
    @State private var ready: AztecAccountStore.ShieldExit?
    @State private var finished = false
    @State private var passport = false
    /// Human Passport's app, where your account earns the score Shield asks for.
    private var passportApp: URL { URL(string: "https://app.passport.xyz")! }
    @State private var amount = "25"
    @State private var stage: Stage = .ready
    @State private var standing: ShieldBridge.Eligibility?
    private var store: AztecAccountStore { .shared }
    private var waiting: Int {
        (store.snapshot.gas ?? []).filter { !$0.claimed }.count + (store.snapshot.shield ?? []).filter { !$0.claimed }.count
    }
    private var exiting: [AztecAccountStore.ShieldExit] { (store.snapshot.exits ?? []).filter { !$0.withdrawn } }
    private var carries: [Carry] { out ? [.usdc, .weth] : Carry.allCases }
    /// What your Aztec account holds of the token, privately (last reading).
    private var held: (units: String, decimals: Int)? {
        guard let h = store.shown.holdings.first(where: { $0.name == carry.rawValue && $0.kind == .token }),
              let p = h.privateUnits, let d = h.decimals else { return nil }
        return (p, d)
    }
    private var units: String? {
        guard let value = Decimal(string: amount), value > 0 else { return nil }
        return NSDecimalNumber(decimal: value * pow(10, asset?.decimals ?? 18)).stringValue
    }
    private var enough: Bool {
        guard let units, let held, let have = Decimal(string: held.units), let want = Decimal(string: units) else { return false }
        return want <= have
    }
    private var amounts: [String] {
        switch carry { case .usdc: ["10", "25", "50"]; case .weth: ["0.005", "0.01", "0.025"]; case .gas: ["5", "10", "25"] }
    }
    private var asset: ShieldBridge.Asset? { ShieldBridge.assets.first { $0.symbol == carry.rawValue } }
    /// Shield's way needs its eligibility; gas never does.
    private var blocked: Bool {
        if ready != nil { return false }
        if out { return standing?.eligible != true || !enough || !AztecProver.isAvailable }
        return carry != .gas && standing?.eligible != true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                MoveFlow {
                    head()
                    MovePhrase("\(amount) \(carry.rawValue)", ink: DS.pickInk)
                    if out {
                        MovePhrase(String(localized: "from your Aztec account"), glue: String(localized: "from"))
                        MovePhrase(String(localized: "to your account."), glue: String(localized: "to"))
                    } else {
                        MovePhrase(String(localized: "to your Aztec account"), glue: String(localized: "to"))
                        MovePhrase(carry == .gas ? String(localized: "for gas.") : String(localized: "privately."))
                    }
                }
                HStack(spacing: DS.Space.s2) {
                    ForEach([false, true], id: \.self) { o in
                        Button {
                            withAnimation(DS.Motion.standard) {
                                out = o
                                if o, carry == .gas { carry = .usdc; amount = amounts[1] }
                            }
                        } label: { Chip(text: o ? String(localized: "Out of Aztec") : String(localized: "Into Aztec"), selected: o == out) }
                        .buttonStyle(PressSpring())
                        .disabled(stage != .ready)
                    }
                }
                .padding(.top, DS.Space.s4)
                HStack(spacing: DS.Space.s2) {
                    ForEach(carries, id: \.self) { c in
                        Button {
                            withAnimation(DS.Motion.standard) { carry = c; amount = amounts[1] }
                        } label: { Chip(text: c == .gas ? String(localized: "AZTEC for gas") : c.rawValue, selected: c == carry) }
                        .buttonStyle(PressSpring())
                        .disabled(stage != .ready)
                    }
                }
                .padding(.top, DS.Space.s2)
                HStack(spacing: DS.Space.s2) {
                    ForEach(amounts, id: \.self) { a in
                        Button { withAnimation(DS.Motion.standard) { amount = a } } label: {
                            Chip(text: "\(a) \(carry.rawValue)", selected: a == amount)
                        }
                        .buttonStyle(PressSpring())
                        .disabled(stage != .ready)
                    }
                }
                .padding(.top, DS.Space.s2)
                Text(line)
                    .dsText(.subhead12)
                    .foregroundStyle(lineInk)
                    .padding(.top, DS.Space.s3)
                if carry != .gas, ready == nil, stage == .ready, let standing, !standing.eligible, !standing.sanctioned {
                    // The score is earned on Human Passport's own page, with
                    // this account connected there as itself (no ID).
                    DSDoorRow(icon: "person.badge.shield.checkmark", label: "Raise your score on Human Passport") { passport = true }
                        .padding(.top, DS.Space.s2)
                }
                HStack(spacing: DS.Space.s1) {
                    ProtocolInlineMark(mark: "aztec")
                    Text(carry == .gas ? "Powered by Aztec" : "Powered by Shield").dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
                .padding(.top, DS.Space.s2)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .sheet(isPresented: $passport, onDismiss: {
            Task { if let account = YourAccountKey.address { standing = await ShieldBridge.eligibility(account) } }
        }) {
            AztecBrowserView(url: passportApp, aztec: false, ethereum: true)
                .presentationDragIndicator(.visible)
        }
        .task {
            // Where your account stands with Shield: public, read once.
            if let account = YourAccountKey.address, !DemoMode.isActive {
                standing = await ShieldBridge.eligibility(account)
            }
            if AztecProver.isAvailable, !DemoMode.isActive { await store.refresh() }
            // A deposit Aztec has carried is claimed while the sentence shows,
            // and an exit whose proof is on Ethereum is offered to finish.
            while !Task.isCancelled {
                if waiting > 0 {
                    await AztecGas.settle()
                    await ShieldBridge.settle()
                }
                var next: AztecAccountStore.ShieldExit?
                for e in exiting where next == nil {
                    switch await ShieldBridge.state(of: e) {
                    case .ready: next = e
                    case .done: AztecAccountStore.shared.markExitWithdrawn(e.transaction, withdrawal: "consumed")
                    case .waiting: break
                    }
                }
                if stage == .ready { ready = next }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private var line: String {
        switch stage {
        case .ready:
            if let ready {
                let figure = PrivateMoney.figure(ready.amountUnits, decimals: ShieldBridge.assets.first { $0.symbol == ready.symbol }?.decimals ?? 18, symbol: ready.symbol)
                return String(localized: "\(figure) from Aztec is ready on Ethereum. Finish takes it to your account.")
            }
            if out {
                if !exiting.isEmpty { return String(localized: "On its way: Aztec's proof reaches Ethereum in an hour or so, then Finish here.") }
                guard let standing else { return String(localized: "Asking Shield where your account stands…") }
                if standing.sanctioned { return String(localized: "Shield will not move money for this account.") }
                if !standing.eligible {
                    return String(localized: "Shield needs a Human Passport score of \(Int(standing.threshold)) for this account (no ID); it has \(Int(standing.score)).")
                }
                guard let held else { return String(localized: "Your Aztec account holds no \(carry.rawValue).") }
                let have = PrivateMoney.figure(held.units, decimals: held.decimals, symbol: carry.rawValue)
                return enough || units == nil
                    ? String(localized: "You have \(have) privately. About 20 seconds to prove here, then an hour or so until you can finish.")
                    : String(localized: "You have \(have) privately on Aztec.")
            }
            if waiting > 0 { return String(localized: "On its way: Aztec carries it in minutes, then it is yours.") }
            if carry == .gas { return String(localized: "Gas pays for what your Aztec account does. It cannot be sent to anyone.") }
            guard let standing else { return String(localized: "Asking Shield where your account stands…") }
            if standing.sanctioned { return String(localized: "Shield will not take money from this account.") }
            if !standing.eligible {
                return String(localized: "Shield needs a Human Passport score of \(Int(standing.threshold)) for this account (no ID); it has \(Int(standing.score)). Up to $\(Int(standing.maxUSD)).")
            }
            return String(localized: "Arrives private in 5 to 15 minutes. Shield keeps 0.5%; up to $\(Int(standing.maxUSD)) in all.")
        case .working(let words): return words
        case .sent:
            if finished { return String(localized: "Finished: it is in your account on Ethereum.") }
            if out { return String(localized: "Sent out of Aztec. In an hour or so Aztec's proof reaches Ethereum; finish it here then.") }
            return String(localized: "Sent. Aztec carries it in minutes; Holdings shows it when it lands.")
        case .failed(let why): return why
        }
    }

    private var lineInk: Color {
        if case .failed = stage { return DS.destructiveInk }
        return DS.textSecondary
    }

    private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { leave() } label: {
                Text("Back").dsText(.heading24).foregroundStyle(DS.textSecondary).frame(minHeight: 48)
            }
            .buttonStyle(RowPress())
            Spacer(minLength: DS.Space.s3)
            Button { Task { await send() } } label: {
                Text(footWord).dsText(.heading34).foregroundStyle(stage == .ready ? DS.pickInk : DS.textSecondary)
                    .frame(minHeight: 48, alignment: .trailing)
            }
            .buttonStyle(RowPress())
            .disabled(stage != .ready || DemoMode.isActive || blocked)
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.vertical, DS.Space.s2)
    }

    private var footWord: LocalizedStringKey {
        switch stage {
        case .ready:
            if DemoMode.isActive { "Not in the demo" }
            else if ready != nil { "Finish" }
            else if out, units != nil, held != nil, !enough { "Not enough" }
            else if blocked { "Not yet" }
            else { "Send" }
        case .working: "Sending…"
        case .sent: "Sent"
        case .failed: "Try again"
        }
    }

    @MainActor
    private func send() async {
        guard let units else { return }
        stage = .working(String(localized: "Checking…"))
        let report: @Sendable (YourAccountChain.Stage) async -> Void = { s in
            await MainActor.run {
                stage = .working(s == .signing ? String(localized: "Confirm with Face ID") : String(localized: "Sending…"))
            }
        }
        do {
            if let finishing = ready {
                try await ShieldBridge.finish(finishing, stage: report)
                ready = nil
                finished = true
            } else if out, let asset {
                stage = .working(String(localized: "Proving on this iPhone…"))
                _ = try await ShieldBridge.exit(asset, units: units)
            } else if let asset, carry != .gas {
                _ = try await ShieldBridge.deposit(asset, units: units, stage: report)
            } else {
                _ = try await AztecGas.send(units: units, stage: report)
            }
            stage = .sent
            DSHaptic.success()
        } catch {
            stage = .failed(AztecEngine.words(error))
            try? await Task.sleep(for: .seconds(3))
            if case .failed = stage { stage = .ready }
        }
    }
}
