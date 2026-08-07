import Foundation
import SwiftData

/// The furnished demo, as a state someone can enter and leave — the onboarding
/// fork's fourth card.
///
/// **Why it exists.** Every hero this app has — the treemaps, the sankey, the
/// day dial, the room heads, the agent panel, the brief — needs a corpus to
/// draw, so a new install shows none of them. The three fork cards each fix
/// that with the person's OWN data, which is the right answer and is also a
/// commitment: a folder, a wallet, or somebody to follow. Someone still
/// deciding whether this app is for them has nothing to look at until they
/// have already decided. The demo is the fourth answer: see it furnished
/// first, commit second.
///
/// **Why it is not the lead card.** The three real cards produce evidence from
/// your own life, and that is what converts; a demo that led would make the
/// common path "explore a stranger's beautiful corpus, then land on an empty
/// lot". So it sits last, phrased as the option for someone not ready to
/// connect anything — an escape hatch, not the nudge.
///
/// **Why it writes to the real store rather than a container of its own.**
/// An isolated container makes exit free (close the door, nothing to delete)
/// and keeps the rows off the person's iCloud. It was still declined: the app
/// holds exactly one container by design — `SharedStore.live`'s own comment
/// records that opening the store twice gives two contexts over one file that
/// silently disagree — and swapping containers mid-session would put that
/// invariant on the demo path, where a bug reads as data loss. The demo rows
/// use only existing `Thing` fields, so nothing here touches CloudKit's
/// Production schema; what it costs is ~330 rows mirroring to the person's
/// zone and then a matching set of deletes on exit. That is a real cost, and
/// the honest mitigation is that leaving is always one tap away and always
/// complete (`DemoSeedAll.teardown`).
///
/// **The §83 obligation.** A fake Stripe dispute and a fake $12,480 crown in
/// the app's ordinary chrome are exactly the fake status the honesty rule
/// bans. So the demo is never silent: while it is active the shell wears a
/// standing banner that says so and carries the way out. If that banner is
/// ever made dismissible, this stops being honest.
enum DemoMode {
    private static let activeKey = "demo.mode.active"

    /// Read from `BridgeStore.init` and from view bodies, so it stays cheap
    /// and non-isolated — one `UserDefaults` read.
    static var isActive: Bool { UserDefaults.standard.bool(forKey: activeKey) }

    private static let seenKey = "demo.mode.hasSeen"

    /// Sticky once the demo has ever been entered, and never cleared by
    /// leaving — that is the point. The fork uses it to stop offering a tour
    /// of a room the person has just walked out of.
    static var hasSeen: Bool { UserDefaults.standard.bool(forKey: seenKey) }

    /// The standing questions a furnished install would plausibly have kept.
    ///
    /// Deliberately only two, and both composable from state this seed
    /// guarantees: `today` composes over whatever the corpus holds, and
    /// `wallet` has the seeded address and its balance curve behind it. The
    /// tempting additions (`context:<source>`, `overdue`, a `search:`) all
    /// depend on a composer finding something in a window, and a kept ask
    /// whose composer comes back empty renders as a chip that answers
    /// nothing — worse than not offering it. Widen this only against a real
    /// run, not by reasoning about what the seed probably contains.
    private static let keptAsks: [(kind: String, title: String)] = [
        ("today", String(localized: "How's my day?")),
        ("wallet", String(localized: "How's my wallet?")),
    ]

    /// Set while the rows have been promised but not yet poured.
    private static let pendingKey = "demo.mode.pourPending"

    /// Rows per beat, and the beat. Together these spend ~1.6s on a ~330-row
    /// seed. Small enough that each step is well inside a frame's budget;
    /// slow enough to read as arriving rather than as a stutter.
    private static let pourChunk = 12
    private static let pourBeat = Duration.milliseconds(55)

    /// Claim the mode WITHOUT landing any rows — instant, so the caller can
    /// lift the onboarding cover immediately.
    ///
    /// Split from the pour on purpose, and the split IS the delight: seeding
    /// behind the cover would hand someone a finished feed, which reads as a
    /// screenshot. Lifting first and pouring after lets them watch the app
    /// fill — chips appearing, rows landing, the crown arriving — which is the
    /// one moment that shows what this product actually does rather than
    /// describing it.
    @MainActor
    static func begin(store: BridgeStore) {
        UserDefaults.standard.set(true, forKey: activeKey)
        UserDefaults.standard.set(true, forKey: pendingKey)
        UserDefaults.standard.set(true, forKey: seenKey)
        // The catalog must not contradict the feed: rooms full of rows over a
        // catalog claiming nothing is connected reads as a bug. `bridges`
        // persists on write, so this survives relaunch with no init path of
        // its own.
        store.bridges = BridgeApp.demo
        for ask in keptAsks { KeptAskStore.shared.keep(ask.kind, title: ask.title) }
        NSLog("[Casberi] demoMode: began")
    }

    /// Pour the rows in, a handful at a time, yielding between each so the
    /// feed can draw every beat.
    ///
    /// The chunking is `ImportCommit`'s shape and exists for its reason as
    /// well as for the animation: these are main-actor inserts into the
    /// context a live `@Query` is watching, so doing all ~330 at once holds
    /// the main thread through the exact frames this is trying to make
    /// beautiful. A chunk is a commit here too, which is what makes the pour
    /// safe to interrupt — a kill mid-pour leaves the pending flag set and
    /// the next launch finishes the job, because `seed` dedupes on
    /// `sourceRef`.
    ///
    /// Idempotent and self-clearing; cheap to call on every launch.
    @MainActor
    static func pourIfNeeded(context: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return }

        // State before rows: the crown, the balance curve and the seller
        // tables are what the room HEADS read, and a head that arrives after
        // its own rows reads as a late correction rather than a filling app.
        DemoSeedAll.seedBridgeStateForDemo()

        let landed = Set(((try? context.fetch(FetchDescriptor<Thing>())) ?? [])
            .compactMap(\.sourceRef))
        let rows = DemoSeedAll.rooms().filter { !landed.contains($0.sourceRef ?? "") }
        for start in stride(from: 0, to: rows.count, by: pourChunk) {
            for thing in rows[start..<min(start + pourChunk, rows.count)] {
                context.insert(thing)
            }
            context.saveHonestly()
            try? await Task.sleep(for: pourBeat)
        }
        UserDefaults.standard.set(false, forKey: pendingKey)
        NSLog("[Casberi] demoMode: poured %d rows", rows.count)
    }

    /// Leave, and leave nothing behind.
    ///
    /// The verb is EXIT, not delete — the person never chose to keep any of
    /// this, so asking them to "delete everything" would be asking them to
    /// take responsibility for rows the app poured in. What they land on is
    /// the ordinary empty feed, which already knows how to invite the first
    /// real thing.
    @MainActor
    static func exit(context: ModelContext, store: BridgeStore) {
        let rows = DemoSeedAll.teardown(context)
        store.bridges = []
        for ask in keptAsks { KeptAskStore.shared.remove(ask.kind) }
        UserDefaults.standard.set(false, forKey: activeKey)
        // A pour interrupted by Exit must not resume on the next launch —
        // otherwise the rows the person just removed pour straight back in,
        // and the app looks like it refused to let go.
        UserDefaults.standard.set(false, forKey: pendingKey)
        NSLog("[Casberi] demoMode: exited, %d rows removed", rows)
    }
}
