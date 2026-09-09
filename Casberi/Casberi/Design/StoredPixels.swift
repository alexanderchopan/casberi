import UIKit
import SwiftUI
import SwiftData
import ImageIO

/// One decoded copy of a row's OWN stored pixels (prd §626, 2026-09-06),
/// decoded OFF the main thread and forgotten per row (2026-09-08).
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
/// **What the second pass changed (2026-09-08), and why.** The first cut
/// memoised the `UIImage` but still built it with `UIImage(data:)`, whose
/// bitmap is decoded lazily AT DRAW — on the main thread, inside the
/// CoreAnimation commit — so a room of card-width posts still paid every
/// JPEG decode on main the first time each row scrolled in. And the memo was
/// flushed whole at the end of EVERY foreground sweep, so every return to
/// the app re-decoded every visible picture on main during the first scroll:
/// the "once in a while it lags" that survived six perf passes. Now:
///
///   • the bytes are read on main (an external-storage file, cheap and
///     unavoidable — the model lives on the main context), the pixel size is
///     read from the image HEADER without decoding, and the decode itself
///     runs on a utility task through `preparingForDisplay()`, which hands
///     back a bitmap CoreAnimation can commit without decoding again;
///   • a row that asks before the bitmap is ready draws a well the picture's
///     own shape (`StoredPicture`) and the bitmap fades in — `RemoteThumb`'s
///     grammar for a fresh arrival, a pop for a cache hit;
///   • the memo is forgotten PER ROW by the five writers that can replace an
///     existing picture (`forget(_:)`), never flushed whole. A writer that
///     only fills a nil (`ScreenshotIngest`, `FilesBridge`) needs no call: a
///     nil is remembered for at most `absentTTL`, so a picture that lands
///     from a sweep or a CloudKit import shows within the minute with no
///     invalidation at all, and a positive is never wrong.
///
/// `scripts/row-cost-audit.py` pins the writers' `forget` calls in place of
/// the old sweep-end flush, with a mutation for each.
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

    /// A decode in flight, one per row, so ten body passes during the decode
    /// share one task instead of reading the file ten times.
    private static var inflight: [UUID: Task<UIImage?, Never>] = [:]
    /// The pixel size read from the header, kept so a placeholder can hold the
    /// picture's shape before the bitmap exists — and so `probe` stays a memo
    /// hit after the bitmap has been evicted by cost.
    private static var sizes: [UUID: CGSize] = [:]
    /// Rows known to hold no picture, with the moment that was learned. A
    /// negative is the one answer a writer this cache cannot see could make
    /// stale (a heal, a CloudKit import), so it expires by itself.
    private static var absent: [UUID: Date] = [:]
    static let absentTTL: TimeInterval = 60

    // MARK: Reading

    /// The decoded bitmap, if it is already in the memo. Never touches the
    /// store; safe in any body.
    static func cached(for thing: Thing) -> UIImage? {
        guard thing.isLive else { return nil }
        return cache.object(forKey: thing.id.uuidString as NSString)
    }

    /// Whether the row holds a picture, and its pixel size — answered from the
    /// memo where it can be, from the image HEADER (no decode) where it must
    /// read, and starting the off-main decode as a side effect so the bitmap
    /// is usually ready by the time the view built on this answer draws.
    ///
    /// Nil means no stored picture, or bytes that will not decode: the same
    /// nil-ness as the `if let data = …, let img = UIImage(data: data)` this
    /// replaces, so every `else if` chain built on it keeps its branches.
    static func probe(_ thing: Thing) -> CGSize? {
        // `isLive` FIRST: this is called from view bodies, and reading a
        // stored property on a tombstoned model traps inside SwiftData
        // (liveness corollary 5, the whole reason these bodies are guarded).
        guard thing.isLive else { return nil }
        let id = thing.id
        if let size = sizes[id] { return size }
        if let since = absent[id], Date().timeIntervalSince(since) < absentTTL { return nil }
        guard let data = thing.previewImageData, let size = headerSize(of: data) else {
            absent[id] = Date()
            return nil
        }
        absent[id] = nil
        sizes[id] = size
        startDecode(id: id, data: data)
        return size
    }

    /// The decoded bitmap, awaiting the off-main decode when it is not in the
    /// memo yet. `fresh` is true when this call had to wait — the caller's cue
    /// to fade the picture in rather than pop it.
    static func prepared(for thing: Thing) async -> (image: UIImage, fresh: Bool)? {
        if let hit = cached(for: thing) { return (hit, false) }
        guard probe(thing) != nil else { return nil }
        let id = thing.id
        guard let task = inflight[id] else {
            // Probed, sized, but no task: the bitmap was evicted by cost.
            // Re-read and decode once more.
            guard thing.isLive, let data = thing.previewImageData else { return nil }
            startDecode(id: id, data: data)
            return await prepared(for: thing)
        }
        guard let image = await task.value else { return nil }
        return (image, true)
    }

    /// The bitmap NOW, decoding on the calling thread when it must — for a
    /// sheet's poster and the Mac's Quick Look, never for a feed row.
    static func imageNow(for thing: Thing) -> UIImage? {
        if let hit = cached(for: thing) { return hit }
        guard probe(thing) != nil, thing.isLive,
              let data = thing.previewImageData,
              let image = UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data)
        else { return nil }
        remember(image, for: thing.id)
        return image
    }

    // MARK: Forgetting

    /// A writer that REPLACED (or cleared) an existing row's picture says so
    /// here, so the next read decodes the new bytes. Called by the five
    /// writers that can touch a row already drawn — see the header. A writer
    /// that only fills a nil need not call it; the negative memo expires.
    static func forget(_ id: UUID) {
        cache.removeObject(forKey: id.uuidString as NSString)
        inflight[id]?.cancel()
        inflight[id] = nil
        sizes[id] = nil
        absent[id] = nil
    }

    /// Drop everything. Kept for the demo mode's enter/leave, where every row
    /// changes at once; a sweep no longer calls it.
    static func flush() {
        cache.removeAllObjects()
        for task in inflight.values { task.cancel() }
        inflight.removeAll()
        sizes.removeAll()
        absent.removeAll()
    }

    // MARK: Decoding

    private static func startDecode(id: UUID, data: Data) {
        guard inflight[id] == nil else { return }
        inflight[id] = Task.detached(priority: .userInitiated) {
            // `preparingForDisplay` does the full decode here, on this task,
            // so the main thread commits a bitmap rather than a JPEG.
            let image = UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data)
            await MainActor.run {
                if let image, !Task.isCancelled { remember(image, for: id) }
                inflight[id] = nil
            }
            return Task.isCancelled ? nil : image
        }
    }

    private static func remember(_ image: UIImage, for id: UUID) {
        cache.setObject(image, forKey: id.uuidString as NSString,
                        cost: cost(of: image, fallback: 0))
    }

    /// Width and height from the image header — ImageIO reads the SOF marker
    /// and stops, so this is microseconds and allocates no bitmap.
    private static func headerSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0
        else { return nil }
        // EXIF orientation 5–8 swaps the axes the way `UIImage.size` will.
        if let o = props[kCGImagePropertyOrientation] as? UInt32, o >= 5 {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }

    /// Decoded bitmap bytes where the image can say, the encoded length
    /// otherwise. A `UIImage` made from data has a `cgImage`, so the fallback
    /// is for the shapes that do not (a CIImage-backed or animated one) rather
    /// than a common path.
    private static func cost(of image: UIImage, fallback: Int) -> Int {
        guard let cg = image.cgImage else { return max(fallback, 1) }
        return cg.bytesPerRow * cg.height
    }
}

