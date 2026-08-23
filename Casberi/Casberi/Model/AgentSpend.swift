import Foundation
import SwiftData

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
        /// Input tokens served from a previous request's cache (2026-08-20),
        /// billed at a fraction of the input rate. Optional for a reason beyond
        /// honesty: a NON-optional field with a default would break decoding of
        /// every receipt already on disk, because Swift's synthesized decoder
        /// calls `decode` for those and `decodeIfPresent` only for Optionals —
        /// the trap that would have silently unfollowed every feed if
        /// `RSSStore.Feed` had ever gained a field.
        var cachedInputTokens: Int?
        /// Input tokens WRITTEN to the cache, billed at a premium. Kept beside
        /// the read rather than netted against it: they are the two halves of
        /// the same trade, and showing only the saving would make a receipt
        /// into an advertisement.
        var cacheWriteTokens: Int?
        /// The most recent model id the provider actually answered with, when
        /// it says. Worth keeping: it is the only place a silently rotated
        /// pin becomes visible.
        var model: String?
        /// Dollars, and ONLY when the provider itself reported them (today:
        /// OpenRouter). Never computed here.
        var reportedUSD: Double?
        /// Dollars this APP's own requests cost, summed from the price the
        /// provider stated for each finished generation (2026-08-23, prd §459).
        ///
        /// **A different number from `reportedUSD`, and the difference is the
        /// complaint this whole file opens with.** That one is the key's
        /// LIFETIME total, which cannot separate what Casberi asked from
        /// everything else the same key is used for — the exact reason somebody
        /// had to open a provider dashboard and guess. This one is the sum of
        /// generations this app started, so it answers "what did Casberi spend"
        /// for the first time.
        ///
        /// Optional for the reason its neighbours are: a non-Optional with a
        /// default fails the decode of every receipt already on disk.
        var appCostUSD: Double?
        /// How many of this app's requests actually got a price back. Kept
        /// beside the sum because it is what makes the sum readable: a total
        /// covering 3 of 40 requests is not a small bill, it is a mostly
        /// unanswered question, and the screen says which.
        var appCostRequests: Int?
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
                input: Int? = nil, output: Int? = nil, model: String? = nil,
                cacheRead: Int? = nil, cacheWrite: Int? = nil) {
        let key = provider.rawValue
        let now = Date()
        lock.lock()
        var entry = entries[key] ?? Entry(provider: key, requests: 0, toolRounds: 0,
                                          inputTokens: nil, outputTokens: nil,
                                          cachedInputTokens: nil, cacheWriteTokens: nil,
                                          model: nil, reportedUSD: nil,
                                          appCostUSD: nil, appCostRequests: nil,
                                          first: now, last: now)
        entry.requests += 1
        if round > 0 { entry.toolRounds += 1 }
        if let input { entry.inputTokens = (entry.inputTokens ?? 0) + input }
        if let output { entry.outputTokens = (entry.outputTokens ?? 0) + output }
        // A zero is a real reading — "this round hit no cache" — and is
        // accumulated like any other, so a provider that reports the field
        // always gets a total rather than a total that appears only once
        // something was cached.
        if let cacheRead { entry.cachedInputTokens = (entry.cachedInputTokens ?? 0) + cacheRead }
        if let cacheWrite { entry.cacheWriteTokens = (entry.cacheWriteTokens ?? 0) + cacheWrite }
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
                                          cachedInputTokens: nil, cacheWriteTokens: nil,
                                          model: nil, reportedUSD: nil,
                                          appCostUSD: nil, appCostRequests: nil,
                                          first: now, last: now)
        entry.reportedUSD = usd
        entries[key] = entry
        lock.unlock()
        flush()
    }

    /// What ONE of this app's own requests cost, as the provider priced it
    /// (2026-08-23, prd §459, OpenRouter's `/v1/generation`).
    ///
    /// ACCUMULATES, where `recordReported` replaces — and the two must never be
    /// confused. That one folds in a lifetime total from the provider's side,
    /// so adding it to itself would compound; this is a per-generation price
    /// that exists exactly once, so summing is the only reading that means
    /// anything.
    ///
    /// The paired count is what keeps the sum honest. A generation whose price
    /// never came back is simply absent from both, so the screen can say "for 3
    /// of 40 requests" rather than presenting a partial total as a bill.
    func recordAppCost(provider: AgentProvider, usd: Double) {
        guard usd >= 0 else { return }
        let key = provider.rawValue
        let now = Date()
        lock.lock()
        var entry = entries[key] ?? Entry(provider: key, requests: 0, toolRounds: 0,
                                          inputTokens: nil, outputTokens: nil,
                                          cachedInputTokens: nil, cacheWriteTokens: nil,
                                          model: nil, reportedUSD: nil,
                                          appCostUSD: nil, appCostRequests: nil,
                                          first: now, last: now)
        entry.appCostUSD = (entry.appCostUSD ?? 0) + usd
        entry.appCostRequests = (entry.appCostRequests ?? 0) + 1
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

    /// "18.4k of that came from cache" (2026-08-20), or nil when this provider
    /// never reported a cache hit or reported only misses.
    ///
    /// A share of `inputTokens`, not a number beside it — every provider here
    /// counts cached tokens INSIDE the input total, so printing them as a
    /// separate figure would read as extra spend when it is the opposite.
    /// Deliberately no percentage and no money: the saving depends on that
    /// model's cache-read rate, which is exactly the rate table this file
    /// refuses to keep.
    var cacheLine: String? {
        guard let cachedInputTokens, cachedInputTokens > 0 else { return nil }
        func short(_ n: Int) -> String {
            if n >= 1_000_000 { return String(format: "%.1fm", Double(n) / 1_000_000) }
            if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
            return "\(n)"
        }
        return String(localized: "\(short(cachedInputTokens)) of that was served from cache.")
    }

    /// "OpenRouter charged $0.0143 for what Casberi asked" (2026-08-23, prd
    /// §459) — the first dollar figure in this app that is about THIS APP, and
    /// still not one this app computed.
    ///
    /// **Four decimals, not two.** A single ask on a cheap model is fractions of
    /// a cent, and `$0.00` on a screen whose purpose is to show a real cost
    /// reads as "free" — the confident zero this file's own doc forbids
    /// everywhere else.
    ///
    /// **It states its own COVERAGE whenever it is partial.** A generation whose
    /// price never came back contributes to neither half, so a total spanning 3
    /// of 40 requests would otherwise read as a very cheap month rather than a
    /// mostly unanswered question. Silent only when it covers everything.
    var appCostLine: String? {
        guard let appCostUSD, let appCostRequests, appCostRequests > 0 else { return nil }
        let money = String(format: "$%.4f", appCostUSD)
        guard appCostRequests < requests else {
            return String(localized: "\(money) for what Casberi asked, priced by your provider.")
        }
        return String(localized: "\(money) for what Casberi asked — priced for \(appCostRequests) of \(requests) requests.")
    }
}

