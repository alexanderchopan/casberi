import BackgroundTasks
import Foundation
import SwiftData

/// Opportunistic wallet sampling (2026-07-15) — the value line is only ever as
/// dense as how often you open the app (holdings sample at most once per 4h,
/// on foreground). A BGAppRefreshTask lets iOS run a holdings read while you're
/// away, so the line fills in between opens WITHOUT changing the honesty: each
/// sample is still a real onchain read, still forward-only, never back-filled —
/// there are simply more of them. The footer copy softens from "sampled as you
/// use Casberi" accordingly.
///
/// iOS decides IF and WHEN this runs (it never fires on a fixed clock, and
/// never at all on the Simulator) — the app only registers a handler and asks
/// politely. Registration MUST happen before the app finishes launching, so it
/// runs from `CasberiApp.init`; scheduling runs each time we background.
enum WalletBackgroundRefresh {
    static let taskID = "com.casberi.app.walletsample"

    /// Registered once at launch (CasberiApp.init). No-op harm if the OS never
    /// schedules the task — it just sits idle.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false); return
            }
            handle(refresh)
        }
    }

    /// Asks iOS for a future run — only when there's a wallet to sample. Called
    /// on background (RootShell scenePhase) and after each run (self-chaining).
    /// `earliestBeginDate` mirrors the 4h sample throttle: a sooner run would
    /// only be throttled out by recordSample anyway.
    @MainActor
    static func schedule() {
        // Widened for notifications (prd §306): this task is no longer only
        // about the wallet's value line, so a wallet is no longer the only
        // reason to want it. Someone with Stripe connected and no wallet at all
        // still needs the pass that finds a dispute while they are away.
        guard !WalletStore.shared.addresses.isEmpty || Notifications.settings.anyOn else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        // Notifications want a tighter cadence than the 4h holdings throttle —
        // a deadline three days out is no use announced two days late. This is
        // a FLOOR, not a promise: iOS runs the task when it decides to, which
        // is the ceiling §306 states rather than hides.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Chain the next run first, so a crash mid-work still leaves one queued.
        // Hops to the main actor because the gate now reads `Notifications`
        // settings and `WalletStore`, both main-isolated — the submit itself is
        // thread-safe, and BGTaskScheduler delivers this handler off-main.
        Task { @MainActor in schedule() }
        // The expiration handler is armed BEFORE the work starts (an early OS
        // expiration must still find a cancel hook), and completion runs
        // exactly once — either the work finishes (success unless cancelled) or
        // expiration reports failure. Leaving a task un-completed makes iOS
        // treat it as a failure and throttle future scheduling.
        let state = CompletionState()
        task.expirationHandler = {
            state.work?.cancel()
            state.complete(task, success: false)
        }
        state.work = Task { @MainActor in
            // The same read a foreground does: holdings, which records the
            // value sample the balance sparkline draws from.
            _ = await WalletIngest.topHoldingsByWallet()
            // …and then the notification sweep (prd §306). It runs on whatever
            // has ALREADY landed rather than driving a full bridge refresh:
            // this task's budget is seconds, a full sweep is dozens of network
            // reads, and an expired task is one iOS throttles next time. The
            // bridges land rows on foreground and through their own paths; this
            // asks what among them deserves telling.
            await runNotifySweep()
            state.complete(task, success: !Task.isCancelled)
        }
    }

    /// Sweep the corpus, schedule what deserves it, and re-arm the whisper
    /// (prd §306). Shared by the background task and the foreground pass, so
    /// the two can never drift into deciding different things.
    ///
    /// Reads `SharedStore.live` rather than opening its own container — two
    /// containers over one store file is two contexts that disagree.
    @MainActor
    static func runNotifySweep() async {
        guard let context = SharedStore.live?.mainContext else { return }
        guard let things = sweepCorpus(context) else { return }
        let (plans, photos) = NotifySweep.plans(things: things)
        // **THE TWO DEVNETS SPEAK HERE TOO (prd §522).** Neither can be reached
        // by a corpus sweep: Hegotá lands no `Thing` at all by design (§500),
        // and vibenet's two chain-wide clocks — a timelock ending, the chain
        // being wiped — belong to no row. Merged into the SAME submit rather
        // than sent on their own, so a devnet alarm competes in one batch with
        // every other alarm (`NotifyRules.collapse` keeps the worst and counts
        // the rest) instead of arriving as a second buzz beside a dispute — and
        // so `notify-selftest.sh`'s "only one file submits" guard stays true.
        let devnet = DevnetNotify.plans()
        await Notifications.submit(plans + devnet, photos: photos)
        // AFTER the submit, never before: pruning first would drop an entry in
        // the same pass that was about to announce it.
        DevnetNotify.prune()
        // The whisper is re-scheduled on every sweep so its content is as fresh
        // as the last run before it fires — see `Notifications.scheduleWhisper`
        // for why a repeating trigger would be wrong.
        // `detail` is the two-fact form ("14 new while you were away, wallet
        // +1.5%") — the same line the capsule shows. Nil whisper means nil
        // line, which pulls any pending one: nothing to say, nothing fires.
        await Notifications.scheduleWhisper(
            line: DayBrief.whisper(things: things.filter(\.isLive))?.detail)
    }

    /// Only the rows this sweep could possibly speak about (PERF 2026-08-11).
    ///
    /// It used to fetch the WHOLE store, fully hydrated, on the MAIN ACTOR,
    /// on every foreground — and the sweep runs early in a foreground, so on a
    /// large corpus that is time spent before anything can be scrolled.
    /// `scripts/main-thread-profile.sh` put it at 6% of the main thread on a
    /// 6,000-row corpus, and the cost is linear in corpus size.
    ///
    /// Nothing downstream can reach a row outside these two sets, and both
    /// stay small at any corpus size:
    ///
    ///   • The LANDING scan (`NotifySweep.plans`' `fresh`) only ever speaks
    ///     about what landed inside `NotifySweep.newsWindow` (36h).
    ///   • `DayBrief.whisper` speaks about what landed inside the AWAY window,
    ///     which after a long absence reaches further back than 36h — so the
    ///     floor is whichever of the two goes deeper. Taking the news window
    ///     alone would silently empty the whisper for exactly the person who
    ///     had been away longest, which is the one it exists for.
    ///   • The DEADLINE scan is the one class that fires about an OLD row, so
    ///     it is fetched by its own predicate rather than by recency. It stays
    ///     tiny because only a reminder, an event or a dated bridge row
    ///     carries `dueAt` at all.
    ///
    /// FAILS SAFE: a refused predicate falls back to the old whole-store read
    /// rather than sweeping an empty array, because "fetched nothing" and
    /// "there is nothing to say" are indistinguishable downstream — this
    /// decides what reaches someone's lock screen, and quietly notifying
    /// about nothing is the one outcome worth a slow path to avoid.
    /// Not `private`: `-notifyProbe` feeds `NotifySweep.plans` through this
    /// too, so the only exerciser the sweep has (the simulator never runs a
    /// `BGAppRefreshTask`) reports on the input production actually uses.
    @MainActor
    static func sweepCorpus(_ context: ModelContext) -> [Thing]? {
        let now = Date.now
        let floor = min(now.addingTimeInterval(-NotifySweep.newsWindow),
                        DayBrief.windowStart(now: now))
        let recent = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.capturedAt > floor },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        // DISJOINT from `recent` by construction (`capturedAt <= floor`), which
        // is what lets the two results simply concatenate below: everything in
        // `recent` is newer than the floor and everything here is older, and
        // each is internally sorted, so `recent + dated` is already globally
        // newest-first. No dedupe set, no merge, no re-sort — and `DayBrief`
        // needs that order, since `lead` takes `landed.first` as "the newest
        // thing" and would otherwise name the wrong one.
        //
        // `dueAt != nil` and nothing tighter: `NotifyRules.deadlineIsNear`
        // narrows to its own future window, and expressing that here would
        // mean unwrapping an optional inside a `#Predicate`.
        let dated = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.dueAt != nil && $0.capturedAt <= floor },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        guard let recentRows = try? context.fetch(recent),
              let datedRows = try? context.fetch(dated)
        else { return try? context.fetch(FetchDescriptor<Thing>()) }
        return datedRows.isEmpty ? recentRows : recentRows + datedRows
    }

    /// One-shot completion + a slot for the work handle, so the expiration
    /// handler can be armed before the work exists and neither path double-
    /// calls setTaskCompleted (Apple requires exactly one call).
    private final class CompletionState {
        private let lock = NSLock()
        private var done = false
        var work: Task<Void, Never>?

        func complete(_ task: BGAppRefreshTask, success: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            task.setTaskCompleted(success: success)
        }
    }
}
