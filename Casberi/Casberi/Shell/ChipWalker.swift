import Foundation
import SwiftData

/// The source strip's store reads, OFF the main thread (PERF 2026-09-08).
///
/// **What this moves.** `MainSurface.newestPerSource()` asks the store for
/// the newest row of every candidate seat — one indexed fetch per name, ~70
/// names — plus a 400-row read of the shell's own query to learn which
/// non-catalog sources exist. That walk ran on the main thread, and on a cold
/// launch it ran TWICE before the first frame: once inline on the first body
/// pass (`chipSnapshot` with `liveChips` still nil), once from `onAppear`
/// (`freezeChips(force: true)`). Both sat between `init` and the first pixel.
///
/// **Why an actor and not a `Task.detached`.** The main `ModelContext` walked
/// off the main actor is a SIGSEGV that reads like the liveness class and is
/// not it (prd §617) — so this is a `@ModelActor`, whose context is its own,
/// created on the same container `SharedStore.adopt` published at launch.
/// Nothing model-shaped crosses the boundary: the result is names and dates.
///
/// **What still runs on main.** The assembly — the catalog fold, the stored
/// category order, the connected live-room seats — is pure and stays in
/// `MainSurface.assembleChips`, because it reads main-actor state
/// (`BridgeStore`, `CategoryOrder`, the `-categoryOrder` seed) and costs
/// nothing.
///
/// The first frame paints from `ChipOrderCache` (the order the strip wore
/// last time) and the walk corrects it once the frame is on screen. The
/// correction is usually a no-op; a source whose last row was deleted since
/// the previous launch drops its chip a beat after first paint, which is the
/// one visible case and the honest one.
@ModelActor
actor ChipWalker {
    struct Walk: Sendable {
        /// Every seat with a row, newest first — the order the strip wears.
        var newest: [String]
        var hasPinned: Bool
    }

    /// One walk against the shared container, or nil when no container has
    /// been adopted yet (never, in the app; kept for harness safety).
    static func walk(seeds: Set<String>) async -> Walk? {
        guard let container = SharedStore.live else { return nil }
        let walker = ChipWalker(modelContainer: container)
        return await walker.perform(seeds: seeds)
    }

    private func perform(seeds: Set<String>) -> Walk {
        var candidates = seeds
        // Which NON-catalog sources exist — the same 400-row, source-only read
        // the shell's own query used to serve on main.
        var recent = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        recent.fetchLimit = 400
        recent.propertiesToFetch = [\.source]
        for thing in (try? modelContext.fetch(recent)) ?? [] where thing.isLive {
            candidates.insert(thing.source)
        }
        var out: [(String, Date)] = []
        for name in candidates where Corpus.earnsRoom(name) {
            var d = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == name },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = 1
            // Only the column the sort and the order need. Without this the one
            // row faults its heavy inline text in — per source, per refresh.
            d.propertiesToFetch = [\.source, \.capturedAt]
            guard let newest = (try? modelContext.fetch(d))?.first, newest.isLive
            else { continue }
            out.append((name, newest.capturedAt))
        }
        let ordered = out.sorted { $0.1 > $1.1 }.map(\.0)
        // `Pinboard.hasAny`'s read, spelled here because that helper is
        // main-actor-isolated and this context is not.
        var pinned = FetchDescriptor<Thing>(predicate: #Predicate { $0.pinnedAt != nil })
        pinned.fetchLimit = 1
        pinned.propertiesToFetch = [\.pinnedAt]
        let hasPinned = ((try? modelContext.fetch(pinned))?.first?.isLive) ?? false
        return Walk(newest: ordered, hasPinned: hasPinned)
    }
}

/// The order the strip wore at the end of its last walk — what the first
/// frame paints from, so a launch never waits on the store for its dock
/// (PERF 2026-09-08). Written after every walk; read on the first body pass
/// only. Scratch-suite aware like every other DEBUG-run default here.
enum ChipOrderCache {
    struct Snapshot: Codable, Equatable {
        var labels: [String]
        var venues: [String: [String]]
        var sources: [String]
    }

    private static let key = "dock.order.cache"

    static func load() -> Snapshot? {
        guard let data = ScratchDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        ScratchDefaults.standard.set(data, forKey: key)
    }
}
