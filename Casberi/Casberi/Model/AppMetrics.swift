import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// MetricKit (2026-09-05) — the two failure classes no check in this repo can
/// see, arriving on their own instead of being asked for.
///
/// **Why this exists.** Every crash this project has diagnosed
/// (176 / 177 / 188 / 250 / 280 / 281 / 511 / 521) was diagnosed from an `.ips`
/// file the user exported by hand, days after the fact, and each one's entry in
/// CLAUDE.md ends the same way: the build was clean, the static audits passed on
/// the crashing binary, and no simulator could reproduce it. `verify.sh` reaches
/// exactly as far as a simulator reaches. MetricKit reaches the other side —
/// the shipped Release binary, on a real device, under a real CPU quota — and
/// hands over the two things that side alone knows:
///
///   • `MXCrashDiagnostic` / `MXHangDiagnostic`, with the attributed thread's
///     call stack, delivered on the NEXT LAUNCH after the event;
///   • `MXAppExitMetric.backgroundExitData.cumulativeAppWatchdogExitCount` —
///     the 0x8BADF00D class of prd §614, counted rather than reported, so a
///     regression shows up as a number going back up instead of as a second
///     round of user reports.
///
/// **What it is NOT, stated here because a metrics screen that overstates
/// itself is worse than none.** It is not a profiler and it cannot say WHY:
/// launch and hang times arrive as HISTOGRAMS whose buckets are hundreds of
/// milliseconds wide, aggregated over a whole day, so it can tell you something
/// got slower and never which line did it. `scripts/perf.sh` and `LaunchPerf`
/// keep that job. It is also thin evidence at this app's size — payloads come
/// from the devices that actually ran the build, and for a solo pre-launch app
/// that is a handful of days from one or two phones, so a moved bucket is a
/// hint, not a measurement.
///
/// **Delivery, exactly.** A subscriber must be registered or the system keeps
/// nothing — `pastPayloads` stays empty forever without the `add` in `begin()`.
/// Daily metric payloads arrive at most once per 24h. Diagnostics arrive on the
/// launch after the event. **Nothing is delivered in the Simulator**, which is
/// why every reading here is honest about being empty rather than drawing a row
/// of dashes, and why the logic that shapes a payload lives in
/// `AppMetricsDigest` where a harness can reach it.
///
/// **Nothing leaves the device.** No network, so nothing to declare in
/// `NetworkReach` (prd §205) and no receipt to record: this reads a store the
/// OS already keeps for this app and renders it locally. The one thing it
/// writes is `remembered` below.
final class AppMetrics: NSObject, @unchecked Sendable {

    static let shared = AppMetrics()

    /// Register the subscriber. Called once from `CasberiApp.init`.
    ///
    /// In `init` rather than on first foreground for the reason
    /// `UNUserNotificationCenter.current().delegate` is: a diagnostic payload
    /// for the crash that JUST happened is delivered early in the next launch,
    /// and a subscriber added after that delivery gets nothing — the one launch
    /// where the payload matters most is the one that would lose it.
    static func begin() {
        #if canImport(MetricKit)
        MXMetricManager.shared.add(shared)
        #endif
    }

    // MARK: - The remembered diagnostics
    //
    // MetricKit's own `pastDiagnosticPayloads` rotates on a schedule Apple does
    // not document, and this screen is opened perhaps monthly — so a crash
    // could arrive, sit in the system's store, and rotate out before anyone
    // looked. What is kept here is the RENDERED LINE, not a parallel model of
    // the payload: `report()` is the only thing that turns a payload into
    // words, and this stores its output. That is deliberate and it is the
    // `NetworkLedger.resolvedService` lesson — a second copy of a rule is how
    // two surfaces come to disagree, and the disagreement is invisible.

    struct Remembered: Codable, Equatable {
        /// kind + instant + deepest frame. Two payloads describing one event
        /// (the system still holds it AND we saved it) collapse to one row.
        var id: String
        var at: Date
        var text: String
    }

    private static let storeKey = "metrics.diagnostics.v1"
    /// Long, because these are RARE and the whole point is to still have one
    /// when somebody finally opens the screen.
    private static let retention: TimeInterval = 90 * 86_400
    private static let maxRemembered = 40

