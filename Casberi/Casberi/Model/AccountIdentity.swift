import Foundation

/// WHOSE account a connection reads (prd §1162) — "acme" under GitHub,
/// "Acme Inc" under Stripe — drawn under the name on its account page.
///
/// A key carries no name, so "Reading" was all a page could say, and a person
/// with a work and a personal account could not tell which key they had
/// pasted until the wrong repositories arrived. Several seats already learned
/// the name and kept it to themselves (Stripe's account, Polar's and Sentry's
/// organisation, PostHog's project, Wise's profile); the token bridges learn
/// it from the provider's own "who am I" read at connect
/// (`TokenWhoAmI`). This is the one place a page asks.
///
/// Keyed by the seat id, in the app-group defaults, like `AccountNotes`. A
/// name is a fact about the account, never a secret, and never part of the key.
enum AccountIdentity {
    static let key = "account.identity.v1"

    static var defaults: UserDefaults { SharedStore.groupDefaults ?? .standard }

    /// The account's name, from this store or the seat's own record. Reads
    /// `UserDefaults` only — never the Keychain, never the network — so a page
    /// may call it from `onAppear`.
    static func name(for seat: String) -> String? {
        if let stored = (defaults.dictionary(forKey: key) as? [String: String])?[seat], !stored.isEmpty {
            return stored
        }
        let held: String? = switch seat {
        case TokenBridge.stripe.bridgeID:  StripeAccount.accountName
        case TokenBridge.polar.bridgeID:   PolarAccount.orgName
        case TokenBridge.sentry.bridgeID:  SentryAccount.orgName
        case TokenBridge.posthog.bridgeID: PostHogAccount.projectName
        case TokenBridge.wise.bridgeID:    WiseAuth.profileName
        default: nil
        }
        guard let held, !held.isEmpty else { return nil }
        return held
    }

    static func set(_ name: String?, for seat: String) {
        var book = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { book.removeValue(forKey: seat) } else { book[seat] = trimmed }
        if book.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(book, forKey: key) }
        NotificationCenter.default.post(name: changed, object: seat)
    }

    /// Posted with the seat id when a name is learned — the page that is open
    /// re-reads, since the name arrives a beat after the connect does.
    static let changed = Notification.Name("AccountIdentity.changed")
}

/// The token bridges' "who am I" (prd §1162): one read per provider that
/// documents one, on the host the bridge already reads, so nothing new is
/// reached. Nil where a provider has none (Readwise, Bitrefill, Privacy, Dodo,
/// PagerDuty) or the read fails — a missing name draws nothing, never a guess.
enum TokenWhoAmI {
    static func name(_ bridge: TokenBridge, token: String) async -> String? {
        switch bridge {
        case .github:
            let me = await IngestSupport.getJSON("https://api.github.com/user", auth: "Bearer \(token)") as? [String: Any]
            return me?["login"] as? String
        case .gitlab:
            let me = await IngestSupport.getJSON("https://gitlab.com/api/v4/user",
                                                 headers: ["PRIVATE-TOKEN": token]) as? [String: Any]
            return me?["username"] as? String
        case .calendly:
            let me = await IngestSupport.getJSON("https://api.calendly.com/users/me", auth: "Bearer \(token)") as? [String: Any]
            let resource = me?["resource"] as? [String: Any]
            return (resource?["name"] as? String) ?? (resource?["email"] as? String)
        case .notion:
            let me = await IngestSupport.getJSON("https://api.notion.com/v1/users/me", auth: "Bearer \(token)",
                                                 headers: ["Notion-Version": "2022-06-28"]) as? [String: Any]
            let bot = me?["bot"] as? [String: Any]
            return (bot?["workspace_name"] as? String) ?? (me?["name"] as? String)
        case .todoist:
            let me = await IngestSupport.getJSON("https://api.todoist.com/api/v1/user", auth: "Bearer \(token)") as? [String: Any]
            return (me?["full_name"] as? String) ?? (me?["email"] as? String)
        case .raindrop:
            let me = await IngestSupport.getJSON("https://api.raindrop.io/rest/v1/user", auth: "Bearer \(token)") as? [String: Any]
            let user = me?["user"] as? [String: Any]
            return (user?["fullName"] as? String) ?? (user?["email"] as? String)
        case .calcom:
            let me = await IngestSupport.getJSON("https://api.cal.com/v2/me", auth: "Bearer \(token)",
                                                 headers: ["cal-api-version": "2026-05-01"]) as? [String: Any]
            let data = me?["data"] as? [String: Any]
            return (data?["username"] as? String) ?? (data?["email"] as? String)
        // The account the token reads, not the person: Cloudflare keys are
        // scoped to accounts, and the account's name is what its dashboard
        // leads with. `account_settings:read` is one of the door's four reads.
        case .cloudflare:
            let page = await IngestSupport.getJSON("https://api.cloudflare.com/client/v4/accounts?per_page=1",
                                                   auth: "Bearer \(token)") as? [String: Any]
            return ((page?["result"] as? [[String: Any]])?.first)?["name"] as? String
        case .trello:
            guard let key = TokenVault.get(TrelloAuth.keyVaultKey) else { return nil }
            let me = await IngestSupport.getJSON("https://api.trello.com/1/members/me",
                                                 auth: TrelloAuth.header(key: key, token: token)) as? [String: Any]
            return (me?["fullName"] as? String) ?? (me?["username"] as? String)
        default:
            return nil
        }
    }
}
