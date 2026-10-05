import Foundation

/// What a book address says about ITSELF on web3.bio's `/profile` read — its
/// bio and the handles its name records link (prd §1025). The Addresses index
/// turns those into "Same person?" suggestions (`ContactSuggest.claimed`); it
/// never merges on them, because a text record is whatever its owner typed.
///
/// **Why a store, and why only the book.** `AddressNames`' reasons, one call
/// cheaper: an answer is persisted, misses included, for a fortnight, and a
/// pass spends at most `perPassBudget` reads. Only addresses in the wallet
/// book are asked — the ones the person named or watched — never a passing
/// counterparty, so a busy month of transfers buys nothing here.
///
/// Same host as the names (`api.web3.bio`, already declared in
/// `NetworkReach`'s "Names & avatars"), keyless, demo-gated in
/// `Web3Bio.profile(for:)`.
@MainActor
final class ContactProfiles {
    static let shared = ContactProfiles()

    struct Entry: Codable, Equatable {
        /// The first record's own description, or nil.
        var bio: String?
        /// Identity keys the address's records link (`gh:x`, `fc:y`, `bsky:z`).
        var claims: [String]
        var askedAt: Date
    }

    private static let storeKey = "contactProfiles.v1"
    private static let freshness: TimeInterval = 14 * 24 * 3600
    static let perPassBudget = 6

    private var entries: [String: Entry] = [:]
    private var asking: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    /// Every answer, as the suggester reads it.
    var profiles: [ContactSuggest.Profile] {
        entries.sorted { $0.key < $1.key }.compactMap { address, entry in
            guard entry.bio != nil || !entry.claims.isEmpty else { return nil }
            return ContactSuggest.Profile(key: Identity.key(.wallet, address), bio: entry.bio,
                                          claims: entry.claims)
        }
    }

    /// A record's links as identity keys, for the networks the app keeps a
    /// roster of. X has none (nobody is watched there), so `twitter` drops.
    nonisolated static func claims(of records: [Web3Bio.Record]) -> [String] {
        var out: [String] = []
        for record in records {
            for (platform, handle) in record.links.sorted(by: { $0.key < $1.key }) {
                let key: String
                switch platform {
                case "github":    key = Identity.key(.github, handle)
                case "bluesky":   key = Identity.key(.bluesky, handle)
                default:          continue
                }
                if !out.contains(key) { out.append(key) }
            }
        }
        return out
    }

    /// Asks for the book's addresses, newest first, bounded by the budget.
    func fill(_ addresses: [String]) async {
        var spent = 0
        for raw in addresses {
            guard spent < Self.perPassBudget else { return }
            let address = raw.lowercased()
            guard ENS.isHexAddress(address), !asking.contains(address) else { continue }
            if let known = entries[address], Date.now.timeIntervalSince(known.askedAt) < Self.freshness { continue }
            asking.insert(address)
            defer { asking.remove(address) }
            spent += 1
            // nil is no answer (a throttle, the demo): nothing is stored, so
            // the next pass asks again.
            guard let records = await Web3Bio.profile(for: address) else { continue }
            entries[address] = Entry(bio: records.compactMap(\.bio).first,
                                     claims: Self.claims(of: records), askedAt: .now)
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }

    #if DEBUG
    var count: Int { entries.count }
    func forgetAll() { entries = [:]; persist() }
    #endif
}
