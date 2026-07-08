import Foundation

/// The catalog — the 15 bridges research proved viable (PRD S9 grades), one
/// list read by the Apps tile (count), the Apps page (Available section),
/// and the catalog screen (grouped). Names are the join key everywhere.
enum BridgeCatalog {

    struct Offer {
        let name: String
        let tagline: String
        let group: String
        /// True = the bridge is wired today (local frameworks). The rest say
        /// "Arrives with bridges" instead of pretending.
        let connectable: Bool
        /// One plain sentence for the App-Store-style detail page — what
        /// connecting is worth, in Bob's words.
        let summary: String
        /// True when connecting needs the person's input first (feed URLs,
        /// a pasted token) — Connect opens the bridge's setup screen instead
        /// of firing a permission ask. Setup bridges skip onboarding's
        /// mini store: that screen is one-tap connects only.
        var needsSetup: Bool = false
    }

    /// Grouped by what they're worth, verb taglines (S25).
    static let offers: [Offer] = [
        Offer(name: "Photos",      tagline: "Screenshots, straight to your feed",            group: "Your photos",    connectable: true,
              summary: "The screenshots you take flow into your feed, searchable by what's in them — no album to dig through."),
        Offer(name: "Calendar",    tagline: "Events join your things",               group: "Your schedule",  connectable: true,
              summary: "Your events land alongside everything else, so your day shows up in your week — and Casberi can add one when you ask."),
        Offer(name: "Reminders",   tagline: "Lists stay in reach",                   group: "Your schedule",  connectable: true,
              summary: "Your reminders join your things and stay findable, and Casberi can add one to your list when you ask."),
        Offer(name: "Zerion",      tagline: "Your onchain life, in your feed",     group: "Your wallet",    connectable: false,
              summary: "Paste the wallet address you want to watch and its swaps, sends, and receives land in your feed like any other thing — read-only, no trading — with your portfolio's moves showing up in your week."),
        Offer(name: "Gmail",       tagline: "Your inbox, findable",                  group: "Your mail",      connectable: true,
              summary: "Your recent mail becomes findable things. Connects over IMAP with a Google app password — your real password is never shared, and it's read-only. Needs 2-Step Verification on your Google account.",
              needsSetup: true),
        Offer(name: "iCloud Mail", tagline: "Your @icloud.com inbox, findable",      group: "Your mail",      connectable: true,
              summary: "Your recent @icloud.com mail becomes findable things. Connects over IMAP with an app-specific password from appleid.apple.com — your real password is never shared, and it's read-only.",
              needsSetup: true),
        Offer(name: "ChatGPT",     tagline: "Import your chats, keep them findable", group: "Your agent",     connectable: true,
              summary: "A one-time import of your chat history, kept searchable alongside your things. (No live read — OpenAI doesn't offer one; this is your export, backfilled.)",
              needsSetup: true),
        Offer(name: "Claude",      tagline: "Connect it to your things",             group: "Your agent",     connectable: false,
              summary: "Claude connects to Casberi — it reads your things when you ask and saves only what you approve. The inverse of a bridge: a client reaching in, not data pulled out."),
        Offer(name: "Dexscreener", tagline: "Watch any token",                      group: "Your wallet",    connectable: true,
              summary: "Watch any token — paste its address or a Dexscreener link and its live price chart lands in your feed, drawn on your iPhone. Public price data only; nothing about you leaves the device. Charts open on Dexscreener.",
              needsSetup: true),
        Offer(name: "Venice",      tagline: "Private AI, nothing retained",          group: "Your agent",     connectable: false,
              summary: "Venice keeps chats on your own device by design, so there's nothing to read in — its private API is a candidate to power Casberi's answers instead."),
        Offer(name: "OpenClaw",    tagline: "Your agents' work lands here",          group: "Your machines",  connectable: false,
              summary: "What your agents make — jobs, runs, outputs — lands in your feed with full provenance, and their approvals reach you here."),
        Offer(name: "GitHub",      tagline: "PRs and issues, in your feed",         group: "Your work",      connectable: true,
              summary: "The issues and pull requests that involve you become findable things. Connects with a read-only token you make in GitHub settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Linear",      tagline: "Your issues stay in reach",             group: "Your work",      connectable: true,
              summary: "The issues assigned to you join your things and surface when they matter. Connects with a personal API key from Linear settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Notion",      tagline: "Pages join your things",                group: "Your work",      connectable: true,
              summary: "The pages you connect become findable things, so what you wrote isn't stranded in one more app. Pages only. Connects with an integration token from notion.so — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "X",           tagline: "Bookmarks become findable",             group: "Your saves",     connectable: false,
              summary: "The posts you bookmarked stop disappearing — they land in your feed, findable later."),
        Offer(name: "Reddit",      tagline: "Saved posts become findable",           group: "Your saves",     connectable: false,
              summary: "Your saved posts join your things and become searchable instead of lost in a list."),
        Offer(name: "YouTube",     tagline: "Your likes and playlists, findable",    group: "Your watching",  connectable: false,
              summary: "The videos you liked and saved to playlists become findable things. (Watch history stays sealed — the API doesn't expose it.)"),
        Offer(name: "Apple Music", tagline: "What you play stays in reach",          group: "Your listening", connectable: false,
              summary: "What you've been playing lands in your feed, so your listening is part of your week too."),
        Offer(name: "Spotify",     tagline: "Liked songs join your things",          group: "Your listening", connectable: false,
              summary: "Your liked songs become things you can find and revisit alongside everything else."),
        Offer(name: "Telegram",    tagline: "Chats join your things",                group: "Your messages",  connectable: false,
              summary: "The messages worth keeping become findable things — the one messenger with a sanctioned way in."),
        Offer(name: "Apple Health", tagline: "Workouts land in your feed",           group: "Your fitness",   connectable: true,
              summary: "Your workouts join your things — a run shows up next to the plan that inspired it. Everything stays on this iPhone: HealthKit never touches a server."),
        Offer(name: "Strava",      tagline: "Every activity, one record",            group: "Your fitness",   connectable: false,
              summary: "Rides and runs land in your feed with distance and time, next to your gym screenshots and plans."),
        Offer(name: "Cal.com",     tagline: "Bookings land in your feed",            group: "Your schedule",  connectable: true,
              summary: "The meetings people book with you join your things as events, next to your calendar. Connects with an API key from Cal.com settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Calendly",    tagline: "Meetings join your things",             group: "Your schedule",  connectable: true,
              summary: "Your scheduled meetings land as events beside everything else. Connects with a personal access token from Calendly's integrations page — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Todoist",     tagline: "Tasks beside your lists",               group: "Your schedule",  connectable: true,
              summary: "Your open tasks join your things alongside Reminders. Connects with the API token from Todoist settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Slack",       tagline: "Messages worth keeping",                group: "Your messages",  connectable: false,
              summary: "The messages you save land as findable things — decisions and links stop drowning in channels."),
        Offer(name: "Raindrop",    tagline: "Bookmarks become findable",             group: "Your saves",     connectable: true,
              summary: "Your Raindrop bookmarks join your things, searchable next to everything else you saved. Connects with a token from Raindrop settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Readwise",    tagline: "Highlights stay with you",              group: "Your reading",   connectable: true,
              summary: "Your highlights land in your feed — what you read joins what you do. Connects with your Readwise access token — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "RSS",         tagline: "Any site with a feed",                  group: "Your reading",   connectable: true,
              summary: "Follow any site that publishes a feed — new posts land in your feed as links, fetched by this iPhone directly. No account, no algorithm in between.",
              needsSetup: true),
        Offer(name: "Farcaster",   tagline: "Your casts, in your feed",              group: "Your network",   connectable: true,
              summary: "An open social protocol — your casts are public, so this connects with just your username. No password, nothing stored but the name.",
              needsSetup: true),
        Offer(name: "Bluesky",     tagline: "Your posts, in your feed",              group: "Your network",   connectable: true,
              summary: "Built on an open protocol — your posts are public, so this connects with just your handle. No password, nothing stored but the name. Likes arrive with sign-in, later.",
              needsSetup: true),
    ]

    /// Group order for the catalog screen (insertion order of first member).
    static var groups: [(String, [Offer])] {
        var order: [String] = []
        var buckets: [String: [Offer]] = [:]
        for offer in offers {
            if buckets[offer.group] == nil { order.append(offer.group) }
            buckets[offer.group, default: []].append(offer)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// Offers not yet among the person's bridges — what the Apps page lists
    /// under Available and the tile counts as "to add". A–Z: the flat list is
    /// an inventory you scan by name (the grouped catalog keeps value order —
    /// its job is selling the worth; this list's job is lookup).
    static func available(besides bridgeNames: [String]) -> [Offer] {
        let taken = Set(bridgeNames)
        return offers.filter { !taken.contains($0.name) }
            .sorted { $0.name < $1.name }
    }
}
