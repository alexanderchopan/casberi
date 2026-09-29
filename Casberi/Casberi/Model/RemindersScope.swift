import Foundation

/// The Reminders room's tiles (prd §993): All · Today · Scheduled · New —
/// Apple's own smart lists, so the room reads the way the list it mirrors
/// does. New is a VERB, like the Notes room's: it never lights, and its tap
/// opens the Reminders app, because a reminder is made there and never
/// written inside Casberi (ruling 2026-07-25, SourceActions' 2026-07-13 rule).
///
/// There is no Done tile. The ingest lands OPEN reminders and only marks one
/// done when it had already landed it, so a Done list would be the fraction
/// this app happened to see finish — a list claiming to be Apple's Completed
/// that is not (§83).
///
/// Foundation-only, like `NotesScope`, so a harness can compile it whole.
enum RemindersScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, today, scheduled, new

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return String(localized: "All")
        case .today:     return String(localized: "Today")
        case .scheduled: return String(localized: "Scheduled")
        case .new:       return String(localized: "New")
        }
    }

    /// Read by VoiceOver and the tooltip.
    var summary: String {
        switch self {
        case .all:       return String(localized: "Your open reminders")
        case .today:     return String(localized: "Due today or overdue")
        case .scheduled: return String(localized: "Reminders with a date")
        case .new:       return String(localized: "Make a reminder in Reminders")
        }
    }

    /// What the held lead says when this scope holds nothing. One clause
    /// (prd §799).
    var emptyHeadline: String {
        switch self {
        case .all, .new: return String(localized: "Nothing to do.")
        case .today:     return String(localized: "Nothing due today.")
        case .scheduled: return String(localized: "Nothing scheduled.")
        }
    }

    /// The tiles that SCOPE the list; New is a verb and never stands.
    var isVerb: Bool { self == .new }

    /// Whether a reminder stands under this scope. Today is Apple's Today:
    /// due before tomorrow, overdue included. A done reminder stands under
    /// All only (as the room's "Done" group), never under a date scope.
    func allows(done: Bool, dueAt: Date?, now: Date = .now,
                calendar: Calendar = .current) -> Bool {
        switch self {
        case .all, .new:
            return true
        case .today:
            guard !done, let dueAt,
                  let tomorrow = calendar.date(byAdding: .day, value: 1,
                                               to: calendar.startOfDay(for: now)) else { return false }
            return dueAt < tomorrow
        case .scheduled:
            return !done && dueAt != nil
        }
    }
}
