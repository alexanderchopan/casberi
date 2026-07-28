import Foundation
import SwiftData

/// Delight for the feed-follow bridges (2026-07-28) — YouTube and Reddit,
/// the sibling of `SocialMoments` for sources that aren't "social" threads
/// (no thread reader, no profile card — `SocialThread.isSocial` excludes
/// both) but still carry a moment worth surfacing. Every check here is a
/// read-only pass over what `FeedFollowIngest` already landed, or a small
/// bit of persisted state (UserDefaults) alongside it — nothing here
/// changes what lands, only what gets announced.
@MainActor
enum FeedFollowMoments {
    /// A gap this long or more, ending just now, reads as "was away" — same
    /// bar `SocialMoments` uses for a watched account's quiet return.
    private static let quietDays: Double = 30
    /// A thing older than this when a pass runs is a re-scan, not a fresh
    /// arrival — same self-throttle every moment in this app relies on.
    private static let freshWindow: TimeInterval = 600

    // MARK: - Quiet return (a followed channel/person going dark 30+ days)

    /// Same shape as `SocialMoments.checkReturns`, generalized over a
    /// followed feed-follow entry rather than a network's watched-account
    /// list — the landed thing's `authorHandle` already carries the entry's
    /// learned feed name (`FeedFollowIngest` sets it), so there's no
    /// separate roster to resolve.
    static func checkReturns(_ kind: FeedFollowKind, context: ModelContext) {
        let names = kind.store.entries.map(\.displayName).filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        let source = kind.source
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        guard let things = try? context.fetch(descriptor) else { return }
        let watched = Set(names)
        var byName: [String: [Thing]] = [:]
        for thing in things {
            guard let name = thing.authorHandle, watched.contains(name) else { continue }
            byName[name, default: []].append(thing)
        }
        let verb = kind == .youtube ? "uploaded" : "posted"
        for (name, items) in byName {
            let sorted = items.sorted { $0.capturedAt > $1.capturedAt }
            guard sorted.count >= 2 else { continue }
            let newest = sorted[0]
            guard newest.capturedAt.timeIntervalSinceNow > -freshWindow else { continue }
            let gapDays = sorted[1].capturedAt.distance(to: newest.capturedAt) / 86400
            guard gapDays >= quietDays else { continue }
            SourceMoments.shared.fire(
                String(localized: "\(name) \(verb) again after \(Int(gapDays)) days"), source: kind.source)
        }
    }

    // MARK: - YouTube: a video's views doubling since we last looked

    /// Self-relative on purpose, not compared across a channel's other
    /// videos — a video's OWN first sighting just seeds the mark (nothing
    /// to compare against yet, so a channel's very first sync can't flood
    /// this), and every check after only fires on a genuine doubling, which
    /// a counter re-checked every refresh can't trip on nearly every pass
    /// the way a bare "any increase" mark would (views only ever climb).
    static func checkYouTubeBreakout(ref: String, title: String, channel: String, views: Int) {
        guard views > 0 else { return }
        let key = "moment.youtube.views.\(ref)"
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else {
            defaults.set(views, forKey: key)
            return
        }
        let prev = defaults.integer(forKey: key)
        guard prev > 0, views >= prev * 2 else {
            if views > prev { defaults.set(views, forKey: key) }
            return
        }
        defaults.set(views, forKey: key)
        SourceMoments.shared.fire(
            String(localized: "\u{201c}\(title)\u{201d} on \(channel) just doubled its views"),
            source: "YouTube")
    }

    // MARK: - YouTube: a creator quietly retitling an already-landed upload

    /// Creators A/B test titles constantly — nobody else surfaces this, and
    /// it costs nothing (the diff is against a title already in hand from
    /// the same fetch that re-checks views). Called on a genuine text
    /// change only; the caller already guards against a blank/unchanged
    /// title.
    static func fireRetitle(from oldTitle: String, to newTitle: String, channel: String) {
        SourceMoments.shared.fire(
            String(localized: "\(channel) retitled a video \u{201c}\(newTitle)\u{201d} (was \u{201c}\(oldTitle)\u{201d})"),
            source: "YouTube")
    }

    // MARK: - Reddit: a post linking something you already saved elsewhere

