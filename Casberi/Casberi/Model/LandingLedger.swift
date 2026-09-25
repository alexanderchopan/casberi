import Foundation
import SwiftData

/// WHEN A THING LANDED IN THIS PROCESS (prd §901b, 2026-09-25 — user: "the
/// tile morphs into the category glyph and then back but i don't notice it.
/// is it live" → "why wouldn't we want to fix it?").
///
/// `LeadCycle` asks whether a row "landed while you look". It read
/// `Thing.capturedAt` against the page's wave — and `capturedAt` is the
/// thing's OWN date, not its arrival. Most bridges stamp it from upstream
/// (`item.date`, `row.date`, `notice.at`, a block's time): a reply from forty
/// minutes ago that arrived in this pull was forty minutes old to the rule
/// and never turned. Census 2026-09-25: 52 landing sites stamp `.now`, about
/// sixty stamp the provider's date. `-leadCycleProbe` passed because it built
/// a `Thing` with the default `capturedAt = .now`; the feed did not.
///
/// This is the ARRIVAL clock. Every `Thing` inserted into any context is
/// stamped at the moment its context saves (`ModelContext.willSave`, read off
/// `insertedModelsArray` — the models are live and on their own thread
/// there), which is also the moment the `@Query` re-runs and the row mounts,
/// so the two clocks agree to the frame. Process-local on purpose: "landed
/// while you look" is a fact about this launch, so it is not a stored
/// property — no schema version, no CloudKit deploy — and a row materialised
/// from the store carries no stamp, so the corpus you open to stays at rest
/// (§901). A thing synced in from another device carries none either (no
/// save here); that is the one landing this cannot see.
///
/// Bounded: entries older than `keep` are pruned on every write, so a
/// long-lived process holds a minute of arrivals, never the corpus. The demo
/// pour suspends it (`suspended`): a seed dated at fixed hours of fixed days
/// is furniture, not news.
///
/// Installed once, from `RootShell`, beside `SaveCoalescer.holdForHand`.
/// Nothing is called out to inside the lock (prd §721).
enum LandingLedger {
    /// How long a landing is remembered — past `LeadCycle.freshWindow`, with
    /// room for a coalesced save held for a still hand (prd §725).
    static let keep: TimeInterval = 60

    /// True while the demo pours; a poured row is not a landing.
    nonisolated(unsafe) static var suspended = false

    private static let lock = NSLock()
    nonisolated(unsafe) private static var landings: [UUID: TimeInterval] = [:]
    nonisolated(unsafe) private static var observer: NSObjectProtocol?

    /// Observe every context's `willSave`. Idempotent.
    static func install() {
        lock.lock()
        guard observer == nil else { lock.unlock(); return }
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: nil, queue: nil
        ) { note in
            guard let context = note.object as? ModelContext else { return }
            let ids = context.insertedModelsArray.compactMap { ($0 as? Thing)?.id }
            guard !ids.isEmpty else { return }
            record(ids)
        }
        lock.unlock()
    }

    /// Stamp these things as landed now.
    static func record(_ ids: [UUID],
                       at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        guard !suspended else { return }
        lock.lock(); defer { lock.unlock() }
        landings = landings.filter { now - $0.value < keep }
        for id in ids { landings[id] = now }
    }

    /// When this thing landed in this process, or nil: it was here when the
    /// process began, came from the store, or landed longer than `keep` ago.
    static func landedAt(_ id: UUID) -> TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return landings[id]
    }

    /// Everything forgotten.
    static func forget() {
        lock.lock(); defer { lock.unlock() }
        landings.removeAll()
    }
}
