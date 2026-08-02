import Foundation
import Security

/// Personal-access tokens live in the Keychain — never UserDefaults, never a
/// server. One generic-password item per bridge, readable only by this app.
///
/// **Storage policy (prd §277, 2026-08-02).** Every item this vault writes is
/// `…ThisDeviceOnly` and explicitly non-synchronizable. Both matter, and they
/// stop different things:
///
/// - **`ThisDeviceOnly`** keeps the item out of encrypted device backups, so a
///   backup restored onto a second phone does not carry the person's live API
///   keys with it. The plain `AfterFirstUnlock` this used to write is
///   restorable that way. `AfterFirstUnlock` itself is kept (rather than
///   `WhenUnlocked`) because bridges sync while the screen is locked; the
///   `ThisDeviceOnly` variant changes the backup rule, not when the app can
///   read.
/// - **Non-synchronizable** keeps them off iCloud Keychain. Absent the
///   attribute the default is already false, so this states an existing
///   guarantee rather than changing one — but it states it where the audit
///   can see it, which is the point (`scripts/keychain-audit.sh`).
///
/// The delete paths ask for `kSecAttrSynchronizableAny` on purpose: a query
/// that doesn't name the attribute only matches non-synchronizable items, so
/// without it "Delete access" would silently skip any synced item an older
/// build (or a future bug) had left behind.
enum TokenVault {
    private static let service = "com.casberi.app.tokens"

    /// The one place the write policy is spelled, so `set` and `migrate`
    /// cannot drift apart on it.
    private static var writePolicy: [String: Any] {
        [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
    }

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
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(token.utf8),
        ]
        add.merge(writePolicy) { current, _ in current }
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
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
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Migration

    private static let migratedKey = "keychain.hardened.v1"

    /// Re-write every existing item under the current write policy.
    ///
    /// Keychain accessibility is fixed when an item is ADDED, so keys stored
    /// by an earlier build keep the old, backup-restorable policy until they
    /// are written again — which for a key you set once and never touch is
    /// never. This runs once, reads each item's own data back, and re-adds it.
    ///
    /// Deliberately silent and best-effort: a failure here leaves the item
    /// exactly as it was (still readable, still working), which is why it is
    /// safe to run at launch. It reports what it did so `-keychainProbe` can
    /// say so out loud.
    @discardableResult
    static func migrateToDeviceOnly(force: Bool = false) -> (moved: Int, kept: Int) {
        if !force && UserDefaults.standard.bool(forKey: migratedKey) { return (0, 0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            UserDefaults.standard.set(true, forKey: migratedKey)
            return (0, 0)
        }

        var moved = 0, kept = 0
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else { kept += 1; continue }
            let accessible = item[kSecAttrAccessible as String] as? String
            let synced = (item[kSecAttrSynchronizable as String] as? Bool) ?? false
            let alreadyRight =
                accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String) && !synced
            if alreadyRight { kept += 1; continue }

            delete(account)
            var add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
            ]
            add.merge(writePolicy) { current, _ in current }
            if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { moved += 1 } else { kept += 1 }
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
        return (moved, kept)
    }

    /// What the vault currently holds, by policy — the honest input to
    /// `-keychainProbe`. Never returns or logs a secret's VALUE.
    static func policyCensus() -> (total: Int, deviceOnly: Int, synchronizable: Int) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return (0, 0, 0) }
        var deviceOnly = 0, synced = 0
        for item in items {
            if item[kSecAttrAccessible as String] as? String
                == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String) { deviceOnly += 1 }
            if (item[kSecAttrSynchronizable as String] as? Bool) ?? false { synced += 1 }
        }
        return (items.count, deviceOnly, synced)
    }
}
