import Foundation

/// Store-page previews (option 4, 2026-07-07): the dream left the feed and
/// lives HERE — each not-yet-connectable app's product page streams a small
/// preview of its shape through the real gen-UI engine, the way App Store
/// screenshots preview an app. The feed itself is 100% real from minute one;
/// fake content is confined to the one surface where preview framing is
/// honest and expected.
enum StorePreview {

    /// Up to two sample row titles for an offer — the story card's middle
    /// band ghosts what lands, parsed from the same preview doc the product
    /// page streams so the story and the page never disagree. Cached: the
    /// carousel's interactive scroll re-evaluates card bodies every frame,
    /// and the parse is constant per offer.
    private static var sampleCache: [String: [String]] = [:]
    static func sampleTitles(for name: String) -> [String] {
        if let hit = sampleCache[name] { return hit }
        var titles: [String] = []
        for line in doc(for: name) ?? [] {
            guard titles.count < 2 else { break }
            let quotes = line.split(separator: "\"").enumerated()
                .filter { $0.offset % 2 == 1 }.map { String($0.element) }
            if line.contains("TxRow(\"") {
                // TxRow(verb, body, context) — the verb alone ("Swapped")
                // reads as a broken placeholder; the body is the story.
                if quotes.count >= 2 { titles.append("\(quotes[0]) \(quotes[1])") }
            } else if line.contains("Row(\"") {
                if let t = quotes.first { titles.append(t) }
            } else if line.contains("TakeawayCard(") || line.contains("ApprovalCard(") {
                if quotes.count >= 2 { titles.append(quotes[1]) }
            }
        }
        sampleCache[name] = titles
        return titles
    }

