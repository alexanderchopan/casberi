import SwiftUI
import SwiftData

/// Bankr, connected — by creator address alone. The tokens the address
/// launched are public (Bankr's own API serves them with no key), so this
/// stores nothing but the address and never trades. Same shape as the other
/// address/handle bridges.
struct BankrScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var addressField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var recent: [Thing] = []
    @State private var chart = GenStream()

    private var bankr: BankrStore { BankrStore.shared }

    private func loadRecent() {
        recent = recentBridgeThings(source: "Bankr", context: modelContext)
    }

    var body: some View {
        List {
            addressSection
            if !chart.els.isEmpty {
                Section {
                    GenRender(id: "root", els: chart.els)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            }
            if !recent.isEmpty {
                RecentThingsSection(header: "YOUR TOKENS", things: recent)
            }
            footerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Bankr")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadRecent()
            addressField = bankr.address
            if BankrStore.isAddress(bankr.address) {
                Task { await sync() }
            }
        }
    }

    private var addressSection: some View {
        Section {
            BridgeFieldRow(placeholder: "0x… your creator address",
                           text: $addressField,
                           buttonLabel: bankr.address.isEmpty ? "Connect" : "Update",
                           action: connect)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: "Fetching your tokens…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("YOUR CREATOR ADDRESS").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("The wallet you launch tokens from — public, so there's no key to give.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Read-only. The tokens you launched land as things — Casberi never trades or moves funds.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func connect() {
        let address = BankrStore.normalize(addressField)
        guard BankrStore.isAddress(address) else {
            result = "That doesn't look like a wallet address (0x…)."
            resultIsError = true
            return
        }
        bankr.address = address
        addressField = address
        DSHaptic.tap()
        Task { await sync() }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await BankrIngest.refresh(context: modelContext)
        syncing = false
        loadRecent()
        guard let added else {
            result = "Couldn't reach Bankr — check the address and your connection."
            resultIsError = true
            return
        }
        resultIsError = false
        if let doc = await BankrIngest.launchesChart() { chart.paint(doc) }
        result = added > 0 ? "\(added) tokens in" : "Up to date"
        let proof = added > 0 ? "\(added) tokens in" : "Synced just now"
        if let existing = store.bridges.first(where: { $0.name == "Bankr" }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: "bankr", name: "Bankr", status: .connected,
                statusLine: proof, can: ["Reads the tokens you launched.",
                                         "Read-only — never trades or moves funds."]
            ))
            DSHaptic.success()
        }
    }
}
