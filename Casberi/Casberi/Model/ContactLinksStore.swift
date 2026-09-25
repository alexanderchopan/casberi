import Foundation
import Observation

/// The link ledger's home on disk and in iCloud (prd §916, section 2.3).
///
/// The VALUE (`LinkLedger`) owns every rule; this class owns where it lives:
/// UserDefaults `addresses.links.local.v1` through `DefaultsWrite` (§721 — a
/// write inside a lock deadlocks every view body), and the same `KeyValueMirror`
/// the wallet book rides, carrying ONLY `mirrorable` edges — both keys public,
/// never a `contact:` key (§169: the mirror is addresses, not a phone book).
@Observable
@MainActor
final class ContactLinksStore {
    static let shared = ContactLinksStore()

    private static let storeKey = "addresses.links.local.v1"

    private(set) var ledger: LinkLedger

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode(LinkLedger.self, from: data) {
            ledger = decoded
        } else {
            ledger = LinkLedger()
        }
    }

    // MARK: - Writes

    func record(_ link: ContactLink) {
        let next = ledger.recording(link)
        guard next != ledger else { return }
        ledger = next
        persist()
    }

    func decline(_ x: String, _ y: String) {
        let next = ledger.declining(x, y)
        guard next != ledger else { return }
        ledger = next
        persist()
    }

    func confirm(_ x: String, _ y: String) {
        let next = ledger.confirming(x, y)
        guard next != ledger else { return }
        ledger = next
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        DefaultsWrite.set(data, forKey: Self.storeKey)
        mirror.push()
    }

    // MARK: - Mirror

    // Lazy because the closures name `self`; ignored by observation because
    // a mirror is machinery, not state a view reads.
    @ObservationIgnored private lazy var mirror = KeyValueMirror<ContactLink>(
        entriesKey: "addresses.links.v1",
        tombstonesKey: "addresses.links.tombstones.v1",
        localTombstonesKey: "addresses.links.tombstones.local.v1",
        snapshot: { [weak self] in self?.ledger.mirrorable ?? [:] },
        newer: { incoming, standing in
            guard let standing else { return incoming }
            return incoming.at > standing.at ? incoming : nil
        },
        apply: { [weak self] merged in
            guard let self else { return }
            let next = self.ledger.merging(remote: merged)
            guard next != self.ledger else { return }
            self.ledger = next
            guard let data = try? JSONEncoder().encode(self.ledger) else { return }
            DefaultsWrite.set(data, forKey: Self.storeKey)
        })

    func attach() { mirror.attach() }

    #if DEBUG
    /// `-addressesForget YES` — empty the ledger, so a probe starts clean.
    func forget() {
        ledger = LinkLedger()
        DefaultsWrite.remove(Self.storeKey)
    }
    #endif
}

extension ContactLink: KeyValueMirrored {
    var mirrorStamp: Date { at }
}
