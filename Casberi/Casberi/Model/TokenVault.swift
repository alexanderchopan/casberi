import Foundation
import Security

/// Personal-access tokens live in the Keychain — never UserDefaults, never a
/// server. One generic-password item per bridge, readable only by this app.
///
/// **A pasted key reaches your other devices (prd §1162, amends §277 item 2;
/// user, 2026-10-07: "yes let them").** §277 made every item device-only and
/// never weighed what that cost: someone on the iPhone and the Mac connected
/// every keyed account twice. A key you PASTE now syncs through iCloud
/// Keychain — end-to-end encrypted with or without Advanced Data Protection,
/// the route §982's locked-note key already takes — and the other device
/// registers the seat when the key arrives (`BridgeStore.reconcileKeyedSeats`).
/// What stays on the device, by `syncs(_:)`'s allowlist:
///
/// - **Web sessions** (X, Instagram, TikTok, Threads, Spotify, Duolingo,
///   Privy, Rocket Money, Acorns): a cookie is a signed-in browser, and two
///   devices presenting one session is the shape a service flags.
/// - **OAuth tokens that refresh** (Slack, Dropbox, Twitch): a refresh token
///   spent on two devices races, and the loser is signed out.
/// - **A key that needs a setting the vault doesn't hold** (PostHog's and
///   Sentry's host, AWS's region, Steam's profile, a mail address): the other
///   device would hold the key and read the wrong place with it.
///
/// An allowlist, not a denylist: a credential nobody classified stays on the
/// device, which costs a second paste rather than shipping a session cookie.
///
/// **Storage policy for what stays (prd §277, 2026-08-02).** An item that
/// does not sync is `…ThisDeviceOnly` and explicitly non-synchronizable. Both
/// matter, and they stop different things:
///
/// - **`ThisDeviceOnly`** keeps the item out of encrypted device backups, so a
///   backup restored onto a second phone does not carry the person's live
///   sessions with it. `AfterFirstUnlock` itself is kept (rather than
///   `WhenUnlocked`) because bridges sync while the screen is locked; the
///   `ThisDeviceOnly` variant changes the backup rule, not when the app can
///   read.
/// - **Non-synchronizable** keeps them off iCloud Keychain. Absent the
///   attribute the default is already false, so this states an existing
///   guarantee rather than changing one — but it states it where the audit
///   can see it, which is the point (`scripts/keychain-audit.py`).
///
/// Every read and delete asks for `kSecAttrSynchronizableAny`: a query that
/// doesn't name the attribute matches only non-synchronizable items, so it
/// would miss every synced key. A synced key deleted here is deleted on every
/// device — disconnecting is a fact about the account, not the phone.
enum TokenVault {
    private static let service = "com.casberi.app.tokens"

