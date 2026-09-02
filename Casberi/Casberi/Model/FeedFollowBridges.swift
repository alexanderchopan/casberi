import Foundation
import Observation
import SwiftData

/// The feed-follow bridges (2026-07-12) — Substack, Reddit, YouTube, Podcasts.
/// Each is Pinterest's move at heart: a public name (a publication, a
/// subreddit or user, a channel, a show) becomes a feed URL this iPhone
/// fetches directly, and new posts land as link things. No account, no token,
/// no server — the same fetch → parse → dedupe → things path RSS established,
/// with FeedParser doing the parsing. Every bridge watches a LIST, the way
/// Bluesky and Farcaster do, so you can follow several of each.
///
/// The four differ only in how a name becomes a feed URL:
///   • Substack — `<pub>.substack.com/feed`, or a custom domain's `/feed`.
///   • Reddit   — `reddit.com/r/<sub>/.rss` or `/user/<name>/.rss`.
///   • YouTube  — `…/feeds/videos.xml?channel_id=<UC…>`, the id resolved once
///     from the channel page (people paste an @handle, not a UC id).
///   • Podcasts — the show's own RSS, found through Apple's keyless iTunes
///     Search API (the field is a search, not a paste).

// MARK: - Store (one watched-feed list per bridge)

/// One entry in a bridge's followed list. `input` is what the person gave
/// (the dedupe + remove key); `feedURL` is the resolved feed (built at add
/// time, or lazily on first sync for YouTube); `title` is learned from the
/// feed itself, so the row reads as the publication's real name.
struct FeedFollowEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var input: String
    var feedURL: String = ""
    var title: String = ""

    var displayName: String { title.isEmpty ? input : title }
}

@Observable
final class FeedFollowStore {
    static let substack = FeedFollowStore(key: "feed.substack")
    static let reddit   = FeedFollowStore(key: "feed.reddit")
    static let youtube  = FeedFollowStore(key: "feed.youtube")
    static let podcasts = FeedFollowStore(key: "feed.podcasts")
    static let telegram = FeedFollowStore(key: "feed.telegram")

    private let key: String
    var entries: [FeedFollowEntry] { didSet { persist() } }

    init(key: String) {
        self.key = key
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([FeedFollowEntry].self, from: data) {
            entries = saved
        } else {
            entries = []
        }
    }

    var isEmpty: Bool { entries.isEmpty }
    var inputs: [String] { entries.map(\.input) }

    func add(_ entry: FeedFollowEntry) {
        guard !entry.input.isEmpty,
              !entries.contains(where: { $0.input.caseInsensitiveCompare(entry.input) == .orderedSame })
        else { return }
        entries.append(entry)
    }

    func remove(input: String) {
        // The feed's HTTP record goes with the follow (2026-08-05) — see
        // `FeedFreshness.forget`. Keyed on the RESOLVED feed URL, which is
        // what was actually fetched; an entry never synced has none yet and
        // has nothing to forget.
        for entry in entries
        where entry.input.caseInsensitiveCompare(input) == .orderedSame && !entry.feedURL.isEmpty {
            FeedFreshness.forget(entry.feedURL)
        }
        entries.removeAll { $0.input.caseInsensitiveCompare(input) == .orderedSame }
    }

    func removeAll() {
        for entry in entries where !entry.feedURL.isEmpty { FeedFreshness.forget(entry.feedURL) }
        entries = []
    }

    /// The learned title for a watched input, for the accounts list.
    func display(for input: String) -> String {
        entries.first { $0.input.caseInsensitiveCompare(input) == .orderedSame }?.displayName ?? input
    }

    func setFeedURL(_ url: String, for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].feedURL != url else { return }
        entries[i].feedURL = url
    }

    func setTitle(_ title: String, for id: UUID) {
        guard !title.isEmpty,
              let i = entries.firstIndex(where: { $0.id == id }), entries[i].title != title else { return }
        entries[i].title = title
    }

    /// Forgets a learned title so the next sync re-learns it from the feed.
    /// `setTitle` deliberately refuses an empty string (a feed with no
    /// `<title>` must not blank a good name), so a genuine reset needs its own
    /// door — see `YouTubeFollowRepair`, which is the only caller: a follow
    /// pointed at the wrong channel learned the wrong channel's real name, and
    /// re-pointing it without clearing that would land the right videos under
    /// the wrong publisher.
    func clearTitle(for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }), !entries[i].title.isEmpty else { return }
        entries[i].title = ""
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Kind (the words + the URL rule that differ per bridge)

enum FeedFollowKind: String, CaseIterable {
    case substack = "Substack"
    case reddit   = "Reddit"
    case youtube  = "YouTube"
    case podcasts = "Podcasts"
    /// Public CHANNELS only (prd §456) — broadcast media with a public web
    /// page, which is why this is a feed follow and not the MTProto problem
    /// §57 declined. A group or a DM can never arrive here.
    case telegram = "Telegram"

    var source: String { rawValue }
    var bridgeID: String { rawValue.lowercased() }
    var refPrefix: String { rawValue.lowercased() }

