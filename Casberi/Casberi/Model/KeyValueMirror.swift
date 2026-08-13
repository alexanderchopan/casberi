import Foundation

/// One person's small, user-authored records carried between their own devices
/// through `NSUbiquitousKeyValueStore` (2026-08-13, prd §372).
///
/// This is `AddressBookSync` (2026-08-01) with the address book taken out of
/// it. That file was written for one store, and §266 named the consequence at
/// the time: `WalletStore.addresses` is equally the person's own data and did
/// NOT mirror, so a second device received a wallet's NAME but not its WATCH —
/// you'd see "Mom" on your iPad and no wallet behind it. The same gap stands
/// for `TokenWatchOrder.manual`, `KeptAskStore.order` and `AddressNudge.declined`.
///
/// **Why key-value store and not SwiftData**, unchanged from the original: these
/// are tens of rows read SYNCHRONOUSLY from hot paths (`AddressBook.name(for:)`
/// is consulted by every counterparty resolver), so moving them into the model
/// container would put a store fetch on those paths and add `@Model` types to a
/// schema that has to stay CloudKit-lightweight-migratable.
///
/// **Consent.** Gated on the SAME `icloud.sync` toggle the corpus mirror uses,
/// which ships OFF. Nothing here leaves the device until the person turns that
/// on, and the Data tray's existing ADP note covers these copies too.
///
/// **Deletions.** The classic key-value-store failure is a deleted row coming
/// back from whichever device still holds it. So a removal writes a TOMBSTONE —
/// the key and when it went — and a merge compares stamps: the newest fact
/// about a key wins, whether that fact is an edit or a deletion.
///
/// **Every storage key is passed in and none is derived**, so the address
/// book's three shipped keys stay byte-identical through this extraction. A
/// generic that built its own key names from a type name would have silently
/// orphaned every synced book already in iCloud — the whole population, with
/// nothing failing.
protocol KeyValueMirrored: Codable, Equatable {
    /// The stamp a merge compares. The type owns what this means: the book
    /// uses "when this entry last changed", falling back to when it was first
    /// added for rows written before the field existed.
    var mirrorStamp: Date { get }
}

final class KeyValueMirror<Entry: KeyValueMirrored> {

    private let entriesKey: String
    private let tombstonesKey: String
    private let localTombstonesKey: String
    /// What this device currently holds, keyed by identity.
    private let snapshot: () -> [String: Entry]
    /// Replaces the local store with a merged one. Called only from here.
    private let apply: ([String: Entry]) -> Void
    /// Which of two versions of one key stands, or nil when the standing one
    /// does — passed in because the rule is the STORE'S, not the mirror's: the
    /// book's winner keeps the earliest `addedAt` either side knows, which no
    /// generic could know to do.
    private let newer: (Entry, Entry?) -> Entry?

    /// Long enough that a phone left in a drawer for a season still learns
    /// about a deletion; short enough that the payload can't grow forever.
    private static var tombstoneLifetime: TimeInterval { 90 * 24 * 3600 }

    private var tombstones: [String: Date]
    /// True while a remote merge is being applied, so the write it causes
    /// doesn't bounce straight back out as a push.
    private var applyingRemote = false
    private var attached = false

