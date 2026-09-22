import SwiftUI
import SwiftData

/// NEAR AI, connected — by key (2026-09-20, prd §848). The seat that can prove
/// what answered you.
///
/// NEAR AI runs open-weight models inside sealed hardware. Each enclave
/// publishes a signing address and signs a line naming the model and the
/// SHA-256 of the exact request and response bytes; this phone recovers the
/// signer and compares it to the published address itself, with no server in
/// between (`NearAIVerify`). Nothing else in the catalogue can make that claim,
/// and the page is built around saying exactly what it does and does not mean.
///
/// Two facts on this page exist because they would otherwise be discovered
/// rather than told:
///
/// - **Answers arrive whole, not a word at a time.** A streamed body is
///   rewritten by the gateway on the way out, so the gateway signs it and its
///   line names no model; only a whole body carries the model enclave's own
///   signature. The seat buys the stronger proof with the streaming
///   (`NearAICloud.answer`).
/// - **Not every model on NEAR AI can be verified.** Its catalogue proxies
///   Claude, GPT and Gemini, which are not enclave-hosted and produce no
///   signature. The picker offers them because NEAR AI does, and the badge
///   simply never appears — it is earned per answer, never promised per seat.
///
/// `lands: true` for the same reason every keyed seat has it since §839: a
/// conversation in the composer lands as a chat thing that grows as you talk.
struct NearAISetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.nearai)

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "NEAR AI", seatID: "nearai", source: "NEAR AI",
            state: AccountPageState.of(name: "NEAR AI", seatID: "nearai",
                                       connected: configured, store: store),
            mode: .pasteKey,
            keyed: true,
            lands: true,
            teardown: {
                AgentKey.clear(.nearai)
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
            BridgeSetupCard(steps: [], numbered: false) {
                DSSlabButton(title: "Get your API key",
                             detail: "cloud.near.ai",
                             systemImage: "arrow.up.right",
                             url: URL(string: "https://cloud.near.ai"))
            }
            DSSlabField(placeholder: AgentProvider.nearai.placeholder, text: $keyDraft,
                        actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                        secure: true,
                        isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                        action: connect)
            BridgeSyncStatusRows(proof: result)
            // The one explaining sentence this page gets (prd §748). It is
            // kept because it names the trade the controls cannot: an answer
            // that arrives all at once looks like a slow seat unless you know
            // why, and "signed" is meaningless without "whole".
            DSSlabNote(text: "Answers arrive all at once, because that is what the hardware can sign. NEAR AI bills you directly.",
                       plain: true)
        }
    }

    /// Connects only after NEAR AI accepts the key.
    ///
    /// The check is the ATTESTATION read, not a models list — `cloud-api.near.ai/v1/models`
    /// answers 200 with no key at all, so a models read would accept anything
    /// (`AgentAnswer.check` carries the measurement). It is also the honest
    /// check for this seat specifically: a key that cannot fetch an attestation
    /// cannot verify an answer, and connecting on one would claim a capability
    /// the seat does not have.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.check(candidate, provider: .nearai)
            checking = false
            if outcome == .accepted {
                AgentKey.set(candidate, for: .nearai)
                configured = true
                keyDraft = ""
                DSHaptic.success()
                result = .connected(String(localized: "answers now offer \"Try with your key\" on NEAR AI."))
                store.registerConnected(id: "nearai", name: "NEAR AI",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Checks the hardware's signature on each answer, on this iPhone."])
            } else {
                result = .failed(outcome.line(for: .nearai))
            }
        }
    }

    @ViewBuilder private var agentRowsBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            AgentActiveStatusRow(provider: .nearai)
            AgentModelRow(provider: .nearai)
            AgentSpendRow(provider: .nearai)
            // The librarian's switch, moved off Settings with the key card
            // (prd §871). It draws only on the ACTIVE key's page, so it
            // cannot read as a per-seat setting.
            AgentLibrarianRow(provider: .nearai)
        }
    }
}
