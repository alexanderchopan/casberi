import Foundation
import Observation

/// **LEND, IN MOVE (prd §1674).** The sentence's state: which market (a
/// token on a network), how much, and whether it lends or takes back. The
/// calls are `AaveLend`'s, checked by `AaveLend.checked`, and go through your
/// account's one simulated path (`YourAccountChain.lendCalls`): run against
/// the real state as the account, then one Face ID operation. Nothing that
/// fails the simulation is signed.
///
/// Reads, per market, at once: what the account holds, what it has lent
/// (the aToken's balance, interest included) and Aave's supply rate. The
/// pinned aToken is held to the reserve's own; a market whose reserve names
/// another is not offered.
@MainActor
@Observable
final class LendMove {

    enum Mode: Equatable { case lend, takeBack }

    enum Stage: Equatable {
        case reading
        case ready
        case working(YourAccountChain.Stage)
        case done(String)
        case failed(String)
    }

    typealias Market = AaveLend.Market

    var mode: Mode
    var stage: Stage = .reading
    var chainId = 8453
    var symbol = "USDC"
    /// The amount picked, as typed ("500"); nil until one is.
    var amount: String?
    /// Everything there is: the whole balance (lend) or all that is lent.
    var all = false

    /// Base units, decimal, by `key(market)`.
    private(set) var held: [String: String] = [:]
    private(set) var lent: [String: String] = [:]
    /// **ROUND-UPS IS NOT LENT (prd §1690).** What Round-ups keeps in Aave's
    /// USDC on Base, split off the account's aUSDC there: never offered to
    /// Take back, never drawn as lent, held as its own row in Holdings.
    private(set) var roundUps = "0"
    private(set) var rates: [String: Double] = [:]
    /// USD per unit by lower-cased symbol, for every market's token: Holdings'
    /// Lent rows draw dollars off these, never Private's prices, which only
    /// name what is held privately.
    private(set) var prices: [String: Double] = [:]
    /// The markets whose reserve did not name the pinned aToken.
    private(set) var refused: Set<String> = []
    /// ETH kept back for the operation's fee, per network (base units).
    private(set) var reserve: [Int: String] = [:]
    /// Each network's gas price, wei, for the cost line (prd §1700z).
    private(set) var gasPriceWei: [Int: Decimal] = [:]

    // MARK: - Olla (prd §1970)

    /// stAZTEC held, base units.
    private(set) var ollaShares = "0"
    /// What one stAZTEC is worth in AZTEC, base units: `convertToAssets(1e18)`.
    private(set) var ollaRate: String?
    /// Requests filed and not yet claimed: waiting, or ready to claim.
    private(set) var ollaRequests: [OllaStake.Request] = []
    /// Anything at Olla: staked, or on its way back.
    var anyOlla: Bool { (Decimal(string: ollaShares) ?? 0) > 0 || !ollaRequests.isEmpty }
    var ollaReady: [OllaStake.Request] { ollaRequests.filter(\.ready) }
    var ollaWaiting: [OllaStake.Request] { ollaRequests.filter { !$0.ready } }

    /// The AZTEC asked back, ready or still waiting, base units.
    func ollaBack(ready: Bool) -> String {
        let sum = ollaRequests.filter { $0.ready == ready }.reduce(Decimal(0)) { $0 + (Decimal(string: $1.assets) ?? 0) }
        return Self.digits(sum)
    }

    /// **CLAIM IS THE ACT** while Withdraw stands on Olla with a request
    /// ready: the deck claims it before anything else is asked back.
    var claims: Bool { mode == .takeBack && market?.place == .olla && !ollaReady.isEmpty }

    /// stAZTEC a withdrawal of the picked amount burns: every share for all,
    /// else the amount at today's price, never more than is held.
    var ollaSharesAsked: String? {
        guard let units else { return nil }
        if all { return ollaShares }
        guard let rate = ollaRate, let s = OllaStake.shares(forAssets: units, rate: rate),
              let d = Decimal(string: s), let held = Decimal(string: ollaShares) else { return nil }
        return Self.digits(min(d, held))
    }

    /// Below Olla's least request (100 stAZTEC): said, and nothing is signed.
    var ollaUnderMinimum: Bool {
        guard mode == .takeBack, !claims, market?.place == .olla, let s = ollaSharesAsked.flatMap({ Decimal(string: $0) }) else { return false }
        return s < OllaStake.minimumShares
    }

