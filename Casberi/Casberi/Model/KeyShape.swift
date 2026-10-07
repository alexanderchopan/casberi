import Foundation

/// Whose key a pasted string is, by the prefix its issuer stamps on it (prd
/// §1162).
///
/// **Only to say "that's another service's key", never to say a key is
/// good.** A prefix is a fact the issuer publishes and a key carries on its
/// face, so a Stripe key pasted into Linear's field is a mistake the app can
/// name before any request — the person has three dashboards open and copied
/// from the wrong one. The reverse claim is not available: many services
/// (Readwise, Todoist, Vercel, Polar, Dodo) stamp nothing, and §418–§452's
/// rule stands — a guessed prefix "reads as a validation rule". So an
/// unrecognised string is NEVER refused here; the provider's own answer
/// decides that.
///
/// Prefixes are the issuers' published ones (the `SecretScan.apiKeyPattern`
/// set and each seat's own placeholder), longest first so `sk-ant-` is
/// Anthropic's before any shorter `sk-` could claim it. A bare `sk-` or `sk_`
/// is deliberately absent: OpenAI, Splits and others share it.
/// Foundation-only, compiled whole by `scripts/key-shape-selftest.sh`.
enum KeyShape {
    /// (prefix, the catalogue name of the service that issues it).
    static let prefixes: [(prefix: String, service: String)] = [
        ("nostr+walletconnect://", "Lightning"),
        ("github_pat_", "GitHub"), ("ghp_", "GitHub"), ("gho_", "GitHub"),
        ("ghu_", "GitHub"), ("ghs_", "GitHub"),
        ("sk_live_", "Stripe"), ("sk_test_", "Stripe"), ("rk_live_", "Stripe"),
        ("rk_test_", "Stripe"), ("pk_live_", "Stripe"), ("pk_test_", "Stripe"),
        ("cal_live_", "Cal.com"), ("cal_test_", "Cal.com"),
        ("lin_api_", "Linear"),
        ("sntryu_", "Sentry"), ("sntrys_", "Sentry"),
        ("glpat-", "GitLab"),
        ("sk-ant-", "Anthropic"), ("sk-or-", "OpenRouter"), ("sk-proj-", "OpenAI"),
        ("xai-", "Grok"),
        ("phx_", "PostHog"), ("phc_", "PostHog"),
        ("xoxb-", "Slack"), ("xoxp-", "Slack"),
        ("ntn_", "Notion"),
        ("AKIA", "AWS"),
        ("AIza", "Google"),
    ].sorted { $0.prefix.count > $1.prefix.count }

    /// The service a key's prefix names, or nil when it names none.
    static func issuer(of key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefixes.first { trimmed.hasPrefix($0.prefix) }?.service
    }

    /// The OTHER service a pasted key belongs to, when its prefix says so —
    /// nil when it is this service's, or carries no prefix anyone publishes.
    static func belongsElsewhere(_ key: String, pastedInto service: String) -> String? {
        guard let issuer = issuer(of: key), issuer != service else { return nil }
        return issuer
    }

    /// The sentence for it, said before anything is sent.
    static func sentence(issuer: String, service: String) -> String {
        String(localized: "That's a \(issuer) key. \(service) needs a \(service) key.")
    }
}