/// OpenRouter's own credit ceiling (2026-08-09) — parsed at the exact call
/// site `AgentAnswer.check` already makes for OpenRouter's `/v1/auth/key`
/// (`data.usage`/`data.limit`/`data.limit_remaining`), the free "who am I"
/// read every provider here gets checked with before its key saves. Riding
/// that call rather than opening a second one: `check` runs at connect time
/// and — since 2026-08-09 — from `BridgeRefresh`'s foreground sweep behind
/// `dueForHeal("openrouter.credits")`, so this reading is at most ~10 minutes
/// stale, the same STATE-not-EVENT window Stripe's balance uses (§216).
///
/// **Two thresholds, either sufficient — a guess, not measured** (no
/// OpenRouter key is stored on this build host to calibrate against).
/// RELATIVE (under 15% of the limit remaining) catches a modest key well
/// before it's exhausted; ABSOLUTE (under $3 remaining, and used instead of
/// the relative test once the limit itself is "large") catches a big limit
/// where 15% is still real money and the relative test alone would fire too
/// late — a $500 limit's 15% is $75, plenty to keep answering on, so the
/// absolute floor is the one that actually means "about to stop working"
/// there. The two rules agree exactly at the boundary (15% of $20 is $3).
///
/// Landing the Thing needs a `ModelContext`, which `AgentAnswer.check`
/// doesn't have (it runs from setup-screen `Task`s and the foreground
/// sweep's own `Task`, neither of which threads one into a nonisolated,
/// non-`@MainActor` static func) — so `record` only marks a bucket crossing
/// as PENDING; `drainPending` is the one place with a real context in hand
/// and does the actual insert, the DeFi health-factor bucket shape
/// (`WalletDeFi.sync`/`MorphoDeFi.sync`) split across two functions instead
/// of one.
enum OpenRouterCredits {
    private static let limitKey     = "openrouter.credits.limit"
    private static let remainingKey = "openrouter.credits.remaining"
    private static let bucketKey    = "openrouter.credits.bucket"      // "low" | "ok"
    private static let pendingKey   = "openrouter.credits.pendingLowThing"

