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
        var id: UInt32 { index }
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
    }

    /// The next address's index: one past the highest, so none is reused.
    static func nextIndex(_ entries: [Entry]) -> UInt32 {
        entries.map(\.index).max().map { $0 + 1 } ?? 0
    }

    /// The addresses asked about on each look: the newest few, but never one
    /// whose move is under way. Asked together, they meet at the node (through
    /// Tor, so not at an address of yours).
    static let watchCap = 8

    static func watched(_ entries: [Entry]) -> [Entry] {
        Array(entries.filter { if case .moving = $0.state { false } else { true } }
            .sorted { $0.index > $1.index }
            .prefix(watchCap))
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
