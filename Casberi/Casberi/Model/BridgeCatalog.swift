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
        Offer(name: "Photos",      tagline: "Screenshots, straight to your feed",            group: "Photos",    connectable: true,
              summary: "The screenshots you take flow into your feed, searchable by what's in them — no album to dig through."),
        Offer(name: "Calendar",    tagline: "Events join your things",               group: "Schedule",  connectable: true,
              summary: "Your events land alongside everything else, so your day shows up in your week — and Casberi can add one when you ask."),
        Offer(name: "Reminders",   tagline: "Lists stay in reach",                   group: "Schedule",  connectable: true,
              summary: "Your reminders join your things and stay findable, and Casberi can add one to your list when you ask."),
        Offer(name: "Wallet",      tagline: "Track any wallet's activity",          group: "Wallet",    connectable: true,
              summary: "Paste a wallet address and its onchain activity — received, sent, tokens in and out, across chains — lands in your feed like anything else. Read-only, public data, no server. Watching an address can never trade or move funds.",
              needsSetup: true),
        Offer(name: "Gmail",       tagline: "Your inbox, findable",                  group: "Mail",      connectable: true,
              summary: "Your recent mail becomes findable things. Connects over IMAP with a Google app password — your real password is never shared, and it's read-only. Needs 2-Step Verification on your Google account.",
              needsSetup: true),
        Offer(name: "iCloud Mail", tagline: "Your @icloud.com inbox, findable",      group: "Mail",      connectable: true,
              summary: "Your recent @icloud.com mail becomes findable things. Connects over IMAP with an app-specific password from appleid.apple.com — your real password is never shared, and it's read-only.",
              needsSetup: true),
        Offer(name: "ChatGPT",     tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              summary: "A one-time import of your chat history, kept searchable alongside your things. (No live read — OpenAI doesn't offer one; this is your export, backfilled.)",
              needsSetup: true),
        Offer(name: "Claude",      tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              summary: "A one-time import of your Claude chat history, kept searchable alongside your things. (No live read — Anthropic doesn't offer one; this is your export, backfilled.)",
              needsSetup: true),
        Offer(name: "Dexscreener", tagline: "Track any token",                       group: "Wallet",    connectable: true,
              summary: "Watch any token — paste its address or a Dexscreener link and its live price chart lands in your feed, drawn on your iPhone. Public price data only; nothing about you leaves the device. Charts open on Dexscreener.",
              needsSetup: true),
        Offer(name: "Kalshi",      tagline: "Watch real-event odds",                 group: "Markets",   connectable: true,
              summary: "Watch any market on Kalshi, the CFTC-regulated event exchange — search a team or event and its live odds land in your feed. Public price data only, read-only: nothing here places a trade.",
              needsSetup: true),
        Offer(name: "Venice",      tagline: "Private AI, nothing retained",          group: "Agent",     connectable: false,
              summary: "Venice keeps chats on your own device by design, so there's nothing to read in — its private API is a candidate to power Casberi's answers instead."),
        Offer(name: "OpenClaw",    tagline: "Your agents' work lands here",          group: "Machines",  connectable: false,
              summary: "What your agents make — jobs, runs, outputs — lands in your feed with full provenance, and their approvals reach you here."),
        Offer(name: "GitHub",      tagline: "PRs and issues, in your feed",         group: "Work",      connectable: true,
              summary: "The issues and pull requests that involve you become findable things. Connects with a read-only token you make in GitHub settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Linear",      tagline: "Your issues stay in reach",             group: "Work",      connectable: true,
              summary: "The issues assigned to you join your things and surface when they matter. Connects with a personal API key from Linear settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Notion",      tagline: "Pages join your things",                group: "Work",      connectable: true,
              summary: "The pages you connect become findable things, so what you wrote isn't stranded in one more app. Pages only. Connects with an integration token from notion.so — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Reddit",      tagline: "Follow subreddits and people",          group: "Saves",     connectable: true,
              summary: "Follow any subreddit or person on Reddit — their new posts land in your feed as links, through Reddit's own public feed. No account, no sign-in. Read-only.",
              needsSetup: true),
        Offer(name: "YouTube",     tagline: "Follow any channel",                    group: "Watching",  connectable: true,
              summary: "Follow any YouTube channel — its new uploads land in your feed as links, through YouTube's own public feed. Paste the channel's @handle or URL. No account. Read-only.",
              needsSetup: true),
        Offer(name: "Apple Music", tagline: "What you play stays in reach",          group: "Listening", connectable: true,
              summary: "What you've recently played lands in your feed, opening back in Apple Music. Uses Apple's own MusicKit with your permission — read-only, nothing added to your library. Everything stays on this iPhone."),
        Offer(name: "Spotify",     tagline: "Liked songs join your things",          group: "Listening", connectable: false,
              summary: "Your liked songs become things you can find and revisit alongside everything else."),
        Offer(name: "Telegram",    tagline: "Chats join your things",                group: "Messages",  connectable: false,
              summary: "The messages worth keeping become findable things — the one messenger with a sanctioned way in."),
        Offer(name: "Apple Health", tagline: "Workouts land in your feed",           group: "Fitness",   connectable: true,
              summary: "Your workouts join your things — a run shows up next to the plan that inspired it. Everything stays on this iPhone: HealthKit never touches a server."),
        Offer(name: "Strava",      tagline: "Every activity, one record",            group: "Fitness",   connectable: false,
              summary: "Rides and runs land in your feed with distance and time, next to your gym screenshots and plans."),
        Offer(name: "Cal.com",     tagline: "Bookings land in your feed",            group: "Schedule",  connectable: true,
              summary: "The meetings people book with you join your things as events, next to your calendar. Connects with an API key from Cal.com settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Calendly",    tagline: "Meetings join your things",             group: "Schedule",  connectable: true,
              summary: "Your scheduled meetings land as events beside everything else. Connects with a personal access token from Calendly's integrations page — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Todoist",     tagline: "Tasks beside your lists",               group: "Schedule",  connectable: true,
              summary: "Your open tasks join your things alongside Reminders. Connects with the API token from Todoist settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Slack",       tagline: "Messages worth keeping",                group: "Work",      connectable: false,
              summary: "The messages you save land as findable things — decisions and links stop drowning in channels."),
        Offer(name: "Pinterest",   tagline: "Your pins, in your feed",               group: "Saves",     connectable: true,
              summary: "Your recent public pins land in your feed as links — what you saved on Pinterest joins everything else. Connects with just your username through Pinterest's own public feed: no password, nothing stored but the name. Public boards only.",
              needsSetup: true),
        Offer(name: "Raindrop",    tagline: "Bookmarks become findable",             group: "Saves",     connectable: true,
              summary: "Your Raindrop bookmarks join your things, searchable next to everything else you saved. Connects with a token from Raindrop settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Readwise",    tagline: "Highlights stay with you",              group: "Reading",   connectable: true,
              summary: "Your highlights land in your feed — what you read joins what you do. Connects with your Readwise access token — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Apple Journal", tagline: "Your entries, findable",              group: "Notes",     connectable: true,
              summary: "A one-time import of Journal's own export — entries become findable notes, dated as you wrote them. In Journal: your profile picture → Export Journal, unzip in Files, pick the folder here. Apple offers no live read.",
              needsSetup: true),
        Offer(name: "Day One",     tagline: "Import your journal",                   group: "Notes",     connectable: true,
              summary: "A one-time import of your Day One export — every entry becomes a findable note, dated as you wrote it, tags kept. Export JSON in Day One, unzip in Files, pick the file here. Re-imports add only what's new.",
              needsSetup: true),
        Offer(name: "Apple Notes", tagline: "Share notes in",                        group: "Notes",     connectable: true,
              summary: "Share any note straight into Casberi — open it in Notes, tap share, choose Casberi. Apple offers no export or live read for Notes, so they arrive one at a time, as you share them.",
              needsSetup: true),
        Offer(name: "RSS",         tagline: "Any site with a feed",                  group: "Reading",   connectable: true,
              summary: "Follow any site that publishes a feed — new posts land in your feed as links, fetched by this iPhone directly. No account, no algorithm in between.",
              needsSetup: true),
        Offer(name: "Farcaster",   tagline: "Track any Farcaster account",           group: "Network",   connectable: true,
              summary: "An open social protocol — casts are public, so this connects with just a username: your own or anyone's. No password, nothing stored but the name.",
              needsSetup: true),
        Offer(name: "Bluesky",     tagline: "Your posts, in your feed",              group: "Network",   connectable: true,
              summary: "Built on an open protocol — your posts are public, so this connects with just your handle. No password, nothing stored but the name. Likes arrive with sign-in, later.",
              needsSetup: true),
        Offer(name: "X",           tagline: "Bookmarks become findable",             group: "Network",   connectable: false,
              summary: "The posts you bookmarked stop disappearing — they land in your feed, findable later."),
        Offer(name: "Steam",       tagline: "What you play, in your feed",           group: "Games",     connectable: true,
              summary: "Recently played games land in your feed, linking to their store pages. Connects with a free Steam Web API key and your public profile name — the key stays in this iPhone's Keychain. Read-only.",
              needsSetup: true),
        Offer(name: "Obsidian",    tagline: "Your vault, beside your things",        group: "Notes",     connectable: true,
              summary: "Point at your vault folder and your notes land as things — findable next to everything else. Fully local: the vault is read in place, never modified, and nothing leaves this iPhone.",
              needsSetup: true),
        Offer(name: "Twitch",      tagline: "Live follows land in your feed",        group: "Watching",  connectable: true,
              summary: "When a channel you follow goes live, the stream lands in your feed as a link — catch it while it's on. Sign-in happens on Twitch's own page with a short code; read-only, no password in the app.",
              needsSetup: true),
        Offer(name: "Substack",    tagline: "Follow any publication",                group: "Reading",   connectable: true,
              summary: "Follow any Substack — new posts land in your feed as links, fetched straight from the publication's own feed. Paste its URL or name. No account. Read-only.",
              needsSetup: true),
        Offer(name: "Kindle",      tagline: "Import your highlights",                group: "Reading",   connectable: true,
              summary: "A one-time import of your Kindle's highlights — the My Clippings.txt the device writes becomes findable notes, grouped by book. No account; Amazon offers no live read.",
              needsSetup: true),
        Offer(name: "Podcasts",    tagline: "Follow any show",                       group: "Listening", connectable: true,
              summary: "Follow any podcast — new episodes land in your feed as links. Search for a show and pick it; episodes arrive through the show's own public feed. No account. Read-only.",
              needsSetup: true),
        Offer(name: "Contacts",    tagline: "The people you know, findable",         group: "People",    connectable: true,
              summary: "Your contacts become findable people — a name you're looking for turns up with everything it connects to. Search-only: they never crowd your feed. Everything stays on this iPhone — Contacts never touches a server. Read-only."),
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
