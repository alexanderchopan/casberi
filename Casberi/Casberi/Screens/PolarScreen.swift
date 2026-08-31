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
    @State private var result: String?
    @State private var resultIsError = false
    @State private var flipTrigger = 0

    @State private var recent: [Thing] = []
    @State private var mrr: String?
    @State private var activeSubs: Int?

    private var hasToken: Bool {
        _ = accountVersion
        return TokenBridge.polar.connected
    }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Polar",
                mode: .pasteKey,
                intro: "Paste a read-only token and the money that needs you keeps arriving: a dispute and its deadline, a refund, a subscription leaving a healthy state. Individual payments never land, and nothing here reads a customer's name or card.",
                connected: hasToken,
                flipTrigger: flipTrigger)
            if hasToken {
                RoomDoor(name: "Polar", source: PolarWatch.source)
                    .listRowSeparator(.hidden)
            }
            if hasToken {
                readingSection.listRowSeparator(.hidden)
                if !recent.isEmpty {
                    RecentThingsSection(header: "Landed", things: recent.live)
                }
                BridgeDisconnectSection(bridgeID: TokenBridge.polar.bridgeID,
                                        name: "Polar",
                                        teardown: {
                                            TokenVault.delete(TokenBridge.polar.tokenKey)
                                            PolarAccount.clear()
                                            accountVersion += 1
                                            load()
                                        })
                    .listRowSeparator(.hidden)
            } else {
                tokenSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Polar")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Polar")
        .onAppear {
            load()
            if hasToken { Task { await sync() } }
        }
    }

    // MARK: - Step one: the token

    private var tokenSection: some View {
        Section {
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
                // The three scopes ARE the read-only promise (Stripe's own
                // reasoning) — a token minted with only these physically
                // cannot refund, cancel, or create anything.
                DSCheckList(lines: ["Refunds — read",
                                    "Subscriptions — read",
                                    "Organizations — read"])
                BridgeStepLines(steps: [TokenBridge.polar.steps[1]], numbered: false)
                DSSlabField(placeholder: TokenBridge.polar.placeholder,
                            text: $tokenField, actionLabel: "Save", secure: true,
                            action: saveToken)
                BridgeSyncStatusRows(syncing: connecting,
                                     syncingLine: String(localized: "Checking the token…"),
                                     result: result, resultIsError: resultIsError)
            }
        }
        .dsSlabSection()
    }

    // MARK: - Connected: the reading

    /// The one live figure on the screen, and a STATE rather than an event
    /// (§216) — so it renders as a card that updates in place and never
    /// lands in the feed as a row.
    private var readingSection: some View {
        Section {
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
                                     result: result, resultIsError: resultIsError)
                DSSlabNote(text: "Refunds, disputes and subscriptions leaving a healthy state land on their own.")
            }
        }
        .dsSlabSection()
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

    // MARK: - Actions

    private func load() {
        recent = recentBridgeThings(source: PolarWatch.source, context: modelContext)
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
                resultIsError = false
                result = name.isEmpty ? String(localized: "Connected")
                                      : String(localized: "Connected to \(name)")
                flipTrigger += 1
                DSHaptic.success()
                PolarWatch.registerBridge(store: store)
                load()
                await sync()
            case .rejected(let detail):
                var message = String(localized: "Polar didn't accept that token. Check you copied the whole thing — and that it's a Production token, not a Sandbox one.")
                if let detail { message += String(localized: " (Polar said: \"\(detail)\".)") }
                fail(message)
            case .missingScope(let detail):
                var message = String(localized: "That token works, but it's missing a permission this needs. Add Refunds (read) and Subscriptions (read) to the token in Polar.")
                if let detail { message += String(localized: " (Polar said: \"\(detail)\".)") }
                fail(message)
            case .unreachable:
                fail(String(localized: "Couldn't reach Polar — check your connection."))
            }
        }
    }

    private func fail(_ message: String) {
        resultIsError = true
        result = message
    }

    private func sync() async {
        guard !syncing, hasToken else { return }
        syncing = true
        defer { syncing = false }
        let added = await PolarIngest.refresh(context: modelContext)
        load()
        PolarWatch.registerBridge(store: store)
        if let added {
            result = added > 0 ? String(localized: "\(added) new")
                               : String(localized: "Up to date")
            resultIsError = false
        } else {
            result = String(localized: "Couldn't reach Polar — check your connection.")
            resultIsError = true
        }
    }
}
