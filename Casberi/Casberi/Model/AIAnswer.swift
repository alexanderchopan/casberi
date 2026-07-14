import Foundation

/// BYO-key (prd §67) — the person's own AI key powers a "try with your key"
/// they tap per answer. It is a VERB, never a fallback: nothing leaves this
/// iPhone until the tap, and what leaves goes straight from the device to the
/// provider's own API — Casberi runs no server and never sees a byte. The key
/// and which provider it belongs to live in the Keychain (TokenVault), like
/// every bridge token.
enum AIKey {
    /// The key slot in the Keychain. The account name is legacy
    /// ("anthropic-key") so keys saved before multi-provider still read — the
    /// value is now ANY provider's key, and the provider is stored alongside.
    static let vaultKey = "token.anthropic-key"
    private static let providerKey = "token.ai-provider"

    static var isConfigured: Bool { TokenVault.get(vaultKey) != nil }

    /// The provider the saved key belongs to. A legacy key saved before the
    /// provider was recorded is Anthropic — that was the only option then.
    static var provider: AIProvider {
        guard isConfigured else { return .anthropic }
        if let raw = TokenVault.get(providerKey), let p = AIProvider(rawValue: raw) { return p }
        return .anthropic
    }

    static func set(_ key: String, provider: AIProvider) {
        TokenVault.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: vaultKey)
        TokenVault.set(provider.rawValue, for: providerKey)
    }

    static func clear() {
        TokenVault.delete(vaultKey)
        TokenVault.delete(providerKey)
    }

    /// The tail of the stored key for the settings line ("…3kQA") — enough to
    /// recognize it, never enough to leak it.
    static var hint: String {
        guard let key = TokenVault.get(vaultKey), key.count > 4 else { return "" }
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
/// touches only these two switches (plus `AIProvider`).
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
        }
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Synthesizes a grounded answer over the retrieved candidates with the
    /// person's key, under the SAME shared instructions/prompt the on-device
    /// model answers with (OnDeviceModel.synthesisInstructions/Prompt).
    static func synthesize(query: String, candidates: [OnDeviceModel.Candidate]) async -> String? {
        guard let key = TokenVault.get(AIKey.vaultKey), !candidates.isEmpty else { return nil }
        let provider = AIKey.provider

        let system = OnDeviceModel.synthesisInstructions(length: "a few plain sentences")
        let prompt = OnDeviceModel.synthesisPrompt(query: query, candidates: candidates)

        guard let request = buildRequest(provider: provider, key: key, system: system, prompt: prompt) else {
            return nil
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            NSLog("[Casberi] AIAnswer: network failure")
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
    /// Gemini generateContent). The grounded system + prompt are identical.
    private static func buildRequest(provider: AIProvider, key: String,
                                     system: String, prompt: String) -> URLRequest? {
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
        case .openai:
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
