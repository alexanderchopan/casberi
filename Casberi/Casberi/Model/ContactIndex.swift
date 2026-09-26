import Foundation

/// The contact index — one contact per component of identities joined by
/// links (prd §916, `docs/addresses-spec.md` section 2).
///
/// **Nothing here is stored.** A `Contact` is a value built at read time from
/// the stores that already hold the identities (`ContactIndexSources.swift`
/// gathers them into `Seed`s) plus the link ledger. Disconnecting a seat
/// removes its rows by itself; there is no reconcile pass to get wrong.
///
/// **A display name is never a key** (§632). Two seeds both called "Alex" are
/// two contacts until a link says otherwise — the harness mutates a name
/// merge back in and must catch it.
///
/// Foundation-only on purpose: `scripts/addresses-selftest.sh` compiles this
/// file and `ContactLinks.swift` whole.
struct Identity: Hashable, Codable {

    /// Every way the app can know somebody. The ORDER is the lead-identity
    /// precedence (section 2.1): what Mail, Contacts and GitHub carry comes
    /// first, because more people use those than Farcaster (user, 2026-09-24).
    enum Kind: String, Codable, CaseIterable {
        case contact, email, github, wallet
        case ens, basename, linea, farcaster, lens
        case bluesky, nostr, worldApp, feed

        var precedence: Int { Self.allCases.firstIndex(of: self) ?? .max }

        /// A name service — the kinds whose key IS a human-readable name.
        var isNameService: Bool {
            switch self {
            case .ens, .basename, .linea, .lens: return true
            default: return false
            }
        }

        /// The key prefix, so a key alone says its kind. Wallet keys are the
        /// bare `0x…` and name-service keys the bare name.
        var prefix: String {
            switch self {
            case .contact:   return "contact:"
            case .email:     return "mail:"
            case .github:    return "gh:"
            case .farcaster: return "fc:"
            case .bluesky:   return "bsky:"
            case .nostr:     return "nostr:"
            case .worldApp:  return "world:"
            case .feed:      return "feed:"
            case .wallet, .ens, .basename, .linea, .lens: return ""
            }
        }
    }

    let kind: Kind
    /// Canonical, lowercased, prefixed — see `key(_:_:)`.
    let key: String
    /// How this identity joined its contact: nil for a seed's own identity,
    /// else the tier of the edge it was reached through.
    var tier: LinkTier?
    /// Who made that edge (`you` draws as "you confirmed").
    var source: String?

    init(kind: Kind, key: String, tier: LinkTier? = nil, source: String? = nil) {
        self.kind = kind; self.key = key; self.tier = tier; self.source = source
    }

    // MARK: - Keys

    /// The one canonical key for a raw identity. Case is folded because an
    /// EIP-55 address, a GitHub login and a handle each spell one identity
    /// two ways (§857's mixed-case lookup trap); a leading `@` is dropped.
    static func key(_ kind: Kind, _ raw: String) -> String {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix(kind.prefix), !kind.prefix.isEmpty { body.removeFirst(kind.prefix.count) }
        if body.hasPrefix("@") { body.removeFirst() }
        return kind.prefix + body.lowercased()
    }

    static func make(_ kind: Kind, _ raw: String) -> Identity {
        Identity(kind: kind, key: key(kind, raw))
    }

    /// A key back to its kind, for link endpoints that are not seeds.
    static func parse(key: String) -> Identity? {
        for kind in Kind.allCases where !kind.prefix.isEmpty && key.hasPrefix(kind.prefix) {
            return Identity(kind: kind, key: key)
        }
        if key.hasPrefix("0x"), key.count == 42 { return Identity(kind: .wallet, key: key) }
        if let named = Kind.classify(primaryName: key) { return Identity(kind: named, key: key) }
        return nil
    }

    /// The body after the prefix: the address, the handle, the name.
    var body: String { String(key.dropFirst(kind.prefix.count)) }

    /// What a row's line draws for this identity.
    var label: String {
        switch kind {
        case .wallet:                    return "…" + body.suffix(4)
        case .farcaster, .bluesky:       return "@" + body
        case .email, .github, .contact,
             .nostr, .worldApp, .feed,
             .ens, .basename, .linea, .lens: return body
        }
    }
}

