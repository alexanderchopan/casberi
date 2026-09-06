import Foundation

/// The phone's own perf numbers, readable ON the phone (prd §623, 2026-09-05).
///
/// **What this closes.** `docs/perf-spec.md` P0 — "baseline the phone" — was
/// written as a procedure that needs Xcode attached to the device: a Release
/// scheme, two launch arguments, and somebody reading the console. Every
/// number in the perf record is Debug on a simulator because that procedure
/// never ran. MetricKit (§622) fixes half of it: histograms arrive from real
/// devices, but at most once a day, aggregated, and only after the build has
/// been out long enough. This is the other half — the SAME spans, this
/// launch, this device, on the Diagnostics screen, seconds after they happen.
///
/// **What it records, and where the numbers come from.** Nothing here
/// measures anything. Every reading is handed in by an instrument that
/// already exists and already fires once per user event:
///   • `Launch`, `ForegroundSweep`, `AskFirstPaint`, `AskSettled` — from
///     `AppSignposts`, at the exact `.end` of each MetricKit interval, so the
///     figure on the screen and the figure in Apple's histogram are the same
///     stopwatch. No new signpost call site (the metrics self-test's closed
///     set stands); a `Date` is stamped beside each `.begin` and read beside
///     its `.end`.
///   • `SweepStalls` — from `SweepClock.report()`, the 16ms main-actor
///     heartbeat: hitch count, worst stall, and the slot charged the most.
///     Only while `measuring` is on, because the heartbeat is a cost.
///
/// **`measuring` is the P0 switch, moved from the Xcode scheme to a toggle.**
/// It writes the very keys the launch arguments write (`launchTimer`,
/// `sweepTimer`) into the standard defaults, which is where `LaunchClock`
/// and `SweepClock` already read them — so a Release build with the toggle
/// on behaves exactly like the scheme-driven procedure the spec describes,
/// with nothing attached. Both gates cache on first read, so it takes effect
/// on the next launch, and the screen says so.
///
/// **Cost.** One `Date` subtraction and one small `UserDefaults` write per
/// user event (a launch, an activation, an ask). The write is the largest
/// part and it is bounded: `keepPerSpan` readings per span, `retention` days.
/// Nothing runs per row, per frame, or in a view body.
///
/// **Nothing leaves the device**, and no ask TEXT is stored — an ask reading
/// carries its duration and the channel that painted it, never the question.
///
/// Foundation-only ON PURPOSE: `scripts/perf-readings-selftest.sh` compiles
/// this file verbatim against fixtures (the `AppMetricsDigest` shape), which
/// is the only proof the digest holds — the simulator can produce readings,
/// but a green run there says only that the write path executes.
enum PerfReadings {

    struct Reading: Codable, Equatable {
        var span: String
        var ms: Double
        var at: Date
        var build: String
        /// Free text the instrument attaches — the ask's paint channel, the
        /// sweep's hitch count and worst slot. Never the ask itself.
        var note: String
    }

    /// Fixed order, because the screen reads top-down as "open → sweep → ask"
    /// and a dictionary's order would shuffle it per launch.
    static let spans = ["Launch", "LaunchStore", "ChipsWalk", "ForegroundSweep", "AskFirstPaint", "AskSettled", "SweepStalls"]

    static let storeKey = "perf.readings.v1"
    static let keepPerSpan = 20
    static let retention: TimeInterval = 30 * 86_400

    /// Injectable so the harness writes to a suite of its own and the app's
    /// standard domain is never touched by a test.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard
    /// Same reason; the app passes its real build number, the harness a fixed one.
    nonisolated(unsafe) static var buildLabel: () -> String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    // MARK: - Recording

    /// Append one reading. Callers are the once-per-event instruments named in
    /// the header; a new caller must be one too.
    static func record(_ span: String, ms: Double, note: String = "", now: Date = Date()) {
        var rows = load()
        rows.append(Reading(span: span, ms: ms, at: now, build: buildLabel(), note: note))
        save(prune(rows, now: now))
    }

