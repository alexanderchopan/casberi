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
    /// The same fetch, exposed (2026-08-22, prd §441) — so a caller that needs
    /// BOTH this and the connections map pays for one walk instead of two.
    ///
    /// `AddressConnections` reads Wallet things, a strict subset of what this
    /// predicate already asks for, and the wallet manager builds both readings
    /// in one `onAppear`. Newest-first, `.live` at the boundary — the contract
    /// `summaries` depends on and every other caller inherits.
    static func relevant(in context: ModelContext) -> [Thing] { all(in: context) }

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

    /// What one address's history amounts to — how much, and how recently
    /// (2026-08-22, prd §440).
    ///
    /// The count alone was the row's whole relationship fact, and it cannot
    /// separate a correspondent from a stranger: "12 together" reads the same
    /// whether the last of those twelve was on Tuesday or in 2023. The date is
    /// the half that makes a book of forty a RECORD rather than a list of
    /// strings, and it costs nothing — `all(in:)` is already sorted
    /// newest-first, so the first thing seen for a key IS its most recent.
    ///
    /// Deliberately no amount, no direction and no rate. §435's ruling is that
    /// this screen states relationships and never money, and §295's is that it
    /// states facts and never analysis — "how much you have dealt and when you
    /// last did" is both of those and nothing more.
    struct Summary: Equatable {
        var count: Int
        /// The newest landed thing for this address. Never nil for a summary
        /// that exists, since a summary is only created by seeing one.
        var lastAt: Date
    }

    /// Every address's summary in a single pass — what the manager's "Most
    /// active" sort orders on and what each row states. One walk over one
    /// fetch, rather than the per-address filter `history` does, because the
    /// list needs all of them at once.
    static func summaries(in context: ModelContext) -> [String: Summary] {
        summaries(from: all(in: context))
    }

    /// The same summary from things already fetched — see `relevant(in:)`.
    /// **Requires newest-first**, which is the whole reason the insert-or-bump
    /// below is correct; handed an arbitrary order it would stamp whichever
    /// row happened to come first as the latest.
    static func summaries(from things: [Thing]) -> [String: Summary] {
        var out: [String: Summary] = [:]
        // Newest-first, so the FIRST sighting of a key carries its latest
        // date; later ones only add to the count. Written as an insert-or-bump
        // rather than a max() for exactly that reason — the ordering is the
        // fetch's, and re-deriving it per row would walk the same array again.
        for thing in things {
            guard let key = key(of: thing) else { continue }
            if out[key] == nil {
                out[key] = Summary(count: 1, lastAt: thing.capturedAt)
            } else {
                out[key]?.count += 1
            }
        }
        return out
    }

    /// The count alone, for callers that only ever wanted the number.
    static func counts(in context: ModelContext) -> [String: Int] {
        summaries(in: context).mapValues(\.count)
    }
}
