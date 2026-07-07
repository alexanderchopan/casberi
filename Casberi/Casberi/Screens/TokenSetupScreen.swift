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
        let name = bridge.rawValue
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        List {
            stepsSection
            tokenSection
            if !recent.isEmpty { recentSection }
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
            HStack(spacing: DS.Space.s2) {
                SecureField(bridge.placeholder, text: $tokenField)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(connect)
                Button(bridge.connected ? "Update" : "Connect", action: connect)
                    .dsText(.label12)
                    .foregroundStyle(tokenField.isEmpty ? DS.textTertiary : .white)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 28)
                    .background(tokenField.isEmpty ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                                in: Capsule(style: .continuous))
                    .disabled(tokenField.isEmpty)
                    .buttonStyle(.plain)
            }
            .listRowBackground(DS.surfaceSheet)
            if syncing {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Fetching your \(bridge.noun)…")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .listRowBackground(DS.surfaceSheet)
            } else if let result {
                Text(result)
                    .dsText(.subhead13)
                    .foregroundStyle(resultIsError ? DS.attention : DS.confirm)
                    .listRowBackground(DS.surfaceSheet)
            }
        } header: {
            Text("YOUR TOKEN").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("The token stays in this iPhone's Keychain and goes only to \(bridge.rawValue) itself. Read-only.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    private var recentSection: some View {
        Section {
            ForEach(recent) { thing in
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                    Text(LiveTimeText.short(thing.capturedAt))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .listRowBackground(DS.surfaceSheet)
            }
        } header: {
            Text("LANDED").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
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
        if let existing = store.bridges.first(where: { $0.name == bridge.rawValue }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: bridge.bridgeID, name: bridge.rawValue, status: .connected,
                statusLine: proof, can: [bridge.canLine]
            ))
            DSHaptic.success()
        }
    }
}
