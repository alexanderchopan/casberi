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
    static func backfill(context: ModelContext) {
        guard !running else { return }
        running = true
        defer { running = false }

        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.detectedAt == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = batch
        guard let pending = try? context.fetch(d), !pending.isEmpty else { return }

        let now = Date()
        for thing in pending where thing.isLive {
            // Both may legitimately be nil — that IS the answer for most things,
            // and `detectedAt` is what stops it being re-asked forever.
            thing.detectedPlace = VerbDerivation.placeURL(for: thing)?.absoluteString
            thing.detectedTel = VerbDerivation.telURL(in: thing)?.absoluteString
            thing.detectedAt = now
        }
        context.saveHonestly()
    }

    /// Re-scan a thing whose text changed under it (a heal that rewrites
    /// `content`, an enrichment that fills in a title). Clearing the stamp is
    /// enough — the next sweep picks it up. Cheap enough to call from an ingest
    /// that knows it rewrote something; never required for correctness of the
    /// FIRST scan, which the sweep handles on its own.
    static func invalidate(_ thing: Thing) {
        guard thing.isLive else { return }
        thing.detectedAt = nil
    }
}
