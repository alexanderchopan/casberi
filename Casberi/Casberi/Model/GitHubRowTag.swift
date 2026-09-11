import Foundation

/// **WHAT A GITHUB ROW IS, AND WHOSE IT IS** (user ruling, 2026-09-11).
///
/// Two derivations, both over fields every landed row ALREADY carries — no new
/// `Thing` property, no CloudKit deploy, nothing to backfill. That is the whole
/// reason this file exists rather than a stamped tag at ingest: a stamp would
/// be right for rows landed after it and silently absent on the corpus a person
/// already has, and the GitHub bridge has no heal pass to fix them up.
///
/// ## The tag under the time
///
/// The room is a plain feed — no head card, no chip strip, no sections of its
/// own (the ruling that deleted `GitHubRoomCard`: *"it is just a row no
/// sections… just a feed and those are tags"*). So the one thing a row must say
/// beyond its sentence is WHAT KIND of thing it is, and that goes in the
/// trailing slot under the timestamp, which is where `BandRow` already puts the
/// project name — free in a single-source room. Plain tinted text, never a
/// chip: a chip means tappable (the 2026-07-06 band ruling).
///
/// **It names the OBJECT, never the reason.** A notification's title already
/// leads with its reason ("Review requested · org/repo · …"), so a tag saying
/// "Review" would print the same word twice on one row. The tag says "Pull
/// request", and the two halves of the row answer different questions.
///
/// **The URL is the authority, not the ref.** `gh:` and `gh:notif:` rows both
/// point at an issue OR a pull request and nothing in the ref says which — but
/// `github.com/o/r/pull/9` and `/issues/9` are exact, on every row ever landed,
/// including the ones that predate this file. The ref namespace answers the
/// rest, where it is unambiguous.
///
/// ## Whose it is
///
/// The face rail scopes the feed to one watched repo or person, and the match
/// is the same kind of derivation: a repo owns a row whose URL sits under it, a
/// person owns a row they authored.
///
/// **A notification is scoped by REPO and never by PERSON**, and this is the
/// one rule here that is not obvious. `GitHubFeedFetch.notifications` stamps the
/// REPOSITORY OWNER onto `authorHandle` — it says so in its own comment, because
/// GitHub's notifications payload names no actor anywhere — so treating that
/// field as "who did this" would file every notification from `tokio-rs/tokio`
/// under a watched person who happens to own the org. The row is real, the face
/// is real, and the claim "this is theirs" is the false one.
///
/// Foundation-only by design so `scripts/github-rowtag-selftest.sh` can compile
/// it WHOLE and unmodified.
enum GitHubRowTag {

    // MARK: - The tag

    /// What a row IS. One axis, seven values — a second axis (open vs merged,
    /// say) would make this slot a second sentence, and `BandRow` already
    /// strikes a done row through.
    enum Kind: String, CaseIterable {
        case pullRequest, issue, release, star, gist, activity, watching

        /// The word drawn under the time. Sentence case, the design law's own
        /// rule for every label in the app.
        var word: String {
            switch self {
            case .pullRequest: return String(localized: "Pull request")
            case .issue:       return String(localized: "Issue")
            case .release:     return String(localized: "Release")
            case .star:        return String(localized: "Star")
            case .gist:        return String(localized: "Gist")
            // NOT "Push". An events-feed row may be a push, a fork, a branch
            // created, a release published or somebody starring something —
            // `GitHubFeedFetch.contributionLine` words all six — so the tag
            // takes the feed's own word rather than naming the commonest case
            // and being wrong about the rest.
            case .activity:    return String(localized: "Activity")
            case .watching:    return String(localized: "Watching")
            }
        }
    }

