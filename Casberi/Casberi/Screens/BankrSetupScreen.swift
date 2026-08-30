import SwiftUI
import SwiftData

/// Bankr, connected — by key (2026-07-16, prd §82; the sign-up and the acting
/// permission joined 2026-08-29, prd §529). Bankr is an agent with a wallet,
/// so unlike the other key seats its answers can weigh what you hold and what
/// the market is doing, not only what you saved. The key is checked with Bankr
/// before it saves (no dead key claiming a capability — honesty rule), lands
/// in the Keychain via the same vault every agent key uses, and appears in
/// Settings → Your key alongside the rest.
///
/// ## THE WHOLE SETUP HAPPENS HERE NOW
///
/// This seat's setup is not a paste, it is an errand: make an account, mint a
/// key, come back. Every step of that used to happen in Safari, with Casberi
/// in the background — which is most of a new person's first experience of the
/// feature, spent outside the app.
///
/// Both doors open `DSWebSheet` instead. **Passkeys are what make that work**:
/// `SFSafariViewController` runs the system's own passkey UI against the same
/// iCloud Keychain Safari uses, so signing up with Face ID inside this sheet is
/// what happens in Safari. Casberi reads nothing — not a keystroke, not a
/// cookie, not the page. The key still comes back by paste, and only Bankr can
/// remove that last step (see prd §529: a "Connect with Bankr" button is
/// theirs to build, not ours to fake).
///
/// ## THE READ-ONLY ASK BECAME A CHOICE
///
/// The same key that answers can also trade — that has always been true, and
/// until now the answer was to ask for a read-only key and prefix every prompt
/// "answer only". Both still hold for the ANSWER path. What changed is that
/// the capability is no longer left latent behind a sentence: `BankrAgent.canAct`
/// makes it a switch, off by default, and the conversation gives it a door
/// with a person standing in it.
struct BankrSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var configured = AgentKey.isConfigured(.bankr)
    @State private var canAct = BankrAgent.canAct
    @State private var web: URL?
    @State private var flipTrigger = 0

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Bankr",
                mode: .pasteKey,
                intro: "Make a key in a page that opens here, and Bankr can answer about your wallets and live markets when you tap for it. It can also act on instructions you confirm, if you turn that on.",
                flipTrigger: flipTrigger)
            setupSection
            if configured { conversationSection }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Bankr")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Bankr")
        .dsWebSheet($web)
    }

    /// The connect form — steps whole, furniture gone (prd §218).
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // Verb over address, the 2026-08-14 anatomy. Two doors, and
                // the ORDER is the point: somebody who has never heard of
                // Bankr needs the account first, and the old screen offered
                // only the key page, which is a dead end without one.
                DSSlabButton(title: configured ? "Open Bankr" : "Create an account or sign in",
                             detail: "bankr.bot",
                             systemImage: "person.crop.circle") {
                    DSHaptic.tap()
                    web = URL(string: "https://bankr.bot")
                }
                DSSlabButton(title: "Get your API key",
                             detail: "bankr.bot/api-keys",
                             systemImage: "key") {
                    DSHaptic.tap()
                    web = URL(string: "https://bankr.bot/api-keys")
                }
                BridgeStepLines(steps: ["Sign in with a passkey, then make a key with agent access."],
                                numbered: false)
                DSSlabField(placeholder: AgentProvider.bankr.placeholder, text: $keyDraft,
                            actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                            secure: true,
                            isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                            action: connect)
                // The last step of the errand, made one tap. `PasteButton`
                // reads the clipboard through the system rather than through
                // us, so it raises no paste banner and Casberi never sees a
                // clipboard it wasn't handed.
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !pasted.isEmpty else { return }
                    Task { @MainActor in keyDraft = pasted }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
                AgentActiveStatusRow(provider: .bankr)
                AgentModelRow(provider: .bankr)
                AgentSpendRow(provider: .bankr)
                DSSlabNote(text: "Answers re-run on Bankr — wallet and live markets included — only when you tap.")
            }
        }
        .dsSlabSection()
    }

    /// The conversation, and the permission that changes what it can do. Only
    /// once a key exists: a switch governing a credential nobody has pasted is
    /// the dead control §83 bans.
    private var conversationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSSlabButton(title: "Talk to Bankr",
                             detail: canAct ? "Ask, or tell it what to do" : "Ask about your wallets",
                             systemImage: "bubble.left.and.bubble.right") {
                    DSHaptic.tap()
                    route.path.append(.bankrChat)
                }
                Toggle(isOn: $canAct) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let Bankr act on what you tell it")
                            .dsText(.callout15).foregroundStyle(DS.textPrimary)
                        // The cost is stated on the control that causes it,
                        // never in fine print elsewhere (the OpenRouter
                        // private-routing anatomy) — and this is the only
                        // switch in the app that can spend money.
                        Text("Off, every question is prefixed answer only. On, a second button appears in the conversation and each instruction asks you first. Bankr decides what it does — Casberi can't check it beforehand or undo it. A read-only key can't act whatever this says.")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .onChange(of: canAct) { _, on in
                    BankrAgent.canAct = on
                    // Turning it on is a permission, so it gets the weightier
                    // feedback of the two.
                    if on { DSHaptic.success() } else { DSHaptic.tap() }
                }
            }
        }
        .dsSlabSection()
    }

    /// Connects only after Bankr accepts the key — the seat registers with
    /// what it can actually do, nothing more. Validation spends nothing: a
    /// bogus job id 404s on a good key, 401s on a bad one.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.check(candidate, provider: .bankr)
            checking = false
            if outcome == .accepted {
                AgentKey.set(candidate, for: .bankr)
                configured = true
                // A new key arrives with no permission (2026-08-29). `clear`
                // forgets `canAct`, but an UPDATE never clears — so without
                // this a key pasted today inherits a permission granted for a
                // credential that is gone.
                canAct = BankrAgent.canAct
                keyDraft = ""
                flipTrigger += 1
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with your key\" on Bankr.")
                store.registerConnected(id: "bankr", name: "Bankr",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Reads your wallet and live markets to answer.",
                                              canAct
                                                ? "Acts on instructions you confirm, one at a time."
                                                : "Never trades, sends, or swaps."])
            } else {
                // Four ways this can fail and four sentences for them (audit
                // 2026-07-31) — a rate limit, a blocked account and a dropped
                // connection are not the key, and one shared "check it and try
                // again" sent people hunting a key that was never wrong.
                resultIsError = true
                result = outcome.line(for: .bankr)
            }
        }
    }
}
