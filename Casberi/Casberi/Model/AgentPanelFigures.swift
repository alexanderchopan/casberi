import Foundation

/// The CROSS-SOURCE figures (prd §337) — the ones no room can draw.
///
/// Every registry figure in `FeedInsight` is pure over ONE room's things by
/// contract, which is exactly why the All feed has never had a hero: a chart
/// of everything at once, composed that way, is a chart of nothing. What is
/// left is composed the other way round — it takes the WHOLE corpus and finds
/// the axis all rooms genuinely share (the theme river went in §836; the
/// semantic map, `scatter`, went with the Today brief that drew it,
/// 2026-10-01):
///
///   • `dial` — the clock. Every thing has an hour; nothing in the app has
///              ever asked which one.
///
/// Foundation-only over flat inputs, like `AgentPanel` itself, so
/// `scripts/agent-panel-selftest.sh` compiles them whole with no stubs.
enum AgentPanelFigures {

    // MARK: - Input

    /// One thing, flattened to what these figures read. `Sendable`: every
    /// field is a value type.
    struct Entry: Equatable, Sendable {
        var source: String
        var at: Date
        /// The terms already stamped on the thing (`ocrTopics` + tags).
        var terms: [String] = []
    }

    // MARK: - 1 · The day dial

    /// A week of things placed on a 24-hour clock.
    ///
    /// Hour is taken in the CURRENT calendar, not UTC: the question is "when
    /// is your day", and a day is a local thing. Recency is normalised across
    /// the window rather than against a fixed span, so a quiet week still uses
    /// the whole radius instead of huddling at the rim.
    static func dial(_ entries: [Entry], now: Date = .now,
                     days: Int = 7, cap: Int = 400) -> [AgentPanel.DialMark] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: now) else { return [] }
        let window = entries.filter { $0.at >= start && $0.at <= now }
        guard !window.isEmpty else { return [] }
        // Newest first, then capped — a busy corpus draws its most recent
        // `cap` marks rather than a random sample, so the rim is always true.
        return window
            .sorted { $0.at > $1.at }
            .prefix(cap)
            .map { entry in
                let comps = cal.dateComponents([.hour, .minute], from: entry.at)
                let hour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
                // Recency buckets by whole DAY, not by elapsed seconds over
                // the window (§339). Normalising against the span pinned
                // nearly every mark to the rim on any corpus whose week is
                // front-loaded — which is most of them — and the dial drew as
                // a ring with a dead centre, reading as a loading spinner
                // rather than a clock. Seven discrete rings distribute by
                // CONSTRUCTION, and they say something the old radius could
                // not: this hour, and which day.
                let daysAgo = cal.dateComponents([.day],
                                                 from: cal.startOfDay(for: entry.at),
                                                 to: cal.startOfDay(for: now)).day ?? 0
                let ring = 1 - (Double(min(max(daysAgo, 0), days - 1)) / Double(max(1, days - 1)))
                return AgentPanel.DialMark(hour: hour, recency: ring, source: entry.source)
            }
    }

    /// The busiest four-hour stretch, as words — "busiest 9a–1p".
    ///
    /// A dial at tile scale can carry no legend, and its shape is the whole
    /// reading; this is the one line that says what the shape MEANS. A reading,
    /// not a tally (§213): it names a window, never a count.
    static func busiestWindow(_ marks: [AgentPanel.DialMark], width: Int = 4) -> String? {
        guard marks.count >= 8 else { return nil }
        var perHour = Array(repeating: 0, count: 24)
        for mark in marks { perHour[min(23, max(0, Int(mark.hour)))] += 1 }
        var bestStart = 0, bestCount = -1
        for start in 0..<24 {
            var total = 0
            for offset in 0..<width { total += perHour[(start + offset) % 24] }
            // Ties go to the EARLIER window so the label is stable across
            // opens on a corpus with two equally busy stretches.
            if total > bestCount { bestCount = total; bestStart = start }
        }
        guard bestCount > 0 else { return nil }
        return String(localized: "busiest \(clock(bestStart))–\(clock((bestStart + width) % 24))")
    }

    private static func clock(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "a" : "p")"
    }
}
