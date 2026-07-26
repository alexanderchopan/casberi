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

    var body: some View {
        List {
            BridgeSetupHeader(name: "OpenRouter")
            setupSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
                    if let url = AgentProvider.openrouter.consoleURL { openURL(url) }
                }
                BridgeStepLines(steps: ["Create a key and copy it.",
                                     "Paste it below — it's checked with OpenRouter before it saves."])
                DSSlabField(placeholder: AgentProvider.openrouter.placeholder, text: $keyDraft,
                            actionLabel: checking ? "CHECKING…" : (configured ? "UPDATE" : "CONNECT"),
                            secure: true,
                            isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                            action: connect)
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                DSSlabNote(text: "OpenRouter auto-picks whichever of its 400+ models fits your question. Your key powers \"Try with your key\": any answer re-runs there, straight from this iPhone, only when you tap.\n\nThe key lives in the Keychain, goes only to OpenRouter, and OpenRouter bills you directly.")
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
            let ok = await AgentAnswer.validate(candidate, provider: .openrouter)
            checking = false
            if ok {
                AgentKey.set(candidate, for: .openrouter)
                configured = true
                keyDraft = ""
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with your key\" on OpenRouter.")
                store.registerConnected(id: "openrouter", name: "OpenRouter",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Routes to whichever model fits, and remembers a chat's earlier answers."])
            } else {
                resultIsError = true
                result = String(localized: "OpenRouter didn't accept that key — check it and try again.")
            }
        }
    }
}
