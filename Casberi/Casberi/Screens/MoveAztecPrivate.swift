import SwiftUI
import Observation
import SwiftData

/// **YOUR PRIVATE BALANCE ON AZTEC, IN SEND (prd §1700f items 11–14).** The
/// same sentence 0xBow's private balance has (`MovePrivateSentence`), for
/// your Aztec account:
///
/// - **In** (`.deposit`): picked as "Your private account · Aztec" among
///   Send's recipients. "Send 2 USDC to your private account on Aztec." Your
///   Safe deposits through Shield (USDC or WETH), gas riding along in the
///   same operation when the account needs it; the claim on Aztec follows.
///   Or it says what stands in the way: "Fund …ca8d on Ethereum first.", or
///   "Shield needs a Human Passport score of 20 first." with Human Passport in
///   the foot (the only door a Casberi Safe has to a score).
/// - **From** (`.send`): picked as "Aztec · Private" in Send's networks.
///   "Send 2 USDC from your private account on Aztec to …4f38." An Aztec
///   address is a private send inside Aztec; an Ethereum address, anyone's,
///   is out through Shield, finished from Needs you. Either asks the
///   co-signer first (`AztecCoSign`). Any token the account can send
///   privately is offered, by its contract (prd §1711 item 3); only Shield's
///   USDC and WETH can leave.
/// - **Checked first** (prd §1711 items 4, 5): an Aztec address must be one
///   anyone can receive at (Aztec's own `isValid`), and one you never paid,
///   or one that looks like one you did, is said; an Ethereum address gets
///   every check Move's Send makes (`MoveChecks.recipient`). A warning makes
///   the verb "Send anyway", a second tap.
///
/// No chips, no direction to choose: the place you send to or from says it.
@MainActor
@Observable
final class AztecMove {
    enum Mode: Equatable { case deposit, send }

    enum Stage: Equatable {
        case reading
        /// Your Safe holds too little to move in (or gas is short and it
        /// holds no AZTEC for it).
        case needsFunds(address: String)
        /// Shield will not take it: below the Passport score, or sanctioned.
        case shieldNo(score: Int, threshold: Int, sanctioned: Bool)
        /// Nothing private on Aztec to send from yet.
        case nothingPrivate
        /// Your Aztec account has no gas for a send of its own.
        case needsGas
        case ready
        case working(String)
        case done(String)
        case failed(String)
    }

    struct Option: Equatable, Identifiable {
        let symbol: String
        let amount: String
        /// The token's contract on Aztec, for a send from your private
        /// account; nil for a deposit, which is Shield's asset by symbol.
        let token: String?
        let decimals: Int
        var id: String { (token ?? symbol) + " " + amount }

        init(symbol: String, amount: String, token: String? = nil, decimals: Int? = nil) {
            self.symbol = symbol
            self.amount = amount
            self.token = token
            self.decimals = decimals ?? (symbol == "USDC" ? 6 : 18)
        }
    }

    var mode: Mode = .deposit
    var stage: Stage = .reading
    var symbol = "USDC"
    var amount = ""
    /// The picked token's contract on Aztec and its decimals (a send).
    private(set) var token: String?
    private var pickedDecimals: Int?
    var recipient: String?
    /// What the recipient was checked against, and for whom (prd §1711).
    private(set) var findings: [MoveWarnings.Finding] = []
    private(set) var findingsFor: String?
    /// The recipient whose warning the first tap on "Send anyway" armed.
    private(set) var armed: String?
    private(set) var options: [Option] = []
    /// What the Safe holds on Ethereum, base units, by symbol.
    private(set) var safeHeld: [String: String] = [:]
    /// Whether a deposit brings gas along (the account is short of it).
    private(set) var bringsGas = false
    private(set) var maxUSD: Double?

