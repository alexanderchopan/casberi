import Foundation
import Observation

/// **A CONTACT YOU REMOVED STAYS REMOVED (prd §1610, user: "there doesn't
/// seem to be a way to remove a contact").** Remove from Contacts forgets
/// what Casberi itself holds of them (a wallet's name in the book, a name
/// you saved) and records their keys here, so whatever else still feeds the
/// contact (a card in your iPhone's Contacts, something you follow) keeps it
/// off the list. Following is untouched: Unfollow is its own door.
///
/// Naming them again by hand (`AddressBook.setName`, `ContactBook.save`)
/// brings them back. Persisted in `contacts.removed.v1` and mirrored through
/// iCloud like the saved names, so a removal holds on the Mac too.
struct RemovedContact: Codable, Identifiable, Equatable, KeyValueMirrored {
    /// The identity key (`Identity.key`).
    let id: String
    /// The lead key of the contact it was removed with: naming any one of
    /// its identities again brings every one back.
    let contact: String
    var removedAt: Date

    var mirrorStamp: Date { removedAt }
}

@Observable
@MainActor
final class ContactsRemoved {
    static let shared = ContactsRemoved()

    private static let storeKey = "contacts.removed.v1"

    private(set) var entries: [String: RemovedContact]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: RemovedContact].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
        DispatchQueue.main.async { Self.shared.attach() }
    }

    /// Whether any of the contact's identities was removed.
    func removed(_ contact: Contact) -> Bool {
        !entries.isEmpty && contact.identities.contains { entries[$0.key] != nil }
    }

    /// Remove a contact: its wallets leave the book, its saved names go, and
    /// every key it holds is kept off the list.
    func remove(_ contact: Contact) {
        for identity in contact.identities {
            if identity.kind == .wallet { AddressBook.shared.remove(identity.body) }
            ContactBook.shared.remove(identity.key)
            entries[identity.key] = RemovedContact(id: identity.key, contact: contact.lead.key, removedAt: .now)
        }
        persist()
    }

    /// Named again by hand: it comes back.
    func restore(_ key: String) {
        guard let group = entries[key]?.contact else { return }
        for gone in entries.values where gone.contact == group {
            entries[gone.id] = nil
            mirror.noteRemoval(gone.id)
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        DefaultsWrite.set(data, forKey: Self.storeKey)
        mirror.push()
    }

    // MARK: - Mirror

    @ObservationIgnored private lazy var mirror = KeyValueMirror<RemovedContact>(
        entriesKey: "contacts.removed.v1",
        tombstonesKey: "contacts.removed.tombstones.v1",
        localTombstonesKey: "contacts.removed.tombstones.local.v1",
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
