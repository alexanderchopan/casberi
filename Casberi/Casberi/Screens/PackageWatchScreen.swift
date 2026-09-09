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
    /// This week's releases per watched package.
    @State private var weekly: [String: (week: Int, new: Bool)] = [:]

    var body: some View {
        AccountPage(
            name: registry.displayName, seatID: registry.bridgeID,
            // `registry.displayName` is what `PackageWatchBridge` stamps as
            // `source:`, so the Activity row and the rows can never disagree.
            source: registry.displayName,
            state: AccountPageState.of(name: registry.displayName, seatID: registry.bridgeID,
                                       connected: connected, store: store),
            mode: .noAccount,
            rows: rows,
            query: nameField,
            onRemoveRow: unwatch,
            teardown: { PackageStore.shared.disconnect(registry) },
            sheet: $sheet,
            act: { addBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            countWeek()
            // Opening the page doesn't connect — watching a package does.
            if connected { Task { await sync() } }
        }
        .onChange(of: watched) { _, _ in countWeek() }
    }

    // MARK: - The roster

    /// One row per watched package. The version last seen is the one fact that
    /// makes a row worth more than an echo of what was typed, so it leads the
    /// subline; "Watching" stands until the first read lands, rather than a
    /// blank or a guessed version.
    private var rows: [AccountPageShape.Row] {
        watched.map { name in
            let counted = weekly[name.lowercased()] ?? (week: 0, new: false)
            let version = packages.version(registry, name)
            let released = AccountPageShape.subline(nouns: String(localized: "releases"),
                                                    weekCount: counted.week)
            return AccountPageShape.Row(
                id: name, title: name,
                subline: version.map { "\($0) · \(released)" } ?? String(localized: "Watching"),
                weekCount: counted.week, hasNew: counted.new,
                isYou: false, avatarURL: nil)
        }
    }

    /// This week's releases per package, keyed off each row's REF (prd §659).
    ///
    /// The ingest stamps no `authorHandle` — a package is not a person — so
    /// the identity is read back out of `sourceRef`, which carries the
    /// lowercased name by construction (`PackageShape.name(fromRef:)`, the
    /// same parser `unwatch` prunes with). Radicle, the other keyless watch
    /// list with nothing author-shaped to stamp, reads its rows the same way.
    private func countWeek() {
        weekly = AccountWeek.counts(source: registry.displayName, seatID: registry.bridgeID,
                                    context: modelContext) {
            PackageShape.name(fromRef: $0.sourceRef, registry: registry)
        }
    }


    // MARK: - Sections

    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: placeholder, text: $nameField,
                        actionLabel: String(localized: "Watch"),
                        focus: $fieldFocused, action: watch)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading the registry…"),
                                 proof: lastResult)
            // Names the accepted shapes, because pasting a package page is
            // how a lot of people will arrive (`normalize` takes the name).
            DSSlabNote(text: note, plain: true)
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
            String(localized: "A name like react or @vercel/og, or any npm link. Each new version lands, and so does a deprecation.")
        case .pypi:
            String(localized: "A name like requests, or any PyPI link. Each new version lands, stamped with when it was published.")
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

    private func unwatch(_ name: String) {
        packages.remove(registry, name)
        // Its rows leave with it (prd §286). Every ref carries the registry
        // and the lowercased package name, which is what makes this matchable
        // without parsing a title — one parser, shared with `countWeek`, so a
        // prune and a count can never disagree about which rows are whose.
        let needle = name.lowercased()
        FollowPrune.remove(source: registry.displayName, context: modelContext) { thing in
            PackageShape.name(fromRef: thing.sourceRef, registry: registry) == needle
        }
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
