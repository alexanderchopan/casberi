import Foundation

/// **WHAT YOU FOLLOW, LISTED WHERE YOU READ IT (prd §1118).** Reading,
/// Media and Work each get one tile that lists what the person chose to
/// follow there — feeds, channels, shows, boards, repos, packages — in the
/// Subscriptions anatomy (§1117): a box that counts what arrived, the verb
/// first, then one row per thing followed. The account page that used to
/// hold the list keeps import, export and disconnect.
///
/// This is the pure half: what a followed thing is, which landed rows are
/// its, and the figures a row and the box state. The stores stay the truth
/// (`RSSStore`, `FeedFollowStore`, `PinterestStore`, `PackageStore`, …);
/// `FollowingReading` reads them and the corpus and hands both here.
///
/// **A row is attributed by what the ingest stamped, never by a guess.** A
/// feed's rows carry its name in `authorHandle` (RSS and the feed-follow
/// seats write it on every row); a watch's rows carry its key in
/// `sourceRef`. A followed thing nothing landed for yet still lists, with
/// nothing counted.
///
/// Foundation-only, so `scripts/following-selftest.sh` compiles it whole.
enum Following {

    /// The three rooms that hold a list of what you follow.
    enum Room: String, CaseIterable, Sendable {
        case reading, media, work
    }

    /// One thing followed, as its store holds it.
    struct Followed: Equatable, Sendable {
        /// Stable across launches: the seat and the store's own key.
        var id: String
        var name: String
        /// The app it is followed through (`Thing.source` of its rows).
        var seat: String
        /// Its site, for the doors to its mail and its plan (§1113's rule:
        /// a registrable domain, never a name).
        var site: String?
        /// The `authorHandle` values its rows carry (a feed's name, learned
        /// and given). Matched without case.
        var handles: [String] = []
        /// The `sourceRef` prefixes its rows carry (a watch's key).
        var refPrefixes: [String] = []
        /// A piece of the address its rows open (a GitHub repo's releases
        /// carry only a release id in their ref, never the repo).
        var linkFragments: [String] = []
        /// What a remove hands back to the store (an RSS feed's address, a
        /// Substack's input, a package's name). nil when the list is read
        /// from an account and cannot be edited here (Twitch's follows).
        var removeKey: String?
    }

    /// One landed row, as far as this reading needs it.
    struct Post: Equatable, Sendable {
        var source: String
        var handle: String?
        var ref: String?
        var link: String? = nil
        /// The row's face (a feed's mark, a channel's avatar).
        var avatar: String? = nil
        var at: Date
    }

