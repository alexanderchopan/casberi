import SwiftUI
import SwiftData

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
    /// Whether `lastResult` is a failure — see `PrivacyPoolsScreen` (audit,
    /// 2026-07-31): hardcoding `false` painted "Couldn't reach GeckoTerminal"
    /// in confirm green with the count-up animation.
    @State private var lastResultIsError = false

    var body: some View {
        List {
            BridgeSetupHeader(name: "GeckoTerminal", connected: gecko.connected)
            chainsSection.listRowSeparator(.hidden)
            if gecko.connected {
                ChipLiveNote(name: "GeckoTerminal", verb: "for what's trending.")
                    .listRowSeparator(.hidden)
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
        .dsScreenTitle("GeckoTerminal")
        .onAppear {
            // Opening the screen doesn't connect — the person taps a chain to
            // watch it. Only refresh if something's already watched: viewing is
            // not consent to connect.
            if gecko.connected { Task { await sync() } }
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
                ForEach(TrendingChain.allCases) { chain in
                    DSSlabSwitch(title: chain.display, isOn: Binding(
                        get: { gecko.isWatching(chain) },
                        // Guard on the committed value: a same-value commit
                        // must not invert the watch behind the switch.
                        set: { on in
                            guard on != gecko.isWatching(chain) else { return }
                            toggle(chain)
                        }
                    ))
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading the chain…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                DSSlabNote(text: "Switch a chain on and its top movers land. Read-only.")
            }
        }
        .dsSlabSection()
    }

    /// The read-only promise is the slab note's, beside the switches that make
    /// the connection — so the footer, which said it again in longer words,
    /// keeps only what the note doesn't say (§252's ruling, 2026-07-31).
    private var footerSection: some View {
        BridgeFooterNote(
            lede: "Trending is GeckoTerminal's own ranking — by 24-hour volume and price move — fetched directly by \(DS.device) through its public API.")
    }

    // MARK: - Actions

    private func toggle(_ chain: TrendingChain) {
        if gecko.isWatching(chain) {
            gecko.remove(chain)
            // Its trending rows leave with it (prd §286). The chain is in
            // each row's own sourceRef ("gecko:<chain>:<token>").
            FollowPrune.remove(source: "GeckoTerminal", context: modelContext) {
                $0.sourceRef?.hasPrefix("gecko:\(chain.gecko):") == true
            }
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
                lastResultIsError = false
                let proof = added > 0
            ? String(localized: "\(added) trending in")
            : String(localized: "Synced just now")
                store.registerConnected(id: "geckoterminal", name: "GeckoTerminal", proof: proof,
                                        can: ["Reads the trending tokens on the chains you watch.",
                                              "Read-only — never buys, sells, or trades."])
            } else {
                lastResult = String(localized: "Couldn't reach GeckoTerminal — check your connection.")
                lastResultIsError = true
            }
        } while syncPending && gecko.connected
    }
}
