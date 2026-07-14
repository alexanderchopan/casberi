import SwiftUI
import SwiftData

/// Steam's setup — the steps to a free Web API key, the key and profile
/// fields, then the games that landed. Same shape as Mail (two inputs) and
/// the token bridges (key in Keychain, proof below).
struct SteamScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var keyField = ""
    @State private var profileField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var recent: [Thing] = []

    private func loadRecent() {
        recent = recentBridgeThings(source: "Steam", context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Steam")
            stepsSection.listRowSeparator(.hidden)
            fieldsSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                PinToHomeButton(source: "Steam", inSection: true)
                    .listRowSeparator(.hidden)
                RecentThingsSection(header: "Games", things: recent)
                    .listRowSeparator(.hidden)
            }
            if SteamBridge.connected { removeSection.listRowSeparator(.hidden) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Steam")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadRecent()
            profileField = SteamBridge.profile
            if SteamBridge.connected { Task { await sync() } }
        }
    }

    private var steps: [String] = [
        "Open steamcommunity.com/dev/apikey and sign in.",
        "Enter any domain (casberi.app works) and copy the key.",
        "Paste it with your profile name below. Your profile must be public.",
    ]

    private var stepsSection: some View {
        Section {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    Text("\(i + 1)")
                        .dsText(.body17).fontWeight(.bold)
                        .foregroundStyle(DS.tint).frame(width: 20)
                    Text(LocalizedStringKey(text))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            }
        } header: {
            Text("Get a free key").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    private var fieldsSection: some View {
        Section {
            TextField("Profile name or SteamID", text: $profileField)
                .dsText(.body17).foregroundStyle(DS.textPrimary).tint(DS.tint)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.vertical, DS.Space.s1)
                .dsListCardRow()
            HStack(spacing: DS.Space.s2) {
                SecureField("Web API key", text: $keyField)
                    .dsText(.body17).foregroundStyle(DS.textPrimary).tint(DS.tint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit(connect)
                Button(SteamBridge.connected ? "Update" : "Connect", action: connect)
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
            .dsListCardRow()
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your games…"),
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Account").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("The key stays in this iPhone's Keychain and goes only to Steam itself. Read-only — public profile data.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var removeSection: some View {
        Section {
            Button("Remove key", role: .destructive) {
                SteamBridge.disconnect()
                store.bridges.removeAll { $0.id == "steam" }
                result = String(localized: "Key removed — your things stay.")
                resultIsError = false
                DSHaptic.tap()
            }
            .dsText(.callout15)
            .dsListCardRow()
        } footer: {
            Text("Removing the key stops syncing. What already landed stays yours.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var canConnect: Bool {
        !profileField.trimmingCharacters(in: .whitespaces).isEmpty
            && !keyField.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func connect() {
        guard canConnect else { return }
        SteamBridge.profile = profileField.trimmingCharacters(in: .whitespaces)
        TokenVault.set(keyField.trimmingCharacters(in: .whitespaces),
                       for: SteamBridge.tokenKey)
        keyField = ""
        DSHaptic.tap()
        Task { await sync(justConnected: true) }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await SteamIngest.refresh(context: modelContext)
        syncing = false
        loadRecent()
        guard let added else {
            // A fresh key that fails doesn't stay (same rule as the token
            // bridges) — no dead connection retrying on every foreground.
            if justConnected { SteamBridge.disconnect() }
            result = String(localized: "Couldn't reach Steam — check the key, the profile name, and that the profile is public.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) games in") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) games in" : "Synced just now"
        if store.registerConnected(id: "steam", name: "Steam", proof: proof,
                                   can: ["Reads what you've played.",
                                         "Read-only — public profile data."]) {
            DSHaptic.success()
        }
    }
}
