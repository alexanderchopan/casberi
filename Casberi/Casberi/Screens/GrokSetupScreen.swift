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
///
/// **ON `AccountPage` SINCE §639 (2026-09-06).** The connected state was
/// `BridgeConnectedState`'s identity card with the form retired behind a
/// Connection door; both are the chassis's now — the header IS the identity,
/// and the form is the "Your key" sheet, reached from the row that says
/// where the key lives. `lands: false`: a key that answers stores nothing,
/// so there is no Activity count and nothing in the corpus to shut a reader
/// out of.
struct GrokSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.grok)

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Grok", seatID: "grok", source: "Grok",
            state: AccountPageState.of(name: "Grok", seatID: "grok",
                                       connected: configured, store: store),
            intro: "Answers about your things when the on-device model isn't enough — only when you tap for it.",
            mode: .pasteKey,
            keyed: true,
            // A KEY THAT ANSWERS LANDS NOTHING. There is no room, no count and
            // nothing in the corpus to shut a reader out of — so the Activity
            // row and "Who may read it" are absent rather than reading zero
            // about a seat that is working (see `AccountPage.lands`).
            lands: false,
            teardown: {
                AgentKey.clear(.grok)
                configured = false
            },
            sheet: $sheet,
            act: {
                if configured {
                    // The CONNECTION's live facts, not the form's — which
                    // agent answers, on which model, at what spend. The form
                    // itself is the "Your key" sheet now, which is where a key
                    // is replaced by exactly the path it was pasted.
                    agentRowsBlock
                } else {
                    setupBlock
                }
            },
            more: { EmptyView() },
            keySheet: { setupBlock }
        )
    }

    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Verb over address, the 2026-08-14 anatomy.
            // Unnumbered — the door did step one (ruling 2026-08-14).
            BridgeSetupCard(steps: ["Create an API key and copy it.",
                                 "Paste it below — checked before it saves"],
                            numbered: false) {
                DSSlabButton(title: "Get your API key",
                             detail: "console.x.ai",
                             systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://console.x.ai/") { openURL(url) }
                }
            }
            DSSlabField(placeholder: AgentProvider.grok.placeholder, text: $keyDraft,
                        actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                        secure: true,
                        isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                        action: connect)
            BridgeSyncStatusRows(proof: result)
            // The opening clause was the header's own tagline — "Try with
            // your key, on Grok" — restated a screen below it
            // (2026-07-31). The consent clause it carried stays.
            DSSlabNote(text: "xAI has no free tier — buy credits before a key can answer.", plain: true)
        }
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
                DSHaptic.success()
                result = .connected(String(localized: "answers now offer \"Try with your key\" on Grok."))
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
                result = .failed(outcome.line(for: .grok))
            }
        }
    }

    /// Which agent answers, on which model, and what it has cost — the live
    /// facts about a key that is already working. They render nothing when
    /// this provider is not configured, which is why they can sit here
    /// unconditionally.
    @ViewBuilder private var agentRowsBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            AgentActiveStatusRow(provider: .grok)
            AgentModelRow(provider: .grok)
            AgentSpendRow(provider: .grok)
        }
    }


}
