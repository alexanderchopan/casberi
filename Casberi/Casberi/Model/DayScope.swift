import Foundation

/// The Day room's tiles (prd §1049, built §1056): All, and New, the verb.
/// Mail and Lists tiles were proposed and dropped: each was a few seats'
/// rows (§1049's bundle rule). Foundation-only, its conformance beside every
/// other in `ScopeTileGlyphs.swift`.
enum DayScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, new

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .new: return String(localized: "New")
        }
    }

    var summary: String {
        switch self {
        case .all: return String(localized: "What needs you next")
        case .new: return String(localized: "Make an event, a reminder or an email")
        }
    }

    var isVerb: Bool { self == .new }
}

/// What New in the Day room can make, each in the app that makes it (the
/// rooms' own New doors: Calendar's `calshow:`, Reminders' scheme, the mail
/// seat's compose).
enum DayMake: String, CaseIterable, Identifiable, Sendable {
    case event, reminder, email

    var id: String { rawValue }

    var label: String {
        switch self {
        case .event:    return String(localized: "Event")
        case .reminder: return String(localized: "Reminder")
        case .email:    return String(localized: "Email")
        }
    }
}
