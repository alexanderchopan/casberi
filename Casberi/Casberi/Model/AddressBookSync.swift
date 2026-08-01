import Foundation

/// The address book's iCloud mirror (2026-08-01).
///
/// **Why it exists.** `AddressBook`'s own header says a name the person typed
/// is their data, not bookkeeping — and yet it was the one piece of their data
/// that lived only in this device's UserDefaults while the corpus rode
/// CloudKit. Names died with the phone and never reached a second device. A
/// book you can lose isn't a ledger.
///
/// **Why key-value store and not SwiftData.** The book is tens of rows read
/// SYNCHRONOUSLY from every ingest path (`AddressBook.name(for:)` is consulted
/// by every counterparty resolver), so moving it into the model container
/// would put a store fetch on a hot path and add a `@Model` type to a schema
/// that has to stay CloudKit-lightweight-migratable. `NSUbiquitousKeyValueStore`
/// carries a small dictionary between a person's own devices with no schema at
/// all, which is exactly the shape of the problem.
///
/// **Consent.** Gated on the SAME `icloud.sync` toggle the corpus mirror uses,
/// which ships OFF. Nothing here leaves the device until the person turns that
/// on, and the Data tray's existing ADP note covers this copy too.
///
/// **Deletions.** The classic key-value-store failure is a deleted row coming
/// back from whichever device still holds it. So a removal writes a TOMBSTONE
/// — the key and when it went — and a merge compares stamps: the newest fact
/// about a key wins, whether that fact is an edit or a deletion. Tombstones
/// are pruned after 90 days, long past any device's plausible offline window.
final class AddressBookSync {
    static let shared = AddressBookSync()

    private static let entriesKey = "addressBook.entries.v1"
    private static let tombstonesKey = "addressBook.tombstones.v1"
    private static let localTombstonesKey = "wallet.addressBook.tombstones.local.v1"
    /// Long enough that a phone left in a drawer for a season still learns
    /// about a deletion; short enough that the payload can't grow forever.
    private static let tombstoneLifetime: TimeInterval = 90 * 24 * 3600

    private var tombstones: [String: Date]
    /// True while a remote merge is being applied, so the write it causes
    /// doesn't bounce straight back out as a push.
    private var applyingRemote = false
    private var attached = false

    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.localTombstonesKey)
            as? [String: Double] ?? [:]
        tombstones = raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    // MARK: - Availability

    /// Whether this device is signed into iCloud, resolved once. Re-read only
    /// when the system says it changed: `ubiquityIdentityToken` is a daemon
    /// round trip, and `enabled` is consulted from `push()`, which runs on
    /// every single book mutation.
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
    /// already up there. Deferred off `AddressBook`'s initializer — it calls
    /// back into `AddressBook.shared`, which during `init` does not exist yet.
    func attach() {
        guard !attached else { return }
        attached = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(remoteChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(iCloudAccountChanged),
            name: .NSUbiquityIdentityDidChange, object: nil)
        syncNow()
    }

    /// Signed in or out since launch — re-resolve rather than trusting the
    /// value cached at attach.
    @objc private func iCloudAccountChanged(_ note: Notification) {
        signedIntoICloud = FileManager.default.ubiquityIdentityToken != nil
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

    @objc private func remoteChanged(_ note: Notification) {
        guard enabled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.mergeRemote()
            self?.push()
        }
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
            forKey: Self.localTombstonesKey)
    }

    private func prune() {
        let floor = Date.now.addingTimeInterval(-Self.tombstoneLifetime)
        tombstones = tombstones.filter { $0.value > floor }
    }

    // MARK: - Push

    /// Writes this device's whole book and tombstone set up. Whole-blob rather
    /// than per-key: the book is tens of rows, and one value can't tear the way
    /// a hundred independent keys landing out of order can.
    /// No `synchronize()` here: the system schedules its own upload, Apple
    /// documents an explicit call as rarely necessary, and this runs on every
    /// book mutation. `syncNow` still forces one, because that IS the explicit
    /// exchange.
    func push() {
        guard enabled, !applyingRemote else { return }
        let store = NSUbiquitousKeyValueStore.default
        if let data = try? JSONEncoder().encode(AddressBook.shared.syncSnapshot) {
            store.set(data, forKey: Self.entriesKey)
        }
        store.set(tombstones.mapValues(\.timeIntervalSince1970), forKey: Self.tombstonesKey)
    }

    // MARK: - Merge

    /// Merges what's up there into what's here, newest fact per key wins.
    ///
    /// Four cases, and the deletion ones are the reason this isn't a plain
    /// dictionary union:
    ///   • remote has an entry we don't → take it, unless we deleted it LATER;
    ///   • both have it → the later `stamp` wins;
    ///   • remote deleted a key we still hold → drop it, if their deletion is
    ///     later than our copy's last edit;
    ///   • we deleted a key they still hold → our tombstone survives the merge
    ///     and the push re-asserts it.
    private func mergeRemote() {
        let store = NSUbiquitousKeyValueStore.default
        let remoteEntries: [String: AddressBook.Entry] = (store.data(forKey: Self.entriesKey))
            .flatMap { try? JSONDecoder().decode([String: AddressBook.Entry].self, from: $0) } ?? [:]
        let remoteTombstones: [String: Date] = (store.dictionary(forKey: Self.tombstonesKey)
            as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }

        var merged = AddressBook.shared.syncSnapshot
        var changed = false

        for (key, remote) in remoteEntries {
            // A deletion here that happened after their edit stands.
            if let deletedHere = tombstones[key], deletedHere >= remote.stamp { continue }
            guard let winner = AddressBook.newer(remote, than: merged[key]) else { continue }
            merged[key] = winner
            changed = true
        }

        for (key, deletedThere) in remoteTombstones {
            if let standing = merged[key], standing.stamp <= deletedThere {
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
        AddressBook.shared.applyMerged(merged)
        applyingRemote = false
    }
}
