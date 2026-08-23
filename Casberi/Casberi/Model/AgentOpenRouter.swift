import Foundation

/// The four things OpenRouter can do that no direct provider in this catalog
/// can (2026-08-23, prd §459), plus the sidecar that remembers what a chosen
/// model actually IS.
///
/// Every other agent seat here is one company answering with its own models, so
/// the only choices are the key and the pin. OpenRouter is a router: one key
/// reaches every model there is, and the request body carries policy — WHO may
/// serve it, what happens when the first choice is dead, whether the router may
/// go and read the open web. That policy is where the remaining headroom was,
/// and every knob below is a promise this app can make on somebody's behalf
/// that it cannot make anywhere else.
///
/// **PRIVATE ROUTING IS THE ONE THAT MATTERS, and it is ON by default.**
/// `provider.data_collection = "deny"` tells OpenRouter to route only to
/// backends that do not retain or train on the prompt — which is this app's own
/// pitch expressed as a wire constraint rather than a paragraph on a settings
/// screen. It is the strongest privacy statement available anywhere in the BYOK
/// catalog, because it is enforced by somebody else's routing table instead of
/// by our conduct (the `CursorFetch` grade, one rung up).
///
/// It has a real cost and the cost is NOT hidden: a model whose every backend
/// retains prompts becomes unroutable, and OpenRouter answers **404**. So this
/// file never quietly retries without the promise — a silent retry is the
/// promise broken at exactly the moment it mattered — and `AgentAnswer` words
/// that 404 as its own failure naming both of its causes (a retired model id, or
/// no backend that would agree), because from a status code alone the two are
/// indistinguishable and asserting either would be a guess printed as a fact.
///
/// **WEB SEARCH IS OFF by default, and that asymmetry is deliberate.** Private
/// routing only ever narrows what happens to a question already being sent;
/// search sends the question somewhere new AND bills per result. `searchesWeb`
/// has been false for OpenRouter since BYOK shipped, with `AgentProvider`'s own
/// comment naming the reason — the search suffix "this app doesn't append" —
/// so this is that named gap closed as an explicit opt-in rather than a
/// capability quietly switched on.
///
/// **FALLBACK IS ALLOWED ONLY BECAUSE THE ANSWER NAMES WHO WROTE IT.** A chain
/// that silently answers on a different model than the one somebody picked is
/// fake status; the same pass that added the chain put the answering model on
/// the provenance badge whenever it differs from the choice, so the two are one
/// feature and neither should ship without the other.
///
/// **Pure by design** — Foundation only, no `URLSession`, no SwiftData — so
/// `agent-keyed-selftest.sh` compiles it WHOLE and unmodified. **UNMEASURED:
/// no OpenRouter key is stored on this build host and there is no egress to
/// `openrouter.ai` from it**, so every shape below is documentation-derived.
/// Each one fails safe: an ignored body key changes nothing, a refused route is
/// a worded failure, and an unknown fact reads as the conservative answer.
enum AgentOpenRouter {

    /// The router's own "pick something sensible" model — what this seat has
    /// pinned since it shipped, and the reason `seesImages`/`searchesWeb` were
    /// false: the model it lands on can vary, so nothing about it may be
    /// claimed in advance.
    static let autoModel = "openrouter/auto"

    static func isAuto(_ model: String) -> Bool { model == autoModel }

    // MARK: - Stored choices

    private static let privateRoutingKey = "openrouter.privateRouting"
    private static let webSearchKey      = "openrouter.webSearch"

