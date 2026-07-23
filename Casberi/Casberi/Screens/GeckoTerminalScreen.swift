import SwiftUI
import SwiftData

/// The GeckoTerminal things already in the corpus — newest first, a @Query so
/// the list grows live as a sync lands trending tokens.
private let geckoRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "GeckoTerminal" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// GeckoTerminal, connected — the tokens trending now on the chains you watch.
/// You pick the chains; their current top movers land as link things on every
/// visit and app foreground. No account, no key — GeckoTerminal's trending
/// endpoint is public and keyless. Read-only public price data: never a path to
/// buy, sell, or trade. Each trending row's sheet draws the same live on-device
/// chart a watched token's does.
struct GeckoTerminalScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var gecko = TrendingStore.shared
    @State private var syncing = false
    /// A chain toggled while a sync is mid-flight sets this; the running sync
    /// loops once more when it lands so the new chain isn't stranded until the
    /// next visit.
    @State private var syncPending = false
    @State private var lastResult: String?

    @Query(geckoRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "GeckoTerminal", connected: gecko.connected)
            chainsSection.listRowSeparator(.hidden)
            if recent.isEmpty {
                // Only before the first chain: a ghost captioned "when you
                // switch a chain on" under an ON toggle would be fake status
                // (honesty rule; review 2026-07-16).
                if !gecko.connected {
                    GhostPreviewSection(name: "GeckoTerminal",
                                        replaceLine: "The real movers replace this when you switch a chain on.")
                        .listRowSeparator(.hidden)
                }
            } else {
                RecentThingsSection(header: gecko.trendingHeader, things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
            }
            if gecko.connected {
                BridgeDisconnectSection(
                    bridgeID: "geckoterminal", name: "GeckoTerminal",
                    teardown: {
                        TrendingStore.shared.disconnect()
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "GeckoTerminal")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle("GeckoTerminal")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Opening the screen doesn't connect — the person taps a chain to
            // watch it. Only refresh if something's already watched: viewing is
            // not consent to connect.
            if gecko.connected { Task { await sync() } }
        }
    }

    // MARK: - Chains

    private var chainsSection: some View {
        Section {
            // A switch, not an appearing checkmark — the row IS the connect
            // verb here (the OpenSea ruling, mock review 2026-07-16). One list
            // row holding every chain — separate rows leak a hairline that
            // survives .listRowSeparator(.hidden). Design law: no hairlines.
            VStack(spacing: 0) {
                ForEach(TrendingChain.allCases) { chain in
                    Toggle(isOn: Binding(
                        get: { gecko.isWatching(chain) },
                        // Guard on the committed value: a same-value commit
                        // must not invert the watch behind the switch.
                        set: { on in
                            guard on != gecko.isWatching(chain) else { return }
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
            Text("Switch a chain on and watching starts — its current top movers land as links, newest first. Read-only.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Trending is GeckoTerminal's own ranking — by 24-hour volume and price move — fetched directly by this iPhone through its public API. Read-only: nothing here buys, sells, or trades.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func toggle(_ chain: TrendingChain) {
        if gecko.isWatching(chain) {
            gecko.remove(chain)
        } else {
            gecko.add(chain)
        }
        DSHaptic.tap()
        Task { await sync() }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard gecko.connected else {
            // Unwatching the last chain leaves nothing to sync — clear the seat.
            store.remove("geckoterminal")
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
            let added = await TrendingIngest.refresh(context: modelContext)
            // Disconnected mid-sync (teardown ran while this awaited) — don't
            // resurrect the seat the person just removed.
            guard gecko.connected else { store.remove("geckoterminal"); return }
            if let added {
                lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
                let proof = added > 0 ? "\(added) trending in" : "Synced just now"
                store.registerConnected(id: "geckoterminal", name: "GeckoTerminal", proof: proof,
                                        can: ["Reads the trending tokens on the chains you watch.",
                                              "Read-only — never buys, sells, or trades."])
            } else {
                lastResult = String(localized: "Couldn't reach GeckoTerminal — check your connection.")
            }
        } while syncPending && gecko.connected
    }
}
