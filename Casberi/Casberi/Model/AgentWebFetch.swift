import Foundation

/// Reading the page behind a saved link, on the person's own key (2026-08-20).
///
/// The corpus is full of links whose words were never stored. `LinkTitle`
/// fetches a `<head>` and `FeedArticleText` reads the body for RSS and
/// Substack rows alone — so for most saved links the keyed agent grounds on a
/// title, a domain and at best a 300-character excerpt. Ask it "what did that
/// piece actually argue?" and it answers from the headline, fluently, which is
/// the failure mode this codebase fears most: a plausible answer over evidence
/// nobody has.
///
/// Anthropic's `web_fetch` is a SERVER tool — the API fetches the page inside
/// the same request and inserts the text, so nothing here opens a connection,
/// no host of ours joins `NetworkReach`, and the round costs one request rather
/// than two. What makes it usable here rather than merely available is its own
/// security rule: **it can only fetch a URL that already appeared in the
/// conversation.** Claude may not construct one. So the reachable set is
/// exactly the set of links this person saved and the tools chose to show —
/// which is the grounding contract restated as a wire constraint, and the
/// reason this is the one web capability that does not widen what a keyed
/// answer is allowed to draw on.
///
/// **Where the URLs come from, and where they deliberately don't.** They ride
/// the CORPUS TOOL results (`AgentCorpusTools.serialize`), never the numbered
/// candidate list. Two reasons, both load-bearing: the candidate list is shared
/// verbatim with the on-device model (`OnDeviceModel.numberedCandidates` — one
/// contract, two engines), so adding a line there changes what the free path
/// reads for a capability it does not have; and a URL costs ~20 tokens, so
/// printing sixteen of them on every ask spends real money to enable a fetch
/// the model usually doesn't want. A tool result carries a URL only for a thing
/// the model went and asked about.
///
/// **The policy below is the gate, and it is a gate rather than a formality.**
/// A `Thing.content` is whatever a bridge stamped on it, so the candidate set
/// includes `casberi://` deep links, `obsidian://` vault doors, `file://`
/// paths, signed CDN URLs that carry a token in their query, and — on a
/// self-hosted PostHog or a followed feed — private hostnames. Handing any of
/// those to somebody else's fetcher is a leak, a wasted round, or both. Every
/// rule here has a real row in this corpus behind it.
enum AgentWebFetch {

    /// The tool version. `web_fetch_20260318` is current and adds dynamic
    /// filtering — Claude writes and runs code to keep the relevant part of a
    /// page before it reaches the context window, which is what makes a large
    /// article affordable at all. That filtering rides the code-execution tool,
    /// which the API enables ITSELF for the request: declaring
    /// `code_execution` beside this would hand the model a second execution
    /// environment and is explicitly not wanted.
    ///
    /// No beta header (verified against the tool's own documentation
    /// 2026-08-20, alongside `web_search_20260209`, which this file's sibling
    /// declaration has used unheadered since it shipped).
    static let toolType = "web_fetch_20260318"

    /// How many pages one answer may read, and how much of each may land.
    ///
    /// **Both are BILLING bounds, like `AgentCorpusTools.maxRounds`, and the
    /// arithmetic is why they are this small.** Fetched text is input tokens on
    /// the round that fetched it and on every round after it. A typical article
    /// is ~2,500 tokens; a large documentation page ~25,000; a research-paper
    /// PDF ~125,000. Unbounded, one saved PDF turns a question into a dollar.
    /// At 12,000 the cap TRUNCATES rather than failing, so the worst case is a
    /// partial read of something enormous rather than a broken answer, and two
    /// uses covers the shape this exists for — read the piece, and read the one
    /// it answers — without letting a model that has decided to survey
    /// something walk the whole corpus.
    static let maxUses = 2
    static let maxContentTokens = 12_000

    /// The documented ceiling: a longer URL comes back `url_too_long`. Checked
    /// here so a URL that could only ever fail is never printed — paying input
    /// tokens to show the model a link it cannot use is the worst of both.
    static let urlLengthCap = 250

