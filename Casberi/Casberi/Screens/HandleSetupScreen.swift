import SwiftUI
import SwiftData

/// The handle-only bridges — Bluesky and Farcaster connect by public name
/// alone (no password, no token, nothing stored but the name), so their
/// screens are the same shape. This enum carries the words that differ,
/// the way TokenBridge does for the paste-a-token screens.
enum HandleBridge: String {
    case bluesky   = "Bluesky"
    case farcaster = "Farcaster"

    /// BridgeStore id, and the connected-strip route.
    var bridgeID: String {
        switch self {
        case .bluesky:   "bsky"
        case .farcaster: "fc"
        }
    }

    /// What the person types — Bluesky says handle, Farcaster says username.
    var nameNoun: String {
        switch self {
        case .bluesky:   "handle"
        case .farcaster: "username"
        }
    }

    var placeholder: String {
        switch self {
        case .bluesky:   "you"
        case .farcaster: "yourname"
        }
    }

    /// The fixed part of the name, shown around the field so the person
    /// types only what's theirs.
    var fieldPrefix: String? {
        switch self {
        case .bluesky:   nil
        case .farcaster: "farcaster.xyz/"
        }
    }

    var fieldSuffix: String? {
        switch self {
        case .bluesky:   ".bsky.social"
        case .farcaster: nil
        }
    }

    /// What the field shows for an existing connection — Bluesky's default
    /// suffix comes off so the display matches what the person typed.
    var displayName: String {
        switch self {
        case .bluesky:
            let name = BlueskyStore.shared.handle
            return name.hasSuffix(".bsky.social")
                ? String(name.dropLast(".bsky.social".count))
                : name
        case .farcaster:
            return FarcasterStore.shared.username
        }
    }

    /// What lands, for proof lines: "3 posts in".
    var noun: String {
        switch self {
        case .bluesky:   "posts"
        case .farcaster: "casts"
        }
    }

    var fieldFooter: String {
        switch self {
        case .bluesky:
            "Just the handle — your posts are public, so there's no password to give."
        case .farcaster:
            "Just the username — casts are public on the open protocol, so there's no password to give."
        }
    }

    var recentHeader: String {
        switch self {
        case .bluesky:   "Your posts"
        case .farcaster: "Your casts"
        }
    }

    var footerLine: String {
        switch self {
        case .bluesky:
            "Read-only, public data only. Likes arrive with sign-in, later."
        case .farcaster:
            "Read-only, public data only — served by the Farcaster team's own public node."
        }
    }

    var canLine: String {
        switch self {
        case .bluesky:   "Reads your public posts."
        case .farcaster: "Reads your public casts."
        }
    }

    /// The stored name, read straight from the bridge's own store so the
    /// screen tracks it like the originals did.
    var currentName: String {
        switch self {
        case .bluesky:   BlueskyStore.shared.handle
        case .farcaster: FarcasterStore.shared.username
        }
    }

    func setName(_ name: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.handle = name
        case .farcaster: FarcasterStore.shared.username = name
        }
    }

    func normalize(_ raw: String) -> String {
        switch self {
        case .bluesky:   BlueskyStore.normalize(raw)
        case .farcaster: FarcasterStore.normalize(raw)
        }
    }

    @MainActor
    func refresh(context: ModelContext) async -> Int? {
        switch self {
        case .bluesky:   await BlueskyIngest.refresh(context: context)
        case .farcaster: await FarcasterIngest.refresh(context: context)
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

    private func loadRecent() {
        recent = recentBridgeThings(source: bridge.rawValue, context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: bridge.rawValue)
            nameSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                RecentThingsSection(header: bridge.recentHeader, things: recent)
                    .listRowSeparator(.hidden)
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
            nameField = bridge.displayName
            if !bridge.currentName.isEmpty {
                Task { await sync() }
            }
        }
    }

    private var nameSection: some View {
        Section {
            BridgeFieldRow(placeholder: bridge.placeholder, text: $nameField,
                           buttonLabel: bridge.currentName.isEmpty ? "Connect" : "Update",
                           prefix: bridge.fieldPrefix, suffix: bridge.fieldSuffix,
                           action: connect)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: "Fetching your \(bridge.noun)…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("YOUR \(bridge.nameNoun)").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text(bridge.fieldFooter)
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
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
        bridge.setName(name)
        nameField = name
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
