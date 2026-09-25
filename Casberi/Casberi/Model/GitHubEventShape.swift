import Foundation

/// **WHAT A GITHUB EVENT SAYS** (prd §909, 2026-09-24 — user feedback, off the
/// GitHub room: *"Can we read more relevant data to the pull requests and
/// branches? Just titles and tap to open the whole with body?"*).
///
/// One events-feed entry, read into the three things a row needs — its TITLE,
/// the PAGE a tap opens, and the WORDS the sheet shows — from the payload the
/// feed already carries. **Zero extra requests**: GitHub's public events API
/// ships the whole pull request object on a `PullRequestEvent`, the whole issue
/// on an `IssuesEvent`, the branch name on a `CreateEvent` and the head sha on
/// a `PushEvent`, and until this file every one of those was thrown away at
/// `contributionLine`, which worded the row as "Opened a pull request in
/// owner/repo" and pointed it at the repository's front page.
///
/// ## The three fields
///
/// - **title** — the verb, the object's own title, the repo: `Merged · Fix the
///   flaky widget test · owner/repo`. The VERB LEADS (§303's clamp ruling:
///   `IngestSupport.titleLine` cuts at 80 and eats the tail, so what must
///   survive goes first). A push keeps its line — the head commit's subject is
///   a second request, made for your own pushes and deliberately NOT for a
///   watched person's (`GitHubFeedFetch.eventsFor` says why) — and a branch is
///   NAMED, not counted.
/// - **url** — the object, never the repository, wherever the payload names
///   one: the pull request, the issue, the commit a push landed, the branch a
///   create made, the release, the fork. This is the "tap to open the whole":
///   the row's disc opens the page that holds the body, the diff, the thread.
///   It is also what tags the row — `GitHubRowTag.kind` reads the URL FIRST,
///   so a pull request event now wears "Pull request" under its time instead
///   of "Activity", with no change to that file.
/// - **body** — the pull request's or issue's own description, trimmed and
///   clamped, for `Thing.summary`. DISPLAY copy by the `involved` feed's
///   standing reason: text GitHub's payload authored and handed us, not text
///   we scraped, so the retrieval-only `enrichedText` rule does not apply.
///
/// ## What it deliberately does not do
///
/// It never fetches. A release's notes stay a live read on open (`releaseBody`)
/// and a push's commit message stays the caller's bounded follow-up; putting
/// either here would make a watched person's feed cost a request per row.
///
/// Foundation-only BY DESIGN, so `scripts/github-event-selftest.sh` compiles
/// it WHOLE AND UNMODIFIED; `GitHubFeedFetch.eventThing` is its one caller.
enum GitHubEventShape {

    /// A row's three fields. `body` is already clamped to `bodyCap`.
    struct Row: Equatable {
        var title: String
        var url: String
        var body: String?
    }

    /// The ceiling a stored body is clamped to — the chat/journal imports'
    /// ceiling, shared with every other GitHub body through
    /// `GitHubFeedFetch.clampBody`, which delegates here so there is ONE number.
    static let bodyCap = 4000

    static func clamp(_ text: String) -> String {
        text.count > bodyCap ? String(text.prefix(bodyCap)) + "…" : text
    }

