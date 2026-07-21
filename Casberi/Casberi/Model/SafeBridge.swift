import Foundation
import SwiftData

/// Safe (formerly Gnosis Safe) multisig support (2026-07-20) — a watched
/// address that turns out to be a Safe gets its pending signature queue read
/// through Safe's own Transaction Service (keyless, `api.safe.global/
/// tx-service/<seg>/...`), no separate connect step: detection and the queue
/// both ride `WalletIngest.refresh`, exactly like approvals. A new pending
/// transaction lands a thing ("2 of 3 signatures collected on a transfer");
/// the sheet card re-reads live confirmation counts, since they can climb
/// after the thing first landed.
///
/// Verified live (2026-07-20, curl against the real API, not from docs
/// prose): the base URL migrated off the old per-chain
/// `safe-transaction-<network>.safe.global` subdomains to
/// `api.safe.global/tx-service/<seg>/...`; `seg` is a Safe-internal short
/// name, NOT always the chain's EIP-3770 shortName — Polygon is `pol`, not
/// `matic`. Keyless access works (capped at 2 RPS on the free tier). The
/// Safe WEB APP's own door-URL chain-prefix could not be independently
/// verified for every chain in the time available (only "eth" was confirmed
/// live) — rather than guess and risk a dead/wrong link, this bridge omits
/// that door entirely; the card states counts and lets the person open their
/// own Safe app.
enum SafeBridge {

    private struct Chain {
        let network: String   // WalletChainStore id
        let seg: String        // Safe Transaction Service's own path segment
    }
    private static let chains: [Chain] = [
        Chain(network: "eth-mainnet",   seg: "eth"),
        Chain(network: "base-mainnet",  seg: "base"),
        Chain(network: "arb-mainnet",   seg: "arb1"),
        Chain(network: "opt-mainnet",   seg: "oeth"),
        Chain(network: "matic-mainnet", seg: "pol"),
    ]

    private static func baseURL(_ seg: String) -> String {
        "https://api.safe.global/tx-service/\(seg)/api/v1"
    }

    private static func isSafeKey(_ seg: String, _ address: String) -> String {
        "wallet.safe.isSafe.\(seg).\(address.lowercased())"
    }
    private static func isSafeCheckedAtKey(_ seg: String, _ address: String) -> String {
        "wallet.safe.isSafe.checkedAt.\(seg).\(address.lowercased())"
    }

    /// A negative result stays trusted for a day before re-checking
    /// (2026-07-20, fixed in review) — Safe deploys counterfactually via
    /// CREATE2, so an address can be a real, precomputed Safe address today
    /// that genuinely becomes one later once the contract lands there; a
    /// permanent negative cache would freeze that as "not a Safe" forever.
    /// A POSITIVE, in contrast, really is permanent — nothing un-deploys a
    /// Safe once it exists.
    private static let negativeCacheTTL: TimeInterval = 24 * 3600