    var decimals: Int { pickedDecimals ?? (symbol == "USDC" ? 6 : 18) }
    /// Shield's asset for what is picked: by symbol for a deposit, by the
    /// token's pinned contract for a send (`AztecAccountStore.priced`),
    /// never by a name any app's token can take.
    var asset: ShieldBridge.Asset? {
        guard let token else { return ShieldBridge.assets.first { $0.symbol == symbol } }
        guard let coin = AztecAccountStore.priced[token.lowercased()] else { return nil }
        return ShieldBridge.assets.first { $0.symbol.lowercased() == coin }
    }
    /// Only Shield's USDC and WETH can leave Aztec.
    var cannotLeave: Bool { mode == .send && toEthereum && asset == nil }
    var units: String? { PrivateMoney.baseUnits(amount, decimals: decimals) }
    var acting: Bool { if case .working = stage { true } else { false } }

    /// Whether `recipient` is an Aztec account (a private send) or an
    /// Ethereum address (out through Shield).
    var toAztec: Bool { recipient.map(AztecAddressText.isAztec) ?? false }
    var toEthereum: Bool { recipient.map(PrivateMoney.isAddress) ?? false }

    static let usdcSteps = ["1", "2", "5", "10", "25", "50", "100", "250", "500", "1000"]
    static let wethSteps = ["0.0005", "0.001", "0.0025", "0.005", "0.01", "0.025", "0.05", "0.1"]

    func pick(_ amount: String, of symbol: String) {
        self.symbol = symbol
        self.amount = amount
        token = nil
        pickedDecimals = nil
    }

    func pick(_ option: Option) {
        symbol = option.symbol
        amount = option.amount
        token = option.token
        pickedDecimals = option.decimals
    }

    /// Amounts a token without Shield's steps offers: 1, 2 and 5 at every
    /// power of ten up to what is held, the last seven, then all of it.
    static func steps(upTo held: Decimal) -> [String] {
        guard held > 0 else { return [] }
        var all: [String] = []
        for k in -6...9 {
            for m in ["1", "2", "5"] {
                all.append(k < 0 ? "0." + String(repeating: "0", count: -k - 1) + m : m + String(repeating: "0", count: k))
            }
        }
        var out = Array(all.filter { (Decimal(string: $0) ?? 0) <= held }.suffix(7))
        let whole = "\(held)"
        if out.last.flatMap({ Decimal(string: $0) }) != held, whole.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil {
            out.append(whole)
        }
        return out
    }

    /// Whether Casberi can send a held token privately: the engine read a
    /// private transfer off its interface; a reading made before it said
    /// trusts Shield's two tokens alone.
    static func sendable(_ h: AztecAccountStore.Holding) -> Bool {
        h.sendable ?? (AztecAccountStore.priced[h.address.lowercased()] != nil)
    }

    /// Where the move stands: balances, Shield's word, the account's gas.
    func read() async {
        stage = .reading
        // A deposit is Shield's asset by symbol, never a send's token.
        if mode == .deposit { token = nil; pickedDecimals = nil }
        if DemoMode.isActive {
            options = (Self.usdcSteps.prefix(3)).map { Option(symbol: "USDC", amount: $0) }
            if amount.isEmpty { pick("2", of: "USDC") }
            stage = .ready
            return
        }
        guard let safe = YourAccountKey.address else { stage = .failed(String(localized: "There is no account on this iPhone")); return }
        switch mode {
        case .deposit:
            async let standing = ShieldBridge.eligibility(safe)
            var held: [String: String] = [:]
            for asset in ShieldBridge.assets { held[asset.symbol] = await Self.balance(of: asset.ethToken, at: safe) }
            held["AZTEC"] = await Self.balance(of: AztecGas.token, at: safe)
            safeHeld = held
            bringsGas = AztecProver.isAvailable && AztecGas.needed
            options = depositOptions(held)
            guard let standing = await standing else { stage = .failed(String(localized: "Shield did not answer")); return }
            maxUSD = standing.maxUSD
            if standing.sanctioned || !standing.eligible {
                stage = .shieldNo(score: Int(standing.score), threshold: Int(standing.threshold), sanctioned: standing.sanctioned)
                return
            }
            let gasShort = bringsGas && (Decimal(string: held["AZTEC"] ?? "0") ?? 0) < (Decimal(string: AztecGas.rideAlong) ?? 0)
            if options.isEmpty || gasShort { stage = .needsFunds(address: safe); return }
            if !options.contains(where: { $0.symbol == symbol && $0.amount == amount }), let first = options.first {
                pick(options.count > 1 ? options[1].amount : first.amount, of: first.symbol)
            }
            stage = .ready
        case .send:
            if AztecProver.isAvailable { await AztecAccountStore.shared.refresh() }
            let store = AztecAccountStore.shared
            // Every token it can send, by its contract (prd §1711 item 3).
            options = store.privateHeld.filter(Self.sendable).flatMap { h -> [Option] in
                guard let units = h.privateUnits, let have = Decimal(string: units), let d = h.decimals else { return [] }
                let steps = switch AztecAccountStore.priced[h.address.lowercased()] {
                case "usdc"?: Self.usdcSteps
                case "weth"?: Self.wethSteps
                default: Self.steps(upTo: have / pow(10, d))
                }
                return steps.filter { (Decimal(string: $0) ?? 0) * pow(10, d) <= have }
                    .map { Option(symbol: h.name, amount: $0, token: h.address, decimals: d) }
            }
            if options.isEmpty { stage = .nothingPrivate; return }
            if AztecGas.needed { stage = .needsGas; return }
            if !options.contains(where: { $0.token == token && $0.amount == amount }), let first = options.first {
                pick(first)
            }
            stage = .ready
        }
    }