    /// Route only to backends that do not retain or train on the prompt.
    ///
    /// **Defaults to TRUE, and the spelling is what makes that work.** A
    /// `UserDefaults.bool(forKey:)` on an unset key is `false`, so the stored
    /// value is read as an *object* and only a real stored `false` turns it off
    /// — otherwise the default here would be a lie for every install that has
    /// never opened the screen, which is all of them.
    static var privateRouting: Bool {
        get { (UserDefaults.standard.object(forKey: privateRoutingKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: privateRoutingKey) }
    }

    /// Let the router search the open web when the saved things fall short.
    /// Off unless somebody says otherwise: it is billed per result on top of the
    /// model's own tokens, and an ask that silently costs more than the person
    /// expected is the one surprise a spending screen cannot undo.
    static var webSearch: Bool {
        get { UserDefaults.standard.bool(forKey: webSearchKey) }
        set { UserDefaults.standard.set(newValue, forKey: webSearchKey) }
    }

    // MARK: - Body fragments (pure)

    /// The `provider` block, or nil when there is nothing to ask for.
    ///
    /// Only `data_collection` is sent. `sort`, `order` and `quantizations` are
    /// all real and all decline for the same reason: they express a preference
    /// this app has no basis for on somebody else's behalf, and each one
    /// narrows the routable set further, which is more 404s bought with
    /// nothing. `allow_fallbacks` is deliberately left at OpenRouter's own
    /// default (true) — turning it off would make a single busy backend look
    /// like an outage.
    static func providerPreferences(privateRouting: Bool) -> [String: Any]? {
        guard privateRouting else { return nil }
        return ["data_collection": "deny"]
    }

    /// The web plugin, or nil when search is off.
    ///
    /// **The `:online` model-id suffix was measured against this and REJECTED.**
    /// It is OpenRouter's documented shorthand for exactly this plugin, and it
    /// is one string instead of a body key — but a suffix does not compose:
    /// every free model on the platform is already suffixed (`…:free`), so
    /// `deepseek/deepseek-chat-v3:free:online` is a second variant on an id that
    /// has one, and the free tier is precisely where somebody is most likely to
    /// want search. The plugin form composes with any id, including one this
    /// app has never seen.
    ///
    /// `max_results` is a BILLING bound and the arithmetic is why it is 3:
    /// results are priced per result, so the default of 5 makes every searched
    /// ask cost noticeably more than the model it ran on. Three is enough to
    /// answer "what happened since I saved this" and small enough that a
    /// searched ask stays in the same order of magnitude as an ordinary one.
    static func webSearchPlugins(webSearch: Bool) -> [[String: Any]]? {
        guard webSearch else { return nil }
        return [["id": "web", "max_results": webSearchResults]]
    }

    static let webSearchResults = 3

    /// The ordered chain to try, or nil when there is nothing to fall back
    /// FROM.
    ///
    /// A pinned model that has been retired 404s, and `AgentModels` exists
    /// because that failure is silent until somebody asks a question. Here the
    /// router itself can carry the recovery: try the pin, then `openrouter/auto`,
    /// which is by construction never a dead id.
    ///
    /// nil for `openrouter/auto` itself — it already routes, so a chain would
    /// name it twice — and nil for an empty id, which is not a choice.
    ///
    /// **Sent ALONGSIDE `model`, never instead of it.** OpenRouter documents
    /// both spellings and this app cannot test which one this account's version
    /// honours; sending both means the chain works where `models` is read and
    /// behaviour is exactly unchanged where it is ignored. The failure mode of
    /// guessing wrong is an unrecognized body key, which is the 400 risk this
    /// codebase refuses to take on the answer path.
    static func fallbackChain(_ model: String) -> [String]? {
        guard !model.isEmpty, !isAuto(model) else { return nil }
        return [model, autoModel]
    }

    /// Whether a `cache_control` breakpoint means anything to this model.
    ///
    /// Prompt caching (prd §415) is Anthropic's own wire feature, and OpenRouter
    /// passes those breakpoints through to Anthropic-backed models unchanged —
    /// so a person who pins `anthropic/claude-…` here should stop re-paying for
    /// the same sixteen candidates every tool round, exactly as they would on a
    /// direct key. Every other family either caches automatically with nothing
    /// to send or does not cache at all, and in both cases the breakpoint is
    /// dead weight in the body.
    ///
    /// `openrouter/auto` is excluded, and that is the whole reason this is a
    /// function of the model rather than of the provider: the router picks after
    /// the request is built, so at the moment the body is written nobody knows
    /// where it will land.
    static func honoursCacheControl(_ model: String) -> Bool {
        model.hasPrefix("anthropic/")
    }

    // MARK: - Generation receipts

    /// Where a finished answer's real price is read back from — the one place in
    /// this catalog a provider states dollars for a SINGLE request (prd §459).
    ///
    /// `AgentSpend` records tokens and refuses to price them, and `/v1/auth/key`
    /// answers with a LIFETIME total for the key — which cannot separate what
    /// Casberi asked from everything else the same key is used for. That
    /// separation is the whole complaint `AgentSpend`'s own doc opens with. This
    /// endpoint closes it: given the id the stream already carried, OpenRouter
    /// states what that one generation cost, so the receipt can finally say what
    /// THIS APP spent rather than what the key has spent.
    static func generationURL(id: String) -> URL? {
        guard !id.isEmpty,
              let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://openrouter.ai/api/v1/generation?id=\(escaped)")
    }

    /// The cost out of a `/v1/generation` body, or nil when it isn't there.
    ///
    /// `total_cost` is the field that includes everything — the model's tokens
    /// AND any web-search results the plugin billed — which is why it is read
    /// rather than summing the token halves ourselves. A NEGATIVE reading is
    /// refused rather than clamped: a generation cannot earn money, so a
    /// negative is a shape we do not understand, and understanding it wrongly
    /// would quietly subtract from a running total.
    static func generationCost(json: [String: Any]) -> Double? {
        guard let data = json["data"] as? [String: Any] else { return nil }
        guard let cost = numeric(data["total_cost"]), cost >= 0 else { return nil }
        return cost
    }

    /// OpenRouter states money as a JSON number in some payloads and a string in
    /// others (its `/models` pricing is entirely strings). Read both, so a
    /// change of encoding cannot silently turn every price into "not reported".
    static func numeric(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let text = raw as? String { return Double(text) }
        return nil
    }
}

/// What we knew about the model somebody CHOSE, at the moment they chose it
/// (2026-08-23, prd §459).
///
/// `AgentModelStore` keeps the id, which is all the wire needs. But the id is
/// also the only thing anything else had, so three separate honest refusals were
/// stacked on top of it: a keyed answer never sent a screenshot's own picture to
/// OpenRouter, the monthly ceiling paused a librarian pinned to a model that
/// costs nothing, and the picker offered four hundred names with no way to tell
/// a free one from a frontier one. All three were correct while `openrouter/auto`
/// was the only possibility — the router picks after the fact, so nothing may be
/// claimed in advance — and all three became needlessly conservative the moment
/// somebody pinned a specific model whose own listing states its modalities and
/// its price.
///
/// **The id is the guard, and it is what keeps this from becoming fake status.**
/// Facts are stored against the id they describe and handed back ONLY when that
/// id is still the current choice. A launch-arg pin, a re-pick, a provider
/// renaming a model — each leaves facts describing something else, and every one
/// of them resolves to nil, which falls back to the conservative answer the app
/// gave before this existed. Being wrong here means sending a private photograph
/// to a text-only model that has no use for it, so the failure has to land on the
/// safe side by construction rather than by care.
struct AgentModelFacts: Codable, Equatable, Sendable {
    /// The model these facts describe. Never assumed to be current.
    var id: String
    /// Whether the model's own listing says it accepts images.
    var seesImages: Bool
    /// Dollars per million tokens, when the listing priced it. Kept for the
    /// picker's own label — never used to compute a bill, which is
    /// `AgentSpend`'s standing refusal and unchanged here.
    var promptUSDPerMillion: Double?
    var completionUSDPerMillion: Double?
    /// Every priced dimension the listing carried was zero.
    var free: Bool

