import Foundation
import SwiftData

/// The wallet bridge (2026-07-08) — reads a public wallet's onchain activity
/// (received/sent, tokens in and out) across chains and lands it as things.
/// Called directly from this iPhone: no server. The address is public and
/// read-only — watching one can never trade or move funds.
///
/// EVM fungible activity rides Zerion first (2026-07-19, once Alchemy went
/// pay-as-you-go and hit quota): one `/transactions` call per wallet covers
/// every chain and both directions, replacing Alchemy's `alchemy_getAssetTransfers`
/// fan-out (up to 10 requests/wallet). Only when Zerion actually reaches a
/// wallet — a miss falls straight through to the original full Alchemy fetch
/// for that wallet (see `fetch`). NFT-category activity (erc721/erc1155)
/// keeps riding Alchemy UNCONDITIONALLY even when Zerion covers the fungible
/// side — this file has no measured Zerion NFT-transfer schema, and
/// degrading an NFT receipt to silently-dropped would be worse than the
/// small, cheap Alchemy call it still costs.
enum WalletIngest {

    /// Which family a chain belongs to — the wallet's two pipelines, not a
    /// cosmetic tag. Both read holdings through the same Zerion-first call
    /// (`collectCandidates`), but ACTIVITY forks: EVM rides Zerion-first/
    /// Alchemy-fallback here (`fetch`), Solana rides `SolanaActivity`
    /// (Alchemy, batched getSignaturesForAddress + getTransaction) —
    /// untouched for now, already cheap (2 requests/wallet) and its
    /// signing-based direction model doesn't map onto Zerion's fungible
    /// `Transfer` shape the way EVM's from/to model does. Same feed either
    /// way.
    private enum ChainKind { case evm, solana }

    /// Every chain we CAN read, and where a tx opens. One `getAssetTransfers`
    /// per direction per EVM chain.
    private struct Chain {
        let network, explorer, symbol, displayName: String
        var kind: ChainKind = .evm
        /// The native coin's decimals. The Portfolio endpoint returns a native
        /// balance with NULL metadata, so this can't be read off the response —
        /// and getting it wrong is silent, not loud: SOL scaled by 10^18 instead
        /// of 10^9 computes to $0.00005, drops under `holdingFloor`, and the
        /// coin simply vanishes from the treemap (measured 2026-07-16).
        var nativeDecimals: Int = 18
    }
    private static let allChains: [Chain] = [
        Chain(network: "eth-mainnet",  explorer: "https://etherscan.io/tx/",              symbol: "ETH",   displayName: "Ethereum"),
        Chain(network: "base-mainnet", explorer: "https://basescan.org/tx/",              symbol: "ETH",   displayName: "Base"),
        Chain(network: "arb-mainnet",  explorer: "https://arbiscan.io/tx/",               symbol: "ETH",   displayName: "Arbitrum"),
        Chain(network: "opt-mainnet",  explorer: "https://optimistic.etherscan.io/tx/",   symbol: "ETH",   displayName: "Optimism"),
        Chain(network: "matic-mainnet",explorer: "https://polygonscan.com/tx/",           symbol: "MATIC", displayName: "Polygon"),
        Chain(network: "solana-mainnet", explorer: "https://solscan.io/tx/",              symbol: "SOL",   displayName: "Solana",
              kind: .solana, nativeDecimals: 9),
        Chain(network: "robinhood-mainnet", explorer: "https://robinhoodchain.blockscout.com/tx/", symbol: "ETH", displayName: "Robinhood"),
    ]

    /// The chain a landed transfer belongs to, read off its stored explorer
    /// link (exact prefix match, so etherscan.io never claims
    /// optimistic.etherscan.io's links). The thing sheet's stage subline —
    /// kept HERE so a new chain can't reach transfers without also naming
    /// itself (the catalog-drift class).
    static func chainName(forContent content: String) -> String? {
        allChains.first { content.hasPrefix($0.explorer) }?.displayName
    }

    /// The chain's native coin symbol ("ETH", "MATIC", "SOL") — the prepare
    /// path's fee line (WalletPrepare, prd §112) quotes fees in it. Read off
    /// THIS table so a fee can never disagree with the treemap's own label
    /// (review 2026-07-17: a hand-rolled second map said "POL" where the
    /// holdings screen says "MATIC").
    static func nativeSymbol(forNetwork network: String) -> String? {
        allChains.first { $0.network == network }?.symbol
    }

    /// The chain's own address-page URL (2026-07-20, for the EIP-7702
    /// delegation thing's content link) — not a mechanical fact of its own:
    /// every explorer here is Etherscan-family and takes `/address/<addr>`
    /// the same way `/tx/<hash>` names a transaction, so this is a rewrite of
    /// the SAME measured `explorer` prefix `chainName(forContent:)` already
    /// reads, not a second host to keep in sync.
    static func explorerAddressURL(forNetwork network: String, address: String) -> String? {
        guard let tx = allChains.first(where: { $0.network == network })?.explorer else { return nil }
        return tx.replacingOccurrences(of: "/tx/", with: "/address/") + address
    }

    /// The chain's own display name ("Base", "Arbitrum") — for a title clause
    /// that names WHICH chain a cross-chain signal happened on (2026-07-20,
    /// the Aave health-factor alert).
    static func displayName(forNetwork network: String) -> String? {
        allChains.first { $0.network == network }?.displayName
    }

    /// The chains actually read this pass — the person's selection (default: all
    /// of them). Filtered from `allChains` so turning a chain off drops it from
    /// the transfer sync, the holdings read, and the value samples alike, and
    /// spends no requests on it. Read off Observation (`activeNetworkIDs`), so
    /// the background holdings fetches can call it safely (2026-07-15).
    private static var chains: [Chain] {
        let active = Set(WalletChainStore.activeNetworkIDs())
        return allChains.filter { active.contains($0.network) }
    }

    /// The chains the TRANSFER sync reads — EVM only, since that pipeline IS
    /// `getAssetTransfers`. Firing it at `solana-mainnet` would spend a request
    /// per watched address per direction to be told the method doesn't exist.
    private static var transferChains: [Chain] { chains.filter { $0.kind == .evm } }

    /// The networks one address can actually live on, by its SHAPE — base58
    /// reads Solana, `0x…` reads the EVM chains. This is what makes Solana free
    /// for an EVM-only person: their wallets never carry `solana-mainnet` into
    /// the holdings call, so turning it on costs them no requests. (The endpoint
    /// tolerates the mismatch — measured 2026-07-16, it returns nothing for the
    /// wrong pair rather than 400ing — but paying for a guaranteed-empty read on
    /// every address every foreground is waste, not safety.)
    private static func networks(for address: String) -> [String] {
        let wantsSolana = SNS.isAddress(address)
        return chains.filter { ($0.kind == .solana) == wantsSolana }.map(\.network)
    }

    @MainActor private static var running = false

    /// The USD floor a holding must clear to count (ruling 2026-07-15, up from
    /// $1). Airdrop-spam tokens that carry a fake price were sneaking past the
    /// old $1 line and inflating the "across N tokens" count / treemap; $1.99
    /// drops the dust while keeping genuine small positions.
    static let holdingFloor: Double = 1.99

    /// The upper sanity bound a single priced position must stay UNDER to count
    /// (2026-07-17). Symmetric to `holdingFloor`. A fake-priced airdrop can
    /// report an astronomically large on-chain balance that, times any nonzero
    /// price, computes to a garbage or non-finite USD value (`hexToDouble` of a
    /// huge/overlong balance hex → a >1e59 amount, even ±Infinity). Such a
    /// token isn't a real holding: no single position approaches $1T. Left
    /// unfiltered it poisoned the aggregated total AND crashed the treemap's
    /// `Int(usd.squareRoot() * 10)` cell-scaling on a tester's wallet (a
    /// non-finite / out-of-range `Double`→`Int` is a hard runtime trap), while
    /// loading fine for a dev whose wallets held no such token.
    static let holdingCeiling: Double = 1e12

    /// Reads recent transfers for every watched address, across chains, and
    /// lands new ones. Returns the new count, or nil when nothing could be
    /// reached at all (offline / bad key).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let watched = WalletStore.shared.addresses.map(\.address)
        guard !watched.isEmpty, !running else { return watched.isEmpty ? nil : 0 }
        running = true
        defer { running = false }

        // Watched entries can be ENS or `.sol` names; the APIs need an address —
        // resolve first, or nothing ever lands (the bug: a watched name
        // returned empty silently).
        let addresses = await resolvedAddresses(watched)
        guard !addresses.isEmpty else { return nil }
        // The transfer sync is EVM-only, so a Solana wallet contributes nothing
        // here — it still reads holdings below. A person watching ONLY Solana
        // has no transfer jobs at all, which must not read as "unreachable":
        // `reachedAny` stays false, and the holdings path is what speaks.
        let evmAddresses = evmOnly(addresses)

        let existing = IngestSupport.existingSourceRefs(context)
        // The cross-provider safety net for the Zerion cutover (2026-07-19):
        // a transfer Alchemy already landed carries a stable `content`
        // permalink (`chain.explorer + hash`) independent of whatever ref
        // scheme produced it. See `IngestSupport.existingContent`.
        let existingWalletContent = IngestSupport.existingContent(context, source: "Wallet")

        // Zerion first for EVM fungible activity — one request per wallet,
        // covering every chain and both directions at once. Only used for a
        // wallet where it actually answers (`zerionByAddress[addr] != nil`);
        // a miss leaves that wallet's entry absent and `fetch` falls through
        // to the original full Alchemy call for it.
        let zerionResults = await IngestSupport.boundedGather(evmAddresses, maxConcurrent: 4) { addr in
            (addr.lowercased(), await ZerionAPI.transactions(address: addr))
        }
        // `uniquingKeysWith`, not `uniqueKeysWithValues`: two watched entries
        // (an ENS name and its raw hex, say) can resolve to the SAME address,
        // and `evmAddresses` carries no uniqueness guarantee — a duplicate key
        // would crash `uniqueKeysWithValues` on every refresh for that wallet.
        let zerionByAddress = Dictionary(zerionResults, uniquingKeysWith: { first, _ in first })

