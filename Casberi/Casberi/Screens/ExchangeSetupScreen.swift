import SwiftUI
import SwiftData

/// Connecting an exchange, read-only (2026-07-21, prd §163). One screen, both
/// venues — the steps differ only in what the venue calls its permissions.
///
/// The verdict is the whole design. `ExchangeBridge.connect` asks the exchange
/// what the key may do BEFORE storing it, so a key that can move money is
/// never written to the device at all. When it is refused, the reply names the
/// offending permissions, and this screen shows those names — "this key can
/// trade" is actionable in a way "invalid key" never is, because it tells you
/// which box to untick on a key you then remake.
///
/// The copy deliberately does NOT say "so Casberi can't trade your funds".
/// Casberi has no signing path and no order endpoint; it could not trade with
/// a trade-capable key either (user, 2026-07-21). The true reason is smaller
/// and worth stating plainly: an API key is usable by whoever holds it, so the
/// app asks for the weakest one that does the job.
struct ExchangeSetupScreen: View {
    let venue: ExchangeBridge.Venue

    @Environment(BridgeStore.self) private var store
    @State private var keyDraft = ""
    @State private var secretDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var connected: Bool

    init(venue: ExchangeBridge.Venue) {
        self.venue = venue
        _connected = State(initialValue: ExchangeBridge.credentials(venue) != nil)
    }

    /// The credentials door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        List {
            if connected {
                // Connected (prd §186). The identity here is the VERDICT —
                // the §163 permission check is this bridge's whole point, so
                // "read-only key, verified" is the fact worth leading with,
                // and it's one we actually hold: a key that could move money
                // was never stored in the first place.
                BridgeConnectedState(
                    bridgeID: venue.rawValue,
                    name: venue.display,
                    identity: String(localized: "Read-only key"),
                    connectionNote: String(localized: "\(venue.display) confirmed this key can't trade or withdraw · stored in this iPhone's Keychain"),
                    capabilitiesFallback: [String(localized: "Reads your balances."),
                                           String(localized: "Adds them to your combined total."),
                                           String(localized: "Can't place an order, withdraw, or transfer.")],
                    openConnection: { showConnection = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                stepsSection.listRowSeparator(.hidden)
                connectSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(venue.display)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: venue.display) {
                stepsSection.listRowSeparator(.hidden)
                connectSection.listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        Section {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                step(i + 1, text)
            }
        } header: {
            Text("Make a view-only key").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    /// Named per venue, because the permission a person has to find is named
    /// differently in each dashboard and "give it read access" helps nobody
    /// standing in front of a list of checkboxes.
    private var steps: [String] {
        switch venue {
        case .kraken:
            return ["At kraken.com, open Settings → API and create a new key.",
                    "Tick only the Query permissions — Query Funds, and Query Ledger Entries if you want deposits and withdrawals to show. Leave every Create, Modify, Withdraw and Deposit box unticked.",
                    "Paste the key and its private key below. Casberi asks Kraken what the key can do before it saves."]
        case .coinbase:
            return ["At the Coinbase developer portal, create an API key for your account.",
                    "Give it View permission only — not Trade, not Transfer.",
                    "Paste the key name and its private key below. Casberi asks Coinbase what the key can do before it saves."]
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text("\(n)")
                .dsText(.subhead13).fontWeight(.bold)
                .foregroundStyle(DS.tint)
                .frame(width: 16)
            Text(LocalizedStringKey(text))
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dsListCardRow()
    }

    // MARK: - Connect

    private var connectSection: some View {
        Section {
            field(placeholder: venue == .kraken ? "API key" : "Key name", text: $keyDraft, secure: false)
            field(placeholder: venue == .kraken ? "Private key" : "Private key (PEM)", text: $secretDraft, secure: true)
            HStack {
                Spacer()
                // A hand-rolled button that paints its own background must swap
                // that background when disabled — `.disabled` dims a plain
                // button's label, not your fill (honesty rule, prd §83).
                let armed = !checking
                    && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty
                    && !secretDraft.trimmingCharacters(in: .whitespaces).isEmpty
                Button { connect() } label: {
                    Text(checking ? "Checking…" : (connected ? "Update" : "Connect"))
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(armed ? AnyShapeStyle(.white) : AnyShapeStyle(DS.textTertiary))
                        .padding(.horizontal, DS.Space.s4)
                        .frame(height: 44)
                        .background(armed ? AnyShapeStyle(DS.tint) : AnyShapeStyle(DS.gray200),
                                    in: Capsule(style: .continuous))
                        .animation(DS.Motion.standard, value: armed)
                }
                .buttonStyle(.plain)
                .disabled(!armed)
            }
            .dsListCardRow()
            BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
        } footer: {
            Text("Your balances join your watched wallets in one combined total and one map.\n\nCasberi asks \(venue.display) what this key is allowed to do before storing it, and hands it back if it can move money — an API key works for whoever holds it, so the app keeps the weakest one that does the job.\n\nThe key lives in the Keychain and goes only to \(venue.display). Nothing here can place an order, withdraw, or transfer.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    private func field(placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .dsText(.callout15)
        .padding(.horizontal, DS.Space.s3)
        .frame(height: 44)
        .background(DS.fillFaint, in: Capsule(style: .continuous))
        .dsListCardRow()
    }

    private func connect() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // The secret is NOT whitespace-trimmed the way the key is: Coinbase's
        // is a PEM whose newlines are structural, and trimming the trailing one
        // is enough to make it unparseable.
        let secret = secretDraft
        guard !key.isEmpty, !secret.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let verdict = await ExchangeBridge.connect(venue, key: key, secret: secret)
            checking = false
            switch verdict {
            case .readOnly:
                connected = true
                keyDraft = ""
                secretDraft = ""
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — your \(venue.display) balance now joins your wallets.")
                store.registerConnected(id: venue.rawValue, name: venue.display,
                                        proof: String(localized: "View-only key, verified with \(venue.display)"),
                                        can: [String(localized: "Reads your balances."),
                                              String(localized: "Adds them to your combined total."),
                                              String(localized: "Can't place an order, withdraw, or transfer.")])
            case .tooPowerful(let permissions):
                resultIsError = true
                // Name what's wrong: the person has to go back and untick
                // something specific, and only the exchange knows which.
                result = String(localized: "That key can \(permissions.joined(separator: ", ")) — make a view-only one and paste that instead. It wasn't saved.")
            case .unverifiable(let why):
                resultIsError = true
                result = why
            }
        }
    }
}
