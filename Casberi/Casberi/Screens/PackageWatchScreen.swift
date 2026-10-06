import SwiftUI
import SwiftData

/// npm and PyPI, connected — one screen, parameterised by registry.
///
/// The two seats are genuinely the same screen: name a package, its releases
/// land. Everything that differs between them (the placeholder, the note, what
/// a row's subtitle says) comes off `PackageRegistry`, so there is one
/// behaviour to maintain rather than two that drift.
///
/// Modelled on `HuggingFaceScreen` — the other keyless watch list — down to the
/// requeue-if-a-sync-is-in-flight handling, because adding a second package
/// while the first is still reading is the normal way people use this.
struct PackageWatchScreen: View {
    let registry: PackageRegistry

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var packages = PackageStore.shared
    @State private var nameField = ""
    @State private var syncing = false
    /// A package added while a sync is mid-flight requeues it, so the new
    /// watch lands now rather than next visit (the GeckoTerminal lesson).
    @State private var syncPending = false
    @State private var lastResult: BridgeProof?
    @FocusState private var fieldFocused: Bool

    private var watched: [String] { packages.list(registry) }
    private var connected: Bool { packages.connected(registry) }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: registry.displayName, seatID: registry.bridgeID,
            // `registry.displayName` is what `PackageWatchBridge` stamps as
            // `source:`, so the Activity row and the rows can never disagree.
            source: registry.displayName,
            state: AccountPageState.of(name: registry.displayName, seatID: registry.bridgeID,
                                       connected: connected, store: store),
            mode: .noAccount,
            // What you watch is Work's Watching list now (prd §1119): this
            // page starts the first watch, and disconnects.
            rows: [],
            teardown: { PackageStore.shared.disconnect(registry) },
            sheet: $sheet,
            act: { addBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            // Opening the page doesn't connect — watching a package does.
            if connected { Task { await sync() } }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if connected {
                FollowListDoor(room: .work, count: watched.count)
            } else {
                DSSlabField(placeholder: placeholder, text: $nameField,
                            actionLabel: String(localized: "Watch"),
                            focus: $fieldFocused, action: watch)
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading the registry…"),
                                 proof: lastResult)
            // Names the accepted shapes, because pasting a package page is
            // how a lot of people will arrive (`normalize` takes the name).
            if !connected { DSSlabNote(text: note, plain: true) }
        }
    }

    private var placeholder: String {
        switch registry {
        case .npm:  String(localized: "Package name, or its npm link")
        case .pypi: String(localized: "Package name, or its PyPI link")
        }
    }

    private var note: String {
        switch registry {
        case .npm:
            String(localized: "Like react or @vercel/og. Each new version lands, and so does a deprecation.")
        case .pypi:
            String(localized: "Like requests. Each new version lands, stamped with when it was published.")
        }
    }




    // MARK: - Actions

    private func watch() {
        let name = registry.normalize(nameField)
        guard !name.isEmpty else { return }
        guard packages.add(registry, name) else {
            lastResult = .says(String(localized: "Already watching \(name)."))
            nameField = ""
            return
        }
        nameField = ""
        fieldFocused = false
        DSHaptic.tap()
        Task { await sync() }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard connected else {
            // Unwatching the last package leaves nothing to sync — clear the
            // seat rather than leave a dead one.
            store.remove(registry.bridgeID)
            return
        }
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let added = await PackageIngest.refresh(registry, context: modelContext)
            // Disconnected mid-sync (teardown ran while this awaited) — don't
            // resurrect the seat the person just removed.
            guard connected else { store.remove(registry.bridgeID); return }
            if let added {
                lastResult = added > 0 ? .landed(added) : .upToDate
                let proof = added > 0
                    ? String(localized: "\(added) in")
                    : String(localized: "Synced just now")
                store.registerConnected(
                    id: registry.bridgeID, name: registry.displayName, proof: proof,
                    can: ["Reads the current version of the packages you watch.",
                          "Read-only — it never installs, publishes, or signs in."])
            } else {
                lastResult = .failed(String(localized: "Couldn't reach \(registry.displayName) — check your connection."))
            }
        } while syncPending && connected
    }
}
