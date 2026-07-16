import Foundation
import SwiftData

/// The wallet bridge (2026-07-08) — reads a public wallet's onchain activity
/// (received/sent, tokens in and out) across chains and lands it as things.
/// Powered by Alchemy's Transfers API, called directly from this iPhone: no
/// server. The address is public and read-only — watching one can never trade
/// or move funds. (This replaced the Zerion concept: Zerion's key is server-
/// only by their rules, so it couldn't stay serverless; Alchemy can.)
enum WalletIngest {

    /// Every chain we CAN read, and where a tx opens. One `getAssetTransfers`
    /// per direction per chain.
    private struct Chain { let network, explorer, symbol: String }
    private static let allChains: [Chain] = [
        Chain(network: "eth-mainnet",  explorer: "https://etherscan.io/tx/",              symbol: "ETH"),
        Chain(network: "base-mainnet", explorer: "https://basescan.org/tx/",              symbol: "ETH"),
        Chain(network: "arb-mainnet",  explorer: "https://arbiscan.io/tx/",               symbol: "ETH"),
        Chain(network: "opt-mainnet",  explorer: "https://optimistic.etherscan.io/tx/",   symbol: "ETH"),
        Chain(network: "matic-mainnet",explorer: "https://polygonscan.com/tx/",           symbol: "MATIC"),
        Chain(network: "robinhood-mainnet", explorer: "https://robinhoodchain.blockscout.com/tx/", symbol: "ETH"),
    ]

    /// The chains actually read this pass — the person's selection (default: all
    /// of them). Filtered from `allChains` so turning a chain off drops it from
    /// the transfer sync, the holdings read, and the value samples alike, and
    /// spends no requests on it. Read off Observation (`activeNetworkIDs`), so
    /// the background holdings fetches can call it safely (2026-07-15).
    private static var chains: [Chain] {
        let active = Set(WalletChainStore.activeNetworkIDs())
        return allChains.filter { active.contains($0.network) }
    }

    @MainActor private static var running = false

    /// The USD floor a holding must clear to count (ruling 2026-07-15, up from
    /// $1). Airdrop-spam tokens that carry a fake price were sneaking past the
    /// old $1 line and inflating the "across N tokens" count / treemap; $1.99
    /// drops the dust while keeping genuine small positions.
    static let holdingFloor: Double = 1.99

    /// Reads recent transfers for every watched address, across chains, and
    /// lands new ones. Returns the new count, or nil when nothing could be
    /// reached at all (offline / bad key).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let watched = WalletStore.shared.addresses.map(\.address)
        guard !watched.isEmpty, !running else { return watched.isEmpty ? nil : 0 }
        running = true
        defer { running = false }

        // Watched entries can be ENS names; the Transfers API needs hex —
        // resolve first, or nothing ever lands (the bug: a watched name
        // returned empty silently).
        let addresses = await hexAddresses(watched)
        guard !addresses.isEmpty else { return nil }

        let existing = IngestSupport.existingSourceRefs(context)

