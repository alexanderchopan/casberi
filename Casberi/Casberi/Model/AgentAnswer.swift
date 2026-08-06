import Foundation

/// BYO-key (prd §67, providers 2026-07-14) — the person's own agent key
/// powers a "try with your key" they tap per answer. It is a VERB, never a
/// fallback: nothing leaves this iPhone until the tap, and what leaves goes
/// straight from the device to the provider they chose — Casberi runs no
/// server and never sees a byte. Keys live in the Keychain (TokenVault),
/// like every bridge token.
///
/// The key is an AGENT key, never "the Anthropic key" (user ruling
/// 2026-07-14): seven providers speak here — Claude, ChatGPT, Gemini,
/// Venice, Bankr, OpenRouter, and Grok — one request shape each, one
/// contract for all. Bankr (2026-07-16) is the one agent that isn't a bare
/// model: it's a wallet-attached trading agent, so its answers may ALSO draw
/// on the wallet and live markets (the sanctioned grounding divergence), and
/// every prompt it gets is hard-prefixed "answer only — never execute"
/// (the answer verb stays a read; writes would be separate consented
/// verbs, unbuilt). OpenRouter (2026-07-24) is the multi-model divergence:
/// it never pins one model, riding its own `openrouter/auto` router
/// instead, so it stays honestly text-only/no-search rather than claiming
/// a capability whichever model it lands on might not have.
///
/// Grok (2026-07-31, prd §242) rides the same OpenAI-compatible request
/// shape as OpenAI/Venice/OpenRouter — xAI's API speaks it natively — so it
/// joins that branch rather than growing a fourth one.
///
/// The reason it's here isn't "a seventh model" — it's the only provider
/// that could ever see X, which none of this app's own bridges can reach at
/// all (X's API is closed, no keyless read exists). That's still a PLAN, not
/// a shipped feature: three separate documentation fetches on 2026-07-31
/// each described a DIFFERENT current shape for xAI's search/citations
/// (an older `search_parameters` body, a newer `web_search` tool with no
/// confirmed X-specific mode, and uncertainty over whether tool-use even
/// applies to the `/v1/chat/completions` endpoint this file calls, as
/// opposed to a separate Responses API). Writing request code against three
/// disagreeing sources isn't the same risk as this codebase's usual
/// "UNMEASURED, re-measure before hardening" pattern (PostHog/1Claw/Privacy
/// all had ONE stable spec to transcribe) — so it's deliberately UNBUILT
/// until either a real Grok key can confirm the live shape, or the user
/// accepts shipping a best-guess version anyway. No user-facing copy here
/// or on `GrokSetupScreen`/the catalog offer claims this works.
enum AgentProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai
    case google
    case venice
    case bankr
    case openrouter
    case grok

    var id: String { rawValue }

    /// The agent the person knows ("Claude"), not the vendor.
    var agent: String {
        switch self {
        case .anthropic:  "Claude"
        case .openai:     "ChatGPT"
        case .google:     "Gemini"
        case .venice:     "Venice"
        case .bankr:      "Bankr"
        case .openrouter: "OpenRouter"
        case .grok:       "Grok"
        }
    }

    /// The company that takes the key and sends the bill.
    var company: String {
        switch self {
        case .anthropic:  "Anthropic"
        case .openai:     "OpenAI"
        case .google:     "Google"
        case .venice:     "Venice"
        case .bankr:      "Bankr"
        case .openrouter: "OpenRouter"
        case .grok:       "xAI"
        }
    }

    /// Where a key comes from — the settings small print.
    var console: String {
        switch self {
        case .anthropic:  "console.anthropic.com"
        case .openai:     "platform.openai.com"
        case .google:     "aistudio.google.com"
        case .venice:     "venice.ai"
        case .bankr:      "bankr.bot/api-keys"
        case .openrouter: "openrouter.ai/keys"
        // console.x.ai answers 403 to a scripted request (bot-protected SPA,
        // verified 2026-07-31) rather than 404/unreachable — a real,
        // resolving console, unlike the cases elsewhere in this codebase
        // that omit a door for lack of ANY confirmable host. The root, not
        // a guessed sub-path — SPA routing under it isn't independently
        // confirmable, and a wrong deep link is worse than the root.
        case .grok:       "console.x.ai"
        }
    }

    var placeholder: String {
        switch self {
        case .anthropic:  "sk-ant-…"
        case .openai:     "sk-…"
        case .google:     "AIza…"
        case .venice:     "Paste your Venice key"
        case .bankr:      "Paste your Bankr key"
        case .openrouter: "Paste your OpenRouter key"
        case .grok:       "xai-…"
        }
    }

    /// Anthropic keeps its original vault key so keys saved before the
    /// providers arrived keep working.
    var vaultKey: String {
        self == .anthropic ? "token.anthropic-key" : "token.\(rawValue)-key"
    }

    /// The model a request actually names — the person's own choice when they
    /// have made one on the connect screen, else the pin below (2026-08-06,
    /// `AgentModelStore`). Every call site reads THIS, so a choice reaches the
    /// answer path, the key check and the librarian sweep without any of them
    /// knowing a choice exists.
    var model: String { AgentModelStore.chosen(self) ?? defaultModel }

    /// The fallback pin, used until the provider's own model list is read and
    /// something is picked from it. Kept because a list read can fail — a pin
    /// that might be stale still beats no request at all.
    var defaultModel: String {
        switch self {
        case .anthropic:  "claude-opus-4-8"
        case .openai:     "gpt-4o"
        case .google:     "gemini-2.5-flash"
        case .venice:     "llama-3.3-70b"
        // Bankr picks its own model per job — this names no request.
        case .bankr:      "bankr-agent"
        // OpenRouter's own router — picks whichever of its 400+ models fits
        // the request, so the app never pins one model or exposes a picker.
        case .openrouter: "openrouter/auto"
        // CORRECTED 2026-07-31, hours after first being written: this was
        // pinned to "grok-4", which xAI's own model list does not contain —
        // ANY request would have failed the moment someone added a key.
        // The published ids are grok-4.5 / grok-4.3 / grok-4.20-0309-*, and
        // xAI names 4.5 the current default ("the most intelligent and
        // fastest model we've built"). The first pin was written from
        // memory of the product NAME rather than read off the docs, which
        // is exactly the failure the "measure, don't assume" rule exists to
        // catch — and it survived because no key exists to fail against.
        //
        // Still UNVERIFIED against a live `/v1/models` read: read off
        // documentation, not measured, unlike every other pin here. xAI
        // rotates ids (Venice's own comment notes the same risk for the
        // same reason), and 4.5's ".5" suffix suggests a faster cadence
        // than most. `-byokProbe` against a real key is the check.
        case .grok:       "grok-4.5"
        }
    }

    /// Whether this agent can look at a screenshot's own picture, not just
    /// its OCR'd text (2026-07-21). Claude, ChatGPT, and Gemini are
    /// multimodal on the models above; Venice's pinned model is text-only
    /// and Bankr answers from the wallet, not the corpus — both stay
    /// honestly text-only rather than silently dropping a photo. OpenRouter's
    /// auto router can land on a text-only model, so it stays honestly
    /// text-only too rather than gambling a photo on whichever model it
    /// picked. Stated on the connect screens, never assumed.
    var seesImages: Bool {
        switch self {
        case .anthropic, .openai, .google: true
        // Grok: false is the SAFE default, not a measured fact (2026-07-31)
        // — xAI's own docs describe image input on some chat models without
        // confirming it for the specific id `model` pins above, and the
        // honesty rule's one-way door is clear: understating a capability
        // costs a screenshot going text-only, overstating one silently
        // drops a photo the person thought was seen. Re-measure before
        // flipping this.
        case .venice, .bankr, .openrouter, .grok: false
        }
    }

    /// Whether a keyed answer may also draw on live web search, not only
    /// the things saved here (2026-07-21) — a real divergence from "grounded
    /// in your things," so it's named on the connect screens. ChatGPT's
    /// search needs a different API (the Responses API, not the chat
    /// endpoint this app calls) and isn't wired up yet; Bankr already
    /// grounds on live markets its own way and doesn't need a second path.
    /// OpenRouter's search rides a separate paid `:online` model suffix this
    /// app doesn't append to the pinned `openrouter/auto` — claiming it here
    /// without appending the suffix would be the over-claim the honesty rule
    /// forbids.
    var searchesWeb: Bool {
        switch self {
        case .anthropic, .google, .venice: true
        // Grok: no search tool is wired to the plain chat request AT ALL yet
        // (see the file-level doc comment on `AgentProvider` — the intended
        // X-search verb is unbuilt pending a confirmed live wire shape). Even
        // once it exists, the design intent is for it to ride a SEPARATE,
        // explicit request fired only from a thing's own "What's X saying
        // about this?" verb — never silently appended to an ordinary keyed
        // answer the way Claude/Gemini/Venice's tool declarations are, since
        // it's billed per source and shouldn't fire on every routine answer.
        case .openai, .bankr, .openrouter, .grok: false
        }
    }

    /// What this agent can additionally do, beyond a plain text answer —
    /// shown on the connect screens so a person picks (or expects) the right
    /// thing (2026-07-21). Every provider here remembers a keyed
    /// conversation's prior turns except Bankr, which answers each prompt
    /// fresh off the wallet and live markets instead of the chat so far.
    /// nil means nothing more to say — Bankr's own explainer already covers
    /// its divergence.
    var capabilityLine: String? {
        switch self {
        case .anthropic, .google:
            "Also sees your screenshots' own pictures, remembers this chat's answers so far, and can search the web when your things fall short."
        case .openai:
            "Also sees your screenshots' own pictures, and remembers this chat's answers so far."
        case .venice:
            "Remembers this chat's answers so far, and can search the web when your things fall short — screenshots stay text-only."
        case .bankr:
            nil
        case .openrouter:
            "Auto-picks whichever model fits your question and remembers this chat's answers so far — screenshots and web search stay off since the model it lands on can vary."
        case .grok:
            "Remembers this chat's answers so far — screenshots and web search stay off for now."
        }
    }
}