    /// Opened from a lent row (`opens`): its market, once.
    init(mode: Mode = .lend, opens: Bool = false) {
        self.mode = mode
        if opens, let at = Self.opening {
            chainId = at.chainId
            symbol = at.symbol
            Self.opening = nil
        }
    }

    /// Holdings' reading of your account's lent money, kept between visits.
    static let holdings = LendMove(mode: .takeBack)

    // MARK: - In the Wallet's number (prd §1695)

    /// Lent's one position in the portfolio, as Private's is: one block in
    /// the box and one share of the total, never folded into the token it
    /// is, so Tokens, Lent and Private add up to the number above them.
    static let walletSymbol = WalletPortfolio.lentSymbol
    static let holderID = "lent"

    /// What is lent in dollars: every market priced, and Round-ups (USDC,
    /// a dollar each). Nil while a lent market has no price, so the head
    /// and the total never state part of it as all of it.
    func lentUSD() -> Double? {
        var usd = RoundUpsPot.dollars(roundUps)
        for m in AaveLend.markets {
            // What Olla owes back counts with what it stakes: it is yours.
            let back = m.place == .olla ? (Decimal(string: ollaBack(ready: true)) ?? 0) + (Decimal(string: ollaBack(ready: false)) ?? 0) : 0
            guard let units = Decimal(string: lent[Self.key(m)] ?? "0").map({ $0 + back }), units > 0 else { continue }
            guard let price = prices[m.symbol.lowercased()] else { return nil }
            usd += NSDecimalNumber(decimal: units / pow(10, m.decimals)).doubleValue * price
        }
        return usd
    }

    /// Whether the last read heard every market's aToken balance: only then
    /// is an empty market "nothing lent" rather than "not reached".
    private(set) var lentAnswered = false

    /// **LENT STANDS ON ITS LAST READING (prd §1697, as a wallet does, §825).**
    /// What was lent, in dollars, when every market last answered and was
    /// priced, kept on the phone per account; a read that misses a market, or
    /// a price, stands on it, dated, for up to three days. Never zero for
    /// "not reached": a relaunch with Aave unreachable kept the total short by
    /// everything lent and said nothing.
    struct Reading: Codable, Equatable {
        let account: String
        let usd: Double
        let at: Date
    }

    private static let readingKey = "lend.lastReading.v1"
    static let readingFloor: TimeInterval = 3 * 86_400

    static func lastReading(for account: String, now: Date = .now) -> Reading? {
        guard let data = UserDefaults.standard.data(forKey: readingKey),
              let r = try? JSONDecoder().decode(Reading.self, from: data),
              r.account.lowercased() == account.lowercased(),
              now.timeIntervalSince(r.at) <= readingFloor else { return nil }
        return r
    }

    /// What Lent stands on now: this read when it heard everything (nil when
    /// nothing is lent), else the last reading, with its date.
    func standing(account: String) -> (usd: Double, asOf: Date?)? {
        if lentAnswered, let usd = lentUSD() {
            guard usd > 0 else { return nil }
            return (usd: usd, asOf: nil)
        }
        guard let last = Self.lastReading(for: account) else { return nil }
        return (usd: last.usd, asOf: last.at)
    }

    /// Your account's lent money, read fresh, as the portfolio's venue, and
    /// the date it stands on when that is a last reading.
    func walletHolding(account: String) async -> (venues: [(symbol: String, usd: Double, holderID: String, label: String)], asOf: Date?) {
        await read(account: account)
        if lentAnswered, let usd = lentUSD(), !YourAccountDemo.isDemo(account),
           let data = try? JSONEncoder().encode(Reading(account: account, usd: usd, at: .now)) {
            DefaultsWrite.set(data, forKey: Self.readingKey)
        }
        guard let stand = standing(account: account) else { return ([], nil) }
        return ([(symbol: Self.walletSymbol, usd: stand.usd, holderID: Self.holderID, label: String(localized: "Lent"))], stand.asOf)
    }
    /// The market a lent row opens Take back on.
    static var opening: (chainId: Int, symbol: String)?

    nonisolated static func key(_ m: Market) -> String { "\(m.chainId)|\(m.symbol)" }

