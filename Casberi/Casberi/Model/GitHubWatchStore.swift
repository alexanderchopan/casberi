import Foundation
import Observation
import SwiftData

/// **THE WATCHED REPOS AND PEOPLE, IN MEMORY** — so the GitHub room's face rail
/// costs nothing on the body path (2026-09-11).
///
/// Every other face rail in the app reads an in-memory store: the social rail
/// takes `FarcasterStore.shared.socialAccounts`, the wallet and devnet rails
/// take their watch lists. `MainSurface.socialAccounts` says why in its own
/// comment — the rail is built inside `topInset`, which is evaluated on **every
/// body pass** and is already that surface's most expensive property.
///
/// GitHub is the one seat whose watch list is not a store but the CORPUS: a
/// watch IS a `Thing` (the `GitHubRepoWatch`/`TokenWatch` precedent, and the
/// reason removing the row unwatches it). Reading it the way the others read
/// theirs would put a `FetchDescriptor` in a body — §628's ruling verbatim, and
/// §646's `0x8BADF00D` one room over. So the fetch happens on a corpus change
/// and the rail reads this.
///
/// **It is a CACHE of the corpus and never the truth.** `GitHubRepoWatch.add`,
/// `GitHubPersonWatch.add` and the account page's remove all write the store
/// first and refresh this second; nothing here decides whether a watch exists.
@Observable
@MainActor
final class GitHubWatchStore {
    static let shared = GitHubWatchStore()

    struct Watch: Identifiable, Equatable {
        let ref: String
        /// The repo's full name, or the person's display name.
        let title: String
        let avatarURL: String?
        let isRepo: Bool
        var id: String { ref }
    }

    private(set) var watches: [Watch] = []

    private init() {}

    /// Re-reads the watch rows. Cheap enough to call on a corpus change: the
    /// predicate is a plain string equality (the ONE shape SwiftData can push
    /// down to SQL here — never `tags.contains`, which crashes mid-fetch) and
    /// the result is bounded by the watch list, not by the corpus.
    func refresh(context: ModelContext) {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "GitHub" && $0.sourceRef != nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 400
        let rows = (try? context.fetch(descriptor)) ?? []
        var found: [Watch] = []
        for thing in rows {
            // `isLive` FIRST, every time: reading any stored property of a
            // deleted model traps inside SwiftData, and this walk holds a
            // derived array — the liveness class exactly (docs/liveness.md).
            guard thing.isLive, let ref = thing.sourceRef else { continue }
            let isRepo = ref.hasPrefix("gh:watchrepo:")
            let isPerson = GitHubLinks.personLogin(fromRef: ref) != nil
            guard isRepo || isPerson else { continue }
            found.append(Watch(ref: ref, title: thing.title,
                               // A repo files the OWNER's avatar as art and a
                               // person files their own as a FACE (the 2026-08-14
                               // ruling `GitHubPersonWatch` records); the rail
                               // wants a picture either way.
                               avatarURL: thing.authorAvatarURL ?? thing.previewImageURL,
                               isRepo: isRepo))
        }
        // Assign only on a real change, so the rail is not invalidated by every
        // sweep that landed nothing about a watch.
        if found != watches { watches = found }
    }

    /// Everything scoped away when a face is picked — the ids the rail offers.
    var refs: [String] { watches.map(\.ref) }
}
