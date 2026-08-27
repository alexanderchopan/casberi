import Foundation
import SwiftData

/// THE OFF-CHAIN HALF OF THE BOOK (2026-08-27, prd §498).
///
/// The address book is the app's one PEOPLE surface now — user ruling, the
/// same session that unified Wallet's and vibenet's ledgers (§496): *"maybe we
/// need 'contacts' for literal apple contacts? and 'social' for social
/// profiles"*. This is where those two populations come from.
///
/// **They are EPHEMERAL, and that is the whole design.** Nothing here is
/// written to `AddressBook`, persisted, or synced to iCloud. Each row is an
/// `AddressBook.Entry` VALUE built for display from a source that already
/// holds it — the corpus for contacts, the watch stores for social — so:
///
///   · the book needs no import step, no picker, and no permission of its own;
///     a contact you already connected is simply there
///   · unwatching an account or disconnecting Contacts removes the row by
///     itself, with no reconcile pass that could get it wrong
///   · the sync mirror never carries a phone number or a handle, which is the
///     half of §169's crypto-only ruling worth keeping — that ledger is
///     addresses, and it stays addresses
///   · every WRITE door is shut by construction rather than by a rule someone
///     has to remember: `AddressBook.entry(for:)` answers nil for these keys,
///     so `isInBook` is false and rename/note/group/remove are already gated
///
/// **The bulk-import rule still stands** (`SocialFollows`' §87 picker ruling,
/// restated in the §498 spec): nothing here WRITES the book, so following a
/// forty-person starter pack still cannot dump forty entries into somebody's
/// ledger. What it can do is show you the accounts you already chose to watch.
///
/// **Twitch is not here yet, and that is a fact about the roster rather than a
/// decision.** `SocialRoomSource.accounts(for:)` is the one dispatch (§489) and
/// only Bluesky, Farcaster and Nostr carry a `socialAccounts` roster; Twitch
/// watches channels through a store with no such shape. It joins the day it
/// grows one, and reading it a second way here is exactly the per-bridge fork
/// §489 spent a pass deleting.
@MainActor
enum AddressBookPeople {

    /// How many of each population a book row list will hold. A bound rather
    /// than a paging story: this list is read top-to-bottom by a person, the
    /// scrubber gives it twenty-six aiming points, and a phone book of two
    /// thousand contacts is a different screen than the one this is.
    ///
    /// Stated rather than silent — `AddressBookScreen` says "showing the first
    /// N" when the cap bites, because a list that quietly stops is §307's
    /// silent truncation, which this codebase has now paid for in five rooms.
    static let contactCap = 500

    /// The key an ephemeral row stands under. Namespaced so it can never
    /// collide with a real address (`AddressBook.key(for:)` leaves a non-hex
    /// string exactly as it is) and so `looksLikeAddress` refuses it, which
    /// keeps it out of every paste and watch path.
    static func contactKey(_ ref: String) -> String { "contact:" + ref }
    static func socialKey(source: String, handle: String) -> String {
        source.lowercased() + ":" + handle.lowercased()
    }

    /// Everybody in the phone's address book that the Contacts bridge landed.
    ///
    /// Scoped by SOURCE in the predicate — a string-equality `#Predicate` is
    /// the shape SwiftData can push down to SQL, unlike the `.contains` on a
    /// transformable array that traps at runtime (CLAUDE.md's own gotcha).
    /// Sorted by title in the fetch so the cap takes a stable set rather than
    /// whatever five hundred rows the store happened to hand back.
    static func contacts(in context: ModelContext) -> [AddressBook.Entry] {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Contacts" },
            sortBy: [SortDescriptor(\.title, order: .forward)])
        descriptor.fetchLimit = contactCap
        guard let things = try? context.fetch(descriptor) else { return [] }
        return things.compactMap { thing in
            // Liveness per corollary 6: these are live models straight from a
            // fetch, but the array is handed onward, so it is filtered at the
            // boundary rather than on a promise that readers re-check.
            guard thing.isLive else { return nil }
            let name = thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let ref = thing.sourceRef ?? thing.id.uuidString
            return AddressBook.Entry(
                address: contactKey(ref),
                name: name,
                // The corpus row's own capture date, so `.recent` orders these
                // beside real entries rather than piling them all on today.
                addedAt: thing.capturedAt,
                kind: .contact,
                provenance: String(localized: "Contacts"))
        }
    }

    /// Every social profile you watch, across the sources that carry a roster.
    ///
    /// `SocialRoomSource.accounts(for:)` is the ONE dispatch — the roster
    /// ternary §489 deleted is exactly the bug that would come back here: read
    /// one store for every source and the Social chip fills with the wrong
    /// network's people while looking perfectly correct.
    static func social() -> [AddressBook.Entry] {
        // Catalog order rather than `Set`'s, so the rows do not reshuffle
        // between body passes — the non-total-order failure this book's own
        // harness exists to catch.
        let sources = SocialThread.sources.sorted()
        return sources.flatMap { source in
            SocialRoomSource.accounts(for: source).map { account in
                AddressBook.Entry(
                    address: socialKey(source: source, handle: account.key),
                    name: account.title,
                    // No date to be had — a watch list records no when — so
                    // these sort by name and sit at the bottom of `.recent`
                    // rather than claiming they were added today.
                    addedAt: .distantPast,
                    kind: .social,
                    provenance: source + " · " + account.key)
            }
        }
    }

    /// Both populations, for the book's list. Deduped by key against whatever
    /// the real book already holds — the ledger's own entry always wins, so an
    /// address you have named never gets shadowed by an ephemeral row.
    ///
    /// It takes the book's keys rather than reading `AddressBook.shared`
    /// itself, so this stays a pure function of what it is handed and the
    /// caller keeps its single walk.
    static func rows(in context: ModelContext,
                     excluding bookKeys: Set<String>) -> [AddressBook.Entry] {
        (contacts(in: context) + social()).filter { !bookKeys.contains($0.id) }
    }
}
