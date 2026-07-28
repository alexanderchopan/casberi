import Photos
import SwiftData
import UIKit

/// Screenshot ingestion through PhotoKit (M1 capture path). The permission ask
/// happens in context — connecting the Photos bridge is the moment of unlock —
/// and connect ends in proof: found screenshots land as things immediately.
/// A screenshot's title, read off its own OCR text (prd §218, 2026-07-25).
///
/// Screenshots were titled with the literal string "Screenshot" forever, while
/// their OCR text went straight into `content` and on to search, Spotlight and
/// the embedding index. So the app read every screenshot and then showed the
/// person the word "Screenshot" — four identical rows in a row on a real feed,
/// and (since the onboarding fork) potentially a new user's first impression of
/// the whole product.
///
/// The first meaningful LINE, not the first N characters: Vision returns one
/// line per recognized text region, top to bottom, and a screenshot's first
/// region is almost always the status bar — a bare clock. Taking a prefix of
/// the joined text would title half the corpus "9:41".
enum ScreenshotTitle {
    /// What a screenshot is called before (or without) readable text. Also the
    /// marker the retitle heal looks for, so it must stay in sync with the
    /// title `land` assigns.
    static let placeholder = "Screenshot"

    /// A clock ("9:41", "12:05 AM") — the status bar, present in nearly every
    /// iOS screenshot and never what the shot is about.
    private static let clock = /^\d{1,2}[:.]\d{2}(\s?[APap]\.?[Mm]\.?)?$/

    /// nil when the text carries nothing worth a title — the caller keeps the
    /// placeholder rather than inventing one (the honesty rule: a row that
    /// can't say what it is says "Screenshot", never a guess).
    static func from(_ ocrText: String) -> String? {
        let candidates = ocrText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                // Too short to mean anything: a stray glyph, a badge count, "OK".
                guard line.count >= 4 else { return false }
                // Needs a letter — "100%", "5G", "23:59" are chrome, not content.
                guard line.contains(where: { $0.isLetter }) else { return false }
                guard line.wholeMatch(of: clock) == nil else { return false }
                // Status-bar words that survive the tests above.
                return !["searching…", "searching...", "no service",
                         "wi-fi", "airplane mode"].contains(line.lowercased())
            }

        // Prefer the first line that reads like PROSE, not the first line
        // that merely passes the filters (measured 2026-07-25). Vision returns
        // regions top-to-bottom, and the top of a screenshot is chrome: on a
        // home-screen shot the first survivors were the widget labels "Apps"
        // and "Fitness" — which retitled three different screenshots
        // identically, the exact problem this change exists to fix, wearing a
        // different word. A line with three words is nearly always the content
        // (a message, a headline, a receipt line); a bare noun is nearly always
        // a label. Falls back through two words to any survivor, so a genuinely
        // terse screenshot still gets the best available line rather than none.
        func words(_ s: String) -> Int {
            s.split(whereSeparator: { $0 == " " || $0 == "\t" }).count
        }
        let best = candidates.first(where: { words($0) >= 3 })
            ?? candidates.first(where: { words($0) >= 2 })
            ?? candidates.first
        guard let best else { return nil }
        return best.count > 80 ? String(best.prefix(79)) + "…" : best
    }
}

enum ScreenshotIngest {

