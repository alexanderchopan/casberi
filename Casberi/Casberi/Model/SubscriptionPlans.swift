import Foundation

/// What Track a subscription can offer before any card has spoken (prd §1164).
///
/// A subscription is anything you hold a plan with, FREE ONES INCLUDED (user:
/// "some people have 0 dollar subscriptions that still should be tracked"),
/// so nothing here asks whether you pay. Two lists, both hand-kept:
///   • `apps` — catalogue apps sold as a plan (a free tier counts). Their
///     account page offers Track, and a first connect raises the tray once.
///   • `popular` — services no catalogue app reads (Netflix, iCloud+), the
///     tray's opening list with no card connected. Each carries its own
///     domain for the billing door; no price, because a price varies by plan
///     and country and a wrong one accepted unread is a fake fact (prd §83).
/// Foundation-only, so `subscriptions-selftest.sh` compiles it as shipped.
enum SubscriptionPlans {
    struct Service: Equatable {
        var name: String
        var site: String
    }

    /// Catalogue apps you can hold a plan with. Names are `BridgeCatalog`
    /// offer names exactly; `subscriptions-selftest.sh` fails on one the
    /// catalogue does not hold.
    static let apps: Set<String> = [
        "Acorns", "Apple Music", "Calendly", "Cal.com", "CardPointers", "ChatGPT", "Claude",
        "Cloudflare", "Coinbase", "Day One", "Dropbox", "Duolingo", "Garmin", "Gemini", "GitHub",
        "GitLab", "Grok", "Hugging Face", "Jira", "Kindle", "Linear", "Notion", "Obsidian",
        "PagerDuty", "PostHog", "Raindrop", "Readwise", "Rocket Money", "Sentry", "Slack",
        "Snapchat", "Spotify", "Strava", "Substack", "Telegram", "Todoist", "Trello", "Twitch",
        "Venice", "Vercel", "X", "YouTube",
    ]

    /// The tray's opening list, A–Z (prd §995): the services most people hold
    /// a plan with, catalogue apps among them so the list reads whole.
    static let popular: [Service] = [
        .init(name: "1Password", site: "1password.com"),
        .init(name: "Adobe Creative Cloud", site: "adobe.com"),
        .init(name: "Amazon Prime", site: "amazon.com"),
        .init(name: "Apple Music", site: "music.apple.com"),
        .init(name: "Apple One", site: "apple.com"),
        .init(name: "Apple TV+", site: "tv.apple.com"),
        .init(name: "Audible", site: "audible.com"),
        .init(name: "ChatGPT", site: "chatgpt.com"),
        .init(name: "Claude", site: "claude.ai"),
        .init(name: "Disney+", site: "disneyplus.com"),
        .init(name: "Dropbox", site: "dropbox.com"),
        .init(name: "Duolingo", site: "duolingo.com"),
        .init(name: "Google One", site: "one.google.com"),
        .init(name: "Hulu", site: "hulu.com"),
        .init(name: "iCloud+", site: "icloud.com"),
        .init(name: "Max", site: "max.com"),
        .init(name: "Microsoft 365", site: "microsoft.com"),
        .init(name: "Netflix", site: "netflix.com"),
        .init(name: "Nintendo Switch Online", site: "nintendo.com"),
        .init(name: "Notion", site: "notion.so"),
        .init(name: "Paramount+", site: "paramountplus.com"),
        .init(name: "Peacock", site: "peacocktv.com"),
        .init(name: "PlayStation Plus", site: "playstation.com"),
        .init(name: "Spotify", site: "spotify.com"),
        .init(name: "Strava", site: "strava.com"),
        .init(name: "The New York Times", site: "nytimes.com"),
        .init(name: "Xbox Game Pass", site: "xbox.com"),
        .init(name: "YouTube Premium", site: "youtube.com"),
    ]

    /// Whether an app is one you can hold a plan with.
    static func sells(_ app: String) -> Bool { apps.contains(app) }

    /// Popular services whose name, or a word in it, starts with what was
    /// typed — the catalogue lookup's rule (`SubscriptionAddTray.apps`).
    static func popular(matching query: String) -> [Service] {
        let q = query.lowercased()
        guard !q.isEmpty else { return popular }
        return popular.filter { s in
            let name = s.name.lowercased()
            return name.hasPrefix(q) || name.split(separator: " ").contains { $0.hasPrefix(q) }
        }
    }

    /// Whether a tracked name already stands for `name`: the same key
    /// (`Subscriptions.key`), so "Spotify" and "spotify " are one plan.
    static func isTracked(_ name: String, among tracked: [String]) -> Bool {
        let k = Subscriptions.key(name)
        return !k.isEmpty && tracked.contains { Subscriptions.key($0) == k }
    }

    // MARK: - The ask after a connect

    private static let askedKey = "subscriptions.askedOnConnect.v1"

    /// A first connect raises the tray once per app, ever: a second connect
    /// of the same app, or a reconnect after a Disconnect, asks nothing.
    static func shouldAsk(_ app: String, tracked: [String],
                          defaults: UserDefaults = .standard) -> Bool {
        guard sells(app), !isTracked(app, among: tracked) else { return false }
        return !(defaults.stringArray(forKey: askedKey) ?? []).contains(app)
    }

    static func markAsked(_ app: String, defaults: UserDefaults = .standard) {
        var asked = defaults.stringArray(forKey: askedKey) ?? []
        guard !asked.contains(app) else { return }
        asked.append(app)
        defaults.set(asked, forKey: askedKey)
    }
}