        // Every (address, chain, direction) combination is an independent
        // network call — fetched serially before, up to
        // `addresses × chains × 2` round trips in a row on every foreground
        // (2026-07-13: seconds of wall-clock for a couple of watched
        // wallets). Fanned out, capped at 4 in flight — Alchemy's free-tier
        // key rate-limits per second, and an uncapped burst (up to 30
        // requests for 3 wallets) drew silent 429s that the old serial
        // pacing never triggered (review 2026-07-13). `boundedGather`
        // preserves job order, matching `topHoldingsByWallet` below.
        let jobs = addresses.flatMap { address in
            chains.flatMap { chain in
                [true, false].map { received in (address, chain, received) }   // received (to) + sent (from)
            }
        }
        let results = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            let (address, chain, received) = job
            return (address, chain, received, await fetch(address: address, chain: chain, received: received))
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
                fresh.append(leg)
            }
        }
        // Name the new transfers' counterparties BEFORE landing them — a
        // title is written once, so the name has to be there at write time.
        let names = await counterpartyNames(for: fresh)
        // The tokens the wallet actually HOLDS above the dust floor — an
        // airdrop-spam token that was never really held (unpriced, or under the
        // floor) is dropped from the ACTIVITY feed too now (2026-07-15), the
        // same way the holdings treemap already drops it. One batched read for
        // the whole pass.
        let heldPriced = await heldPricedContracts(addresses: addresses)
        // …and the non-spam NFT contracts each wallet holds, for the NFT arm of
        // the same filter — an airdropped junk NFT is dropped from the feed the
        // way a junk token is (2026-07-15). Keyed "address|network".
        let ownedNFTs = await ownedNFTContracts(addresses: addresses)

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
        if added > 0 { context.saveHonestly() }
        return reachedAny ? added : nil
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
        thing.counterpartyAddress = router
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

    /// Resolves watched entries to hex, dropping any ENS name that won't
    /// resolve (a typo'd name simply lands nothing, honestly).
    private static func hexAddresses(_ raw: [String]) async -> [String] {
        var out: [String] = []
        for a in raw {
            if ENS.isHexAddress(a) { out.append(a) }
            else if let hex = await ENS.resolve(a) { out.append(hex) }
        }
        return out
    }

    private static func fetch(address: String, chain: Chain,
                              received: Bool) async -> [[String: Any]]? {
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
            "category": ["external", "internal", "erc20", "erc721", "erc1155"],
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
            }
            title = t2
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

        /// "$12.4K across 5 tokens" — compact, no cents theater.
        var subline: String {
            let amount: String
            if totalUSD >= 1_000_000 { amount = String(format: "$%.1fM", totalUSD / 1_000_000) }
            else if totalUSD >= 10_000 { amount = String(format: "$%.0fK", totalUSD / 1_000) }
            else if totalUSD >= 1_000 { amount = String(format: "$%.1fK", totalUSD / 1_000) }
            else { amount = String(format: "$%.0f", totalUSD) }
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
    @MainActor
    static func holdingsChart() async -> [String]? {
        let groups = await topHoldingsByWallet()
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
    /// zero wallets (one wallet's own view already IS its portfolio).
    @MainActor
    static func combinedHoldings(pinnedOnly: Bool = false) async -> HoldingsGroup? {
        let watched = pinnedOnly
            ? WalletStore.shared.addresses.filter(\.pinnedToHome)
            : WalletStore.shared.addresses
        guard watched.count > 1 else { return nil }
        let hexes = await hexAddresses(watched.map(\.address))
        guard !hexes.isEmpty, let h = await holdings(addresses: hexes) else { return nil }
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
    /// composing its own document (Home's and Feed's pinned-wallet module)
    /// rather than rendering the Wallet screen's standalone one. A wallet
    /// with nothing priced simply doesn't contribute a group (correct-but-
    /// empty, not a failure) — order follows watch order, the first address leads.
    /// `pinnedOnly` restricts to addresses with their own pin on (Home and
    /// Feed's leading module); the Wallet screen and its own Feed chip show
    /// everything watched regardless of pin (ruling 2026-07-09).
    @MainActor
    static func topHoldingsByWallet(pinnedOnly: Bool = false) async -> [HoldingsGroup] {
        let watched = pinnedOnly
            ? WalletStore.shared.addresses.filter(\.pinnedToHome)
            : WalletStore.shared.addresses
        guard !watched.isEmpty else { return [] }
        // Concurrent, not sequential — three watched wallets waiting on three
        // requests in a row is the difference between a couple seconds and
        // most of an app launch (2026-07-09: separating wallets must not
        // make the pinned module noticeably slower to appear than the old
        // single combined request was).
        let results = await withTaskGroup(of: (Int, HoldingsGroup?).self) { group in
            for (i, entry) in watched.enumerated() {
                group.addTask {
                    guard let hex = await hexAddresses([entry.address]).first,
                          let h = await holdings(addresses: [hex]) else { return (i, nil) }
                    return (i, HoldingsGroup(label: entry.label.isEmpty ? entry.short : entry.label,
                                             address: entry.address,
                                             cells: h.cells, totalUSD: h.total,
                                             tokenCount: h.count,
                                             topBySymbol: topBySymbol(h.bySymbol)))
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
        // moment (delight 2026-07-15) — fired only over the FULL watched set
        // (`!pinnedOnly`, so Home's pinned pass and the Wallet screen's full
        // pass can't disagree on the mark) and only with more than one wallet
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
        if !pinnedOnly, watched.count > 1, groups.count == watched.count {
            let combined = groups.reduce(0.0) { $0 + $1.totalUSD }
            let signature = watched.map { $0.address.lowercased() }.sorted().joined(separator: ",")
            if WalletMoments.shared.notedNewHigh(scope: "combined:\(signature)", value: combined) {
                WalletMoments.shared.fire(String(localized: "Across your wallets: a new high, \(TokenStats.compact(combined)) 📈"))
            }
        }
        return groups
    }

    /// The top-5-by-value cells for one or more hex addresses, combined —
    /// builds on `fetchHeldTokens` (the shared read), so the treemap and the
    /// activity spam filter agree on what "held" means. `bySymbol` (every
    /// counted position summed by symbol) rides out too, for the combined
    /// sheet's per-token attribution (2026-07-15).
    private static func holdings(addresses: [String])
        async -> (cells: [String], total: Double, count: Int, bySymbol: [String: Double])? {
        guard let tokens = await fetchHeldTokens(addresses: addresses) else { return nil }
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
        guard !bySymbol.isEmpty else { return nil }

        // Top 5 by value; sqrt-scale so a big holding doesn't slice the rest
        // to slivers. Icons for "token" mode are a bundled local set keyed by
        // symbol (TokenIcon) — Alchemy's own logo field turned out null for
        // nearly everything, so the cell string carries no icon data. A routed
        // cell trails "@t:chain:address" (stripped by KindCountRow.parse, never
        // shown) so a tap can open that token's chart.
        let cells = bySymbol.sorted { $0.value > $1.value }.prefix(5)
            .map { sym, usd in
                let route = routeBySymbol[sym].map { " @t:\($0.route)" } ?? ""
                return "\(sym) \(max(1, Int(usd.squareRoot() * 10)))\(route)"
            }
        return (cells, bySymbol.values.reduce(0, +), bySymbol.count, bySymbol)
    }

    /// One priced token a wallet holds — the shared read behind both the
    /// holdings treemap and the activity spam filter, so "what you hold" means
    /// the same thing to both. Native coins carry a nil contract.
    private struct HeldToken {
        let symbol: String
        let contract: String?
        let network: String
        let usd: Double
    }

    /// Every priced token (>= the dust floor) the given addresses hold, across
    /// the read chains — Alchemy's Portfolio `by-address` (balances + metadata +
    /// prices in one call). Chunked at 3 addresses ("Maximum allowed addresses
    /// is 3", measured 2026-07-15 — a 4th 400s the whole call) and paged up to
    /// 8 pages (≈800 tokens) so a whale's real holdings surface without
    /// unbounded paging. nil only when nothing was reachable at all.
    private static func fetchHeldTokens(addresses: [String]) async -> [HeldToken]? {
        guard !addresses.isEmpty else { return nil }
        let networks = chains.map(\.network)
        // network → native symbol, so a chain's own coin (ETH/MATIC) — which
        // the API returns with a null symbol — still names itself.
        let native = Dictionary(uniqueKeysWithValues: chains.map { ($0.network, $0.symbol) })
        let url = "https://api.g.alchemy.com/data/v1/\(IngestSupport.alchemyKey)/assets/tokens/by-address"

        var out: [HeldToken] = []
        var reached = false
        for chunk in stride(from: 0, to: addresses.count, by: 3).map({
            Array(addresses[$0..<min($0 + 3, addresses.count)])
        }) {
            var pageKey: String? = nil
            for _ in 0..<8 {
                var body: [String: Any] = [
                    "addresses": chunk.map { ["address": $0, "networks": networks] },
                    "withMetadata": true, "withPrices": true,
                ]
                if let pageKey { body["pageKey"] = pageKey }
                guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
                      let data = root["data"] as? [String: Any],
                      let tokens = data["tokens"] as? [[String: Any]] else { break }
                reached = true

                for t in tokens {
                    let md = t["tokenMetadata"] as? [String: Any]
                    let mdSymbol = (md?["symbol"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    // Native coin has no tokenAddress and no symbol — name it by chain.
                    let isNative = (t["tokenAddress"] as? String) == nil
                    guard let symbol = mdSymbol ?? (isNative ? native[t["network"] as? String ?? ""] : nil),
                          let balHex = t["tokenBalance"] as? String,
                          let price = firstPrice(t["tokenPrices"]), price > 0 else { continue }
                    let decimals = (md?["decimals"] as? Int) ?? 18   // native is always 18
                    let amount = hexToDouble(balHex) / pow(10, Double(decimals))
                    let usd = amount * price
                    guard usd >= holdingFloor else { continue }
                    out.append(HeldToken(symbol: clean(symbol),
                                         contract: (t["tokenAddress"] as? String)?.lowercased(),
                                         network: (t["network"] as? String) ?? "",
                                         usd: usd))
                }

                guard let next = data["pageKey"] as? String, !next.isEmpty else { break }
                pageKey = next
            }
        }
        guard reached else { return nil }
        return out
    }

    /// The contract addresses (lowercased) the given wallets hold above the
    /// dust floor — the activity spam filter's allowlist: a received token that
    /// isn't in this set was pushed at the wallet, not chosen by it. Native
    /// coins have no contract and are never spam-filtered anyway. nil (not an
    /// empty set) when the holdings read FAILED — the caller must then fail open
    /// and land everything, or a transient hiccup would silently drop every
    /// legitimate received token (an empty set is a real "holds nothing").
    private static func heldPricedContracts(addresses: [String]) async -> Set<String>? {
        guard let tokens = await fetchHeldTokens(addresses: addresses) else { return nil }
        return Set(tokens.compactMap(\.contract))
    }

    /// The NON-spam NFT contracts each wallet holds, keyed "address|network"
    /// (2026-07-15) — the NFT spam filter's allowlist, the sibling of
    /// `heldPricedContracts`. Alchemy's `getContractsForOwner` flags each held
    /// contract `isSpam`; a received NFT whose contract isn't among the wallet's
    /// non-spam holdings on that chain was an airdrop pushed at you. A KEY being
    /// present means that (address, chain) was read successfully — a missing key
    /// is "couldn't read", so the caller fails OPEN (an NFT on an unread chain
    /// is never dropped).
    private static func ownedNFTContracts(addresses: [String]) async -> [String: Set<String>] {
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
    ]

    // MARK: - NFTs (2026-07-14)

    /// One NFT a watched wallet holds — enough for a shelf cell and its
    /// OpenSea door. Read-only public data, like everything else here.
    struct WalletNFT: Identifiable {
        let contract: String
        let tokenId: String
        let name: String
        let collection: String
        let imageURL: String
        /// OpenSea's chain path ("ethereum", "base").
        let chainPath: String
        var id: String { "\(chainPath):\(contract):\(tokenId)" }
        var openseaURL: URL? {
            URL(string: "https://opensea.io/assets/\(chainPath)/\(contract)/\(tokenId)")
        }
    }

    struct NFTGroup {
        /// The watched entry's own address string — the stable row identity
        /// (labels are free text and can repeat).
        let address: String
        let label: String
        let nfts: [WalletNFT]
    }

    /// NFT holdings change rarely; every Wallet-screen appearance re-hitting
    /// 2 GETs per wallet for identical bytes wastes quota (the TokenPulse
    /// 15-minute idiom). Keyed by the watched set, so add/remove refetches.
    @MainActor private static var nftCache: (key: String, at: Date, groups: [NFTGroup])?

    /// Every watched wallet's NFTs, one group per wallet that holds any —
    /// the Wallet screen's shelf. A wallet with none simply contributes no
    /// group (correct-but-empty, not a failure). Wallets fetch concurrently
    /// (bounded — the same Alchemy key the transfer sync bursts on).
    @MainActor
    static func nftsByWallet() async -> [NFTGroup] {
        let watched = WalletStore.shared.addresses
        guard !watched.isEmpty else { return [] }
        let key = watched.map { $0.address.lowercased() }.sorted().joined(separator: ",")
        if let cached = nftCache, cached.key == key,
           cached.at.timeIntervalSinceNow > -900 {
            return cached.groups
        }
        let fetched = await IngestSupport.boundedGather(watched, maxConcurrent: 4) { entry in
            guard let hex = await hexAddresses([entry.address]).first else {
                return NFTGroup(address: entry.address, label: "", nfts: [])
            }
            return NFTGroup(address: entry.address,
                            label: entry.label.isEmpty ? entry.short : entry.label,
                            nfts: await nfts(addressHex: hex))
        }
        let groups = fetched.filter { !$0.nfts.isEmpty }
        nftCache = (key, .now, groups)
        // A watched wallet receiving a new piece is a moment (delight
        // 2026-07-15) — the berry rain falls and the toast names it, sibling
        // to the starred-repo release rain. Silent on the first-ever read
        // (seeds the baseline; no "received 40 NFTs" on connect).
        let arrivals = WalletMoments.shared.newlyArrived(from: groups)
        if let first = arrivals.first {
            let more = arrivals.count > 1 ? " +\(arrivals.count - 1) more" : ""
            WalletMoments.shared.fire(String(localized: "\(first.label) received \(first.nft.name)\(more) 🖼️"))
        }
        return groups
    }

    /// The NFT strips Home shows (ruling 2026-07-14): pinned wallets only,
    /// minus any whose strip was long-press removed. Rides the same cache as
    /// the Wallet screen's shelves.
    @MainActor
    static func pinnedNFTGroups() async -> [NFTGroup] {
        let showing = WalletStore.shared.addresses
            .filter { $0.pinnedToHome && !$0.nftStripHidden }
            .map { $0.address.lowercased() }
        guard !showing.isEmpty else { return [] }
        return await nftsByWallet().filter { showing.contains($0.address.lowercased()) }
    }

    /// A wallet's NFTs off Alchemy's NFT API — the image-bearing chains
    /// (Ethereum + Base), spam filtered, first page only. Pieces without an
    /// image are skipped: a shelf of gray squares says nothing.
    static func nfts(addressHex: String, limit: Int = 12) async -> [WalletNFT] {
        let sources: [(network: String, path: String)] =
            [("eth-mainnet", "ethereum"), ("base-mainnet", "base")]
        var out: [WalletNFT] = []
        for source in sources {
            let url = "https://\(source.network).g.alchemy.com/nft/v3/\(IngestSupport.alchemyKey)"
                + "/getNFTsForOwner?owner=\(addressHex)&withMetadata=true"
                + "&pageSize=\(limit)&excludeFilters%5B%5D=SPAM"
            guard let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let owned = root["ownedNfts"] as? [[String: Any]] else { continue }
            for n in owned {
                guard let contract = n["contract"] as? [String: Any],
                      let contractAddr = contract["address"] as? String,
                      let tokenId = n["tokenId"] as? String,
                      let image = n["image"] as? [String: Any],
                      let imageURL = IngestSupport.imageURL(
                        (image["thumbnailUrl"] as? String) ?? (image["cachedUrl"] as? String))
                else { continue }
                let collection = ((contract["openSeaMetadata"] as? [String: Any])?["collectionName"] as? String)
                    ?? (contract["name"] as? String) ?? ""
                let shortId = tokenId.count > 8 ? "\(tokenId.prefix(6))…" : tokenId
                let name = (n["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (collection.isEmpty ? "#\(shortId)" : "\(collection) #\(shortId)")
                out.append(WalletNFT(contract: contractAddr, tokenId: tokenId,
                                     name: name, collection: collection,
                                     imageURL: imageURL, chainPath: source.path))
            }
        }
        return Array(out.prefix(limit))
    }

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
        let addresses = await hexAddresses(watched)
        out.append("Resolved \(addresses.count)/\(watched.count) address(es) to hex")
        guard !addresses.isEmpty else {
            out.append("FAIL address/ENS resolution — nothing to query")
            return out
        }

        let networks = chains.map(\.network)
        let url = "https://api.g.alchemy.com/data/v1/\(IngestSupport.alchemyKey)/assets/tokens/by-address"
        let body: [String: Any] = [
            "addresses": addresses.map { ["address": $0, "networks": networks] },
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
        out.append("Tokens returned: \(tokens.count), of which priced: \(priced)")
        let groups = await topHoldingsByWallet()
        if !groups.isEmpty {
            for g in groups {
                out.append("OK \(g.label): \(g.cells.count) cells — \(g.cells.joined(separator: ", "))")
            }
        } else if priced == 0 {
            out.append("Empty (correct): nothing priced held — only unpriced/airdrop tokens")
        } else {
            out.append(String(format: "Empty: %d priced token(s), all under the $%.2f floor (dust/spam)", priced, holdingFloor))
        }
        return out
    }

    private static func firstPrice(_ raw: Any?) -> Double? {
        guard let arr = raw as? [[String: Any]], let first = arr.first else { return nil }
        if let s = first["value"] as? String { return Double(s) }
        if let d = first["value"] as? Double { return d }
        return nil
    }

    private static func hexToDouble(_ hex: String) -> Double {
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        var v = 0.0
        for c in s { guard let d = c.hexDigitValue else { return v }; v = v * 16 + Double(d) }
        return v
    }

    private static func clean(_ symbol: String) -> String {
        let up = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        return up.isEmpty ? "TOKEN" : String(up.prefix(6))
    }

    /// Compact amount: 1,240 · 0.53 · 0.00042.
    private static func format(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v >= 1000 {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: v)) ?? String(Int(v))
        }
        if v >= 1 { return String(format: "%.2f", v) }
        return String(format: "%.4f", v)
    }
}
