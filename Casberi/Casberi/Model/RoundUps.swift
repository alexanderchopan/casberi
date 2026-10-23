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
