import Foundation

/// **OLLA, EARN'S PLACE FOR AZTEC (prd §1970).** Olla is liquid staking for
/// the AZTEC token on Ethereum: AZTEC goes into its vault, stAZTEC comes back
/// in the same transaction, and each stAZTEC is worth more AZTEC as Aztec's
/// staking rewards come in. Earn takes it as it takes Aave: the token decides
/// the place (USDC → Aave, AZTEC → Olla), from your public account, one
/// simulated Face ID operation.
///
/// MEASURED on Ethereum mainnet (2026-11-24, block ~26,486,700), keyless:
/// - The vault (an ERC-1967 proxy, implementation `0x2dc8…ee1f`) carries
///   every selector used here in its live code: `deposit(uint256,address,
///   uint256)` `0xbc157ac1`, `requestRedeem(uint256,address,address)`
///   `0x7d41c86e`, `claimRequestById(uint256)` `0x809f8360`,
///   `activeRequestIds(address)` `0xea7c316c`, `getWithdrawalRequest(uint256)`
///   `0xae485651`, `convertToAssets(uint256)` `0x07a2d13a`.
/// - 32.46M AZTEC behind 29.75M stAZTEC: 1 stAZTEC = 1.0911 AZTEC; 30 days
///   earlier 1.0671 (an archive read), so about 31% a year after Olla's fee.
/// - **Taking back is a queue (ERC-7540).** `requestRedeem` burns the shares
///   at once and files a request; a later rebalance finalizes it, then
///   `claimRequestById` pays the controller. Request 16 waited 4,362 blocks
///   (~14.5 hours); rebalances run about daily. `activeRequestIds(owner)`
///   lists requests not yet claimed, finalized ones included (request 15,
///   finalized, still listed). A request is (finalized, shares,
///   assetsExpected, rate), four static words.
/// - The owner asking for itself needs no allowance on stAZTEC (`msg.sender
///   == owner` skips `spendAllowance`).
/// - SafetyModule `0x3e3d…f8cd`: `withdrawalMinimum` 100 stAZTEC, deposit
///   cap 100M AZTEC, nothing paused.
/// - Olla's own docs: the live StakingManager carries a change made after the
///   Pashov audit that the audit does not cover; governance may upgrade after
///   a 2-day timelock; the fee is 10% of rewards, settable up to 50%.
///
/// Pure (Foundation only, with `AaveLend`'s words): `scripts/olla-stake-
/// selftest.sh` compiles it.
enum OllaStake {

    static let vault = "0x561c7cff430d2351dba8d75bfc48b7a6aae6187a"
    static let stAztec = "0x5d422936ce2636f8a890cd73ac01e7f1523d20ca"
    static let aztec = "0xa27ec0006e59f245217ff08cd52a7e8b169e62d2"

    /// The least a request may burn: SafetyModule's `withdrawalMinimum`.
    static let minimumShares: Decimal = 100 * pow(10, 18)
    /// One stAZTEC in base units, what `convertToAssets` is asked of.
    static let oneShare = "1000000000000000000"
    /// Thirty days of Ethereum's 12-second blocks: the rate's window.
    static let windowBlocks = 216_000
    static let windowDays = 30.0
    /// A deposit may mint no less than this share of the quote.
    static let keepBps: Decimal = 9_950

    /// One request filed and not yet claimed.
    struct Request: Equatable, Sendable, Codable {
        let id: String
        let ready: Bool
        let shares: String
        /// What it pays at most (base units), the rate locked when asked.
        let assets: String
    }

    // MARK: - The calls

    /// Stake `assets` (base units) of AZTEC: approve the vault exactly that,
    /// then `deposit` to the account, minting no fewer than `minShares`.
    static func deposit(_ assets: String, minShares: String, account: String) -> [AaveLend.Call]? {
        guard let a = AaveLend.word(assets), let m = AaveLend.word(minShares), AaveLend.isAddress(account),
              positive(assets) else { return nil }
        return [AaveLend.Call(to: aztec, data: "0x095ea7b3" + word(address: vault) + a, value: "0"),
                AaveLend.Call(to: vault, data: "0xbc157ac1" + a + word(address: account) + m, value: "0")]
    }

    /// Ask back `shares` (base units) of stAZTEC, the account owner and
    /// controller both: it is paid to the account when claimed.
    static func requestBack(_ shares: String, account: String) -> [AaveLend.Call]? {
        guard let s = AaveLend.word(shares), AaveLend.isAddress(account), positive(shares),
              (Decimal(string: shares) ?? 0) >= minimumShares else { return nil }
        let me = word(address: account)
        return [AaveLend.Call(to: vault, data: "0x7d41c86e" + s + me + me, value: "0")]
    }

    /// Claim every ready request, one call each, in one operation.
    static func claim(_ ids: [String]) -> [AaveLend.Call]? {
        let words = ids.compactMap(AaveLend.word)
        guard !ids.isEmpty, words.count == ids.count else { return nil }
        return words.map { AaveLend.Call(to: vault, data: "0x809f8360" + $0, value: "0") }
    }

