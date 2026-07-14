import Foundation

/// The AI providers Casberi can answer with on the BYO-key path (prd §67).
/// The key is a VERB the person taps per answer — nothing leaves this iPhone
/// until the tap, and what leaves goes straight from the device to the
/// provider's own API. Casberi runs no server and never sees the key.
///
/// Adding a provider is one case in each switch below — its label, flagship
/// model, key console, and key shape. The wire details (endpoint, headers,
/// request/response shape) live in `AIAnswer`, so every provider answers
/// under the SAME grounded contract as the on-device model.
enum AIProvider: String, CaseIterable {
    case anthropic
    case openai
    case google

    /// The short word the UI shows for a saved key — the model family the
    /// person recognizes, not the company name.
    var label: String {
        switch self {
        case .anthropic: "Claude"
        case .openai:    "GPT"
        case .google:    "Gemini"
        }
    }

    /// The flagship model the key buys — a stronger answer than on-device,
    /// under the same grounded contract (prd §67).
    var model: String {
        switch self {
        case .anthropic: "claude-opus-4-8"
        case .openai:    "gpt-5"
        case .google:    "gemini-2.5-pro"
        }
    }

    /// Where to get a key — named in the footnote so the person can find one.
    var console: String {
        switch self {
        case .anthropic: "console.anthropic.com"
        case .openai:    "platform.openai.com"
        case .google:    "aistudio.google.com"
        }
    }

    /// Recognize a provider from the shape of a pasted key. Every provider
    /// stamps its keys with a distinct prefix, so one paste picks the provider
    /// with no menu to tap. Order matters: Anthropic's `sk-ant-` is a stricter
    /// case of OpenAI's `sk-`, so it must be checked first. nil when the shape
    /// matches nobody — the caller words that honestly (no silent guess).
    static func detect(_ key: String) -> AIProvider? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.hasPrefix("sk-ant-") { return .anthropic }
        if k.hasPrefix("AIza")    { return .google }
        if k.hasPrefix("sk-")     { return .openai }   // sk-, sk-proj-, sk-svcacct-…
        return nil
    }
}
