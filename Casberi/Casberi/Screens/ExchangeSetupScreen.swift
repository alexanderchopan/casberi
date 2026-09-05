import SwiftUI
import SwiftData

/// Connecting an exchange, read-only (2026-07-21, prd §163). One screen,
/// every venue (Kraken/Coinbase, then Binance/Gemini Exchange added
/// 2026-07-27) — the steps differ only in what the venue calls its
/// permissions.
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
    @State private var result: BridgeProof?

    /// Read straight from the Keychain, like `SpotifyAuth.connected` /
    /// `DropboxAuth.connected` — so a disconnect (which only ever touches
    /// `TokenVault`) is reflected the moment anything else on this screen
    /// triggers a re-render, with no state var of our own to fall out of sync.
    private var connected: Bool { ExchangeBridge.credentials(venue) != nil }

    /// The credentials door, open (prd §186).
    @State private var showConnection = false

    var body: some View {
        // `venue.display`, not `venue.rawValue` — `.geminiExchange`'s raw
        // value has no space, so it would miss `washHue`'s "gemini exchange"
        // key; `display` is what every other venue already matches on too.
        BridgeSetupPage(name: venue.display, computedTitle: venue.display) {
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
                    connectionNote: String(localized: "\(venue.display) confirmed this key can't trade or withdraw · stored in \(DS.device)'s Keychain"),
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
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: venue.display) {
                connectForm
                if connected { removeSection.listRowSeparator(.hidden) }
            }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218, 2026-07-25).
    @ViewBuilder private var connectForm: some View {
        BridgeSetupHeader(
            name: venue.display,
            mode: .pasteKey,
            intro: "Paste a read-only key and your balances and trades keep arriving. \(venue.display) is asked what the key may do before it is ever stored — one that can move money is refused and never written to this \(DS.device).")
        setupSection
    }

    private var removeSection: some View {
        // No purge dialog here, and that falls out of the data rather than a
        // flag: an exchange seat lands no `Thing` at all (§484's rowless
        // nine), so `BridgeDisconnectSection` finds nothing to offer.
        BridgeDisconnectSection(bridgeID: venue.rawValue, name: venue.display,
                                teardown: { ExchangeBridge.disconnect(venue) },
                                note: String(localized: "Its balance leaves your combined total."))
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = setupURL {
                    // Verb over address, the 2026-08-14 anatomy.
                    DSSlabButton(title: "Get your API key",
                                 detail: doorHost,
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(url)
                    }
                }
                BridgeStepLines(steps: steps, numbered: false)
                DSSlabField(placeholder: keyPlaceholder,
                            text: $keyDraft, actionLabel: "", action: connect)
                DSSlabField(placeholder: secretPlaceholder,
                            text: $secretDraft,
                            actionLabel: checking ? "Checking…" : (connected ? "Update" : "Connect"),
                            secure: true, isArmed: armed, action: connect)
                BridgeSyncStatusRows(proof: result)
                // Two sentences, not three paragraphs — but the §163
                // permission check STAYS said (prd §192 protected this text as
                // load-bearing trust content, not padding). What left is the
                // capability line the product page and the connected state
                // both already carry.
                //
                // "— nothing here can place an order, withdraw, or transfer"
                // left too (audit, 2026-07-31): the sentence above it already
                // says a key that can move money is handed back, this screen's
                // connected state carries the clause word for word as its third
                // capability line, and the doc note at the top of this file
                // rules that the copy shouldn't be leaning on "Casberi can't
                // trade" in the first place.
                DSSlabNote(text: "\(venue.display) is asked what this key can do before it's stored — anything that can move money is refused.")
            }
        }
        .dsSlabSection()
    }

    /// The key page, per venue — checked live 2026-07-25 (Binance/Gemini
    /// added 2026-07-27, docs-verified, not click-walked live).
    private var setupURL: URL? {
        switch venue {
        case .kraken:   URL(string: "https://www.kraken.com/u/security/api")
        case .coinbase: URL(string: "https://portal.cdp.coinbase.com/access/api")
        case .binance:  URL(string: "https://www.binance.com/en/my/settings/api-management")
        case .geminiExchange: URL(string: "https://exchange.gemini.com/settings/api")
        }
    }

    /// The address under the door's verb — derived from `setupURL` so it can
    /// never drift from where the door actually goes (the TokenBridges rule).
    private var doorHost: String {
        guard let host = setupURL?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Kraken/Binance/Gemini all call the identifier an "API key"; only
    /// Coinbase's CDP scheme names it instead of keying it.
    private var keyPlaceholder: String {
        switch venue {
        case .kraken, .binance, .geminiExchange: "API key"
        case .coinbase: "Key name"
        }
    }

    private var secretPlaceholder: String {
        switch venue {
        case .kraken, .binance, .geminiExchange: "Private key"
        case .coinbase: "Private key (PEM)"
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
            return ["Create a key with only the Query permissions ticked — Query Funds, plus Query Ledger Entries for deposits and withdrawals."]
        case .coinbase:
            return ["Create an API key with View permission only — not Trade, not Transfer."]
        case .binance:
            return ["Create an API key with only \"Enable Reading\" ticked — leave Spot & Margin Trading, Withdrawals, and everything else off."]
        case .geminiExchange:
            return ["Create an API key with the Auditor role — not Trader, not Fund Manager."]
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
                keyDraft = ""
                secretDraft = ""
                DSHaptic.success()
                result = .connected(String(localized: "your \(venue.display) balance now joins your wallets."))
                store.registerConnected(id: venue.rawValue, name: venue.display,
                                        proof: String(localized: "View-only key, verified with \(venue.display)"),
                                        can: [String(localized: "Reads your balances."),
                                              String(localized: "Adds them to your combined total."),
                                              String(localized: "Can't place an order, withdraw, or transfer.")])
            case .tooPowerful(let permissions):
                // Name what's wrong: the person has to go back and untick
                // something specific, and only the exchange knows which.
                result = .says(String(localized: "That key can \(permissions.joined(separator: ", ")) — make a view-only one and paste that instead. It wasn't saved."))
            case .unverifiable(let why):
                result = .failed(why)
            }
        }
    }
}
