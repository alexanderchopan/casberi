import SwiftUI
import SwiftData

/// OpenRouter, connected — by key (2026-07-24). One API key routes across
/// OpenRouter's 400+ models, so unlike every other agent here it never pins
/// one model — it rides OpenRouter's own `openrouter/auto` router. The key
/// is checked with OpenRouter before it saves (no dead key claiming a
/// capability — honesty rule), lands in the Keychain via the same vault
/// every agent key uses, and appears in Settings → Your key alongside the
/// rest.
struct OpenRouterSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var configured = AgentKey.isConfigured(.openrouter)
    @State private var flipTrigger = 0

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "OpenRouter",
                mode: .pasteKey,
                intro: "Paste a key and OpenRouter can answer questions about your things through whichever model you've picked there. It's asked only when you tap for it, never on its own.",
                flipTrigger: flipTrigger)
            setupSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // OpenRouter's mark is near-black, so `DS.washHue` returns nil and this
        // paints nothing — called anyway so the family has no exception to
        // remember, and a rebrand with a real hue lands for free.
        .bridgeSetupWash(name: "OpenRouter")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("OpenRouter")
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). Step one was "At openrouter.ai → Keys, sign in and open …", which is
    /// the button below rather than a sentence you retype.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: "Open openrouter.ai → Keys", systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://openrouter.ai/settings/keys") { openURL(url) }
                }
                // "Paste it below" sat directly above a field placeheld "Paste
                // your OpenRouter key" — §220's own finding, in the family it
                // was never applied to (2026-07-31). With one instruction left
                // the numerals go too, per §220's boundary.
                BridgeStepLines(steps: ["Create a key and copy it — it's checked with OpenRouter before it saves."],
                                numbered: false)
                DSSlabField(placeholder: AgentProvider.openrouter.placeholder, text: $keyDraft,
                            actionLabel: checking ? "CHECKING…" : (configured ? "UPDATE" : "CONNECT"),
                            secure: true,
                            isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                            action: connect)
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                AgentActiveStatusRow(provider: .openrouter)
                AgentModelRow(provider: .openrouter)
                AgentSpendRow(provider: .openrouter)
                // The opening sentence ("auto-picks whichever model fits") was
                // the header's own tagline — "One key, whichever model fits" —
                // a screen apart (2026-07-31). "there" lost its antecedent
                // with it, so it names OpenRouter now.
                DSSlabNote(text: "The key lives in the Keychain, goes only to OpenRouter, and OpenRouter bills you directly.")
            }
        }
        .dsSlabSection()
    }

    /// Connects only after OpenRouter accepts the key — the seat registers
    /// with what it can actually do, nothing more.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.check(candidate, provider: .openrouter)
            checking = false
            if outcome == .accepted {
                AgentKey.set(candidate, for: .openrouter)
                configured = true
                keyDraft = ""
                flipTrigger += 1
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with your key\" on OpenRouter.")
                store.registerConnected(id: "openrouter", name: "OpenRouter",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Routes to whichever model fits, and remembers a chat's earlier answers."])
            } else {
                // Four ways this can fail and four sentences for them (audit
                // 2026-07-31) — a rate limit, a blocked account and a dropped
                // connection are not the key, and one shared "check it and try
                // again" sent people hunting a key that was never wrong.
                resultIsError = true
                result = outcome.line(for: .openrouter)
            }
        }
    }
}
