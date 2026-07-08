import SwiftUI
import SwiftData

/// One screen for every paste-a-token bridge — the steps to find the token,
/// a field that sends it straight to the Keychain, and proof when things
/// land. The same shape as RSS and Bluesky: state the way in plainly, then
/// show it working.
struct TokenSetupScreen: View {
    let bridge: TokenBridge

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var tokenField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false

    private var recent: [Thing] {
        recentBridgeThings(source: bridge.rawValue, context: modelContext)
    }

    var body: some View {
        List {
            stepsSection
            tokenSection
            if !recent.isEmpty {
                RecentThingsSection(header: "LANDED", things: recent)
            }
            if bridge.connected { removeSection }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(bridge.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if bridge.connected {
                Task { await sync() }
            }
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(Array(bridge.steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    Text("\(i + 1)")
                        .dsText(.subhead13).fontWeight(.bold)
                        .foregroundStyle(DS.tint)
                        .frame(width: 16)
                    Text(text)
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(DS.surfaceSheet)
            }
        } header: {
            Text("GET YOUR TOKEN").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        }
    }

    private var tokenSection: some View {
        Section {
            BridgeFieldRow(placeholder: bridge.placeholder, text: $tokenField,
                           buttonLabel: bridge.connected ? "Update" : "Connect",
                           secure: true, action: connect)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: "Fetching your \(bridge.noun)…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("YOUR TOKEN").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("The token stays in this iPhone's Keychain and goes only to \(bridge.rawValue) itself. Read-only.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    private var removeSection: some View {
        Section {
            Button("Remove token", role: .destructive) {
                TokenVault.delete(bridge.tokenKey)
                store.bridges.removeAll { $0.id == bridge.bridgeID }
                result = "Token removed — your things stay."
                resultIsError = false
                DSHaptic.tap()
            }
            .dsText(.callout15)
            .listRowBackground(DS.surfaceSheet)
        } footer: {
            Text("Removing the token stops syncing. What already landed stays yours.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    private func connect() {
        let token = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        TokenVault.set(token, for: bridge.tokenKey)
        tokenField = ""
        DSHaptic.tap()
        Task { await sync(justConnected: true) }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await TokenIngest.refresh(bridge, context: modelContext)
        syncing = false
        guard let added else {
            // A fresh paste that fails doesn't stay: keeping it would show
            // "Update"/"Remove token" for a connection that never worked and
            // retry a dead token on every foreground.
            if justConnected { TokenVault.delete(bridge.tokenKey) }
            result = "That token didn't work — check it (and your connection) and paste again."
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? "\(added) \(bridge.noun) in" : "Up to date"
        let proof = added > 0 ? "\(added) \(bridge.noun) in" : "Synced just now"
        if store.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                   proof: proof, can: [bridge.canLine]) {
            DSHaptic.success()
        }
    }
}
