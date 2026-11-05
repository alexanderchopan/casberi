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
struct MoveAztecGasSentence<Head: View>: View {
    var inTray = false
    var leave: () -> Void = {}
    @ViewBuilder let head: () -> Head

    enum Stage: Equatable { case ready, working(String), sent, failed(String) }

    enum Carry: String, CaseIterable { case usdc = "USDC", weth = "WETH", gas = "AZTEC" }

    @State private var carry: Carry = .usdc
    @State private var amount = "25"
    @State private var stage: Stage = .ready
    @State private var standing: ShieldBridge.Eligibility?
    private var store: AztecAccountStore { .shared }
    private var waiting: Int {
        (store.snapshot.gas ?? []).filter { !$0.claimed }.count + (store.snapshot.shield ?? []).filter { !$0.claimed }.count
    }
    private var amounts: [String] {
        switch carry { case .usdc: ["10", "25", "50"]; case .weth: ["0.005", "0.01", "0.025"]; case .gas: ["5", "10", "25"] }
    }
    private var asset: ShieldBridge.Asset? { ShieldBridge.assets.first { $0.symbol == carry.rawValue } }
    /// Shield's way needs its eligibility; gas never does.
    private var blocked: Bool { carry != .gas && standing?.eligible != true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                MoveFlow {
                    head()
                    MovePhrase("\(amount) \(carry.rawValue)", ink: DS.pickInk)
                    MovePhrase(String(localized: "to your Aztec account"), glue: String(localized: "to"))
                    MovePhrase(carry == .gas ? String(localized: "for gas.") : String(localized: "privately."))
                }
                HStack(spacing: DS.Space.s2) {
                    ForEach(Carry.allCases, id: \.self) { c in
                        Button {
                            withAnimation(DS.Motion.standard) { carry = c; amount = amounts[1] }
                        } label: { Chip(text: c == .gas ? String(localized: "AZTEC for gas") : c.rawValue, selected: c == carry) }
                        .buttonStyle(PressSpring())
                        .disabled(stage != .ready)
                    }
                }
                .padding(.top, DS.Space.s4)
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
        .task {
            // Where your account stands with Shield: public, read once.
            if let account = YourAccountKey.address, !DemoMode.isActive {
                standing = await ShieldBridge.eligibility(account)
            }
            // A deposit Aztec has carried is claimed while the sentence shows.
            while !Task.isCancelled {
                if waiting > 0 {
                    await AztecGas.settle()
                    await ShieldBridge.settle()
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private var line: String {
        switch stage {
        case .ready:
            if waiting > 0 { return String(localized: "On its way: Aztec carries it in minutes, then it is yours.") }
            if carry == .gas { return String(localized: "Gas pays for what your Aztec account does. It cannot be sent to anyone.") }
            guard let standing else { return String(localized: "Asking Shield where your account stands…") }
            if standing.sanctioned { return String(localized: "Shield will not take money from this account.") }
            if !standing.eligible {
                return String(localized: "Shield needs a Human Passport score of \(Int(standing.threshold)) for this account (no ID); it has \(Int(standing.score)). Up to $\(Int(standing.maxUSD)).")
            }
            return String(localized: "Arrives private in 5 to 15 minutes. Shield keeps 0.5%; up to $\(Int(standing.maxUSD)) in all.")
        case .working(let words): return words
        case .sent: return String(localized: "Sent. Aztec carries it in minutes; Holdings shows it when it lands.")
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
        case .ready: DemoMode.isActive ? "Not in the demo" : (blocked ? "Not yet" : "Send")
        case .working: "Sending…"
        case .sent: "Sent"
        case .failed: "Try again"
        }
    }

    @MainActor
    private func send() async {
        let decimals = asset?.decimals ?? 18
        guard let value = Decimal(string: amount) else { return }
        let units = NSDecimalNumber(decimal: value * pow(10, decimals)).stringValue
        stage = .working(String(localized: "Checking…"))
        let report: @Sendable (YourAccountChain.Stage) async -> Void = { s in
            await MainActor.run {
                stage = .working(s == .signing ? String(localized: "Confirm with Face ID") : String(localized: "Sending…"))
            }
        }
        do {
            if let asset, carry != .gas {
                _ = try await ShieldBridge.deposit(asset, units: units, stage: report)
            } else {
                _ = try await AztecGas.send(units: units, stage: report)
            }
            stage = .sent
            DSHaptic.success()
        } catch {
            stage = .failed(error.localizedDescription)
            try? await Task.sleep(for: .seconds(3))
            if case .failed = stage { stage = .ready }
        }
    }
}
