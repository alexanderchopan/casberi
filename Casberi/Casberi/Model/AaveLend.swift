import Foundation

/// **LEND (prd §1674).** Move's fifth verb puts your account's USDC or ETH in
/// Aave and takes it back: "Lend 500 USDC on Aave on Base." The word is Lend,
/// never Earn — it says what happens (the money goes to borrowers, and that
/// is where the rate comes from) and keeps "earning" for the private balance.
///
/// Two markets on two networks, each read and simulated against the real
/// state on 2026-11-02 (Base head 53,433,491, Ethereum 26,329,901):
///
/// - **USDC**: approve the Pool exactly the amount, then `supply` on behalf
///   of the account. Taking back is `withdraw` to the account; all of it is
///   `type(uint256).max`, which Aave reads as the whole balance.
/// - **ETH**: wrapped first (`WETH.deposit`), then the same approve and
///   `supply`. Taking back withdraws the WETH and unwraps it; all of it
///   withdraws the whole balance and unwraps what was read (the aToken rounds
///   down a wei, so what arrives is never less).
///
/// The approval is the amount, never unlimited: `supply` spends it to zero,
/// so nothing is left standing for the Permissions door to flag.
///
/// Pure (Foundation only): `scripts/aave-lend-selftest.sh` compiles it.
enum AaveLend {

    /// **ONE WAY OFF.** False, Move draws no Lend and Holdings no lent rows.
    static let on = true

    struct Market: Equatable, Sendable {
        let chainId: Int
        /// "Base", the account's own network name.
        let network: String
        /// Aave v3's Pool there (`WalletDeFi`'s, the same address).
        let pool: String
        /// What the sentence says: "USDC" or "ETH".
        let symbol: String
        /// What Aave holds: USDC, or WETH for ETH.
        let asset: String
        /// The receipt token that grows: `getReserveData(asset)`'s ninth word.
        let aToken: String
        let decimals: Int
        var native: Bool { symbol == "ETH" }
    }

    /// Read off each Pool's `getReserveData` on 2026-11-02 (the aToken is
    /// its ninth word; symbols aBasUSDC, aBasWETH, aEthUSDC, aEthWETH), every
    /// reserve active, none frozen or paused.
    static let markets: [Market] = [
        Market(chainId: 8453, network: "Base", pool: "0xa238dd80c259a72e81d7e4664a9801593f98d1c5",
               symbol: "USDC", asset: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
               aToken: "0x4e65fe4dba92790696d040ac24aa414708f5c0ab", decimals: 6),
        Market(chainId: 8453, network: "Base", pool: "0xa238dd80c259a72e81d7e4664a9801593f98d1c5",
               symbol: "ETH", asset: "0x4200000000000000000000000000000000000006",
               aToken: "0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7", decimals: 18),
        Market(chainId: 1, network: "Ethereum", pool: "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
               symbol: "USDC", asset: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
               aToken: "0x98c23e9d8f34fefb1b7bd6a91b7ff122f4e16f5c", decimals: 6),
        Market(chainId: 1, network: "Ethereum", pool: "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
               symbol: "ETH", asset: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
               aToken: "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8", decimals: 18),
    ]

    /// The networks Lend offers, in the account's order: Aave has no market
    /// on Robinhood Chain.
    static let chainIds = [8453, 1]

    /// Whether a token is one of these markets' aTokens (prd §1695): what
    /// is lent, never a token you can spend, so the Tokens list never counts
    /// it beside Lent (an Alchemy read lists an aToken as a plain ERC-20).
    static func isReceipt(_ contract: String?) -> Bool {
        guard let c = contract?.lowercased() else { return false }
        return markets.contains { $0.aToken == c }
    }

    static func market(chainId: Int, symbol: String) -> Market? {
        markets.first { $0.chainId == chainId && $0.symbol == symbol }
    }

    /// One contract call: where, its calldata, and the ETH it carries
    /// (decimal wei), as `YourAccountChain.privateCalls` takes them.
    struct Call: Equatable, Sendable {
        let to: String
        let data: String
        let value: String
    }

    // MARK: - The calls

    /// Lend `amount` (base units, decimal) of the market's token.
    static func lend(_ amount: String, in m: Market, account: String) -> [Call]? {
        guard let a = word(amount), isAddress(account), positive(amount) else { return nil }
        let approve = Call(to: m.asset, data: "0x095ea7b3" + word(address: m.pool) + a, value: "0")
        let supply = Call(to: m.pool, data: "0x617ba037" + word(address: m.asset) + a + word(address: account) + zero, value: "0")
        if m.native {
            return [Call(to: m.asset, data: "0xd0e30db0", value: amount), approve, supply]
        }
        return [approve, supply]
    }

    /// Take back `amount` (base units, decimal). With `all`, the whole
    /// balance is withdrawn (`max`) and `amount` is what was read of it, the
    /// ETH unwrapped; without, exactly `amount`.
    static func takeBack(_ amount: String, all: Bool, in m: Market, account: String) -> [Call]? {
        guard let a = word(amount), isAddress(account), positive(amount) else { return nil }
        let withdraw = Call(to: m.pool, data: "0x69328dec" + word(address: m.asset) + (all ? max : a) + word(address: account),
                            value: "0")
        if m.native {
            return [withdraw, Call(to: m.asset, data: "0x2e1a7d4d" + a, value: "0")]
        }
        return [withdraw]
    }

