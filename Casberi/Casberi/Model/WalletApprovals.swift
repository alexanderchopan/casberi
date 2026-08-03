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
///
/// Permit2 grants (2026-07-20) ride the exact same pass: a second,
/// address-filtered `eth_getLogs` per (wallet, chain) reads Permit2's OWN
/// `Approval` event (a different mechanism from approving Permit2 itself,
/// which is just a plain ERC-20 approval already caught above) — same spam
/// filter, same land-once-then-recheck-live shape via `WalletPrepare`.
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

    /// Permit2 (2026-07-20) — Uniswap's canonical token-approval contract, the
    /// SAME address on every EVM chain here. Approving Permit2 itself is a
    /// plain ERC-20 `Approval` (already caught above); separately, Permit2's
    /// OWN contract tracks a per-spender allowance inside its storage — the
    /// grant apps built on Permit2 actually spend against, and the one worth
    /// surfacing. Address + topic0 both verified live (Etherscan/BaseScan/
    /// Arbiscan/PolygonScan/OP Etherscan for the address; Uniswap's own
    /// `IAllowanceTransfer.sol` + a keccak256 cross-check against
    /// 4byte.directory for the event) — don't re-derive without re-measuring.
    static let permit2Address = "0x000000000022d473030f116ddee9f6b43ac78ba3"
    /// `Approval(address indexed owner, address indexed token, address
    /// indexed spender, uint160 amount, uint48 expiration)` — 3 indexed topics
    /// plus topic0 = 4 total, distinct from the plain ERC-20 Approval's 3.
    /// Internal, not private: `WalletPrepare` re-reads a landed grant's log
    /// and needs to recognize this shape too.
    static let permit2ApprovalTopic =
        "0xda9fa7c1b00402c17d0161b249b1ab8bbec047c5a52207b9c112deffd817036b"

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

    /// Every landed approval/Permit2-grant thing on the given wallets whose
    /// LIVE on-chain state is still active (2026-07-23, prd §196) — the exact
    /// read `WalletPrepare`'s own prepare card runs when a thing's sheet
    /// opens, batched here so the Worth-a-look tray can warn about a grant
    /// that's still live without ever warning about one already revoked
    /// somewhere else. A landed approval thing is the EVENT of approving,
    /// which never expires on its own record — only a fresh read says
    /// whether it's still true.
    ///
    /// Sequential, not concurrent: `WalletPrepare.check` is `@MainActor`, and
    /// `Thing` isn't `Sendable`, so a `TaskGroup` closure can't capture one
    /// across a task boundary without a real refactor. A live-checked warning
    /// list is a handful of `eth_call`s at most in practice (this app has
    /// never approved anything itself) — not worth the risk for a read that
    /// already rides the same foreground-refresh cadence as the DeFi/Safe/
    /// delegation reads beside it.
    @MainActor
    /// Returns each still-active grant WITH the check that proved it active
    /// (2026-08-03) — the live allowance, the token contract and the chain.
    /// Handing the check back is what lets `WalletApprovalExposure` price the
    /// grant without re-running the two RPC reads this loop just paid for.
    static func activeApprovals(hexAddresses: [String], context: ModelContext)
        async -> [(thing: Thing, check: WalletPrepare.Check)] {
        let all = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == "Wallet" }
        ))) ?? []
        let candidates = all.filter { thing in
            WalletPrepare.applies(to: thing)
                && hexAddresses.contains { WalletWatch.sameAddress($0, thing.walletAddress ?? "") }
        }
        var active: [(thing: Thing, check: WalletPrepare.Check)] = []
        for thing in candidates {
            // Corollary 6: `check` awaits, so a Thing this loop deleted
            // out from under us must not be read on the next turn.
            guard thing.isLive else { continue }
            if let check = await WalletPrepare.check(for: thing), check.active {
                active.append((thing, check))
            }
        }
        return active
    }

    /// The prepare path (`WalletPrepare`, prd §112) rides this same measured
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

    /// The widest `eth_getLogs` block range this chain's measured hosts take
    /// — exposed so another file needing log pagination on these same
    /// public hosts (`UniswapLiquidity`'s activity sweep) reuses the
    /// measured number instead of re-guessing it (the `DeFiRisk` lesson: a
    /// threshold must not be able to disagree with itself across files).
    static func maxLogRange(forNetwork network: String) -> Int? {
        allChains.first { $0.network == network }?.maxRange
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
                    // Snapshot as immutable locals before the async lets —
                    // `scanned` is mutated below, and capturing the `var`
                    // itself into two concurrently-executing initializers is
                    // a Swift 6 concurrency error, not just a style nit.
                    let chunkFrom = scanned + 1
                    let to = min(scanned + chain.maxRange, latest)
                    // Both queries run concurrently — the Permit2 read (2026-07-20)
                    // doubles this loop's requests per chunk (bounded by
                    // `maxChunks`, so steady-state is +1 request per pass, not per
                    // chunk of a long catch-up). Either failing breaks the whole
                    // scan, same as before: `scanned` must never advance past a
                    // chunk this wallet's Permit2 grants weren't actually read for.
                    async let approvalChunk = fetchLogs(chain, owner: address,
                                                        from: chunkFrom, to: to)
                    async let permit2Chunk = fetchPermit2Logs(chain, owner: address,
                                                              from: chunkFrom, to: to)
                    guard let a = await approvalChunk, let p = await permit2Chunk
                    else { break }
                    logs += a
                    logs += p
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
                                existing: IngestSupport.existingSourceRefs(context, source: "Wallet"),
                                heldByOwner: held, ownedNFTs: owned)
    }

    // MARK: - Parsing

    private struct Event {
        /// The token/collection the grant concerns — for ERC-20/ForAll this
        /// is where the log originated (`log.address`); for a Permit2 grant
        /// the log originates from Permit2 itself, so this is the TOKEN
        /// address Permit2's event names instead (topics[2]). Either way it's
        /// what the held-tokens spam filter and `tokenMetadata` key on.
        let contract: String
        let spender: String
        let forAll: Bool
        /// True for a grant read off Permit2's own `Approval` event rather
        /// than the token's plain ERC-20 one — same story, different
        /// mechanism, so the title says so and the sourceRef gets its own
        /// namespace (`WalletPrepare` needs to read the allowance back
        /// through Permit2's own contract, not the token's).
        var viaPermit2 = false
        /// Raw approved value (ERC-20/Permit2) or the bool word (ForAll) — 0 is a REVOKE.
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
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String
            else { continue }

            let asset: String
            let spender: String
            let forAll: Bool
            let viaPermit2 = topic0 == permit2ApprovalTopic
            let rawValue: Double

            if viaPermit2 {
                // Permit2's own Approval: owner/token/spender all indexed
                // (topics[1..3]) — the token it concerns, not Permit2's own
                // address, is what the held-tokens filter and metadata key on.
                guard topics.count == 4 else { continue }
                asset = "0x" + topics[2].suffix(40).lowercased()
                spender = "0x" + topics[3].suffix(40).lowercased()
                forAll = false
                rawValue = permit2Amount((log["data"] as? String) ?? "0x0")
            } else {
                guard let contract = (log["address"] as? String)?.lowercased()
                else { continue }
                // 4 topics under the Approval signature = an ERC-721
                // single-token grant (indexed tokenId) — skipped, see
                // `approvalTopic`.
                if topic0 == approvalTopic, topics.count != 3 { continue }
                guard topics.count == 3, let spenderTopic = topics.last else { continue }
                asset = contract
                spender = "0x" + spenderTopic.suffix(40).lowercased()
                forAll = topic0 == forAllTopic
                rawValue = WalletIngest.hexToDouble((log["data"] as? String) ?? "0x0")
            }
            // The spam filter (lesson 2): an ERC-20/Permit2 approval counts
            // only for a token THIS wallet holds above the dust floor; an
            // operator grant only for a collection among ITS non-spam
            // holdings. A nil set means that wallet's read failed or found
            // nothing — closed either way (a fake story is worse than a late
            // one).
            if forAll {
                guard ownedNFTs?.contains(asset) == true else { continue }
            } else {
                guard held?.contains(asset) == true else { continue }
            }
            events.append(Event(
                contract: asset, spender: spender, forAll: forAll,
                viaPermit2: viaPermit2, rawValue: rawValue,
                block: WalletIngest.hexToInt(blockHex),
                txHash: txHash,
                logIndex: WalletIngest.hexToInt(indexHex)))
        }
        events = Array(events.suffix(10))
        guard !events.isEmpty else { return [] }

        let meta = await tokenMetadata(contracts: events.map(\.contract), chain: chain)
        let times = await blockTimes(blocks: events.map(\.block), chain: chain)

        var out: [Thing] = []
        var seen = Set<String>()
        for e in events {
            // A grant read off Permit2's own event gets its own namespace —
            // `WalletPrepare` needs to tell the two apart to read the live
            // allowance back through the right contract (Permit2 vs the
            // token itself).
            let ref = "wallet:\(e.viaPermit2 ? "permit2" : "approval"):\(chain.network):\(e.txHash):\(e.logIndex)"
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }
            let thing = Thing(
                kind: .transaction,
                title: title(for: e, meta: meta[e.contract]),
                content: revokeURL(address: owner, chainId: chain.chainId),
                source: "Wallet",
                capturedAt: times[e.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = owner
            // Only the REAL block time (2026-07-31) — never the `.now`
            // fallback `capturedAt` accepts one line up. The tray renders this
            // as "Granted Mar 2024", and a fallback rendered as a sentence
            // would date a years-old grant to today, understating the age of
            // precisely the approvals worth revoking. Unknown stays nil and
            // the row simply says nothing. See `Thing.grantedAt`.
            thing.grantedAt = times[e.block]
            thing.counterpartyAddress = e.spender
            // An approval names an asset too — "Approved Uniswap to spend
            // unlimited ÚЅDС" is the same lie in a more dangerous sentence,
            // since the thing you're being asked to trust IS the token
            // (prd §160, added in review 2026-07-21: the transfer arms were
            // flagged and this one was not, so the corpus disagreed with
            // itself about the same token).
            if let symbol = meta[e.contract]?.symbol {
                WalletSafety.flagSpoofedSymbol(thing, symbols: [symbol])
            }
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
        // The one clause that differs from a plain approval — same story,
        // a different mechanism, stated honestly rather than folded in silent.
        let via = e.viaPermit2 ? " through Permit2" : ""
        if e.forAll {
            return e.rawValue == 0
                ? String(localized: "Revoked \(spender)'s access to all \(asset)")
                : String(localized: "Approved \(spender) to manage all \(asset)")
        }
        if e.rawValue == 0 {
            return String(localized: "Revoked \(spender)'s \(asset) approval\(via)")
        }
        // The unlimited approval is THE thing worth knowing about — 2^256-1 in
        // practice (or Permit2's own uint160 max), but any astronomically-
        // over-supply value means the same.
        if e.rawValue >= unlimitedThreshold {
            return String(localized: "Approved \(spender) to spend unlimited \(asset)\(via)")
        }
        if let decimals = meta?.decimals {
            let amount = WalletIngest.format(e.rawValue / pow(10, Double(decimals)))
            return String(localized: "Approved \(spender) to spend \(amount) \(asset)\(via)")
        }
        return String(localized: "Approved \(spender) to spend \(asset)\(via)")
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
        return WalletIngest.hexToInt(hex)
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

    /// Permit2's own grants where the OWNER topic is this wallet — unlike
    /// `fetchLogs` above, ALSO address-filtered to Permit2 itself (its event
    /// is only meaningful read from that one contract).
    private static func fetchPermit2Logs(_ chain: Chain, owner: String,
                                        from: Int, to: Int) async -> [[String: Any]]? {
        let ownerTopic = "0x000000000000000000000000" + owner.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "address": permit2Address,
            "fromBlock": hex(from), "toBlock": hex(to),
            "topics": [permit2ApprovalTopic, ownerTopic],
        ]
        return await call(chain, method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// The first 32-byte word of a Permit2 `Approval` event's `data` — the
    /// `amount` (uint160); the second word (`expiration`, uint48) isn't
    /// needed for the approval story. Malformed/short data reads as 0 (a
    /// revoke), never a guess.
    private static func permit2Amount(_ data: String) -> Double {
        var s = data.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 64 else { return 0 }
        return WalletIngest.hexToDouble("0x" + s.prefix(64))
    }

    /// Where "unlimited" starts, in a token's raw units (2026-08-03). Named
    /// rather than spelled twice: the row title and `WalletApprovalExposure`
    /// must agree on which grants are unlimited, or the card would price a
    /// grant the row calls unlimited as if it were capped. (`DeFiRisk`'s
    /// lesson: a threshold must not be able to disagree with itself across
    /// files.) 2^256-1 in practice, or Permit2's uint160 max — any value
    /// astronomically past a real supply means the same thing.
    static let unlimitedThreshold: Double = 1e40

    /// Symbol + decimals for ONE token, cached forever (2026-08-03) — the
    /// exposure card's other half. Neither value can change for a deployed
    /// ERC-20, so a contract is asked once per install and never again; the
    /// card's marginal cost is one `eth_call` pair the first time a token
    /// appears in an approval, and nothing thereafter.
    ///
    /// A read that answers with nothing is NOT cached: a flaky public host
    /// would otherwise pin "we don't know this token's decimals" for the life
    /// of the install, and a missing `decimals` is what makes a capped grant
    /// unpriceable.
    static func tokenFacts(network: String, contract: String)
        async -> (symbol: String?, decimals: Int?) {
        let key = "wallet.tokenfacts.\(network).\(contract.lowercased())"
        let defaults = UserDefaults.standard
        if let cached = defaults.dictionary(forKey: key) {
            return (cached["symbol"] as? String, cached["decimals"] as? Int)
        }
        guard let chain = allChains.first(where: { $0.network == network }) else { return (nil, nil) }
        let facts = await tokenMetadata(contracts: [contract], chain: chain)[contract]
        guard let facts, facts.symbol != nil || facts.decimals != nil else { return (nil, nil) }
        var store: [String: Any] = [:]
        if let s = facts.symbol { store["symbol"] = s }
        if let d = facts.decimals { store["decimals"] = d }
        defaults.set(store, forKey: key)
        return facts
    }

    /// Symbol + decimals for the approved tokens — keyless (2026-07-19,
    /// replacing `alchemy_getTokenMetadata`): `symbol()`/`decimals()` read
    /// straight off the token contract via `eth_call` on the SAME public RPC
    /// hosts `fetchLogs`/`blockNumber` above already ride, no Alchemy
    /// involved at all. `symbol()` falls back to `name()` when it reverts —
    /// the same fallback Alchemy's own metadata call made, needed by the
    /// minority of pre-standard tokens that only implement one. One or two
    /// calls per unique contract, capped as a backstop (a pass lands at most
    /// 10 events per wallet per chain). Serial ON PURPOSE: the sibling
    /// timestamp reads hit the measured-flaky public hosts, and this whole
    /// path runs at most a handful of contracts on the rare pass that
    /// actually landed events. A contract that answers with nothing stays nil
    /// and the title falls back to its short hex.
    private static func tokenMetadata(contracts: [String], chain: Chain)
        async -> [String: (symbol: String?, decimals: Int?)] {
        var seen = Set<String>()
        let unique = contracts.filter { seen.insert($0).inserted }
        var out: [String: (symbol: String?, decimals: Int?)] = [:]
        for contract in unique.prefix(12) {
            async let symbolRet = call(chain, method: "eth_call",
                                       params: [["to": contract, "data": "0x95d89b41"], "latest"])
            async let decimalsRet = call(chain, method: "eth_call",
                                         params: [["to": contract, "data": "0x313ce567"], "latest"])
            var symbol = (await symbolRet as? String).flatMap(IngestSupport.decodeABIString)
            if symbol == nil {
                let nameRet = await call(chain, method: "eth_call",
                                         params: [["to": contract, "data": "0x06fdde03"], "latest"])
                symbol = (nameRet as? String).flatMap(IngestSupport.decodeABIString)
            }
            let decimals = (await decimalsRet as? String).map(WalletIngest.hexToInt)
            out[contract] = (symbol, decimals)
        }
        return out
    }

    /// Real timestamps for the events' blocks — an approval found after a week
    /// away should land dated when it happened, not when the app next opened.
    ///
    /// Covers every distinct block in the batch (2026-07-31), where it used to
    /// take the newest 8. The events themselves are already capped at 10, so
    /// this is at most two extra reads per chain per pass — and the two it
    /// used to drop were the OLDEST, which is backwards twice over: an old
    /// grant is the one whose date carries the most information, and since
    /// `grantedAt` is set only from a real read, a missing one is now a fact
    /// the tray declines to state rather than a slightly-off sort key.
    private static func blockTimes(blocks: [Int], chain: Chain) async -> [Int: Date] {
        var out: [Int: Date] = [:]
        for block in Set(blocks).sorted(by: >).prefix(10) {
            guard let b = await call(chain, method: "eth_getBlockByNumber",
                                     params: [hex(block), false]) as? [String: Any],
                  let ts = b["timestamp"] as? String else { continue }
            out[block] = Date(timeIntervalSince1970: WalletIngest.hexToDouble(ts))
        }
        return out
    }

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }
}
