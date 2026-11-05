import Foundation
import Security

/// YOUR AZTEC ACCOUNT'S ONE SECRET (prd §1700): 32 random bytes in iCloud
/// Keychain, stored as the private-money root is (prd §1562): a synchronizable
/// generic password, end-to-end encrypted by iCloud Keychain, AfterFirstUnlock
/// (a synchronizable item can be neither ThisDeviceOnly nor biometric), in the
/// app id's shared group so the Mac reads what the iPhone wrote. The engine
/// derives the account's secret and signing key from it, so a phone signed in
/// to the same Apple account gets the same account back (the Apple account is
/// the security, user 2026-11-03). Never logged; only the engine page sees it.
enum AztecRoot {
    private static let service = "com.casberi.app.aztec.root"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "root",
            kSecAttrSynchronizable as String: true,
        ]
    }

    /// Whether the root is on this device (iCloud Keychain may not have
    /// brought it yet). Reads presence only, never the bytes.
    static var exists: Bool {
        var read = query
        read[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(read as CFDictionary, nil) == errSecSuccess
    }

    /// The root, made the first time it is asked for. `made` says which.
    /// `create: false` never makes one: an account already used here must
    /// find ITS root, never start a new, empty account over it (prd §1700f
    /// item 5).
    static func ensure(create: Bool = true) -> (bytes: Data, made: Bool)? {
        var read = query
        read[kSecReturnData as String] = true
        var out: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &out) == errSecSuccess, let data = out as? Data, data.count == 32 {
            return (data, false)
        }
        guard create else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        var add = query
        add[kSecValueData as String] = Data(bytes)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrAccessGroup as String] = TokenVault.sharedAccessGroup
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem, let again = ensureExisting() { return (again, false) }
        guard status == errSecSuccess else {
            NSLog("aztecEngine| root | failed %d", status)
            return nil
        }
        return (Data(bytes), true)
    }

    /// A root another device added between our read and our write.
    private static func ensureExisting() -> Data? {
        var read = query
        read[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(read as CFDictionary, &out) == errSecSuccess, let data = out as? Data, data.count == 32 else { return nil }
        return data
    }
}
