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
    private var cursor = 0
    private var task: Task<Void, Never>?

    /// Starts (or restarts) streaming a document.
    func stream(_ lines: [String]) {
        task?.cancel()
        doc = lines.joined(separator: "\n")
        els = [:]
        cursor = 0
        progress = 0
        streaming = true
        completed = false

        // Section boundaries: offset after each `root`/Widget/Shelf line.
        boundaries = []
        var offset = 0
        for line in lines {
            offset += line.count + 1
            if line.hasPrefix("root") || line.contains("Widget") || line.contains("Shelf") {
                boundaries.insert(offset)
            }
        }

        let total = doc.count
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            while let self, !Task.isCancelled, self.cursor < total {
                self.cursor = min(self.cursor + Int.random(in: 2...6), total)
                self.publish()
                if self.cursor >= total { break }
                let nearBoundary = self.boundaries.contains {
                    self.cursor >= $0 && self.cursor - $0 < 8
                }
                let delay = nearBoundary ? Double.random(in: 150...400) : 30
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
        publish()
    }

    private func publish() {
        let prefix = doc.prefix(cursor)
        progress = cursor
        els = GenParser.parse(prefix: prefix, isComplete: cursor >= doc.count)
    }

    deinit { task?.cancel() }
}
