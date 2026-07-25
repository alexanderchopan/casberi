import SwiftUI
import SwiftData

/// The OpenSea things already in the corpus — newest first, a @Query so the
/// list grows live as a sync lands collections.
private let openSeaRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "OpenSea" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// OpenSea, connected — new NFT drops' home in Casberi. You pick which chains
/// to watch; their newest collections (the ones with real artwork) land as
/// link things on every visit and app foreground. No account, no sign-in —
/// read-only public marketplace data, never a path to buy or bid.
struct OpenSeaScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var opensea = OpenSeaStore.shared
    @State private var syncing = false
    /// A chain toggled while a sync is mid-flight sets this; the running sync
    /// loops once more when it lands so the new chain isn't stranded until the
    /// next visit.
    @State private var syncPending = false
    @State private var lastResult: String?

    @Query(openSeaRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "OpenSea", connected: opensea.connected)
            chainsSection.listRowSeparator(.hidden)
            if recent.isEmpty {
                // Only before the first chain: a ghost captioned "when you
                // switch a chain on" under an ON toggle would be fake status
                // (honesty rule; review 2026-07-16).
                if !opensea.connected {
                    GhostPreviewSection(name: "OpenSea",
                                        replaceLine: "Your real drops replace this when you switch a chain on.")
                        .listRowSeparator(.hidden)
                }
            } else {
                RecentThingsSection(header: "New drops", things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
            }
            if opensea.connected {
                BridgeDisconnectSection(
                    bridgeID: "opensea", name: "OpenSea",
                    teardown: {
                        OpenSeaStore.shared.disconnect()
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "OpenSea")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("OpenSea")
        .onAppear {
            // Opening the screen doesn't connect — the person taps a chain to
            // watch it (like RSS wants a feed pasted). Only refresh if
            // something's already watched: viewing is not consent to connect.
            if opensea.connected { Task { await sync() } }
        }
    }

    // MARK: - Chains

    /// Each chain is one SWITCH SLAB (prd §190). The row is this screen's
    /// connect verb for that lane — flipping it starts a real watch — so it
    /// gets a full block rather than a line in a stacked toggle list. The
    /// section header and its paragraph went with the furniture; the sync
    /// result rides the status row, the promise rides the one sentence.
    private var chainsSection: some View {
        Section {
            VStack(spacing: DS.Space.s2) {
                ForEach(OpenSeaChain.allCases) { chain in
                    DSSlabSwitch(title: chain.display, isOn: Binding(
                        get: { opensea.isWatching(chain) },
                        // Guard on the committed value: a same-value commit
                        // must not invert the watch behind the switch.
                        set: { on in
                            guard on != opensea.isWatching(chain) else { return }
                            toggle(chain)
                        }
                    ))
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading the chain…"),
                                     result: lastResult, resultIsError: false)
                DSSlabNote(text: "Switch a chain on and its newest drops land. Read-only.")
            }
        }
        .dsSlabSection()
    }

    private var footerSection: some View {
        Section {
            Text("Fetched directly by this iPhone through OpenSea's public API — no account, no ranking. Read-only: nothing here buys, sells, or bids.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func toggle(_ chain: OpenSeaChain) {
        if opensea.isWatching(chain) {
            opensea.remove(chain)
        } else {
            opensea.add(chain)
        }
        DSHaptic.tap()
        Task { await sync() }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard opensea.connected else {
            // Unwatching the last chain leaves nothing to sync — clear the seat.
            store.remove("opensea")
            return
        }
        // A chain toggled while a sync is mid-flight requeues rather than being
        // dropped — the running pass loops once more (re-reading the watched
        // chains) so the new chain lands now, not next visit.
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let added = await OpenSeaIngest.refresh(context: modelContext)
            // Disconnected mid-sync (teardown ran while this awaited) — don't
            // resurrect the seat the person just removed.
            guard opensea.connected else { store.remove("opensea"); return }
            if let added {
                lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
                let proof = added > 0 ? "\(added) drops in" : "Synced just now"
                store.registerConnected(id: "opensea", name: "OpenSea", proof: proof,
                                        can: ["Reads new NFT collections on the chains you watch.",
                                              "Read-only — never buys, sells, or bids."])
            } else {
                lastResult = String(localized: "Couldn't reach OpenSea — check your connection.")
            }
        } while syncPending && opensea.connected
    }
}