    private let lock = NSLock()

    /// Payloads arrive on a background queue, so every touch is locked.
    private func remember(_ rows: [Remembered]) {
        guard !rows.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var byID: [String: Remembered] = [:]
        for row in Self.loadRows() + rows { byID[row.id] = row }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        let kept = byID.values
            .filter { $0.at > cutoff }
            .sorted { $0.at > $1.at }
            .prefix(Self.maxRemembered)
        if let data = try? JSONEncoder().encode(Array(kept)) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    private static func loadRows() -> [Remembered] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let rows = try? JSONDecoder().decode([Remembered].self, from: data)
        else { return [] }
        return rows
    }

    /// Empties the remembered diagnostics. The system's own store is not ours
    /// to clear, and saying so is the honest half of this verb.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
}

// MARK: - Subscription

#if canImport(MetricKit)
extension AppMetrics: MXMetricManagerSubscriber {

    /// One line per daily payload. Kept in a Release build on purpose: it costs
    /// a single `NSLog` a day and it is the only way a `log stream` against a
    /// device can show that delivery is happening at all — the state that
    /// otherwise looks identical to "MetricKit is broken".
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            NSLog("[Casberi] metricKit: metric payload %@ → %@ (build %@)",
                  ISO8601DateFormatter().string(from: payload.timeStampBegin),
                  ISO8601DateFormatter().string(from: payload.timeStampEnd),
                  payload.metaData?.applicationBuildVersion ?? "?")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var rows: [Remembered] = []
        for payload in payloads {
            for line in AppMetrics.diagnosticEntries(payload) {
                NSLog("[Casberi] metricKit: %@", line.text)
                rows.append(line)
            }
        }
        remember(rows)
    }
}
#endif

// MARK: - The reading
//
// ONE renderer, reached by the Diagnostics screen and by `-metricsProbe`. The
// probe exists to read this headlessly on a device over `log stream`; the
// screen exists so a report can be a screenshot of facts. Both must say the
// same thing or the probe stops being evidence about the screen.

extension AppMetrics {

    /// Every line the Diagnostics screen prints for MetricKit, in order.
    static func report() -> [String] {
        #if canImport(MetricKit)
        var out: [String] = []
        let payloads = MXMetricManager.shared.pastPayloads
        let diagnostics = MXMetricManager.shared.pastDiagnosticPayloads

        // Delivered diagnostics, newest first: the system's own store merged
        // with what we kept, deduped by event identity.
        var byID: [String: Remembered] = [:]
        for row in loadRows() { byID[row.id] = row }
        for payload in diagnostics {
            for row in diagnosticEntries(payload) { byID[row.id] = row }
        }
        let events = byID.values.sorted { $0.at > $1.at }

        if payloads.isEmpty && events.isEmpty {
            out.append("MetricKit: subscribed, nothing delivered yet")
            out.append("→ daily metrics arrive at most once every 24h, and a crash or hang report arrives on the FIRST LAUNCH AFTER it happened. Neither is ever delivered in the Simulator — this reads empty there by design, not by fault.")
            return out
        }
        out.append("MetricKit: \(payloads.count) daily payload(s) · \(events.count) diagnostic event(s)")

        for row in events.prefix(8) {
            out.append(row.text)
        }
        if events.count > 8 { out.append("… and \(events.count - 8) older event(s)") }

        if let latest = payloads.last {
            out.append(contentsOf: metricLines(latest))
        }
        return out
        #else
        return ["MetricKit: unavailable on this platform"]
        #endif
    }
}

#if canImport(MetricKit)
extension AppMetrics {

    // MARK: Diagnostics → lines