    private func depositOptions(_ held: [String: String]) -> [Option] {
        ShieldBridge.assets.flatMap { asset -> [Option] in
            guard let have = Decimal(string: held[asset.symbol] ?? "0"), have > 0 else { return [] }
            let steps = asset.symbol == "USDC" ? Self.usdcSteps : Self.wethSteps
            return steps.filter { (Decimal(string: $0) ?? 0) * pow(10, asset.decimals) <= have }
                .map { Option(symbol: asset.symbol, amount: $0) }
        }
    }

    /// An ERC-20 balance on Ethereum, base units, or "0".
    static func balance(of token: String, at owner: String) async -> String {
        let data = "0x70a08231" + String(repeating: "0", count: 24) + owner.lowercased().dropFirst(2)
        guard let answer = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_call", [["to": token, "data": data], "latest"]) as? String
        else { return "0" }
        return ShieldBridge.decimal(hex: String(answer.dropFirst(2))) ?? "0"
    }

    /// The move, as the sentence says it.
    func run() async {
        guard stage == .ready, let units, !refused, !cannotLeave else { return }
        let report: @Sendable (YourAccountChain.Stage) async -> Void = { s in
            await MainActor.run { self.stage = .working(s == .signing ? String(localized: "Confirm with Face ID") : String(localized: "Sending…")) }
        }
        do {
            switch mode {
            case .deposit:
                guard let asset else { return }
                stage = .working(String(localized: "Checking…"))
                let gas = bringsGas ? try await AztecGas.plan(units: AztecGas.rideAlong) : nil
                let sent = try await ShieldBridge.deposit(asset, units: units, gas: gas, stage: report)
                stage = .done(sent.transaction)
            case .send:
                guard let recipient else { return }
                if toAztec {
                    guard let token else { return }
                    try await PrivateRootKey.unlock(reason: String(localized: "Send privately on Aztec"))
                    try await AztecCoSign.approve(String(localized: "Send \(PrivateMoney.figure(units, decimals: decimals, symbol: symbol)) on Aztec to \(recipient)"))
                    stage = .working(String(localized: "Proving…"))
                    let out = try await AztecEngine.shared.call("sendToken", [token, recipient.lowercased(), units]) as? [String: Any]
                    let hash = out?["tx"] as? String ?? ""
                    if !hash.isEmpty {
                        AztecActivity.record(.init(hash: hash, kind: .send, symbol: symbol, amountUnits: units, decimals: decimals,
                                                   to: recipient.lowercased(), fee: out?["fee"] as? String, at: .now))
                    }
                    stage = .done(hash)
                } else if toEthereum, let asset {
                    stage = .working(String(localized: "Proving…"))
                    let exit = try await ShieldBridge.exit(asset, units: units, to: recipient)
                    stage = .done(exit.transaction)
                }
                await AztecAccountStore.shared.refresh()
            }
            DSHaptic.success()
        } catch {
            stage = .failed(AztecEngine.words(error))
        }
    }

