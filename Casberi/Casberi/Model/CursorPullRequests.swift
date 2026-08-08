import Foundation
import SwiftData

/// What became of the pull request your agent opened (2026-08-08, prd §340).
///
/// The Cursor bridge lands a finished run and stops there, and its own note
/// explains why that was right: a terminal run is terminal forever, so nothing
/// in that file ever needs reconciling. But the run is not the end of the
/// story — **the agent opened a pull request, and the thing you actually want
/// to know a day later is whether it went in.** Until now the corpus held
/// "an agent opened a PR" and could never say what happened next, so the row
/// aged into a question nobody could answer without leaving the app.
///
/// This closes that loop the way the Stripe bridge closes a dispute: join the
/// two halves on the PERMALINK both of them name, rather than on any identifier
/// we invent. A Cursor row already stores the PR url in `content`; GitHub will
/// answer for that exact url; so the join needs no new `Thing` field and no
/// CloudKit Production deploy.
///
/// ## Why it asks GitHub directly rather than reading the events feed
///
/// The GitHub bridge lands events, gists, notifications, releases, stars and
/// watches — `PullRequestEvent` is in that firehose, but it is scoped to what
/// you follow, capped at ninety days, and silent about a PR merged by somebody
/// else on a repository you don't watch. Asking about the one PR we already
/// have the url for is a single GET that answers exactly the question, for
/// every repository the token can see, with no window.
///
/// ## The rails
///
/// * **It reads, and only reads.** One verb, `GET`, against one path shape.
///   The §303 conduct promise is about `CursorBridge.swift`'s own file and is
///   guarded there mechanically; this file is separate precisely so that guard
///   stays about Cursor, and it holds itself to the same standard.
/// * **It needs the GitHub bridge connected.** No token, no pass — this
///   borrows an existing, already-declared reach (`api.github.com` is in
///   `NetworkReach`), and never asks the person for a new one.
/// * **It is bounded.** One request per unresolved PR, capped per pass, and a
///   row is asked once more only while its answer is still open. A merged or
///   closed PR is final, so it is never asked again.
/// * **It states no duration.** The run's start and the merge time are both
///   real, so a duration is knowable — but it would have to live somewhere,
///   and the only somewhere without a new field is a display string. The fact
///   that it merged is the news; how long it sat is not worth a field, and
///   inventing it from our own first sight is the Hyperliquid trap.
///
/// **UNMEASURED (2026-08-08).** No Cursor key is stored on this host and no
/// agent run exists to carry a real PR url, so this has never run against live
/// data. Every read returns nil on failure and every failure leaves the row
/// exactly as it was, so it fails safe: a drifted field means the loop simply
/// never closes, rather than closing wrongly.
enum CursorPullRequests {

    /// The tag a merged PR gains. Unlocalized and stable, for the reason
    /// `CursorAgentStatus.facetTag` is — a landed marker that a language
    /// change must not silently rewrite.
    static let mergedTag = "Merged"
    /// Closed WITHOUT merging. A separate word on purpose: "closed" and
    /// "merged" are opposite outcomes for the person who launched the agent,
    /// and folding them together would report a rejected PR as a landed one.
    static let closedTag = "PR closed"

    /// How many unresolved PRs one pass will ask about. Each is a request, and
    /// this rides the same foreground sweep as ~27 other bridges.
    private static let perPass = 12

    // MARK: - Reading a PR url