    /// One event, worded. nil for a type with no clean line, which is skipped
    /// rather than shown raw.
    static func row(type: String, repo: String, payload: [String: Any]) -> Row? {
        let home = "https://github.com/\(repo)"
        switch type {
        case "PushEvent":
            // GitHub's events feed slimmed the PushEvent payload — it no longer
            // carries `size`/`commits`, only ref/head/before — so a count is
            // usually absent. Name the branch rather than claim "0 commits"
            // (honesty rule); keep the count path for the rare feed that has it.
            let n = (payload["size"] as? Int) ?? (payload["commits"] as? [Any])?.count
            let branch = branchName(payload["ref"])
            let title: String
            if let n, n > 0 {
                title = String(localized: "Pushed \(n) commit to \(repo)")
            } else {
                title = branch.map { "Pushed to \($0) in \(repo)" } ?? "Pushed to \(repo)"
            }
            // The commit the push landed: its page carries the whole message,
            // which is the body a push has. The branch when the head is
            // missing, the repo when both are.
            let url: String
            if let head = string(payload["head"]) {
                url = "\(home)/commit/\(head)"
            } else if let branch, let path = pathEncoded(branch) {
                url = "\(home)/tree/\(path)"
            } else {
                url = home
            }
            return Row(title: title, url: url, body: nil)

        case "PullRequestEvent":
            let action = string(payload["action"]) ?? "updated"
            guard let pr = payload["pull_request"] as? [String: Any],
                  let title = string(pr["title"]) else {
                return Row(title: "\(action.capitalized) a pull request in \(repo)",
                           url: home, body: nil)
            }
            let merged = (pr["merged"] as? Bool) == true
                || string(pr["merged_at"]) != nil
            // The pull request is the object; the verb and the repo are its
            // qualifier, on the line under it (`TitleSeam`, prd §915).
            return Row(title: TitleSeam.join(title, "\(verb(action, merged: merged)) · \(repo)"),
                       url: string(pr["html_url"]) ?? home,
                       body: string(pr["body"]).map(clamp))

        case "IssuesEvent":
            let action = string(payload["action"]) ?? "updated"
            guard let issue = payload["issue"] as? [String: Any],
                  let title = string(issue["title"]) else {
                return Row(title: "\(action.capitalized) an issue in \(repo)",
                           url: home, body: nil)
            }
            return Row(title: TitleSeam.join(title, "\(verb(action, merged: false)) · \(repo)"),
                       url: string(issue["html_url"]) ?? home,
                       body: string(issue["body"]).map(clamp))

        case "CreateEvent":
            let kind = string(payload["ref_type"]) ?? "ref"
            // A repository create names no ref; a branch or tag is NAMED, and
            // its page is the branch (a tag renders there too).
            guard kind != "repository" else {
                return Row(title: "Created \(repo)", url: home, body: nil)
            }
            guard let ref = string(payload["ref"]) else {
                return Row(title: "Created a \(kind) in \(repo)", url: home, body: nil)
            }
            let url = pathEncoded(ref).map { "\(home)/tree/\($0)" } ?? home
            return Row(title: "Created \(kind) \(ref) in \(repo)", url: url, body: nil)

        case "ReleaseEvent":
            let release = payload["release"] as? [String: Any]
            let tag = string(release?["tag_name"]) ?? ""
            let title = tag.isEmpty ? "Published a release in \(repo)" : "Released \(tag) in \(repo)"
            return Row(title: title, url: string(release?["html_url"]) ?? home, body: nil)

        case "ForkEvent":
            let forkee = payload["forkee"] as? [String: Any]
            return Row(title: "Forked \(repo)", url: string(forkee?["html_url"]) ?? home, body: nil)

        case "WatchEvent":
            return Row(title: "Starred \(repo)", url: home, body: nil)

        default:
            return nil
        }
    }

    /// The word that leads a pull request's or issue's row. GitHub's public
    /// events publish eleven actions; four are news and the rest (labeled,
    /// assigned, synchronize, edited, review_requested…) are housekeeping the
    /// row states as "Updated" rather than as a raw snake_case word with a
    /// capital letter on it.
    static func verb(_ action: String, merged: Bool) -> String {
        switch action {
        case "opened":   return String(localized: "Opened")
        case "reopened": return String(localized: "Reopened")
        case "closed":   return merged ? String(localized: "Merged") : String(localized: "Closed")
        default:         return String(localized: "Updated")
        }
    }

    /// "refs/heads/main" → "main"; nil when absent or empty.
    static func branchName(_ raw: Any?) -> String? {
        guard let ref = string(raw) else { return nil }
        let name = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
        return name.isEmpty ? nil : name
    }

    /// A branch or tag name as a URL path, slashes kept — `feature/x` is one
    /// branch and GitHub reads it under `/tree/feature/x`.
    static func pathEncoded(_ name: String) -> String? {
        name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    /// A JSON string field, trimmed, or nil when absent, not a string, or empty
    /// — so an empty `body` never lands as a blank block.
    static func string(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }
}
