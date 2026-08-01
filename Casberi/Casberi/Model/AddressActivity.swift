import Foundation
import SwiftData

/// What the corpus already knows about an address — ONE definition of
/// "activity", read two ways (2026-08-01).
///
/// It exists because there were two definitions and they disagreed. The
/// address card's "Your history together · N" counted Wallet counterparty
/// transactions plus the Peer fills and Privacy Pools deposits a watched
/// wallet made (the §207 seats, which ride the watched wallets and have no
/// home of their own). The Wallet manager's "Most active" sort counted only
/// the first kind — the §207 addition never propagated back — so a wallet
/// whose activity is mostly Peer fills sorted as inactive while its own card
/// said "· 40". Two readings of one word is a bug that can only be fixed by
/// deleting one of them, so `belongs(_:)` below is now the only answer to
/// "does this thing belong to that address", and both callers ask it.
enum AddressActivity {

    /// Which address-book entry a thing belongs to, or nil for one that
    /// belongs to none. Two kinds of belonging, and the source decides which:
    ///   • a **Wallet** transaction where this address was the COUNTERPARTY —
    ///     someone you transacted with (a wallet's own transactions are not
    ///     history with itself, so the owner is deliberately not read here);
    ///   • a **Peer** fill or **Privacy Pools** deposit MADE BY this address,
    ///     stamped by both bridges as `walletAddress`.
    static func key(of thing: Thing) -> String? {
        if thing.source == "Wallet" {
            guard let counterparty = thing.counterpartyAddress, !counterparty.isEmpty
            else { return nil }
            return AddressBook.key(for: counterparty)
        }
        guard let owner = thing.walletAddress, !owner.isEmpty else { return nil }
        return AddressBook.key(for: owner)
    }

    /// Every thing carrying activity for any address, newest first — the one
    /// fetch both readings start from. Filtered `.live` AT THE BOUNDARY, per
    /// the corollary-4 rule: this hands an array onward, so the guarantee is
    /// made here rather than promised to downstream readers.
    private static func all(in context: ModelContext) -> [Thing] {
        let fetched = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate {
                $0.source == "Wallet" || $0.source == "Peer" || $0.source == "Privacy Pools"
            },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
        return fetched.live
    }

    /// Everything the corpus knows about ONE address, newest first.
    static func history(for address: String, in context: ModelContext) -> [Thing] {
        let wanted = AddressBook.key(for: address)
        return all(in: context).filter { key(of: $0) == wanted }
    }

    /// Every address's count in a single pass — what the manager's "Most
    /// active" sort orders on and what each row states. One walk over one
    /// fetch, rather than the per-address filter `history` does, because the
    /// list needs all of them at once.
    static func counts(in context: ModelContext) -> [String: Int] {
        var counts: [String: Int] = [:]
        for thing in all(in: context) {
            guard let key = key(of: thing) else { continue }
            counts[key, default: 0] += 1
        }
        return counts
    }
}