    /// Requests read access if needed and ingests recent screenshots.
    /// Returns the number of new things, or nil when access was declined.
    @MainActor
    static func connectAndIngest(context: ModelContext, limit: Int = 20) async -> Int? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        // A connect with nothing landed yet is a genuinely fresh start — a
        // cursor left over from a previous connect would skip the library.
        if !hasLandedScreenshots(context: context) { resetBackfill() }
        let added = ingest(context: context, limit: limit)
        // The rest of the library, and thumbnails, save behind the connect
        // proof — never blocking it.
        Task { @MainActor in
            backfill(context: context)
            _ = await heal(context: context)
        }
        return added
    }

    /// The AUTHORITATIVE gate for the foreground/pull refresh: does the app
    /// actually have Photos read access right now? Keying off this instead of
    /// the stored bridge status is the 2026-07-24 fix — new screenshots stopped
    /// refreshing because the `pho` bridge status had drifted off exactly
    /// `.connected` while full access was granted the whole time, so the old
    /// status-only gate silently skipped every ingest after connect.
    @MainActor
    static var hasAccess: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: return true
        default: return false
        }
    }

    /// LIMITED access — the app can only ever see the handful of assets the
    /// person picked in the system sheet. Every fetch below still succeeds and
    /// still returns "all the screenshots", so nothing in the ingest can tell
    /// this apart from a small library: new screenshots simply never appear
    /// (they aren't in the picked set) and older ones are missing wholesale.
    /// That is indistinguishable, from inside the app, from the bug it looks
    /// like — so the bridge has to SAY it (honesty rule); see `BridgeRefresh`
    /// and the Photos row on `BridgeDetailScreen`.
    @MainActor
    static var accessIsLimited: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
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
        let fetched = fetchScreenshots(limit: limit)
        let added = land(fetched.merged, context: context)
        // A head window where EVERY asset was new means the window was too
        // small for what arrived since the last pass — there are probably more
        // just past its edge (a screenshotting spree while the app sat in the
        // background). Re-open the walk so the tail can't be stranded; it
        // dedupes on the way back down and costs a few foregrounds.
        if added >= limit, backfillDone { resetBackfill() }
        return (added, fetched.albumFound.count, fetched.predicateFound.count, fetched.merged.count)
    }

    // MARK: - Backfill

    /// The head fetch above is `limit`-capped and newest-first, so it can only
    /// ever see the most recent handful of screenshots — which means the
    /// corpus was permanently truncated to whatever existed at connect plus
    /// whatever arrived after (report 2026-07-25: "they don't always show the
    /// photos that are in Photos, especially if they are a bit older").
    /// Nothing walked backwards. This does: each refresh takes the next batch
    /// deeper into the library, so a big library fills in progressively over a
    /// few foregrounds instead of never.
    ///
    /// The walk is by INDEX into each newest-first fetch, not by a creationDate
    /// cursor. A date cursor was the first shape and it silently dropped
    /// assets: `creationDate < cursor` skips EVERY asset tied on the boundary
    /// timestamp, and screenshots tie constantly (a burst, an import, anything
    /// batch-written). Measured 2026-07-25 on a 12-asset library — the walk
    /// landed 8 and declared itself finished. An index can't tie.
    private static let doneKey = "photos.backfill.done"
    private static func offsetKey(_ path: String) -> String { "photos.backfill.offset.\(path)" }

    /// Restarts the walk — for a genuinely fresh connect, or after the visible
    /// library widens (limited access picking more photos).
    static func resetBackfill() {
        UserDefaults.standard.removeObject(forKey: doneKey)
        for path in ["album", "predicate", "debug"] {
            UserDefaults.standard.removeObject(forKey: offsetKey(path))
        }
    }

    static var backfillDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    /// Real landed screenshots — the demo seeds share the "Photos" source but
    /// carry `sample:` refs, and counting them would make every fresh connect
    /// on a seeded install look like a re-connect.
    @MainActor
    private static func hasLandedScreenshots(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Photos" })
        return ((try? context.fetch(descriptor)) ?? []).contains {
            $0.kind == .screenshot && !($0.sourceRef ?? "sample:").hasPrefix("sample:")
        }
    }

    /// One batch of the backwards walk. Returns how many landed; 0 once the
    /// library is fully walked (and every pass after that costs nothing).
    ///
    /// An index walk re-reads a few assets when the library GROWS between
    /// passes (newest-first, so new items shift the window shallower) — those
    /// dedupe out on `sourceRef` and cost nothing. That direction is the safe
    /// one: it re-walks rather than skips.
    @MainActor
    @discardableResult
    static func backfill(context: ModelContext, batch: Int = 200) -> Int {
        guard hasAccess, !backfillDone else { return 0 }

        var assets: [PHAsset] = []
        var exhausted = true
        for path in walkPaths() {
            let offset = UserDefaults.standard.integer(forKey: offsetKey(path.name))
            let total = path.result.count
            guard offset < total else { continue }
            let end = min(offset + batch, total)
            assets.append(contentsOf: path.result.objects(at: IndexSet(integersIn: offset..<end)))
            UserDefaults.standard.set(end, forKey: offsetKey(path.name))
            if end < total { exhausted = false }
        }
        if exhausted { UserDefaults.standard.set(true, forKey: doneKey) }

        // Dedupe across the paths before landing — the same screenshot is in
        // both the album and the mediaSubtypes fetch.
        var merged: [PHAsset] = []
        var seen: Set<String> = []
        for asset in assets where !seen.contains(asset.localIdentifier) {
            seen.insert(asset.localIdentifier)
            merged.append(asset)
        }
        return land(merged, context: context)
    }

    /// The walk's sources, each as a full newest-first fetch result.
    /// `PHFetchResult` is lazy — `count` and a windowed `objects(at:)` don't
    /// materialize the rest of the library.
    @MainActor
    private static func walkPaths() -> [(name: String, result: PHFetchResult<PHAsset>)] {
        let sort = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let albumOptions = PHFetchOptions()
        albumOptions.sortDescriptors = sort
        var paths: [(String, PHFetchResult<PHAsset>)] = []
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        if let screenshots = albums.firstObject {
            paths.append(("album", PHAsset.fetchAssets(in: screenshots, options: albumOptions)))
        }

        let predicateOptions = PHFetchOptions()
        predicateOptions.sortDescriptors = sort
        predicateOptions.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        paths.append(("predicate", PHAsset.fetchAssets(with: .image, options: predicateOptions)))

        #if DEBUG
        // A simulator library holds no true screenshots, so neither path above
        // has anything to walk — fall back to ordinary images, exactly as the
        // head fetch does, so this path stays demonstrable off-device.
        if paths.allSatisfy({ $0.1.count == 0 }) {
            let fallback = PHFetchOptions()
            fallback.sortDescriptors = sort
            return [("debug", PHAsset.fetchAssets(with: .image, options: fallback))]
        }
        #endif
        return paths
    }

    // MARK: - Fetch & land

    /// Two independent fetches, unioned by localIdentifier:
    ///  1) The Screenshots smart album — iOS's own list, updated by the
    ///     screenshot capture pipeline itself. Direct, no subtype predicate.
    ///  2) The mediaSubtypes predicate — the historical path. Field report
    ///     2026-07-24 (build 138, iOS 26): only the album path caught new
    ///     screenshots on the reporter's device; the mediaSubtypes predicate
    ///     silently returned zero for newer captures while still returning
    ///     older ones. Keeping the predicate as a second source is a cheap
    ///     safety net for whatever the album misses (edited screenshots
    ///     saved as new assets, third-party capture apps, etc.).
    /// This is the HEAD of the corpus — the newest `limit`. Everything deeper
    /// is `backfill`'s job.
    @MainActor
    private static func fetchScreenshots(limit: Int)
    -> (albumFound: [PHAsset], predicateFound: [PHAsset], merged: [PHAsset])
    {
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

        return (albumAssets, predicateAssets, merged)
    }

    /// Lands whatever the fetch found, deduped on the asset id.
    @MainActor
    private static func land(_ assets: [PHAsset], context: ModelContext) -> Int {
        guard !assets.isEmpty else { return 0 }
        let existing = IngestSupport.existingSourceRefs(context, source: "Photos")
        var added = 0
        for asset in assets {
            guard !existing.contains(asset.localIdentifier) else { continue }
            let date = asset.creationDate ?? .now
            let thing = Thing(
                kind: .screenshot,
                title: ScreenshotTitle.placeholder,   // the OCR pass retitles it once it can (§218)
                source: "Photos",
                createdAt: date,
                capturedAt: date,
                sourceRef: asset.localIdentifier
            )
            context.insert(thing)
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
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
    ///
    /// Single-flight, same as every other bridge's `running` guard (Bluesky/
    /// Farcaster) — and load-bearing here for a reason those don't share:
    /// this loop AWAITS (thumbnail/OCR) in between fetching `things` and
    /// possibly `context.delete`-ing one of them. A second overlapping call
    /// (an automatic scenePhase sweep landing mid pull-to-refresh, or two
    /// quick pulls while a slow iCloud-backed thumbnail is still loading)
    /// fetches its OWN `things` snapshot before the first call's delete
    /// lands, then reads/deletes that same now-gone `Thing` after its own
    /// await resumes — the exact "never touch a dead Thing" crash class
    /// (see CLAUDE.md), just reached from Model code instead of a View.
    @MainActor private static var healing = false

    @MainActor
    static func heal(context: ModelContext) async -> (thumbed: Int, ocred: Int, removed: Int) {
        guard !healing else { return (0, 0, 0) }
        healing = true
        defer { healing = false }

        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Photos" })
        // Kind filters run in memory — #Predicate can't compare Codable enums.
        // A row with a thumbnail, an OCR attempt, and a real (non-placeholder)
        // title can't match any branch below (each is guarded on exactly one
        // of these being missing) — filtering it out here, before the PHAsset
        // walk, is behavior-preserving (perf, 2026-07-28). Without this, a
        // deliberate pull re-fetched the FULL screenshot history's PHAssets
        // from the Photos DB every time, on the main thread, growing forever
        // with library size even though almost every row is already healed.
        let things = ((try? context.fetch(descriptor)) ?? [])
            .filter {
                $0.kind == .screenshot && $0.sourceRef != nil
                    && ($0.previewImageData == nil || $0.ocrAt == nil
                        || $0.title == ScreenshotTitle.placeholder)
            }
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
        var retitled = 0
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
                        // The row stops saying "Screenshot" and says what it
                        // is (§218). The swap rides `BandRow`'s existing
                        // ripple (prd §171) — that transition is keyed on the
                        // title string, so a retitle crossfades and a scroll
                        // never does. Only ever overwrites the PLACEHOLDER: a
                        // title someone's own capture path gave this thing is
                        // never clobbered by machine-read text.
                        if thing.title == ScreenshotTitle.placeholder,
                           let read = ScreenshotTitle.from(text) {
                            thing.title = read
                        }
                    }
                    thing.ocrAt = .now
                    ocred += 1
                }
                // The RETITLE HEAL: a screenshot OCR'd before §218 has its
                // text but still wears the placeholder, and `ocrAt` means it
                // is never re-read — so without this the words already on
                // device would stay invisible forever. Cheap (no Vision, no
                // pixels): it reads `content` the earlier pass already wrote.
                else if thing.title == ScreenshotTitle.placeholder,
                        !thing.content.isEmpty,
                        let read = ScreenshotTitle.from(thing.content) {
                    thing.title = read
                    retitled += 1
                    reindex.append(thing)
                }
            } else if fullAccess, thing.previewImageData == nil, !found.contains(id) {
                removedIDs.append(thing.id)
                context.delete(thing)
                removed += 1
            }
        }
        if thumbed > 0 || ocred > 0 || removed > 0 || retitled > 0 {
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
