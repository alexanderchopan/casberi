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

    /// A card key back to the card's OWN ref (`contact:<CNContact id>`, case
    /// kept): keys fold case, and the corpus stores the ref as Contacts
    /// spells it, so a face or a fact that wants the card's thing needs the
    /// original spelling. Written by `seeds`, read from anywhere.
    nonisolated(unsafe) private static var cardRefs: [String: String] = [:]
    nonisolated static func cardRef(forKey key: String) -> String? { cardRefs[key] }

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
                             avatar: entry.avatarURL, since: entry.addedAt,
                             keywords: [entry.note ?? ""]))
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
        var refs: [String: String] = [:]
        defer { cardRefs = refs }
        for thing in (try? context.fetch(contactsDescriptor)) ?? [] {
            guard thing.kind == .contact, let ref = thing.sourceRef else { continue }
            refs[Identity.key(.contact, ref)] = ref
            let facts = thing.facts.compactMap(ThingFact.init(encoded:))
            let hasCompany = facts.contains { $0.label == "Company" }
            let company = facts.first { $0.label == "Company" }?.value
            let role = facts.first { $0.label == "Role" }?.value
            let isOrganization = hasCompany && company == thing.title
            // The company and the role are SEARCHED, never drawn (user,
            // 2026-09-25): "stripe" finds the designer at Stripe.
            out.append(.init(Identity.make(.contact, ref), name: thing.title, typed: true,
                             kind: isOrganization ? .organization : .person,
                             since: thing.capturedAt,
                             keywords: [company ?? "", role ?? ""]))
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

    // MARK: - Activity (the row's line, and Recent)

    /// How many of the newest things one rebuild reads. A bound, not a
    /// window: the newest thing from a contact you dealt with a year ago is
    /// still its row's line if it is in here, and Recent is the 30-day slice
    /// the list cuts itself.
    static let activityWindow = 800

    /// The corpus's newest word on every identity, in ONE walk of the newest
    /// things (2026-09-25): the title of the newest thing from or about each
    /// key, and the newest moment it dealt WITH you. Wallet transfers, mail
    /// and GitHub rows are with you by nature; a social row only when it is
    /// a notice about your post (`quote`, prd §704) — a followed account's
    /// own cast is FROM them and feeds the line, never Recent, or everybody
    /// you follow would be "recent" whenever they posted. The card itself is
    /// not a thing from the person.
    static func activity(context: ModelContext) -> [String: ContactIndex.Activity] {
        var descriptor = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\Thing.capturedAt, order: .reverse)])
        descriptor.fetchLimit = activityWindow
        descriptor.propertiesToFetch = [\.source, \.kind, \.sourceRef, \.authorHandle, \.walletAddress,
                                        \.counterpartyAddress, \.authorEmail, \.title, \.capturedAt, \.quote]
        var rows: [ContactIndex.ActivityRow] = []
        for thing in (try? context.fetch(descriptor)) ?? [] {
            guard thing.kind != .contact else { continue }
            let notification = thing.sourceRef?.hasPrefix("gh:notif:") ?? false
            guard !notification else { continue }
            // The transfer's OWN wallet is the one it is from, never the one
            // it was with: a followed wallet's transfer is a thing from them
            // (the line), and a transfer from your own watched wallet is
            // not you dealing with yourself (Savings sat under Recent).
            let withKeys = ContactIndex.keys(
                source: thing.source, kind: thing.kind.rawValue, sourceRef: thing.sourceRef,
                authorHandle: thing.authorHandle, walletAddress: nil,
                counterpartyAddress: thing.counterpartyAddress, authorEmail: thing.authorEmail,
                isNotification: notification)
            let social = ["Farcaster", "Bluesky", "Nostr"].contains(thing.source)
            if !withKeys.isEmpty {
                rows.append(.init(keys: withKeys, title: thing.title, at: thing.capturedAt,
                                  acted: !social || thing.quote != nil))
            }
            if let w = thing.walletAddress, w.hasPrefix("0x"), w.count == 42 {
                rows.append(.init(keys: [Identity.key(.wallet, w)], title: thing.title,
                                  at: thing.capturedAt, acted: false))
            }
        }
        return ContactIndex.activity(rows: rows)
    }

    /// The distinct counterparties of the month's landed transfers, newest
    /// first, at most 40 — what the sweep asks web3.bio to name.
    static func recentCounterparties(context: ModelContext) -> [String] {
        let since = Date.now.addingTimeInterval(-30 * 86400)
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Wallet" && $0.capturedAt > since },
                                       sortBy: [SortDescriptor(\Thing.capturedAt, order: .reverse)])
        d.fetchLimit = 200
        d.propertiesToFetch = [\.counterpartyAddress, \.capturedAt]
        var out: [String] = []
        for thing in (try? context.fetch(d)) ?? [] {
            guard let c = thing.counterpartyAddress?.lowercased(), c.hasPrefix("0x"), c.count == 42,
                  !out.contains(c) else { continue }
            out.append(c)
            if out.count == 40 { break }
        }
        return out
    }

    @discardableResult
    static func rebuild(context: ModelContext) -> [Contact] {
        let store = ContactLinksStore.shared
        let seeds = seeds(context: context)
        let cards = cards(context: context)
        for link in discoverVerified() { store.record(link) }
        for link in ContactSuggest.stated(cards: cards, seeds: seeds) { store.record(link) }
        for link in ContactSuggest.suggested(cards: cards, seeds: seeds) { store.record(link) }
        let built = ContactIndex.build(seeds: seeds, links: store.ledger.all,
                                       activity: activity(context: context))
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
        // The line and Recent (2026-09-25): how many rows carry a newest
        // thing, and how many dealt with you in the last 30 days.
        let lined = built.filter { $0.lastThing != nil }.count
        let recent = built.filter { ($0.lastActedAt ?? .distantPast) > Date.now.addingTimeInterval(-30 * 86400) }.count
        lines.append("activity: \(lined) of \(built.count) carry a newest thing | recent: \(recent) dealt with you in 30 days")
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
