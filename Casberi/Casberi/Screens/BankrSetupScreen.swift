import SwiftUI
import SwiftData

/// Bankr, connected — by key (2026-07-16, prd §82). Bankr is an agent with a
/// wallet, so unlike the other key seats its answers can weigh what you hold
/// and what the market is doing, not only what you saved — nothing reads IN,
/// the seat powers answers OUT. The key is checked with Bankr before it saves
/// (no dead key claiming a capability — honesty rule), lands in the Keychain
/// via the same vault every agent key uses, and appears in Settings → Your
/// key alongside the rest.
///
/// The read-only ask is the point of step 2: the same key that answers could
/// also trade. Every question Casberi sends is hard-prefixed "answer only",
/// and a read-only key makes that structural rather than a promise.
struct BankrSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var configured = AgentKey.isConfigured(.bankr)
    @State private var flipTrigger = 0

    var body: some View {
        List {
            BridgeSetupHeader(name: "Bankr", flipTrigger: flipTrigger)
            setupSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Bankr")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Bankr")
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). Step one was "At bankr.bot/api-keys, sign in and open …", which is
    /// the button below rather than a sentence you retype.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: "Open bankr.bot/api-keys", systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://bankr.bot/api-keys") { openURL(url) }
                }
                // Two duplicates in one line (2026-07-31). "Answers never
                // trade — a read-only key keeps it that way" is the note below
                // it ("nothing here trades, sends, or swaps"), which keeps the
                // promise because it's adjacent to the field and names the
                // stronger guarantee — every question is prefixed answer only,
                // whatever the key can do. "Paste it below" is the field's own
                // placeholder ("Paste your Bankr key"), §220's finding. One
                // instruction left, so the numerals go too.
                BridgeStepLines(steps: ["Make the key read-only, and enable agent access — it's checked with Bankr before it saves."],
                                numbered: false)
                DSSlabField(placeholder: AgentProvider.bankr.placeholder, text: $keyDraft,
                            actionLabel: checking ? "CHECKING…" : (configured ? "UPDATE" : "CONNECT"),
                            secure: true,
                            isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                            action: connect)
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                AgentActiveStatusRow(provider: .bankr)
                DSSlabNote(text: "Your key powers \"Try with your key\": any answer re-runs on Bankr — which can weigh your wallet and live markets, not just your things — only when you tap. Every question says answer only: nothing here trades, sends, or swaps.\n\nThe key lives in the Keychain, goes only to Bankr, and Bankr bills you directly.")
            }
        }
        .dsSlabSection()
    }

    /// Connects only after Bankr accepts the key — the seat registers with
    /// what it can actually do, nothing more. Validation spends nothing: a
    /// bogus job id 404s on a good key, 401s on a bad one.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.check(candidate, provider: .bankr)
            checking = false
            if outcome == .accepted {
                AgentKey.set(candidate, for: .bankr)
                configured = true
                keyDraft = ""
                flipTrigger += 1
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with your key\" on Bankr.")
                store.registerConnected(id: "bankr", name: "Bankr",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Reads your wallet and live markets to answer.",
                                              "Never trades, sends, or swaps."])
            } else {
                // Four ways this can fail and four sentences for them (audit
                // 2026-07-31) — a rate limit, a blocked account and a dropped
                // connection are not the key, and one shared "check it and try
                // again" sent people hunting a key that was never wrong.
                resultIsError = true
                result = outcome.line(for: .bankr)
            }
        }
    }
}
