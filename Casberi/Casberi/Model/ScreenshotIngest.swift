import Photos
import SwiftData
import UIKit

/// Screenshot ingestion through PhotoKit (M1 capture path). The permission ask
/// happens in context — connecting the Photos bridge is the moment of unlock —
/// and connect ends in proof: found screenshots land as things immediately.
enum ScreenshotIngest {

    /// Requests read access if needed and ingests recent screenshots.
    /// Returns the number of new things, or nil when access was declined.
    @MainActor
    static func connectAndIngest(context: ModelContext, limit: Int = 20) async -> Int? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let added = ingest(context: context, limit: limit)
        // Thumbnails save behind the connect proof, never blocking it.
        Task { @MainActor in _ = await heal(context: context) }
        return added
    }

    /// Ingests the most recent screenshots as things, deduped on the asset id.
    @MainActor
    static func ingest(context: ModelContext, limit: Int = 20) -> Int {
        ingestWithReport(context: context, limit: limit).added
    }

    /// The real ingest, exposed with a per-path count so Diagnostics can show
    /// exactly what each fetch found — the field-report pattern for a
    /// silent-drop bug ("no new screenshots" while Photos has them).
    @MainActor
    static func ingestWithReport(context: ModelContext, limit: Int = 20)
    -> (added: Int, albumFound: Int, predicateFound: Int, merged: Int)
    {
        // Two independent fetches, unioned by localIdentifier:
        //  1) The Screenshots smart album — iOS's own list, updated by the
        //     screenshot capture pipeline itself. Direct, no predicate.
        //  2) The mediaSubtypes predicate — the historical path. Field report
        //     2026-07-24 (build 138, iOS 26): only the album path caught new
        //     screenshots on the reporter's device; the mediaSubtypes predicate
        //     silently returned zero for newer captures while still returning
        //     older ones. Keeping the predicate as a second source is a cheap
        //     safety net for whatever the album misses (edited screenshots
        //     saved as new assets, third-party capture apps, etc.).
        let sort = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let albumOptions = PHFetchOptions()
        albumOptions.sortDescriptors = sort
        albumOptions.fetchLimit = limit
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        var albumAssets: [PHAsset] = []
        albums.enumerateObjects { collection, _, _ in
            PHAsset.fetchAssets(in: collection, options: albumOptions)
                .enumerateObjects { asset, _, _ in albumAssets.append(asset) }
        }

        let predicateOptions = PHFetchOptions()
        predicateOptions.sortDescriptors = sort
        predicateOptions.fetchLimit = limit
        predicateOptions.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        var predicateAssets: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: predicateOptions)
            .enumerateObjects { asset, _, _ in predicateAssets.append(asset) }

        var merged: [PHAsset] = []
        var seenIDs: Set<String> = []
        for asset in (albumAssets + predicateAssets) {
            guard !seenIDs.contains(asset.localIdentifier) else { continue }
            seenIDs.insert(asset.localIdentifier)
            merged.append(asset)
        }

        #if DEBUG
        // Simulator photo libraries rarely hold true screenshots; fall back to
        // recent images so the connect-ends-in-proof path can be demonstrated.
        if merged.isEmpty {
            let fallback = PHFetchOptions()
            fallback.sortDescriptors = sort
            fallback.fetchLimit = min(limit, 4)
            PHAsset.fetchAssets(with: .image, options: fallback)
                .enumerateObjects { asset, _, _ in merged.append(asset) }
        }
        #endif

        let existing = IngestSupport.existingSourceRefs(context, source: "Photos")

        var added = 0
        for asset in merged {
            guard !existing.contains(asset.localIdentifier) else { continue }
            let date = asset.creationDate ?? .now
            let thing = Thing(
                kind: .screenshot,
                title: "Screenshot",   // when it landed is capturedAt — no timestamp noise in the title
                source: "Photos",
                createdAt: date,
                capturedAt: date,
                sourceRef: asset.localIdentifier
            )
            context.insert(thing)
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return (added, albumAssets.count, predicateAssets.count, merged.count)
    }

    /// The screenshot corpus heals itself (2026-07-10). Three passes over
    /// every Photos screenshot thing:
    ///   1. THUMBNAIL — a thing whose asset still exists but carries no stored
    ///      picture gets a small JPEG saved into the corpus, so the row
    ///      survives the original later leaving Photos.
    ///   1b. OCR (prd §67 ⑤) — a thing whose text was never read gets it read
    ///      off the pixels into `content` (bounded per pass, `ocrAt` marks the
    ///      attempt either way), so search, the semantic index, Spotlight, and
    ///      answers see what the screenshot SAYS. The embedding clears so the
    ///      foreground sweep re-embeds with the new words.
    ///   2. RECONCILE — a thing whose asset is CONFIRMED gone (full library
    ///      access, the fetch finds nothing, and no thumbnail was ever saved)
    ///      is removed: it could only ever render as its hue-field fallback
    ///      (the "green square"), which reads as a bug, not a record. Under
    ///      LIMITED access nothing is removed — an unselected asset is
    ///      indistinguishable from a deleted one, and re-granting would have
    ///      brought it back.
    @MainActor
    static func heal(context: ModelContext) async -> (thumbed: Int, ocred: Int, removed: Int) {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Photos" })
        // Kind filters run in memory — #Predicate can't compare Codable enums.
        let things = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.kind == .screenshot && $0.sourceRef != nil }
        guard !things.isEmpty else { return (0, 0, 0) }

        let ids = things.map { $0.sourceRef!.replacingOccurrences(of: "phasset:", with: "") }
        var found: Set<String> = []
        var assets: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in
                found.insert(asset.localIdentifier)
                assets[asset.localIdentifier] = asset
            }
        let fullAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized

        var thumbed = 0, ocred = 0, removed = 0
        var removedIDs: [UUID] = []
        var reindex: [Thing] = []
        for (thing, id) in zip(things, ids) {
            if let asset = assets[id] {
                // Bound the per-refresh work — the rest heal on later passes.
                if thing.previewImageData == nil, thumbed < 40,
                   let data = await thumbnail(asset) {
                    thing.previewImageData = data
                    thumbed += 1
                }
                // OCR is heavier than a thumbnail — a tighter bound; `ocrAt`
                // marks the attempt so a text-less photo is never re-read.
                if thing.ocrAt == nil, ocred < 12 {
                    if let text = await ScreenshotOCR.text(for: asset) {
                        thing.content = text
                        thing.embedding = nil   // re-embed with the new words
                        reindex.append(thing)   // Spotlight learns them too
                    }
                    thing.ocrAt = .now
                    ocred += 1
                }
            } else if fullAccess, thing.previewImageData == nil, !found.contains(id) {
                removedIDs.append(thing.id)
                context.delete(thing)
                removed += 1
            }
        }
        if thumbed > 0 || ocred > 0 || removed > 0 {
            context.saveHonestly()
            SpotlightIndex.remove(ids: removedIDs)
            SpotlightIndex.index(reindex)
        }
        return (thumbed, ocred, removed)
    }

    /// One small JPEG for the corpus — 480pt longest side is retina-sharp at
    /// every row size and a detail-sheet preview, tens of KB, and safe to
    /// mirror through CloudKit.
    private static func thumbnail(_ asset: PHAsset) async -> Data? {
        let loaded: UIImage? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true   // iCloud-optimized originals
            opts.deliveryMode = .highQualityFormat
            var reported = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 480, height: 480),
                contentMode: .aspectFill, options: opts
            ) { img, info in
                // Skip the degraded first callback so the real image isn't
                // discarded (the PhotoWell/GenCover fix).
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                guard !reported else { return }
                reported = true
                cont.resume(returning: img)
            }
        }
        return loaded?.jpegData(compressionQuality: 0.7)
    }
}
