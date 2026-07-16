import Foundation
import Observation

/// The GitHub feeds a person watches (2026-07-14) — one connection, several
/// streams they each turn on, the way a watched wallet exposes holdings and
/// NFTs as separate strips. GitHub is more than "issues that involve me": your
/// stars are a saves collection, your gists are notes, releases and your own
/// contributions are activity over time. Each feed lands things under the one
/// `GitHub` source, tagged by feed so it stays findable on its own.
///
/// Two kinds sit here, and the copy says so: `stars`/`following` are
/// COLLECTIONS you curated; `releases`/`contributions`/`involved` are ACTIVITY.
/// `releases` is activity OVER the starred set — it only means something
/// because stars defines which repos to watch.
enum GitHubFeed: String, CaseIterable, Identifiable {
    case involved       // Issues & PRs that involve you (the original feed)
    case stars          // Repositories you starred
    case releases       // New releases from repos you star
    case gists          // Your gists
    case contributions  // Your own recent activity
    case following      // Repositories you watch

    var id: String { rawValue }

    /// The picker label — words, sentence case (design law).
    var title: String {
        switch self {
        case .involved:      "Issues & PRs"
        case .stars:         "Stars"
        case .releases:      "New releases"
        case .gists:         "Gists"
        case .contributions: "Contributions"
        case .following:     "Watched repos"
        }
    }

    /// One line under the label — what lands here.
    var blurb: String {
        switch self {
        case .involved:      "Issues and pull requests that involve you."
        case .stars:         "Repositories you've starred."
        case .releases:      "New releases from repos you star."
        case .gists:         "Your gists, as notes."
        case .contributions: "Your own recent public activity on GitHub."
        case .following:     "Repositories you watch."
        }
    }

    /// The tag stamped on each of this feed's things, so the feed is findable
    /// on its own (all still share the `GitHub` source).
    var tag: String {
        switch self {
        case .involved:      "Issues & PRs"
        case .stars:         "Stars"
        case .releases:      "Releases"
        case .gists:         "Gists"
        case .contributions: "Contributions"
        case .following:     "Watching"
        }
    }
}

/// Which GitHub feeds are on. Persisted in UserDefaults, keyed the same for the
/// @Observable UI store and the off-main fetch layer (which reads the defaults
/// directly rather than touching the singleton across actors).
@Observable
final class GitHubFeeds {
    static let shared = GitHubFeeds()
    private static let key = "github.feeds.enabled"

    /// A fresh connect starts with every feed on — connecting GitHub means all
    /// of it, and the picker is there to turn feeds OFF what you don't want.
    static let defaultOn: Set<GitHubFeed> = Set(GitHubFeed.allCases)

    private(set) var enabled: Set<GitHubFeed>

    private init() { enabled = Self.enabledFromDefaults() }

    /// The persisted selection, read straight off UserDefaults — thread-safe,
    /// so the nonisolated fetch layer never reaches across an actor into the
    /// @Observable singleton. Absent key = never chosen = the defaults.
    static func enabledFromDefaults() -> Set<GitHubFeed> {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else {
            return defaultOn
        }
        return Set(raw.compactMap(GitHubFeed.init(rawValue:)))
    }

    func isOn(_ feed: GitHubFeed) -> Bool { enabled.contains(feed) }

    func toggle(_ feed: GitHubFeed) {
        if enabled.contains(feed) { enabled.remove(feed) } else { enabled.insert(feed) }
        persist()
    }

    func set(_ feeds: Set<GitHubFeed>) { enabled = feeds; persist() }

    private func persist() {
        UserDefaults.standard.set(enabled.map(\.rawValue), forKey: Self.key)
    }
}

/// The per-feed fetches — each one or two GETs against GitHub's own API with
/// the stored token, landing things the caller dedupes on `sourceRef`. Mirrors
/// the other TokenIngest fetches: build Thing values here (off-main), the
/// @MainActor refresh inserts them.
enum GitHubFeedFetch {
    private static let api = "https://api.github.com"

    /// Stamped on a stable major release (a clean x.0.0) so the arrival
    /// celebration in the shell can key on it — a repo you star hitting v16 is
    /// a moment worth a berry shower, a point release isn't.
    static let majorReleaseTag = "Major release"