/// The stored keys — per provider, with one ACTIVE provider that keyed
/// answers run on (the one whose key was saved last).
enum AgentKey {
    private static let activeDefaultsKey = "byok.provider"

    static var configured: [AgentProvider] {
        AgentProvider.allCases.filter { TokenVault.get($0.vaultKey) != nil }
    }

    static var isConfigured: Bool { !configured.isEmpty }

    static func isConfigured(_ provider: AgentProvider) -> Bool {
        TokenVault.get(provider.vaultKey) != nil
    }

    /// The provider a keyed answer runs on — the last one saved, falling
    /// back to any configured one.
    static var active: AgentProvider? {
        if let raw = UserDefaults.standard.string(forKey: activeDefaultsKey),
           let provider = AgentProvider(rawValue: raw),
           isConfigured(provider) { return provider }
        return configured.first
    }

    static func set(_ key: String, for provider: AgentProvider) {
        TokenVault.set(key.trimmingCharacters(in: .whitespacesAndNewlines),
                       for: provider.vaultKey)
        UserDefaults.standard.set(provider.rawValue, forKey: activeDefaultsKey)
    }

    /// Makes an ALREADY-configured provider the active one, without touching
    /// its stored key (2026-07-31, prd §242). No-ops on an unconfigured
    /// provider — activating a key that doesn't exist would just mint a
    /// dangling pointer `active` then has to fall back past anyway.
    ///
    /// Exists because `set` doubled as the only way to change the active
    /// provider, which meant re-becoming active required re-pasting a key
    /// that hadn't changed. With more than one key ever stored — a real
    /// case once Venice/Bankr/OpenRouter/Grok all sit in the same "Agent"
    /// catalog group — reconnecting via any ONE tile silently answered with
    /// whichever provider happened to be saved last, and nothing on any of
    /// those screens said so.
    static func activate(_ provider: AgentProvider) {
        guard isConfigured(provider) else { return }
        UserDefaults.standard.set(provider.rawValue, forKey: activeDefaultsKey)
    }

    static func clear(_ provider: AgentProvider) {
        TokenVault.delete(provider.vaultKey)
        if UserDefaults.standard.string(forKey: activeDefaultsKey) == provider.rawValue {
            UserDefaults.standard.removeObject(forKey: activeDefaultsKey)
        }
        // The receipt goes with the key (2026-08-06). Removing a key and
        // leaving its spend row behind would keep reporting on a credential
        // that is gone — and the row would then start accumulating against a
        // DIFFERENT key if the same provider is ever reconnected, which makes
        // the one number on that screen quietly wrong.
        AgentSpend.shared.forget(provider)
        // The model choice goes too: it was picked from that key's own list,
        // and a different key on the same provider may not be entitled to it.
        AgentModelStore.set(nil, for: provider)
    }

    /// The tail of a stored key for the settings line ("…3kQA") — enough to
    /// recognize it, never enough to leak it.
    static func hint(_ provider: AgentProvider) -> String {
        guard let key = TokenVault.get(provider.vaultKey), key.count > 4 else { return "" }
        return "…" + key.suffix(4)
    }
}

/// One exchange in a keyed conversation (2026-07-21) — the question exactly
/// as it was sent, and the prose that came back. A follow-up ("which of
/// those was from march?") threads prior turns into the next request the
/// same way the on-device model's own session does, so "those" still means
/// something.
struct AgentTurn: Sendable {
    let question: String
    let answer: String
}

/// A keyed answer: the prose, plus which numbered candidates it actually
/// drew on (validated indices into the candidates it was given) — empty when
/// the provider didn't point at specific things, in which case the caller
/// shows plain prose instead of a grounded row.
///
/// `searchedWeb` and `imagesSeen` are the honesty half (2026-07-21): an
/// answer that leaned on live search is a different promise than one made
/// only from your things, and an answer that actually LOOKED at a screenshot
/// did something its OCR'd text couldn't. Both are OBSERVED, never assumed —
/// `searchedWeb` is set only when the provider's own stream says the search
/// tool ran, so a provider that could search but didn't never claims it.
struct AgentAnswerResult: Sendable {
    let text: String
    let picks: [Int]
    var searchedWeb = false
    var imagesSeen = 0
    /// Real `Thing` ids the CORPUS TOOLS surfaced and the answer pointed at
    /// (2026-08-06) — the grounding rows for a tool-loop answer, in the order
    /// the model picked them. Empty on the single-shot path, where `picks`
    /// carries the same job as indices into the candidate list instead.
    ///
    /// Two fields rather than one because the two paths ground differently
    /// and collapsing them would lose that: `picks` indexes a list the CALLER
    /// already holds, while these are ids the caller must go and fetch,
    /// possibly for things its own retrieval never found — which is the
    /// entire point of giving the model tools.
    var toolHitIDs: [String] = []
    /// How many extra billed requests the tool loop cost — 0 means the model
    /// answered from what it was handed, which is the common case and not a
    /// failure. Shown in the provenance badge, so the person can see when a
    /// question went looking.
    var toolRounds = 0
    /// The model the provider says actually answered, when it says. The only
    /// place a silently rotated pin becomes visible.
    var model: String?
}

/// Why a keyed answer didn't arrive (2026-07-21). The old path collapsed all
/// of these to nil and the composer blamed the key for every one of them —
/// which is a lie when the model simply declined, or the network dropped.
/// Each case words itself.
enum AgentAnswerFailure: Error, Sendable {
    /// No key saved, or it vanished from the vault mid-flight.
    case noKey
    /// The provider rejected the key (401/403) — the one case where
    /// "check your key" is the honest advice.
    case rejectedKey
    /// The provider is rate-limiting this key (429).
    case rateLimited
    /// A valid answer that the model declined to give. NOT a failure the
    /// person can fix by touching their key.
    case refused
    /// Couldn't reach the provider at all.
    case unreachable
    /// The provider answered, but with an error (5xx or anything else).
    case providerError(Int)
    /// A clean 200 that carried no words.
    case empty

