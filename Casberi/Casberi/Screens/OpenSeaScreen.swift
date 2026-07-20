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
        .dsPageBackground()
        .navigationTitle("OpenSea")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Opening the screen doesn't connect — the person taps a chain to
            // watch it (like RSS wants a feed pasted). Only refresh if
            // something's already watched: viewing is not consent to connect.
            if opensea.connected { Task { await sync() } }
        }
    }

    // MARK: - Chains

    private var chainsSection: some View {
        Section {
            // A switch, not an appearing checkmark — the row IS the connect
            // verb here, and a control that starts a live watch should look
            // like one with both states visible (mock review 2026-07-16).
            // One list row holding every chain (a VStack) — separate rows leak
            // a hairline that survives .listRowSeparator(.hidden) (the
            // first-post-header-separator gotcha). Design law: no hairlines.
            VStack(spacing: 0) {
                ForEach(OpenSeaChain.allCases) { chain in
                    Toggle(isOn: Binding(
                        get: { opensea.isWatching(chain) },
                        // Guard on the committed value: a same-value commit (a
                        // knob drag released on its own side, an accessibility
                        // set) must not invert the watch behind the switch.
                        set: { on in
                            guard on != opensea.isWatching(chain) else { return }
                            toggle(chain)
                        }
                    )) {
                        Text(chain.display)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                    }
                    .tint(DS.tint)
                    .padding(.vertical, DS.Space.s1)
                }
            }
            .dsListCardRow()
        } header: {
            HStack {
                Text("Chains").dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer()
                if syncing {
                    ProgressView().controlSize(.small)
                } else if let lastResult {
                    Text(lastResult).dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        } footer: {
            Text("Switch a chain on and watching starts — its newest collections land as links, the ones with real artwork, not the empty test contracts. Read-only.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
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
