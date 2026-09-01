import Foundation

/// WEI ON THE FRAMES DEVNET, AND WHY IT CANNOT BE A `UInt64` (prd §548
/// amendment, 2026-09-01). Foundation-only BY DESIGN so
/// `scripts/frames-tx-selftest.sh` compiles it WHOLE.
///
/// **The obvious type overflows on this chain's own accounts.** `UInt64` tops
/// out at ~18.4 ETH expressed in wei, and the address this seat offers as its
/// first worked example holds **99,999.999762 ETH** — a genesis-funded dev
/// account, measured 2026-09-01, `0x152d02c7e14af6612e39c` wei. Parsing that
/// into a `UInt64` does not throw; `UInt64(_:radix:)` returns nil and a
/// `?? 0` beside it renders the richest account on the chain as **empty**.
/// That is the failure this file exists to make impossible: a balance is
/// carried as its raw hex and converted through `Decimal`, which is wide
/// enough for any 256-bit value this chain can produce.
///
/// **Nothing here rounds to a currency.** Test ETH has no price and no market,
/// so there is no dollar figure to be had and no `priceValue` is ever stamped
/// — the §83 rule in the place it would be most tempting to break, since every
/// other money surface in this app shows one.
enum FramesMoney {

    /// One ETH in wei. Named rather than spelled inline because the count of
    /// zeros is the whole of its correctness.
    static let weiPerETH = Decimal(string: "1000000000000000000")!

    /// A `0x…` quantity as a `Decimal`, or nil when it is not one.
    ///
    /// Built digit by digit rather than through `UInt64` — see the type doc.
    /// An empty body is nil, NOT zero: `eth_getBalance` answering with nothing
    /// is a read that did not happen, and drawing it as a zero balance is the
    /// §515a mistake (an unreached read is not evidence of an empty account).
    static func decimal(fromHex raw: String) -> Decimal? {
        let body = raw.hasPrefix("0x") || raw.hasPrefix("0X") ? String(raw.dropFirst(2)) : raw
        guard !body.isEmpty, body.count <= 64 else { return nil }
        var total = Decimal(0)
        for ch in body {
            guard let digit = ch.hexDigitValue else { return nil }
            total = total * 16 + Decimal(digit)
        }
        return total
    }

    /// Wei as ETH, to `places` decimals, rounded DOWN.
    ///
    /// Down rather than to-nearest, deliberately: a balance rounded up reads
    /// as more than the account holds, and on a send screen that is the number
    /// somebody would act on. The same reason `WalletIngest` truncates.
    static func eth(fromWeiHex raw: String, places: Int = 4) -> String? {
        guard let wei = decimal(fromHex: raw) else { return nil }
        var quotient = wei / weiPerETH
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, places, .down)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        formatter.usesGroupingSeparator = true
        return formatter.string(from: rounded as NSDecimalNumber)
    }

    /// A balance line for a screen, or nil when the read did not happen.
    /// **No currency symbol and no dollar figure** — see the type doc.
    static func balanceLine(weiHex: String?) -> String? {
        guard let weiHex, let amount = eth(fromWeiHex: weiHex) else { return nil }
        return String(localized: "\(amount) test ETH")
    }
}
