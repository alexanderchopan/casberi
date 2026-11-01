import Foundation

/// **THREATS' BOX IS WHETHER THEY ARE GROWING (prd §1633).** The page's box
/// was a count over "trying to fool you" (user: "need to stop talking like
/// 'they tried to fool you'"). What the count could not say is whether more
/// or fewer are arriving, so the box is this month's count against the last
/// month's, over one bar a week for twelve weeks.
///
/// Foundation-only, so `permissions-box-selftest.sh` compiles it as shipped.
struct ThreatTrend: Equatable {
    /// One count a week, oldest first; the last is this week.
    let weeks: [Int]
    /// The first day of each week, matching `weeks`.
    let starts: [Date]
    let thisMonth: Int
    let lastMonth: Int
    let thisWeek: Int

    static let weekCount = 12

    static func read(_ dates: [Date], now: Date, calendar: Calendar = .current,
                     weeks count: Int = weekCount) -> ThreatTrend {
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let starts = (0..<count).reversed().compactMap {
            calendar.date(byAdding: .day, value: -7 * $0, to: thisWeekStart)
        }
        var weeks = Array(repeating: 0, count: starts.count)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        var thisMonth = 0, lastMonth = 0
        for date in dates where date <= now {
            if date >= monthStart { thisMonth += 1 }
            else if date >= lastMonthStart { lastMonth += 1 }
            guard let first = starts.first, date >= first else { continue }
            let index = (starts.lastIndex { $0 <= date }) ?? 0
            weeks[index] += 1
        }
        return ThreatTrend(weeks: weeks, starts: starts, thisMonth: thisMonth,
                           lastMonth: lastMonth, thisWeek: weeks.last ?? 0)
    }

    enum Compare: Equatable {
        /// More than last month.
        case up(from: Int)
        /// Fewer than last month.
        case down(from: Int)
        case same
        /// None last month and some this month.
        case firstSince
        /// None either month.
        case quiet
    }

    var compare: Compare {
        switch (thisMonth, lastMonth) {
        case (0, 0): return .quiet
        case (_, 0): return .firstSince
        case let (a, b) where a > b: return .up(from: b)
        case let (a, b) where a < b: return .down(from: b)
        default: return .same
        }
    }

    /// Under which bars a month's name stands: the first week to start in a
    /// new month, and the first bar only when no month turns within its
    /// next two, so a turn is never hidden behind the month before it.
    func monthLabels(calendar: Calendar = .current) -> [Int: String] {
        let turns = starts.indices.dropFirst().filter {
            calendar.component(.month, from: starts[$0]) != calendar.component(.month, from: starts[$0 - 1])
        }
        var out: [Int: String] = [:]
        for i in ([0] + turns) where !(i == 0 && (turns.first ?? .max) <= 2) {
            out[i] = starts[i].formatted(.dateTime.month(.abbreviated))
        }
        return out
    }
}
