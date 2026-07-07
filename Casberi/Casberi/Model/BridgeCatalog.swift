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
        Offer(name: "Gmail",       tagline: "What matters in your inbox",            group: "Your mail",      connectable: false,
              summary: "The mail that matters becomes findable things — no inbox to wade through — and Casberi can draft a reply when you ask."),
        Offer(name: "iCloud Mail", tagline: "Your @icloud.com inbox, findable",      group: "Your mail",      connectable: false,
              summary: "Connects with an app-specific password (the sanctioned route) and the mail that matters becomes findable things. This is the ACCOUNT — the Mail app itself has no door for other apps, and Apple Notes has none at all; those reach Casberi through the share sheet."),
        Offer(name: "ChatGPT",     tagline: "Import your chats, keep them findable", group: "Your agent",     connectable: false,
              summary: "A one-time import of your chat history, kept searchable alongside your things. (No live read — OpenAI doesn't offer one; this is your export, backfilled.)"),
        Offer(name: "Claude",      tagline: "Connect it to your things",             group: "Your agent",     connectable: false,
              summary: "Claude connects to Casberi — it reads your things when you ask and saves only what you approve. The inverse of a bridge: a client reaching in, not data pulled out."),
        Offer(name: "Bankr",       tagline: "Its asks wait for your tap",            group: "Your agent",     connectable: false,
              summary: "A trading agent that works through your gateway. Casberi never trades — Bankr's asks land here as approvals, its moves show up through your wallet, and nothing happens without your tap."),
        Offer(name: "Venice",      tagline: "Private AI, nothing retained",          group: "Your agent",     connectable: false,
              summary: "Venice keeps chats on your own device by design, so there's nothing to read in — its private API is a candidate to power Casberi's answers instead."),
        Offer(name: "OpenClaw",    tagline: "Your agents' work lands here",          group: "Your machines",  connectable: false,
              summary: "What your agents make — jobs, runs, outputs — lands in your feed with full provenance, and their approvals reach you here."),
        Offer(name: "GitHub",      tagline: "PRs and issues, in your feed",         group: "Your work",      connectable: false,
              summary: "Your pull requests and issues become things you can find and act on, without living in the repo."),
        Offer(name: "Linear",      tagline: "Your issues stay in reach",             group: "Your work",      connectable: false,
              summary: "The issues assigned to you join your things and surface when they matter."),
        Offer(name: "Notion",      tagline: "Pages join your things",                group: "Your work",      connectable: false,
              summary: "Your Notion pages become findable things, so what you wrote isn't stranded in one more app."),
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
