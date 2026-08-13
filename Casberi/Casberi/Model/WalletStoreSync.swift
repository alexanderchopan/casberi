import Foundation

/// The watch list's iCloud mirror (2026-08-13, prd §372).
///
/// **Why it exists.** §266 mirrored the address book and named this gap in the
/// same breath: `WalletStore.addresses` is equally the person's own data and
/// did NOT mirror, so a second device received a wallet's NAME but not its
/// WATCH. The result reads as a bug — your iPad shows "Mom" in the book, with
/// no wallet behind it, no balance, no history, and no explanation.
///
/// Everything about HOW it syncs lives in `KeyValueMirror`, which was extracted
/// from `AddressBookSync` for this. What is stated here is only what belongs to
/// the watch list: its own three storage keys, and the fact that its merge rule
/// and its apply are the store's (`WalletStore.newer` / `applyMerged`), because
/// an ordered, capped list merges differently from a book of names.
///
/// **The cap survives the merge by grandfathering, never by evicting** — see
/// `WalletStore.applyMerged`, where that ruling is written down. Two devices
/// each watching five means ten, and nothing is thrown away.
///
/// **What this deliberately does NOT carry: ORDER.** The person's ordering is
/// local. A merge keeps this device's order for wallets it already had and
/// appends arrivals, so re-ordering on the iPad doesn't reshuffle the phone.
/// Syncing order would need an ordering CRDT for a list of five rows, and the
/// failure it prevents (your wallets in a different order on your other device)
/// is one the person can see and fix in a drag.
final class WalletStoreSync {
    static let shared = WalletStoreSync()

    private let mirror = KeyValueMirror<WalletStore.WatchedAddress>(
        entriesKey: "walletStore.addresses.v1",
        tombstonesKey: "walletStore.tombstones.v1",
        localTombstonesKey: "wallet.addresses.tombstones.local.v1",
        snapshot: { WalletStore.shared.syncSnapshot },
        newer: { WalletStore.newer($0, than: $1) },
        apply: { WalletStore.shared.applyMerged($0) })

    private init() {}

    /// Starts listening and merges whatever is already up there. Deferred off
    /// `WalletStore`'s initializer — the mirror calls back into
    /// `WalletStore.shared`, which during `init` does not exist yet.
    func attach() { mirror.attach() }

    /// Pulls, merges, and pushes. Called when the person flips iCloud sync on.
    func syncNow() { mirror.syncNow() }

    /// Writes this device's whole watch list up — called from `addresses`'
    /// `didSet`, the one choke point every mutation passes through.
    func push() { mirror.push() }

    /// Records that a wallet was unwatched here, so whichever device still
    /// holds it doesn't push it straight back.
    func noteRemoval(_ key: String) { mirror.noteRemoval(key) }
}

extension WalletStore.WatchedAddress: KeyValueMirrored {
    /// `.distantPast` for a row written before the field existed — the honest
    /// floor, so a device carrying a real stamp wins.
    var mirrorStamp: Date { stamp }
}
