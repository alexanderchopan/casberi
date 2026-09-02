import SwiftUI
import SwiftData

/// Radicle, connected — peer-to-peer Git. Watch a repo by its id and its
/// patches and issues land as they happen.
///
/// No account, no key: `radicle-httpd` is a read-only gateway with no
/// credential of any kind, so there is nothing here to mint and nothing a leak
/// could spend.
///
/// **The seed field is not a setting, it is the trust boundary**, and the
/// screen says so in the one note it spends on it. Radicle has no central host
/// and no global index: whichever seed you name is both the only thing that
/// can answer you and the thing that learns which repos you asked about. Every
/// other bridge here reaches a host we chose; this is the first Work seat where
/// the person chooses, which is why `NetworkReach` cannot declare it and the
/// requests name their service to `NetworkLedger` instead (§289).
struct RadicleScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var radicle = RadicleStore.shared
    @State private var repoField = ""
    @State private var seedField = ""
    @State private var syncing = false
    /// A repo added mid-sync requeues it, so the new watch lands now rather
    /// than next visit (the GeckoTerminal lesson).
    @State private var syncPending = false
    @State private var searching = false
    @State private var found: [RadicleWire.Repo] = []
    @State private var lastResult: String?
    @State private var lastResultIsError = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Radicle",
                mode: .noAccount,
                intro: "Name a repo and its patches and issues arrive as they happen. Radicle has no central host, so the seed you pick is the only thing that can answer you, and it sees what you ask for.",
                connected: radicle.connected)
            if radicle.connected {
                RoomDoor(name: "Radicle", source: "Radicle")
                    .listRowSeparator(.hidden)
            }
            addSection.listRowSeparator(.hidden)
            if !found.isEmpty { resultsSection }
            seedSection.listRowSeparator(.hidden)
            if !radicle.repos.isEmpty { watchlistSection }
            if radicle.connected {
                BridgeDisconnectSection(
                    bridgeID: "radicle", name: "Radicle",
                    teardown: { RadicleStore.shared.disconnect() }
                ).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Radicle")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Radicle")
        .onAppear {
            seedField = radicle.seed
            // Opening the screen doesn't connect — watching a repo does.
            if radicle.connected { Task { await sync() } }
        }
    }

    // MARK: - Sections

    /// One field, two verbs. WATCH takes an id straight; FIND asks the seed to
    /// turn a name into one.
    ///
    /// **FIND is a separate, explicit tap because it is measured expensive** —
    /// `/repos/search` answers in 5.3-6.5s against 0.26s for every other read
    /// (2026-08-18), so an as-you-type search would leave the screen looking
    /// frozen for six seconds a keystroke. It also cannot be the only door: a
    /// seed serves only what it seeds, so a repo it doesn't hold is unfindable
    /// by name and reachable by id.
    private var addSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Repo id, or a name to find"),
                            text: $repoField,
                            actionLabel: String(localized: "Watch"),
                            focus: $fieldFocused,
                            isArmed: RadicleWire.normalizeRID(repoField) != nil,
                            secondaryLabel: String(localized: "Find"),
                            secondaryArmed: !repoField.trimmingCharacters(in: .whitespaces).isEmpty
                                && RadicleWire.normalizeRID(repoField) == nil,
                            secondaryAction: find,
                            action: watch)
                BridgeSyncStatusRows(syncing: syncing || searching,
                                     syncingLine: searching
                                        ? String(localized: "Asking the seed…")
                                        : String(localized: "Reading the seed…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                DSSlabNote(text: "An id like rad:z3gqcJ…, or any Radicle link.")
            }
        }
        .dsSlabSection()
    }

    /// What FIND came back with. Named repos with their delegates, so picking
    /// one is a decision about a real project rather than a hash.
    private var resultsSection: some View {
        Section {
            ForEach(found, id: \.rid) { repo in
                Button { watch(repo.rid) } label: {
                    repoRow(rid: repo.rid, name: repo.name,
                            detail: repo.description
                                ?? repo.delegates.map(\.display).joined(separator: ", "))
                }
                .buttonStyle(.plain)
                .dsListCardRow()
            }
        } header: {
            Text(found.count == 1 ? "1 result" : "\(found.count) results")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    /// The seed. Editable, defaulted, and never silently changed.
    private var seedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Seed host"),
                            text: $seedField,
                            actionLabel: String(localized: "Use"),
                            keyboard: .URL,
                            isArmed: RadicleWire.normalizeSeed(seedField) != nil
                                && RadicleWire.normalizeSeed(seedField) != radicle.seed,
                            action: useSeed)
                DSSlabNote(text: "A seed answers only for the repos it seeds.")
            }
        }
        .dsSlabSection()
    }

    private var watchlistSection: some View {
        Section {
            ForEach(radicle.repos, id: \.self) { rid in
                repoRow(rid: rid,
                        name: radicle.name(for: rid) ?? rid,
                        detail: radicle.name(for: rid) == nil ? "" : rid)
                    .dsListCardRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { unwatch(rid) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    // A swipe has no Mac-mouse equivalent — right-click mirrors
                    // it (Mac polish, 2026-07-28).
                    .contextMenu {
                        Button(role: .destructive) { unwatch(rid) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
        } header: {
            Text(radicle.repos.count == 1 ? "Watching" : "Watching \(radicle.repos.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    private func repoRow(rid: String, name: String, detail: String) -> some View {
        HStack(spacing: DS.Space.s3) {
            // Square, not round — a repo is a project, not a person (the mark
            // grammar ruling, prd §184).
            BridgeIcon(name: "Radicle", size: DS.Mark.list, circular: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private func watch() { watch(repoField) }

    private func watch(_ raw: String) {
        guard let id = RadicleWire.normalizeRID(raw) else {
            lastResult = String(localized: "That isn't a Radicle repo id.")
            lastResultIsError = true
            return
        }
        guard radicle.add(id) else {
            lastResult = String(localized: "Already watching that repo.")
            lastResultIsError = false
            repoField = ""
            return
        }
        repoField = ""
        found = []
        fieldFocused = false
        DSHaptic.tap()
        Task { await sync() }
    }

    private func unwatch(_ rid: String) {
        let name = radicle.name(for: rid) ?? rid
        radicle.remove(rid)
        // Its rows leave with it (prd §286). Every ref carries the RID as its
        // third component, so the prefix is exact — matched on `sourceRef`
        // rather than on a display name, which two repos can share.
        FollowPrune.remove(source: "Radicle", context: modelContext) {
            $0.sourceRef?.contains(":\(rid):") == true
        }
        lastResult = String(localized: "Stopped watching \(name).")
        lastResultIsError = false
        DSHaptic.tap()
        Task { await sync() }
    }

    /// Points every later read at a different seed.
    ///
    /// Landed rows are deliberately LEFT ALONE. A patch that was proposed
    /// happened whether or not this seed still carries it, and deleting real
    /// history because the person changed which node they ask would be a far
    /// worse surprise than a permalink that has moved. The snapshots ARE
    /// cleared, because they are this seed's counts and diffing them against
    /// another node's would report every difference between two seeds as news.
    private func useSeed() {
        guard let host = RadicleWire.normalizeSeed(seedField), host != radicle.seed else { return }
        radicle.seed = host
        seedField = host
        for rid in radicle.repos { radicle.remember(RadicleWire.Snapshot(), for: rid) }
        DSHaptic.tap()
        Task {
            let (ok, version) = await RadicleIngest.probeSeed(host)
            guard !ok else { await sync(); return }
            lastResult = version == nil
                ? String(localized: "Couldn't reach \(host).")
                : String(localized: "\(host) doesn't answer as a Radicle seed.")
            lastResultIsError = true
        }
    }

    private func find() {
        let query = repoField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !searching else { return }
        searching = true
        lastResult = nil
        Task {
            defer { searching = false }
            let hits = await RadicleIngest.search(seed: radicle.seed, query: query)
            found = hits
            if hits.isEmpty {
                // Not an error: a seed genuinely may not hold it, which is the
                // one thing about this network the copy must keep saying.
                lastResult = String(localized: "\(radicle.seed) doesn't seed anything called that.")
                lastResultIsError = false
            }
        }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard radicle.connected else {
            // Unwatching the last repo leaves nothing to sync — clear the seat
            // rather than leave a dead one.
            store.remove("radicle")
            return
        }
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let added = await RadicleIngest.refresh(context: modelContext)
            // Disconnected mid-sync (teardown ran while this awaited) — don't
            // resurrect the seat the person just removed.
            guard radicle.connected else { store.remove("radicle"); return }
            if let added {
                lastResult = added > 0
                    ? String(localized: "\(added) new")
                    : String(localized: "Up to date")
                lastResultIsError = false
                let proof = added > 0
                    ? String(localized: "\(added) in")
                    : String(localized: "Synced just now")
                store.registerConnected(
                    id: "radicle", name: "Radicle", proof: proof,
                    can: ["Reads patches and issues from the repos you watch, on the seed you name.",
                          "Read-only — the gateway has no credential and no way to write."])
            } else {
                lastResult = String(localized: "Couldn't reach \(radicle.seed) — check your connection.")
                lastResultIsError = true
            }
        } while syncPending && radicle.connected
    }
}
