import Foundation

/// The PURE half of the MetricKit read (2026-09-05) — histogram summarising and
/// call-stack flattening, over plain Foundation types.
///
/// Split from `AppMetrics.swift` for the `BridgeHealth.folded` reason, which is
/// the strongest form of it in this tree: **nothing in this project can produce
/// a MetricKit payload.** MetricKit delivers only on a real device, only in a
/// shipped build, and at most once a day — so there is no path here, on the
/// simulator or otherwise, that can exercise the code that turns a payload into
/// the lines a person reads. Foundation-only and pure, this file compiles
/// VERBATIM into `scripts/metrics-selftest.sh` against hand-built fixtures, and
/// that harness is the only proof these rules hold.
///
/// The failure modes are all SILENT WRONG ANSWERS on a screen whose entire
/// purpose is to be screenshotted and believed:
///
///   • a quantile read off the wrong bucket — a launch time reported as half or
///     double what the device measured, which is worse than reporting nothing;
///   • the WRONG THREAD's stack — MetricKit hands over every thread, and only
///     the attributed one crashed; picking the first would symbolicate a thread
///     that was sitting in `mach_msg_trap`;
///   • a stack rendered root-first — the leaf is the line that crashed, and a
///     reader who takes frame 0 as the cause diagnoses `main`;
///   • frames whose offsets don't survive the trip — `atos` gives a wrong
///     function silently, never an error.
enum AppMetricsDigest {

    // MARK: - Histograms

    /// One MetricKit bucket, unit-free. MetricKit's own `MXHistogramBucket`
    /// carries a `Measurement`; the unit is fixed per histogram and belongs to
    /// the caller's label, so it is converted once at the boundary and never
    /// travels through here.
    struct Bucket: Equatable {
        var start: Double
        var end: Double
        var count: Int
        init(_ start: Double, _ end: Double, _ count: Int) {
            self.start = start; self.end = end; self.count = count
        }
    }

    /// The number of samples a histogram holds.
    static func total(_ buckets: [Bucket]) -> Int {
        buckets.reduce(0) { $0 + max(0, $1.count) }
    }

    /// The END of the bucket the q-th sample falls in — an UPPER BOUND, never
    /// an estimate of the value.
    ///
    /// This returns `end` and the caller renders it with a `≤` for a reason
    /// worth stating: a histogram cannot tell you where inside a bucket its
    /// samples sat, so interpolating across the bucket (the usual quantile
    /// trick) would invent precision the device never reported. MetricKit's
    /// launch buckets are hundreds of milliseconds wide — wide enough that an
    /// invented midpoint could sit either side of a decision.
    ///
    /// Buckets are sorted by `start` first: `bucketEnumerator` is documented to
    /// yield them in order and does, but a quantile silently computed off an
    /// unsorted list is exactly the kind of wrong number this file exists not
    /// to print.
    static func quantileBucketEnd(_ buckets: [Bucket], q: Double) -> Double? {
        let n = total(buckets)
        guard n > 0, q > 0, q <= 1 else { return nil }
        // Ceiling, so q=0.5 over 2 samples names the bucket the 1st sits in and
        // q=1 always names the last non-empty bucket rather than falling off
        // the end.
        //
        // SNAPPED TO 1e-6 BEFORE THE CEILING. `q * n` is not exact in binary
        // floating point, and a bare ceiling over a product that overshot by
        // one ulp names the NEXT bucket — a plausible number, off by exactly
        // one bucket, appearing only at particular sample counts, which is the
        // shape of a bug that gets read off a screenshot and believed.
        //
        // MEASURED rather than assumed, because the assumption was wrong the
        // first time: `0.9 * 10` is exactly 9.0, and so is every other product
        // of the three quantiles this app actually asks for (0.5, 0.9, 1)
        // against every n up to 200,000 — checked, zero disagreements. The
        // snapping is still load-bearing because this is a general quantile:
        // over q in 0.01…1.00 and n in 1…5000, 702 of 500,000 pairs disagree,
        // the smallest being n=25 q=0.28, where 7.000000000000001 ceilings to
        // 8. The harness asserts that case, not the one that reads plausibly.
        let exact = ((q * Double(n)) * 1e6).rounded() / 1e6
        let target = max(1, Int(exact.rounded(.up)))
        var seen = 0
        for bucket in buckets.sorted(by: { $0.start < $1.start }) where bucket.count > 0 {
            seen += bucket.count
            if seen >= target { return bucket.end }
        }
        return nil
    }

    /// `"time to first draw: 41 launches · median ≤ 1200ms · p90 ≤ 2400ms · worst ≤ 4800ms"`,
    /// or nil when the histogram is empty — a metric with no samples has
    /// nothing to say, and a row of dashes on a diagnostics screen reads as a
    /// broken instrument rather than as an untouched one.
    static func histogramLine(_ label: String,
                              _ buckets: [Bucket],
                              unit: String,
                              noun: String) -> String? {
        let n = total(buckets)
        guard n > 0 else { return nil }
        func at(_ q: Double) -> String {
            quantileBucketEnd(buckets, q: q).map { "≤ \(number($0))\(unit)" } ?? "—"
        }
        return "\(label): \(n) \(noun) · median \(at(0.5)) · p90 \(at(0.9)) · worst \(at(1))"
    }

