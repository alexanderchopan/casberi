import SwiftUI
import SwiftData

/// The handle-only bridges — Bluesky and Farcaster connect by public name
/// alone (no password, no token, nothing stored but the name), so their
/// screens are the same shape. This enum carries the words that differ,
/// the way TokenBridge does for the paste-a-token screens.
enum HandleBridge: String {
    case bluesky   = "Bluesky"
    case farcaster = "Farcaster"
    case pinterest = "Pinterest"

    /// BridgeStore id, and the connected-strip route.
    var bridgeID: String {
        switch self {
        case .bluesky:   "bsky"
        case .farcaster: "fc"
        case .pinterest: "pinterest"
        }
    }

    /// What the person types — Bluesky says handle, Farcaster says username.
    var nameNoun: String {
        switch self {
        case .bluesky:   "handle"
        case .farcaster, .pinterest: "username"
        }
    }

    var placeholder: String {
        switch self {
        case .bluesky:   "you"
        case .farcaster, .pinterest: "yourname"
        }
    }

    /// The fixed part of the name, shown around the field so the person
    /// types only what's theirs.
    var fieldPrefix: String? {
        switch self {
        case .bluesky:   nil
        case .farcaster: "farcaster.xyz/"
        case .pinterest: "pinterest.com/"
        }
    }

    var fieldSuffix: String? {
        switch self {
        case .bluesky:   ".bsky.social"
        case .farcaster, .pinterest: nil
        }
    }

    /// Bluesky and Farcaster watch a LIST of accounts (2026-07-10) — a small
    /// following feed, not just your own mirror. Pinterest stays single.
    var supportsMultiple: Bool { self == .bluesky || self == .farcaster }

    /// Bluesky and Farcaster have public, keyless people search (2026-07-11)
    /// — the field doubles as a finder. Pinterest has no such surface.
    var supportsSearch: Bool { self == .bluesky || self == .farcaster }

    func search(_ query: String) async -> [UserSearch.Hit] {
        switch self {
        case .bluesky:   await UserSearch.bluesky(query)
        case .farcaster: await UserSearch.farcaster(query)
        case .pinterest: []
        }
    }

    /// A tapped search hit connects like a typed name — plus, for Farcaster,
    /// the fid the search already carried (saves the first sync's resolve).
    func add(hit: UserSearch.Hit) {
        switch self {
        case .bluesky:
            BlueskyStore.shared.add(hit.handle)
        case .farcaster:
            let name = FarcasterStore.normalize(hit.handle)
            FarcasterStore.shared.add(name)
            if let fid = hit.fid { FarcasterStore.shared.setFid(fid, for: name) }
        case .pinterest:
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
        }
    }

    /// The list row's short form — Bluesky's ".bsky.social" comes off.
    func shortName(_ name: String) -> String {
        self == .bluesky && name.hasSuffix(".bsky.social")
            ? String(name.dropLast(".bsky.social".count)) : name
    }

    func addName(_ raw: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.add(raw)
        case .farcaster: FarcasterStore.shared.add(raw)
        case .pinterest: PinterestStore.shared.username = PinterestStore.normalize(raw)
        }
    }

    func removeName(_ name: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.remove(name)
        case .farcaster: FarcasterStore.shared.remove(name)
        case .pinterest: PinterestStore.shared.username = ""
        }
    }

    /// What the field shows for an existing connection — for the single
    /// bridge (Pinterest), the connected name; for the multi bridges the
    /// field is a fresh "add another", so it starts empty.
    var displayName: String {
        switch self {
        case .bluesky, .farcaster: return ""
        case .pinterest:           return PinterestStore.shared.username
        }
    }

    /// What lands, for proof lines: "3 posts in".
    var noun: String {
        switch self {
        case .bluesky:   "posts"
        case .farcaster: "casts"
        case .pinterest: "pins"
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
        }
    }

    var recentHeader: String {
        switch self {
        case .bluesky:   "Your posts"
        case .farcaster: "Your casts"
        case .pinterest: "Your pins"
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
        }
    }

    var canLine: String {
        switch self {
        case .bluesky:   "Reads your public posts."
        case .farcaster: "Reads your public casts."
        case .pinterest: "Reads your public pins."
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
        }
    }

    func normalize(_ raw: String) -> String {
        switch self {
        case .bluesky:   BlueskyStore.normalize(raw)
        case .farcaster: FarcasterStore.normalize(raw)
        case .pinterest: PinterestStore.normalize(raw)
        }
    }

    @MainActor
    func refresh(context: ModelContext) async -> Int? {
        switch self {
        case .bluesky:   await BlueskyIngest.refresh(context: context)
        case .farcaster: await FarcasterIngest.refresh(context: context)
        case .pinterest: await PinterestIngest.refresh(context: context)
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
            if !bridge.currentName.isEmpty {
                BridgeDisconnectSection(
                    bridgeID: bridge.bridgeID, name: bridge.rawValue,
                    teardown: { bridge.setName(""); accountNames = [] }
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
        // The debounced people search — each keystroke restarts the task,
        // so only a 300ms pause actually asks the network. Already-watched
        // accounts stay out of the results; they're in the list above.
        .task(id: nameField) {
            guard bridge.supportsSearch else { return }
            let q = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2 else {
                if !hits.isEmpty { hits = [] }
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let watched = Set(bridge.names)
            let found = await bridge.search(q)
                .filter { !watched.contains(bridge.normalize($0.handle)) }
            guard !Task.isCancelled else { return }
            hits = found
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
            }
        } header: {
            Text(accountNames.count == 1 ? "Watching" : "Watching \(accountNames.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    private var nameSection: some View {
        Section {
            BridgeFieldRow(placeholder: bridge.placeholder, text: $nameField,
                           buttonLabel: buttonLabel,
                           prefix: bridge.fieldPrefix, suffix: bridge.fieldSuffix,
                           action: connect)
            ForEach(hits) { hit in
                Button { pick(hit) } label: {
                    HStack(spacing: DS.Space.s3) {
                        if let avatar = hit.avatarURL {
                            RemoteThumb(urlString: avatar, size: 28,
                                        fallback: bridge.rawValue, circular: true)
                        } else {
                            BridgeIcon(name: bridge.rawValue, size: 28, circular: true)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(hit.displayName)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Text("@\(bridge.shortName(hit.handle))")
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(DS.surfaceSheet)
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: "Fetching \(bridge.noun)…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text(bridge.supportsMultiple ? "Add \(anArticle) \(bridge.nameNoun)"
                                         : "Your \(bridge.nameNoun)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        } footer: {
            Text(bridge.fieldFooter)
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
            Text(bridge.footerLine)
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
        hits = []
        DSHaptic.tap()
        Task { await sync() }
    }

    /// A tapped search result connects that account — same path as typing
    /// the name exactly, minus the typing.
    private func pick(_ hit: UserSearch.Hit) {
        bridge.add(hit: hit)
        accountNames = bridge.names
        nameField = ""
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
            result = "Couldn't find that \(bridge.nameNoun) — check the spelling."
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? "\(added) \(bridge.noun) in" : "Up to date"
        let proof = added > 0 ? "\(added) \(bridge.noun) in" : "Synced just now"
        if store.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                   proof: proof, can: [bridge.canLine]) {
            DSHaptic.success()
        }
    }
}
