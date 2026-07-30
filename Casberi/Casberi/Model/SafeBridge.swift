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
/// `matic`. Keyless access works (capped at 2 RPS on the free tier). The
/// Safe WEB APP's own door-URL chain-prefix could not be independently
/// verified for every chain in the time available (only "eth" was confirmed
/// live) — rather than guess and risk a dead/wrong link, this bridge omits
/// that door entirely; the card states counts and lets the person open their
/// own Safe app.
///
/// Re-verified live 2026-07-30 while adding (2)/(3): `/owners/{addr}/safes/`
/// answers per chain (vitalik.eth: 59 on eth, more on base — overwhelmingly
/// NOT his, confirming the spam-decoy risk above is real, not theoretical);
/// `/safes/{addr}/` carries `nonce`/`threshold`/`owners`/`modules`/`guard`;
/// `/multisig-transactions/{hash}/` exists (the original bridge assumed it
/// might not and always re-fetched the whole queue instead); and the `gno`
/// segment (Gnosis Chain) answers cleanly — not previously in this bridge's
/// chain list despite Gnosis Pay accounts being Safes themselves.
enum SafeBridge {

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
        noteDiscovery(count: discovered.count)
        return out
    }

    private static func label(_ addr: String) -> String {
        WalletIngest.knownLabel(for: addr) ?? WalletStore.shortAddress(addr)
    }

    private static func param(_ params: [[String: Any]], _ name: String) -> String? {
        params.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String
    }

    /// "a transfer to <label>" / "an approval for <label>" / "a batch of 3
    /// transfers" / the decoded contract call's humanized method name / the
    /// honest "a transaction" when nothing is known — never a guess.
    private static func describe(_ tx: [String: Any]) -> String {
        if let decoded = tx["dataDecoded"] as? [String: Any] {
            return describe(decoded: decoded, fallbackTo: tx["to"] as? String)
        }
        if let valueStr = tx["value"] as? String, let value = Double(valueStr), value > 0 {
            if let to = tx["to"] as? String {
                return String(localized: "a transfer to \(label(to))")
            }
            return String(localized: "a transfer")
        }
        return String(localized: "a transaction")
    }

    /// One decoded call, described. Split out from `describe` so a batch's
    /// NESTED calls are named by the exact same rules as a top-level one.
    private static func describe(decoded: [String: Any], fallbackTo: String?) -> String {
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
            return describeBatch(inner)
        }
        if method == "transfer", let to = param(params, "to") {
            return String(localized: "a transfer to \(label(to))")
        }
        if method == "approve", let spender = param(params, "spender") {
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
    private static func describeBatch(_ calls: [[String: Any]]) -> String {
        if calls.count == 1, let only = calls[0]["dataDecoded"] as? [String: Any] {
            return describe(decoded: only, fallbackTo: calls[0]["to"] as? String)
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
            for tx in pending {
                guard let safeTxHash = tx["safeTxHash"] as? String else { continue }
                // STRANDED: the Safe has already executed past this nonce, so
                // this transaction can never execute — its signatures are
                // spent. Landing it as "2 of 3 signatures collected" would
                // ask for a signature that cannot possibly help, which is the
                // dead control the honesty rule forbids. It still shows in
                // the sheet's own recheck (as `.replaced`) if it was landed
                // before it went stale.
                if let currentNonce, let txNonce = tx["nonce"] as? Int, txNonce < currentNonce {
                    continue
                }
                let ref = "wallet:safe:\(chain.seg):\(safeTxHash)"
                guard !existing.contains(ref) else { continue }
                let required = (tx["confirmationsRequired"] as? Int) ?? 0
                let have = (tx["confirmations"] as? [[String: Any]])?.count ?? 0
                var title = String(localized:
                    "\(have) of \(required) signatures collected on \(describe(tx))")
                // Only when we know exactly which of the Safe's owners is
                // "you" — reached via a signer's own watched EOA — can we
                // honestly say whose turn it is. Watching the Safe's own
                // address doesn't tell us which of its N owners you are.
                if let owner = candidate.viaOwner {
                    title += hasSigned(tx, owner: owner)
                        ? String(localized: " — waiting on others")
                        : String(localized: " — your signature is needed")
                }
                let thing = Thing(kind: .transaction, title: title, source: "Wallet", sourceRef: ref)
                thing.walletAddress = candidate.viaOwner ?? safeAddress
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
                noteThresholdIfMet(chain: chain, safeTxHash: safeTxHash,
                                   have: have, required: required, tx: tx)
            }
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    // MARK: - Moments (2026-07-30)

    /// The one moment in this feature that earns the berry rain: a pending
    /// transaction reaching its threshold. It's the release of real suspense
    /// — the thing you've been waiting days on can finally execute — and it's
    /// rare, which is the bar `SourceMoments` is held to everywhere else.
    ///
    /// Fired once per `safeTxHash`, on the TRANSITION into met (a transaction
    /// first seen already-complete is history, not news — the same
    /// seed-the-baseline-silently rule every sibling cursor obeys).
    @MainActor
    private static func noteThresholdIfMet(chain: Chain, safeTxHash: String,
                                           have: Int, required: Int, tx: [String: Any]) {
        guard required > 0, have >= required else { return }
        let key = "moment.safe.ready.\(chain.seg).\(safeTxHash)"
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(true, forKey: key)
        SourceMoments.shared.fire(
            String(localized: "Fully signed — \(describe(tx)) is ready to execute"),
            source: "Wallet")
    }

    /// The discovery moment: the reverse lookup found Safes this person is a
    /// signer on and never watched. Framed as an invitation, never an alarm —
    /// finding something FOR you is good news, and the same fact worded as a
    /// warning would read as an accusation. Fires once ever.
    @MainActor
    private static func noteDiscovery(count: Int) {
        guard count > 0 else { return }
        let key = "moment.safe.discovered.v1"
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(true, forKey: key)
        SourceMoments.shared.fire(
            count == 1
                ? String(localized: "You're a signer on a Safe — its queue is in your feed")
                : String(localized: "You're a signer on \(count) Safes — their queues are in your feed"),
            source: "Wallet")
    }

    @MainActor private static var running = false

    /// A standalone sync for `SafeScreen`'s on-appear, matching
    /// `PeerBridge.syncNow`/`PrivacyPoolsBridge.syncNow`'s shape: resolves the
    /// watched wallets itself and reads the existing-refs set scoped to
    /// "Wallet" (the same source `WalletIngest.refresh`'s own pass uses —
    /// Safe things fold into the Wallet feed rather than earning their own
    /// chip, like approvals and delegation already do).
    @MainActor
    static func syncNow(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return 0 }
        return await sync(context: context, addresses: addresses,
                          existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
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
        let thing = Thing(kind: .transaction, title: title, source: "Wallet", sourceRef: ref)
        thing.walletAddress = ownerAddress
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
    @MainActor
    static func pendingCounts(addresses: [String]) async -> [String: Int] {
        guard !addresses.isEmpty else { return [:] }
        var out: [String: Int] = [:]
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
            out[key, default: 0] += count
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
                    let titles = live.prefix(3).map(describe).joined(separator: "; ")
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
