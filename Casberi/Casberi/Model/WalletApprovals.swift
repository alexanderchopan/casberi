import Foundation
import SwiftData

/// Token approvals on watched wallets (2026-07-16, prd §84) — the wallet
/// bridge's security surface. A new `Approval` / `ApprovalForAll` event on a
/// watched wallet is a real "while I was away" moment ("Approved Uniswap to
/// spend unlimited USDC"), so it lands as a thing. Read-only like everything
/// here — REVOKING is an on-chain transaction Casberi never executes, so each
/// approval thing's content is the wallet's Revoke.cash page (the tool built
/// for exactly that), and the Wallet screen carries a per-wallet
/// "check approvals" door to the same place.
///
/// The economics that make this keyless-cheap: backfilling a wallet's FULL
/// approval history is the expensive read (Revoke.cash needs indexer keys for
/// it) — but watching NEW approvals forward is a filtered `eth_getLogs` per
/// wallet per chain per pass, tiny because the owner address is an indexed
/// topic. So the first sight of a wallet seeds a block cursor silently (the
/// NFT-arrival baseline idiom: no "40 approvals!" dump on connect) and every
/// later pass reads only the gap.
///
/// TWO lessons measured before shipping (2026-07-16):
/// (1) The app's Alchemy free tier caps eth_getLogs at a TEN-block range —
///     useless here. So the log reads ride each chain's public keyless RPC
///     instead (per-chain hosts + range caps below, all measured); only the
///     token-metadata call stays on Alchemy (its own method, not range-bound).
/// (2) Spam tokens EMIT FAKE Approval events with any famous address as the
///     owner topic — vitalik.eth "approved" 3,832 times across ~3,800 junk
///     contracts in one measured window, none signed by him. So an approval
///     lands only for a token THAT WALLET actually holds above the dust floor
///     (an operator grant, only for a collection it really owns) — per owner,
///     not pooled across the watch list — and the pass fails CLOSED (cursor
///     untouched, retry next pass) when the held set couldn't be read: a
///     fabricated "you approved X" is worse than a delayed one. The known
///     cost, accepted: an approval on a token the wallet has since fully spent
///     doesn't land (indistinguishable from spam without history) — the
///     Revoke.cash door still shows it one tap away.
enum WalletApprovals {

    /// The EVM chains approvals are read on: the keyless RPC hosts that
    /// actually serve wide `eth_getLogs` (tried in order), the widest block
    /// range each accepts (measured 2026-07-16 — don't raise without
    /// re-measuring), and the chain id Revoke.cash's address page takes.
    /// The wallet's other chains sit this out: Solana has no EVM approvals,
    /// and Robinhood Chain isn't on Revoke.cash — an approval thing whose
    /// "fix it" link can't show the approval would break the honesty rule.
    /// NOTE: membership here must keep up with `WalletChainStore.selectable`
    /// by hand — a new EVM chain added there is silently approval-blind until
    /// its host + range are measured and added here.
    private struct Chain {
        let network: String        // Alchemy id, matching WalletChainStore
        let chainId: Int           // Revoke.cash / EVM chain id
        let rpcs: [String]         // keyless hosts, first that answers wins
        let maxRange: Int          // widest getLogs block range the host takes
    }
    private static let allChains: [Chain] = [
        Chain(network: "eth-mainnet", chainId: 1,
              rpcs: ["https://rpc.mevblocker.io", "https://eth.api.onfinality.io/public"],
              maxRange: 900_000),
        Chain(network: "base-mainnet", chainId: 8453,
              rpcs: ["https://mainnet.base.org"], maxRange: 9_000),
        Chain(network: "arb-mainnet", chainId: 42161,
              rpcs: ["https://arb1.arbitrum.io/rpc"], maxRange: 450_000),
        Chain(network: "opt-mainnet", chainId: 10,
              rpcs: ["https://mainnet.optimism.io"], maxRange: 9_000),
        Chain(network: "matic-mainnet", chainId: 137,
              rpcs: ["https://polygon.api.onfinality.io/public"], maxRange: 90_000),
    ]
    private static var chains: [Chain] {
        let active = Set(WalletChainStore.activeNetworkIDs())
        return allChains.filter { active.contains($0.network) }
    }

