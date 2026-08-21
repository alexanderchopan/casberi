import Foundation
import SwiftData

/// Safe (formerly Gnosis Safe) multisig support (2026-07-20, extended
/// 2026-07-30) — three ways a watched wallet touches a Safe, all keyless
/// against Safe's own Transaction Service, all riding `WalletIngest.refresh`
/// exactly like approvals (no separate connect step, §207 "watching is
/// consent"):
///
/// (1) The watched address IS a Safe — its pending queue lands as things
///     ("2 of 3 signatures collected on a transfer"); the sheet card
///     re-reads live confirmation counts.
/// (2) The watched address is a SIGNER on a Safe it doesn't itself watch
///     (2026-07-30) — `/owners/{eoa}/safes/` finds every Safe naming that
///     address as an owner, on every active chain. This is the common case
///     (a person watches their own EOA, not the multisig), but the endpoint
///     answers for ANY address ever named an owner at deployment — nothing
///     requires that owner's consent, so a spam-deployed decoy naming a
///     stranger is free to create. Surfaced only when the candidate Safe has
///     both a non-empty pending queue AND `nonce > 0` (it has actually
///     executed something) — a decoy nobody funds or uses fails one of the
///     two for free, so this stays a real-signal filter, not a guess.
/// (3) Either kind of Safe's OWN CONFIGURATION changing — a new/removed
///     owner, a changed threshold, a newly enabled module or guard — lands
///     as its own alert, on change only (`WalletSafety`'s delegation-cursor
///     idiom: seed the baseline silently on first sight, alert on drift).
///     A module in particular can move funds outside the threshold
///     entirely, so this is the highest-stakes fact this bridge can state.
///
/// Verified live (2026-07-20, curl against the real API, not from docs
/// prose): the base URL migrated off the old per-chain
/// `safe-transaction-<network>.safe.global` subdomains to
/// `api.safe.global/tx-service/<seg>/...`; `seg` is a Safe-internal short
/// name, NOT always the chain's EIP-3770 shortName — Polygon is `pol`, not
/// `matic`. Keyless access works (capped at 2 RPS on the free tier).
///
/// The Safe WEB APP's door-URL chain-prefix was originally omitted rather
/// than guessed (only "eth" had been confirmed live). It is no longer a
/// guess: every `shortName` below is read from Safe's own config service
/// (2026-07-30), `safeAppURL` builds the queue link from it, and since
/// 2026-07-31 (prd §241) `pendingCounts` hands that link to the Worth-a-look
/// row that asks a person to go sign something — which until then named the
/// Safe app in a sentence and offered no way to reach it.
///
/// Re-verified live 2026-07-30 while adding (2)/(3): `/owners/{addr}/safes/`
/// answers per chain (vitalik.eth: 59 on eth, more on base — overwhelmingly
/// NOT his, confirming the spam-decoy risk above is real, not theoretical);
/// `/safes/{addr}/` carries `nonce`/`threshold`/`owners`/`modules`/`guard`;
/// `/multisig-transactions/{hash}/` exists (the original bridge assumed it
/// might not and always re-fetched the whole queue instead); and the `gno`
/// segment (Gnosis Chain) answers cleanly — not previously in this bridge's
/// chain list despite Gnosis Pay accounts being Safes themselves.
///
/// Three enrichments (2026-08-11), all keyless, no new endpoint:
/// (4) Row titles now name an AMOUNT ("a transfer of 1,500 USDC to
///     alice.eth") when the target token's symbol/decimals are cached
///     (`prefetchFacts`, riding the same `WalletApprovals.tokenFacts` read
///     the approvals card uses), and call an unlimited ERC-20 approval
///     "unlimited" rather than a number nobody can read.
/// (5) A pending transaction's eventual RESOLUTION — executed, or replaced
///     by a rival at the same nonce — now lands its own closing thing,
///     with how long it sat pending read off Safe's own `submissionDate`/
///     `executionDate` (`resolveTracking`/`landOutcome`). Before this the
///     feed opened the question ("2 of 3 signatures collected") and never
///     answered it; a replaced transaction — usually a co-signer rejecting
///     it — was previously invisible outside the sheet's own live recheck.
/// (6) Safe's own "reject" shape (a zero-value, no-data call to the Safe
///     itself, proposed to burn a nonce so a rival can't execute) is named
///     for what it is instead of falling through to the generic "a
///     transaction" — the one Safe-native action whose whole point is that
///     it moves nothing, previously described identically to a mystery.
/// (7) This bridge finally reaches the lock screen (`NotifySweep.classify`):
///     a pending transaction tagged "Your turn" at landing time fires
///     `.safeSignatureNeeded` — the clearest "needs YOU" shape this app has,
///     since a co-signer's own app has no way to page you — and a config
///     change tagged "Module added" reuses `.approvalGranted` (structurally
///     the same "something new can move your funds" news). Both tags are
///     set structurally at landing time, never parsed from the title, the
///     Stripe/Cursor/Apple-Wallet shape. An owner/threshold/guard change
///     alone still doesn't notify — real news, but not the fund-draining-
///     outside-the-threshold shape the right-hand slot is reserved for; nor
///     does an executed or replaced outcome (5) — closure with nothing left
///     to act on, so it stays a feed row rather than a buzz.
/// (8) Safe gets its OWN source and its own room head (2026-08-11, prd §349
///     amendment). It used to land under `source: "Wallet"` like Aave/Morpho/
///     Hyperliquid/Aerodrome — folded in as a sub-lens because it had no chip
///     of its own to fold. That premise no longer held: Peer/Privacy Pools/
///     Gnosis Pay/Railgun/ether.fi all already carry their own chip, so
///     "Wallet" was one lens with its own chip beside five that shared it —
///     an inconsistency, not a design. `sourceName` is now `"Safe"`;
///     `retagToOwnSource` is a one-time pass that re-stamps every ALREADY-
///     LANDED Safe row (found by its `wallet:safe*` ref prefix, which never
///     changed) from `"Wallet"` to `"Safe"`, so nobody's existing queue items
///     vanish from the feed history the day this ships. `Model/SafeRoom.swift`
///     draws the room head — the signature queue as rings, ranked "your turn"
///     first then longest-waiting — off the SAME tracking snapshot this file
///     already keeps for the loop-closers in (5), extended with the fields a
///     card needs (`have`/`required`/`yourTurn`/`submittedAt`/a cached
///     description), so the head spends no extra read.
enum SafeBridge {

    /// The seat's own source name — `PeerBridge.sourceName`/
    /// `GnosisPayBridge.sourceName`'s shape, joined 2026-08-11. Read here
    /// rather than spelled as a literal at every landing site, the same
    /// reason those two are.
    static let sourceName = "Safe"

    private struct Chain {
        let network: String?   // WalletChainStore id; nil = not chain-toggle-gated (always active)
        let seg: String        // Safe Transaction Service's own path segment
        /// The Safe WEB APP's chain prefix (EIP-3770 shortName) — NOT the same
        /// string as `seg`. Polygon proves it: the tx-service segment is
        /// `pol` while the web app's shortName is `matic`. Read from Safe's
        /// own config service (2026-07-30, `safe-config.safe.global/api/v1/
        /// chains/`, the authoritative list) rather than assumed equal to
        /// `seg` — which is exactly the guess the original bridge refused to
        /// make, correctly, when it omitted this door entirely.
        let shortName: String
    }
    /// `gno` (Gnosis Chain) carries `network: nil` — it isn't a
    /// WalletChainStore/Alchemy-selectable chain at all (same reason
    /// `GnosisPayBridge` reads it over its own public RPCs rather than
    /// through the chain picker), so its Safe reads aren't gated by that
    /// toggle either — they run whenever a watched EOA might be a Gnosis
    /// Pay/Safe signer.
    private static let chains: [Chain] = [
        Chain(network: "eth-mainnet",   seg: "eth",  shortName: "eth"),
        Chain(network: "base-mainnet",  seg: "base", shortName: "base"),
        Chain(network: "arb-mainnet",   seg: "arb1", shortName: "arb1"),
        Chain(network: "opt-mainnet",   seg: "oeth", shortName: "oeth"),
        Chain(network: "matic-mainnet", seg: "pol",  shortName: "matic"),
        Chain(network: nil,             seg: "gno",  shortName: "gno"),
    ]

    /// The door out — the person's own Safe app, open on this Safe's queue.
    /// The one action this bridge can't do and shouldn't: signing happens
    /// there, never here, and until now there was no way to get there at all.
    private static func safeAppURL(chain: Chain, safeAddress: String) -> String {
        "https://app.safe.global/transactions/queue?safe=\(chain.shortName):\(EIP55.checksum(safeAddress))"
    }

