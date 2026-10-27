import CryptoKit
import Foundation

/// **RECEIVE TO A FRESH ADDRESS: THE PURE HALF (prd §1560).**
///
/// Receive, with the Private switch on, shows an address never used before.
/// Anyone pays it from any wallet; what lands is moved into your private
/// balance by a deposit SENT FROM THAT ADDRESS, so your public account never
/// touches the money.
///
/// - **The keys.** One 32-byte root made on the phone (`FreshAddressKey`,
///   device-only Keychain). Address `i` is the secp256k1 key
///   `HMAC-SHA256(root, "casberi fresh address v1" ‖ i ‖ counter)`, the first
///   counter whose MAC is a valid scalar (0 < k < n). One `i` per tap of
///   New address, never reused.
/// - **The gas (option a of §1541 item 3's three).** A fresh address holds
///   only what it was paid, so the deposit pays its own gas out of it:
///   `value = (balance − gasBudget × maxFee) × 10000 / (10000 + vettingBPS)`,
///   rounded down, which is what the SDK's `msg.value = value + value ×
///   bps / 10000` fits under. A paymaster needs a keyed provider and a smart
///   account; 0xBow relays no deposit. ETH only: a token needs ETH for gas.
/// - **Worth moving.** Nothing moves when the gas could cost more than what
///   moves (`value < reserve`), or below the pool's minimum: the line says
///   it arrived, too little to move.
/// - **Whose note.** The deposit is an ordinary deposit for YOUR private
///   account (`prepareDeposit`, its owner the keystore your account
///   registered), not `depositFor`; only the sender differs. The pool does
///   not ask who sends (measured: 934,403 gas from the owner and from a
///   stranger alike), and the fresh address needs no keystore of its own.
///
/// Pure (Foundation + CryptoKit): `private-money-selftest.sh` drives it.
enum FreshAddress {

    // MARK: - The keys