extension Identity.Kind {
    /// The kind of a primary name by its SHAPE — `AddressNames` stores a
    /// localized label beside each name, so the label is not a key. A
    /// Farcaster handle is the one `@`-prefixed row; the rest are suffixes.
    /// A bare word is a World App username; any other dotted name is ENS
    /// (which is where `.wei`/`.gwei` file too — they resolve like ENS).
    static func classify(primaryName: String) -> Identity.Kind? {
        let n = primaryName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !n.isEmpty, !n.hasPrefix("0x") else { return nil }
        if n.hasPrefix("@") { return .farcaster }
        if n.hasSuffix(".base.eth") { return .basename }
        if n.hasSuffix(".linea.eth") { return .linea }
        if n.hasSuffix(".lens") { return .lens }
        if n.contains(".") { return .ens }
        return .worldApp
    }
}

struct Contact: Identifiable, Equatable {
    /// A row need not be a person (user, 2026-09-24: "someone may have
    /// addresses that aren't people"). The wallet book's kinds (§169/§294)
    /// plus the three the seats add.
    enum Kind: String, Codable, Equatable {
        case person, organization, contract, safe, smartAccount, key, publication
    }

    /// The lead identity's key (section 2.1) — stable while links are added.
    let id: String
    let name: String
    let kind: Kind
    /// Ordered by `Identity.Kind.precedence`, then key.
    let identities: [Identity]
    let avatar: String?
    /// The newest moment this contact DEALT with you (`Activity.actedAt`, or
    /// a seed's own stamp) — what files a row under Recent.
    let lastActedAt: Date?
    /// The newest thing from or about this contact, as its title — the row's
    /// one line (2026-09-25). Nil draws the identities instead.
    let lastThing: String?
    /// Words a search may hit that no row draws: a card's company and role,
    /// a wallet entry's note. Never drawn (user, 2026-09-25: a company line
    /// is meaningless); only matched.
    let keywords: [String]

    var lead: Identity { identities[0] }
    func has(_ key: String) -> Bool { identities.contains { $0.key == key } }

    /// Nobody named this contact and no seat did: its name is a wallet's
    /// tail. It sorts last in the list and never names a transfer row.
    var isUnnamed: Bool { name.hasPrefix("…") }
}

enum ContactIndex {

    /// One identity as a store holds it. `name` is what the person TYPED
    /// (`typed`) or what the seat reports (a display name); the two rank
    /// differently (section 2.2). A wallet seed's name is typed or nil — an
    /// auto-name (`…44b1`) is not a name, and the gatherer never passes one.
    struct Seed: Equatable {
        let identity: Identity
        var name: String?
        var typed: Bool = false
        var kind: Contact.Kind = .person
        var avatar: String?
        var since: Date?
        var lastActedAt: Date?
        var keywords: [String] = []

        init(_ identity: Identity, name: String? = nil, typed: Bool = false,
             kind: Contact.Kind = .person, avatar: String? = nil,
             since: Date? = nil, lastActedAt: Date? = nil, keywords: [String] = []) {
            self.identity = identity; self.name = name; self.typed = typed
            self.kind = kind; self.avatar = avatar; self.since = since
            self.lastActedAt = lastActedAt; self.keywords = keywords
        }
    }

    /// What the corpus holds for ONE identity key: the newest thing from or
    /// about it, and the newest moment it dealt with you. The two differ on
    /// purpose — a followed account's own post is a thing FROM them (the
    /// row's line), a reply, a transfer or a mail is a thing WITH you
    /// (Recent). `activity(rows:)` folds a corpus walk into this.
    struct Activity: Equatable {
        var lastThing: String?
        var lastAt: Date?
        var actedAt: Date?
    }

    /// One corpus row as the activity pass reads it: the identity keys it
    /// names (`keys(...)`), its title, when, and whether it was WITH you.
    struct ActivityRow: Equatable {
        let keys: [String]
        let title: String
        let at: Date
        let acted: Bool
    }