    private static let prefix = "agent.modelfacts."

    private static func key(_ provider: AgentProvider, _ task: AgentTask) -> String {
        prefix + provider.rawValue + task.storeSuffix
    }

    /// Remembers what was on screen when a model was picked. Called from the
    /// picker, which is the one place the listing and the choice are both in
    /// hand — re-reading the list later to learn this would be a settings screen
    /// firing requests for being looked at, which this app keeps deciding
    /// against.
    static func remember(_ facts: AgentModelFacts, for provider: AgentProvider, task: AgentTask) {
        guard let data = try? JSONEncoder().encode(facts) else { return }
        UserDefaults.standard.set(data, forKey: key(provider, task))
    }

    static func forget(_ provider: AgentProvider, task: AgentTask) {
        UserDefaults.standard.removeObject(forKey: key(provider, task))
    }

    /// Every task's facts for one provider — paired with clearing its key, so a
    /// removed key leaves nothing behind that could describe the next one.
    static func forgetAll(_ provider: AgentProvider) {
        AgentTask.allCases.forEach { forget(provider, task: $0) }
    }

    /// The stored facts, but only while they still describe `current`.
    ///
    /// `current` is passed in rather than read here so this stays pure and the
    /// harness can prove the staleness rule without a UserDefaults on either
    /// end — the shape `AgentBudget.rebased` already uses for the same reason.
    static func matching(_ stored: AgentModelFacts?, current: String) -> AgentModelFacts? {
        guard let stored, stored.id == current, !current.isEmpty else { return nil }
        return stored
    }

    static func stored(_ provider: AgentProvider, task: AgentTask) -> AgentModelFacts? {
        guard let data = UserDefaults.standard.data(forKey: key(provider, task)),
              let decoded = try? JSONDecoder().decode(AgentModelFacts.self, from: data)
        else { return nil }
        return decoded
    }

    /// The facts for whatever this provider will actually send, or nil.
    static func current(_ provider: AgentProvider, task: AgentTask = .ask) -> AgentModelFacts? {
        matching(stored(provider, task: task), current: provider.model(for: task))
    }

    /// Whether this ask may carry a screenshot's own picture.
    ///
    /// The provider's own flag is the FLOOR and can only be raised, never
    /// lowered: a direct Anthropic key sees images whatever any listing says,
    /// and a router with nothing known about its destination does not. So an
    /// absent fact leaves the shipped answer exactly as it was.
    static func seesImages(_ provider: AgentProvider, task: AgentTask = .ask) -> Bool {
        if provider.seesImages { return true }
        return current(provider, task: task)?.seesImages ?? false
    }

    /// Whether the model this task runs on costs nothing.
    ///
    /// Unknown reads as PAID. The one caller is the monthly ceiling, where
    /// guessing "free" would let unbounded billed work run against a cap
    /// somebody set precisely to stop it.
    static func isFree(_ provider: AgentProvider, task: AgentTask = .ask) -> Bool {
        current(provider, task: task)?.free ?? false
    }
}
