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
/// the capability is named where it actually lives: the key's own scope
/// makes it a switch, off by default, and the conversation gives it a door
/// with a person standing in it.
struct BankrSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @Environment(ShellChrome.self) private var chrome
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var configured = AgentKey.isConfigured(.bankr)
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
                BridgeStepLines(steps: ["Sign in, then mint a key. Read-only lets Bankr answer; a full key lets it act."],
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
                // THE FAB IS THE ONLY CHAT (user, 2026-08-31: "the only place
                // to chat with any agent is in the fab"). This used to push a
                // SECOND conversation screen, which duplicated the composer's
                // whole surface — its own turn renderer, its own history, its
                // own field — so the two never knew what you had said in the
                // other. It raises the one composer now, exactly as the berry
                // does, and Bankr is a chip in it like every other key.
                DSSlabButton(title: "Talk to Bankr",
                             detail: "Ask about your wallets, or tell it what to do",
                             systemImage: "bubble.left.and.bubble.right") {
                    DSHaptic.tap()
                    chrome.composerRequest += 1
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
                // No permission to carry over any more (2026-08-31): what a
                // key may do travels with the key itself.
                keyDraft = ""
                flipTrigger += 1
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — \"Ask Bankr\" now appears when you type.")
                store.registerConnected(id: "bankr", name: "Bankr",
                                        proof: String(localized: "Key in the Keychain"),
                                        // What Bankr may do is the KEY's scope,
                                        // not a switch in here (2026-08-31) —
                                        // so this claims only what is true of
                                        // every key.
                                        can: ["Answers with your key — only when you tap.",
                                              "Reads your wallet and live markets to answer.",
                                              "What it may do is set by the key you minted."])
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
