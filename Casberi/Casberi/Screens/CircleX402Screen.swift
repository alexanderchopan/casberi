import SwiftUI
import SwiftData

/// Circle x402, connected — the marketplace of APIs that sell themselves to
/// software by the call. You pick the lanes; the companies listing in them land
/// in your feed with what they sell and what a call costs. No account, no key:
/// Circle's discovery API is public. Read-only, and that is the whole shape of
/// the seat — Casberi never pays an x402 service and shows no path to.
///
/// The lanes are filtered ON DEVICE, not by the API's own `category` parameter,
/// and that is load-bearing rather than incidental: Circle's filter accepts six
/// values while the data carries seven, so a server-side filter can't reach a
/// fifth of the marketplace. See `X402Ingest`'s header, quirk 1.
struct CircleX402Screen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var x402 = X402Store.shared
    @State private var syncing = false
    /// A lane toggled mid-flight requeues rather than being stranded until the
    /// next visit — `GeckoTerminalScreen`'s pattern.
    @State private var syncPending = false
    @State private var lastResult: String?
    /// Whether `lastResult` is a failure — see `PrivacyPoolsScreen` (audit,
    /// 2026-07-31): hardcoding `false` painted a reach failure in confirm green.
    @State private var lastResultIsError = false

    private var watchingEverything: Bool {
        x402.watched.count == X402Category.allCases.count
    }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Circle x402",
                mode: .noAccount,
                intro: "Pick the lanes you care about below, and the companies selling APIs to agents land in your feed. Nothing here pays for a call.",
                connected: x402.connected)
            if x402.connected {
                RoomDoor(name: "Circle x402", source: X402Ingest.source)
                    .listRowSeparator(.hidden)
            }
            lanesSection.listRowSeparator(.hidden)
            if x402.connected {
                BridgeDisconnectSection(
                    bridgeID: "x402", name: "Circle x402",
                    teardown: {
                        X402Store.shared.disconnect()
                    }
                ).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Circle x402")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Circle x402")
        .onAppear {
            // Opening the screen doesn't connect — a lane switch is the consent.
            if x402.connected { Task { await sync() } }
        }
    }

    // MARK: - Lanes

    /// One SWITCH SLAB per lane (prd §190) — flipping one starts a real watch,
    /// so it earns a block rather than a line in a stacked list.
    ///
    /// The "watch everything" button is GATED on there being something left to
    /// watch: shown once every lane is on, it would be a control that does
    /// nothing, which the honesty rule forbids outright.
    private var lanesSection: some View {
        Section {
            VStack(spacing: DS.Space.s2) {
                if !watchingEverything {
                    DSSlabButton(title: String(localized: "Watch every lane"),
                                 systemImage: "square.grid.2x2") {
                        DSHaptic.tap()
                        for category in X402Category.allCases { x402.add(category) }
                        Task { await sync() }
                    }
                }
                ForEach(X402Category.allCases) { category in
                    DSSlabSwitch(title: category.display, isOn: Binding(
                        get: { x402.isWatching(category) },
                        // Guard on the committed value: a same-value commit must
                        // not invert the watch behind the switch.
                        set: { on in
                            guard on != x402.isWatching(category) else { return }
                            toggle(category)
                        }
                    ))
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading the marketplace…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                DSSlabNote(text: "Switch a lane on and its companies land. Read-only.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Actions

    private func toggle(_ category: X402Category) {
        if x402.isWatching(category) {
            x402.remove(category)
            // No prune, unlike GeckoTerminal's per-chain sweep (§286), and the
            // reason is what a row IS here: a landed row is a COMPANY, and a
            // company usually sells into several lanes at once — Orthogonal
            // sits in five. Pruning by the lane just switched off would delete
            // rows still earned by the lanes still on.
        } else {
            x402.add(category)
        }
        DSHaptic.tap()
        Task { await sync() }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard x402.connected else {
            // Unwatching the last lane leaves nothing to sync — clear the seat.
            store.remove("x402")
            return
        }
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let added = await X402Ingest.refresh(context: modelContext)
            // Disconnected mid-sync (teardown ran while this awaited) — don't
            // resurrect the seat the person just removed.
            guard x402.connected else { store.remove("x402"); return }
            if let added {
                lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
                lastResultIsError = false
                let proof = added > 0
                    ? String(localized: "\(added) listed in")
                    : String(localized: "Synced just now")
                store.registerConnected(id: "x402", name: "Circle x402", proof: proof,
                                        can: ["Reads Circle's public directory of x402 services.",
                                              "Read-only — never pays for a call."])
            } else {
                lastResult = String(localized: "Couldn't reach Circle — check your connection.")
                lastResultIsError = true
            }
        } while syncPending && x402.connected
    }
}
