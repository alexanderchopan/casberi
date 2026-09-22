import Foundation
import QuartzCore
import os

/// **ONE FACT ABOUT THE HAND, FOR EVERYONE WHO SCHEDULES WORK (prd §666,
/// 2026-09-09, user: "i should be able to quickly scroll left and right up
/// and down flick the dock around and so on without worrying it's going to
/// snag").** Three gestures own the main thread while they run — a feed
/// scroll, a dock flick, a room swipe — and every deferrable pass (the
/// foreground sweep, the index backfills, the detectors) waits here for all
/// three to be still before it starts. `ShellChrome` already held the first
/// two as flags for the swipe budget's lift; this is the same fact with no
/// `ShellChrome` in hand, so a model-layer sweep can ask.
///
/// It is also where the hitch meter learns a gesture began and ended.
@MainActor
enum GestureGate {
    private(set) static var scrolling = false
    private(set) static var dock = false
    private(set) static var swipe = false

    static var busy: Bool { scrolling || dock || swipe }

    static func set(scrolling on: Bool) { transition(&scrolling, on, .scroll) }
    static func set(dock on: Bool)      { transition(&dock, on, .dock) }
    static func set(swipe on: Bool)     { transition(&swipe, on, .swipe) }

    private static func transition(_ flag: inout Bool, _ on: Bool, _ kind: HitchMeter.Kind) {
        guard flag != on else { return }
        flag = on
        if on { HitchMeter.shared.begin(kind) } else { HitchMeter.shared.end(kind) }
    }

    /// **THE CAP IS FOR A STUCK FLAG, NOT A HAND (prd §725, 2026-09-13, user:
    /// "the dock sometimes freezes when scrolling back and forth").** Every
    /// gesture ends, and every flag here is cleared at its end (§658's
    /// amendment closed the one door a flag could stick through), so the only
    /// thing a cap protects against is a flag nobody clears. Three seconds
    /// was short enough that a person flicking the dock back and forth
    /// reached it — and at the cap EVERY waiter landed at once, under the
    /// finger: the unbounded room build, the sweep's kick, its landings'
    /// save and every `@Query` that save re-runs. That is the freeze.
    /// A flick decelerates in under two seconds; eight is past any
    /// deliberate back-and-forth and still bounds a flag that stuck.
    static let stuckFlagCapMs = 8000
    static let stuckFlagCap: Duration = .milliseconds(stuckFlagCapMs)