    static func forget() {
        defaults.removeObject(forKey: storeKey)
    }

    static func load() -> [Reading] {
        guard let data = defaults.data(forKey: storeKey),
              let rows = try? JSONDecoder().decode([Reading].self, from: data)
        else { return [] }
        return rows
    }

    private static func save(_ rows: [Reading]) {
        if let data = try? JSONEncoder().encode(rows) {
            defaults.set(data, forKey: storeKey)
        }
    }

    /// Newest `keepPerSpan` per span, nothing older than `retention`. Pure, so
    /// the harness can prove the bound.
    static func prune(_ rows: [Reading], now: Date) -> [Reading] {
        let cutoff = now.addingTimeInterval(-retention)
        var perSpan: [String: [Reading]] = [:]
        for r in rows where r.at > cutoff { perSpan[r.span, default: []].append(r) }
        var out: [Reading] = []
        for (_, list) in perSpan {
            out += list.sorted { $0.at < $1.at }.suffix(keepPerSpan)
        }
        return out.sorted { $0.at < $1.at }
    }

    // MARK: - The switch

    /// The two keys `LaunchClock.reports` and `SweepClock.isOn` read. Written
    /// as a pair because they are one decision — "measure this device" — and
    /// a stall count with no launch number beside it is half a baseline.
    static let switchKeys = ["launchTimer", "sweepTimer"]

    static var measuring: Bool {
        get { switchKeys.allSatisfy { defaults.bool(forKey: $0) } }
        set { for k in switchKeys { defaults.set(newValue, forKey: k) } }
    }

    // MARK: - Digest

    /// What the Diagnostics screen draws, one line per span. Pure over the
    /// rows so the harness can pin every shape: empty, one reading, the
    /// median/worst arithmetic, and the note carried on the newest.
    static func lines(_ rows: [Reading], now: Date = Date(), measuring: Bool) -> [String] {
        var out: [String] = []
        if rows.isEmpty {
            out.append("Performance: no readings yet — open the app, pull to refresh, ask something, then come back")
        }
        for span in spans {
            let list = rows.filter { $0.span == span }.sorted { $0.at < $1.at }
            guard let last = list.last else { continue }
            let sorted = list.map(\.ms).sorted()
            let median = sorted[sorted.count / 2]
            let worst = sorted.last ?? last.ms
            var line = "\(title(span)): last \(fmt(last.ms))"
            if list.count > 1 {
                line += " · median \(fmt(median)) · worst \(fmt(worst)) over \(list.count)"
            }
            if !last.note.isEmpty { line += " · \(last.note)" }
            line += " · \(last.build)"
            out.append(line)
        }
        if !measuring {
            out.append("Stalls are not being measured — turn on \"Measure stalls\" below and relaunch to record them")
        } else if !rows.contains(where: { $0.span == "SweepStalls" }) {
            out.append("Measuring stalls — the first reading lands after the next launch's foreground sweep")
        }
        return out
    }

    static func title(_ span: String) -> String {
        switch span {
        case "Launch": return "Open → first screen"
        case "LaunchStore": return "  of which: store opened"
        case "ChipsWalk": return "  of which: source strip resolved"
        case "ForegroundSweep": return "Foreground sweep"
        case "AskFirstPaint": return "Ask → first paint"
        case "AskSettled": return "Ask → settled"
        case "SweepStalls": return "Worst stall during a sweep"
        default: return span
        }
    }

    /// Milliseconds under two seconds, seconds above — a person reads
    /// "1.4s" faster than "1412ms", and the spec's own numbers switch there.
    static func fmt(_ ms: Double) -> String {
        if ms >= 2000 { return String(format: "%.1fs", ms / 1000) }
        return "\(Int(ms.rounded()))ms"
    }
}