    /// Trims a trailing `.0` so whole numbers read as whole numbers, and keeps
    /// one decimal otherwise. MetricKit bucket edges are round by construction;
    /// a converted unit (bytes → MB) is not.
    static func number(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    // MARK: - Call stacks

    /// One frame, in the only form that is any use later: the binary and the
    /// offset into its text segment, which is exactly what `atos -o <dSYM> -l
    /// <load address>` takes. A symbol name is not available here — the device
    /// has no dSYM — so pretending to one would be the fake-status failure.
    struct Frame: Equatable {
        var binary: String
        var offset: Int
        var sampleCount: Int
    }

    /// The attributed thread's stack, LEAF FIRST, from an `MXCallStackTree`
    /// JSON representation.
    ///
    /// Three rules, each of which is a wrong answer if broken:
    ///
    /// 1. **The attributed thread wins.** `callStacks` holds every thread;
    ///    `threadAttributed` marks the one that crashed or hung. Taking the
    ///    first would usually hand back a thread parked in `mach_msg_trap` —
    ///    a plausible-looking stack of the wrong thread, which is worse than
    ///    no stack. Falls back to the first only when nothing is marked.
    ///
    /// 2. **Leaf first — and the tree ALREADY IS (prd §628, 2026-09-06).**
    ///    `callStackRootFrames` is the crash point, and each `subFrames` step
    ///    is the CALLER: the walk runs leaf → … → `main` → `start`. The first
    ///    cut of this assumed the opposite (root = `main`), reversed the walk,
    ///    and THEN capped it — so on a real report the cap kept the twelve
    ///    frames nearest `start` and discarded the leaf. Build 525's two
    ///    watchdog reports each rendered as `dyld, main, SwiftUI ×3, UIKit ×2,
    ///    GraphicsServices, CoreFoundation ×4` and nothing else: the main
    ///    thread's run-loop scaffolding, identical in both, with the one
    ///    frame that mattered cut off the end. That order is coherent ONLY as
    ///    a root-first list — under the old assumption it would have meant
    ///    SwiftUI called `main` — which is how the polarity was settled: by
    ///    the device's own output, not by a fixture built on the same guess.
    ///    The cap keeps the leaf end now; the harness's fixtures carry the
    ///    real shape, including that report.
    ///
    /// 3. **The heaviest branch at a fork.** A crash stack is one chain, but a
    ///    HANG stack is SAMPLED and forks wherever the samples disagreed;
    ///    `sampleCount` is which way most of the time went. Following the first
    ///    child instead would report whichever branch the encoder happened to
    ///    write first — a different answer for the same hang, run to run.
    ///
    /// Depth is capped so a malformed or cyclic tree cannot walk forever on a
    /// device: this parses data the OS hands us, and a diagnostics reader that
    /// can hang the app is a worse bug than the one it was opened to explain.
    static func frames(callStackTreeJSON data: Data, limit: Int = 12) -> [Frame] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]],
              !stacks.isEmpty else { return [] }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks[0]
        guard let roots = stack["callStackRootFrames"] as? [[String: Any]] else { return [] }

        var chain: [Frame] = []
        var here = heaviest(roots)
        var depth = 0
        while let node = here, depth < 512 {
            depth += 1
            if let frame = frame(from: node) { chain.append(frame) }
            here = heaviest(node["subFrames"] as? [[String: Any]] ?? [])
        }
        // The walk is already leaf-first; the cap must keep THAT end. (See
        // rule 2 — `reversed().prefix()` here is precisely the bug.)
        return Array(chain.prefix(limit))
    }

    /// `sampleCount` decides; ties go to the first, so the walk is
    /// deterministic for a crash tree where every count is 1.
    private static func heaviest(_ nodes: [[String: Any]]) -> [String: Any]? {
        guard !nodes.isEmpty else { return nil }
        return nodes.max { count(of: $0) < count(of: $1) } ?? nodes[0]
    }

    private static func count(of node: [String: Any]) -> Int {
        (node["sampleCount"] as? NSNumber)?.intValue ?? 0
    }

    private static func frame(from node: [String: Any]) -> Frame? {
        // `binaryName` is the one field with no sane default: a frame that
        // cannot say which binary it is in cannot be symbolicated, and printing
        // it would put an un-actionable line above an actionable one.
        guard let binary = node["binaryName"] as? String, !binary.isEmpty else { return nil }
        let offset = (node["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue ?? 0
        return Frame(binary: binary, offset: offset, sampleCount: count(of: node))
    }

    /// `"Casberi +2592912"` — the form `atos` takes, and the form build 280 and
    /// 281's two reports were compared in (CLAUDE.md: "both threads at the same
    /// Casberi offset in each"), so two payloads can be read against each other
    /// straight off the screen.
    static func frameLines(_ frames: [Frame]) -> [String] {
        frames.map { "\($0.binary) +\($0.offset)" }
    }

    /// Our own binary's deepest frame — the one line worth putting on a summary
    /// row, because a stack whose every Casberi frame is missing is a crash
    /// inside a system framework and reads completely differently.
    static func ownFrame(_ frames: [Frame], binary: String) -> String? {
        frames.first { $0.binary == binary }.map { "\($0.binary) +\($0.offset)" }
    }
}
