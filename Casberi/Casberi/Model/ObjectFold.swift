import Foundation

/// ONE ROW PER THING YOU BUILD OR READ (prd §1079).
///
/// A merged room lists every app's rows by day, so the things those rows are
/// ABOUT repeat: a pull request is opened, reviewed, commented on and merged,
/// and each lands as its own GitHub row; a Sentry issue regresses and
/// resolves; an article arrives by RSS, is saved to Raindrop and highlighted
/// in Readwise. The Wallet never had this problem because its merge was over
/// money, and one token held in five places is one holding. This is that
/// merge for events: rows naming the same object fold into the NEWEST one,
/// which is the object's current state, and the rest stay reachable from its
/// sheet (`ThingSheetView`'s same-object rows) and from the app's own pick in
/// the account menu, where only that app's rows stand.
///
/// **Exact, never inferred** — `ThingLinks`' and `RelatedThings.keptBefore`'s
/// rule, for their reason: a wrong merge hides a row the person needed and
/// reads as a bug, and a missed one costs a repeated row.
///
/// - **Work** folds only on links that NAME an object, by a shape known per
///   service (a PR, an issue, a ticket, an incident, a deployment, a build, a
///   dispute). A plain "same link" rule is wrong there: PostHog, Stripe, Dodo
///   and Cloudflare stamp distinct readings with one dashboard URL, Slack's
///   permalinks are messages, and an AWS alarm's name lives in the fragment,
///   which canonicalisation drops — so every alarm would have been one row.
/// - **Reading** folds on the canonical article link (`ThingLinks.canonicalLink`,
///   the one canonicaliser), with a path. L2BEAT and Walletbeat are out: their
///   rows are a project's ratings changing, each a reading of its own, and a
///   project page is not an article.
///
/// Foundation-only: `scripts/object-fold-selftest.sh` compiles this file and
/// `ThingLinks.swift` whole.
enum ObjectFold {

    enum Room: Equatable {
        case work, reading

        /// The merged room's name (`RoomAccounts.workRoom`, `.readingRoom`),
        /// spelled here so this file stays Foundation-only.
        init?(room: String) {
            switch room {
            case "Work":    self = .work
            // Media folds its Read half's articles (prd §1204): Reading
            // folded into it, and the fold reads only those rows.
            case "Reading", "Media": self = .reading
            default:        return nil
            }
        }
    }

    /// Reading's rows that are readings, not articles.
    static let readingExcluded: Set<String> = ["L2BEAT", "Walletbeat"]

    /// The object a row is about, or nil when it names none we can be sure of.
    /// `link` is the row's own permalink (`Thing.content` for a link row).
    static func key(room: Room, source: String, link: String) -> String? {
        let raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("http://") || raw.hasPrefix("https://") else { return nil }
        switch room {
        case .work:
            return workKey(raw)
        case .reading:
            guard !readingExcluded.contains(source),
                  let canonical = ThingLinks.canonicalLink(raw),
                  canonical.count >= 12, ThingLinks.hasPath(canonical) else { return nil }
            return "read:" + canonical
        }
    }

