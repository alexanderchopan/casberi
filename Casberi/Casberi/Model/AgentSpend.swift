import Foundation

/// What the person's own key was asked to do (2026-08-06) — the receipt for
/// the one path in this app that costs somebody money.
///
/// Settings has said "They bill you directly" since BYOK shipped, and that
/// sentence was true and unmeasurable: nothing recorded a single request, so
/// the only way to learn what Casberi had spent your key on was to open the
/// provider's own dashboard and try to tell this app's requests apart from
/// everything else you use the same key for. This is `NetworkLedger`'s idea
/// applied to tokens instead of hosts — the claim made checkable from inside
/// the app that makes it.
///
/// **It records tokens, and refuses to invent a price.** A per-model rate
/// table is exactly the artifact this codebase keeps learning not to ship: it
/// renders perfectly whatever is in it, it goes stale silently the day a
/// provider re-prices or the day a pinned model id rotates (see
/// `AgentProvider.model`'s own correction history), and a wrong dollar figure
/// on a spending screen is believed. So a row says 41,200 in / 3,900 out
/// across 12 requests, which is measured, and names the provider's own console
/// as the place the bill lives. The ONE exception is a number the provider
/// itself states: OpenRouter's `/v1/auth/key` returns the key's real usage in
/// dollars, so that is shown, attributed, and never mixed with the local
/// counts.
///
/// **Measured, never estimated — which means some rows are honestly blank.**
/// Usage is parsed out of each provider's own response: Anthropic reports it
/// on `message_start`/`message_delta`, Gemini on `usageMetadata`, and the
/// OpenAI-compatible shape only when the request asked for it via
/// `stream_options.include_usage`, which this app sends to OpenAI and
/// OpenRouter (both document it) and not to Venice or Grok, whose support is
/// unconfirmed and where an unknown body key risks a 400 on the answer path
/// itself. A provider that reports nothing gets a request count and no token
/// counts, and the screen says so rather than showing a confident zero.
final class AgentSpend: @unchecked Sendable {

    static let shared = AgentSpend()

    struct Entry: Codable, Identifiable, Equatable {
        /// `AgentProvider.rawValue`. Stored as the raw string so a provider
        /// retired from the enum still decodes and can still be shown or
        /// cleared, rather than vanishing from a receipt.
        var provider: String
        /// Requests actually issued — INCLUDING each round of a tool loop,
        /// since each round is a separate billed call. `rounds` below is what
        /// separates "12 questions" from "12 questions that took 19 calls".
        var requests: Int
        /// Extra requests beyond the first that a tool loop cost.
        var toolRounds: Int
        /// nil when this provider has never reported usage — distinct from 0,
        /// which would claim a free request.
        var inputTokens: Int?
        var outputTokens: Int?
        /// The most recent model id the provider actually answered with, when
        /// it says. Worth keeping: it is the only place a silently rotated
        /// pin becomes visible.
        var model: String?
        /// Dollars, and ONLY when the provider itself reported them (today:
        /// OpenRouter). Never computed here.
        var reportedUSD: Double?
        var first: Date
        var last: Date

        var id: String { provider }
    }

    /// A ceiling on nothing in particular — there are seven providers. Present
    /// so a corrupted decode can't grow the store without bound.
    static let maxProviders = 32

    private let storeKey = "agent.spend.v1"
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    // MARK: - Recording

    /// One billed request. Called once per round of a tool loop, not once per
    /// question — `round` is 0 for the first call of an exchange and counts up,
    /// which is what makes the tool loop's real cost visible instead of hiding
    /// inside an ordinary-looking request count.
    ///
    /// `input`/`output` are nil whenever the provider didn't say; they are
    /// ADDED to whatever is stored rather than replacing it, and a nil report
    /// against a stored count leaves the count alone (a provider that reports
    /// sometimes shouldn't erase what it reported before).
    func record(provider: AgentProvider, round: Int = 0,
                input: Int? = nil, output: Int? = nil, model: String? = nil) {
        let key = provider.rawValue
        let now = Date()
        lock.lock()
        var entry = entries[key] ?? Entry(provider: key, requests: 0, toolRounds: 0,
                                          inputTokens: nil, outputTokens: nil,
                                          model: nil, reportedUSD: nil,
                                          first: now, last: now)
        entry.requests += 1
        if round > 0 { entry.toolRounds += 1 }
        if let input { entry.inputTokens = (entry.inputTokens ?? 0) + input }
        if let output { entry.outputTokens = (entry.outputTokens ?? 0) + output }
        if let model, !model.isEmpty { entry.model = model }
        entry.last = now
        entries[key] = entry
        lock.unlock()
        flush()
    }

    /// A spend figure the PROVIDER stated, in dollars — never a local
    /// computation. Replaces rather than accumulates: it is a running total on
    /// their side, so adding it to itself on every read would compound.
    func recordReported(provider: AgentProvider, usd: Double) {
        let key = provider.rawValue
        let now = Date()
        lock.lock()
        var entry = entries[key] ?? Entry(provider: key, requests: 0, toolRounds: 0,
                                          inputTokens: nil, outputTokens: nil,
                                          model: nil, reportedUSD: nil,
                                          first: now, last: now)
        entry.reportedUSD = usd
        entries[key] = entry
        lock.unlock()
        flush()
    }

    // MARK: - Reading

    /// Every provider this key has spent anything on, busiest first.
    func snapshot() -> [Entry] {
        lock.lock()
        let all = Array(entries.values)
        lock.unlock()
        return all.sorted { $0.requests == $1.requests ? $0.last > $1.last : $0.requests > $1.requests }
    }

    func entry(for provider: AgentProvider) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[provider.rawValue]
    }

    /// Total requests across every provider — the one number the settings row
    /// leads with.
    var totalRequests: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.values.reduce(0) { $0 + $1.requests }
    }

    /// Forgets one provider's record — paired with removing its key, so
    /// deleting a key doesn't leave its receipt behind.
    func forget(_ provider: AgentProvider) {
        lock.lock()
        entries[provider.rawValue] = nil
        lock.unlock()
        flush()
    }

    func forgetAll() {
        lock.lock()
        entries = [:]
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    // MARK: - Persistence

    /// The `UserDefaults` write stays INSIDE the lock: outside it, two flushes
    /// racing could persist out of order and leave the older snapshot on disk
    /// (`NetworkLedger`'s own note, same reason).
    private func flush() {
        lock.lock()
        if entries.count > Self.maxProviders {
            let keep = entries.values.sorted { $0.last > $1.last }.prefix(Self.maxProviders)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.provider, $0) })
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
        lock.unlock()
    }
}

extension AgentSpend.Entry {
    /// "41.2k in · 3.9k out", or nil when this provider has never reported
    /// usage. Nil is a real answer and the screen prints its own sentence for
    /// it — a "0 in · 0 out" would claim the requests were free.
    var tokenLine: String? {
        guard let inputTokens, let outputTokens else { return nil }
        func short(_ n: Int) -> String {
            if n >= 1_000_000 { return String(format: "%.1fm", Double(n) / 1_000_000) }
            if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
            return "\(n)"
        }
        return "\(short(inputTokens)) in · \(short(outputTokens)) out"
    }
}
