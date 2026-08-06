import SwiftUI
import SwiftData

/// APPLE WALLET'S SETUP SCREEN (2026-08-06, prd §313).
///
/// **This screen is a contract, not copy.** Apple granted the FinanceKit
/// entitlement against a written description of exactly this screen: that
/// BEFORE anything is requested it states what will be read, that the data
/// stays on the device, that the app has no server, and that nothing is
/// uploaded, sold or shared — and that a one-tap disconnect stops the reading
/// and deletes what landed.
///
/// So the disclosure below is not marketing and must not be trimmed for
/// balance. Every sentence corresponds to a promise on file with Apple, and
/// `AppleWalletBridge.disconnect(context:)` is what makes the last one true.
///
/// The order matters too: the person reads what happens BEFORE the button that
/// makes it happen. Apple's own prompt appears only after they tap Connect,
/// which means this screen — not the system sheet — is where informed consent
/// actually occurs.
struct AppleWalletScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome

    @State private var connecting = false
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var flipTrigger = 0
    @State private var recent: [Thing] = []
    @State private var balances: [String: String] = [:]
    @State private var stateVersion = 0

    private var isConnected: Bool {
        _ = stateVersion
        return AppleWalletBridge.connected
    }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Apple Wallet",
                mode: .onThisDevice,
                intro: "Apple Card, Apple Cash and Savings, with the merchant's real name. United States only, iOS 17.4 or later.",
                connected: isConnected,
                flipTrigger: flipTrigger)

            if !AppleWalletBridge.isSupported && !isConnected {
                unavailableSection
            } else if isConnected {
                if !balances.isEmpty { balanceSection }
                if !recent.isEmpty {
                    RecentThingsSection(header: "Landed", things: recent.live)
                }
                promiseSection
                BridgeDisconnectSection(bridgeID: AppleWalletBridge.seatID,
                                        name: AppleWalletBridge.sourceName,
                                        teardown: {
                                            AppleWalletBridge.disconnect(context: modelContext)
                                            stateVersion += 1
                                            load()
                                        })
            } else {
                promiseSection
                connectSection
            }

            if let result {
                Section {
                    Text(result)
                        .dsText(.subhead13)
                        .foregroundStyle(resultIsError ? DS.textPrimary : DS.textSecondary)
                }
            }

        }
        .dsPageBackground()
        .scrollContentBackground(.hidden)
        .navigationTitle("Apple Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    // MARK: - The promise (the entitlement's own terms, in plain words)

    private var promiseSection: some View {
        Section {
            // Not numbered: these are four FACTS, not an ordered procedure —
            // §220's rule, and numerals here would send the eye hunting for a
            // step 1 that doesn't exist.
            BridgeStepLines(steps: [
                String(localized: "Read on this \(DS.device). Casberi has no server, so nothing is uploaded or sold."),
                String(localized: "It can't spend or move money."),
                String(localized: "Disconnect and everything it brought in is deleted."),
            ], numbered: false)
        } header: {
            Text("Before you connect")
        }
    }

    // MARK: - Connect

    private var connectSection: some View {
        Section {
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    Text(connecting ? "Connecting…" : "Connect Apple Wallet")
                        .dsText(.body17).fontWeight(.semibold)
                    Spacer()
                    if connecting { ProgressView() }
                }
            }
            .disabled(connecting)
        }
    }

    /// The honest dead-end. An unsupported device gets a real explanation
    /// rather than a Connect button that can only fail — the no-dead-controls
    /// rule (§83).
    private var unavailableSection: some View {
        Section {
            Text("This \(DS.device) can't share financial data. It's US-only, and needs iOS 17.4.")
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Balances

    /// Balances are shown per account and NEVER summed. Three accounts are
    /// three facts; one total across a credit line, a cash balance and savings
    /// is an accounting choice nobody agreed on — the wallet composition
    /// ruling (§240), and `StripeScreen`'s standing rule about currencies.
    private var balanceSection: some View {
        Section {
            ForEach(balances.keys.sorted(), id: \.self) { name in
                HStack {
                    Text(name)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                    Text(balances[name] ?? "")
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Balances")
        } footer: {
            Text("Never added together.")
                .dsText(.label11)
                .foregroundStyle(DS.textTertiary)
        }
    }

    // MARK: - Actions

    @MainActor
    private func connect() async {
        connecting = true
        defer { connecting = false }
        let outcome = await AppleWalletBridge.connect(context: modelContext, store: store)
        stateVersion += 1
        result = outcome.line
        switch outcome {
        case .connected:
            resultIsError = false
            flipTrigger += 1
            DSHaptic.success()
            load()
        default:
            resultIsError = true
        }
    }

    @MainActor
    private func load() {
        balances = AppleWalletBridge.balances
        let name = AppleWalletBridge.sourceName
        var fetch = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        fetch.fetchLimit = 5
        recent = (try? modelContext.fetch(fetch)) ?? []
    }
}
