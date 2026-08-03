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

    /// Single-flight, but TIME-BOXED rather than a bare flag (2026-08-02).
    ///
    /// It was `running: Bool`, set before the walk and cleared in a `defer`.
    /// The walk reads iCloud Drive files, and those reads block with no
    /// timeout — so one evicted file could park the pass forever, and since
    /// the `defer` never ran, the flag never cleared. Every later refresh
    /// then returned at the guard without doing anything, for the rest of
    /// the app's life: no new files, and — because the prune lives after the
    /// walk — no deletions either. Reported 2026-08-02 as a folder holding
    /// two screenshots showing dozens in the app, with pull-to-refresh doing
    /// nothing. Both halves of that are this one flag.
    ///
    /// A stuck pass can't be cancelled (the block is inside synchronous
    /// FileManager calls, which ignore Task cancellation), so this doesn't
    /// try: it lets the NEXT pass through once the current one is past
    /// plausibly-alive, which is what actually restores the feature.
    @MainActor private static var runningSince: Date?
    private static let stuckAfter: TimeInterval = 120

    /// Extensions worth reading as text for a preview — everything else lands
    /// with just its size as the fact, since a binary's bytes aren't a useful
    /// preview and misdecoding them isn't worth the risk.
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "log", "yaml", "yml",
        "xml", "html", "htm", "rtf", "swift", "py", "js", "ts", "css",
    ]

    /// One regular file from a folder walk, with its ref (`Thing.sourceRef`
    /// form) and a FRESH `url` resolved in THIS walk — never reconstructed
    /// from a path string later. Shared by `refresh` and `heal`: a real bug,
    /// caught live 2026-07-29 ("still not showing images" after two prior
    /// fixes), was `heal` rebuilding each file's URL via
    /// `URL(fileURLWithPath: base + rel)` from a SEPARATE later resolution of
    /// the same bookmark — any standardization/symlink difference between
    /// the two resolutions silently points at the wrong path, which reads as
    /// "never enriches" with no error anywhere. One walk, one set of URLs,
    /// used immediately.
    private struct WalkedFile {
        let ref: String
        let url: URL
        let name: String
        let modified: Date
        let size: Int64
        /// False for an iCloud Drive file whose bytes aren't on this device
        /// yet. READING one blocks — `String(contentsOf:)` and the image
        /// reads synchronously wait on the download, with no timeout — so
        /// this is what lets a pass land the row NOW and read it later,
        /// instead of stalling on a file nobody asked for.
        ///
        /// A not-downloaded file is still PRESENT: it stays in the walk and
        /// therefore in `allRefs`, or the prune would read "not downloaded"
        /// as "deleted from the folder" and remove a file that is sitting
        /// right there.
        let isDownloaded: Bool
    }

    /// Walks the folder for every regular file outside dot-directories. Must
    /// run inside an active `startAccessingSecurityScopedResource` window on
    /// `folder` and off the main actor — the walk itself, and any resource
    /// read it does, can silently block on an iCloud download.
    /// nil means the walk itself couldn't start (folder moved/permission
    /// lost) — distinct from an empty array, a folder that's genuinely just
    /// empty right now. Callers rely on that distinction (`refresh` disconnects
    /// on nil, but a legitimately empty folder is not a failure).
    private static func walk(_ folder: URL) -> [WalkedFile]? {
        let fm = FileManager.default
        let base = folder.standardizedFileURL.path
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey,
                                      .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles]) else { return nil }
        // `allObjects` materializes the walk synchronously — iterating the
        // NSEnumerator directly is unavailable from async contexts in Swift 6.
        var result: [WalkedFile] = []
        for case let url as URL in walker.allObjects {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let std = url.standardizedFileURL
            let rel = String(std.path.dropFirst(base.count))
            // Metadata reads (size, dates, download status) are LOCAL even
            // for an evicted iCloud file — it's reading the CONTENTS that
            // blocks, which is why the flag rides along instead of the walk
            // trying to avoid these keys.
            let ubiquitous = values?.isUbiquitousItem == true
            let status = values?.ubiquitousItemDownloadingStatus
            result.append(WalkedFile(
                ref: "files:\(rel)", url: std, name: std.lastPathComponent,
                modified: values?.contentModificationDate ?? .distantPast,
                size: Int64(values?.fileSize ?? 0),
                isDownloaded: !ubiquitous || status == .current || status == .downloaded))
        }
        return result
    }

    /// Walks the folder for regular files, lands new ones as file things —
    /// newest 100 by modification date per sync, so a giant folder arrives in
    /// waves instead of flooding the feed — and PRUNES things whose file is
    /// no longer in the folder (deleted since the last sync; bug report,
    /// 2026-07-29: a removed file kept showing forever, since this only ever
    /// added). Pruning reads the SAME walk, so it can never disagree with
    /// what just landed. Returns nil when the folder can't be reached
    /// (moved/permission lost).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = FilesStore.shared
        guard store.connected else { return nil }
        if let since = runningSince, Date.now.timeIntervalSince(since) < Self.stuckAfter {
            return 0
        }
        // Clear only OUR marker: a stuck pass that finally returns must not
        // clear the marker of the pass that has since taken over.
        let mine = Date.now
        runningSince = mine
        defer { if runningSince == mine { runningSince = nil } }

        guard let folder = store.folderURL() else { return nil }
        let existing = IngestSupport.existingSourceRefs(context, source: "Files")

        // The walk + per-file preview read happen off the main thread: the
        // folder can be iCloud Drive, and FileManager/String(contentsOf:)
        // silently block on the iCloud download for any file they touch,
        // synchronously on the calling thread. Left on @MainActor, a large
        // or not-yet-downloaded folder freezes the UI and can trip the
        // main-thread watchdog.
        let outcome: (new: [(file: WalkedFile, preview: String)], allRefs: Set<String>)? =
            await Task.detached(priority: .userInitiated) {
                () -> (new: [(file: WalkedFile, preview: String)], allRefs: Set<String>)? in
                // False just means the URL wasn't security-scoped (an
                // in-sandbox folder) — reading still works; only balance
                // the stop when it began.
                let scoped = folder.startAccessingSecurityScopedResource()
                defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

                guard let files = walk(folder) else { return nil }
                let sorted = files.sorted { $0.modified > $1.modified }

                var new: [(file: WalkedFile, preview: String)] = []
                for file in sorted.prefix(100) where !existing.contains(file.ref) {
                    // An evicted iCloud file lands on its SIZE rather than
                    // its text — reading it would block this whole pass on a
                    // download nobody asked for, which is the stall that used
                    // to latch the single-flight flag forever. `heal` reads
                    // the text once the bytes are actually here.
                    new.append((file, file.isDownloaded
                        ? Self.preview(of: file.url, size: file.size)
                        : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)))
                }
                return (new, Set(files.map(\.ref)))
            }.value

        guard let outcome else { return nil }
        var added = 0
        for (file, preview) in outcome.new {
            let thing = Thing(
                kind: .file,
                title: file.name,
                content: preview,
                source: "Files",
                capturedAt: file.modified,
                sourceRef: file.ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }

        // Prune — any landed Files thing whose ref the walk didn't see this
        // time is gone from the folder. `existing` (fetched before the walk)
        // is the full prior set; anything in it but not in `outcome.allRefs`
        // was deleted since the last sync.
        var removed = 0
        var removedIDs: [UUID] = []
        if !existing.isEmpty {
            let goneRefs = existing.subtracting(outcome.allRefs)
            if !goneRefs.isEmpty {
                let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Files" })
                for thing in (try? context.fetch(descriptor)) ?? [] {
                    guard let ref = thing.sourceRef, goneRefs.contains(ref) else { continue }
                    removedIDs.append(thing.id)
                    context.delete(thing)
                    removed += 1
                }
            }
        }

        if added > 0 || removed > 0 {
            context.saveHonestly()
            SpotlightIndex.remove(ids: removedIDs)
        }
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

    /// Whether a Files/`files:`-ref'd thing is an IMAGE file — the membership
    /// test the mixed Files room (grid vs rows) and its topic map share with
    /// the heal above, so "what counts as an image" can never fork between
    /// the pass that makes the thumbnail and the screens that draw it. Kept
    /// on the sourceRef's extension rather than `previewImageData != nil` so
    /// the claim is explicit: a thumbnail proves an image, but an image whose
    /// heal hasn't reached it yet is still an image.
    static func isImageRef(_ sourceRef: String?) -> Bool {
        guard let ref = sourceRef, ref.hasPrefix("files:") else { return false }
        let rel = String(ref.dropFirst("files:".count))
        return imageExtensions.contains((rel as NSString).pathExtension.lowercased())
    }

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
            // Third-party capture tools whose default names are just as
            // machine-generated as the OS's own — CleanShot X is the popular
            // one (2026-07-29, seen live: "CleanShot 2026-07-29 at
            // 20.48.52@2x.png").
            || lower.hasPrefix("cleanshot")
    }

    /// Single-flight, same reason as `runningSince` above and as
    /// `ScreenshotIngest.healing`: this loop awaits (thumbnail/OCR) between
    /// fetching `things` and mutating one, so a second overlapping call could
    /// read/write a `Thing` a first call's save already moved past. TIME-BOXED
    /// for the same reason `refresh`'s is — this pass reads file CONTENTS
    /// (thumbnail, OCR) and an evicted iCloud file blocks those with no
    /// timeout, so a bare flag can latch and never clear.
    @MainActor private static var healingSince: Date?

    /// Thumbnails, OCRs, and retitles the image files a sync already landed —
    /// the same land-fast/heal-later split `ScreenshotIngest.heal` uses,
    /// since a folder can be large (or live on iCloud Drive, not yet fully
    /// downloaded) and must never block the walk in `refresh`. Capped per
    /// pass so a big folder arrives in waves; returns what it actually did.
    @MainActor
    static func heal(context: ModelContext) async -> (thumbed: Int, ocred: Int) {
        if let since = healingSince, Date.now.timeIntervalSince(since) < Self.stuckAfter {
            return (0, 0)
        }
        let mine = Date.now
        healingSince = mine
        defer { if healingSince == mine { healingSince = nil } }

        guard let folder = FilesStore.shared.folderURL() else { return (0, 0) }

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

        // A FRESH walk, matched to `things` by ref — see `WalkedFile`'s doc
        // for why this replaced reconstructing each path from a string.
        let byRef: [String: URL] = await Task.detached(priority: .utility) { () -> [String: URL] in
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            var map: [String: URL] = [:]
            for f in walk(folder) ?? [] { map[f.ref] = f.url }
            return map
        }.value

        var thumbed = 0, ocred = 0
        var reindex: [Thing] = []
        for thing in things {
            // Not in the current walk — moved or deleted since this Thing
            // landed; `refresh` prunes it on its own next pass. Nothing to
            // read here.
            guard let ref = thing.sourceRef, let fileURL = byRef[ref] else { continue }
            let originalName = fileURL.lastPathComponent

            // Bound the per-pass work — the rest heal on later passes, same
            // as Photos.
            if thing.previewImageData == nil, thumbed < 40,
               let data = await thumbnail(url: fileURL) {
                thing.previewImageData = data
                thumbed += 1
            }
            // OCR is heavier than a thumbnail — a tighter bound; `ocrAt`
            // marks the attempt so a text-less image is never re-read.
            if thing.ocrAt == nil, ocred < 12 {
                let result = await ocrRead(url: fileURL)
                // `attempted == false` means the pixels couldn't be loaded at
                // all this pass (an iCloud file not yet downloaded, most
                // likely) — NOT the same as "read fine, found no words".
                // Leaving `ocrAt` nil here is load-bearing: a real bug, caught
                // live 2026-07-29, set `ocrAt = .now` regardless of whether
                // OCR actually ran, permanently recording "done" for a file
                // that was never read and could then never be retried once
                // its bytes WERE available.
                if result.attempted {
                    if let text = result.text {
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
                        // Read fine, genuinely no words — clear the byte-size
                        // line `preview()` landed it with, so an OCR'd-and-
                        // wordless image reads as genuinely empty, the same
                        // signal `FeedScreen.isWordless` reads off a Photos
                        // screenshot. Once there's a thumbnail the picture
                        // carries the row; the size was never the point.
                        thing.content = ""
                    }
                    thing.ocrAt = .now
                    ocred += 1
                }
            }
        }
        if thumbed > 0 || ocred > 0 {
            context.saveHonestly()
            SpotlightIndex.index(reindex)
        }
        return (thumbed, ocred)
    }

    /// One small JPEG for the corpus — 480pt longest side, the same target
    /// `ScreenshotIngest.thumbnail` uses, so every `previewImageData` reader
    /// (`PhotoWell`, the sheet) already knows how to size it. No pre-flight
    /// readiness check — `CGImageSourceCreateWithURL` fails safely (nil) if
    /// it can't get bytes, and this already runs detached, so an iCloud
    /// download it has to wait through costs this background task, never the
    /// UI thread. Guessing at readiness from iCloud metadata cost two
    /// separate live bugs (2026-07-29); just attempting the read is simpler
    /// and can't disagree with reality the way a heuristic can.
    private static func thumbnail(url: URL) async -> Data? {
        await Task.detached(priority: .utility) { () -> Data? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
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
    /// `attempted == false` means the image couldn't be loaded at all (see
    /// `thumbnail`'s doc on why there's no readiness pre-check) — the caller
    /// must not treat that as "read, no text", or it can never retry once
    /// the bytes really are available.
    private static func ocrRead(url: URL) async -> (attempted: Bool, text: String?) {
        let cg: CGImage? = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }.value
        guard let cg else { return (false, nil) }
        return (true, await ScreenshotOCR.text(for: cg))
    }
}