    /// A payload's crashes, hangs, CPU and disk exceptions — and, on iOS only,
    /// its slow launches — as one remembered row each.
    static func diagnosticEntries(_ payload: MXDiagnosticPayload) -> [Remembered] {
        var rows: [Remembered] = []
        let at = payload.timeStampEnd

        for d in payload.crashDiagnostics ?? [] {
            var head = "CRASH"
            if let signal = d.signal { head += " signal \(signal)" }
            if let type = d.exceptionType { head += " exc \(type)" }
            if let code = d.exceptionCode { head += "/\(code)" }
            // The termination reason is where 0x8BADF00D says so IN WORDS
            // ("scene-update watchdog transgression…"), which is the single
            // most diagnostic string in the 511/521 reports.
            if let reason = d.terminationReason, !reason.isEmpty {
                head += " · \(reason.prefix(120))"
            }
            rows.append(row(kind: head, at: at, diagnostic: d, tree: d.callStackTree))
        }
        for d in payload.hangDiagnostics ?? [] {
            let seconds = d.hangDuration.converted(to: .seconds).value
            rows.append(row(kind: "HANG \(AppMetricsDigest.number(seconds))s",
                            at: at, diagnostic: d, tree: d.callStackTree))
        }
        for d in payload.cpuExceptionDiagnostics ?? [] {
            let cpu = d.totalCPUTime.converted(to: .seconds).value
            let sampled = d.totalSampledTime.converted(to: .seconds).value
            rows.append(row(kind: "CPU EXCEPTION \(AppMetricsDigest.number(cpu))s of \(AppMetricsDigest.number(sampled))s",
                            at: at, diagnostic: d, tree: d.callStackTree))
        }
        for d in payload.diskWriteExceptionDiagnostics ?? [] {
            let mb = d.totalWritesCaused.converted(to: .megabytes).value
            rows.append(row(kind: "DISK WRITE EXCEPTION \(AppMetricsDigest.number(mb))MB",
                            at: at, diagnostic: d, tree: d.callStackTree))
        }
        // NOT `#if !targetEnvironment(macCatalyst)`, and the reason is worth
        // keeping because the header reads the other way. `MXAppLaunchDiagnostic`
        // and `appLaunchDiagnostics` are declared `API_AVAILABLE(ios(16.0))
        // API_UNAVAILABLE(macos, tvos, watchos)` — which governs NATIVE macOS.
        // Mac Catalyst inherits the iOS availability unless a symbol says
        // `API_UNAVAILABLE(macCatalyst)`, and this one does not. MEASURED, not
        // reasoned: `swiftc -typecheck -target arm64-apple-ios18.0-macabi`
        // against the macOS SDK compiles this block clean. A guard here would
        // have cost the Mac its slow-launch diagnostics for nothing.
        for d in payload.appLaunchDiagnostics ?? [] {
            let seconds = d.launchDuration.converted(to: .seconds).value
            rows.append(row(kind: "SLOW LAUNCH \(AppMetricsDigest.number(seconds))s",
                            at: at, diagnostic: d, tree: d.callStackTree))
        }
        return rows
    }

    /// `tree` is passed in rather than read off `diagnostic`: `callStackTree`
    /// is declared on each MXDiagnostic SUBCLASS, never on `MXDiagnostic`
    /// itself, so the shared shape has to take it as an argument.
    private static func row(kind: String, at: Date,
                            diagnostic: MXDiagnostic,
                            tree: MXCallStackTree) -> Remembered {
        // 40 frames, not the digest's 12 (prd §671): build 551's hang read
        // `assignWithCopy for FaceScopeRail` under twelve AttributeGraph
        // frames and stopped, so the view whose update was looping was
        // never named — the Casberi caller sat just below the cap.
        let frames = AppMetricsDigest.frames(callStackTreeJSON: tree.jsonRepresentation(), limit: 40)
        let own = AppMetricsDigest.ownFrame(frames, binary: ownBinaryName)
        let build = diagnostic.metaData.applicationBuildVersion
        let head = "\(short(at)) \(kind) · \(diagnostic.applicationVersion) (\(build)) · \(diagnostic.metaData.osVersion) · \(diagnostic.metaData.deviceType)"
        // The deepest OUR-BINARY frame on the head line, then the top of the
        // attributed stack under it. A crash with no Casberi frame at all is a
        // different animal from one in our own code and must read that way at
        // a glance.
        let stack = AppMetricsDigest.frameLines(frames)
        let body = stack.isEmpty ? "" : "\n    " + stack.joined(separator: "\n    ")
        let text = own.map { "\(head) · in \($0)\(body)" } ?? "\(head)\(body)"
        return Remembered(id: "\(kind)|\(Int(at.timeIntervalSince1970))|\(stack.first ?? "-")",
                          at: at, text: text)
    }

