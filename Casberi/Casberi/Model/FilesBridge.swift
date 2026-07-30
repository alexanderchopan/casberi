import Foundation
import ImageIO
import Observation
import SwiftData
import UIKit

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

    // MARK: - Image enrichment (2026-07-27)

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp",
    ]

    /// A filename the person never typed — a camera/screenshot naming
    /// convention. The retitle heal only ever overwrites a title that still
    /// IS the raw filename and matches one of these (never a name someone in
    /// Files actually gave the file, and never a title this heal already
    /// rewrote — checked by comparing against the current filename, not a
    /// fixed placeholder, since there's no single placeholder string here the
    /// way `ScreenshotTitle.placeholder` is one for Photos).
    private static func isMachineGeneratedName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("img_") || lower.hasPrefix("img-")
            || lower.hasPrefix("screenshot") || lower.hasPrefix("screen shot")
            || lower.hasPrefix("pxl_") || lower.hasPrefix("dsc")
            || lower.hasPrefix("photo_") || lower.hasPrefix("photo-")
    }

    /// Single-flight, same reason as `running` above and as
    /// `ScreenshotIngest.healing`: this loop awaits (thumbnail/OCR) between
    /// fetching `things` and mutating one, so a second overlapping call could
    /// read/write a `Thing` a first call's save already moved past.
    @MainActor private static var healing = false

    /// Thumbnails, OCRs, and retitles the image files a sync already landed —
    /// the same land-fast/heal-later split `ScreenshotIngest.heal` uses,
    /// since a folder can be large (or live on iCloud Drive, not yet fully
    /// downloaded) and must never block the walk in `refresh`. Capped per
    /// pass so a big folder arrives in waves; returns what it actually did.
    @MainActor
    static func heal(context: ModelContext) async -> (thumbed: Int, ocred: Int) {
        guard !healing else { return (0, 0) }
        healing = true
        defer { healing = false }

        guard let folder = FilesStore.shared.folderURL() else { return (0, 0) }
        let base = folder.standardizedFileURL.path

        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Files" })
        // Kind/extension filters run in memory — #Predicate can't compare a
        // Codable enum or derive a path extension.
        let things = ((try? context.fetch(descriptor)) ?? [])
            .filter { thing in
                guard thing.kind == .file, let ref = thing.sourceRef,
                      ref.hasPrefix("files:") else { return false }
                let rel = String(ref.dropFirst("files:".count))
                guard imageExtensions.contains((rel as NSString).pathExtension.lowercased())
                else { return false }
                return thing.previewImageData == nil || thing.ocrAt == nil
            }
        guard !things.isEmpty else { return (0, 0) }

        // False just means the URL wasn't security-scoped (an in-sandbox
        // folder) — reading still works; only balance the stop when it began.
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        var thumbed = 0, ocred = 0
        var reindex: [Thing] = []
        for thing in things {
            guard let ref = thing.sourceRef else { continue }
            let rel = String(ref.dropFirst("files:".count))
            let fileURL = URL(fileURLWithPath: base + rel)
            let originalName = (rel as NSString).lastPathComponent

            // Bound the per-pass work — the rest heal on later passes, same
            // as Photos. Each of these skips (returns nil) rather than
            // blocking when the file lives on iCloud Drive and hasn't
            // downloaded yet — `isReady` checks before ever touching pixels.
            if thing.previewImageData == nil, thumbed < 40,
               let data = await thumbnail(url: fileURL) {
                thing.previewImageData = data
                thumbed += 1
            }
            // OCR is heavier than a thumbnail — a tighter bound; `ocrAt`
            // marks the attempt so a text-less image is never re-read.
            if thing.ocrAt == nil, ocred < 12 {
                if let text = await ocrText(url: fileURL) {
                    thing.content = text
                    thing.embedding = nil   // re-embed with the new words
                    reindex.append(thing)   // Spotlight learns them too
                    // Only ever overwrites a filename the camera/screenshot
                    // path gave it — a name someone in Files actually typed
                    // is never clobbered by machine-read text.
                    if thing.title == originalName, isMachineGeneratedName(originalName),
                       let read = ScreenshotTitle.from(text) {
                        thing.title = read
                    }
                } else {
                    // No words found — clear the byte-size line `preview()`
                    // landed it with, so an OCR'd-and-wordless image reads as
                    // genuinely empty, the same signal `FeedScreen.isWordless`
                    // reads off a Photos screenshot. Once there's a thumbnail
                    // the picture carries the row; the size was never the
                    // point.
                    thing.content = ""
                }
                thing.ocrAt = .now
                ocred += 1
            }
        }
        if thumbed > 0 || ocred > 0 {
            context.saveHonestly()
            SpotlightIndex.index(reindex)
        }
        return (thumbed, ocred)
    }

    /// Whether a file's bytes are actually here to read — an iCloud Drive
    /// placeholder that hasn't downloaded yet would otherwise trigger an
    /// implicit, blocking download the moment ImageIO opens it (the same
    /// risk `refresh`'s off-main walk exists to avoid). A plain local file
    /// (not a ubiquitous item at all) always passes.
    private static func isReady(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        else { return true }
        guard values.isUbiquitousItem == true else { return true }
        return values.ubiquitousItemDownloadingStatus == .current
    }

    /// One small JPEG for the corpus — 480pt longest side, the same target
    /// `ScreenshotIngest.thumbnail` uses, so every `previewImageData` reader
    /// (`PhotoWell`, the sheet) already knows how to size it.
    private static func thumbnail(url: URL) async -> Data? {
        await Task.detached(priority: .utility) { () -> Data? in
            guard isReady(url), let src = CGImageSourceCreateWithURL(url as CFURL, nil)
            else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            else { return nil }
            return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
        }.value
    }

    /// The pixels OCR reads — bigger than the row thumbnail (small text needs
    /// the resolution), still bounded, mirroring `ScreenshotOCR`'s own load.
    private static func ocrText(url: URL) async -> String? {
        let cg: CGImage? = await Task.detached(priority: .utility) {
            guard isReady(url), let src = CGImageSourceCreateWithURL(url as CFURL, nil)
            else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }.value
        guard let cg else { return nil }
        return await ScreenshotOCR.text(for: cg)
    }
}
