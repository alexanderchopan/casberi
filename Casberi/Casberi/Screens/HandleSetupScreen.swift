import SwiftUI
import SwiftData

/// The name-only bridges — connect by a public name alone (no password, no
/// token, nothing stored but the name), so their screens are the same shape.
/// Two families ride this one enum: the people bridges (Bluesky, Farcaster,
/// Pinterest), and the feed-follow bridges (Substack, Reddit, YouTube,
/// Podcasts), whose per-bridge words and URL rules live in `FeedFollowKind`.
/// This enum carries the words that differ, the way TokenBridge does for the
/// paste-a-token screens; the feed cases delegate to their kind.
enum HandleBridge: String {
    case bluesky   = "Bluesky"
    case farcaster = "Farcaster"
    case pinterest = "Pinterest"
    case substack  = "Substack"
    case reddit    = "Reddit"
    case youtube   = "YouTube"
    case podcasts  = "Podcasts"

    /// The feed-follow kind behind the four feed cases, nil for the people
    /// bridges — the join that lets each switch below fall through to one place.
    var feedKind: FeedFollowKind? { FeedFollowKind(rawValue: rawValue) }

    /// BridgeStore id, and the connected-strip route.
    var bridgeID: String {
        switch self {
        case .bluesky:   "bsky"
        case .farcaster: "fc"
        case .pinterest: "pinterest"
        default:         feedKind!.bridgeID
        }
    }

    /// What the person types — Bluesky says handle, Farcaster says username.
    var nameNoun: String {
        switch self {
        case .bluesky:   "handle"
        case .farcaster, .pinterest: "username"
        default:         feedKind!.nameNoun
        }
    }

    var placeholder: String {
        switch self {
        case .bluesky:   "you"
        case .farcaster, .pinterest: "yourname"
        default:         feedKind!.placeholder
        }
    }

    /// The fixed part of the name, shown around the field so the person
    /// types only what's theirs.
    var fieldPrefix: String? {
        switch self {
        case .farcaster: "farcaster.xyz/"
        case .pinterest: "pinterest.com/"
        default:         nil
        }
    }

    var fieldSuffix: String? {
        switch self {
        case .bluesky:   ".bsky.social"
        default:         nil
        }
    }

    /// Every bridge here but Pinterest watches a LIST — a small following feed,
    /// not just one mirror. Pinterest stays single (its feed is per-user).
    var supportsMultiple: Bool { self != .pinterest }

    /// The bridges whose field doubles as a finder: Bluesky/Farcaster people
    /// search, and Podcasts show search. Pinterest and the templated feeds
    /// (Substack/Reddit/YouTube) have no such surface — you type the name.
    var supportsSearch: Bool {
        self == .bluesky || self == .farcaster || self == .podcasts
    }

    func search(_ query: String) async -> [UserSearch.Hit] {
        switch self {
        case .bluesky:   await UserSearch.bluesky(query)
        case .farcaster: await UserSearch.farcaster(query)
        case .podcasts:  await FeedFetch.searchPodcasts(query)
        default:         []
        }
    }

    /// A tapped search hit connects like a typed name — plus, for Farcaster,
    /// the fid the search carried, or for Podcasts, the feed the search found.
    func add(hit: UserSearch.Hit) {
        switch self {
        case .bluesky:
            BlueskyStore.shared.add(hit.handle)
        case .farcaster:
            if let fid = hit.fid {
                FarcasterStore.shared.add(hit.handle, fid: fid)
            } else {
                FarcasterStore.shared.add(hit.handle)
            }
        case .podcasts:
            FeedFollowStore.podcasts.add(
                FeedFollowEntry(input: hit.displayName, feedURL: hit.feedURL ?? "", title: hit.displayName))
        default:
            break
        }
    }

    /// The connected accounts, for the list the multi-account screen shows.
    var names: [String] {
        switch self {
        case .bluesky:   return BlueskyStore.shared.handles
        case .farcaster: return FarcasterStore.shared.usernames
        case .pinterest:
            let u = PinterestStore.shared.username
            return u.isEmpty ? [] : [u]
        default:         return feedKind!.store.inputs
        }
    }

