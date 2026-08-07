import SwiftUI
import SwiftData

/// Venice, connected — by key (2026-07-14). Venice keeps chats on your own
/// device by design, so there is nothing to read IN; its seat powers answers
/// OUT: a Venice key makes "Try with your key" run on Venice's private API,
/// straight from this iPhone, only on the tap. The key is checked with
/// Venice before it saves (no dead key claiming a capability — honesty
/// rule), lands in the Keychain via the same vault every agent key uses,
/// and appears in Settings → Your key alongside the rest.
struct VeniceSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var configured = AgentKey.isConfigured(.venice)
    @State private var flipTrigger = 0

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Venice",
                mode: .pasteKey,
                intro: "Paste a key and Venice can answer questions about your things when the free on-device model isn't enough. It's asked only when you tap for it, never on its own.",
                flipTrigger: flipTrigger)
            setupSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Venice")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Venice")
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). Step one was "At venice.ai → API keys, sign in and open …", which is
    /// the button below rather than a sentence you retype.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabButton(title: "Open venice.ai → API keys", systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    if let url = URL(string: "https://venice.ai/settings/api") { openURL(url) }
                }
                // "Paste it below" sat directly above a field placeheld "Paste
                // your Venice key" — §220's own finding, in the family it was
                // never applied to (2026-07-31). With one instruction left the
                // numerals go too, per §220's boundary.
                BridgeStepLines(steps: ["Create a key and copy it — it's checked with Venice before it saves."],
                                numbered: false)
                DSSlabField(placeholder: AgentProvider.venice.placeholder, text: $keyDraft,
                            actionLabel: checking ? "CHECKING…" : (configured ? "UPDATE" : "CONNECT"),
                            secure: true,
                            isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                            action: connect)
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                AgentActiveStatusRow(provider: .venice)
                AgentModelRow(provider: .venice)
                AgentSpendRow(provider: .venice)
                DSSlabNote(text: "Venice keeps chats on your device by design. The key lives in the Keychain, goes only to Venice, and Venice bills you directly.")
            }
        }
        .dsSlabSection()
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
                flipTrigger += 1
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with your key\" on Venice.")
                store.registerConnected(id: "venice", name: "Venice",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Remembers a chat's earlier answers, and can search the web."])
            } else {
                // Four ways this can fail and four sentences for them (audit
                // 2026-07-31) — a rate limit, a blocked account and a dropped
                // connection are not the key, and one shared "check it and try
                // again" sent people hunting a key that was never wrong.
                resultIsError = true
                result = outcome.line(for: .venice)
            }
        }
    }
}
