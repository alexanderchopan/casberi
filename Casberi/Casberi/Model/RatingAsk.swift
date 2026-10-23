import Foundation

/// **THE RATING ASK (prd §1477, user, 2026-10-23: "the in app star rating i
/// would do").** Apple's own rating sheet, five stars over the app, asked
/// for through `requestReview` — never a sheet of ours, never a "Do you
/// like Casberi?" pre-question. Apple decides whether it appears, shows it
/// at most three times a year per person, never in a TestFlight build, and
/// always (submitting nothing) in a Debug one.
///
/// **When:** a foreground, once the hand is still, for someone using the
/// app on their own things — at least one app connected, not the demo — who
/// has come back on `daysNeeded` different days doing so. Once per app
/// version at most: a version that already asked never asks again.
///
/// Foundation only, so `rating-ask-selftest.sh` compiles the rule alone.
enum RatingAsk {
    /// Different days the app was opened with something of the person's
    /// own connected, before the first ask.
    static let daysNeeded = 4
    /// The days kept, newest last: more than the rule needs, never a log.
    static let dayCap = 14

    static let daysKey = "ratingAsk.days"
    static let askedKey = "ratingAsk.askedVersion"

    /// Today added to the days, once — and only a day of real use: the demo
    /// and a phone with nothing connected record nothing.
    static func recording(_ day: String, to days: [String], connected: Int, demo: Bool) -> [String] {
        guard !demo, connected > 0, !days.contains(day) else { return days }
        return Array((days + [day]).suffix(dayCap))
    }

    /// Whether this foreground may ask.
    static func shouldAsk(days: [String], connected: Int, demo: Bool,
                          askedVersion: String?, version: String) -> Bool {
        guard !demo, connected > 0, !version.isEmpty, askedVersion != version else { return false }
        return Set(days).count >= daysNeeded
    }

    /// A calendar day as the person lives it, "2026-10-23".
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
