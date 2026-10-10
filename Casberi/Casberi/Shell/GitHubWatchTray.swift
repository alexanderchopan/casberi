import SwiftUI
import SwiftData

/// Watch a repo or a person on GitHub — ONE verb for the account page's
/// field and the room's tray (prd §1030), so the two can never disagree about
/// what a paste means or what a failure says.
///
/// The shape of what was pasted decides the verb: a path with an owner AND a
/// name is a repo, anything else is an account (`TokenSetupScreen.looksLikeRepo`).
/// Neither touches the GitHub account — nothing is starred, subscribed or
/// followed. The person failure names the two ways a paste fails there (a
/// profile URL and a REPO URL look alike, and `GitHubLinks.personLogin`
/// refuses the second rather than quietly watching its owner), and a person's
/// success carries their face (prd §519).
@MainActor
enum GitHubWatchAdd {
    struct Outcome {
        let proof: BridgeProof
        /// The face of whoever just landed — a person's avatar, never a repo's.
        var faces: [String] = []
        /// Whether a watch row was written; a failure or a repeat writes none.
        var added = false
    }

    /// Nil when there is nothing to do: an empty paste, or no GitHub key on
    /// this device (a demo seat, or a key deleted under the room).
    static func watch(_ query: String, context: ModelContext) async -> Outcome? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let token = TokenVault.get(TokenBridge.github.tokenKey) else { return nil }
        if TokenSetupScreen.looksLikeRepo(q) {
            guard let resolved = await GitHubRepoWatch.resolve(q, token: token) else {
                return Outcome(proof: .failed(String(localized: "Couldn't find that repo on GitHub.")))
            }
            guard let thing = GitHubRepoWatch.add(resolved, context: context) else {
                return Outcome(proof: .failed(String(localized: "\(resolved.fullName) is already followed.")))
            }
            return Outcome(proof: .says(String(localized: "Following \(thing.title)")), added: true)
        }
        guard let resolved = await GitHubPersonWatch.resolve(q, token: token) else {
            return Outcome(proof: .failed(String(localized: "No such account on GitHub — a username, or a link to a profile.")))
        }
        guard let thing = GitHubPersonWatch.add(resolved, context: context) else {
            return Outcome(proof: .failed(String(localized: "\(resolved.login) is already followed.")))
        }
        return Outcome(proof: .says(String(localized: "Following \(thing.title)")),
                       faces: [resolved.avatarURL].compactMap { $0 }, added: true)
    }
}

/// THE GITHUB ROOM'S NEXT STEP (prd §1030, user: "we could add a prompt there
/// when they connect", then "ok do both").
///
/// A connect lands in the room (§1029), which skipped the one thing the
/// account page offered after connecting: watching. Every feed is already on
/// by default (`GitHubFeeds.defaultOn`), so the step a new person misses is a
/// repo or a person to follow — and nothing in the room said watching
/// exists.
///
/// Raised twice, through `FeedScreen`'s one sheet: ONCE on the arrival a
/// connect made (`ShellChrome.connectLanding`), and from the room's Watch
/// tile, last in its grid (§1031), on any visit after. The feeds ride under the
/// field because they are the page's other first-run choice, and a person
/// who came here from a connect should not have to go back for them.
struct GitHubWatchTray: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable private var feeds = GitHubFeeds.shared

    @State private var query = ""
    @State private var busy = false
    @State private var result: BridgeProof?
    @State private var faces: [String] = []

    var body: some View {
        DSTray(title: String(localized: "Follow on GitHub"), height: 620,
               detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    DSSlabField(placeholder: AccountPageShape.findPlaceholder(
                                    String(localized: "a repo or person")),
                                text: $query, actionLabel: String(localized: "Follow"),
                                busy: busy, action: watch)
                    BridgeSyncStatusRows(syncing: busy,
                                         syncingLine: TokenSetupScreen.looksLikeRepo(query)
                                            ? String(localized: "Looking it up…")
                                            : String(localized: "Looking them up…"),
                                         proof: result,
                                         faces: faces, faceFallback: TokenBridge.github.rawValue)
                    DSSlabNote(text: "Private to \(DS.device) — nobody is followed or notified, and nothing shows on your GitHub account.")
                    Text("Feeds")
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .padding(.top, DS.Space.s3)
                    ForEach(GitHubFeed.allCases) { feed in
                        DSSlabSwitch(title: feed.title, detail: feed.blurb,
                                     isOn: Binding(
                                        get: { feeds.isOn(feed) },
                                        set: { _ in
                                            feeds.toggle(feed)
                                            DSHaptic.tap()
                                            // A newly-chosen feed lands now,
                                            // not next foreground — the
                                            // account page's own rule.
                                            Task { _ = await TokenIngest.refresh(.github, context: modelContext) }
                                        }))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func watch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        DSHaptic.tap()
        busy = true
        faces = []
        Task {
            let outcome = await GitHubWatchAdd.watch(q, context: modelContext)
            busy = false
            guard let outcome else {
                result = .failed(String(localized: "Connect GitHub first."))
                return
            }
            result = outcome.proof
            guard outcome.added else { return }
            query = ""
            faces = outcome.faces
            // The room's menu reads this store; refreshed here so the face
            // is in the menu when the tray comes down, and the watched
            // repo's releases and issues land now.
            GitHubWatchStore.shared.refresh(context: modelContext)
            _ = await TokenIngest.refresh(.github, context: modelContext)
        }
    }
}