    /// **NOTHING ELSE IS SIGNED.** Every call goes to the market's own asset
    /// or Pool, the approval names the Pool for no more than the supply, the
    /// supply is on behalf of the account, a withdrawal pays the account, and
    /// ETH rides only the wrap. Anything else, and the list is refused.
    static func checked(_ calls: [Call], in m: Market, account: String) -> Bool {
        guard !calls.isEmpty, isAddress(account) else { return false }
        let me = word(address: account), pool = word(address: m.pool), asset = word(address: m.asset)
        var approved: String?
        for c in calls {
            let to = c.to.lowercased(), data = c.data.lowercased()
            let sel = String(data.prefix(10)), args = Array(words(data))
            switch (to, sel) {
            case (m.asset, "0xd0e30db0") where m.native && args.isEmpty && positive(c.value):
                continue
            case (m.asset, "0x095ea7b3") where args.count == 2 && args[0] == pool && c.value == "0":
                approved = args[1]
            case (m.pool, "0x617ba037") where args.count == 4 && args[0] == asset && args[2] == me && args[3] == zero
                && c.value == "0" && approved.map({ $0 >= args[1] }) == true:
                approved = nil
            case (m.pool, "0x69328dec") where args.count == 3 && args[0] == asset && args[2] == me && c.value == "0":
                continue
            case (m.asset, "0x2e1a7d4d") where m.native && args.count == 1 && c.value == "0":
                continue
            default:
                return false
            }
        }
        // An approval no supply spent is left standing: refused.
        return approved == nil
    }

    // MARK: - Reads

    /// `getReserveData(asset)` on the Pool.
    static func reserveDataCall(_ m: Market) -> String { "0x35ea6a75" + word(address: m.asset) }

    /// `balanceOf(account)` on the aToken: what is lent, interest included.
    static func lentCall(account: String) -> String? {
        isAddress(account) ? "0x70a08231" + word(address: account) : nil
    }

    /// The reserve's aToken (the ninth word), to hold the pinned one to.
    static func aToken(reserveData answer: String) -> String? {
        guard let w = wordAt(answer, 8) else { return nil }
        return "0x" + w.suffix(40)
    }

    /// The supply rate a year (0.0508 for 5.08%): `currentLiquidityRate`,
    /// the third word, a per-second rate in rays compounded over a year.
    /// Nil when unreadable or past 100%.
    static func apy(reserveData answer: String) -> Double? {
        guard let w = wordAt(answer, 2), let ray = Double(decimal(hex: w)) else { return nil }
        let apr = ray / 1e27
        guard apr >= 0, apr < 1 else { return nil }
        let seconds = 31_536_000.0
        return pow(1 + apr / seconds, seconds) - 1
    }

    /// "5.1% on Aave": one place under ten, none past it.
    static func rateLine(_ apy: Double?) -> String? {
        guard let apy, apy > 0 else { return nil }
        let pct = apy * 100
        let shown = pct < 10 ? String(format: "%.1f", pct) : String(format: "%.0f", pct)
        return String(localized: "\(shown)% on Aave")
    }

    // MARK: - Words

    private static let zero = String(repeating: "0", count: 64)
    private static let max = String(repeating: "f", count: 64)

    static func isAddress(_ s: String) -> Bool {
        s.count == 42 && s.hasPrefix("0x") && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    private static func positive(_ amount: String) -> Bool {
        amount.range(of: #"^[1-9][0-9]{0,77}$"#, options: .regularExpression) != nil
    }

    private static func word(address: String) -> String {
        String(repeating: "0", count: 24) + address.dropFirst(2).lowercased()
    }

    /// A decimal amount as one 32-byte word; nil past 2^256 or not digits.
    static func word(_ amount: String) -> String? {
        guard amount.range(of: #"^[0-9]{1,78}$"#, options: .regularExpression) != nil else { return nil }
        var digits = amount.compactMap(\.wholeNumberValue)
        var out: [Character] = []
        while !(digits.isEmpty || digits.allSatisfy { $0 == 0 }) {
            var rest: [Int] = [], carry = 0
            for d in digits {
                let cur = carry * 10 + d
                let q = cur / 16
                carry = cur % 16
                if !rest.isEmpty || q > 0 { rest.append(q) }
            }
            out.append(Character(String(carry, radix: 16)))
            digits = rest
        }
        guard out.count <= 64 else { return nil }
        return String(repeating: "0", count: 64 - out.count) + String(out.reversed())
    }

    private static func words(_ data: String) -> [String] {
        let body = Array(data.dropFirst(10))
        guard body.count % 64 == 0 else { return ["?"] }
        return stride(from: 0, to: body.count, by: 64).map { String(body[$0..<$0 + 64]) }
    }

    private static func wordAt(_ answer: String, _ i: Int) -> String? {
        guard answer.hasPrefix("0x") else { return nil }
        let body = Array(answer.dropFirst(2))
        guard body.count >= (i + 1) * 64, body.allSatisfy(\.isHexDigit) else { return nil }
        return String(body[(i * 64)..<((i + 1) * 64)]).lowercased()
    }

    /// A hex word (no 0x) or a 0x quantity as decimal digits.
    static func decimal(hex: String) -> String {
        var digits: [Int] = [0]
        for ch in hex.hasPrefix("0x") ? Substring(hex.dropFirst(2)) : Substring(hex) {
            guard let v = ch.hexDigitValue else { return "0" }
            var carry = v
            for i in stride(from: digits.count - 1, through: 0, by: -1) {
                let cur = digits[i] * 16 + carry
                digits[i] = cur % 10
                carry = cur / 10
            }
            while carry > 0 { digits.insert(carry % 10, at: 0); carry /= 10 }
        }
        let s = digits.map(String.init).joined().drop { $0 == "0" }
        return s.isEmpty ? "0" : String(s)
    }
}