    /// The list row's short form — Bluesky's ".bsky.social" comes off; a feed
    /// follow shows its learned title (the publication's real name).
    func shortName(_ name: String) -> String {
        switch self {
        case .bluesky:
            name.hasSuffix(".bsky.social") ? String(name.dropLast(".bsky.social".count)) : name
        case .farcaster, .pinterest:
            name
        default:
            feedKind!.store.display(for: name)
        }
    }

    func addName(_ raw: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.add(raw)
        case .farcaster: FarcasterStore.shared.add(raw)
        case .pinterest: PinterestStore.shared.username = PinterestStore.normalize(raw)
        default:         feedKind!.store.add(FeedFollowEntry(input: raw))
        }
    }

    func removeName(_ name: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.remove(name)
        case .farcaster: FarcasterStore.shared.remove(name)
        case .pinterest: PinterestStore.shared.username = ""
        default:         feedKind!.store.remove(input: name)
        }
    }

    /// What the field shows for an existing connection — for the single
    /// bridge (Pinterest), the connected name; for the multi bridges the
    /// field is a fresh "add another", so it starts empty.
    var displayName: String {
        switch self {
        case .pinterest: return PinterestStore.shared.username
        default:         return ""
        }
    }

    /// What lands, for proof lines: "3 posts in".
    var noun: String {
        switch self {
        case .bluesky:   "posts"
        case .farcaster: "casts"
        case .pinterest: "pins"
        default:         feedKind!.noun
        }
    }

    var fieldFooter: String {
        switch self {
        case .bluesky:
            "Type a few letters to find someone, or the full handle — posts are public, so there's no password to give."
        case .farcaster:
            "Type a few letters to find someone, or the exact username — casts are public on the open protocol, so there's no password to give."
        case .pinterest:
            "Just the username — your public pins arrive through Pinterest's own feed, so there's no password to give."
        default:
            feedKind!.fieldFooter
        }
    }

    var recentHeader: String {
        switch self {
        case .bluesky:   "Posts"
        case .farcaster: "Casts"
        case .pinterest: "Pins"
        default:         feedKind!.recentHeader
        }
    }

    var footerLine: String {
        switch self {
        case .bluesky:
            "Read-only, public data only. Likes arrive with sign-in, later."
        case .farcaster:
            "Read-only, public data only — served by the Farcaster team's own public node."
        case .pinterest:
            "Read-only, public boards only — secret boards never appear in the public feed."
        default:
            feedKind!.footerLine
        }
    }

    var canLine: String {
        switch self {
        case .bluesky:   "Reads your public posts."
        case .farcaster: "Reads your public casts."
        case .pinterest: "Reads your public pins."
        default:         feedKind!.canLine
        }
    }

    /// Whether anything is connected — drives the "connected" chrome. For the
    /// multi bridges, the first watched account stands in.
    var currentName: String { names.first ?? "" }

    /// Teardown only (the single Pinterest path + Disconnect): an empty name
    /// clears the connection. Multi-account adds go through `addName`.
    func setName(_ name: String) {
        switch self {
        case .bluesky:
            if name.isEmpty { BlueskyStore.shared.removeAll() } else { BlueskyStore.shared.add(name) }
        case .farcaster:
            if name.isEmpty { FarcasterStore.shared.removeAll() } else { FarcasterStore.shared.add(name) }
        case .pinterest:
            PinterestStore.shared.username = name
        default:
            if name.isEmpty { feedKind!.store.removeAll() }
            else { feedKind!.store.add(FeedFollowEntry(input: name)) }
        }
    }

    func normalize(_ raw: String) -> String {
        switch self {
        case .bluesky:   BlueskyStore.normalize(raw)
        case .farcaster: FarcasterStore.normalize(raw)
        case .pinterest: PinterestStore.normalize(raw)
        default:         feedKind!.normalize(raw)
        }
    }

    @MainActor
    func refresh(context: ModelContext) async -> Int? {
        switch self {
        case .bluesky:   await BlueskyIngest.refresh(context: context)
        case .farcaster: await FarcasterIngest.refresh(context: context)
        case .pinterest: await PinterestIngest.refresh(context: context)
        default:         await FeedFollowIngest.refresh(feedKind!, context: context)
        }
    }
}

