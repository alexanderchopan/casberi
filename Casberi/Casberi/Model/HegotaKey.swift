import Foundation
import LocalAuthentication
import P256K
import Security

/// THE KEY THIS PHONE SIGNS HEGOTÁ WITH (prd §525, 2026-08-29) — secp256k1,
/// stored on this device, for a devnet whose money is worthless.
///
/// ## WHY THIS IS NOT THE VIBENET KEY, AND WHY IT IS A WEAKER PROMISE
///
/// `VibenetDeviceKey` is a P-256 key born inside the Secure Enclave: the
/// private half never exists in this process and there is no export path
/// because there is nothing to export. **This key cannot be that.** Hegotá has
/// only ever seen signature scheme `0x1` (secp256k1) — 324 of 324 — and the
/// Enclave speaks P-256, so an Enclave key cannot sign here at all. A P-256
/// scheme `0x2` is defined by the spec and has never been used on that chain,
/// so its wire encoding is unproven (§525).
///
/// So this key is a 32-byte scalar in the Keychain, exactly `SignerKey`'s
/// shape, which means **the bytes exist and could in principle be read**. That
/// is a real downgrade and it is a deliberate, stated ruling rather than an
/// oversight (user, 2026-08-29: *"its devnet so exportable key is fine"*). It
/// is defensible only because of what it can reach: a chain with a faucet,
/// where every token is worthless by construction. **Do not reuse this type,
/// this service, or this reasoning for a chain where value is real.**
///
/// ## WHY A SEPARATE KEY RATHER THAN SHARING THE SAFE SIGNER'S
///
/// `SignerKey` already holds a secp256k1 scalar and could sign here. It must
/// not: that key is one owner of a Safe holding real funds. Sharing would mean
/// one biometric re-enrollment kills both, a devnet bug reaches the item that
/// guards real money, and a signature intended for a test chain is produced by
/// the key that can move mainnet value. Different stakes, different key, its
/// own service name.
///
/// ## WHAT IS THE SAME, ON PURPOSE
///
/// The self-check. Every signature is verified by RECOVERING the public key
/// back out of it and requiring it to be this phone's — which proves in one
/// curve operation that the digest signed is the digest asked for, that the
/// recovery id is the right one of four, and that the cached address still
/// belongs to the stored scalar. `SignerKey` does this and its reasoning
/// carries over unchanged.
enum HegotaKey {

    /// Its OWN service. Never `SignerKey`'s — see the type doc.
    private static let service = "casberi-hegota-signer"
    private static let account = "device-secp256k1"
    private static let addressKey = "hegota.signer.address"

    // MARK: - Presence

    /// Three states, and collapsing any two is a wrong sentence on a screen
    /// about a key (`VibenetDeviceKey.Presence`'s ruling, same reasoning).
    enum Presence: Equatable { case none, present, destroyed }

    /// Attribute-only, so it decrypts nothing and raises no prompt.
    static func presence() -> Presence {
        guard address() != nil else { return .none }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess { return .present }
        if status == errSecItemNotFound { return .destroyed }
        // Never report destroyed on a maybe — that sentence sends somebody to
        // arrange a replacement they may not need.
        return .present
    }

    /// The address this key signs as, cached so a row can be drawn without
    /// decrypting the scalar.
    static func address() -> String? {
        UserDefaults.standard.string(forKey: addressKey)
    }

