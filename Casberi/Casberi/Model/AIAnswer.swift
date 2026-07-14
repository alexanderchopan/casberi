import Foundation

/// BYO-key (prd §67) — the person's own AI keys power a "try with <name>"
/// they tap per answer. It is a VERB, never a fallback: nothing leaves this
/// iPhone until the tap, and what leaves goes straight from the device to
/// that provider's own API — Casberi runs no server and never sees a byte.
/// Keys live in the Keychain (TokenVault), one slot per provider, so several
/// providers can be connected at once (ruling 2026-07-14).
enum AIKey {
    /// The single-key slots from before multi-provider (2026-07-14) — a key
    /// saved then moves into its per-provider slot once, on first read.
    private static let legacyKeySlot = "token.anthropic-key"
    private static let legacyProviderSlot = "token.ai-provider"

    /// One-shot legacy migration, run lazily before any read. The old build
    /// stored one key + a provider record; move it into the provider's own
    /// slot so it keeps working untouched. A key with no record is Anthropic —
    /// that was the only option then.
    private static let migrated: Bool = {
        if let key = TokenVault.get(legacyKeySlot) {
            let provider = TokenVault.get(legacyProviderSlot)
                .flatMap(AIProvider.init(rawValue:)) ?? .anthropic
            if TokenVault.get(provider.slotKey) == nil {
                TokenVault.set(key, for: provider.slotKey)
            }
            TokenVault.delete(legacyKeySlot)
            TokenVault.delete(legacyProviderSlot)
        }
        return true
    }()

    static func key(for provider: AIProvider) -> String? {
        _ = migrated
        return TokenVault.get(provider.slotKey)
    }

    static func isConnected(_ provider: AIProvider) -> Bool { key(for: provider) != nil }

    /// The providers with a key saved, in the fixed catalog order — the
    /// composer's chip row and the settings overview both read this.
    static var connected: [AIProvider] { AIProvider.allCases.filter(isConnected) }

    static var isConfigured: Bool { !connected.isEmpty }

    static func set(_ key: String, provider: AIProvider) {
        _ = migrated
        TokenVault.set(key.trimmingCharacters(in: .whitespacesAndNewlines),
                       for: provider.slotKey)
    }

    static func clear(_ provider: AIProvider) {
        _ = migrated
        TokenVault.delete(provider.slotKey)
    }

    /// The tail of a stored key for the settings line ("…3kQA") — enough to
    /// recognize it, never enough to leak it.
    static func hint(_ provider: AIProvider) -> String {
        guard let key = key(for: provider), key.count > 4 else { return "" }
        return "…" + key.suffix(4)
    }
}

/// The device→provider call itself. Same contract as the on-device model:
/// grounded strictly on the candidates it is handed (the SAME retrieved things
/// the on-device answer saw), plain sentences, never invents a thing. The key
/// buys a stronger model, not a different contract (prd §67); the one
/// divergence is length. Returns nil on a missing key, a rejected key, a
/// refusal, or a network failure — the caller words that honestly.
///
/// Every provider's wire details are isolated to `buildRequest`/`parseResponse`
/// here, so `synthesize` is one flow for all of them and adding a provider
/// touches only these switches (plus `AIProvider`).
enum AIAnswer {
    /// Checks a key against its provider before it's saved — a cheap models
    /// read, no tokens billed. True means the provider accepted the key.
    static func validate(_ key: String, provider: AIProvider) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(provider.model)")!)
            request.setValue(trimmed, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        case .google:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!)
            request.setValue(trimmed, forHTTPHeaderField: "x-goog-api-key")
        case .venice:
            request = URLRequest(url: URL(string: "https://api.venice.ai/api/v1/models")!)
            request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        }
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Synthesizes a grounded answer over the retrieved candidates with the
    /// person's key for ONE named provider — the chip the person tapped names
    /// it, so the routing is never a guess.
    static func synthesize(query: String, candidates: [OnDeviceModel.Candidate],
                           provider: AIProvider) async -> String? {
        guard let key = AIKey.key(for: provider), !candidates.isEmpty else { return nil }

        let system = OnDeviceModel.synthesisInstructions(length: "a few plain sentences")
        let prompt = OnDeviceModel.synthesisPrompt(query: query, candidates: candidates)

        let request = buildRequest(provider: provider, key: key, system: system, prompt: prompt)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            NSLog("[Casberi] AIAnswer(%@): network failure", provider.rawValue)
            return nil
        }
        guard http.statusCode == 200 else {
            NSLog("[Casberi] AIAnswer(%@): HTTP %d", provider.rawValue, http.statusCode)
            return nil
        }
        let text = parseResponse(provider: provider, data: data)
        return (text?.isEmpty ?? true) ? nil : text
    }

    // MARK: - Per-provider wire details

    /// Builds the POST for one provider — endpoint, auth header, and the body
    /// shape each one expects (Anthropic Messages, OpenAI Chat Completions,
    /// Gemini generateContent, Venice's OpenAI-compatible completions). The
    /// grounded system + prompt are identical across all of them.
    private static func buildRequest(provider: AIProvider, key: String,
                                     system: String, prompt: String) -> URLRequest {
        var request: URLRequest
        let body: [String: Any]
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": provider.model,
                "max_tokens": 1024,
                "system": system,
                "messages": [["role": "user", "content": prompt]],
            ]
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = [
                "model": provider.model,
                // A reasoning model spends this budget on thinking too, so give
                // it headroom — a starved budget returns an empty 200, not prose.
                "max_completion_tokens": 2048,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": prompt],
                ],
            ]
        case .google:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(provider.model):generateContent")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "system_instruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": prompt]]]],
            ]
        case .venice:
            request = URLRequest(url: URL(string: "https://api.venice.ai/api/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = [
                "model": provider.model,
                "max_tokens": 1024,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": prompt],
                ],
                // Venice injects its own system prompt by default — turn that
                // off so the grounded contract is OURS, same as every provider.
                "venice_parameters": ["include_venice_system_prompt": false],
            ]
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90
        return request
    }

    /// Pulls the grounded prose out of one provider's 200 body. A refusal is a
    /// valid 200 for every provider — treat it as "no answer", never as text.
    private static func parseResponse(provider: AIProvider, data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch provider {
        case .anthropic:
            if let stop = root["stop_reason"] as? String, stop == "refusal" { return nil }
            guard let content = root["content"] as? [[String: Any]] else { return nil }
            return content
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .openai, .venice:
            guard let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else { return nil }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty { return nil }
            return (message["content"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .google:
            guard let candidates = root["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            return parts
                .compactMap { $0["text"] as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
