import SwiftUI
import SwiftData

/// Grok, connected — by key (2026-07-31, prd §242). Same BYO-key contract
/// every agent here keeps: checked with the provider before it saves, lands
/// in the Keychain via the same vault, appears in Settings → Your key
/// alongside the rest.
///
/// The reason to eventually WANT this seat is bigger than "a seventh
/// model" — it would be the only agent that could see X, which none of this
/// app's own bridges can reach at all (X's API is closed, no keyless read
/// exists). That's still a PLAN, not a shipped verb: three documentation
/// fetches on 2026-07-31 each described a different current shape for
/// xAI's search/citations (an older `search_parameters` body, a newer
/// `web_search` tool with no confirmed X-specific mode, and doubt over
/// whether tool-use even reaches the `/v1/chat/completions` endpoint this
/// app calls, as opposed to a separate Responses API). Rather than write
/// request code against three disagreeing sources, this screen makes NO
/// claim about X — every string below is checked against what actually
/// ships today, the same bar `WalletBalanceHeadline`'s "no claim about the
/// crown" rule holds elsewhere. Structurally this is `OpenRouterSetupScreen`
/// with a different name and console; a real X verb, once the wire shape is
/// confirmed, is the natural next goal here.
struct GrokSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var configured = AgentKey.isConfigured(.grok)
    @State private var flipTrigger = 0

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Grok",
                mode: .pasteKey,
                intro: "Paste a key and Grok can answer questions about your corpus when the free on-device model isn't enough. It's asked only when you tap for it, never on its own.",
                flipTrigger: flipTrigger)
            setupSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Grok's mark is pure black, so `DS.washHue` returns nil and this
        // paints nothing — called anyway so the family has no exception to
        // remember, and a rebrand with a real hue lands for free.
        .bridgeSetupWash(name: "Grok")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Grok")
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: "Open console.x.ai", systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://console.x.ai/") { openURL(url) }
                }
                BridgeStepLines(steps: ["Create an API key and copy it.",
                                     "Paste it below — it's checked with xAI before it saves."])
                DSSlabField(placeholder: AgentProvider.grok.placeholder, text: $keyDraft,
                            actionLabel: checking ? "CHECKING…" : (configured ? "UPDATE" : "CONNECT"),
                            secure: true,
                            isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                            action: connect)
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                AgentActiveStatusRow(provider: .grok)
                AgentModelRow(provider: .grok)
                AgentSpendRow(provider: .grok)
                // The opening clause was the header's own tagline — "Try with
                // your key, on Grok" — restated a screen below it
                // (2026-07-31). The consent clause it carried stays.
                DSSlabNote(text: "xAI has no free tier, so your team needs credits before a key can answer — buy them in the same console.")
            }
        }
        .dsSlabSection()
    }

    /// Connects only after xAI accepts the key — the seat registers with
    /// what it can actually do, nothing more.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.check(candidate, provider: .grok)
            checking = false
            if outcome == .accepted {
                AgentKey.set(candidate, for: .grok)
                configured = true
                keyDraft = ""
                flipTrigger += 1
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with your key\" on Grok.")
                store.registerConnected(id: "grok", name: "Grok",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Remembers a chat's earlier answers."])
            } else {
                // The two real causes were named in ONE sentence until the
                // 2026-07-31 audit, because the check could only say yes or
                // no. `AgentKeyCheck` separates them: a wrong key gets
                // "check you copied the whole thing", and the credits case —
                // the measured 200-with-`team_blocked` xAI answers for a real
                // key that can't answer — gets its own `.blocked` sentence
                // pointing at the console. Nobody reads a fix meant for
                // someone else's problem anymore.
                resultIsError = true
                result = outcome.line(for: .grok)
            }
        }
    }
}
