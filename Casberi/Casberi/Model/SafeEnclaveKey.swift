import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// THE SAFE OWNER THAT LIVES IN THE SECURE ENCLAVE (prd §913) — a P-256 key
/// born inside the chip, one per device, that can never leave it. The Safe
/// accepts it through Safe's own passkey signer contract
/// (`SafeWebAuthnSignature.swift`), so this is §425's co-signer with the one
/// promise `SignerKey` cannot make: the private half never exists in this
/// process, and there is nothing to export.
///
/// ## `FramesPasskey`'s body, its own service
///
/// The item is the shape `FramesPasskey` proved on the Frames devnet — the
/// Enclave-wrapped `dataRepresentation` in a generic password, `.privateKeyUsage`
/// (right here, where it governs a real Enclave key, and wrong in `SignerKey`,
/// where §426 dropped it) with `.biometryCurrentSet`, so **re-enrolling Face
/// ID destroys the key** (§427: a changed enrolled set is a changed authority
/// the chain cannot see), and `presence()` tells destroyed from absent
/// without a prompt. Never that file's item: two seats, two keys.
///
/// The public half is cached in UserDefaults where drawing it costs nothing;
/// the signer ADDRESS is not derived here — the proxy's creation code is the
/// compiler's, so `SafeEnclaveSigner` reads it back from the factory and
/// caches that.
///
/// **Nothing here reaches the network or knows what a Safe is.** The
/// `reason` on `sign` is the Face ID sheet's sentence.
enum SafeEnclaveKey {

    private static let service = "com.casberi.app.signer.enclave"
    private static let account = "safe-passkey-v1"
    private static let publicKeyDefaultsKey = "signer.enclave.publicKey"

    /// **False on every simulator.** No simulator run can make this key.
    static var enclaveAvailable: Bool { SecureEnclave.isAvailable }

    static func biometryAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    enum Presence: Equatable { case none, present, destroyed }

    /// Attributes only — no `kSecReturnData` — so no prompt.
    static func presence() -> Presence {
        guard publicKey() != nil else { return .none }
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
        return .present
    }

    static var exists: Bool { publicKey() != nil }

    /// The public half, `x ‖ y`, 64 bytes.
    static func publicKey() -> [UInt8]? {
        guard let hex = UserDefaults.standard.string(forKey: publicKeyDefaultsKey),
              let bytes = SafeABI.hexBytes(hex), bytes.count == 64 else { return nil }
        return bytes
    }

    static func publicKeyX() -> [UInt8]? { publicKey().map { Array($0[0..<32]) } }
    static func publicKeyY() -> [UInt8]? { publicKey().map { Array($0[32..<64]) } }

    /// Make the key and return its public half. An item left by a previous
    /// install is ADOPTED, not duplicated (§531's lesson): the cached public
    /// half is gone after a reinstall while the Keychain item is not.
    @discardableResult
    static func create() throws -> [UInt8] {
        guard enclaveAvailable else { throw Failure.noEnclave }
        guard biometryAvailable() else { throw Failure.noBiometry }
        guard presence() == .none else { throw Failure.alreadyExists }

        if let adopted = try adoptStoredKey() { return adopted }

        var acError: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet], &acError) else {
            throw Failure.keychainRefused(acError.map {
                OSStatus(CFErrorGetCode($0.takeRetainedValue() as CFError)) } ?? errSecParam)
        }
        let key: SecureEnclave.P256.Signing.PrivateKey
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control)
        } catch {
            throw Failure.enclaveRefused
        }
        let x963 = key.publicKey.x963Representation
        guard x963.count == 65, x963.first == 0x04 else { throw Failure.enclaveRefused }

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.dataRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }
        return cache(publicKey: [UInt8](x963.dropFirst()))
    }

    private static func adoptStoredKey() throws -> [UInt8]? {
        guard let key = try loadKey(context: nil) else { return nil }
        let x963 = key.publicKey.x963Representation
        guard x963.count == 65 else { return nil }
        return cache(publicKey: [UInt8](x963.dropFirst()))
    }

    private static func cache(publicKey xy: [UInt8]) -> [UInt8] {
        UserDefaults.standard.set(Keccak256.hexString(xy), forKey: publicKeyDefaultsKey)
        return xy
    }

    /// Sign 32 already-hashed bytes. Returns `r ‖ s` with `s` folded low.
    /// **A Face ID every time** — `reason` is the sheet's sentence.
    static func sign(digest: [UInt8], reason: String) throws -> (r: [UInt8], s: [UInt8]) {
        guard digest.count == 32 else { throw Failure.badDigest }
        let context = LAContext()
        context.localizedReason = reason
        // No passcode fallback, for `SignerKey`'s reason: anyone holding an
        // unlocked phone could otherwise sign.
        context.localizedFallbackTitle = ""
        guard let key = try loadKey(context: context) else { throw Failure.noKey }
        let signature: P256.Signing.ECDSASignature
        do {
            // The pre-hashed overload. `signature(for: Data)` would SHA-256
            // the digest again and sign something else — the trap
            // `VibenetDeviceKey` shipped once.
            signature = try key.signature(for: SafeEnclaveDigest(Data(digest)))
        } catch {
            throw Failure.signingRefused
        }
        let raw = [UInt8](signature.rawRepresentation)
        guard raw.count == 64 else { throw Failure.badDigest }
        return (Array(raw[0..<32]), SafeWebAuthn.lowS(Array(raw[32..<64])))
    }

    /// The one call that reconstitutes the Enclave key.
    private static func loadKey(context: LAContext?) throws -> SecureEnclave.P256.Signing.PrivateKey? {
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
        guard status == errSecSuccess, let blob = item as? Data else {
            if status == errSecItemNotFound { return nil }
            throw Failure.keychainRefused(status)
        }
        return try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob,
                                                          authenticationContext: context)
    }

    /// Deletes the key and forgets the public half. The caller owns the
    /// sentence: the Safe's other owners should `swapOwner` the proxy out
    /// first, or the Safe is one signature short.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: publicKeyDefaultsKey)
        SafeEnclaveSigner.forgetAddresses()
    }

    enum Failure: Error, Equatable {
        case noEnclave
        case noBiometry
        case alreadyExists
        case enclaveRefused
        case keychainRefused(OSStatus)
        case badDigest
        case noKey
        case signingRefused
    }
}

/// 32 already-hashed bytes as a CryptoKit `Digest`, so nothing hashes them again.
private struct SafeEnclaveDigest: Digest {
    private let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    static var byteCount: Int { 32 }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }
}

extension SafeEnclaveDigest: Sequence {
    func makeIterator() -> Array<UInt8>.Iterator { [UInt8](bytes).makeIterator() }
}
