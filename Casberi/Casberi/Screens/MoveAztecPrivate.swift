import SwiftUI
import Observation

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
///   co-signer first (`AztecCoSign`).
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

    /// A token you can move, and how much of it, base units.
    struct Holding: Equatable, Identifiable {
        let symbol: String
        let units: String
        var id: String { symbol }
    }

    var mode: Mode = .deposit
    var stage: Stage = .reading
    var symbol = "USDC"
    var amount = ""
    var recipient: String?
    private(set) var holdings: [Holding] = []
    /// What the Safe holds on Ethereum, base units, by symbol.
    private(set) var safeHeld: [String: String] = [:]
    /// Whether a deposit brings gas along (the account is short of it).
    private(set) var bringsGas = false
    private(set) var maxUSD: Double?
    /// Your co-signer, when Shield scores it and not your account: the
    /// deposit is then the co-signer's own (prd §1720).
    private(set) var viaCoSigner: String?

    // MARK: - In dollars (prd §1700y, as Railgun's §1728)

    /// USD per coin, by symbol: USDC, WETH (at ETH's price), AZTEC.
    private(set) var prices: [String: Double] = [:]
    /// Aztec's minimum fee per unit of L2 gas, in Fee Juice's smallest unit.
    private(set) var feePerL2Gas: Decimal?
    /// Ethereum's gas price, wei, for a move-in signed by Your account.
    private(set) var gasPriceWei: Decimal?
    /// When this sentence began reading, for "Getting your private balance
    /// ready · 12 s" in the foot (real seconds, as Railgun's).
    private(set) var readingSince: Date?

    /// Shield's cut, both ways: 0.5% (its own page, prd §1700d).
    static let shieldBps = 50
    /// A private send's gas on Aztec: one transfer used 644K to 742K
    /// (twelve fee-bearing mainnet blocks read 2026-11-08); the higher, rounded.
    static let sendMana = 750_000
    /// An exit through Shield burns and messages Ethereum: more than a send.
    static let exitMana = 1_400_000
    /// A move-in on Ethereum: Shield's deposit used 170K to 175K (its portal's
    /// own deposits, read 2026-11-09), plus Your account's approve and its own
    /// overhead (~120K, measured 2026-11-03); gas riding along adds its
    /// portal's deposit and approve.
    static let depositGas = 350_000
    static let gasAlongGas = 150_000

    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Base units of a token in dollars.
    func dollars(_ units: String, symbol: String) -> Double? {
        guard let price = prices[symbol], let u = Decimal(string: units) else { return nil }
        let places = symbol == "USDC" ? 6 : 18
        return NSDecimalNumber(decimal: u / pow(10, places)).doubleValue * price
    }

    /// The line under the sentence: "$25.00 · you have $120.00" (prd §1700y).
    /// No price: what you have, in the token.
    var amountLine: String? {
        guard let available else { return nil }
        var parts: [String] = []
        if let units, (Decimal(string: units) ?? 0) > 0, let usd = dollars(units, symbol: symbol) { parts.append(Self.usd(usd)) }
        parts.append(dollars(available, symbol: symbol).map { String(localized: "you have \(Self.usd($0))") }
                     ?? String(localized: "you have \(PrivateMoney.figure(available, decimals: decimals, symbol: symbol))"))
        return parts.joined(separator: " · ")
    }

    /// Half · All (prd §1700y, Railgun's §1728 item 1 without its floor):
    /// each types its amount, exact; one Shield would refuse is not drawn.
    enum Pick: CaseIterable { case half, all }

    func amount(for pick: Pick) -> String? {
        guard let available, let held = Decimal(string: available), held > 0 else { return nil }
        var value: Decimal
        switch pick {
        case .half:
            var half = held / 2, down = Decimal()
            NSDecimalRound(&down, &half, 0, .down)
            value = down
        case .all: value = held
        }
        guard value > 0 else { return nil }
        if mode == .deposit, symbol == "USDC", let maxUSD, value > Decimal(maxUSD) * 1_000_000 { return nil }
        var whole = value / pow(10, decimals), cut = Decimal()
        NSDecimalRound(&cut, &whole, decimals, .down)
        return NSDecimalNumber(decimal: cut).stringValue
    }

    /// What this move costs, in dollars and its parts (prd §1700y, the shape
    /// of Railgun's `Cost`): Shield's cut where Shield carries it, then the
    /// gas: Aztec's from your Fee Juice, Ethereum's from your account, and
    /// 30 AZTEC when gas rides along. nil where a price is missing: the foot
    /// then says Shield's percentage, as before.
    var cost: PrivateCost? {
        guard amountOK, let units else { return nil }
        var usd = 0.0
        var parts: [PrivateCost.Part] = []
        func aztecGas(_ mana: Int) -> Double? {
            guard let feePerL2Gas, let aztec = prices["AZTEC"] else { return nil }
            let fj = Decimal(mana) * feePerL2Gas / pow(10, 18)
            return NSDecimalNumber(decimal: fj).doubleValue * aztec
        }
        func shieldCut() -> Bool {
            var raw = (Decimal(string: units) ?? 0) * Decimal(Self.shieldBps) / 10_000, cut = Decimal()
            NSDecimalRound(&cut, &raw, 0, .down)
            let text = NSDecimalNumber(decimal: cut).stringValue
            guard let cutUSD = dollars(text, symbol: symbol) else { return false }
            usd += cutUSD
            parts.append(.init(words: String(localized: "Shield"), figure: PrivateMoney.figure(text, decimals: decimals, symbol: symbol)))
            return true
        }
        switch mode {
        case .deposit:
            guard shieldCut(), let gasPriceWei, let eth = prices["WETH"] else { return nil }
            let gas = Decimal(Self.depositGas + (bringsGas ? Self.gasAlongGas : 0)) * gasPriceWei / pow(10, 18)
            let gasUSD = NSDecimalNumber(decimal: gas).doubleValue * eth
            usd += gasUSD
            parts.append(.init(words: String(localized: "Gas, from your account"), figure: String(localized: "about \(Self.usd(gasUSD))")))
            if bringsGas {
                guard let along = dollars(AztecGas.rideAlong, symbol: "AZTEC") else { return nil }
                usd += along
                parts.append(.init(words: String(localized: "Aztec's gas, for your account there"), figure: "30 AZTEC"))
            }
        case .send where toEthereum:
            guard shieldCut(), let gas = aztecGas(Self.exitMana) else { return nil }
            usd += gas
            parts.append(.init(words: String(localized: "Gas, from your Fee Juice"), figure: String(localized: "about \(Self.usd(gas))")))
        case .send:
            guard let gas = aztecGas(Self.sendMana) else { return nil }
            usd += gas
            parts.append(.init(words: String(localized: "Gas, from your Fee Juice"), figure: String(localized: "about \(Self.usd(gas))")))
        }
        return PrivateCost(usd: usd, parts: parts)
    }

    /// What the cost line says after the dollars: what the move buys you.
    var costTail: String {
        switch mode {
        case .deposit: String(localized: "private in 5 to 15 minutes")
        case .send where toEthereum: String(localized: "on Ethereum in about an hour")
        case .send: String(localized: "who, what and how much stay private")
        }
    }

    #if DEBUG
    /// For `CasberiTests`: a sentence's inputs, no network (prd §1700y).
    func seedForTests(mode: Mode, symbol: String, held: String, amount: String, recipient: String? = nil,
                      prices: [String: Double], feePerL2Gas: Decimal?, gasPriceWei: Decimal?,
                      maxUSD: Double? = nil, bringsGas: Bool = false) {
        self.mode = mode
        self.symbol = symbol
        self.holdings = [Holding(symbol: symbol, units: held)]
        self.amount = amount
        self.recipient = recipient
        self.prices = prices
        self.feePerL2Gas = feePerL2Gas
        self.gasPriceWei = gasPriceWei
        self.maxUSD = maxUSD
        self.bringsGas = bringsGas
    }
    #endif

    /// Prices, and the fees a cost is made of; read with the balances, never
    /// holding up the sentence.
    private func readCosts() async {
        var found: [String: Double] = [:]
        let mainnet = await MainnetPrices.prices(for: ["usdc", "eth"])
        if let usdc = mainnet["usdc"] { found["USDC"] = usdc }
        if let eth = mainnet["eth"] { found["WETH"] = eth }
        let aztec = await DefiLlamaPrices.prices(for: [("eth-mainnet", AztecGas.token)])
        if let p = aztec.values.first?.price { found["AZTEC"] = p }
        prices = found
        switch mode {
        case .deposit:
            if let hex = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_gasPrice", []) as? String {
                gasPriceWei = ShieldBridge.decimal(hex: String(hex.dropFirst(2))).flatMap { Decimal(string: $0) }
            }
        case .send:
            guard AztecProver.isAvailable,
                  let fees = try? await AztecEngine.shared.call("minFees") as? [String: Any],
                  let l2 = fees["l2"] as? String else { return }
            feePerL2Gas = Decimal(string: l2)
        }
    }

    var decimals: Int { symbol == "USDC" ? 6 : 18 }
    var asset: ShieldBridge.Asset? { ShieldBridge.assets.first { $0.symbol == symbol } }
    /// What was typed, in base units: a comma is a decimal point, a leading
    /// point reads as "0.", and a trailing point (mid-typing) is ignored.
    var units: String? {
        var typed = amount.replacingOccurrences(of: ",", with: ".")
        if typed.hasSuffix(".") { typed.removeLast() }
        // ".5" is half (prd §1700r, user: "the send button stays inactive").
        if typed.hasPrefix(".") { typed = "0" + typed }
        return PrivateMoney.baseUnits(typed, decimals: decimals)
    }
    /// How much of the picked token there is to move, base units.
    var available: String? { holdings.first { $0.symbol == symbol }?.units }

    /// **ANY AMOUNT (prd §1700q, user: "we don't want a fixed list we want be
    /// able to add whatever user wants").** The amount is typed; what stands
    /// in its way is said, never a list of allowed amounts: more than you
    /// hold, or more than Shield moves for your score.
    enum AmountProblem: Equatable {
        case moreThanHeld(String)
        case overShieldCap(Int)
    }
    var amountProblem: AmountProblem? {
        guard let units, let want = Decimal(string: units), want > 0 else { return nil }
        if let available, let have = Decimal(string: available), want > have {
            return .moreThanHeld(PrivateMoney.figure(available, decimals: decimals, symbol: symbol))
        }
        // Shield's cap is in dollars: USDC is read as dollars; WETH's is
        // Shield's to refuse, as there is no price here to read it by.
        if mode == .deposit, symbol == "USDC", let maxUSD, want > Decimal(maxUSD) * 1_000_000 {
            return .overShieldCap(Int(maxUSD))
        }
        return nil
    }
    var amountOK: Bool { units != nil && amountProblem == nil }
    var acting: Bool { if case .working = stage { true } else { false } }

    /// Whether `recipient` is an Aztec account (a private send) or an
    /// Ethereum address (out through Shield).
    var toAztec: Bool { recipient.map(AztecAddressText.isAztec) ?? false }
    var toEthereum: Bool { recipient.map(PrivateMoney.isAddress) ?? false }

    /// Picks the token; the typed amount stays.
    func pick(_ symbol: String) {
        self.symbol = symbol
    }

    /// The picked token stays if it is still held; else the first held.
    private func keepPick() {
        if !holdings.contains(where: { $0.symbol == symbol }), let first = holdings.first { symbol = first.symbol }
    }

    /// Where the move stands: balances, Shield's word, the account's gas.
    func read() async {
        stage = .reading
        readingSince = .now
        defer { readingSince = nil }
        if DemoMode.isActive {
            holdings = [Holding(symbol: "USDC", units: "25000000")]
            symbol = "USDC"
            if amount.isEmpty { amount = "2" }
            // The demo's cost is a sample, as Railgun's demo fee is (prd §1700y).
            prices = ["USDC": 1, "WETH": 3000, "AZTEC": 0.0124]
            feePerL2Gas = 2_186_613_113_685
            gasPriceWei = 400_000_000
            stage = .ready
            return
        }
        Task { await readCosts() }
        guard let safe = YourAccountKey.address else { stage = .failed(String(localized: "There is no account on this iPhone")); return }
        switch mode {
        case .deposit:
            async let safeStanding = ShieldBridge.eligibility(safe)
            var held: [String: String] = [:]
            for asset in ShieldBridge.assets { held[asset.symbol] = await Self.balance(of: asset.ethToken, at: safe) }
            held["AZTEC"] = await Self.balance(of: AztecGas.token, at: safe)
            bringsGas = AztecProver.isAvailable && AztecGas.needed
            guard var standing = await safeStanding else { stage = .failed(String(localized: "Shield did not answer")); return }
            // **YOUR CO-SIGNER, WHEN SHIELD SCORES IT (prd §1720).** A Safe
            // cannot link accounts on Human Passport's page; your co-signer
            // can. When your account is not eligible and your co-signer is,
            // the deposit is the co-signer's, and what it holds counts too
            // (your account moves it the rest).
            viaCoSigner = nil
            if !standing.eligible, !standing.sanctioned,
               let coSigner = try? await YourAccountChain.knownSigners(YourAccountOp.ethereum, safe).first,
               let theirs = await ShieldBridge.eligibility(coSigner), theirs.eligible {
                viaCoSigner = coSigner
                standing = theirs
                for asset in ShieldBridge.assets {
                    let more = Decimal(string: await Self.balance(of: asset.ethToken, at: coSigner)) ?? 0
                    held[asset.symbol] = NSDecimalNumber(decimal: (Decimal(string: held[asset.symbol] ?? "0") ?? 0) + more).stringValue
                }
            }
            safeHeld = held
            holdings = depositHoldings(held)
            maxUSD = standing.maxUSD
            if standing.sanctioned || !standing.eligible {
                stage = .shieldNo(score: Int(standing.score), threshold: Int(standing.threshold), sanctioned: standing.sanctioned)
                return
            }
            let gasShort = bringsGas && (Decimal(string: held["AZTEC"] ?? "0") ?? 0) < (Decimal(string: AztecGas.rideAlong) ?? 0)
            if holdings.isEmpty || gasShort { stage = .needsFunds(address: safe); return }
            keepPick()
            stage = .ready
        case .send:
            // **WHAT IT LAST READ, AT ONCE (prd §1700r, user: "why does
            // 'reading aztec' take so long?" — the engine's start and sync, a
            // minute or two measured).** The stored balance stands while the
            // engine refreshes behind it; a move already under way is never
            // taken back to ready.
            let store = AztecAccountStore.shared
            func fill() {
                holdings = store.privateHeld.compactMap { h -> Holding? in
                    guard let units = h.privateUnits, let have = Decimal(string: units), have > 0, h.decimals != nil else { return nil }
                    return Holding(symbol: h.name, units: units)
                }
            }
            fill()
            if !holdings.isEmpty, !AztecGas.needed { keepPick(); stage = .ready }
            if AztecProver.isAvailable { await store.refresh() }
            guard stage == .reading || stage == .ready else { return }
            fill()
            if holdings.isEmpty { stage = .nothingPrivate; return }
            if AztecGas.needed { stage = .needsGas; return }
            keepPick()
            stage = .ready
        }
    }

    private func depositHoldings(_ held: [String: String]) -> [Holding] {
        ShieldBridge.assets.compactMap { asset -> Holding? in
            guard let units = held[asset.symbol], let have = Decimal(string: units), have > 0 else { return nil }
            return Holding(symbol: asset.symbol, units: units)
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
        guard stage == .ready, amountOK, let units, let asset else { return }
        let steps = PrivateSendSteps.shared
        // Last send's rows go; this send's start at its own tap (prd §1700x).
        steps.forget(.move)
        let report: @Sendable (YourAccountChain.Stage) async -> Void = { s in
            await MainActor.run {
                self.stage = .working(s == .signing ? String(localized: "Confirm with Face ID") : String(localized: "Sending…"))
                switch s {
                case .signing, .cosigning: steps.mark(.signing)
                case .sending, .landing: steps.mark(.sent)
                case .preparing: break
                }
            }
        }
        do {
            switch mode {
            case .deposit:
                stage = .working(String(localized: "Checking…"))
                // A move-in is signed on Ethereum, not proved (prd §1700x), as
                // Railgun's is: Checking · Signing · Sent on Ethereum.
                steps.begin(.move, plan: .signed(.ethereum))
                let gas = bringsGas ? try await AztecGas.plan(units: AztecGas.rideAlong) : nil
                if let coSigner = viaCoSigner {
                    let sent = try await ShieldBridge.depositFromCoSigner(asset, units: units, coSigner: coSigner, gas: gas) { words in
                        self.stage = .working(words)
                    }
                    steps.finish()
                    stage = .done(sent.transaction)
                } else {
                    let sent = try await ShieldBridge.deposit(asset, units: units, gas: gas, stage: report)
                    steps.finish()
                    stage = .done(sent.transaction)
                }
            case .send:
                guard let recipient else { return }
                if toAztec {
                    try await PrivateRootKey.unlock(reason: String(localized: "Send privately on Aztec"))
                    try await AztecCoSign.approve(String(localized: "Send \(PrivateMoney.figure(units, decimals: decimals, symbol: symbol)) on Aztec to \(recipient)"))
                    // The rows' clock starts at the tap, before a cold engine
                    // has said anything (prd §1700w).
                    steps.begin(.move, plan: .send(.aztec))
                    stage = .working(String(localized: "Sending…"))
                    let out = try await AztecEngine.shared.call("sendPrivately", [symbol, recipient.lowercased(), units]) as? [String: Any]
                    stage = .done(out?["tx"] as? String ?? "")
                } else if toEthereum {
                    steps.begin(.move, plan: .send(.aztec))
                    stage = .working(String(localized: "Sending…"))
                    let exit = try await ShieldBridge.exit(asset, units: units, to: recipient)
                    stage = .done(exit.transaction)
                }
                await AztecAccountStore.shared.refresh()
            }
            DSHaptic.success()
        } catch {
            // The rows keep the failure on the step it reached (prd §1700x).
            steps.fail(AztecEngine.words(error))
            stage = .failed(AztecEngine.words(error))
        }
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

    private enum Blank { case token, recipient }
    @State private var open: Blank?
    @FocusState private var typing: Bool
    @State private var typed = ""
    @State private var notAnAddress = false
    @State private var copied = false
    @State private var passport = false
    @Environment(ShellChrome.self) private var chrome

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
        // A failure keeps the sentence's own verb: "Send" drew twice (above
        // and inside), found by the Railgun session on the simulator (prd §1700y).
        case .ready, .working, .failed: true
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
            if move.stage == .ready {
                MoveClause { amountField }
                MoveClause {
                    Button { toggle(.token) } label: {
                        MoveWord(move.symbol, ink: DS.pickInk)
                            .environment(\.moveQuiet, open != nil && open != .token)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("Token, \(move.symbol)"))
                    .accessibilityHint(Text("Picks the token"))
                }
            } else {
                MoveClause(glue: isDone ? String(localized: "Sent") : nil) {
                    MoveWord(figure, ink: DS.textPrimary)
                        .accessibilityLabel(Text("Amount, \(figure)"))
                }
            }
            if move.mode == .deposit {
                // "Your private balance", as on Ethereum (prd §1719): in Move
                // a balance is where money sits; "account" stays where it
                // has an address and apps (Your account, Receive).
                MoveWordsClause(glue: String(localized: "to"), words: String(localized: "your private balance"),
                                ink: move.stage == .ready ? DS.pickInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.pickRecipient) } },
                                hint: Text("Picks who it goes to"))
                MovePhrase(String(localized: "Aztec."), glue: String(localized: "on"))
            } else {
                MoveWordsClause(glue: String(localized: "from"), words: String(localized: "your private balance on Aztec"),
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

    /// The amount, typed (prd §1700q): the decimal pad, the token's places
    /// at most, and the figure in the sentence's own rung.
    private var amountField: some View {
        MoveRungReader { rung in
            TextField(text: Binding(get: { move.amount }, set: { move.amount = $0 }),
                      prompt: Text(verbatim: "0").foregroundStyle(DS.textTertiary)) { Text(verbatim: "0") }
                .keyboardType(.decimalPad)
                .focused($typing)
                .dsText(rung)
                .monospacedDigit()
                .foregroundStyle(DS.pickInk)
                .fixedSize()
                .opacity(open != nil ? 0.3 : 1)
        }
        .accessibilityLabel(Text("Amount"))
        .onChange(of: move.amount) { _, now in
            if open != nil, typing { open = nil }
            if let dot = now.firstIndex(where: { $0 == "." || $0 == "," }),
               now.distance(from: dot, to: now.endIndex) - 1 > move.decimals {
                move.amount = String(now[...now.index(dot, offsetBy: move.decimals)])
            }
        }
    }

    // MARK: - The line

    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready, .working:
            if stepsRun != nil {
                // The steps stand in the foot; the sentence stands alone (prd §1700x).
                EmptyView()
            } else if move.stage == .ready, let problem = move.amountProblem {
                Text(verbatim: problemLine(problem)).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if move.stage == .ready {
                // The amount in dollars and two choices (prd §1700y, as
                // Railgun's §1728 item 1); what it costs is the foot's.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if let words = move.amountLine {
                        Text(verbatim: words).dsText(.body17).foregroundStyle(DS.textSecondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    chips
                }
            } else {
                Text(verbatim: readyLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            // A failure the rows carry is said once, on its step.
            if stepsRun == nil {
                Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            // Who moves it, said once, when it is not your account (prd
            // §1720): Shield takes it from the wallet it scored.
            let who = move.viaCoSigner.map { String(localized: "From your co-signer (\(AddressTail.short($0)))") }
            return [who, String(localized: "Through Shield"), String(localized: "0.5% fee"), String(localized: "5 to 15 minutes"), gas]
                .compactMap { $0 }.joined(separator: " · ")
        case .send:
            if move.toEthereum {
                return [String(localized: "Through Shield"), String(localized: "0.5% fee"), String(localized: "finish on Ethereum in about an hour")]
                    .joined(separator: " · ")
            }
            return String(localized: "Who, what and how much stay private · about 20 seconds")
        }
    }

    private func problemLine(_ problem: AztecMove.AmountProblem) -> String {
        switch problem {
        case .moreThanHeld(let have): String(localized: "You have \(have).")
        case .overShieldCap(let cap): String(localized: "Shield moves up to $\(cap) at a time for your score.")
        }
    }

    private var fundsLine: String {
        let gasShort = move.bringsGas && (Decimal(string: move.safeHeld["AZTEC"] ?? "0") ?? 0) < (Decimal(string: AztecGas.rideAlong) ?? 0)
        if gasShort, !(move.holdings.isEmpty) {
            return String(localized: "Your Aztec account needs 30 AZTEC as gas the first time.")
        }
        return String(localized: "Shield moves USDC or WETH from your account on Ethereum.")
    }

    /// How long the send took, tap to block, so the next wait feels known (prd §1700w).
    private var sentTotal: Int? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move, run.ok == true else { return nil }
        return run.total
    }

    private var doneLine: String {
        switch move.mode {
        case .deposit: String(localized: "On its way: Aztec carries it in minutes, then it is yours.")
        case .send:
            move.toEthereum ? String(localized: "Proved. In about an hour Needs you offers Finish on Ethereum.")
                : sentTotal.map { String(localized: "Sent privately · \($0) s") } ?? String(localized: "Sent privately.")
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
            case .token: tokens
            case .recipient: recipients
            }
        }
        .padding(.vertical, DS.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The tokens there are to move, each with how much (prd §1700q).
    private var tokens: some View {
        ForEach(move.holdings) { holding in
            let places = holding.symbol == "USDC" ? 6 : 18
            let shown = PrivateMoney.figure(holding.units, decimals: places, symbol: holding.symbol)
            let picked = holding.symbol == move.symbol
            Button {
                withAnimation(DS.Motion.standard) { move.pick(holding.symbol); open = nil }
                DSHaptic.selection()
            } label: {
                HStack(spacing: DS.Space.s3) {
                    AssetMark(name: holding.symbol, size: DS.Face.list)
                    Text(verbatim: holding.symbol).dsText(.body17)
                        .foregroundStyle(picked ? DS.textSecondary : DS.textPrimary)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: shown).dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
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
        // **YOUR ADDRESSES FIRST (prd §1700r, user: "it doesn't suggest my
        // existing addresses" — "it should").** Your account on Ethereum
        // (an exit to yourself), then the address book as Send's To lists it,
        // filtered by what is typed; the field and Paste stay for anyone else.
        ForEach(suggestions, id: \.address) { s in
            Button { take(s.address) } label: {
                HStack(spacing: DS.Space.s3) {
                    WalletFace(address: s.address, size: DS.Face.list, circular: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: s.name).dsText(MoveSentence.choiceRung).foregroundStyle(DS.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(verbatim: s.line).dsText(.body17).foregroundStyle(DS.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: DS.Space.s2)
                }
                .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
        }
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

    private struct Suggestion { let name: String; let line: String; let address: String }

    /// Your account, then the book's Ethereum addresses (prd §1700r).
    private var suggestions: [Suggestion] {
        let q = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let typingAnAddress = AztecAddressText.isAztec(q) || PrivateMoney.isAddress(q)
        guard !typingAnAddress else { return [] }
        var out: [Suggestion] = []
        let mine = YourAccountKey.address
        let yours = String(localized: "Your account")
        if let mine, q.isEmpty || yours.lowercased().contains(q) || mine.lowercased().hasPrefix(q) {
            out.append(Suggestion(name: yours, line: String(localized: "Ethereum · \(AddressTail.short(mine))"), address: mine))
        }
        for e in AddressBook.shared.all where ENS.isHexAddress(e.address)
            && !(mine.map { WalletWatch.sameAddress($0, e.address) } ?? false)
            && (q.isEmpty || e.name.lowercased().contains(q) || e.address.lowercased().hasPrefix(q)) {
            out.append(Suggestion(name: e.name, line: AddressTail.short(e.address), address: EIP55.checksum(e.address)))
            if out.count >= 20 { break }
        }
        return out
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
        move.stage == .ready && move.amountOK && (move.mode == .deposit || move.toAztec || move.toEthereum) && !DemoMode.isActive
    }

    /// This sentence's send, while it works, once it failed with its steps, and
    /// once it is done (prd §1700x): the rows stand in the foot above the act.
    private var stepsRun: PrivateSendSteps.Run? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move else { return nil }
        switch move.stage {
        case .working: return run
        case .failed: return run.ok == false ? run : nil
        case .done: return run.ok == true ? run : nil
        default: return nil
        }
    }

    private var foot: some View {
        VStack(spacing: 0) {
            // ONE THING AT A TIME over the act (prd §1700y, agreed with the
            // Railgun session): the steps while it works and after, the
            // warming row while the balance is read, the cost while ready.
            if let run = stepsRun {
                // Face ID came before a send's clock; a move-in signs inside it.
                PrivateStepRows(run: run, confirmed: move.mode == .send ? String(localized: "Confirmed with Face ID") : nil)
                    .padding(.bottom, DS.Space.s3)
                    .transition(.opacity)
            } else if move.stage == .reading, move.mode == .send, let since = move.readingSince {
                PrivateWarmingRow(since: since)
                    .padding(.bottom, DS.Space.s1)
                    .transition(.opacity)
            } else if move.stage == .ready, move.amountOK {
                PrivateCostLine(cost: move.cost, tail: move.costTail, fallback: readyLine)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Space.s1)
                    .transition(.opacity)
            }
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
                    footButton(DemoMode.isActive ? String(localized: "Not in the demo") : footVerb, on: ready) {
                        open = nil
                        typing = false
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

    /// Half · All (prd §1700y): each types its amount, exact; one Shield
    /// would refuse, or nothing to halve, is not drawn (§83).
    @ViewBuilder private var chips: some View {
        let picks = AztecMove.Pick.allCases.compactMap { p in move.amount(for: p).map { (pick: p, value: $0) } }
        if !picks.isEmpty {
            HStack(spacing: DS.Space.s2) {
                ForEach(picks, id: \.pick) { item in
                    let on = move.amount == item.value
                    Button {
                        typing = false
                        move.amount = item.value
                        DSHaptic.selection()
                    } label: {
                        Chip(text: item.pick == .half ? String(localized: "Half") : String(localized: "All"), selected: on)
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
        }
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

    private func footButton(_ word: String, on: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(verbatim: word)
                .dsText(.heading34)
                .foregroundStyle(on ? DS.pickInk : DS.textTertiary)
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
