import Foundation

/// **WHICH ACCOUNTS AND WHICH KEY ARE THIS PHONE'S** (user: "it's hard to tell
/// which account was created by me on my device vs one i follow / watch", and
/// "can't tell which key is for my account").
///
/// The app keeps no record of which accounts it created, and that is not the
/// fact that matters anyway: what this phone can DO is set by whether its key
/// is an actor on the account. So "On this phone" means exactly that — the
/// same test `FeedScreen.signableVibenetAccounts` gates Send and Authorize on —
/// and every other watched account is "Watching".
///
/// `ours` is read once per body pass by the caller and handed in, so a list of
/// rows hashes the key once rather than once a row.
enum VibenetThisPhone {
    /// This phone's actorId, lowercased; nil when the phone has no key.
    static func actorID() -> String? { VibenetDeviceKey.actorID()?.lowercased() }

    static func isKey(_ actorId: String, ours: String?) -> Bool {
        guard let ours else { return false }
        return actorId.lowercased() == ours
    }

    static func actsFor(_ item: VibenetAccountItem, ours: String?) -> Bool {
        item.actors.contains { isKey($0.actorId, ours: ours) }
    }

    /// The group words, one spelling for the list, the picker and the deck.
    static var onPhoneGroup: String { String(localized: "On this phone") }
    static var watchingGroup: String { String(localized: "Watching") }
    /// A key row's name when the key is this phone's.
    static var keyName: String { String(localized: "This phone") }
}