    /// Chunks per (wallet, chain) pass — bounds the catch-up after a long
    /// absence. On the small-range chains (Base/Optimism, 9k blocks ≈ 5h)
    /// 16 chunks cover ~3 days; a longer gap scans the NEWEST window and
    /// accepts the hole (what changed recently matters most; an unbounded
    /// crawl of a shared public RPC serves no one). The hole is a known
    /// limit of the small-range chains, not a bug — the Revoke.cash door is
    /// the complete record either way.
    private static let maxChunks = 16

    /// ERC-20 `Approval(owner, spender, value)` — also emitted per-token by
    /// ERC-721s with a FOURTH topic (the indexed tokenId); those single-token
    /// grants are skipped below (low risk, high noise — Revoke.cash's own
    /// dashboard leads with allowances and operators too).
    private static let approvalTopic =
        "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"
    /// `ApprovalForAll(owner, operator, approved)` — the NFT operator grant.
    /// Internal, not private: `WalletPrepare` re-reads a landed approval's log
    /// and needs to tell the two shapes apart.
    static let forAllTopic =
        "0x17307eab39ab6107e8899845ad3d59bd9653f200f220920489ca2b5937696c31"

    /// The wallet's approvals dashboard on Revoke.cash — the address page is
    /// public and unauthenticated, takes a hex address OR an ENS name (both
    /// verified live 2026-07-16); chainId preselects the chain the event
    /// happened on (defaults to Ethereum without it).
    static func revokeURL(address: String, chainId: Int? = nil) -> String {
        var url = "https://revoke.cash/address/\(address)"
        if let chainId { url += "?chainId=\(chainId)" }
        return url
    }

    /// Whether Revoke.cash can serve this watched entry as stored — a hex
    /// address or an ENS name (their page resolves names). Solana forms are
    /// out (no EVM approvals there); a door to a 404 would be a dead control.
    static func canServe(_ address: String) -> Bool {
        ENS.isHexAddress(address)
            || (ENS.looksLikeName(address) && !SNS.looksLikeName(address))
    }

    /// The prepare path (`WalletPrepare`, prd §111) rides this same measured
    /// chain table — one table, so a chain added above serves the sync AND the
    /// prepare reads, and a network this table doesn't know honestly can't
    /// prepare. Reads only, like everything on these hosts.
    static func rpcRead(network: String, method: String, params: [Any]) async -> Any? {
        guard let chain = allChains.first(where: { $0.network == network }) else { return nil }
        return await call(chain, method: method, params: params)
    }

    static func chainId(forNetwork network: String) -> Int? {
        allChains.first { $0.network == network }?.chainId
    }

    private static func cursorKey(_ network: String, _ address: String) -> String {
        "wallet.approvals.cursor.\(network).\(address.lowercased())"
    }

    /// Unwatching takes the approval cursors with it (called from
    /// `WalletStore.addresses.didSet`, next to the value-history and
    /// high-water wipes) so re-watching seeds a fresh baseline instead of
    /// back-filling the unwatched gap into the feed — the same "re-watching
    /// starts honest, at zero" rule the sibling keys obey. A wallet stored as
    /// an ENS name misses (cursors key on the RESOLVED hex, which the store
    /// can't know synchronously) — its stale cursor is bounded by the chunk
    /// budget and orphaned keys are inert.
    static func clearCursors(address: String) {
        for chain in allChains {
            UserDefaults.standard.removeObject(forKey: cursorKey(chain.network, address))
        }
    }

    /// Two passes racing (the probe alongside a foreground refresh) could each
    /// read the same cursor and double-land — one runs, the other returns 0.
    @MainActor private static var running = false