    /// One plain sentence for the composer — what happened, and only where
    /// it's true, what to do about it.
    var line: String {
        switch self {
        case .noKey:
            String(localized: "No key saved — add one in Settings to ask an agent.")
        case .rejectedKey:
            String(localized: "Your key was turned down — check it in Settings.")
        case .rateLimited:
            String(localized: "Your agent is rate-limiting this key — try again in a minute.")
        case .refused:
            String(localized: "The agent declined to answer that one. Your key is fine.")
        case .unreachable:
            String(localized: "Couldn't reach your agent — check your connection.")
        case .providerError(let status):
            String(localized: "Your agent had trouble answering (error \(status)) — try again.")
        case .empty:
            String(localized: "Your agent came back with nothing. Try asking it another way.")
        }
    }
}

/// What a key check actually found (connect-screen audit, 2026-07-31). The
/// old check answered a bare Bool, so all four agent screens said the same
/// "didn't accept that key — check it and try again" for a rejected key, a
/// rate limit, a key the provider itself has blocked, and no network at all.
/// Three of those four are not the key, and telling someone to re-check a key
/// that was never wrong is the failure `StripeFetch.Outcome` exists to avoid.
///
/// Only what the wire genuinely separates gets a case. It stays distinct from
/// `AgentAnswerFailure` — that one words a failed ANSWER (a refusal, an empty
/// reply, a missing key are all possible there and none of them are here), and
/// its advice is "your key is fine", which is the opposite of this screen's job.
enum AgentKeyCheck: Equatable {
    case accepted
    /// 401/403 — the provider turned the key down. The one case where
    /// "check your key" is the honest advice.
    case rejected
    /// 429 — the key is real and the provider is throttling it right now.
    case rateLimited
    /// The provider took the key and then said it can't answer. Only Grok
    /// reports this (MEASURED 2026-07-31, see `check`): xAI's key endpoint
    /// answers 200 with `team_blocked`/`api_key_blocked`/`api_key_disabled`
    /// for a real key whose team has no credits, while every actual request
    /// from it 403s. No other provider here exposes a comparable signal, so
    /// no other provider ever returns this — the honesty rule cuts both ways.
    case blocked
    /// The provider answered, but with nothing this could read — a 5xx, or a
    /// 200 whose body didn't parse.
    case providerError(Int)
    /// Nothing came back at all.
    case unreachable

    /// One plain sentence for the connect screen — what happened, and what to
    /// do about it. Worded once here rather than five times on each of the
    /// four agent screens: the sentences differ only by the provider's own
    /// name and console, which this already knows, and four hand-kept copies
    /// of the same five strings drift (the `BridgeSetupHeader` "one source of
    /// words" rule). `.accepted` has no line — nothing failed.
    func line(for provider: AgentProvider) -> String {
        switch self {
        case .accepted:
            ""
        case .rejected:
            String(localized: "\(provider.company) turned that key down — check you copied the whole thing.")
        case .rateLimited:
            String(localized: "\(provider.company) is rate-limiting this key — try again in a minute.")
        case .blocked:
            String(localized: "\(provider.company) blocked this key — usually no credits, or it's disabled. Check \(provider.console).")
        case .providerError(let status):
            String(localized: "\(provider.company) returned an unexpected HTTP \(status) — not your key. Try again.")
        case .unreachable:
            String(localized: "Couldn't reach \(provider.company) — check your connection.")
        }
    }
}

/// The device→provider call itself. Same contract as the on-device model:
/// grounded strictly on the candidates it is handed (the SAME retrieved
/// things the on-device answer saw), plain sentences, never invents a thing.
/// Returns nil on a missing key, a rejected key, a refusal, or a network
/// failure — the caller words that honestly.
enum AgentAnswer {

    /// Checks a key against its provider before it's saved — a models read,
    /// no tokens billed.
    static func check(_ key: String, provider: AgentProvider) async -> AgentKeyCheck {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(provider.model)")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models/\(provider.model)")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .google:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(provider.model)")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .venice:
            // Venice rotates model names — the list endpoint outlives any one.
            request = URLRequest(url: URL(string: "https://api.venice.ai/api/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .bankr:
            // Bankr has no free "who am I" read, but auth is checked before
            // the job lookup: a good key asking for a job that doesn't exist
            // gets 404, a bad key gets 401/403 — so a bogus job id validates
            // the key without submitting (and billing) a prompt.
            request = URLRequest(url: URL(string: "https://api.bankr.bot/agent/job/casberi-key-check")!)
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        case .openrouter:
            // Echoes back the key's own limits/usage — a free read, no model
            // call, no tokens billed.
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/key")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .grok:
            // MEASURED 2026-07-31 (curl, no key): `/v1/api-key` answers 401
            // "unauthenticated:no-credentials" with no credentials at all —
            // a real endpoint, distinct from the model-list read the pinned
            // `model` string can't itself vouch for. A models LIST read
            // (Venice's own pattern) would be the model-name-proof choice,
            // but xAI's `/v1/api-key` is the documented purpose-built
            // key-identity check, so it's used here; re-confirm the 200
            // shape once a real key exists.
            request = URLRequest(url: URL(string: "https://api.x.ai/v1/api-key")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .unreachable }
        // Bankr's bogus job id: a good key gets 404, which is the whole trick
        // (see the request above).
        if provider == .bankr, http.statusCode == 404 { return .accepted }
        let verdict = classify(status: http.statusCode)
        // Grok needs the BODY, not just the status (MEASURED 2026-07-31 with a
        // real key): `/v1/api-key` answers **200** for a perfectly real key
        // whose team has no credits — and every actual request from that same
        // key gets 403 `permission-denied`, "Your newly created team doesn't
        // have any credits or licenses yet."
        //
        // A status-only check would therefore report CONNECTED for a key that
        // cannot answer a single question — the exact fake status the honesty
        // rule forbids, and worse than a plain rejection because the failure
        // then surfaces later, on an answer, looking like a bug in the app.
        // The response carries the truth in three flags; all three are read,
        // since a blocked KEY and a blocked TEAM fail identically from here.
        if provider == .grok, verdict == .accepted {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return .providerError(http.statusCode) }
            let blocked = (json["team_blocked"] as? Bool ?? false)
                || (json["api_key_blocked"] as? Bool ?? false)
                || (json["api_key_disabled"] as? Bool ?? false)
            return blocked ? .blocked : .accepted
        }
        return verdict
    }

    /// The status codes every provider here speaks in common. 401/403 is the
    /// key, 429 is the quota, anything else the provider answered with is the
    /// provider's own trouble — the same split `streamText` already makes on
    /// the answer path.
    private static func classify(status: Int) -> AgentKeyCheck {
        switch status {
        case 200:      .accepted
        case 401, 403: .rejected
        case 429:      .rateLimited
        default:       .providerError(status)
        }
    }

