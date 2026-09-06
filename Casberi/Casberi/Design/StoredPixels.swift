import UIKit
import SwiftData

/// One decoded copy of a row's OWN stored pixels (prd §626, 2026-09-06).
///
/// **The cost this removes, and where it was found.** Five view builders read
/// `thing.previewImageData` and call `UIImage(data:)` **inside a view body** —
/// `PostCard.liveBody` (a FEED ROW), `ThingContent.kindSwitch`,
/// `SocialPostViews.photos`, `NoteSheetViews.thumb(_:)` and one more sheet
/// body. Two costs ride on every one of those evaluations:
///
///   1. `previewImageData` is `@Attribute(.externalStorage)`, so reading it
///      faults a separate file off disk rather than reading a column;
///   2. `UIImage(data:)` returns a NEW image object whose backing bitmap is
///      decoded lazily at draw time — so a fresh one per body pass throws the
///      decoded bitmap away and pays the full decode again at the next draw.
///
/// And a row's body is not evaluated once. **SwiftUI re-evaluates a LEAF
/// view's body on the model's own observation, through that leaf's own
/// attribute node, with no involvement from the parent** (liveness corollary
/// 5, build 188) — and this app writes to the store constantly during a
/// foreground sweep, every bridge save re-emitting every live `@Query`. So
/// the decode ran again and again, in the rooms that carry pictures, which
/// are the bulk-import rooms this whole perf effort is about.
///
/// **Nothing in the perf record covers this.** `docs/perf-spec.md` P3 names
/// `previewImageData != nil` as a disk read and proposes memoising the
/// EXISTENCE test; it never noticed that five call sites read the bytes and
/// decode them. There is no scroll instrument, so nothing measured it either.
/// Stated as this file's rule 3 requires: **this work no longer runs per body
/// evaluation; it runs once per row per foreground sweep.**
///
/// **POSITIVES ONLY, and that is the whole safety argument.** A row with no
/// stored pixels is not remembered, so the nil → pixels transition needs no
/// invalidation at all: a miss re-reads, every time, exactly as today. That
/// matters because a sweep's slots keep landing thumbnails after
/// `runForegroundWork()` has returned, so any "no pixels" memo would have to
/// outlive writes it cannot see. Caching only what exists makes the whole
/// question disappear, and leaves the empty case behaving precisely as it did
/// before this file existed.
///
/// **Invalidation is ONE line, because of a fact worth recording.** Every
/// write to an *existing* row's `previewImageData` happens inside a foreground
/// sweep — `ScreenshotIngest`, `FilesBridge` and `SnapchatImport` write only
/// when it `== nil`, `InstagramCaptions` fills a cover, and `ContactsIngest`
/// clears one for a contact who removed their photo. The only writes outside a
/// sweep (`RootShell.saveDroppedFile`, `DemoCorpus`, `DemoSeedAll`) are on a
/// Thing being CREATED, so its id has never been cached. Hence `flush()` at
/// the sweep's end covers every replacement, with no per-site call to forget
/// and no drift between a writer and a cache it does not know about.
///
/// Firing that flush EARLY is harmless — a positive entry dropped early costs
/// one re-decode, never a wrong picture.
///
/// **Bounded by COST, not by count** — `RemoteThumb`'s ruling in
/// `ShapedRows.swift`, for the same reason: a card-width post image is ~30× a
/// 26pt thumb, so no entry count can speak for both. The cost is the decoded
/// bitmap's own bytes where the image can report them.
@MainActor
enum StoredPixels {

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        // Half of `RemoteThumb`'s 48MB: these are the app's own stored
        // thumbnails, capped at one size by every writer, where that cache
        // holds full-width remote media at several sizes per URL.
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    /// The row's stored picture, decoded at most once per sweep.
    ///
    /// Returns nil when the row has no stored pixels or the bytes will not
    /// decode — the same answer, and the same nil-ness, as the
    /// `if let data = …, let img = UIImage(data: data)` this replaces.
    static func image(for thing: Thing) -> UIImage? {
        // `isLive` FIRST: this is called from view bodies, and reading a
        // stored property on a tombstoned model traps inside SwiftData
        // (liveness corollary 5, the whole reason these bodies are guarded).
        // Reading `id` on a dead model is exactly what the guard forbids.
        guard thing.isLive else { return nil }
        let key = thing.id.uuidString as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = thing.previewImageData, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: cost(of: image, fallback: data.count))
        return image
    }

    /// Drop everything. Called once at the end of a foreground sweep — see the
    /// invalidation paragraph above for why one call covers every writer.
    static func flush() { cache.removeAllObjects() }

    /// Decoded bitmap bytes where the image can say, the encoded length
    /// otherwise. A `UIImage` made from data has a `cgImage`, so the fallback
    /// is for the shapes that do not (a CIImage-backed or animated one) rather
    /// than a common path.
    private static func cost(of image: UIImage, fallback: Int) -> Int {
        guard let cg = image.cgImage else { return fallback }
        return cg.bytesPerRow * cg.height
    }
}
