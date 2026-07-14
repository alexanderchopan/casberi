import Foundation

/// BYO-key (prd §67) — the person's own Anthropic API key powers a "try with
/// your key" they tap per answer. It is a VERB, never a fallback: nothing
/// leaves this iPhone until the tap, and what leaves goes straight from the
/// device to api.anthropic.com — Casberi runs no server and never sees a byte.
/// The key lives in the Keychain (TokenVault), like every bridge token.
enum ClaudeKey {
    static let vaultKey = "token.anthropic-key"

    static var isConfigured: Bool { TokenVault.get(vaultKey) != nil }

    static func set(_ key: String) {
        TokenVault.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: vaultKey)
    }

    static func clear() { TokenVault.delete(vaultKey) }

    /// The tail of the stored key for the settings line ("…3kQA") — enough to
    /// recognize it, never enough to leak it.
    static var hint: String {
        guard let key = TokenVault.get(vaultKey), key.count > 4 else { return "" }
        return "…" + key.suffix(4)
    }
}

/// The device→Anthropic call itself. Same contract as the on-device model:
/// grounded strictly on the candidates it is handed (the SAME retrieved things
/// the on-device answer saw), plain sentences, never invents a thing. Returns
/// nil on a missing key, a rejected key, a refusal, or a network failure — the
/// caller words that honestly.
enum ClaudeAnswer {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-4-8"

    /// Checks a key against Anthropic before it's saved — a Models API read,
    /// no tokens billed. True means Anthropic accepted the key.
    static func validate(_ key: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(model)")!)
        request.setValue(key.trimmingCharacters(in: .whitespacesAndNewlines),
                         forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Synthesizes a grounded answer over the retrieved candidates with the
    /// person's key, under the SAME shared instructions/prompt the on-device
    /// model answers with (OnDeviceModel.synthesisInstructions/Prompt) — the
    /// key buys a stronger model, not a different contract (prd §67). The one
    /// divergence is length: the big model may run a few sentences.
    static func synthesize(query: String, candidates: [OnDeviceModel.Candidate]) async -> String? {
        guard let key = TokenVault.get(ClaudeKey.vaultKey), !candidates.isEmpty else { return nil }

        let system = OnDeviceModel.synthesisInstructions(length: "a few plain sentences")
        let prompt = OnDeviceModel.synthesisPrompt(query: query, candidates: candidates)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            NSLog("[Casberi] ClaudeAnswer: network failure")
            return nil
        }
        guard http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[Casberi] ClaudeAnswer: HTTP %d", http.statusCode)
            return nil
        }
        // A refusal is a valid 200 — treat it as "no answer", never as text.
        if let stop = root["stop_reason"] as? String, stop == "refusal" { return nil }
        guard let content = root["content"] as? [[String: Any]] else { return nil }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