    var market: Market? { AaveLend.market(chainId: chainId, symbol: symbol) }
    var network: YourAccountOp.Network? { YourAccountOp.networks.first { $0.chainId == chainId } }
    var acting: Bool { if case .working = stage { true } else { false } }

    /// What the amount may come out of: held (less ETH's fee reserve) to
    /// lend, lent to take back.
    func available(_ m: Market) -> String? {
        switch mode {
        case .lend:
            guard let have = held[Self.key(m)] else { return nil }
            guard m.native else { return have }
            let keep = Decimal(string: reserve[m.chainId] ?? "0") ?? 0
            let left = (Decimal(string: have) ?? 0) - keep
            return left > 0 ? Self.digits(left) : "0"
        case .takeBack:
            // Claiming takes every ready request, whatever was typed.
            if m.place == .olla, claims { return ollaBack(ready: true) }
            return lent[Self.key(m)]
        }
    }

    /// The amount in base units: what was picked, or all of what is available.
    var units: String? {
        guard let m = market else { return nil }
        if claims { return available(m).flatMap { $0 == "0" ? nil : $0 } }
        if all { return available(m).flatMap { $0 == "0" ? nil : $0 } }
        return amount.flatMap { PrivateMoney.baseUnits($0, decimals: m.decimals) }
    }

    /// "500 USDC", "0.0842 ETH": what the sentence says it moves.
    var figure: String {
        guard let m = market else { return symbol }
        guard let units else { return "0 \(m.symbol)" }
        // A claim is Olla's figure, not one typed: whole AZTEC, rounded down
        // (it pays at least this), never six places of false precision.
        if claims, let d = Decimal(string: units) {
            var whole = d / pow(10, m.decimals), rounded = Decimal()
            NSDecimalRound(&rounded, &whole, 0, .down)
            return "\(rounded.formatted(.number.precision(.fractionLength(0)))) \(m.symbol)"
        }
        return PrivateMoney.figure(units, decimals: m.decimals, symbol: m.symbol)
    }

    func pick(_ step: String?, all: Bool) {
        self.amount = step
        self.all = all
    }

    // MARK: - In dollars, as every Move sentence says them (prd §1700z)

    /// A market's token amount, base units, in dollars.
    func dollars(_ units: String, in m: Market) -> Double? {
        guard let price = prices[m.symbol.lowercased()], let u = Decimal(string: units) else { return nil }
        return NSDecimalNumber(decimal: u / pow(10, m.decimals)).doubleValue * price
    }

    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// "$250.00" (or "0.08 ETH" with no price): what the amount may come out
    /// of, the You have fact's value (prd §1898 item 6).
    var haveFigure: String? {
        guard let m = market, let have = available(m) else { return nil }
        return dollars(have, in: m).map(Self.usd) ?? PrivateMoney.figure(have, decimals: m.decimals, symbol: m.symbol)
    }

    /// Half of what is available, in the token's own places, rounded down;
    /// nil when there is nothing to halve.
    var half: String? {
        guard let m = market, let have = available(m).flatMap({ Decimal(string: $0) }), have > 1 else { return nil }
        var raw = have / 2 / pow(10, m.decimals), cut = Decimal()
        NSDecimalRound(&cut, &raw, min(m.decimals, 6), .down)
        return cut > 0 ? NSDecimalNumber(decimal: cut).stringValue : nil
    }

    /// A lend's gas with the account's own calls around it: 246K measured
    /// for ETH (the reserve's own figure, above), rounded.
    static let gas = 250_000

    /// What it costs: the network's gas from your account. Aave takes
    /// nothing to lend or take back. nil without the gas price or ETH's.
    var cost: PrivateCost? {
        guard units != nil, let price = gasPriceWei[chainId], let eth = prices["eth"] else { return nil }
        let usd = NSDecimalNumber(decimal: Decimal(Self.gas) * price / pow(10, 18)).doubleValue * eth
        // The part's figure is the total's own words: one part, one figure,
        // never "under $0.01" over "about $0.00" (user, 2026-11-21).
        let figure = PrivateCost(usd: usd, parts: []).amount
        return PrivateCost(usd: usd, parts: [.init(words: String(localized: "Gas, from your account"), figure: figure)])
    }

