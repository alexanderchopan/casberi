import SwiftUI
import SwiftData

/// Steam's setup — the steps to a free Web API key, the key and profile
/// fields, then the games that landed. Same shape as Mail (two inputs) and
/// the token bridges (key in Keychain, proof below).
struct SteamScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var keyField = ""
    @State private var profileField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false

    /// The credentials door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if SteamBridge.connected {
                // Connected (prd §186): the profile IS the identity here —
                // Steam stores what the person typed, so this screen can lead
                // with whose library it's reading rather than the key fields
                // that fetched it, which used to sit here forever.
                BridgeConnectedState(
                    bridgeID: "steam",
                    name: "Steam",
                    identity: SteamBridge.profile,
                    connectionNote: String(localized: "Web API key · stored in \(DS.device)'s Keychain"),
                    capabilitiesFallback: ["Reads what you've played.",
                                           "Read-only — public profile data."],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                connectForm
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Steam")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Steam")
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Steam") {
                connectForm
                removeSection.listRowSeparator(.hidden)
            }
        }
        .onAppear {
            profileField = SteamBridge.profile
            if SteamBridge.connected { Task { await sync() } }
        }
    }

    /// The connect form — steps whole (user ruling 2026-07-23), furniture gone
    /// (prd §218, 2026-07-25). Leads the screen before connecting; lives
    /// behind the door after.
    @ViewBuilder private var connectForm: some View {
        BridgeSetupHeader(name: "Steam")
        setupSection
    }

    /// What's left once "Open steamcommunity.com/dev/apikey and sign in."
    /// became the button that does it.
    ///
    /// "Paste it with your profile name below" went (audit, 2026-07-31) — it
    /// re-typed the two fields under it, placeheld `Profile name or SteamID`
    /// and `Web API key`, which is §220's Kraken finding. The requirement it
    /// was carrying is a real one nothing else on the screen states, so that
    /// half stayed.
    private var steps: [String] = [
        "Enter any domain (casberi.app works) and copy the key.",
        "Your profile must be public.",
    ]

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: "Open steamcommunity.com/dev/apikey",
                             systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://steamcommunity.com/dev/apikey") {
                        openURL(url)
                    }
                }
                BridgeStepLines(steps: steps)
                // Two inputs, ONE act — so only the second slab wears the
                // verb, and it stays inert until both are filled.
                DSSlabField(placeholder: String(localized: "Profile name or SteamID"),
                            text: $profileField, actionLabel: "", action: connect)
                DSSlabField(placeholder: String(localized: "Web API key"),
                            text: $keyField,
                            actionLabel: SteamBridge.connected ? "UPDATE" : "CONNECT",
                            secure: true, isArmed: canConnect, action: connect)
                BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your games…"),
                                     result: result, resultIsError: resultIsError)
                // What LANDS is the header's own line — `BridgeSetupHeader`
                // shows Steam's tagline, "What you play, in your feed", in
                // primary body type at the top of this screen, so the sentence
                // added here earlier the same day ("The games you play land in
                // your feed") was that line paraphrased 60 points lower
                // (audit, 2026-07-31). What's left is the part the header
                // can't say.
                DSSlabNote(text: "Your key stays in \(DS.device)'s Keychain, goes only to Steam, and only ever reads public profile data.")
            }
        }
        .dsSlabSection()
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
