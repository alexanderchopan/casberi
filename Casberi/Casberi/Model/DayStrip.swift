import Foundation

/// TODAY'S SHAPE, under the next thing in the Day room's box (prd §1087, the
/// canvas's Box B, user: "i love Box B on the Day").
///
/// One axis across the day's waking hours, each timed event a block on it,
/// two lanes so an overlap shows as two blocks one over the other, a mark at
/// now, and one sentence under it: what overlaps, then the next free stretch.
/// Pure and Foundation-only, compiled whole by `day-strip-selftest.sh`.
struct DayStrip: Equatable, Sendable {
    struct Event: Equatable, Sendable {
        let id: String
        let title: String
        let start: Date
        /// nil when the event says no end (a Cal.com or Calendly booking):
        /// drawn at `assumedLength`.
        let end: Date?
        var allDay = false
    }

    struct Block: Equatable, Sendable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        /// 0 or 1: the second lane holds what overlaps the first.
        let lane: Int
        /// Whether another timed event shares any of its time.
        let overlaps: Bool
    }

    /// The axis: whole hours, 8 to 8 unless the day's events reach past them.
    let from: Date
    let to: Date
    let blocks: [Block]
    /// Titles of the day's all-day events, which take no time on the axis.
    let allDay: [String]
    /// The first two events still ahead that share time, by start.
    let overlap: (first: String, second: String)?
    /// The next free stretch from now of at least `minFree`; `until` is nil
    /// when nothing else is booked before the axis ends.
    let free: (from: Date, until: Date?)?

    /// An event clipped to today.
    private struct Span {
        let id: String
        let title: String
        let start: Date
        let end: Date
    }

    static let assumedLength: TimeInterval = 30 * 60
    static let minFree: TimeInterval = 30 * 60
    static let defaultFromHour = 8
    static let defaultToHour = 20

    var isEmpty: Bool { blocks.isEmpty && allDay.isEmpty }

    static func == (a: DayStrip, b: DayStrip) -> Bool {
        a.from == b.from && a.to == b.to && a.blocks == b.blocks && a.allDay == b.allDay
            && a.overlap?.first == b.overlap?.first && a.overlap?.second == b.overlap?.second
            && a.free?.from == b.free?.from && a.free?.until == b.free?.until
    }

    /// Where `date` falls on the axis, 0…1.
    func position(_ date: Date) -> Double {
        let span = to.timeIntervalSince(from)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(from) / span))
    }

    /// The day's strip from its events: today's only, timed ones on the axis.
    static func make(_ events: [Event], now: Date, calendar: Calendar) -> DayStrip {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DayStrip(from: now, to: now, blocks: [], allDay: [], overlap: nil, free: nil)
        }
        let today = events.filter { e in
            let end = e.end ?? e.start.addingTimeInterval(assumedLength)
            return e.start < dayEnd && end > dayStart
        }
        let allDay = today.filter { $0.allDay }.map { $0.title }
        var timed: [Span] = []
        for e in today where !e.allDay {
            let stated: Date = e.end ?? e.start.addingTimeInterval(assumedLength)
            let end: Date = min(max(stated, e.start.addingTimeInterval(60)), dayEnd)
            timed.append(Span(id: e.id, title: e.title, start: max(e.start, dayStart), end: end))
        }
        timed.sort { a, b in a.start != b.start ? a.start < b.start : a.id < b.id }

        // The axis: 8 to 8, widened to whole hours around the day's events.
        func hour(_ h: Int) -> Date {
            calendar.date(bySettingHour: h, minute: 0, second: 0, of: dayStart) ?? dayStart
        }
        var from = hour(defaultFromHour)
        var to = hour(defaultToHour)
        if let earliest = timed.map({ $0.start }).min(), earliest < from {
            from = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        }
        if let latest = timed.map({ $0.end }).max(), latest > to {
            let interval = calendar.dateInterval(of: .hour, for: latest)
            let rounded: Date = interval.map { $0.start == latest ? latest : $0.end } ?? latest
            to = min(rounded, dayEnd)
        }

        // Two lanes: a block goes in the first lane free at its start.
        var laneEnds: [Date] = [.distantPast, .distantPast]
        var blocks: [Block] = []
        for span in timed {
            let shares = timed.contains { other in
                other.id != span.id && other.start < span.end && other.end > span.start
            }
            let lane = laneEnds[0] <= span.start ? 0 : 1
            laneEnds[lane] = max(laneEnds[lane], span.end)
            blocks.append(Block(id: span.id, title: span.title, start: span.start, end: span.end,
                                lane: lane, overlaps: shares))
        }

        // The first overlap that still matters: both not yet over.
        var overlap: (String, String)?
        outer: for (i, a) in timed.enumerated() where a.end > now {
            for b in timed[(i + 1)...] where b.start < a.end && b.end > now {
                overlap = (a.title, b.title)
                break outer
            }
        }

        // The next free stretch from now, within the axis.
        var free: (Date, Date?)?
        if now < to {
            var cursor = max(now, from)
            for span in timed where span.end > cursor {
                if span.start.timeIntervalSince(cursor) >= minFree {
                    free = (cursor, span.start)
                    break
                }
                cursor = max(cursor, span.end)
            }
            if free == nil, cursor < to, to.timeIntervalSince(cursor) >= minFree {
                free = (cursor, nil)
            }
        }
        return DayStrip(from: from, to: to, blocks: blocks, allDay: allDay,
                        overlap: overlap.map { (first: $0.0, second: $0.1) },
                        free: free.map { (from: $0.0, until: $0.1) })
    }
}