    /// The accessibility every item that STAYS must carry. Spelled ONCE —
    /// `writePolicy`, the migrations and `policyCensus` all read it, so
    /// changing it can't leave one of them behind silently re-writing (or
    /// mis-reporting) every item forever.
    private static let requiredAccessible =
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    /// The one place the device-only policy is spelled, so `set` and the
    /// migrations cannot drift apart on it.
    private static var writePolicy: [String: Any] {
        [
            kSecAttrAccessible as String: requiredAccessible,
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// The policy for a key that syncs (prd §1162). A synchronizable item
    /// cannot be `ThisDeviceOnly`, so it is plain `AfterFirstUnlock` — still
    /// readable while the screen is locked, which is when bridges sync.
    ///
    /// **The access group is NAMED, and it is the app identifier.** The two
    /// platforms default to different groups — the iPhone to the app id, the
    /// Mac to its first `keychain-access-groups` entry
    /// (`35428TQK3S.group.com.casberi.app`, `Casberi-Catalyst.entitlements`) —
    /// and the iPhone is not entitled to the Mac's. A key written into the
    /// Mac's default group would sync and never be readable on the phone.
    /// Both apps are signed with one application identifier, so its group is
    /// the one both can always read.
    private static var syncPolicy: [String: Any] {
        [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessGroup as String: sharedAccessGroup,
        ]
    }

    /// The application identifier both platforms are signed with — the one
    /// keychain group the iPhone and the Mac can both read (prd §1162).
    static let sharedAccessGroup = "35428TQK3S.com.casberi.app"

    /// Add `query`; if the named group is refused (`errSecMissingEntitlement`,
    /// a build signed without the app id), add it to the default group, where
    /// it still works on this device. Returns the status of the add that
    /// counted.
    @discardableResult
    static func addNamingGroup(_ query: [String: Any]) -> OSStatus {
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecMissingEntitlement,
              query[kSecAttrAccessGroup as String] != nil else { return status }
        var bare = query
        bare.removeValue(forKey: kSecAttrAccessGroup as String)
        return SecItemAdd(bare as CFDictionary, nil)
    }

    /// Whether this item reaches the person's other devices (prd §1162).
    static func syncs(_ key: String) -> Bool { syncedKeys.contains(key) }

    /// Bridges whose key needs a setting this vault does not hold — their
    /// host or region lives in `UserDefaults`, which does not travel.
    static let localTokenBridges: Set<TokenBridge> = [.posthog, .sentry, .aws]

    /// The pasted keys, by construction from the types that name them, plus
    /// the settings a synced key cannot work without (they live in the vault
    /// already, so they travel beside it).
    static let syncedKeys: Set<String> = {
        var keys = Set(TokenBridge.allCases.filter { !localTokenBridges.contains($0) }.map(\.tokenKey))
        // Bankr signs in on its own page; every other agent key is pasted.
        keys.formUnion(AgentProvider.allCases.filter { $0 != .bankr }.map(\.vaultKey))
        keys.formUnion(ExchangeBridge.Venue.allCases.map(\.vaultKey))
        keys.formUnion([TrelloAuth.keyVaultKey, JiraAuth.domainVaultKey, JiraAuth.emailVaultKey,
                        ASCAuth.keyIDVaultKey, ASCAuth.issuerVaultKey, WiseAuth.profileVaultKey])
        return keys
    }()

    /// The key, THIS DEVICE'S OWN COPY FIRST (prd §1162). A key pasted before
    /// §1162 keeps its device-only copy beside the synced one
    /// (`migrateToSynced` never deletes it), and two devices may each have
    /// held a different key for one app — a work account here, a personal one
    /// there. The copy this device was given is the one it keeps reading; the
    /// synced copy serves a device that never had one. One IPC either way.
    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let rows = result as? [[String: Any]] else { return nil }
        let row = rows.first { !isSynced($0) } ?? rows.first
        guard let data = row?[kSecValueData as String] as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Every account the vault holds, or nil when it could not answer — one
    /// attributes-only read for a pass that asks about many keys at once
    /// (`reconcileKeyedSeats`), where a read per key was ~35 IPCs per sweep.
    static func storedAccounts() -> Set<String>? {
        items().map { Set($0.compactMap { $0[kSecAttrAccount as String] as? String }) }
    }

    /// Bumped by EVERY write below (prd §628), so a reader that memoises a
    /// Keychain answer — `AgentKey.configured` — can key on it and never miss
    /// a writer. A `SecItemCopyMatching` is an IPC round trip to securityd,
    /// and three sheet bodies were making one (or eight) per body evaluation.
    /// A key arriving from iCloud is a write nobody here made, so the
    /// foreground sweep bumps it too (`noteArrivals`).
    nonisolated(unsafe) static var generation = 0

    /// A synced key may have arrived since the last look (prd §1162).
    static func noteArrivals() { generation += 1 }

    /// Store a key. **A replace UPDATES in place** (prd §1162): a delete
    /// followed by an add reaches the other device as two changes, and one
    /// sweep landing between them reads the key as removed and drops the seat
    /// — losing its pause and its health record when the add arrives as a new
    /// connection. The copy of the OTHER kind goes (a device-only leftover
    /// beside a synced key), so `get` cannot read a stale one.
    static func set(_ token: String, for key: String) {
        generation += 1
        let synced = syncs(key)
        let data = Data(token.utf8)
        func locate(_ syncable: Bool) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: key,
             kSecAttrSynchronizable as String: syncable]
        }
        SecItemDelete(locate(!synced) as CFDictionary)
        let updated = SecItemUpdate(locate(synced) as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        guard updated == errSecItemNotFound else { return }
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        // The POLICY wins a conflict, not the caller — a call site that set
        // its own accessibility would otherwise silently opt out of it.
        add.merge(synced ? syncPolicy : writePolicy) { _, policy in policy }
        addNamingGroup(add)
    }

    static func delete(_ key: String) {
        generation += 1
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
    /// mail password is covered without an enumeration to forget. Synced keys
    /// go from every device (prd §1162).
    static func deleteAll() {
        generation += 1
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Migration

    private static let migratedKey = "keychain.hardened.v1"
    private static let syncedMigrationKey = "keychain.synced.v1"

    /// Every item, attributes only, or nil when the vault could not ANSWER —
    /// `errSecInteractionNotAllowed` before the first unlock after a reboot is
    /// not "nothing to do", and treating it as done would retire a migration
    /// for the life of the install with nothing anywhere to say so.
    private static func items(withData: Bool = false) -> [[String: Any]]? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        if withData { query[kSecReturnData as String] = true }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { return nil }
        return result as? [[String: Any]] ?? []
    }

    private static func isSynced(_ item: [String: Any]) -> Bool {
        (item[kSecAttrSynchronizable as String] as? Bool) ?? false
    }

    /// Re-write every existing device-bound item under the current
    /// accessibility policy.
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
    /// in memory, and leaves the item untouched when it fails.
    ///
    /// A synchronizable item is left alone: it cannot be `ThisDeviceOnly`,
    /// and since §1162 it is synced on purpose (`migrateToSynced`).
    @discardableResult
    static func migrateToDeviceOnly(force: Bool = false)
    -> (hardened: Int, alreadyRight: Int, failed: Int) {
        generation += 1
        if !force && UserDefaults.standard.bool(forKey: migratedKey) { return (0, 0, 0) }
        guard let items = items() else { return (0, 0, 0) }

        var hardened = 0, alreadyRight = 0, failed = 0
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { failed += 1; continue }
            if isSynced(item) || item[kSecAttrAccessible as String] as? String == requiredAccessible {
                alreadyRight += 1
                continue
            }
            let locate: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: false,
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

    /// Carry every pasted key stored device-only by an earlier build into
    /// iCloud Keychain (prd §1162), so a key pasted before this build reaches
    /// the other device too — without it, only keys pasted from now on would.
    ///
    /// **It COPIES and never deletes.** Synchronizability is part of an
    /// item's identity, so the synced copy is a second item beside the
    /// device-only one, which stays — and `get` reads it first. That is what
    /// makes the pass safe when two devices held DIFFERENT keys for one app (a
    /// work account on the Mac, a personal one on the iPhone): both may add
    /// their copy before either sees the other's, iCloud keeps one, and
    /// neither device loses the key it was using. The synced copy serves a
    /// device that never had one. A duplicate is a copy already synced; a
    /// failed add leaves everything as it was and retries next launch.
    @discardableResult
    static func migrateToSynced(force: Bool = false) -> (moved: Int, failed: Int) {
        if !force && UserDefaults.standard.bool(forKey: syncedMigrationKey) { return (0, 0) }
        guard let items = items(withData: true) else { return (0, 0) }
        generation += 1

        var moved = 0, failed = 0
        for item in items where !isSynced(item) {
            guard let account = item[kSecAttrAccount as String] as? String, syncs(account) else { continue }
            guard let data = item[kSecValueData as String] as? Data else { failed += 1; continue }
            var add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
            ]
            add.merge(syncPolicy) { _, policy in policy }
            let status = addNamingGroup(add)
            guard status == errSecSuccess || status == errSecDuplicateItem else { failed += 1; continue }
            moved += 1
        }
        if failed == 0 { UserDefaults.standard.set(true, forKey: syncedMigrationKey) }
        return (moved, failed)
    }

    /// What the vault currently holds, by policy — the honest input to
    /// `-keychainProbe`. Never returns or logs a secret's VALUE. `misplaced`
    /// counts what breaks its rule: a synced item for a key that stays, a
    /// device item that is not `ThisDeviceOnly`, or a pasted key with no
    /// synced copy at all. A device-only copy BESIDE a synced one is the
    /// migration's design, not a misplacement (`migrateToSynced`).
    /// `sharedGroup` counts synced items in the app-id group — a synced item
    /// anywhere else is one the other platform cannot read.
    static func policyCensus() -> (total: Int, deviceOnly: Int, synchronizable: Int,
                                   misplaced: Int, sharedGroup: Int) {
        guard let items = items() else { return (0, 0, 0, 0, 0) }
        var deviceOnly = 0, synced = 0, misplaced = 0, shared = 0
        let syncedAccounts = Set(items.filter(isSynced).compactMap { $0[kSecAttrAccount as String] as? String })
        for item in items {
            let account = item[kSecAttrAccount as String] as? String ?? ""
            let isDeviceOnly = item[kSecAttrAccessible as String] as? String == requiredAccessible
            if isDeviceOnly { deviceOnly += 1 }
            if isSynced(item) {
                synced += 1
                if item[kSecAttrAccessGroup as String] as? String == sharedAccessGroup { shared += 1 }
                if !syncs(account) { misplaced += 1 }
            } else if !isDeviceOnly || (syncs(account) && !syncedAccounts.contains(account)) {
                misplaced += 1
            }
        }
        return (items.count, deviceOnly, synced, misplaced, shared)
    }
}