    /// Folds rows into one `Activity` per key, newest winning — pure, so the
    /// harness can hand it rows out of order and watch the older one lose.
    static func activity(rows: [ActivityRow]) -> [String: Activity] {
        var out: [String: Activity] = [:]
        for row in rows {
            for key in row.keys {
                var a = out[key] ?? Activity()
                if (a.lastAt ?? .distantPast) < row.at {
                    a.lastAt = row.at; a.lastThing = row.title
                }
                if row.acted, (a.actedAt ?? .distantPast) < row.at { a.actedAt = row.at }
                out[key] = a
            }
        }
        return out
    }

    // MARK: - Build

    /// Every contact, from the seeds and the ledger. Deterministic: the same
    /// inputs give the same list in the same order (by lead precedence, then
    /// name, then key), so a row does not move between two rebuilds.
    static func build(seeds: [Seed], links: [ContactLink],
                      activity: [String: Activity] = [:]) -> [Contact] {
        // Every seed's key is a node; a merging link's endpoints join. A
        // link end that is no seed still becomes an identity on the contact.
        var parent: [String: String] = [:]
        func find(_ k: String) -> String {
            var k = k
            while let p = parent[k], p != k { k = p }
            return k
        }
        func union(_ x: String, _ y: String) {
            let rx = find(x), ry = find(y)
            guard rx != ry else { return }
            parent[min(rx, ry) == rx ? ry : rx] = min(rx, ry)
        }
        var seedsByKey: [String: [Seed]] = [:]
        for seed in seeds {
            parent[seed.identity.key] = parent[seed.identity.key] ?? seed.identity.key
            seedsByKey[seed.identity.key, default: []].append(seed)
        }
        var edges: [String: [ContactLink]] = [:]
        for link in links where link.merges {
            for end in [link.a, link.b] where parent[end] == nil {
                guard Identity.parse(key: end) != nil else { continue }
                parent[end] = end
            }
            guard parent[link.a] != nil, parent[link.b] != nil else { continue }
            union(link.a, link.b)
            edges[link.a, default: []].append(link)
            edges[link.b, default: []].append(link)
        }

        var components: [String: [String]] = [:]
        for key in parent.keys { components[find(key), default: []].append(key) }

        var out: [Contact] = []
        for keys in components.values {
            let identities: [Identity] = keys.compactMap { key in
                seedsByKey[key]?.first?.identity ?? Identity.parse(key: key)
            }
            guard !identities.isEmpty else { continue }
            // The lead: the identity precedence, then the OLDEST seed, then
            // the key — so a later-added identity never takes the id.
            let lead = identities.min { l, r in
                if l.kind.precedence != r.kind.precedence { return l.kind.precedence < r.kind.precedence }
                let ls = seedsByKey[l.key]?.first?.since ?? .distantFuture
                let rs = seedsByKey[r.key]?.first?.since ?? .distantFuture
                if ls != rs { return ls < rs }
                return l.key < r.key
            }!
            // Each identity's tier: the edge it was FIRST reached through,
            // walking out from the lead — verified beats stated at equal
            // depth because the walk visits verified edges first.
            var tiers: [String: (LinkTier?, String?)] = [lead.key: (nil, nil)]
            var frontier = [lead.key]
            while !frontier.isEmpty {
                var next: [String] = []
                for key in frontier {
                    let out = (edges[key] ?? []).sorted { a, b in
                        if a.tier != b.tier { return a.tier == .verified }
                        return a.pairKey < b.pairKey
                    }
                    for link in out {
                        let other = link.a == key ? link.b : link.a
                        guard tiers[other] == nil else { continue }
                        tiers[other] = (link.tier, link.source)
                        next.append(other)
                    }
                }
                frontier = next
            }
            let ordered = identities
                .map { id -> Identity in
                    var id = id
                    if let t = tiers[id.key] { id.tier = t.0; id.source = t.1 }
                    return id
                }
                .sorted { l, r in
                    if l.kind.precedence != r.kind.precedence { return l.kind.precedence < r.kind.precedence }
                    return l.key < r.key
                }
            let componentSeeds = ordered.flatMap { seedsByKey[$0.key] ?? [] }
            // The corpus's newest word on ANY identity in the component —
            // a link-only identity (a card's email) counts too, because a
            // mail from that address is from this person.
            let acts = ordered.compactMap { activity[$0.key] }
            let newest = acts.filter { $0.lastAt != nil }.max { ($0.lastAt ?? .distantPast) < ($1.lastAt ?? .distantPast) }
            let acted = (componentSeeds.compactMap(\.lastActedAt) + acts.compactMap(\.actedAt)).max()
            var keywords: [String] = []
            for word in componentSeeds.flatMap(\.keywords) where !word.isEmpty && !keywords.contains(word) {
                keywords.append(word)
            }
            out.append(Contact(id: lead.key,
                               name: name(lead: lead, identities: ordered, seeds: componentSeeds),
                               kind: kind(of: componentSeeds),
                               identities: ordered,
                               avatar: componentSeeds.compactMap(\.avatar).first,
                               lastActedAt: acted,
                               lastThing: newest?.lastThing,
                               keywords: keywords))
        }
        return out.sorted { l, r in
            if l.lead.kind.precedence != r.lead.kind.precedence {
                return l.lead.kind.precedence < r.lead.kind.precedence
            }
            let c = l.name.localizedCaseInsensitiveCompare(r.name)
            if c != .orderedSame { return c == .orderedAscending }
            return l.id < r.id
        }
    }

