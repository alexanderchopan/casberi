import Foundation
import Observation
import SwiftData

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
    case notifications  // WHY an issue/PR needs you — review, mention, assign
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
        case .notifications: "Notifications"
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
        case .notifications: "Why an issue or PR needs you — reviews, mentions, assignments."
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
        case .notifications: "Notifications"
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

    /// Every enabled feed, combined, plus new releases from directly-watched
    /// repos (2026-07-16 — `GitHubRepoWatch`, independent of the feed picker
    /// the way a specific watched wallet address is independent of "Tokens").
    /// nil ONLY when the token itself is rejected (so the caller retires a
    /// dead token); a single feed failing contributes nothing but never
    /// fails the whole refresh.
    @MainActor
    static func all(token: String, context: ModelContext) async -> [Thing]? {
        // Nothing selected and nothing watched → nothing to fetch, and no
        // reason to spend the identity call. (A bad token is caught the
        // moment a feed or a watch is on.)
        let feeds = Array(GitHubFeeds.enabledFromDefaults())
        let watchedRepos = GitHubRepoWatch.watchedRepos(context: context)
        guard !feeds.isEmpty || !watchedRepos.isEmpty else { return [] }
        guard let login = await login(token: token) else { return nil }

        // A repo that's both starred and directly watched would otherwise
        // have its `.../releases` endpoint hit twice this refresh (once via
        // the `releases` feed, once via the watched-repo check) — merge
        // into one deduped pass when both are active.
        let mergeReleases = feeds.contains(.releases) && !watchedRepos.isEmpty
        let runFeeds = mergeReleases ? feeds.filter { $0 != .releases } : feeds

        // The feed batch and the watched-repo release check hit disjoint
        // endpoints — run them concurrently rather than one after the other.
        async let feedBatches: [[Thing]] = runFeeds.isEmpty ? [] :
            IngestSupport.boundedGather(runFeeds, maxConcurrent: 4) { feed in
                await fetch(feed, login: login, token: token) ?? []
            }
        async let extraReleases: [Thing] =
            mergeReleases ? mergedReleases(watchedRepos: watchedRepos, token: token)
            : (watchedRepos.isEmpty ? [] : releasesFor(watchedRepos, token: token))

        var things = await feedBatches.flatMap { $0 }
        things += await extraReleases
        return things
    }

    /// Starred + directly-watched repos' releases, checked as one deduped
    /// pass. A starred-fetch failure contributes nothing here (matching how
    /// any other failed feed contributes nothing) rather than failing the
    /// whole refresh.
    private static func mergedReleases(watchedRepos: [String], token: String) async -> [Thing] {
        let starred = await starredRepoNames(token: token) ?? []
        let names = Array(Set(starred.map { $0.lowercased() } + watchedRepos))
        return await releasesFor(names, token: token)
    }

    static func fetch(_ feed: GitHubFeed, login: String, token: String) async -> [Thing]? {
        switch feed {
        case .involved:      await involved(login: login, token: token)
        case .notifications: await notifications(token: token)
        case .stars:         await stars(token: token)
        case .releases:      await releases(token: token)
        case .gists:         await gists(token: token)
        case .contributions: await contributions(login: login, token: token)
        case .following:     await following(token: token)
        }
    }

    // MARK: - Feeds

    /// Issues & PRs that involve you — the original GitHub feed. Keeps its old
    /// `gh:<id>` ref so things landed before feeds existed still dedupe. Open
    /// PRs among the results also get a CI verdict tag (below) — a real
    /// differentiator on a row that's otherwise just a title and a link.
    private static func involved(login: String, token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON(
            "\(api)/search/issues?q=involves:\(login)&sort=updated&per_page=30",
            auth: "Bearer \(token)") as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        var things: [Thing] = []
        var prTargets: [(thing: Thing, path: String, number: Int)] = []
        for item in items {
            guard let id = item["id"], let title = item["title"] as? String,
                  let link = item["html_url"] as? String else { continue }
            let t = thing(.link, title: title, content: link, ref: "gh:\(id)",
                         feed: .involved, at: IngestSupport.isoDate(item["updated_at"]))
            things.append(t)
            if item["pull_request"] != nil, (item["state"] as? String) == "open",
               let repoURL = item["repository_url"] as? String,
               let path = repoPath(fromAPI: repoURL),
               let number = item["number"] as? Int {
                prTargets.append((t, path, number))
            }
        }
        // CI verdict for open PRs only, capped so a busy inbox doesn't fan
        // out dozens of extra calls on every refresh (the `releases` feed's
        // repo cap, applied here).
        let capped = Array(prTargets.prefix(15))
        _ = await IngestSupport.boundedGather(capped, maxConcurrent: 4) { target -> Void in
            if let verdict = await checkVerdict(path: target.path, number: target.number, token: token) {
                target.thing.tags.append(verdict)
            }
        }
        return things
    }

    /// "owner/repo" out of a search result's `repository_url` (the API form,
    /// `https://api.github.com/repos/owner/repo`) — what the checks and
    /// releases endpoints below key on.
    private static func repoPath(fromAPI url: String) -> String? {
        let prefix = "\(api)/repos/"
        guard url.hasPrefix(prefix) else { return nil }
        return String(url.dropFirst(prefix.count))
    }

    /// "Checks passing"/"Checks failing" for an open PR's head commit — nil
    /// while any run is still in progress (honesty rule: no verdict beats a
    /// stale one) or when the repo runs no checks at all.
    private static func checkVerdict(path: String, number: Int, token: String) async -> String? {
        guard let pr = await IngestSupport.getJSON("\(api)/repos/\(path)/pulls/\(number)",
                                   auth: "Bearer \(token)") as? [String: Any],
              let sha = (pr["head"] as? [String: Any])?["sha"] as? String,
              let root = await IngestSupport.getJSON(
                "\(api)/repos/\(path)/commits/\(sha)/check-runs?per_page=50",
                auth: "Bearer \(token)") as? [String: Any],
              let runs = root["check_runs"] as? [[String: Any]], !runs.isEmpty
        else { return nil }
        let conclusions = runs.compactMap { $0["conclusion"] as? String }
        guard conclusions.count == runs.count else { return nil }   // one still running
        // A cancelled or stale run finished without ever really answering —
        // no verdict beats a stale one, so it's excluded rather than folded
        // into "passing".
        let inconclusive: Set<String> = ["cancelled", "stale"]
        guard !conclusions.contains(where: inconclusive.contains) else { return nil }
        let failing: Set<String> = ["failure", "timed_out", "action_required"]
        return conclusions.contains(where: failing.contains) ? "Checks failing" : "Checks passing"
    }

    /// Why an issue or PR needs you — GitHub's own notifications, worded into
    /// a reason and never marked read (this bridge stays read-only, prd §67).
    /// Issue/PR subjects only: the other subject types (Discussion, Release,
    /// CheckSuite…) don't share one clean URL-rewrite rule.
    private static func notifications(token: String) async -> [Thing]? {
        guard let items = await IngestSupport.getJSON(
            "\(api)/notifications?per_page=30", auth: "Bearer \(token)") as? [[String: Any]]
        else { return nil }
        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let subject = item["subject"] as? [String: Any],
                  let title = subject["title"] as? String,
                  let type = subject["type"] as? String,
                  type == "Issue" || type == "PullRequest",
                  let apiURL = subject["url"] as? String,
                  let link = notificationHTMLURL(fromAPI: apiURL),
                  let repo = (item["repository"] as? [String: Any])?["full_name"] as? String
            else { return nil }
            let reason = notificationReason(item["reason"] as? String)
            return thing(.link, title: "\(reason) · \(repo) · \(title)", content: link,
                        ref: "gh:notif:\(id)", feed: .notifications,
                        at: IngestSupport.isoDate(item["updated_at"]))
        }
    }

    /// A notification subject's API url (`.../repos/o/r/issues/N` or
    /// `.../pulls/N`) rewritten to the web page it names.
    private static func notificationHTMLURL(fromAPI url: String) -> String? {
        let prefix = "\(api)/repos/"
        guard url.hasPrefix(prefix) else { return nil }
        let s = "https://github.com/" + url.dropFirst(prefix.count)
        return s.replacingOccurrences(of: "/pulls/", with: "/pull/")
    }

    private static func notificationReason(_ raw: String?) -> String {
        switch raw ?? "" {
        case "review_requested": "Review requested"
        case "mention":          "Mentioned you"
        case "team_mention":     "Mentioned your team"
        case "assign":           "Assigned to you"
        case "author":           "New activity"
        case "comment":          "New comment"
        case "state_change":     "Status changed"
        case "ci_activity":      "CI activity"
        case "subscribed":       "New activity"
        case "manual":           "You subscribed"
        default:                 "Notification"
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
            t.enrichedText = repoBlurb(repo)
            return t
        }
    }

    /// A repo's description + topics, joined for retrieval only (2026-07-16)
    /// — `Thing.enrichedText`, never shown, just what semantic search reads
    /// beyond the bare repo name. nil when the repo carries neither.
    private static func repoBlurb(_ repo: [String: Any]) -> String? {
        var parts: [String] = []
        if let desc = (repo["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !desc.isEmpty { parts.append(desc) }
        if let topics = repo["topics"] as? [String], !topics.isEmpty {
            parts.append(topics.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// New releases from the repos you star — activity over the starred set.
    /// The starred list defines which repos to check; only releases published
    /// in the last 60 days land, so a first sync isn't a wall of old tags.
    private static func releases(token: String) async -> [Thing]? {
        guard let names = await starredRepoNames(token: token) else { return nil }
        return await releasesFor(names, token: token)
    }

    /// The starred-repo names the `releases` feed checks — extracted so
    /// `all()` can merge them with directly-watched repos into ONE release
    /// pass when both are active, instead of checking an overlapping repo
    /// twice in the same refresh.
    private static func starredRepoNames(token: String) async -> [String]? {
        guard let repos = await IngestSupport.getJSON(
            "\(api)/user/starred?sort=created&direction=desc&per_page=20",
            auth: "Bearer \(token)") as? [[String: Any]] else { return nil }
        return Array(repos.compactMap { $0["full_name"] as? String }.prefix(15))
    }

    /// The shared release-check, over an explicit repo list — the starred
    /// set (above) or a direct `GitHubRepoWatch` (2026-07-16), which needs
    /// the identical check without the starred-set discovery call.
    private static func releasesFor(_ names: [String], token: String) async -> [Thing] {
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
        var things: [Thing] = []
        var pushTargets: [(thing: Thing, repo: String, sha: String)] = []
        for ev in events {
            guard let id = ev["id"] as? String, let type = ev["type"] as? String,
                  let repo = (ev["repo"] as? [String: Any])?["name"] as? String,
                  let payload = ev["payload"] as? [String: Any],
                  let line = contributionLine(type, repo: repo, payload: payload)
            else { continue }
            let t = thing(.link, title: line, content: "https://github.com/\(repo)",
                         ref: "gh:event:\(id)", feed: .contributions,
                         at: IngestSupport.isoDate(ev["created_at"]))
            things.append(t)
            if type == "PushEvent", let sha = payload["head"] as? String, !sha.isEmpty {
                pushTargets.append((t, repo, sha))
            }
        }
        // The real commit message beats the branch-name fallback — capped so a
        // busy pusher doesn't fan out dozens of extra calls on every refresh
        // (the `involved` feed's PR-verdict cap, applied here).
        let capped = Array(pushTargets.prefix(15))
        _ = await IngestSupport.boundedGather(capped, maxConcurrent: 4) { target -> Void in
            if let message = await commitMessage(repo: target.repo, sha: target.sha, token: token) {
                target.thing.title = IngestSupport.titleLine("\(message) · \(target.repo)")
            }
        }
        return things
    }

    /// The head commit's own message (first line only — a multi-line body is
    /// dropped) for a push event, replacing the branch-name fallback in
    /// `contributionLine` with what was actually pushed. GitHub's events feed
    /// no longer carries the message on the event itself (see below), so this
    /// is a follow-up call keyed off the `head` sha the payload does carry.
    private static func commitMessage(repo: String, sha: String, token: String) async -> String? {
        guard let root = await IngestSupport.getJSON(
            "\(api)/repos/\(repo)/commits/\(sha)", auth: "Bearer \(token)") as? [String: Any],
              let raw = (root["commit"] as? [String: Any])?["message"] as? String,
              let message = raw.split(separator: "\n").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces), !message.isEmpty
        else { return nil }
        return message
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
            t.enrichedText = repoBlurb(repo)
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

    // MARK: - Conversation (an issue/PR's thread, read live — 2026-07-16)

    /// An issue or PR's comments, read live when the sheet opens — the same
    /// "thread context, fetched fresh, never stored" pattern as a Bluesky or
    /// Farcaster reply section (`SocialThread`), reusing its `SocialReply`
    /// shape: GitHub's `{user, body, html_url, created_at}` maps onto it
    /// directly. Inline code-review comments aren't included — the plain
    /// issue/PR conversation is.
    @MainActor
    static func comments(for thing: Thing) async -> [SocialReply] {
        guard thing.kind == .link,
              let (path, number) = issuePath(thing.content),
              let token = TokenVault.get(TokenBridge.github.tokenKey)
        else { return [] }
        guard let items = await IngestSupport.getJSON(
            "\(api)/repos/\(path)/issues/\(number)/comments?per_page=30",
            auth: "Bearer \(token)") as? [[String: Any]]
        else { return [] }
        // Oldest-first from GitHub; the tail is the most recent conversation.
        return items.suffix(SocialThread.replyCap).compactMap { c -> SocialReply? in
            guard let id = c["id"], let body = c["body"] as? String, !body.isEmpty,
                  let user = c["user"] as? [String: Any],
                  let login = user["login"] as? String,
                  let url = c["html_url"] as? String else { return nil }
            return SocialReply(id: "\(id)", handle: login,
                               avatarURL: IngestSupport.imageURL(user["avatar_url"] as? String),
                               text: body, when: IngestSupport.isoDate(c["created_at"]), url: url)
        }
    }

    /// "owner/repo" and the number, parsed from a github.com issue or pull
    /// URL — issues and PRs share the same comments endpoint.
    private static func issuePath(_ content: String) -> (String, Int)? {
        guard let parts = webURLPathParts(content), parts.count >= 4,
              parts[2] == "issues" || parts[2] == "pull",
              let number = Int(parts[3]) else { return nil }
        return ("\(parts[0])/\(parts[1])", number)
    }

    /// A github.com web URL's path components — EXACT host match only
    /// (never a substring check, which would accept a spoofed host like
    /// "github.com.evil.example"). Also accepts a scheme-less URL
    /// ("github.com/owner/repo", a common paste) by retrying with
    /// "https://" prepended, since `URL(string:)` leaves `host` nil
    /// without a scheme.
    static func webURLPathParts(_ raw: String) -> [String]? {
        func parts(of s: String) -> [String]? {
            guard let url = URL(string: s),
                  url.host == "github.com" || url.host == "www.github.com"
            else { return nil }
            return url.pathComponents.filter { $0 != "/" }
        }
        return parts(of: raw) ?? parts(of: "https://\(raw)")
    }

    /// "owner/repo" out of a github.com web URL, scheme-less or not.
    static func repoPath(fromWebURL raw: String) -> String? {
        guard let parts = webURLPathParts(raw), parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    // MARK: - Release notes (read live — 2026-07-16)

    /// A release's own notes, fetched fresh when the sheet opens rather than
    /// stored — `Thing.enrichedText` is reserved for retrieval only, never a
    /// field a view renders directly, so this follows the star-count/social-
    /// engagement precedent instead: live, and simply absent if unreachable.
    static func releaseBody(thing: Thing, token: String) async -> String? {
        guard let ref = thing.sourceRef, ref.hasPrefix("gh:release:") else { return nil }
        let id = ref.dropFirst("gh:release:".count)
        guard let path = repoPath(fromWebURL: thing.content) else { return nil }
        guard let rel = await IngestSupport.getJSON("\(api)/repos/\(path)/releases/\(id)",
                                   auth: "Bearer \(token)") as? [String: Any],
              let body = (rel["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else { return nil }
        return plainFromMarkdown(body)
    }

    /// Markdown release notes, read as plain text: headers lose their `#`s,
    /// list markers become a bullet dot. Not a renderer — a light strip so
    /// the raw syntax doesn't clutter a sheet that has no markdown view.
    private static func plainFromMarkdown(_ md: String) -> String {
        md.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            while l.hasPrefix("#") { l.removeFirst() }
            l = l.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
            return l
        }.joined(separator: "\n")
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