    var store: FeedFollowStore {
        switch self {
        case .substack: FeedFollowStore.substack
        case .reddit:   FeedFollowStore.reddit
        case .youtube:  FeedFollowStore.youtube
        case .podcasts: FeedFollowStore.podcasts
        case .telegram: FeedFollowStore.telegram
        }
    }

    /// The bridge whose field is a search, not a paste.
    var searches: Bool { self == .podcasts }

    var nameNoun: String {
        switch self {
        case .substack: "publication"
        case .reddit:   "subreddit or user"
        case .youtube:  "channel"
        case .podcasts: "show"
        case .telegram: "channel"
        }
    }

    var placeholder: String {
        switch self {
        case .substack: "read.substack.com or a name"
        case .reddit:   "r/swift or u/name"
        case .youtube:  "@handle or channel URL"
        case .podcasts: "Search a show"
        case .telegram: "@channel or t.me link"
        }
    }

    /// What lands, for proof lines: "3 posts in".
    var noun: String {
        switch self {
        case .substack, .reddit: "posts"
        case .youtube:           "videos"
        case .podcasts:          "episodes"
        case .telegram:          "posts"
        }
    }

    var recentHeader: String {
        switch self {
        case .substack, .reddit: "Posts"
        case .youtube:           "Videos"
        case .podcasts:          "Episodes"
        case .telegram:          "Posts"
        }
    }

    var fieldFooter: String {
        switch self {
        case .substack: "Paste a Substack URL or its name — new posts land as links. No account, no algorithm in between."
        case .reddit:   "Follow a subreddit (r/name) or a person (u/name) — new posts land as links, through Reddit's own feed."
        case .youtube:  "Paste a channel URL or its @handle — new uploads land as links, through YouTube's own feed."
        case .podcasts: "Search for a show — new episodes land as links, through the show's own feed. No account."
        case .telegram: "Name a public channel — its posts land as they are broadcast, read from the channel's own public page. No account."
        }
    }

    /// The connect screen's one sentence (prd §315) — the mode's consequence
    /// and the payoff, in that order. Replaced `footerLine`, which said the
    /// same facts in the footer's tertiary gray at the bottom of the screen.
    var setupIntro: String {
        switch self {
        case .substack:
            String(localized: "Name a publication and its posts arrive, straight from its own feed. A subscriber-only post stays behind Substack's wall.")
        case .reddit:
            String(localized: "Name a subreddit or a person and their public posts arrive, through Reddit's own RSS.")
        case .youtube:
            String(localized: "Name a channel and its uploads arrive through YouTube's own feed. Shorts are tagged so you can filter them out.")
        case .podcasts:
            String(localized: "Name a show and its episodes arrive through the show's own public feed.")
        case .telegram:
            String(localized: "Name a public channel and its posts arrive from the channel's own page. Groups and your own chats are never readable this way.")
        }
    }

    var canLine: String {
        switch self {
        case .substack: "Reads the Substacks you follow."
        case .reddit:   "Reads the subreddits and people you follow."
        case .youtube:  "Reads the channels you follow."
        case .podcasts: "Reads the shows you follow."
        case .telegram: "Reads the public channels you follow."
        }
    }

    /// Cleans a typed input into the stored, deduped form.
    func normalize(_ raw: String) -> String {
        switch self {
        case .substack: FeedURL.substackInput(raw)
        case .reddit:   FeedURL.redditInput(raw)
        case .youtube:  raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .podcasts: raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .telegram: TelegramChannel.normalizeHandle(raw)
        }
    }

    /// Builds (or resolves) the feed URL for an input. Async because YouTube
    /// resolves its channel id from the channel page; the rest are pure string
    /// templates and return at once.
    func feedURL(for input: String) async -> String? {
        switch self {
        case .substack: FeedURL.substack(input)
        case .reddit:   FeedURL.reddit(input)
        case .youtube:  await FeedURL.youtube(input)
        // Picking a search result already carries the feed; a typed show name
        // resolves through the same search — first match wins.
        case .podcasts: await FeedFetch.searchPodcasts(input).first?.feedURL
        // A pure string template like Substack's — the channel's own preview
        // page. Refused for a name Telegram could not serve, so a typo never
        // becomes a request for somebody else's page.
        case .telegram: TelegramChannel.isValidHandle(input)
            ? TelegramChannel.previewURL(for: input) : nil
        }
    }
}

// MARK: - URL rules

