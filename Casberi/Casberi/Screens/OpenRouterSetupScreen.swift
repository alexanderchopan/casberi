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
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.openrouter)
    @State private var showConnection = false

    var body: some View {
        // OpenRouter's mark is near-black, so `DS.washHue` returns nil and this
        // paints nothing — called anyway so the family has no exception to
        // remember, and a rebrand with a real hue lands for free.
        BridgeSetupPage(name: "OpenRouter") {
            if configured {
                // Connected (prd §186): the form retires behind one door and
                // the live facts about this key take the screen. A BYOK key
                // stores no account name of its own — only the secret, in the
                // Keychain — so this leads with the provider's own name over a
                // truthful note about HOW it is connected.
                BridgeConnectedState(
                    bridgeID: "openrouter",
                    name: "OpenRouter",
                    connectionNote: String(localized: "Your key · stored in \(DS.device)'s Keychain"),
                    capabilitiesFallback: ["Answers with your key — only when you tap.",
                                       "Routes to whichever model fits, and remembers a chat's earlier answers."],
                    openConnection: { showConnection = true })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                // The CONNECTION's live facts, not the form's — which agent
                // answers, on which model, at what spend.
                agentRows
            } else {
                BridgeSetupHeader(
                    name: "OpenRouter",
                    mode: .pasteKey,
                    intro: "Paste a key and OpenRouter can answer questions about your things through whichever model you've picked there. It's asked only when you tap for it, never on its own.")
                setupSection
            }
        }

        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "OpenRouter") {
                setupSection
                removeSection
            }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). Step one was "At openrouter.ai → Keys, sign in and open …", which is
    /// the button below rather than a sentence you retype.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // Verb over address, the 2026-08-14 anatomy.
                DSSlabButton(title: "Get your API key",
                             detail: "openrouter.ai",
                             systemImage: "arrow.up.right") {
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
                            actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                            secure: true,
                            isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                            action: connect)
                BridgeSyncStatusRows(proof: result)
                // The opening sentence ("auto-picks whichever model fits") was
                // the header's own tagline — "One key, whichever model fits" —
                // a screen apart (2026-07-31). "there" lost its antecedent
                // with it, so it names OpenRouter now.
                DSSlabNote(text: "The key lives in the Keychain, goes only to OpenRouter, which bills you directly.")
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
                DSHaptic.success()
                result = .connected(String(localized: "answers now offer \"Try with your key\" on OpenRouter."))
                store.registerConnected(id: "openrouter", name: "OpenRouter",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Routes to whichever model fits, and remembers a chat's earlier answers.",
                                              // The promise the toggle below
                                              // keeps, stated where somebody
                                              // reads what this seat does
                                              // rather than only where they
                                              // could change it (2026-08-23).
                                              "Only ever to a provider that agrees not to keep your question."])
            } else {
                // Four ways this can fail and four sentences for them (audit
                // 2026-07-31) — a rate limit, a blocked account and a dropped
                // connection are not the key, and one shared "check it and try
                // again" sent people hunting a key that was never wrong.
                result = .failed(outcome.line(for: .openrouter))
            }
        }
    }

    /// Which agent answers, on which model, and what it has cost — the live
    /// facts about a key that is already working. Each renders nothing when
    /// this provider is not configured.
    @ViewBuilder private var agentRows: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                AgentActiveStatusRow(provider: .openrouter)
                AgentModelRow(provider: .openrouter)
                // The two knobs only a router has (2026-08-23, prd §459). They
                // sit under the model picker because both are about the request
                // that model will serve, and above the receipt because one of
                // them is what the receipt will end up costing.
                OpenRouterRoutingRow(provider: .openrouter)
                AgentSpendRow(provider: .openrouter)
            }
        }
        .dsSlabSection()
    }

    /// The key's way out — the shared row, so this screen says "Disconnect"
    /// the way every other setup screen does (prd §608). It lands no `Thing`,
    /// so no purge is offered.
    private var removeSection: some View {
        BridgeDisconnectSection(bridgeID: "openrouter", name: "OpenRouter") {
            AgentKey.clear(.openrouter)
            configured = false
        }
    }

}