    /// The Work object a link names, by service. Each arm is one service's
    /// own object URL, and anything else — a dashboard, a list, a message —
    /// is nil.
    static func workKey(_ raw: String) -> String? {
        guard let comps = URLComponents(string: raw), var host = comps.host?.lowercased()
        else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let parts = comps.path.split(separator: "/").map(String.init)
        func after(_ word: String) -> String? {
            guard let i = parts.firstIndex(of: word), i + 1 < parts.count else { return nil }
            let next = parts[i + 1]
            return next.isEmpty ? nil : next
        }

        switch true {
        case host == "github.com":
            // owner/repo/pull/12, owner/repo/issues/12 (one number space, so a
            // PR's notification and its events meet), owner/repo/commit/<sha>.
            guard parts.count >= 4 else { return nil }
            let repo = "\(parts[0])/\(parts[1])".lowercased()
            switch parts[2] {
            case "pull", "issues":
                guard Int(parts[3]) != nil else { return nil }
                return "github:\(repo)#\(parts[3])"
            case "commit":
                return "github:\(repo)@\(parts[3].lowercased())"
            default:
                return nil
            }

        case parts.contains("-") && (after("merge_requests") != nil || after("issues") != nil):
            // GitLab, any host: group/project/-/merge_requests/7.
            guard let dash = parts.firstIndex(of: "-") else { return nil }
            let project = parts[..<dash].joined(separator: "/").lowercased()
            if let n = after("merge_requests"), Int(n) != nil {
                return "gitlab:\(host)/\(project)!\(n)"
            }
            if let n = after("issues"), Int(n) != nil {
                return "gitlab:\(host)/\(project)#\(n)"
            }
            return nil

        case host == "linear.app":
            // workspace/issue/ENG-12/slug — the key is the issue's id.
            return after("issue").map { "linear:\($0.uppercased())" }

        case host.hasSuffix(".atlassian.net"):
            return after("browse").map { "jira:\(host):\($0.uppercased())" }

        case host == "trello.com":
            return after("c").map { "trello:\($0)" }

        case host == "notion.so" || host.hasSuffix(".notion.site"):
            // A page's id is the trailing 32 hex of its last path part.
            guard let last = parts.last else { return nil }
            let tail = String(last.split(separator: "-").last ?? Substring(last))
            guard tail.count == 32, tail.allSatisfy(\.isHexDigit) else { return nil }
            return "notion:\(tail.lowercased())"

        case host == "sentry.io" || host.hasSuffix(".sentry.io"):
            return after("issues").flatMap { Int($0) != nil ? "sentry:\($0)" : nil }

        case host.hasSuffix(".pagerduty.com"):
            return after("incidents").map { "pagerduty:\(host):\($0)" }

        case host.hasSuffix(".vercel.app"):
            // A deployment's own host is unique to it.
            return "vercel:\(host)"

        case host == "vercel.com":
            // The inspector: team/project/<deployment id>.
            guard parts.count == 3 else { return nil }
            return "vercel:\(parts.joined(separator: "/").lowercased())"

        case host.contains("radicle"):
            if let id = after("patches") { return "radicle:patch:\(id)" }
            if let id = after("issues") { return "radicle:issue:\(id)" }
            return nil

        case host == "appstoreconnect.apple.com":
            // A build's TestFlight page (apps/<app>/testflight/ios/<build>).
            // The version page is the app's, not a version's, so it is no key.
            guard parts.count >= 5, parts[2] == "testflight" else { return nil }
            return "asc:build:\(parts[4])"

        case host == "dashboard.stripe.com":
            for word in ["disputes", "payouts", "subscriptions", "invoices", "payments"] {
                if let id = after(word) { return "stripe:\(id)" }
            }
            return nil

        case host == "polar.sh":
            return after("sales").map { "polar:sale:\($0)" }

        case host == "console.aws.amazon.com":
            // An alarm's name is in the FRAGMENT (`#alarmsV2:alarm/<name>`),
            // its region in the query; a pipeline run is in the path.
            if let fragment = comps.fragment, fragment.hasPrefix("alarmsV2:alarm/") {
                let name = String(fragment.dropFirst("alarmsV2:alarm/".count))
                guard !name.isEmpty else { return nil }
                let region = comps.queryItems?.first { $0.name == "region" }?.value ?? ""
                return "aws:alarm:\(region):\(name)"
            }
            return after("executions").map { "aws:run:\($0)" }

        default:
            return nil
        }
    }

    /// One row of the room, as the fold sees it.
    struct Row<ID: Hashable> {
        let id: ID
        let key: String?
        let at: Date
    }

    /// The rows folded away: every member of an object but its newest. A row
    /// with no key stands. Ties on time keep the first in the given order.
    static func folded<ID: Hashable>(_ rows: [Row<ID>]) -> Set<ID> {
        var head: [String: Row<ID>] = [:]
        for row in rows {
            guard let key = row.key else { continue }
            if let kept = head[key], kept.at >= row.at { continue }
            head[key] = row
        }
        var out = Set<ID>()
        for row in rows {
            guard let key = row.key, let kept = head[key], kept.id != row.id else { continue }
            out.insert(row.id)
        }
        return out
    }
}