    /// The crossing only this app can see: a subreddit post's own outbound
    /// link already sitting in the corpus from a DIFFERENT source. A pure
    /// corpus join, no extra network call — mirrors
    /// `SocialMoments.checkSlackCrossings` exactly, down to reading a field
    /// (`externalLink`) captured at landing rather than re-parsing HTML
    /// here. NEWS ONLY: only a post that landed within `freshWindow` is
    /// checked, so a rescan of the same listing can't refire it.
    static func checkRedditLinkCrossings(context: ModelContext) {
        let source = "Reddit"
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        guard let posts = try? context.fetch(descriptor) else { return }
        let fresh = posts.filter { $0.capturedAt.timeIntervalSinceNow > -freshWindow && $0.externalLink != nil }
        guard !fresh.isEmpty else { return }

        let othersDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source != source })
        guard let others = try? context.fetch(othersDescriptor) else { return }
        var savedByURL: [String: Thing] = [:]
        for candidate in others {
            guard let key = normalizedURL(candidate.content) else { continue }
            savedByURL[key] = candidate
        }
        guard !savedByURL.isEmpty else { return }

        for post in fresh {
            guard let link = post.externalLink, let key = normalizedURL(link),
                  let saved = savedByURL[key], saved.capturedAt < post.capturedAt else { continue }
            let feed = post.authorHandle ?? "Reddit"
            SourceMoments.shared.fire(
                String(localized: "\(feed) is talking about \u{201c}\(saved.title)\u{201d} — you already saved it"),
                source: "Reddit")
        }
    }

    // MARK: - Reddit: the same poster showing up across subreddits you follow

    /// The join only your specific follow set can see: one person posting
    /// in two DIFFERENT subreddits you both follow — `authorHandle` is the
    /// feed identity (the subreddit), `postAuthor` the actual `/u/name`.
    /// Only fires the FIRST time a given author is discovered spanning 2+
    /// followed subreddits (a persisted flag, not a fresh-window check) —
    /// re-stating the same pairing every time they post again would be
    /// noise, not news.
    static func checkRedditCrossPosters(context: ModelContext) {
        let source = "Reddit"
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        guard let things = try? context.fetch(descriptor) else { return }
        var subsByAuthor: [String: Set<String>] = [:]
        var hasFreshPost: Set<String> = []
        for thing in things {
            guard let author = thing.postAuthor, !author.isEmpty,
                  let feed = thing.authorHandle, !feed.isEmpty else { continue }
            subsByAuthor[author, default: []].insert(feed)
            if thing.capturedAt.timeIntervalSinceNow > -freshWindow { hasFreshPost.insert(author) }
        }
        for (author, feeds) in subsByAuthor where feeds.count >= 2 {
            guard hasFreshPost.contains(author) else { continue }
            let key = "moment.reddit.crosspost.\(author)"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }
            UserDefaults.standard.set(true, forKey: key)
            let names = feeds.sorted().joined(separator: " and ")
            SourceMoments.shared.fire(
                String(localized: "u/\(author) posts in both \(names) — you follow both"), source: "Reddit")
        }
    }

    /// Reddit's Atom author name arrives as "/u/name" — the bare name reads
    /// better in a sentence.
    static func normalizedRedditAuthor(_ raw: String) -> String {
        var a = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/u/", "u/"] where a.hasPrefix(prefix) {
            a.removeFirst(prefix.count)
            break
        }
        return a
    }

    /// The first link in `links` that doesn't point back at reddit.com/
    /// redd.it — what actually made the post worth crossing, decoded (feed
    /// hrefs arrive HTML-escaped).
    static func firstExternalLink(_ links: [String]) -> String? {
        for raw in links {
            let link = IngestSupport.decodeHTMLEntities(raw)
            guard let host = URL(string: link)?.host?.lowercased(),
                  !host.contains("reddit.com"), !host.contains("redd.it") else { continue }
            return link
        }
        return nil
    }

    /// Loose equality for a link across sources — same rule as
    /// `SocialMoments.normalizedURL` (strips scheme, a leading "www.", a
    /// trailing slash); duplicated rather than shared since the two moments
    /// files are otherwise fully independent of each other.
    private static func normalizedURL(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for prefix in ["https://www.", "http://www.", "https://", "http://"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : s.lowercased()
    }
}
