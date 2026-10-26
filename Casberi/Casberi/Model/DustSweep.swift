import Foundation

/// **SWEEP (prd §1537).** Move's fifth verb: every token on one network worth
/// less than $1 (or $5, the round-ups choice), swapped for ETH in ONE
/// transaction and one Face ID (user, 2026-10-26: "default to 1$ but give
/// user option to set to 5$. just like we do roundups. one faceid. … it needs
/// to go in move since it is a money action. we could call it sweep").
///
/// This file picks what is swept and what stays, and why; the swaps are
/// Move's own (`YourAccountChain.Swap`), quoted by Relay and signed through
/// `YourAccountChain.transact`, which simulates the whole batch before Face
/// ID and refuses it unless every swap pays its minimum. Pure: amounts are
/// base-unit decimal strings, so `dust-sweep-selftest.sh` reads it with no
/// network and no SwiftUI.
///
/// - ETH is what comes back, so it is never swept.
/// - A token with no price stays: nothing says it is under the line.
/// - A token Relay has not verified stays, unless a swap here bought it:
///   most dust is sent by strangers, and selling it calls its own contract.
/// - The network's dollar stays while round-ups count change in it.
/// - A swap whose ETH is worth less than half of what it sells stays: Relay's
///   flat fee eats a token worth a few cents.
/// - Ten swaps at most in one sweep; the rest wait for the next.
enum DustSweep {

    /// One token the account holds on the network being swept.
    struct Holding: Equatable, Sendable, Identifiable {
        let symbol: String
        /// nil for the network's own coin.
        let contract: String?
        let decimals: Int
        /// Base units, a decimal string.
        let units: String
        /// Dollars for all of it; nil when nothing priced it.
        let usd: Double?
        /// Relay verified it, or a swap from this account bought it.
        let trusted: Bool
        /// The network's dollar, where round-ups wait.
        let isDollar: Bool
        var id: String { contract?.lowercased() ?? symbol.uppercased() }
        var isNative: Bool { contract == nil }
    }

    enum Stay: Equatable, Sendable {
        case noPrice
        case notVerified
        /// Round-ups' change is counted in it.
        case roundUps
        /// Past `maxSwaps`: the next sweep takes it.
        case nextSweep
        /// Relay gave no route for it.
        case noRoute
        /// What comes back is worth less than half of it.
        case costsMore
        /// You took it out of this sweep.
        case leftOut
    }

    /// One line under the sentence: a token, and why it stays (nil: swept).
    struct Row: Equatable, Sendable, Identifiable {
        let holding: Holding
        let stay: Stay?
        var id: String { holding.id }
    }

    struct Plan: Equatable, Sendable {
        /// Most dollars first.
        var sweeps: [Holding]
        var stays: [(Holding, Stay)]
        var sweptUSD: Double { sweeps.reduce(0) { $0 + ($1.usd ?? 0) } }
        /// What is swept, then what stays, each in its own order.
        var rows: [Row] { sweeps.map { Row(holding: $0, stay: nil) } + stays.map { Row(holding: $0.0, stay: $0.1) } }
        static func == (a: Plan, b: Plan) -> Bool {
            a.sweeps == b.sweeps && a.stays.map(\.0) == b.stays.map(\.0) && a.stays.map(\.1) == b.stays.map(\.1)
        }
    }

    /// The two lines a sweep can draw, as round-ups' two steps are.
    static let choices = [1, 5]
    static let defaultUnder = 1
    /// A batch of swaps grows its gas with each; ten stays well inside a
    /// block on every network the account is on.
    static let maxSwaps = 10
    /// The least a swap must return, as a share of what it sells.
    static let leastBack = 0.5

    // MARK: - The setting

    private static let underKey = "yourAccount.sweep.under"

    /// $1 or $5; $1 until you pick. The demo's line is the default and never
    /// written (§1475).
    static var under: Int {
        get {
            if YourAccountDemo.isOn { return defaultUnder }
            let saved = UserDefaults.standard.integer(forKey: underKey)
            return choices.contains(saved) ? saved : defaultUnder
        }
        set {
            guard !YourAccountDemo.isOn, choices.contains(newValue) else { return }
            UserDefaults.standard.set(newValue, forKey: underKey)
        }
    }

    // MARK: - The plan

    /// What on one network is swept, and what stays with its reason.
    /// `roundUpsWaiting`: round-ups count change in this network's dollar.
    /// `leftOut`: the ids you took out of this sweep.
    static func plan(_ holdings: [Holding], under: Int, roundUpsWaiting: Bool,
                     leftOut: Set<String> = []) -> Plan {
        let line = Double(choices.contains(under) ? under : defaultUnder)
        var sweeps: [Holding] = []
        var stays: [(Holding, Stay)] = []
        let ordered = holdings.sorted { ($0.usd ?? -1) != ($1.usd ?? -1) ? ($0.usd ?? -1) > ($1.usd ?? -1) : $0.symbol < $1.symbol }
        for h in ordered where !h.isNative && isPositive(h.units) {
            guard let usd = h.usd else { stays.append((h, .noPrice)); continue }
            guard usd < line else { continue }
            if leftOut.contains(h.id) { stays.append((h, .leftOut)) }
            else if !h.trusted { stays.append((h, .notVerified)) }
            else if h.isDollar && roundUpsWaiting { stays.append((h, .roundUps)) }
            else if sweeps.count >= maxSwaps { stays.append((h, .nextSweep)) }
            else { sweeps.append(h) }
        }
        return Plan(sweeps: sweeps, stays: stays)
    }

    /// Relay's answers folded in: a token with no quote stays `.noRoute`, one
    /// whose ETH is worth less than `leastBack` of it stays `.costsMore`.
    /// `back(id)` is the ETH a quote returns, in wei, nil for no quote;
    /// `ethPrice` nil keeps every quoted token (the simulation still holds
    /// each swap to its minimum).
    static func judged(_ plan: Plan, back: (String) -> String?, ethPrice: Double?) -> Plan {
        var sweeps: [Holding] = []
        var stays = plan.stays
        for h in plan.sweeps {
            guard let wei = back(h.id), isPositive(wei) else { stays.append((h, .noRoute)); continue }
            if let ethPrice, let usd = h.usd, let backUSD = dollars(wei, decimals: 18, price: ethPrice),
               backUSD < usd * leastBack {
                stays.append((h, .costsMore))
                continue
            }
            sweeps.append(h)
        }
        return Plan(sweeps: sweeps, stays: stays)
    }

    /// The ETH a sweep returns, summed: what the sentence says comes back.
    static func total(_ amounts: [String]) -> String {
        var sum = Decimal(0)
        for a in amounts { if let d = Decimal(string: a), a.allSatisfy(\.isNumber) { sum += d } }
        return NSDecimalNumber(decimal: sum).stringValue
    }

    // MARK: - Base units

    static func isPositive(_ units: String) -> Bool {
        !units.isEmpty && units.allSatisfy(\.isNumber) && units.contains { $0 != "0" }
    }

    /// Base units at a price, in dollars; nil for anything but digits.
    static func dollars(_ units: String, decimals: Int, price: Double) -> Double? {
        guard !units.isEmpty, units.allSatisfy(\.isNumber), let d = Decimal(string: units) else { return nil }
        let whole = NSDecimalNumber(decimal: d / pow(10, decimals)).doubleValue
        return whole * price
    }
}