    /// The ref namespaces `GitHubFeedFetch` stamps, longest first.
    ///
    /// ORDER IS LOAD-BEARING: `gh:` prefixes every one of them, so a plain
    /// `hasPrefix("gh:")` test placed first would claim every row in the room.
    /// Spelled as a table rather than a switch so the harness can walk it.
    static let refKinds: [(prefix: String, kind: Kind)] = [
        ("gh:release:", .release),
        ("gh:star:", .star),
        ("gh:gist:", .gist),
        ("gh:event:", .activity),
        ("gh:watchrepo:", .watching),
        (GitHubLinks.personRefPrefix, .watching),
    ]

    /// What this row is, or nil when nothing here can say — which is a real
    /// case (a row landed by some future feed) and draws no tag at all rather
    /// than a guess.
    static func kind(ref: String?, url: String?) -> Kind? {
        // The URL first, because it is the only thing that separates an issue
        // from a pull request and it is exact on every row ever landed.
        if let url, let parts = GitHubLinks.webURLPathParts(url), parts.count >= 3 {
            switch parts[2] {
            case "pull", "pulls": return .pullRequest
            case "issues":        return .issue
            case "releases":      return .release
            default:              break
            }
        }
        guard let ref else { return nil }
        for entry in refKinds where ref.hasPrefix(entry.prefix) { return entry.kind }
        // A bare `gh:<id>` is the `involved` feed, whose rows are issues and
        // pull requests alike. The URL above already separated them; reaching
        // here means the URL was missing or unparseable, and "Issue" would be
        // a coin flip. No tag.
        return nil
    }

    /// The word, ready to draw.
    static func word(ref: String?, url: String?) -> String? {
        kind(ref: ref, url: url)?.word
    }

    // MARK: - Whose it is

    /// What the rail hands back when a face is picked: the watch's own ref, so
    /// the scope value is the same string the watch row carries and nothing has
    /// to agree on a second spelling.
    static func scopeIsRepo(_ scope: String) -> Bool { scope.hasPrefix("gh:watchrepo:") }

    /// "owner/repo" out of a repo watch's ref.
    static func repoName(scope: String) -> String? {
        guard scope.hasPrefix("gh:watchrepo:") else { return nil }
        let name = String(scope.dropFirst("gh:watchrepo:".count))
        return name.isEmpty ? nil : name
    }

    /// Does this row belong to the picked face?
    ///
    /// `ref` is the row's own `sourceRef`, `url` its `content`, `authorHandle`
    /// the face it leads with.
    static func matches(scope: String, ref: String?, url: String?,
                        authorHandle: String?) -> Bool {
        // The watch row itself is always in its own scope — it is the proof the
        // watch exists, and a scope that hides it would read as "nothing here"
        // the moment you watch something with no activity yet.
        if ref == scope { return true }
        if let repo = repoName(scope: scope) {
            guard let url, let path = GitHubLinks.repoPath(fromWebURL: url) else { return false }
            return path.lowercased() == repo.lowercased()
        }
        guard let login = GitHubLinks.personLogin(fromRef: scope) else { return false }
        // See this file's header: a notification's face is the REPOSITORY's
        // owner, not whoever acted, so it may never answer "whose is this".
        if let ref, ref.hasPrefix("gh:notif:") { return false }
        guard let handle = authorHandle, !handle.isEmpty else { return false }
        return handle.lowercased() == login.lowercased()
    }

    // MARK: - The rail

    /// Whether the room draws a face rail at all.
    ///
    /// **Zero watches means NO ROW** (user, 2026-09-11: *"if they paste their
    /// own key… if it is just themselves that would suck to see a third row"*).
    /// With nothing watched the rail would be the word "All" alone — a control
    /// with one option, which is §83's dead control wearing a band row that the
    /// feed could have used.
    ///
    /// ONE watch is enough, unlike Vibenet's `watched > 1`, and the difference
    /// is real rather than a looser threshold: there, All and the single
    /// account show the same rows, so the choice is between a thing and itself.
    /// Here All is your whole GitHub — your issues, your stars, every release
    /// from every repo you starred — and one watched person is a strict slice
    /// of it. Two different readings, so two chips earn their row.
    static func railShows(source: String, watched: Int) -> Bool {
        source == "GitHub" && watched > 0
    }
}
