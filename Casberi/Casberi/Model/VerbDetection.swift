import Foundation
import SwiftData

/// Detect once, store, read forever (prd §260, 2026-08-01).
///
/// A profile of a swipe (`sample` against a Release build, 4,304 busy
/// main-thread samples) put `VerbDerivation`'s two `NSDataDetector` passes at
/// **~21% of all busy main-thread time** — the app's single largest cost while
/// swiping, and the reason the lag read as even across rooms rather than
/// concentrated in a big one. The mechanism, worth stating because it is not
/// obvious and cost four rounds of wrong guesses to find: a feed row attaches a
/// `.contextMenu`, and `contextMenu(menuItems:)` takes a NON-ESCAPING builder,
/// so its contents are built for every row on every render — not on long-press.
/// Each build faulted the heavy `content` column and ran an address scan and a
/// phone scan over the whole text, for a menu almost nobody opens.
///
/// Caching the results by text was tried first and measured NO improvement,
/// even at a 20,000-entry limit — the scans are simply cold most of the time,
/// because a swipe brings a room's rows into view for the first time. The cost
/// is structural: it is per-render work that should never have been per-render.
/// So detection moved to where the input actually changes — the thing itself.
///
/// Deliberately NOT wired into each bridge's ingest. There are ~40 landing
/// paths and one of them would be forgotten; a single bounded sweep over
/// whatever is unstamped covers every path that exists and every path added
/// later, including things arriving by CloudKit merge from another device,
/// which no ingest hook here would ever see.
@MainActor
enum VerbDetection {
    /// Things scanned per pass. The scans are the expensive thing this file
    /// exists to bound, so the sweep is deliberately small and repeats: it runs
    /// on every foreground (off the launch window), so a large corpus drains
    /// over a handful of opens instead of stalling one.
    /// Bump when the scan learns a new field, so already-stamped rows are
    /// re-enrolled. 1 = tel + place (prd §260). 2 = mailto joined them (§262),
    /// after a device profile measured it at 7% of main-thread samples.
    static let version = 2

    private static let batch = 150

    /// Guards against two sweeps overlapping — the pass is `async` and a fast
    /// background/foreground bounce could otherwise start a second one over the
    /// same unstamped rows.
    private static var running = false

    /// Stamp the next batch of unscanned things.
    ///
    /// Ordered NEWEST FIRST on purpose: the rows a person can actually see are
    /// the recent ones, so the verbs come back where they'd be noticed first
    /// and the long tail fills in behind them.
    /// The scans run OFF the main actor since 2026-08-06 (the post-271 "laggy
    /// at open" report). They used to run on it — 150 rows × three
    /// `NSDataDetector`/regex passes over each row's full text, synchronously,
    /// on every single foreground — which is the same shape of stall the
    /// profile above found in the render path, simply moved to a different
    /// moment. Only the FETCH and the write back onto the models have to be on
    /// main; the scanning takes a String and returns Strings. See
    /// `VerbDerivation.Input` and `ScreenshotTopics.extract`, the same fix.
    static func backfill(context: ModelContext) async {
        guard !running else { return }
        running = true
        defer { running = false }

        let current = version
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.detectionVersion != current },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = batch
        guard let pending = try? context.fetch(d), !pending.isEmpty else { return }

        let detected = await VerbDerivation.detect(pending.map(VerbDerivation.Input.init))

        // Per-ROW liveness AFTER the await, not the fetch that ran before it
        // (COROLLARY 6): a bridge heal can tombstone a row while the scans
        // run, and this is the first read of a stored property since.
        let now = Date()
        var changed = false
        for (thing, found) in zip(pending, detected) where thing.isLive {
            // All three may legitimately be nil — that IS the answer for most
            // things, and `detectedAt` is what stops it being re-asked forever.
            thing.detectedPlace = found.place
            thing.detectedTel = found.tel
            thing.detectedMailto = found.mailto
            thing.detectedAt = now
            thing.detectionVersion = current
            changed = true
        }
        if changed { context.saveHonestly() }
    }

    /// Re-scan a thing whose text changed under it (a heal that rewrites
    /// `content`, an enrichment that fills in a title). Clearing the stamp is
    /// enough — the next sweep picks it up. Cheap enough to call from an ingest
    /// that knows it rewrote something; never required for correctness of the
    /// FIRST scan, which the sweep handles on its own.
    static func invalidate(_ thing: Thing) {
        guard thing.isLive else { return }
        thing.detectedAt = nil
        thing.detectionVersion = nil
    }
}
