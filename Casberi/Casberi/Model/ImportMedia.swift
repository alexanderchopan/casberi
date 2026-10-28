import Foundation
import AVFoundation
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
///
/// The X and Instagram importers that read most of this are deleted (prd
/// §1579); the journal imports thumbnail through it, and `FilesBridge` and
/// the note sheet share its readers.
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

    /// One frame from a video, written as the SAME 480pt JPEG the image path
    /// writes — so a video tiles in a room's grid through exactly the
    /// `previewImageData` route a photograph already uses, with no second
    /// field, no second code path in the grid, and no CloudKit deploy.
    ///
    /// Moved here from `FilesBridge` on 2026-08-18 (prd §396) for the X
    /// archive's videos; that importer is deleted (prd §1579) and
    /// `FilesBridge` is its one caller.
    ///
    /// Three decisions, each a wrong-looking poster if got wrong:
    ///
    /// `appliesPreferredTrackTransform` — without it every video shot in
    /// portrait posters on its side. The rotation lives in the track's
    /// transform, not the pixels, so the frame comes back landscape and
    /// perfectly plausible.
    ///
    /// The frame is taken a second IN, never at zero. A great many videos open
    /// on black (a fade, a shutter, a leading blank frame), and a black tile in
    /// a grid reads as a picture that failed to load rather than as the video
    /// it is. Short clips take their own midpoint instead, since one second
    /// into a 400ms clip is past the end.
    ///
    /// It opens the security scope ITSELF when handed a root: `AVURLAsset`
    /// opens a file by a stricter route than `CGImageSource` and answers a nil
    /// frame without it, indistinguishable from a video we cannot read.
    static func posterFrame(url: URL, folder: URL?) async -> Data? {
        await Task.detached(priority: .utility) { () -> Data? in
            let scoped = folder?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { folder?.stopAccessingSecurityScopedResource() } }

            let asset = AVURLAsset(url: url)
            guard let seconds = try? await CMTimeGetSeconds(asset.load(.duration)),
                  seconds.isFinite, seconds > 0 else { return nil }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            let at = CMTime(seconds: min(1, seconds / 2), preferredTimescale: 600)
            guard let cg = try? await generator.image(at: at).image else { return nil }
            return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
        }.value
    }

    /// Writes the decoded pixels back, synchronously — no suspension between
    /// the lookup and the write.
    @MainActor
    static func apply(_ pixels: [String: Data], to landed: [Thing]) {
        guard !pixels.isEmpty else { return }
        for thing in landed {
            guard let ref = thing.sourceRef, let data = pixels[ref] else { continue }
            thing.previewImageData = data
            StoredPixels.forget(thing.id)   // a drawn picture may be replaced — prd §626
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

    /// Every file in a named subdirectory of an export, keyed by its basename
    /// WITHOUT the extension (2026-08-17, prd §398).
    ///
    /// For the two journal exports, which both name their media by an opaque
    /// id and neither of which states a usable path:
    ///
    ///   * Day One's entry JSON carries `photos: [{ md5, type }]` and the file
    ///     lands at `photos/<md5>.<type>` — but `type` is the export's word for
    ///     the format ("jpeg", "heic") and does not always match the extension
    ///     on disk, so keying on the STEM sidesteps the mismatch entirely.
    ///   * Apple Journal's per-entry HTML carries `<img src="Resources/…">`
    ///     with a path relative to a directory whose depth is Apple's business,
    ///     not ours.
    ///
    /// ONE listing for the whole import, which is the point: a per-entry lookup
    /// would list the root's children on every call, and a fifteen-year journal
    /// would pay that thousands of times.
    ///
    /// No fence is needed here and its absence is not an oversight: every URL
    /// handed back was enumerated from INSIDE `root`, so there is no path out of
    /// a data file and no attacker-supplied component to escape with.
    static func mediaIndex(in subdirectory: String, under root: URL) -> [String: URL] {
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
            let dir = base.appending(path: subdirectory)
            guard let files = try? manager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                let stem = file.deletingPathExtension().lastPathComponent
                // FIRST WINS, so an export holding both a full-size picture and
                // a thumbnail of it under one stem can't have the answer depend
                // on the order the filesystem happened to enumerate them in.
                guard !stem.isEmpty, index[stem] == nil else { continue }
                index[stem] = file
            }
            if !index.isEmpty { break }
        }
        return index
    }
}
