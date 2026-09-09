import Foundation
import SwiftData

/// How many saves this process has made (prd §623, 2026-09-05). One integer,
/// always on: `SweepClock` reads it at pass begin and end so a sweep report
/// carries `saves=N` beside its hitch count — the question "does every bridge
/// save re-emit the feed's query" needs both numbers on one line, and until
/// this the saves were not counted anywhere. Main-actor in practice (every
/// ingest is), and a lost increment under a stray background save costs a
/// count of one, never a wrong save.
///
/// `requested` (2026-09-08) counts the saves ASKED for, so a sweep line can
/// say `saves=3 (asked 41)` — the coalescer's whole effect, in one pair.
enum SaveCensus {
    nonisolated(unsafe) static var count = 0
    nonisolated(unsafe) static var requested = 0
}

/// One save per burst instead of one per bridge (PERF, 2026-09-08).
///
/// **The cost.** Every bridge pass already saves ONCE, at its end — that was
/// measured and is not the problem. The problem is how many passes a
/// foreground sweep runs: ~45 slots, staggered 120ms apart (40ms on a pull),
/// each landing after its own network round trip, each ending in a save. And
/// a save is not cheap on this app's main thread: it posts the context's
/// `didSave`, and **every mounted `@Query` re-runs on it** — a fetch plus a
/// per-model `Codable` snapshot of the whole bounded window (prd §646) — so a
/// sweep re-materialised the All room forty times in the seconds after every
/// return to the app, which is exactly when the person is scrolling it.
/// Measured 2026-09-08: the main context's autosave never fires between
/// explicit saves (a standalone SwiftData probe, ten inserts 30ms apart, zero
/// saves in 1.5s), so the explicit saves ARE the re-emissions, and
/// coalescing them coalesces the query re-runs one for one.
///
/// **What this does.** A save asked for from inside a bridge pass — the
/// `landing` task-local is true there, set by `BridgeRefresh.landingTask` and
/// inherited by every child task — is DEFERRED: the request is noted, and one
/// real save runs after `quietMs` without another request, or `maxLatencyMs`
/// after the first, whichever comes first. A save asked for from anywhere
/// else (a pin, a delete, an edit, an import screen, the share extension) is
/// exactly what it was: immediate, honest about its outcome. Nothing but the
/// sweep's own saves are ever held, and none is held past a second.
///
/// **What it cannot break.** A fetch on the same context sees pending
/// inserts (`includePendingChanges`, measured), so a bridge that reads back
/// what a sibling landed reads it. `saveHonestly` reports `true` for a
/// deferred save, which is the truth a bridge can act on — its rows are in
/// the context and WILL be written; a failure at flush time is logged with
/// every site the batch carried, so nothing is swallowed. A background
/// transition flushes at once (`RootShell`), and the process is not a
/// crash-safe store for a second of ingest anyway: every bridge re-lands
/// what a lost save dropped on its next pass, by design (ref dedupe).
///
/// Only the MAIN context is coalesced — a private context (the MCP server,
/// the Shortcuts intents) saves inline, because its `@Query` cost is nil and
/// its lifetime is the call.
enum SaveCoalescer {
    @TaskLocal static var landing = false

    static let quietMs = 300
    static let maxLatencyMs = 1000

    @MainActor private static var pending: ModelContext?
    @MainActor private static var sites: [String] = []
    @MainActor private static var firstRequest: Date?
    @MainActor private static var flushTask: Task<Void, Never>?

    /// Note a deferred save and (re)arm the flush.
    @MainActor
    static func request(_ context: ModelContext, site: String) {
        SaveCensus.requested += 1
        if let held = pending, held !== context {
            // Two contexts in one burst: never merge them, write the earlier.
            flushNow()
        }
        pending = context
        sites.append(site)
        let now = Date()
        if firstRequest == nil { firstRequest = now }
        let sinceFirst = now.timeIntervalSince(firstRequest ?? now) * 1000
        let wait = max(0, min(Double(quietMs), Double(maxLatencyMs) - sinceFirst))
        flushTask?.cancel()
        flushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(wait)))
            guard !Task.isCancelled else { return }
            flushNow()
        }
    }

    /// Write whatever is held, now. Safe to call with nothing pending.
    @MainActor
    static func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        guard let context = pending else { return }
        let batch = sites
        pending = nil
        sites = []
        firstRequest = nil
        // A sibling's immediate save may already have written the batch;
        // an empty save posts nothing and is skipped rather than counted.
        guard context.hasChanges else { return }
        do {
            try context.save()
            SaveCensus.count += 1
        } catch {
            NSLog("[Casberi] coalesced save failed (\(batch.count) requests: \(batch.joined(separator: ", "))): \(error)")
        }
    }

    /// Whether a save is being held right now — for the sweep report.
    @MainActor
    static var isHolding: Bool { pending != nil }
}

extension ModelContext {
    /// Saves and reports the outcome instead of swallowing it (RULE,
    /// 2026-07-15). A bare `try? context.save()` was the ingestion layer's
    /// default everywhere — a failed save (disk pressure, a CloudKit
    /// merge/validation rejection) silently dropped whatever was just
    /// inserted or changed, with nothing downstream ever finding out. This
    /// at minimum logs the failure so it's observable, and returns whether
    /// it actually saved so a user-facing write (a screen reacting to a tap,
    /// not a background ingest) can correct an optimistic UI update instead
    /// of leaving a lie on screen — the same honesty rule that bans dead
    /// controls and fake status.
    ///
    /// Inside a bridge pass the save is coalesced — see `SaveCoalescer`.
    @discardableResult
    func saveHonestly(file: StaticString = #fileID, line: UInt = #line) -> Bool {
        if SaveCoalescer.landing, Thread.isMainThread {
            MainActor.assumeIsolated {
                SaveCoalescer.request(self, site: "\(file):\(line)")
            }
            return true
        }
        do {
            try save()
            SaveCensus.count += 1
            return true
        } catch {
            NSLog("[Casberi] save failed at \(file):\(line): \(error)")
            return false
        }
    }
}
