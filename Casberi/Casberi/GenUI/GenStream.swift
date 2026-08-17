import SwiftUI
import Observation

/// The stream driver — the Swift `useLangStream`. Feeds the parser a growing
/// prefix of the document on the prototype's cadence:
///   • 400ms initial delay, then 2–6 characters per tick
///   • 30ms between ticks; 150–400ms pause just after a section boundary
///     (a line starting `root` or containing Widget/Shelf)
/// Generated surfaces stream; records paint (brief §5 load rule).
@Observable
final class GenStream {
    private(set) var els: GenEls = [:]
    private(set) var streaming = false
    /// True once the document has fully rendered — either the typewriter reached
    /// the end or `paint` set it whole. Stays false when a stream is cancelled
    /// mid-flight (a view remount, e.g. under a zoom transition), so a caller can
    /// tell an interrupted entrance from a finished one and reconcile.
    private(set) var completed = false
    /// Characters rendered so far — a caller watches this to tell a stream that
    /// is still advancing from one that has stalled (main-actor contention under
    /// a zoom transition can suspend the tick without cancelling it).
    private(set) var progress = 0

    private var doc = ""
    private var boundaries: Set<Int> = []
    /// Each line's character range in `doc`, text only (the joining newline is
    /// excluded) — the reveal budget below needs to know where a line starts.
    private var lineSpans: [(start: Int, end: Int)] = []
    private var cursor = 0
    private var task: Task<Void, Never>?
    /// `GenParser.parseIncremental`'s carry-forward cache — valid only for
    /// the CURRENT `doc`; reset alongside it in `stream(_:)`/`paint(_:)`.
    private var parseCache: GenEls = [:]
    private var parseCacheCompleteLines = 0

    /// How many characters of ONE line are revealed a tick at a time before the
    /// cursor snaps to the end of it — see the long note in `stream(_:)`.
    private static let lineRevealBudget = 200

    /// Starts (or restarts) streaming a document.
    func stream(_ lines: [String]) {
        task?.cancel()
        doc = lines.joined(separator: "\n")
        els = [:]
        cursor = 0
        progress = 0
        streaming = true
        completed = false
        parseCache = [:]
        parseCacheCompleteLines = 0

        // Section boundaries: offset after each `root`/Widget/Shelf line.
        boundaries = []
        lineSpans = []
        var offset = 0
        for line in lines {
            lineSpans.append((offset, offset + line.count))
            offset += line.count + 1
            if line.hasPrefix("root") || line.contains("Widget") || line.contains("Shelf") {
                boundaries.insert(offset)
            }
        }

        let total = doc.count
        // The tick SCALES with the document (2026-07-22). The 2–6 chars/tick
        // cadence was tuned for a short prose answer; a richly composed
        // document (the Today brief: ~1,400 characters, and a single
        // `MoneyHero` line is ~400 of them) took over ten seconds to finish
        // painting — and most of that was spent on characters that produce NO
        // visible change, because a component mounts on its line's first
        // token and its value CSV/treemap cells render nothing incrementally.
        // Pacing by length keeps the assembling-before-your-eyes feel while
        // bounding how long it takes: a short answer's step stays exactly 2–6
        // (`total/90` floors at 2 under ~270 chars, so nothing about today's
        // prose changes), and a long one steps wider instead of slower.
        let step = max(2, min(18, total / 90))
        task = Task { @MainActor [weak self] in
            // Was 400ms — read as a beat too long before anything appears
            // (report 2026-07-09). 150ms still separates the entrance from
            // the tab switch/launch that triggered it, just tighter.
            try? await Task.sleep(for: .milliseconds(150))
            var lineIdx = 0
            while let self, !Task.isCancelled, self.cursor < total {
                let previous = self.cursor
                self.cursor = min(self.cursor + Int.random(in: step...(step + 4)), total)
                // A LINE REVEALS AT MOST `lineRevealBudget` CHARACTERS one tick
                // at a time; past that the cursor snaps to the end of it (PERF
                // 2026-08-16).
                //
                // The length scaling above bounds the STEP at 18, so a long
                // document is still paced at total/18 ticks × 30ms — and the
                // documents got long: one `ClusterMap` line carries a
                // coordinate triple per dot for up to 300 dots, i.e. thousands
                // of characters, and a `MoneyHero` is ~400. At 18/tick that one
                // map line alone is several hundred ticks and the better part
                // of ten seconds, every one of them re-running
                // `parseIncremental` and republishing on the main actor.
                //
                // And it buys nothing, for the reason the step-scaling note
                // above already gives: a component mounts on its line's first
                // token, and its value CSV / treemap cells / dot list render
                // NOTHING incrementally. Those characters are pure cost.
                //
                // Budgeting per line rather than naming the atomic components
                // is deliberate: a registry of component names would need an
                // entry per new component and would silently pace the next one
                // wrongly, where a budget derives the answer from the shape of
                // the line itself. 200 sits well above any prose line the
                // brief composes (`ins = Insight("…")` with the longest lede is
                // ~130) and well below every data line, so what a person
                // watches type out is untouched.
                while lineIdx + 1 < self.lineSpans.count,
                      self.cursor > self.lineSpans[lineIdx].end {
                    lineIdx += 1
                }
                if lineIdx < self.lineSpans.count {
                    let span = self.lineSpans[lineIdx]
                    if self.cursor > span.start + Self.lineRevealBudget {
                        self.cursor = min(max(self.cursor, span.end), total)
                    }
                }
                self.publish()
                if self.cursor >= total { break }
                // The section pause fires on CROSSING a boundary rather than on
                // sitting within 8 characters of one. Two reasons, both from
                // the snap above: a tick that jumps a whole data line can clear
                // that 8-character window entirely and lose the pause, and the
                // old proximity test could fire on several consecutive ticks
                // for ONE boundary (at 2 chars/tick, up to four 150–400ms
                // pauses where the design wants one).
                let delay = self.boundaries.contains { $0 > previous && $0 <= self.cursor }
                    ? Double.random(in: 150...400) : 30
                try? await Task.sleep(for: .milliseconds(Int(delay)))
            }
            if let self {
                self.streaming = false
                // Reached the end on our own (not cancelled by a restart/remount).
                if !Task.isCancelled { self.completed = true }
            }
        }
    }

    /// Paints the full document at once — the cached last-good path for
    /// offline paint (brief §3 Composition), and previews.
    func paint(_ lines: [String]) {
        task?.cancel()
        doc = lines.joined(separator: "\n")
        cursor = doc.count
        streaming = false
        completed = true
        parseCache = [:]
        parseCacheCompleteLines = 0
        publish()
    }

    private func publish() {
        let prefix = doc.prefix(cursor)
        progress = cursor
        els = GenParser.parseIncremental(prefix: prefix, isComplete: cursor >= doc.count,
                                         cache: &parseCache, cachedCompleteLines: &parseCacheCompleteLines)
    }

    deinit { task?.cancel() }
}
