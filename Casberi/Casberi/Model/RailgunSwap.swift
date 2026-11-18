import Foundation

/// **A SWAP INSIDE YOUR PRIVATE BALANCE (prd §1875).** Railgun's classic relay
/// adapter takes the token out of your Railgun wallet, makes the exchange's
/// two calls, and puts what it bought back in, in one transaction a
/// broadcaster sends (or a fresh address of yours, §1726): your account
/// appears nowhere, and the screening node clears the adapter's shield at once
/// because the same transaction's unshield is already valid (measured
/// 2026-11-18 in the node's source; the 7702 adapter is not covered there, so
/// a swap never goes through it).
///
/// Pure: the fee arithmetic and the check every swap's calls pass before
/// anything is proved. The calls are written by `YourAccountSwap.calls`, the
/// same routes public Swap takes, with the adapter as the account that sells
/// and receives.
enum RailgunSwap {
    /// What Railgun keeps of `units` at `bps`, rounded down as its contract
    /// does: ⌊units × bps / 10,000⌋.
    static func fee(_ units: String, bps: Int) -> String? {
        guard let n = whole(units), bps >= 0, bps < 10_000 else { return nil }
        return floorString(n * Decimal(bps) / 10_000)
    }

    /// What reaches the adapter of `units` sent out at `bps`: the swap sells
    /// exactly this.
    static func afterFee(_ units: String, bps: Int) -> String? {
        guard let n = whole(units), let f = fee(units, bps: bps).flatMap(whole) else { return nil }
        let left = n - f
        return left > 0 ? floorString(left) : nil
    }

    /// Whether `calls` are a swap the adapter may make: exactly two, the
    /// first on the sold token handing `amount` to a router of Ethereum's
    /// book (an exact approval, or v4's exact transfer), the second that
    /// router, carrying no ETH and naming the adapter as the receiver.
    static func checked(_ calls: [YourAccountSwap.Call], sell: String, amount: String, adapter: String,
                        routers: Set<String> = YourAccountSwap.routers(1)) -> Bool {
        guard calls.count == 2, let amountWord = SafeABI.word(uint256: amount),
              let adapterWord = SafeABI.word(address: adapter) else { return false }
        let hand = calls[0], swap = calls[1]
        let router = swap.to.lowercased()
        guard routers.contains(router), let routerWord = SafeABI.word(address: router),
              hand.to.lowercased() == sell.lowercased(), hand.value == "0", swap.value == "0",
              hand.data.count == 68 else { return false }
        let selector = Array(hand.data.prefix(4))
        guard selector == YourAccountSwap.approveSelector || selector == YourAccountSwap.transferSelector,
              Array(hand.data[4..<36]) == routerWord, Array(hand.data[36..<68]) == amountWord else { return false }
        return contains(swap.data, adapterWord)
    }

    /// The calls as the engine takes them.
    static func wire(_ calls: [YourAccountSwap.Call]) -> [RailgunEngineWire.Swap.Call] {
        calls.map { .init(to: $0.to, data: SafeABI.hex($0.data)) }
    }

    // MARK: - Arithmetic on whole base units

    private static func whole(_ s: String) -> Decimal? {
        guard !s.isEmpty, s.allSatisfy(\.isNumber), s.count <= 36 else { return nil }
        return Decimal(string: s)
    }

    private static func floorString(_ d: Decimal) -> String {
        var x = d, out = Decimal()
        NSDecimalRound(&out, &x, 0, .down)
        return NSDecimalNumber(decimal: out).stringValue
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}