/// A row's stored picture, drawn when its bitmap is ready.
///
/// Built on `StoredPixels.probe`, so the caller has already decided the
/// picture EXISTS and reserved its branch; this view only decides WHEN the
/// pixels show. Until then it draws a well the picture's own shape — the
/// layout never shifts when the bitmap lands — and a bitmap that had to be
/// decoded fades in with the token motion (`RemoteThumb`'s rule: arrival,
/// never a pop; a memo hit pops, because an already-known picture
/// re-appearing softly would read as re-loading).
struct StoredPicture<Content: View>: View {
    let thing: Thing
    let size: CGSize
    @ViewBuilder let content: (UIImage) -> Content
    @State private var image: UIImage?

    init(_ thing: Thing, size: CGSize, @ViewBuilder content: @escaping (UIImage) -> Content) {
        self.thing = thing
        self.size = size
        self.content = content
        _image = State(initialValue: StoredPixels.cached(for: thing))
    }

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`): this leaf
    /// re-evaluates on the model's own observation, so the guard is here,
    /// not in the parent that made it.
    var body: some View {
        if thing.isLive { liveBody }
    }

    private var liveBody: some View {
        Group {
            if let image {
                content(image)
            } else {
                content(Self.blank(size))
                    .hidden()
                    .overlay {
                        Rectangle().fill(DS.fillFaint)
                    }
            }
        }
        .task(id: thing.id) { await load() }
    }

    private func load() async {
        guard image == nil else { return }
        guard let (decoded, fresh) = await StoredPixels.prepared(for: thing) else { return }
        if fresh { withAnimation(DS.Motion.standard) { image = decoded } }
        else { image = decoded }
    }

    /// A transparent image of the picture's own pixel size, so the placeholder
    /// takes exactly the frame the caller's modifiers will give the picture.
    private static func blank(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in }
    }
}
