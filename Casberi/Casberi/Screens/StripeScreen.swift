import SwiftUI
import SwiftData

/// Stripe, connected — paste a restricted key, and that's the whole setup.
///
/// Deliberately shorter than `PostHogScreen`, which needed three steps (key →
/// project → watch list). Stripe has ONE account behind a key and nothing to
/// choose: the five shapes it lands are the five shapes, and offering a set of
/// toggles over them would be the connect screen §96 deleted — a source wearing
/// switches instead of a verb with a visible outcome.
///
/// Two states, one at a time (the §83 corollary about disabled controls that
/// still paint a live background): no key → the key field; a key → the balance,
/// what's landed, and Disconnect.
struct StripeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL

    @State private var keyField = ""
    /// Bumped whenever the key changes, so the derived reads below
    /// re-evaluate. The Keychain stays the source of truth — mirroring it into
    /// @State meant hand-kept assignments that could disagree with it
    /// (the PostHog contract).
    @State private var accountVersion = 0

    @State private var connecting = false
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var flipTrigger = 0

    @State private var recent: [Thing] = []
    /// The balance reading the sweep last stored — mirrored into state so the
    /// card redraws after a sync without re-reading UserDefaults in a body.
    @State private var available: String?
    @State private var pending: String?

    private var hasKey: Bool {
        _ = accountVersion
        return TokenBridge.stripe.connected
    }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Stripe",
                mode: .pasteKey,
                intro: "Paste a read-only key and the money that needs you keeps arriving: a dispute and its deadline, a payout, a cancelled subscription, a failed payment. Individual charges never land, and nothing here reads a customer's name or card.",
                connected: hasKey,
                flipTrigger: flipTrigger)
            if hasKey {
                balanceSection.listRowSeparator(.hidden)
                if !recent.isEmpty {
                    RecentThingsSection(header: "Landed", things: recent.live)
                }
                BridgeDisconnectSection(bridgeID: TokenBridge.stripe.bridgeID,
                                        name: "Stripe",
                                        teardown: {
                                            TokenVault.delete(TokenBridge.stripe.tokenKey)
                                            StripeAccount.clear()
                                            accountVersion += 1
                                            load()
                                        })
                    .listRowSeparator(.hidden)
            } else {
                keySection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Stripe")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Stripe")
        .onAppear {
            load()
            if hasKey { Task { await sync() } }
        }
    }

    // MARK: - Step one: the key

    private var keySection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = TokenBridge.stripe.setupURL {
                    // Step one, doing itself (prd §218) — verb over address,
                    // the 2026-08-14 anatomy.
                    DSSlabButton(title: TokenBridge.stripe.doorTitle,
                                 detail: TokenBridge.stripe.doorHost,
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(url)
                    }
                }
                // The next line, then the list it points AT, then the last
                // line and the field. The scopes used to sit below the field,
                // which is why the first step had to name all six in prose to
                // be useful there — the reorder is what let that sentence lose
                // them (2026-07-31). Unnumbered since 2026-08-14: the door did
                // step one, and a "2" under it read as a missing-1 riddle.
                BridgeStepLines(steps: [TokenBridge.stripe.steps[0]], numbered: false)
                // The permissions are the honest ask, and they're why this
                // bridge's read-only promise is STRUCTURAL rather than kept by
                // conduct (the Privacy.com divergence): a restricted key with
                // these six reads and nothing else physically cannot refund,
                // charge or pay out, whatever the app does. The list IS the
                // read-only promise, so the gray note that restated it is gone.
                DSCheckList(lines: ["Events — read",
                                    "Disputes — read",
                                    "Payouts — read",
                                    "Subscriptions — read",
                                    "Invoices — read",
                                    "Balance — read"])
                BridgeStepLines(steps: [TokenBridge.stripe.steps[1]], numbered: false)
                // Slabbed with the rest of the family (audit, 2026-07-31) — it
                // was a `BridgeFieldRow` capsule, the one control on the screen
                // still wearing the pre-§218 shape.
                DSSlabField(placeholder: TokenBridge.stripe.placeholder,
                            text: $keyField, actionLabel: "SAVE", secure: true,
                            action: saveKey)
                BridgeSyncStatusRows(syncing: connecting,
                                     syncingLine: String(localized: "Checking the key…"),
                                     result: result, resultIsError: resultIsError)
            }
        }
        .dsSlabSection()
    }

    // MARK: - Connected: the balance

    /// The one live figure on the screen, and the one thing here that is a
    /// STATE rather than an event (§216) — so it renders as a card that updates
    /// in place and never lands in the feed as a row. A balance nobody has read
    /// yet shows nothing rather than a fake zero.
    private var balanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let available {
                    readout(String(localized: "Available"), available)
                }
                if let pending {
                    readout(String(localized: "On the way"), pending)
                }
                if available == nil && pending == nil {
                    Text("Reading your balance…")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading Stripe…"),
                                     result: result, resultIsError: resultIsError)
                DSSlabNote(text: "Disputes, payouts, cancellations and failed payments land on their own.")
            }
        }
        .dsSlabSection()
    }

    /// One figure and what it is. Local to this screen rather than a shared
    /// component: it's two Texts, and the family's other setup screens have no
    /// figure to show — a shared "readout" with one caller is a name to keep in
    /// step for nothing.
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
        recent = recentBridgeThings(source: StripeWatch.source, context: modelContext)
        let balance = StripeState.balance()
        available = text(balance.available)
        // Money in flight, with the day it lands. "£2,140" answers how much and
        // leaves WHEN hanging, which is the half you actually plan around —
        // and Stripe knows the answer (`arrival_date`), so withholding it was
        // the number hiding information it already had. Month and day, never a
        // bare weekday (the Aerodrome lesson).
        pending = text(balance.pending).map { amount in
            guard let arrives = balance.arrivesAt else { return amount }
            return "\(amount) · arrives \(arrives.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    /// Per-currency, joined — never summed. An account taking money in three
    /// currencies has three balances, and adding them would invent an exchange
    /// rate nobody quoted (the Hyperliquid "never invent a single total" rule).
    private func text(_ buckets: [String: Int]) -> String? {
        let live = buckets.filter { $0.value != 0 }
        guard !live.isEmpty else { return nil }
        return live.sorted { $0.key < $1.key }
            .map { StripeMoney.text($0.value, currency: $0.key) }
            .joined(separator: " · ")
    }

    private func saveKey() {
        let key = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        connecting = true
        result = nil
        Task {
            let outcome = await StripeFetch.validate(key: key)
            connecting = false
            switch outcome {
            case .ok(let account, let name):
                TokenVault.set(key, for: TokenBridge.stripe.tokenKey)
                StripeAccount.accountID = account
                StripeAccount.accountName = name
                keyField = ""
                accountVersion += 1
                resultIsError = false
                result = name.isEmpty ? String(localized: "Connected")
                                      : String(localized: "Connected to \(name)")
                flipTrigger += 1
                DSHaptic.success()
                StripeWatch.registerBridge(store: store)
                load()
                await sync()
            // Four failures, four different sentences. Collapsing them into
            // "couldn't connect" would leave the two RECOVERABLE ones (a test
            // key, a key missing one permission) looking identical to a typo,
            // and the fix for each is different.
            case .testKey:
                fail(String(localized: "That's a test-mode key — only real money is held here. Mint a live restricted key."))
            case .rejected:
                fail(String(localized: "Stripe didn't accept that key. Check you copied the whole thing."))
            case .missingScope:
                fail(String(localized: "That key works, but it can't read Events — the one permission this needs. Add Events (read) to the key in Stripe."))
            case .unreachable:
                fail(String(localized: "Couldn't reach Stripe — check your connection."))
            }
        }
    }

    private func fail(_ message: String) {
        resultIsError = true
        result = message
    }

    /// Reads Stripe and lands whatever counts as news.
    private func sync() async {
        guard !syncing, hasKey else { return }
        syncing = true
        defer { syncing = false }
        let added = await StripeIngest.refresh(context: modelContext)
        load()
        StripeWatch.registerBridge(store: store)
        if let added {
            result = added > 0 ? String(localized: "\(added) new")
                               : String(localized: "Up to date")
            resultIsError = false
        } else {
            result = String(localized: "Couldn't reach Stripe — check your connection.")
            resultIsError = true
        }
        // Money arriving says nothing here — it lands in the feed, which is
        // where arrivals live (2026-08-19). Money being CHALLENGED still
        // answers on the screen you are standing on, because the bad kind of
        // news has to say what it is rather than waiting to be scrolled past. Only ever on a sync the person is
        // present for; the background pass stays silent and lets the feed row
        // and its deadline do the telling.
        if let alarm = StripeIngest.lastPassAlarm {
            chrome.flash(alarm, tone: .failure, seconds: 3.5)
        }
    }
}
