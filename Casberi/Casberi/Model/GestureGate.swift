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

    /// Returns when no gesture is under way, or after `cap` — a hand that
    /// never settles must not starve the work forever. Polled rather than
    /// awaited on a continuation because the flags are written from three
    /// places that must stay cheap; 50ms is below what any sweep can feel.
    static func idle(cap: Duration = .seconds(3)) async {
        let deadline = ContinuousClock.now + cap
        while busy, ContinuousClock.now < deadline {
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

    enum Kind: String, Codable { case scroll, dock, swipe }

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
    private var worst: Double = 0
    private var hitches = 0
    private var frames = 0
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
        states[kind] = signposter.beginInterval("Gesture", id: signposter.makeSignpostID(), "\(kind.rawValue)")
        if link == nil { start() }
    }

    func end(_ kind: Kind) {
        guard let began = open.removeValue(forKey: kind) else { return }
        if let state = states.removeValue(forKey: kind) {
            signposter.endInterval("Gesture", state, "worst \(Int(self.worst))ms hitches \(self.hitches)")
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
        lastTimestamp = nil; worst = 0; hitches = 0; frames = 0
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
        frames += 1
        if delta > budget * 1.5 { hitches += 1 }
        if delta > worst { worst = delta }
    }
}
