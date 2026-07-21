import Foundation
import SwiftData

/// Watch a repo directly (2026-07-16) — the private half of GitHub's own
/// star/subscribe. Both of those are PUBLIC: anyone can see what you starred
/// or watch. A Casberi watch never touches the GitHub account at all — it's
/// read with the same connected token but tracked purely on this iPhone, so
/// following a competitor's repo or a dependency never shows up on your
/// public profile. The watch IS the thing (the Stocktwits/TokenWatch
/// precedent): it lands immediately as proof, and deleting it (the sheet's
/// own delete verb — feed swipes stay read-only, ruling 2026-07-15) unwatches
/// it — no separate store to drift out of sync. Its releases then land the
/// exact way a starred repo's do (`GitHubFeedFetch.releasesFor`).
enum GitHubRepoWatch {
    struct Resolved: Identifiable {
        let fullName: String       // "owner/repo"
        let htmlURL: String
        let avatarURL: String?
        let language: String?
        let stars: Int
        var id: String { fullName }
    }

    private static let refPrefix = "gh:watchrepo:"

    static func ref(_ fullName: String) -> String { "\(refPrefix)\(fullName.lowercased())" }

    /// Resolves a bare "owner/repo" slug or a github.com URL (scheme-less
    /// pastes included) to a real repo with one GET — an exact-match
    /// lookup, unlike a fuzzy ticker search.
    static func resolve(_ query: String, token: String) async -> Resolved? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let slug = GitHubFeedFetch.repoPath(fromWebURL: q) ?? q
        guard slug.split(separator: "/").count == 2,
              let repo = await IngestSupport.getJSON("https://api.github.com/repos/\(slug)",
                                   auth: "Bearer \(token)") as? [String: Any],
              let full = repo["full_name"] as? String,
              let html = repo["html_url"] as? String
        else { return nil }
        return Resolved(fullName: full, htmlURL: html,
                        avatarURL: IngestSupport.imageURL(
                            (repo["owner"] as? [String: Any])?["avatar_url"] as? String),
                        language: repo["language"] as? String,
                        stars: repo["stargazers_count"] as? Int ?? 0)
    }

    /// Adds the watch as a visible thing immediately. Returns nil when it's
    /// already watched.
    @MainActor
    @discardableResult
    static func add(_ repo: Resolved, context: ModelContext) -> Thing? {
        let r = ref(repo.fullName)
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == r }))) ?? 0
        guard existing == 0 else { return nil }
        let thing = Thing(kind: .link, title: repo.fullName, content: repo.htmlURL,
                          source: "GitHub", capturedAt: .now, tags: ["Watching"], sourceRef: r)
        thing.previewImageURL = repo.avatarURL
        thing.repoLanguage = repo.language
        thing.starCount = repo.stars
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return thing
    }

    /// The repos watched right now, derived from the corpus — scoped to this
    /// bridge's watch rows only (mirrors `StockWatch.watchedSymbols`).
    @MainActor
    static func watchedRepos(context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "GitHub" && $0.sourceRef != nil })
        descriptor.propertiesToFetch = [\.sourceRef]
        return ((try? context.fetch(descriptor)) ?? [])
            .compactMap(\.sourceRef)
            .compactMap { $0.hasPrefix(refPrefix) ? String($0.dropFirst(refPrefix.count)) : nil }
    }
}
