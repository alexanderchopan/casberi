import Foundation

/// **WHAT IS PRIVATE EARNS (prd §1541 item 2, §1563).** On Ethereum every
/// private deposit goes into 0xBow's yield pool for its token: the pool holds
/// SHARES (ppETH, ppUSDC), an ERC-4626 wrapper over Aave's deposit, whose
/// worth in the token rises as Aave pays. So a note's amount is shares, and
/// what it is worth is shares × the share's exchange rate — the yield earned
/// is in the value, never a separate figure.
///
/// The rate Holdings shows ("1.0% on Aave") is read live, never kept or
/// promised: Aave's current supply rate for the token (`getReserveData`'s
/// `currentLiquidityRate`, a per-second rate in rays, compounded over a
/// year), less the share's own fee on the yield (`feeBps`, 20% when read
/// 2026-10-26). No answer, no line.
///
/// Pure (Foundation only): `scripts/private-money-selftest.sh` compiles it.
enum PrivateYield {

    /// Aave v3's Ethereum pool, where each share's aToken lives (read off
    /// each share's `asset().POOL()` on 2026-10-26).
    static let aavePool = "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"

    static let exchangeRateCall = "0x3ba0b9a9"
    static let feeBpsCall = "0x24a9d853"

    /// `getReserveData(address)` for the token the share wraps.
    static func reserveDataCall(underlying: String) -> String? {
        guard PrivateMoney.isAddress(underlying) else { return nil }
        return "0x35ea6a75" + String(repeating: "0", count: 24) + underlying.dropFirst(2).lowercased()
    }

    /// Word `i` of an ABI answer, decimal; nil when the answer is too short.
    static func word(_ answer: String, _ i: Int) -> String? {
        guard answer.hasPrefix("0x") else { return nil }
        let body = Array(answer.dropFirst(2))
        guard body.count >= (i + 1) * 64, body.allSatisfy(\.isHexDigit) else { return nil }
        return PrivateMoney.decimal(hex: "0x" + String(body[(i * 64)..<((i + 1) * 64)]))
    }

    /// `ReserveDataLegacy`: configuration, liquidityIndex, then
    /// currentLiquidityRate (the third word).
    static func liquidityRate(reserveData answer: String) -> String? { word(answer, 2) }

    /// The yearly rate the share earns, as a fraction (0.0104 for 1.04%):
    /// Aave's per-second supply rate compounded over a year, less the share's
    /// fee on the yield. Nil for an unreadable rate, a fee past 100% or a
    /// rate no market pays (over 100% a year).
    static func apy(liquidityRateRay: String, feeBps: Int) -> Double? {
        guard let ray = Double(liquidityRateRay), ray >= 0, (0...10_000).contains(feeBps) else { return nil }
        let apr = ray / 1e27
        guard apr < 1 else { return nil }
        let seconds = 31_536_000.0
        let gross = pow(1 + apr / seconds, seconds) - 1
        return gross * (1 - Double(feeBps) / 10_000)
    }

    /// The row's line: "1.0% on Aave". Nil with no rate, so the row says its
    /// network instead (never a stale or invented figure).
    static func line(apy: Double?) -> String? {
        guard let apy, apy > 0 else { return nil }
        let percent = (apy * 100).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(percent)% on Aave")
    }

    /// What `shares` are worth in the token, base units: shares × the rate
    /// (the token's units per WHOLE share) ÷ 10^shareDecimals, rounded down.
    static func underlying(shares: String, exchangeRate: String, shareDecimals: Int) -> String? {
        guard let s = Decimal(string: shares), let r = Decimal(string: exchangeRate), s >= 0, r > 0,
              (0...36).contains(shareDecimals) else { return nil }
        var scale = Decimal(1)
        for _ in 0..<shareDecimals { scale *= 10 }
        return PrivateMoney.plain(s * r / scale)
    }

    // MARK: - Take it back on a yield pool

    /// After a ragequit the account holds loose SHARES (the pool pays out what
    /// it holds): the same transaction lets the share's zap take them and
    /// pay the token (`redeemToUnderlying`), and for ETH unwraps the WETH it
    /// pays. `worth` is the shares' value read before signing; the share only
    /// rises, so unwrapping that much never asks for more than arrived.
    /// Measured in simulation on Ethereum (`mainnet-sim.mjs ragequit`).
    static func takeBackCalls(pool: PrivacyNetwork.YieldPool, shares: String, owner: String,
                              worth: String) -> [(to: String, data: String)]? {
        guard PrivateMoney.isAddress(owner), let sharesWord = uint(shares), let worthWord = uint(worth) else { return nil }
        let ownerWord = String(repeating: "0", count: 24) + owner.dropFirst(2).lowercased()
        let zapWord = String(repeating: "0", count: 24) + pool.zap.dropFirst(2).lowercased()
        var calls: [(to: String, data: String)] = [
            (pool.share, "0x095ea7b3" + zapWord + sharesWord),
            (pool.zap, "0x7aa6a9fd" + sharesWord + ownerWord),
        ]
        if pool.native { calls.append((pool.underlying, "0x2e1a7d4d" + worthWord)) }
        return calls
    }

    /// A decimal as one 32-byte word, hex; nil past 2^256 or not a whole number.
    static func uint(_ decimal: String) -> String? {
        guard !decimal.isEmpty, decimal.allSatisfy(\.isNumber), let hex = PrivateMoney.hex(decimal) else { return nil }
        let digits = String(hex.dropFirst(2))
        guard digits.count <= 64 else { return nil }
        return String(repeating: "0", count: 64 - digits.count) + digits
    }
}