    /// secp256k1's group order n, big-endian.
    static let curveOrder: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
        0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B, 0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41,
    ]

    static let domain = Array("casberi fresh address v1".utf8)

    /// Address `index`'s private key, or nil for a root that is not 32 bytes.
    static func key(root: [UInt8], index: UInt32) -> [UInt8]? {
        guard root.count == 32 else { return nil }
        let mac = SymmetricKey(data: root)
        for counter in UInt32(0)..<64 {
            let message = domain + bigEndian(index) + bigEndian(counter)
            let k = [UInt8](HMAC<SHA256>.authenticationCode(for: message, using: mac))
            if isScalar(k) { return k }
        }
        return nil
    }

    /// A secp256k1 private key: 32 bytes, 0 < k < n.
    static func isScalar(_ k: [UInt8]) -> Bool {
        k.count == 32 && k.contains(where: { $0 != 0 }) && k.lexicographicallyPrecedes(curveOrder)
    }

    private static func bigEndian(_ n: UInt32) -> [UInt8] {
        [UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)]
    }

    // MARK: - The book

    /// One fresh address and what became of what it was paid.
    struct Entry: Codable, Equatable, Identifiable {
        let index: UInt32
        let address: String
        let made: Date
        var state: State
        /// The private root it comes from (`PrivateRoot.id`, prd §1562); nil
        /// for the device-only root an address made before it came from.
        var root: String? = nil
        /// The network it was shown for (prd §1567); nil for Sepolia, where
        /// every address made before was.
        var chainId: Int? = nil
        /// What its state counts, by symbol (prd §1567: USDC arrives too);
        /// nil for ETH.
        var symbol: String? = nil
        var id: String { "\(root ?? PrivateRoot.legacy):\(index)" }
        var network: Int { chainId ?? 11_155_111 }
        var token: String { symbol ?? "ETH" }
        /// A transaction for it is out and not yet seen.
        var isSent: Bool { if case .sent = state { true } else { false } }
    }

    enum State: Codable, Equatable {
        /// Nothing has arrived.
        case waiting
        /// Arrived (`amount`, base units), the deposit under way.
        case moving(amount: String)
        /// Deposited `amount` by `tx`: a note of yours, waiting for approval.
        case moved(amount: String, tx: String)
        /// Arrived, but the gas would cost more than what would move.
        case tooLittle(amount: String)
        /// The move failed; the next look tries again.
        case failed(amount: String)
        /// A token arrived and the address holds no ETH to move it; your
        /// private ETH is too little to pay its gas (prd §1567).
        case needsGas(amount: String)
        /// **SENT AND NOT YET SEEN (the review of 2026-10-26, findings 2
        /// and 6).** A transaction for this address is out: its own approval
        /// or deposit (`nonce` its nonce, kept BEFORE it was broadcast), or
        /// the relayed private withdrawal paying its gas (`tx` empty until
        /// the relayer answered). Each look asks the chain about it
        /// (`sentVerdict`) and nothing new is sent or paid for the address
        /// while it may still land: never marked failed because a wait ran out.
        case sent(amount: String, tx: String, step: SentStep, nonce: String?, at: Date)
    }

    enum SentStep: String, Codable, Equatable { case gas, approve, deposit }

    /// **ETH AND USDC APART (the review of 2026-10-26, finding 4).** What a
    /// look at an Ethereum fresh address asks about: each token it holds,
    /// ETH first — so USDC under the pool's smallest deposit never hides the
    /// ETH beside it, as it did when any USDC at all went the token's way.
    enum LookOrder: Equatable { case nothing, eth, usdc, both }

    static func lookOrder(eth: String, usdc: String, usdcPool: Bool) -> LookOrder {
        let hasETH = (Decimal(string: eth) ?? 0) > 0
        let hasUSDC = usdcPool && (Decimal(string: usdc) ?? 0) > 0
        switch (hasETH, hasUSDC) {
        case (true, true): return .both
        case (true, false): return .eth
        case (false, true): return .usdc
        case (false, false): return .nothing
        }
    }

    /// What the chain says of a sent transaction now.
    enum SentVerdict: Equatable { case landed, reverted, waiting, dropped }

    /// How long a transaction nobody's node knows may stay unknown before
    /// it is taken as dropped (its nonce still free: sending again is safe);
    /// a relayed withdrawal is the relayer's to post, so it gets a day.
    static let droppedAfter: TimeInterval = 60 * 60
    static let relayDroppedAfter: TimeInterval = 24 * 60 * 60

    /// Landed or reverted by its receipt; still on its way while the node
    /// knows it or its nonce was taken (mined, the receipt not served yet);
    /// dropped only when the node has not known it for `after` and the
    /// nonce is still free. Unknown answers are never a verdict.
    static func sentVerdict(receipt: String?, known: Bool?, nonceTaken: Bool?, age: TimeInterval, after: TimeInterval) -> SentVerdict {
        if let receipt { return receipt == "0x1" ? .landed : .reverted }
        if nonceTaken == true || known != false { return .waiting }
        return age > after ? .dropped : .waiting
    }

    /// The next address's index under `root`: one past its highest, so none
    /// is reused. Each root counts its own.
    static func nextIndex(_ entries: [Entry], root: String? = nil) -> UInt32 {
        entries.filter { $0.root == root }.map(\.index).max().map { $0 + 1 } ?? 0
    }

    /// The addresses asked about on each look: the newest few, but never one
    /// whose move is under way. Asked together, they meet at the node (through
    /// Tor, so not at an address of yours).
    static let watchCap = 8

    static func watched(_ entries: [Entry]) -> [Entry] {
        let open = entries.filter { if case .moving = $0.state { false } else { true } }
            .sorted { ($0.made, $0.index) > ($1.made, $1.index) }
        let newest = Array(open.prefix(watchCap))
        // One with a transaction out is looked at however old (finding 2):
        // otherwise newer addresses would hide it and it would never resolve.
        return newest + open.dropFirst(watchCap).filter(\.isSent)
    }

    /// What a look at an address's balance does: move it, say it was too
    /// little, or nothing. Dust left by a move never moves again, and a
    /// moved address says what it moved until it is paid enough again.
    enum Decision: Equatable { case move(Plan), tooLittle, nothing }

    static func decide(_ entry: Entry, balance: String, plan: Plan?) -> Decision {
        if let plan { return .move(plan) }
        guard let held = Decimal(string: balance), held > 0 else { return .nothing }
        switch entry.state {
        case .waiting: return .tooLittle
        default: return .nothing
        }
    }

    // MARK: - The deposit's gas, out of what arrived

    /// The deposit's gas limit: measured at 934,403 (`eth_estimateGas` on
    /// Sepolia, from the owner and from a stranger) and ×1.25 = 1,168,004,
    /// rounded up. The estimate is checked against it before signing.
    static let gasBudget = 1_250_000

    struct Plan: Equatable {
        /// What the note holds, base units.
        let value: String
        /// What the transaction carries: `value` plus 0xBow's vetting fee.
        let msgValue: String
        /// The most the gas can cost (`gasBudget × maxFee`).
        let reserve: String
    }

    /// The deposit that empties `balance` (base units) less its own gas at
    /// `maxFee` (wei a gas), or nil when that is not worth moving.
    static func plan(balance: String, maxFee: String, vettingBPS: Int, minimum: String) -> Plan? {
        guard let have = Decimal(string: balance), let fee = Decimal(string: maxFee),
              let floor = Decimal(string: minimum), (0...10_000).contains(vettingBPS) else { return nil }
        let reserve = Decimal(gasBudget) * fee
        let spare = have - reserve
        guard spare > 0 else { return nil }
        let value = Decimal(string: PrivateMoney.plain(spare * 10_000 / Decimal(10_000 + vettingBPS))) ?? 0
        let vetting = Decimal(string: PrivateMoney.plain(value * Decimal(vettingBPS) / 10_000)) ?? 0
        let carried = value + vetting
        guard value >= max(floor, reserve, 1), carried + reserve <= have else { return nil }
        return Plan(value: PrivateMoney.plain(value), msgValue: PrivateMoney.plain(carried),
                    reserve: PrivateMoney.plain(reserve))
    }

    /// The prepared deposit is the one planned: to the Entrypoint, carrying
    /// exactly the planned value. Checked before the fresh key signs.
    static func matches(to: String, value: String, plan: Plan, entrypoint: String) -> Bool {
        to.lowercased() == entrypoint.lowercased() && PrivateMoney.decimal(hex: value) == plan.msgValue
    }

    // MARK: - On Ethereum: into the yield pool, its gas out of what arrived (prd §1567)

    /// The smallest budget the pool takes, in the token: its minimum (in
    /// shares, `Entrypoint.assets`) at today's rate, rounded up, plus the
    /// router's own headroom (1 ppm of the budget) and its supply buffer.
    static func minimumBudget(minimumShares: String, exchangeRate: String, shareDecimals: Int) -> String? {
        guard let shares = Decimal(string: minimumShares), let rate = Decimal(string: exchangeRate), shares >= 0, rate > 0,
              (0...36).contains(shareDecimals) else { return nil }
        var scale = Decimal(1)
        for _ in 0..<shareDecimals { scale *= 10 }
        var worth = shares * rate / scale, up = Decimal()
        NSDecimalRound(&up, &worth, 0, .up)
        var headroom = up / 1_000_000, roomUp = Decimal()
        NSDecimalRound(&roomUp, &headroom, 0, .up)
        return PrivateMoney.plain(up + roomUp + 10)
    }

    /// An ETH deposit through ppETH's router, sent by the fresh address: the
    /// most it may spend (what arrived less the most its gas can cost at
    /// `maxFee`), the router refunding what it does not use. Nil — "too
    /// little to move" — under the pool's smallest deposit, or when the gas
    /// could cost more than what moves.
    struct YieldPlan: Equatable {
        let budget: String
        let reserve: String
    }

    static func yieldPlan(balance: String, maxFee: String, minimumBudget: String, gas: Int = gasBudget) -> YieldPlan? {
        guard let have = Decimal(string: balance), let fee = Decimal(string: maxFee), let floor = Decimal(string: minimumBudget),
              gas > 0 else { return nil }
        let reserve = Decimal(gas) * fee
        let budget = have - reserve
        guard budget >= max(floor, reserve, 1) else { return nil }
        return YieldPlan(budget: PrivateMoney.plain(budget), reserve: PrivateMoney.plain(reserve))
    }

    /// Below this, what arrived is too little to move: the pool's smallest
    /// deposit plus the gas kept back — computed from the pool's terms and
    /// today's fees, never a constant (≈ 0.0041 ETH on 2026-10-26 at 0.05
    /// gwei: 0.004 shares at 1.00125, plus 1.25M gas at twice the price).
    static func tooLittleBelow(minimumBudget: String, maxFee: String, gas: Int = gasBudget) -> String? {
        guard let floor = Decimal(string: minimumBudget), let fee = Decimal(string: maxFee) else { return nil }
        let reserve = Decimal(gas) * fee
        return PrivateMoney.plain(max(floor, reserve) + reserve)
    }

    /// The prepared yield deposit is the one planned: to the token's own
    /// router, no approvals for ETH, carrying no more than the budget.
    static func matchesYield(to: String, value: String, approvals: Int, budget: String, pool: PrivacyNetwork.YieldPool) -> Bool {
        guard to.lowercased() == pool.router.lowercased(), let most = Decimal(string: budget),
              let carried = Decimal(string: PrivateMoney.decimal(hex: value)) else { return false }
        return pool.native ? (approvals == 0 && carried <= most && carried > 0) : carried == 0
    }

    /// **A TOKEN AT A FRESH ADDRESS (prd §1567): its gas.** A fresh address
    /// paid USDC holds no ETH to move it. Its approval and deposit cost at
    /// most `need` at `maxFee`; what it already holds counts. The shortfall
    /// is what your private ETH pays it, relayed (no link to your account).
    static func tokenGas(ethHeld: String, maxFee: String) -> (need: String, shortfall: String)? {
        guard let held = Decimal(string: ethHeld), let fee = Decimal(string: maxFee) else { return nil }
        let need = Decimal(FreshTx.approveGas + gasBudget) * fee
        return (PrivateMoney.plain(need), PrivateMoney.plain(max(need - held, 0)))
    }

    // MARK: - The pool's terms for a token (`Entrypoint.assets`)

    /// `assets(address)`'s selector.
    static let assetsSelector = "f11b8188"

    static func assetsCall(token: String) -> String? {
        guard PrivateMoney.isAddress(token) else { return nil }
        return "0x" + assetsSelector + String(repeating: "0", count: 24) + token.dropFirst(2).lowercased()
    }

    struct AssetConfig: Equatable {
        let enabled: Bool
        let minimum: String
        let vettingBPS: Int
    }

    /// `(bool enabled, uint256 minAmount, uint256 vettingFeeBPS, uint256
    /// maxRelayFee)`, four words; nil for anything shorter or a fee past 100%.
    static func assetConfig(_ result: String) -> AssetConfig? {
        guard result.hasPrefix("0x") else { return nil }
        let body = Array(result.dropFirst(2))
        guard body.count >= 256, body.allSatisfy(\.isHexDigit) else { return nil }
        func word(_ i: Int) -> String { PrivateMoney.decimal(hex: "0x" + String(body[(i * 64)..<((i + 1) * 64)])) }
        guard let bps = Int(word(2)), bps <= 10_000 else { return nil }
        return AssetConfig(enabled: word(0) != "0", minimum: word(1), vettingBPS: bps)
    }
}
