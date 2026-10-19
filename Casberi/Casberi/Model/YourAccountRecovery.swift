import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// **YOUR ACCOUNT'S RECOVERY KEY (prd §1421, §1427): a P-256 key in iCloud
/// Keychain**, so every device signed in to the person's Apple ID holds it
/// and a new iPhone takes the account back with no phrase. It is the
/// account's second owner, at threshold 1 with no delay, through its own
/// Safe passkey signer (`SafeWebAuthnSignerFactory`'s proxy for the key). It
/// never signs a payment: its one job is to move the account to a new
/// device key (`YourAccountChain.recover`).
///
/// A synchronizable item cannot live in the Secure Enclave or carry a
/// biometric access control (both are device-only), so it is
/// `AfterFirstUnlock` in iCloud Keychain (end-to-end encrypted), in the app
/// id's shared group so the Mac reads what the iPhone wrote, and the app asks
/// for the device owner — Face ID, Touch ID or the passcode — before it
/// signs. The item is keyed by the account's address, and carries key 0's
/// public half, so a phone that holds nothing else knows which account it
/// recovers. Measured in `tools/safe-account-spike` on an iPhone (2026-10-19).
enum YourAccountRecovery {
    private static let service = "com.casberi.app.account.recovery"

    struct Stored: Codable {
        /// The private scalar, 32 bytes.
        let key: Data
        /// Key 0's `x ‖ y`, hex: the key the address comes from.
        let origin: String
    }

    private static func query(_ account: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: true,
        ]
        if let account { q[kSecAttrAccount as String] = account.lowercased() }
        return q
    }

    /// The accounts whose recovery key this device holds — the iCloud
    /// Keychain's word, read without a prompt.
    static func accounts() -> [(address: String, origin: String)] {
        var q = query(nil)
        q[kSecReturnAttributes as String] = true
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let rows = out as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let account = row[kSecAttrAccount as String] as? String, ENS.isHexAddress(account),
                  let data = row[kSecValueData as String] as? Data,
                  let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
            return (EIP55.checksum(account), stored.origin)
        }
    }

    private static func load(_ account: String) -> Stored? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    static func exists(for account: String) -> Bool { load(account) != nil }

    /// The recovery key's public half, when this device holds it.
    static func publicKey(for account: String) -> (x: [UInt8], y: [UInt8])? {
        guard let stored = load(account),
              let key = try? P256.Signing.PrivateKey(rawRepresentation: stored.key) else { return nil }
        let xy = [UInt8](key.publicKey.rawRepresentation)
        return (Array(xy[0..<32]), Array(xy[32..<64]))
    }

    enum Failure: Error, Equatable { case keychainRefused(OSStatus), noOrigin, refused }

    /// Make the account's recovery key, once; the same key thereafter.
    @discardableResult
    static func make(for account: String) throws -> (x: [UInt8], y: [UInt8]) {
        if let existing = publicKey(for: account) { return existing }
        guard let origin = YourAccountKey.originHex else { throw Failure.noOrigin }
        let fresh = P256.Signing.PrivateKey()
        let data = try JSONEncoder().encode(Stored(key: fresh.rawRepresentation, origin: origin))
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrAccessGroup as String] = TokenVault.sharedAccessGroup
        let status = TokenVault.addNamingGroup(add)
        guard status == errSecSuccess else { throw Failure.keychainRefused(status) }
        let xy = [UInt8](fresh.publicKey.rawRepresentation)
        return (Array(xy[0..<32]), Array(xy[32..<64]))
    }

    /// Sign 32 pre-hashed bytes with the recovery key, after the device owner
    /// says yes: `r ‖ s`, `s` low.
    static func sign(_ digest: [UInt8], for account: String, reason: String) async throws -> (r: [UInt8], s: [UInt8]) {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil),
              (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true,
              let stored = load(account) else { throw Failure.refused }
        let key = try P256.Signing.PrivateKey(rawRepresentation: stored.key)
        let raw = [UInt8](try key.signature(for: RecoveryDigest(Data(digest))).rawRepresentation)
        return (Array(raw[0..<32]), SafeWebAuthn.lowS(Array(raw[32..<64])))
    }
}

/// 32 already-hashed bytes, signed as they are.
private struct RecoveryDigest: Digest {
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    static var byteCount: Int { 32 }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    func makeIterator() -> Array<UInt8>.Iterator { [UInt8](bytes).makeIterator() }
    var description: String { "RecoveryDigest" }
    static func == (a: RecoveryDigest, b: RecoveryDigest) -> Bool { a.bytes == b.bytes }
    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}
