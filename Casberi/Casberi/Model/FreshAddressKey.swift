#if DEBUG
import Foundation
import Security
import P256K

/// **THE FRESH ADDRESSES' KEYS (prd §1560, §1562) — DEBUG builds only, Sepolia only.**
///
/// Address `i`'s key is `FreshAddress.key(root:index:)` of a fresh root.
/// Since prd §1562 that root is derived from the private root in iCloud
/// Keychain (`PrivateRoot.derive(_:.freshAddresses)`), so a new phone walks
/// the same addresses back (`FreshReceive.restore`). Addresses made before
/// it come from the device-only root (`entry.root == nil`): made on this
/// device, kept in the Keychain on this device only (never synchronizable),
/// never shown, never sent, and no longer made anew — it is only read, for
/// the addresses it already made.
///
/// Not behind Face ID: what lands is moved INTO your private balance by a
/// deposit this key signs, which only you can spend.
///
/// Its keys sign through `PrivacyTestnetSender.send(_:key:…)`, so through
/// `TestnetTx`, which cannot make a transaction off a testnet.
enum FreshAddressKey {

    private static let service = "com.casberi.app.fresh-addresses"
    private static let account = "sepolia-fresh-root-v1"

    enum Failure: Error { case keychain(OSStatus), curve, noRoot }

    /// The device-only root, if this phone made one before prd §1562.
    private static func legacyRoot() throws -> [UInt8] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            throw status == errSecItemNotFound ? Failure.noRoot : Failure.keychain(status)
        }
        return [UInt8](data)
    }

    /// Address `index`'s signing key under `root`: the private root's
    /// through `FreshSigner` (shipping, prd §1567), else the device-only root's.
    static func key(_ index: UInt32, root: String?) throws -> P256K.Recovery.PrivateKey {
        if let root { return try FreshSigner.key(index, root: root) }
        var fresh = try legacyRoot()
        defer { for i in fresh.indices { fresh[i] = 0 } }
        guard let k = FreshAddress.key(root: fresh, index: index) else { throw Failure.curve }
        return try P256K.Recovery.PrivateKey(dataRepresentation: Data(k), format: .uncompressed)
    }

    /// Address `index` under `root`, checksummed.
    static func address(_ index: UInt32, root: String?) throws -> String {
        if let root { return try FreshSigner.address(index, root: root) }
        let k = try key(index, root: root)
        guard let made = SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](k.publicKey.dataRepresentation)) else {
            throw Failure.curve
        }
        return made
    }

    /// `-freshAddressForget YES`: the device-only root goes, and with it every
    /// address it made (only for a simulator's tests: money still at one is
    /// lost). The private root is never touched here.
    static func forget() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}
#endif
