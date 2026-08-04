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
    @State private var lastResult: String?
    @State private var lastResultIsError = false
    @State private var flipTrigger = 0
    @FocusState private var fieldFocused: Bool

    private var watched: [String] { packages.list(registry) }
    private var connected: Bool { packages.connected(registry) }

    var body: some View {
        List {
            BridgeSetupHeader(name: registry.displayName, connected: connected,
                              flipTrigger: flipTrigger)
            addSection.listRowSeparator(.hidden)
            if !watched.isEmpty {
                watchlistSection
            }
            if connected {
                ChipLiveNote(name: registry.displayName, verb: "for what just shipped.")
                    .listRowSeparator(.hidden)
                BridgeDisconnectSection(
                    bridgeID: registry.bridgeID, name: registry.displayName,
                    teardown: { PackageStore.shared.disconnect(registry) }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: registry.displayName)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(registry.displayName)
        .onAppear {
            // Opening the screen doesn't connect — watching a package does.
            if connected { Task { await sync() } }
        }
    }

    // MARK: - Sections

    private var addSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: placeholder, text: $nameField,
                            actionLabel: String(localized: "WATCH"),
                            focus: $fieldFocused, action: watch)
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading the registry…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                // Names the accepted shapes, because pasting a package page is
                // how a lot of people will arrive (`normalize` takes the name).
                DSSlabNote(text: note)
            }
        }
        .dsSlabSection()
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

    private var watchlistSection: some View {
        Section {
            ForEach(watched, id: \.self) { name in
                HStack(spacing: DS.Space.s3) {
                    // Square, not round — a package is a topic, not a person
                    // (the mark grammar ruling, prd §184).
                    BridgeIcon(name: registry.displayName, size: 32, circular: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        // The version we last saw, which is the one fact that
                        // makes this row worth more than an echo of what was
                        // typed. "Watching" until the first read lands, rather
                        // than a blank or a guessed version.
                        Text(packages.version(registry, name) ?? String(localized: "Watching"))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .dsListCardRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { unwatch(name) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                // A swipe has no Mac-mouse equivalent — right-click mirrors it
                // (Mac polish, 2026-07-28).
                .contextMenu {
                    Button(role: .destructive) { unwatch(name) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(watched.count == 1 ? "Watching" : "Watching \(watched.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        BridgeFooterNote(lede: footerLede)
    }

    private var footerLede: String {
        switch registry {
        case .npm:
            String(localized: "Fetched directly by \(DS.device) from the public registry — no account, no key. Download counts are never fetched: a tally isn't news.")
        case .pypi:
            String(localized: "Fetched directly by \(DS.device) from the public index — no account, no key. Download counts are never fetched: a tally isn't news.")
        }
    }

    // MARK: - Actions

    private func watch() {
        let name = registry.normalize(nameField)
        guard !name.isEmpty else { return }
        guard packages.add(registry, name) else {
            lastResult = String(localized: "Already watching \(name).")
            lastResultIsError = false
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
        // Its rows leave with it (prd §286). Every release ref is prefixed
        // with the registry and the lowercased package name, which is what
        // makes this matchable without parsing a title.
        let prefix = "\(registry.rawValue):"
        let needle = name.lowercased()
        FollowPrune.remove(source: registry.displayName, context: modelContext) { thing in
            guard let ref = thing.sourceRef, ref.hasPrefix(prefix) else { return false }
            // `npm:release:<name>:<version>` and `npm:deprecated:<name>` — the
            // name is the component after the shape, and it is matched WHOLE
            // rather than by `contains`, or unwatching `react` would also take
            // every row belonging to `react-router`.
            let parts = ref.split(separator: ":", maxSplits: 3).map(String.init)
            return parts.count >= 3 && parts[2] == needle
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
                lastResult = added > 0
                    ? String(localized: "\(added) new")
                    : String(localized: "Up to date")
                lastResultIsError = false
                let proof = added > 0
                    ? String(localized: "\(added) in")
                    : String(localized: "Synced just now")
                store.registerConnected(
                    id: registry.bridgeID, name: registry.displayName, proof: proof,
                    can: ["Reads the current version of the packages you watch.",
                          "Read-only — it never installs, publishes, or signs in."])
                flipTrigger += 1
            } else {
                lastResult = String(localized: "Couldn't reach \(registry.displayName) — check your connection.")
                lastResultIsError = true
            }
        } while syncPending && connected
    }
}
