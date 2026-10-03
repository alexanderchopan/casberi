import Foundation
import LocalAuthentication
import P256K
import Security

/// THE KEY THIS PHONE SIGNS ON THE LOGOS TESTNET WITH (prd §1084,
/// 2026-10-03; user: "Frames send is fine b/c its testnet") — a secp256k1
/// scalar in the Keychain, signing BIP-340 Schnorr, for a chain whose coins
/// are worthless and which is reset from genesis when it upgrades.
///
/// ## ITS OWN KEY, ITS OWN SERVICE
///
/// `FramesKey` holds a scalar of the same curve. It must not sign here: two
/// chains, two nonce spaces, and a "remove this key" on one seat must never
/// empty the other. `logos-selftest.sh` fails the build if this file names
/// another seat's service.
///
/// ## THE SAME WEAKER PROMISE FRAMES MADE, FOR THE SAME REASON
///
/// LEZ signs Schnorr over secp256k1 (measured: every signature on the chain
/// verifies under BIP-340), and the Secure Enclave speaks only P-256, so the
/// scalar is bytes in the Keychain — device-only, never synchronized, read
/// only to sign. Defensible only because the chain's coins are test coins
/// (§525's ruling, carried by §548). **Do not reuse this for real value.**
///
/// ## WHAT IS THE SAME, ON PURPOSE
///
/// `FramesKey`'s proven rules, transplanted: a reinstall ADOPTS the item it
/// finds rather than dead-ending on a duplicate; an unreadable keychain is
/// never read as an empty one (nothing is deleted on a maybe); a delete
/// matches every synchronizability; and every signature is VERIFIED against
/// this phone's own key before it leaves.
///
/// **One account per phone.** Frames grew a second account in §774 because
/// people asked; nobody has asked here, and one key is the smallest thing
/// that sends.
enum LogosKey {

    /// Its OWN service. Never `FramesKey`'s or `SignerKey`'s.
    private static let service = "casberi-logos-signer"
    private static let account = "device-secp256k1-schnorr"
    /// The account id this key signs as, cached so a menu can be drawn
    /// without decrypting the scalar.
    private static let idKey = "logos.signer.account"

    /// The LEZ account id this phone holds the key for, or nil. A defaults
    /// read, never a Keychain one — a body may ask it.
    static func accountID() -> String? { UserDefaults.standard.string(forKey: idKey) }

    static func holds(_ id: String?) -> Bool { id != nil && id == accountID() }

    enum Failure: Error, Equatable {
        case alreadyExists
        case missing
        case curve
        case selfCheck
        case locked(OSStatus)
        case keychainRefused(OSStatus)
    }

    // MARK: - Making one

    /// Make this phone's account, or adopt the one a reinstall left behind.
    /// Returns its LEZ account id.
    @discardableResult
    static func create() throws -> String {
        if accountID() != nil, itemExists() { throw Failure.alreadyExists }
        UserDefaults.standard.removeObject(forKey: idKey)

        var fresh = try freshScalar()
        defer { fresh.resetBytes(in: 0..<fresh.count) }
        let id = try id(of: fresh)
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(fresh),
            // Device-only and non-synchronizable (`keychain-audit.py`), the
            // constant `FramesKey` measured and shipped: a software key with
            // biometry asked at SIGN time, never on the write.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        add[kSecValueData as String] = nil
        switch status {
        case errSecSuccess:
            UserDefaults.standard.set(id, forKey: idKey)
            return id
        case errSecDuplicateItem:
            // A reinstall wipes defaults and keeps the Keychain: the item IS
            // this phone's account, and may hold coins. Adopt it.
            return try adopt()
        default:
            throw Failure.keychainRefused(status)
        }
    }

    /// The account id of the key already stored, remembered again.
    private static func adopt() throws -> String {
        var scalar = try readScalar(context: nil)
        defer { scalar.resetBytes(in: 0..<scalar.count) }
        let id = try id(of: scalar)
        UserDefaults.standard.set(id, forKey: idKey)
        return id
    }

    /// Attribute-only: decrypts nothing and raises no prompt.
    private static func itemExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // Only "not found" is absence; anything else is a keychain we could
        // not read, which is never reported as an empty one.
        return status != errSecItemNotFound
    }

    /// Remove this phone's account key and forget it. The coins on it stay
    /// on the chain, where nobody can move them again.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: idKey)
    }

    // MARK: - Signing

    /// Signs a message hash: a 64-byte BIP-340 signature and the 32-byte
    /// x-only key, the witness LEZ takes. Face ID (or the passcode) is asked
    /// for at the read, with `reason`.
    ///
    /// **Verified before it leaves**: the signature is checked against the
    /// key it came from, and that key must still derive the account this
    /// phone remembers — one curve operation proving the hash signed is the
    /// hash asked for, and that the stored scalar still belongs to the
    /// account the sheet named.
    static func sign(hash: [UInt8], reason: String) throws -> (signature: [UInt8], publicKey: [UInt8]) {
        guard hash.count == 32 else { throw Failure.curve }
        guard let expected = accountID() else { throw Failure.missing }
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""
        var scalar = try readScalar(context: context)
        defer { scalar.resetBytes(in: 0..<scalar.count) }
        guard let key = try? P256K.Schnorr.PrivateKey(dataRepresentation: scalar) else { throw Failure.curve }

        // Nothing re-hashes: the `for data:` overload would SHA-256 the
        // input and sign something else (`SignerKey`'s recorded trap).
        var aux = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, aux.count, &aux) == errSecSuccess,
              let signature = try? key.signature(for: HashDigest(hash), auxiliaryRand: aux)
        else { throw Failure.curve }

        let publicKey = key.xonly.bytes
        guard key.xonly.isValidSignature(signature, for: HashDigest(hash)),
              LogosWire.accountID(publicKey: publicKey) == expected
        else { throw Failure.selfCheck }
        return ([UInt8](signature.dataRepresentation), publicKey)
    }

    // MARK: - Private

    private static func freshScalar() throws -> [UInt8] {
        guard let key = try? P256K.Schnorr.PrivateKey() else { throw Failure.curve }
        return [UInt8](key.dataRepresentation)
    }

    private static func id(of scalar: [UInt8]) throws -> String {
        guard let key = try? P256K.Schnorr.PrivateKey(dataRepresentation: scalar) else { throw Failure.curve }
        return LogosWire.accountID(publicKey: key.xonly.bytes)
    }

    private static func readScalar(context: LAContext?) throws -> [UInt8] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecItemNotFound { throw Failure.missing }
            throw Failure.locked(status)
        }
        return [UInt8](data)
    }
}