    /// `("owner", "repo", 42)` out of a GitHub pull-request url, or nil.
    ///
    /// Deliberately strict: it matches the `/pull/<n>` shape and nothing else,
    /// so a Cursor page url — which is what `content` holds when the run
    /// opened no PR — parses as nil rather than as some other repository's
    /// pull request. Host-checked for the same reason.
    static func parse(_ raw: String) -> (owner: String, repo: String, number: Int)? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com") else { return nil }
        // `split` drops the empty leading component, so "/owner/repo/pull/42"
        // is exactly ["owner", "repo", "pull", "42"].
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 4,
              !parts[0].isEmpty, !parts[1].isEmpty,
              parts[2] == "pull",
              let number = Int(parts[3]), number > 0
        else { return nil }
        return (parts[0], parts[1], number)
    }

    // MARK: - The pass

    /// Ask about every Cursor row whose pull request we don't yet know the end
    /// of, and record what GitHub says.
    ///
    /// Returns how many rows changed, so a caller can tell "nothing to do"
    /// from "the read never ran" — the distinction every probe in this app
    /// exists to make.
    @MainActor
    @discardableResult
    static func reconcile(context: ModelContext) async -> Int {
        guard let token = TokenVault.get(TokenBridge.github.tokenKey), !token.isEmpty
        else { return 0 }

        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Cursor" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        let rows = ((try? context.fetch(descriptor)) ?? []).live

        // Candidates first, as VALUES — the url and the model are separated
        // here on purpose. Everything below the first `await` re-checks
        // liveness before it touches the model again (corollary 6: a [Thing]
        // held across a suspension is stale on resume, and this pass suspends
        // once per request).
        let pending: [(thing: Thing, owner: String, repo: String, number: Int)] =
            rows.compactMap { thing in
                guard thing.tags.contains("PR"),
                      !thing.tags.contains(mergedTag),
                      !thing.tags.contains(closedTag),
                      let parsed = parse(thing.content) else { return nil }
                return (thing, parsed.owner, parsed.repo, parsed.number)
            }
        guard !pending.isEmpty else { return 0 }

        var changed = 0
        for candidate in pending.prefix(perPass) {
            guard let verdict = await state(owner: candidate.owner, repo: candidate.repo,
                                            number: candidate.number, token: token)
            else { continue }
            guard case .decided(let merged, let at) = verdict else { continue }
            // Re-checked AFTER the await, per corollary 6 — the foreground
            // sweep deletes rows in exactly this window.
            let thing = candidate.thing
            guard thing.isLive else { continue }
            thing.tags.append(merged ? mergedTag : closedTag)
            // The moment it happened, kept where retrieval can reach it and
            // no screen has to render it (the 2026-07-15 retrieval-only
            // ruling). This is what makes "what merged last week" answerable
            // without a new stored property.
            if let at {
                let stamp = ISO8601DateFormatter().string(from: at)
                let line = merged
                    ? "Pull request merged \(stamp)."
                    : "Pull request closed without merging \(stamp)."
                thing.enrichedText = [thing.enrichedText, line]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            }
            changed += 1
        }
        if changed > 0 { context.saveHonestly() }
        return changed
    }

    /// What GitHub says about one pull request.
    private enum Verdict {
        /// Still open — ask again next pass.
        case open
        /// Final. `merged` false means closed without merging.
        case decided(merged: Bool, at: Date?)
    }

    private static func state(owner: String, repo: String, number: Int,
                              token: String) async -> Verdict? {
        let path = "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(number)"
        guard let root = await IngestSupport.getJSON(
            path, auth: "Bearer \(token)") as? [String: Any] else { return nil }
        // `merged_at` is the authority, not `merged`: the boolean is absent
        // from some responses while the timestamp is the field GitHub
        // documents as the merge's own moment. A closed PR that never merged
        // carries `closed_at` and a null `merged_at`, which is exactly the
        // distinction this pass exists to keep.
        let mergedAt = IngestSupport.isoDate(root["merged_at"])
        if mergedAt != nil { return .decided(merged: true, at: mergedAt) }
        guard let rawState = root["state"] as? String else { return nil }
        guard rawState.lowercased() == "closed" else { return .open }
        return .decided(merged: false, at: IngestSupport.isoDate(root["closed_at"]))
    }

    // MARK: - Probe

    /// `-cursorPRProbe YES` — what this pass sees, without changing anything.
    ///
    /// An unchanged room has FIVE causes that look identical from the feed: no
    /// GitHub token, no Cursor row carrying a PR at all, every PR already
    /// resolved, every PR still genuinely open, or a url shape this build
    /// can't parse. Only the last is a bug, and it is invisible — the row just
    /// keeps saying a PR was opened, forever.
    @MainActor
    static func diagnose(context: ModelContext) async {
        let hasToken = (TokenVault.get(TokenBridge.github.tokenKey)?.isEmpty == false)
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Cursor" })
        descriptor.fetchLimit = 200
        let rows = ((try? context.fetch(descriptor)) ?? []).live
        let tagged = rows.filter { $0.tags.contains("PR") }
        let resolved = tagged.filter {
            $0.tags.contains(mergedTag) || $0.tags.contains(closedTag)
        }
        NSLog("[Casberi] cursorPR| githubToken=%@ cursorRows=%d withPR=%d resolved=%d",
              hasToken ? "yes" : "NO", rows.count, tagged.count, resolved.count)
        // One line per row (the -todayProbe truncation lesson), naming whether
        // the url parsed — the one failure that renders as nothing at all.
        for thing in tagged.prefix(20) where thing.isLive {
            let parsed = parse(thing.content)
            NSLog("[Casberi] cursorPRRow| parsed=%@ state=%@ title=%@",
                  parsed.map { "\($0.owner)/\($0.repo)#\($0.number)" } ?? "NO",
                  thing.tags.contains(mergedTag) ? mergedTag
                    : thing.tags.contains(closedTag) ? closedTag : "open",
                  thing.title)
        }
    }
}
