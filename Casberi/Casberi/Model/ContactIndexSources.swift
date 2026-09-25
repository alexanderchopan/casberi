import Foundation
import SwiftData

/// The stores the contact index is built FROM, and the verified links they
/// already imply (prd §916, `docs/addresses-spec.md` sections 2.4 and 3).
///
/// This is the impure half of `ContactIndex`: it reads the wallet book, the
/// social watch lists, the corpus's contacts and GitHub people, the feed
/// follows, and the names `AddressNames` has verified — and hands
/// `ContactIndex.build` a list of seeds. Nothing here is persisted; the one
/// thing written is a VERIFIED edge into the ledger, which is re-derivable
/// and recorded only so the mirror can carry it to a device without the seat.
///
/// Every read is main-actor because every store is (`IngestSupport` rule: a
/// function handed the main `ModelContext` is `@MainActor`).
@MainActor
enum ContactIndexSources {

    /// The contacts as of the last `rebuild()`. Empty until one has run —
    /// and it runs on the probe and on a foreground sweep (step 3), never
    /// from a body (§628).
    /// One snapshot, assigned whole on the main actor and READ from anywhere:
    /// `WalletIngest.knownLabel` is a synchronous, nonisolated lookup the
    /// sheet makes, so the reader takes the pair together and never indexes
    /// one half against the other's stale copy.
    nonisolated(unsafe) private static var snapshot: (contacts: [Contact], byKey: [String: Int]) = ([], [:])
    static var contacts: [Contact] { snapshot.contacts }

    // MARK: - Seeds

