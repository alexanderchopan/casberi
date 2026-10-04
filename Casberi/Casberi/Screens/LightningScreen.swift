import SwiftUI
import SwiftData

/// Lightning, connected (prd §1098) — one field, then the balance.
///
/// Splits' shape: saving is not the end of connecting, because what the
/// connection may DO has to be read first. The save asks the wallet
/// (`NostrWalletConnect.methods`) and keeps the string only when none of the
/// methods can pay — a connection that could would make "nothing here can
/// spend" a promise of ours rather than a fact of the credential. A refused
/// Replace leaves the working connection in place.
struct LightningScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    @State private var field = ""
    @State private var credentialVersion = 0
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var balanceSats: Int?
    @State private var relayHost: String?

    @State private var sheet: AccountPageSheet?

    private var bridge: TokenBridge { .lightning }

    private var hasConnection: Bool {
        _ = credentialVersion
        return LightningAuth.configured
    }

    private var mask: String? { BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil }

    var body: some View {
        AccountPage(
            name: "Lightning", seatID: bridge.bridgeID, source: LightningIngest.source,
            state: AccountPageState.of(name: "Lightning", seatID: bridge.bridgeID,
                                       connected: hasConnection, store: store),
            mode: .pasteKey,
            keyed: true,
            teardown: {
                LightningAuth.clear()
                credentialVersion += 1
                load()
            },
            sheet: $sheet,
            act: {
                if hasConnection { standingBlock } else { keyBlock }
            },
            more: { EmptyView() },
            keySheet: { keyBlock }
        )
        .onAppear {
            load()
            if hasConnection { Task { await sync() } }
        }
    }

    @ViewBuilder private var keyBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            BridgeSetupCard(steps: bridge.steps, startingAt: 1, numbered: false) { EmptyView() }
            DSSlabField(placeholder: bridge.placeholder,
                        text: $field, actionLabel: "Save", secure: true,
                        action: save)
            BridgeSyncStatusRows(syncing: connecting,
                                 syncingLine: String(localized: "Asking your wallet what this connection can do…"),
                                 proof: result)
        }
    }

    @ViewBuilder private var standingBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let sats = balanceSats {
                Text(verbatim: mask ?? BitcoinBridge.formatAmount(sats: sats))
                    .dsText(.price40).monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
            } else {
                Text("Reading your wallet…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            }
            if let relayHost {
                Text("Through \(relayHost)")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading your wallet…"),
                                 proof: result)
        }
    }

    private func load() {
        balanceSats = hasConnection ? LightningState.balanceSats : nil
        relayHost = LightningAuth.connection?.relayHosts.first
    }

    private func save() {
        let raw = field
        connecting = true
        result = nil
        Task {
            let outcome = await LightningAuth.connect(raw)
            connecting = false
            guard outcome == .kept else {
                result = LightningAuth.sentence(outcome).map(BridgeProof.failed)
                return
            }
            field = ""
            credentialVersion += 1
            result = .connected(nil)
            DSHaptic.success()
            LightningWatch.registerBridge(store: store)
            load()
            await sync()
        }
    }

    private func sync() async {
        guard !syncing, hasConnection else { return }
        syncing = true
        defer { syncing = false }
        let added = await LightningIngest.refresh(context: modelContext)
        load()
        LightningWatch.registerBridge(store: store)
        if let added {
            if let failure = LightningIngest.lastPassFailure {
                result = .failed(failure)
            } else {
                result = added > 0 ? .landed(added) : .upToDate
            }
        } else {
            result = .failed(LightningIngest.lastPassFailure
                             ?? String(localized: "Couldn't reach your wallet's relay — check your connection."))
        }
    }
}