    /// The preview document for an offer, or nil when a preview would add
    /// nothing (connectable apps show real things instead; Venice lands no
    /// things — its key powers answers, so the tagline row speaks for it).
    static func doc(for name: String) -> [String]? {
        switch name {
        case "Wallet": [
            "root = Stack([map, t1, t2])",
            "map = TagMap(\"Holdings\", null, [ETH 4210, USDC 1840, SOL 980, LINK 460])",
            "t1 = TxRow(\"Swapped\", \"0.4 ETH → 1,120 USDC\", \"Base · Uniswap\")",
            "t2 = TxRow(\"Received\", \"250 USDC\", \"from maya.eth\")",
        ]
        case "Gmail": [
            "root = Stack([w])",
            "w = Widget(\"Waiting on you\", null, [m1, m2])",
            "m1 = MailRow(\"Your hotel reservation is confirmed\", \"Check-in Fri, 2 nights.\", \"8:12 AM\")",
            "m2 = MailRow(\"Re: token layer sign-off\", \"Looks good — ship it.\", \"Yesterday\")",
        ]
        case "iCloud Mail": [
            "root = Stack([w])",
            "w = Widget(\"Waiting on you\", null, [m1])",
            "m1 = MailRow(\"Your invoice is ready\", \"View or download anytime.\", \"9:02 AM\")",
        ]
        case "OpenClaw": [
            "root = Stack([a, w])",
            "a = ApprovalCard(\"CLAUDE-CODE · VIA OPENCLAW\", \"Deploy the staging build?\", \"wants to run: deploy --env staging\")",
            "w = Widget(\"From your machines\", null, [r1, r2])",
            "r1 = Row(\"Nightly backup ran\", \"Run\", \"OpenClaw\", \"4:00 AM\")",
            "r2 = Row(\"Parse March invoices\", \"Job\", \"OpenClaw\", \"2h\")",
        ]
        case "Tokens": [
            "root = Stack([w])",
            "w = Widget(\"Watchlist\", null, [r1, r2])",
            "r1 = Row(\"BankrCoin · $BNKR\", \"Link\", \"Tokens\", \"now\")",
            "r2 = Row(\"Degen · $DEGEN\", \"Link\", \"Tokens\", \"now\")",
        ]
        case "ChatGPT": [
            "root = Stack([c])",
            "c = TakeawayCard(\"LISBON TRIP\", \"Trip plan: Lisbon\", \"Three neighborhoods, two day trips, one food market.\")",
        ]
        case "Claude": [
            "root = Stack([c])",
            "c = TakeawayCard(\"IMPORTED\", \"Refactor plan: sync layer\", \"CloudKit zones, conflict rules, and the migration order.\")",
        ]
        case "Gemini": [
            "root = Stack([c])",
            "c = TakeawayCard(\"IMPORTED\", \"Compare mirrorless cameras\", \"Sensor size first, then lenses — the body is the cheap part.\")",
        ]
        case "GitHub": [
            "root = Stack([w])",
            "w = Widget(\"In your feed\", null, [r1, r2])",
            "r1 = Row(\"PR #142: token layer\", \"Link\", \"GitHub\", \"1h\")",
            "r2 = Row(\"Issue: dark mode contrast\", \"Link\", \"GitHub\", \"3h\")",
        ]
        case "Linear": [
            "root = Stack([w])",
            "w = Widget(\"Assigned to you\", null, [r1])",
            "r1 = Row(\"CAS-88: polish the composer\", \"Link\", \"Linear\", \"2h\")",
        ]
        case "Notion": [
            "root = Stack([w])",
            "w = Widget(\"Pages\", null, [r1])",
            "r1 = Row(\"Q3 planning notes\", \"Note\", \"Notion\", \"1d\")",
        ]
        case "X": [
            "root = Stack([w])",
            "w = Widget(\"Bookmarked\", null, [r1])",
            "r1 = Row(\"Thread: on-device models in 2026\", \"Link\", \"X\", \"5h\")",
        ]
        case "Reddit": [
            "root = Stack([w])",
            "w = Widget(\"Saved\", null, [r1])",
            "r1 = Row(\"The best coastal drives near Lisbon\", \"Link\", \"Reddit\", \"1d\")",
        ]
        case "YouTube": [
            "root = Stack([w])",
            "w = Widget(\"Liked and saved\", null, [r1])",
            "r1 = Row(\"Deadlift form, 8 minutes\", \"Link\", \"YouTube\", \"2d\")",
        ]
        case "Twitch": [
            "root = Stack([w])",
            "w = Widget(\"Live now\", null, [r1])",
            "r1 = Row(\"LIVE: northernlion — Balatro\", \"Link\", \"Twitch\", \"now\")",
        ]
        case "Apple Music", "Spotify": [
            "root = Stack([w])",
            "w = Widget(\"Listening\", null, [r1])",
            "r1 = Row(\"Liked: Verano porteño\", \"Link\", \"\(name)\", \"1d\")",
        ]
        case "Apple Health": [
            "root = Stack([w])",
            "w = Widget(\"Training\", null, [r1, r2])",
            "r1 = Row(\"Evening run · 5.2 km\", \"Event\", \"Apple Health\", \"6:31 PM\")",
            "r2 = Row(\"Strength · 45 min\", \"Event\", \"Apple Health\", \"Yesterday\")",
        ]
        case "Strava": [
            "root = Stack([w])",
            "w = Widget(\"Activities\", null, [r1, r2])",
            "r1 = Row(\"Morning ride · 24.1 km\", \"Event\", \"Strava\", \"7:02 AM\")",
            "r2 = Row(\"Long run · 12 km\", \"Event\", \"Strava\", \"Sun\")",
        ]
        case "Cal.com": [
            "root = Stack([w])",
            "w = Widget(\"Booked with you\", null, [r1, r2])",
            "r1 = Row(\"Intro call · Sam K\", \"Event\", \"Cal.com\", \"2:00 PM\")",
            "r2 = Row(\"Portfolio review · 30 min\", \"Event\", \"Cal.com\", \"Thu\")",
        ]
        case "Calendly": [
            "root = Stack([w])",
            "w = Widget(\"On your schedule\", null, [r1, r2])",
            "r1 = Row(\"Interview · Riley M\", \"Event\", \"Calendly\", \"11:30 AM\")",
            "r2 = Row(\"Coffee chat · 15 min\", \"Event\", \"Calendly\", \"Fri\")",
        ]
        case "Todoist": [
            "root = Stack([w])",
            "w = Widget(\"On your list\", null, [r1, r2])",
            "r1 = Row(\"Renew passport\", \"Reminder\", \"Todoist\", \"today\")",
            "r2 = Row(\"Send the invoice\", \"Reminder\", \"Todoist\", \"Fri\")",
        ]
        case "Slack": [
            "root = Stack([c])",
            "c = TakeawayCard(\"#DESIGN\", \"Decision: ship the new feed rows\", \"Maya: let's go with the color tags — sign-off attached.\")",
        ]
        case "Raindrop": [
            "root = Stack([w])",
            "w = Widget(\"Saved\", null, [r1, r2])",
            "r1 = Row(\"The grammar of color systems\", \"Link\", \"Raindrop\", \"2h\")",
            "r2 = Row(\"Lisbon: 36 hours\", \"Link\", \"Raindrop\", \"1d\")",
        ]
        case "Readwise": [
            "root = Stack([c])",
            "c = TakeawayCard(\"HIGHLIGHT · THE CREATIVE ACT\", \"Perfection is the enemy of done\", \"The work tells you what it wants to be — your job is to listen.\")",
        ]
        case "RSS": [
            "root = Stack([w])",
            "w = Widget(\"New posts\", null, [r1, r2])",
            "r1 = Row(\"Daring Fireball: On the new iPad\", \"Link\", \"RSS\", \"3h\")",
            "r2 = Row(\"Stratechery: Aggregation, again\", \"Link\", \"RSS\", \"6h\")",
        ]
        // Broad, not "your posts": the bridge watches ANY account — your own
        // or anyone's — plus mentions, so the preview shows the accounts you
        // follow, not a personal timeline (user, 2026-07-14).
        case "Bluesky": [
            "root = Stack([w])",
            "w = Widget(\"Accounts you watch\", null, [r1, r2])",
            "r1 = Row(\"jay: the feed you own beats the feed you rent\", \"Chat\", \"Bluesky\", \"2h\")",
            "r2 = Row(\"pfrazee: at-proto federation is live\", \"Chat\", \"Bluesky\", \"5h\")",
        ]
        // Farcaster grew likes, mentions, and /channels (2026-07-14) — the
        // preview shows a watched account and a channel cast, not a save pile.
        case "Farcaster": [
            "root = Stack([w])",
            "w = Widget(\"Accounts and channels\", null, [r1, r2])",
            "r1 = Row(\"dwr: base fees at all-time low\", \"Chat\", \"Farcaster\", \"4h\")",
            "r2 = Row(\"v: shipping in /dev today\", \"Chat\", \"Farcaster\", \"1h\")",
        ]
        case "OpenSea": [
            "root = Stack([w])",
            "w = Widget(\"New drops\", null, [r1, r2])",
            "r1 = Row(\"Fidenza · new collection\", \"Link\", \"OpenSea\", \"now\")",
            "r2 = Row(\"Base Punks · minting now\", \"Link\", \"OpenSea\", \"1h\")",
        ]
        case "GeckoTerminal": [
            "root = Stack([w])",
            "w = Widget(\"Trending on Base\", null, [r1, r2])",
            "r1 = Row(\"Higher · $HIGHER\", \"Link\", \"GeckoTerminal\", \"now\")",
            "r2 = Row(\"Brett · $BRETT\", \"Link\", \"GeckoTerminal\", \"now\")",
        ]
        case "Kalshi": [
            "root = Stack([w])",
            "w = Widget(\"Live odds\", null, [r1, r2])",
            "r1 = Row(\"Fed holds rates in March · 68%\", \"Link\", \"Kalshi\", \"now\")",
            "r2 = Row(\"Lakers make the playoffs · 74%\", \"Link\", \"Kalshi\", \"2h\")",
        ]
        case "Stocktwits": [
            "root = Stack([w])",
            "w = Widget(\"Watching\", null, [r1, r2])",
            "r1 = Row(\"Apple Inc · $AAPL\", \"Link\", \"Stocktwits\", \"now\")",
            "r2 = Row(\"NVDA holding the 200-day — adding here\", \"Chat\", \"Stocktwits\", \"1h\")",
        ]
        // The rest of the connectable catalog (2026-07-14): every card in the
        // discover carousel now ghosts what lands instead of empty air. Each
        // row's tag is the kind it becomes; the source is the app it comes from.
        case "Photos": [
            "root = Stack([w])",
            "w = Widget(\"From your screenshots\", null, [r1, r2])",
            "r1 = Row(\"Recipe: miso-glazed salmon\", \"Screenshot\", \"Photos\", \"2h\")",
            "r2 = Row(\"Lisbon flight — confirmation\", \"Screenshot\", \"Photos\", \"Yesterday\")",
        ]
        case "Calendar": [
            "root = Stack([w])",
            "w = Widget(\"On your calendar\", null, [r1, r2])",
            "r1 = Row(\"Dentist\", \"Event\", \"Calendar\", \"9:00 AM\")",
            "r2 = Row(\"Team sync\", \"Event\", \"Calendar\", \"Wed\")",
        ]
        case "Reminders": [
            "root = Stack([w])",
            "w = Widget(\"Your lists\", null, [r1, r2])",
            "r1 = Row(\"Book the flights\", \"Reminder\", \"Reminders\", \"today\")",
            "r2 = Row(\"Call the landlord\", \"Reminder\", \"Reminders\", \"Fri\")",
        ]
        case "Pinterest": [
            "root = Stack([w])",
            "w = Widget(\"Your pins\", null, [r1, r2])",
            "r1 = Row(\"Kitchen shelving ideas\", \"Link\", \"Pinterest\", \"1d\")",
            "r2 = Row(\"Weeknight pasta board\", \"Link\", \"Pinterest\", \"2d\")",
        ]
        case "Substack": [
            "root = Stack([w])",
            "w = Widget(\"New posts\", null, [r1, r2])",
            "r1 = Row(\"Slow Boring: the housing fix\", \"Link\", \"Substack\", \"3h\")",
            "r2 = Row(\"Lenny: onboarding that sticks\", \"Link\", \"Substack\", \"1d\")",
        ]
        case "Podcasts": [
            "root = Stack([w])",
            "w = Widget(\"New episodes\", null, [r1, r2])",
            "r1 = Row(\"Acquired: the Nvidia episode\", \"Link\", \"Podcasts\", \"6h\")",
            "r2 = Row(\"The Daily: this morning\", \"Link\", \"Podcasts\", \"1d\")",
        ]
        case "Steam": [
            "root = Stack([w])",
            "w = Widget(\"Recently played\", null, [r1, r2])",
            "r1 = Row(\"Balatro · 2.1 hrs\", \"Link\", \"Steam\", \"today\")",
            "r2 = Row(\"Hades II · 40 min\", \"Link\", \"Steam\", \"Yesterday\")",
        ]
        case "Kindle": [
            "root = Stack([w])",
            "w = Widget(\"Highlights\", null, [r1, r2])",
            "r1 = Row(\"Atomic Habits — you get what you repeat\", \"Note\", \"Kindle\", \"1d\")",
            "r2 = Row(\"Dune — fear is the mind-killer\", \"Note\", \"Kindle\", \"3d\")",
        ]
        case "Apple Notes": [
            "root = Stack([w])",
            "w = Widget(\"Shared in\", null, [r1])",
            "r1 = Row(\"Apartment move — checklist\", \"Note\", \"Apple Notes\", \"2h\")",
        ]
        case "Apple Journal": [
            "root = Stack([w])",
            "w = Widget(\"Your entries\", null, [r1, r2])",
            "r1 = Row(\"A good day on the coast\", \"Note\", \"Apple Journal\", \"Sun\")",
            "r2 = Row(\"First run in weeks\", \"Note\", \"Apple Journal\", \"Mar 3\")",
        ]
        case "Day One": [
            "root = Stack([w])",
            "w = Widget(\"Your journal\", null, [r1, r2])",
            "r1 = Row(\"Lisbon, day two\", \"Note\", \"Day One\", \"May 14\")",
            "r2 = Row(\"On finishing the draft\", \"Note\", \"Day One\", \"Apr 2\")",
        ]
        case "Obsidian": [
            "root = Stack([w])",
            "w = Widget(\"From your vault\", null, [r1, r2])",
            "r1 = Row(\"Sync layer — design notes\", \"Note\", \"Obsidian\", \"1d\")",
            "r2 = Row(\"Books to read in 2026\", \"Note\", \"Obsidian\", \"4d\")",
        ]
        case "Shopify": [
            "root = Stack([w])",
            "w = Widget(\"New drops\", null, [r1, r2])",
            "r1 = Row(\"Aer Travel Pack 3 · $230\", \"Product\", \"Shopify\", \"2h\")",
            "r2 = Row(\"Restock: the merino tee\", \"Product\", \"Shopify\", \"1d\")",
        ]
        case "Deals": [
            "root = Stack([w])",
            "w = Widget(\"Fresh deals\", null, [r1, r2])",
            "r1 = Row(\"Sony WH-1000XM5 · $278 (was $399)\", \"Product\", \"Deals\", \"1h\")",
            "r2 = Row(\"Anker power bank · $34\", \"Product\", \"Deals\", \"3h\")",
        ]
        case "Open Food Facts": [
            "root = Stack([w])",
            "w = Widget(\"Scanned in\", null, [r1, r2])",
            "r1 = Row(\"Oatly Barista Edition · Nutri-Score C\", \"Product\", \"Open Food Facts\", \"now\")",
            "r2 = Row(\"Clif Bar, Chocolate Chip · Nutri-Score D\", \"Product\", \"Open Food Facts\", \"1d\")",
        ]
        default:
            nil
        }
    }
}