    /// The step rows' plan: signed, sent on this network (prd §1700z).
    var plan: PrivateSendSteps.Plan {
        .signed(chainId == 1 ? .ethereum : .base)
    }

    /// Any market where something is lent: Holdings' rows, and whether Take
    /// back has anything to say.
    var anyLent: Bool { lent.values.contains { (Decimal(string: $0) ?? 0) > 0 } || !ollaRequests.isEmpty }

    // MARK: - Reading

    /// The account the last finished read was of: a reading stands for it.
    private(set) var readFor: String?

    func read(account: String) async {
        if case .working = stage { return }
        // **EARN OPENS ON HOME'S READING (2026-11-27, user: "earn takes a
        // while to read").** Home reads the same markets for the same account
        // into `holdings`; a new deck stands on that reading at once and this
        // read replaces its figures as they land, never "Reading…" over a page
        // the phone already knows.
        if readFor != account, self !== Self.holdings, Self.holdings.readFor == account {
            take(Self.holdings)
            settle()
        }
        // A refresh keeps the deck as it stands: the pick, the keys, the act.
        let refreshing = stage == .ready && readFor == account
        if !refreshing { stage = .reading }
        async let priced = MainnetPrices.prices(for: AaveLend.markets.map(\.symbol))
        if YourAccountDemo.isDemo(account) {
            readDemo()
        } else {
            await readChain(account: account)
        }
        let found = await priced
        if found != prices { prices = found }
        readFor = account
        if stage == .reading { settle() }
    }

    /// Another deck's reading of the same account, figures only: the mode
    /// and the pick stay this deck's.
    private func take(_ other: LendMove) {
        held = other.held
        lent = other.lent
        roundUps = other.roundUps
        rates = other.rates
        prices = other.prices
        refused = other.refused
        reserve = other.reserve
        gasPriceWei = other.gasPriceWei
        ollaShares = other.ollaShares
        ollaRate = other.ollaRate
        ollaRequests = other.ollaRequests
        lentAnswered = other.lentAnswered
        readFor = other.readFor
    }

    /// After a read or a pick: the first market with something to move,
    /// ready either way (an empty market says so in its line).
    func settle() {
        if let m = market, !(Decimal(string: available(m) ?? "0") ?? 0 > 0) {
            if let first = AaveLend.markets.first(where: { (Decimal(string: available($0) ?? "0") ?? 0) > 0 && !refused.contains(Self.key($0)) }) {
                chainId = first.chainId
                symbol = first.symbol
            }
        }
        // No amount is picked for you: the deck opens on the keys (prd §1897
        // item 4, the ladder that pre-picked one is deleted).
        stage = .ready
    }

    private func readDemo() {
        for m in AaveLend.markets {
            let net = YourAccountOp.networks.first { $0.chainId == m.chainId }
            let token = m.native ? YourAccountOp.eth : net.map(YourAccountOp.dollar(on:))
            held[Self.key(m)] = net.flatMap { n in YourAccountDemo.held(on: n).first { $0.token == token }?.units } ?? "0"
            lent[Self.key(m)] = m.chainId == 8453 && !m.native ? "150000000" : "0"
        }
        roundUps = RoundUpsPot.demoPot
        readOllaDemo()
        lentAnswered = true
        rates = ["8453|USDC": 0.0508, "8453|ETH": 0.0143, "1|USDC": 0.0379, "1|ETH": 0.0145, "1|AZTEC": 0.31]
        reserve = [8453: "100000000000000", 1: "1000000000000000"]
        gasPriceWei = [8453: 6_000_000, 1: 400_000_000]
    }

