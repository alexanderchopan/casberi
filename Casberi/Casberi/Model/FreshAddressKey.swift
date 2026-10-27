#if DEBUG
import Foundation
import Security
import P256K

/// **THE FRESH ADDRESSES' ROOT (prd §1560) — DEBUG builds only, Sepolia only.**
///
/// One 32-byte root made on this device, kept in the Keychain on this device
/// only (`…WhenUnlockedThisDeviceOnly`, never synchronizable), never shown and
/// never sent. Address `i`'s key is `FreshAddress.key(root:index:)` of it.
/// Not behind Face ID: what lands is moved by a deposit this key signs, and
/// that move already asks Face ID for the private account's seed.
///
/// Its keys sign through `PrivacyTestnetSender.send(_:key:…)`, so through
/// `TestnetTx`, which cannot make a transaction off a testnet.
enum FreshAddressKey {

    private static let service = "com.casberi.app.fresh-addresses"
    private static let account = "sepolia-fresh-root-v1"

    enum Failure: Error { case keychain(OSStatus), curve }

    /// The root, made the first time.
    private static func root() throws -> [UInt8] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 { return [UInt8](data) }
        guard status == errSecItemNotFound else { throw Failure.keychain(status) }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.curve }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(bytes),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
        return bytes
    }

    /// Address `index`'s signing key.
    static func key(_ index: UInt32) throws -> P256K.Recovery.PrivateKey {
        var root = try root()
        defer { for i in root.indices { root[i] = 0 } }
        guard let k = FreshAddress.key(root: root, index: index) else { throw Failure.curve }
        return try P256K.Recovery.PrivateKey(dataRepresentation: Data(k), format: .uncompressed)
    }

    /// Address `index`, checksummed.
    static func address(_ index: UInt32) throws -> String {
        let k = try key(index)
        guard let made = SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](k.publicKey.dataRepresentation)) else {
            throw Failure.curve
        }
        return made
    }

    /// `-freshAddressForget YES`: the root goes, and with it every address
    /// it made (only for a simulator's tests: money still at one is lost).
    static func forget() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}
#endif
