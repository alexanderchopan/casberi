import Foundation

/// Tier-2 and tier-3 links from the corpus — what a rule can say about two
/// identities being one contact (prd §916, `docs/addresses-spec.md` section 3).
///
/// **Stated** (tier 3): a contact card's own field names a handle the app
/// follows — "Farcaster: jesse", "GitHub: torvalds" in the card's social
/// profiles or IM addresses. The card said it; the edge merges the handle
/// INTO that card and nothing else.
///
/// **Suggested** (tier 2): the corpus makes it LOOK like one person — a card's
/// full name equals a seat's display name, an email's mailbox equals a GitHub
/// login you watch, two social accounts share a display name. A suggestion
/// NEVER merges (§632); it draws one "Same person?" row, and the person
/// decides. A "No" is remembered forever for the pair.
///
/// Foundation-only, so `scripts/addresses-selftest.sh` compiles it whole and
/// can mutate a name match into a merge and watch it fail.
enum ContactSuggest {

    /// One Apple contact card, as the index sees it.
    struct Card: Equatable {
        let key: String                 // `contact:<id>`
        let name: String
        /// `"Service: handle"` lines from the card (`ContactsIngest.retrievalText`).
        let lines: [String]
        let emails: [String]
    }

    /// The services a card line can name that the app also holds a roster for.
    static func identity(fromCardLine line: String) -> Identity? {
        guard let sep = line.range(of: ":") else { return nil }
        let service = line[line.startIndex..<sep.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
        let handle = line[sep.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !handle.isEmpty else { return nil }
        switch service {
        case "farcaster", "warpcast": return Identity.make(.farcaster, handle)
        case "bluesky":               return Identity.make(.bluesky, handle)
        case "nostr":                 return Identity.make(.nostr, handle)
        case "github":                return Identity.make(.github, handle)
        default:                      return nil
        }
    }

    /// Stated edges: a card line naming a handle among the seeds — and the
    /// card's own EMAILS (2026-09-25), so a mail from that address resolves
    /// to the card and stands under its "With you". A mailbox needs no
    /// roster to be an identity: the card said it, which is the whole of
    /// what "stated" means.
    static func stated(cards: [Card], seeds: [ContactIndex.Seed], at: Date = .now) -> [ContactLink] {
        let held = Set(seeds.map(\.identity.key))
        var out: [ContactLink] = []
        for card in cards {
            for line in card.lines {
                guard let identity = identity(fromCardLine: line), held.contains(identity.key) else { continue }
                out.append(ContactLink(card.key, identity.key, tier: .stated, source: "contact.card", at: at))
            }
            for email in card.emails where email.contains("@") {
                out.append(ContactLink(card.key, Identity.key(.email, email), tier: .stated, source: "contact.card", at: at))
            }
        }
        return out
    }

    /// Suggested edges. Every rule here is a LOOK-ALIKE, and the tier says so.
    static func suggested(cards: [Card], seeds: [ContactIndex.Seed], at: Date = .now) -> [ContactLink] {
        var out: [ContactLink] = []
        var seen = Set<String>()
        func add(_ a: String, _ b: String, _ source: String) {
            guard a != b else { return }
            let key = ContactLink.pairKey(a, b)
            guard seen.insert(key).inserted else { return }
            out.append(ContactLink(a, b, tier: .suggested, source: source, at: at))
        }
        // A seat's display name, folded, → the seeds that carry it.
        var byName: [String: [ContactIndex.Seed]] = [:]
        for seed in seeds where !seed.typed {
            guard let name = seed.name, name.count >= 3 else { continue }
            byName[fold(name), default: []].append(seed)
        }
        // A card's full name equals a seat's display name.
        for card in cards {
            for seed in byName[fold(card.name)] ?? [] { add(card.key, seed.identity.key, "corpus.name") }
        }
        // Two seats share a display name (a Farcaster and a Bluesky "Uma").
        for (_, group) in byName where group.count > 1 {
            let keys = group.map(\.identity.key).sorted()
            for i in keys.indices { for j in keys.indices where j > i { add(keys[i], keys[j], "corpus.name") } }
        }
        // An email's mailbox equals a GitHub login you watch.
        let logins = Set(seeds.filter { $0.identity.kind == .github }.map(\.identity.body))
        for seed in seeds where seed.identity.kind == .email {
            let mailbox = seed.identity.body.split(separator: "@").first.map(String.init) ?? ""
            if !mailbox.isEmpty, logins.contains(mailbox) { add(seed.identity.key, Identity.key(.github, mailbox), "corpus.email") }
        }
        for card in cards {
            for email in card.emails {
                let mailbox = email.lowercased().split(separator: "@").first.map(String.init) ?? ""
                if !mailbox.isEmpty, logins.contains(mailbox) { add(card.key, Identity.key(.github, mailbox), "corpus.email") }
            }
        }
        return out
    }

    /// The ONE suggestion the list may draw: the newest live suggestion whose
    /// two ends are both in the index.
    static func next(in ledger: LinkLedger, known: (String) -> Bool) -> ContactLink? {
        ledger.all
            .filter { $0.suggests && known($0.a) && known($0.b) }
            .max { $0.at < $1.at }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