        // Every (address, chain, direction) combination is an independent
        // network call — fetched serially before, up to
        // `addresses × chains × 2` round trips in a row on every foreground
        // (2026-07-13: seconds of wall-clock for a couple of watched
        // wallets). Fanned out, capped at 4 in flight — Alchemy's free-tier
        // key rate-limits per second, and an uncapped burst (up to 30
        // requests for 3 wallets) drew silent 429s that the old serial
        // pacing never triggered (review 2026-07-13). `boundedGather`
        // preserves job order, matching `topHoldingsByWallet` below.
        let jobs = evmAddresses.flatMap { address in
            transferChains.flatMap { chain in
                [true, false].map { received in (address, chain, received) }   // received (to) + sent (from)
            }
        }
        let results = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            let (address, chain, received) = job
            let zerion = zerionByAddress[address.lowercased()] ?? nil
            return (address, chain, received,
                   await fetch(address: address, chain: chain, received: received, zerion: zerion))
        }

        // A hash whose SWAP already landed (ref "wallet:swap:<network>:<hash>")
        // must keep BOTH its legs suppressed forever — the legs' own per-uid
        // refs were never persisted (only the swap's was), so without this
        // every later refresh would re-fetch them and re-land the same trade.
        let swappedHashes = Set(existing.compactMap { ref -> String? in
            ref.hasPrefix("wallet:swap:") ? String(ref.dropFirst("wallet:swap:".count)) : nil
        })

        var reachedAny = false
        var fresh: [Leg] = []
        var seenThisPass = Set<String>()
        for (address, chain, received, transfers) in results {
            guard let transfers else { continue }
            reachedAny = true
            for t in transfers {
                guard let uid = t["uniqueId"] as? String else { continue }
                let ref = "wallet:\(uid)"
                // A transfer between two watched addresses comes back from
                // BOTH queries with the same uniqueId — land it once.
                guard !existing.contains(ref), seenThisPass.insert(ref).inserted
                else { continue }
                let leg = Leg(t: t, chain: chain, received: received, ref: ref, address: address)
                // Already folded into a landed swap — never re-land its legs.
                if !leg.hash.isEmpty,
                   swappedHashes.contains("\(chain.network):\(leg.hash)") { continue }
                // The Zerion-cutover safety net (2026-07-19): this exact
                // transaction may already be landed under an Alchemy-sourced
                // ref this pass's `ref` set can't see (different uid scheme
                // entirely) — its permalink can. See `zerionTransferDict`.
                if !leg.hash.isEmpty,
                   existingWalletContent.contains(chain.explorer + leg.hash) { continue }
                fresh.append(leg)
            }
        }
        // Gas spent (2026-07-20): one receipt read per NEW outgoing tx this
        // wallet initiated this pass, deduped by (chain, address, hash) — a
        // batch tx can produce several legs but pays gas once. Doesn't touch
        // `added`/`reached`: a running total isn't a landed thing. Computed
        // here (from `fresh`, before it's landed), but NOT accumulated until
        // after the corresponding things are durably saved below — see the
        // note there.
        var seenGasTxs = Set<String>()
        let gasJobs: [WalletGas.Job] = fresh
            .filter { !$0.received && !$0.hash.isEmpty }
            .compactMap { leg in
                let key = "\(leg.chain.network)|\(leg.address.lowercased())|\(leg.hash)"
                guard seenGasTxs.insert(key).inserted else { return nil }
                return WalletGas.Job(network: leg.chain.network, address: leg.address, hash: leg.hash)
            }
        // Name the new transfers' counterparties BEFORE landing them — a
        // title is written once, so the name has to be there at write time.
        let names = await counterpartyNames(for: fresh)
        // The tokens the wallet actually HOLDS above the dust floor — an
        // airdrop-spam token that was never really held (unpriced, or under the
        // floor) is dropped from the ACTIVITY feed too now (2026-07-15), the
        // same way the holdings treemap already drops it. One batched read for
        // the whole pass.
        let heldByOwner = await heldPricedContractsByOwner(addresses: addresses)
        let heldPriced = heldByOwner.map { Set($0.values.joined()) }
        // …and the non-spam NFT contracts each wallet holds, for the NFT arm of
        // the same filter — an airdropped junk NFT is dropped from the feed the
        // way a junk token is (2026-07-15). Keyed "address|network". EVM only:
        // `getContractsForOwner` is an EVM method, and the legs it filters are
        // EVM legs anyway.
        let ownedNFTs = await ownedNFTContracts(addresses: evmAddresses)

        // Fold each wallet's legs by (address, chain, tx hash): a hash that
        // BOTH sends and receives for one wallet is a trade — one
        // "Swapped 0.5 ETH → 1,200 USDC on Uniswap" thing, not two half-stories
        // (a lone "Sent to Uniswap" and a lone "Received from Uniswap"). A hash
        // that only sends, or only receives, stays one thing per leg.
        var groups: [String: [Leg]] = [:]
        var order: [String] = []
        for leg in fresh {
            let key = "\(leg.address)|\(leg.chain.network)|\(leg.hash)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(leg)
        }

        // Address-poisoning tagging (2026-07-20): addresses THIS wallet has
        // sent to are the unambiguous trust anchor — never the received
        // side, which is exactly what a poisoner controls. One fetch for the
        // whole pass, before the per-leg loop below needs it.
        let knownGoodByOwner = WalletSafety.knownGoodCounterparties(context: context, owners: evmAddresses)

        var landed: [Thing] = []
        for key in order {
            let legs = groups[key]!
            let sends = legs.filter { !$0.received }
            let receives = legs.filter { $0.received }
            // Both directions with DIFFERENT assets = a swap (same asset both
            // ways is a wrap/self-route — left per-leg). The largest send and
            // largest receive are the trade; smaller same-hash legs are its fee
            // dust and fold in silently.
            if let sMax = sends.max(by: { $0.value < $1.value }),
               let rMax = receives.max(by: { $0.value < $1.value }),
               sMax.asset.uppercased() != rMax.asset.uppercased() {
                let swapRef = "wallet:swap:\(sMax.chain.network):\(sMax.hash)"
                guard !existing.contains(swapRef),
                      let thing = swapThing(sent: sMax, received: rMax, ref: swapRef, names: names)
                else { continue }
                landed.append(thing)
                continue
            }
            for leg in legs {
                // A received token/NFT the wallet doesn't actually hold (a junk
                // airdrop pushed at you) is dropped from the feed, mirroring the
                // holdings dust rule. Sends are never spam (you don't spam-send);
                // native coins always pass. Both arms fail OPEN — a failed
                // holdings/NFT read leaves the key/set nil, so a hiccup never
                // eats real activity.
                if leg.received, let contract = leg.contract {
                    // Spam TOKEN: a received ERC-20 not held above the floor.
                    if leg.category == "erc20", let heldPriced,
                       !heldPriced.contains(contract) { continue }
                    // Spam NFT: a received ERC-721/1155 whose contract isn't
                    // among the wallet's non-spam holdings on that chain
                    // (Alchemy's own isSpam classification).
                    if leg.category == "erc721" || leg.category == "erc1155",
                       let owned = ownedNFTs["\(leg.address.lowercased())|\(leg.chain.network)"],
                       !owned.contains(contract) { continue }
                }
                if let thing = thing(from: leg.t, chain: leg.chain, received: leg.received,
                                     ref: leg.ref, address: leg.address, names: names) {
                    if leg.received {
                        let knownGood = knownGoodByOwner[leg.address.lowercased()] ?? []
                        WalletSafety.flagPoisoning(thing, knownGood: knownGood)
                    }
                    landed.append(thing)
                }
            }
        }

        var added = 0
        for thing in landed {
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        // Durable before the gas total accumulates (2026-07-20 review):
        // gas is a bare running sum with no per-tx ledger, so a job whose
        // underlying thing never actually saved (an app kill, a rejected
        // write) would re-fetch and re-count its fee next launch with no
        // way to detect or undo the double-count — the same "land and SAVE
        // before advancing" lesson `WalletApprovals` already learned.
        let saved = added == 0 || context.saveHonestly()
        if saved, !gasJobs.isEmpty { await WalletGas.accumulate(jobs: gasJobs) }
        // New token approvals ride the same pass (2026-07-16, prd §84) — an
        // incremental filtered-log read per wallet per chain, landing
        // "Approved X to spend unlimited Y" things whose link is the wallet's
        // Revoke.cash page. Inside the running guard like everything above.
        let approvalsAdded = await WalletApprovals.sync(context: context,
                                                        addresses: evmAddresses,
                                                        existing: existing,
                                                        heldByOwner: heldByOwner,
                                                        ownedNFTs: ownedNFTs)
        added += approvalsAdded
        // Peer fills ride the same pass when that seat is on (prd §112) — a
        // filtered-log read per wallet against Peer's orchestrators on Base,
        // landing "Bought 25 USDC with Venmo on Peer" things. Inside the
        // running guard like everything above; no-ops unless connected.
        let peerAdded = await PeerBridge.sync(context: context,
                                              addresses: evmAddresses,
                                              existing: existing)
        added += peerAdded ?? 0
        // …and the Solana arm (prd §86), which lands its own things off its own
        // two calls. Inside the running guard like everything above.
        let solana = await solanaSync(context: context, addresses: solanaOnly(addresses),
                                      existing: existing, heldPriced: heldPriced)
        added += solana.added
        // EIP-7702 delegation watch (2026-07-20) rides the same pass — one
        // eth_getCode per wallet per active EVM chain, landing a thing only
        // when the delegate CHANGES. Inside the running guard like everything
        // above.
        let delegationAdded = await WalletSafety.sync(context: context,
                                                      addresses: evmAddresses,
                                                      existing: existing)
        added += delegationAdded
        // Aave health-factor risk watch (2026-07-20) rides the same pass —
        // one getUserAccountData read per wallet per Aave-supported chain,
        // landing a thing only on a NEW crossing into risk. Inside the
        // running guard like everything above.
        let defiAdded = await WalletDeFi.sync(context: context,
                                              addresses: evmAddresses,
                                              existing: existing)
        added += defiAdded
        // Safe multisig pending-queue watch (2026-07-20) rides the same
        // pass — detection + queue read per wallet per active EVM chain,
        // landing a thing for every newly seen pending transaction. Inside
        // the running guard like everything above.
        let safeAdded = await SafeBridge.sync(context: context,
                                              addresses: evmAddresses,
                                              existing: existing)
        added += safeAdded

        // `reachedAny` speaks only for the EVM TRANSFER sync, which a
        // Solana-only watch list never runs — left alone it is vacuously false
        // and the caller paints "Couldn't reach the chain" over a wallet whose
        // treemap is right there showing SOL. Each arm gets to vouch for
        // itself: Solana's RPC answering counts, and failing that the holdings
        // read does (`heldPriced` is non-nil exactly when the Portfolio API
        // answered) — so a Solana wallet whose activity RPC is down but whose
        // holdings load is still honestly "reached".
        // The approvals arm rides PUBLIC RPCs, not Alchemy — things it landed
        // are proof of reach in their own right (review 2026-07-16: without
        // this, a partial Alchemy outage could paint "couldn't reach" over
        // approvals that just landed).
        let reached = reachedAny || solana.reached || approvalsAdded > 0
            || (peerAdded ?? 0) > 0 || delegationAdded > 0 || defiAdded > 0 || safeAdded > 0
            || (evmAddresses.isEmpty && heldPriced != nil)
        return reached ? added : nil
    }

    /// One transfer leg in flight through a refresh pass — the raw Alchemy
    /// transfer plus where it came from. Computed accessors read the fields the
    /// swap-folding and spam filter need without re-indexing the dict each time.
    private struct Leg {
        let t: [String: Any]
        let chain: Chain
        let received: Bool
        let ref: String
        let address: String
        var hash: String { (t["hash"] as? String) ?? "" }
        var asset: String { (t["asset"] as? String) ?? chain.symbol }
        var value: Double { (t["value"] as? Double) ?? 0 }
        var category: String { (t["category"] as? String) ?? "" }
        /// The transferred token's contract, lowercased — nil for native coins.
        var contract: String? {
            ((t["rawContract"] as? [String: Any])?["address"] as? String)?.lowercased()
        }
    }

    /// A trade folded from a matched send+receive on one hash — "Swapped 0.5
    /// ETH → 1,200 USDC on Uniswap". The counterparty is the router both legs
    /// met; it names the venue when the known-contracts table or ENS knows it,
    /// and is the address a "name this address" verb binds to.
    private static func swapThing(sent: Leg, received: Leg, ref: String,
                                  names: [String: String]) -> Thing? {
        guard !sent.hash.isEmpty else { return nil }
        let router = ((sent.t["to"] as? String) ?? (received.t["from"] as? String))?.lowercased()
        let venue = router.flatMap { names[$0] }
        let out = sent.value > 0 ? "\(format(sent.value)) \(sent.asset)" : sent.asset
        let inn = received.value > 0 ? "\(format(received.value)) \(received.asset)" : received.asset
        let head = "Swapped \(out) → \(inn)"
        let title = venue.map { "\(head) on \($0)" } ?? head
        let when = IngestSupport.isoDate((sent.t["metadata"] as? [String: Any])?["blockTimestamp"])
        let thing = Thing(
            kind: .transaction,
            title: title,
            content: sent.chain.explorer + sent.hash,
            source: "Wallet",
            capturedAt: when ?? .now,
            sourceRef: ref
        )
        thing.walletAddress = sent.address
        // The router is the swap's counterparty, and its name is the title's
        // " on …" clause — so it rides `transferCounterparty` (rename-safe),
        // not `transferVenue` (Solana's un-renameable program slot). No
        // direction/amount: a swap is two-legged, and keeps the standard
        // sheet layout until its grammar earns a stage.
        thing.counterpartyAddress = router
        thing.transferCounterparty = venue
        return thing
    }

    // MARK: - Counterparty naming (2026-07-14)

    /// Contract addresses a counterparty slot actually meets, named — only
    /// canonical, publicly verifiable deployments (honesty rule: a wrong name
    /// is worse than no name). Keyed lowercased; several are deployed at the
    /// same address across EVM chains, so the table is chain-agnostic.
    private static let knownContracts: [String: String] = [
        // Uniswap routers (V2, V3, V3-2, Universal — Universal shares its
        // address across the chains we read).
        "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": "Uniswap",
        "0xe592427a0aece92de3edee1f18e0157c05861564": "Uniswap",
        "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45": "Uniswap",
        "0x3fc91a3afd70395cd496c647d5a6cc9d4b2b7fad": "Uniswap",
        // OpenSea's Seaport (1.1, 1.5, 1.6).
        "0x00000000006c3852cbef3e08e8df289169ede581": "OpenSea",
        "0x00000000000000adc04c56bf30ac9d3c0aaf14dc": "OpenSea",
        "0x0000000000000068f116a894984e2db1123eb395": "OpenSea",
        // Aggregators.
        "0x1111111254eeb25477b68fb85ed929f73a960582": "1inch",
        "0x111111125421ca6dc452d289314280a0f8842a65": "1inch",
        "0xdef1c0ded9bec7f1a1670819833240f027b25eff": "0x Exchange",
        // Wrapped natives — a wrap/unwrap's counterparty IS the contract.
        "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": "WETH",
        "0x4200000000000000000000000000000000000006": "WETH",
        "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270": "WMATIC",
        // ENS registrar controllers (name registrations/renewals).
        "0x253553366da8546fc250f225fe3d25d0c782303b": "ENS",
        "0x283af0b28c62c092c9727f1ee09c02ca627eb7f5": "ENS",
    ]

    /// A synchronously-known name for a counterparty address — the person's own
    /// label, a watched Farcaster handle, or a canonical contract (no async ENS).
    /// The thing sheet's "Who" row shows this over the raw hex.
    static func knownLabel(for address: String) -> String? {
        let a = address.lowercased()
        return CounterpartyLabels.shared.label(for: a)
            ?? FarcasterStore.shared.handle(forAddress: a)
            ?? knownContracts[a]
    }

    /// The other side of a transfer, lowercased hex — who it came from when
    /// received, where it went when sent.
    private static func counterparty(of t: [String: Any], received: Bool) -> String? {
        ((received ? t["from"] : t["to"]) as? String)?.lowercased()
    }

    /// Names for a batch of new transfers' counterparties: another watched
    /// wallet's own label first (a move between your wallets says so), then
    /// the known-contracts table, then reverse ENS — capped at 16 lookups per
    /// pass (a first-ever sync can land dozens of transfers; the cache —
    /// misses included — picks up the rest on later passes). An unnamed
    /// address stays unnamed: the title never carries a raw hash.
    @MainActor
    private static func counterpartyNames(for transfers: [Leg]) async -> [String: String] {
        var addrs: [String] = []
        var seen = Set<String>()
        for f in transfers {
            guard let a = counterparty(of: f.t, received: f.received) else { continue }
            if seen.insert(a).inserted { addrs.append(a) }
        }
        guard !addrs.isEmpty else { return [:] }

        var names: [String: String] = [:]
        var unknown: [String] = []
        for a in addrs {
            // A name the PERSON gave this address wins over everything — it's
            // their own record ("Mom", "my Ledger"), truer than any resolver.
            if let mine = CounterpartyLabels.shared.label(for: a) {
                names[a] = mine
            } else if let handle = FarcasterStore.shared.handle(forAddress: a) {
                // A watched Farcaster account's verified wallet — "from @dwr".
                names[a] = handle
            } else if let watched = WalletStore.shared.addresses.first(where: {
                $0.address.lowercased() == a
            }) {
                names[a] = watched.label.isEmpty ? watched.short : watched.label
            } else if let known = knownContracts[a] {
                names[a] = known
            } else {
                unknown.append(a)
            }
        }
        let resolved = await IngestSupport.boundedGather(Array(unknown.prefix(16)),
                                                         maxConcurrent: 4) { a in
            (a, await ENS.reverseName(for: a))
        }
        for (a, n) in resolved where n != nil { names[a] = n }
        return names
    }

    /// Resolves watched entries to the addresses the APIs actually read — ENS
    /// names to hex, `.sol` names to base58 — dropping any name that won't
    /// resolve (a typo'd name simply lands nothing, honestly).
    ///
    /// The result deliberately MIXES families: the holdings read serves both and
    /// routes each address by shape. Callers that can only serve EVM (the
    /// transfer sync, the NFT reads) narrow with `evmOnly`. `.sol` is tried
    /// before ENS because `ENS.looksLikeName` takes ANY dotted string — it would
    /// happily send `toly.sol` to the ENS resolver, which answers with a null
    /// address rather than an error.
    static func resolvedAddresses(_ raw: [String]) async -> [String] {
        var out: [String] = []
        for a in raw {
            if ENS.isHexAddress(a) || SNS.isAddress(a) { out.append(a) }
            else if SNS.looksLikeName(a) {
                if let sol = await SNS.resolve(a) {
                    out.append(sol)
                    await MainActor.run { WalletStore.shared.noteResolution(a, resolved: sol) }
                }
            }
            else if let hex = await ENS.resolve(a) {
                out.append(hex)
                // Every resolution feeds the store's cache (2026-07-20) — the
                // scoped feed, history page, and row labels all need to match
                // a landed thing's RESOLVED hex back to the WATCHED spelling,
                // and this loop is the one place both forms meet.
                await MainActor.run { WalletStore.shared.noteResolution(a, resolved: hex) }
            }
        }
        return out
    }

    /// The hex addresses among a resolved set. The EVM-only pipelines can't do
    /// anything with a base58 one but spend a request finding out.
    private static func evmOnly(_ addresses: [String]) -> [String] {
        addresses.filter { ENS.isHexAddress($0) }
    }

    /// The base58 addresses among a resolved set — the Solana arm's input.
    private static func solanaOnly(_ addresses: [String]) -> [String] {
        addresses.filter { SNS.isAddress($0) }
    }

    /// Lands the Solana half of a pass (prd §86) — the non-EVM ingest. Sits
    /// beside the EVM arm rather than inside it because the two share almost
    /// nothing: a different call shape (batched JSON-RPC, not
    /// `getAssetTransfers`), a different notion of direction (signing, not
    /// from/to) and a different noise problem. What they DO share is the spam
    /// rule's input — `heldPriced`, already fetched once for the whole pass —
    /// and the honesty contract: `reached` false means the RPC was unreachable,
    /// never "nothing happened".
    ///
    /// Returns the count landed and whether Solana was actually reached.
    @MainActor
    private static func solanaSync(context: ModelContext, addresses: [String],
                                   existing: Set<String>,
                                   heldPriced: Set<String>?) async -> (added: Int, reached: Bool) {
        // Nothing to do, and — crucially — not a failure: `reached` false here
        // must not make the caller cry "couldn't reach the chain".
        guard !addresses.isEmpty, chains.contains(where: { $0.kind == .solana }),
              let solanaChain = allChains.first(where: { $0.kind == .solana })
        else { return (0, false) }

        let key = IngestSupport.alchemyKey
        let solPrice = await SolanaActivity.solPrice(key: key)
        // Two at a time — the same courtesy the EVM fan-out shows a free-tier
        // key, and each wallet is already only two requests.
        let results = await IngestSupport.boundedGather(addresses, maxConcurrent: 2) { address in
            (address, await SolanaActivity.moves(address: address, key: key))
        }

        var reached = false
        var fresh: [(address: String, move: SolanaActivity.Move)] = []
        var seen = Set<String>()
        for (address, moves) in results {
            guard let moves else { continue }   // nil = unreachable, not empty
            reached = true
            for move in moves {
                let ref = "wallet:sol:\(move.signature)"
                // One signature can name two watched wallets — land it once.
                guard !existing.contains(ref), seen.insert(ref).inserted,
                      SolanaActivity.isNews(move, heldPriced: heldPriced, solPrice: solPrice)
                else { continue }
                fresh.append((address, move))
            }
        }
        guard !fresh.isEmpty else { return (0, reached) }

        // ONE naming call for the whole pass, not one per move.
        let symbols = await SolanaActivity.symbols(for: fresh.flatMap { $0.move.legs.map(\.mint) })
        var landed: [Thing] = []
        for (address, move) in fresh {
            // No story means a leg we couldn't name — dropped rather than
            // printed as a raw mint. See `SolanaActivity.story`.
            guard let story = SolanaActivity.story(for: move, symbols: symbols) else { continue }
            let thing = Thing(
                kind: .transaction,
                title: story.title,
                content: solanaChain.explorer + move.signature,
                source: "Wallet",
                capturedAt: move.when,
                sourceRef: "wallet:sol:\(move.signature)"
            )
            thing.walletAddress = address
            thing.transferDirection = story.direction
            thing.transferAmount = story.amount
            thing.transferVenue = story.venue
            landed.append(thing)
        }
        for thing in landed {
            context.insert(thing)
            SpotlightIndex.index([thing])
        }
        if !landed.isEmpty { context.saveHonestly() }
        return (landed.count, reached)
    }

    /// One (address, chain, direction) job's transfers, in the Alchemy
    /// `getAssetTransfers`-shaped dictionary form `Leg` and `thing(from:)`
    /// already know how to read. `zerion` is this address's prefetched
    /// Zerion activity (nil = Zerion didn't reach this wallet — the full
    /// Alchemy fetch below is unchanged for it). When Zerion DID reach the
    /// wallet, its matching fungible legs are used directly and Alchemy is
    /// asked ONLY for the NFT categories (small, cheap, unconditional — see
    /// the type header on `WalletIngest`).
    private static func fetch(address: String, chain: Chain, received: Bool,
                              zerion: [ZerionAPI.Transfer]?) async -> [[String: Any]]? {
        if let zerion {
            let mapped = zerion
                .filter { $0.network == chain.network && $0.received == received }
                .map(zerionTransferDict)
            let nfts = await fetchAlchemy(address: address, chain: chain, received: received,
                                          categories: ["erc721", "erc1155"]) ?? []
            return mapped + nfts
        }
        return await fetchAlchemy(address: address, chain: chain, received: received,
                                  categories: ["external", "internal", "erc20", "erc721", "erc1155"])
    }

    /// Maps one Zerion fungible leg into the Alchemy-shaped dictionary —
    /// only this fetch layer differs by source; every downstream rule (swap
    /// folding, counterparty naming, the spam filter) runs unchanged.
    /// `uniqueId` is deterministic and Zerion-namespaced (never collides with
    /// an Alchemy uid's own format) — stable across passes so a re-run
    /// doesn't re-land the same leg, but by construction DIFFERENT from
    /// whatever ref an earlier Alchemy sync gave the same real transaction.
    /// That's exactly why `refresh` also cross-checks `existingWalletContent`
    /// — it's what stops a transfer Alchemy already landed from landing a
    /// SECOND time under this new ref the day Zerion takes over a wallet.
    private static func zerionTransferDict(_ t: ZerionAPI.Transfer) -> [String: Any] {
        var d: [String: Any] = [
            "hash": t.hash,
            "asset": t.symbol,
            "value": t.amount,
            "category": t.contract != nil ? "erc20" : "external",
            "uniqueId": "zerion:\(t.hash):\(t.received ? "in" : "out"):\(t.symbol):"
                + "\(t.counterparty ?? ""):\(t.amount)",
            "metadata": ["blockTimestamp": IngestSupport.isoString(t.when)],
        ]
        if let contract = t.contract { d["rawContract"] = ["address": contract] }
        if let cp = t.counterparty { d[t.received ? "from" : "to"] = cp }
        return d
    }

    private static func fetchAlchemy(address: String, chain: Chain, received: Bool,
                                     categories: [String]) async -> [[String: Any]]? {
        let url = "https://\(chain.network).g.alchemy.com/v2/\(IngestSupport.alchemyKey)"
        let params: [String: Any] = [
            "fromBlock": "0x0", "toBlock": "latest",
            received ? "toAddress" : "fromAddress": address,
            // "internal" added (2026-07-09): ETH that moves through a
            // contract call — swap proceeds, unwrapped WETH, a DeFi
            // withdrawal — rides an internal transfer, not "external". A
            // wallet whose recent activity is mostly onchain interactions
            // rather than direct sends was showing "connected, nothing
            // landed" because that whole category was unfetched.
            "category": categories,
            "withMetadata": true, "excludeZeroValue": true,
            "maxCount": "0xa", "order": "desc",
        ]
        let body: [String: Any] = [
            "id": 1, "jsonrpc": "2.0",
            "method": "alchemy_getAssetTransfers", "params": [params],
        ]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let transfers = result["transfers"] as? [[String: Any]] else { return nil }
        return transfers
    }

    private static func thing(from t: [String: Any], chain: Chain,
                              received: Bool, ref: String, address: String,
                              names: [String: String] = [:]) -> Thing? {
        guard let hash = t["hash"] as? String else { return nil }
        let asset = (t["asset"] as? String) ?? chain.symbol
        let amount = (t["value"] as? Double).map(format) ?? ""
        let cp = counterparty(of: t, received: received)
        // A move between two of YOUR OWN watched wallets is housekeeping, not
        // news (delight 2026-07-15): the app understands your setup, so it
        // says "Main → Cold" instead of a one-sided "Sent … to Cold". Only
        // when more than one wallet is watched (labels are meaningful) and the
        // counterparty is itself watched. The amount leads so the row still
        // reads at a glance; "Moved" replaces the directional verb.
        let watched = WalletStore.shared.addresses
        let title: String
        // The directional facts, kept as data beside the sentence built from
        // them — so TransferStage reads fields, not words. nil on the "Moved"
        // arm: a self-transfer has no single direction (and no stage).
        var direction: String? = nil
        var amountText: String? = nil
        var counterpartyName: String? = nil
        if watched.count > 1,
           let cp, let other = watched.first(where: { $0.address.lowercased() == cp }),
           let mine = watched.first(where: { $0.address.lowercased() == address.lowercased() }) {
            let otherLabel = other.label.isEmpty ? other.short : other.label
            let myLabel = mine.label.isEmpty ? mine.short : mine.label
            let from = received ? otherLabel : myLabel
            let to = received ? myLabel : otherLabel
            let head = amount.isEmpty ? "Moved \(asset)" : "Moved \(amount) \(asset)"
            title = "\(head) · \(from) → \(to)"
        } else {
            let verb = received ? "Received" : "Sent"
            var t2 = amount.isEmpty ? "\(verb) \(asset)" : "\(verb) \(amount) \(asset)"
            // The counterparty, when it has a name (a watched wallet's label, a
            // known contract, or reverse ENS) — "Sent 0.5 ETH to Uniswap" is a
            // story where a bare receipt wasn't. Nameless stays plain: the
            // title never wears a raw hash.
            if let who = cp.flatMap({ names[$0] }) {
                t2 += received ? " from \(who)" : " to \(who)"
                counterpartyName = who
            }
            title = t2
            direction = received ? "received" : "sent"
            amountText = amount.isEmpty ? asset : "\(amount) \(asset)"
        }
        let when = IngestSupport.isoDate((t["metadata"] as? [String: Any])?["blockTimestamp"])
        let thing = Thing(
            kind: .transaction,
            title: title,
            content: chain.explorer + hash,
            source: "Wallet",
            capturedAt: when ?? .now,
            sourceRef: ref
        )
        thing.walletAddress = address
        thing.counterpartyAddress = cp
        thing.transferDirection = direction
        thing.transferAmount = amountText
        thing.transferCounterparty = counterpartyName
        return thing
    }

    /// One watched wallet's holdings — a label (name or short address) paired
    /// with its top-5-by-value cells ("ETH 34, USDC 12, …").
    struct HoldingsGroup {
        let label: String
        /// The watched wallet this group belongs to — nil for the combined
        /// "All wallets" group, which spans every address (2026-07-15, feeds
        /// the allocation bar which needs to key back to a wallet's face
        /// color without guessing from the label).
        var address: String? = nil
        let cells: [String]
        /// Total USD across every counted holding (the >= $1 set, not just
        /// the top-5 cells) and how many that is — the subline's fact.
        let totalUSD: Double
        let tokenCount: Int
        /// The counted positions summed by symbol (top few by value) — snapshotted
        /// into each value sample so the combined sheet can attribute a move to a
        /// token ("mostly ETH"). Empty when this group wasn't built for sampling.
        var topBySymbol: [String: Double] = [:]
        /// Set only on a LAST-KNOWN group (an unreachable wallet showing its
        /// cached treemap): the moment it was sampled, so the subline can say
        /// "as of 2h ago" instead of claiming the number is current
        /// (2026-07-17). nil on a live group — the normal case.
        var stale: Date? = nil

        /// "$12.4K across 5 tokens" live, or "$12.4K · as of 2h ago" when the
        /// group is a stale last-known snapshot — compact, no cents theater.
        var subline: String {
            let amount: String
            if totalUSD >= 1_000_000 { amount = String(format: "$%.1fM", totalUSD / 1_000_000) }
            else if totalUSD >= 10_000 { amount = String(format: "$%.0fK", totalUSD / 1_000) }
            else if totalUSD >= 1_000 { amount = String(format: "$%.1fK", totalUSD / 1_000) }
            else { amount = String(format: "$%.0f", totalUSD) }
            if let stale {
                let mins = max(1, Int(Date.now.timeIntervalSince(stale) / 60))
                let ago: String
                if mins < 60 { ago = "\(mins)m ago" }
                else if mins < 60 * 24 { ago = "\(mins / 60)h ago" }
                else { ago = "\(mins / 1_440)d ago" }
                return String(localized: "\(amount) · as of \(ago)")
            }
            return "\(amount) across \(tokenCount) token\(tokenCount == 1 ? "" : "s")"
        }
    }

    /// A treemap PER watched wallet, sized by USD value — the same TagMap
    /// idiom Home uses. Real, from Alchemy's Portfolio API (balances +
    /// metadata + prices in one call). Unpriced spam tokens have no price and
    /// drop out; the top 5 per wallet are shown. Separate, not combined
    /// (ruling 2026-07-09): two watched addresses are usually two different
    /// purposes (main vs. cold, personal vs. a DAO) and summing them into one
    /// total hid which wallet actually held what.
    /// Whether a wallet group's address is the one the feed is scoped to —
    /// hex compares case-insensitively (EIP-55 case is a checksum, not
    /// identity), base58 exactly (Solana case IS identity). Mirrors the
    /// asymmetry `WalletStore.dedupeKey` and the switcher's `sameAddress` use.
    private static func scopeMatch(_ groupAddress: String?, _ scope: String) -> Bool {
        guard let groupAddress else { return false }
        return ENS.isHexAddress(scope)
            ? groupAddress.lowercased() == scope.lowercased()
            : groupAddress == scope
    }

    @MainActor
    static func holdingsChart(scopeTo address: String? = nil) async -> [String]? {
        var groups = await topHoldingsByWallet()
        // The Wallet feed can scope to one watched wallet (prd §128) — filter
        // the groups AFTER the fetch, never before, so every wallet's value
        // history still samples (topHoldingsByWallet's recordSample side effect)
        // regardless of what the feed is currently showing.
        if let address { groups = groups.filter { scopeMatch($0.address, address) } }
        guard !groups.isEmpty else { return nil }
        let ids = groups.indices.map { "w\($0)" }
        var doc = ["root = Stack([\(ids.joined(separator: ", "))])"]
        for (i, g) in groups.enumerated() {
            doc.append("w\(i) = TagMap(\(q(g.label)), \(q(g.subline)), [\(g.cells.joined(separator: ", "))], \(q("token")))")
        }
        return doc
    }

    private static func q(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "'"))\""
    }

    /// The COMBINED holdings across every watched wallet (2026-07-15) — the
    /// "bundle" view. `holdings(addresses:)` already aggregates any number of
    /// addresses by symbol, so this passes them all at once: one total, one
    /// top-5 treemap summing the same >= $1 positions the per-wallet view
    /// shows separately. Added ALONGSIDE the per-wallet treemaps, not instead
    /// of them (ruling 2026-07-15, revising 2026-07-09): the separate views
    /// stay the default so you never lose which wallet holds what — this is an
    /// extra overview answering "what am I worth in total." Nil with one or
    /// zero wallets (one wallet's own view already IS its portfolio). The
    /// `pinnedOnly` restriction retired with the Home board (2026-07-20) — no
    /// caller ever requested it once Home was the only pinned-only consumer.
    @MainActor
    static func combinedHoldings() async -> HoldingsGroup? {
        let watched = WalletStore.shared.addresses
        guard watched.count > 1 else { return nil }
        let resolved = await resolvedAddresses(watched.map(\.address))
        guard !resolved.isEmpty, let h = (await holdings(addresses: resolved)).group else { return nil }
        return HoldingsGroup(label: String(localized: "All wallets"), cells: h.cells,
                             totalUSD: h.total, tokenCount: h.count,
                             topBySymbol: topBySymbol(h.bySymbol))
    }

    /// The top 8 positions by USD from a by-symbol map — the snapshot each value
    /// sample stores (bounded so the persisted history stays small), enough for
    /// the combined sheet's "what moved" without carrying a whale's whole book.
    private static func topBySymbol(_ bySymbol: [String: Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues:
            bySymbol.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) })
    }

    /// Builds a single-group treemap document (label + subline + cells) — the
    /// `q`-escaped form the combined "bundle" view paints. Kept here so the
    /// escaping matches `holdingsChart`'s and callers don't rebuild the string.
    static func groupDocument(_ g: HoldingsGroup) -> [String] {
        ["root = TagMap(\(q(g.label)), \(q(g.subline)), [\(g.cells.joined(separator: ", "))], \(q("token")))"]
    }

    /// Every watched wallet's holdings, one group per address — for a caller
    /// composing its own document rather than rendering the Wallet screen's
    /// standalone one. A wallet with nothing priced simply doesn't contribute
    /// a group (correct-but-empty, not a failure) — order follows watch
    /// order, the first address leads. The `pinnedOnly` restriction retired
    /// with the Home board (2026-07-20) — every watched wallet shows now,
    /// which is what the Wallet screen and Feed chip already did.
    @MainActor
    static func topHoldingsByWallet() async -> [HoldingsGroup] {
        let watched = WalletStore.shared.addresses
        guard !watched.isEmpty else { return [] }
        // Concurrent, not sequential — three watched wallets waiting on three
        // requests in a row is the difference between a couple seconds and
        // most of an app launch (2026-07-09: separating wallets must not
        // make the pinned module noticeably slower to appear than the old
        // single combined request was).
        let results = await withTaskGroup(of: (Int, HoldingsGroup?).self) { group in
            for (i, entry) in watched.enumerated() {
                group.addTask {
                    if case let .group(g) = await walletGroupOutcome(entry) { return (i, g) }
                    return (i, nil)   // unreachable OR reached-but-empty both drop here
                }
            }
            var collected: [(Int, HoldingsGroup?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        // Every real fetch feeds the wallet's value history (2026-07-14) —
        // forward-only, throttled inside recordSample, never back-filled.
        for (i, g) in results { if let g {
            WalletStore.shared.recordSample(address: watched[i].address, totalUSD: g.totalUSD,
                                            holdings: g.topBySymbol)
        } }
        let groups = results.sorted { $0.0 < $1.0 }.compactMap(\.1)
        // The combined "Across your wallets" total hitting a new high is a
        // moment (delight 2026-07-15) — fired only with more than one wallet
        // (a lone wallet's own high rides its per-address mark in recordSample).
        //
        // TWO honesty guards, both mirroring §77's combined-line rules:
        // (1) The mark is scoped to the WATCHED SET's signature, so adding or
        //     removing a wallet starts a fresh mark (seeded silently) — a
        //     composition change can never masquerade as a new high (the exact
        //     +millions-% artifact §77 fixed for the line). (2) Only when every
        //     watched wallet priced this pass (`groups.count == watched.count`),
        //     so a wallet intermittently failing to fetch — then recovering —
        //     doesn't read as a gain either.
        if watched.count > 1, groups.count == watched.count {
            let combined = groups.reduce(0.0) { $0 + $1.totalUSD }
            let signature = watched.map { $0.address.lowercased() }.sorted().joined(separator: ",")
            if WalletMoments.shared.notedNewHigh(scope: "combined:\(signature)", value: combined) {
                WalletMoments.shared.fire(String(localized: "Across your wallets: a new high, \(TokenStats.compact(combined)) 📈"))
            }
        }
        return groups
    }

    /// One watched wallet's holdings outcome — the three states Home has to
    /// tell apart (2026-07-17). `topHoldingsByWallet` collapses `.empty` and
    /// `.unreachable` into "no group"; the pinned path below keeps them
    /// distinct so an unreachable wallet holds its last-known card (or an honest
    /// error) instead of silently vanishing.
    private enum WalletHoldingsOutcome {
        case group(HoldingsGroup)   // reached the chain, and it holds priced tokens
        case empty                  // reached the chain, nothing priced (correct-and-empty)
        case unreachable            // couldn't reach the chain (offline / rate-limited / unresolved)
    }

    private static func walletGroupOutcome(_ entry: WalletStore.WatchedAddress) async -> WalletHoldingsOutcome {
        guard let address = await resolvedAddresses([entry.address]).first else { return .unreachable }
        // A wallet with every chain switched off has nothing to ask — that's a
        // deliberate empty, not a chain we failed to reach. Classify it .empty
        // so Home shows no card rather than crying "couldn't reach the chain"
        // over a config the user chose (review 2026-07-17). Mirrors
        // fetchHeldTokens' own `routed.isEmpty` guard, which returns the same
        // nil this would otherwise read as unreachable.
        guard !networks(for: address).isEmpty else { return .empty }
        let h = await holdings(addresses: [address])
        guard h.reached else { return .unreachable }
        guard let g = h.group else { return .empty }
        return .group(HoldingsGroup(label: entry.label.isEmpty ? entry.short : entry.label,
                                    address: entry.address,
                                    cells: g.cells, totalUSD: g.total,
                                    tokenCount: g.count,
                                    topBySymbol: topBySymbol(g.bySymbol)))
    }

    /// The top-5-by-value cells for one or more hex addresses, combined —
    /// builds on `fetchHeldTokens` (the shared read), so the treemap and the
    /// activity spam filter agree on what "held" means. `bySymbol` (every
    /// counted position summed by symbol) rides out too, for the combined
    /// sheet's per-token attribution (2026-07-15).
    /// `reached` distinguishes "couldn't reach the chain" (nil group) from
    /// "reached, but nothing priced" (also nil group) — the two collapse to the
    /// same empty treemap, but only the first should surface an error or hold a
    /// last-known card; the second is correct-and-empty (2026-07-17).
    private static func holdings(addresses: [String])
        async -> (reached: Bool, group: (cells: [String], total: Double, count: Int, bySymbol: [String: Double])?) {
        guard let tokens = await fetchHeldTokens(addresses: addresses) else { return (false, nil) }
        var bySymbol: [String: Double] = [:]
        // Each symbol's biggest single position also remembers WHERE it is
        // (chain slug + token address) so its treemap cell can open the same
        // chart a watched token gets (2026-07-14). Native coins have no token
        // address — their cells stay routeless and fall back to the Wallet screen.
        var routeBySymbol: [String: (usd: Double, route: String)] = [:]
        for token in tokens {
            bySymbol[token.symbol, default: 0] += token.usd
            if let contract = token.contract, let slug = chainSlug[token.network],
               token.usd > (routeBySymbol[token.symbol]?.usd ?? 0) {
                routeBySymbol[token.symbol] = (token.usd, "\(slug):\(contract)")
            }
        }
        guard !bySymbol.isEmpty else { return (true, nil) }

        // Top 5 by value; sqrt-scale so a big holding doesn't slice the rest
        // to slivers. Icons for "token" mode are a bundled local set keyed by
        // symbol (TokenIcon) — Alchemy's own logo field turned out null for
        // nearly everything, so the cell string carries no icon data. A routed
        // cell trails "@t:chain:address" (stripped by KindCountRow.parse, never
        // shown) so a tap can open that token's chart.
        let cells = bySymbol.sorted { $0.value > $1.value }.prefix(5)
            .map { sym, usd in
                let route = routeBySymbol[sym].map { " @t:\($0.route)" } ?? ""
                return "\(sym) \(treemapWeight(usd))\(route)"
            }
        return (true, (cells, bySymbol.values.reduce(0, +), bySymbol.count, bySymbol))
    }

    /// One priced token a wallet holds — the shared read behind both the
    /// holdings treemap and the activity spam filter, so "what you hold" means
    /// the same thing to both. Native coins carry a nil contract.
    /// Sendable so a read can be cached in and returned across `HoldingsCache`.
    private struct HeldToken: Sendable {
        let symbol: String
        let contract: String?
        let network: String
        let usd: Double
        /// The wallet that holds it, lowercased — the Portfolio endpoint names
        /// each token's owner, so a multi-address read stays attributable
        /// (the approvals spam filter is per-owner; a pooled set would let a
        /// spam-emitted fake approval on wallet A pass because wallet B holds
        /// the token — review 2026-07-16).
        let owner: String
    }

    /// Every priced token (>= the dust floor) the given addresses hold, across
    /// the read chains — Alchemy's Portfolio `by-address` (balances + metadata +
    /// prices in one call). Chunked at 3 addresses ("Maximum allowed addresses
    /// is 3", measured 2026-07-15 — a 4th 400s the whole call) and paged up to
    /// 8 pages (≈800 tokens) so a whale's real holdings surface without
    /// unbounded paging. nil only when nothing was reachable at all.
    /// One holding as the Portfolio endpoint hands it over, before the floor is
    /// applied. The price is optional because a missing one isn't always a
    /// junk token — on Solana it's the norm (see `priceSPL`).
    private struct Candidate {
        let symbol: String
        let contract: String?
        let network: String
        let amount: Double
        let owner: String
        var price: Double?
    }

    /// Coalesces concurrent holdings reads and briefly caches the result — the
    /// scaling relief for the shared Alchemy key (see `fetchHeldTokens`). Nested
    /// so it can hold `HeldToken`. An entry is stored only on a real read; a nil
    /// (nothing reached) never lands, so a rate-limited miss isn't remembered.
    private actor HoldingsCache {
        static let shared = HoldingsCache()
        private static let ttl: TimeInterval = 90

        private struct Entry { let tokens: [HeldToken]; let at: Date }
        private var fresh: [String: Entry] = [:]
        private var inFlight: [String: Task<[HeldToken]?, Never>] = [:]

        /// A live-enough read for `key`: a fresh cache hit, the value of an
        /// already-running fetch for the same key, or a new fetch (whose task
        /// every concurrent caller then shares). The actor's serialization is
        /// what makes the check-then-register step race-free — there is no await
        /// between reading `inFlight` and writing it.
        func tokens(key: String, fetch: @Sendable @escaping () async -> [HeldToken]?) async -> [HeldToken]? {
            if let e = fresh[key], e.at.timeIntervalSinceNow > -Self.ttl { return e.tokens }
            if let running = inFlight[key] { return await running.value }
            let task = Task { await fetch() }
            inFlight[key] = task
            let result = await task.value
            inFlight[key] = nil
            if let result { fresh[key] = Entry(tokens: result, at: Date()) }
            return result
        }

        /// Drop every cached read so the next fetch goes live. A deliberate
        /// pull-to-refresh calls this so the TTL never serves stale holdings
        /// under a gesture whose whole contract is "re-fetch now" — the in-flight
        /// coalescing map is untouched, so a pull still joins (not doubles) a
        /// read already on the wire. Also the only thing that bounds `fresh`,
        /// which otherwise only ever grows.
        func invalidate() { fresh.removeAll() }
    }

    /// Clears the holdings cache so the next read is live — for pull-to-refresh
    /// (see `HoldingsCache.invalidate`). Automatic foreground fan-out does NOT
    /// call this; only a deliberate user pull does.
    static func invalidateHoldingsCache() async { await HoldingsCache.shared.invalidate() }

    /// The priced-holdings read, coalesced and briefly cached (2026-07-17).
    ///
    /// One app foreground fans the SAME `by-address` Portfolio call out 5–8×:
    /// Home's pinned + combined passes, the Wallet screen's two, Feed's chip,
    /// BridgeRefresh, plus the approvals and Solana spam filters — none aware of
    /// the others. On Alchemy's shared free key that multiplies the month's
    /// compute burn for byte-identical data (the shared-key capacity ceiling,
    /// see `fetchPortfolioPage`). The wrapper sits at THIS boundary so every
    /// caller and the SPL/DeFiLlama price-fills below ride it. `HoldingsCache`
    /// does the coalescing (concurrent asks for one address-set await a single
    /// network task — zero staleness) and holds a 90s TTL under the existing
    /// stale-card layer (`recordSample` + "as of Xh ago"), which still owns
    /// anything older. A nil (nothing reached) is never cached, so a
    /// rate-limited miss stays free to heal next try.
    private static func fetchHeldTokens(addresses: [String]) async -> [HeldToken]? {
        guard !addresses.isEmpty else { return nil }
        // Key on the ROUTED request, not the bare addresses: a chain toggled
        // off changes `networks(for:)`, and the key must move with it so a
        // config change can't be served a pre-toggle read from the cache.
        let key = addresses.sorted()
            .map { "\($0):\(networks(for: $0).joined(separator: ","))" }
            .joined(separator: "|")
        return await HoldingsCache.shared.tokens(key: key) {
            await fetchHeldTokensUncached(addresses: addresses)
        }
    }

    private static func fetchHeldTokensUncached(addresses: [String]) async -> [HeldToken]? {
        let (candidates, reached) = await collectCandidates(addresses: addresses)
        guard reached else { return nil }

        // Alchemy first — inline EVM prices, then its SPL Prices endpoint
        // (`priceSPL`) — then the keyless DeFiLlama backstop over anything still
        // unpriced. A token surfaces from the backstop EXACTLY when it would
        // otherwise be dropped by the `price > 0` guard below and vanish from
        // the treemap (worst on Solana, and worst under the shared Alchemy
        // key's rate limits — the two the backstop exists to cover).
        let priced = await priceSPL(candidates)
        let backstopped = await backstopPrices(priced)
        return backstopped.compactMap { c in
            guard let price = c.price, price > 0 else { return nil }
            let usd = c.amount * price
            // `.isFinite` FIRST: an untrusted balance/price can overflow to inf
            // (or NaN), and `inf >= holdingFloor` is true — so the floor alone
            // lets a poison value through to the treemap's `Int(...)` (crash)
            // and into the persisted sample (crash again next launch). The
            // ceiling then drops a fake-priced airdrop whose value is FINITE but
            // still absurdly large (see `holdingCeiling`) — treemapWeight clamps
            // that safely, but left in it would inflate the displayed combined
            // total and dominate the allocation bar.
            guard usd.isFinite, usd >= holdingFloor, usd < holdingCeiling else { return nil }
            return HeldToken(symbol: c.symbol, contract: c.contract,
                             network: c.network, usd: usd, owner: c.owner)
        }
    }

    /// The raw holdings Alchemy's Portfolio `by-address` hands back for the
    /// given addresses — balances + metadata + whatever prices it joined —
    /// before any floor, SPL fill, or backstop. Split out of `fetchHeldTokens`
    /// (2026-07-17) so the DeFiLlama probe can walk the SAME candidate list the
    /// real read builds. `reached` is false only when NOTHING was reachable at
    /// all (the nil the caller turns into "couldn't reach the chain").
    private static func collectCandidates(addresses: [String]) async -> (candidates: [Candidate], reached: Bool) {
        guard !addresses.isEmpty else { return ([], false) }
        // Zerion first (2026-07-19): one keyed `/positions` call per wallet
        // covers EVM + Solana holdings, priced, OFF Alchemy's paid credits — the
        // move that stops the biggest burn. Only when it actually answers
        // (`reached`); an empty key or an unreachable read falls straight through
        // to the Alchemy path below, so holdings never depend on Zerion being up.
        // See `ZerionAPI`.
        if ZerionAPI.isConfigured {
            let z = await collectCandidatesZerion(addresses: addresses)
            if z.reached { return z }
        }
        return await collectCandidatesAlchemy(addresses: addresses)
    }

    /// Zerion's holdings for the given wallets, mapped into `Candidate`s — the
    /// preferred read (see `collectCandidates`). `reached` is false only when NO
    /// wallet answered (the fall-back-to-Alchemy signal); one wallet answering is
    /// enough to prefer Zerion for the whole set. Each wallet is filtered to ITS
    /// OWN routed networks, so a chain toggled off in `WalletChainStore` is
    /// dropped even though the single Zerion call asked for every mapped chain.
    private static func collectCandidatesZerion(addresses: [String]) async -> (candidates: [Candidate], reached: Bool) {
        let routed = addresses.map { (address: $0, networks: Set(networks(for: $0))) }
                              .filter { !$0.networks.isEmpty }
        guard !routed.isEmpty else { return ([], false) }
        // Bounded like the Alchemy fan-out — Zerion's free tier is 10 req/s, and
        // a watched set of a dozen wallets shouldn't burst past it.
        let holdings = await IngestSupport.boundedGather(routed, maxConcurrent: 4) { r in
            await ZerionAPI.holdings(address: r.address)
        }
        var candidates: [Candidate] = []
        var reached = false
        for (i, result) in holdings.enumerated() {
            guard let result else { continue }   // this wallet unreached — skip it, don't fail the set
            reached = true
            let allowed = routed[i].networks
            for h in result where allowed.contains(h.network) {
                candidates.append(Candidate(symbol: h.symbol, contract: h.contract,
                                            network: h.network, amount: h.amount,
                                            owner: h.owner, price: h.price))
            }
        }
        return (candidates, reached)
    }

    private static func collectCandidatesAlchemy(addresses: [String]) async -> (candidates: [Candidate], reached: Bool) {
        guard !addresses.isEmpty else { return ([], false) }
        // network → the native coin's symbol AND decimals. A chain's own coin
        // comes back with null metadata, so neither can be read off the
        // response — both have to come from our table.
        let native = Dictionary(uniqueKeysWithValues:
            chains.map { ($0.network, (symbol: $0.symbol, decimals: $0.nativeDecimals)) })
        let url = "https://api.g.alchemy.com/data/v1/\(IngestSupport.alchemyKey)/assets/tokens/by-address"

        // Each address carries its OWN network list, by shape — so a chunk can
        // mix a `0x…` wallet and a `.sol` one and neither pays for the other's
        // chains. An address whose chains are all switched off has nothing to
        // ask and is dropped rather than sent with an empty list.
        let routed = addresses.map { (address: $0, networks: networks(for: $0)) }
                              .filter { !$0.networks.isEmpty }
        guard !routed.isEmpty else { return ([], false) }

        var candidates: [Candidate] = []
        var reached = false
        for chunk in stride(from: 0, to: routed.count, by: 3).map({
            Array(routed[$0..<min($0 + 3, routed.count)])
        }) {
            var pageKey: String? = nil
            for _ in 0..<8 {
                var body: [String: Any] = [
                    "addresses": chunk.map { ["address": $0.address, "networks": $0.networks] },
                    "withMetadata": true, "withPrices": true,
                ]
                if let pageKey { body["pageKey"] = pageKey }
                guard let root = await fetchPortfolioPage(url, body: body),
                      let data = root["data"] as? [String: Any],
                      let tokens = data["tokens"] as? [[String: Any]] else { break }
                reached = true

                for t in tokens {
                    let md = t["tokenMetadata"] as? [String: Any]
                    let mdSymbol = (md?["symbol"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    let network = (t["network"] as? String) ?? ""
                    // Native coin has no tokenAddress and no symbol — name it by
                    // chain. NOT lowercased: an EVM contract is case-insensitive
                    // hex, but a Solana mint is base58, where case IS the address.
                    let contract = t["tokenAddress"] as? String
                    let isNative = contract == nil
                    guard let symbol = mdSymbol ?? (isNative ? native[network]?.symbol : nil),
                          let balHex = t["tokenBalance"] as? String else { continue }
                    let decimals = (md?["decimals"] as? Int)
                        ?? (isNative ? native[network]?.decimals : nil)
                        ?? 18   // an ERC-20 that didn't report its own
                    candidates.append(Candidate(symbol: clean(symbol), contract: contract,
                                                network: network,
                                                amount: hexToDouble(balHex) / pow(10, Double(decimals)),
                                                owner: ((t["address"] as? String) ?? "").lowercased(),
                                                price: firstPrice(t["tokenPrices"])))
                }

                guard let next = data["pageKey"] as? String, !next.isEmpty else { break }
                pageKey = next
            }
        }
        return (candidates, reached)
    }

    /// One Portfolio page, retried on a rate limit or a transient server drop
    /// (2026-07-17). The key is shared across every user on Alchemy's free
    /// tier, so a 429 is a normal, self-healing condition — treating it like a
    /// hard failure is exactly what made a pinned wallet's card vanish on Home
    /// for one user while it loaded fine for another (same code, different
    /// luck). Retries a 429, a 5xx, or a transport drop (status 0) with a short
    /// backoff; a 400/401 (bad request / bad key) won't self-heal, so it fails
    /// fast. Total added wait is bounded (~2s worst case) so an offline device
    /// still falls through to the last-known card quickly rather than hanging.
    private static func fetchPortfolioPage(_ url: String, body: [String: Any]) async -> [String: Any]? {
        let backoff: [UInt64] = [500_000_000, 1_500_000_000]   // 0.5s, then 1.5s
        for attempt in 0...backoff.count {
            let (json, status) = await IngestSupport.postJSONStatus(url, body: body)
            if let root = json as? [String: Any] { return root }
            let retriable = status == 429 || status == 0 || (500...599).contains(status)
            guard retriable, attempt < backoff.count else { return nil }
            try? await Task.sleep(nanoseconds: backoff[attempt])
        }
        return nil
    }

    /// Prices the Solana holdings the Portfolio endpoint left unpriced.
    ///
    /// Measured 2026-07-16: `withPrices` prices EVM tokens inline, but on Solana
    /// it prices native SOL and nothing else — two different wallets, 100 tokens
    /// each, exactly one priced. Alchemy DOES know the SPL prices; that endpoint
    /// just doesn't join them. So the mints go back out through the Prices
    /// endpoint, which answers them (USDC $0.9999, JUP $0.2016). Without this a
    /// Solana wallet's treemap shows SOL alone and reads as "holds only SOL" —
    /// false, and exactly the kind of false the honesty rule is pointed at.
    ///
    /// Capped at 25 mints per request (its documented limit, measured: a 26th
    /// errors the call) and 100 in total — a treemap's top 5 is long since
    /// decided by then, and an unbounded fan-out over a whale's junk-token tail
    /// would spend a rate limit the transfer sync shares. The cap is applied in
    /// the order the API returned, NOT by iterating a Set: a wallet just over
    /// 100 mints (the test wallet returns exactly 100) would otherwise price an
    /// arbitrary subset each pass — Swift's Set order is seeded per process —
    /// and its treemap cells would come and go with the holdings unchanged.
    private static func priceSPL(_ candidates: [Candidate]) async -> [Candidate] {
        let mints = candidates.filter {
            $0.network == "solana-mainnet" && $0.price == nil
        }.compactMap(\.contract)
        guard !mints.isEmpty else { return candidates }
        var seen = Set<String>()
        let unique = Array(mints.filter { seen.insert($0).inserted }.prefix(100))
        let url = "https://api.g.alchemy.com/prices/v1/\(IngestSupport.alchemyKey)/tokens/by-address"

        var found: [String: Double] = [:]
        for chunk in stride(from: 0, to: unique.count, by: 25).map({
            Array(unique[$0..<min($0 + 25, unique.count)])
        }) {
            let body: [String: Any] = [
                "addresses": chunk.map { ["network": "solana-mainnet", "address": $0] },
            ]
            guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
                  let data = root["data"] as? [[String: Any]] else { continue }
            for entry in data {
                guard let address = entry["address"] as? String,
                      let price = firstPrice(entry["prices"]), price > 0 else { continue }
                found[address] = price
            }
        }
        guard !found.isEmpty else { return candidates }

        return candidates.map { c in
            guard c.price == nil, let contract = c.contract,
                  let price = found[contract] else { return c }
            var priced = c
            priced.price = price
            return priced
        }
    }

    /// Fills any candidate STILL unpriced after Alchemy — an EVM token its
    /// Portfolio didn't join a price for, or an SPL mint its Prices endpoint
    /// missed — from the keyless DeFiLlama backstop (`DefiLlamaPrices`, prd
    /// §115). It only ever fills `price == nil` (never overrides Alchemy) and
    /// only trusts a price at or above the confidence floor, so a token
    /// surfaces here exactly when it would otherwise be dropped by
    /// `fetchHeldTokens`' `price > 0` guard and vanish from the treemap. The
    /// whole wallet's misses go out in one batched request that doesn't ride
    /// the shared Alchemy key.
    private static func backstopPrices(_ candidates: [Candidate]) async -> [Candidate] {
        var seen = Set<String>()
        let unpriced = candidates.compactMap { c -> (network: String, contract: String)? in
            guard c.price == nil, let contract = c.contract,
                  seen.insert("\(c.network)|\(contract)").inserted else { return nil }
            return (network: c.network, contract: contract)
        }
        // Capped like `priceSPL` (100), in API order: a spam-heavy whale reports
        // ~180 unpriced mints, almost all junk DeFiLlama will never price, and
        // re-asking that tail on every foreground refresh is wasted work — a
        // treemap's top cells and the "across N tokens" count are long decided
        // by the first 100. Deduped first (a token held by several watched
        // wallets appears once per owner) so the cap counts distinct mints.
        guard !unpriced.isEmpty else { return candidates }
        let found = await DefiLlamaPrices.prices(for: Array(unpriced.prefix(100)))
        guard !found.isEmpty else { return candidates }

        return candidates.map { c in
            guard c.price == nil, let contract = c.contract,
                  let p = found["\(c.network)|\(contract)"],
                  p.confidence >= DefiLlamaPrices.confidenceFloor else { return c }
            var priced = c
            priced.price = p.price
            return priced
        }
    }

    #if DEBUG
    /// The `-defillamaProbe <address>` walk: for one wallet, how many held
    /// tokens Alchemy leaves unpriced and how many DeFiLlama then rescues — the
    /// backstop's whole reason to exist, measured end-to-end on a real wallet
    /// (prd §115). Reuses `collectCandidates` + `priceSPL`, so it exercises the
    /// exact path `fetchHeldTokens` runs, then reports the backstop's verdict
    /// per still-unpriced mint. Reads only.
    static func backstopDiagnostic(address: String) async -> [String] {
        // Resolve ENS / `.sol` names the way the real read does, or a name
        // routes as the wrong family and the Portfolio call comes back empty.
        let resolved = await resolvedAddresses([address])
        guard let addr = resolved.first else { return ["FAILED — couldn't resolve \(address)"] }
        // Deliberately the Alchemy path (not Zerion-first `collectCandidates`) —
        // this probe measures Alchemy's coverage vs the DeFiLlama backstop, and
        // Zerion-priced candidates would make "unpriced after Alchemy" a lie.
        let (candidates, reached) = await collectCandidatesAlchemy(addresses: [addr])
        guard reached else { return ["FAILED — nothing reachable (offline / bad key)"] }
        let afterAlchemy = await priceSPL(candidates)
        let unpriced = afterAlchemy.filter { $0.price == nil && $0.contract != nil }
        var out = [String(format: "%d held token(s), %d unpriced after Alchemy",
                          candidates.count, unpriced.count)]
        guard !unpriced.isEmpty else {
            out.append("nothing for the backstop to do")
            return out
        }
        let found = await DefiLlamaPrices.prices(for: unpriced.map {
            (network: $0.network, contract: $0.contract!)
        })
        var rescued = 0, lowConf = 0, missed = 0
        for c in unpriced {
            guard let p = found["\(c.network)|\(c.contract!)"] else {
                missed += 1
                out.append("  \(c.symbol) [\(c.network)]: no DeFiLlama price")
                continue
            }
            if p.confidence >= DefiLlamaPrices.confidenceFloor {
                rescued += 1
                out.append(String(format: "  %@: $%.4f (conf %.2f) → RESCUED", c.symbol, p.price, p.confidence))
            } else {
                lowConf += 1
                out.append(String(format: "  %@: $%.4f (conf %.2f) → below floor, skipped", c.symbol, p.price, p.confidence))
            }
        }
        out.append(String(format: "backstop: %d rescued, %d low-confidence, %d unpriced",
                          rescued, lowConf, missed))
        return out
    }
    #endif

    /// The contract addresses (lowercased) the given wallets hold above the
    /// dust floor — the activity spam filter's allowlist: a received token that
    /// isn't in this set was pushed at the wallet, not chosen by it. Native
    /// coins have no contract and are never spam-filtered anyway. nil (not an
    /// empty set) when the holdings read FAILED — the caller must then fail open
    /// and land everything, or a transient hiccup would silently drop every
    /// legitimate received token (an empty set is a real "holds nothing").
    static func heldPricedContracts(addresses: [String]) async -> Set<String>? {
        guard let tokens = await fetchHeldTokens(addresses: addresses) else { return nil }
        // Each entry normalised the way its OWN family compares, because this
        // set meets BOTH now (prd §86). An EVM leg's contract arrives
        // lowercased and its hex is case-insensitive, so folding case is free.
        // A Solana mint is base58, where case IS the address: lowercasing one
        // would match nothing and quietly filter every real SPL receipt out as
        // spam. The two alphabets can't collide, so one set still serves both.
        return Set(tokens.compactMap { token -> String? in
            guard let contract = token.contract else { return nil }
            return token.network == SolanaActivity.network ? contract : contract.lowercased()
        })
    }

    /// The same allowlist keyed by OWNER (lowercased address) — the approvals
    /// spam filter's shape (prd §84): a fake Approval event naming wallet A
    /// must not ride on wallet B's real holding, so the pooled set isn't
    /// allowed there. Entries are normalised per family exactly like
    /// `heldPricedContracts` (EVM lowercased, Solana mints case-preserved);
    /// `refresh` derives its pooled set from this map so the two filters ride
    /// ONE Portfolio fetch.
    static func heldPricedContractsByOwner(addresses: [String])
        async -> [String: Set<String>]? {
        guard let tokens = await fetchHeldTokens(addresses: addresses) else { return nil }
        var out: [String: Set<String>] = [:]
        for token in tokens {
            guard let contract = token.contract else { continue }
            let normalized = token.network == SolanaActivity.network
                ? contract : contract.lowercased()
            out[token.owner, default: []].insert(normalized)
        }
        return out
    }

    /// The NON-spam NFT contracts each wallet holds, keyed "address|network"
    /// (2026-07-15) — the NFT spam filter's allowlist, the sibling of
    /// `heldPricedContracts`. Alchemy's `getContractsForOwner` flags each held
    /// contract `isSpam`; a received NFT whose contract isn't among the wallet's
    /// non-spam holdings on that chain was an airdrop pushed at you. A KEY being
    /// present means that (address, chain) was read successfully — a missing key
    /// is "couldn't read", so the caller fails OPEN (an NFT on an unread chain
    /// is never dropped).
    static func ownedNFTContracts(addresses: [String]) async -> [String: Set<String>] {
        // The EVM chains getContractsForOwner serves — the five established
        // ones (Robinhood's NFT API may 404, which just leaves it unfiltered).
        let nets = ["eth-mainnet", "base-mainnet", "arb-mainnet", "opt-mainnet", "matic-mainnet"]
        let jobs = addresses.flatMap { a in nets.map { (a, $0) } }
        let results = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            let (addr, net) = job
            return ("\(addr.lowercased())|\(net)", await nonSpamContracts(address: addr, network: net))
        }
        var out: [String: Set<String>] = [:]
        for (key, contracts) in results {
            guard let contracts else { continue }   // failed read → key absent → fail open
            out[key] = contracts
        }
        return out
    }

    /// The non-spam NFT contracts (lowercased) an address holds on one chain, or
    /// nil when the read failed. Pages up to ~500 contracts — enough for a real
    /// collector without unbounded paging.
    private static func nonSpamContracts(address: String, network: String) async -> Set<String>? {
        var out = Set<String>()
        var pageKey: String?
        var reached = false
        for _ in 0..<5 {
            var url = "https://\(network).g.alchemy.com/nft/v3/\(IngestSupport.alchemyKey)"
                + "/getContractsForOwner?owner=\(address)&pageSize=100"
            if let pageKey, let enc = pageKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                url += "&pageKey=\(enc)"
            }
            guard let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let contracts = root["contracts"] as? [[String: Any]] else { break }
            reached = true
            for c in contracts {
                guard (c["isSpam"] as? Bool) != true,
                      let addr = c["address"] as? String else { continue }
                out.insert(addr.lowercased())
            }
            guard let next = root["pageKey"] as? String, !next.isEmpty else { break }
            pageKey = next
        }
        return reached ? out : nil
    }

    /// Alchemy network ids → the Dexscreener chain slugs TokenChart routes
    /// on (the inverse of TokenChart's own alchemyNetwork table).
    private static let chainSlug: [String: String] = [
        "eth-mainnet": "ethereum", "base-mainnet": "base", "arb-mainnet": "arbitrum",
        "opt-mainnet": "optimism", "matic-mainnet": "polygon",
        // Solana rides free: both chart tiers `TokenChart` falls through
        // (GeckoTerminal, then Dexscreener) spell it "solana", so an SPL cell's
        // tap opens a real chart the same way an ERC-20 cell's does.
        "solana-mainnet": "solana",
    ]

    /// A step-by-step trace of the holdings path for DiagnosticsScreen — the
    /// same call `topHoldings` makes, reporting each step's real result so a
    /// screenshot says WHY the treemap is (or isn't) on Home. Distinguishes an
    /// unreachable API from a wallet that simply holds nothing priced (all
    /// airdrop spam) — the latter is correct-but-empty, not a failure.
    @MainActor
    static func holdingsDiagnostic() async -> [String] {
        var out: [String] = []
        let watched = WalletStore.shared.addresses.map(\.address)
        guard !watched.isEmpty else { return ["No watched address"] }
        let addresses = await resolvedAddresses(watched)
        let evm = evmOnly(addresses)
        out.append("Resolved \(addresses.count)/\(watched.count) address(es) — \(evm.count) EVM, \(addresses.count - evm.count) Solana")
        guard !addresses.isEmpty else {
            out.append("FAIL address/ENS/.sol resolution — nothing to query")
            return out
        }

        // Routed by shape, exactly as `fetchHeldTokens` does — a diagnostic that
        // asked differently than the real read would be worse than none.
        let routed = addresses.map { (address: $0, networks: networks(for: $0)) }
                              .filter { !$0.networks.isEmpty }
        guard !routed.isEmpty else {
            out.append("FAIL every watched address's chains are switched off")
            return out
        }
        let url = "https://api.g.alchemy.com/data/v1/\(IngestSupport.alchemyKey)/assets/tokens/by-address"
        let body: [String: Any] = [
            "addresses": routed.map { ["address": $0.address, "networks": $0.networks] },
            "withMetadata": true, "withPrices": true,
        ]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any] else {
            out.append("FAIL Portfolio API unreachable (no 200 JSON) — key or network")
            return out
        }
        guard let data = root["data"] as? [String: Any],
              let tokens = data["tokens"] as? [[String: Any]] else {
            out.append("FAIL Portfolio API returned no data.tokens (unexpected shape)")
            return out
        }
        let priced = tokens.filter { (firstPrice($0["tokenPrices"]) ?? 0) > 0 }.count
        let solTokens = tokens.filter { ($0["network"] as? String) == "solana-mainnet" }.count
        out.append("Tokens returned: \(tokens.count) (\(solTokens) Solana), priced inline: \(priced)")
        if solTokens > 0 {
            out.append("Solana: inline prices cover native SOL only — SPL prices come from the separate Prices call")
        }
        let groups = await topHoldingsByWallet()
        if !groups.isEmpty {
            for g in groups {
                out.append("OK \(g.label): \(g.cells.count) cells — \(g.cells.joined(separator: ", "))")
            }
        } else if priced == 0 && solTokens == 0 {
            out.append("Empty (correct): nothing priced held — only unpriced/airdrop tokens")
        } else {
            out.append(String(format: "Empty: %d priced token(s), all under the $%.2f floor (dust/spam)", priced, holdingFloor))
        }
        return out
    }

    private static func firstPrice(_ raw: Any?) -> Double? {
        guard let arr = raw as? [[String: Any]], let first = arr.first else { return nil }
        // `.isFinite`: `Double("1e400")` returns `.infinity`, not nil, so an
        // absurd/malformed price string would otherwise pass straight through.
        if let s = first["value"] as? String, let d = Double(s), d.isFinite { return d }
        if let d = first["value"] as? Double, d.isFinite { return d }
        return nil
    }

    static func hexToDouble(_ hex: String) -> Double {
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        var v = 0.0
        for c in s { guard let d = c.hexDigitValue else { return v }; v = v * 16 + Double(d) }
        return v
    }

    /// A treemap cell's area weight from a USD value, in a guaranteed-safe Int
    /// range. `Int(Double)` TRAPS on a non-finite or oversized value, and these
    /// USD numbers are built from untrusted on-chain data: a spam/airdrop
    /// token's bogus price string parses to `.infinity` (Swift's `Double(_:)`
    /// overflows to inf, it does NOT return nil), and a giant balance hex
    /// overflows `hexToDouble` to a huge/inf Double — either sails past the
    /// `usd >= holdingFloor` gate (inf and huge finite both compare `>=`) and,
    /// because inf sorts to the top, is guaranteed into the top-5 cells. A raw
    /// `Int(usd.squareRoot() * 10)` was therefore a launch crash for any wallet
    /// holding one such token, and — since the value is persisted in the
    /// last-known sample — it replayed on every later cold launch. Clamp so a
    /// bad value degrades to a small cell instead of killing the process.
    static func treemapWeight(_ usd: Double) -> Int {
        let scaled = usd.squareRoot() * 10
        guard scaled.isFinite else { return 1 }
        return max(1, Int(min(scaled, 1_000_000)))
    }

    /// A hex quantity as an Int, clamped to a safe range. `Int(Double)` traps
    /// on a non-finite or oversized value, and these hex strings come from
    /// untrusted on-chain data / the flaky public RPCs the wallet reads — a
    /// malformed or adversarial response must degrade, not kill the process.
    /// Used for block numbers, log indices, and the like where a plain
    /// `Int(hexToDouble(...))` would be a crash on bad input. The cap (9e15) is
    /// far above any real block number yet below 2^53, so `Int(_:)` is exact.
    static func hexToInt(_ hex: String) -> Int {
        let v = hexToDouble(hex)
        guard v.isFinite, v >= 0 else { return 0 }
        return v < 9_000_000_000_000_000 ? Int(v) : 9_000_000_000_000_000
    }

    private static func clean(_ symbol: String) -> String {
        let up = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        return up.isEmpty ? "TOKEN" : String(up.prefix(6))
    }

    /// Compact amount: 1,240 · 0.53 · 0.00042. Shared with `SolanaActivity`,
    /// whose titles sit beside these in the same feed and must round alike.
    static func format(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v >= 1000 {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
            // `%.0f`, not `Int(v)`: the formatter returns nil exactly for
            // NaN/inf, and `Int(v)` would then trap on that same value.
            return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
        }
        if v >= 1 { return String(format: "%.2f", v) }
        return String(format: "%.4f", v)
    }
}
