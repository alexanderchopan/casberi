import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The recovery key of prd §1421: a P-256 key in iCloud Keychain, so every
/// device signed in to your Apple ID has it and a new phone can recover with
/// no phrase. A synced item cannot live in the Secure Enclave or carry a
/// biometric access control (both are device-only), so the app asks for
/// Face ID before it reads the key. It never signs a payment: it only moves
/// the account to a new device key.
///
/// Testnet harness only.
enum RecoveryKey {
    private static let service = "com.casberi.safespike.recovery"
    private static let account = "recovery-v1"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: true]
    }

    static var exists: Bool { (try? load()) != nil }

    @discardableResult
    static func make() throws -> SafeAccount.Key {
        if let existing = try load() { return key(existing) }
        let fresh = P256.Signing.PrivateKey()
        var add = baseQuery
        add[kSecValueData as String] = fresh.rawRepresentation
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Chain.RPCError(message: "Keychain refused the recovery key (\(status))") }
        return key(fresh)
    }

    static func current() throws -> SafeAccount.Key? { try load().map(key) }

    private static func load() throws -> P256.Signing.PrivateKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw Chain.RPCError(message: "Keychain read failed (\(status))") }
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    private static func key(_ privateKey: P256.Signing.PrivateKey) -> SafeAccount.Key {
        let xy = [UInt8](privateKey.publicKey.rawRepresentation)
        return SafeAccount.Key(x: Array(xy[0..<32]), y: Array(xy[32..<64])) { digest in
            try await faceID("Use your recovery key")
            let raw = [UInt8](try privateKey.signature(for: PreHashedDigest(Data(digest))).rawRepresentation)
            return (Array(raw[0..<32]), SafeWebAuthn.lowS(Array(raw[32..<64])))
        }
    }

    private static func faceID(_ reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        _ = try await context.evaluatePolicy(policy, localizedReason: reason)
    }
}

/// 32 already-hashed bytes for a software P-256 key.
struct PreHashedDigest: Digest {
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    static var byteCount: Int { 32 }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    func makeIterator() -> Array<UInt8>.Iterator { [UInt8](bytes).makeIterator() }
    var description: String { "PreHashedDigest" }
    static func == (a: PreHashedDigest, b: PreHashedDigest) -> Bool { a.bytes == b.bytes }
    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}
