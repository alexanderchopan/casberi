import SwiftUI

/// **YOUR PRIVATE BALANCE ON ETHEREUM, FOR EVERY OTHER TOKEN (prd §1713,
/// §1721).** The sentence Move draws when the token is neither ETH nor USDC:
/// Railgun holds it, and the person never chose that (§1713 item 1).
///
/// - **In** (`.deposit`): picked as "Your private balance · Ethereum" with a
///   token on Ethereum already in the sentence. "Send 12 DAI to your private
///   balance on Ethereum." Your account approves and shields in one Face ID
///   operation (`RailgunPocket.shield`). The amount is typed (prd §1727);
///   it moves in at $10 worth or more (§1713 item 2), and a token Casberi
///   cannot price is not offered.
/// - **Out** (`.takeBack`): picked from a Railgun row (Send's token list,
///   Holdings). "Send 400 DAI from your private balance to your account."
///   your account sends it. To someone else ("…to ...e07a.") a Railgun
///   broadcaster sends it, paid inside Railgun in a token it takes, so no
///   account of yours is on the transaction (§1721 item 3, §1723). A wallet
///   holding none of those tokens is offered a little ETH for fees first.
///
/// The foot says what Railgun takes, read from its proxy (item 6), and
/// "Powered by Railgun".
@MainActor
@Observable
final class RailgunMove {
    enum Mode: Equatable { case deposit, takeBack }

    /// What opened the sentence: a token, and which way.
    struct Opening: Equatable {
        var contract: String?
        var takeBack: Bool
        /// Out to someone else; nil is your account.
        var recipient: String? = nil
    }

    enum Stage: Equatable {
        case reading
        /// Under the $10 minimum to move in, or nothing private to take back.
        case nothing
        /// A send to someone else, asking a broadcaster what it costs.
        case quoting
        /// A send to someone else with nothing to pay a broadcaster in.
        case needsFees
        case ready
        case working(String)
        case done(String)
        case failed(String)
    }

    /// What moves: a token and the typed amount of it.
    struct Option: Equatable {
        let contract: String
        let symbol: String
        let decimals: Int
        /// Base units, decimal.
        let units: String
    }

    /// A token that can move, and how much of it there is.
    struct Holding: Equatable, Identifiable {
        let contract: String
        let symbol: String
        let decimals: Int
        /// Base units, decimal.
        let units: String
        let price: Double?
        var id: String { contract.lowercased() }
    }

    /// **ANY AMOUNT (prd §1727, user: "it should let me enter in a custom
    /// amount").** What stands in a typed amount's way is said, never a list
    /// of allowed amounts.
    enum AmountProblem: Equatable {
        case moreThanHeld(String)
        /// Moving in under $10 worth (§1713 item 2).
        case underMinimum
    }

    var mode: Mode = .deposit
    var stage: Stage = .reading
    /// The token asked for when the sentence opened.
    var wanted: String?
    private(set) var holdings: [Holding] = []
    /// The token picked, by contract.
    private(set) var token: String?
    /// The amount, typed.
    var amount = ""
    private(set) var feeBps: Int?
    /// Out to someone else (prd §1721 item 3); nil, or your own account's
    /// address, is taking it back.
    var recipient: String?
    /// The broadcaster's terms for the picked amount.
    private(set) var quote: RailgunEngineWire.Quote?
    /// The fee token's symbol and decimals, for the line.
    private var feeToken: (symbol: String, decimals: Int)?
    /// No broadcaster can carry it (none answered, or nothing to pay one
    /// in), and your private ETH pays a fresh sender's gas (prd §1726).
    private(set) var viaFresh = false

    /// The token you hold on Ethereum worth the most, when none reaches the
    /// $10 floor: the sentence names it (prd §1728 item 2).
    struct Short: Equatable { let symbol: String; let usd: Double }
    private(set) var underFloor: Short?
    /// Gas now (wei) and ETH's price, for the cost line (prd §1728 item 6).
    private var gasPriceWei: Decimal?
    private var ethUSD: Double?

    /// A send to someone else: a broadcaster sends it, never your account.
    var toSomeoneElse: Bool {
        guard mode == .takeBack, let recipient, PrivateMoney.isAddress(recipient) else { return false }
        return recipient.lowercased() != YourAccountKey.address?.lowercased()
    }

    static var floorUSD: Double { RailgunRouting.floorUSD }

    var holding: Holding? { holdings.first { $0.contract.lowercased() == token?.lowercased() } }

    /// What was typed, in the token's base units: a comma is a decimal
    /// point, and a trailing point (mid-typing) is ignored.
    var units: String? {
        guard let holding else { return nil }
        var typed = amount.replacingOccurrences(of: ",", with: ".")
        if typed.hasSuffix(".") { typed.removeLast() }
        return PrivateMoney.baseUnits(typed, decimals: holding.decimals)
    }

    /// The token and the typed amount, once there is more than nothing.
    var picked: Option? {
        guard let h = holding, let units, let want = Decimal(string: units), want > 0 else { return nil }
        return Option(contract: h.contract, symbol: h.symbol, decimals: h.decimals, units: units)
    }

    var amountProblem: AmountProblem? {
        guard let h = holding, let units, let want = Decimal(string: units), want > 0 else { return nil }
        if let have = Decimal(string: h.units), want > have {
            return .moreThanHeld(RailgunHoldings.figure(h.units, decimals: h.decimals) + " " + h.symbol)
        }
        if mode == .deposit, !RailgunRouting.meetsFloor(units: units, decimals: h.decimals, price: h.price, floorUSD: Self.floorUSD) {
            return .underMinimum
        }
        return nil
    }

