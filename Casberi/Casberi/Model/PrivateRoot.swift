import CryptoKit
import Foundation

/// **ONE ROOT FOR PRIVATE MONEY, AND HOW A NEW PHONE GETS IT BACK (prd §1562).**
///
/// Private money had two secrets, both device-only: the seed of your private
/// account (`PrivacyPoolsKey`) and the root of the fresh addresses
/// (`FreshAddressKey`). Losing the phone lost the private balance and
/// whatever still sat at a fresh address. Now both come from ONE 32-byte
/// root kept in iCloud Keychain (`PrivateRootKey`), each by its own HKDF:
///
///     seed   = HKDF-SHA256(root, salt "casberi private money root v1", info "privacy pools seed")
///     fresh  = HKDF-SHA256(root, salt …,                              info "fresh addresses")
///     owner  = HKDF-SHA256(root, salt …,  info "testnet owner" ‖ counter), the first valid secp256k1 scalar
///
/// The seed enters 0xBow's own HKDF tree exactly where the device-only seed
/// did; the fresh root enters `FreshAddress.key` exactly where the
/// device-only root did; the owner (DEBUG, Sepolia: the stand-in for your
/// account, §1554 item 4) owns the account's keystore entry. So a phone that
/// holds the root rebuilds all three, and with them the notes (found again
/// from the pool's own events, `PrivacyEngine.discover`) and the fresh
/// addresses (walked to the gap, below).
///
/// Pure (Foundation + CryptoKit): `private-money-selftest.sh` pins every
/// derivation against Node's `crypto.hkdfSync`.
enum PrivateRoot {

    static let salt = Array("casberi private money root v1".utf8)

    enum Purpose: String, CaseIterable {
        case poolSeed = "privacy pools seed"
        case freshAddresses = "fresh addresses"
        case testnetOwner = "testnet owner"
    }

    /// The 32 bytes `purpose` takes from `root`; nil for a root that is not 32 bytes.
    static func derive(_ root: [UInt8], _ purpose: Purpose, counter: UInt32? = nil) -> [UInt8]? {
        guard root.count == 32 else { return nil }
        var info = Array(purpose.rawValue.utf8)
        if let counter { info += [UInt8(counter >> 24), UInt8((counter >> 16) & 0xff), UInt8((counter >> 8) & 0xff), UInt8(counter & 0xff)] }
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: root), salt: salt, info: info, outputByteCount: 32)
        return key.withUnsafeBytes { [UInt8]($0) }
    }

    /// The owner's secp256k1 key: the first counter whose output is a scalar.
    static func ownerKey(_ root: [UInt8]) -> [UInt8]? {
        for counter in UInt32(0)..<64 {
            if let k = derive(root, .testnetOwner, counter: counter), FreshAddress.isScalar(k) { return k }
        }
        return nil
    }

    /// The root's public name: never the root, never anything derived for a
    /// use. Sixteen hex digits of `SHA-256("casberi private root id v1" ‖ root)`.
    static func id(_ root: [UInt8]) -> String? {
        guard root.count == 32 else { return nil }
        let digest = SHA256.hash(data: Array("casberi private root id v1".utf8) + root)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Notes and fresh addresses made before the root (prd §1554, §1560)
    /// belong to the device-only account: `nil` in a note's or an entry's
    /// `root`, "legacy" where an id must be a word.
    static let legacy = "legacy"

    // MARK: - Walking the fresh addresses back (the gap limit)

    /// What a new phone asks of fresh address `index` on the network.
    struct Seen: Equatable {
        let index: UInt32
        /// Base units, decimal.
        let balance: String
        /// Transactions sent FROM it: a move leaves one.
        let nonce: Int
        var used: Bool { nonce > 0 || (Decimal(string: balance) ?? 0) > 0 }
    }

    /// Twenty unused in a row ends the walk, as BIP44's does (§1097's).
    static let gap: UInt32 = 20

    /// The indices to ask next, or nil when the walk is done: `gap` past the
    /// last used index, in one batch.
    static func nextBatch(_ seen: [Seen]) -> ClosedRange<UInt32>? {
        let asked = seen.map(\.index).max().map { $0 + 1 } ?? 0
        let lastUsed = seen.filter(\.used).map(\.index).max()
        let end = lastUsed.map { $0 + gap } ?? (gap - 1)
        return asked <= end ? asked...end : nil
    }

    /// The book a walk rebuilds: every address up to the last used one, each
    /// in the state its balance and nonce say (paid and never moved:
    /// waiting, so the watch moves it; moved before: moved, so its dust
    /// never says "too little"), then one more never used, the address
    /// Receive shows. Nothing used: address 0 alone.
    static func restored(_ seen: [Seen]) -> [(index: UInt32, state: FreshAddress.State)] {
        let byIndex = Dictionary(seen.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        guard let last = seen.filter(\.used).map(\.index).max() else { return [(0, .waiting)] }
        var out: [(index: UInt32, state: FreshAddress.State)] = (0...last).map { i in
            guard let s = byIndex[i], s.nonce > 0 else { return (i, .waiting) }
            return (i, .moved(amount: "0", tx: ""))
        }
        out.append((last + 1, .waiting))
        return out
    }

    // MARK: - Moving the device-only account's money in

    /// What a withdrawal from the device-only account moves into the root's:
    /// the approved balance less the relayer's fee on all of it, or nil when
    /// that is not worth a withdrawal (the fee would take more than half).
    static func migrationAmount(spendable: String, terms: PrivateMoney.RelayerTerms) -> String? {
        guard let held = Decimal(string: spendable), held > 0,
              let fee = Decimal(string: PrivateMoney.relayFee(spendable, terms: terms)) else { return nil }
        let amount = held - fee
        guard amount > fee else { return nil }
        return PrivateMoney.plain(amount)
    }

    // MARK: - What needs your attention (Move › Security)

    enum Backup: Equatable {
        /// Nothing private on this phone, or all of it under a root in
        /// iCloud Keychain on an iCloud account.
        case fine
        /// Private money under the device-only account: Move it in.
        case deviceOnly
        /// A root, but no iCloud account to carry it: it is on this phone only.
        case noICloud
    }

    static func backup(holdsPrivate: Bool, deviceOnlyHolds: Bool, iCloud: Bool) -> Backup {
        guard holdsPrivate else { return .fine }
        if deviceOnlyHolds { return .deviceOnly }
        return iCloud ? .fine : .noICloud
    }
}
