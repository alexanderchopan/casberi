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
    @State private var balances: [String: String] = [:]
    @State private var stateVersion = 0

    private var isConnected: Bool {
        _ = stateVersion
        return AppleWalletBridge.connected
    }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Apple Wallet", seatID: AppleWalletBridge.seatID,
            source: AppleWalletBridge.sourceName,
            state: AccountPageState.of(name: "Apple Wallet", seatID: AppleWalletBridge.seatID,
                                       connected: isConnected, store: store),
            intro: "Apple Card, Apple Cash and Savings, with the merchant's real name. United States only, iOS 17.4 or later.",
            mode: .onThisDevice,
            teardown: {
                AppleWalletBridge.disconnect(context: modelContext)
                stateVersion += 1
                load()
            },
            sheet: $sheet,
            act: {
                if !AppleWalletBridge.isSupported && !isConnected {
                    unavailableBlock
                } else if isConnected {
                    if !balances.isEmpty { balanceBlock }
                } else {
                    promiseBlock
                    connectBlock
                }
                if let result {
                    Text(result)
                        .dsText(.subhead13)
                        .foregroundStyle(resultIsError ? DS.textPrimary : DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            },
            more: {
                // The entitlement's own terms stay on the page once connected
                // too — they are what this seat promised, and a promise that
                // disappears the moment it is kept is one nobody can check.
                if isConnected { promiseBlock }
            },
            keySheet: { EmptyView() }
        )
        .task { load() }
    }


    // MARK: - The promise (the entitlement's own terms, in plain words)

    @ViewBuilder private var promiseBlock: some View {
        // Not numbered: these are three FACTS, not an ordered procedure —
        // §220's rule, and numerals here would send the eye hunting for a
        // step 1 that doesn't exist.
        BridgeStepLines(steps: [
            String(localized: "Read on this \(DS.device). Nothing is uploaded."),
            String(localized: "It can't spend or move money."),
            String(localized: "Disconnect and everything it brought in is deleted."),
        ], numbered: false)
    }

    // MARK: - Connect

    @ViewBuilder private var connectBlock: some View {
        // The screen's one verb as the screen's one filled block (prd §218) —
        // it was a plain list row, which on a page with no rows around it read
        // as a label rather than the act itself.
        DSSlabButton(title: connecting ? "Connecting…" : "Connect Apple Wallet",
                     systemImage: "creditcard",
                     busy: connecting,
                     enabled: !connecting) {
            DSHaptic.tap()
            Task { await connect() }
        }
    }

    /// The honest dead-end. An unsupported device gets a real explanation
    /// rather than a Connect button that can only fail — the no-dead-controls
    /// rule (§83).
    @ViewBuilder private var unavailableBlock: some View {
        Text("This \(DS.device) can't share financial data. It's US-only, and needs iOS 17.4.")
            .dsText(.subhead13)
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Balances

    /// Balances are shown per account and NEVER summed. Three accounts are
    /// three facts; one total across a credit line, a cash balance and savings
    /// is an accounting choice nobody agreed on — the wallet composition
    /// ruling (§240), and `StripeScreen`'s standing rule about currencies.
    @ViewBuilder private var balanceBlock: some View {
        ForEach(balances.keys.sorted(), id: \.self) { name in
            HStack {
                Text(name)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                Text(balances[name] ?? "")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
            }
            .frame(minHeight: AccountFactRow.height)
        }
        Text("Never added together.")
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
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
            DSHaptic.success()
            load()
        default:
            resultIsError = true
        }
    }

    @MainActor
    private func load() {
        balances = AppleWalletBridge.balances
    }
}
