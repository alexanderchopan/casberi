import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// THE KEY THIS PHONE SIGNS AZTEC TESTNET TRANSACTIONS WITH (2026-10-11) — a
/// P-256 key born in the Secure Enclave, the curve Aztec's own `EcdsaRAccount`
/// verifies (measured: a Secure Enclave key signed four mined testnet
/// transactions). `SafeEnclaveKey`'s body, its own service: two seats, two
/// keys, and removing one never empties the other.
///
/// **Testnet only.** This key is the only key its account accepts, so on a
/// real network it would move money — which this app does not do. Every
/// request reaches it through `AztecSignRequest.check`, which refuses any
/// chain but an Aztec testnet before Face ID is offered.
///
/// **No recovery.** The stock account cannot change its key (`SinglePrivate
/// Immutable`), and re-enrolling Face ID destroys this one
/// (`.biometryCurrentSet`). On a testnet that strands test money; the page
/// says so.
enum AztecSignerKey {

    private static let service = "com.casberi.app.aztec.signer"
    private static let account = "aztec-p256-v1"
    private static let publicKeyDefaultsKey = "aztec.signer.publicKey"

    /// **False on every simulator.**
    static var enclaveAvailable: Bool { SecureEnclave.isAvailable }

    enum Presence: Equatable { case none, present, destroyed }

    /// Attributes only — no prompt.
    static func presence() -> Presence {
        guard publicKey() != nil else { return .none }
        #if DEBUG && targetEnvironment(simulator)
        return UserDefaults.standard.data(forKey: standInKey) == nil ? .destroyed : .present
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .destroyed }
        return .present
    }

    /// The public half, `x ‖ y`, hex — what the computer's tool builds the
    /// account from. A defaults read, safe in a body.
    static func publicKeyHex() -> String? {
        UserDefaults.standard.string(forKey: publicKeyDefaultsKey)
    }

    static func publicKey() -> [UInt8]? {
        guard let hex = publicKeyHex(), hex.count == 128 else { return nil }
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }

    enum Failure: Error, Equatable {
        case noEnclave, noBiometry, alreadyExists, enclaveRefused
        case keychainRefused(OSStatus), badDigest, noKey, signingRefused
    }

    /// Make the key (or adopt the one a reinstall left) and return its
    /// public half.
    @discardableResult
    static func create() throws -> [UInt8] {
        #if DEBUG && targetEnvironment(simulator)
        // The simulator has no Secure Enclave: a software stand-in, in DEBUG
        // simulator builds only (compiled out of every shipped binary), so
        // the request → sheet → signature → mined path can be driven here.
        let standIn = P256.Signing.PrivateKey()
        UserDefaults.standard.set(standIn.rawRepresentation, forKey: Self.standInKey)
        return cache(standIn.publicKey)
        #else
        guard enclaveAvailable else { throw Failure.noEnclave }
        var laError: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &laError) else {
            throw Failure.noBiometry
        }
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
        do { key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control) } catch {
            throw Failure.enclaveRefused
        }
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
        return cache(key.publicKey)
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static let standInKey = "aztec.signer.simulatorStandIn"
    #endif

    private static func adoptStoredKey() throws -> [UInt8]? {
        guard let key = try loadKey(context: nil) else { return nil }
        return cache(key.publicKey)
    }

    private static func cache(_ publicKey: P256.Signing.PublicKey) -> [UInt8] {
        let xy = [UInt8](publicKey.rawRepresentation)
        UserDefaults.standard.set(xy.map { String(format: "%02x", $0) }.joined(), forKey: publicKeyDefaultsKey)
        return xy
    }

    /// Signs a CHECKED request (`AztecSignRequest.check` said `.sign`): P-256
    /// over `sha256(messageHash)`, `s` folded low (Barretenberg refuses a
    /// high-S signature in-circuit, measured). Face ID every time, no passcode
    /// fallback. Verified against this key before it leaves.
    static func sign(messageHash: String, reason: String) throws -> (r: [UInt8], s: [UInt8]) {
        guard let digest = AztecSignRequest.digest(messageHash) else { throw Failure.badDigest }
        #if DEBUG && targetEnvironment(simulator)
        guard let raw = UserDefaults.standard.data(forKey: standInKey),
              let standIn = try? P256.Signing.PrivateKey(rawRepresentation: raw),
              let made = try? standIn.signature(for: AztecDigest(Data(digest))) else { throw Failure.noKey }
        let bytes = [UInt8](made.rawRepresentation)
        return (Array(bytes[0..<32]), SafeWebAuthn.lowS(Array(bytes[32..<64])))
        #else
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""
        guard let key = try loadKey(context: context) else { throw Failure.noKey }
        let signature: P256.Signing.ECDSASignature
        do { signature = try key.signature(for: AztecDigest(Data(digest))) } catch { throw Failure.signingRefused }
        guard key.publicKey.isValidSignature(signature, for: AztecDigest(Data(digest))) else {
            throw Failure.signingRefused
        }
        let raw = [UInt8](signature.rawRepresentation)
        guard raw.count == 64 else { throw Failure.badDigest }
        return (Array(raw[0..<32]), SafeWebAuthn.lowS(Array(raw[32..<64])))
        #endif
    }

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
        return try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
    }

    /// Removes the key. Whatever its account holds can never move again.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: publicKeyDefaultsKey)
        #if DEBUG && targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: standInKey)
        #endif
    }
}

/// 32 already-hashed bytes as a CryptoKit `Digest`, so nothing hashes them again.
private struct AztecDigest: Digest {
    private let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    static var byteCount: Int { 32 }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }
}

extension AztecDigest: Sequence {
    func makeIterator() -> Array<UInt8>.Iterator { [UInt8](bytes).makeIterator() }
}
