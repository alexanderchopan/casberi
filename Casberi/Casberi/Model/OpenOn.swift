import Foundation

/// **WHERE THE APP OPENS (user, 2026-11-14: "a setting in settings for which
/// screen to open on by default, wallet or feed").** The Feed unless you say
/// the Wallet; Settings' "Open on" row flips it. Read once, as a window's
/// `FeedFilter` is made, so a pick takes hold on the next open and never
/// moves the screen you are on.
enum OpenOn: String {
    case feed, wallet

    static let key = "launch.opensOn"

    static var current: OpenOn {
        OpenOn(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .feed
    }

    /// The `filter.source` a new window starts on.
    var source: String {
        switch self {
        case .feed:   "All"
        case .wallet: CategoryFold.walletRoom
        }
    }

    var label: String {
        switch self {
        case .feed:   String(localized: "Feed")
        case .wallet: String(localized: "Wallet")
        }
    }

    var flipped: OpenOn { self == .feed ? .wallet : .feed }
}
