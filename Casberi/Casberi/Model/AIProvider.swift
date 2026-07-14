import Foundation

/// The AI providers Casberi can answer with on the BYO-key path (prd §67).
/// A key is a VERB the person taps per answer — nothing leaves this iPhone
/// until the tap, and what leaves goes straight from the device to the
/// provider's own API. Casberi runs no server and never sees the key.
///
/// Keys are per-provider now (ruling 2026-07-14): connect several and the
/// composer offers one "Try with <name>" chip per connected provider — the
/// chip names exactly where the question goes. Adding a provider is one case
/// in each switch below plus the wire switches in `AIAnswer`.
enum AIProvider: String, CaseIterable {
    case anthropic
    case openai
    case google
    case venice

    /// The short word the UI shows — the model family (or service) the person
    /// recognizes, not the company name.
    var label: String {
        switch self {
        case .anthropic: "Claude"
        case .openai:    "GPT"
        case .google:    "Gemini"
        case .venice:    "Venice"
        }
    }

    /// The flagship model the key buys — a stronger answer than on-device,
    /// under the same grounded contract (prd §67).
    var model: String {
        switch self {
        case .anthropic: "claude-opus-4-8"
        case .openai:    "gpt-5"
        case .google:    "gemini-2.5-pro"
        case .venice:    "llama-3.3-70b"
        }
    }

    /// Where to get a key — named in setup copy so the person can find one.
    var console: String {
        switch self {
        case .anthropic: "console.anthropic.com"
        case .openai:    "platform.openai.com"
        case .google:    "aistudio.google.com"
        case .venice:    "venice.ai"
        }
    }

    /// The catalog app this provider's key lives under (store entry, ruling
    /// 2026-07-14) — and its BridgeStore seat id, so a connected key seats the
    /// app like any other bridge.
    var offerName: String {
        switch self {
        case .anthropic: "Claude"
        case .openai:    "ChatGPT"
        case .google:    "Gemini"
        case .venice:    "Venice"
        }
    }

    var seatID: String {
        switch self {
        case .anthropic: "claude"
        case .openai:    "gpt"
        case .google:    "gemini"
        case .venice:    "venice"
        }
    }

    /// This provider's Keychain slot — one per provider, so several keys
    /// coexist (TokenVault.deleteAll still sweeps them all).
    var slotKey: String { "token.ai.\(rawValue)" }

    /// Recognize a provider from the shape of a pasted key — the settings
    /// overview's one-field paste. Order matters: Anthropic's `sk-ant-` is a
    /// stricter case of OpenAI's `sk-`. Venice keys carry no distinctive
    /// prefix, so they connect from Venice's own app page (where the provider
    /// is known without guessing) — never from shape. nil when the shape
    /// matches nobody; the caller words that honestly (no silent guess).
    static func detect(_ key: String) -> AIProvider? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.hasPrefix("sk-ant-") { return .anthropic }
        if k.hasPrefix("AIza")    { return .google }
        if k.hasPrefix("sk-")     { return .openai }   // sk-, sk-proj-, sk-svcacct-…
        return nil
    }
}
