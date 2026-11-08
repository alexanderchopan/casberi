import Foundation

/// **WHICH PRIVATE POCKET A TOKEN GOES TO, AND HOW MUCH MOVES (prd §1713
/// items 1 and 2, §1721).** Foundation-only, so `railgun-selftest.sh`
/// compiles it whole and unmodified.
///
/// - **Routing is by token, and the person never picks.** On Ethereum, ETH
///   and USDC go to Privacy Pools; any other token goes to Railgun. Off
///   Ethereum, nothing goes to Railgun.
/// - **The same $10 floor** as Privacy Pools: a token moves in from $10
///   worth at the price Casberi reads, rounded up to 1, 2 or 5 of its power
///   of ten. A token with no price has no floor to measure, so it is not
///   offered in. Taking back has no floor: all of it is always offered.
enum RailgunRouting {
    /// Ethereum's USDC, the one dollar Privacy Pools holds there.
    static let ethereumUSDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
    static let ethereumChainID = 1
    static let floorUSD: Double = 10

    static func goesToRailgun(symbol: String, contract: String?, chainId: Int) -> Bool {
        guard chainId == ethereumChainID, let contract, !contract.isEmpty else { return false }
        return contract.lowercased() != ethereumUSDC && symbol.uppercased() != "ETH"
    }

    /// One amount a sentence offers: base units, decimal; `all` is the
    /// whole of what is held.
    struct Step: Equatable {
        let units: String
        let all: Bool
    }

    /// The amounts a token offers. With `floorUSD`, from that much worth up
    /// to (not past) what is held, then all of it; with no price, nothing.
    /// Without a floor (taking back), steps from $10 worth where priced,
    /// and all of it always.
    static func ladder(decimals: Int, held: String, price: Double?, floorUSD: Double?) -> [Step] {
        guard let heldUnits = Decimal(string: held), heldUnits > 0 else { return [] }
        let scale = pow(Decimal(10), decimals)
        let whole = NSDecimalNumber(decimal: heldUnits / scale).doubleValue
        var steps: [Double] = []
        if let floorUSD {
            guard let price, price > 0 else { return [] }
            let start = nice(floorUSD / price)
            guard start <= whole else { return [] }
            var x = start
            while x < whole, steps.count < 4 {
                steps.append(x)
                x = nextNice(x)
            }
        } else if let price, price > 0 {
            var x = nice(Self.floorUSD / price)
            while x < whole, steps.count < 3 {
                steps.append(x)
                x = nextNice(x)
            }
        }
        var out = steps.map { step -> Step in
            var units = Decimal(step) * scale, rounded = Decimal()
            NSDecimalRound(&rounded, &units, 0, .down)
            return Step(units: NSDecimalNumber(decimal: rounded).stringValue, all: false)
        }
        out.append(Step(units: held, all: true))
        return out
    }

    /// The smallest 1, 2 or 5 times a power of ten at or above `x`.
    static func nice(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let p = pow(10, floor(log10(x)))
        for m in [1.0, 2.0, 5.0, 10.0] where m * p >= x * 0.999_999 { return m * p }
        return 10 * p
    }

    /// The next of 1, 2, 5, 10 … after a nice `x`.
    static func nextNice(_ x: Double) -> Double {
        let p = pow(10, floor(log10(x) + 1e-9))
        let m = (x / p).rounded()
        return m < 1.5 ? 2 * p : m < 3.5 ? 5 * p : 10 * p
    }
}
