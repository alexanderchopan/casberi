import Foundation

/// "On this day" — a real thing from the same month and day in a PRIOR year,
/// surfaced beside a habit source's own calendar heatmap (delight pass
/// 2026-07-21). Rides the SAME `visible` things the heatmap already draws
/// from, so it never costs a query of its own; a real match only, never
/// invented — no match, no card.
enum OnThisDay {
    struct Echo {
        let thing: Thing
        /// Whole years back — always ≥ 1 (this year's own match doesn't
        /// count as an anniversary).
        let years: Int

        var label: String {
            years == 1
                ? String(localized: "On this day, last year")
                : String(localized: "On this day, \(years) years ago")
        }
    }

    /// The closest anniversary match — a year ago beats two years ago. Ties
    /// (more than one thing shares the closest matching year) keep the
    /// FIRST encountered, which for `visible` (already newest-first from the
    /// feed's own query) is the most recently captured of that day.
    static func find(in things: [Thing], now: Date = .now, calendar: Calendar = .current) -> Echo? {
        let today = calendar.dateComponents([.month, .day], from: now)
        let thisYear = calendar.component(.year, from: now)
        var best: (thing: Thing, years: Int)?
        for thing in things {
            let parts = calendar.dateComponents([.month, .day, .year], from: thing.capturedAt)
            guard parts.month == today.month, parts.day == today.day,
                  let year = parts.year else { continue }
            let years = thisYear - year
            guard years >= 1 else { continue }
            if best == nil || years < best!.years {
                best = (thing, years)
            }
        }
        return best.map { Echo(thing: $0.thing, years: $0.years) }
    }
}