    private func readChain(account: String) async {
        // **EVERY READ AT ONCE (2026-11-27).** Aave's markets, Olla and each
        // network's gas price need no other's answer. Asked round after round
        // (Aave, then Olla's block and its archive call, then Base's gas, then
        // Ethereum's) they were five round trips over Tor before the deck drew;
        // at once, the deck waits on the slowest branch alone.
        async let aave = Self.readAave(account: account)
        async let ollaHeard = readOlla(account: account)
        async let gas = Self.gasPrices()
        let found = await aave
        // Every market's aToken balance heard, or the reading is partial.
        let ollaAnswered = await ollaHeard
        lentAnswered = found.count == AaveLend.markets.filter({ $0.place == .aave }).count && found.allSatisfy { $0.lent != nil }
            && ollaAnswered
        for r in found {
            guard let m = AaveLend.markets.first(where: { Self.key($0) == r.key }) else { continue }
            // A reserve that names another aToken is not the market this was
            // built for: offered nowhere, signed for never.
            if let a = r.aToken, a.lowercased() != m.aToken { refused.insert(r.key) } else { refused.remove(r.key) }
            if let h = r.held { held[r.key] = h }
            if let l = r.lent {
                if let pot = RoundUpsPot.market, r.key == Self.key(pot) {
                    // Held to the chain: a pot larger than what is there is cut to it.
                    let parts = RoundUpsPot.split(aBalance: l, pot: RoundUpsPot.pot)
                    // Never while change carried from another network may still be on its way.
                    if parts.roundUps != RoundUpsPot.pot, RoundUpsPot.mayHeal(carriedAt: RoundUpsPot.carriedAt) {
                        RoundUpsPot.pot = parts.roundUps
                    }
                    roundUps = parts.roundUps
                    lent[r.key] = parts.lent
                } else {
                    lent[r.key] = l
                }
            }
            if let rate = r.rate { rates[r.key] = rate }
        }
        for (id, price) in await gas {
            // Twice today's price for the most a lend of ETH has taken with
            // the account's own calls around it (246k measured, 600k kept).
            reserve[id] = Self.digits(price * 600_000 * 2)
            gasPriceWei[id] = price
        }
    }

    private typealias Read = (key: String, held: String?, lent: String?, rate: Double?, aToken: String?)

    /// Per Aave market, at once: what the account holds, what it has lent
    /// and the reserve (the rate, the aToken).
    private nonisolated static func readAave(account: String) async -> [Read] {
        await withTaskGroup(of: Read.self) { group in
            for m in AaveLend.markets where m.place == .aave {
                guard let net = YourAccountOp.networks.first(where: { $0.chainId == m.chainId }) else { continue }
                group.addTask {
                    let token = m.native ? YourAccountOp.eth : YourAccountOp.Token(symbol: m.symbol, decimals: m.decimals, contract: m.asset)
                    async let have = YourAccountChain.balance(net, token, of: account)
                    async let given = Self.call(net, to: m.aToken, data: AaveLend.lentCall(account: account))
                    async let reserve = Self.call(net, to: m.pool, data: AaveLend.reserveDataCall(m))
                    let r = await reserve
                    return (Self.key(m), await have, await given.map(AaveLend.decimal(hex:)),
                            r.flatMap(AaveLend.apy(reserveData:)), r.flatMap(AaveLend.aToken(reserveData:)))
                }
            }
            var out: [Read] = []
            for await r in group { out.append(r) }
            return out
        }
    }