    /// Detects whether `address` is a Safe on this chain — a confirmed
    /// positive caches forever; a negative is re-checked periodically (see
    /// `negativeCacheTTL`). nil means the read itself failed (offline,
    /// rate-limited) — never cached, so a transient outage can't freeze a
    /// real Safe as permanently "not one".
    private static func isSafe(chain: Chain, address: String) async -> Bool? {
        let key = isSafeKey(chain.seg, address)
        if let cached = UserDefaults.standard.object(forKey: key) as? Bool {
            if cached { return true }
            let checkedAt = UserDefaults.standard.double(forKey: isSafeCheckedAtKey(chain.seg, address))
            if Date.now.timeIntervalSince1970 - checkedAt < negativeCacheTTL { return false }
        }
        let (_, status) = await IngestSupport.getJSONStatus("\(baseURL(chain.seg))/safes/\(address)/")
        guard status == 200 || status == 404 else { return nil }
        let result = status == 200
        UserDefaults.standard.set(result, forKey: key)
        if !result {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970,
                                      forKey: isSafeCheckedAtKey(chain.seg, address))
        }
        return result
    }

    /// Unwatching wipes the Safe-detection cache too (called from
    /// `WalletStore.addresses.didSet`, next to every sibling cursor) — the
    /// same "re-watching starts honest" rule; also the only way to recover
    /// from a negative that's still inside its TTL.
    static func clearCache(address: String) {
        for chain in chains {
            UserDefaults.standard.removeObject(forKey: isSafeKey(chain.seg, address))
            UserDefaults.standard.removeObject(forKey: isSafeCheckedAtKey(chain.seg, address))
        }
    }

    /// `[String: Any]` (raw JSON) isn't provably `Sendable` to the compiler
    /// even though it's plain, immutable data passed only by value here —
    /// this thin wrapper asserts that explicitly rather than restructuring
    /// every raw-dictionary call site into a typed model just to cache it.
    private struct JSONRows: @unchecked Sendable {
        let rows: [[String: Any]]
    }
    /// Coalesced (2026-07-20) — the same three independent callers as
    /// `WalletDeFi.accountData` (the sync arm, the Wallet screen's live
    /// state, the Safe kept ask) hit this exact endpoint every foreground
    /// pass, against Safe's 2-RPS free-tier cap. `isSafe`'s OWN cache is
    /// untouched (a different kind of cache, for a different reason — see
    /// its own doc comment); this only coalesces the QUEUE read.
    private static let queueCache = CoalescingCache<JSONRows>()

    /// The pending (unexecuted) queue for a confirmed Safe — nil only on an
    /// unreachable read, never on "empty queue" (that's `[]`).
    private static func pendingQueue(chain: Chain, address: String) async -> [[String: Any]]? {
        let key = "\(chain.seg)|\(address.lowercased())"
        let boxed = await queueCache.value(key: key, ttl: 60) {
            await fetchPendingQueue(chain: chain, address: address).map(JSONRows.init)
        }
        return boxed?.rows
    }

    private static func fetchPendingQueue(chain: Chain, address: String) async -> [[String: Any]]? {
        guard let root = await IngestSupport.getJSON(
                "\(baseURL(chain.seg))/safes/\(address)/multisig-transactions/?executed=false")
                as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return nil }
        return results
    }

    /// "a transfer" / the decoded contract call's method name / the honest
    /// "a transaction" when neither is known — never a guess.
    private static func describe(_ tx: [String: Any]) -> String {
        if let decoded = tx["dataDecoded"] as? [String: Any],
           let method = decoded["method"] as? String, !method.isEmpty {
            return method
        }
        if let valueStr = tx["value"] as? String, let value = Double(valueStr), value > 0 {
            return String(localized: "a transfer")
        }
        return String(localized: "a transaction")
    }

    /// Reads each watched wallet's Safe status + pending queue per active EVM
    /// chain and lands a thing for every NEWLY seen pending `safeTxHash`.
    /// Rides `WalletIngest.refresh` inside its running guard, like the other
    /// arms.
    @MainActor
    static func sync(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int {
        guard !addresses.isEmpty else { return 0 }
        let active = Set(WalletChainStore.activeNetworkIDs())
        var added = 0
        for chain in chains where active.contains(chain.network) {
            for address in addresses {
                guard let safe = await isSafe(chain: chain, address: address), safe else { continue }
                guard let pending = await pendingQueue(chain: chain, address: address) else { continue }
                for tx in pending {
                    guard let safeTxHash = tx["safeTxHash"] as? String else { continue }
                    let ref = "wallet:safe:\(chain.seg):\(safeTxHash)"
                    guard !existing.contains(ref) else { continue }
                    let required = (tx["confirmationsRequired"] as? Int) ?? 0
                    let have = (tx["confirmations"] as? [[String: Any]])?.count ?? 0
                    let title = String(localized:
                        "\(have) of \(required) signatures collected on \(describe(tx))")
                    let thing = Thing(kind: .transaction, title: title, source: "Wallet", sourceRef: ref)
                    thing.walletAddress = address
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                    added += 1
                }
            }
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    /// Each address's total pending-signature count, summed across every
    /// chain it's a detected Safe on — the Wallet screen's live summary row.
    /// Absent (not just zero) for an address that isn't a Safe anywhere.
    @MainActor
    static func pendingCounts(addresses: [String]) async -> [String: Int] {
        guard !addresses.isEmpty else { return [:] }
        var out: [String: Int] = [:]
        for chain in chains where WalletChainStore.activeNetworkIDs().contains(chain.network) {
            for address in addresses {
                guard let safe = await isSafe(chain: chain, address: address), safe else { continue }
                let pending = await pendingQueue(chain: chain, address: address) ?? []
                out[address.lowercased(), default: 0] += pending.count
            }
        }
        return out
    }

    // MARK: - Live recheck (the sheet card)

    struct Check {
        enum Status {
            /// Still in the queue — the live confirmation count.
            case pending(have: Int, required: Int)
            /// No longer in the pending queue — executed, or replaced by a
            /// same-nonce transaction (a Safe allows exactly one live
            /// transaction per nonce). Either way there's nothing left to
            /// wait on.
            case resolved
        }
        let status: Status
    }

    enum Outcome {
        case ok(Check)
        case fail(String)
    }

    static func applies(to thing: Thing) -> Bool {
        thing.sourceRef?.hasPrefix("wallet:safe:") == true && !(thing.walletAddress ?? "").isEmpty
    }

    @MainActor
    static func check(for thing: Thing) async -> Check? {
        if case .ok(let check) = await outcome(for: thing) { return check }
        return nil
    }

    /// Re-fetches the SAME wallet's pending queue (the only endpoint this
    /// bridge verified live) and finds the matching entry — rather than
    /// assume a single-transaction-by-hash endpoint exists unverified.
    @MainActor
    static func outcome(for thing: Thing) async -> Outcome {
        guard applies(to: thing), let ref = thing.sourceRef, let address = thing.walletAddress
        else { return .fail("not a safe thing") }
        let parts = ref.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count == 4 else { return .fail("malformed ref") }
        let seg = parts[2], safeTxHash = parts[3]
        guard let chain = chains.first(where: { $0.seg == seg }) else { return .fail("unknown chain") }
        guard WalletChainStore.activeNetworkIDs().contains(chain.network)
        else { return .fail("chain switched off") }
        guard let pending = await pendingQueue(chain: chain, address: address)
        else { return .fail("unreachable") }
        guard let tx = pending.first(where: { ($0["safeTxHash"] as? String) == safeTxHash }) else {
            return .ok(Check(status: .resolved))
        }
        let required = (tx["confirmationsRequired"] as? Int) ?? 0
        let have = (tx["confirmations"] as? [[String: Any]])?.count ?? 0
        return .ok(Check(status: .pending(have: have, required: required)))
    }

    /// `-safeProbe YES` — reports which watched wallets are detected Safes
    /// (per chain) and their pending counts, or the honest unreachable/none.
    @MainActor
    static func probe() async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        var lines: [String] = []
        for chain in chains where WalletChainStore.activeNetworkIDs().contains(chain.network) {
            for address in addresses {
                guard let safe = await isSafe(chain: chain, address: address) else {
                    lines.append("\(WalletStore.shortAddress(address)) \(chain.seg): unreachable")
                    continue
                }
                guard safe else { continue }
                let pending = await pendingQueue(chain: chain, address: address) ?? []
                lines.append("\(WalletStore.shortAddress(address)) \(chain.seg): SAFE, \(pending.count) pending")
            }
        }
        return lines.isEmpty ? "no Safes detected" : lines.joined(separator: " | ")
    }
}
