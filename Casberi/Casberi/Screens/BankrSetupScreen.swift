import SwiftUI
import SwiftData

/// Bankr, connected — by key (2026-07-16, prd §82; the in-app sign-up joined
/// 2026-08-29, prd §529). Bankr is an agent with a wallet,
/// so unlike the other key seats its answers can weigh what you hold and what
/// the market is doing, not only what you saved. The key is checked with Bankr
/// before it saves (no dead key claiming a capability — honesty rule), lands
/// in the Keychain via the same vault every agent key uses, and appears in
/// Settings → Your key alongside the rest.
///
/// ## SIGN IN, AND THE KEY IS MADE FOR YOU (prd §800, reverses §529's "only
/// Bankr can remove that last step")
///
/// This seat's setup was an errand: make an account, find the key page, tick
/// read-only, copy the key, come back, paste. Measured on a real account
/// (§777's capture), bankr.bot's own key page makes a key with one call that
/// rides the sign-in cookie — so Connect opens `BankrSignInSheet`, the person
/// signs in on Bankr's own page (email, X, Farcaster, Telegram — Bankr's
/// choice of doors, not ours), and the sheet asks for the key from that page.
/// The key is checked with Bankr, stored, and the sheet closes. Pasting stays
/// in the "Your key" sheet for a key somebody already has.
///
/// ## READ-ONLY IS THE REQUEST, NOT A CHECKBOX
///
/// The same key that answers can also trade — that has always been true. A
/// key this app makes is asked for read-only with only the Agent API on, and
/// one that comes back wider is not stored (`BankrKeyMint.Outcome.tooWide`).
/// Every prompt is still prefixed "answer only — never execute"
/// (`BankrAgent.prompt`), which is what bounds a PASTED key.
///
/// **ON `AccountPage` SINCE §639 (2026-09-06).** The connected state was
/// `BridgeConnectedState`'s identity card with the form retired behind a
/// Connection door; both are the chassis's now — the header IS the identity,
/// and the form is the "Your key" sheet, reached from the row that says
/// where the key lives. `lands: false`: a key that answers stores nothing,
/// so there is no Activity count and nothing in the corpus to shut a reader
/// out of.
struct BankrSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @Environment(ShellChrome.self) private var chrome
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.bankr)

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Bankr", seatID: "bankr", source: "Bankr",
            state: AccountPageState.of(name: "Bankr", seatID: "bankr",
                                       connected: configured, store: store),
            mode: .signIn,
            keyed: true,
            // A KEY THAT ANSWERS NOW LANDS ITS CONVERSATIONS (prd §839) — one
            // chat thing per composer session — so this seat has a room, an
            // Activity count and a corpus a reader can be shut out of, and
            // `lands: false` would now hide all three (`AccountPage.lands`).
            lands: true,
            cardSheet: { _ in
                AnyView(BankrSignInSheet { key, fresh in
                    Task { await accept(key, newAccount: fresh) }
                })
            },
            teardown: {
                AgentKey.clear(.bankr)
                configured = false
            },
            sheet: $sheet,
            act: {
                if configured {
                    // The CONNECTION's live facts, not the form's — which
                    // agent answers, on which model, at what spend. The form
                    // itself is the "Your key" sheet now.
                    agentRowsBlock
                } else {
                    connectBlock
                }
            },
            more: {
                if configured { conversationBlock }
            },
            keySheet: { keyBlock }
        )
    }

    /// Connect: one verb that ends connected (prd §800).
    @ViewBuilder private var connectBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // THE CEILING, above the door (prd §641's honesty sweep). Bankr
            // holds a wallet of ITS OWN — that is the whole point of the seat
            // — and the screen's own "Ask about your wallets" invites the
            // opposite reading. Unnumbered: facts, not steps (§220).
            BridgeStepLines(steps: [
                String(localized: "Bankr answers from its own wallet, not yours."),
                String(localized: "It can't see the wallets you watch here."),
            ], numbered: false)
            DSSlabButton(title: "Connect",
                         detail: String(localized: "Sign in to Bankr"),
                         systemImage: "person.crop.circle",
                         busy: checking) { sheet = .card(id: "bankrSignIn") }
            BridgeSyncStatusRows(syncing: checking,
                                 syncingLine: String(localized: "Checking the key…"),
                                 proof: result)
            DSSlabNote(text: "Casberi makes a read-only key for you. Every prompt says answer only, never execute.", plain: true)
        }
    }

    /// The "Your key" sheet: a key somebody already has, pasted.
    @ViewBuilder private var keyBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: AgentProvider.bankr.placeholder, text: $keyDraft,
                        actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                        secure: true,
                        isArmed: !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                        paste: { keyDraft = $0 },
                        action: connect)
            BridgeSyncStatusRows(proof: result)
        }
    }

    /// The conversation. Only once a key exists: a door onto an agent nobody
    /// has a credential for is the dead control §83 bans.
    @ViewBuilder private var conversationBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // THE FAB IS THE ONLY CHAT (user, 2026-08-31: "the only place
            // to chat with any agent is in the fab"). This used to push a
            // SECOND conversation screen, which duplicated the composer's
            // whole surface — its own turn renderer, its own history, its
            // own field — so the two never knew what you had said in the
            // other. It raises the one composer now, exactly as the berry
            // does, and Bankr is a chip in it like every other key.
            DSSlabButton(title: "Ask Bankr",
                         detail: "Ask about your wallets and live markets",
                         systemImage: "bubble.left.and.bubble.right") {
                DSHaptic.tap()
                chrome.composerRequest += 1
            }
        }
    }

    /// A pasted key.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        Task { @MainActor in
            if await accept(candidate, newAccount: false) { keyDraft = "" }
        }
    }

    /// Connects only after Bankr accepts the key — made or pasted, the seat
    /// registers with what it can actually do, nothing more. Validation spends
    /// nothing: a bogus job id 404s on a good key, 401s on a bad one.
    @MainActor @discardableResult
    private func accept(_ candidate: String, newAccount: Bool) async -> Bool {
        checking = true
        result = nil
        let outcome = await AgentAnswer.check(candidate, provider: .bankr)
        checking = false
        guard outcome == .accepted else {
            // Four ways this can fail and four sentences for them (audit
            // 2026-07-31) — a rate limit, a blocked account and a dropped
            // connection are not the key, and one shared "check it and try
            // again" sent people hunting a key that was never wrong.
            result = .failed(outcome.line(for: .bankr))
            return false
        }
        AgentKey.set(candidate, for: .bankr)
        configured = true
        DSHaptic.success()
        // A sign-in that MADE the account says so (prd §800): Privy's "log in
        // or sign up" makes a new account for a method the person never used
        // before, and a second, empty Bankr account is not something to find
        // out about later.
        result = .connected(newAccount
            ? String(localized: "Connected to a new Bankr account.")
            : String(localized: "\"Ask Bankr\" now appears when you type."))
        store.registerConnected(id: "bankr", name: "Bankr",
                                proof: String(localized: "Key in the Keychain"),
                                // Three reads and no writes, which is
                                // the whole of what this seat does
                                // (2026-09-03).
                                can: ["Answers with your key — only when you tap.",
                                      "Reads live markets to answer.",
                                      "Only ever asked: answer only — never execute."])
        return true
    }

    /// Which agent answers, on which model, and what it has cost — the live
    /// facts about a key that is already working. Each renders nothing when
    /// this provider is not configured.
    @ViewBuilder private var agentRowsBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            AgentActiveStatusRow(provider: .bankr)
            AgentModelRow(provider: .bankr)
            AgentSpendRow(provider: .bankr)
        }
    }


}