    // MARK: - The recipient, checked (prd §1711 items 4, 5)

    /// The findings that stand for the recipient as it is now.
    var shownFindings: [MoveWarnings.Finding] {
        guard let recipient, findingsFor == recipient else { return [] }
        return findings
    }
    var leadWarning: MoveWarnings.Finding? { shownFindings.first }
    /// "Send anyway": a warning stands; the first tap arms it, the second sends.
    var warned: Bool { MoveWarnings.arms(shownFindings) }
    /// An Aztec address no one can receive at: nothing sends.
    var refused: Bool { shownFindings.contains { if case .fails = $0 { true } else { false } } }
    /// Still asking about the recipient: the verb waits for the answer.
    var checking: Bool { mode == .send && recipient != nil && findingsFor != recipient }
    var mustArm: Bool { warned && armed != recipient }
    func arm() { armed = recipient }

    /// Checks the recipient once per address. An Aztec address: Aztec's own
    /// `isValid` (half of all 64-digit values are no one's: a typo there is
    /// money no one can read), then whether you paid it, or one it looks
    /// like. An Ethereum address, the end of an exit: everything Move's Send
    /// looks up, against your account's own history.
    func checkRecipient(context: ModelContext) async {
        guard mode == .send, let to = recipient, findingsFor != to else { return }
        var found: [MoveWarnings.Finding] = []
        if DemoMode.isActive {
            found = []
        } else if AztecAddressText.isAztec(to) {
            let answer = try? await AztecEngine.shared.call("addressValid", [to]) as? [String: Any]
            if answer?["valid"] as? Bool == false {
                found = [.fails(String(localized: "No one can receive at this Aztec address. Check it."))]
            } else if to.lowercased() != AztecAccountStore.shared.snapshot.address?.lowercased() {
                let sent = AztecAccountStore.shared.aztecSentTo
                if sent[to.lowercased()] == nil {
                    found = [MoveWarnings.aztecImitated(to, sentTo: sent) ?? .firstSend]
                }
            }
        } else if PrivateMoney.isAddress(to), let account = YourAccountKey.address {
            found = await MoveChecks.recipient(to, from: account, on: YourAccountOp.ethereum, context: context)
        }
        guard recipient == to else { return }
        findings = found
        findingsFor = to
    }

    /// Claims what Aztec has carried, gas first (a claim pays from gas).
    func settle() async {
        await AztecGas.settle()
        await ShieldBridge.settle()
    }

    var waiting: Bool {
        let s = AztecAccountStore.shared.snapshot
        return (s.gas ?? []).contains { !$0.claimed } || (s.shield ?? []).contains { !$0.claimed }
    }
}

struct MoveAztecPrivateSentence<Head: View>: View {
    let move: AztecMove
    var inTray = false
    /// Leaves the sentence: back to Send's recipients (`pickRecipient`) or
    /// its networks (`switchOff`), as 0xBow's does.
    var leave: (MovePrivateLeave) -> Void = { _ in }
    @ViewBuilder let head: () -> Head

