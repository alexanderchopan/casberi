import Photos
import SwiftData

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
        return ingest(context: context, limit: limit)
    }

    /// Ingests the most recent screenshots as things, deduped on the asset id.
    @MainActor
    static func ingest(context: ModelContext, limit: Int = 20) -> Int {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        var assets = PHAsset.fetchAssets(with: .image, options: options)

        #if DEBUG
        // Simulator photo libraries rarely hold true screenshots; fall back to
        // recent images so the connect-ends-in-proof path can be demonstrated.
        if assets.count == 0 {
            let fallback = PHFetchOptions()
            fallback.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fallback.fetchLimit = min(limit, 4)
            assets = PHAsset.fetchAssets(with: .image, options: fallback)
        }
        #endif

        let existing = Set(
            ((try? context.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate { $0.sourceRef != nil }
            ))) ?? []).compactMap(\.sourceRef)
        )

        var added = 0
        assets.enumerateObjects { asset, _, _ in
            guard !existing.contains(asset.localIdentifier) else { return }
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
        if added > 0 { try? context.save() }
        return added
    }
}
