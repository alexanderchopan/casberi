import Foundation

/// The Day room's tiles (prd §1049, built §1056): All, Subscriptions, and
/// New, the verb. Subscriptions (prd §1111) is every mailing list that writes
/// to you, the Wallet's Subscriptions tile in the room where mail lives: one
/// idea in two rooms, which the user ruled needs a place here despite
/// §1049's bundle rule ("no matter what it needs to be a tile", "it is
/// something we are converging on and having user build up"). Foundation-
/// only, its conformance beside every other in `ScopeTileGlyphs.swift`.
enum DayScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, subscriptions, new

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .subscriptions: return String(localized: "Subscriptions")
        case .new: return String(localized: "New")
        }
    }

    var summary: String {
        switch self {
        case .all: return String(localized: "What needs you next")
        case .subscriptions: return String(localized: "The newsletters and lists that write to you")
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
