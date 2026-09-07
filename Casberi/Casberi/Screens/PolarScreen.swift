import SwiftUI
import SwiftData

/// Polar, connected — paste a read-only token, and that's the whole setup.
/// `StripeScreen`'s exact shape: one account behind one credential, nothing
/// to choose, two states (no token → the field; a token → the reading, what's
/// landed, and Disconnect).
struct PolarScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL

    @State private var tokenField = ""
    @State private var accountVersion = 0

    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?

    @State private var mrr: String?
    @State private var activeSubs: Int?

    private var hasToken: Bool {
        _ = accountVersion
        return TokenBridge.polar.connected
    }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Polar", seatID: TokenBridge.polar.bridgeID, source: PolarWatch.source,
            state: AccountPageState.of(name: "Polar", seatID: TokenBridge.polar.bridgeID,
                                       connected: hasToken, store: store),
            intro: "Sales as they happen, plus what needs you: a dispute and its deadline, a refund, a subscription going bad. Never a customer's name or card.",
            mode: .pasteKey,
            keyed: true,
            teardown: {
                TokenVault.delete(TokenBridge.polar.tokenKey)
                accountVersion += 1
            },
            sheet: $sheet,
            act: {
                if hasToken {
                    // What the key is reading right now. The token form is the
                    // "Your key" sheet, reached from the row that says where
                    // the key lives.
                    readingBlock
                } else {
                    tokenBlock
                }
            },
            more: { EmptyView() },
            keySheet: { tokenBlock }
        )
        .onAppear {
            load()
            if hasToken { Task { await sync() } }
        }
    }


    /// The one live figure on the screen, and a STATE rather than an event
    /// (§216) — so it renders as a card that updates in place and never
    /// lands in the feed as a row.
    @ViewBuilder private var readingBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let mrr {
                readout(String(localized: "Recurring revenue"), "\(mrr)/mo")
            }
            if let activeSubs {
                readout(String(localized: "Active subscribers"), "\(activeSubs)")
            }
            if mrr == nil && activeSubs == nil {
                Text("Reading your revenue…")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading Polar…"),
                                 proof: result)
            DSSlabNote(text: "Sales, refunds, disputes and subscriptions leaving a healthy state land on their own. Renewals stay out.", plain: true)
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(label)
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
            Spacer(minLength: DS.Space.s2)
            Text(value)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
        }
    }

    // MARK: - The key

    /// The connect form — steps whole, furniture gone (prd §218). It is the
    /// act field with no key, and the "Your key" sheet once there is one, so a
    /// key is replaced by exactly the path it was pasted.
    @ViewBuilder private var tokenBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let url = TokenBridge.polar.setupURL {
                DSSlabButton(title: TokenBridge.polar.doorTitle,
                             detail: TokenBridge.polar.doorHost,
                             systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    openURL(url)
                }
            }
            BridgeStepLines(steps: [TokenBridge.polar.steps[0]], numbered: false)
            // The four scopes ARE the read-only promise (Stripe's own
            // reasoning) — a token minted with only these physically
            // cannot refund, cancel, or create anything. Orders joined
            // them in §537; a token minted before that has three, which
            // costs the sales half and nothing else (see `PolarFetch.orders`).
            DSCheckList(lines: ["Orders — read",
                                "Refunds — read",
                                "Subscriptions — read",
                                "Organizations — read"])
            BridgeStepLines(steps: [TokenBridge.polar.steps[1]], numbered: false)
            DSSlabField(placeholder: TokenBridge.polar.placeholder,
                        text: $tokenField, actionLabel: "Save", secure: true,
                        action: saveToken)
            BridgeSyncStatusRows(syncing: connecting,
                                 syncingLine: String(localized: "Checking the token…"),
                                 proof: result)
        }
    }

    // MARK: - Actions

    private func load() {
        let reading = PolarState.reading()
        mrr = PolarState.mrrText()
        activeSubs = reading.activeSubscriptions
    }

    private func saveToken() {
        let token = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        // A double paste is invisible behind the dots and 401s exactly like a
        // wrong token, so it gets said plainly here rather than being sent to
        // Polar to come back as "Unauthorized" (2026-08-31 — the measured
        // cause of the first report against this bridge).
        guard !PolarFetch.isDoubled(token) else {
            fail(String(localized: "That looks like the token pasted twice. Clear the field and paste it once."))
            return
        }
        connecting = true
        result = nil
        Task {
            let outcome = await PolarFetch.validate(key: token)
            connecting = false
            switch outcome {
            case .ok(_, let name, let slug):
                TokenVault.set(token, for: TokenBridge.polar.tokenKey)
                PolarAccount.orgName = name
                PolarAccount.orgSlug = slug
                tokenField = ""
                accountVersion += 1
                result = .connected(name.isEmpty ? nil : name)
                DSHaptic.success()
                PolarWatch.registerBridge(store: store)
                load()
                await sync()
            case .rejected(let detail):
                var message = String(localized: "Polar didn't accept that token. Check you copied the whole thing — and that it's a Production token, not a Sandbox one.")
                if let detail { message += String(localized: " (Polar said: \"\(detail)\".)") }
                fail(message)
            case .missingScope(let detail):
                var message = String(localized: "That token works, but it's missing a permission this needs. Add Orders (read), Refunds (read) and Subscriptions (read) to the token in Polar.")
                if let detail { message += String(localized: " (Polar said: \"\(detail)\".)") }
                fail(message)
            case .unreachable:
                fail(String(localized: "Couldn't reach Polar — check your connection."))
            }
        }
    }

    private func fail(_ message: String) {
        result = .failed(message)
    }

    private func sync() async {
        guard !syncing, hasToken else { return }
        syncing = true
        defer { syncing = false }
        let added = await PolarIngest.refresh(context: modelContext)
        load()
        PolarWatch.registerBridge(store: store)
        if let added {
            result = .landed(added)
        } else {
            result = .failed(String(localized: "Couldn't reach Polar — check your connection."))
        }
    }


}
