import SwiftUI
import SwiftData

/// The Peer things already in the corpus — newest first, a @Query so the list
/// grows live as a sync lands fills.
private let peerRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Peer" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Peer, connected — your fiat↔crypto trades, as they settle (prd §113).
/// Peer is non-custodial: every trade settles onchain into the person's OWN
/// wallet, so there is no account, no key, no OAuth — the seat rides the
/// watched wallets the way Strava rides Apple Health, and connecting is one
/// switch. What the seat adds over the bare wallet feed is the WHY: "Bought
/// 25 USDC with Venmo on Peer" instead of an unexplained transfer. Read-only
/// by design and by ruling: nothing here ever starts a trade, and Peer's
/// zero-knowledge design keeps the Venmo/PayPal side private — the chain
/// (and so this screen) never sees it.
struct PeerScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    @State private var lastResult: String?
    @AppStorage(PeerBridge.seatKey) private var connected = false

    @Query(peerRecentDescriptor) private var recent: [Thing]

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Peer", connected: connected)
            connectSection.listRowSeparator(.hidden)
            if recent.isEmpty {
                if !connected {
                    GhostPreviewSection(name: "Peer",
                                        replaceLine: "Your real fills replace this when you switch this on.")
                        .listRowSeparator(.hidden)
                }
            } else {
                RecentThingsSection(header: String(localized: "Recent fills"),
                                    things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
            }
            if connected {
                BridgeDisconnectSection(
                    bridgeID: "peer", name: "Peer",
                    teardown: {
                        PeerBridge.disconnect()
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Peer")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle("Peer")
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
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if hasWallets {
                    // The seat as one SWITCH SLAB (prd §190) — the row is the
                    // connect verb, so it gets the full block.
                    DSSlabSwitch(title: String(localized: "Land my Peer trades"),
                                 isOn: Binding(
                        get: { connected },
                        set: { on in
                            guard on != connected else { return }
                            toggle(on)
                        }
                    ))
                } else {
                    // No wallet watched = nothing Peer settles into that this
                    // app can see. A disabled switch would be a dead control
                    // (honesty rule) — the live verb is the prerequisite, and
                    // a thing that navigates wears the door slab.
                    DSSlabDoor(title: "Watch a wallet first") {
                        HomeRoute.shared.pushBridge(.wallet)
                    }
                }
                DSSlabNote(text: "Rides your watched wallets — read-only, never trades.")
            }
        }
        .dsSlabSection()
    }

    private var footerSection: some View {
        Section {
            Text("Fills are read from Base's public chain by this iPhone — no Peer account, no key. Peer's zero-knowledge design keeps your Venmo or PayPal side private; the chain never shows it, so neither does Casberi. Read-only: nothing here ever starts a trade.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func toggle(_ on: Bool) {
        connected = on
        DSHaptic.tap()
        if on {
            // Register the seat EAGERLY — the switch is the connect verb, so
            // the catalog must show connected the moment it's on, not only
            // after the first sync succeeds (a live bridge wearing "not
            // connected" is fake status; review 2026-07-17). The sync then
            // upgrades the proof line with real counts.
            register(proof: watchingProof)
            Task { await sync() }
        } else {
            // Switching off clears the seat; the corpus keeps its things (the
            // full remove-things choice lives in the disconnect section).
            PeerBridge.disconnect()
            store.remove("peer")
            lastResult = nil
        }
    }

    /// Sweep + land; the bridge's status line carries the proof.
    private func sync() async {
        guard connected else { store.remove("peer"); return }
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let added = await PeerBridge.syncNow(context: modelContext)
        // Disconnected mid-sync (teardown ran while this awaited) — don't
        // resurrect the seat the person just removed.
        guard connected else { store.remove("peer"); return }
        if let added {
            lastResult = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
            register(proof: added > 0 ? "\(added) fill\(added == 1 ? "" : "s") in"
                                      : watchingProof)
        } else {
            lastResult = String(localized: "Couldn't reach Base — check your connection.")
        }
    }

    private var watchingProof: String {
        let n = WalletStore.shared.addresses.count
        return "Watching \(n) wallet\(n == 1 ? "" : "s")"
    }

    private func register(proof: String) {
        store.registerConnected(id: "peer", name: "Peer", proof: proof,
                                can: ["Reads Peer fills for the wallets you watch, from the public chain.",
                                      "Read-only — never starts, signs, or settles a trade."])
    }
}
