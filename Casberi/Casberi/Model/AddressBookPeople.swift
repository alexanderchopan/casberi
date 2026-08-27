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
/// **Twitch joins by a DIFFERENT ROAD, and the road is forced** (user, 2026-08-27:
/// *"yes lets add twitch"*). `SocialRoomSource.accounts(for:)` is §489's one
/// dispatch for sources that keep a watch list, and Twitch keeps none — its
/// follow graph lives on Twitch's own servers and is read fresh every sweep
/// (`streams/followed`), so there is no local roster to ask.
///
/// What makes the corpus a legitimate substitute HERE and nowhere else: that
/// endpoint returns only channels you already follow, so every Twitch row in
/// the corpus is by construction a channel you chose. The distinct
/// `authorHandle`s over that source ARE the follow list.
///
/// **This is deliberately not generalised to every source carrying an
/// `authorHandle`.** X, Instagram and TikTok stamp one too, and folding them in
/// would fill the book with hundreds of people whose post you merely saw —
/// which is the opposite of what a book is for. A relationship you chose is the
/// bar; Twitch clears it because following is what put the row there, and a
/// liked stranger's post does not.
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

    /// **Handles are carried WHOLE** (user ruling, 2026-08-27, on the merged
    /// card). They were tail-truncated so a 64-character Nostr pubkey would
    /// not run off a row — right for a ROW, wrong for the card, where each
    /// account is a block with its own Copy: a value you can copy and cannot
    /// read is the one shape a copyable field must not take. The card wraps
    /// the full value; nothing prints these on a row any more, since a
    /// person's row carries no subline at all.

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
                    // The SOURCE alone, no handle — the row no longer prints a
                    // subline (§498 polish).
                    provenance: source,
                    // WHERE THIS PERSON HAS BEEN MET, in the field that
                    // already means exactly that. A social network is a
                    // network the way vibenet is one, so `merged` below can
                    // union them with no second concept, and the face draws a
                    // dot per entry with no second rule.
                    networks: [source],
                    avatarURL: account.avatarURL,
                    accounts: [source + " · " + account.key])
            }
        }
    }

    /// The channels you follow on Twitch, read off the corpus — see this
    /// file's header for why the corpus is the roster here and why that does
    /// NOT generalise to every source stamping an `authorHandle`.
    ///
    /// Distinct by handle, keeping the NEWEST row's date, so a channel that
    /// streams weekly sorts by its last stream rather than its first. Capped
    /// like the contact walk, and for the same reason: this is a list a person
    /// reads, not a page of results.
    static func twitch(in context: ModelContext) -> [AddressBook.Entry] {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Twitch" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = twitchScan
        guard let things = try? context.fetch(descriptor) else { return [] }
        var seen: Set<String> = []
        var out: [AddressBook.Entry] = []
        for thing in things {
            // Liveness at the boundary (corollary 6) — the array is handed
            // onward, so it is filtered here rather than on a promise.
            guard thing.isLive,
                  let handle = thing.authorHandle?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !handle.isEmpty,
                  seen.insert(handle.lowercased()).inserted
            else { continue }
            out.append(AddressBook.Entry(
                address: socialKey(source: "Twitch", handle: handle),
                name: handle,
                // Newest first out of the fetch, so the first row seen for a
                // handle carries its most recent stream.
                addedAt: thing.capturedAt,
                kind: .social,
                provenance: "Twitch",
                networks: ["Twitch"],
                accounts: ["Twitch · " + handle]))
        }
        return out
    }

    /// How many Twitch rows are scanned to build the channel list. A stream
    /// lands one row per broadcast, so a heavy follower accumulates rows fast
    /// — this bounds the walk without bounding the CHANNELS, which are what
    /// the list is actually made of.
    static let twitchScan = 400

    /// Every population, for the book's list. Deduped by key against whatever
    /// the real book already holds — the ledger's own entry always wins, so an
    /// address you have named never gets shadowed by an ephemeral row.
    ///
    /// It takes the book's keys rather than reading `AddressBook.shared`
    /// itself, so this stays a pure function of what it is handed and the
    /// caller keeps its single walk.
    static func rows(in context: ModelContext,
                     excluding bookKeys: Set<String>) -> [AddressBook.Entry] {
        merged(contacts(in: context) + social() + twitch(in: context))
            .filter { !bookKeys.contains($0.id) }
    }

    /// The label an address stands under when a person has several
    /// identities. "Vibenet" where that is what it is, so the devnet warning
    /// survives into the merged card — the one place it has to, since this is
    /// the block somebody copies from.
    static func addressLabel(for entry: AddressBook.Entry) -> String {
        entry.networkBadge ?? String(localized: "Address")
    }

    /// ONE PERSON, EVERY IDENTITY THEY HAVE (user ruling, 2026-08-27: *"if i
    /// am on farcaster bluesky and wallet those are all addresses named
    /// Alex"*).
    ///
    /// `merged` above folds a person's SOCIAL accounts together; this folds
    /// those into the book's own named entries, so an address you called
    /// "Alex" and the Bluesky and Farcaster accounts of the same name become
    /// one row with three blocks on its card rather than three rows.
    ///
    /// **The BOOK entry is always the base**, never the ephemeral one, and
    /// that is what keeps the merge safe: the row that stands is the persisted
    /// one, with its address, note, groups, kind and dates intact, so nothing
    /// a person typed can be shadowed or lost by a display-name match. The
    /// ephemeral rows only ever ADD — accounts to the list, and an avatar if
    /// the book entry had none.
    ///
    /// **It is a heuristic and it is bounded like one.** A display name is the
    /// strongest signal two identities are one person and it is what Apple's
    /// own contact linking uses, but it can be wrong — so an auto-named row is
    /// excluded (`…44b1` is not a name anybody chose, and matching on it would
    /// merge strangers), and the base entry keeps everything, so being wrong
    /// costs an extra block on a card rather than a lost row.
    static func fold(book: [AddressBook.Entry],
                     people: [AddressBook.Entry]) -> [AddressBook.Entry] {
        var byName: [String: Int] = [:]      // folded name → index in `out`
        var out = book
        for (index, entry) in book.enumerated() {
            // Its own address is the FIRST block on its card — a person's
            // wallet address is one of their identities, listed beside the
            // others rather than above them.
            out[index].accounts = [addressLabel(for: entry) + " · " + entry.short]
            guard !WalletStore.isAutoName(entry.name, for: entry.address) else { continue }
            let key = entry.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if byName[key] == nil { byName[key] = index }
        }
        var unmatched: [AddressBook.Entry] = []
        for person in people {
            let key = person.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // Contacts never fold into an address, for `merged`'s own stated
            // reason: claiming your phone's "Alex" IS this wallet is a bigger
            // assertion than a name match can carry.
            guard person.kind == .social, let index = byName[key] else {
                unmatched.append(person)
                continue
            }
            for line in person.accounts ?? [] where !(out[index].accounts ?? []).contains(line) {
                out[index].accounts = (out[index].accounts ?? []) + [line]
            }
            if out[index].avatarURL == nil { out[index].avatarURL = person.avatarURL }
        }
        return out + unmatched
    }

    /// ONE PERSON, ONE ROW (user ruling, 2026-08-27, seeing three rows named
    /// "You" and two named "Uma": *"what do we do when we have multiple for
    /// same person like Uma and You. i think it should be one entry"*).
    ///
    /// Somebody you follow on Bluesky and Farcaster is one person, and a book
    /// that lists them twice is a book that has not understood what it is for.
    /// Their accounts union onto a single entry, which is also what let the
    /// source badge go: a badge existed to tell those duplicate rows apart,
    /// and once there are no duplicate rows there is nothing for it to say.
    ///
    /// **Merged by display NAME, and only within SOCIAL.** The name is the
    /// strongest signal two accounts are one person and it is the same one
    /// Apple's own contacts linking uses — but it is a heuristic, so it is
    /// spent only where being wrong is cheap. A contact is deliberately NOT
    /// merged into a social profile of the same name: that claims your phone's
    /// "Uma Patel" is this Bluesky account, which is a bigger assertion about
    /// somebody's identity than a display-name match can carry, and being
    /// wrong there hides a real person's row behind a stranger's.
    ///
    /// The FIRST entry seen wins the row (source order is stable — sorted
    /// sources, then Twitch), so the identity a row stands under does not
    /// change between body passes. An avatar fills in from whichever account
    /// has one, since a person with a picture anywhere should show it.
    static func merged(_ entries: [AddressBook.Entry]) -> [AddressBook.Entry] {
        var order: [String] = []
        var byName: [String: AddressBook.Entry] = [:]
        for entry in entries {
            // Contacts pass through untouched — see the ruling above.
            guard entry.kind == .social else {
                order.append(entry.id)
                byName[entry.id] = entry
                continue
            }
            let key = "social:" + entry.name.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard var standing = byName[key] else {
                order.append(key)
                byName[key] = entry
                continue
            }
            for tag in entry.networks ?? [] where !(standing.networks ?? []).contains(tag) {
                standing.networks = (standing.networks ?? []) + [tag]
            }
            for line in entry.accounts ?? [] where !(standing.accounts ?? []).contains(line) {
                standing.accounts = (standing.accounts ?? []) + [line]
            }
            if standing.avatarURL == nil { standing.avatarURL = entry.avatarURL }
            // The newest sighting dates the row — a person you saw on Twitch
            // today and Bluesky in March was seen today.
            standing.addedAt = max(standing.addedAt, entry.addedAt)
            byName[key] = standing
        }
        return order.compactMap { byName[$0] }
    }
}
