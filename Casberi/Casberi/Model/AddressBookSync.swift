import Foundation

/// The address book's iCloud mirror (2026-08-01).
///
/// **Why it exists.** `AddressBook`'s own header says a name the person typed
/// is their data, not bookkeeping — and yet it was the one piece of their data
/// that lived only in this device's UserDefaults while the corpus rode
/// CloudKit. Names died with the phone and never reached a second device. A
/// book you can lose isn't a ledger.
///
/// **The engine moved out on 2026-08-13** (prd §372). Every rule this file used
/// to spell — the `icloud.sync` gate, the whole-blob push, tombstones with a
/// 90-day life, newest-fact-per-key merging — now lives in `KeyValueMirror`,
/// which `WalletStoreSync` uses for the watch list. What stays here is the part
/// that is genuinely the BOOK'S: which storage keys it owns, what a snapshot
/// is, and `AddressBook.newer`'s rule that a winning entry keeps the earliest
/// `addedAt` either side knows.
///
/// **The three key names are load-bearing and must never change.** They are
/// what every already-synced device is reading and writing today; deriving them
/// from a type name during the extraction would have orphaned every book in
/// iCloud at once, with nothing failing and nothing to see.
final class AddressBookSync {
    static let shared = AddressBookSync()

    private let mirror = KeyValueMirror<AddressBook.Entry>(
        entriesKey: "addressBook.entries.v1",
        tombstonesKey: "addressBook.tombstones.v1",
        localTombstonesKey: "wallet.addressBook.tombstones.local.v1",
        snapshot: { AddressBook.shared.syncSnapshot },
        newer: { AddressBook.newer($0, than: $1) },
        apply: { AddressBook.shared.applyMerged($0) })

    private init() {}

    /// Starts listening and merges whatever is already up there. Deferred off
    /// `AddressBook`'s initializer — the mirror calls back into
    /// `AddressBook.shared`, which during `init` does not exist yet.
    func attach() { mirror.attach() }

    /// Pulls, merges, and pushes. Called when the person flips iCloud sync on.
    func syncNow() { mirror.syncNow() }

    /// Writes this device's whole book up — called on every book mutation.
    func push() { mirror.push() }

    /// Records that a key was deleted here, BEFORE the entry goes, so the push
    /// the removal triggers already carries the tombstone with it.
    func noteRemoval(_ key: String) { mirror.noteRemoval(key) }
}

extension AddressBook.Entry: KeyValueMirrored {
    /// The book's merge stamp is `stamp` — `updatedAt`, falling back to
    /// `addedAt` for entries written before that field existed, which is the
    /// honest floor: whatever the other device has that carries a real stamp
    /// is newer.
    var mirrorStamp: Date { stamp }
}