enum FeedURL {
    /// A Substack input keeps its host when one is given, else the bare slug.
    static func substackInput(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://", "www.", "@"] where t.hasPrefix(junk) {
            t.removeFirst(junk.count)
        }
        if let slash = t.firstIndex(of: "/") { t = String(t[..<slash]) }
        return t
    }

    static func substack(_ input: String) -> String? {
        let t = substackInput(input)
        guard !t.isEmpty else { return nil }
        if t.contains(".") { return "https://\(t)/feed" }        // a host (custom or *.substack.com)
        return "https://\(t).substack.com/feed"                  // a bare slug
    }

    /// A Reddit input canonicalizes to "r/<sub>" or "u/<name>". A bare word is
    /// read as a subreddit — the common follow.
    static func redditInput(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["https://", "http://", "www.", "old.reddit.com/", "reddit.com/"] where t.lowercased().hasPrefix(junk) {
            t.removeFirst(junk.count)
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lower = t.lowercased()
        if lower.hasPrefix("r/") { let n = t.dropFirst(2); return n.isEmpty ? "" : "r/" + n }
        if lower.hasPrefix("u/") { let n = t.dropFirst(2); return n.isEmpty ? "" : "u/" + n }
        if lower.hasPrefix("user/") { let n = t.dropFirst(5); return n.isEmpty ? "" : "u/" + n }
        // A bare word is a subreddit; empty input stays empty so the field's
        // non-empty guard rejects it instead of storing "r/".
        return t.isEmpty ? "" : "r/" + t
    }

    static func reddit(_ input: String) -> String? {
        let t = redditInput(input)
        if t.hasPrefix("r/") { return "https://www.reddit.com/r/\(t.dropFirst(2))/.rss" }
        if t.hasPrefix("u/") { return "https://www.reddit.com/user/\(t.dropFirst(2))/.rss" }
        return nil
    }

    static func youtube(_ input: String) async -> String? {
        guard let id = await FeedFetch.resolveYouTubeChannelID(input) else { return nil }
        return "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"
    }
}

// MARK: - Fetch (a browser-ish UA — Reddit 429s the default one) + resolvers

enum FeedFetch {
    /// A feed GET with a real User-Agent. Reddit answers the default URLSession
    /// agent with a 429; YouTube and Substack don't care, so one path serves
    /// all four. A non-2xx is a failed fetch, not empty data.
    ///
    /// `service` is which of the four asked (2026-08-03). Two of them fetch a
    /// host the reach registry structurally cannot name — a Substack on its
    /// own domain, and a podcast feed on whatever site the show publishes
    /// from — so the caller passes its own name and the receipts screen files
    /// the host under it. See `NetworkLedger.Entry.service`.
    static func data(_ url: URL, as service: String? = nil) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; Casberi/1.0; +https://casberi.app)",
                         forHTTPHeaderField: "User-Agent")
        NetworkLedger.shared.record(request, as: service)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) { return nil }
        return data
    }

    /// A channel's UC… id — used as-is when the input already carries one,
    /// otherwise scraped from the channel page the @handle/URL points to.
    ///
    /// THE FIRST `"channelId"` IN THE PAGE IS NOT THIS CHANNEL'S, and reading
    /// it was this function's shipped behaviour until 2026-08-05. Measured
    /// against three handles, three for three wrong:
    ///
    ///     @MrBeast     "channelId" → UCAiLfjNXkNv24uhpzUgPa6A   canonical → UCX6OQ3DkcsbYNE6H8uQQuVA
    ///     @mkbhd       "channelId" → UCG7J20LhUeLl6y_Emi7OJrA   canonical → UCBJycsmduvYEL83R_U4JriQ
    ///     @veritasium  "channelId" → UCin0m13qWv3-051xlWlHamA   canonical → UCHnyfMqiRRG1u-2MsSQLbXA
    ///
    /// A channel page's initial-data blob names other channels before it names
    /// its own, so following an `@handle` — the shape the field's own
    /// placeholder asks for — silently followed a DIFFERENT channel. It failed
    /// invisibly: a real feed came back, real videos landed, and the follow's
    /// learned title was the wrong channel's real name, so nothing anywhere
    /// read as an error.
    ///
    /// The order below is what the page says about ITSELF, strongest first —
    /// `<link rel="canonical">` and `"externalId"` are the channel's own
    /// identity, and the `channel/UC…` fallback was already correct 3/3
    /// (because the canonical link is the first `channel/` occurrence in the
    /// document). The naive `"channelId"` read is gone rather than demoted:
    /// it never answers correctly, so keeping it anywhere in the chain would
    /// only be a slower way to be wrong. Guarded nightly — see
    /// `scripts/live-integrations.sh`.
    static func resolveYouTubeChannelID(_ raw: String) async -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        // A pasted `/channel/UC…` URL or a bare id. Strict form first — a real
        // id is exactly "UC" + 22 base64url characters — with the old loose
        // match kept as a fallback so a future length change can't stop a
        // person pasting their own id.
        if let id = match(t, pattern: "UC[A-Za-z0-9_-]{22}(?![A-Za-z0-9_-])")
            ?? match(t, pattern: "UC[A-Za-z0-9_-]{20,}") { return id }

        var page = t
        if !page.contains("://") {
            if page.hasPrefix("@") {
                page = "https://www.youtube.com/\(page)"
            } else if page.lowercased().hasPrefix("youtube.com") || page.lowercased().hasPrefix("m.youtube.com") {
                page = "https://www." + page.replacingOccurrences(of: "m.youtube.com", with: "youtube.com")
            } else {
                page = "https://www.youtube.com/@\(page)"
            }
        }
        guard let url = URL(string: page), let data = await data(url),
              let html = String(data: data, encoding: .utf8) else { return nil }
        for pattern in [
            "<link[^>]+rel=[\"']canonical[\"'][^>]+href=[\"'][^\"']*/channel/(UC[A-Za-z0-9_-]{22})",
            "\"externalId\":\"(UC[A-Za-z0-9_-]{22})\"",
            "channel/(UC[A-Za-z0-9_-]{22})",
        ] {
            if let id = match(html, pattern: pattern, group: 1) { return id }
        }
        return nil
    }

    /// Apple's keyless podcast directory — a show search that hands back each
    /// result's own RSS feed, so picking one stores the feed with no follow-up
    /// lookup. The Hit carries the artwork (the row thumbnail) and the artist
    /// (its subtitle).
    static func searchPodcasts(_ query: String) async -> [UserSearch.Hit] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let json = await IngestSupport.getJSON(
                "https://itunes.apple.com/search?media=podcast&limit=8&term=\(q)") as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let feed = r["feedUrl"] as? String, !feed.isEmpty,
                  let name = (r["collectionName"] as? String) ?? (r["trackName"] as? String), !name.isEmpty
            else { return nil }
            let artist = (r["artistName"] as? String) ?? "Podcast"
            let art = IngestSupport.imageURL((r["artworkUrl600"] as? String) ?? (r["artworkUrl100"] as? String))
            return UserSearch.Hit(handle: artist, displayName: name, avatarURL: art, fid: nil, feedURL: feed)
        }
    }

    private static func match(_ s: String, pattern: String, group: Int = 0) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group else { return nil }
        return ns.substring(with: m.range(at: group))
    }
}