    /// Synthesizes a grounded answer over the retrieved candidates with the
    /// person's key, under the SAME shared instructions/prompt the on-device
    /// model answers with (OnDeviceModel.synthesisInstructions/Prompt) — the
    /// key buys a stronger model, not a different contract (prd §67). Runs
    /// on the active provider.
    ///
    /// Three divergences from the on-device contract, all sanctioned
    /// 2026-07-21 and all named on the connect screens: `history` threads a
    /// keyed conversation's prior turns so a follow-up is understood in
    /// context; a candidate whose provider `seesImages` sends the
    /// screenshot's own picture alongside its OCR'd text, not just the text;
    /// a provider that `searchesWeb` may lean on live search when the saved
    /// things fall short, told explicitly to prefer them first. `onPartial`
    /// — when given — is called with the growing prose as it streams in, the
    /// same live-paint contract `OnDeviceModel.synthesisStream` already
    /// gives the composer; nil means the caller only wants the final text
    /// (the headless `-byokProbe` hook).
    ///
    /// (Bankr carries its own two divergences, documented on `bankrAnswer` —
    /// async job flow, wallet/market grounding — and answers through neither
    /// of the three above: no history, no images, no search tool, since its
    /// whole answer already isn't bound to the candidate list.)
    /// A fourth divergence since 2026-08-06, and the one that changes what the
    /// key BUYS: when the caller hands over a `corpus` snapshot, the request
    /// carries `AgentCorpusTools` and the answer runs as a bounded tool loop —
    /// the model can search the person's things itself, follow a lead with a
    /// second read, and ask which sources exist, instead of summarizing the
    /// one pre-retrieved candidate list it was handed. The on-device path has
    /// worked this way since 2026-07-15 (`AnswerTools`); this is the paid path
    /// catching up to the free one. An empty `corpus` keeps the old
    /// single-shot behaviour exactly.
    ///
    /// `provider` overrides the app-wide active one for THIS ask (prd §242's
    /// "Make active" without the app-wide flip) — the composer uses it so a
    /// person holding four keys can send one question to a second agent
    /// without changing what every later question runs on.
    static func synthesize(query: String, candidates: [OnDeviceModel.Candidate],
                           history: [AgentTurn] = [],
                           provider explicitProvider: AgentProvider? = nil,
                           corpus: [AnswerTools.Snapshot] = [],
                           onPartial: ((String) -> Void)? = nil)
    async -> Result<AgentAnswerResult, AgentAnswerFailure> {
        guard let provider = explicitProvider ?? AgentKey.active,
              let key = TokenVault.get(provider.vaultKey) else { return .failure(.noKey) }

        // The credential tripwire (prd §277, 2026-08-02). Everything past this
        // line leaves the device for somebody else's API, so the corpus text
        // that grounds the answer is scrubbed FIRST — and a candidate whose
        // text was scrubbed also drops its PICTURE, since a screenshot of a
        // recovery phrase would sail past every text rule straight into a
        // multimodal request. Before the Bankr fork on purpose: it posts the
        // same candidates.
        //
        // The on-device path deliberately does NOT do this. It never leaves,
        // and "what's my wifi password?" is a fair question to ask your own
        // corpus — hiding it there would be privacy theatre that costs the
        // person the answer.
        let candidates = candidates.map { candidate -> OnDeviceModel.Candidate in
            let title = SecretScan.redacted(candidate.title)
            let note = SecretScan.redacted(candidate.note)
            // `carriesSecret` reads the thing's FULL text; `note` is only a
            // 300-character excerpt, so testing the excerpt alone would let a
            // screenshot whose phrase sits past character 300 keep its
            // picture — the exact hole this gate exists to close.
            let clean = title == candidate.title
                && note == candidate.note
                && !candidate.carriesSecret
            return OnDeviceModel.Candidate(
                title: title, kind: candidate.kind, source: candidate.source,
                when: candidate.when, note: note,
                imageData: clean ? candidate.imageData : nil,
                carriesSecret: candidate.carriesSecret)
        }

        // Bankr diverges twice, both sanctioned (2026-07-16): it answers
        // through an async job (submit → poll), and it may ground on the
        // wallet and live markets — so an empty candidate list still asks.
        if provider == .bankr {
            return await bankrAnswer(query: query, candidates: candidates, key: key)
        }
        // With tools the model can reach things the local retriever missed, so
        // an empty candidate list is a starting point rather than a dead end.
        // Without them it is the whole evidence set, and a bigger model over
        // nothing is only a slower way to say "nothing matches".
        let toolsOn = !corpus.isEmpty
        guard !candidates.isEmpty || toolsOn else { return .failure(.empty) }

        var system = OnDeviceModel.synthesisInstructions(length: "a few plain sentences")
        if toolsOn { system += toolGuidance }
        system += toolsOn ? toolPickInstructions : pickInstructions
        if provider.searchesWeb { system += webSearchGuidance }

        // First turn sends the full prompt (instructions + numbered
        // candidates); a follow-up sends just the bare question — the
        // candidates and grounding rule already live in `history`'s first
        // exchange and the (unchanged) system prompt.
        let userText = history.isEmpty
            ? OnDeviceModel.synthesisPrompt(query: query, candidates: candidates)
            : query

        let images: [(index: Int, data: Data)] = provider.seesImages
            ? Array(candidates.enumerated().compactMap { i, c in c.imageData.map { (i, $0) } }.prefix(6))
            : []

        // The numbered candidates own labels 1…N for the whole exchange, so a
        // thing a tool surfaces later is #N+1 and one "PICKS:" line means one
        // unambiguous thing whichever list it came from. Reserved rather than
        // renumbered: the candidates are already written into the prompt by
        // the time any tool runs, so their numbers can no longer move.
        let sink = AgentCorpusTools.Sink(reserved: candidates.count)
        var steps: [AgentStep] = []
        var finalText = ""
        var searchedWeb = false
        var answeredModel: String?
        var rounds = 0

        while true {
            // The LAST permitted round declares no tools at all, so the model
            // is never handed a tool it won't be allowed to use — it is asked
            // a question it must answer from what it already has.
            let declareTools = toolsOn && rounds < AgentCorpusTools.maxRounds
            // Strip the "PICKS: …" marker line from every partial paint too, so
            // it never flashes in the live answer before settling. Each round
            // paints from empty on purpose: a round that ends in a tool call
            // emits a preamble ("let me look…"), and the answer that replaces
            // it is the one worth keeping.
            let liveOnPartial: ((String) -> Void)? = onPartial.map { forward in
                { raw in forward(stripPickLine(raw)) }
            }
            guard let wire = makeRequest(provider: provider, key: key, system: system,
                                         history: history, userText: userText,
                                         images: images, steps: steps,
                                         declareTools: declareTools) else {
                return .failure(.noKey)
            }
            var request = wire.request
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 90

            let streamed: StreamOutcome
            switch await streamText(request, onPartial: liveOnPartial, parse: wire.parse) {
            case .success(let outcome):
                streamed = outcome
            case .failure(let failure):
                // A failed round was usually still a billed request — a 429 or
                // a 5xx arrives after the provider has read the prompt. It is
                // recorded with no token counts, which is the honest shape:
                // it happened, and nobody told us what it cost.
                AgentSpend.shared.record(provider: provider, round: rounds)
                NSLog("[Casberi] AgentAnswer(%@): %@", provider.rawValue, String(describing: failure))
                return .failure(failure)
            }
            AgentSpend.shared.record(provider: provider, round: rounds,
                                     input: streamed.inputTokens,
                                     output: streamed.outputTokens,
                                     model: streamed.model)
            if streamed.searchedWeb { searchedWeb = true }
            if let model = streamed.model { answeredModel = model }
            finalText = streamed.text

            let calls = streamed.toolCalls
            guard declareTools, !calls.isEmpty else { break }
            rounds += 1
            steps.append(.toolCalls(calls))
            steps.append(.toolResults(calls.map {
                AgentCorpusTools.run($0, corpus: corpus, sink: sink)
            }))
        }

        let text = stripPickLine(finalText)
        guard !text.isEmpty else { return .failure(.empty) }
        let grounding = resolvePicks(from: finalText, candidateCount: candidates.count,
                                     surfaced: sink.ids)
        return .success(AgentAnswerResult(text: text, picks: grounding.picks,
                                          searchedWeb: searchedWeb,
                                          imagesSeen: images.count,
                                          toolHitIDs: grounding.toolHitIDs,
                                          toolRounds: rounds,
                                          model: answeredModel))
    }

