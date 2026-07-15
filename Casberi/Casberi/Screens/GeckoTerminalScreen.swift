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
            BridgeSetupHeader(name: "GeckoTerminal")
            chainsSection.listRowSeparator(.hidden)
            if gecko.connected { pinToHomeSection.listRowSeparator(.hidden) }
            if !recent.isEmpty {
                RecentThingsSection(header: gecko.trendingHeader, things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
            }
            if gecko.connected {
                BridgeDisconnectSection(
                    bridgeID: "geckoterminal", name: "GeckoTerminal",
                    teardown: {
                        TrendingStore.shared.disconnect()
                        HomePinnedSources.shared.clear("GeckoTerminal")
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
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
            ForEach(TrendingChain.allCases) { chain in
                Button {
                    toggle(chain)
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Text(chain.display)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer()
                        if gecko.isWatching(chain) {
                            Image(systemName: "checkmark")
                                .dsText(.body17).foregroundStyle(DS.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsListCardRow()
            }
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
            Text("Watch a chain and its current top movers land as links, newest first. Read-only.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    // MARK: - Pin to Home

    private var pinnedToHome: Bool { HomePinnedSources.shared.isPinned("GeckoTerminal") }

    private var pinToHomeSection: some View {
        Section {
            Button {
                HomePinnedSources.shared.toggle("GeckoTerminal")
                CorpusSignal.shared.bump()
                DSHaptic.tap()
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: pinnedToHome ? "pin.fill" : "pin")
                    Text(pinnedToHome ? "Pinned to Home" : "Pin to Home")
                }
                .dsText(.body17).foregroundStyle(pinnedToHome ? DS.tint : DS.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(pinnedToHome ? DS.tintDim : DS.gray100,
                            in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        } footer: {
            Text("The trending movers ride a strip on Home.")
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