// MARK: - Repairing follows the old resolver pointed at the wrong channel

/// A one-time re-resolution of every YouTube follow (2026-08-05).
///
/// `FeedFetch.resolveYouTubeChannelID` read the first `"channelId"` in a
/// channel page, which is another channel's — see the measured table in its
/// own doc. So every follow added by `@handle` or channel URL, for as long as
/// that code shipped, points at a channel the person never chose. Fixing the
/// resolver only fixes follows added AFTER the fix; this fixes the ones
/// already stored, which is most of them.
///
/// PROVABLE, NOT INFERRED. It re-resolves the person's own stored input and
/// compares against the channel id in the feed URL that input produced. A
/// difference is proof the stored one is wrong; equality means the follow was
/// always fine and nothing is touched. No follow is ever removed and no input
/// is ever rewritten — only the derived feed URL and the title learned through
/// it.
///
/// THE ROWS GO TOO, and only in the proven-wrong case: a follow that has been
/// landing a stranger's uploads under that stranger's name has filled the feed
/// with videos from a channel the person never asked for, and re-pointing the
/// follow would strand them — `HandleBridge.removeName` prunes by the follow's
/// CURRENT learned name, so after the repair nothing could ever explain them
/// again. This is §286's ruling ("if you unfollow something it shouldn't show
/// in your corpus") reaching the case where the app, not the person, chose
/// wrong.
///
/// IT DOES NOT MARK ITSELF DONE UNTIL EVERY ENTRY HAS ANSWERED. YouTube
/// answers a client it has decided to throttle with a plain 404 (measured, see
/// `FeedFreshness.troubleAfter`), so a pass that resolves nothing is a
/// throttled pass, not a clean bill of health — marking done there would leave
/// a wrong follow wrong forever.
@MainActor
enum YouTubeFollowRepair {
    private static let doneKey = "feed.youtube.idRecheck.v1"
    /// Entries already verified, by entry id. Without it a follow list longer
    /// than `perPass` would re-check the same first four every pass and never
    /// reach the fifth — the pass has to be resumable per entry, not just
    /// bounded.
    private static let seenKey = "feed.youtube.idRecheck.seen"

    /// Channel pages are ~1.4MB each. Four per pass keeps a repair invisible
    /// on a foreground while still finishing in one sync for anyone with a
    /// normal follow list.
    private static let perPass = 4

