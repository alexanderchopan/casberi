import SwiftUI
import SwiftData

/// The Deals things already in the corpus — newest first, a @Query so the list
/// grows live as a sync lands deals.
private let dealsRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Deals" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Deals, connected — the aggregators' feeds in Casberi. You pick which sources
/// to follow; their newest deals land as product things on every visit and app
/// foreground. No account, read-only public feeds — nothing here buys anything.
struct DealsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var deals = DealsStore.shared
    @State private var syncing = false
    @State private var lastResult: String?

    @Query(dealsRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "Deals")
            sourcesSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                RecentThingsSection(header: "Latest deals", things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
            }
            if deals.connected {
                BridgeDisconnectSection(
                    bridgeID: "deals", name: "Deals",
                    teardown: {
                        DealsStore.shared.disconnect()
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Deals")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftTopEdge()
        .navigationTitle("Deals")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if deals.connected { Task { await sync() } }
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(DealSource.allCases) { source in
                Button {
                    toggle(source)
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Text(source.display)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer()
                        if deals.isOn(source) {
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
                Text("Sources").dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer()
                if syncing {
                    ProgressView().controlSize(.small)
                } else if let lastResult {
                    Text(lastResult).dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        } footer: {
            Text("Turn on a source and its newest deals — each already priced in the headline — land in your feed as products. Read-only.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Fetched directly by this iPhone through each aggregator's public feed — no account, no ranking. Read-only: nothing here buys anything.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func toggle(_ source: DealSource) {
        if deals.isOn(source) { deals.remove(source) } else { deals.add(source) }
        DSHaptic.tap()
        Task { await sync() }
    }

    private func sync() async {
        guard deals.connected else {
            store.remove("deals")
            return
        }
        if syncing { return }
        syncing = true
        let added = await DealsIngest.refresh(context: modelContext)
        syncing = false
        guard deals.connected else { store.remove("deals"); return }
        guard let added else {
            lastResult = String(localized: "Couldn't reach the deal feeds — check your connection.")
            return
        }
        lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) deals in" : "Synced just now"
        store.registerConnected(id: "deals", name: "Deals", proof: proof,
                                can: ["Reads the deal feeds you follow.",
                                      "Read-only — never buys anything."])
    }
}
