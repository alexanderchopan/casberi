import Foundation
import UIKit
import ImageIO
import SwiftData

/// The pictures inside an export folder (2026-08-05, prd §310).
///
/// WHY THE ROOMS WERE EMPTY. Every one of the four importers declined media for
/// the same reason, written into each of their type docs: the images "live
/// under `data/` as files relative to a temporary security-scoped folder, with
/// no copy-into-app-storage path here". That was true and it had a real cost —
/// Instagram is a photo app whose room in this app was a wall of text, and a
/// person who imported years of their own photographs got captions and nothing
/// to look at.
///
/// WHAT CHANGED IS THE FRAMING, not the constraint. The objection was to
/// COPYING originals — a decade of full-size photos into a CloudKit-mirrored
/// store is a genuinely bad idea, and still is. But every other picture in this
/// app is a 480pt thumbnail on `previewImageData` (`ScreenshotIngest`,
/// `FilesBridge`, `SnapchatImport` all write exactly that), and a thumbnail is
/// small enough to be the same class of object as the row's own text. So the
/// export's originals stay where they are, untouched and unreferenced, and what
/// lands is the same derived thumbnail every other reader in this app already
/// knows how to draw.
///
/// READ INSIDE THE SCOPED GRANT. These files are only reachable while the
/// importer's `startAccessingSecurityScopedResource` is held, which is exactly
/// why this happens during the import rather than as a later heal pass: there
/// is no second chance at a folder the person has stopped granting. That also
/// bounds it — a heal could take its time, an import cannot, so `perImport`
/// caps how many pictures one run will read.
///
/// UNMEASURED, like everything else that reads these exports. The relative
/// paths below come from the same parsers the importers were built against, and
/// a path that doesn't resolve simply yields no thumbnail — the row lands
/// exactly as it did before, with its text and its date.
enum ImportMedia {

    /// How many pictures one import will thumbnail. Each is a decode plus a
    /// re-encode, so this is the slowest thing in an import by a wide margin;
    /// the cap keeps a decade of photographs from turning one tap into several
    /// minutes. Rows past it land without a picture, which is what they did
    /// before this existed.
    static let perImport = 2_000

    /// One picture to read: a row's `sourceRef` and the file it names. Plain
    /// values on purpose — this is what crosses the await instead of a model.
    struct Job: Sendable {
        let ref: String
        let file: URL
    }

    /// Thumbnails every job. Takes NO `Thing`, so nothing can be tombstoned
    /// underneath it and the liveness rules have nothing to say about it.
    static func decode(_ jobs: [Job]) async -> [String: Data] {
        guard !jobs.isEmpty else { return [:] }
        var out: [String: Data] = [:]
        for job in jobs {
            if let data = await thumbnail(at: job.file) { out[job.ref] = data }
        }
        return out
    }

    /// Writes the decoded pixels back, synchronously — no suspension between
    /// the lookup and the write.
    @MainActor
    static func apply(_ pixels: [String: Data], to landed: [Thing]) {
        guard !pixels.isEmpty else { return }
        for thing in landed {
            guard let ref = thing.sourceRef, let data = pixels[ref] else { continue }
            thing.previewImageData = data
        }
    }

    /// A 480pt / q0.7 JPEG for a file inside the export, or nil.
    ///
    /// The same size and quality as every other `previewImageData` writer here
    /// — deliberately, so a row from an import is indistinguishable from a row
    /// from a connected folder and no reader needs to know which it got. Decode
    /// runs OFF the main actor: a JPEG decode is not something to do on the
    /// thread that is also trying to draw the progress line.
    static func thumbnail(at url: URL) async -> Data? {
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

    /// A 480pt / q0.7 JPEG for bytes already in hand, rather than a file on
    /// disk (2026-08-18, prd §395).
    ///
    /// Same size, same quality, same off-main decode as the file version above
    /// — one object, two doors — because a cover fetched from Instagram's CDN
    /// has to be indistinguishable from a picture read out of the export folder
    /// once it lands. `CGImageSourceCreateWithData` is the only difference.
    static func thumbnail(data: Data) async -> Data? {
        await Task.detached(priority: .utility) { () -> Data? in
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
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

    /// Resolves a path the export states RELATIVE to its own root, trying the
    /// picked folder and then one level down — the same two-level search every
    /// importer's own `read` does, and for the same reason: whether a person
    /// picks the folder they unzipped or the one it unzipped INTO is a coin
    /// flip.
    ///
    /// Refuses to leave the export. A relative path is data out of a file, and
    /// a `../../..` in one would otherwise read whatever it liked from the
    /// grant we are holding — so the resolved path must still sit under the
    /// root it was resolved against.
    static func resolve(_ relative: String, under root: URL) -> URL? {
        guard !relative.isEmpty, !relative.hasPrefix("/") else { return nil }
        let manager = FileManager.default
        var candidates = [root.appending(path: relative)]
        if let children = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for child in children
            where (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                candidates.append(child.appending(path: relative))
            }
        }
        let fence = root.standardizedFileURL.path
        for candidate in candidates {
            let resolved = candidate.standardizedFileURL
            guard resolved.path.hasPrefix(fence) else { continue }
            if manager.fileExists(atPath: resolved.path) { return resolved }
        }
        return nil
    }

    /// The picture for an X post, which the archive files by TWEET ID rather
    /// than by a path the JSON states: `data/tweets_media/<id>-<something>.jpg`.
    ///
    /// So this is a directory scan keyed on the id prefix, not a lookup — the
    /// one place these two exports genuinely differ. The directory is listed
    /// ONCE per import and handed back as an index, because doing it per post
    /// would be a full directory enumeration per row.
    static func xMediaIndex(under root: URL) -> [String: URL] {
        let manager = FileManager.default
        var roots = [root]
        if let children = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            roots += children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
        }
        var index: [String: URL] = [:]
        for base in roots {
            let dir = base.appending(path: "data/tweets_media")
            guard let files = try? manager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                // `<id>-<hash>.<ext>` — the id is everything before the first
                // dash. A post with several pictures yields several files; the
                // first wins, since `previewImageData` holds one.
                let name = file.lastPathComponent
                guard let dash = name.firstIndex(of: "-") else { continue }
                let id = String(name[name.startIndex..<dash])
                guard !id.isEmpty, index[id] == nil else { continue }
                index[id] = file
            }
            if !index.isEmpty { break }
        }
        return index
    }
}