    struct Report {
        var checked = 0
        var wrong = 0
        var pruned = 0
        /// Entries whose channel page didn't answer this pass — the reason
        /// `done` is withheld. Reported rather than swallowed: "nothing was
        /// wrong" and "we couldn't look" are different answers.
        var unresolved = 0
        var done = false
    }

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    /// The channel id a stored feed URL was built around, or nil for a URL
    /// this bridge didn't build.
    static func channelID(inFeedURL url: String) -> String? {
        guard let range = url.range(of: "channel_id=", options: .caseInsensitive) else { return nil }
        let tail = url[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return tail.hasPrefix("UC") ? String(tail) : nil
    }

    @discardableResult
    static func run(context: ModelContext, force: Bool = false) async -> Report? {
        guard force || !isDone else { return nil }
        let store = FeedFollowStore.youtube
        guard !store.isEmpty else {
            UserDefaults.standard.set(true, forKey: doneKey)
            return Report(done: true)
        }
        var report = Report()
        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        if force { seen = [] }
        // Everything this repair could ever have an opinion about. An entry
        // with no resolved feed URL has nothing to compare against (it will
        // resolve fresh, with the fixed resolver); an input that already
        // carries an id never went through the scrape, so it was never wrong.
        let eligible = store.entries.filter { entry in
            guard !entry.feedURL.isEmpty, channelID(inFeedURL: entry.feedURL) != nil else { return false }
            return entry.input.range(of: "UC[A-Za-z0-9_-]{22}", options: .regularExpression) == nil
        }
        for entry in eligible where !seen.contains(entry.id.uuidString) {
            guard report.checked < perPass else { break }
            guard let stored = channelID(inFeedURL: entry.feedURL) else { continue }
            report.checked += 1
            guard let real = await FeedFetch.resolveYouTubeChannelID(entry.input) else {
                report.unresolved += 1
                continue
            }
            seen.insert(entry.id.uuidString)
            guard real != stored else { continue }
            report.wrong += 1
            let strangersName = entry.title
            FeedFreshness.forget(entry.feedURL)
            store.setFeedURL("https://www.youtube.com/feeds/videos.xml?channel_id=\(real)", for: entry.id)
            store.clearTitle(for: entry.id)
            if !strangersName.isEmpty {
                report.pruned += SocialTopics.pruneAuthor(
                    source: "YouTube", handle: strangersName, remainingTopics: [], context: context)
            }
        }
        UserDefaults.standard.set(Array(seen), forKey: seenKey)
        // Done when every eligible entry has answered at least once. A pass
        // that resolved nothing is a throttled pass, not a clean bill of
        // health — see the type doc.
        if eligible.allSatisfy({ seen.contains($0.id.uuidString) }) {
            UserDefaults.standard.set(true, forKey: doneKey)
            UserDefaults.standard.removeObject(forKey: seenKey)
            report.done = true
        }
        return report
    }
}

// MARK: - Ingest (one path, parameterized by kind)

enum FeedFollowIngest {

    @MainActor private static var running: Set<String> = []

    /// One followed entry's fetch outcome — the sequential bookkeeping loop
    /// below needs the resolved feed URL (to remember it) alongside the
    /// parse. `parsed` is nil when resolution succeeded but the feed's
    /// content couldn't be fetched THIS pass — the resolution still gets
    /// persisted (see `refresh`) so a transient content-fetch failure
    /// doesn't undo an expensive resolution (YouTube's channel-page scrape,
    /// Podcasts' iTunes search) and force it to re-run next time.
    ///
    /// `reached` splits that nil in two (2026-08-05). A 304 also carries no
    /// parse — the publisher answered and nothing changed — and folding it in
    /// with an unreachable host would make a fully up-to-date sync of nothing
    /// but 304s report "couldn't reach any of them".
    private struct Fetched {
        let entry: FeedFollowEntry
        let resolvedFeedURL: String?
        let parsed: FeedParser.Parsed?
        var reached = false
    }

    /// A Telegram channel page as if it were a feed.
    ///
    /// **The posts are REVERSED here, and that is the whole reason this is a
    /// named function rather than three inline lines.** `refresh` takes
    /// `items.prefix(15)` because every feed format on earth is newest-first,
    /// while `t.me/s/<channel>` publishes OLDEST-first — so mapping in
    /// document order hands the ingest the fifteen oldest posts on the page
    /// and silently drops the five newest. The room would fill, and never with
    /// today's news.
    private static func telegramParsed(_ data: Data, entry: FeedFollowEntry) -> FeedParser.Parsed? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        let handle = TelegramChannel.normalizeHandle(entry.input)
        guard let channel = TelegramChannel.parse(html, handle: handle) else { return nil }

        var parsed = FeedParser.Parsed()
        parsed.root = "feed"
        parsed.title = channel.title
        parsed.iconURL = channel.avatarURL ?? ""

        parsed.items = channel.posts.reversed().map { post in
            var item = FeedParser.Item()
            // `refresh` builds the ref as "<refPrefix>:<guid>", and this arm's
            // prefix is "telegram" — so a guid of "post:<channel>/<id>" is
            // exactly `TelegramChannel.refPrefix` plus the post, which is what
            // `Corpus.liveRefPrefixes` matches on to let these rows into All.
            item.guid = "post:\(post.channel)/\(post.id)"
            item.link = post.url
            item.date = post.date
            item.title = IngestSupport.titleLine(telegramTitle(post))
            // The words themselves, so the room reads as posts rather than as
            // a list of clamped headlines.
            if !post.text.isEmpty { item.summary = post.text }
            item.imageURL = post.photoURL ?? ""
            // A forward names someone the channel itself is not, which is
            // precisely what `FeedParser.author` is for; a post the channel
            // wrote names nobody and stays the channel's own.
            item.author = post.forwardedFrom ?? ""
            var tags: [String] = []
            if post.forwardedFrom != nil { tags.append("Forwarded") }
            if post.photoURL != nil { tags.append("Photo") }
            if post.hasVideo { tags.append("Video") }
            item.categories = tags
            return item
        }
        return parsed
    }

