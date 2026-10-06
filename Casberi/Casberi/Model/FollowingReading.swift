import Foundation
import Observation
import SwiftData

/// **THE READING HALF OF `Following` (prd §1118).** Reads each room's
/// stores and the rows they landed, and hands both to `Following.compose`.
/// From a `.task`, never a body (prd §628); a sheet and a row read
/// `items(for:)`, which is plain memory.
///
/// The stores stay the truth: following and stopping write the store first
/// and re-read here second, as `GitHubWatchStore` does.
@Observable
@MainActor
final class FollowingReading {
    static let shared = FollowingReading()

    private(set) var items: [Following.Room: [Following.Item]] = [:]

    /// The service's other pages, by a followed thing's id (§1113 widened to
    /// feeds): the list it also writes from in Day, the plan in the Wallet.
    struct Link: Equatable {
        var planID: String?
        var listID: String?
    }
    private(set) var links: [String: Link] = [:]
    /// The rooms read at least once, so a box can tell "none" from "not yet".
    private(set) var read: Set<Following.Room> = []

    private init() {}

    func items(for room: Following.Room) -> [Following.Item] { items[room] ?? [] }

    /// What you follow that is this plan or this list, and the room it is
    /// listed in: the door back from the Wallet's and Day's sheets.
    func followed(planID: String? = nil, listID: String? = nil) -> (Following.Item, Following.Room)? {
        for room in Following.Room.allCases {
            for item in items(for: room) {
                let link = links[item.id]
                if let planID, link?.planID == planID { return (item, room) }
                if let listID, link?.listID == listID { return (item, room) }
            }
        }
        return nil
    }

    func item(_ id: String) -> Following.Item? {
        for list in items.values { if let item = list.first(where: { $0.id == id }) { return item } }
        return nil
    }

    /// The room whose Track tray follows through this app, for an app that
    /// needs nothing but a name to start (prd §1119): no account, no key, so
    /// its first follow IS its connect. Twitch and GitHub sign in first.
    nonisolated static func trackRoom(forSeat seat: String) -> Following.Room? {
        switch seat {
        case "RSS", "Substack": .reading
        case "YouTube", "Podcasts", "Pinterest": .media
        case PackageRegistry.npm.displayName, PackageRegistry.pypi.displayName, "Hugging Face", "Radicle": .work
        default: nil
        }
    }

    /// The apps each room reads what you follow from.
    nonisolated static func seats(_ room: Following.Room) -> [String] {
        switch room {
        case .reading: ["RSS", "Substack"]
        case .media:   ["YouTube", "Podcasts", "Pinterest", "Twitch"]
        case .work:    ["GitHub", PackageRegistry.npm.displayName, PackageRegistry.pypi.displayName,
                        "Hugging Face", "Radicle"]
        }
    }

    /// Re-read one room.
    func refresh(_ room: Following.Room, context: ModelContext) {
        let seats = Self.seats(room)
        var posts = Self.posts(seats: seats, context: context)
        // The demo pours rows, never follow lists (`DemoSeedAll`): what it
        // follows is what landed, each feed by the name its rows carry, and
        // nothing in it can be stopped.
        var followed = DemoMode.isActive ? Self.landed(posts, room: room, context: context)
            : Self.followed(room, context: context)
        if room == .media, !DemoMode.isActive {
            // Twitch's follows are read from the person's account, never kept
            // here: who went live is who they follow. Listed, not editable.
            let names = Set(posts.filter { $0.source == "Twitch" }.compactMap(\.handle).filter { !$0.isEmpty })
            followed += names.sorted().map {
                Following.Followed(id: "twitch:\($0.lowercased())", name: $0, seat: "Twitch", handles: [$0])
            }
        }
        if room == .work {
            // A GitHub row is a watch's by the rule the account page already
            // counts with (`GitHubRowTag.matches`); the watch row itself is
            // not news about the watch.
            let scopes = followed.filter { $0.seat == "GitHub" }.map(\.id)
            posts = posts.compactMap { post in
                guard post.source == "GitHub" else { return post }
                guard let ref = post.ref, !ref.hasPrefix("gh:watchrepo:"),
                      GitHubLinks.personLogin(fromRef: ref) == nil else { return nil }
                guard let scope = scopes.first(where: {
                    GitHubRowTag.matches(scope: $0, ref: ref, url: post.link ?? "", authorHandle: post.handle)
                }) else { return nil }
                var owned = post
                owned.handle = "scope:\(scope)"
                return owned
            }
        }
        let next = Following.compose(followed, posts: posts)
        if items[room] != next { items[room] = next }
        // Joined over the two Subscriptions readings as last read
        // (`ServiceLinks.refresh` reads them first, from the box's task).
        let plans = SubscriptionsReading.shared.items
            .map { ServiceIdentity.Plan(id: $0.id, name: $0.name, site: $0.site) }
        let lists = MailSubscriptionsReading.shared.items
            .map { ServiceIdentity.List(id: $0.id, name: $0.name, address: $0.address) }
        var nextLinks = links
        for item in next {
            let link = Link(planID: Following.plan(site: item.site, plans: plans),
                            listID: Following.list(site: item.site, lists: lists))
            nextLinks[item.id] = link.planID == nil && link.listID == nil ? nil : link
        }
        if nextLinks != links { links = nextLinks }
        read.insert(room)
        #if DEBUG
        for item in next {
            NSLog("[Casberi] following| %@ | %@ | %@ | %d this month | %d seen", room.rawValue,
                  item.seat, item.name, item.lastMonth, item.count)
        }
        #endif
    }

