import Foundation

/// **WHAT AN APP FOLLOWS BY NAME (prd §1300, user: "every category's + lists
/// its follow-by-name apps from the catalogue").** A Feed section's + is a
/// list of its category's catalogue apps that can follow something you name
/// — a person, a channel, a package — connected or not, so a + never has to
/// be kept in step with the catalogue by hand. An app that needs an account
/// first opens its page (GitHub's key, a mail app's sign-in).
///
/// An app joins by a row here and nothing else: its category comes from the
/// catalogue (`BridgeCatalog.category(of:)`), and what its row opens from
/// `FeedScreen.followByName`. An app that reads only your own account (X,
/// Instagram, TikTok, Twitch's follows) has no row: there is nothing to name.
enum FollowByName {
    /// One app the + lists, and what it follows.
    struct Door: Equatable, Sendable {
        let app: String
        let what: String
    }

    /// What each app follows, by catalogue name.
    static let whats: [String: String] = [
        // Social
        "Bluesky": String(localized: "A person"),
        "Telegram": String(localized: "A public channel"),
        // Work
        "GitHub": String(localized: "A person or a repo"),
        "Hugging Face": String(localized: "An author"),
        "npm": String(localized: "A package"),
        "PostHog": String(localized: "An event"),
        "PyPI": String(localized: "A package"),
        "Radicle": String(localized: "A repo"),
        // Media
        "L2BEAT": String(localized: "A chain"),
        "Pinterest": String(localized: "A board or a person"),
        "Podcasts": String(localized: "A show"),
        "RSS": String(localized: "A site"),
        "Substack": String(localized: "A newsletter"),
        "Walletbeat": String(localized: "A wallet"),
        "YouTube": String(localized: "A channel"),
        // Life
        "Calendar": String(localized: "A calendar by link"),
        "Gmail": String(localized: "A sender"),
        "iCloud Mail": String(localized: "A sender"),
    ]

    /// Where a row lands, the same from the Feed and from Sources: the tray
    /// that app's follow already runs. `.github` and `.mail` need the account
    /// first, and open its page until it is connected; `.page` is an app
    /// whose follow lives on its own page (PostHog, L2BEAT, Walletbeat).
    enum Landing: Equatable {
        case socialFollow, reading, calendar, github, mail, page
        case track(Following.Room)
    }

    static func landing(for app: String) -> Landing {
        switch app {
        case "Bluesky", "Telegram": return .socialFollow
        case "RSS", "Substack":     return .reading
        case "Calendar":            return .calendar
        case "GitHub":              return .github
        case "Gmail", "iCloud Mail": return .mail
        default:
            guard let target = FollowTrackTray.Target(rawValue: app) else { return .page }
            return .track(FollowTrackTray.Target.of(.work).contains(target) ? .work : .media)
        }
    }

    /// The category's apps that follow by name, A–Z: what its + lists.
    static func doors(in category: String) -> [Door] {
        BridgeCatalog.offers
            .compactMap { offer -> Door? in
                guard let what = whats[offer.name], BridgeCatalog.category(of: offer) == category else { return nil }
                return Door(app: offer.name, what: what)
            }
            .sorted { $0.app.localizedStandardCompare($1.app) == .orderedAscending }
    }
}
