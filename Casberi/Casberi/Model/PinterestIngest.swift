import Foundation
import Observation
import SwiftData

/// The Pinterest bridge (2026-07-09) — handle-only, like Bluesky: Pinterest
/// still publishes a public RSS feed per user (pinterest.com/<name>/feed.rss),
/// so your recent public pins land as link things with just a username. No
/// OAuth, no developer-app review, no token — the official API's
/// confidential-client dance doesn't fit a serverless iPhone, and the feed
/// carries the same content for a personal corpus. Public boards only, by
/// construction.
///
/// **It FOLLOWS since prd §819 (2026-09-18).** A beta tester: "I wasn't
/// expecting my Pinterest tab to be only about my previous pins and not about
/// pins I'd love to see". Recommendations sit behind Pinterest's sign-in, but
/// every public BOARD has the same feed (`pinterest.com/<name>/<board>.rss`,
/// measured 2026-09-18 on natgeo/travel: 200, 25 items, the user feed's shape),
/// so the seat is a list now: yours first, then the boards and people you
/// follow. A board list per person is NOT keyless (the boards resource answers
/// 403), so a board is followed by pasting its link.
///
/// A follow is `name` (that person's public pins) or `name/board`. Every row
/// carries the follow it arrived through in `authorHandle`, which is what the
/// room's face rail scopes on and what unfollowing prunes by (§286).
@Observable
final class PinterestStore {
    static let shared = PinterestStore()
    /// The one username the seat held before §819 — migrated into `follows`
    /// as `mine` on first read, then removed.
    private static let legacyKey = "pinterest.username"
    private static let followsKey = "pinterest.follows"
    private static let mineKey = "pinterest.mine"
    private static let metaKey = "pinterest.meta"

    /// What a follow's own feed told us: the board's title and its newest
    /// pin's picture, which is the board's face on the room's rail.
    struct Meta: Codable, Equatable {
        var title: String
        var cover: String?
    }

    /// Everything followed, in the order added — yours first when you have one.
    private(set) var follows: [String] {
        didSet { UserDefaults.standard.set(follows, forKey: Self.followsKey) }
    }

    /// The follow that is YOU. The first plain username added to an empty seat
    /// is yours (that is what the seat asked for before §819); a board is never.
    private(set) var mine: String? {
        didSet { UserDefaults.standard.set(mine, forKey: Self.mineKey) }
    }

    private(set) var meta: [String: Meta] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(meta), forKey: Self.metaKey) }
    }

    private init() {
        let d = UserDefaults.standard
        var follows = d.stringArray(forKey: Self.followsKey) ?? []
        var mine = d.string(forKey: Self.mineKey)
        if let legacy = d.string(forKey: Self.legacyKey), !legacy.isEmpty {
            if !follows.contains(legacy) { follows.insert(legacy, at: 0) }
            mine = mine ?? legacy
            d.set(follows, forKey: Self.followsKey)
            d.set(mine, forKey: Self.mineKey)
            d.removeObject(forKey: Self.legacyKey)
        }
        self.follows = follows
        self.mine = mine
        self.meta = (d.data(forKey: Self.metaKey))
            .flatMap { try? JSONDecoder().decode([String: Meta].self, from: $0) } ?? [:]
    }

    var connected: Bool { !follows.isEmpty }

    static func isBoard(_ follow: String) -> Bool { follow.contains("/") }

    /// The feed a follow reads.
    static func feedURL(_ follow: String) -> URL? {
        URL(string: isBoard(follow)
            ? "https://www.pinterest.com/\(follow).rss"
            : "https://www.pinterest.com/\(follow)/feed.rss")
    }

    /// How a follow reads in a list: a board by its own title and its owner
    /// ("Travel · natgeo"), a person by name.
    func display(_ follow: String) -> String {
        guard Self.isBoard(follow) else { return follow }
        let owner = follow.split(separator: "/").first.map(String.init) ?? follow
        let title = meta[follow]?.title ?? follow.split(separator: "/").last.map(String.init) ?? follow
        return "\(title) · \(owner)"
    }

    /// Adds a normalized follow; nothing for a link that names no person or
    /// board (a pin, the home page).
    func add(_ raw: String) {
        let f = Self.normalize(raw)
        guard !f.isEmpty, !follows.contains(f) else { return }
        if follows.isEmpty, mine == nil, !Self.isBoard(f) { mine = f }
        follows.append(f)
    }

    func remove(_ follow: String) {
        follows.removeAll { $0 == follow }
        meta[follow] = nil
        if mine == follow { mine = nil }
    }

    func removeAll() {
        follows = []
        mine = nil
        meta = [:]
    }

    func learn(_ follow: String, _ m: Meta) {
        if meta[follow] != m { meta[follow] = m }
    }

    /// Pinterest's own Share button hands out `pin.it/<code>`, which redirects
    /// to the board or profile it names. Follow it and hand back the landing
    /// URL; anything else comes back untouched. UNMEASURED against a real
    /// short link (none was to hand, 2026-09-18) — a link that lands anywhere
    /// but a board or profile normalizes to nothing, so it cannot add a wrong
    /// follow, only no follow.
    static func resolveShortLink(_ raw: String) async -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.lowercased().contains("pin.it/"),
              let url = URL(string: t.hasPrefix("http") ? t : "https://\(t)")
        else { return raw }
        NetworkLedger.shared.record(url)
        guard let (_, response) = try? await URLSession.shared.data(from: url),
              let landed = response.url else { return raw }
        return landed.absoluteString
    }

    /// Paths Pinterest uses for things that are not a person or a board.
    private static let reserved: Set<String> = [
        "pin", "search", "ideas", "today", "business", "settings", "_saved",
        "_created", "_profile", "explore", "categories", "topics",
    ]

    /// "pinterest.com/name", "@name", "name/board", a board's full link (with
    /// its trailing slash or `.rss`) and a country host (`uk.pinterest.com`)
    /// all normalize; a pin link or a reserved path answers "".
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://"] where s.hasPrefix(junk) { s.removeFirst(junk.count) }
        // A share-sheet short link names nothing until it is followed
        // (`resolveShortLink`); read raw it would pass for "pin.it/<board>".
        if s.hasPrefix("pin.it/") { return "" }
        if let host = s.split(separator: "/", maxSplits: 1).first,
           host.hasSuffix("pinterest.com") || host.contains("pinterest.") {
            s = String(s.dropFirst(host.count))
        }
        if let q = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<q]) }
        if s.hasPrefix("@") { s.removeFirst() }
        if s.hasSuffix(".rss") { s.removeLast(4) }
        var parts = s.split(separator: "/").map(String.init)
        if parts.last == "feed" { parts.removeLast() }
        guard let name = parts.first, !reserved.contains(name) else { return "" }
        guard parts.count > 1, !reserved.contains(parts[1]) else { return name }
        return "\(name)/\(parts[1])"
    }
}

