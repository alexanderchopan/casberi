import Foundation

/// A small generic coalescing cache (2026-07-20), mirroring `WalletIngest`'s
/// private `HoldingsCache` shape exactly (check fresh → check in-flight →
/// spawn task → populate; a nil result is never cached, so a rate-limited
/// miss stays free to heal next try) — genericized so the same shape serves
/// more than one payload type.
///
/// Exists because three independent callers now read the SAME Aave/Safe
/// primitives every foreground pass: `WalletIngest.refresh`'s own sync arms
/// (`WalletDeFi.sync`/`SafeBridge.sync`), the Wallet screen's live state
/// (`WalletDeFi.positions`/`SafeBridge.pendingCounts`), and the new
/// Aave/Safe kept-ask composers — each unaware of the others, exactly the
/// "same call fired 5-8× per foreground" problem `HoldingsCache` was built
/// to solve for holdings. Applied at the PRIMITIVE read (one `eth_call` /
/// one queue fetch), not the higher-level aggregate function, mirroring
/// where `HoldingsCache` itself sits (in front of the raw Portfolio fetch,
/// not in front of `topHoldingsByWallet`).
actor CoalescingCache<Value: Sendable> {
    private struct Entry { let value: Value; let at: Date }
    private var fresh: [String: Entry] = [:]
    private var inFlight: [String: Task<Value?, Never>] = [:]

    /// A live-enough value for `key`: a fresh cache hit (within `ttl`), the
    /// value of an already-running fetch for the same key, or a new fetch
    /// every concurrent caller then shares. The actor's own serialization
    /// makes the check-then-register step race-free (no `await` between
    /// reading `inFlight` and writing it).
    func value(key: String, ttl: TimeInterval,
              fetch: @Sendable @escaping () async -> Value?) async -> Value? {
        if let e = fresh[key], e.at.timeIntervalSinceNow > -ttl { return e.value }
        if let running = inFlight[key] { return await running.value }
        let task = Task { await fetch() }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { fresh[key] = Entry(value: result, at: .now) }
        return result
    }
}
