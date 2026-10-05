import Foundation
import Observation

/// The senders the person added to Day's Subscriptions tile from a mail's
/// sheet (prd §1115): a sender whose mail carries no list header, or mail
/// that landed before §1111 kept the headers. `SubscriptionStore`'s shape:
/// `UserDefaults` mirrored through iCloud key-value storage (`KeyValueMirror`),
/// a handful of small records, no `Thing` field and no CloudKit deploy.
///
/// It keeps the ADDRESS, keyed as `MailSubscriptions.key(listID: nil,
/// address:)` keys, so every mail from that sender files, the ones before the
/// add included (`MailSubscriptions.file`).
@Observable
@MainActor
final class MailSubscriptionStore {
    static let shared = MailSubscriptionStore()

    struct Entry: Codable, Equatable {
        /// The lowercased address.
        var id: String
        /// The sender's name when it was added.
        var name: String
        /// When it was added — the mirror's stamp.
        var at: Date
    }

    private static let storeKey = "mailSubscriptions.added.local.v1"

    private(set) var entries: [String: Entry]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
        // `attach` reads the singleton, which does not exist until this
        // initializer returns (`NoteFolderStore`'s shape).
        DispatchQueue.main.async { Self.shared.attach() }
    }

    /// The addresses the reading files.
    var addresses: Set<String> { Set(entries.keys) }

    // MARK: - Writes

    /// Adds a sender. Returns its key, or nil for an address that is not one.
    @discardableResult
    func add(address: String, name: String?) -> String? {
        guard let key = MailSubscriptions.key(listID: nil, address: address) else { return nil }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        entries[key] = Entry(id: key, name: trimmed.isEmpty ? key : trimmed, at: .now)
        persist()
        return key
    }

    /// Stops tracking a sender. Mail that carries a list header stays on the
    /// tile: only what the person added goes.
    func remove(address: String) {
        guard let key = MailSubscriptions.key(listID: nil, address: address),
              entries[key] != nil else { return }
        mirror.noteRemoval(key)
        entries[key] = nil
        persist()
    }

    /// Forget every added sender (`-mailSubscriptionAdd clear`).
    func removeAll() {
        for key in entries.keys { mirror.noteRemoval(key) }
        entries = [:]
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        DefaultsWrite.set(data, forKey: Self.storeKey)
        mirror.push()
    }

    // MARK: - Mirror

    @ObservationIgnored private lazy var mirror = KeyValueMirror<Entry>(
        entriesKey: "mailSubscriptions.added.v1",
        tombstonesKey: "mailSubscriptions.added.tombstones.v1",
        localTombstonesKey: "mailSubscriptions.added.tombstones.local.v1",
        snapshot: { [weak self] in self?.entries ?? [:] },
        newer: { incoming, standing in
            guard let standing else { return incoming }
            return incoming.at > standing.at ? incoming : nil
        },
        apply: { [weak self] merged in
            guard let self, merged != self.entries else { return }
            self.entries = merged
            guard let data = try? JSONEncoder().encode(merged) else { return }
            DefaultsWrite.set(data, forKey: Self.storeKey)
        })

    func attach() { mirror.attach() }
}

extension MailSubscriptionStore.Entry: KeyValueMirrored {
    var mirrorStamp: Date { at }
}