    /// What a post is CALLED. Its own first words, or — for a post that is
    /// purely a photograph or a video — the headline of whatever it linked to,
    /// falling back to naming the medium. Never an empty string: `refresh`
    /// skips an item with no title, so a wordless photo post would silently
    /// never land.
    private static func telegramTitle(_ post: TelegramChannel.Post) -> String {
        if !post.text.isEmpty { return post.text }
        if let link = post.linkTitle, !link.isEmpty { return link }
        return post.hasVideo ? String(localized: "Video") : String(localized: "Photo")
    }

    /// How long to wait before the one retry a newly-resolved follow gets.
    /// Long enough to be a different moment to the throttled host, short
    /// enough that somebody watching the field does not read the pause as a
    /// hang — see `fetchAndParse`, which is the only caller.
    private static let firstFetchRetry: TimeInterval = 2

    /// Resolving/fetching/parsing one entry — no shared state, so every
    /// followed entry can run concurrently instead of one round trip at a
    /// time (2026-07-13).
    private static func fetchAndParse(_ entry: FeedFollowEntry, kind: FeedFollowKind) async -> Fetched? {
        var feedURL = entry.feedURL
        var resolvedFeedURL: String?
        if feedURL.isEmpty {
            guard let built = await kind.feedURL(for: entry.input) else { return nil }
            feedURL = built
            resolvedFeedURL = built
        }
        guard let url = URL(string: feedURL) else { return nil }
        // Conditional GET + the feed's own health, shared with the RSS bridge
        // (2026-08-05) — see `FeedFreshness`. It records the host under this
        // bridge's name for the receipts screen too, which two of the four
        // genuinely need: a Substack on its own domain and a podcast feed on
        // whatever host the show publishes from are both hosts the reach
        // registry structurally cannot name (prd §289).
        //
        // A REFUSED FIRST FETCH IS RETRIED ONCE, and the reason is measured
        // rather than defensive. YouTube's `feeds/videos.xml` answers a client
        // it has decided to throttle with a plain 404 or 500 —
        // `FeedFreshness.troubleAfter` records the 2026-08-05 measurement of
        // exactly that, and 2026-08-28 measured it again on the report that
        // prompted this: NASA's channel feed came back 404/500 on four of four
        // bursts, two control channels failed and succeeded in the same
        // windows, and the same NASA URL answered 200 with a full body the
        // moment the requests were paced a minute apart. Nothing about that
        // feed is wrong.
        //
        // This is the ONE fetch somebody is standing in front of. A background
        // pass can lose a round and try again in an hour; the pass that
        // follows a name just typed cannot, because the setup screen reports
        // its failure back as a sentence and the person deletes a follow that
        // was about to work.
        //
        // Scoped to the FIRST fetch — `resolvedFeedURL != nil` is true only on
        // the pass that resolved this follow — so a steady-state sync over
        // twenty feeds never doubles its requests, and a genuinely dead feed
        // costs one extra request the day it is added and none ever after.
        var outcome = await FeedFreshness.fetch(url, as: kind.source)
        if case .failed = outcome, resolvedFeedURL != nil {
            try? await Task.sleep(for: .seconds(firstFetchRetry))
            outcome = await FeedFreshness.fetch(url, as: kind.source)
        }
        switch outcome {
        case .fresh(let data):
            // Telegram is the one arm whose body is not XML — a channel's own
            // web page rather than a feed document (prd §456). It forks HERE
            // and nowhere else: `FeedFreshness` above is transport-only, and
            // producing a `FeedParser.Parsed` rather than a type of its own
            // leaves every stamp, heal and dedupe in `refresh` untouched.
            let parsed = kind == .telegram
                ? telegramParsed(data, entry: entry)
                : FeedParser.parse(data)
            return Fetched(entry: entry, resolvedFeedURL: resolvedFeedURL,
                           parsed: parsed, reached: true)
        case .notModified:
            return Fetched(entry: entry, resolvedFeedURL: resolvedFeedURL,
                           parsed: nil, reached: true)
        case .failed:
            // The resolution (if any) is still worth returning and
            // persisting even though this pass never reached the feed's
            // actual content (review 2026-07-13 — see the struct doc above).
            return resolvedFeedURL != nil
                ? Fetched(entry: entry, resolvedFeedURL: resolvedFeedURL, parsed: nil) : nil
        }
    }

