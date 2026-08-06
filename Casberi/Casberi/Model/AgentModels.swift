import Foundation

/// Which model a key answers with (2026-08-06) — read from the provider
/// instead of pinned in our source.
///
/// `AgentProvider.defaultModel` is a hardcoded id per provider, and the class
/// of bug that creates is already in this codebase's history: the Grok pin
/// shipped as `grok-4`, an id xAI's model list does not contain, so EVERY
/// request from that provider would have failed the moment anybody added a
/// key — and it survived review because no key existed to fail against. It was
/// caught by reading, hours later. `gpt-4o` and `claude-opus-4-8` carry the
/// same exposure with a slower fuse: a pin doesn't announce that it has aged
/// out, it just starts 404ing, and a 404 surfaces as `providerError(404)`,
/// which the composer words as "your agent had trouble answering — try again."
///
/// So: the provider's own list is the authority, the pin is the fallback for
/// when that read fails, and the person can choose. Choosing is the secondary
/// benefit and a real one — the pins are all frontier-tier, and plenty of what
/// this app asks a key to do (naming a screenshot from its OCR text, digesting
/// a thread) is work a cheap fast model does perfectly for a fraction of the
/// cost.
///
/// **UNMEASURED against every provider.** Each endpoint below is read off
/// public documentation; no key for any of these is stored on the build host,
/// and there is no egress to most of them. Every read fails to nil, and nil
/// means "keep using the pin" — so a wrong endpoint costs the picker, never
/// the answer path.
enum AgentModelStore {
    private static let prefix = "agent.model."

    /// The model this provider should answer with — the person's choice, or
    /// nil to mean "whatever `defaultModel` says". Nil rather than resolving
    /// here so the fallback lives in exactly one place (`AgentProvider.model`).
    static func chosen(_ provider: AgentProvider) -> String? {
        let value = UserDefaults.standard.string(forKey: prefix + provider.rawValue)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func set(_ model: String?, for provider: AgentProvider) {
        let key = prefix + provider.rawValue
        guard let model, !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespaces), forKey: key)
    }

    /// DEBUG hook: `-agentModel "<provider>:<model id>"`, or `clear` to drop
    /// every choice. Splits on the FIRST colon — a model id may contain one
    /// (`openai/gpt-4o`, and every OpenRouter id does), a provider raw value
    /// never can.
    static func seedFromLaunchArgs() {
        guard let raw = UserDefaults.standard.string(forKey: "agentModel") else { return }
        if raw == "clear" {
            AgentProvider.allCases.forEach { set(nil, for: $0) }
            return
        }
        guard let colon = raw.firstIndex(of: ":"),
              let provider = AgentProvider(rawValue: String(raw[..<colon])) else { return }
        set(String(raw[raw.index(after: colon)...]), for: provider)
    }
}

/// One model a provider offers.
struct AgentModelInfo: Identifiable, Equatable, Sendable {
    /// The id to send in a request — the only field that has to be right.
    let id: String
    /// A human label when the provider gives one, else the id repeated.
    let label: String
}

enum AgentModels {

    /// Asks the provider what it offers. Returns nil when the read failed for
    /// any reason — the caller keeps the pin and says the list is unavailable,
    /// which is a different sentence from "this provider offers nothing".
    ///
    /// Bankr returns an EMPTY list rather than nil, and that distinction is
    /// load-bearing: it isn't a model, it's an agent that picks its own model
    /// per job (`defaultModel` there names no request at all), so there is
    /// genuinely nothing to choose and the screen should say so rather than
    /// showing a broken picker.
    static func list(provider: AgentProvider, key: String) async -> [AgentModelInfo]? {
        var request: URLRequest
        switch provider {
        case .bankr:
            return []
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .google:
            request = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .venice:
            request = URLRequest(url: URL(string: "https://api.venice.ai/api/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .openrouter:
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .grok:
            request = URLRequest(url: URL(string: "https://api.x.ai/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 20
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let models: [AgentModelInfo]
        switch provider {
        case .google:
            // Gemini names models "models/gemini-2.5-flash" and the request
            // path wants the bare id, so the prefix is stripped here rather
            // than at every call site. Only models that can actually answer a
            // generateContent call are offered — the list also carries
            // embedding and tuning endpoints, and picking one of those would
            // fail every question with a 400 that reads like a broken app.
            let entries = root["models"] as? [[String: Any]] ?? []
            models = entries.compactMap { entry in
                guard let name = entry["name"] as? String else { return nil }
                let methods = entry["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains("generateContent") else { return nil }
                let id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                return AgentModelInfo(id: id, label: entry["displayName"] as? String ?? id)
            }
        default:
            // Anthropic, OpenAI, Venice, OpenRouter and xAI all answer the
            // same `{ data: [ { id, … } ] }` envelope.
            let entries = root["data"] as? [[String: Any]] ?? []
            models = entries.compactMap { entry in
                guard let id = entry["id"] as? String else { return nil }
                let label = entry["display_name"] as? String
                    ?? entry["name"] as? String
                    ?? id
                return AgentModelInfo(id: id, label: label)
            }
        }
        return dedupe(usable(models, for: provider))
    }

    /// Drops what can't answer a chat request. OpenAI's list is the reason
    /// this exists: it carries whisper, tts, dall-e, embeddings and moderation
    /// alongside the chat models, and every one of them is a confidently
    /// offered choice that fails on the first question.
    ///
    /// Deliberately a DENYLIST of known non-chat families rather than an
    /// allowlist of known-good prefixes: an allowlist silently hides the next
    /// model a provider ships, which is the exact failure this whole file
    /// exists to end.
    private static func usable(_ models: [AgentModelInfo],
                               for provider: AgentProvider) -> [AgentModelInfo] {
        guard provider == .openai || provider == .venice || provider == .openrouter else {
            return models
        }
        let excluded = ["whisper", "tts", "dall-e", "text-embedding", "embedding",
                        "moderation", "omni-moderation", "davinci", "babbage",
                        "codex", "-audio", "-realtime", "-transcribe", "-tts",
                        "upscal", "image", "stable-diffusion", "flux"]
        return models.filter { model in
            let id = model.id.lowercased()
            return !excluded.contains { id.contains($0) }
        }
    }

    /// Same id twice is possible on OpenRouter (it lists free and paid
    /// variants that normalize to one id on some plans); first wins, order
    /// otherwise preserved as the provider returned it.
    private static func dedupe(_ models: [AgentModelInfo]) -> [AgentModelInfo] {
        var seen = Set<String>()
        return models.filter { seen.insert($0.id).inserted }
    }
}