    /// Each Lend network's gas price, wei, at once.
    private nonisolated static func gasPrices() async -> [(Int, Decimal)] {
        await withTaskGroup(of: (Int, Decimal)?.self) { group in
            for id in AaveLend.chainIds {
                guard let net = YourAccountOp.networks.first(where: { $0.chainId == id }) else { continue }
                group.addTask {
                    guard let hex = try? await YourAccountChain.rpc(net, "eth_gasPrice", []) as? String,
                          let price = Decimal(string: AaveLend.decimal(hex: hex)) else { return nil }
                    return (id, price)
                }
            }
            var out: [(Int, Decimal)] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
    }

    private nonisolated static func call(_ net: YourAccountOp.Network, to: String, data: String?) async -> String? {
        guard let data, let bytes = SafeABI.hexBytes(data) else { return nil }
        guard let answer = try? await YourAccountChain.ethCall(net, to: to, data: bytes), answer.count > 2 else { return nil }
        return answer
    }

    // MARK: - Acting

    func run(account: String) async {
        guard stage == .ready, let m = market, let net = network, let units else { return }
        if YourAccountDemo.isDemo(account) {
            stage = .failed(YourAccountDemo.actsLater)
            return
        }
        guard !refused.contains(Self.key(m)) else {
            stage = .failed(String(localized: "Aave's \(m.symbol) on \(m.network) is not the market Casberi knows, so nothing was signed"))
            return
        }
        if ollaUnderMinimum {
            stage = .failed(String(localized: "Olla takes back 100 stAZTEC or more"))
            return
        }
        let calls: [AaveLend.Call]? = if m.place == .olla {
            ollaCalls(units, account: account)
        } else {
            switch mode {
            case .lend: AaveLend.lend(units, in: m, account: account)
        // All of what you lent, never Round-ups beside it: Aave's `max` only
        // where Round-ups holds nothing in this market (prd §1690).
            case .takeBack: AaveLend.takeBack(units, all: all && !(RoundUpsPot.market == m && roundUps != "0"), in: m, account: account)
            }
        }
        guard let calls, AaveLend.checked(calls, in: m, account: account) else {
            stage = .failed(String(localized: "This could not be written"))
            return
        }
        let reason = switch (m.place, mode) {
        case (.olla, _) where claims: String(localized: "Claim \(figure) from Olla")
        case (.olla, .lend): String(localized: "Deposit \(figure) on Olla")
        case (.olla, .takeBack): String(localized: "Withdraw \(figure) from Olla")
        case (.aave, .lend): String(localized: "Lend \(figure) on Aave")
        case (.aave, .takeBack): String(localized: "Take back \(figure) from Aave")
        }
        // The rows in the foot, as every Move sentence has (prd §1700z).
        let steps = PrivateSendSteps.shared
        steps.begin(.move, plan: plan)
        stage = .working(.preparing)
        do {
            let sent = try await YourAccountChain.lendCalls(calls.map { ($0.to, $0.data, $0.value) }, on: net, reason: reason) { s in
                await MainActor.run {
                    self.stage = .working(s)
                    switch s {
                    case .signing, .cosigning: steps.mark(.signing)
                    case .sending, .landing: steps.mark(.sent)
                    case .preparing: break
                    }
                }
            }
            switch sent.outcome {
            case .landed(let tx, _): steps.finish(); stage = .done(tx ?? "")
            // Taken and not seen yet: done, with no transaction to name.
            case .pending: steps.finish(); stage = .done("")
            case .dryRun: steps.clear(); stage = .ready
            }
        } catch let failure as YourAccountChain.Failure {
            steps.fail(failure.message)
            stage = .failed(failure.message)
        } catch {
            steps.fail(error.localizedDescription)
            stage = .failed(error.localizedDescription)
        }
    }

    // MARK: - Olla's reads and calls (prd §1970)

    /// Olla's calls for this move: claim what is ready, deposit at no less
    /// than 0.5% under today's price, or ask the shares back.
    private func ollaCalls(_ units: String, account: String) -> [AaveLend.Call]? {
        if claims { return OllaStake.claim(ollaReady.map(\.id)) }
        switch mode {
        case .lend:
            guard let rate = ollaRate, let least = OllaStake.minShares(forAssets: units, rate: rate) else { return nil }
            return OllaStake.deposit(units, minShares: least, account: account)
        case .takeBack:
            return ollaSharesAsked.flatMap { OllaStake.requestBack($0, account: account) }
        }
    }

    /// AZTEC held, stAZTEC and its worth, the price now and 30 days ago, and
    /// every request not yet claimed. True when the stake and the requests
    /// were both heard: only then is "nothing at Olla" a fact.
    private func readOlla(account: String) async -> Bool {
        guard let m = AaveLend.olla, let net = YourAccountOp.networks.first(where: { $0.chainId == m.chainId }) else { return true }
        let token = YourAccountOp.Token(symbol: m.symbol, decimals: m.decimals, contract: m.asset)
        async let have = YourAccountChain.balance(net, token, of: account)
        async let shares = Self.call(net, to: m.aToken, data: OllaStake.balanceCall(account: account))
        async let rate = Self.call(net, to: m.pool, data: OllaStake.assetsCall(shares: OllaStake.oneShare))
        async let ids = Self.call(net, to: m.pool, data: OllaStake.activeRequestsCall(account: account))
        let kept = Self.ollaThen.flatMap { Date.now.timeIntervalSince($0.at) < Self.ollaThenKept ? $0.price : nil }
        async let then = Self.rateBack(net, vault: m.pool, kept: kept)
        let key = Self.key(m)
        if let h = await have { held[key] = h }
        let now = await rate.flatMap(OllaStake.amount)
        if let now { ollaRate = now }
        let old = await then
        if kept == nil, let old { Self.ollaThen = (old, .now) }
        if let now, let old, let apy = OllaStake.apy(now: now, then: old) { rates[key] = apy }
        let heardShares = await shares.flatMap(OllaStake.amount)
        if let s = heardShares {
            ollaShares = s
            if let r = ollaRate { lent[key] = OllaStake.assets(forShares: s, rate: r) ?? lent[key] }
        }
        guard let list = await ids.flatMap(OllaStake.ids) else { return false }
        // Every request at once, in Olla's order; one unread and the list is partial.
        let answers = await withTaskGroup(of: (Int, OllaStake.Request?).self) { group in
            for (i, id) in list.enumerated() {
                group.addTask {
                    let answer = await Self.call(net, to: m.pool, data: OllaStake.requestCall(id: id))
                    return (i, answer.flatMap { OllaStake.request(id: id, $0) })
                }
            }
            var out = [OllaStake.Request?](repeating: nil, count: list.count)
            for await pair in group { out[pair.0] = pair.1 }
            return out
        }
        let found = answers.compactMap { $0 }
        guard found.count == list.count else { return false }
        ollaRequests = found
        await tellOllaReady(m)
        return heardShares != nil && ollaRate != nil
    }

    /// **THE PRICE 30 DAYS BACK, KEPT AN HOUR.** Two round trips in a row (the
    /// head, then an archive call), and it moves with the window's start
    /// alone: an hour is a 720th of the window, under the rate's last place.
    private static var ollaThen: (price: String, at: Date)?
    private static let ollaThenKept: TimeInterval = 3_600

    /// The share price 30 days back, off an archive read: nil where the node
    /// keeps no history, and then no rate is said.
    private nonisolated static func rateBack(_ net: YourAccountOp.Network, vault: String, kept: String?) async -> String? {
        if let kept { return kept }
        guard let headHex = try? await YourAccountChain.rpc(net, "eth_blockNumber", []) as? String,
              let head = Int(AaveLend.decimal(hex: headHex)), head > OllaStake.windowBlocks,
              let data = OllaStake.assetsCall(shares: OllaStake.oneShare) else { return nil }
        let at = "0x" + String(head - OllaStake.windowBlocks, radix: 16)
        guard let answer = try? await YourAccountChain.rpc(net, "eth_call", [["to": vault, "data": data], at]) as? String else { return nil }
        return OllaStake.amount(answer)
    }

    /// **READY TO CLAIM, SAID ONCE (prd §1970):** a request Olla finalized is
    /// told while you are away, once per request.
    private func tellOllaReady(_ m: Market) async {
        guard !DemoMode.isActive else { return }
        let key = "olla.toldReady"
        var told = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        for r in ollaReady where !told.contains(r.id) {
            told.insert(r.id)
            UserDefaults.standard.set(Array(told), forKey: key)
            let figure = PrivateMoney.figure(r.assets, decimals: m.decimals, symbol: m.symbol)
            await Notifications.outcome(.readyToClaim, id: "olla:" + r.id, place: "Olla",
                                        body: String(localized: "Claim \(figure) from Olla"), mark: "AZTEC", awayOnly: true)
        }
    }

    /// The demo's Olla, and `-ollaSample` on a simulator: AZTEC held, some
    /// staked, and a request waiting or ready (DEBUG).
    private func readOllaDemo() {
        guard let m = AaveLend.olla else { return }
        let key = Self.key(m)
        held[key] = "0"; lent[key] = "0"; ollaShares = "0"; ollaRequests = []
        ollaRate = "1091078987799669200"
        #if DEBUG
        let sample = UserDefaults.standard.string(forKey: "ollaSample") ?? ""
        guard !sample.isEmpty else { return }
        held[key] = "12400000000000000000000"
        ollaShares = "4593580000000000000000"
        lent[key] = OllaStake.assets(forShares: ollaShares, rate: ollaRate ?? "0") ?? "0"
        if sample == "waiting" || sample == "ready" {
            ollaRequests = [OllaStake.Request(id: "17", ready: sample == "ready", shares: "1000000000000000000000",
                                              assets: "1091078987799669200000")]
        }
        #endif
    }

    private static func digits(_ d: Decimal) -> String {
        var value = d, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
