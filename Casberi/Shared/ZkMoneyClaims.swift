import Foundation
import Security

/// A zk.money payment link's claim secret, kept on THIS device only
/// (2026-10-17, prd §1384). Shared: the app's paste and the share extension
/// both capture payment links.
///
/// §1273 kept nothing after the `#`, because the row syncs to iCloud and
/// lives in Spotlight, and whoever holds the secret can take the money. That
/// was safe and it lost the money's way home: a link someone sent you could
/// no longer be claimed from where you kept it. Now the row still keeps only
/// the bare URL, and the whole link goes to the Keychain, device-only and
/// never synchronized, under the row's id in the app group (the extension and
/// the app both read it). The thing sheet's "Claim in zk.money" reads it back
/// on tap and opens it in Safari, where the person's zk.money wallet lives.
///
/// A capture STAGES the secret in memory (`stage`); only a site that inserts
/// the row keeps it (`commit`), so a draft, an autosave or a preview never
/// leaves a key behind (review, 2026-10-17: the note sheet's 800ms autosave
/// re-ran capture over a link still in the editor).
///
/// The index of ids is not secret: it lets a verb ask "is there one?"
/// without a Keychain read per row (prd §628), from a set held in memory and
/// re-read at most every few seconds, so a row the share extension kept
/// gains its verb soon after.
enum ZkMoneyClaims {
    private static let service = "com.casberi.app.zkmoney.claim"
    private static let indexKey = "zkmoney.claims.v1"

    /// The app group as a Keychain access group: the bare id on iOS, the
    /// team-prefixed one the Mac is entitled to (`Casberi-Catalyst.entitlements`).
    private static var group: String {
        #if targetEnvironment(macCatalyst)
        "35428TQK3S." + SharedStore.appGroup
        #else
        SharedStore.appGroup
        #endif
    }

    private static let defaults: UserDefaults = UserDefaults(suiteName: SharedStore.appGroup) ?? .standard

    private static let lock = NSLock()
    nonisolated(unsafe) private static var staged: [UUID: String] = [:]
    nonisolated(unsafe) private static var cachedIndex: (ids: Set<String>, at: Date)?

    /// Holds a captured secret for a row not yet inserted. Memory only.
    static func stage(_ secret: String, for id: UUID) {
        lock.withLock { staged[id] = secret }
    }

    /// Keeps the staged secret for a row that was just inserted, and says so
    /// in its body. false when nothing was staged or the Keychain refused.
    @discardableResult
    static func commit(_ thing: Thing) -> Bool {
        let secret = lock.withLock { staged.removeValue(forKey: thing.id) }
        guard let secret else { return false }
        let kept = keep(secret, for: thing.id)
        if thing.enrichedText == ZkMoneyLink.paymentNote(kept: false) || thing.enrichedText == nil {
            thing.enrichedText = ZkMoneyLink.paymentNote(kept: kept)
        }
        return kept
    }

    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString,
         kSecUseDataProtectionKeychain as String: true]
    }

    /// Keeps `link` for the row `id`. false when it is not a payment link or
    /// the Keychain refused it, so the row says the secret was not kept.
    @discardableResult
    static func keep(_ link: String, for id: UUID) -> Bool {
        guard case .payment? = ZkMoneyLink.link(link), let data = link.data(using: .utf8) else { return false }
        forget(id)
        var add = query(id)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        add[kSecAttrAccessGroup as String] = group
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            // A build signed without the group still keeps it on this device;
            // only the share extension's copy would then be out of the app's
            // reach, and the row's words follow what `has` finds.
            add.removeValue(forKey: kSecAttrAccessGroup as String)
            status = SecItemAdd(add as CFDictionary, nil)
        }
        #if DEBUG
        NSLog("[Casberi] zkMoneyClaims: keep status %d", status)
        #endif
        guard status == errSecSuccess else { return false }
        var ids = Set(defaults.stringArray(forKey: indexKey) ?? [])
        ids.insert(id.uuidString)
        defaults.set(Array(ids), forKey: indexKey)
        lock.withLock { cachedIndex = (ids, .now) }
        return true
    }

    /// Whether a secret was kept for the row, from the index alone: a set in
    /// memory, re-read from the app group at most every five seconds (the
    /// verb asks twice per visible link row).
    static func has(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let c = cachedIndex, Date.now.timeIntervalSince(c.at) < 5 { return c.ids.contains(id.uuidString) }
        let ids = Set(defaults.stringArray(forKey: indexKey) ?? [])
        cachedIndex = (ids, .now)
        return ids.contains(id.uuidString)
    }

    /// The whole link, read on tap.
    static func link(for id: UUID) -> URL? {
        var read = query(id)
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(read as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let text = String(data: data, encoding: .utf8),
              case .payment? = ZkMoneyLink.link(text) else { return nil }
        return URL(string: text)
    }

    static func forget(_ id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
        let ids = (defaults.stringArray(forKey: indexKey) ?? []).filter { $0 != id.uuidString }
        defaults.set(ids, forKey: indexKey)
        lock.withLock { cachedIndex = nil }
    }

    /// Drops every secret whose row is gone: a deleted row takes its money's
    /// key with it at the next launch. Walks the KEYCHAIN, not the index, so
    /// a secret whose index entry was lost to two processes writing at once
    /// is still found.
    static func prune(keeping live: Set<UUID>) {
        for id in keptIDs where !live.contains(id) { forget(id) }
    }

    /// Every row id this device holds a secret for, read off the Keychain.
    static var keptIDs: [UUID] {
        var all: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecUseDataProtectionKeychain as String: true,
                                  kSecReturnAttributes as String: true,
                                  kSecMatchLimit as String: kSecMatchLimitAll]
        var out: CFTypeRef?
        guard SecItemCopyMatching(all as CFDictionary, &out) == errSecSuccess,
              let items = out as? [[String: Any]] else { return [] }
        all.removeAll()
        return items.compactMap { ($0[kSecAttrAccount as String] as? String).flatMap { UUID(uuidString: $0) } }
    }
}
