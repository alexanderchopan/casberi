import Foundation

/// **WHERE THE APP OPENS (user, 2026-11-14: "a setting in settings for which
/// screen to open on by default, wallet or feed").** Home unless you say
/// Activity (prd §1807: the app is one wallet, and Home leads); Settings' "Open on" row flips it. Read once, as a window's
/// `FeedFilter` is made, so a pick takes hold on the next open and never
/// moves the screen you are on.
enum OpenOn: String {
    case feed, wallet

    static let key = "launch.opensOn"

    static var current: OpenOn {
        // The Mac carries no wallet (prd §1893): it opens on Activity.
        guard WalletHere.isOn else { return .feed }
        return OpenOn(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .wallet
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
        case .feed:   String(localized: "Activity")
        case .wallet: String(localized: "Home")
        }
    }

    var flipped: OpenOn { self == .feed ? .wallet : .feed }
}