    struct Item: Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        var seat: String
        var site: String?
        /// Every row of its the reading saw.
        var count: Int
        /// How many arrived in the last thirty days — the row's figure.
        var lastMonth: Int
        /// The median gap between rows, in days; nil under three rows.
        var cadenceDays: Double?
        var last: Date?
        var since: Date?
        /// When each row arrived, newest first: the days the box's calendar
        /// puts its face on.
        var arrivals: [Date]
        /// The face its newest row wears.
        var avatar: String? = nil
        var removeKey: String?
        var removable: Bool { removeKey != nil }
    }

    /// The window the row and the box count ("8 posts" means thirty days).
    static let windowDays = 30.0

    /// Which followed thing a row is, if any: the first whose seat is the
    /// row's source and whose handle or ref prefix the row carries.
    static func owner(of post: Post, in followed: [Followed]) -> Int? {
        let handle = post.handle?.trimmingCharacters(in: .whitespaces).lowercased()
        let ref = post.ref?.lowercased()
        let link = post.link?.lowercased()
        for (index, f) in followed.enumerated() where f.seat == post.source {
            if let handle, !handle.isEmpty,
               f.handles.contains(where: { $0.lowercased() == handle }) { return index }
            if let ref, f.refPrefixes.contains(where: { ref.hasPrefix($0.lowercased()) }) { return index }
            if let link, f.linkFragments.contains(where: { link.contains($0.lowercased()) }) { return index }
        }
        return nil
    }

    /// Every followed thing with its figures, the busiest this month first,
    /// then by name. Nothing is dropped: a follow nothing landed for lists
    /// with zero.
    static func compose(_ followed: [Followed], posts: [Post], now: Date = .now) -> [Item] {
        var dates = Array(repeating: [Date](), count: followed.count)
        var faces = Array(repeating: (at: Date.distantPast, url: String?.none), count: followed.count)
        for post in posts {
            guard let index = owner(of: post, in: followed) else { continue }
            dates[index].append(post.at)
            if let url = post.avatar, !url.isEmpty, post.at > faces[index].at { faces[index] = (post.at, url) }
        }
        let monthStart = now.addingTimeInterval(-windowDays * 86_400)
        let items = followed.enumerated().map { index, f -> Item in
            let sorted = dates[index].sorted(by: >)
            return Item(id: f.id, name: f.name, seat: f.seat, site: f.site,
                        count: sorted.count,
                        lastMonth: sorted.filter { $0 >= monthStart && $0 <= now }.count,
                        cadenceDays: cadence(sorted), last: sorted.first, since: sorted.last,
                        arrivals: sorted, avatar: faces[index].url, removeKey: f.removeKey)
        }
        return items.sorted {
            if $0.lastMonth != $1.lastMonth { return $0.lastMonth > $1.lastMonth }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// The median gap between arrivals, in days, from three arrivals up:
    /// two is an accident, not a cadence.
    static func cadence(_ newestFirst: [Date]) -> Double? {
        guard newestFirst.count >= 3 else { return nil }
        let gaps = zip(newestFirst, newestFirst.dropFirst())
            .map { $0.0.timeIntervalSince($0.1) / 86_400 }
            .sorted()
        let mid = gaps.count / 2
        return gaps.count % 2 == 1 ? gaps[mid] : (gaps[mid - 1] + gaps[mid]) / 2
    }

    /// The mailing list a followed site also writes from (§1113's rule):
    /// a sender at the site's registrable domain, never a mailbox provider,
    /// never by name. The lists come loudest first, so the first is the one.
    static func list(site: String?, lists: [ServiceIdentity.List]) -> String? {
        guard let domain = ServiceIdentity.registrable(site) else { return nil }
        return lists.first { list in
            guard let address = list.address, address.contains("@"),
                  let sender = ServiceIdentity.registrable(address),
                  !ServiceIdentity.mailboxDomains.contains(sender) else { return false }
            return sender == domain
        }?.id
    }

    /// The paid plan a followed site is, if exactly one is: the plan whose
    /// site the person gave is this domain, else the one whose name is the
    /// domain's own label ("Stratechery" for stratechery.com). A feed's
    /// title is the publisher's word and never matched. Two answers are none.
    static func plan(site: String?, plans: [ServiceIdentity.Plan]) -> String? {
        guard let domain = ServiceIdentity.registrable(site) else { return nil }
        let bySite = plans.filter { ServiceIdentity.registrable($0.site) == domain }
        if bySite.count > 1 { return nil }
        if let one = bySite.first { return one.id }
        let label = ServiceIdentity.compact(ServiceIdentity.label(ofDomain: domain))
        guard label.count >= 4 else { return nil }
        let byName = plans.filter { ServiceIdentity.compact($0.name) == label }
        return byName.count == 1 ? byName[0].id : nil
    }

    /// The site a feed address names: its host, without `www.`. A YouTube
    /// or podcast feed is the platform's, so it names no site (§1113: a
    /// shared domain names nothing).
    static func site(ofFeed raw: String) -> String? {
        guard let host = URL(string: raw.trimmingCharacters(in: .whitespaces))?.host?.lowercased()
        else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return sharedHosts.contains(where: { bare == $0 || bare.hasSuffix("." + $0) }) ? nil : bare
    }

    /// Hosts that serve many publishers' feeds, so a feed there is not that
    /// host's: matching on them would join every publisher to one plan.
    static let sharedHosts: [String] = [
        "youtube.com", "apple.com", "feedburner.com", "feeds.feedburner.com",
        "medium.com", "substack.com", "blogspot.com", "wordpress.com", "ghost.io",
        "anchor.fm", "libsyn.com", "simplecast.com", "megaphone.fm", "transistor.fm",
        "buzzsprout.com", "podbean.com", "soundcloud.com", "pinterest.com", "t.me",
        "github.com", "huggingface.co", "npmjs.com", "pypi.org",
    ]
}
