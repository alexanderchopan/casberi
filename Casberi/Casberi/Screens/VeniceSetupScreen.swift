import SwiftUI
import SwiftData

/// Venice, connected — by key (2026-07-14). Venice keeps chats on your own
/// device by design, so there is nothing to read IN; its seat powers answers
/// OUT: a Venice key makes "Try with your key" run on Venice's private API,
/// straight from this iPhone, only on the tap. The key is checked with
/// Venice before it saves (no dead key claiming a capability — honesty
/// rule), lands in the Keychain via the same vault every agent key uses,
/// and appears in Settings → Your key alongside the rest.
///
/// **ON `AccountPage` SINCE §639 (2026-09-06).** The connected state was
/// `BridgeConnectedState`'s identity card with the form retired behind a
/// Connection door; both are the chassis's now — the header IS the identity,
/// and the form is the "Your key" sheet, reached from the row that says
/// where the key lives. `lands: false`: a key that answers stores nothing,
/// so there is no Activity count and nothing in the corpus to shut a reader
/// out of.
struct VeniceSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.venice)

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Venice", seatID: "venice", source: "Venice",
            state: AccountPageState.of(name: "Venice", seatID: "venice",
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
                AgentKey.clear(.venice)
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

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). Step one was "At venice.ai → API keys, sign in and open …", which is
    /// the button below rather than a sentence you retype.
    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Verb over address, the 2026-08-14 anatomy.
            // "Paste it below" sat directly above a field placeheld "Paste
            // your Venice key" — §220's own finding, in the family it was
            // never applied to (2026-07-31). With one instruction left the
            // numerals go too, per §220's boundary.
            BridgeSetupCard(steps: ["Create a key — checked before it saves"],
                            numbered: false) {
                DSSlabButton(title: "Get your API key",
                             detail: "venice.ai",
                             systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://venice.ai/settings/api") { openURL(url) }
                }
            }
            DSSlabField(placeholder: AgentProvider.venice.placeholder, text: $keyDraft,
                        actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                        secure: true,
                        isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                        action: connect)
            BridgeSyncStatusRows(proof: result)
            DSSlabNote(text: "The key lives in the Keychain, goes only to Venice, and Venice bills you directly.", plain: true)
        }
    }

    /// Connects only after Venice accepts the key — the seat registers with
    /// what it can actually do, nothing more.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.check(candidate, provider: .venice)
            checking = false
            if outcome == .accepted {
                AgentKey.set(candidate, for: .venice)
                configured = true
                keyDraft = ""
                DSHaptic.success()
                result = .connected(String(localized: "answers now offer \"Try with your key\" on Venice."))
                store.registerConnected(id: "venice", name: "Venice",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Remembers a chat's earlier answers, and can search the web."])
            } else {
                // Four ways this can fail and four sentences for them (audit
                // 2026-07-31) — a rate limit, a blocked account and a dropped
                // connection are not the key, and one shared "check it and try
                // again" sent people hunting a key that was never wrong.
                result = .failed(outcome.line(for: .venice))
            }
        }
    }

    /// Which agent answers, on which model, and what it has cost — the live
    /// facts about a key that is already working. They render nothing when
    /// this provider is not configured, which is why they can sit here
    /// unconditionally.
    @ViewBuilder private var agentRowsBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            AgentActiveStatusRow(provider: .venice)
            AgentModelRow(provider: .venice)
            AgentSpendRow(provider: .venice)
        }
    }


}
