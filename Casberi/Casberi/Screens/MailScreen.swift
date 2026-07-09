import SwiftUI
import SwiftData

/// One screen for both mail bridges — the steps to make an app-specific
/// password, an address field and a password field, then the recent inbox.
/// Read-only over IMAP; the real account password never enters the app.
struct MailScreen: View {
    let provider: MailProvider

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var addressField = ""
    @State private var passwordField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var recent: [Thing] = []

    private func loadRecent() {
        recent = recentBridgeThings(source: provider.source, context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: provider.source)
            stepsSection.listRowSeparator(.hidden)
            fieldsSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                RecentThingsSection(header: "Recent", things: recent)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(provider.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadRecent()
            addressField = provider.address
            if provider.connected { Task { await sync() } }
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(Array(provider.steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    Text("\(i + 1)")
                        .dsText(.body17).fontWeight(.bold)
                        .foregroundStyle(DS.tint).frame(width: 20)
                    Text(text)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DS.Space.s1)
                .listRowBackground(DS.surfaceSheet)
            }
        } header: {
            Text("Get an app password").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    private var fieldsSection: some View {
        Section {
            TextField(provider.addressPlaceholder, text: $addressField)
                .dsText(.body17).foregroundStyle(DS.textPrimary).tint(DS.tint)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .padding(.vertical, DS.Space.s1)
                .listRowBackground(DS.surfaceSheet)
            HStack(spacing: DS.Space.s2) {
                SecureField(provider.passwordPlaceholder, text: $passwordField)
                    .dsText(.body17).foregroundStyle(DS.textPrimary).tint(DS.tint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit(connect)
                Button(provider.connected ? "Update" : "Connect", action: connect)
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(canConnect ? .white : DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4).frame(height: 36)
                    .background(canConnect ? AnyShapeStyle(DS.tint) : AnyShapeStyle(DS.gray200),
                                in: Capsule(style: .continuous))
                    .animation(DS.Motion.standard, value: canConnect)
                    .armedPop(canConnect)
                    .disabled(!canConnect)
                    .buttonStyle(.plain)
            }
            .padding(.vertical, DS.Space.s1)
            .listRowBackground(DS.surfaceSheet)
            BridgeSyncStatusRows(syncing: syncing, syncingLine: "Reading your inbox…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Your account").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text(provider.footer).dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var canConnect: Bool {
        !addressField.trimmingCharacters(in: .whitespaces).isEmpty
            && !passwordField.isEmpty
    }

    private func connect() {
        guard canConnect else { return }
        var p = provider
        p.address = addressField.trimmingCharacters(in: .whitespaces)
        TokenVault.set(passwordField, for: provider.passwordKey)
        passwordField = ""
        DSHaptic.tap()
        Task { await sync(justConnected: true) }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await MailIngest.refresh(provider, context: modelContext)
        syncing = false
        loadRecent()
        guard let added else {
            if justConnected { TokenVault.delete(provider.passwordKey) }
            result = "Couldn't sign in — check the address and app-specific password."
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? "\(added) in your feed" : "Up to date"
        let proof = added > 0 ? "\(added) mail in" : "Synced just now"
        if let existing = store.bridges.first(where: { $0.name == provider.source }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: provider.bridgeID, name: provider.source, status: .connected,
                statusLine: proof, can: ["Reads your inbox.", "Read-only — never sends."]
            ))
            DSHaptic.success()
        }
    }
}