    /// Query keys whose value is a credential rather than a locator. A signed
    /// CDN link is a real shape in this corpus — Instagram's `og:image` is
    /// signed and expires in days (§395), Snapchat's memory downloads are
    /// signed and expire in seven — and a permalink is never signed, so
    /// dropping these costs nothing real.
    private static let credentialQueryKeys: Set<String> = [
        "token", "access_token", "id_token", "refresh_token", "auth", "authorization",
        "key", "api_key", "apikey", "secret", "client_secret", "password", "passwd",
        "sig", "signature", "session", "sessionid", "session_id", "sid", "code",
    ]

    /// Hosts that are this person's own machine or network. Anthropic refuses
    /// these itself (`url_not_allowed` covers private addresses), so the reason
    /// to check is not that the fetch would succeed — it is that printing
    /// `http://192.168.1.14:8000/notes` into somebody else's context window
    /// tells them the shape of a private network to buy nothing at all.
    private static func isPrivateHost(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host.hasSuffix(".local") || host.hasSuffix(".internal") || host.hasSuffix(".home") {
            return true
        }
        if host == "::1" || host.hasPrefix("[") { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("0.") { return true }
        if host.hasPrefix("192.168.") || host.hasPrefix("169.254.") { return true }
        // 172.16.0.0 – 172.31.255.255, the private range that needs arithmetic
        // rather than a prefix — 172.15 and 172.32 are public.
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    /// The URL to show the model, or nil to show none.
    ///
    /// Returns the ORIGINAL string when it passes, never a re-serialized one: a
    /// URL that survives a parse-and-rebuild round trip is not always the same
    /// URL (percent-encoding is not canonical), and the model is about to hand
    /// this string back for a fetch, where a byte that changed is a page that
    /// 404s.
    ///
    /// Nil is the right answer far more often than it looks — most things in
    /// this corpus are not links at all.
    static func fetchable(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= urlLengthCap else { return nil }
        // A whitespace-bearing string is not one URL, whatever else it is.
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        guard let components = URLComponents(string: trimmed) else { return nil }
        // http and https only. Every other scheme in this corpus is a LOCAL
        // door — `casberi://thing/…`, `obsidian://open?vault=…`,
        // `photos-redirect://`, `shareddocuments://`, `file://` — and a remote
        // fetcher can do nothing with one but be told it exists.
        guard let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        guard let host = components.host, !host.isEmpty, host.contains(".") || host == "localhost"
        else { return nil }
        guard !isPrivateHost(host) else { return nil }
        // `user:pass@host` — a credential in the authority, which no permalink
        // has and which would be handed over verbatim.
        guard components.user == nil, components.password == nil else { return nil }
        for item in components.queryItems ?? [] {
            if credentialQueryKeys.contains(item.name.lowercased()) { return nil }
        }
        return trimmed
    }

    /// The declaration Anthropic's `tools` array takes. Citations stay OFF (the
    /// default): the app already paints its own grounding rows from `PICKS:`,
    /// and a citation arrives as extra `text` blocks carrying a `citations`
    /// array that this app's stream reader concatenates as prose — so turning
    /// them on would spend tokens to produce text that renders identically.
    static func anthropicDeclaration() -> [String: Any] {
        ["type": toolType,
         "name": "web_fetch",
         "max_uses": maxUses,
         "max_content_tokens": maxContentTokens]
    }

    /// What the system prompt says about it. Short on purpose, and it says the
    /// bound out loud for the same reason `AgentCorpusTools`'s guidance does: a
    /// model that does not know it may read two pages plans to read six, gets
    /// refused, and answers from a survey it never finished.
    static let guidance = """


        Some of the things your tools return carry the web address they came \
        from. When the answer depends on what a page actually SAYS rather than \
        on its title, you may read it with web_fetch — but only an address you \
        have already been shown, at most \(maxUses) per answer, and only when \
        the saved excerpt genuinely isn't enough.
        """
}
