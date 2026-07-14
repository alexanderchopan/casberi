import Foundation
import Security

/// Personal-access tokens live in the Keychain — never UserDefaults, never a
/// server. One generic-password item per bridge, readable only by this app.
enum TokenVault {
    private static let service = "com.casberi.app.tokens"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ token: String, for key: String) {
        delete(key)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Every stored account name with the given prefix, in ONE Keychain
    /// round-trip — for callers that check several slots per render
    /// (AIKey.connected), where one read per slot would multiply securityd
    /// IPCs on the render path.
    static func accounts(withPrefix prefix: String) -> Set<String> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let attrs = items as? [[String: Any]] else { return [] }
        return Set(attrs.compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0.hasPrefix(prefix) })
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Every credential in the vault, gone — the "Delete access" wipe (user
    /// ruling 2026-07-13: delete THINGS and delete ACCESS are two verbs).
    /// One service-wide delete, so every current and future token, key, and
    /// mail password is covered without an enumeration to forget.
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
