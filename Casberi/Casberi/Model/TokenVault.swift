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

    /// The accessibility every item must carry. Spelled ONCE — `writePolicy`,
    /// the migration's "is this already right?" test and `policyCensus` all
    /// read it, so changing it can't leave one of the three behind silently
    /// re-writing (or mis-reporting) every item forever.
    private static let requiredAccessible =
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    /// The one place the write policy is spelled, so `set` and `migrate`
    /// cannot drift apart on it.
    private static var writePolicy: [String: Any] {
        [
            kSecAttrAccessible as String: requiredAccessible,
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
        // The POLICY wins a conflict, not the caller — a call site that set
        // its own accessibility would otherwise silently opt out of it.
        add.merge(writePolicy) { _, policy in policy }
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

    /// Re-write every existing item under the current accessibility policy.
    ///
    /// Keychain accessibility is fixed when an item is ADDED, so keys stored
    /// by an earlier build keep the old, backup-restorable policy until they
    /// are written again — which for a key you paste once and never touch is
    /// never.
    ///
    /// **It updates in place and never deletes, and that is not a style
    /// choice.** The first version read each item's data, `delete`d it and
    /// re-`add`ed it under the new policy — so ANY failure of the add
    /// (`errSecInteractionNotAllowed` if the device relocked between the two
    /// calls, a residual duplicate, a missing entitlement) destroyed the
    /// person's live API key outright, and counted it as "kept". This runs
    /// unattended at launch. `kSecAttrAccessible` is updatable, so
    /// `SecItemUpdate` does the same job atomically, never holds the secret
    /// in memory, and leaves the item untouched when it fails — which is what
    /// the old comment claimed and the old code did not do.
    ///
    /// Synchronizable items are reported by `policyCensus` rather than
    /// converted here: no version of this vault ever wrote one, and the only
    /// way to un-sync an item IS the destructive delete/add above.
    @discardableResult
    static func migrateToDeviceOnly(force: Bool = false)
    -> (hardened: Int, alreadyRight: Int, failed: Int) {
        if !force && UserDefaults.standard.bool(forKey: migratedKey) { return (0, 0, 0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // Only a real ANSWER retires the migration. `errSecInteractionNotAllowed`
        // — a background launch before the first unlock after a reboot, when
        // every after-first-unlock item is unreadable — is not "nothing to
        // do", and treating it as done would leave the keys loose for the
        // life of the install with nothing anywhere to say so.
        guard status == errSecSuccess || status == errSecItemNotFound else { return (0, 0, 0) }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            UserDefaults.standard.set(true, forKey: migratedKey)   // empty vault, nothing to carry
            return (0, 0, 0)
        }

        var hardened = 0, alreadyRight = 0, failed = 0
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { failed += 1; continue }
            if item[kSecAttrAccessible as String] as? String == requiredAccessible {
                alreadyRight += 1
                continue
            }
            let locate: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            let change: [String: Any] = [kSecAttrAccessible as String: requiredAccessible]
            if SecItemUpdate(locate as CFDictionary, change as CFDictionary) == errSecSuccess {
                hardened += 1
            } else {
                failed += 1
            }
        }
        // A partial pass retries next launch rather than declaring victory.
        if failed == 0 { UserDefaults.standard.set(true, forKey: migratedKey) }
        return (hardened, alreadyRight, failed)
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
            if item[kSecAttrAccessible as String] as? String == requiredAccessible { deviceOnly += 1 }
            if (item[kSecAttrSynchronizable as String] as? Bool) ?? false { synced += 1 }
        }
        return (items.count, deviceOnly, synced)
    }
}
