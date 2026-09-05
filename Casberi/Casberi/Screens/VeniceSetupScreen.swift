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
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.venice)
    @State private var showConnection = false

    var body: some View {
        BridgeSetupPage(name: "Venice") {
            if configured {
                // Connected (prd §186): the form retires behind one door and the
                // live facts about this key take the screen. A BYOK key stores no
                // account name of its own — only the secret, in the Keychain — so
                // this leads with the provider's own name over a truthful note
                // about HOW it is connected, never a display name we would guess.
                BridgeConnectedState(
                    bridgeID: "venice",
                    name: "Venice",
                    connectionNote: String(localized: "Your key · stored in \(DS.device)'s Keychain"),
                    capabilitiesFallback: ["Answers with your key — only when you tap.",
                                       "Remembers a chat's earlier answers, and can search the web."],
                    openConnection: { showConnection = true })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                // These three are the CONNECTION's live facts, not the form's —
                // which agent answers, on which model, at what spend — so they sit
                // in the connected state rather than travelling into the sheet.
                agentRows
            } else {
                BridgeSetupHeader(
                    name: "Venice",
                    mode: .pasteKey,
                    intro: "Paste a key and Venice can answer questions about your things when the free on-device model isn't enough. It's asked only when you tap for it, never on its own.")
                setupSection
            }
        }
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "Venice") {
                setupSection
                removeSection
            }
        }
    }

    /// The connect form — steps whole, furniture gone (prd §218,
    /// 2026-07-25). Step one was "At venice.ai → API keys, sign in and open …", which is
    /// the button below rather than a sentence you retype.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // Verb over address, the 2026-08-14 anatomy.
                DSSlabButton(title: "Get your API key",
                             detail: "venice.ai",
                             systemImage: "arrow.up.right") {
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
                            actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                            secure: true,
                            isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                            action: connect)
                BridgeSyncStatusRows(proof: result)
                DSSlabNote(text: "The key lives in the Keychain, goes only to Venice, and Venice bills you directly.")
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
    @ViewBuilder private var agentRows: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                AgentActiveStatusRow(provider: .venice)
                AgentModelRow(provider: .venice)
                AgentSpendRow(provider: .venice)
            }
        }
        .dsSlabSection()
    }

    /// The key's way out — the shared row, so this screen says "Disconnect"
    /// the way every other setup screen does (prd §608). It lands no `Thing`,
    /// so no purge is offered.
    private var removeSection: some View {
        BridgeDisconnectSection(bridgeID: "venice", name: "Venice") {
            AgentKey.clear(.venice)
            configured = false
        }
    }

}
