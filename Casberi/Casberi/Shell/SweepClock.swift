import Foundation

/// Where a FOREGROUND SWEEP's time goes — the class `perf.sh` structurally
/// cannot see (2026-08-06).
///
/// The perf pass tracks three numbers: launch init→ready, steady RSS, answer
/// latency. A build can hold all three flat and still feel worse to use, and
/// after build 271 it did: `BridgeRefresh.refreshAllConnected` grew from 42
/// slots to 45, several of them main-actor work over the whole corpus
/// (`ScreenshotTopics` NLTagger passes, `XArchiveImport.healRoom`,
/// `FeedArticleText`, `YouTubeShorts`), every one of them firing within ~2s of
/// the moment somebody opens the app and starts scrolling. None of it touches
/// launch, RSS or the answer path, so the nightly reads green over a build that
/// stutters — the §257 lesson one layer out: a metric with no breakdown tells
/// you to panic, not what to do.
///
/// Two readings, deliberately separate because they answer different questions:
///
///  • **Per-label wall time** — how long each instrumented sweep took. Says
///    what is SLOW. It includes the sweep's own awaits (a network read), so a
///    big number here is not by itself a jank finding.
///  • **Hitches** — how long the MAIN ACTOR was unavailable, sampled by a
///    16ms heartbeat that measures its own lateness. Says what is JANKY, which
///    is the thing being complained about. A hitch is charged to every label
///    in flight when it happened, and that is an honest CONCURRENT-WITH, never
///    a caused-by: ~45 tasks share the actor and only the heartbeat's own
///    lateness is measured, not the identity of whatever blocked it. A hitch
///    with no label open is still recorded (`(none)`), which is how work this
///    file does NOT instrument shows up at all.
///
/// Off unless `-sweepTimer YES` is passed, and off costs one `Bool` read per
/// call — so, unlike `LaunchPerf`, it is measurable in RELEASE, where the
/// numbers people actually run live (DEBUG's `-Onone` NLTagger pass is an
/// upper bound, not the shipped cost).
///
/// Read headlessly:
/// `xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "sweepPerf"'`
/// or `-sweepTimerProbe YES`, which turns it on, fires a sweep and dumps the
/// summary. One NSLog per line — a joined multi-line message gets truncated by
/// the log reader (the `-todayProbe` lesson).
@MainActor
enum SweepClock {

    // MARK: - Gate

    private static var cachedOn: Bool?
    /// Read once per process: this is checked on every instrumented call and a
    /// `UserDefaults` hit per call would be an instrument that costs what it
    /// measures (`LaunchPerf`'s throttling lesson, one step earlier).
    static var isOn: Bool {
        if let cachedOn { return cachedOn }
        // The probe's own flag counts as the switch. Both land in the argument
        // domain before any of this code runs, which removes the ordering
        // question entirely: a probe that had to call `enable()` itself would
        // have to beat the sweep it means to measure, and on a later
        // foreground it wouldn't.
        let d = UserDefaults.standard
        let on = d.bool(forKey: "sweepTimer") || d.bool(forKey: "sweepTimerProbe")
        cachedOn = on
        return on
    }
    /// For the probe, which turns the instrument on from inside the process.
    static func enable() { cachedOn = true }

    // MARK: - Accounting

    private struct Entry {
        var calls = 0
        var wallMs: Double = 0
        var hitches = 0
        var hitchMs: Double = 0
    }
    private static var entries: [String: Entry] = [:]
    /// First-seen order, so the report reads in the order the sweep ran rather
    /// than in a dictionary's arbitrary one.
    private static var order: [String] = []
    private static var inFlight: [String: Int] = [:]

    private static var passStart: ContinuousClock.Instant?
    private static var openWork = 0
    private static var hitches = 0
    private static var hitchTotalMs: Double = 0
    private static var hitchMaxMs: Double = 0
    private static var monitor: Task<Void, Never>?
    private static var reportPending: Task<Void, Never>?

    /// `Duration.components.attoseconds` carries only the SUB-SECOND remainder
    /// — `seconds` holds the rest — so reading attoseconds alone reports a
    /// 1.4s sweep as 400ms and a 2.0s one as zero. Exactly the sweeps worth
    /// finding are the ones that cross the boundary, so this is spelled once
    /// and used everywhere rather than at four call sites.
    private static func ms(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }

    // MARK: - Pass

    /// Call at the top of a foreground sweep. Resets the accounting and starts
    /// the heartbeat. Safe to call when the instrument is off (does nothing)
    /// and safe to call again mid-pass (a re-entrant sweep just extends the
    /// current one rather than zeroing counters underneath in-flight work).
    static func beginPass(force: Bool = false) {
        guard isOn else { return }
        guard passStart == nil else { return }
        entries = [:]
        order = []
        hitches = 0
        hitchTotalMs = 0
        hitchMaxMs = 0
        passStart = .now
        NSLog("[Casberi] sweepPerf pass=begin force=%@", force ? "YES" : "NO")
        startMonitor()
    }