/// One screen for every handle-only bridge: state the way in plainly (a
/// public name, nothing else), then show it working.
struct HandleSetupScreen: View {
    let bridge: HandleBridge

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var nameField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false

    /// This bridge's things — cached per appearance and after each sync, rather
    /// than re-fetched twice on every body pass. The source is per-bridge, so
    /// this is the cache path rather than a static @Query.
    @State private var recent: [Thing] = []

    /// The watched accounts (multi bridges) — a local snapshot refreshed on
    /// each add/remove, since the screen doesn't observe the store directly.
    @State private var accountNames: [String] = []

    /// People matching what's typed so far — the field doubles as a finder
    /// on the bridges with public search. Cleared on add and on emptying.
    @State private var hits: [UserSearch.Hit] = []

    private func loadRecent() {
        recent = recentBridgeThings(source: bridge.rawValue, context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: bridge.rawValue)
            nameSection.listRowSeparator(.hidden)
            if bridge.supportsMultiple, !accountNames.isEmpty {
                accountsSection.listRowSeparator(.hidden)
            }
            if !recent.isEmpty {
                RecentThingsSection(header: bridge.recentHeader, things: recent)
                    .listRowSeparator(.hidden)
            }
            // Every connected account is pinnable (ruling 2026-07-12) — except
            // the auto-social ones (Bluesky/Farcaster), which show by default
            // and carry the inverse "Show on Home" toggle instead. Shown once
            // the account has landed a thing — an empty source composes no tile,
            // so its pin would be a dead control.
            if !bridge.currentName.isEmpty, !recent.isEmpty,
               !HomePinnedSources.autoSocial.contains(bridge.rawValue) {
                pinToHomeSection.listRowSeparator(.hidden)
            }
            if !bridge.currentName.isEmpty, HomePinnedSources.autoSocial.contains(bridge.rawValue) {
                showOnHomeSection.listRowSeparator(.hidden)
            }
            if !bridge.currentName.isEmpty {
                BridgeDisconnectSection(
                    bridgeID: bridge.bridgeID, name: bridge.rawValue,
                    teardown: {
                        bridge.setName("")
                        accountNames = []
                        HomePinnedSources.shared.clear(bridge.rawValue)
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(bridge.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadRecent()
            accountNames = bridge.names
            nameField = bridge.displayName
            if !bridge.currentName.isEmpty {
                Task { await sync() }
            }
        }
        // The debounced people search — already-watched accounts stay out of
        // the results; they're in the list above.
        .task(id: nameField) {
            guard bridge.supportsSearch else { return }
            let q = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = await debouncedSearch(q, fetch: {
                let watched = Set(bridge.names)
                return await bridge.search(q)
                    .filter { !watched.contains(bridge.normalize($0.handle)) }
            }) {
                hits = found
            }
        }
    }

    /// Pin to Home (prd 58, Goal 4) — the board grows from the catalog:
    /// connecting an account can end here, without waiting for it to earn
    /// a card the automatic way. Same verb, both directions, as Wallet's
    /// own per-address pin.
    private var pinnedToHome: Bool { HomePinnedSources.shared.isPinned(bridge.rawValue) }

    private var pinToHomeSection: some View {
        Section {
            Button {
                HomePinnedSources.shared.toggle(bridge.rawValue)
                CorpusSignal.shared.bump()
                DSHaptic.tap()
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: pinnedToHome ? "pin.fill" : "pin")
                    Text(pinnedToHome ? "Pinned to Home" : "Pin to Home")
                    Spacer()
                }
                .dsText(.body17).foregroundStyle(pinnedToHome ? DS.tint : DS.textPrimary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Show on Home — the inverse of "Pin to Home" for auto-social sources
    /// (Bluesky/Farcaster): their latest post shows by default, so this brings
    /// back a card the person removed (long-press → Remove from Home, or this
    /// toggle) rather than opting one in. Management lives on the source's own
    /// screen, per ruling 58a.
    private var shownOnHome: Bool { !HomePinnedSources.shared.isHidden(bridge.rawValue) }

    private var showOnHomeSection: some View {
        Section {
            Button {
                // shownOnHome true means visible → hide; false means hidden → show.
                HomePinnedSources.shared.setHidden(bridge.rawValue, shownOnHome)
                CorpusSignal.shared.bump()
                DSHaptic.tap()
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: shownOnHome ? "pin.fill" : "pin.slash")
                    Text(shownOnHome ? "On Home" : "Show on Home")
                    Spacer()
                }
                .dsText(.body17).foregroundStyle(shownOnHome ? DS.tint : DS.textPrimary)
            }
            .buttonStyle(.plain)
        } footer: {
            Text(shownOnHome
                 ? "Your latest \(bridge.rawValue) post shows on Home. Turn this off — or long-press the card — to remove it."
                 : "Removed from Home. Turn this on to show your latest \(bridge.rawValue) post again.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    /// The watched-accounts list (Bluesky/Farcaster) — each removable, the
    /// way the wallet manager lists watched addresses.
    private var accountsSection: some View {
        Section {
            ForEach(accountNames, id: \.self) { name in
                HStack(spacing: DS.Space.s3) {
                    BridgeIcon(name: bridge.rawValue, size: 28, circular: true)
                    Text(bridge.shortName(name)).dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        bridge.removeName(name)
                        accountNames = bridge.names
                        DSHaptic.tap()
                    } label: { Label("Remove", systemImage: "minus.circle") }
                }
                .dsListCardRow()
                .listRowSeparator(.hidden)
            }
        } header: {
            Text(accountNames.count == 1 ? "Watching" : "Watching \(accountNames.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    private var nameSection: some View {
        // Field + search hits + status in ONE list row (a VStack) — a headed
        // Section of stacked rows leaks a hairline between them that row-level
        // .listRowSeparator(.hidden) won't suppress (SwiftUI first-post-header
        // separator). Design law: no hairlines, zero exceptions.
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                BridgeFieldRow(placeholder: bridge.placeholder, text: $nameField,
                               buttonLabel: buttonLabel,
                               prefix: bridge.fieldPrefix, suffix: bridge.fieldSuffix,
                               action: connect)
                ForEach(hits) { hit in
                    BridgeSearchResultRow(
                        imageURL: hit.avatarURL, fallbackIcon: bridge.rawValue,
                        title: hit.displayName, subtitle: "@\(bridge.shortName(hit.handle))",
                        action: { pick(hit) })
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Fetching \(bridge.noun)…"),
                                     result: result, resultIsError: resultIsError)
            }
            .dsListCardRow()
        } header: {
            Text(bridge.supportsMultiple ? "Add \(anArticle) \(bridge.nameNoun)"
                                         : "Your \(bridge.nameNoun)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        } footer: {
            Text(LocalizedStringKey(bridge.fieldFooter))
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var buttonLabel: String {
        if bridge.supportsMultiple { return "Add" }
        return bridge.currentName.isEmpty ? "Connect" : "Update"
    }

    private var anArticle: String {
        bridge.nameNoun.first.map { "aeiou".contains($0) ? "an" : "a" } ?? "a"
    }

    private var footerSection: some View {
        Section {
            Text(LocalizedStringKey(bridge.footerLine))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func connect() {
        let name = bridge.normalize(nameField)
        guard !name.isEmpty else { return }
        if bridge.supportsMultiple {
            bridge.addName(name)
            accountNames = bridge.names
            nameField = ""          // the field is ready for the next one
        } else {
            bridge.setName(name)
            nameField = name
        }
        afterAdd()
    }

    /// A tapped search result connects that account — same path as typing
    /// the name exactly, minus the typing.
    private func pick(_ hit: UserSearch.Hit) {
        bridge.add(hit: hit)
        accountNames = bridge.names
        nameField = ""
        afterAdd()
    }

    private func afterAdd() {
        hits = []
        DSHaptic.tap()
        Task { await sync() }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await bridge.refresh(context: modelContext)
        syncing = false
        loadRecent()
        guard let added else {
            result = String(localized: "Couldn't find that \(bridge.nameNoun) — check the spelling.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) \(bridge.noun) in") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) \(bridge.noun) in" : "Synced just now"
        if store.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                   proof: proof, can: [bridge.canLine]) {
            DSHaptic.success()
        }
    }
}
