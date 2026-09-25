import Foundation

/// The link ledger — the ONE thing the Addresses room persists that no seat
/// already holds (prd §916, `docs/addresses-spec.md` section 2.3).
///
/// A `ContactLink` says two identity keys belong to one contact, and HOW the
/// app knows it (`LinkTier`). The keys are `Identity.key`'s canonical form
/// (`ContactIndex.swift`); the pair is stored sorted so one pair is one row.
///
/// **Three tiers, and what each may do (section 3 of the spec):**
///   · `verified` — a fact from the network (Farcaster's verifications,
///     web3.bio forward-checked) or from the person ("Yes, same person").
///     Merges silently.
///   · `suggested` — the corpus says these look like one person. Never merges;
///     draws one "Same person?" row. A "No" is remembered forever for the pair
///     (`declined`), and a re-suggestion cannot clear it.
///   · `stated` — the contact card's own field names the identity. Merges into
///     that contact.
///
/// **A declined pair still merges on a later VERIFIED edge.** A "No" was an
/// opinion about a guess; a verification is a fact, and the app says so.
///
/// Foundation-only on purpose: `scripts/addresses-selftest.sh` compiles this
/// file and `ContactIndex.swift` whole. Persistence and the iCloud mirror live
/// in `ContactLinksStore.swift`.
enum LinkTier: String, Codable, Equatable {
    case verified, suggested, stated
}

struct ContactLink: Codable, Equatable, Hashable {
    /// The two keys, sorted, so `pairKey` is one spelling per pair.
    let a: String
    let b: String
    var tier: LinkTier
    /// Who said so: `farcaster.verifications`, `web3.bio`, `ens`,
    /// `contact.card`, `corpus.email`, `you`.
    var source: String
    var at: Date
    var declined: Bool = false

    init(_ x: String, _ y: String, tier: LinkTier, source: String,
         at: Date = .now, declined: Bool = false) {
        let (lo, hi) = x <= y ? (x, y) : (y, x)
        a = lo; b = hi
        self.tier = tier; self.source = source; self.at = at; self.declined = declined
    }

    static func pairKey(_ x: String, _ y: String) -> String {
        x <= y ? x + "|" + y : y + "|" + x
    }
    var pairKey: String { a + "|" + b }

    /// The one private key shape: an Apple contact. `CNContact.identifier` is
    /// not stable across devices, and the mirror ledger carries addresses,
    /// never anybody's phone book (§169) — so an edge touching one never
    /// leaves the device.
    static let privatePrefix = "contact:"
    var isPublic: Bool {
        !a.hasPrefix(Self.privatePrefix) && !b.hasPrefix(Self.privatePrefix)
    }

    /// Whether the component walk may cross this edge.
    var merges: Bool { tier != .suggested }

    /// Whether the room may draw this pair as a "Same person?" row.
    var suggests: Bool { tier == .suggested && !declined }
}

/// The ledger as a VALUE, so every rule is a pure function the harness can
/// mutate; the store wraps one of these.
struct LinkLedger: Codable, Equatable {
    var links: [String: ContactLink] = [:]

    var all: [ContactLink] { links.values.sorted { $0.pairKey < $1.pairKey } }

    func link(_ x: String, _ y: String) -> ContactLink? { links[ContactLink.pairKey(x, y)] }

    /// The merge rule for one incoming edge against what stands:
    ///   · nothing stands → take it;
    ///   · a verified edge stands → keep it (a fact does not downgrade);
    ///   · a declined suggestion stands → another suggestion changes nothing,
    ///     a verified or stated edge replaces it (the fact wins the opinion);
    ///   · a live suggestion or a stated edge stands → a higher tier replaces
    ///     it, the same tier refreshes its stamp and source.
    func recording(_ incoming: ContactLink) -> LinkLedger {
        var next = self
        let key = incoming.pairKey
        guard let standing = links[key] else { next.links[key] = incoming; return next }
        switch (standing.tier, incoming.tier) {
        case (.verified, _):
            return self
        case (.suggested, .suggested) where standing.declined:
            return self
        case (.suggested, .suggested), (.stated, .stated):
            var kept = standing
            kept.at = max(standing.at, incoming.at)
            kept.source = incoming.source
            next.links[key] = kept
        case (_, .verified), (.suggested, .stated):
            next.links[key] = incoming
        case (.stated, .suggested):
            return self
        }
        return next
    }

    /// "No" on a suggestion. Sticks forever for the pair; a verified edge
    /// arriving later still replaces it (see `recording`).
    func declining(_ x: String, _ y: String, at: Date = .now) -> LinkLedger {
        var next = self
        let key = ContactLink.pairKey(x, y)
        if var standing = links[key], standing.tier == .suggested {
            standing.declined = true
            standing.at = at
            next.links[key] = standing
        } else if links[key] == nil {
            next.links[key] = ContactLink(x, y, tier: .suggested, source: "you", at: at, declined: true)
        }
        return next
    }

    /// "Yes, same person": the pair becomes a verified edge the person made.
    func confirming(_ x: String, _ y: String, at: Date = .now) -> LinkLedger {
        recording(ContactLink(x, y, tier: .verified, source: "you", at: at))
    }

    /// What the iCloud mirror may carry: public keys on both ends, nothing
    /// that names an Apple contact.
    var mirrorable: [String: ContactLink] {
        links.filter { $0.value.isPublic }
    }

    /// A remote copy folded in: each pair through `recording`, so the same
    /// rules decide, and a remote decline lands as a decline.
    func merging(remote: [String: ContactLink]) -> LinkLedger {
        var next = self
        for (_, link) in remote.sorted(by: { $0.key < $1.key }) {
            next = next.recording(link)
            if link.declined, link.tier == .suggested {
                next = next.declining(link.a, link.b, at: link.at)
            }
        }
        return next
    }
}