    // MARK: - Name

    /// Fixed precedence, never ranked (section 2.2): the name YOU typed, then
    /// a verified name-service identity (ENS first, then Base, Linea, Lens),
    /// then a seat's display name, then the lead's own label. A typed name
    /// always wins — §169's "naming is free" is the person's authority over
    /// their book.
    static func name(lead: Identity, identities: [Identity], seeds: [Seed]) -> String {
        if let typed = seeds.first(where: { $0.typed && !($0.name ?? "").isEmpty })?.name { return typed }
        if let named = identities.first(where: { $0.kind.isNameService }) { return named.body }
        if let display = seeds.first(where: { !($0.name ?? "").isEmpty })?.name { return display }
        return lead.label
    }

    /// The wallet's kind check knows better than a social seat: any seed that
    /// says contract, Safe, smart account or key names the contact; a
    /// publication only when nothing says otherwise.
    static func kind(of seeds: [Seed]) -> Contact.Kind {
        let kinds = seeds.map(\.kind)
        for k in [Contact.Kind.safe, .smartAccount, .contract, .key, .organization] where kinds.contains(k) {
            return k
        }
        if !kinds.isEmpty, kinds.allSatisfy({ $0 == .publication }) { return .publication }
        return .person
    }

    // MARK: - Lookup

    /// The identity keys a thing names, in the order they should be tried —
    /// the pure half of `contact(for:)` (section 2.5). A GitHub notification's
    /// `authorHandle` is the repo OWNER, not the actor (`GitHubRowTag`), so it
    /// yields nothing; a mail sender whose handle is a display name holds no
    /// address and yields nothing either.
    static func keys(source: String, kind: String, sourceRef: String?,
                     authorHandle: String?, walletAddress: String?,
                     counterpartyAddress: String?, authorEmail: String?,
                     isNotification: Bool) -> [String] {
        var out: [String] = []
        if kind == "contact", let ref = sourceRef, ref.hasPrefix("contact:") {
            out.append(Identity.key(.contact, ref))
        }
        if let c = counterpartyAddress, c.hasPrefix("0x"), c.count == 42 { out.append(Identity.key(.wallet, c)) }
        if let w = walletAddress, w.hasPrefix("0x"), w.count == 42 { out.append(Identity.key(.wallet, w)) }
        if let e = authorEmail, e.contains("@") { out.append(Identity.key(.email, e)) }
        if let h = authorHandle, !h.isEmpty {
            switch source {
            case "Farcaster": out.append(Identity.key(.farcaster, h))
            case "Bluesky":   out.append(Identity.key(.bluesky, h))
            case "Nostr":     out.append(Identity.key(.nostr, h))
            case "GitHub" where !isNotification: out.append(Identity.key(.github, h))
            // A `where` on a multi-pattern case binds to its LAST pattern
            // only — the harness caught "Gmail" matching a bare display
            // name — so the address test is one guard for all three.
            case "Gmail", "iCloud Mail", "Mail":
                if h.contains("@") { out.append(Identity.key(.email, h)) }
            default: break
            }
        }
        return out
    }
}