    var amountOK: Bool { picked != nil && amountProblem == nil }

    /// Picks the token; the typed amount stays.
    func pick(_ h: Holding) {
        token = h.contract
        amountChanged()
    }

    private var quoteTask: Task<Void, Never>?

    /// A new amount or token: any quote is for the old one. A send to
    /// someone else asks a broadcaster again once typing pauses.
    func amountChanged() {
        quoteTask?.cancel()
        quote = nil
        switch stage {
        case .quoting, .needsFees, .failed: stage = .ready
        case .ready: break
        default: return
        }
        guard toSomeoneElse, amountOK else { return }
        stage = .quoting
        quoteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.requote()
        }
    }

    var acting: Bool { if case .working = stage { true } else { false } }

    /// Reads what can move: your account's tokens on Ethereum (in) or your
    /// Railgun wallet's spendable tokens (back), and Railgun's fee.
    func read() async {
        stage = .reading
        quoteTask?.cancel()
        quote = nil
        // The demo reads nothing: 0.05 gwei and $3,000 an ETH.
        let demo = DemoMode.isActive
        let signature = mode == .deposit ? "shieldFee()" : "unshieldFee()"
        async let fee = Self.readFee(signature)
        async let gas: Decimal? = demo ? Decimal(50_000_000) : RailgunPocket.gasPriceWei()
        async let eth: Double? = demo ? 3_000 : Self.ethPrice()
        feeBps = await fee
        gasPriceWei = await gas
        ethUSD = await eth
        underFloor = nil
        var found: [Holding] = []
        switch mode {
        case .deposit where DemoMode.isActive:
            // The demo's account holds only ETH and USDC on Ethereum; its
            // sentence shows DAI moving in, at $1, and sends nothing.
            // `-railgunDemoUnder YES` holds $7.52 of it, under the floor.
            let under = UserDefaults.standard.bool(forKey: "railgunDemoUnder")
            if under {
                underFloor = Short(symbol: "DAI", usd: 7.52)
            } else {
                found = [Holding(contract: RailgunHoldings.demo[0].contract, symbol: "DAI", decimals: 18,
                                 units: "120000000000000000000", price: 1)]
            }
        case .deposit:
            guard let account = YourAccountKey.address else {
                stage = .nothing; return
            }
            let net = YourAccountOp.ethereum
            let dollar = YourAccountOp.dollar(on: net).contract?.lowercased()
            for h in await YourAccountTokens.held(account, on: net) {
                guard let contract = h.token.contract, contract.lowercased() != dollar,
                      RailgunRouting.goesToRailgun(symbol: h.token.symbol, contract: contract, chainId: net.chainId),
                      let price = h.price, price > 0 else { continue }
                guard RailgunRouting.meetsFloor(units: h.units, decimals: h.token.decimals, price: price, floorUSD: Self.floorUSD) else {
                    let usd = YourAccountOp.dollars(h.units, decimals: h.token.decimals, price: price)
                    if usd >= 0.01, usd > (underFloor?.usd ?? 0) { underFloor = Short(symbol: h.token.symbol, usd: usd) }
                    continue
                }
                found.append(Holding(contract: contract, symbol: h.token.symbol, decimals: h.token.decimals,
                                     units: h.units, price: price))
            }
        case .takeBack:
            let store = RailgunHoldings.shared
            // Prices for the dollars and the cost, never a sync (prd §1728).
            await store.readPrices()
            found = store.spendableShown.map {
                Holding(contract: $0.contract, symbol: $0.symbol, decimals: $0.decimals,
                        units: $0.spendable, price: store.prices[$0.symbol.uppercased()])
            }
        }
        holdings = found
        let keep = found.first { $0.contract.lowercased() == token?.lowercased() }
            ?? found.first { $0.contract.lowercased() == wanted?.lowercased() }
            ?? found.first
        token = keep?.contract
        if DemoMode.isActive, amount.isEmpty { amount = "25" }
        stage = keep == nil ? .nothing : .ready
        amountChanged()
        #if DEBUG
        if DemoMode.isActive, UserDefaults.standard.string(forKey: "railgunStepsPreview") != nil {
            Task { await previewSteps() }
        }
        #endif
    }

    /// Asks a broadcaster what sending the picked amount costs. The demo
    /// asks nothing: its fee is 0.14 USDC.
    func requote() async {
        guard let picked, let to = recipient, toSomeoneElse else { return }
        quote = nil
        viaFresh = false
        stage = .quoting
        if DemoMode.isActive {
            // `-railgunDemoFresh YES` shows the fresh sender's line (§1726).
            viaFresh = UserDefaults.standard.bool(forKey: "railgunDemoFresh")
            stage = .ready
            return
        }
        do {
            let q = try await RailgunPocket.quote(token: picked.contract, amount: picked.units, to: to)
            guard self.picked == picked else { return }
            // The fee is named or the send is not offered (§83): the
            // holdings reading, else the token's own record.
            if let held = RailgunHoldings.shared.shown.first(where: { $0.id == q.feeToken.lowercased() }) {
                feeToken = (held.symbol, held.decimals)
            } else if let listed = await YourAccountTokens.lookUp(q.feeToken, on: YourAccountOp.ethereum) {
                feeToken = (listed.token.symbol, listed.token.decimals)
            } else {
                feeToken = nil
            }
            // Its price, for the cost in dollars (prd §1728 item 6); WETH
            // reads ETH's.
            feePriceUSD = nil
            if let symbol = feeToken?.symbol.lowercased(), symbol != "weth" {
                let prices = await MainnetPrices.prices(for: [symbol])
                feePriceUSD = prices[symbol] ?? prices[symbol.uppercased()]
            }
            guard self.picked == picked else { return }
            quote = q
            stage = feeToken == nil ? .failed(String(localized: "Railgun did not answer. Nothing was sent.")) : .ready
        } catch let failure as RailgunPocket.Failure where [.noFeeToken, .feeTokenPending, .noBroadcaster].contains(failure) {
            // A fresh sender carries it when your private ETH pays its gas.
            let covered = await RailgunPocket.privateGasCovers()
            guard self.picked == picked else { return }
            if covered {
                viaFresh = true
                stage = .ready
            } else {
                stage = failure == .noFeeToken ? .needsFees : .failed(Self.words(failure))
            }
        } catch {
            guard self.picked == picked else { return }
            stage = .failed(Self.words(error))
        }
    }

    // MARK: - In dollars (prd §1728 items 1 and 6)

    static func ethPrice() async -> Double? {
        let prices = await MainnetPrices.prices(for: ["eth"])
        return prices["eth"] ?? prices["ETH"]
    }

    /// "$10": the floor, as the sentence says it.
    static var floorText: String {
        floorUSD.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// "$25.00": the one way this sentence writes dollars.
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// A token amount in base units, written whole and exact ("7.525").
    static func plain(_ units: Decimal, decimals: Int) -> String {
        var whole = units / pow(10, decimals), cut = Decimal()
        NSDecimalRound(&cut, &whole, decimals, .down)
        return NSDecimalNumber(decimal: cut).stringValue
    }

    /// The typed amount in dollars, where the token has a price.
    var amountUSD: Double? {
        guard let h = holding, let price = h.price, let units, (Decimal(string: units) ?? 0) > 0 else { return nil }
        return YourAccountOp.dollars(units, decimals: h.decimals, price: price)
    }

    /// The line under the sentence: "$25.00 · from $10 · you have $120.00".
    /// No price: what you have, in the token.
    var amountLine: String? {
        guard let h = holding else { return nil }
        let have: String = h.price.map { String(localized: "you have \(Self.usd(YourAccountOp.dollars(h.units, decimals: h.decimals, price: $0)))") }
            ?? String(localized: "you have \(RailgunHoldings.figure(h.units, decimals: h.decimals) + " " + h.symbol)")
        var parts: [String] = []
        if let amountUSD { parts.append(Self.usd(amountUSD)) }
        if mode == .deposit { parts.append(String(localized: "\(Self.floorText) or more")) }
        parts.append(have)
        return parts.joined(separator: " · ")
    }

    /// The amounts a chip types: $10 worth (moving in only, where the token
    /// has a price), half, all. Exact, in the token's own places.
    enum Pick: CaseIterable { case floor, half, all }

    func amount(for pick: Pick) -> String? {
        guard let h = holding, let held = Decimal(string: h.units), held > 0 else { return nil }
        switch pick {
        case .floor:
            guard mode == .deposit, let price = h.price, price > 0 else { return nil }
            // $10 worth, rounded UP at six places so it never falls short.
            var tokens = Decimal(Self.floorUSD) / Decimal(price), up = Decimal()
            NSDecimalRound(&up, &tokens, min(h.decimals, 6), .up)
            guard up * pow(10, h.decimals) <= held else { return nil }
            return NSDecimalNumber(decimal: up).stringValue
        case .half:
            var half = held / 2, down = Decimal()
            NSDecimalRound(&down, &half, 0, .down)
            guard down > 0 else { return nil }
            // Half under the floor is no choice moving in (§83).
            if mode == .deposit, !RailgunRouting.meetsFloor(units: NSDecimalNumber(decimal: down).stringValue,
                                                            decimals: h.decimals, price: h.price, floorUSD: Self.floorUSD) { return nil }
            return Self.plain(down, decimals: h.decimals)
        case .all:
            return Self.plain(held, decimals: h.decimals)
        }
    }

    /// What this move costs, in dollars and in its parts (prd §1728 item 6):
    /// Railgun's cut of the amount, then whoever pays the gas — your
    /// account, a broadcaster in its fee token, or your private ETH for a
    /// fresh sender. nil where a price is missing: the line then says
    /// Railgun's percentage, as before.
    var cost: PrivateCost? {
        guard let picked, let h = holding, let price = h.price, let bps = feeBps,
              let units = Decimal(string: picked.units) else { return nil }
        var cutUnits = units * Decimal(bps) / 10_000, cut = Decimal()
        NSDecimalRound(&cut, &cutUnits, 0, .down)
        let cutText = NSDecimalNumber(decimal: cut).stringValue
        var usd = YourAccountOp.dollars(cutText, decimals: h.decimals, price: price)
        var parts = [PrivateCost.Part(words: String(localized: "Railgun"),
                               figure: RailgunHoldings.figure(cutText, decimals: h.decimals) + " " + h.symbol)]
        func gasUSD(_ gas: Int, plus extraWei: Decimal = 0) -> Double? {
            guard let gasPriceWei, let ethUSD else { return nil }
            let wei = Decimal(gas) * gasPriceWei + extraWei
            return NSDecimalNumber(decimal: wei / pow(10, 18)).doubleValue * ethUSD
        }
        switch mode {
        case .deposit:
            guard let gas = gasUSD(RailgunPocket.shieldGas) else { return nil }
            usd += gas
            parts.append(.init(words: String(localized: "Gas, from your account"), figure: String(localized: "about \(Self.usd(gas))")))
        case .takeBack where toSomeoneElse && viaFresh:
            guard let gas = gasUSD(RailgunPocket.unshieldGas, plus: RailgunPocket.lastRelayerFeeWei ?? 0) else { return nil }
            usd += gas
            parts.append(.init(words: String(localized: "A new address of yours sends it, its gas from your private ETH"),
                               figure: String(localized: "about \(Self.usd(gas))")))
        case .takeBack where toSomeoneElse:
            guard let feeWords, let feeUSD = broadcasterFeeUSD else { return nil }
            usd += feeUSD
            parts.append(.init(words: String(localized: "A Railgun broadcaster sends it"), figure: feeWords))
        case .takeBack:
            guard let gas = gasUSD(RailgunPocket.unshieldGas) else { return nil }
            usd += gas
            parts.append(.init(words: String(localized: "Gas, from your account"), figure: String(localized: "about \(Self.usd(gas))")))
        }
        return PrivateCost(usd: usd, parts: parts)
    }

    /// The broadcaster's fee in dollars: WETH at ETH's price, any other fee
    /// token at its own (`feePriceUSD`, read with the quote).
    private var broadcasterFeeUSD: Double? {
        if DemoMode.isActive, toSomeoneElse { return 0.14 }
        guard let q = quote, let feeToken else { return nil }
        let price = feeToken.symbol.uppercased() == "WETH" ? ethUSD : feePriceUSD
        guard let price else { return nil }
        return YourAccountOp.dollars(PrivateMoney.decimal(hex: q.fee), decimals: feeToken.decimals, price: price)
    }
    private var feePriceUSD: Double?

    /// The broadcaster's fee as the line says it: "0.14 USDC".
    var feeWords: String? {
        if DemoMode.isActive, toSomeoneElse { return "0.14 USDC" }
        guard let q = quote, let feeToken else { return nil }
        return RailgunHoldings.figure(PrivateMoney.decimal(hex: q.fee), decimals: feeToken.decimals) + " " + feeToken.symbol
    }

    /// About $10 of ETH, as WETH, for broadcasters' fees.
    func addFees() async {
        guard !DemoMode.isActive else { return }
        do {
            let prices = await MainnetPrices.prices(for: ["eth"])
            guard let price = prices["eth"] ?? prices["ETH"], price > 0 else {
                stage = .failed(String(localized: "Couldn't price ETH. Nothing was sent.")); return
            }
            var wei = Decimal(RailgunRouting.nice(Self.floorUSD / price)) * pow(10, 18), whole = Decimal()
            NSDecimalRound(&whole, &wei, 0, .up)
            // A shield like any move-in: its rows are signed (§1728 item 5).
            PrivateSendSteps.shared.forget(.move)
            unlockedFirst = false
            PrivateSendSteps.shared.begin(.move, plan: .signed(.ethereum))
            stage = .working(String(localized: "Sending…"))
            _ = try await RailgunPocket.addFees(wei: NSDecimalNumber(decimal: whole).stringValue) { [weak self] s in
                await self?.say(s)
            }
            PrivateSendSteps.shared.finish()
            stage = .done(String(localized: "On its way: private in about an hour. Then send again."))
            await RailgunHoldings.shared.refresh(force: true)
        } catch {
            PrivateSendSteps.shared.fail(Self.words(error))
            stage = .failed(Self.words(error))
        }
    }

    /// Railgun's fee off its proxy (`shieldFee()`/`unshieldFee()`, basis
    /// points), never a constant (§1713 item 6). The demo reads nothing:
    /// 25, the value measured on 2026-11-07.
    static func readFee(_ signature: String) async -> Int? {
        if DemoMode.isActive { return 25 }
        guard let hex = try? await YourAccountChain.ethCall(YourAccountOp.ethereum, to: RailgunPocket.proxy,
                                                           data: YourAccount.sel(signature)) else { return nil }
        return Int(PrivateMoney.decimal(hex: hex))
    }

    /// Moves it: in through your account's shield, or back to your account.
    /// **THE STEPS, AS AZTEC'S (prd §1728 item 5, §1700x).** One model and
    /// one set of rows for every private send (`PrivateSendSteps`,
    /// `PrivateStepRows`), standing in the foot over the act. A move-in is
    /// signed: Checking · Signing · Sent on Ethereum. A send to someone is
    /// proved after Face ID: Checking · Proving on this iPhone · Sent on
    /// Ethereum. Taking back is proved, then signed by your account. The
    /// engine says when a proof starts and a send leaves (`step` lines);
    /// your account's stages say the signing.
    static let takeBackPlan = PrivateSendSteps.Plan(steps: [.checking, .proving, .signing, .sent(.ethereum)])

    /// Moves it: in through your account's shield, or back to your account.
    func run() async {
        guard let picked, amountOK, !DemoMode.isActive else { return }
        let steps = PrivateSendSteps.shared
        // Last send's rows go; this send's start with it.
        steps.forget(.move)
        unlockedFirst = false
        do {
            switch mode {
            case .deposit:
                steps.begin(.move, plan: .signed(.ethereum))
                stage = .working(String(localized: "Sending…"))
                _ = try await RailgunPocket.shield(token: picked.contract, amount: picked.units) { [weak self] s in
                    await self?.say(s)
                }
                steps.finish()
                stage = .done(String(localized: "On its way: private in about an hour."))
            case .takeBack where toSomeoneElse && viaFresh:
                stage = .working(String(localized: "Confirm with Face ID"))
                _ = try await RailgunPocket.sendFromFresh(token: picked.contract, amount: picked.units, to: recipient ?? "",
                                                          unlocked: { [weak self] in self?.started(.send(.ethereum)) }) { _ in }
                steps.finish()
                stage = .done(String(localized: "Sent privately."))
            case .takeBack where toSomeoneElse:
                guard let q = quote else { return }
                stage = .working(String(localized: "Confirm with Face ID"))
                _ = try await RailgunPocket.send(q, unlocked: { [weak self] in self?.started(.send(.ethereum)) })
                quote = nil
                steps.finish()
                stage = .done(String(localized: "Sent privately."))
            case .takeBack:
                guard let account = YourAccountKey.address else { stage = .failed(String(localized: "No account on this iPhone")); return }
                stage = .working(String(localized: "Confirm with Face ID"))
                _ = try await RailgunPocket.send(token: picked.contract, amount: picked.units, to: account,
                                                 unlocked: { [weak self] in self?.started(Self.takeBackPlan) }) { [weak self] s in
                    await self?.say(s)
                }
                steps.finish()
                stage = .done(String(localized: "Back in your account."))
            }
            DSHaptic.success()
            await RailgunHoldings.shared.refresh(force: true)
        } catch {
            // The rows keep the failure on the step it reached (§1700x).
            steps.fail(Self.words(error))
            stage = .failed(Self.words(error))
        }
    }

    #if DEBUG
    /// `-railgunStepsPreview send|in|fail` (prd §1728 item 5): in the demo,
    /// plays one run through the real model, sentence and foot: a send to
    /// someone (Face ID, checking 2 s, proving 8 s, handed over), a move-in
    /// (checking, signing, sent), or a send that fails while proving. Nothing
    /// is sent; NSLogs each step.
    func previewSteps() async {
        guard DemoMode.isActive, let kind = UserDefaults.standard.string(forKey: "railgunStepsPreview") else { return }
        let steps = PrivateSendSteps.shared
        func step(_ key: PrivateSendSteps.Key, after s: Double) async {
            try? await Task.sleep(for: .seconds(s))
            steps.mark(key)
            NSLog("railgunStepsPreview| %@ | %@", kind, key.rawValue)
        }
        try? await Task.sleep(for: .seconds(3))
        steps.forget(.move)
        unlockedFirst = false
        if kind == "in" {
            steps.begin(.move, plan: .signed(.ethereum))
            stage = .working(String(localized: "Sending…"))
            await step(.signing, after: 2)
            await step(.sent, after: 3)
            try? await Task.sleep(for: .seconds(6))
            steps.finish()
            stage = .done(String(localized: "On its way: private in about an hour."))
            return
        }
        started(.send(.ethereum))
        await step(.proving, after: 2)
        if kind == "fail" {
            try? await Task.sleep(for: .seconds(5))
            steps.fail(Self.words(RailgunPocket.Failure.noBroadcaster))
            stage = .failed(Self.words(RailgunPocket.Failure.noBroadcaster))
            return
        }
        await step(.sent, after: 8)
        try? await Task.sleep(for: .seconds(3))
        steps.finish()
        stage = .done(String(localized: "Sent privately."))
    }
    #endif

    /// Face ID said yes: the rows' clock starts, and "Confirmed with Face
    /// ID" leads them.
    private func started(_ plan: PrivateSendSteps.Plan) {
        unlockedFirst = true
        PrivateSendSteps.shared.begin(.move, plan: plan)
        stage = .working(String(localized: "Sending…"))
    }

    /// Face ID came before this send's clock (a send out, never a move-in).
    private(set) var unlockedFirst = false

    /// Your account's stages: its Face ID and co-signer are the Signing
    /// step, its sending the Sent one.
    private func say(_ s: YourAccountChain.Stage) {
        let steps = PrivateSendSteps.shared
        switch s {
        case .preparing: break
        case .signing:
            steps.mark(.signing)
            stage = .working(String(localized: "Confirm with Face ID"))
        case .cosigning:
            steps.mark(.signing)
            stage = .working(String(localized: "Waiting for your co-signer"))
        case .sending, .landing:
            steps.mark(.sent)
            stage = .working(String(localized: "Sending…"))
        }
    }

    /// Says what went wrong (prd §1727): your account's own reason (Face ID,
    /// gas, Ethereum), never folded into "Railgun did not answer", and the
    /// cause logged whatever the words.
    static func words(_ error: Error) -> String {
        NSLog("railgunMove| failed | %@", String(describing: error))
        // The broadcaster may already have it: never "nothing was sent".
        if (error as? RailgunEngineWire.Failure)?.name == "BroadcastUnconfirmed" {
            return String(localized: "The broadcaster did not confirm. Check Activity before sending again.")
        }
        if let failure = error as? YourAccountChain.Failure { return failure.message }
        if error is PrivateRootKey.Failure {
            return String(localized: "Face ID did not open the private account")
        }
        if error is URLError {
            return String(localized: "Ethereum could not be reached")
        }
        return switch error as? RailgunPocket.Failure {
        case .untrusted?: String(localized: "Railgun's records did not check out. Nothing was sent.")
        case .nothingSpendable?: String(localized: "Not private yet: Railgun lists it in about an hour.")
        case .notRailgun?: String(localized: "That was not Railgun's call. Nothing was sent.")
        case .noAccount?: String(localized: "No account on this iPhone")
        case .noRoot?, .curve?: String(localized: "Face ID did not open the private account")
        case .noBroadcaster?: String(localized: "No Railgun broadcaster answered. Nothing was sent.")
        case .feeNotCovered?: String(localized: "That leaves nothing for the broadcaster's fee. Send a little less.")
        case .noFeeToken?: String(localized: "A broadcaster takes its fee in WETH or USDC, and your private balance holds neither.")
        case .feeTokenPending?: String(localized: "Your ETH for fees is private in about an hour. Send then.")
        case .noPrivateGas?: String(localized: "No broadcaster can send it, and your private ETH can't pay its gas. Nothing was sent.")
        case .gasOnItsWay?: String(localized: "Its gas is on its way from your private ETH. Try again in a minute.")
        default: String(localized: "Railgun did not answer. Nothing was sent.")
        }
    }
}