    /// Stop following, the way each app's own page does it: the store
    /// first, its rows with it where that page prunes them (prd §286), then
    /// every room that reads the app re-read.
    func stop(_ item: Following.Item, context: ModelContext) {
        guard let key = item.removeKey else { return }
        switch item.seat {
        case "RSS":
            let rss = RSSStore.shared
            if let index = rss.feeds.firstIndex(where: { $0.url.caseInsensitiveCompare(key) == .orderedSame }) {
                rss.remove(at: IndexSet(integer: index))
            }
        case "Hugging Face":
            HuggingFaceStore.shared.remove(key)
            FollowPrune.remove(source: "Hugging Face", context: context) {
                $0.authorHandle?.caseInsensitiveCompare(key) == .orderedSame
            }
        case "Radicle":
            RadicleStore.shared.remove(key)
            FollowPrune.remove(source: "Radicle", context: context) {
                $0.sourceRef?.contains(":\(key):") == true
            }
        case "GitHub":
            // The watch IS its row (`GitHubRepoWatch`): deleting it unwatches.
            let doomed = (try? context.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate { $0.sourceRef == key }))) ?? []
            SpotlightIndex.remove(ids: doomed.map(\.id))
            for thing in doomed { context.delete(thing) }
            context.saveHonestly()
            GitHubWatchStore.shared.refresh(context: context)
        default:
            if let bridge = HandleBridge(rawValue: item.seat) {
                bridge.removeName(key, context: context)
            } else if let registry = PackageRegistry.allCases.first(where: { $0.displayName == item.seat }) {
                PackageStore.shared.remove(registry, key)
                let needle = key.lowercased()
                FollowPrune.remove(source: registry.displayName, context: context) { thing in
                    PackageShape.name(fromRef: thing.sourceRef, registry: registry) == needle
                }
            }
        }
        for room in Following.Room.allCases where Self.seats(room).contains(item.seat) {
            refresh(room, context: context)
        }
    }

    /// Whether stopping takes what already arrived with it (prd §286): every
    /// app's own page prunes but RSS's, and GitHub's watch is its one row.
    nonisolated static func prunes(_ seat: String) -> Bool { seat != "RSS" && seat != "GitHub" }

    // MARK: - The stores

    private static func followed(_ room: Following.Room, context: ModelContext) -> [Following.Followed] {
        switch room {
        case .reading:
            let feeds = RSSStore.shared.feeds.map { feed in
                Following.Followed(id: "rss:\(feed.url.lowercased())", name: feed.displayName, seat: "RSS",
                                   site: Following.site(ofFeed: feed.url),
                                   handles: Self.names(feed.title, feed.displayName), removeKey: feed.url)
            }
            return feeds + entries(FeedFollowStore.substack, seat: "Substack")
        case .media:
            let pins = PinterestStore.shared.follows.map { follow in
                Following.Followed(id: "pinterest:\(follow.lowercased())",
                                   name: PinterestStore.shared.display(follow), seat: "Pinterest",
                                   handles: [follow], removeKey: follow)
            }
            return entries(FeedFollowStore.youtube, seat: "YouTube")
                + entries(FeedFollowStore.podcasts, seat: "Podcasts") + pins
        case .work:
            GitHubWatchStore.shared.refresh(context: context)
            let github = GitHubWatchStore.shared.watches.map { watch in
                Following.Followed(id: watch.ref, name: watch.title, seat: "GitHub",
                                   handles: ["scope:\(watch.ref)"], removeKey: watch.ref)
            }
            let packages = PackageRegistry.allCases.flatMap { registry in
                (PackageStore.shared.watched[registry] ?? []).map { name in
                    Following.Followed(
                        id: "\(registry.rawValue):\(name.lowercased())", name: name, seat: registry.displayName,
                        refPrefixes: ["\(registry.rawValue):release:\(name.lowercased()):",
                                      "\(registry.rawValue):deprecated:\(name.lowercased())"],
                        removeKey: name)
                }
            }
            let authors = HuggingFaceStore.shared.authors.map { author in
                Following.Followed(id: "hf:\(author.lowercased())", name: author, seat: "Hugging Face",
                                   handles: [author], removeKey: author)
            }
            let radicle = RadicleStore.shared.repos.map { rid in
                Following.Followed(id: "radicle:\(rid)", name: RadicleStore.shared.names[rid] ?? rid,
                                   seat: "Radicle",
                                   refPrefixes: ["radicle:patch:\(rid):", "radicle:issue:\(rid):"],
                                   removeKey: rid)
            }
            return github + packages + authors + radicle
        }
    }

    /// One follow per app and name the rows carry, read-only. Only where a
    /// row names what was followed: a feed's name (`authorHandle`), a
    /// package's (its ref), an author on Hugging Face. A GitHub watch is a
    /// row of its own, so it reads as it does outside the demo; a Radicle
    /// row names its author, never its repo, so the demo lists none.
    private static func landed(_ posts: [Following.Post], room: Following.Room,
                               context: ModelContext) -> [Following.Followed] {
        var seen = Set<String>()
        var out: [Following.Followed] = []
        for post in posts {
            var name: String?
            var prefixes: [String] = []
            if let registry = PackageRegistry.allCases.first(where: { $0.displayName == post.source }) {
                name = PackageShape.name(fromRef: post.ref, registry: registry)
                if let name {
                    prefixes = ["\(registry.rawValue):release:\(name):", "\(registry.rawValue):deprecated:\(name)"]
                }
            } else if post.source != "Radicle", post.source != "GitHub" {
                name = post.handle?.trimmingCharacters(in: .whitespaces)
            }
            guard let name, !name.isEmpty else { continue }
            let id = "\(post.source.lowercased()):\(name.lowercased())"
            guard seen.insert(id).inserted else { continue }
            out.append(Following.Followed(id: id, name: name, seat: post.source,
                                          handles: prefixes.isEmpty ? [name] : [], refPrefixes: prefixes))
        }
        if room == .work { out += followed(.work, context: context).filter { $0.seat == "GitHub" } }
        return out
    }

    private static func entries(_ store: FeedFollowStore, seat: String) -> [Following.Followed] {
        store.entries.map { entry in
            Following.Followed(id: "\(seat.lowercased()):\(entry.input.lowercased())", name: entry.displayName,
                               seat: seat, site: Following.site(ofFeed: entry.feedURL),
                               handles: names(entry.title, entry.input, entry.displayName),
                               removeKey: entry.input)
        }
    }

    private static func names(_ raw: String...) -> [String] {
        Array(Set(raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
    }

    /// The rows the room's seats landed, newest first, five columns only.
    private static func posts(seats: [String], context: ModelContext) -> [Following.Post] {
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { seats.contains($0.source) },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 4_000
        d.propertiesToFetch = [\.source, \.authorHandle, \.sourceRef, \.capturedAt, \.content,
                               \.authorAvatarURL]
        return ((try? context.fetch(d)) ?? []).compactMap { thing in
            guard thing.isLive else { return nil }
            return Following.Post(source: thing.source, handle: thing.authorHandle, ref: thing.sourceRef,
                                  link: thing.content, avatar: thing.authorAvatarURL, at: thing.capturedAt)
        }
    }
}