    static func biometryAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                             error: &error)
    }

    // MARK: - Making one

    @discardableResult
    static func create() throws -> String {
        guard presence() == .none else { throw Failure.alreadyExists }
        guard let key = try? P256K.Recovery.PrivateKey(format: .uncompressed),
              let addr = ethereumAddress(uncompressedPublicKey: [UInt8](key.publicKey.dataRepresentation))
        else { throw Failure.curve }

        var scalar = [UInt8](key.dataRepresentation)
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(scalar),
            // Device-only and non-synchronizable, named for
            // `scripts/keychain-audit.py`. Worthless money is still not a
            // reason to let a signing key ride a backup onto another device.
            //
            // **`WhenUnlockedThisDeviceOnly`, not `WhenPasscodeSetThisDeviceOnly`
            // — measured, not a downgrade for its own sake.** `SignerKey`
            // (this file's own shape: a software key with no `SecAccessControl`
            // object on its storage, biometry enforced only at SIGN time via
            // `kSecUseAuthenticationContext`) uses `WhenUnlockedThisDeviceOnly`
            // and it is the proven, shipped choice. `WhenPasscodeSet` failed
            // `-25308` (errSecInteractionNotAllowed) on a real signed Catalyst
            // run: that protection class needs an authenticated/interactive
            // session to ESTABLISH, which `VibenetDeviceKey` gets for free
            // because generating its Enclave key with `.biometryCurrentSet`
            // triggers a biometric prompt before the blob is ever written —
            // this key has no such step, so nothing here interacts with the
            // user before the write. Matching `SignerKey`'s constant is
            // matching its whole reasoning, not a smaller number for its own
            // sake.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        scalar.resetBytes(in: 0..<scalar.count)
        add[kSecValueData as String] = nil
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }

        UserDefaults.standard.set(addr, forKey: addressKey)
        return addr
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: addressKey)
    }

    // MARK: - Signing

    /// Signs 32 bytes and returns `v || r || s` — **the recovery byte FIRST**,
    /// and `v` as a bare 0/1 rather than 27/28.
    ///
    /// That ordering is not a style choice and not what most chains use: it was
    /// measured off this chain's own wire across 324 signatures (§525), and
    /// `r || s || v` recovers nothing there. It is the single easiest thing
    /// here to get wrong while looking right, which is why the layout is
    /// asserted in the harness rather than left to this comment.
    static func sign(hash: [UInt8], reason: String) throws -> [UInt8] {
        guard hash.count == 32 else { throw Failure.curve }
        guard let expected = address() else { throw Failure.missing }

        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecItemNotFound { throw Failure.missing }
            throw Failure.locked(status)
        }

        var scalar = [UInt8](data)
        defer { scalar.resetBytes(in: 0..<scalar.count) }
        guard let key = try? P256K.Recovery.PrivateKey(dataRepresentation: scalar,
                                                       format: .uncompressed)
        else { throw Failure.curve }

        // Nothing re-hashes here. The `signature(for data:)` overload would
        // SHA-256 the input and sign something else entirely — `SignerKey`'s
        // own recorded trap.
        let digest = HashDigest(hash)
        guard let signature = try? key.signature(for: digest),
              let compact = try? signature.compactRepresentation
        else { throw Failure.curve }

        // THE SELF-CHECK. Recover our own public key back out and require it to
        // be this phone: one curve operation proving the digest signed is the
        // digest asked for, that the recovery id is the right one of four, and
        // that the cached address still belongs to the stored scalar.
        guard let recovered = try? P256K.Recovery.PublicKey(digest, signature: signature,
                                                            format: .uncompressed),
              let recoveredAddress = ethereumAddress(uncompressedPublicKey: [UInt8](recovered.dataRepresentation)),
              recoveredAddress.lowercased() == expected.lowercased()
        else { throw Failure.selfCheck }

        return [UInt8(compact.recoveryId)] + [UInt8](compact.signature)
    }

    /// `keccak256(uncompressed public key without its 0x04 tag)`, last 20 bytes.
    static func ethereumAddress(uncompressedPublicKey key: [UInt8]) -> String? {
        guard key.count == 65, key.first == 0x04 else { return nil }
        let hash = Keccak256.hash(Array(key.dropFirst()))
        return "0x" + hash.suffix(20).map { String(format: "%02x", $0) }.joined()
    }

    enum Failure: Error, Equatable {
        case alreadyExists
        case missing
        case curve
        case selfCheck
        case locked(OSStatus)
        case keychainRefused(OSStatus)
    }
}
