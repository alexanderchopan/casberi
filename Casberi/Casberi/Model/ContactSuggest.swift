import Foundation

/// Tier-2 and tier-3 links from the corpus — what a rule can say about two
/// identities being one contact (prd §916, `docs/addresses-spec.md` section 3).
///
/// **Stated** (tier 3): a contact card's own field names a handle the app
/// follows — "Bluesky: jesse", "GitHub: torvalds" in the card's social
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
        // Two seats share a display name (a Bluesky and a Nostr "Uma").
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

    // MARK: - More rules (prd §1025)

    /// What else the app knows about ONE identity that a rule can read: the
    /// words it says about itself (a Bluesky bio, a web3.bio
    /// description) and the handles its profile claims (web3.bio's `links`,
    /// read for book addresses only). Both are the identity's OWN claim about
    /// itself — self-asserted, so they SUGGEST and never merge.
    struct Profile: Equatable {
        /// The identity the words belong to.
        let key: String
        var bio: String? = nil
        /// Identity keys the profile names as its own (`gh:x`, `fc:y`).
        var claims: [String] = []
    }

    /// A book entry as the provenance rule reads it.
    struct BookEntry: Equatable {
        let address: String
        let name: String
        let provenance: String?
    }

    /// A mail sender as the inbox names them: the address and the display name
    /// the message carried.
    struct Sender: Equatable {
        let email: String
        let name: String
    }

    /// The handles a bio spells as LINKS — `github.com/x`, `bsky.app/profile/x`,
    /// `@x.bsky.social`. A bare `@x`
    /// names nothing: it could be any network's x.
    static func handles(inBio bio: String) -> [Identity] {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        func token(after marker: String, in text: String) -> [String] {
            var out: [String] = []
            var rest = text[...]
            while let r = rest.range(of: marker, options: .caseInsensitive) {
                let tail = rest[r.upperBound...]
                let word = String(tail.prefix { $0.unicodeScalars.allSatisfy(allowed.contains) })
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !word.isEmpty { out.append(word) }
                rest = tail
            }
            return out
        }
        var out: [Identity] = []
        func add(_ id: Identity?) {
            guard let id, !out.contains(where: { $0.key == id.key }) else { return }
            out.append(id)
        }
        for login in token(after: "github.com/", in: bio) { add(Identity.make(.github, login)) }
        for handle in token(after: "bsky.app/profile/", in: bio) { add(Identity.make(.bluesky, handle)) }
        for word in token(after: "@", in: bio) where word.lowercased().hasSuffix(".bsky.social") {
            add(Identity.make(.bluesky, word))
        }
        return out
    }

    /// A profile's claims and its bio's links, to a handle the app HOLDS.
    /// Suggested: a person can write anyone's GitHub in a bio.
    static func claimed(profiles: [Profile], seeds: [ContactIndex.Seed], at: Date = .now) -> [ContactLink] {
        let held = Set(seeds.map(\.identity.key))
        var out: [ContactLink] = []
        var seen = Set<String>()
        for profile in profiles {
            let fromBio = profile.bio.map { handles(inBio: $0).map(\.key) } ?? []
            for (key, source) in profile.claims.map({ ($0, "web3.bio.links") }) + fromBio.map({ ($0, "corpus.bio") }) {
                guard key != profile.key, held.contains(key),
                      seen.insert(ContactLink.pairKey(profile.key, key)).inserted else { continue }
                out.append(ContactLink(profile.key, key, tier: .suggested, source: source, at: at))
            }
        }
        return out
    }

    /// A book entry saved from a social door — "Bluesky · @jesse", or the
    /// name `@jesse` under provenance `Bluesky` — to that handle, when the
    /// app holds it. Suggested: the door verified the address at the moment
    /// of saving, but the app did not keep the proof.
    static func fromProvenance(_ entries: [BookEntry], seeds: [ContactIndex.Seed], at: Date = .now) -> [ContactLink] {
        let held = Set(seeds.map(\.identity.key))
        var out: [ContactLink] = []
        for entry in entries {
            guard let provenance = entry.provenance, !provenance.isEmpty else { continue }
            let parts = provenance.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
            let service = parts[0].lowercased()
            let handle = parts.count > 1 && parts[1].hasPrefix("@") ? parts[1]
                : entry.name.hasPrefix("@") ? entry.name : nil
            guard let handle else { continue }
            let identity: Identity
            switch service {
            case "bluesky":   identity = Identity.make(.bluesky, handle)
            default:          continue
            }
            let wallet = Identity.key(.wallet, entry.address)
            guard held.contains(identity.key), wallet != identity.key else { continue }
            out.append(ContactLink(wallet, identity.key, tier: .suggested, source: "book.provenance", at: at))
        }
        return out
    }

    /// A mail sender whose display name IS a card's full name, from an address
    /// the card does not list. Two words at least — a first name alone is
    /// everybody — and a name two cards share suggests nothing.
    static func senders(_ senders: [Sender], cards: [Card], at: Date = .now) -> [ContactLink] {
        var byName: [String: [Card]] = [:]
        for card in cards { byName[fold(card.name), default: []].append(card) }
        var out: [ContactLink] = []
        var seen = Set<String>()
        for sender in senders {
            let name = fold(sender.name)
            guard sender.email.contains("@"), name.split(separator: " ").count >= 2,
                  let match = byName[name], match.count == 1 else { continue }
            let card = match[0]
            guard !card.emails.contains(where: { $0.caseInsensitiveCompare(sender.email) == .orderedSame }) else { continue }
            let mail = Identity.key(.email, sender.email)
            guard seen.insert(ContactLink.pairKey(card.key, mail)).inserted else { continue }
            out.append(ContactLink(card.key, mail, tier: .suggested, source: "corpus.sender", at: at))
        }
        return out
    }

    /// The ONE suggestion the list may draw: the newest live suggestion whose
    /// two ends are both in the index — or one end in it and the other an
    /// identity that may JOIN it without being a row of its own (a mail
    /// sender's address, `joinable`), which a Yes files under the contact.
    ///
    /// `apart` says the two ends are NOT already one contact: a suggestion
    /// whose ends another link already joined asks a question with no
    /// answer (a card stating a GitHub login, and a profile linking the same
    /// login to the card's wallet), and a Yes would change nothing.
    static func next(in ledger: LinkLedger, known: (String) -> Bool,
                     joinable: (String) -> Bool = { _ in false },
                     apart: (String, String) -> Bool = { _, _ in true }) -> ContactLink? {
        ledger.all
            .filter { $0.suggests && ((known($0.a) && known($0.b))
                                      || (known($0.a) && joinable($0.b))
                                      || (joinable($0.a) && known($0.b)))
                      && apart($0.a, $0.b) }
            .max { $0.at < $1.at }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