enum PinterestIngest {

    @MainActor private static var running = false

    /// Reads every follow's public feed and lands new pins as link things,
    /// each stamped with the follow it came through. Returns the new count, or
    /// nil when NO feed could be read (a wrong name answers an HTML page the
    /// parser yields nothing from) — one dead board does not fail the seat.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = PinterestStore.shared
        let follows = store.follows
        guard !follows.isEmpty, !running else { return follows.isEmpty ? nil : 0 }
        running = true
        defer { running = false }

        let existing = IngestSupport.thingsByRef(context, source: "Pinterest")
        let backfill = ArtlessBackfill(context, source: "Pinterest")
        var seen = Set(existing.keys)
        var added = 0
        var healed = false
        var anyRead = false

        for follow in follows {
            guard let url = PinterestStore.feedURL(follow) else { continue }
            NetworkLedger.shared.record(url)
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            let parsed = FeedParser.parse(data)
            guard !parsed.items.isEmpty || !parsed.title.isEmpty else { continue }
            anyRead = true
            // A person's feed is titled "Pinterest", so only a board's title
            // is worth keeping.
            store.learn(follow, .init(
                title: PinterestStore.isBoard(follow) && !parsed.title.isEmpty ? parsed.title : follow,
                cover: IngestSupport.imageURL(parsed.items.first?.imageURL)))

            for item in parsed.items.prefix(25) {
                guard !item.link.isEmpty else { continue }
                let ref = "pinterest:\(item.guid.isEmpty ? item.link : item.guid)"
                if let thing = existing[ref] {
                    backfill.patch(ref, image: item.imageURL)
                    // Rows landed before §819 carry no follow; the first feed
                    // that still holds one claims it.
                    if thing.authorHandle == nil { thing.authorHandle = follow; healed = true }
                    continue
                }
                // One pin on two followed boards lands once.
                guard seen.insert(ref).inserted else { continue }
                let thing = Thing(
                    kind: .link,
                    // Pins are often untitled — an empty row title reads broken.
                    title: item.title.isEmpty ? "Pin" : item.title,
                    content: item.link,
                    source: "Pinterest",
                    capturedAt: item.date ?? .now,
                    sourceRef: ref
                )
                thing.authorHandle = follow
                // The pin's image, so the feed row leads with a thumbnail (the
                // whole point of a Pinterest feed) instead of the generic glyph.
                thing.previewImageURL = IngestSupport.imageURL(item.imageURL)
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 || healed || backfill.any { context.saveHonestly() }
        return anyRead ? added : nil
    }
}
