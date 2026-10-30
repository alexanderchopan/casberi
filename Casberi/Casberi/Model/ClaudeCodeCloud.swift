import Foundation

/// Your Claude Code sessions in Anthropic's cloud, read live with the
/// claude.ai sign-in (prd §1625) — the pure half, Foundation only, so
/// `claude-code-cloud-selftest.sh` compiles it whole.
///
/// ## WHAT WAS MEASURED (2026-10-30, a real account)
///
///   · `GET claude.ai/v1/code/sessions` with the session's cookies and two
///     headers, `x-organization-uuid` (the organization that can chat) and
///     `anthropic-version: 2023-06-01`, answers `data` (20 a page) and a
///     `next_cursor`. Without the first header: 401 "x-organization-uuid
///     header is required"; without the second: 400.
///   · A session: `id` (`cse_…`), `title`, `created_at`/`updated_at` (ISO
///     8601), `worker_status` (`idle`/`running`), `status_bucket`
///     (`completed`/`failed`), `config.sources` (`git_repository` with a
///     GitHub `url`), and `external_metadata`: `current_branches` (an object
///     keyed by branch name) and `post_turn_summary` — Claude's own read of
///     where the session stands: `status_category` (`completed`,
///     `need_input`, `failed`), `status_detail`, `recent_action` and
///     `needs_action` (a sentence, empty when nothing is asked).
///   · `GET …/sessions/<id>/events` answers the session as it happened; not
///     read here.
///
/// So a session lands as a row that says what Claude says of it, and one
/// Claude is waiting on is tagged "Needs you" by Claude's own `need_input`,
/// never a guess. (Work's Needs you reads Work's rows only, and Claude Code
/// sits in Agents, so it does not reach there.)
enum ClaudeCodeCloud {

    static let source = "Claude Code"

    /// The state a row carries as a TAG, in stable English (`WorkStage`'s
    /// rule), drawn on the row as it is spelled.
    enum State: String, Equatable {
        case needsYou = "Needs you"
        case running = "Running"
        case failed = "Failed"
        case done = "Completed"
    }

    struct Session: Equatable {
        let id: String
        let title: String
        /// `owner/repo`, from the first GitHub source.
        let repo: String?
        let branch: String?
        let state: State
        /// What Claude says it needs, else where it stands, else what it did.
        let line: String
        let created: Date?
        let updated: Date?

        var ref: String { "claudecode:cloud:\(id)" }
        var link: String { "https://claude.ai/code/\(id)" }
        var tags: [String] {
            var tags = ["Session", state.rawValue]
            if let name = repo?.split(separator: "/").last { tags.append(String(name)) }
            return tags
        }
    }

    /// The sessions in one page of `/v1/code/sessions`, or nil when the body
    /// is not that shape (the site moved).
    static func sessions(_ json: Any?) -> [Session]? {
        guard let root = json as? [String: Any], let data = root["data"] as? [[String: Any]] else { return nil }
        return data.compactMap(session)
    }

    static func session(_ raw: [String: Any]) -> Session? {
        guard let id = raw["id"] as? String, !id.isEmpty else { return nil }
        let meta = raw["external_metadata"] as? [String: Any] ?? [:]
        let summary = meta["post_turn_summary"] as? [String: Any] ?? [:]
        let category = summary["status_category"] as? String
        let needs = (summary["needs_action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state: State
        if raw["worker_status"] as? String == "running" {
            state = .running
        } else if category == "need_input" || !needs.isEmpty {
            state = .needsYou
        } else if category == "failed" || raw["status_bucket"] as? String == "failed" {
            state = .failed
        } else {
            state = .done
        }
        let line = [needs, summary["status_detail"] as? String ?? "", summary["recent_action"] as? String ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let title = (raw["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Session(
            id: id,
            title: title.isEmpty ? "Claude Code session" : title,
            repo: repo(raw),
            branch: (meta["current_branches"] as? [String: Any])?.keys.sorted().first,
            state: state,
            line: line,
            created: (raw["created_at"] as? String).flatMap(date),
            updated: (raw["updated_at"] as? String).flatMap(date))
    }

    /// `owner/repo` from the first GitHub source.
    static func repo(_ raw: [String: Any]) -> String? {
        let sources = (raw["config"] as? [String: Any])?["sources"] as? [[String: Any]] ?? []
        for source in sources {
            guard let url = (source["url"] as? String).flatMap(URL.init(string:)),
                  url.host == "github.com" else { continue }
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
            return "\(parts[0])/\(name)"
        }
        return nil
    }

    static func date(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
