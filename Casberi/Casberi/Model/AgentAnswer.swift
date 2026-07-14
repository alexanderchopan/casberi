import Foundation

/// BYO-key (prd §67, providers 2026-07-14) — the person's own agent key
/// powers a "try with your key" they tap per answer. It is a VERB, never a
/// fallback: nothing leaves this iPhone until the tap, and what leaves goes
/// straight from the device to the provider they chose — Casberi runs no
/// server and never sees a byte. Keys live in the Keychain (TokenVault),
/// like every bridge token.
///
/// The key is an AGENT key, never "the Anthropic key" (user ruling
/// 2026-07-14): four providers speak here — Claude, ChatGPT, Gemini, and
/// Venice — one request shape each, one contract for all.
enum AgentProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai
    case google
    case venice

    var id: String { rawValue }

    /// The agent the person knows ("Claude"), not the vendor.
    var agent: String {
        switch self {
        case .anthropic: "Claude"
        case .openai:    "ChatGPT"
        case .google:    "Gemini"
        case .venice:    "Venice"
        }
    }

    /// The company that takes the key and sends the bill.
    var company: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai:    "OpenAI"
        case .google:    "Google"
        case .venice:    "Venice"
        }
    }

    /// Where a key comes from — the settings small print.
    var console: String {
        switch self {
        case .anthropic: "console.anthropic.com"
        case .openai:    "platform.openai.com"
        case .google:    "aistudio.google.com"
        case .venice:    "venice.ai"
        }
    }

    var placeholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai:    "sk-…"
        case .google:    "AIza…"
        case .venice:    "Paste your Venice key"
        }
    }

    /// Anthropic keeps its original vault key so keys saved before the
    /// providers arrived keep working.
    var vaultKey: String {
        self == .anthropic ? "token.anthropic-key" : "token.\(rawValue)-key"
    }

    var model: String {
        switch self {
        case .anthropic: "claude-opus-4-8"
        case .openai:    "gpt-4o"
        case .google:    "gemini-2.5-flash"
        case .venice:    "llama-3.3-70b"
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
        }
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Synthesizes a grounded answer over the retrieved candidates with the
    /// person's key, under the SAME shared instructions/prompt the on-device
    /// model answers with (OnDeviceModel.synthesisInstructions/Prompt) — the
    /// key buys a stronger model, not a different contract (prd §67). Runs
    /// on the active provider. The one divergence is length: the big model
    /// may run a few sentences.
    static func synthesize(query: String, candidates: [OnDeviceModel.Candidate]) async -> String? {
        guard let provider = AgentKey.active,
              let key = TokenVault.get(provider.vaultKey),
              !candidates.isEmpty else { return nil }

        let system = OnDeviceModel.synthesisInstructions(length: "a few plain sentences")
        let prompt = OnDeviceModel.synthesisPrompt(query: query, candidates: candidates)

        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": provider.model,
                "max_tokens": 1024,
                "system": system,
                "messages": [["role": "user", "content": prompt]],
            ])
        case .openai, .venice:
            // One OpenAI-compatible shape covers both — Venice's API speaks it.
            let base = provider == .openai ? "https://api.openai.com/v1"
                                           : "https://api.venice.ai/api/v1"
            request = URLRequest(url: URL(string: "\(base)/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": provider.model,
                "max_tokens": 1024,
                "messages": [["role": "system", "content": system],
                             ["role": "user", "content": prompt]],
            ])
        case .google:
            request = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(provider.model):generateContent")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "system_instruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": prompt]]]],
                "generationConfig": ["maxOutputTokens": 1024],
            ])
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            NSLog("[Casberi] AgentAnswer(%@): network failure", provider.rawValue)
            return nil
        }
        guard http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[Casberi] AgentAnswer(%@): HTTP %d", provider.rawValue, http.statusCode)
            return nil
        }
        let text = extractText(root, provider: provider)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Each provider's response shape, reduced to the answer text — or nil
    /// when the 200 carried a refusal instead of an answer.
    private static func extractText(_ root: [String: Any], provider: AgentProvider) -> String? {
        switch provider {
        case .anthropic:
            // A refusal is a valid 200 — treat it as "no answer", never as text.
            if let stop = root["stop_reason"] as? String, stop == "refusal" { return nil }
            guard let content = root["content"] as? [[String: Any]] else { return nil }
            return content
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
        case .openai, .venice:
            guard let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else { return nil }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty { return nil }
            return message["content"] as? String
        case .google:
            guard let candidates = root["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            return parts.compactMap { $0["text"] as? String }.joined()
        }
    }
}
