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
    enum Mode: Equatable { case deposit, takeBack, swap }

    /// What a private swap buys (prd §1875): a token Railgun holds on
    /// Ethereum, never ETH or USDC, which are Privacy Pools' (§1713).
    struct Buy: Equatable, Identifiable {
        let contract: String
        let symbol: String
        let decimals: Int
        var id: String { contract.lowercased() }
    }

    static let buyable: [Buy] = FreshTx.railgunTokens.map { Buy(contract: $0.contract, symbol: $0.symbol, decimals: $0.decimals) }

    /// What opened the sentence: a token, and which way.
    struct Opening: Equatable {
        var contract: String?
        var takeBack: Bool
        /// Out to someone else; nil is your account.
        var recipient: String? = nil
        /// A swap inside your private balance (prd §1875).
        var swap = false
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

    /// **THE SEND BEHIND ITS SHEET (prd §1806, as Aztec's §1777).** A send to
    /// someone asks for Face ID, then needs nobody while it is proved and
    /// handed to a broadcaster. So the sheet closes at that point and the
    /// move is kept here: the shell's capsule draws its steps, a toast says
    /// it landed, and Move opened on it again shows this same sentence.
    /// Moving in and taking back are signed by your account after, and stay.
    static var kept: RailgunMove?
    /// Closes the sheet; nil where the sentence is a page, which stays.
    var onAway: (() -> Void)?
    /// Another send is still proving behind its sheet: the engine proves
    /// one at a time, and its words name no send.
    private var anotherIsGoing: Bool {
        guard let other = Self.kept, other !== self, case .working = other.stage else { return false }
        return true
    }
    /// What the toast says when a send behind its sheet lands.
    static var landedWords: String { String(localized: "Sent privately") }
    /// This move's: a swap lands as one (prd §1875).
    private var landed: String { mode == .swap ? String(localized: "Swapped privately") : Self.landedWords }
    /// The broadcaster's terms for the picked amount.
    private(set) var quote: RailgunEngineWire.Quote?
    /// A private swap's (prd §1875): what it buys, and its plan once priced.
    var buy: Buy?
    private(set) var swapPlan: RailgunPocket.SwapPlan?
    /// The demo's swap: what comes back, priced off its own numbers.
    private(set) var demoBack: String?
    /// What For offers: every listed token but the one sold.
    var buyChoices: [Buy] { Self.buyable.filter { $0.contract.lowercased() != token?.lowercased() } }
    /// "about 0.0063 WBTC": what comes back into your private balance.
    var getsWords: String? {
        guard let buy else { return nil }
        if let demoBack { return String(localized: "about \(demoBack) \(buy.symbol)") }
        guard let plan = swapPlan else { return nil }
        return String(localized: "about \(RailgunHoldings.figure(plan.buyBack, decimals: buy.decimals)) \(buy.symbol)")
    }
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
        guard mode == .takeBack, let recipient else { return false }
        if toPrivate { return true }
        guard PrivateMoney.isAddress(recipient) else { return false }
        return recipient.lowercased() != YourAccountKey.address?.lowercased()
    }

    /// To someone's private balance on Railgun (prd §1877): the send stays
    /// inside Railgun, a broadcaster (or a fresh sender) carrying it.
    var toPrivate: Bool { mode == .takeBack && recipient.map(RailgunSwap.isPrivateAddress) == true }
    /// A note only the receiver can read (prd §1877).
    var note = ""
    private(set) var transferPlan: RailgunPocket.TransferPlan?

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
        swapPlan = nil
        transferPlan = nil
        demoBack = nil
        switch stage {
        case .quoting, .needsFees, .failed: stage = .ready
        case .ready: break
        default: return
        }
        // A swap is priced once what it buys is picked, as a send to
        // someone else is once typing pauses.
        guard toSomeoneElse || (mode == .swap && buy != nil), amountOK else { return }
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
        if Self.kept === self { Self.kept = nil }
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
        case .takeBack, .swap:
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
        // The demo's swap buys WBTC, so its sentence reads whole (prd §1875).
        if DemoMode.isActive, mode == .swap, buy == nil { buy = Self.buyable.first { $0.symbol == "WBTC" } }
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
        if mode == .swap { await requoteSwap(); return }
        if toPrivate { await requoteTransfer(); return }
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

    /// Prices the swap (prd §1875): the route for what reaches the adapter,
    /// what comes back after Railgun's two fees, and who carries it. The
    /// demo prices it off its own numbers and sends nothing.
    private func requoteSwap() async {
        guard let picked, let buy else { return }
        swapPlan = nil
        demoBack = nil
        viaFresh = false
        stage = .quoting
        #if DEBUG
        // `-railgunFirstSyncPreview <percent>` (prd §1885): the first sync's
        // row in the demo, held there; nothing syncs.
        if DemoMode.isActive, let shown = UserDefaults.standard.string(forKey: "railgunFirstSyncPreview") {
            RailgunSync.shared.since = .now.addingTimeInterval(-95)
            RailgunSync.shared.firstTime = true
            RailgunSync.shared.heard("progress utxo Scanning \(Int(shown) ?? 40)%")
            return
        }
        #endif
        if DemoMode.isActive {
            // The demo's own prices (2026-11-18's), less Railgun's two fees.
            let prices: [String: Double] = ["DAI": 1, "USDT": 1, "WBTC": 63_300, "WETH": 1_768, "LINK": 14.5, "UNI": 7.2, "AAVE": 160]
            if let sell = prices[picked.symbol], let get = prices[buy.symbol],
               let sold = Double(picked.units).map({ $0 / pow(10, Double(picked.decimals)) }) {
                demoBack = (sold * sell / get * 0.995).formatted(.number.precision(.significantDigits(1...4)))
            }
            stage = .ready
            return
        }
        do {
            let plan = try await RailgunPocket.quoteSwap(
                sell: YourAccountOp.Token(symbol: picked.symbol, decimals: picked.decimals, contract: picked.contract),
                buy: YourAccountOp.Token(symbol: buy.symbol, decimals: buy.decimals, contract: buy.contract),
                amount: picked.units)
            guard self.picked == picked, self.buy == buy else { return }
            if let b = plan.broadcast {
                if let held = RailgunHoldings.shared.shown.first(where: { $0.id == b.feeToken.lowercased() }) {
                    feeToken = (held.symbol, held.decimals)
                } else if let listed = await YourAccountTokens.lookUp(b.feeToken, on: YourAccountOp.ethereum) {
                    feeToken = (listed.token.symbol, listed.token.decimals)
                } else {
                    feeToken = nil
                }
                feePriceUSD = nil
                if let symbol = feeToken?.symbol.lowercased(), symbol != "weth" {
                    let prices = await MainnetPrices.prices(for: [symbol])
                    feePriceUSD = prices[symbol] ?? prices[symbol.uppercased()]
                }
            }
            viaFresh = plan.broadcast == nil
            swapPlan = plan
            stage = !viaFresh && feeToken == nil ? .failed(String(localized: "Railgun did not answer. Nothing was sent.")) : .ready
        } catch {
            guard self.picked == picked, self.buy == buy else { return }
            stage = .failed(Self.words(error))
        }
    }

    /// Prices a send to a private address (prd §1877). The demo asks
    /// nothing: its fee is 0.14 USDC.
    private func requoteTransfer() async {
        guard let picked, let to = recipient else { return }
        transferPlan = nil
        viaFresh = false
        stage = .quoting
        if DemoMode.isActive { stage = .ready; return }
        do {
            let plan = try await RailgunPocket.quoteTransfer(token: picked.contract, amount: picked.units, to: to, memo: note)
            guard self.picked == picked, recipient == to else { return }
            if let b = plan.broadcast {
                if let held = RailgunHoldings.shared.shown.first(where: { $0.id == b.feeToken.lowercased() }) {
                    feeToken = (held.symbol, held.decimals)
                } else if let listed = await YourAccountTokens.lookUp(b.feeToken, on: YourAccountOp.ethereum) {
                    feeToken = (listed.token.symbol, listed.token.decimals)
                } else {
                    feeToken = nil
                }
                feePriceUSD = nil
                if let symbol = feeToken?.symbol.lowercased(), symbol != "weth" {
                    let prices = await MainnetPrices.prices(for: [symbol])
                    feePriceUSD = prices[symbol] ?? prices[symbol.uppercased()]
                }
            }
            viaFresh = plan.broadcast == nil
            transferPlan = plan
            stage = !viaFresh && feeToken == nil ? .failed(String(localized: "Railgun did not answer. Nothing was sent.")) : .ready
        } catch {
            guard self.picked == picked, recipient == to else { return }
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

    /// "You have $120.00": the head of the amount's menu (prd §1802).
    var haveLine: String? {
        guard let h = holding else { return nil }
        return h.price.map { String(localized: "You have \(Self.usd(YourAccountOp.dollars(h.units, decimals: h.decimals, price: $0)))") }
            ?? String(localized: "You have \(RailgunHoldings.figure(h.units, decimals: h.decimals) + " " + h.symbol)")
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
        case .swap:
            // Railgun takes its fee twice: out to the exchange and back in.
            usd *= 2
            parts[0] = .init(words: String(localized: "Railgun, out and back in"),
                             figure: RailgunPocket.percent(bps: bps * 2))
            if viaFresh {
                guard let gas = gasUSD(FreshTx.railgunSwapGas, plus: RailgunPocket.lastRelayerFeeWei ?? 0) else { return nil }
                usd += gas
                parts.append(.init(words: String(localized: "A new address of yours sends it, its gas from your private ETH"),
                                   figure: String(localized: "about \(Self.usd(gas))")))
            } else {
                guard let feeWords, let feeUSD = broadcasterFeeUSD else { return nil }
                usd += feeUSD
                parts.append(.init(words: String(localized: "A Railgun broadcaster sends it"), figure: feeWords))
            }
        }
        return PrivateCost(usd: usd, parts: parts)
    }

    /// The broadcaster's fee in dollars: WETH at ETH's price, any other fee
    /// token at its own (`feePriceUSD`, read with the quote).
    private var broadcasterFeeUSD: Double? {
        if DemoMode.isActive, toSomeoneElse || mode == .swap { return mode == .swap ? 0.93 : 0.14 }
        guard let fee = broadcastFee, let feeToken else { return nil }
        let price = feeToken.symbol.uppercased() == "WETH" ? ethUSD : feePriceUSD
        guard let price else { return nil }
        return YourAccountOp.dollars(PrivateMoney.decimal(hex: fee), decimals: feeToken.decimals, price: price)
    }
    private var feePriceUSD: Double?

    /// The broadcaster's fee as the line says it: "0.14 USDC".
    var feeWords: String? {
        if DemoMode.isActive, toSomeoneElse || mode == .swap { return mode == .swap ? "0.00053 WETH" : "0.14 USDC" }
        guard let fee = broadcastFee, let feeToken else { return nil }
        return RailgunHoldings.figure(PrivateMoney.decimal(hex: fee), decimals: feeToken.decimals) + " " + feeToken.symbol
    }

    /// The broadcaster's fee, hex base units: a send's or a swap's.
    private var broadcastFee: String? { quote?.fee ?? swapPlan?.broadcast?.fee ?? transferPlan?.broadcast?.fee }

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
            RailgunHoldings.shared.afterMove()
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
    /// A swap's (prd §1875): said as swapped, never as sent.
    static let swapStepsPlan = PrivateSendSteps.Plan(steps: [.checking, .proving, swapped])
    static let swapped = PrivateSendSteps.Step(key: .sent, running: String(localized: "Swapping on Ethereum"),
                                               done: String(localized: "Swapped on Ethereum"))
    /// A new address of yours carries it (prd §1726): its first step is the
    /// gas coming from your private ETH, said as that, never "Checking"
    /// (user, 2026-11-18: "shouldn't it say better things than checking").
    static let payingGas = PrivateSendSteps.Step(key: .checking, running: String(localized: "Paying gas from your private ETH"),
                                                 done: String(localized: "Paid gas from your private ETH"))
    static let swapFreshPlan = PrivateSendSteps.Plan(steps: [payingGas, .proving, swapped])
    @MainActor static var sendFreshPlan: PrivateSendSteps.Plan {
        PrivateSendSteps.Plan(steps: [payingGas, .proving, .sent(.ethereum)])
    }

    /// Moves it: in through your account's shield, or back to your account.
    func run() async {
        guard let picked, amountOK, !DemoMode.isActive else { return }
        guard mode == .deposit || !anotherIsGoing else { stage = .failed(String(localized: "A send is still on its way")); return }
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
            case .takeBack where toPrivate && viaFresh:
                guard let plan = transferPlan else { return }
                stage = .working(String(localized: "Confirm with Face ID"))
                let hash = try await RailgunPocket.transferFromFresh(plan, unlocked: { [weak self] in self?.started(Self.sendFreshPlan, away: true) }) { _ in }
                try await Self.mined(hash)
                finishSteps()
                stage = .done(String(localized: "Sent privately."))
            case .takeBack where toPrivate:
                guard let plan = transferPlan else { return }
                stage = .working(String(localized: "Confirm with Face ID"))
                let hash = try await RailgunPocket.transfer(plan, unlocked: { [weak self] in self?.started(.send(.ethereum), away: true) })
                transferPlan = nil
                try await Self.mined(hash)
                finishSteps()
                stage = .done(String(localized: "Sent privately."))
            case .takeBack where toSomeoneElse && viaFresh:
                stage = .working(String(localized: "Confirm with Face ID"))
                let hash = try await RailgunPocket.sendFromFresh(token: picked.contract, amount: picked.units, to: recipient ?? "",
                                                          unlocked: { [weak self] in self?.started(Self.sendFreshPlan, away: true) }) { _ in }
                try await Self.mined(hash)
                finishSteps()
                stage = .done(String(localized: "Sent privately."))
            case .takeBack where toSomeoneElse:
                guard let q = quote else { return }
                stage = .working(String(localized: "Confirm with Face ID"))
                let hash = try await RailgunPocket.send(q, unlocked: { [weak self] in self?.started(.send(.ethereum), away: true) })
                quote = nil
                try await Self.mined(hash)
                finishSteps()
                stage = .done(String(localized: "Sent privately."))
            case .swap where viaFresh:
                guard let plan = swapPlan else { return }
                stage = .working(String(localized: "Confirm with Face ID"))
                let hash = try await RailgunPocket.swapFromFresh(plan, unlocked: { [weak self] in self?.started(Self.swapFreshPlan, away: true) }) { _ in }
                try await Self.mined(hash)
                finishSteps()
                stage = .done(String(localized: "Swapped privately."))
            case .swap:
                guard let plan = swapPlan else { return }
                stage = .working(String(localized: "Confirm with Face ID"))
                let hash = try await RailgunPocket.swap(plan, unlocked: { [weak self] in self?.started(Self.swapStepsPlan, away: true) })
                swapPlan = nil
                try await Self.mined(hash)
                finishSteps()
                stage = .done(String(localized: "Swapped privately."))
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
            if Self.kept === self { Self.kept = nil }
            DSHaptic.success()
            RailgunHoldings.shared.afterMove()
        } catch {
            // The rows keep the failure on the step it reached (§1700x),
            // in the sheet or behind it (prd §1806).
            if Self.kept === self, steps.away != nil { steps.failAway(Self.words(error)) } else { steps.fail(Self.words(error)) }
            stage = .failed(Self.words(error))
            if Self.kept === self { DSHaptic.failure() }
            // A broadcaster that turned it down sent nothing, and the engine
            // passes it over now: priced again at once, the next way and its
            // cost are on the sheet, so the next tap is the one that goes
            // (user, 2026-11-18: "fix the two taps"; prd §1895).
            if (error as? RailgunEngineWire.Failure)?.name == "BroadcastRefused" {
                if mode == .swap { await requoteSwap() }
                else if toPrivate { await requoteTransfer() }
                else if toSomeoneElse { await requote() }
            }
        }
    }

    /// **"SWAPPED" IS SAID ONCE IT IS IN A BLOCK (prd §1895).** A send was
    /// called done when it was handed over; MEV Blocker kept one it could
    /// never mine and the sheet said "Swapped" (2026-11-18). Its receipt is
    /// waited for: a revert is a failure, and four minutes with no block is
    /// said as such, never as done.
    static func mined(_ hash: String) async throws {
        guard let network = PrivacyNetwork.forChain(FreshTx.railgunChain) else { return }
        do {
            guard try await FreshSigner.landed(hash, on: network) else { throw RailgunPocket.Failure.notMined }
        } catch FreshSigner.Failure.reverted {
            throw RailgunPocket.Failure.failedOnChain
        }
    }

    /// The send came back good: behind its sheet, or in it.
    private func finishSteps() {
        let steps = PrivateSendSteps.shared
        if Self.kept === self, steps.away != nil { steps.finishAway() } else { steps.finish() }
    }

    /// The sheet closed over a send still going (prd §1806).
    func goAway() {
        PrivateSendSteps.shared.sendAway(from: .railgun, landed: landed)
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
            steps.mark(key, from: .railgun)
            NSLog("railgunStepsPreview| %@ | %@ | %@", kind, key.rawValue, steps.away != nil ? "behind the sheet" : "in the sheet")
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
        // As a real send to someone: behind its sheet from here (prd §1806).
        started(.send(.ethereum), away: true)
        await step(.proving, after: 2)
        if kind == "fail" {
            try? await Task.sleep(for: .seconds(5))
            let words = Self.words(RailgunPocket.Failure.noBroadcaster)
            if Self.kept === self, steps.away != nil { steps.failAway(words) } else { steps.fail(words) }
            stage = .failed(words)
            return
        }
        await step(.sent, after: 8)
        try? await Task.sleep(for: .seconds(3))
        finishSteps()
        stage = .done(String(localized: "Sent privately."))
        if Self.kept === self { Self.kept = nil }
    }
    #endif

    /// Face ID said yes: the rows' clock starts, and "Confirmed with Face
    /// ID" leads them.
    private func started(_ plan: PrivateSendSteps.Plan, away: Bool = false) {
        unlockedFirst = true
        PrivateSendSteps.shared.begin(.move, plan: plan, swap: mode == .swap)
        stage = .working(String(localized: "Sending…"))
        // Face ID was the last ask: the rest needs nobody, so the sheet
        // goes and the shell's capsule says the rest (prd §1806).
        if away, let onAway, PrivateSendSteps.shared.sendAway(from: .railgun, landed: landed) {
            Self.kept = self
            onAway()
        }
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
        if case .notMined? = error as? RailgunPocket.Failure {
            return String(localized: "Not in a block after four minutes. Check Activity before you try again.")
        }
        if case .failedOnChain? = error as? RailgunPocket.Failure {
            return String(localized: "It failed on Ethereum. Your tokens did not move.")
        }
        // Gas rose past what the new address was given: never signed.
        if case .refused(let why)? = error as? FreshSigner.Failure, why.hasPrefix("its gas rose") {
            return String(localized: "Gas rose while it was paid. Nothing was sent. Try again.")
        }
        // The dry run reverted: never signed (prd §1894).
        if case .reverted(_)? = error as? FreshSigner.Failure {
            return String(localized: "Ethereum would have turned it down. Nothing was sent.")
        }
        // It answered, and refused: nothing went out (prd §1887).
        if (error as? RailgunEngineWire.Failure)?.name == "BroadcastRefused" {
            return String(localized: "The broadcaster turned it down. Nothing was sent. The next try goes another way.")
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
        case .noFeeToken?: String(localized: "A broadcaster takes its fee in WETH or USDC, and Railgun holds neither.")
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

    /// The deck's open step (prd §1927): the token, what a swap buys, the
    /// amount on Move's keys, or the note.
    private enum Blank { case token, buy, amount, note }
    @State private var open: Blank?
    /// The cost's list stands in the receipt's place (prd §1876).
    @State private var costOpen = false
    /// The note to a private address is being written (prd §1877).
    @FocusState private var writing: Bool
    /// The Railgun address being named, and the name typed (prd §1965).
    @State private var saving: String?
    @State private var savingName = ""
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        // **A RECEIPT, AS EVERY VERB'S (prd §1931).**
        deck
        // **SAVE WHO YOU PAY (prd §1965, as Aztec's §1964):** one field, the
        // address under it; the book files it as Railgun's.
        .alert("Save this Railgun address", isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } })) {
            TextField("Name", text: $savingName)
            Button("Save") {
                if let address = saving, !savingName.trimmingCharacters(in: .whitespaces).isEmpty {
                    AddressBook.shared.setName(savingName, for: address, networks: ["railgun"])
                    DSHaptic.success()
                }
                saving = nil
            }
            Button("Cancel", role: .cancel) { saving = nil }
        } message: {
            Text(verbatim: saving.map { AddressTail.short($0) } ?? "")
        }
        // Send opens whole: its deck clips in the short sheet.
        .onAppear { chrome.moveTall = true }
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        // The deck opens on the keys once read (prd §1782, as Earn's).
        .onChange(of: move.stage == .ready, initial: true) { _, on in
            if on, open == nil, move.amount.isEmpty { withAnimation(DS.Motion.standard) { open = .amount } }
        }
        // The token's places at most, and every figure asks again (prd §1727).
        .onChange(of: move.amount) { _, now in
            let places = move.holding?.decimals ?? 18
            if let dot = now.firstIndex(where: { $0 == "." || $0 == "," }),
               now.distance(from: dot, to: now.endIndex) - 1 > places {
                move.amount = String(now[...now.index(dot, offsetBy: places)])
                return
            }
            move.amountChanged()
        }
        // A send kept behind its sheet is shown as it stands, running or
        // failed, never read over (prd §1806).
        .task(id: move.mode) { if RailgunMove.kept !== move { await move.read() } }
        .onAppear {
            move.onAway = inTray ? { chrome.moveTray = false } : nil
            if RailgunMove.kept === move { PrivateSendSteps.shared.bringBack() }
        }
        .onDisappear {
            guard RailgunMove.kept === move else { return }
            if case .working = move.stage {
                move.goAway()
            } else {
                // A failure seen is put away with its sheet.
                RailgunMove.kept = nil
                PrivateSendSteps.shared.forget(.move)
            }
        }
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
                           ? String(localized: "Moving to Railgun takes $10 or more.")
                           : move.mode == .swap ? String(localized: "Nothing private to swap yet.")
                           : String(localized: "Nothing private to take back yet."), ink: DS.textSecondary)
            }
        default:
            if !isDone { head() }
            if picking {
                // The amount typed, the token its own word (prd §1727).
                if !move.amount.isEmpty { MoveClause { MoveWord(move.amount, ink: MoveSentence.settledInk) } }
                MoveClause {
                    Button { toggle() } label: {
                        MoveWord(move.holding?.symbol ?? "", ink: MoveSentence.settledInk)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("Token, \(move.holding?.symbol ?? "")"))
                    .accessibilityHint(Text("Picks the token"))
                }
            } else {
                MoveClause(glue: isDone ? (move.mode == .swap ? String(localized: "Swapped") : String(localized: "Sent")) : nil) {
                    MoveWord(figure, ink: DS.textPrimary)
                        .accessibilityLabel(Text("Amount, \(figure)"))
                }
            }
            switch move.mode {
            case .deposit:
                MoveWordsClause(glue: String(localized: "to"), words: "Railgun",
                                ink: DS.textPrimary,
                                action: { if move.stage == .ready { leave(.pickRecipient) } },
                                hint: Text("Picks the address"))
                MovePhrase(String(localized: "Ethereum."), glue: String(localized: "on"))
            case .takeBack:
                MoveWordsClause(glue: String(localized: "from"), words: "Railgun",
                                ink: DS.textPrimary,
                                action: { if move.stage == .ready { leave(.switchOff) } },
                                hint: Text("Picks where it comes from"))
                // Your account (your account sends it), or someone else (a
                // broadcaster sends it, §1721 item 3); a tap picks who.
                MoveWordsClause(glue: String(localized: "to"),
                                words: move.toPrivate ? String(localized: "\(YourAccount.short(move.recipient ?? ""))'s private balance.")
                                    : move.toSomeoneElse ? YourAccount.short(move.recipient ?? "") + "." : String(localized: "your account."),
                                ink: DS.textPrimary,
                                action: { if picking { leave(.pickRecipient) } },
                                hint: Text("Picks the address"))
            case .swap:
                // One place, named once (prd §1875): "Swap 400 DAI for WBTC
                // in your private balance."
                MoveWordsClause(glue: String(localized: "for"), words: move.buy?.symbol ?? String(localized: "a token"),
                                ink: move.buy == nil ? DS.textSecondary : DS.textPrimary,
                                action: { if picking { toggleBuy() } },
                                hint: Text("Picks what it buys"))
                MoveWordsClause(glue: String(localized: "in"), words: "Railgun.",
                                ink: DS.textPrimary,
                                action: { if move.stage == .ready { leave(.switchOff) } },
                                hint: Text("Picks where it comes from"))
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
            // What you have and the sums are the amount's menu (prd §1802).
            // The floor is still said: it is a rule, and no menu shows it.
            if move.mode == .deposit {
                Text(verbatim: String(localized: "\(RailgunMove.floorText) or more"))
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
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
            Text("A broadcaster takes its fee in WETH or USDC, and Railgun holds neither. Add about $10 of ETH for fees first.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .done(let words):
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: doneLine(words)).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The Railgun address this send paid, if it has no name yet.
                if let address = unsavedRecipient {
                    Button {
                        savingName = ""
                        saving = address
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            Text("Save \(AddressTail.short(address))").dsText(.heading17)
                                .foregroundStyle(DS.pickInk)
                            Spacer(minLength: DS.Space.s2)
                        }
                        .frame(minHeight: DSFeed.headHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Saves this Railgun address by a name you give"))
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - The cost (prd §1728 item 6)

    /// The Cost row's cost, once the move is ready to cost (prd §1876).
    private var costRow: PrivateCost? {
        move.stage == .ready && move.amountOK ? move.cost : nil
    }

    /// Above the verb: what the cost buys you; the cost is a row among the
    /// choices (prd §1876). While a send to someone else is quoted, what it
    /// waits on, in real seconds: the wallet syncing, then the broadcasters.
    @ViewBuilder private var costLine: some View {
        if move.stage == .quoting {
            if let since = RailgunSync.shared.since {
                PrivateWarmingRow(since: since, firstTime: RailgunSync.shared.firstTime, percent: RailgunSync.shared.percent, railgun: true)
            } else {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner(size: .small)
                    Text("Finding a broadcaster…").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // The shared view (§1700y); no price, Railgun's percentage.
            PrivateCostNote(cost: move.cost, tail: costTail, fallback: readyLine)
        }
    }

    /// What the cost buys: private in an hour (in), your account nowhere on
    /// it (to someone else); taking back says the sum alone.
    private var costTail: String? {
        switch move.mode {
        case .deposit: String(localized: "private in about an hour")
        case .takeBack where move.toPrivate: String(localized: "only they see how much")
        case .takeBack where move.toSomeoneElse: String(localized: "your account isn't on it")
        case .takeBack: nil
        // A private swap is private by name: no tail repeats it (user,
        // 2026-11-18: "it's a private swap isn't that assumed").
        case .swap: nil
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
        guard let total = stepsRun?.total, move.mode != .deposit else { return words }
        if move.mode == .swap { return String(localized: "Swapped privately · \(total) s") }
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
        case .swap:
            let both = move.feeBps.map { String(localized: "Railgun takes \(RailgunPocket.percent(bps: $0 * 2))") }
            return [both, move.viaFresh ? String(localized: "gas from your private ETH")
                    : move.feeWords.map { String(localized: "\($0) to the broadcaster") }].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var problemLine: String {
        switch move.amountProblem {
        case .moreThanHeld(let have)?: String(localized: "You have \(have).")
        case .underMinimum?: String(localized: "Moving to Railgun takes $10 or more.")
        case nil: ""
        }
    }

    // MARK: - Amount and token

    private func toggle(_ blank: Blank = .token) {
        guard picking else { return }
        withAnimation(DS.Motion.standard) { open = open == blank ? nil : blank }
        DSHaptic.selection()
    }

    /// **THE FACTS (prd §1927):** what the rows said that is not a choice,
    /// as the deck's receipt.
    private var facts: [(name: String, value: String)] {
        var out: [(name: String, value: String)] = []
        // **NOTHING THE SENTENCE SAYS (prd §1929):** where it goes and comes
        // from are the sentence's words; a move-in names Ethereum there too.
        if move.mode != .deposit {
            out.append((String(localized: "Network"), String(localized: "Ethereum")))
        }
        // What comes back, after Railgun's two fees (prd §1875).
        if move.mode == .swap, let gets = move.getsWords { out.append((String(localized: "You get"), gets)) }
        // "Through Railgun" is the sentence's own word now (prd §1929).
        return out
    }

    /// The deck's receipt: the facts, the cost a row of them (prd §1876),
    /// and where no price makes a dollar cost, Railgun's percentage.
    /// The line is the receipt's while the move is ready (prd §1929).
    private var lineInDeck: Bool { move.stage == .ready || move.stage == .quoting }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // The token and its amount are the receipt's lines (prd §1931).
            if lineInDeck { line }
            MoveCostRows(cost: costRow, open: $costOpen, indented: false) {
                ForEach(facts, id: \.name) { f in MoveFactRow(name: f.name, value: f.value, indented: false) }
            }
            if !costOpen, costRow == nil, move.stage == .ready, move.amountOK {
                Text(verbatim: readyLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The note, typed: at most 140 characters, which only the receiver
    /// can read; a change asks the broadcaster again, as the amount does.
    private var noteField: some View {
        TextField(text: $move.note, prompt: Text("Optional").foregroundStyle(DS.textTertiary)) { Text("Note") }
            .focused($writing)
            .onAppear { writing = true }
            .dsText(.body17)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(DS.textPrimary)
            .tint(DS.pickInk)
            .submitLabel(.done)
            .onChange(of: move.note) { _, now in
                if now.count > 140 { move.note = String(now.prefix(140)); return }
                move.amountChanged()
            }
    }

    private func toggleBuy() { toggle(.buy) }

    /// What a swap can buy: Railgun's listed tokens on Ethereum, as Move's
    /// one token list (prd §1910).
    private var buyList: some View {
        MoveTokenGrid(places: [MoveTokenPlace(id: "railgun", choices: move.buyChoices.map { b in
            MoveTokenChoice(id: b.symbol, symbol: b.symbol, network: "Ethereum", badge: MoveSentence.networkMark(chainId: 1),
                            picked: b == move.buy) {
                withAnimation(DS.Motion.standard) { move.buy = b; open = .amount }
                move.amountChanged()
            }
        })])
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// $10 · Half · All (prd §1728 item 1): each types its amount, exact;
    /// a choice that would be under the floor, or more than you have, is
    /// not drawn (§83).
    /// **ONE CONTROL, AS ROUND-UPS' (user, 2026-11-10: "the design needs to
    /// match how we do roundups").** Its halves share the row's width, 4 pt
    /// apart, each a `Chip` that fills, the pick crossfading
    /// (`MoveSecurity.RoundUpStepPick`'s anatomy), never small pills on the left.

    private func chipWord(_ pick: RailgunMove.Pick) -> String {
        switch pick {
        case .floor: RailgunMove.floorText
        case .half: String(localized: "Half")
        case .all: String(localized: "All")
        }
    }

    /// What your private balance holds on Railgun, as Move's one token list
    /// (prd §1910).
    private var tokens: some View {
        MoveTokenGrid(places: [MoveTokenPlace(id: "railgun-held", choices: move.holdings.map { h in
            MoveTokenChoice(id: h.id, symbol: h.symbol, network: "Ethereum", badge: MoveSentence.networkMark(chainId: 1),
                            sub: RailgunHoldings.figure(h.units, decimals: h.decimals), picked: h == move.holding) {
                withAnimation(DS.Motion.standard) { move.pick(h); open = .amount }
            }
        })])
    }

    // MARK: - The foot

    private var ready: Bool {
        move.stage == .ready && move.amountOK && !DemoMode.isActive
            && (!move.toSomeoneElse || move.viaFresh || ((move.quote != nil || move.transferPlan != nil) && move.feeWords != nil))
            && (move.mode != .swap || (move.swapPlan != nil && (move.viaFresh || move.feeWords != nil)))
    }

    @Environment(\.moveBack) private var back
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// **RAILGUN'S DECK (prd §1927, as Earn's §1901).**
    private var deck: some View {
        MoveReceiptDeck(title: move.mode == .swap ? String(localized: "Swap") : String(localized: "Send"),
                        inTray: inTray, backDisabled: move.acting, back: {
            withAnimation(DS.Motion.standard) {
                // Back is the menu, never the step before (prd §1911).
                if costOpen { costOpen = false } else { open = nil; back?() }
            }
        }, lines: {
            // **THE LINES STAND WHILE IT GOES, AS PUBLIC SEND'S (prd §1980).**
            if (picking || move.acting), !isDone {
                MoveReceiptSteps(steps: steps, disabled: !picking)
            }
        }, content: {
                Group {
                    if open == .amount, picking {
                        VStack(spacing: MoveReceipt.gap) {
                            Spacer(minLength: 0)
                            // The quick amounts are the keys' top row (prd §1932).
                            let quick = RailgunMove.Pick.allCases.compactMap { p in move.amount(for: p).map { (p, $0) } }
                            if !quick.isEmpty {
                                MoveQuickKeys(keys: quick.map { p, value in
                                    MoveQuickKeys.Key(id: value, word: chipWord(p), on: move.amount == value) { move.amount = value }
                                })
                            }
                            MoveKeypad(text: $move.amount, places: min(move.holding?.decimals ?? 6, 6),
                                       keyHeight: MoveSentence.bigKeyHeight, big: true)
                        }
                        .transition(.opacity)
                    } else if open == .token, picking {
                        listBody { tokens }
                    } else if open == .buy, picking {
                        listBody { buyList }
                    } else if open == .note, picking {
                        listBody { noteField.frame(minHeight: 48) }
                    } else if picking, !isDone {
                        listBody {
                            VStack(alignment: .leading, spacing: DS.Space.s2) {
                                if move.stage == .quoting { costLine.frame(maxWidth: .infinity, alignment: .leading) }
                                if !lineInDeck { line }
                                receipt
                            }
                        }
                    } else {
                        // Reading, working, done: the sentence says where it
                        // stands, the steps and the line the rest.
                        listBody {
                            VStack(alignment: .leading, spacing: DS.Space.s3) {
                                // While it goes the lines say it, as public Send's (prd §1980).
                                if !move.acting {
                                    MoveFlow { sentence }
                                        .moveHoldFill()
                                        .allowsHitTesting(false)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if let run = stepsRun {
                                    PrivateStepRows(run: run, confirmed: move.unlockedFirst ? String(localized: "Confirmed with Face ID") : nil)
                                        .transition(.opacity)
                                }
                                if !lineInDeck { line }
                            }
                        }
                    }
                }
        }, word: { footWord })
        .animation(DS.Motion.standard, value: open)
    }

    private func listBody<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView { content().padding(.vertical, DS.Space.s2) }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
            .transition(.opacity)
    }

    /// Where it goes (back to Send's recipients), the token, what a swap
    /// buys, the amount, and the note to a private address.
    private var steps: [MoveDeckStep] {
        var out: [MoveDeckStep] = []
        // **THE SENTENCE'S WORDS ARE THE LINES (prd §1931).**
        switch move.mode {
        case .deposit:
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), answered: true, value: "Railgun", glyph: "lock.fill") { leave(.pickRecipient) })
        case .takeBack:
            out.append(MoveDeckStep(id: "from", word: String(localized: "From"), answered: true, value: "Railgun", glyph: "lock.fill") { leave(.switchOff) })
            // A Railgun address you saved is said by its name (prd §1965).
            // The name keeps the address's tail, to check by (prd §1965a, as §1964b).
            let to = move.toPrivate ? (AddressBook.shared.name(for: move.recipient ?? "").map { "\($0) · \(AddressTail.short(move.recipient ?? ""))" }
                                        ?? YourAccount.short(move.recipient ?? ""))
                : move.toSomeoneElse ? YourAccount.short(move.recipient ?? "") : String(localized: "Your account")
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), answered: true, value: to) { leave(.pickRecipient) })
        case .swap:
            break
        }
        let held = move.holding.map { MoveRowMark(token: $0.symbol, network: MoveSentence.networkMark(chainId: 1)) }
        out.append(MoveDeckStep(id: "token", word: String(localized: "Token"),
                                on: open == .token, answered: move.holding != nil,
                                value: move.holding.map { "\($0.symbol) · Ethereum" }, mark: held) { toggle(.token) })
        if move.mode == .swap {
            out.append(MoveDeckStep(id: "buy", word: String(localized: "Token"), on: open == .buy, answered: move.buy != nil,
                                    value: move.buy.map { "\($0.symbol) · Railgun" },
                                    mark: move.buy.map { MoveRowMark(token: $0.symbol) }) { toggle(.buy) })
        }
        out.append(MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: open == .amount,
                                answered: !move.amount.isEmpty,
                                value: move.amount.isEmpty ? (open == .amount ? "0" : nil)
                                    : "\(move.amount) \(move.holding?.symbol ?? "")") { toggle(.amount) })
        if move.toPrivate {
            out.append(MoveDeckStep(id: "note", word: String(localized: "Note"), on: open == .note,
                                    answered: !move.note.isEmpty, value: move.note.isEmpty ? nil : move.note) { toggle(.note) })
            // **NAME IT BEFORE IT GOES (prd §1965):** a send to someone
            // leaves its sheet once Face ID answers, so the receipt asks too.
            if let address = unsavedRecipient {
                out.append(MoveDeckStep(id: "name", word: String(localized: "Name"), answered: false, value: String(localized: "Save")) {
                    savingName = ""
                    saving = address
                })
            }
        }
        return out
    }

    /// The Railgun address this send pays, if the book has no name for it (prd §1965).
    private var unsavedRecipient: String? {
        guard move.toPrivate, let address = move.recipient, AddressBook.shared.entry(for: address) == nil else { return nil }
        return address
    }

    /// **THE FOOT'S ONE WORD (prd §1897 item 7).**
    @ViewBuilder private var footWord: some View {
        switch move.stage {
        case .done:
            MoveFootWord(word: String(localized: "Done")) {
                if inTray { chrome.moveTray = false } else { leave(.switchOff) }
            }
        case .failed:
            MoveFootWord(word: String(localized: "Try again")) { Task { await move.read() } }
        case .reading, .nothing:
            EmptyView()
        case .needsFees:
            MoveFootWord(word: DemoMode.isActive ? String(localized: "Not in the demo") : String(localized: "Add ETH for fees")) {
                guard !DemoMode.isActive else { return }
                Task { await move.addFees() }
            }
        case .working:
            MoveFootWord(word: footVerb, ink: DS.textSecondary)
        default:
            MoveHoldWord(word: DemoMode.isActive ? String(localized: "Not in the demo")
                            : move.mode == .swap ? String(localized: "Hold to swap") : String(localized: "Hold to send"),
                         enabled: ready) {
                open = nil
                move.onAway = inTray ? { chrome.moveTray = false } : nil
                Task { await move.run() }
            }
        }
    }

    private var footVerb: String {
        if case .working(let words) = move.stage { return words }
        return move.mode == .swap ? String(localized: "Swap") : String(localized: "Send")
    }


}
