import Foundation

/// BYO-key (prd §67, providers 2026-07-14) — the person's own agent key
/// powers a "try with your key" they tap per answer. It is a VERB, never a
/// fallback: nothing leaves this iPhone until the tap, and what leaves goes
/// straight from the device to the provider they chose — Casberi runs no
/// server and never sees a byte. Keys live in the Keychain (TokenVault),
/// like every bridge token.
///
/// The key is an AGENT key, never "the Anthropic key" (user ruling
/// 2026-07-14): six providers speak here — Claude, ChatGPT, Gemini,
/// Venice, Bankr, and OpenRouter — one request shape each, one contract
/// for all. Bankr (2026-07-16) is the one agent that isn't a bare model:
/// it's a wallet-attached trading agent, so its answers may ALSO draw on
/// the wallet and live markets (the sanctioned grounding divergence), and
/// every prompt it gets is hard-prefixed "answer only — never execute"
/// (the answer verb stays a read; writes would be separate consented
/// verbs, unbuilt). OpenRouter (2026-07-24) is the multi-model divergence:
/// it never pins one model, riding its own `openrouter/auto` router
/// instead, so it stays honestly text-only/no-search rather than claiming
/// a capability whichever model it lands on might not have.
enum AgentProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai
    case google
    case venice
    case bankr
    case openrouter

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
        }
    }

    /// Where `console` actually opens (prd §218's "step one becomes the button
    /// it was describing" — a URL set in body text is an instruction the app
    /// could have followed itself). Venice, Bankr and OpenRouter keep the exact
    /// deep links their own setup screens shipped, and those screens now read
    /// them from here so one agent's console can't live at two addresses; the
    /// other three open the host `console` names, so the button can never land
    /// somewhere its own label didn't promise.
    var consoleURL: URL? {
        switch self {
        case .anthropic:  URL(string: "https://console.anthropic.com")
        case .openai:     URL(string: "https://platform.openai.com")
        case .google:     URL(string: "https://aistudio.google.com")
        case .venice:     URL(string: "https://venice.ai/settings/api")
        case .bankr:      URL(string: "https://bankr.bot/api-keys")
        case .openrouter: URL(string: "https://openrouter.ai/settings/keys")
        }
    }

    /// The one thing worth knowing BEFORE minting this agent's key — nil for
    /// the agents that have nothing extra to say. Shown beside the key field
    /// for the SELECTED agent only (2026-07-26): the settings sheet used to
    /// print all six consoles and both caveats as one seven-line block of
    /// small print, which is five agents' worth of noise around the one
    /// being set up.
    var keyCaution: String? {
        switch self {
        case .bankr:      "Make it a read-only key — answers never trade."
        case .openrouter: "Routes to whichever model fits — no model to pick."
        case .anthropic, .openai, .google, .venice: nil
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
        }
    }

    /// Anthropic keeps its original vault key so keys saved before the
    /// providers arrived keep working.
    var vaultKey: String {
        self == .anthropic ? "token.anthropic-key" : "token.\(rawValue)-key"
    }

    var model: String {
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
        case .venice, .bankr, .openrouter: false
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
        case .openai, .bankr, .openrouter: false
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

    static func clear(_ provider: AgentProvider) {
        TokenVault.delete(provider.vaultKey)
        if UserDefaults.standard.string(forKey: activeDefaultsKey) == provider.rawValue {
            UserDefaults.standard.removeObject(forKey: activeDefaultsKey)
        }
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
            String(localized: "Your agent is rate-limiting this key right now — try again in a minute.")
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

/// The device→provider call itself. Same contract as the on-device model:
/// grounded strictly on the candidates it is handed (the SAME retrieved
/// things the on-device answer saw), plain sentences, never invents a thing.
/// Returns nil on a missing key, a rejected key, a refusal, or a network
/// failure — the caller words that honestly.
enum AgentAnswer {

    /// Checks a key against its provider before it's saved — a models read,
    /// no tokens billed. True means the provider accepted the key.
    static func validate(_ key: String, provider: AgentProvider) async -> Bool {
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
        }
        request.timeoutInterval = 15
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        if provider == .bankr { return http.statusCode == 404 || http.statusCode == 200 }
        return http.statusCode == 200
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
    static func synthesize(query: String, candidates: [OnDeviceModel.Candidate],
                           history: [AgentTurn] = [],
                           onPartial: ((String) -> Void)? = nil)
    async -> Result<AgentAnswerResult, AgentAnswerFailure> {
        guard let provider = AgentKey.active,
              let key = TokenVault.get(provider.vaultKey) else { return .failure(.noKey) }

        // Bankr diverges twice, both sanctioned (2026-07-16): it answers
        // through an async job (submit → poll), and it may ground on the
        // wallet and live markets — so an empty candidate list still asks.
        if provider == .bankr {
            return await bankrAnswer(query: query, candidates: candidates, key: key)
        }
        guard !candidates.isEmpty else { return .failure(.empty) }

        var system = OnDeviceModel.synthesisInstructions(length: "a few plain sentences") + pickInstructions
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

        // Strip the "PICKS: …" marker line from every partial paint too, so
        // it never flashes in the live answer before settling.
        let liveOnPartial: ((String) -> Void)? = onPartial.map { forward in
            { raw in forward(extractPicks(from: raw, candidateCount: candidates.count).text) }
        }

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
                "messages": anthropicMessages(history: history, userText: userText, images: images),
            ]
            if provider.searchesWeb {
                body["tools"] = [["type": "web_search_20260209", "name": "web_search"]]
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            parse = anthropicDelta
        case .openai, .venice, .openrouter:
            // One OpenAI-compatible shape covers all three — Venice's and
            // OpenRouter's APIs both speak it.
            let base: String
            switch provider {
            case .openai:     base = "https://api.openai.com/v1"
            case .venice:     base = "https://api.venice.ai/api/v1"
            default:          base = "https://openrouter.ai/api/v1"
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
            var body: [String: Any] = [
                "model": provider.model,
                "max_tokens": 1024,
                "stream": true,
                "messages": messages,
            ]
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
            var body: [String: Any] = [
                "system_instruction": ["parts": [["text": system]]],
                "contents": contents,
                "generationConfig": ["maxOutputTokens": 1024],
            ]
            if provider.searchesWeb {
                let searchTool: [String: Any] = ["google_search": [String: Any]()]
                body["tools"] = [searchTool]
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            parse = geminiDelta
        case .bankr:
            return .failure(.noKey) // unreachable — bankr returned above
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        let streamed: StreamOutcome
        switch await streamText(request, onPartial: liveOnPartial, parse: parse) {
        case .success(let outcome):
            streamed = outcome
        case .failure(let failure):
            NSLog("[Casberi] AgentAnswer(%@): %@", provider.rawValue, String(describing: failure))
            return .failure(failure)
        }
        let (text, picks) = extractPicks(from: streamed.text, candidateCount: candidates.count)
        guard !text.isEmpty else { return .failure(.empty) }
        return .success(AgentAnswerResult(text: text, picks: picks,
                                          searchedWeb: streamed.searchedWeb,
                                          imagesSeen: images.count))
    }

    // MARK: - The "PICKS: …" marker — structured grounding without a
    // separate structured-output API per provider

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

    /// Appended only for a provider that `searchesWeb` — the one line that
    /// changes the grounding contract, so it says so plainly to the model
    /// too: the saved things come first, search only fills real gaps.
    private static let webSearchGuidance = """
         You may also use live web search when it would meaningfully improve \
        the answer, but always prefer and lean on the things listed above \
        first — they are what the person actually saved.
        """

    /// Splits the model's own "PICKS: 2, 5" marker line off the end of the
    /// answer — the prose with that line (and the blank line before it)
    /// removed, and the 0-based indices it named, validated against the
    /// candidate count. No marker, or nothing parseable → no picks, the
    /// whole text stays prose (the caller shows it plain, same as before
    /// this existed).
    private static func extractPicks(from text: String, candidateCount: Int) -> (text: String, picks: [Int]) {
        let lines = text.components(separatedBy: "\n")
        guard let markerIndex = lines.lastIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("PICKS:")
        }) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }
        let marker = lines[markerIndex].trimmingCharacters(in: .whitespaces)
        let value = marker.dropFirst("PICKS:".count).trimmingCharacters(in: .whitespaces)
        let picks: [Int] = value.uppercased() == "NONE" ? [] : value
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .map { $0 - 1 }
            .filter { $0 >= 0 && $0 < candidateCount }
        let prose = lines[..<markerIndex].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (prose.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : prose, picks)
    }

    // MARK: - Streaming transport

    /// What one SSE line's parsed JSON means to the caller — an incremental
    /// chunk of prose to append, a refusal that abandons the whole answer,
    /// the provider's own signal that its web-search tool actually ran, or
    /// an event type this parser doesn't care about.
    private enum StreamDelta {
        case text(String)
        case refused
        case searched
        case ignore
    }

    /// Everything one stream produced: the accumulated prose, whether the
    /// model declined, and whether its live search actually ran.
    private struct StreamOutcome {
        var text = ""
        var refused = false
        var searchedWeb = false
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
                case .ignore:
                    continue
                }
            }
        } catch {
            // A connection dropped mid-stream. Whatever text arrived stands —
            // a partial answer is still a real answer, and the person can see
            // it got cut. Only a drop before ANY text is a failure.
            if outcome.text.isEmpty { return .failure(.unreachable) }
        }
        if outcome.refused { return .failure(.refused) }
        return .success(outcome)
    }

    /// Anthropic's SSE shape: `content_block_delta` events carry the text;
    /// a `message_delta` whose `stop_reason` is "refusal" is a valid 200
    /// that must not be read as an answer.
    private static func anthropicDelta(_ json: [String: Any]) -> StreamDelta {
        let type = json["type"] as? String
        if type == "content_block_delta",
           let delta = json["delta"] as? [String: Any],
           delta["type"] as? String == "text_delta",
           let t = delta["text"] as? String {
            return .text(t)
        }
        // The search tool actually running opens its own content block — the
        // observed signal, not the fact that we offered the tool.
        if type == "content_block_start",
           let block = json["content_block"] as? [String: Any] {
            let blockType = block["type"] as? String
            if blockType == "server_tool_use" || blockType == "web_search_tool_result" {
                return .searched
            }
        }
        if type == "message_delta",
           let delta = json["delta"] as? [String: Any],
           delta["stop_reason"] as? String == "refusal" {
            return .refused
        }
        return .ignore
    }

    /// The OpenAI-compatible chat-completions SSE shape (ChatGPT and
    /// Venice): each chunk's `choices[0].delta.content` is the next slice of
    /// text; a populated `delta.refusal` is a refusal, never text.
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
        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return .ignore }
        if let refusal = delta["refusal"] as? String, !refusal.isEmpty { return .refused }
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
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first else { return .ignore }
        // Gemini attaches groundingMetadata only when its search actually ran
        // — the observed signal. Reported before the text below because the
        // metadata rides its own chunk.
        if first["groundingMetadata"] != nil { return .searched }
        guard let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return .ignore }
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
                                          images: [(index: Int, data: Data)]) -> [[String: Any]] {
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
        return messages
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