    static func seeds(context: ModelContext) -> [ContactIndex.Seed] {
        var out: [ContactIndex.Seed] = []

        // The wallet book: every named or watched address, with the kind the
        // chain check found (§294). A name the person TYPED ranks above every
        // display name; an auto-name (`…44b1`) is not a name at all.
        for entry in AddressBook.shared.all {
            let typed = !WalletStore.isAutoName(entry.name, for: entry.address)
            let kind: Contact.Kind
            switch entry.kind {
            case .contract:     kind = .contract
            case .safe:         kind = .safe
            case .smartAccount: kind = .smartAccount
            case .key:          kind = .key
            default:            kind = .person
            }
            out.append(.init(Identity.make(.wallet, entry.address),
                             name: typed ? entry.name : nil, typed: typed, kind: kind,
                             avatar: entry.avatarURL, since: entry.addedAt))
        }

        for account in FarcasterStore.shared.accounts {
            out.append(.init(Identity.make(.farcaster, account.username),
                             name: account.displayName, avatar: account.avatarURL))
        }
        for account in BlueskyStore.shared.accounts {
            out.append(.init(Identity.make(.bluesky, account.handle),
                             name: account.displayName, avatar: account.avatarURL))
        }
        for account in NostrStore.shared.accounts where !account.pubkeyHex.isEmpty {
            out.append(.init(Identity.make(.nostr, account.pubkeyHex),
                             name: account.displayName, avatar: account.avatarURL))
        }

        // Apple contacts: things of kind `.contact`. The card's own name is
        // TYPED — it is the person's book — and a card with a company and no
        // person name is an organization.
        let contactsDescriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Contacts" })
        for thing in (try? context.fetch(contactsDescriptor)) ?? [] {
            guard thing.kind == .contact, let ref = thing.sourceRef else { continue }
            let facts = thing.facts.compactMap(ThingFact.init(encoded:))
            let hasCompany = facts.contains { $0.label == "Company" }
            let company = facts.first { $0.label == "Company" }?.value
            let isOrganization = hasCompany && company == thing.title
            out.append(.init(Identity.make(.contact, ref), name: thing.title, typed: true,
                             kind: isOrganization ? .organization : .person,
                             since: thing.capturedAt))
        }

        // GitHub people you watch (§519): `.link` things under the person ref.
        let githubDescriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "GitHub" })
        for thing in (try? context.fetch(githubDescriptor)) ?? [] {
            guard let ref = thing.sourceRef, let login = GitHubLinks.personLogin(fromRef: ref) else { continue }
            out.append(.init(Identity.make(.github, login), name: thing.title,
                             avatar: thing.authorAvatarURL, since: thing.capturedAt))
        }

        // What the person saved by hand (`ContactBook`, section 2.6): a
        // sender, a login, a poster, a feed — each a TYPED name, so it names
        // the contact over any seat's display name.
        for saved in ContactBook.shared.all {
            guard let identity = Identity.parse(key: saved.id) else { continue }
            out.append(.init(identity, name: saved.name, typed: true,
                             kind: identity.kind == .feed ? .publication : .person,
                             since: saved.addedAt))
        }

        // Publications: a row is an address that is not a person (user,
        // 2026-09-24). Every feed follow, keyed on its feed URL.
        for feed in RSSStore.shared.feeds {
            out.append(.init(Identity.make(.feed, feed.url), name: feed.displayName, kind: .publication))
        }
        for store in [FeedFollowStore.substack, .reddit, .youtube, .podcasts, .telegram] {
            for entry in store.entries where !entry.feedURL.isEmpty {
                out.append(.init(Identity.make(.feed, entry.feedURL), name: entry.displayName, kind: .publication))
            }
        }
        return out
    }

    // MARK: - Verified links the stores already hold

    /// Tier-1 edges nothing had to ask for: a Farcaster account's verified
    /// addresses (Snapchain, §85's shape), and every name `AddressNames`
    /// stores — each already forward-verified before it was written (§599,
    /// §916). Recorded into the ledger so the mirror carries them.
    static func discoverVerified() -> [ContactLink] {
        var out: [ContactLink] = []
        for account in FarcasterStore.shared.accounts {
            let handle = Identity.key(.farcaster, account.username)
            for address in account.verifiedAddresses {
                out.append(ContactLink(handle, Identity.key(.wallet, address),
                                       tier: .verified, source: "farcaster.verifications"))
            }
        }
        for (address, record) in AddressNames.shared.allRecords {
            let wallet = Identity.key(.wallet, address)
            for entry in record.names {
                guard let kind = Identity.Kind.classify(primaryName: entry.name) else { continue }
                out.append(ContactLink(wallet, Identity.key(kind, entry.name),
                                       tier: .verified,
                                       source: kind == .farcaster || kind.isNameService ? "web3.bio" : "ens"))
            }
        }
        return out
    }

    // MARK: - Rebuild

    /// The contact cards as `ContactSuggest` reads them: the name, the
    /// "Service: handle" lines, the emails — never drawn, never stored here.
    static func cards(context: ModelContext) -> [ContactSuggest.Card] {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Contacts" })
        return ((try? context.fetch(descriptor)) ?? []).compactMap { thing in
            guard thing.kind == .contact, let ref = thing.sourceRef else { return nil }
            let facts = thing.facts.compactMap(ThingFact.init(encoded:))
            return ContactSuggest.Card(
                key: Identity.key(.contact, ref), name: thing.title,
                lines: (thing.enrichedText ?? "").split(separator: "\n").map(String.init),
                emails: facts.filter { $0.action == .mail }.map(\.value))
        }
    }

    @discardableResult
    static func rebuild(context: ModelContext) -> [Contact] {
        let store = ContactLinksStore.shared
        let seeds = seeds(context: context)
        let cards = cards(context: context)
        for link in discoverVerified() { store.record(link) }
        for link in ContactSuggest.stated(cards: cards, seeds: seeds) { store.record(link) }
        for link in ContactSuggest.suggested(cards: cards, seeds: seeds) { store.record(link) }
        let built = ContactIndex.build(seeds: seeds, links: store.ledger.all)
        var byKey: [String: Int] = [:]
        for (i, contact) in built.enumerated() {
            for identity in contact.identities { byKey[identity.key] = i }
        }
        snapshot = (built, byKey)
        return built
    }

    // MARK: - Yourself

    /// Whether a contact IS the person — it carries a social account marked
    /// `mine`, or anything the join verified onto one (your Farcaster
    /// account's verified wallets ride with it). The Addresses list is the
    /// parties behind your accounts, and you are not one of them: Manage
    /// holds your accounts, and the demo showed "you", "You" and "You" as
    /// three strangers (user, 2026-09-25). The index still BUILDS the
    /// contact, so a transfer between your own wallets keeps its name.
    static func isYours(_ contact: Contact) -> Bool {
        contact.identities.contains { yourKeys.contains($0.key) }
    }

    /// The keys of every account marked yours, read live from the stores.
    private static var yourKeys: Set<String> {
        var out = Set<String>()
        for a in FarcasterStore.shared.accounts where a.mine {
            out.insert(Identity.make(.farcaster, a.username).key)
        }
        for a in BlueskyStore.shared.accounts where a.mine {
            out.insert(Identity.make(.bluesky, a.handle).key)
        }
        for a in NostrStore.shared.accounts where a.mine && !a.pubkeyHex.isEmpty {
            out.insert(Identity.make(.nostr, a.pubkeyHex).key)
        }
        return out
    }

    // MARK: - The seam (section 2.5)

    /// The contact a thing is from or about, or nil when the app holds none.
    /// Reads the LAST rebuild; it never fetches.
    nonisolated static func contact(for thing: Thing) -> Contact? {
        let keys = ContactIndex.keys(
            source: thing.source, kind: thing.kind.rawValue, sourceRef: thing.sourceRef,
            authorHandle: thing.authorHandle, walletAddress: thing.walletAddress,
            counterpartyAddress: thing.counterpartyAddress, authorEmail: thing.authorEmail,
            isNotification: thing.sourceRef?.hasPrefix("gh:notif:") ?? false)
        for key in keys { if let hit = contact(forKey: key) { return hit } }
        return nil
    }

    nonisolated static func contact(forKey key: String) -> Contact? {
        let snap = snapshot
        guard let i = snap.byKey[key], snap.contacts.indices.contains(i),
              snap.contacts[i].has(key) else { return nil }
        return snap.contacts[i]
    }

    #if DEBUG
    /// `-addressesProbe YES` — the index, rebuilt and printed: the count, the
    /// ledger by tier, then one line per contact with every identity and how
    /// it joined. Never a phone number or an email address: an email
    /// identity prints its kind and the mailbox's host only, a contact its
    /// name. One line per fact (the `-todayProbe` truncation lesson).
    static func probe(context: ModelContext) -> [String] {
        let built = rebuild(context: context)
        let ledger = ContactLinksStore.shared.ledger.all
        var lines = ["\(built.count) contacts | seeds: \(seeds(context: context).count) | links: v=\(ledger.filter { $0.tier == .verified }.count) s=\(ledger.filter { $0.tier == .suggested }.count) st=\(ledger.filter { $0.tier == .stated }.count) declined=\(ledger.filter(\.declined).count)"]
        let linked = built.filter { $0.identities.count > 1 }
        lines.append("linked: \(linked.count) of \(built.count) contacts carry more than one identity")
        // Yourself, built and then kept off the list (`isYours`).
        let yours = built.filter(isYours)
        lines.append("yours: \(yours.count) hidden from the list | \(yours.map(\.name).joined(separator: ", "))")
        for contact in built {
            let ids = contact.identities.map { id -> String in
                let how = id.tier.map { " (\($0.rawValue)\(id.source == "you" ? ", you" : ""))" } ?? ""
                switch id.kind {
                case .email:   return "email@\(id.body.split(separator: "@").last ?? "")\(how)"
                case .contact: return "contact\(how)"
                default:       return "\(id.kind.rawValue) \(id.label)\(how)"
                }
            }
            lines.append("contact| \(contact.name) | \(contact.kind.rawValue) | \(ids.joined(separator: " · "))")
        }
        return lines
    }
    #endif
}
