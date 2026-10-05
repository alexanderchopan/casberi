import Foundation
import Observation

/// The subscriptions the person added by hand (prd §1105) — anything no card,
/// account or bill reading can see. Kept in `UserDefaults` and mirrored
/// through iCloud key-value storage (`KeyValueMirror`), `NoteFolderStore`'s
/// shape: a handful of small records, no `Thing` field and no CloudKit
/// deploy.
@Observable
@MainActor
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    private static let storeKey = "subscriptions.manual.local.v1"

    private(set) var entries: [String: Subscriptions.Manual]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: Subscriptions.Manual].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
        // `attach` reads the singleton, which does not exist until this
        // initializer returns (`NoteFolderStore`'s shape).
        DispatchQueue.main.async { Self.shared.attach() }
    }

    var all: [Subscriptions.Manual] {
        entries.values.sorted { $0.at < $1.at }
    }

    // MARK: - Writes

    /// Adds one, or replaces the one already kept under the same name.
    @discardableResult
    func add(name raw: String, amount: Double, currency: String = "USD", yearly: Bool,
             anchor: Date, paysWith: String?, site: String?) -> Subscriptions.Manual? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, amount > 0 else { return nil }
        let key = Subscriptions.key(name)
        let entry = Subscriptions.Manual(
            id: key, name: name, amount: amount, currency: currency, yearly: yearly,
            anchor: anchor, paysWith: paysWith, site: Self.cleanSite(site), at: .now)
        entries[key] = entry
        persist()
        return entry
    }

    func remove(_ id: String) {
        guard entries[id] != nil else { return }
        mirror.noteRemoval(id)
        entries[id] = nil
        persist()
    }

    /// "notion.so", whatever was typed: no scheme, no path, lowercased. Nil
    /// for anything that is not a host.
    static func cleanSite(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !s.isEmpty else { return nil }
        for prefix in ["https://", "http://", "www."] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        guard s.contains("."), !s.contains(" "), !s.hasPrefix("."), !s.hasSuffix(".") else { return nil }
        return s
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        DefaultsWrite.set(data, forKey: Self.storeKey)
        mirror.push()
    }

    // MARK: - Mirror

    @ObservationIgnored private lazy var mirror = KeyValueMirror<Subscriptions.Manual>(
        entriesKey: "subscriptions.manual.v1",
        tombstonesKey: "subscriptions.manual.tombstones.v1",
        localTombstonesKey: "subscriptions.manual.tombstones.local.v1",
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

extension Subscriptions.Manual: KeyValueMirrored {
    var mirrorStamp: Date { at }
}
