import Foundation
import Observation
import SwiftData

/// The Files bridge (2026-07-27) — watch any folder, not just an Obsidian
/// vault: the person picks a folder in the document picker, a security-scoped
/// bookmark remembers it, and whatever lands inside becomes findable things on
/// every sync. Same shape as `ObsidianBridge` (connect once, heal every
/// foreground) but for arbitrary files rather than Markdown notes — a
/// Downloads folder, a scans folder, anything iCloud Drive can point at.
/// Fully local — no account, no key, no network, and the folder itself is
/// never modified (read-only enumeration).
@Observable
final class FilesStore {
    static let shared = FilesStore()
    private static let bookmarkKey = "filesFolder.bookmark"
    private static let nameKey = "filesFolder.name"

    /// The folder's display name — proof of WHICH folder is connected.
    var folderName: String {
        didSet { UserDefaults.standard.set(folderName, forKey: Self.nameKey) }
    }

    private init() {
        folderName = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
    }

    var connected: Bool {
        UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    /// Saves the picked folder. Call within the picker's security-scoped
    /// access window.
    func setFolder(url: URL) -> Bool {
        guard let bookmark = try? url.bookmarkData() else { return false }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        folderName = url.lastPathComponent
        return true
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        folderName = ""
    }

    /// Resolves the bookmark to a live URL. Caller must balance
    /// `startAccessingSecurityScopedResource` / stop.
    func folderURL() -> URL? {
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

enum FilesIngest {

    @MainActor private static var running = false

    /// Extensions worth reading as text for a preview — everything else lands
    /// with just its size as the fact, since a binary's bytes aren't a useful
    /// preview and misdecoding them isn't worth the risk.
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "log", "yaml", "yml",
        "xml", "html", "htm", "rtf", "swift", "py", "js", "ts", "css",
    ]

    /// Walks the folder for regular files and lands new ones as file things —
    /// newest 100 by modification date per sync, so a giant folder arrives in
    /// waves instead of flooding the feed. Returns nil when the folder can't
    /// be reached (moved/permission lost).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = FilesStore.shared
        guard store.connected, !running else { return store.connected ? 0 : nil }
        running = true
        defer { running = false }

        guard let folder = store.folderURL() else { return nil }
        let existing = IngestSupport.existingSourceRefs(context, source: "Files")
        let base = folder.standardizedFileURL.path

        // The walk + per-file preview read happen off the main thread: the
        // folder can be iCloud Drive, and FileManager/String(contentsOf:)
        // silently block on the iCloud download for any file they touch,
        // synchronously on the calling thread. Left on @MainActor, a large
        // or not-yet-downloaded folder freezes the UI and can trip the
        // main-thread watchdog.
        let landed: [(ref: String, name: String, modified: Date, preview: String)]? =
            await Task.detached(priority: .userInitiated) { () -> [(ref: String, name: String, modified: Date, preview: String)]? in
                // False just means the URL wasn't security-scoped (an
                // in-sandbox folder) — reading still works; only balance
                // the stop when it began.
                let scoped = folder.startAccessingSecurityScopedResource()
                defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

                let fm = FileManager.default
                let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
                guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                 options: [.skipsHiddenFiles]) else { return nil }

                // Collect (url, modified, size) for every regular file
                // outside dot-directories. `allObjects` materializes the
                // walk synchronously — iterating the NSEnumerator directly
                // is unavailable from async contexts in Swift 6.
                var files: [(url: URL, modified: Date, size: Int64)] = []
                for case let url as URL in walker.allObjects {
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    guard values?.isRegularFile == true else { continue }
                    files.append((url, values?.contentModificationDate ?? .distantPast,
                                  Int64(values?.fileSize ?? 0)))
                }
                files.sort { $0.modified > $1.modified }

                var result: [(ref: String, name: String, modified: Date, preview: String)] = []
                for file in files.prefix(100) {
                    let rel = String(file.url.standardizedFileURL.path.dropFirst(base.count))
                    let ref = "files:\(rel)"
                    guard !existing.contains(ref) else { continue }
                    result.append((ref, file.url.lastPathComponent, file.modified,
                                    Self.preview(of: file.url, size: file.size)))
                }
                return result
            }.value

        guard let landed else { return nil }
        var added = 0
        for file in landed {
            let thing = Thing(
                kind: .file,
                title: file.name,
                content: file.preview,
                source: "Files",
                capturedAt: file.modified,
                sourceRef: file.ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    /// A short line describing a landed file — its text (readable formats,
    /// first 300 chars, the Obsidian-note shape) or just its size (everything
    /// else — a PDF, an image, a zip — where the bytes aren't a preview).
    private static func preview(of url: URL, size: Int64) -> String {
        if textExtensions.contains(url.pathExtension.lowercased()),
           let body = try? String(contentsOf: url, encoding: .utf8) {
            return String(body.prefix(300))
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
