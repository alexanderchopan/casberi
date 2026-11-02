import Foundation

/// **SPEND PAYS WITH ANYTHING (prd §1666).** Bitrefill's accountless door
/// takes USDC on Base alone (§1473), so Spend's "with" was a fact, not a
/// choice. Now it is a choice: ETH or USDC, on Base or Ethereum. Anything
/// but USDC on Base is turned into it first — on Base through its own pools
/// (§1542), from Ethereum by Across (§1555, §1566) — and the card is paid
/// once the dollars are read on Base, exactly as before.
///
/// What is sold is the card's price in the token, plus `headroomBps` for the
/// pool's price, the slippage limit and Across's fee; a quote whose minimum
/// still falls short is asked once more for proportionally more
/// (`rescale`). What is left over stays in the account as USDC on Base. Two
/// signatures, never one: the swap's, then Bitrefill's payment, which can
/// only be signed once the dollars are there.
///
/// Pure (Foundation only): `spend-topup-selftest.sh` compiles it whole.
enum SpendTopUp {
    /// Base and Ethereum, as their chain ids.
    static let base = 8453
    static let ethereum = 1

    /// What is sold over the price: 3%, room for the pool's price and its
    /// slippage limit (0.5% on Base, 0.3% on Ethereum) and Across's fee
    /// (a few cents to dollars), so one quote covers the card almost always.
    static let headroomBps = 300

    /// Whether `token` on `chainId` can pay: ETH or the network's dollar, on
    /// Base or Ethereum. `contract` is nil for ETH; `dollar` is the network's.
    static func pays(contract: String?, dollar: String, chainId: Int) -> Bool {
        guard chainId == base || chainId == ethereum else { return false }
        return contract == nil || contract?.lowercased() == dollar.lowercased()
    }

    /// Whether it pays as it is: USDC on Base, no swap first.
    static func direct(contract: String?, dollar: String, chainId: Int) -> Bool {
        chainId == base && contract != nil && contract?.lowercased() == dollar.lowercased()
    }

    /// What to sell for `cost` (USDC base units, 6 decimals) of a token worth
    /// `price` dollars, with `headroomBps` over, in the token's base units,
    /// rounded up; nil without a positive price or cost.
    static func estimate(cost: String, price: Double, decimals: Int, headroomBps: Int = headroomBps) -> String? {
        guard price > 0, price.isFinite, (0...36).contains(decimals), let c = Decimal(string: cost), c > 0 else { return nil }
        let dollars = c / pow(10, 6)
        let units = dollars / Decimal(price) * pow(10, decimals) * (1 + Decimal(headroomBps) / 10_000)
        return whole(units)
    }

    /// A quote whose minimum fell short of `cost`: sell `sold` × cost ÷
    /// minimum, and 1% more; nil for a minimum of nothing.
    static func rescale(sold: String, minimum: String, cost: String) -> String? {
        guard let s = Decimal(string: sold), let m = Decimal(string: minimum), let c = Decimal(string: cost), m > 0, s > 0 else {
            return nil
        }
        return whole(s * c / m * Decimal(string: "1.01")!)
    }

    /// Whether at least `cost` comes back: the quote's minimum, never its
    /// hope.
    static func covers(minimum: String, cost: String) -> Bool {
        guard let m = Decimal(string: minimum), let c = Decimal(string: cost) else { return false }
        return m >= c
    }

    /// A positive decimal rounded up to a whole number, as digits.
    private static func whole(_ d: Decimal) -> String? {
        var x = d, r = Decimal()
        NSDecimalRound(&r, &x, 0, .up)
        guard r > 0 else { return nil }
        let s = NSDecimalNumber(decimal: r).stringValue
        return s.allSatisfy(\.isNumber) ? s : nil
    }
}
