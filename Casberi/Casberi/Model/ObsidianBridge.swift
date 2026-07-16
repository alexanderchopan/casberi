import Foundation
import Observation
import SwiftData

/// The Obsidian bridge (2026-07-08) — a vault is a plain folder of Markdown,
/// so it connects by POINTING AT THE FOLDER: the person picks their vault in
/// the document picker, a security-scoped bookmark remembers it, and notes
/// land as note things on every sync. Fully local — no account, no key, no
/// network, and the vault itself is never modified (read-only enumeration).
@Observable
final class ObsidianStore {
    static let shared = ObsidianStore()
    private static let bookmarkKey = "obsidian.bookmark"
    private static let nameKey = "obsidian.vaultName"

    /// The vault's display name — proof of WHICH folder is connected.
    var vaultName: String {
        didSet { UserDefaults.standard.set(vaultName, forKey: Self.nameKey) }
    }

    private init() {
        vaultName = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
    }

    var connected: Bool {
        UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    /// Saves the picked vault folder. Call within the picker's
    /// security-scoped access window.
    func setVault(url: URL) -> Bool {
        guard let bookmark = try? url.bookmarkData() else { return false }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        vaultName = url.lastPathComponent
        return true
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        vaultName = ""
    }

    /// Resolves the bookmark to a live URL. Caller must balance
    /// `startAccessingSecurityScopedResource` / stop.
    func vaultURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }
}

enum ObsidianIngest {

    @MainActor private static var running = false

    /// Walks the vault for Markdown files and lands new ones as note things —
    /// newest 100 by modification date per sync, so a giant vault arrives in
    /// waves instead of flooding the feed. Returns nil when the vault can't
    /// be reached (moved/permission lost).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = ObsidianStore.shared
        guard store.connected, !running else { return store.connected ? 0 : nil }
        running = true
        defer { running = false }

        guard let vault = store.vaultURL() else { return nil }
        // False just means the URL wasn't security-scoped (an in-sandbox
        // vault) — reading still works; only balance the stop when it began.
        let scoped = vault.startAccessingSecurityScopedResource()
        defer { if scoped { vault.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = fm.enumerator(at: vault, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles]) else { return nil }

        // Collect (url, modified) for every .md outside dot-directories.
        // `allObjects` materializes the walk synchronously — iterating the
        // NSEnumerator directly is unavailable from async contexts in Swift 6.
        var notes: [(url: URL, modified: Date)] = []
        for case let url as URL in walker.allObjects {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            notes.append((url, values?.contentModificationDate ?? .distantPast))
        }
        notes.sort { $0.modified > $1.modified }

        let existing = IngestSupport.existingSourceRefs(context)
        let base = vault.standardizedFileURL.path
        var added = 0

        for note in notes.prefix(100) {
            let rel = String(note.url.standardizedFileURL.path.dropFirst(base.count))
            let ref = "obsidian:\(rel)"
            guard !existing.contains(ref) else { continue }
            let body = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
            let thing = Thing(
                kind: .note,
                title: note.url.deletingPathExtension().lastPathComponent,
                content: String(body.prefix(300)),
                source: "Obsidian",
                capturedAt: note.modified,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }
}