    /// Reads new approval events for the given (resolved, hex) addresses and
    /// lands them as things. Returns the landed count. Called inside
    /// `WalletIngest.refresh`'s pass, so it rides every path that syncs the
    /// wallet (foreground refresh, the Wallet screen, probes) under the same
    /// running guard — and shares that pass's held-tokens / owned-NFTs reads
    /// for the spam filter. `heldByOwner` is keyed by lowercased owner, like
    /// `ownedNFTs`' "address|network" keys — per wallet, per lesson 2.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>, heldByOwner: [String: Set<String>]?,
                     ownedNFTs: [String: Set<String>]) async -> Int {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses,
                                existing: existing, heldByOwner: heldByOwner,
                                ownedNFTs: ownedNFTs)
    }

    /// The pass body — callers must hold `running`.
    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String],
                                   existing: Set<String>,
                                   heldByOwner: [String: Set<String>]?,
                                   ownedNFTs: [String: Set<String>]) async -> Int {
        guard !addresses.isEmpty else { return 0 }
        // Fail CLOSED without the held set (lesson 2 above): cursors stay put,
        // so nothing is lost — the gap simply lands next pass.
        guard let heldByOwner else { return 0 }
        let defaults = UserDefaults.standard
        var added = 0

        for chain in chains {
            guard let latest = await blockNumber(chain) else { continue }
            for address in addresses {
                let key = cursorKey(chain.network, address)
                guard let cursor = defaults.object(forKey: key) as? Int else {
                    // First sight: seed the baseline silently — history before
                    // the watch isn't ours to dump into the feed.
                    defaults.set(latest, forKey: key)
                    continue
                }
                guard latest > cursor else { continue }
                var from = cursor + 1
                let budget = chain.maxRange * maxChunks
                if latest - from >= budget { from = latest - budget + 1 }   // hole accepted
                // Chunked forward scan — a mid-scan failure keeps the cursor
                // at the last DURABLE point so the remainder retries next
                // pass instead of leaving a silent hole.
                var scanned = from - 1
                var logs: [[String: Any]] = []
                while scanned < latest {
                    let to = min(scanned + chain.maxRange, latest)
                    guard let chunk = await fetchLogs(chain, owner: address,
                                                      from: scanned + 1, to: to)
                    else { break }
                    logs += chunk
                    scanned = to
                }
                guard scanned > cursor else { continue }   // nothing read — transient
                // Land and SAVE before advancing the cursor — a cursor that
                // runs ahead of durability would turn an app kill during the
                // metadata fetches into permanently lost approvals (review
                // 2026-07-16). Refs can't collide across (wallet, chain)
                // pairs (the owner topic and network are both in the ref), so
                // `existing` staying fixed across the loop is sound.
                let landed = await things(from: logs, chain: chain, owner: address,
                                          existing: existing,
                                          held: heldByOwner[address.lowercased()],
                                          ownedNFTs: ownedNFTs["\(address.lowercased())|\(chain.network)"])
                if !landed.isEmpty {
                    for thing in landed {
                        context.insert(thing)
                        SpotlightIndex.index([thing])
                    }
                    guard context.saveHonestly() else { continue }   // unsaved → retry the gap next pass
                    added += landed.count
                }
                defaults.set(scanned, forKey: key)
            }
        }
        return added
    }

    /// `-approvalProbe <blocksBack|YES>` — runs the approval sync over the
    /// watched wallets headlessly. A numeric spec first rewinds every cursor
    /// that many blocks below each chain's head, so real past approvals land
    /// and the whole path (logs → spam filter → metadata → titles → things)
    /// verifies without waiting for a live approval to happen. Holds the
    /// running guard across the REWIND too — rewound cursors abandoned to a
    /// racing foreground refresh would land the old window into the real feed
    /// outside any probe (review 2026-07-16); waits briefly for an in-flight
    /// pass rather than reporting a misleading 0.
    @MainActor
    static func probe(context: ModelContext, blocksBack: Int?) async -> Int {
        for _ in 0..<60 where running {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !running else { return 0 }
        running = true
        defer { running = false }
        // Resolve names the way the real refresh does — a wallet watched as
        // "vitalik.eth" must probe as its hex, not be silently skipped.
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched)
            .filter { ENS.isHexAddress($0) }
        if let back = blocksBack {
            for chain in chains {
                guard let latest = await blockNumber(chain) else { continue }
                for address in addresses {
                    UserDefaults.standard.set(max(0, latest - back),
                                              forKey: cursorKey(chain.network, address))
                }
            }
        }
        let held = await WalletIngest.heldPricedContractsByOwner(addresses: addresses)
        let owned = await WalletIngest.ownedNFTContracts(addresses: addresses)
        return await syncLocked(context: context, addresses: addresses,
                                existing: IngestSupport.existingSourceRefs(context),
                                heldByOwner: held, ownedNFTs: owned)
    }

    // MARK: - Parsing

    private struct Event {
        let contract: String     // the token/collection that emitted it
        let spender: String
        let forAll: Bool
        /// Raw approved value (ERC-20) or the bool word (ForAll) — 0 is a REVOKE.
        let rawValue: Double
        let block: Int
        let txHash: String
        let logIndex: Int
    }

    /// Turns one pass's logs for one (owner, chain) into things — spam
    /// filtered against what THIS wallet really holds, then the newest 10 only
    /// (a busy gap folds to its recent tail rather than flooding the feed),
    /// deduped against the corpus and within the pair (a flaky public host
    /// could repeat a log).
    @MainActor
    private static func things(from logs: [[String: Any]], chain: Chain,
                               owner: String, existing: Set<String>,
                               held: Set<String>?,
                               ownedNFTs: Set<String>?) async -> [Thing] {
        var events: [Event] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String],
                  let topic0 = topics.first?.lowercased(),
                  let contract = (log["address"] as? String)?.lowercased(),
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String
            else { continue }
            // 4 topics under the Approval signature = an ERC-721 single-token
            // grant (indexed tokenId) — skipped, see `approvalTopic`.
            if topic0 == approvalTopic, topics.count != 3 { continue }
            guard topics.count == 3, let spenderTopic = topics.last else { continue }
            let forAll = topic0 == forAllTopic
            // The spam filter (lesson 2): an ERC-20 approval counts only for a
            // token THIS wallet holds above the dust floor; an operator grant
            // only for a collection among ITS non-spam holdings. A nil set
            // means that wallet's read failed or found nothing — closed either
            // way (a fake story is worse than a late one).
            if forAll {
                guard ownedNFTs?.contains(contract) == true else { continue }
            } else {
                guard held?.contains(contract) == true else { continue }
            }
            events.append(Event(
                contract: contract,
                spender: "0x" + spenderTopic.suffix(40).lowercased(),
                forAll: forAll,
                rawValue: WalletIngest.hexToDouble((log["data"] as? String) ?? "0x0"),
                block: Int(WalletIngest.hexToDouble(blockHex)),
                txHash: txHash,
                logIndex: Int(WalletIngest.hexToDouble(indexHex))))
        }
        events = Array(events.suffix(10))
        guard !events.isEmpty else { return [] }

        let meta = await tokenMetadata(contracts: events.map(\.contract), chain: chain)
        let times = await blockTimes(blocks: events.map(\.block), chain: chain)

        var out: [Thing] = []
        var seen = Set<String>()
        for e in events {
            let ref = "wallet:approval:\(chain.network):\(e.txHash):\(e.logIndex)"
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }
            let thing = Thing(
                kind: .transaction,
                title: title(for: e, meta: meta[e.contract]),
                content: revokeURL(address: owner, chainId: chain.chainId),
                source: "Wallet",
                capturedAt: times[e.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = owner
            thing.counterpartyAddress = e.spender
            out.append(thing)
        }
        return out
    }

    /// "Approved Uniswap to spend unlimited USDC" / "Revoked 1inch's USDC
    /// approval" / "Approved OpenSea to manage all Doodles". The spender is
    /// named only when honestly known (the person's label, a watched handle,
    /// or a canonical contract) — else its short hex; a title never invents.
    @MainActor
    private static func title(for e: Event, meta: (symbol: String?, decimals: Int?)?) -> String {
        let spender = WalletIngest.knownLabel(for: e.spender)
            ?? WalletStore.shortAddress(e.spender)
        let asset = meta?.symbol ?? WalletStore.shortAddress(e.contract)
        if e.forAll {
            return e.rawValue == 0
                ? String(localized: "Revoked \(spender)'s access to all \(asset)")
                : String(localized: "Approved \(spender) to manage all \(asset)")
        }
        if e.rawValue == 0 {
            return String(localized: "Revoked \(spender)'s \(asset) approval")
        }
        // The unlimited approval is THE thing worth knowing about — 2^256-1 in
        // practice, but any astronomically-over-supply value means the same.
        if e.rawValue >= 1e40 {
            return String(localized: "Approved \(spender) to spend unlimited \(asset)")
        }
        if let decimals = meta?.decimals {
            let amount = WalletIngest.format(e.rawValue / pow(10, Double(decimals)))
            return String(localized: "Approved \(spender) to spend \(amount) \(asset)")
        }
        return String(localized: "Approved \(spender) to spend \(asset)")
    }

    // MARK: - RPC reads (public keyless hosts; metadata rides Alchemy)

    private static func call(_ chain: Chain, method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": method, "params": params]
        for rpc in chain.rpcs {
            if let root = await IngestSupport.postJSON(rpc, body: body) as? [String: Any],
               let result = root["result"], !(result is NSNull) {
                return result
            }
        }
        return nil
    }

    private static func blockNumber(_ chain: Chain) async -> Int? {
        guard let hex = await call(chain, method: "eth_blockNumber", params: []) as? String
        else { return nil }
        return Int(WalletIngest.hexToDouble(hex))
    }

    /// Approval + ApprovalForAll logs where the OWNER topic is this wallet —
    /// filtered server-side by indexed topic, so even a wide block range
    /// answers small. nil when every host refused or errored the range.
    private static func fetchLogs(_ chain: Chain, owner: String,
                                  from: Int, to: Int) async -> [[String: Any]]? {
        let ownerTopic = "0x000000000000000000000000" + owner.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "topics": [[approvalTopic, forAllTopic], ownerTopic],
        ]
        return await call(chain, method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// Symbol + decimals for the approved tokens — Alchemy's own metadata
    /// method (not range-bound, so the free tier serves it fine), one call per
    /// unique contract, capped as a backstop (a pass lands at most 10 events
    /// per wallet per chain). Serial ON PURPOSE: the sibling timestamp reads
    /// hit the measured-flaky public hosts, and this whole path runs at most a
    /// handful of calls on the rare pass that actually landed events. A
    /// contract that answers with nothing stays nil and the title falls back
    /// to its short hex.
    private static func tokenMetadata(contracts: [String], chain: Chain)
        async -> [String: (symbol: String?, decimals: Int?)] {
        var seen = Set<String>()
        let unique = contracts.filter { seen.insert($0).inserted }
        let url = "https://\(chain.network).g.alchemy.com/v2/\(IngestSupport.alchemyKey)"
        var out: [String: (symbol: String?, decimals: Int?)] = [:]
        for contract in unique.prefix(12) {
            let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                       "method": "alchemy_getTokenMetadata",
                                       "params": [contract]]
            guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
                  let m = root["result"] as? [String: Any] else { continue }
            let symbol = ((m["symbol"] as? String) ?? (m["name"] as? String))
                .flatMap { $0.isEmpty ? nil : $0 }
            out[contract] = (symbol, m["decimals"] as? Int)
        }
        return out
    }

    /// Real timestamps for the events' blocks (capped) — an approval found
    /// after a week away should land dated when it happened, not when the app
    /// next opened. A block past the cap stamps .now, close enough for the
    /// tail of a busy pass.
    private static func blockTimes(blocks: [Int], chain: Chain) async -> [Int: Date] {
        var out: [Int: Date] = [:]
        for block in Set(blocks).sorted(by: >).prefix(8) {
            guard let b = await call(chain, method: "eth_getBlockByNumber",
                                     params: [hex(block), false]) as? [String: Any],
                  let ts = b["timestamp"] as? String else { continue }
            out[block] = Date(timeIntervalSince1970: WalletIngest.hexToDouble(ts))
        }
        return out
    }

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }
}