    /// A clean x.0.0 (minor and patch both zero, major ≥ 1) — tolerant of a
    /// leading `v` and monorepo `pkg@`/`@scope/pkg@` prefixes.
    static func isMajorRelease(_ tag: String) -> Bool {
        guard let r = tag.range(of: #"(\d+)\.0\.0(?:\D|$)"#, options: .regularExpression)
        else { return false }
        return (Int(tag[r].prefix { $0.isNumber }) ?? 0) >= 1
    }

    /// Who the token belongs to — the identity every activity feed needs, and
    /// the one call that tells a bad token from an empty feed (a rejected token
    /// answers 401 here, so the caller can retire it).
    static func login(token: String) async -> String? {
        guard let user = await IngestSupport.getJSON("\(api)/user", auth: "Bearer \(token)")
                as? [String: Any] else { return nil }
        return user["login"] as? String
    }

    /// Every enabled feed, combined. nil ONLY when the token itself is rejected
    /// (so the caller retires a dead token); a single feed failing contributes
    /// nothing but never fails the whole refresh.
    static func all(token: String) async -> [Thing]? {
        // Nothing selected → nothing to fetch, and no reason to spend the
        // identity call. (A bad token is caught the moment a feed is on.)
        let feeds = Array(GitHubFeeds.enabledFromDefaults())
        guard !feeds.isEmpty else { return [] }
        guard let login = await login(token: token) else { return nil }
        let batches = await IngestSupport.boundedGather(feeds, maxConcurrent: 4) { feed in
            await fetch(feed, login: login, token: token) ?? []
        }
        return batches.flatMap { $0 }
    }

    static func fetch(_ feed: GitHubFeed, login: String, token: String) async -> [Thing]? {
        switch feed {
        case .involved:      await involved(login: login, token: token)
        case .stars:         await stars(token: token)
        case .releases:      await releases(token: token)
        case .gists:         await gists(token: token)
        case .contributions: await contributions(login: login, token: token)
        case .following:     await following(token: token)
        }
    }

    // MARK: - Feeds

    /// Issues & PRs that involve you — the original GitHub feed. Keeps its old
    /// `gh:<id>` ref so things landed before feeds existed still dedupe.
    private static func involved(login: String, token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON(
            "\(api)/search/issues?q=involves:\(login)&sort=updated&per_page=30",
            auth: "Bearer \(token)") as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { item in
            guard let id = item["id"], let title = item["title"] as? String,
                  let link = item["html_url"] as? String else { return nil }
            return thing(.link, title: title, content: link, ref: "gh:\(id)",
                         feed: .involved, at: IngestSupport.isoDate(item["updated_at"]))
        }
    }

    /// Repos you've starred, newest star first. The star media type wraps each
    /// row as `{ starred_at, repo }`, so "when you saved it" is the WHEN.
    private static func stars(token: String) async -> [Thing]? {
        guard let items = await IngestSupport.getJSON(
            "\(api)/user/starred?sort=created&direction=desc&per_page=30",
            auth: "Bearer \(token)",
            headers: ["Accept": "application/vnd.github.star+json"]) as? [[String: Any]]
        else { return nil }
        return items.compactMap { item in
            let repo = (item["repo"] as? [String: Any]) ?? item
            guard let id = repo["id"], let full = repo["full_name"] as? String,
                  let link = repo["html_url"] as? String else { return nil }
            let avatar = (repo["owner"] as? [String: Any])?["avatar_url"] as? String
            let at = IngestSupport.isoDate(item["starred_at"])
                ?? IngestSupport.isoDate(repo["updated_at"])
            let t = thing(.link, title: full, content: link, ref: "gh:star:\(id)",
                          feed: .stars, at: at, image: IngestSupport.imageURL(avatar))
            // The stargazer count at star time is the "since you starred"
            // anchor — captured once (dedupe on ref), never back-filled.
            t.starCount = repo["stargazers_count"] as? Int
            t.repoLanguage = repo["language"] as? String
            return t
        }
    }

    /// New releases from the repos you star — activity over the starred set.
    /// The starred list defines which repos to check; only releases published
    /// in the last 60 days land, so a first sync isn't a wall of old tags.
    private static func releases(token: String) async -> [Thing]? {
        guard let repos = await IngestSupport.getJSON(
            "\(api)/user/starred?sort=created&direction=desc&per_page=20",
            auth: "Bearer \(token)") as? [[String: Any]] else { return nil }
        let names = Array(repos.compactMap { $0["full_name"] as? String }.prefix(15))
        let cutoff = Date.now.addingTimeInterval(-60 * 24 * 3600)
        let found = await IngestSupport.boundedGather(names, maxConcurrent: 5) { full -> Thing? in
            // per_page=5, not 1: a draft (null published_at) can sit at the top
            // for a token that can see drafts, hiding a real release right
            // behind it — take the newest PUBLISHED one instead.
            guard let arr = await IngestSupport.getJSON(
                "\(api)/repos/\(full)/releases?per_page=5", auth: "Bearer \(token)")
                    as? [[String: Any]],
                  let rel = arr.first(where: { IngestSupport.isoDate($0["published_at"]) != nil }),
                  let id = rel["id"], let url = rel["html_url"] as? String,
                  let published = IngestSupport.isoDate(rel["published_at"]),
                  published >= cutoff else { return nil }
            let tag = (rel["tag_name"] as? String) ?? (rel["name"] as? String) ?? ""
            let short = full.split(separator: "/").last.map(String.init) ?? full
            let t = thing(.link, title: tag.isEmpty ? short : "\(short) \(tag)",
                          content: url, ref: "gh:release:\(id)", feed: .releases, at: published)
            // A stable major (not a prerelease) earns the celebration marker.
            if !((rel["prerelease"] as? Bool) ?? false), isMajorRelease(tag) {
                t.tags.append(majorReleaseTag)
            }
            return t
        }
        return found.compactMap { $0 }
    }

    /// Your gists — snippets you saved, landing as notes.
    private static func gists(token: String) async -> [Thing]? {
        guard let items = await IngestSupport.getJSON(
            "\(api)/gists?per_page=30", auth: "Bearer \(token)") as? [[String: Any]]
        else { return nil }
        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let url = item["html_url"] as? String else { return nil }
            let desc = (item["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let firstFile = (item["files"] as? [String: Any])?.keys.sorted().first
            return thing(.note, title: desc ?? firstFile ?? "Gist", content: url,
                         ref: "gh:gist:\(id)", feed: .gists,
                         at: IngestSupport.isoDate(item["updated_at"]))
        }
    }

    /// Your own recent activity — pushes, PRs, issues, releases. The public
    /// events feed, worded into a line per event; event types with no clean
    /// line are skipped rather than shown raw.
    private static func contributions(login: String, token: String) async -> [Thing]? {
        guard let events = await IngestSupport.getJSON(
            "\(api)/users/\(login)/events?per_page=30", auth: "Bearer \(token)")
                as? [[String: Any]] else { return nil }
        return events.compactMap { ev in
            guard let id = ev["id"] as? String, let type = ev["type"] as? String,
                  let repo = (ev["repo"] as? [String: Any])?["name"] as? String,
                  let line = contributionLine(type, repo: repo,
                                              payload: ev["payload"] as? [String: Any] ?? [:])
            else { return nil }
            return thing(.link, title: line, content: "https://github.com/\(repo)",
                         ref: "gh:event:\(id)", feed: .contributions,
                         at: IngestSupport.isoDate(ev["created_at"]))
        }
    }

    private static func contributionLine(_ type: String, repo: String,
                                         payload: [String: Any]) -> String? {
        switch type {
        case "PushEvent":
            // GitHub's events feed slimmed the PushEvent payload — it no longer
            // carries `size`/`commits`, only ref/head/before — so a count is
            // usually absent. Name the branch rather than claim "0 commits"
            // (honesty rule); keep the count path for the rare feed that has it.
            let n = (payload["size"] as? Int) ?? (payload["commits"] as? [Any])?.count
            if let n, n > 0 {
                return "Pushed \(n) commit\(n == 1 ? "" : "s") to \(repo)"
            }
            let branch = (payload["ref"] as? String)?
                .replacingOccurrences(of: "refs/heads/", with: "") ?? ""
            return branch.isEmpty ? "Pushed to \(repo)" : "Pushed to \(branch) in \(repo)"
        case "PullRequestEvent":
            return "\((payload["action"] as? String ?? "updated").capitalized) a pull request in \(repo)"
        case "IssuesEvent":
            return "\((payload["action"] as? String ?? "updated").capitalized) an issue in \(repo)"
        case "CreateEvent":
            return "Created a \(payload["ref_type"] as? String ?? "ref") in \(repo)"
        case "ReleaseEvent":
            let tag = (payload["release"] as? [String: Any])?["tag_name"] as? String ?? ""
            return tag.isEmpty ? "Published a release in \(repo)" : "Released \(tag) in \(repo)"
        case "ForkEvent":  return "Forked \(repo)"
        case "WatchEvent": return "Starred \(repo)"
        default:           return nil
        }
    }

    /// Repos you watch on GitHub — the subscriptions list, as things.
    private static func following(token: String) async -> [Thing]? {
        guard let items = await IngestSupport.getJSON(
            "\(api)/user/subscriptions?per_page=30", auth: "Bearer \(token)") as? [[String: Any]]
        else { return nil }
        return items.compactMap { repo in
            guard let id = repo["id"], let full = repo["full_name"] as? String,
                  let link = repo["html_url"] as? String else { return nil }
            let avatar = (repo["owner"] as? [String: Any])?["avatar_url"] as? String
            let t = thing(.link, title: full, content: link, ref: "gh:watch:\(id)",
                          feed: .following, at: IngestSupport.isoDate(repo["updated_at"]),
                          image: IngestSupport.imageURL(avatar))
            t.repoLanguage = repo["language"] as? String
            return t
        }
    }

    /// The repo's live stargazer count — the "→ now" half of "since you
    /// starred". A public repo answers without auth, but the stored token
    /// lifts the rate limit and reaches private repos. nil on any failure
    /// (the line just doesn't show).
    static func repoStars(path: String, token: String) async -> Int? {
        guard let repo = await IngestSupport.getJSON("\(api)/repos/\(path)",
                                   auth: "Bearer \(token)") as? [String: Any] else { return nil }
        return repo["stargazers_count"] as? Int
    }

    // MARK: - Shared

    /// One GitHub thing — source "GitHub", tagged by feed, one-line title.
    private static func thing(_ kind: ThingKind, title: String, content: String,
                              ref: String, feed: GitHubFeed, at: Date?,
                              image: String? = nil) -> Thing {
        let t = Thing(kind: kind, title: IngestSupport.titleLine(title), content: content,
                      source: "GitHub", capturedAt: at ?? .now,
                      tags: [feed.tag], sourceRef: ref)
        t.previewImageURL = image
        return t
    }
}
