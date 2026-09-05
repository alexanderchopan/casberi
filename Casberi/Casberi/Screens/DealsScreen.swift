import SwiftUI
import SwiftData

/// Deals, connected — the aggregators' feeds in Casberi. You pick which sources
/// to follow; their newest deals land as product things on every visit and app
/// foreground. No account, read-only public feeds — nothing here buys anything.
struct DealsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var deals = DealsStore.shared
    @State private var syncing = false
    @State private var lastResult: String?

    var body: some View {
        BridgeSetupPage(name: "Deals") {
            BridgeSetupHeader(
                name: "Deals",
                mode: .noAccount,
                intro: "Turn on the aggregators below, and today's discounts arrive. Nothing here buys anything.")
            if deals.connected {
                RoomDoor(name: "Deals", source: "Deals")
                    .listRowSeparator(.hidden)
            }
            sourcesSection.listRowSeparator(.hidden)
            if deals.connected {
                BridgeDisconnectSection(
                    bridgeID: "deals", name: "Deals",
                    teardown: {
                        DealsStore.shared.disconnect()
                    }
                ).listRowSeparator(.hidden)
            }
        }
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
            // "Read-only." left the end of this line (audit, 2026-07-31) — the
            // footer below spends a whole sentence on it, and says what it means.
            Text("Turn on a source and its newest deals — each already priced in the headline — land in your feed as products.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }


    private func toggle(_ source: DealSource) {
        if deals.isOn(source) {
            deals.remove(source)
            // Its deals leave with it (prd §286) — the publisher is stamped
            // on each row's `authorHandle` at land time.
            FollowPrune.remove(source: "Deals", context: modelContext) {
                $0.authorHandle == source.publisher
            }
        } else {
            deals.add(source)
        }
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
        let proof = added > 0
            ? String(localized: "\(added) deals in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "deals", name: "Deals", proof: proof,
                                can: ["Reads the deal feeds you follow.",
                                      "Read-only — never buys anything."])
    }
}
