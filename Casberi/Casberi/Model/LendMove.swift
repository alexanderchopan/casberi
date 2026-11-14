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
            guard let units = Decimal(string: lent[Self.key(m)] ?? "0"), units > 0 else { continue }
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
            return lent[Self.key(m)]
        }
    }

    /// The amounts offered: the token's ladder under what is available, then
    /// all of it.
    func choices(_ m: Market) -> [String] {
        guard let have = available(m).flatMap({ Decimal(string: $0) }), have > 0 else { return [] }
        let ladder = m.native ? Self.ethLadder : Self.usdcLadder
        return ladder.filter { step in
            guard let units = PrivateMoney.baseUnits(step, decimals: m.decimals).flatMap({ Decimal(string: $0) }) else { return false }
            return units < have
        }
    }

    static let usdcLadder = ["1", "5", "10", "25", "50", "100", "250", "500", "1000", "2500", "5000", "10000"]
    static let ethLadder = ["0.001", "0.005", "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1", "2.5", "5"]

    /// The amount in base units: what was picked, or all of what is available.
    var units: String? {
        guard let m = market else { return nil }
        if all { return available(m).flatMap { $0 == "0" ? nil : $0 } }
        return amount.flatMap { PrivateMoney.baseUnits($0, decimals: m.decimals) }
    }

    /// "500 USDC", "0.0842 ETH": what the sentence says it moves.
    var figure: String {
        guard let m = market else { return symbol }
        guard let units else { return "0 \(m.symbol)" }
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

    /// Under the sentence: "$100.00 · you have $250.00" (lend) or
    /// "$100.00 · $500.00 lent" (take back); no price, the token.
    var amountLine: String? {
        guard let m = market, let have = available(m) else { return nil }
        var parts: [String] = []
        if let units, let usd = dollars(units, in: m) { parts.append(Self.usd(usd)) }
        let haveText = dollars(have, in: m).map(Self.usd) ?? PrivateMoney.figure(have, decimals: m.decimals, symbol: m.symbol)
        parts.append(mode == .lend ? String(localized: "you have \(haveText)") : String(localized: "\(haveText) lent"))
        return parts.joined(separator: " · ")
    }

    /// "You have $250.00" (lend) or "$500.00 lent" (take back): the head of
    /// the amount's menu (prd §1802).
    var haveLine: String? {
        guard let m = market, let have = available(m) else { return nil }
        let text = dollars(have, in: m).map(Self.usd) ?? PrivateMoney.figure(have, decimals: m.decimals, symbol: m.symbol)
        return mode == .lend ? String(localized: "You have \(text)") : String(localized: "\(text) lent")
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
        return PrivateCost(usd: usd, parts: [.init(words: String(localized: "Gas, from your account"),
                                                   figure: String(localized: "about \(Self.usd(usd))"))])
    }

    /// The step rows' plan: signed, sent on this network (prd §1700z).
    var plan: PrivateSendSteps.Plan {
        .signed(chainId == 1 ? .ethereum : .base)
    }

    /// Any market where something is lent: Holdings' rows, and whether Take
    /// back has anything to say.
    var anyLent: Bool { lent.values.contains { (Decimal(string: $0) ?? 0) > 0 } }

    // MARK: - Reading

    func read(account: String) async {
        if case .working = stage { return }
        stage = .reading
        if YourAccountDemo.isDemo(account) {
            readDemo()
        } else {
            await readChain(account: account)
        }
        let found = await MainnetPrices.prices(for: AaveLend.markets.map(\.symbol))
        if found != prices { prices = found }
        settle()
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
        if let m = market, amount == nil, !all {
            amount = choices(m).last
            all = amount == nil && (Decimal(string: available(m) ?? "0") ?? 0) > 0
        }
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
        lentAnswered = true
        rates = ["8453|USDC": 0.0508, "8453|ETH": 0.0143, "1|USDC": 0.0379, "1|ETH": 0.0145]
        reserve = [8453: "100000000000000", 1: "1000000000000000"]
        gasPriceWei = [8453: 6_000_000, 1: 400_000_000]
    }

    private func readChain(account: String) async {
        typealias Read = (key: String, held: String?, lent: String?, rate: Double?, aToken: String?)
        let found: [Read] = await withTaskGroup(of: Read.self) { group in
            for m in AaveLend.markets {
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
        // Every market's aToken balance heard, or the reading is partial.
        lentAnswered = found.count == AaveLend.markets.count && found.allSatisfy { $0.lent != nil }
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
        for id in AaveLend.chainIds {
            guard let net = YourAccountOp.networks.first(where: { $0.chainId == id }),
                  let hex = try? await YourAccountChain.rpc(net, "eth_gasPrice", []) as? String,
                  let price = Decimal(string: AaveLend.decimal(hex: hex)) else { continue }
            // Twice today's price for the most a lend of ETH has taken with
            // the account's own calls around it (246k measured, 600k kept).
            reserve[id] = Self.digits(price * 600_000 * 2)
            gasPriceWei[id] = price
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
        let calls: [AaveLend.Call]? = switch mode {
        case .lend: AaveLend.lend(units, in: m, account: account)
        // All of what you lent, never Round-ups beside it: Aave's `max` only
        // where Round-ups holds nothing in this market (prd §1690).
        case .takeBack: AaveLend.takeBack(units, all: all && !(RoundUpsPot.market == m && roundUps != "0"), in: m, account: account)
        }
        guard let calls, AaveLend.checked(calls, in: m, account: account) else {
            stage = .failed(String(localized: "This could not be written"))
            return
        }
        let reason = mode == .lend ? String(localized: "Lend \(figure) on Aave") : String(localized: "Take back \(figure) from Aave")
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

    private static func digits(_ d: Decimal) -> String {
        var value = d, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