    /// The executable's own name, so `ownFrame` matches what MetricKit writes
    /// in `binaryName`. Read from the bundle rather than hard-coded: this is
    /// the string a rename would silently break, and the failure would be a
    /// crash row that stops saying which of our lines it was in.
    static var ownBinaryName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String) ?? "Casberi"
    }

    // MARK: Metrics → lines

    /// The newest daily payload, reduced to the numbers this app has actually
    /// been burned by. Deliberately NOT everything MetricKit carries — GPU,
    /// cellular, location and display metrics have never been the question
    /// here, and a screen of numbers nobody reads is how the ones that matter
    /// get missed.
    static func metricLines(_ payload: MXMetricPayload) -> [String] {
        var out: [String] = []
        out.append("Day \(short(payload.timeStampBegin))–\(short(payload.timeStampEnd)) · \(payload.latestApplicationVersion)\(payload.includesMultipleApplicationVersions ? " (+ earlier versions)" : "")")

        if let launch = payload.applicationLaunchMetrics {
            if let line = AppMetricsDigest.histogramLine(
                "Time to first draw", buckets(launch.histogrammedTimeToFirstDraw),
                unit: "ms", noun: "launches") { out.append(line) }
            if let line = AppMetricsDigest.histogramLine(
                "Resume", buckets(launch.histogrammedApplicationResumeTime),
                unit: "ms", noun: "resumes") { out.append(line) }
        }
        if let responsiveness = payload.applicationResponsivenessMetrics,
           let line = AppMetricsDigest.histogramLine(
            "Hang time", buckets(responsiveness.histogrammedApplicationHangTime),
            unit: "ms", noun: "hangs") { out.append(line) }
        if let animation = payload.animationMetrics {
            let ratio = animation.scrollHitchTimeRatio.value
            out.append("Scroll hitch ratio: \(AppMetricsDigest.number(ratio * 1000))ms hitched per 1000ms scrolled")
        }
        if let memory = payload.memoryMetrics {
            let peak = memory.peakMemoryUsage.converted(to: .megabytes).value
            out.append("Peak memory: \(AppMetricsDigest.number(peak))MB")
        }
        if let cpu = payload.cpuMetrics {
            let seconds = cpu.cumulativeCPUTime.converted(to: .seconds).value
            out.append("CPU time: \(AppMetricsDigest.number(seconds))s")
        }
        if let exits = payload.applicationExitMetrics {
            // THE §614 COUNTER. Named apart from the other exit reasons rather
            // than folded into an "abnormal" total, because the whole reason
            // this file exists is that two shipped builds died this exact way
            // and nothing in the pass could see it. Foreground and background
            // are reported separately: a background watchdog kill is the
            // app-switcher-snapshot class, a foreground one is a hang.
            let bg = exits.backgroundExitData
            let fg = exits.foregroundExitData
            out.append("Watchdog exits: \(bg.cumulativeAppWatchdogExitCount) background · \(fg.cumulativeAppWatchdogExitCount) foreground")
            let bad = bg.cumulativeBadAccessExitCount + fg.cumulativeBadAccessExitCount
            let memoryLimit = bg.cumulativeMemoryResourceLimitExitCount + fg.cumulativeMemoryResourceLimitExitCount
            out.append("Other abnormal exits: \(bad) bad-access · \(memoryLimit) memory-limit · \(bg.cumulativeCPUResourceLimitExitCount) cpu-limit · \(bg.cumulativeMemoryPressureExitCount) memory-pressure")
        }
        return out
    }

    /// `MXHistogram` → the unit-free buckets `AppMetricsDigest` works in.
    /// Converted to milliseconds HERE, at the boundary, so the pure half never
    /// has to know a unit.
    private static func buckets(_ histogram: MXHistogram<UnitDuration>) -> [AppMetricsDigest.Bucket] {
        var out: [AppMetricsDigest.Bucket] = []
        let e = histogram.bucketEnumerator
        while let bucket = e.nextObject() as? MXHistogramBucket<UnitDuration> {
            out.append(.init(bucket.bucketStart.converted(to: .milliseconds).value,
                             bucket.bucketEnd.converted(to: .milliseconds).value,
                             bucket.bucketCount))
        }
        return out
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: date)
    }
}
#endif