    private static func isChainActive(_ chain: Chain) -> Bool {
        guard let network = chain.network else { return true }
        return WalletChainStore.activeNetworkIDs().contains(network)
    }

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
        // api.safe.global requires a strict EIP-55 checksum, not just any
        // hex casing — measured 2026-07-28: a lowercased AND an all-caps
        // WETH address both 422 as "Checksum address validation failed";
        // only the mixed-case checksum form gets an honest 200/404. Every
        // address this bridge ever sees arrives lowercased (AddressBook's
        // own comparison form), so without this every Safe watched via a
        // pasted or ENS-resolved address failed silently, forever (a 422
        // reads as "unreachable" below, never cached, retried every pass).
        let (_, status) = await IngestSupport.getJSONStatus(
            "\(baseURL(chain.seg))/safes/\(EIP55.checksum(address))/")
        guard status == 200 || status == 404 else { return nil }
        let result = status == 200
        UserDefaults.standard.set(result, forKey: key)
        if !result {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970,
                                      forKey: isSafeCheckedAtKey(chain.seg, address))
        }
        return result
    }

    /// Is this address a Safe on ANY chain (every chain this bridge knows,
    /// unfiltered by the person's chain toggle — detection is cheap and
    /// cached, and the address book wants the answer regardless of which
    /// chains the wallet feed currently reads)? For the address book's kind
    /// detection (prd §169) — the person supplies a name, the chain supplies
    /// what the thing is.
    static func isSafeAnywhere(_ address: String) async -> Bool {
        for chain in chains {
            if await isSafe(chain: chain, address: address) == true { return true }
        }
        return false
    }

    /// Unwatching wipes the Safe-detection cache, the config snapshot, and
    /// the owner-lookup cache too (called from `WalletStore.addresses.didSet`,
    /// next to every sibling cursor) — the same "re-watching starts honest"
    /// rule; also the only way to recover from a negative that's still
    /// inside its TTL.
    static func clearCache(address: String) {
        for chain in chains {
            UserDefaults.standard.removeObject(forKey: isSafeKey(chain.seg, address))
            UserDefaults.standard.removeObject(forKey: isSafeCheckedAtKey(chain.seg, address))
            UserDefaults.standard.removeObject(forKey: ownerCacheKey(chain.seg, address))
        }
        let lower = address.lowercased()
        let tracking = loadTracking().filter {
            $0.value.safeAddress.lowercased() != lower && ($0.value.ownerAddress?.lowercased() ?? "") != lower
        }
        saveTracking(tracking)
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
                "\(baseURL(chain.seg))/safes/\(EIP55.checksum(address))/multisig-transactions/?executed=false")
                as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return nil }
        return results
    }

    // MARK: - Owner reverse-lookup (2026-07-30)

    private struct JSONStrings: @unchecked Sendable { let rows: [String] }
    private static let ownerCache = CoalescingCache<JSONStrings>()

    private static func ownerCacheKey(_ seg: String, _ address: String) -> String {
        "safe:owners:\(seg)|\(address.lowercased())"
    }

    /// Every Safe address that names `address` as an owner, on this chain —
    /// `[]` for none, nil only on an unreachable read. Ownership doesn't
    /// churn minute to minute, so this rides a longer TTL than the queue
    /// read.
    private static func ownerSafes(chain: Chain, address: String) async -> [String]? {
        let boxed = await ownerCache.value(key: ownerCacheKey(chain.seg, address), ttl: 600) {
            guard let root = await IngestSupport.getJSON(
                    "\(baseURL(chain.seg))/owners/\(EIP55.checksum(address))/safes/")
                    as? [String: Any],
                  let safes = root["safes"] as? [String]
            else { return nil }
            return JSONStrings(rows: safes)
        }
        return boxed?.rows
    }

    // MARK: - Safe detail (nonce + config, shared by the spam filter and the config-change alert)

    private struct SafeConfig: Codable, Equatable {
        let threshold: Int
        let owners: [String]   // lowercased, sorted
        let modules: [String]  // lowercased, sorted
        let guardAddr: String? // lowercased; nil for the zero address (no guard)
    }
    private struct SafeDetail: Sendable {
        let nonce: Int
        let config: SafeConfig
    }
    private static let detailCache = CoalescingCache<SafeDetailBox>()
    private struct SafeDetailBox: @unchecked Sendable { let detail: SafeDetail }

    private static func safeDetail(chain: Chain, address: String) async -> SafeDetail? {
        let boxed = await detailCache.value(key: "\(chain.seg)|\(address.lowercased())", ttl: 60) {
            guard let root = await IngestSupport.getJSON(
                    "\(baseURL(chain.seg))/safes/\(EIP55.checksum(address))/") as? [String: Any]
            else { return nil }
            let threshold = (root["threshold"] as? Int) ?? 0
            let nonce = Int((root["nonce"] as? String) ?? "") ?? (root["nonce"] as? Int) ?? 0
            let owners = ((root["owners"] as? [String]) ?? []).map { $0.lowercased() }.sorted()
            let modules = ((root["modules"] as? [String]) ?? []).map { $0.lowercased() }.sorted()
            let rawGuard = (root["guard"] as? String)?.lowercased()
            let guardAddr = (rawGuard == nil || rawGuard == "0x0000000000000000000000000000000000000000")
                ? nil : rawGuard
            let config = SafeConfig(threshold: threshold, owners: owners, modules: modules, guardAddr: guardAddr)
            return SafeDetailBox(detail: SafeDetail(nonce: nonce, config: config))
        }
        return boxed?.detail
    }

    /// One Safe this pass touched, reachable either because the address
    /// itself is watched (`viaOwner == nil`) or because a watched EOA is one
    /// of its signers (`viaOwner` is that EOA — the "you" `describe`'s
    /// yourTurn wording is computed against).
    private struct Candidate {
        let chain: Chain
        let safeAddress: String
        let viaOwner: String?
    }

    /// Every Safe this app has ever confirmed real (cleared the spam filter
    /// below, or was watched directly) — an append-only local cache, NOT
    /// re-derived live, so the catalog seat (`BridgeStore.reconcileWalletSeats`)
    /// can gate "connected" synchronously the way `GnosisPayBridge.accounts()`
    /// does, without a network round trip on every foreground.
    private static let detectedKey = "wallet.safe.detected.v1"
    private static func rememberDetected(_ chain: Chain, _ safeAddress: String) {
        let entry = "\(chain.seg):\(safeAddress.lowercased())"
        var known = Set((UserDefaults.standard.array(forKey: detectedKey) as? [String]) ?? [])
        guard known.insert(entry).inserted else { return }
        UserDefaults.standard.set(Array(known), forKey: detectedKey)
    }
    static func detectedCount() -> Int {
        ((UserDefaults.standard.array(forKey: detectedKey) as? [String]) ?? []).count
    }

    /// Demo-only direct seed of the detected registry and the pending
    /// tracking snapshot (2026-08-11) — bypasses the network entirely, the
    /// `CloudflareEstateStore.save`/`ASCState.standing` shape every other
    /// bridge-STATE room head's demo seed already uses. `SafeRoomSource`
    /// reads bridge state, not `Thing` rows, so a demo corpus seeding only
    /// the `.transaction` things (`DemoSeedAll.wallet`) would leave
    /// `detectedCount() == 0` and the room head would never compose — this
    /// is the other half. NOT gated `#if DEBUG`: the furnished demo is a
    /// Release-reachable mode, and `demo-selftest.py` check A fails the
    /// build on a demo-facing seed function that isn't.
    static func seedDemoSnapshot(safeAddress: String,
                                 pending: [(ref: String, have: Int, required: Int,
                                           yourTurn: Bool, daysAgo: Double, descriptionText: String,
                                           nonce: Int?)]) {
        rememberDetected(chains[0], safeAddress)
        for p in pending {
            trackPending(ref: p.ref, seg: chains[0].seg, safeAddress: safeAddress, ownerAddress: safeAddress,
                        have: p.have, required: p.required, yourTurn: p.yourTurn,
                        submittedAt: Date.now.addingTimeInterval(-p.daysAgo * 86_400),
                        descriptionText: p.descriptionText, nonce: p.nonce)
        }
    }

    /// Unwinds `seedDemoSnapshot` — called from `DemoSeedAll.teardown`. Same
    /// accepted risk as Cloudflare/ASC's own demo teardown: one registry, no
    /// per-account key, so this can't tell a demo detection from a real one
    /// it might overwrite — exactly what `AccountScreen.demoReentryAvailable`
    /// exists to keep off a lived-in install.
    static func clearDemoSnapshot() {
        UserDefaults.standard.removeObject(forKey: detectedKey)
        saveTracking([:])
    }

    /// Every owner across every detected Safe, deduped — read straight off the
    /// config snapshots `syncConfig` already persists, so the roster costs no
    /// network at all and is available synchronously for a screen's body.
    /// Empty until at least one Safe's config has been read once.
    static func knownCoSigners() -> [String] {
        let detected = (UserDefaults.standard.array(forKey: detectedKey) as? [String]) ?? []
        var seen = Set<String>()
        var out: [String] = []
        for entry in detected {
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            guard let data = UserDefaults.standard.data(forKey: configSnapshotKey(parts[0], parts[1])),
                  let config = try? JSONDecoder().decode(SafeConfig.self, from: data) else { continue }
            for owner in config.owners where seen.insert(owner).inserted {
                out.append(owner)
            }
        }
        return out
    }

    /// One detected Safe's currently-enabled modules, read straight off the
    /// config snapshots `syncConfig` already persists (2026-08-03, prd §293)
    /// — so this costs no network at all, exactly like `knownCoSigners`.
    ///
    /// `syncConfig` has always ALERTED on a module being enabled, and that
    /// alert scrolls away with the rest of the stream. Nothing has ever stated
    /// the standing inventory: which modules can move this Safe's funds
    /// WITHOUT a signature, right now. That's what `WalletActingParties` asks
    /// for.
    struct SafeModules {
        let seg: String
        let safeAddress: String
        let modules: [String]
        let threshold: Int
        let ownerCount: Int
    }

    static func knownModules() -> [SafeModules] {
        let detected = (UserDefaults.standard.array(forKey: detectedKey) as? [String]) ?? []
        return detected.compactMap { entry in
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let data = UserDefaults.standard.data(forKey: configSnapshotKey(parts[0], parts[1])),
                  let config = try? JSONDecoder().decode(SafeConfig.self, from: data)
            else { return nil }
            return SafeModules(seg: parts[0], safeAddress: parts[1], modules: config.modules,
                               threshold: config.threshold, ownerCount: config.owners.count)
        }
    }

    /// Every Safe worth reading this pass for `addresses`: each address
    /// directly, PLUS every Safe it's a signer on that clears the spam
    /// filter (non-empty pending queue AND `nonce > 0` — a decoy naming a
    /// stranger as owner is free to deploy but costs the deployer real gas
    /// to also submit a pending tx to, and a never-executed Safe fails the
    /// nonce check even if someone bothers with a fake pending tx too).
    @MainActor
    private static func candidates(addresses: [String]) async -> [Candidate] {
        var out: [Candidate] = []
        var discovered = Set<String>()
        for chain in chains where isChainActive(chain) {
            for address in addresses {
                if let safe = await isSafe(chain: chain, address: address), safe {
                    rememberDetected(chain, address)
                    out.append(Candidate(chain: chain, safeAddress: address, viaOwner: nil))
                }
                guard let owned = await ownerSafes(chain: chain, address: address) else { continue }
                for safeAddress in owned {
                    guard let pending = await pendingQueue(chain: chain, address: safeAddress),
                          !pending.isEmpty else { continue }
                    guard let detail = await safeDetail(chain: chain, address: safeAddress),
                          detail.nonce > 0 else { continue }
                    rememberDetected(chain, safeAddress)
                    discovered.insert(safeAddress.lowercased())
                    out.append(Candidate(chain: chain, safeAddress: safeAddress, viaOwner: address))
                }
            }
        }
        return out
    }

    /// The chain's native gas token symbol — `WalletIngest.nativeSymbol`
    /// wherever a chain has a WalletChainStore id; Gnosis Chain (`network ==
    /// nil`, see `Chain`'s own doc) isn't in that table, so its native
    /// token is named here instead of guessed as "ETH".
    private static func nativeSymbol(_ chain: Chain) -> String {
        if let network = chain.network, let symbol = WalletIngest.nativeSymbol(forNetwork: network) {
            return symbol
        }
        return "xDAI"
    }

    private static func label(_ addr: String) -> String {
        WalletIngest.knownLabel(for: addr) ?? WalletStore.shortAddress(addr)
    }

    private static func param(_ params: [[String: Any]], _ name: String) -> String? {
        params.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String
    }

    // MARK: - Amounts (2026-08-11)

    private typealias TokenFacts = [String: (symbol: String?, decimals: Int?)]

    /// Every ERC-20 a batch of transactions might quote an amount for — a
    /// plain transfer/approve's own target, at any nesting level inside a
    /// multiSend batch — fetched ONCE per pass off the same cached-forever
    /// read the approvals card already uses, rather than once per
    /// transaction. Gnosis Chain (`chain.network == nil`) can't resolve a
    /// network id to key the read on, so it falls back to no amount stated
    /// there — the same "a read that answers with nothing states nothing"
    /// rule `tokenFacts` itself follows.
    private static func prefetchFacts(chain: Chain, txs: [[String: Any]]) async -> TokenFacts {
        guard let network = chain.network else { return [:] }
        var contracts = Set<String>()
        for tx in txs { contracts.formUnion(neededContracts(tx)) }
        guard !contracts.isEmpty else { return [:] }
        var out: TokenFacts = [:]
        for contract in contracts.prefix(12) {
            out[contract] = await WalletApprovals.tokenFacts(network: network, contract: contract)
        }
        return out
    }

    /// Every contract a decoded `transfer`/`approve` names as its target,
    /// top-level or nested inside a multiSend batch.
    private static func neededContracts(_ tx: [String: Any]) -> Set<String> {
        var out = Set<String>()
        func walk(_ decoded: [String: Any]?, to: String?) {
            guard let decoded, let method = decoded["method"] as? String else { return }
            if method == "multiSend" {
                let params = (decoded["parameters"] as? [[String: Any]]) ?? []
                for call in (batchCalls(params) ?? []) {
                    walk(call["dataDecoded"] as? [String: Any], to: call["to"] as? String)
                }
                return
            }
            if method == "transfer" || method == "approve", let to {
                out.insert(to.lowercased())
            }
        }
        walk(tx["dataDecoded"] as? [String: Any], to: tx["to"] as? String)
        return out
    }

    /// "1,500 USDC" for a decoded call's amount param, given its target
    /// contract's cached facts — nil when either isn't known, which leaves
    /// the caller's older, amount-free wording untouched rather than
    /// guessing at decimals.
    private static func tokenAmountText(contract: String?, rawParam: String?, facts: TokenFacts) -> String? {
        guard let contract, let rawParam, let raw = Double(rawParam),
              let fact = facts[contract.lowercased()],
              let symbol = fact.symbol, let decimals = fact.decimals
        else { return nil }
        return "\(WalletIngest.format(raw / pow(10, Double(decimals)))) \(symbol)"
    }

    /// "a transfer of 1,500 USDC to <label>" / "an approval for <label> to
    /// spend 1,500 USDC" / "an unlimited approval for <label>" / "a batch of
    /// 3 transfers" / "a rejection" / the decoded contract call's humanized
    /// method name / the honest "a transaction" when nothing is known —
    /// never a guess. `facts` (2026-08-11) names the amount when the target
    /// token's symbol/decimals are cached; absent, the older amount-free
    /// wording stands.
    private static func describe(_ tx: [String: Any], chain: Chain, safeAddress: String,
                                 facts: TokenFacts) -> String {
        if let decoded = tx["dataDecoded"] as? [String: Any] {
            return describe(decoded: decoded, fallbackTo: tx["to"] as? String, chain: chain, facts: facts)
        }
        let to = tx["to"] as? String
        let rawValue = Double(tx["value"] as? String ?? "0") ?? 0
        let dataStr = tx["data"] as? String
        let hasData = !(dataStr == nil || dataStr == "0x")
        // Safe's own "reject" shape: a zero-value, no-data call to the Safe
        // ITSELF, proposed solely to burn this nonce so a rival pending
        // transaction can never execute. It carries no `dataDecoded` (there's
        // nothing to decode), so without this check it fell through to the
        // generic "a transaction" — the one Safe-native action whose whole
        // point is that it moves nothing, described identically to a mystery.
        if rawValue == 0, !hasData, let to, to.lowercased() == safeAddress.lowercased() {
            return String(localized: "a rejection — blocks any other transaction at this nonce")
        }
        if rawValue > 0 {
            let amountText = "\(WalletIngest.format(rawValue / pow(10, 18))) \(nativeSymbol(chain))"
            if let to {
                return String(localized: "a transfer of \(amountText) to \(label(to))")
            }
            return String(localized: "a transfer of \(amountText)")
        }
        return String(localized: "a transaction")
    }

    /// One decoded call, described. Split out from `describe` so a batch's
    /// NESTED calls are named by the exact same rules as a top-level one.
    private static func describe(decoded: [String: Any], fallbackTo: String?, chain: Chain,
                                 facts: TokenFacts) -> String {
        guard let method = decoded["method"] as? String, !method.isEmpty else {
            return String(localized: "a transaction")
        }
        let params = (decoded["parameters"] as? [[String: Any]]) ?? []
        // A BATCH (2026-07-30). `multiSend` is not an edge case — it was 96 of
        // 100 transactions on a real measured Safe, because every Safe web-app
        // action that touches more than one thing bundles this way. Rendering
        // the overwhelmingly common case as "multi send" was honest and
        // useless. The nested calls arrive fully decoded on the parameter's
        // own `valueDecoded` (measured: 114 nested entries, each with its own
        // `dataDecoded`), so a batch is named by what it actually DOES.
        if method == "multiSend", let inner = batchCalls(params) {
            return describeBatch(inner, chain: chain, facts: facts)
        }
        if method == "transfer", let to = param(params, "to") {
            if let amountText = tokenAmountText(contract: fallbackTo, rawParam: param(params, "value"), facts: facts) {
                return String(localized: "a transfer of \(amountText) to \(label(to))")
            }
            return String(localized: "a transfer to \(label(to))")
        }
        if method == "approve", let spender = param(params, "spender") {
            // ERC-20's own max-uint256 approval, the same threshold the
            // approvals card prices a grant unlimited at — read here so the
            // two surfaces can never disagree about which grants are
            // unlimited.
            if let raw = param(params, "value").flatMap(Double.init), raw >= WalletApprovals.unlimitedThreshold {
                return String(localized: "an unlimited approval for \(label(spender))")
            }
            if let amountText = tokenAmountText(contract: fallbackTo, rawParam: param(params, "value"), facts: facts) {
                return String(localized: "an approval for \(label(spender)) to spend \(amountText)")
            }
            return String(localized: "an approval for \(label(spender))")
        }
        if params.isEmpty, let fallbackTo {
            return String(localized: "\(humanize(method)) on \(label(fallbackTo))")
        }
        return humanize(method)
    }

    /// The nested calls inside a `multiSend` parameter list, or nil when the
    /// service didn't decode them (an undecodable batch stays "multi send"
    /// rather than claiming a count it can't see).
    private static func batchCalls(_ params: [[String: Any]]) -> [[String: Any]]? {
        for p in params {
            if let decoded = p["valueDecoded"] as? [[String: Any]], !decoded.isEmpty {
                return decoded
            }
        }
        return nil
    }

    /// A batch named by its contents: one call describes itself, a uniform
    /// batch names its verb ("a batch of 12 transfers"), a mixed one stays
    /// honestly generic ("a batch of 5 actions") rather than naming whichever
    /// call happened to be first.
    private static func describeBatch(_ calls: [[String: Any]], chain: Chain, facts: TokenFacts) -> String {
        if calls.count == 1, let only = calls[0]["dataDecoded"] as? [String: Any] {
            return describe(decoded: only, fallbackTo: calls[0]["to"] as? String, chain: chain, facts: facts)
        }
        let methods = Set(calls.compactMap { ($0["dataDecoded"] as? [String: Any])?["method"] as? String })
        guard methods.count == 1, let verb = methods.first else {
            return String(localized: "a batch of \(calls.count) actions")
        }
        if verb == "transfer" {
            return String(localized: "a batch of \(calls.count) transfers")
        }
        return String(localized: "a batch of \(calls.count) \(humanize(verb)) calls")
    }

    /// "multiSend" → "multi send", "changeThreshold" → "change threshold" —
    /// splits an ABI method's camelCase on capitals. Purely cosmetic; never
    /// changes WHICH method is named, only how it reads.
    private static func humanize(_ method: String) -> String {
        var out = ""
        for (i, ch) in method.enumerated() {
            if ch.isUppercase {
                if i > 0 { out += " " }
                out.append(contentsOf: ch.lowercased())
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private static func hasSigned(_ tx: [String: Any], owner: String) -> Bool {
        let confs = (tx["confirmations"] as? [[String: Any]]) ?? []
        return confs.contains { ($0["owner"] as? String)?.lowercased() == owner.lowercased() }
    }

    // MARK: - The roster (2026-07-30)

    /// One owner of a Safe, and whether they've signed the transaction in
    /// hand. A Safe is the only object in this app where OTHER PEOPLE act on
    /// your behalf and you wait on them — every other bridge is solo. So the
    /// queue is rendered as the people it's actually waiting on, not as the
    /// fraction "2 of 3".
    struct Signer: Identifiable, Equatable {
        let address: String
        /// When they signed — nil means they haven't.
        let signedAt: Date?
        /// True for the watched wallet this Safe was reached through, so the
        /// roster can mark which seat is yours. False when we can't know
        /// (a directly-watched Safe doesn't say which of its N owners you are).
        let isYou: Bool
        var signed: Bool { signedAt != nil }
        var id: String { address }

        /// The person's own naming first (address book), then a Farcaster
        /// handle, then short hex — `WalletIngest.knownLabel`'s existing
        /// chain, which is exactly what it was built for.
        var displayName: String {
            WalletIngest.knownLabel(for: address) ?? WalletStore.shortAddress(address)
        }
    }

    /// The full owner roster for one pending transaction, in the Safe's own
    /// owner order (signed and unsigned alike — an unsigned owner is the whole
    /// point of the view). Empty when the Safe's config couldn't be read.
    private static func roster(owners: [String], tx: [String: Any], you: String?) -> [Signer] {
        let confs = (tx["confirmations"] as? [[String: Any]]) ?? []
        var signedAt: [String: Date] = [:]
        for c in confs {
            guard let owner = (c["owner"] as? String)?.lowercased() else { continue }
            // Safe stamps microseconds (6 fractional digits) — the exact shape
            // `ClaudeImport.parseDate` already handles tolerantly, rather than
            // a second ISO8601 formatter pair here that would drift from it.
            signedAt[owner] = ClaudeImport.parseDate(c["submissionDate"] as? String)
                ?? Date.distantPast
        }
        return owners.map { owner in
            Signer(address: owner,
                   signedAt: signedAt[owner.lowercased()],
                   isYou: you.map { $0.lowercased() == owner.lowercased() } ?? false)
        }
    }

    /// Reads every Safe this pass touches (watched directly, or watched
    /// through a signer) and lands a thing for every newly seen pending
    /// `safeTxHash`, plus a config-change alert for any Safe whose owners,
    /// threshold, modules, or guard drifted since last seen. Rides
    /// `WalletIngest.refresh` inside its running guard, like the other arms.
    @MainActor
    static func sync(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int {
        guard !addresses.isEmpty else { return 0 }
        var added = 0
        var heals: [Heal] = []
        var configChecked = Set<String>()   // one config check per (chain,safe) per pass
        for candidate in await candidates(addresses: addresses) {
            let chain = candidate.chain
            let safeAddress = candidate.safeAddress

            let configKey = "\(chain.seg)|\(safeAddress.lowercased())"
            if configChecked.insert(configKey).inserted,
               let detail = await safeDetail(chain: chain, address: safeAddress) {
                let owner = candidate.viaOwner ?? safeAddress
                if syncConfig(context: context, chain: chain, safeAddress: safeAddress,
                              ownerAddress: owner, existing: existing, config: detail.config) {
                    added += 1
                }
            }

            guard let pending = await pendingQueue(chain: chain, address: safeAddress) else { continue }
            let currentNonce = await safeDetail(chain: chain, address: safeAddress)?.nonce
            let facts = await prefetchFacts(chain: chain, txs: pending)
            for tx in pending {
                guard let safeTxHash = tx["safeTxHash"] as? String else { continue }
                // STRANDED: the Safe has already executed past this nonce, so
                // this transaction can never execute — its signatures are
                // spent. Landing it as "2 of 3 signatures collected" would
                // ask for a signature that cannot possibly help, which is the
                // dead control the honesty rule forbids. It still shows in
                // the sheet's own recheck (as `.replaced`) if it was landed
                // before it went stale, and `resolveTracking` below lands its
                // own closing thing the pass it goes stale.
                if let currentNonce, let txNonce = tx["nonce"] as? Int, txNonce < currentNonce {
                    continue
                }
                let ref = "wallet:safe:\(chain.seg):\(safeTxHash)"
                let required = (tx["confirmationsRequired"] as? Int) ?? 0
                let have = (tx["confirmations"] as? [[String: Any]])?.count ?? 0
                let description = describe(tx, chain: chain, safeAddress: safeAddress, facts: facts)
                // Only when we know exactly which of the Safe's owners is
                // "you" — reached via a signer's own watched EOA — can we
                // honestly say whose turn it is. Watching the Safe's own
                // address doesn't tell us which of its N owners you are.
                let yourTurn = candidate.viaOwner.map { !hasSigned(tx, owner: $0) } ?? false
                let face = rowFace(have: have, required: required, yourTurn: yourTurn,
                                   knowsYou: candidate.viaOwner != nil, description: description)
                if !existing.contains(ref) {
                    let thing = Thing(kind: .transaction, title: face.title,
                                      source: sourceName, sourceRef: ref)
                    thing.walletAddress = candidate.viaOwner ?? safeAddress
                    // Tagged structurally (not parsed from the title above) so
                    // `NotifySweep.classify` can tell "your turn" apart from
                    // "waiting on others" without the localized-string trap —
                    // the Stripe/Cursor/Apple-Wallet tag shape.
                    thing.tags = face.tags
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                    added += 1
                } else {
                    // ALREADY LANDED — and until 2026-08-17 that meant the row
                    // was never touched again, while `trackPending` below kept
                    // refreshing the very same counts for the room head. So the
                    // feed went on saying "2 of 3 — your signature is needed"
                    // after two more owners signed, or after YOU signed in the
                    // Safe app, until execution finally landed a closing row;
                    // the head one line above it said something else. Collected
                    // as a value and applied after the loop — see `heals`.
                    heals.append(Heal(ref: ref, title: face.title, tags: face.tags))
                }
                // Seed/refresh tracking so this pending transaction's eventual
                // resolution (executed, or replaced by a rival at the same
                // nonce) can land its own closing thing, and so
                // `SafeRoomSource` always reads this pass's live counts
                // rather than whatever was true when the thing first landed.
                trackPending(ref: ref, seg: chain.seg, safeAddress: safeAddress, ownerAddress: candidate.viaOwner,
                            have: have, required: required, yourTurn: yourTurn,
                            submittedAt: ClaudeImport.parseDate(tx["submissionDate"] as? String),
                            descriptionText: description, nonce: tx["nonce"] as? Int)
            }
            added += await resolveTracking(context: context, chain: chain, safeAddress: safeAddress,
                                           pending: pending, currentNonce: currentNonce, existing: existing)
        }
        let healed = apply(heals, context: context)
        if added > 0 || healed { context.saveHonestly() }
        return added
    }

    // MARK: - Keeping a landed row true

    /// One already-landed pending row's face as this pass reads it. A VALUE,
    /// collected inside the async walk and applied afterwards — never a
    /// `Thing` held across an `await`, which is the liveness class corollary 6
    /// exists for (`SafeBridge.sync` suspends on every chain, every queue read
    /// and every token-facts prefetch, and the app deletes `Thing`s on the
    /// main context throughout).
    private struct Heal {
        let ref: String
        let title: String
        let tags: [String]
    }

    /// Rewrites the landed rows whose face actually moved, and says whether
    /// anything changed.
    ///
    /// One fetch for the whole pass, taken HERE rather than before the walk so
    /// no model crosses a suspension, and the write is unconditional on
    /// nothing: a row whose title and tags already match is left alone, or
    /// every sync would dirty the context (and re-emit the feed's `@Query`)
    /// for a queue that hasn't moved in a week.
    @MainActor
    private static func apply(_ heals: [Heal], context: ModelContext) -> Bool {
        guard !heals.isEmpty else { return false }
        let landed = IngestSupport.thingsByRef(context, source: sourceName)
        var changed = false
        for heal in heals {
            guard let thing = landed[heal.ref], thing.isLive else { continue }
            guard thing.title != heal.title || thing.tags != heal.tags else { continue }
            thing.title = heal.title
            thing.tags = heal.tags
            SpotlightIndex.index([thing])
            changed = true
        }
        return changed
    }

    /// The title and tags one pending transaction wears — the SINGLE
    /// definition, read by both the landing path and the heal above so a row
    /// cannot say one thing when it arrives and another when it updates.
    ///
    /// "Ready to execute" is its own face rather than a fraction (2026-08-17).
    /// `have >= required` means the threshold is MET: nobody's signature is
    /// pending and what it waits on is an execution, so "3 of 3 signatures
    /// collected — waiting on others" was wrong twice in one line. §238 named
    /// this state for its delight toast and no row ever wore it.
    ///
    /// It also fixes a false alarm: `yourTurn` is `!hasSigned(you)` alone, so
    /// a 2-of-3 whose other two owners had both signed said "your signature is
    /// needed" and — since (7) — fired a lock-screen alarm for a transaction
    /// that needed nothing from you. The ready branch is tested FIRST, and the
    /// "Your turn" tag `NotifySweep` keys on now rides `awaitsYou`.
    ///
    /// The rule itself lives in `SafeRoom.Entry`, which is Foundation-only and
    /// harness-compiled — two copies of "what does ready mean" would drift,
    /// and then the feed row and the room head above it would disagree about
    /// the same transaction.
    static func rowFace(have: Int, required: Int, yourTurn: Bool, knowsYou: Bool,
                        description: String) -> (title: String, tags: [String]) {
        let entry = SafeRoom.Entry(ref: "", safeAddress: "", have: have, required: required,
                                   yourTurn: yourTurn, submittedAt: nil,
                                   descriptionText: description, nonce: nil)
        if entry.isReady {
            return (String(localized: "Fully signed — \(description) is ready to execute"),
                    ["Ready to execute"])
        }
        var title = String(localized: "\(have) of \(required) signatures collected on \(description)")
        // No suffix at all when the Safe is watched directly — see `yourTurn`'s
        // own note at the call site: we don't know which owner you are.
        guard knowsYou else { return (title, []) }
        if entry.awaitsYou {
            title += String(localized: " — your signature is needed")
            return (title, ["Your turn"])
        }
        title += String(localized: " — waiting on others")
        return (title, [])
    }

    // MARK: - Loop closers (2026-08-11)

    /// The "N of M signatures collected" thing opens a question the feed
    /// never used to answer: what happened? The threshold-met moment above
    /// closes it early, sometimes — but a Safe with a 1-of-1 threshold, or
    /// one where the last signature lands outside the app's own foreground
    /// pass, never crosses that moment at all, and a REPLACED transaction
    /// (a co-signer rejecting it, or a rival executing at the same nonce)
    /// never had a closing moment to begin with. This tracks every pending
    /// transaction this app has shown, and lands a second thing the pass it
    /// leaves the live queue — executed, or replaced — so the feed states
    /// an ending instead of just going quiet.
    /// The five new fields (2026-08-11) are all OPTIONAL on purpose, not
    /// because any of them is genuinely absent — every upsert below writes
    /// all five — but because a decode of the pre-2026-08-11 shape (`seg`/
    /// `safeAddress`/`ownerAddress` only) must not fail the WHOLE dictionary:
    /// `loadTracking`'s `try?` falls back to `[:]` on any decode error, which
    /// would silently drop every in-flight tracking entry on the update that
    /// ships this. Losing them is harmless self-healing (`sync` re-seeds
    /// within one pass), but a shape change should not be the reason.
    private struct TrackEntry: Codable {
        let seg: String
        let safeAddress: String
        let ownerAddress: String?
        var have: Int?
        var required: Int?
        var yourTurn: Bool?
        var submittedAt: Date?
        var descriptionText: String?
        /// The Safe's own nonce — the queue POSITION (2026-08-17). Two
        /// tracked transactions sharing one are rivals: a Safe executes
        /// exactly one per nonce, so a signature spent on the loser is spent
        /// for nothing (§238, which could state this in the sheet and not at
        /// the room head, because this field wasn't kept). Optional like its
        /// neighbours, so an entry written before this shipped decodes fine
        /// and picks the nonce up on the next sync pass.
        var nonce: Int?
    }
    private static let trackingKey = "wallet.safe.tracking.v1"

    private static func loadTracking() -> [String: TrackEntry] {
        guard let data = UserDefaults.standard.data(forKey: trackingKey),
              let decoded = try? JSONDecoder().decode([String: TrackEntry].self, from: data)
        else { return [:] }
        return decoded
    }
    private static func saveTracking(_ dict: [String: TrackEntry]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: trackingKey)
    }

    /// Seeds OR refreshes one pending transaction's tracking entry — called
    /// every pass for every live pending tx, not just newly-landed ones, so
    /// `have`/`required` stay current for `SafeRoomSource` even when no new
    /// `Thing` lands (2026-08-11). The loop-closer identity fields
    /// (`seg`/`safeAddress`/`ownerAddress`) are set once and never rewritten.
    private static func trackPending(ref: String, seg: String, safeAddress: String, ownerAddress: String?,
                                     have: Int, required: Int, yourTurn: Bool,
                                     submittedAt: Date?, descriptionText: String, nonce: Int? = nil) {
        var tracking = loadTracking()
        var entry = tracking[ref] ?? TrackEntry(seg: seg, safeAddress: safeAddress, ownerAddress: ownerAddress)
        entry.have = have
        entry.required = required
        entry.yourTurn = yourTurn
        entry.submittedAt = submittedAt
        entry.descriptionText = descriptionText
        entry.nonce = nonce
        tracking[ref] = entry
        saveTracking(tracking)
    }

    /// One currently-open pending transaction, for `SafeRoomSource` — the
    /// public-facing shape of `TrackEntry`, read fresh off the tracking store
    /// every call rather than cached again, since `loadTracking` is already a
    /// single UserDefaults read.
    struct PendingSnapshot {
        let ref: String
        let safeAddress: String
        let ownerAddress: String?
        let have: Int
        let required: Int
        let yourTurn: Bool
        let submittedAt: Date?
        let descriptionText: String
        /// The queue position — see `TrackEntry.nonce`. Nil for an entry
        /// tracked before 2026-08-17 and not yet re-seen by a sync pass;
        /// `SafeRoom` never treats an unknown position as a rival, so the
        /// gap costs a missing warning and never a false one.
        let nonce: Int?
    }

    /// Every pending transaction this app is currently watching for a
    /// resolution — i.e. exactly the set `resolveTracking` will check next
    /// pass. Costs no network: it is the loop-closer's own persisted state.
    static func pendingSnapshot() -> [PendingSnapshot] {
        loadTracking().map { ref, e in
            PendingSnapshot(ref: ref, safeAddress: e.safeAddress, ownerAddress: e.ownerAddress,
                            have: e.have ?? 0, required: e.required ?? 0, yourTurn: e.yourTurn ?? false,
                            submittedAt: e.submittedAt, descriptionText: e.descriptionText ?? "",
                            nonce: e.nonce)
        }
    }

    /// "under a day" / "a day" / "N days" — composes into both the executed
    /// and replaced closing sentences below.
    private static func elapsedPhrase(_ seconds: TimeInterval) -> String {
        let days = max(0, Int(seconds / 86_400))
        if days == 0 { return String(localized: "under a day") }
        if days == 1 { return String(localized: "a day") }
        return String(localized: "\(days) days")
    }

    /// Lands the closing thing for one resolved transaction and stops
    /// tracking it. Duration reads Safe's OWN `submissionDate`/`executionDate`
    /// (the transaction's real clock) rather than an app-observed timestamp —
    /// more accurate, and needs nothing persisted beyond the tracking entry
    /// itself.
    @MainActor
    private static func landOutcome(context: ModelContext, chain: Chain, hash: String, tx: [String: Any],
                                    executed: Bool, safeAddress: String, ownerAddress: String?,
                                    existing: Set<String>) async -> Int {
        let ref = "wallet:safeoutcome:\(chain.seg):\(hash)"
        guard !existing.contains(ref) else { return 0 }
        let facts = await prefetchFacts(chain: chain, txs: [tx])
        let description = describe(tx, chain: chain, safeAddress: safeAddress, facts: facts)
        let elapsed = ClaudeImport.parseDate(tx["submissionDate"] as? String).map { start -> String in
            let end = executed ? (ClaudeImport.parseDate(tx["executionDate"] as? String) ?? .now) : .now
            return elapsedPhrase(end.timeIntervalSince(start))
        }
        let title: String
        if executed {
            title = elapsed.map { String(localized: "Executed after \($0) — \(description) went through") }
                ?? String(localized: "Executed — \(description) went through")
        } else {
            title = elapsed.map {
                String(localized: "Replaced after \($0) — \(description) never executed; a rival transaction went through at the same nonce instead")
            } ?? String(localized: "Replaced — \(description) never executed; a rival transaction went through at the same nonce instead")
        }
        let thing = Thing(kind: .transaction, title: title, source: sourceName, sourceRef: ref)
        thing.walletAddress = ownerAddress ?? safeAddress
        context.insert(thing)
        SpotlightIndex.index([thing])
        return 1
    }

    /// Checks every tracked pending transaction for THIS (chain, Safe)
    /// against this pass's own queue read — no extra request for the common
    /// case (still pending). A tracked hash that vanished from the
    /// `executed=false` queue is executed (confirmed via the single-tx
    /// endpoint rather than assumed, so a flaky page can't read as a false
    /// "went through"); one that's still listed but now stranded (its nonce
    /// fell behind the Safe's current nonce) was replaced by a rival.
    @MainActor
    private static func resolveTracking(context: ModelContext, chain: Chain, safeAddress: String,
                                        pending: [[String: Any]], currentNonce: Int?,
                                        existing: Set<String>) async -> Int {
        var tracking = loadTracking()
        let scoped = tracking.filter {
            $0.value.seg == chain.seg && $0.value.safeAddress.lowercased() == safeAddress.lowercased()
        }
        guard !scoped.isEmpty else { return 0 }
        var byHash: [String: [String: Any]] = [:]
        for tx in pending {
            guard let h = tx["safeTxHash"] as? String else { continue }
            byHash[h] = tx
        }
        var added = 0
        for (ref, entry) in scoped {
            let hash = ref.split(separator: ":", maxSplits: 3).map(String.init).last ?? ""
            guard !hash.isEmpty else { tracking.removeValue(forKey: ref); continue }
            if let tx = byHash[hash] {
                let txNonce = tx["nonce"] as? Int
                if let currentNonce, let txNonce, txNonce < currentNonce {
                    added += await landOutcome(context: context, chain: chain, hash: hash, tx: tx,
                                               executed: false, safeAddress: safeAddress,
                                               ownerAddress: entry.ownerAddress, existing: existing)
                    tracking.removeValue(forKey: ref)
                }
                continue   // still live — leave tracked
            }
            guard let root = await IngestSupport.getJSON(
                    "\(baseURL(chain.seg))/multisig-transactions/\(hash)/") as? [String: Any]
            else { continue }   // unreachable this pass — recheck next time
            guard (root["isExecuted"] as? Bool) == true else { continue }
            added += await landOutcome(context: context, chain: chain, hash: hash, tx: root,
                                       executed: true, safeAddress: safeAddress,
                                       ownerAddress: entry.ownerAddress, existing: existing)
            tracking.removeValue(forKey: ref)
        }
        saveTracking(tracking)
        return added
    }

    // MARK: - Connect-time discovery (2026-08-13, prd §376)

    /// What `signerSafes` found, with "couldn't look" kept apart from "found
    /// none" (§85, the rule `FollowImportSheet` quotes: a read that FAILED and
    /// a read that found nothing are two different facts and never share a
    /// line). A connect picker that says "you sign on no Safes" because
    /// api.safe.global was down has stated something it doesn't know.
    struct SignerLookup {
        var safes: [WalletConnectPlan.FoundSafe] = []
        /// False when NO chain answered. A partial read is `true` with
        /// `truncated` set — some chains answering is still a real finding.
        var reachable = true
        /// Set when the budget or the cap cut the walk short, so the caller
        /// can say so rather than presenting a prefix as the whole list.
        var truncated = false
    }

    /// Every Safe that currently names one of `addresses` as an owner —
    /// BOUNDED, because this runs while somebody is waiting on a sheet.
    ///
    /// Three bounds, each measured against a real hazard rather than picked:
    ///
    /// (1) **The spam filter is `nonce > 0` PLUS current ownership.**
    ///     `/owners/{addr}/safes/` answers for any address ever named an
    ///     owner at deployment, and nothing requires that owner's consent —
    ///     measured 2026-07-30, vitalik.eth returns 59 on eth alone,
    ///     overwhelmingly not his. A decoy is free to deploy; one that has
    ///     actually EXECUTED something cost its deployer real gas. Ownership
    ///     is then re-confirmed against the Safe's own live owner list, since
    ///     the reverse index is not the same claim as "is an owner today".
    ///     This is deliberately WEAKER than `candidates`' filter, which also
    ///     demands a non-empty pending queue: that is right for a feed (only
    ///     surface what needs doing) and wrong here, because a Safe you use
    ///     every week has an empty queue most of the time and is exactly what
    ///     somebody connecting a wallet wants offered.
    ///
    /// (2) **A hard read cap.** The free tier is 2 RPS, so detailing 59
    ///     candidates is a 30-second sheet. `detailBudget` caps how many
    ///     Safes are confirmed per connect; the rest are not silently
    ///     dropped, they set `truncated`.
    ///
    /// (3) **A wall-clock budget**, `TodayBrief.liveReadBudget`'s shape: a
    ///     flaky host must not own a screen the person is standing in front
    ///     of. Missing the budget contributes nothing and says so.
    ///
    /// Solana accounts are skipped — Safe is EVM only, and asking about a
    /// base58 address is a request that can only ever 404.
    @MainActor
    /// `requireExecuted: false` drops the `nonce > 0` spam filter, and there
    /// is exactly one caller allowed to ask for that: `SafeSigner`, about the
    /// address THIS APP generated moments ago (prd §426 amendment). The filter
    /// exists because `/owners/{addr}/safes/` answers for any address ever
    /// named an owner and a decoy Safe is free to deploy — but a decoy has to
    /// be deployed naming an address that already exists, and a freshly
    /// generated 32-byte key has never appeared anywhere. So for that one
    /// address the spam risk is not merely low, it is impossible by
    /// construction — while a brand-new 2-of-2 the person just added us to
    /// has `nonce == 0` and would otherwise be invisible on the very screen
    /// that has to warn them about it.
    static func signerSafes(for addresses: [String],
                            budget: Duration = .seconds(8),
                            detailBudget: Int = 12,
                            requireExecuted: Bool = true) async -> SignerLookup {
        let owners = addresses.filter { ENS.isHexAddress($0) }
        guard !owners.isEmpty else { return SignerLookup() }

        let deadline = ContinuousClock.now.advanced(by: budget)
        var out = SignerLookup()
        var answered = false
        var details = 0
        var seen = Set<String>()

        for chain in chains where isChainActive(chain) {
            for owner in owners {
                guard ContinuousClock.now < deadline else {
                    out.truncated = true
                    out.reachable = answered
                    return out
                }
                guard let owned = await ownerSafes(chain: chain, address: owner) else { continue }
                answered = true
                for safeAddress in owned {
                    guard seen.insert(safeAddress.lowercased()).inserted else { continue }
                    guard details < detailBudget else { out.truncated = true; continue }
                    guard ContinuousClock.now < deadline else { out.truncated = true; break }
                    details += 1
                    guard let detail = await safeDetail(chain: chain, address: safeAddress),
                          !requireExecuted || detail.nonce > 0,
                          // The reverse index says "was named an owner"; this
                          // says "is one now". A removed signer must not be
                          // offered a wallet they can no longer act on.
                          detail.config.owners.contains(owner.lowercased())
                    else { continue }
                    out.safes.append(WalletConnectPlan.FoundSafe(address: safeAddress,
                                                                owner: owner,
                                                                chain: chain.seg))
                }
            }
        }
        out.reachable = answered
        return out
    }

    @MainActor private static var running = false

    /// A standalone sync for `SafeScreen`'s on-appear, matching
    /// `PeerBridge.syncNow`/`PrivacyPoolsBridge.syncNow`'s shape: resolves the
    /// watched wallets itself and reads the existing-refs set scoped to
    /// `sourceName` (2026-08-11 — Safe earned its own chip, so this is no
    /// longer the "Wallet" set `WalletIngest.refresh`'s own pass uses).
    @MainActor
    static func syncNow(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return 0 }
        return await sync(context: context, addresses: addresses,
                          existing: IngestSupport.existingSourceRefs(context, source: sourceName))
    }

    /// Phrases describing what changed between two config snapshots — empty
    /// when nothing that matters differs. Several can fire from ONE Safe
    /// transaction (e.g. `addOwnerWithThreshold` changes owners AND
    /// threshold together), so this always bundles into one landed thing
    /// rather than one per field.
    private static func configChangeDescriptions(old: SafeConfig, new: SafeConfig) -> [String] {
        var out: [String] = []
        let oldOwners = Set(old.owners), newOwners = Set(new.owners)
        for added in newOwners.subtracting(oldOwners).sorted() {
            let label = WalletIngest.knownLabel(for: added) ?? WalletStore.shortAddress(added)
            out.append(String(localized: "gained a new owner (\(label))"))
        }
        for removed in oldOwners.subtracting(newOwners).sorted() {
            let label = WalletIngest.knownLabel(for: removed) ?? WalletStore.shortAddress(removed)
            out.append(String(localized: "lost an owner (\(label))"))
        }
        if old.threshold != new.threshold {
            out.append(String(localized: "changed its signature threshold from \(old.threshold) to \(new.threshold)"))
        }
        let oldModules = Set(old.modules), newModules = Set(new.modules)
        // A module bypasses the owner threshold entirely — the highest-stakes
        // config fact this bridge can state, worded plainly rather than
        // folded into a generic "settings changed" line.
        for added in newModules.subtracting(oldModules).sorted() {
            let label = WalletIngest.knownLabel(for: added) ?? WalletStore.shortAddress(added)
            out.append(String(localized: "enabled a module (\(label)) that can move funds without a signature"))
        }
        for removed in oldModules.subtracting(newModules).sorted() {
            let label = WalletIngest.knownLabel(for: removed) ?? WalletStore.shortAddress(removed)
            out.append(String(localized: "removed a module (\(label))"))
        }
        if old.guardAddr != new.guardAddr {
            if let g = new.guardAddr {
                out.append(String(localized: "set a transaction guard (\(WalletIngest.knownLabel(for: g) ?? WalletStore.shortAddress(g)))"))
            } else {
                out.append(String(localized: "removed its transaction guard"))
            }
        }
        return out
    }

    private static func configSnapshotKey(_ seg: String, _ address: String) -> String {
        "wallet.safe.config.\(seg).\(address.lowercased())"
    }

    /// Lands a thing only when `config` differs from the last-seen snapshot
    /// for this (chain, safe) — first sight seeds the baseline silently
    /// (the `WalletSafety` delegation-cursor idiom: presence of the key, not
    /// its value, is "first sight", since a config that never changes would
    /// otherwise look identical to "never checked").
    @MainActor
    private static func syncConfig(context: ModelContext, chain: Chain, safeAddress: String,
                                   ownerAddress: String, existing: Set<String>,
                                   config: SafeConfig) -> Bool {
        let key = configSnapshotKey(chain.seg, safeAddress)
        let defaults = UserDefaults.standard
        let neverChecked = defaults.data(forKey: key) == nil
        let previous: SafeConfig? = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SafeConfig.self, from: $0) }
        guard let encoded = try? JSONEncoder().encode(config) else { return false }
        defaults.set(encoded, forKey: key)
        guard !neverChecked, let previous, previous != config else { return false }
        let phrases = configChangeDescriptions(old: previous, new: config)
        guard !phrases.isEmpty else { return false }
        let ref = "wallet:safeconfig:\(chain.seg):\(safeAddress.lowercased()):"
            + String(Int(Date.now.timeIntervalSince1970))
        guard !existing.contains(ref) else { return false }
        let title = phrases.count == 1
            ? String(localized: "Your Safe \(phrases[0])")
            : String(localized: "Your Safe's settings changed: \(phrases.joined(separator: ", "))")
        let thing = Thing(kind: .transaction, title: title, source: sourceName, sourceRef: ref)
        thing.walletAddress = ownerAddress
        // Tagged structurally, not parsed from `title` — a module can move
        // this Safe's funds WITHOUT a signature, which is the same shape of
        // news as an ERC-20/permit2 approval landing (`NotifySweep.classify`
        // reuses `.approvalGranted` for it rather than a near-duplicate kind).
        if !Set(config.modules).subtracting(previous.modules).isEmpty {
            thing.tags = ["Module added"]
        }
        context.insert(thing)
        SpotlightIndex.index([thing])
        return true
    }

    /// Each address's total ACTIONABLE pending-signature count — for a
    /// directly-watched Safe, every pending item (we don't know which owner
    /// "you" are, so the honest count is the whole queue); for a Safe
    /// reached through a signer, only the ones still missing THAT signer's
    /// signature, matching the "Worth doing" framing the warnings tray
    /// already gives `.safe` (an already-signed item isn't yours to act on
    /// anymore). Absent (not just zero) for an address with nothing pending
    /// anywhere. The Wallet screen's live summary row.
    /// What's pending for one address, and the door to it (2026-07-31, prd
    /// §241). The count was always here; `queueURL` is `SafeBridge`'s own
    /// verified `safeAppURL(chain:safeAddress:)` — built since 2026-07-30 and,
    /// until now, never handed to the one surface that asks a person to go
    /// sign something.
    ///
    /// `queueURL` is nil when this address's pending items span MORE THAN ONE
    /// Safe or chain: the count legitimately sums across them, and picking
    /// one queue to open would send someone to a page that doesn't hold most
    /// of what the row just counted. No door beats an arbitrary one.
    struct Pending: Equatable {
        var count: Int = 0
        var queueURL: String?
        /// Set once the second contributor lands, which is what makes
        /// `queueURL` nil — tracked rather than inferred, since two Safes can
        /// each contribute a legitimately different queue.
        var spansSafes = false
    }

    @MainActor
    static func pendingCounts(addresses: [String]) async -> [String: Pending] {
        guard !addresses.isEmpty else { return [:] }
        var out: [String: Pending] = [:]
        for candidate in await candidates(addresses: addresses) {
            var pending = await pendingQueue(chain: candidate.chain, address: candidate.safeAddress) ?? []
            // Stranded entries never count — see `sync`. A tray row asking for
            // a signature on a transaction that can no longer execute is a
            // dead control wearing a number.
            if let currentNonce = await safeDetail(chain: candidate.chain,
                                                   address: candidate.safeAddress)?.nonce {
                pending = pending.filter { ($0["nonce"] as? Int) ?? Int.max >= currentNonce }
            }
            let count: Int
            if let owner = candidate.viaOwner {
                count = pending.filter { !hasSigned($0, owner: owner) }.count
            } else {
                count = pending.count
            }
            guard count > 0 else { continue }
            let key = (candidate.viaOwner ?? candidate.safeAddress).lowercased()
            let door = safeAppURL(chain: candidate.chain, safeAddress: candidate.safeAddress)
            var entry = out[key] ?? Pending()
            entry.count += count
            if entry.queueURL == nil && !entry.spansSafes {
                entry.queueURL = door
            } else if entry.queueURL != door {
                // A second Safe (or the same Safe on another chain) — the
                // count keeps summing, the door drops out.
                entry.spansSafes = true
                entry.queueURL = nil
            }
            out[key] = entry
        }
        return out
    }

    // MARK: - Live recheck (the sheet card)

    struct Check {
        enum Status {
            /// Still in the queue — the live confirmation count.
            case pending(have: Int, required: Int)
            /// Executed — the transaction went through.
            case executed
            /// No longer pending and never executed — a different
            /// transaction executed at the same nonce instead (a Safe
            /// allows exactly one live transaction per nonce), so this one
            /// can never execute now.
            case replaced
        }
        let status: Status
        /// Every owner of the Safe, signed and unsigned — the people the
        /// queue is waiting on.
        var roster: [Signer] = []
        /// The person's own Safe app, open on this Safe's queue — the one
        /// action this app deliberately can't do.
        var doorURL: String?
        /// How many OTHER pending transactions share this one's nonce. A Safe
        /// executes exactly one transaction per nonce, so a conflict means
        /// signing this one may be wasted — the subtle multisig fact almost
        /// no interface surfaces.
        var conflicts: Int = 0
        /// The Safe has already executed past this nonce while this stayed
        /// pending: it can never execute now, and the signatures on it are
        /// spent. Distinct from `.replaced`, which is the same fact observed
        /// after the transaction left the queue.
        var stranded: Bool = false

        /// Waiting on whom, in words — nil when nobody is (threshold met) or
        /// when the roster couldn't be read.
        var waitingOn: [Signer] { roster.filter { !$0.signed } }
        /// True when the threshold is met and only execution remains.
        var readyToExecute: Bool {
            if case .pending(let have, let required) = status { return required > 0 && have >= required }
            return false
        }
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

    /// Re-fetches the single transaction by hash (verified live 2026-07-30 —
    /// the original bridge assumed only the whole-queue endpoint was safe to
    /// rely on) and, if it's no longer pending, checks the Safe's CURRENT
    /// nonce to tell "executed" apart from "replaced by a same-nonce tx"
    /// instead of conflating both into one "resolved" state.
    @MainActor
    static func outcome(for thing: Thing) async -> Outcome {
        // Build 256: a detached Task runs LATER than it was created, so this
        // row can already be deleted by the time this line does (prd §297).
        guard thing.isLive else { return .fail("That thing is no longer here.") }
        guard applies(to: thing), let ref = thing.sourceRef, let address = thing.walletAddress
        else { return .fail("not a safe thing") }
        let parts = ref.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count == 4 else { return .fail("malformed ref") }
        let seg = parts[2], safeTxHash = parts[3]
        guard let chain = chains.first(where: { $0.seg == seg }) else { return .fail("unknown chain") }
        guard isChainActive(chain) else { return .fail("chain switched off") }
        guard let root = await IngestSupport.getJSON(
                "\(baseURL(chain.seg))/multisig-transactions/\(safeTxHash)/") as? [String: Any]
        else { return .fail("unreachable") }
        // `thing.walletAddress` is either the Safe itself (directly watched)
        // or the signer that led us here — either way the transaction's own
        // `safe` field names the Safe to re-check nonce against.
        let safeAddress = (root["safe"] as? String) ?? address
        let door = safeAppURL(chain: chain, safeAddress: safeAddress)
        let detail = await safeDetail(chain: chain, address: safeAddress)
        // "You" is knowable only when the watched address is an OWNER and not
        // the Safe itself — the same rule the landing wording follows.
        let owners = detail?.config.owners ?? []
        let you = owners.contains(address.lowercased()) ? address : nil
        let people = roster(owners: owners, tx: root, you: you)

        let isExecuted = (root["isExecuted"] as? Bool) ?? false
        if isExecuted {
            return .ok(Check(status: .executed, roster: people, doorURL: door))
        }
        let txNonce = (root["nonce"] as? Int) ?? -1
        if let detail, detail.nonce > txNonce {
            return .ok(Check(status: .replaced, roster: people, doorURL: door))
        }
        let required = (root["confirmationsRequired"] as? Int) ?? 0
        let have = (root["confirmations"] as? [[String: Any]])?.count ?? 0
        // Same-nonce rivals still sitting in the queue: only one of them can
        // ever execute, so signing this one may be spent effort.
        var conflicts = 0
        if let pending = await pendingQueue(chain: chain, address: safeAddress) {
            conflicts = pending.filter {
                ($0["nonce"] as? Int) == txNonce && ($0["safeTxHash"] as? String) != safeTxHash
            }.count
        }
        return .ok(Check(status: .pending(have: have, required: required),
                         roster: people, doorURL: door, conflicts: conflicts))
    }

    /// `-safeProbe YES` — reports which watched wallets are detected Safes
    /// or Safe signers (per chain), their pending counts, and any config
    /// drift about to be flagged — or the honest unreachable/none.
    @MainActor
    static func probe() async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        var lines: [String] = []
        for chain in chains where isChainActive(chain) {
            for address in addresses {
                guard let safe = await isSafe(chain: chain, address: address) else {
                    lines.append("\(WalletStore.shortAddress(address)) \(chain.seg): unreachable")
                    continue
                }
                if safe {
                    let pending = await pendingQueue(chain: chain, address: address) ?? []
                    lines.append("\(WalletStore.shortAddress(address)) \(chain.seg): SAFE, \(pending.count) pending")
                }
                guard let owned = await ownerSafes(chain: chain, address: address), !owned.isEmpty else { continue }
                for safeAddress in owned {
                    let pending = await pendingQueue(chain: chain, address: safeAddress) ?? []
                    let nonce = await safeDetail(chain: chain, address: safeAddress)?.nonce ?? 0
                    guard !pending.isEmpty, nonce > 0 else { continue }
                    let yourTurn = pending.filter { !hasSigned($0, owner: address) }.count
                    let live = pending.filter { ($0["nonce"] as? Int) ?? Int.max >= nonce }
                    let stranded = pending.count - live.count
                    // Nonce rivalry across the WHOLE live queue — the count of
                    // positions holding more than one transaction.
                    let byNonce = Dictionary(grouping: live) { ($0["nonce"] as? Int) ?? -1 }
                    let contested = byNonce.values.filter { $0.count > 1 }.count
                    let facts = await prefetchFacts(chain: chain, txs: Array(live.prefix(3)))
                    let titles = live.prefix(3)
                        .map { describe($0, chain: chain, safeAddress: safeAddress, facts: facts) }
                        .joined(separator: "; ")
                    lines.append("\(WalletStore.shortAddress(address)) \(chain.seg): signer on "
                        + "\(WalletStore.shortAddress(safeAddress)), \(pending.count) pending "
                        + "(\(yourTurn) need your signature, \(stranded) stranded, "
                        + "\(contested) contested nonce\(contested == 1 ? "" : "s")) "
                        + "door=\(safeAppURL(chain: chain, safeAddress: safeAddress))"
                        + (titles.isEmpty ? "" : " → \(titles)"))
                }
            }
        }
        return lines.isEmpty ? "no Safes detected" : lines.joined(separator: " | ")
    }
}