    /// **NOTHING ELSE IS SIGNED.** The approval names the vault for no more
    /// than the deposit that follows it, the deposit mints to the account, a
    /// request names the account as owner and controller, a claim names only
    /// a request. No ETH rides any of it. Anything else, and the list is refused.
    static func checked(_ calls: [AaveLend.Call], account: String) -> Bool {
        guard !calls.isEmpty, AaveLend.isAddress(account) else { return false }
        let me = word(address: account), v = word(address: vault)
        var approved: String?
        for c in calls {
            let to = c.to.lowercased(), data = c.data.lowercased()
            guard c.value == "0" else { return false }
            let sel = String(data.prefix(10)), args = words(data)
            switch (to, sel) {
            case (aztec, "0x095ea7b3") where args.count == 2 && args[0] == v && approved == nil:
                approved = args[1]
            case (vault, "0xbc157ac1") where args.count == 3 && args[1] == me && approved.map({ $0 >= args[0] }) == true:
                approved = nil
            case (vault, "0x7d41c86e") where args.count == 3 && args[1] == me && args[2] == me:
                continue
            case (vault, "0x809f8360") where args.count == 1:
                continue
            default:
                return false
            }
        }
        // An approval no deposit spent is left standing: refused.
        return approved == nil
    }

    // MARK: - Reads

    static func balanceCall(account: String) -> String? {
        AaveLend.isAddress(account) ? "0x70a08231" + word(address: account) : nil
    }

    /// `convertToAssets(shares)` on the vault.
    static func assetsCall(shares: String) -> String? {
        AaveLend.word(shares).map { "0x07a2d13a" + $0 }
    }

    static func activeRequestsCall(account: String) -> String? {
        AaveLend.isAddress(account) ? "0xea7c316c" + word(address: account) : nil
    }

    static func requestCall(id: String) -> String? {
        AaveLend.word(id).map { "0xae485651" + $0 }
    }

    /// One uint256 answer as decimal digits.
    static func amount(_ answer: String) -> String? {
        guard let w = wordAt(answer, 0) else { return nil }
        return AaveLend.decimal(hex: w)
    }

    /// `activeRequestIds`' `uint256[]`: offset, length, then the ids.
    static func ids(_ answer: String) -> [String]? {
        guard let offset = wordAt(answer, 0).flatMap({ Int(AaveLend.decimal(hex: $0)) }), offset % 32 == 0,
              let count = wordAt(answer, offset / 32).flatMap({ Int(AaveLend.decimal(hex: $0)) }), count <= 64 else { return nil }
        var out: [String] = []
        for i in 0..<count {
            guard let w = wordAt(answer, offset / 32 + 1 + i) else { return nil }
            out.append(AaveLend.decimal(hex: w))
        }
        return out
    }

    /// `getWithdrawalRequest(id)`: (finalized, shares, assetsExpected, rate).
    static func request(id: String, _ answer: String) -> Request? {
        guard let f = wordAt(answer, 0), let s = wordAt(answer, 1), let a = wordAt(answer, 2) else { return nil }
        let finalized = AaveLend.decimal(hex: f)
        guard finalized == "0" || finalized == "1" else { return nil }
        return Request(id: id, ready: finalized == "1", shares: AaveLend.decimal(hex: s), assets: AaveLend.decimal(hex: a))
    }

    // MARK: - Arithmetic

    /// Shares for `assets` at `rate` (AZTEC per stAZTEC, base units of one
    /// share's worth), rounded down.
    static func shares(forAssets assets: String, rate: String) -> String? {
        guard let a = Decimal(string: assets), let r = Decimal(string: rate), a > 0, r > 0 else { return nil }
        return digits(a * pow(10, 18) / r)
    }

    /// What `shares` are worth in AZTEC at `rate`, rounded down.
    static func assets(forShares shares: String, rate: String) -> String? {
        guard let s = Decimal(string: shares), let r = Decimal(string: rate), r > 0 else { return nil }
        return digits(s * r / pow(10, 18))
    }

    /// The fewest shares a deposit of `assets` may mint: the quote less 0.5%.
    static func minShares(forAssets assets: String, rate: String) -> String? {
        guard let s = shares(forAssets: assets, rate: rate), let d = Decimal(string: s) else { return nil }
        return digits(d * keepBps / 10_000)
    }

    /// What the pool earned a year, compounded, from the share price now and
    /// `days` ago (0.31 for 31%). Nil when unreadable, falling, or past 1000%.
    static func apy(now: String, then: String, days: Double = windowDays) -> Double? {
        guard let n = Double(now), let t = Double(then), n > 0, t > 0, n >= t, days > 0 else { return nil }
        let a = pow(n / t, 365 / days) - 1
        return a.isFinite && a < 10 ? a : nil
    }

    // MARK: - Words

    private static func positive(_ amount: String) -> Bool {
        amount.range(of: #"^[1-9][0-9]{0,77}$"#, options: .regularExpression) != nil
    }

    private static func word(address: String) -> String {
        String(repeating: "0", count: 24) + address.dropFirst(2).lowercased()
    }

    private static func words(_ data: String) -> [String] {
        let body = Array(data.dropFirst(10))
        guard body.count % 64 == 0 else { return ["?"] }
        return stride(from: 0, to: body.count, by: 64).map { String(body[$0..<$0 + 64]) }
    }

    private static func wordAt(_ answer: String, _ i: Int) -> String? {
        guard answer.hasPrefix("0x"), i >= 0 else { return nil }
        let body = Array(answer.dropFirst(2))
        guard body.count >= (i + 1) * 64, body.allSatisfy(\.isHexDigit) else { return nil }
        return String(body[(i * 64)..<((i + 1) * 64)]).lowercased()
    }

    private static func digits(_ d: Decimal) -> String {
        var value = d, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