    /// Fetches every followed feed for one bridge and lands new items as link
    /// things. Returns new count, 0 when up to date, nil when nothing was
    /// reachable (offline / every feed dead) — the setup screen words each.
    @MainActor
    static func refresh(_ kind: FeedFollowKind, context: ModelContext) async -> Int? {
        let store = kind.store
        guard !store.isEmpty, !running.contains(kind.source) else {
            return running.contains(kind.source) ? 0 : nil
        }
        running.insert(kind.source)
        defer { running.remove(kind.source) }

        // Before the fetch, not after: a follow this repairs must be fetched
        // through its corrected URL in the SAME pass, or the person sees one
        // more round of the wrong channel's uploads. Self-retiring — it reads
        // a flag and returns instantly once every follow has been verified
        // once.
        if kind == .youtube { await YouTubeFollowRepair.run(context: context) }

        var existing = IngestSupport.existingSourceRefs(context, source: kind.source)
        let backfill = ArtlessBackfill(context, source: kind.source)
        var added = 0
        // Retroactive authorHandle backfill (2026-07-18): items that landed
        // before feed-follow set `authorHandle` get their feed name patched in
        // as they're re-seen on refresh, so the feed's "top …" leaderboard fills
        // for a corpus that pre-dates the field. Lazy — the source's things are
        // fetched (and filtered to the handle-less ones) only on the first
        // already-landed ref, so a fresh feed with nothing to patch pays nothing.
        var handleless: [String: Thing]?
        var patchedHandle = false
        func patchHandle(_ ref: String, _ name: String) {
            guard !name.isEmpty else { return }
            if handleless == nil {
                let src = kind.source
                let all = (try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == src }))) ?? []
                handleless = Dictionary(all.filter { $0.authorHandle == nil }
                    .compactMap { t in t.sourceRef.map { ($0, t) } },
                    uniquingKeysWith: { first, _ in first })
            }
            if let thing = handleless?[ref], thing.authorHandle == nil {
                thing.authorHandle = name
                patchedHandle = true
            }
        }

        // YouTube retitle detection + Reddit postAuthor backfill (2026-07-28)
        // — both need the STORED row for an already-landed ref, lazily
        // fetched once per refresh the same way `handleless` above is.
        var byRef: [String: Thing]?
        var extraPatched = false
        func storedThing(_ ref: String) -> Thing? {
            if byRef == nil {
                let src = kind.source
                let all = (try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == src }))) ?? []
                byRef = Dictionary(all.compactMap { t in t.sourceRef.map { ($0, t) } },
                    uniquingKeysWith: { first, _ in first })
            }
            return byRef?[ref]
        }

        // Who wrote the item, per bridge — `Thing.postAuthor`, never
        // `authorHandle` (that is the FEED's identity: the subreddit, the
        // channel, the publication). Reddit's `/u/name` is always a person and
        // never the feed's own name, so it lands as it arrives; everywhere
        // else `FeedParser.author` drops an author that only repeats the feed
        // — a YouTube entry names its own channel there, and filing that as a
        // person would make a channel read as one.
        func itemAuthor(_ raw: String, feedName: String) -> String? {
            guard !raw.isEmpty else { return nil }
            guard kind != .reddit else {
                let name = FeedFollowFields.normalizedRedditAuthor(raw)
                return name.isEmpty ? nil : name
            }
            return FeedParser.author(raw, feedName: feedName)
        }

        // Concurrent fetch, then processed back in the entries' own order
        // (the same ref landing from two entries should resolve the same
        // way it always did — first-in-list wins). Capped at 4 in flight —
        // every entry under one bridge hits the SAME host (all Reddit, all
        // YouTube, …), and this file's own FeedFetch comment notes Reddit
        // already 429s a plain client under normal load; an uncapped burst
        // made that far more likely than the old serial pacing (review
        // 2026-07-13).
        let entries = store.entries
        let fetched = await IngestSupport.boundedGather(entries, maxConcurrent: 4) { entry in
            await fetchAndParse(entry, kind: kind)
        }

        var reachedAny = false
        for case let f? in fetched {
            let entry = f.entry
            if let resolvedFeedURL = f.resolvedFeedURL { store.setFeedURL(resolvedFeedURL, for: entry.id) }
            // A 304 counts as reached before the parse guard drops it — an
            // up-to-date sync must not read as an unreachable one.
            if f.reached { reachedAny = true }
            // Resolved but unreachable this pass, or answered 304 (see the
            // `Fetched` doc) — either way there is no body to land or heal
            // from; a resolution, if any, is saved above.
            guard let parsed = f.parsed else { continue }
            if entry.title.isEmpty, !parsed.title.isEmpty {
                store.setTitle(parsed.title, for: entry.id)
            }
            // The feed's own name, carried onto each item as `authorHandle` (the
            // same field RSS sets, RSSIngest.swift) — it names which channel /
            // publication / subreddit / show an item came from when more than one
            // is followed, and it's the grouping key the feed's "top …" bars rank
            // on (FeedLeaderboard). Feed-follow used to drop it, leaving every
            // YouTube video an indistinguishable `source:"YouTube"` row.
            let feedName = entry.title.isEmpty ? parsed.title : entry.title
            // Podcasts only: a show's own `<itunes:category>` is true of every
            // episode it publishes, and an episode almost never files itself
            // under anything. A blog's or a channel's channel-level categories
            // are far broader than any one post, so the other three take the
            // item's own or nothing.
            let showTags = kind == .podcasts ? parsed.categories : []
            // The feed's OWN mark — a publication's logo, a show's cover art,
            // a subreddit's icon (2026-08-14). RSS has led its rows with this
            // since the field existed and these four never stamped it, so four
            // rooms of somebody-else's-publication rows drew the app glyph
            // where the reading room draws the publisher.
            //
            // ONLY when the feed advertises one — deliberately NOT RSSIngest's
            // host-favicon fallback, which is right there and wrong here.
            // YouTube's `videos.xml` advertises no icon and names no channel
            // avatar anywhere, so the fallback resolves to
            // `youtube.com/favicon.ico`: the same YouTube logo for every
            // channel, i.e. the source glyph with extra steps — and it would
            // take the leading slot from the video's own thumbnail, which is
            // strictly more informative. A feed with no icon keeps exactly
            // what it has today.
            let feedIcon = IngestSupport.imageURL(parsed.iconURL)
            // Newest 15 per feed — the feed is a firehose; the corpus isn't.
            for item in parsed.items.prefix(15) {
                let stableKey = item.guid.isEmpty ? item.link : item.guid
                guard !stableKey.isEmpty else { continue }
                let ref = "\(kind.refPrefix):\(stableKey)"
                // A podcast episode often carries only a <guid> and its audio
                // enclosure — no <link> at all — and landed with an empty
                // `content`, i.e. a row nothing could open. The audio file IS
                // the episode, so it stands in (2026-08-06).
                let openURL = item.link.isEmpty ? item.mediaURL : item.link
                let itemTags = item.categories.isEmpty ? showTags : item.categories

                if existing.contains(ref) {
                    backfill.patch(ref, image: item.imageURL,
                                   face: feedIcon, handle: feedName)
                    patchHandle(ref, feedName)
                    if kind == .youtube, let thing = storedThing(ref) {
                        let decoded = IngestSupport.decodeHTMLEntities(item.title)
                        if !decoded.isEmpty, !thing.title.isEmpty, thing.title != decoded {
                            thing.title = decoded
                            extraPatched = true
                        }
                    }
                    // Rows that landed before the fields below existed heal in
                    // place, within the feed's window — the bar the image and
                    // handle backfills above already set. Reddit's postAuthor
                    // backfill (2026-07-28) is the same line, now that every
                    // bridge lands one.
                    if let thing = storedThing(ref) {
                        if thing.content.isEmpty, !openURL.isEmpty {
                            thing.content = openURL; extraPatched = true
                        }
                        // Never on Reddit — see the insert branch below: that
                        // kind's `externalLink` is the post's own outbound
                        // link, and a later pass reads it to match against the
                        // corpus. An enclosure URL there is a media file being
                        // asked "is this something you saved?", forever.
                        if kind != .reddit, (thing.externalLink ?? "").isEmpty, !item.mediaURL.isEmpty {
                            thing.externalLink = item.mediaURL; extraPatched = true
                        }
                        if thing.postAuthor == nil,
                           let author = itemAuthor(item.author, feedName: feedName) {
                            thing.postAuthor = author; extraPatched = true
                        }
                        // Appended, never assigned — a row's other tags (its
                        // type tag, the `Shorts` one `YouTubeShorts` writes, a
                        // project's) are not this feed's to drop.
                        for tag in itemTags
                        where !thing.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                            thing.tags.append(tag); extraPatched = true
                        }
                    }
                    continue
                }
                guard !item.title.isEmpty else { continue }
                let thing = Thing(
                    kind: .link,
                    title: IngestSupport.decodeHTMLEntities(item.title),
                    content: openURL,
                    source: kind.source,
                    capturedAt: item.date ?? .now,
                    tags: itemTags,
                    sourceRef: ref
                )
                // A podcast episode's own art, when it publishes one — the
                // parser keeps it apart from the show's logo (see the
                // `itunes:image` case), so a per-episode picture reaches the
                // row without ever standing in as the publisher's mark.
                thing.previewImageURL = IngestSupport.imageURL(item.imageURL)
                // Reddit's selftext, a Substack lede, a podcast's show notes —
                // the feed's own `<description>`/`<summary>`, kept by the
                // parser since 2026-07-22. A YouTube description rides
                // `<media:description>`, which that pass never matched and
                // 2026-08-06 added, so a video landed summary-less until then.
                if !item.summary.isEmpty { thing.summary = item.summary }
                if !feedName.isEmpty { thing.authorHandle = feedName }
                thing.authorAvatarURL = feedIcon
                // Who actually wrote it (`itemAuthor`) — distinct from
                // `authorHandle`, which is the feed's own identity.
                if let author = itemAuthor(item.author, feedName: feedName) {
                    thing.postAuthor = author
                }
                // Reddit-only (2026-07-28): the post's own first outbound
                // link. Nothing reads it today — the corpus-join pass that did
                // went with the moment bus (2026-08-19) — but it is what a
                // Reddit row's door would be built from, and it costs one
                // already-parsed field to keep landing it.
                if kind == .reddit {
                    thing.externalLink = FeedFollowFields.firstExternalLink(item.links)
                }
                // The episode's own audio, when the feed declares one. Kept
                // whether or not it stood in for `content` above: the row's
                // bytes are its link, this is the media file itself.
                //
                // `else if`, NOT a second assignment — one field, two owners.
                // Reddit items carry enclosures (any image or video post), so
                // an unconditional write here CLOBBERED the outbound link set
                // one line above — a silent regression the moment enclosures
                // started being read (2026-08-06).
                else if !item.mediaURL.isEmpty { thing.externalLink = item.mediaURL }
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 || backfill.any || patchedHandle || extraPatched { context.saveHonestly() }
        return reachedAny ? added : nil
    }
}
