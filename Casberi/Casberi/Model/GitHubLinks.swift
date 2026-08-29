import Foundation

/// The pure half of GitHub's addressing (prd §519, 2026-08-29) — what a pasted
/// string means, and which accounts an activity pass should read.
///
/// The split is `GitHubRoom`/`GitHubRoomSource`'s and exists for its reason:
/// this file is Foundation-only BY DESIGN, so `scripts/github-person-selftest.sh`
/// compiles it WHOLE AND UNMODIFIED, while everything that touches `Thing` — and
/// so can never be reached by a harness — lives in `GitHubPersonWatch.swift` and
/// `GitHubFeeds.swift`.
///
/// `webURLPathParts` and `repoPath(fromWebURL:)` MOVED here from
/// `GitHubFeedFetch` on the same day rather than being copied: the person parse
/// needs the same exact-host rule, and two readings of one URL drift — after
/// which a repo link and a profile link disagree about which host they trust,
/// which is the one disagreement here that is a security hole rather than a
/// cosmetic one.
enum GitHubLinks {

    // MARK: - Web URLs

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

    // MARK: - People

    /// The account name out of whatever somebody pasted: a bare login, an
    /// `@login`, or a github.com profile URL (scheme-less included, query
    /// string and trailing slash included).
    ///
    /// THREE REFUSALS, each of which is a wrong answer rather than an
    /// inconvenience:
    ///
    ///   · a URL with TWO OR MORE path parts is a REPO, not a profile
    ///     ("github.com/torvalds/linux"). Reading the owner out of it would
    ///     silently watch a person when somebody asked to watch a project —
    ///     a watch that works, lands rows, and is not what was asked for.
    ///   · a host that isn't exactly github.com, inherited from
    ///     `webURLPathParts` above.
    ///   · anything outside GitHub's own login alphabet. This one is the
    ///     security rule: the login is interpolated straight into an API path
    ///     (`/users/<login>/events`), so a `/` or a `..` reaching it addresses
    ///     an endpoint nobody asked for. Letters, digits and hyphens only,
    ///     never leading or trailing a hyphen, at most 39 characters —
    ///     GitHub's own documented ceiling.
    static func personLogin(from raw: String) -> String? {
        var q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parts = webURLPathParts(q) {
            guard parts.count == 1 else { return nil }
            q = parts[0]
        }
        if q.hasPrefix("@") { q.removeFirst() }
        return isValidLogin(q) ? q : nil
    }

    /// GitHub's own login alphabet. Deliberately NOT a check for the handful
    /// of reserved paths ("settings", "explore", …): GitHub answers 404 for
    /// those and the resolve simply fails, whereas a hand-kept reserved list
    /// goes stale and starts refusing real accounts.
    static func isValidLogin(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 39,
              !s.hasPrefix("-"), !s.hasSuffix("-") else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// A watched person's ref. Lowercased, the `gh:watchrepo:` rule exactly —
    /// GitHub logins are case-insensitive, so "Torvalds" and "torvalds" are
    /// one account and must not become two rows.
    static let personRefPrefix = "gh:watchuser:"

    static func personRef(_ login: String) -> String {
        "\(personRefPrefix)\(login.lowercased())"
    }

    /// The login back out of a watch ref, or nil for any other GitHub ref.
    static func personLogin(fromRef ref: String) -> String? {
        guard ref.hasPrefix(personRefPrefix) else { return nil }
        let login = String(ref.dropFirst(personRefPrefix.count))
        return login.isEmpty ? nil : login
    }

    // MARK: - Which accounts an activity pass reads

    /// The logins to read events for this pass, in the order given, deduped
    /// case-insensitively.
    ///
    /// `ownLogin` is dropped ONLY when the `contributions` feed is on, and
    /// that condition is the whole point: that feed already reads exactly this
    /// endpoint for exactly this account, so fetching it again spends a
    /// request for rows the dedupe would throw away — `mergedReleases`'
    /// reasoning, one endpoint over. Dropping it UNCONDITIONALLY would be the
    /// bug: with the feed off, watching yourself is a real thing to want and
    /// would silently read nothing.
    static func activityLogins(watched: [String], ownLogin: String?,
                               contributionsOn: Bool) -> [String] {
        let own = contributionsOn ? ownLogin?.lowercased() : nil
        var seen = Set<String>()
        var out: [String] = []
        for login in watched {
            let key = login.lowercased()
            guard key != own, seen.insert(key).inserted else { continue }
            out.append(login)
        }
        return out
    }
}
