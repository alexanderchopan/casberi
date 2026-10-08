import Foundation

/// THE SITE BEHIND EACH APP, for an account page's Website tile (prd §1197).
///
/// `SubscriptionAddTray.siteByOffer` derives a domain from the hosts an app's
/// bridge reaches, and only when the host's label is the app's own name — so
/// Bluesky (read through `public.api.bsky.app`) had none, and its page drew no
/// Website tile. This table names the homepage outright.
///
/// **A DOOR, NEVER A REACH.** The tile opens the page in the in-app Safari
/// sheet (prd §653) or the Mac's browser: the browser makes that request,
/// never this app, which is `network-reach-audit.sh`'s own reasoning for its
/// setup doors. Nothing here is fetched; a host the app reads belongs in
/// `NetworkReach`, never here.
///
/// The apps that live on this device (Photos, Calendar, Health, Notes…) and
/// the ones with no public site of their own have no entry, and so no tile.
enum AppHomepages {
    static let domain: [String: String] = [
        "0xBow Privacy Pools": "privacypools.com",
        "Railgun": "railgun.org",
        "ENS": "ens.domains",
        "CardPointers": "cardpointers.com",
        "Gnosis Pay": "gnosispay.com",
        "MetaMask Card": "metamask.io",
        "Acorns": "acorns.com",
        "Rocket Money": "rocketmoney.com",
        "Privy": "privy.io",
        "Wise": "wise.com",
        "Splits": "splits.org",
        "Coinbase": "coinbase.com",
        "Kraken": "kraken.com",
        "Binance": "binance.com",
        "Gemini Exchange": "gemini.com",
        "Gmail": "mail.google.com",
        "iCloud Mail": "icloud.com",
        "ChatGPT": "chatgpt.com",
        "Claude": "claude.ai",
        "Claude Code": "claude.com",
        "Gemini": "gemini.google.com",
        "Safe": "safe.global",
        "ether.fi": "ether.fi",
        "L2BEAT": "l2beat.com",
        "Bitrefill": "bitrefill.com",
        "Privacy": "privacy.com",
        "Venice": "venice.ai",
        "Bankr": "bankr.bot",
        "OpenRouter": "openrouter.ai",
        "Grok": "grok.com",
        "NEAR AI": "near.ai",
        "GitHub": "github.com",
        "GitLab": "gitlab.com",
        "Hugging Face": "huggingface.co",
        "Radicle": "radicle.xyz",
        "Logos": "logos.co",
        "Linear": "linear.app",
        "Notion": "notion.so",
        "PostHog": "posthog.com",
        "Slack": "slack.com",
        "Trello": "trello.com",
        "Jira": "atlassian.com",
        "Cloudflare": "cloudflare.com",
        "Sentry": "sentry.io",
        "Vercel": "vercel.com",
        "PagerDuty": "pagerduty.com",
        "npm": "npmjs.com",
        "PyPI": "pypi.org",
        "App Store Connect": "appstoreconnect.apple.com",
        "AWS": "aws.amazon.com",
        "Stripe": "stripe.com",
        "Polar": "polar.sh",
        "Dodo Payments": "dodopayments.com",
        "YouTube": "youtube.com",
        "Spotify": "spotify.com",
        "Strava": "strava.com",
        "Garmin": "garmin.com",
        "Duolingo": "duolingo.com",
        "Cal.com": "cal.com",
        "Calendly": "calendly.com",
        "Todoist": "todoist.com",
        "Pinterest": "pinterest.com",
        "Raindrop": "raindrop.io",
        "Readwise": "readwise.io",
        "Day One": "dayoneapp.com",
        "Telegram": "telegram.org",
        "Bluesky": "bsky.app",
        "Instagram": "instagram.com",
        "Threads": "threads.com",
        "Snapchat": "snapchat.com",
        "TikTok": "tiktok.com",
        "X": "x.com",
        "Steam": "store.steampowered.com",
        "Obsidian": "obsidian.md",
        "Dropbox": "dropbox.com",
        "Twitch": "twitch.tv",
        "Substack": "substack.com",
        "Kindle": "read.amazon.com",
        "NerdWallet": "nerdwallet.com",
    ]

    /// The page to open, this table first, then the catalogue's derived
    /// domain (`siteByOffer`).
    static func url(for offer: String, derived: String?) -> URL? {
        guard let host = domain[offer] ?? derived else { return nil }
        return URL(string: "https://\(host)")
    }
}