    /// Returns when no gesture is under way, or after `cap` (see
    /// `stuckFlagCap`). Polled rather than awaited on a continuation because
    /// the flags are written from three places that must stay cheap; 50ms is
    /// below what any sweep can feel.
    static func idle(cap: Duration = stuckFlagCap) async {
        let deadline = ContinuousClock.now + cap
        // A CANCELLED waiter leaves at once: `Task.sleep` throws the moment
        // its task is cancelled, and `try?` swallowed that — so a waiter
        // whose task was cancelled (a room change under `.task(id:)`, a
        // coalescer re-arm) spun this loop flat out on the main actor for
        // the rest of the cap (code review, 2026-09-13).
        while busy, !Task.isCancelled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// **THE FRAME METER (prd §666).** A `CADisplayLink` that runs only while a
/// gesture is under way and records, per gesture, the worst frame and how
/// many frames missed their budget. Apple's bar is a per-gesture hitch
/// measurement, not a feeling; MetricKit already hands this app a daily
/// scroll-hitch ratio (`AppMetrics`), and this is the same number read live,
/// one gesture at a time, so the next perf pass aims at the actual worst
/// three rather than the plausible ones. Costs nothing at rest: the link is
/// invalidated when no gesture is on.
@MainActor
final class HitchMeter: NSObject {
    static let shared = HitchMeter()

    /// `tap` is the dock's chip tap (prd §668) — a gesture that is over
    /// before its consequences are, so it is measured as a fixed span rather
    /// than by a finger lifting: see `span(_:for:)`.
    enum Kind: String, Codable { case scroll, dock, swipe, tap }

    struct Sample: Codable, Identifiable {
        var id = UUID()
        var kind: Kind
        var at: Date
        var durationMs: Double
        var worstFrameMs: Double
        var hitches: Int
        var frames: Int
    }

    private static let key = "perf.hitches.v1"
    private static let keep = 40

    private var link: CADisplayLink?
    private var open: [Kind: Date] = [:]
    private var lastTimestamp: CFTimeInterval?
    /// One tally PER OPEN GESTURE, started at its own `begin` (2026-09-22).
    /// The meter kept one tally for the link's whole life, reset only when the
    /// link started — so a gesture that began while another was open reported
    /// the running total since the FIRST one. The phone's Diagnostics showed
    /// it: a 516ms tap with "1,536 frames" (120Hz gives ~62), and one 518ms
    /// "worst frame" repeated across every tap, dock and swipe line, because a
    /// 16.7s dock gesture was open under all of them.
    private struct Tally { var worst: Double = 0; var hitches = 0; var frames = 0 }
    private var tallies: [Kind: Tally] = [:]
    private let signposter = OSSignposter(subsystem: "com.casberi.app", category: "Gestures")
    private var states: [Kind: OSSignpostIntervalState] = [:]

    private(set) var samples: [Sample] = {
        guard let data = UserDefaults.standard.data(forKey: HitchMeter.key),
              let saved = try? JSONDecoder().decode([Sample].self, from: data) else { return [] }
        return saved
    }()

    func begin(_ kind: Kind) {
        guard open[kind] == nil else { return }
        open[kind] = Date()
        tallies[kind] = Tally()
        states[kind] = signposter.beginInterval("Gesture", id: signposter.makeSignpostID(), "\(kind.rawValue)")
        if link == nil { start() }
    }

    func end(_ kind: Kind) {
        guard let began = open.removeValue(forKey: kind) else { return }
        let t = tallies.removeValue(forKey: kind) ?? Tally()
        let (worst, hitches, frames) = (t.worst, t.hitches, t.frames)
        if let state = states.removeValue(forKey: kind) {
            signposter.endInterval("Gesture", state, "worst \(Int(worst))ms hitches \(hitches)")
        }
        let sample = Sample(kind: kind, at: began,
                            durationMs: Date().timeIntervalSince(began) * 1000,
                            worstFrameMs: worst, hitches: hitches, frames: frames)
        samples.insert(sample, at: 0)
        if samples.count > Self.keep { samples.removeLast(samples.count - Self.keep) }
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        #if DEBUG
        if hitches > 0 {
            NSLog("hitch: %@ worst %.0fms, %d of %d frames over budget", kind.rawValue, worst, hitches, frames)
        }
        #endif
        if open.isEmpty { stop() }
    }

    /// A gesture with no lift to end it: measure a fixed window from now.
    /// Restarts cleanly if one is already open, so a second tap during the
    /// first's window measures itself rather than extending the first.
    func span(_ kind: Kind, for milliseconds: Int) {
        if open[kind] != nil { end(kind) }
        spanGeneration &+= 1
        let generation = spanGeneration
        begin(kind)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard spanGeneration == generation else { return }
            end(kind)
        }
    }

    private var spanGeneration = 0

    func forget() {
        samples = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// The Diagnostics lines: the worst and the count per kind over the kept
    /// window, then the last few gestures one per line.
    func lines() -> [String] {
        guard !samples.isEmpty else { return ["Hitches: no gestures measured yet this install."] }
        var out: [String] = []
        for kind in [Kind.scroll, .dock, .swipe] {
            let mine = samples.filter { $0.kind == kind }
            guard !mine.isEmpty else { continue }
            let worst = mine.map(\.worstFrameMs).max() ?? 0
            let hitchy = mine.filter { $0.hitches > 0 }.count
            out.append(String(format: "Hitches · %@: %d gestures, %d with a missed frame, worst frame %.0fms",
                              kind.rawValue, mine.count, hitchy, worst))
        }
        for s in samples.prefix(6) {
            out.append(String(format: "  %@ · %.0fms · worst %.0fms · %d/%d frames over budget",
                              s.kind.rawValue, s.durationMs, s.worstFrameMs, s.hitches, s.frames))
        }
        return out
    }

    private func start() {
        lastTimestamp = nil
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ l: CADisplayLink) {
        defer { lastTimestamp = l.timestamp }
        guard let last = lastTimestamp else { return }
        let delta = (l.timestamp - last) * 1000
        // The budget is the link's own frame, so a 60Hz fallback is judged at
        // 16.7ms and a 120Hz frame at 8.3ms — a missed frame is a missed frame.
        let budget = l.duration * 1000
        let missed = delta > budget * 1.5
        for kind in tallies.keys {
            tallies[kind]!.frames += 1
            if missed { tallies[kind]!.hitches += 1 }
            if delta > tallies[kind]!.worst { tallies[kind]!.worst = delta }
        }
    }
}
