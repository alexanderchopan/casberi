import Foundation
import Observation

/// The saved half of Addresses — what the person adds BY HAND (prd §916
/// amendment, `docs/addresses-spec.md` section 2.6; user: "anywhere in the
/// app there is a person even if not social like an rss writer or whatever").
///
/// The seats feed the index; this is the one population that is neither a
/// `Thing` nor a seat's store: a sender you named, a GitHub login, a poster,
/// a feed. A saved contact with a WALLET identity is not here — the wallet
/// book (§169) stays the one ledger for addresses, and `Add to Addresses` on
/// a transfer writes there. Newest stamp wins on merge, the book's own rule.
///
/// Persisted in UserDefaults `addresses.saved.v1` through `DefaultsWrite`
/// (§721) and mirrored through `KeyValueMirror` (`addresses.saved.v1` in
/// iCloud) — every saved key is public by construction (a name you typed for
/// a handle or a mailbox), never a `contact:` key, which a card already holds.
struct SavedContact: Codable, Identifiable, Equatable, KeyValueMirrored {
    /// The identity key it was saved from (`Identity.key`).
    let id: String
    var name: String
    var addedAt: Date
    var updatedAt: Date?

    var mirrorStamp: Date { updatedAt ?? addedAt }
}

@Observable
@MainActor
final class ContactBook {
    static let shared = ContactBook()

    private static let storeKey = "addresses.saved.v1"

    private(set) var entries: [String: SavedContact]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: SavedContact].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
        // The iCloud mirror, one runloop turn later — `attach` reads the
        // singleton, which does not exist until this initializer returns
        // (the wallet book's own shape).
        DispatchQueue.main.async { Self.shared.attach() }
    }

    var all: [SavedContact] { entries.values.sorted { $0.addedAt > $1.addedAt } }

    func name(for key: String) -> String? { entries[key]?.name }
    func has(_ key: String) -> Bool { entries[key] != nil }

    /// Name an identity, or clear its name with a blank (the wallet book's
    /// own convention: blank clears).
    func save(_ identity: Identity, name raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard identity.kind != .contact, identity.kind != .wallet else { return }
        if name.isEmpty { remove(identity.key); return }
        if var standing = entries[identity.key] {
            standing.name = name
            standing.updatedAt = .now
            entries[identity.key] = standing
        } else {
            entries[identity.key] = SavedContact(id: identity.key, name: name, addedAt: .now)
        }
        persist()
    }

    func remove(_ key: String) {
        guard entries.removeValue(forKey: key) != nil else { return }
        mirror.noteRemoval(key)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        DefaultsWrite.set(data, forKey: Self.storeKey)
        mirror.push()
    }

    // MARK: - Mirror

    @ObservationIgnored private lazy var mirror = KeyValueMirror<SavedContact>(
        entriesKey: "addresses.saved.v1",
        tombstonesKey: "addresses.saved.tombstones.v1",
        localTombstonesKey: "addresses.saved.tombstones.local.v1",
        snapshot: { [weak self] in self?.entries ?? [:] },
        newer: { incoming, standing in
            guard let standing else { return incoming }
            return incoming.mirrorStamp > standing.mirrorStamp ? incoming : nil
        },
        apply: { [weak self] merged in
            guard let self, merged != self.entries else { return }
            self.entries = merged
            guard let data = try? JSONEncoder().encode(self.entries) else { return }
            DefaultsWrite.set(data, forKey: Self.storeKey)
        })

    func attach() { mirror.attach() }
    func syncNow() { mirror.syncNow() }
}