    /// Time one sweep. The function times ITSELF at its own definition, so
    /// adding a slot to `BridgeRefresh` needs no matching edit here — and a
    /// slot nobody instrumented still shows up in the hitch line as `(none)`.
    @discardableResult
    static func measure<T>(_ label: String, _ work: () async -> T) async -> T {
        guard isOn else { return await work() }
        // A sweep can be called straight off a screen rather than from the
        // foreground pass (the import screens do exactly that), so it opens
        // its own pass instead of measuring into a stale one.
        if passStart == nil { beginPass() }
        if entries[label] == nil { entries[label] = Entry(); order.append(label) }
        entries[label]?.calls += 1
        inFlight[label, default: 0] += 1
        openWork += 1
        reportPending?.cancel()
        reportPending = nil
        let t0 = ContinuousClock.now
        let value = await work()
        entries[label]?.wallMs += ms(ContinuousClock.now - t0)
        if let n = inFlight[label] { inFlight[label] = n <= 1 ? nil : n - 1 }
        openWork -= 1
        if openWork <= 0 { scheduleReport() }
        return value
    }

    // MARK: - Heartbeat

    /// The jank signal. A 16ms sleep that measures how late it actually woke:
    /// the main actor can only answer it when it is free, so its lateness IS
    /// the stall. Threshold 100ms — well past `Task.sleep`'s own scheduling
    /// slop, and the rough point a stutter becomes something a person feels.
    ///
    /// It measures main-actor unavailability from EVERY source, not just this
    /// sweep (rendering, a `@Query` re-diff, another screen's work). That is
    /// deliberate: the report is about what the app feels like during the
    /// window, and a stall that isn't the sweep's fault is still a stall the
    /// sweep has to share the actor with.
    private static let hitchFloorMs: Double = 100
    private static let tick = Duration.milliseconds(16)
    /// A backstop so a sweep that never settles can't leave a heartbeat
    /// running for the life of the process.
    private static let passCeiling = Duration.seconds(90)

    private static func startMonitor() {
        monitor?.cancel()
        monitor = Task { @MainActor in
            let began = ContinuousClock.now
            while !Task.isCancelled {
                let t0 = ContinuousClock.now
                try? await Task.sleep(for: tick)
                if Task.isCancelled { return }
                let lateMs = ms((ContinuousClock.now - t0) - tick)
                if lateMs >= hitchFloorMs {
                    hitches += 1
                    hitchTotalMs += lateMs
                    hitchMaxMs = max(hitchMaxMs, lateMs)
                    // A stall with nothing instrumented in flight is a finding
                    // in its own right — it says the cost is in a slot this
                    // file doesn't cover — so it is charged somewhere visible
                    // rather than only to the pass total.
                    let charge = inFlight.isEmpty ? ["(none)"] : Array(inFlight.keys)
                    for label in charge {
                        if entries[label] == nil { entries[label] = Entry(); order.append(label) }
                        entries[label]?.hitches += 1
                        entries[label]?.hitchMs += lateMs
                    }
                }
                if ContinuousClock.now - began > passCeiling { return }
            }
        }
    }

    // MARK: - Report

    /// Sweeps are fire-and-forget with no join point, so "the pass is over" is
    /// inferred: nothing in flight, and nothing new started for a beat. The
    /// settle matters because the stagger is 40ms per slot — without it the
    /// first slot finishing before the fortieth starts would end the pass.
    private static let settle = Duration.milliseconds(1200)

    private static func scheduleReport() {
        reportPending?.cancel()
        reportPending = Task { @MainActor in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, openWork <= 0 else { return }
            report()
            monitor?.cancel(); monitor = nil
            passStart = nil
        }
    }

    /// The last completed pass, kept so a probe that dumps AFTER the pass
    /// settled still has something to print. Without it the probe races its
    /// own subject: the pass closes, `passStart` goes nil, and the dump reads
    /// "nothing measured" over a run that measured plenty.
    private static var lastReport: [String] = []

    /// Dump the pass. One NSLog per line.
    static func report() {
        guard isOn else { return }
        let lines = compose()
        lastReport = lines
        for line in lines { NSLog("[Casberi] %@", line) }
    }

    /// The report as lines, so a probe can print it without a second format:
    /// the pass in flight if there is one, else the last one that finished.
    static func summary() -> [String] {
        guard passStart != nil else {
            return lastReport.isEmpty ? ["sweepPass| none (nothing measured)"] : lastReport
        }
        return compose()
    }

    private static func compose() -> [String] {
        guard let passStart else { return ["sweepPass| none (nothing measured)"] }
        let wallMs = ms(ContinuousClock.now - passStart)
        var lines = [String(format:
            "sweepPass| wall=%.0fms labels=%d hitches=%d hitchTotal=%.0fms worst=%.0fms",
            wallMs, order.count, hitches, hitchTotalMs, hitchMaxMs)]
        // Worst first: the report exists to name what to fix, and rank is the
        // whole answer. Ordered by time STALLED, not by wall time — a sweep
        // that waits on a socket for two seconds costs nobody anything, and
        // one that holds the actor for 300ms costs everybody the frame.
        for label in order.sorted(by: { (entries[$0]?.hitchMs ?? 0, entries[$0]?.wallMs ?? 0)
                                      > (entries[$1]?.hitchMs ?? 0, entries[$1]?.wallMs ?? 0) }) {
            guard let e = entries[label] else { continue }
            lines.append(String(format:
                "sweepSlot| %@ calls=%d wall=%.0fms hitches=%d stalled=%.0fms",
                label, e.calls, e.wallMs, e.hitches, e.hitchMs))
        }
        return lines
    }
}

/// Release-safe call shim, so a sweep can time itself in one line without the
/// gate spelled at every call site.
@MainActor @inline(__always)
func sweepTimed<T>(_ label: String, _ work: () async -> T) async -> T {
    await SweepClock.measure(label, work)
}
