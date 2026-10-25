import Foundation

/// **ROUND-UPS (prd §1452).** Every dollar send from your account rounds up
/// to the next $1 (or $5), and the change buys a token you pick — ETH on Base
/// unless you choose another, on any network Relay reaches — once it reaches
/// $5, with the send that gets it there.
///
/// The change never leaves on its own: it waits in your dollar, counted here,
/// because a swap costs Relay a flat few cents (measured 2026-10-21: ~$0.03 on
/// Base, ~$0.07 into Robinhood Chain), so buying each $0.70 would lose a tenth
/// or more of it. One balance, a running count, a buy at $5.
///
/// The buy is a plain `transfer` of the dollar to Relay's deposit address for
/// the route (`YourAccountChain.roundUpCall`) — the same call a send is, so a
/// spend limit's session can carry it too, and no approval is ever granted.
///
/// **What it bought is Spending's Round-ups door (prd §1523)**, never part of
/// the total: the change was kept, not spent.
enum RoundUps {
    /// What the change buys. `address` is Relay's spelling: the zero address
    /// for a network's own coin.
    struct Target: Codable, Equatable, Hashable, Sendable {
        var chainId: Int
        var address: String
        var symbol: String
        var decimals: Int
        var network: String

        static let ethOnBase = Target(chainId: 8453, address: "0x0000000000000000000000000000000000000000",
                                      symbol: "ETH", decimals: 18, network: "Base")
    }

    struct Setting: Codable, Equatable, Sendable {
        var on = false
        /// Dollars to round up to: 1 or 5.
        var step = 1
        var target = Target.ethOnBase
    }

    /// The change is bought once it reaches this, in the dollar's units ($5).
    /// DEBUG's `-roundUpsBuyAt <units>` lowers it for a test account.
    static var buyAt: String {
        #if DEBUG
        if let units = UserDefaults.standard.string(forKey: "roundUpsBuyAt"), Decimal(string: units) != nil { return units }
        #endif
        return "5000000"
    }
    static let dollarDecimals = 6

    private static let settingKey = "yourAccount.roundUps"
    private static func savedKey(_ chainId: Int) -> String { "yourAccount.roundUps.saved.\(chainId)" }

    static var setting: Setting {
        get {
            if YourAccountDemo.isOn { return YourAccountDemo.roundUps }
            return UserDefaults.standard.data(forKey: settingKey).flatMap { try? JSONDecoder().decode(Setting.self, from: $0) } ?? Setting()
        }
        set {
            // The demo's round-ups are its own (prd §1475): a change there
            // draws, and this phone's setting is never touched.
            guard !YourAccountDemo.isOn else { return }
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: settingKey) }
        }
    }

    /// The change counted so far on a network, in its dollar's units.
    static func saved(on chainId: Int) -> String {
        // The demo's change so far: $2.60 of the $5 (§1475).
        if YourAccountDemo.isOn { return chainId == YourAccountOp.base.chainId ? "2600000" : "0" }
        return UserDefaults.standard.string(forKey: savedKey(chainId)) ?? "0"
    }

    static func setSaved(_ units: String, on chainId: Int) {
        guard !YourAccountDemo.isOn else { return }
        UserDefaults.standard.set(units, forKey: savedKey(chainId))
    }

    /// The change waiting on every network, in dollars: what Spending's
    /// Round-ups row says is not bought yet (prd §1523).
    static var waitingUSD: Double {
        YourAccountOp.networks.reduce(0) { sum, net in
            sum + ((Decimal(string: saved(on: net.chainId)).map { NSDecimalNumber(decimal: $0 / pow(10, dollarDecimals)).doubleValue }) ?? 0)
        }
    }

    // MARK: - The buys (prd §1523)

    /// **RELAY'S DEPOSIT ADDRESSES THIS PHONE PAID A ROUND-UP TO.** Relay
    /// hands out a new address per quote, so nothing on chain says a transfer
    /// to one was a round-up's buy: this list does. The landed send to one is
    /// stamped `.roundUp` (`SpendingSource.stampRoundUp`), and the stamp
    /// rides the row through iCloud; the list itself stays on this phone.
    /// Kept when the address is asked for, before the send lands: an address
    /// a send never reached marks nothing. The newest `depositCap` are kept.
    struct Deposit: Codable, Equatable, Sendable {
        var address: String
        var target: Target
        var at: Date
    }

    static let depositCap = 200
    private static let depositsKey = "yourAccount.roundUps.deposits"

    static var deposits: [Deposit] {
        UserDefaults.standard.data(forKey: depositsKey).flatMap { try? JSONDecoder().decode([Deposit].self, from: $0) } ?? []
    }

    static func noteDeposit(_ address: String, target: Target, at: Date = .now) {
        guard !YourAccountDemo.isOn, !address.isEmpty else { return }
        var list = deposits.filter { $0.address.caseInsensitiveCompare(address) != .orderedSame }
        list.append(Deposit(address: address.lowercased(), target: target, at: at))
        if list.count > depositCap { list.removeFirst(list.count - depositCap) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: depositsKey) }
    }

    /// What a round-up paid to each deposit address buys, by lowercased
    /// address: read once for a pass over many rows.
    static func depositTargets() -> [String: Target] {
        Dictionary(deposits.map { ($0.address.lowercased(), $0.target) }, uniquingKeysWith: { _, newer in newer })
    }

    /// What `units` of the dollar rounds up by, to the next `step` dollars;
    /// nothing when it is already whole.
    static func change(_ units: String, step: Int) -> String {
        guard step > 0, let n = Decimal(string: units) else { return "0" }
        let stepUnits = Decimal(step) * pow(10, dollarDecimals)
        var quotient = n / stepUnits
        var floored = Decimal()
        NSDecimalRound(&floored, &quotient, 0, .down)
        let rest = n - floored * stepUnits
        return rest == 0 ? "0" : NSDecimalNumber(decimal: stepUnits - rest).stringValue
    }

    /// One send's round-up: the change it adds, and — when the count reaches
    /// $5 with it — everything counted, to buy now.
    struct Plan: Equatable, Sendable {
        let change: String
        let buy: String?
        let savedAfter: String
    }

    static func plan(dollarSent units: String, saved: String, step: Int) -> Plan {
        let change = change(units, step: step)
        let total = YourAccountOp.sum(saved, change)
        if YourAccountOp.atMost(buyAt, total) {
            return Plan(change: change, buy: total, savedAfter: "0")
        }
        return Plan(change: change, buy: nil, savedAfter: total)
    }
}