    /// A plain one-shot completion: a system prompt, a question, a string back
    /// (2026-08-06). No corpus candidates, no tools, no history, no images, no
    /// streaming — the small, cheap shape the LIBRARIAN work needs
    /// (`AgentLibrarian`: naming a screenshot from its OCR text, digesting a
    /// thread), where there is nothing to ground against and nothing to paint
    /// live.
    ///
    /// It rides `makeRequest` rather than growing a second transport, so a
    /// wire-shape fix reaches both paths. `streamText` is still what reads the
    /// response — a non-streamed request would need a fourth response parser
    /// per provider for no benefit, since nothing here is watching it arrive.
    ///
    /// Bankr is refused rather than attempted: it is a wallet agent that
    /// answers from holdings and live markets, so asking it to name a
    /// screenshot would spend a job on a question it has no way to answer.
    static func complete(system: String, prompt: String,
                         provider explicitProvider: AgentProvider? = nil,
                         maxTokens: Int = 256)
    async -> Result<String, AgentAnswerFailure> {
        guard let provider = explicitProvider ?? AgentKey.active,
              provider != .bankr,
              let key = TokenVault.get(provider.vaultKey) else { return .failure(.noKey) }
        guard var wire = makeRequest(provider: provider, key: key, system: system,
                                     history: [], userText: prompt, images: [],
                                     steps: [], declareTools: false) else {
            return .failure(.noKey)
        }
        // `makeRequest` asks for 1024 tokens, which is right for an answer and
        // wasteful for a title. Re-encoding the body is cheaper than
        // threading a token budget through every branch of a switch that
        // exists to serve the answer path.
        if var body = (try? JSONSerialization.jsonObject(with: wire.request.httpBody ?? Data()))
            as? [String: Any] {
            if body["generationConfig"] != nil {
                body["generationConfig"] = ["maxOutputTokens": maxTokens]
            } else {
                body["max_tokens"] = maxTokens
            }
            wire.request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        var request = wire.request
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        switch await streamText(request, onPartial: nil, parse: wire.parse) {
        case .success(let outcome):
            AgentSpend.shared.record(provider: provider, input: outcome.inputTokens,
                                     output: outcome.outputTokens, model: outcome.model)
            let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .failure(.empty) : .success(text)
        case .failure(let failure):
            AgentSpend.shared.record(provider: provider)
            return .failure(failure)
        }
    }

    // MARK: - One round, in each provider's own wire shape

    /// What the model asked for and what it was given, in the order it
    /// happened. Kept provider-agnostic and rendered per wire below, because
    /// the three shapes disagree about nearly everything — Anthropic pairs a
    /// result to a call by `tool_use_id`, OpenAI by `tool_call_id` on a
    /// message of its own `role: "tool"`, and Gemini pairs by NAME with no id
    /// anywhere in the payload.
    private enum AgentStep {
        case toolCalls([AgentCorpusTools.Call])
        case toolResults([AgentCorpusTools.Result])
    }

    /// One round's request plus the parser for its stream. Returns nil only
    /// for Bankr, which never reaches here (it returns from `synthesize`
    /// above) — spelled as an explicit case rather than a `default` so a
    /// future eighth provider fails to compile instead of silently landing in
    /// somebody else's branch.
    private static func makeRequest(provider: AgentProvider, key: String, system: String,
                                    history: [AgentTurn], userText: String,
                                    images: [(index: Int, data: Data)],
                                    steps: [AgentStep], declareTools: Bool)
    -> (request: URLRequest, parse: ([String: Any]) -> StreamDelta)? {
        var request: URLRequest
        let parse: ([String: Any]) -> StreamDelta
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var body: [String: Any] = [
                "model": provider.model,
                "max_tokens": 1024,
                "system": system,
                "stream": true,
                "messages": anthropicMessages(history: history, userText: userText,
                                              images: images, steps: steps),
            ]
            // Anthropic's web search is a SERVER tool and coexists with
            // client tools in the same array — unlike Gemini's, below.
            var tools: [[String: Any]] = []
            if provider.searchesWeb {
                tools.append(["type": "web_search_20260209", "name": "web_search"])
            }
            if declareTools { tools += AgentCorpusTools.anthropicDeclarations() }
            if !tools.isEmpty { body["tools"] = tools }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            parse = anthropicDelta
        case .openai, .venice, .openrouter, .grok:
            // One OpenAI-compatible shape covers all four — Venice's,
            // OpenRouter's and xAI's APIs all speak it natively (MEASURED
            // 2026-07-31 for the endpoint's mere existence — `/v1/chat/
            // completions` answers 405 to a bare GET rather than 404,
            // confirming it's real and POST-only; the streamed SSE shape
            // itself is unconfirmed against a live key). `default:` was
            // deliberately replaced with an explicit case here — a silent
            // fallthrough is exactly how a future fifth provider would land
            // in the wrong branch unnoticed.
            let base: String
            switch provider {
            case .openai:     base = "https://api.openai.com/v1"
            case .venice:     base = "https://api.venice.ai/api/v1"
            case .openrouter: base = "https://openrouter.ai/api/v1"
            case .grok:       base = "https://api.x.ai/v1"
            default:          return nil
            }
            request = URLRequest(url: URL(string: "\(base)/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if provider == .openrouter {
                // OpenRouter's own attribution headers — optional, but they're
                // how a request shows up as Casberi's on the person's own
                // OpenRouter dashboard rather than an anonymous call.
                request.setValue("https://casberi.app", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("Casberi", forHTTPHeaderField: "X-Title")
            }
            var messages: [[String: Any]] = [["role": "system", "content": system]]
            for turn in history {
                messages.append(["role": "user", "content": turn.question])
                messages.append(["role": "assistant", "content": turn.answer])
            }
            messages.append(["role": "user", "content": openAIUserContent(userText, images: images)])
            messages += openAISteps(steps)
            var body: [String: Any] = [
                "model": provider.model,
                "max_tokens": 1024,
                "stream": true,
                "messages": messages,
            ]
            if declareTools { body["tools"] = AgentCorpusTools.openAIDeclarations() }
            // Usage on a STREAMED OpenAI-compatible response only arrives if
            // the request asks for it. Sent to the two providers that document
            // the option and withheld from Venice and Grok, whose support is
            // unconfirmed: an unknown body key is a 400 risk on the answer
            // path itself, and a missing spend row is a far cheaper failure
            // than a question that won't answer. `AgentSpend` prints its own
            // sentence for a provider that reports nothing.
            if provider == .openai || provider == .openrouter {
                body["stream_options"] = ["include_usage": true]
            }
            // Venice's own extension — a bare "search" boolean/flag on the
            // usual chat-completions body, no separate tool declaration.
            // (ChatGPT never reaches here with searchesWeb true — Anthropic's
            // and Gemini's own tool declarations are the search path there.)
            if provider == .venice {
                body["venice_parameters"] = ["enable_web_search": "on"]
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            parse = openAIDelta
        case .google:
            request = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(provider.model):streamGenerateContent?alt=sse")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var contents: [[String: Any]] = []
            for turn in history {
                contents.append(["role": "user", "parts": [["text": turn.question]]])
                contents.append(["role": "model", "parts": [["text": turn.answer]]])
            }
            var userParts: [[String: Any]] = [["text": userText]]
            for (index, data) in images {
                userParts.append(["text": "Photo for #\(index + 1):"])
                userParts.append(["inline_data": ["mime_type": "image/jpeg", "data": data.base64EncodedString()]])
            }
            contents.append(["role": "user", "parts": userParts])
            contents += geminiSteps(steps)
            var body: [String: Any] = [
                "system_instruction": ["parts": [["text": system]]],
                "contents": contents,
                "generationConfig": ["maxOutputTokens": 1024],
            ]
            // Gemini will not take `google_search` and `functionDeclarations`
            // in the same request on the model generations this app pins, so
            // the two cannot both be offered and one has to win. The corpus
            // tools do: they read the things the person actually saved, which
            // is what this answer is FOR, and web search is the fallback for
            // when those fall short. `searchedWeb` is observed rather than
            // assumed, so a round with no search tool simply never claims one
            // — the badge stays honest without a special case.
            if declareTools {
                body["tools"] = AgentCorpusTools.geminiDeclarations()
            } else if provider.searchesWeb {
                let searchTool: [String: Any] = ["google_search": [String: Any]()]
                body["tools"] = [searchTool]
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            parse = geminiDelta
        case .bankr:
            return nil // unreachable — bankr returns from `synthesize` above
        }
        return (request, parse)
    }

    // MARK: - The "PICKS: …" marker — structured grounding without a
    // separate structured-output API per provider

    /// Prepended to the system prompt when the corpus tools are declared
    /// (2026-08-06). Three things it has to say, each earned:
    ///
    /// 1. USE the tools. A model handed a candidate list AND tools will
    ///    usually just summarize the list, because that is the cheaper thing
    ///    to do and nothing told it otherwise — which would make this whole
    ///    feature invisible.
    /// 2. The rounds are BOUNDED. Without that a model plans a five-search
    ///    strategy, gets cut off at three, and answers from a half-finished
    ///    survey rather than from what it has.
    /// 3. Don't restate the rows. The app paints the things it found as real
    ///    rows underneath the prose, so a model that lists them writes the
    ///    screen twice — the same instruction `AnswerTools` gives on-device.
    private static let toolGuidance = """


        You have tools that read the things this person has saved. Use them \
        before you answer — search for what the question is about, and search \
        again with different words if the first look was thin. You may go back \
        at most \(AgentCorpusTools.maxRounds) times, so make each search count, \
        and answer from what you have when you are done. The app DISPLAYS every \
        thing your tools returned as rows beneath your answer, so never list, \
        number or restate them — write only what they add up to.
        """

    /// Appended to the shared synthesis instructions: asks the model to name,
    /// on its own trailing line, which numbered candidates its answer drew
    /// on — the same `{insight, picks}` shape the on-device `compose()` path
    /// gets from Apple's structured generation (`GroundedAnswerLayout`), but
    /// as one plain marker line instead of a per-provider JSON schema/tool
    /// call. Works identically (and streams cleanly) on all four network
    /// providers, so BYOK answers can paint the same grounded "Found" row
    /// the on-device lookup path already does, not just prose.
    private static let pickInstructions = """


        After you answer, on its own new line, write exactly "PICKS: " \
        followed by the 1-based numbers of the numbered things above that \
        your answer actually draws on, most relevant first, comma-separated \
        — for example "PICKS: 2, 5". Write "PICKS: none" if none apply. \
        Nothing may follow that line.
        """

    /// The same marker, worded for the tool loop — where the numbers span two
    /// lists (the candidates in the prompt, then everything the tools
    /// returned, which carry their own `#n` labels continuing the same run).
    /// One numbering space is the whole reason `Sink` takes a `reserved`
    /// count: two independently-numbered lists would make "PICKS: 3"
    /// ambiguous, and an ambiguous grounding row is a wrong grounding row.
    private static let toolPickInstructions = """


        After you answer, on its own new line, write exactly "PICKS: " \
        followed by the numbers of the things your answer actually draws on, \
        most relevant first, comma-separated — for example "PICKS: 2, 5". Use \
        the number each thing was given, whether it was numbered in the list \
        above or came back from a tool wearing a "#" label. Write "PICKS: \
        none" if none apply. Nothing may follow that line.
        """

    /// Appended only for a provider that `searchesWeb` — the one line that
    /// changes the grounding contract, so it says so plainly to the model
    /// too: the saved things come first, search only fills real gaps.
    private static let webSearchGuidance = """
         You may also use live web search when it would meaningfully improve \
        the answer, but always prefer and lean on the things listed above \
        first — they are what the person actually saved.
        """

    /// The prose with the model's own "PICKS: …" marker line (and the blank
    /// line before it) removed. No marker → the text unchanged, which is also
    /// what a stream mid-flight looks like, so this is safe to call on every
    /// partial paint.
    private static func stripPickLine(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let markerIndex = lines.lastIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("PICKS:")
        }) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let prose = lines[..<markerIndex].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prose.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : prose
    }

    /// Splits the marker's numbers across the two things they can mean: a
    /// number inside the reserved candidate range is an index the CALLER can
    /// resolve itself, and anything above it is the (1-based) position of a
    /// thing the tools surfaced, resolved to a real `Thing` id here.
    ///
    /// Out-of-range numbers are dropped rather than clamped. A model that
    /// invents "PICKS: 47" over a nine-thing exchange has invented a citation,
    /// and clamping it to the ninth thing would turn that into a confident
    /// wrong row — the one failure the grounding rail exists to prevent.
    private static func resolvePicks(from text: String, candidateCount: Int,
                                     surfaced: [String]) -> (picks: [Int], toolHitIDs: [String]) {
        let lines = text.components(separatedBy: "\n")
        guard let markerIndex = lines.lastIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("PICKS:")
        }) else { return ([], []) }
        let marker = lines[markerIndex].trimmingCharacters(in: .whitespaces)
        let value = marker.dropFirst("PICKS:".count).trimmingCharacters(in: .whitespaces)
        guard value.uppercased() != "NONE" else { return ([], []) }
        // The model writes "#4" when it is citing a tool result and "4" when
        // it is citing the prompt's own list; both mean the same number, so
        // the hash is stripped rather than parsed.
        let numbers = value.split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: CharacterSet(charactersIn: " #")))
        }
        var picks: [Int] = []
        var toolHitIDs: [String] = []
        for number in numbers {
            if number >= 1 && number <= candidateCount {
                picks.append(number - 1)
            } else {
                let index = number - candidateCount - 1
                if surfaced.indices.contains(index) { toolHitIDs.append(surfaced[index]) }
            }
        }
        return (picks, toolHitIDs)
    }

    // MARK: - Streaming transport

    /// One fragment of a tool call as it arrives. All three wire shapes stream
    /// a call in PIECES rather than whole — the name arrives in one event and
    /// the JSON arguments dribble in across several — so nothing can be run
    /// until the stream ends. `index` is the provider's own slot number for
    /// the call, which is the only thing that pairs a later argument fragment
    /// back to the name that opened it.
    ///
    /// Gemini is the exception and sets `arguments` whole in one go; it also
    /// sends no id anywhere in the payload, so one is synthesized from the
    /// index (the id is only ever used to pair a result back to its call, and
    /// Gemini's own wire pairs by name).
    private struct ToolFragment {
        let index: Int
        var id: String?
        var name: String?
        var arguments: String?
    }

    /// What one SSE line's parsed JSON means to the caller — an incremental
    /// chunk of prose to append, a refusal that abandons the whole answer,
    /// the provider's own signal that its web-search tool actually ran, a
    /// piece of a tool call, the billed token counts, or an event type this
    /// parser doesn't care about.
    private enum StreamDelta {
        case text(String)
        case refused
        case searched
        case tool([ToolFragment])
        case usage(input: Int?, output: Int?, model: String?)
        case ignore
    }

    /// Everything one stream produced: the accumulated prose, whether the
    /// model declined, whether its live search actually ran, the tool calls it
    /// asked for, and what the provider says the round cost.
    private struct StreamOutcome {
        var text = ""
        var refused = false
        var searchedWeb = false
        var inputTokens: Int?
        var outputTokens: Int?
        var model: String?
        /// Slot number → the call being assembled, in arrival order.
        var toolBuffers: [(index: Int, id: String, name: String, arguments: String)] = []

        /// Merges a fragment into whatever is already buffered for its slot.
        mutating func absorb(_ fragment: ToolFragment) {
            if let position = toolBuffers.firstIndex(where: { $0.index == fragment.index }) {
                if let id = fragment.id, !id.isEmpty { toolBuffers[position].id = id }
                if let name = fragment.name, !name.isEmpty { toolBuffers[position].name = name }
                if let arguments = fragment.arguments { toolBuffers[position].arguments += arguments }
            } else {
                toolBuffers.append((index: fragment.index,
                                    id: fragment.id ?? "call_\(fragment.index)",
                                    name: fragment.name ?? "",
                                    arguments: fragment.arguments ?? ""))
            }
        }

        /// The finished calls, in the order the provider opened them. A buffer
        /// with no name is dropped: it is a slot the stream opened and never
        /// filled (a connection cut mid-call), and running a nameless tool
        /// would only produce an error result the model then has to reason
        /// about.
        var toolCalls: [AgentCorpusTools.Call] {
            toolBuffers.compactMap { buffer in
                guard !buffer.name.isEmpty else { return nil }
                return AgentCorpusTools.Call(id: buffer.id, name: buffer.name,
                                             arguments: buffer.arguments.isEmpty ? "{}" : buffer.arguments)
            }
        }
    }

    /// Reads one provider's SSE response line by line, accumulating text via
    /// `parse`'s per-line JSON and calling `onPartial` with the running
    /// total after each chunk. Returns the final accumulated text, or nil on
    /// a network failure, a non-200 status, or a `.refused` delta. One
    /// implementation for all three streaming providers (Anthropic,
    /// OpenAI-shaped, Gemini) — only `parse` differs.
    private static func streamText(_ request: URLRequest,
                                   onPartial: ((String) -> Void)?,
                                   parse: @escaping ([String: Any]) -> StreamDelta)
    async -> Result<StreamOutcome, AgentAnswerFailure> {
        NetworkLedger.shared.record(request)
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request) else {
            return .failure(.unreachable)
        }
        guard let http = response as? HTTPURLResponse else { return .failure(.unreachable) }
        // Classify before reading a byte — a 401 is the person's key, a 429 is
        // their quota, a 5xx is the provider's problem, and each deserves its
        // own sentence rather than one shrug.
        switch http.statusCode {
        case 200: break
        case 401, 403: return .failure(.rejectedKey)
        case 429: return .failure(.rateLimited)
        default: return .failure(.providerError(http.statusCode))
        }
        var outcome = StreamOutcome()
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard payload != "[DONE]", !payload.isEmpty,
                      let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                switch parse(json) {
                case .text(let chunk):
                    outcome.text += chunk
                    onPartial?(outcome.text)
                case .refused:
                    outcome.refused = true
                case .searched:
                    outcome.searchedWeb = true
                case .tool(let fragments):
                    fragments.forEach { outcome.absorb($0) }
                case .usage(let input, let output, let model):
                    // Anthropic reports input on `message_start` and output on
                    // `message_delta`, so the two halves arrive in different
                    // events — each is taken only when present, never
                    // overwriting a count already read with a nil.
                    if let input { outcome.inputTokens = input }
                    if let output { outcome.outputTokens = output }
                    if let model, !model.isEmpty { outcome.model = model }
                case .ignore:
                    continue
                }
            }
        } catch {
            // A connection dropped mid-stream. Whatever text arrived stands —
            // a partial answer is still a real answer, and the person can see
            // it got cut. Only a drop before ANY text is a failure.
            //
            // A drop before any text but AFTER a tool call was assembled is
            // not a failure either: the round did its job, and the loop will
            // run the tools and ask again.
            if outcome.text.isEmpty && outcome.toolCalls.isEmpty { return .failure(.unreachable) }
        }
        if outcome.refused { return .failure(.refused) }
        return .success(outcome)
    }

    /// Anthropic's SSE shape: `content_block_delta` events carry the text;
    /// a `message_delta` whose `stop_reason` is "refusal" is a valid 200
    /// that must not be read as an answer.
    private static func anthropicDelta(_ json: [String: Any]) -> StreamDelta {
        let type = json["type"] as? String
        // Usage arrives in two halves: the input count rides `message_start`
        // (which also names the model that actually answered), the output
        // count rides the closing `message_delta`.
        if type == "message_start", let message = json["message"] as? [String: Any] {
            let usage = message["usage"] as? [String: Any]
            return .usage(input: usage?["input_tokens"] as? Int,
                          output: usage?["output_tokens"] as? Int,
                          model: message["model"] as? String)
        }
        if type == "content_block_delta",
           let delta = json["delta"] as? [String: Any] {
            if delta["type"] as? String == "text_delta", let t = delta["text"] as? String {
                return .text(t)
            }
            // The arguments of a client tool call, streamed as raw JSON text.
            if delta["type"] as? String == "input_json_delta",
               let partial = delta["partial_json"] as? String,
               let index = json["index"] as? Int {
                return .tool([ToolFragment(index: index, arguments: partial)])
            }
        }
        if type == "content_block_start",
           let block = json["content_block"] as? [String: Any] {
            let blockType = block["type"] as? String
            // The search tool actually running opens its own content block —
            // the observed signal, not the fact that we offered the tool.
            if blockType == "server_tool_use" || blockType == "web_search_tool_result" {
                return .searched
            }
            // A CLIENT tool call opens the same way, and is ours to run.
            if blockType == "tool_use", let index = json["index"] as? Int,
               let name = block["name"] as? String,
               AgentCorpusTools.names.contains(name) {
                return .tool([ToolFragment(index: index, id: block["id"] as? String, name: name)])
            }
        }
        if type == "message_delta" {
            if let delta = json["delta"] as? [String: Any],
               delta["stop_reason"] as? String == "refusal" {
                return .refused
            }
            if let usage = json["usage"] as? [String: Any] {
                return .usage(input: usage["input_tokens"] as? Int,
                              output: usage["output_tokens"] as? Int, model: nil)
            }
        }
        return .ignore
    }

    /// The OpenAI-compatible chat-completions SSE shape (ChatGPT, Venice,
    /// OpenRouter and Grok): each chunk's `choices[0].delta.content` is the
    /// next slice of text; a populated `delta.refusal` is a refusal, never
    /// text.
    private static func openAIDelta(_ json: [String: Any]) -> StreamDelta {
        // Venice reports a search it actually ran as citations riding the
        // chunk. Checked before `choices` because the citation chunk carries
        // no delta of its own. If Venice ever stops sending these we simply
        // stop claiming the search — under-claiming is the honest failure
        // (ChatGPT has no search on this endpoint at all, so it never fires).
        if let venice = json["venice_parameters"] as? [String: Any],
           let citations = venice["web_search_citations"] as? [Any], !citations.isEmpty {
            return .searched
        }
        if let citations = json["citations"] as? [Any], !citations.isEmpty { return .searched }
        // The usage chunk arrives last and carries an EMPTY `choices` array,
        // so it is read before the guard below rejects it.
        if let usage = json["usage"] as? [String: Any] {
            return .usage(input: usage["prompt_tokens"] as? Int,
                          output: usage["completion_tokens"] as? Int,
                          model: json["model"] as? String)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return .ignore }
        if let refusal = delta["refusal"] as? String, !refusal.isEmpty { return .refused }
        // Tool calls stream as an array of index-keyed fragments; one chunk
        // can carry pieces of several calls at once, which is why a delta
        // yields a LIST of fragments rather than one.
        if let calls = delta["tool_calls"] as? [[String: Any]], !calls.isEmpty {
            let fragments: [ToolFragment] = calls.enumerated().compactMap { position, call in
                let function = call["function"] as? [String: Any]
                return ToolFragment(index: call["index"] as? Int ?? position,
                                    id: call["id"] as? String,
                                    name: function?["name"] as? String,
                                    arguments: function?["arguments"] as? String)
            }
            return fragments.isEmpty ? .ignore : .tool(fragments)
        }
        if let content = delta["content"] as? String, !content.isEmpty { return .text(content) }
        return .ignore
    }

    /// Gemini's `streamGenerateContent?alt=sse` shape: each chunk carries
    /// its own incremental `candidates[0].content.parts[].text`; a populated
    /// `promptFeedback.blockReason` (no candidates at all) is a refusal.
    private static func geminiDelta(_ json: [String: Any]) -> StreamDelta {
        if let feedback = json["promptFeedback"] as? [String: Any],
           feedback["blockReason"] != nil {
            return .refused
        }
        // `usageMetadata` rides its own chunk and names cumulative totals for
        // the response, so the last one seen wins — which is what `.usage`'s
        // overwrite (rather than add) semantics already give.
        if let usage = json["usageMetadata"] as? [String: Any] {
            return .usage(input: usage["promptTokenCount"] as? Int,
                          output: usage["candidatesTokenCount"] as? Int,
                          model: json["modelVersion"] as? String)
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first else { return .ignore }
        // Gemini attaches groundingMetadata only when its search actually ran
        // — the observed signal. Reported before the text below because the
        // metadata rides its own chunk.
        if first["groundingMetadata"] != nil { return .searched }
        guard let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return .ignore }
        // A function call arrives WHOLE — name and arguments together, no id.
        let fragments: [ToolFragment] = parts.enumerated().compactMap { position, part in
            guard let call = part["functionCall"] as? [String: Any],
                  let name = call["name"] as? String,
                  AgentCorpusTools.names.contains(name) else { return nil }
            let arguments = call["args"] as? [String: Any] ?? [:]
            let encoded = (try? JSONSerialization.data(withJSONObject: arguments))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return ToolFragment(index: position, id: "call_\(position)_\(name)",
                                name: name, arguments: encoded)
        }
        if !fragments.isEmpty { return .tool(fragments) }
        let t = parts.compactMap { $0["text"] as? String }.joined()
        return t.isEmpty ? .ignore : .text(t)
    }

    // MARK: - Per-provider message bodies

    /// Anthropic's `messages` array: prior turns as plain user/assistant
    /// pairs, then the current turn — a single text block, or (when the
    /// candidate list carries screenshots this agent can see) a text block
    /// per photo labelled by the candidate it belongs to, so the model can
    /// tell which picture goes with which numbered thing.
    private static func anthropicMessages(history: [AgentTurn], userText: String,
                                          images: [(index: Int, data: Data)],
                                          steps: [AgentStep]) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        for turn in history {
            messages.append(["role": "user", "content": turn.question])
            messages.append(["role": "assistant", "content": turn.answer])
        }
        var content: [[String: Any]] = [["type": "text", "text": userText]]
        for (index, data) in images {
            content.append(["type": "text", "text": "Photo for #\(index + 1):"])
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg",
                                      "data": data.base64EncodedString()]])
        }
        messages.append(["role": "user", "content": content])
        // The tool loop so far, replayed: Anthropic pairs a result to its call
        // by `tool_use_id`, and every prior call must be present or the API
        // rejects the whole request rather than ignoring the orphan.
        for step in steps {
            switch step {
            case .toolCalls(let calls):
                messages.append(["role": "assistant", "content": calls.map { call in
                    ["type": "tool_use", "id": call.id, "name": call.name,
                     "input": jsonObject(call.arguments)]
                }])
            case .toolResults(let results):
                messages.append(["role": "user", "content": results.map { result in
                    ["type": "tool_result", "tool_use_id": result.id, "content": result.content]
                }])
            }
        }
        return messages
    }

    /// The OpenAI-compatible replay of the tool loop: the assistant's calls as
    /// one message carrying `tool_calls`, then ONE message per result — the
    /// shape's own rule, and a single merged `role: "tool"` message for two
    /// calls is rejected.
    private static func openAISteps(_ steps: [AgentStep]) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        for step in steps {
            switch step {
            case .toolCalls(let calls):
                messages.append([
                    "role": "assistant",
                    // Some implementations of this shape require the key to be
                    // present even when the turn is pure tool use.
                    "content": NSNull(),
                    "tool_calls": calls.map { call in
                        ["id": call.id, "type": "function",
                         "function": ["name": call.name, "arguments": call.arguments]]
                    },
                ])
            case .toolResults(let results):
                for result in results {
                    messages.append(["role": "tool", "tool_call_id": result.id,
                                     "name": result.name, "content": result.content])
                }
            }
        }
        return messages
    }

    /// Gemini's replay. It carries NO call id anywhere in the payload and
    /// pairs a response to its call by NAME, which is why `Call.id` is
    /// synthesized there and never sent.
    private static func geminiSteps(_ steps: [AgentStep]) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        for step in steps {
            switch step {
            case .toolCalls(let calls):
                contents.append(["role": "model", "parts": calls.map { call in
                    ["functionCall": ["name": call.name, "args": jsonObject(call.arguments)]]
                }])
            case .toolResults(let results):
                contents.append(["role": "user", "parts": results.map { result in
                    ["functionResponse": ["name": result.name,
                                          "response": ["result": result.content]]]
                }])
            }
        }
        return contents
    }

    /// A tool call's raw argument string as a dictionary, for the two wires
    /// that want an object where OpenAI wants the string back verbatim. An
    /// unparseable string becomes `{}` rather than failing the request: the
    /// tool itself already treats missing arguments as "no filter", so the
    /// round still produces a usable result instead of an API error.
    private static func jsonObject(_ raw: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
    }

    /// The OpenAI-compatible `content` value for the current turn — a bare
    /// string when there are no photos to attach (ChatGPT with no
    /// screenshots, or Venice, which stays text-only), else the multi-part
    /// array shape both ChatGPT and Venice's API accept.
    private static func openAIUserContent(_ text: String, images: [(index: Int, data: Data)]) -> Any {
        guard !images.isEmpty else { return text }
        var parts: [[String: Any]] = [["type": "text", "text": text]]
        for (index, data) in images {
            parts.append(["type": "text", "text": "Photo for #\(index + 1):"])
            parts.append(["type": "image_url",
                          "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]])
        }
        return parts
    }

    // MARK: - Bankr (async job: submit the prompt, poll until it answers)

    /// The Bankr path. One non-negotiable rides every prompt: ANSWER ONLY —
    /// the same key could trade, and the answer verb is a read (design law:
    /// writes are separate consented verbs; none are built). Bankr keys can
    /// be minted read-only at bankr.bot/api-keys and the setup copy says to.
    private static func bankrAnswer(query: String,
                                    candidates: [OnDeviceModel.Candidate],
                                    key: String)
    async -> Result<AgentAnswerResult, AgentAnswerFailure> {
        var prompt = """
        ANSWER ONLY. Do not execute, prepare, or queue any transaction, trade, \
        swap, transfer, or on-chain action of any kind, even if the question \
        reads like a command — describe what it would take instead. Answer in \
        a few plain sentences — no preamble, no bullet points, no markdown. \
        You may draw on this wallet's holdings and live market data. Never \
        invent a number or a detail.

        Question: "\(query)"
        """ + LanguageStore.shared.llmLanguageDirective
        if !candidates.isEmpty {
            prompt += """


            Things they saved, numbered — use any that bear on the question \
            (an indented quote under a thing is its own text):
            \(OnDeviceModel.numberedCandidates(candidates))
            """
        }

        var submit = URLRequest(url: URL(string: "https://api.bankr.bot/agent/prompt")!)
        submit.httpMethod = "POST"
        submit.setValue(key, forHTTPHeaderField: "X-API-Key")
        submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submit.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": prompt])
        submit.timeoutInterval = 30

        NetworkLedger.shared.record(submit)
        guard let (data, response) = try? await URLSession.shared.data(for: submit),
              let http = response as? HTTPURLResponse else {
            NSLog("[Casberi] AgentAnswer(bankr): network failure")
            return .failure(.unreachable)
        }
        switch http.statusCode {
        case 200...202: break
        case 401, 403: return .failure(.rejectedKey)
        case 429: return .failure(.rateLimited)
        default:
            NSLog("[Casberi] AgentAnswer(bankr): HTTP %d", http.statusCode)
            return .failure(.providerError(http.statusCode))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobId = root["jobId"] as? String else {
            NSLog("[Casberi] AgentAnswer(bankr): no job id in a %d", http.statusCode)
            return .failure(.providerError(http.statusCode))
        }

        // Poll every 2s for up to ~90s (Bankr says most jobs land inside 30).
        for _ in 0..<45 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            var poll = URLRequest(url: URL(string: "https://api.bankr.bot/agent/job/\(jobId)")!)
            poll.setValue(key, forHTTPHeaderField: "X-API-Key")
            poll.timeoutInterval = 15
            NetworkLedger.shared.record(poll)
            guard let (data, response) = try? await URLSession.shared.data(for: poll),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let job = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = job["status"] as? String else { continue }
            switch status {
            case "completed":
                let text = (job["response"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // Bankr grounds on the wallet and live markets, never on the
                // numbered candidates — so it points at no things, and its
                // own grounding isn't the web search the other agents run.
                return text.isEmpty ? .failure(.empty)
                                    : .success(AgentAnswerResult(text: text, picks: []))
            case "failed", "cancelled":
                NSLog("[Casberi] AgentAnswer(bankr): job %@ — %@", status,
                      job["error"] as? String ?? "no detail")
                return .failure(.refused)
            default:
                continue // pending / processing — keep polling
            }
        }
        NSLog("[Casberi] AgentAnswer(bankr): job timed out")
        return .failure(.unreachable)
    }
}
