import Foundation

/// What Day's + can make (prd §1343: the section's header carries it, since
/// Day has no New tile and no page, §1344), each in the app that makes it:
/// Calendar's `calshow:`, Reminders' scheme, the mail seat's compose; and
/// Track a subscription, which Day says the day of (prd §1327 item 3): the
/// Wallet's own tray, the verb Track, never Add. And Track a mailing list
/// (prd §1706): Life's tray of who writes you, one tap from home, where
/// Track a subscription already is.
enum DayMake: String, CaseIterable, Identifiable, Sendable {
    case event, reminder, email, subscription, mailingList

    var id: String { rawValue }

    var label: String {
        switch self {
        case .event:        return String(localized: "Event")
        case .reminder:     return String(localized: "Reminder")
        case .email:        return String(localized: "Email")
        case .subscription: return SubscriptionWords.track
        case .mailingList:  return String(localized: "Track a mailing list")
        }
    }
}
