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
    @State private var lastResult: BridgeProof?
    @FocusState private var fieldFocused: Bool

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?
    /// This week's rows per watched repo.
    @State private var weekly: [String: (week: Int, new: Bool)] = [:]

    var body: some View {
        AccountPage(
            name: "Radicle", seatID: "radicle", source: "Radicle",
            state: AccountPageState.of(name: "Radicle", seatID: "radicle",
                                       connected: radicle.connected, store: store),
            intro: "Patches and issues as they happen. No central host: the seed you pick answers, and sees what you ask for.",
            mode: .noAccount,
            rows: rows,
            query: repoField,
            onRemoveRow: unwatch,
            teardown: { RadicleStore.shared.disconnect() },
            sheet: $sheet,
            act: {
                addBlock
                if !found.isEmpty { resultsBlock }
            },
            more: { seedBlock },
            keySheet: { EmptyView() }
        )
        .onAppear {
            seedField = radicle.seed
            countWeek()
            // Opening the page doesn't connect — watching a repo does.
            if radicle.connected { Task { await sync() } }
        }
        .onChange(of: radicle.repos) { _, _ in countWeek() }
    }

    // MARK: - The roster

    /// One row per watched repo — its name where the seed gave one, its id
    /// otherwise, and what landed from it this week.
    private var rows: [AccountPageShape.Row] {
        radicle.repos.map { rid in
            let counted = weekly[rid.lowercased()] ?? (week: 0, new: false)
            return AccountPageShape.Row(
                id: rid, title: radicle.name(for: rid) ?? rid,
                subline: AccountPageShape.subline(nouns: String(localized: "patches, issues"),
                                                  weekCount: counted.week),
                weekCount: counted.week, hasNew: counted.new,
                isYou: false, avatarURL: nil)
        }
    }

    /// This week's rows per repo. Nothing stamps the repo id in a field of
    /// its own — every ref carries it as a component — so a row is matched
    /// back to the repo it belongs to the same way `unwatch` prunes: on the
    /// ref, which is exact where a display name two repos can share is not.
    private func countWeek() {
        let watched = radicle.repos
        weekly = AccountWeek.counts(source: "Radicle", seatID: "radicle",
                                    context: modelContext) { thing in
            guard let ref = thing.sourceRef else { return nil }
            return watched.first { ref.contains(":\($0):") }
        }
    }


    /// One field, two verbs. WATCH takes an id straight; FIND asks the seed to
    /// turn a name into one.
    ///
    /// **FIND is a separate, explicit tap because it is measured expensive** —
    /// `/repos/search` answers in 5.3-6.5s against 0.26s for every other read
    /// (2026-08-18), so an as-you-type search would leave the screen looking
    /// frozen for six seconds a keystroke. It also cannot be the only door: a
    /// seed serves only what it seeds, so a repo it doesn't hold is unfindable
    /// by name and reachable by id.
    @ViewBuilder private var addBlock: some View {
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
                                 proof: lastResult)
            DSSlabNote(text: "An id like rad:z3gqcJ…, or any Radicle link.", plain: true)
        }
    }

    /// What FIND came back with. Named repos with their delegates, so picking
    /// one is a decision about a real project rather than a hash.
    @ViewBuilder private var resultsBlock: some View {
        Text(AccountPageShape.onLabel("Radicle"))
            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            .padding(.top, DS.Space.s2)
        ForEach(found, id: \.rid) { repo in
            Button { watch(repo.rid) } label: {
                repoRow(rid: repo.rid, name: repo.name,
                        detail: repo.description
                            ?? repo.delegates.map(\.display).joined(separator: ", "))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The seed. Editable, defaulted, and never silently changed.
    @ViewBuilder private var seedBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: String(localized: "Seed host"),
                        text: $seedField,
                        actionLabel: String(localized: "Use"),
                        keyboard: .URL,
                        isArmed: RadicleWire.normalizeSeed(seedField) != nil
                            && RadicleWire.normalizeSeed(seedField) != radicle.seed,
                        action: useSeed)
            DSSlabNote(text: "A seed answers only for the repos it seeds.", plain: true)
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
            lastResult = .failed(String(localized: "That isn't a Radicle repo id."))
            return
        }
        guard radicle.add(id) else {
            lastResult = .says(String(localized: "Already watching that repo."))
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
        lastResult = .says(String(localized: "Stopped watching \(name)."))
        DSHaptic.tap()
        countWeek()
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
            lastResult = version == nil ? .says(String(localized: "Couldn't reach \(host).")) : .says(String(localized: "\(host) doesn't answer as a Radicle seed."))
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
                lastResult = .says(String(localized: "\(radicle.seed) doesn't seed anything called that."))
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
                lastResult = added > 0 ? .landed(added) : .upToDate
                let proof = added > 0
                    ? String(localized: "\(added) in")
                    : String(localized: "Synced just now")
                store.registerConnected(
                    id: "radicle", name: "Radicle", proof: proof,
                    can: ["Reads patches and issues from the repos you watch, on the seed you name.",
                          "Read-only — the gateway has no credential and no way to write."])
            } else {
                lastResult = .failed(String(localized: "Couldn't reach \(radicle.seed) — check your connection."))
            }
        } while syncPending && radicle.connected
    }
}