    init(entriesKey: String, tombstonesKey: String, localTombstonesKey: String,
         snapshot: @escaping () -> [String: Entry],
         newer: @escaping (Entry, Entry?) -> Entry?,
         apply: @escaping ([String: Entry]) -> Void) {
        self.entriesKey = entriesKey
        self.tombstonesKey = tombstonesKey
        self.localTombstonesKey = localTombstonesKey
        self.snapshot = snapshot
        self.newer = newer
        self.apply = apply
        let raw = UserDefaults.standard.dictionary(forKey: localTombstonesKey)
            as? [String: Double] ?? [:]
        tombstones = raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    // MARK: - Availability

    /// Whether this device is signed into iCloud, resolved once. Re-read only
    /// when the system says it changed: `ubiquityIdentityToken` is a daemon
    /// round trip, and `enabled` is consulted from `push()`, which runs on
    /// every single mutation.
    private lazy var signedIntoICloud: Bool = FileManager.default.ubiquityIdentityToken != nil

    /// Mirroring is on only when the person turned iCloud sync on AND this
    /// device is actually signed into iCloud. The identity check also keeps
    /// `NSUbiquitousKeyValueStore.default` untouched in provisioning states
    /// where the ubiquity entitlement didn't make it into the build.
    ///
    /// The toggle is read FIRST and short-circuits: it ships off, so the
    /// common path costs one `UserDefaults` bool and never touches iCloud.
    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: "icloud.sync") && signedIntoICloud
    }

    // MARK: - Lifecycle

    /// Starts listening for other devices' changes and merges whatever is
    /// already up there. Deferred off the owning store's initializer — it calls
    /// back into that store's singleton, which during `init` does not exist yet.
    func attach() {
        guard !attached else { return }
        attached = true
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil, queue: nil) { [weak self] _ in
                guard let self, self.enabled else { return }
                DispatchQueue.main.async {
                    self.mergeRemote()
                    self.push()
                }
            }
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: nil) { [weak self] _ in
                // Signed in or out since launch — re-resolve rather than
                // trusting the value cached at attach.
                self?.signedIntoICloud = FileManager.default.ubiquityIdentityToken != nil
                self?.syncNow()
            }
        syncNow()
    }

    /// Pulls, merges, and pushes — the whole exchange. Safe to call at any
    /// time; a no-op while sync is off. Called on attach, on a remote change,
    /// and when the person flips the iCloud toggle on.
    func syncNow() {
        guard enabled else { return }
        NSUbiquitousKeyValueStore.default.synchronize()
        mergeRemote()
        push()
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    // MARK: - Tombstones

    /// Records that a key was deleted here. Recorded BEFORE the entry goes, so
    /// the push that the removal triggers already carries the tombstone with it.
    func noteRemoval(_ key: String) {
        tombstones[key] = .now
        persistTombstones()
    }

    private func persistTombstones() {
        prune()
        UserDefaults.standard.set(
            tombstones.mapValues(\.timeIntervalSince1970),
            forKey: localTombstonesKey)
    }

    private func prune() {
        let floor = Date.now.addingTimeInterval(-Self.tombstoneLifetime)
        tombstones = tombstones.filter { $0.value > floor }
    }

    // MARK: - Push

    /// Writes this device's whole store and tombstone set up. Whole-blob rather
    /// than per-key: these are tens of rows, and one value can't tear the way a
    /// hundred independent keys landing out of order can.
    /// No `synchronize()` here: the system schedules its own upload, Apple
    /// documents an explicit call as rarely necessary, and this runs on every
    /// mutation. `syncNow` still forces one, because that IS the explicit
    /// exchange.
    func push() {
        guard enabled, !applyingRemote else { return }
        let store = NSUbiquitousKeyValueStore.default
        if let data = try? JSONEncoder().encode(snapshot()) {
            store.set(data, forKey: entriesKey)
        }
        store.set(tombstones.mapValues(\.timeIntervalSince1970), forKey: tombstonesKey)
    }

    // MARK: - Merge

    /// Merges what's up there into what's here, newest fact per key wins.
    ///
    /// Four cases, and the deletion ones are the reason this isn't a plain
    /// dictionary union:
    ///   • remote has an entry we don't → take it, unless we deleted it LATER;
    ///   • both have it → the later stamp wins (via the store's own `newer`);
    ///   • remote deleted a key we still hold → drop it, if their deletion is
    ///     later than our copy's last edit;
    ///   • we deleted a key they still hold → our tombstone survives the merge
    ///     and the push re-asserts it.
    private func mergeRemote() {
        let store = NSUbiquitousKeyValueStore.default
        let remoteEntries: [String: Entry] = (store.data(forKey: entriesKey))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        let remoteTombstones: [String: Date] = (store.dictionary(forKey: tombstonesKey)
            as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }

        var merged = snapshot()
        var changed = false

        for (key, remote) in remoteEntries {
            // A deletion here that happened after their edit stands.
            if let deletedHere = tombstones[key], deletedHere >= remote.mirrorStamp { continue }
            guard let winner = newer(remote, merged[key]) else { continue }
            merged[key] = winner
            changed = true
        }

        for (key, deletedThere) in remoteTombstones {
            if let standing = merged[key], standing.mirrorStamp <= deletedThere {
                merged.removeValue(forKey: key)
                changed = true
            }
            // Adopt their tombstone so this device re-asserts the deletion too.
            if tombstones[key] == nil || tombstones[key]! < deletedThere {
                tombstones[key] = deletedThere
            }
        }
        persistTombstones()

        guard changed else { return }
        applyingRemote = true
        apply(merged)
        applyingRemote = false
    }
}
