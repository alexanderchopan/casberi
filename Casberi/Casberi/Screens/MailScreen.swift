import SwiftUI
import SwiftData

/// One screen for both mail bridges — the steps to make an app-specific
/// password, an address field and a password field. Read-only over IMAP;
/// the real account password never enters the app.
struct MailScreen: View {
    let provider: MailProvider

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var addressField = ""
    @State private var passwordField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false

    /// The credentials door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if provider.connected {
                // Connected (prd §186): the ADDRESS is the identity — the one
                // fact worth leading with — and the app-password field that
                // used to stare from this screen forever moves behind the door.
                BridgeConnectedState(
                    bridgeID: provider.bridgeID,
                    name: provider.source,
                    identity: provider.address,
                    connectionNote: String(localized: "App password · stored in \(DS.device)'s Keychain. Read-only over IMAP."),
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
        .bridgeSetupWash(name: provider.source)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(provider.rawValue)
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: provider.rawValue) {
                connectForm
                BridgeDisconnectSection(
                    bridgeID: provider.bridgeID, name: provider.source,
                    teardown: { TokenVault.delete(provider.passwordKey) }
                ).listRowSeparator(.hidden)
            }
        }
        .onAppear {
            addressField = provider.address
            if provider.connected { Task { await sync() } }
        }
    }

    /// The connect form — steps whole (user ruling 2026-07-23), furniture gone
    /// (prd §218, 2026-07-25).
    @ViewBuilder private var connectForm: some View {
        BridgeSetupHeader(
            name: provider.source,
            mode: .pasteKey,
            intro: "Make an app-specific password and your mail becomes searchable here. Read-only over IMAP, and your real account password never enters the app.")
        setupSection
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = provider.setupURL {
                    // Verb over address, the 2026-08-14 anatomy.
                    DSSlabButton(title: provider.doorTitle,
                                 detail: provider.doorHost,
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(url)
                    }
                }
                // Unnumbered: one instruction is not a sequence (§220).
                BridgeStepLines(steps: provider.steps, numbered: false)
                // Two inputs, one act — the verb rides the password, where
                // connecting actually happens.
                DSSlabField(placeholder: provider.addressPlaceholder, text: $addressField,
                            actionLabel: "", keyboard: .emailAddress, action: connect)
                DSSlabField(placeholder: provider.passwordPlaceholder, text: $passwordField,
                            actionLabel: provider.connected ? "Update" : "Connect",
                            secure: true, isArmed: canConnect, action: connect)
                BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your inbox…"),
                                     result: result, resultIsError: resultIsError)
                DSSlabNote(text: provider.footer)
            }
        }
        .dsSlabSection()
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
        guard let added else {
            if justConnected { TokenVault.delete(provider.passwordKey) }
            switch MailIngest.lastError {
            case .login:
                result = String(localized: "Login rejected — check the address and app-specific password.")
            case .connect:
                result = String(localized: "Couldn't reach the mail server — check your connection.")
            case .select, .fetch, .timeout:
                result = String(localized: "Signed in, but couldn't read the inbox — try again.")
            case nil:
                result = String(localized: "Couldn't sign in — check the address and app-specific password.")
            }
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) in your feed") : String(localized: "Up to date")
        let proof = added > 0
            ? String(localized: "\(added) mail in")
            : String(localized: "Synced just now")
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
