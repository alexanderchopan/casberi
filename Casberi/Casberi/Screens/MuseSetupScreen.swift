import SwiftUI
import SwiftData

/// Muse, connected — by key (2026-09-20, prd §854). Meta's own model, through
/// the Meta Model API, on the same BYO-key contract every agent here keeps:
/// checked with the provider before it saves, stored in the Keychain via the
/// same vault, listed in Settings → Your key beside the rest.
///
/// Structurally this is `GrokSetupScreen` — a plain OpenAI-compatible seat
/// with a different name and console — and that is the whole reason it was
/// cheap to build: Meta serves `/v1/chat/completions` at `api.meta.ai/v1` with
/// a bearer token and the OpenAI request shape, so `AgentAnswer` reaches it
/// through the branch that already carried OpenAI, Venice, OpenRouter, xAI and
/// NEAR AI. No new transport, no new parser.
///
/// **WHAT IS MEASURED, AND WHAT IS NOT (prd §780b's rule — a seat may ship
/// ahead of its evidence only if it SAYS what it doesn't know).**
///
/// Measured from this machine on 2026-09-20, with no key:
/// - `api.meta.ai/v1/models` and `/v1/chat/completions` both answer **401**
///   with a real JSON error envelope (`invalid_api_key`,
///   `authentication_error`). The host and both paths resolve, and the models
///   read cannot be fooled by an empty string — which is what makes it this
///   seat's key check, where NEAR AI's keyless-200 list could not be.
///
/// Read off Meta's own documentation, never measured here:
/// - the base URL, the bearer scheme, the `LLM|` key prefix, and the model ids
///   (`muse-spark-1.3` and its family). All four are quoted in Meta's curl
///   example.
///
/// Neither measured nor documented, and therefore CLAIMED NOWHERE — not in the
/// capability line, not on this screen:
/// - whether this endpoint accepts a picture (Meta says Muse Spark is
///   multimodal; whether it takes the `image_url` content part this app builds
///   is a different question, and `AgentProvider.seesImages` stays false until
///   somebody measures it);
/// - the wire shape of Meta's web-search grounding;
/// - what an UNFUNDED key does. NEAR AI 402s after the check passes and Grok
///   answers 200 for a credit-less key — two shipped versions of the same trap
///   — and Meta's error taxonomy has not been seen from a real key. The note
///   below says the account needs to be set up rather than pretending the
///   check proves it is.
///
/// **ON `AccountPage` SINCE §639.** `lands: true` since §839 — a key that
/// answers lands its conversations as chat things, so this seat has a room, an
/// Activity count and a corpus a reader can be shut out of. Per §844 the page
/// carries no ask door: the room's Chat tile is the only entrance.
struct MuseSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.meta)

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Muse", seatID: "muse", source: "Muse",
            state: AccountPageState.of(name: "Muse", seatID: "muse",
                                       connected: configured, store: store),
            mode: .pasteKey,
            keyed: true,
            lands: true,
            teardown: {
                AgentKey.clear(.meta)
                configured = false
            },
            sheet: $sheet,
            act: {
                if configured {
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
            BridgeSetupCard(steps: [], numbered: false) {
                DSSlabButton(title: "Get your API key",
                             detail: "dev.meta.ai",
                             systemImage: "arrow.up.right",
                             url: URL(string: "https://dev.meta.ai/"))
            }
            DSSlabField(placeholder: AgentProvider.meta.placeholder, text: $keyDraft,
                        actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                        secure: true,
                        isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                        action: connect)
            BridgeSyncStatusRows(proof: result)
            // Two facts, both true and neither in the header's tagline: the
            // API is in public preview, and Meta bills per token. Nothing here
            // says the key check proves the account can pay — see this file's
            // doc comment for why that would be a guess.
            DSSlabNote(text: "Meta's Model API is in public preview, and bills this key per token.", plain: true)
        }
    }

    /// Connects only after Meta accepts the key — the seat registers with what
    /// it can actually do, nothing more.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.check(candidate, provider: .meta)
            checking = false
            if outcome == .accepted {
                AgentKey.set(candidate, for: .meta)
                configured = true
                keyDraft = ""
                DSHaptic.success()
                result = .connected(String(localized: "answers now offer \"Try with your key\" on Muse."))
                store.registerConnected(id: "muse", name: "Muse",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Remembers a chat's earlier answers."])
            } else {
                result = .failed(outcome.line(for: .meta))
            }
        }
    }

    /// Which agent answers, on which model, and what it has cost — the live
    /// facts about a key that is already working. They render nothing when
    /// this provider is not configured, which is why they can sit here
    /// unconditionally.
    @ViewBuilder private var agentRowsBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            AgentActiveStatusRow(provider: .meta)
            AgentModelRow(provider: .meta)
            AgentSpendRow(provider: .meta)
        }
    }
}
