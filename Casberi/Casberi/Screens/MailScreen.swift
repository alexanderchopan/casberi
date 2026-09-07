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
    @State private var result: BridgeProof?

    /// The credentials door, open (prd §186).

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: provider.source, seatID: provider.bridgeID, source: provider.source,
            state: AccountPageState.of(name: provider.source, seatID: provider.bridgeID,
                                       connected: provider.connected, store: store),
            mode: .pasteKey,
            keyed: true,
            teardown: { TokenVault.delete(provider.passwordKey) },
            sheet: $sheet,
            act: {
                if provider.connected {
                    // The ADDRESS is the identity — the one fact worth leading
                    // with. The app-password field that used to stare from
                    // this screen forever is the "Your key" sheet now.
                    addressLine
                    BridgeSyncStatusRows(syncing: syncing,
                                         syncingLine: String(localized: "Reading your mail…"),
                                         proof: result)
                } else {
                    setupBlock
                }
            },
            more: { EmptyView() },
            keySheet: { setupBlock }
        )
        .onAppear {
            addressField = provider.address
            if provider.connected { Task { await sync() } }
        }
    }

    /// Whose mailbox this reads.
    @ViewBuilder private var addressLine: some View {
        if !provider.address.isEmpty {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: provider.source, size: DS.Mark.list, circular: false)
                Text(provider.address)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
        }
    }


    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Unnumbered: one instruction is not a sequence (§220).
            BridgeSetupCard(steps: provider.steps, numbered: false) {
                if let url = provider.setupURL {
                    // Verb over address, the 2026-08-14 anatomy.
                    DSSlabButton(title: provider.doorTitle,
                                 detail: provider.doorHost,
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(url)
                    }
                }
            }
            // Two inputs, one act — the verb rides the password, where
            // connecting actually happens.
            DSSlabField(placeholder: provider.addressPlaceholder, text: $addressField,
                        actionLabel: "", keyboard: .emailAddress, action: connect)
            DSSlabField(placeholder: provider.passwordPlaceholder, text: $passwordField,
                        actionLabel: provider.connected ? "Update" : "Connect",
                        secure: true, isArmed: canConnect, action: connect)
            BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading your inbox…"),
                                 proof: result)
            DSSlabNote(text: provider.footer, plain: true)
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
        guard let added else {
            if justConnected { TokenVault.delete(provider.passwordKey) }
            switch MailIngest.lastError {
            case .login:
                result = .says(String(localized: "Login rejected — check the address and app-specific password."))
            case .connect:
                result = .says(String(localized: "Couldn't reach the mail server — check your connection."))
            case .select, .fetch, .timeout:
                result = .says(String(localized: "Signed in, but couldn't read the inbox — try again."))
            case nil:
                result = .says(String(localized: "Couldn't sign in — check the address and app-specific password."))
            }
            return
        }
        result = added > 0 ? .says(String(localized: "\(added) in your feed")) : .upToDate
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