struct MoveRailgunSentence<Head: View>: View {
    @Bindable var move: RailgunMove
    var inTray = false
    var leave: (MovePrivateLeave) -> Void = { _ in }
    @ViewBuilder let head: () -> Head

    /// The token list is open.
    @State private var open = false
    @FocusState private var typing: Bool
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if !leadsWithVerb {
                    head().padding(.bottom, DS.Space.s4)
                }
                MoveFlow { sentence }
                    // The sentence says the move and is no control (prd
                    // §1781): its choices are the rows under it.
                    .allowsHitTesting(false)
                    .animation(DS.Motion.standard, value: move.stage)
                    .animation(DS.Motion.standard, value: move.holding)
                Group {
                    // The tokens are a menu on their row (prd §1784).
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        MoveChoiceRows(rows: choiceRows,
                                       open: Binding(get: { open && picking ? "token" : nil }, set: { if $0 == nil { open = false } })) { _ in tokens }
                        line
                    }
                }
                .padding(.top, DS.Space.s6)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .onChange(of: open) { _, now in if now { chrome.moveTall = true } }
        .task(id: move.mode) { await move.read() }
    }

    private var isDone: Bool { if case .done = move.stage { true } else { false } }

    /// The recipient can be picked again while nothing is moving.
    private var picking: Bool {
        switch move.stage {
        case .ready, .quoting, .needsFees, .failed: true
        default: false
        }
    }

    /// The sentence draws the verb itself: never above it as well (a failed
    /// send drew "Send" twice).
    private var leadsWithVerb: Bool {
        switch move.stage {
        case .ready, .working, .quoting, .needsFees, .failed: true
        default: false
        }
    }

    private var figure: String {
        guard let p = move.picked else { return "" }
        return RailgunHoldings.figure(p.units, decimals: p.decimals) + " " + p.symbol
    }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(String(localized: "Reading…"), ink: DS.textSecondary)
        case .nothing:
            if move.mode == .deposit, let short = move.underFloor {
                // Your real number, said once (prd §1728 item 2).
                MovePhrase(String(localized: "Moving in starts at \(RailgunMove.floorText)."), ink: DS.textSecondary)
                MovePhrase(String(localized: "Your \(short.symbol) is \(RailgunMove.usd(short.usd))."), ink: DS.textSecondary)
            } else {
                MovePhrase(move.mode == .deposit
                           ? String(localized: "Moving to your private balance takes $10 or more.")
                           : String(localized: "Nothing private to take back yet."), ink: DS.textSecondary)
            }
        default:
            if !isDone { head() }
            if picking {
                // The amount typed, the token its own word (prd §1727).
                MoveClause { amountField }
                MoveClause {
                    Button { toggle() } label: {
                        MoveWord(move.holding?.symbol ?? "", ink: MoveSentence.settledInk)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("Token, \(move.holding?.symbol ?? "")"))
                    .accessibilityHint(Text("Picks the token"))
                }
            } else {
                MoveClause(glue: isDone ? String(localized: "Sent") : nil) {
                    MoveWord(figure, ink: DS.textPrimary)
                        .accessibilityLabel(Text("Amount, \(figure)"))
                }
            }
            switch move.mode {
            case .deposit:
                MoveWordsClause(glue: String(localized: "to"), words: String(localized: "your private balance"),
                                ink: DS.textPrimary,
                                action: { if move.stage == .ready { leave(.pickRecipient) } },
                                hint: Text("Picks who it goes to"))
                MovePhrase(String(localized: "Ethereum."), glue: String(localized: "on"))
            case .takeBack:
                MoveWordsClause(glue: String(localized: "from"), words: String(localized: "your private balance"),
                                ink: DS.textPrimary,
                                action: { if move.stage == .ready { leave(.switchOff) } },
                                hint: Text("Picks where it comes from"))
                // Your account (your account sends it), or someone else (a
                // broadcaster sends it, §1721 item 3); a tap picks who.
                MoveWordsClause(glue: String(localized: "to"),
                                words: move.toSomeoneElse ? YourAccount.short(move.recipient ?? "") + "." : String(localized: "your account."),
                                ink: DS.textPrimary,
                                action: { if picking { leave(.pickRecipient) } },
                                hint: Text("Picks who it goes to"))
            }
        }
    }

    // MARK: - The line

    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready where move.amountProblem != nil:
            Text(verbatim: problemLine).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        case .ready, .quoting:
            // The amount in dollars, the floor beside it, and three choices
            // (prd §1728 item 1).
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if let words = move.amountLine {
                    Text(verbatim: words).dsText(.body17).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                chips
            }
        case .working(let words):
            // The steps stand in the foot; the sentence stands alone.
            if stepsRun == nil {
                Text(verbatim: words).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .nothing where move.mode == .deposit && move.underFloor != nil:
            // Get more of it (prd §1728 item 2): Receive, or Swap.
            if let short = move.underFloor {
                VStack(alignment: .leading, spacing: 0) {
                    DSDoorRow(icon: "arrow.down.to.line", title: Text("Receive more \(short.symbol)")) { leave(.receive) }
                    DSDoorRow(icon: "arrow.left.arrow.right", title: Text("Swap for more \(short.symbol)")) { leave(.swap) }
                }
            }
        case .failed(let words):
            // A failure the rows carry is said once, on its step.
            if stepsRun == nil {
                Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .needsFees:
            Text("A broadcaster takes its fee in WETH or USDC, and your private balance holds neither. Add about $10 of ETH for fees first.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .done(let words):
            Text(verbatim: doneLine(words)).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    // MARK: - The cost (prd §1728 item 6)

    /// Above the verb: one cost in dollars and what it buys you, the parts
    /// one tap down. While a send to someone else is quoted, what it waits
    /// on, in real seconds: the wallet syncing, then the broadcasters.
    @ViewBuilder private var costLine: some View {
        if move.stage == .quoting {
            if let since = RailgunSync.shared.since {
                PrivateWarmingRow(since: since)
            } else {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner(size: .small)
                    Text("Finding a broadcaster…").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // The shared view (§1700y); no price, Railgun's percentage.
            PrivateCostLine(cost: move.cost, tail: costTail, fallback: readyLine)
        }
    }

    /// What the cost buys: private in an hour (in), your account nowhere on
    /// it (to someone else); taking back says the sum alone.
    private var costTail: String? {
        switch move.mode {
        case .deposit: String(localized: "private in about an hour")
        case .takeBack where move.toSomeoneElse: String(localized: "your account isn't on it")
        case .takeBack: nil
        }
    }

    // MARK: - The steps (prd §1728 item 5, §1700x)

    /// This sentence's send, while it works, once it failed with its steps,
    /// and once it is done: the rows stand in the foot over the act.
    private var stepsRun: PrivateSendSteps.Run? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move else { return nil }
        switch move.stage {
        case .working: return run
        case .failed: return run.ok == false ? run : nil
        case .done: return run.ok == true ? run : nil
        default: return nil
        }
    }

    /// The line under a finished send: how long it took, tap to block.
    private func doneLine(_ words: String) -> String {
        guard let total = stepsRun?.total, move.mode == .takeBack else { return words }
        return move.toSomeoneElse ? String(localized: "Sent privately · \(total) s")
            : String(localized: "Back in your account · \(total) s")
    }

    /// Where no price makes a dollar cost: Railgun's percentage and who
    /// pays the gas (§1713 item 6).
    private var readyLine: String {
        let fee = move.feeBps.map { String(localized: "Railgun takes \(RailgunPocket.percent(bps: $0))") }
        switch move.mode {
        case .deposit:
            return [fee, String(localized: "private in about an hour")].compactMap { $0 }.joined(separator: " · ")
        case .takeBack where move.toSomeoneElse && move.viaFresh:
            return [fee, String(localized: "gas from your private ETH")].compactMap { $0 }.joined(separator: " · ")
        case .takeBack where move.toSomeoneElse:
            return [fee, move.feeWords.map { String(localized: "\($0) to the broadcaster") }].compactMap { $0 }.joined(separator: " · ")
        case .takeBack:
            return [fee, String(localized: "gas from your account")].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var problemLine: String {
        switch move.amountProblem {
        case .moreThanHeld(let have)?: String(localized: "You have \(have).")
        case .underMinimum?: String(localized: "Moving to your private balance takes $10 or more.")
        case nil: ""
        }
    }

    // MARK: - Amount and token

    private func toggle() {
        typing = false
        withAnimation(DS.Motion.standard) { open.toggle() }
        DSHaptic.selection()
    }

    /// **THE SENTENCE'S CHOICES, AS ROWS (prd §1781).** Where it leaves
    /// from, who it goes to, how much and of what: what the sentence's
    /// words opened.
    private var choiceRows: [MoveChoiceRow] {
        guard picking else { return [] }
        let yours = String(localized: "Your private balance")
        var rows: [MoveChoiceRow] = []
        switch move.mode {
        case .deposit:
            rows.append(MoveChoiceRow(id: "to", name: String(localized: "To"), value: yours) { leave(.pickRecipient) })
        case .takeBack:
            rows.append(MoveChoiceRow(id: "from", name: String(localized: "From"), value: yours) { leave(.switchOff) })
            rows.append(MoveChoiceRow(id: "to", name: String(localized: "To"),
                                      value: move.toSomeoneElse ? YourAccount.short(move.recipient ?? "") : String(localized: "Your account")) {
                leave(.pickRecipient)
            })
        }
        rows.append(MoveChoiceRow(id: "amount", name: String(localized: "Amount"), value: move.amount, empty: move.amount.isEmpty) {
            withAnimation(DS.Motion.standard) { open = false }
            typing = true
        })
        rows.append(MoveChoiceRow(id: "token", name: String(localized: "Token"), value: move.holding?.symbol ?? "") { toggle() })
        return rows
    }

    /// The amount, typed (prd §1727): the decimal pad, the token's places at
    /// most, the figure in the sentence's own rung — as Aztec's (§1700q).
    private var amountField: some View {
        MoveRungReader { rung in
            TextField(text: $move.amount,
                      prompt: Text(verbatim: "0").foregroundStyle(DS.textTertiary)) { Text(verbatim: "0") }
                .keyboardType(.decimalPad)
                .focused($typing)
                .dsText(rung)
                .monospacedDigit()
                // Pink while it is typed, as Move's own figure is; white at
                // rest, where pink would read as a thing to tap (prd §1781).
                .foregroundStyle(typing ? DS.pickInk : DS.textPrimary)
                .fixedSize()
        }
        .accessibilityLabel(Text("Amount"))
        .onChange(of: move.amount) { _, now in
            if open, typing { open = false }
            let places = move.holding?.decimals ?? 18
            if let dot = now.firstIndex(where: { $0 == "." || $0 == "," }),
               now.distance(from: dot, to: now.endIndex) - 1 > places {
                move.amount = String(now[...now.index(dot, offsetBy: places)])
                return
            }
            move.amountChanged()
        }
    }

    /// $10 · Half · All (prd §1728 item 1): each types its amount, exact;
    /// a choice that would be under the floor, or more than you have, is
    /// not drawn (§83).
    /// **ONE CONTROL, AS ROUND-UPS' (user, 2026-11-10: "the design needs to
    /// match how we do roundups").** Its halves share the row's width, 4 pt
    /// apart, each a `Chip` that fills, the pick crossfading
    /// (`MoveSecurity.RoundUpStepPick`'s anatomy), never small pills on the left.
    @ViewBuilder private var chips: some View {
        let picks = RailgunMove.Pick.allCases.compactMap { p in move.amount(for: p).map { (pick: p, value: $0) } }
        if !picks.isEmpty, !open {
            HStack(spacing: DS.Space.s1) {
                ForEach(picks, id: \.pick) { item in
                    let on = move.amount == item.value
                    Button {
                        typing = false
                        DSHaptic.selection()
                        withAnimation(DS.Motion.standard) { move.amount = item.value }
                    } label: {
                        Chip(text: chipWord(item.pick), selected: on, fills: true)
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
        }
    }

    private func chipWord(_ pick: RailgunMove.Pick) -> String {
        switch pick {
        case .floor: RailgunMove.floorText
        case .half: String(localized: "Half")
        case .all: String(localized: "All")
        }
    }

    private var tokens: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(move.holdings) { h in
                let picked = h == move.holding
                Button {
                    withAnimation(DS.Motion.standard) { move.pick(h); open = false }
                    DSHaptic.selection()
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        AssetMark(name: h.symbol, size: DS.Face.list)
                        Text(verbatim: h.symbol).dsText(.body17)
                            .foregroundStyle(picked ? DS.textSecondary : DS.textPrimary)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: RailgunHoldings.figure(h.units, decimals: h.decimals)).dsText(.body17)
                            .foregroundStyle(DS.textSecondary).monospacedDigit()
                    }
                    .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityAddTraits(picked ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The foot

    private var ready: Bool {
        move.stage == .ready && move.amountOK && !DemoMode.isActive
            && (!move.toSomeoneElse || move.viaFresh || (move.quote != nil && move.feeWords != nil))
    }

    /// The cost stands over the verb while there is something to cost.
    private var showsCost: Bool {
        move.stage == .quoting || (move.stage == .ready && move.amountOK)
    }

    private var foot: some View {
        VStack(spacing: 0) {
            // One thing at a time over the act (§1700x): the steps while it
            // works and after, else the cost (or what a quote waits on).
            if let run = stepsRun {
                PrivateStepRows(run: run, confirmed: move.unlockedFirst ? String(localized: "Confirmed with Face ID") : nil)
                    .padding(.bottom, DS.Space.s3)
                    .transition(.opacity)
            } else if showsCost {
                costLine
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Space.s1)
                    .transition(.opacity)
            }
            HStack(alignment: .center, spacing: DS.Space.s2) {
                MoveBackCard()
                Spacer(minLength: 0)
                switch move.stage {
                case .done:
                    footButton(String(localized: "Done"), on: true) {
                        if inTray { chrome.moveTray = false } else { leave(.switchOff) }
                    }
                case .failed:
                    footButton(String(localized: "Try again"), on: true) { Task { await move.read() } }
                case .reading, .nothing:
                    EmptyView()
                case .needsFees:
                    footButton(DemoMode.isActive ? String(localized: "Not in the demo") : String(localized: "Add ETH for fees"),
                               on: !DemoMode.isActive) {
                        Task { await move.addFees() }
                    }
                    .disabled(DemoMode.isActive)
                default:
                    footButton(DemoMode.isActive ? String(localized: "Not in the demo") : footVerb, on: ready) {
                        Task { await move.run() }
                    }
                    .disabled(!ready)
                }
            }
            if move.stage != .reading, move.stage != .nothing, !isDone { credit }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    private var footVerb: String {
        if case .working(let words) = move.stage { return words }
        return String(localized: "Send")
    }

    private var credit: some View {
        HStack(spacing: DS.Space.s1) {
            Text("Powered by Railgun").dsText(.label12).foregroundStyle(DS.textTertiary)
            ProtocolInlineMark(mark: "railgun").accessibilityHidden(true)
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
}
