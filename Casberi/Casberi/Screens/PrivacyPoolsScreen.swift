import SwiftUI
import SwiftData

/// The Privacy Pools things already in the corpus — newest first.
private let privacyPoolsRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Privacy Pools" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Privacy Pools (0xBow), connected — your deposits and their screening
/// status (prd §162). Depositing happens from the person's own wallet on
/// 0xBow's app, so there is no account, no key, no OAuth — the seat rides
/// the watched wallets the way Peer does, and connecting is one switch.
/// What the seat adds: each deposit lands as a thing, and the moment the
/// screening clears it to withdraw privately (or declines it), that lands
/// too — the flip people otherwise poll a website for. Read-only by design
/// and by ruling: nothing here deposits, withdraws, proves, or signs, and
/// the withdrawal side is unlinkable by design, so Casberi never sees it.
struct PrivacyPoolsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    @State private var lastResult: String?
    @AppStorage(PrivacyPoolsBridge.seatKey) private var connected = false

    @Query(privacyPoolsRecentDescriptor) private var recent: [Thing]

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }

    var body: some View {
        List {
            BridgeSetupHeader(name: "0xBow Privacy Pools", connected: connected)
            connectSection.listRowSeparator(.hidden)
            if recent.isEmpty {
                if !connected {
                    GhostPreviewSection(name: "0xBow Privacy Pools",
                                        replaceLine: "Your real deposits replace this when you switch this on.")
                        .listRowSeparator(.hidden)
                }
            } else {
                RecentThingsSection(header: String(localized: "Recent activity"),
                                    things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
            }
            if connected {
                BridgeDisconnectSection(
                    bridgeID: "privacypools", name: "0xBow Privacy Pools",
                    teardown: {
                        PrivacyPoolsBridge.disconnect()
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "0xBow Privacy Pools")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle("0xBow Privacy Pools")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Viewing is not consent to connect — only refresh if the switch
            // is already on.
            if connected { Task { await sync() } }
        }
    }

    // MARK: - Connect

    private var connectSection: some View {
        Section {
            if hasWallets {
                Toggle(isOn: Binding(
                    get: { connected },
                    set: { on in
                        guard on != connected else { return }
                        toggle(on)
                    }
                )) {
                    Text("Watch my Privacy Pools deposits")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                }
                .tint(DS.tint)
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            } else {
                // No wallet watched = no deposits this app can see. A
                // disabled switch would be a dead control (honesty rule).
                NavigationLink {
                    BridgeDestinationView(destination: .wallet)
                } label: {
                    Text("Watch a wallet first")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            }
        } header: {
            HStack {
                Text(hasWallets ? "Your wallets" : "Before connecting")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer()
                if syncing {
                    ProgressView().controlSize(.small)
                } else if let lastResult {
                    Text(lastResult).dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        } footer: {
            Text(hasWallets
                 ? "You deposit on Privacy Pools' own app; Casberi lands each deposit here and tells you the moment the screening clears it to withdraw privately — or declines it. That status is the wait people otherwise keep checking a website for."
                 : "Privacy Pools deposits come from your own wallet, so Casberi reads them off the wallets you watch. Watch the wallet you deposit with, then come back here.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Deposits are read from Ethereum's public chain and each deposit's review status from 0xBow's public API by this iPhone — no account, no key. Withdrawals are private by design: the chain can't link them to your deposit, so Casberi never sees or shows that side. Read-only: nothing here deposits, withdraws, or moves funds.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func toggle(_ on: Bool) {
        connected = on
        DSHaptic.tap()
        if on {
            // Register the seat EAGERLY (the Peer lesson, review 2026-07-17).
            register(proof: watchingProof)
            Task { await sync() }
        } else {
            PrivacyPoolsBridge.disconnect()
            store.remove("privacypools")
            lastResult = nil
        }
    }

    private func sync() async {
        guard connected else { store.remove("privacypools"); return }
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let added = await PrivacyPoolsBridge.syncNow(context: modelContext)
        // Disconnected mid-sync — don't resurrect the seat.
        guard connected else { store.remove("privacypools"); return }
        if let added {
            lastResult = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
            register(proof: added > 0 ? "\(added) new" : watchingProof)
        } else {
            lastResult = String(localized: "Couldn't reach the chain — check your connection.")
        }
    }

    private var watchingProof: String {
        let n = WalletStore.shared.addresses.count
        return "Watching \(n) wallet\(n == 1 ? "" : "s")"
    }

    private func register(proof: String) {
        store.registerConnected(id: "privacypools", name: "0xBow Privacy Pools", proof: proof,
                                can: ["Reads Privacy Pools deposits and their screening status for the wallets you watch, from public sources.",
                                      "Read-only — never deposits, withdraws, or moves funds."])
    }
}
