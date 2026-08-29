import Foundation
import SwiftData

/// Watch a PERSON on GitHub (prd §519, 2026-08-29) — `GitHubRepoWatch`'s
/// missing half, and the private half of GitHub's own Follow.
///
/// Following on GitHub is PUBLIC and it NOTIFIES: the person sees a new
/// follower, and anyone can read your following list. A Casberi watch does
/// neither — it reads the same public events feed with the connected token but
/// is tracked purely on this iPhone, so keeping an eye on a maintainer, a
/// competitor or somebody you're about to hire never shows up anywhere.
///
/// The watch IS the thing (the `GitHubRepoWatch`/TokenWatch precedent): it
/// lands immediately as proof, and deleting it in the sheet unwatches it — no
/// separate store to drift out of sync. Their activity then lands the exact way
/// your own does (`GitHubFeedFetch.eventsFor`).
///
/// ONE DIVERGENCE from the repo watch, deliberate: the avatar is stamped as a
/// FACE (`authorHandle`/`authorAvatarURL`), never as the row's ART. That is the
/// 2026-08-14 ruling — an avatar is an identity, not a picture — and `GitHub`
/// has been in `ShapedRows.faceSources` since 2026-08-12, so the leading slot
/// draws it. `GitHubRepoWatch.add` still files the OWNER's avatar as art; it is
/// left alone here because changing it needs a heal for rows already landed,
/// and that is a different pass from this one.
enum GitHubPersonWatch {

    struct Resolved: Identifiable {
        let login: String          // the account name, GitHub's own spelling
        let name: String?          // the display name, when they set one
        let htmlURL: String
        let avatarURL: String?
        let bio: String?
        var id: String { login }
        /// What the row says. The display name when there is one — it is what
        /// a person recognises — with the login carried beside it in the face
        /// slot, so two people called "Alex" are still told apart.
        var title: String { name ?? login }
    }

    /// Resolves whatever was pasted — a bare login, an `@login`, or a profile
    /// URL — to a real account with one GET. The parse is
    /// `GitHubLinks.personLogin`, which refuses a repo URL rather than reading
    /// its owner out (see there).
    static func resolve(_ query: String, token: String) async -> Resolved? {
        guard let login = GitHubLinks.personLogin(from: query) else { return nil }
        guard let user = await IngestSupport.getJSON(
            "https://api.github.com/users/\(login)", auth: "Bearer \(token)") as? [String: Any],
              let real = user["login"] as? String,
              let html = user["html_url"] as? String
        else { return nil }
        func trimmed(_ raw: Any?) -> String? {
            guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty else { return nil }
            return s
        }
        // GitHub's own spelling of the login wins over what was typed — logins
        // are case-insensitive, and the ref is lowercased either way, but the
        // row should read the way the account really writes itself.
        return Resolved(login: real, name: trimmed(user["name"]), htmlURL: html,
                        avatarURL: IngestSupport.imageURL(user["avatar_url"] as? String),
                        bio: trimmed(user["bio"]))
    }

    /// Adds the watch as a visible thing immediately. Returns nil when they're
    /// already watched.
    @MainActor
    @discardableResult
    static func add(_ person: Resolved, context: ModelContext) -> Thing? {
        let r = GitHubLinks.personRef(person.login)
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == r }))) ?? 0
        guard existing == 0 else { return nil }
        let thing = Thing(kind: .link, title: IngestSupport.titleLine(person.title),
                          content: person.htmlURL, source: "GitHub", capturedAt: .now,
                          tags: ["Watching"], sourceRef: r)
        thing.authorHandle = person.login
        thing.authorAvatarURL = person.avatarURL
        // The bio is DISPLAY copy (`summary`), the issue-body precedent: text
        // GitHub's own payload authored and handed us, not text we scraped, so
        // the retrieval-only `enrichedText` ruling (2026-07-15) doesn't apply
        // and putting it there would make it invisible on every screen.
        thing.summary = person.bio
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return thing
    }

    /// The people watched right now, derived from the corpus — scoped to this
    /// bridge's watch rows only (mirrors `GitHubRepoWatch.watchedRepos`).
    @MainActor
    static func watchedPeople(context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "GitHub" && $0.sourceRef != nil })
        descriptor.propertiesToFetch = [\.sourceRef]
        return ((try? context.fetch(descriptor)) ?? [])
            .compactMap(\.sourceRef)
            .compactMap(GitHubLinks.personLogin(fromRef:))
    }
}
