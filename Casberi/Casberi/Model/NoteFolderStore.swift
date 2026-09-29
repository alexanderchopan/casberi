import Foundation
import Observation
import SwiftData

/// The Notes room's folder list on disk and in iCloud (prd §980).
///
/// `NoteFolderName` owns the rules; this owns where the list lives:
/// UserDefaults `notes.folders.local.v1` through `DefaultsWrite` (§721), and
/// the same `KeyValueMirror` the address book rides, behind the same
/// `icloud.sync` consent. A folder's MEMBERS are not here — each row carries
/// its own `Thing.folder` through CloudKit — so this list only has to keep a
/// folder that holds nothing yet.
@Observable
@MainActor
final class NoteFolderStore {
    static let shared = NoteFolderStore()

    private static let storeKey = "notes.folders.local.v1"

    /// Keyed by `NoteFolderName.key`, so two spellings are one folder.
    private(set) var folders: [String: NoteFolderEntry]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: NoteFolderEntry].self, from: data) {
            folders = decoded
        } else {
            folders = [:]
        }
        // `attach` reads the singleton, which does not exist until this
        // initializer returns (`ContactLinksStore`'s shape).
        DispatchQueue.main.async { Self.shared.attach() }
    }

    /// The stored names, unordered; the room orders them with the rows'
    /// names through `NoteFolderName.list`.
    var names: [String] { folders.values.map(\.name) }

    /// The room's list: the stored names and every name `rows` carries.
    func list(with rows: [Thing]) -> [String] {
        NoteFolderName.list(stored: names, filed: rows.map { $0.isLive ? $0.folder : nil })
    }

    // MARK: - Writes

    /// Make a folder, or find the one the name already is. Returns the name
    /// to file under, or nil for a name with nothing in it.
    @discardableResult
    func add(_ raw: String) -> String? {
        guard let clean = NoteFolderName.clean(raw) else { return nil }
        if let standing = NoteFolderName.existing(clean, in: names) { return standing }
        folders[NoteFolderName.key(clean)] = NoteFolderEntry(name: clean, at: .now)
        persist()
        return clean
    }

    /// Delete a folder: its rows are UNFILED, never deleted — they stay in
    /// All. The caller saves the context.
    func remove(_ name: String, in context: ModelContext) {
        let key = NoteFolderName.key(name)
        mirror.noteRemoval(key)
        folders[key] = nil
        persist()
        for thing in members(of: name, in: context) { thing.folder = nil }
    }

    /// Rename a folder and every row filed in it. Renaming onto another
    /// folder's name MERGES the two. Returns the name the rows now carry.
    @discardableResult
    func rename(_ old: String, to raw: String, in context: ModelContext) -> String? {
        guard let clean = NoteFolderName.clean(raw) else { return nil }
        let oldKey = NoteFolderName.key(old)
        let others = folders.filter { $0.key != oldKey }.map { $0.value.name }
        let target = NoteFolderName.existing(clean, in: others) ?? clean
        let newKey = NoteFolderName.key(target)
        if newKey != oldKey {
            mirror.noteRemoval(oldKey)
            folders[oldKey] = nil
        }
        folders[newKey] = NoteFolderEntry(name: target, at: .now)
        persist()
        for thing in members(of: old, in: context) { thing.folder = target }
        return target
    }

    /// Every live row filed under `name`, any spelling. A string-equality
    /// predicate can't fold case, so the fetch takes every filed row and the
    /// compare runs in Swift — the room is tens of rows.
    private func members(of name: String, in context: ModelContext) -> [Thing] {
        let key = NoteFolderName.key(name)
        let filed = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.folder != nil })
        return ((try? context.fetch(filed)) ?? []).filter {
            $0.isLive && $0.folder.map(NoteFolderName.key) == key
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        DefaultsWrite.set(data, forKey: Self.storeKey)
        mirror.push()
    }

    // MARK: - Mirror

    @ObservationIgnored private lazy var mirror = KeyValueMirror<NoteFolderEntry>(
        entriesKey: "notes.folders.v1",
        tombstonesKey: "notes.folders.tombstones.v1",
        localTombstonesKey: "notes.folders.tombstones.local.v1",
        snapshot: { [weak self] in self?.folders ?? [:] },
        newer: { incoming, standing in
            guard let standing else { return incoming }
            return incoming.at > standing.at ? incoming : nil
        },
        apply: { [weak self] merged in
            guard let self, merged != self.folders else { return }
            self.folders = merged
            guard let data = try? JSONEncoder().encode(merged) else { return }
            DefaultsWrite.set(data, forKey: Self.storeKey)
        })

    func attach() { mirror.attach() }
    func syncNow() { mirror.syncNow() }
}

/// One stored folder: its name as first made, and when it last changed.
struct NoteFolderEntry: Codable, Equatable {
    let name: String
    let at: Date
}

extension NoteFolderEntry: KeyValueMirrored {
    var mirrorStamp: Date { at }
}