    static let lowFraction     = 0.15
    static let largeLimitFloor = 20.0
    static let lowAbsoluteFloor = 3.0

    static func isLow(limit: Double, remaining: Double) -> Bool {
        guard limit > 0, remaining >= 0 else { return false }
        return limit >= largeLimitFloor ? remaining <= lowAbsoluteFloor
                                        : remaining <= limit * lowFraction
    }

    /// Pure UserDefaults + `AgentSpend` (thread-safe, no actor requirement) —
    /// safe to call from `check`'s nonisolated context. `data.limit` absent
    /// means an unlimited/free-tier key, OpenRouter's own documented
    /// meaning, not a read failure — clears any stale reading rather than
    /// treating a now-unlimited key as still "low".
    static func record(json: [String: Any]) {
        guard let data = json["data"] as? [String: Any] else { return }
        if let usage = data["usage"] as? Double {
            AgentSpend.shared.recordReported(provider: .openrouter, usd: usage)
        }
        // The monthly ceiling reads the SAME figure (2026-08-20) — a lifetime
        // total, folded into a per-month delta by `AgentBudget`. Recorded here
        // rather than at the cap's own call site so it lands on every read of
        // this endpoint, including the foreground sweep's, and never needs a
        // request of its own.
        if let usage = data["usage"] as? Double { AgentBudget.observe(reportedUSD: usage) }
        let d = UserDefaults.standard
        guard let limit = data["limit"] as? Double else {
            d.removeObject(forKey: limitKey)
            d.removeObject(forKey: remainingKey)
            d.set("ok", forKey: bucketKey)
            return
        }
        let remaining = (data["limit_remaining"] as? Double) ?? limit
        d.set(limit, forKey: limitKey)
        d.set(remaining, forKey: remainingKey)
        let bucket = isLow(limit: limit, remaining: remaining) ? "low" : "ok"
        let last = d.string(forKey: bucketKey)
        d.set(bucket, forKey: bucketKey)
        if bucket == "low", last != "low" {
            d.set(true, forKey: pendingKey)
        }
    }

    /// Lands the Thing a `record()` above marked pending. Reads its numbers
    /// back from the SAME UserDefaults `record` just wrote, so a stale
    /// figure can never be landed twice, and clears the pending flag whether
    /// or not a Thing actually comes out the other end (a dedupe hit, or the
    /// numbers having gone missing between the two calls, are both "nothing
    /// to do", not "try again next time" — the crossing already happened
    /// once and `record` will mark a fresh one if it happens again).
    @MainActor
    @discardableResult
    static func drainPending(context: ModelContext, existing: Set<String>) -> Thing? {
        let d = UserDefaults.standard
        guard d.bool(forKey: pendingKey) else { return nil }
        d.set(false, forKey: pendingKey)
        guard let limit = d.object(forKey: limitKey) as? Double,
              let remaining = d.object(forKey: remainingKey) as? Double
        else { return nil }
        let ref = "openrouter:credits:low:\(Int(Date.now.timeIntervalSince1970))"
        guard !existing.contains(ref) else { return nil }
        let limitText = String(format: "$%.2f", limit)
        let remainingText = String(format: "$%.2f", max(0, remaining))
        let title = String(localized:
            "Your OpenRouter credits are running low — \(remainingText) left of \(limitText)")
        let thing = Thing(kind: .reminder, title: IngestSupport.titleLine(title),
                          content: "https://openrouter.ai/settings/credits",
                          source: "OpenRouter", capturedAt: .now, sourceRef: ref)
        context.insert(thing)
        SpotlightIndex.index([thing])
        context.saveHonestly()
        return thing
    }

    /// Read-only, for `-agentCreditsProbe` and the settings row.
    static var limit: Double? { UserDefaults.standard.object(forKey: limitKey) as? Double }
    static var remaining: Double? { UserDefaults.standard.object(forKey: remainingKey) as? Double }
    static var bucket: String? { UserDefaults.standard.string(forKey: bucketKey) }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: limitKey)
        d.removeObject(forKey: remainingKey)
        d.removeObject(forKey: bucketKey)
        d.removeObject(forKey: pendingKey)
    }
}