    private enum Blank { case amount, recipient }
    @State private var open: Blank?
    @State private var typed = ""
    @State private var notAnAddress = false
    @State private var copied = false
    @State private var passport = false
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if !leadsWithVerb {
                    head().padding(.bottom, DS.Space.s4)
                }
                MoveFlow { sentence }
                    .environment(\.moveQuiet, open != nil)
                    .animation(DS.Motion.standard, value: move.stage)
                    .animation(DS.Motion.standard, value: move.amount)
                    .animation(DS.Motion.standard, value: move.recipient)
                Group {
                    if let open, move.stage == .ready {
                        choices(open)
                            .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity), removal: .opacity))
                    } else {
                        line.transition(.opacity)
                    }
                }
                .padding(.top, open != nil ? DS.Space.s4 : DS.Space.s6)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { if open == nil { foot.transition(.opacity) } }
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        .task(id: move.mode) { await move.read() }
        // Who it goes to, checked before the verb stands (prd §1711).
        .task(id: "\(move.mode)|\(move.recipient ?? "")") { await move.checkRecipient(context: modelContext) }
        // What Aztec has carried is claimed while the sentence stands.
        .task {
            guard AztecProver.isAvailable, !DemoMode.isActive else { return }
            while !Task.isCancelled {
                if move.waiting { await move.settle() }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // Back from Human Passport, Shield is asked again.
        .sheet(isPresented: $passport, onDismiss: { Task { await move.read() } }) {
            AztecBrowserView(url: URL(string: "https://app.passport.xyz")!, aztec: false, ethereum: true)
                .presentationDragIndicator(.visible)
        }
    }

    private var isDone: Bool { if case .done = move.stage { true } else { false } }

    private var leadsWithVerb: Bool {
        switch move.stage {
        case .ready, .working: true
        default: false
        }
    }

    private var figure: String {
        PrivateMoney.figure(move.units ?? "0", decimals: move.decimals, symbol: move.symbol)
    }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(String(localized: "Reading Aztec…"), ink: DS.textSecondary)
        case .needsFunds(let address):
            MoveClause(glue: String(localized: "Fund")) {
                Button { copy(address) } label: { MoveWord(YourAccount.short(address), ink: DS.pickInk) }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Copies the address"))
            }
            MovePhrase(String(localized: "Ethereum"), glue: String(localized: "on"))
            MovePhrase(String(localized: "first."))
        case .shieldNo(_, let threshold, let sanctioned):
            MovePhrase(sanctioned ? String(localized: "Shield will not move money for this account.")
                       : String(localized: "Shield needs a Human Passport score of \(threshold) first."), ink: DS.textPrimary)
        case .nothingPrivate:
            MovePhrase(String(localized: "Nothing private to send on Aztec yet."), ink: DS.textSecondary)
        case .needsGas:
            MovePhrase(String(localized: "Your private account on Aztec needs gas first."), ink: DS.textPrimary)
        default:
            if !isDone { head() }
            MoveClause(glue: isDone ? String(localized: "Sent") : nil) {
                Button { if move.stage == .ready { toggle(.amount) } } label: {
                    MoveWord(figure, ink: move.stage == .ready ? DS.pickInk : DS.textPrimary)
                        .environment(\.moveQuiet, open != nil && open != .amount)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Amount, \(figure)"))
            }
            if move.mode == .deposit {
                MoveWordsClause(glue: String(localized: "to"), words: String(localized: "your private account"),
                                ink: move.stage == .ready ? DS.pickInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.pickRecipient) } },
                                hint: Text("Picks who it goes to"))
                MovePhrase(String(localized: "Aztec."), glue: String(localized: "on"))
            } else {
                MoveWordsClause(glue: String(localized: "from"), words: String(localized: "your private account on Aztec"),
                                ink: move.stage == .ready ? DS.pickInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.switchOff) } },
                                hint: Text("Picks where it comes from"))
                MoveClause(glue: String(localized: "to")) { recipientWord }
            }
        }
    }

    @ViewBuilder private var recipientWord: some View {
        let live = move.stage == .ready
        Button { if live { toggle(.recipient) } } label: {
            Group {
                if let to = move.recipient {
                    MoveWord(AddressTail.short(to) + ".", ink: live ? DS.pickInk : DS.textPrimary)
                } else {
                    MoveWord(String(localized: "address."), ink: open == .recipient ? DS.pickInk : DS.textTertiary)
                }
            }
            .environment(\.moveQuiet, open != nil && open != .recipient)
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(move.recipient.map { "To \($0)" } ?? String(localized: "Pick who it goes to")))
    }

    // MARK: - The line

    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready where move.cannotLeave:
            Text("Only USDC and WETH can leave Aztec.").dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        case .ready where move.leadWarning != nil:
            // The one warning, in the place of the grey line (prd §1509 item 2).
            if let lead = move.leadWarning {
                Text(verbatim: MoveWarnings.line(lead, short: { AddressTail.short($0) },
                                                 day: { $0.formatted(.dateTime.month(.abbreviated).day()) }))
                    .dsText(.body17).foregroundStyle(lead.red ? DS.destructiveInk : DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .ready, .working:
            Text(verbatim: readyLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .needsFunds:
            Text(verbatim: fundsLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .shieldNo(let score, _, let sanctioned):
            if !sanctioned {
                Text("Yours is \(score).").dsText(.body17).foregroundStyle(DS.textSecondary)
            }
        case .needsGas:
            Text("30 AZTEC from your account pays for it, about $0.45.").dsText(.body17).foregroundStyle(DS.textSecondary)
        case .failed(let words):
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        case .done:
            Text(verbatim: doneLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private var readyLine: String {
        if case .working(let words) = move.stage { return words }
        switch move.mode {
        case .deposit:
            let gas = move.bringsGas ? String(localized: "with 30 AZTEC as its gas") : nil
            return [String(localized: "Through Shield"), String(localized: "0.5% fee"), String(localized: "5 to 15 minutes"), gas]
                .compactMap { $0 }.joined(separator: " · ")
        case .send:
            if move.toEthereum {
                return [String(localized: "Through Shield"), String(localized: "0.5% fee"), String(localized: "finish on Ethereum in about an hour")]
                    .joined(separator: " · ")
            }
            return String(localized: "Who, what and how much stay private · about 20 seconds")
        }
    }

    private var fundsLine: String {
        let gasShort = move.bringsGas && (Decimal(string: move.safeHeld["AZTEC"] ?? "0") ?? 0) < (Decimal(string: AztecGas.rideAlong) ?? 0)
        if gasShort, !(move.options.isEmpty) {
            return String(localized: "Your Aztec account needs 30 AZTEC as gas the first time.")
        }
        return String(localized: "At least 1 USDC or 0.0005 WETH moves in.")
    }

    private var doneLine: String {
        switch move.mode {
        case .deposit: String(localized: "On its way: Aztec carries it in minutes, then it is yours.")
        case .send:
            move.toEthereum ? String(localized: "Proved. In about an hour Needs you offers Finish on Ethereum.")
                : String(localized: "Sent privately.")
        }
    }

    // MARK: - Choices

    private func toggle(_ blank: Blank) {
        withAnimation(DS.Motion.standard) { open = open == blank ? nil : blank }
        DSHaptic.selection()
    }

    @ViewBuilder private func choices(_ blank: Blank) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch blank {
            case .amount: amounts
            case .recipient: recipients
            }
        }
        .padding(.vertical, DS.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amounts: some View {
        ForEach(move.options) { option in
            let places = option.decimals
            let shown = PrivateMoney.figure(PrivateMoney.baseUnits(option.amount, decimals: places) ?? "0", decimals: places, symbol: option.symbol)
            let picked = option.amount == move.amount && option.symbol == move.symbol && option.token == move.token
            Button {
                withAnimation(DS.Motion.standard) { move.pick(option); open = nil }
                DSHaptic.selection()
            } label: {
                HStack(spacing: DS.Space.s3) {
                    AssetMark(name: option.symbol, size: DS.Face.list)
                    Text(verbatim: shown).dsText(.body17)
                        .foregroundStyle(picked ? DS.textSecondary : DS.textPrimary).monospacedDigit()
                    Spacer(minLength: DS.Space.s2)
                }
                .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityAddTraits(picked ? [.isSelected] : [])
        }
    }

    /// An Aztec account (a private send) or an Ethereum address (out
    /// through Shield), typed or pasted.
    @ViewBuilder private var recipients: some View {
        if notAnAddress {
            Text("That isn't an Aztec or Ethereum address").dsText(.body17).foregroundStyle(DS.attentionInk)
                .padding(.top, DS.Space.s2)
        }
        TextField(text: $typed, prompt: Text("0x…").foregroundStyle(DS.textTertiary)) { Text("Address") }
            .dsText(.body17)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
            .onSubmit { take(typed) }
        Button { take(UIPasteboard.general.string ?? "") } label: {
            Text("Paste").dsText(.body17).foregroundStyle(DS.pickInk)
                .frame(maxWidth: .infinity, minHeight: DSFeed.headHeight + DS.Space.s3, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    private func take(_ raw: String) {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AztecAddressText.isAztec(address) || PrivateMoney.isAddress(address) else {
            typed = address
            DSHaptic.failure()
            withAnimation(DS.Motion.standard) { notAnAddress = !address.isEmpty }
            return
        }
        notAnAddress = false
        withAnimation(DS.Motion.standard) { move.recipient = address; open = nil }
        DSHaptic.selection()
    }

    // MARK: - The foot

    private var ready: Bool {
        move.stage == .ready && (move.mode == .deposit || move.toAztec || move.toEthereum) && !DemoMode.isActive
            && !move.refused && !move.checking && !move.cannotLeave
    }

    private var foot: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                switch move.stage {
                case .needsFunds(let address):
                    checkAgain
                    Spacer(minLength: DS.Space.s3)
                    footButton(copied ? String(localized: "Copied") : String(localized: "Copy address"), on: true) { copy(address) }
                case .shieldNo(_, _, let sanctioned):
                    checkAgain
                    Spacer(minLength: DS.Space.s3)
                    // The only door a Casberi Safe has to a score (prd §1700f).
                    if !sanctioned {
                        footButton(String(localized: "Human Passport"), on: true) { passport = true }
                    }
                case .needsGas:
                    Spacer(minLength: 0)
                    footButton(String(localized: "Add gas"), on: !DemoMode.isActive) {
                        Task {
                            move.stage = .working(String(localized: "Confirm with Face ID"))
                            do { _ = try await AztecGas.send(units: AztecGas.rideAlong) { _ in }; move.stage = .done("") }
                            catch { move.stage = .failed(AztecEngine.words(error)) }
                        }
                    }
                case .done:
                    Spacer(minLength: 0)
                    footButton(String(localized: "Done"), on: true) {
                        if inTray { chrome.moveTray = false } else { leave(.switchOff) }
                    }
                case .failed:
                    Spacer(minLength: 0)
                    footButton(String(localized: "Try again"), on: true) { Task { await move.read() } }
                case .reading, .nothingPrivate:
                    Spacer(minLength: 0)
                default:
                    Spacer(minLength: 0)
                    footButton(DemoMode.isActive ? String(localized: "Not in the demo") : footVerb, on: ready,
                               ink: move.warned && ready ? (move.leadWarning?.red == true ? DS.destructiveInk : DS.attentionInk) : nil) {
                        open = nil
                        // The first tap on "Send anyway" only arms it; the second sends.
                        if move.mustArm { move.arm(); DSHaptic.failure(); return }
                        Task { await move.run() }
                    }
                    .disabled(!ready)
                }
            }
            if move.stage != .reading, !isDone { credit }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    /// Fits beside the act, never cut (prd §1700f item 13).
    private var checkAgain: some View {
        Button {
            Task { await move.read() }
            DSHaptic.selection()
        } label: {
            Text("Check again").dsText(.heading24).foregroundStyle(DS.textPrimary)
                .lineLimit(1).fixedSize().frame(minHeight: 48)
        }
        .buttonStyle(RowPress())
    }

    private var footVerb: String {
        if case .working(let words) = move.stage { return words }
        if move.checking { return String(localized: "Checking…") }
        if move.warned { return String(localized: "Send anyway") }
        return String(localized: "Send")
    }

    private var credit: some View {
        HStack(spacing: DS.Space.s1) {
            // Shield carries money in and out; a send that stays on Aztec is Aztec's alone.
            Text(move.mode == .send && !move.toEthereum ? "Powered by Aztec" : "Powered by Shield")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            ProtocolInlineMark(mark: "aztec").accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s1)
    }

    private func footButton(_ word: String, on: Bool, ink: Color? = nil, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(verbatim: word)
                .dsText(.heading34)
                .foregroundStyle(on ? (ink ?? DS.pickInk) : DS.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minHeight: 48, alignment: .trailing)
        }
        .buttonStyle(RowPress())
    }

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }
}

enum AztecAddressText {
    /// An Aztec account's address: `0x` and 64 hex characters.
    static func isAztec(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        return t.hasPrefix("0x") && t.count == 66 && t.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}
