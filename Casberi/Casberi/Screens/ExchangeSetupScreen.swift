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
    @Environment(\.openURL) private var openURL
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
                connectForm
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(venue.display)
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: venue.display) {
                connectForm
            }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218, 2026-07-25).
    @ViewBuilder private var connectForm: some View {
        BridgeSetupHeader(name: venue.display)
        setupSection
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = setupURL {
                    DSSlabButton(title: "Open \(setupURLLabel)",
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(url)
                    }
                }
                BridgeStepLines(steps: steps, numbered: false)
                DSSlabField(placeholder: venue == .kraken ? "API key" : "Key name",
                            text: $keyDraft, actionLabel: "", action: connect)
                DSSlabField(placeholder: venue == .kraken ? "Private key" : "Private key (PEM)",
                            text: $secretDraft,
                            actionLabel: checking ? "CHECKING…" : (connected ? "UPDATE" : "CONNECT"),
                            secure: true, isArmed: armed, action: connect)
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                // Two sentences, not three paragraphs — but the §163
                // permission check STAYS said (prd §192 protected this text as
                // load-bearing trust content, not padding). What left is the
                // capability line the product page and the connected state
                // both already carry.
                DSSlabNote(text: "Casberi asks \(venue.display) what this key can do before storing it, and hands it back if it can move money.\n\nIt lives in this iPhone's Keychain and goes only to \(venue.display) — nothing here can place an order, withdraw, or transfer.")
            }
        }
        .dsSlabSection()
    }

    /// The key page, per venue — checked live 2026-07-25.
    private var setupURL: URL? {
        switch venue {
        case .kraken:   URL(string: "https://www.kraken.com/u/security/api")
        case .coinbase: URL(string: "https://portal.cdp.coinbase.com/access/api")
        }
    }

    private var setupURLLabel: String {
        switch venue {
        case .kraken:   "kraken.com → API"
        case .coinbase: "Coinbase developer portal"
        }
    }

    /// The ONE thing left to say after the door (prd §220). Named per venue,
    /// because the permission a person has to find is named differently in each
    /// dashboard and "give it read access" helps nobody standing in front of a
    /// list of checkboxes — that difference is the only reason this is a
    /// `switch` and not a constant.
    ///
    /// The second step was deleted, not shortened: it said "paste the key and
    /// its private key below" over two fields already labelled with those exact
    /// words, then repeated the §163 permission check the note underneath
    /// states in full. Both halves were already on screen. §218 applied
    /// "the placeholder says what to type" to the section headers and stopped
    /// short of the steps; this is the same rule reaching them.
    private var steps: [String] {
        switch venue {
        case .kraken:
            // Kraken's dashboard is checkboxes across four groups, so the line
            // has to name which to tick AND which to leave — one clause each,
            // not a paragraph carrying both plus a conditional.
            return ["Create a key with only the Query permissions ticked — Query Funds, plus Query Ledger Entries for deposits and withdrawals. Leave everything else unticked."]
        case .coinbase:
            return ["Create an API key with View permission only — not Trade, not Transfer."]
        }
    }

    /// A hand-rolled control must state its own disabled state (§83); the slab
    /// field does that for us now, so this is just the arm condition.
    private var armed: Bool {
        !checking
            && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty
            && !secretDraft.trimmingCharacters(in: .whitespaces).isEmpty
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
