import Foundation

/// A keyed read over the Zerion API (`api.zerion.io/v1`), added 2026-07-19 to
/// move the wallet holdings hot path OFF Alchemy's paid credits (the account
/// went pay-as-you-go on Alchemy and hit the ceiling — the shared free key is
/// no longer free). One `/wallets/{address}/positions` call returns every
/// fungible holding across EVM AND Solana in one normalized, PRICED response,
/// with per-chain contract inline — replacing the Alchemy Portfolio
/// `by-address` call (the app's single biggest credit burn, fanned out 5–8× a
/// foreground) AND its separate SPL Prices fill (`WalletIngest.priceSPL`) in
/// one keyed request on Zerion's free developer tier (60k calls/month).
///
/// UNMEASURED against the live API. Written against Zerion's documented schema
/// (developers.zerion.io, `listWalletPositions`) but NOT yet exercised on device
/// — this file was authored on a Linux box with no Xcode/simulator, so the
/// field paths, the native-coin shape, and the Solana chain id are spec-derived,
/// not observed. Mirrors the 1Claw precedent (prd §111): ship behind a probe,
/// re-measure before trusting. Run `-zerionProbe <address>` on a real wallet and
/// compare its holdings against the treemap before relying on it.
///
/// Alchemy stays the FALLBACK (see `WalletIngest.collectCandidates`): an empty
/// key here, or any unreachable/failed read, silently falls through to today's
/// Alchemy path, so shipping this — or shipping it before the key is pasted in —
/// cannot break holdings. Zerion is preferred only when it actually answers.
enum ZerionAPI {

    /// The shipped read-only Zerion key. Paste your `zk_…` from
    /// dashboard.zerion.io here. EMPTY = Zerion off → the Alchemy fallback runs,
    /// exactly as before. Ships in the binary like `IngestSupport.alchemyKey`; a
    /// Zerion API key grants read-only portfolio data, the same risk class as the
    /// Alchemy key already committed here — if it leaks, the worst case is quota
    /// use on public data. Rotate at dashboard.zerion.io.
    static let key = "zk_9e6723c493c64070adb76e706757ad96"

    /// Whether a real key is configured. When false every entry point returns nil
    /// immediately (no request, no auth header built), so the Alchemy fallback
    /// takes over with zero cost.
    static var isConfigured: Bool { !key.isEmpty }

    /// Zerion chain id → the Alchemy network id the rest of the app keys on
    /// (`WalletChainStore`, the treemap, `DefiLlamaPrices.chainKey`). The inverse
    /// of `DefiLlamaPrices.chainKey`, and deliberately ONLY the chains Casberi
    /// reads: a Zerion position on any other chain is skipped, never mis-mapped
    /// onto a network the treemap can't route.
    static let networkFor: [String: String] = [
        "ethereum": "eth-mainnet", "base": "base-mainnet", "arbitrum": "arb-mainnet",
        "optimism": "opt-mainnet", "polygon": "matic-mainnet", "solana": "solana-mainnet",
        // 2026-08-28 (prd §512). Zerion's own ids, read off `/v1/chains/` and checked
        // against a live wallet on each (positions AND transactions), never
        // guessed from the display name: HyperEVM is `hyperevm` here while
        // Alchemy calls the same chain `hyperliquid-mainnet`, and the two
        // spellings sitting either side of one entry is exactly the drift this
        // table exists to hold.
        "hyperevm": "hyperliquid-mainnet", "monad": "monad-mainnet",
    ]

    /// One fungible holding as Zerion hands it over — already decimal-adjusted
    /// (`quantity.float`, so no decimals math and none of the `?? 18` SOL trap
    /// the Alchemy path lives with) and priced. The neutral shape
    /// `WalletIngest` maps straight into its private `Candidate`.
    struct Holding {
        let symbol: String
        /// nil = the chain's native coin (Zerion reports it with no on-chain
        /// implementation address). Passed through UNCHANGED downstream — an EVM
        /// address is case-insensitive hex but a Solana mint is base58 where case
        /// IS the address, so this must not be folded (the per-family rule
        /// `WalletIngest.heldPricedContracts` already lives with).
        let contract: String?
        /// Alchemy network id (mapped through `networkFor`).
        let network: String
        let amount: Double
        /// nil when Zerion didn't price it — `WalletIngest` then lets its SPL /
        /// DeFiLlama fills cover the gap exactly as they cover an Alchemy miss.
        let price: Double?
        let owner: String
    }

    /// Every simple (wallet) fungible holding for one address, across the chains
    /// Casberi maps — priced, non-trash — or nil when Zerion couldn't be reached
    /// at all (the caller's honest-failure signal to fall back to Alchemy; an
    /// EMPTY array is a real "holds nothing"). Filters server-side to
    /// `only_simple` non-trash positions so DeFi LP/loan legs and airdrop spam
    /// never reach the treemap. The address goes in the PATH; auth is HTTP Basic
    /// over base64("<key>:") (Zerion's documented scheme — key as the username,
    /// empty password).
    static func holdings(address: String) async -> [Holding]? {
        // THE DEMO REACHES NOTHING (2026-08-12). Gated at the network
        // boundary, not at a caller: holdings are read from `WalletWatch
        // .liveState` — a per-view read the foreground sweep's demo gate
        // cannot see — and the wallet room is the one room a demo opens with.
        // Found by `verify.sh`'s "Demo reaches nothing" step on its FIRST run,
        // after two earlier reaches of this same class had been found only by
        // reading. nil is the honest answer here: every caller already handles
        // an unreached wallet, and the demo's balances come from its own
        // seeded samples.
        if DemoMode.isActive { return nil }
        guard isConfigured,
              let auth = "\(key):".data(using: .utf8)?.base64EncodedString(),
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        // Ask only for the chains we can route; `filter[positions]=only_simple`
        // drops complex DeFi positions and `filter[trash]=only_non_trash` drops
        // spam, so what comes back is exactly the treemap's population.
        // MEASURED 2026-07-19: `filter[chain_ids]` 400s on `solana` even though
        // `/chains` lists it as a real chain id (and it appears fine in a
        // position's `implementations[].chain_id`) — the filter only accepts EVM
        // chain ids. Solana positions simply aren't reachable through this
        // filtered call; excluding it here is required for EVERY request to
        // succeed, not just Solana wallets (an EVM-only address still 400s if
        // `solana` rides along in the filter list).
        let chains = networkFor.keys.filter { $0 != "solana" }.sorted().joined(separator: ",")
        let query = "filter[positions]=only_simple"
            + "&filter[trash]=only_non_trash"
            + "&currency=usd"
            + "&filter[chain_ids]=\(chains)"
        let url = "https://api.zerion.io/v1/wallets/\(encoded)/positions/?\(query)"

        guard let root = await IngestSupport.getJSON(url, auth: "Basic \(auth)") as? [String: Any],
              let data = root["data"] as? [[String: Any]] else { return nil }

        let owner = address.lowercased()   // matches the Alchemy candidate path
        var out: [Holding] = []
        for item in data {
            guard let attrs = item["attributes"] as? [String: Any] else { continue }
            // Defensive: only simple wallet holdings, never a trash position that
            // slipped the server filter.
            if let flags = attrs["flags"] as? [String: Any],
               flags["is_trash"] as? Bool == true { continue }

            guard let chainId = ((item["relationships"] as? [String: Any])?["chain"]
                    as? [String: Any])?["data"] as? [String: Any],
                  let zid = chainId["id"] as? String,
                  let network = networkFor[zid] else { continue }

            let info = attrs["fungible_info"] as? [String: Any]
            // Symbol first, name as the fallback (the label rule, user
            // 2026-07-21) — a token without a registered ticker used to drop
            // out of the holdings entirely; the Alchemy path applies the same
            // fallback from its tokenMetadata.
            guard let symbol = (info?["symbol"] as? String).flatMap({ $0.isEmpty ? nil : $0 })
                    ?? (info?["name"] as? String).flatMap({ $0.isEmpty ? nil : $0 }),
                  let quantity = attrs["quantity"] as? [String: Any],
                  let amount = doubleValue(quantity["float"]), amount > 0 else { continue }

            // The on-chain address for THIS position's chain. Absent / empty ⇒
            // the native coin (contract nil), the same signal the Alchemy path
            // reads from a missing `tokenAddress`.
            let contract = implementationAddress(info?["implementations"], chainId: zid)

            out.append(Holding(symbol: clean(symbol), contract: contract, network: network,
                               amount: amount, price: doubleValue(attrs["price"]), owner: owner))
        }
        return out
    }

    // MARK: - Uniswap liquidity (2026-07-30)

    /// One Uniswap LP position as Zerion aggregates it — already joined across
    /// the legs Zerion reports separately. This is the ENUMERATION and the
    /// MONEY; the range (in/out) is not here and never can be, so
    /// `UniswapLiquidity` reads ticks on-chain and joins on `tokenId`.
    struct LiquidityPosition {
        /// 3 or 4 — off Zerion's own `protocol` string ("Uniswap V3"/"V4").
        /// Uniswap V2 is deliberately excluded: it has no position NFT, hence
        /// no tokenId to join on, and no range to be in or out of.
        let version: Int
        let network: String
        /// The position-manager NFT id, parsed out of Zerion's display name
        /// ("XAGM/USDC Pool 0.3% #1341219"). The join key to the on-chain read.
        let tokenId: Int
        /// Zerion's own pool label, cleaned of the trailing "#<id>".
        let poolName: String
        /// Principal — the sum of every `deposit` leg's USD value.
        let valueUSD: Double
        /// Uncollected fees — the sum of every `reward` leg's USD value.
        /// MEASURED 2026-07-30: for position #1327831 this summed to $47.65,
        /// matching `UniswapLiquidity`'s independent simulated-`collect()`
        /// read TO THE CENT — two unrelated methods agreeing, which is why
        /// this is trusted as the fee number for V4 (where no cheap on-chain
        /// equivalent exists).
        let feesUSD: Double
    }

    /// Every Uniswap V3/V4 LP position Zerion knows for one address, or nil
    /// when Zerion couldn't be reached (an EMPTY array is a real "holds
    /// none"). Rides `filter[positions]=only_complex` — the exact filter
    /// `holdings` above EXCLUDES, which is why LP has never appeared in the
    /// treemap.
    ///
    /// Zerion reports one entry PER TOKEN LEG PER TYPE — a two-sided position
    /// with fees is four rows (deposit×2, reward×2) — so they're folded here
    /// by (network, version, tokenId) into the one position a person owns.
    ///
    /// KNOWN INCOMPLETE, and the reason V3 does NOT enumerate through this:
    /// measured against a wallet holding three real V3 positions, Zerion
    /// returned only two (it omitted a zero-fee, fully out-of-range one).
    /// `UniswapLiquidity` therefore keeps its own complete keyless on-chain
    /// enumeration for V3 and uses this only to ADD value/fees. V4 has no
    /// such option (its PositionManager isn't ERC721Enumerable), so there
    /// this is the enumeration, incompleteness and all — an honest limit,
    /// stated rather than hidden.
    static func liquidityPositions(address: String) async -> [LiquidityPosition]? {
        guard isConfigured,
              let auth = "\(key):".data(using: .utf8)?.base64EncodedString(),
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        // Same EVM-only chain filter `holdings` needs (a `solana` id 400s the
        // whole request), and Uniswap is EVM-only anyway.
        let chains = networkFor.keys.filter { $0 != "solana" }.sorted().joined(separator: ",")
        let query = "filter[positions]=only_complex&currency=usd&filter[chain_ids]=\(chains)"
        let url = "https://api.zerion.io/v1/wallets/\(encoded)/positions/?\(query)"

        guard let root = await IngestSupport.getJSON(url, auth: "Basic \(auth)") as? [String: Any],
              let data = root["data"] as? [[String: Any]] else { return nil }

        // (network, version, tokenId) → accumulating position.
        var folded: [String: (version: Int, network: String, tokenId: Int,
                              name: String, value: Double, fees: Double)] = [:]
        for item in data {
            guard let attrs = item["attributes"] as? [String: Any],
                  let proto = attrs["protocol"] as? String,
                  let version = uniswapVersion(proto),
                  let name = attrs["name"] as? String,
                  let tokenId = trailingTokenID(name),
                  let chainData = ((item["relationships"] as? [String: Any])?["chain"]
                        as? [String: Any])?["data"] as? [String: Any],
                  let zid = chainData["id"] as? String,
                  let network = networkFor[zid]
            else { continue }
            let value = doubleValue(attrs["value"]) ?? 0
            let isReward = (attrs["position_type"] as? String) == "reward"
            let key = "\(network)|\(version)|\(tokenId)"
            var entry = folded[key] ?? (version, network, tokenId,
                                        poolLabel(name), 0, 0)
            if isReward { entry.fees += value } else { entry.value += value }
            folded[key] = entry
        }
        return folded.values.map {
            LiquidityPosition(version: $0.version, network: $0.network, tokenId: $0.tokenId,
                              poolName: $0.name, valueUSD: $0.value, feesUSD: $0.fees)
        }
    }

    /// "Uniswap V3" → 3, "Uniswap V4" → 4, anything else (V2, SushiSwap V3,
    /// PancakeSwap…) → nil. Matched on the exact protocol strings measured
    /// 2026-07-30; a prefix test would wrongly claim "Uniswap V2".
    private static func uniswapVersion(_ protocolName: String) -> Int? {
        switch protocolName {
        case "Uniswap V3": return 3
        case "Uniswap V4": return 4
        default: return nil
        }
    }

    /// The `#1341219` at the end of a Zerion pool name, in either measured
    /// spelling — bare (`"XAGM/USDC Pool 0.3% #1341219"`) or parenthesised
    /// (`"Uniswap V4 ETH/GoGo Pool (#8472)"`). nil for a name carrying none
    /// (Uniswap V2, which has no position NFT).
    private static func trailingTokenID(_ name: String) -> Int? {
        guard let hash = name.lastIndex(of: "#") else { return nil }
        let digits = name[name.index(after: hash)...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// The pool label without its trailing id — "XAGM/USDC Pool 0.3%".
    /// Only a fallback: the card prefers the SYMBOLS read on-chain, since
    /// those are what every other wallet row in the app is spelled from.
    private static func poolLabel(_ name: String) -> String {
        guard let hash = name.lastIndex(of: "#") else { return name }
        var label = String(name[name.startIndex..<hash])
        while let last = label.last, last == " " || last == "(" { label.removeLast() }
        return label.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Activity (2026-07-19)

    /// One fungible-asset leg of a wallet's activity, as Zerion's
    /// `/transactions` hands it over — the neutral shape `WalletIngest` maps
    /// into an Alchemy-`getAssetTransfers`-SHAPED dictionary so every
    /// downstream rule (swap folding, counterparty naming, the spam filter,
    /// dedup) runs UNCHANGED; only the fetch layer differs (mirrors
    /// `collectCandidates`/`Holding` above). Deliberately fungible-ONLY: an
    /// NFT transfer (no `fungible_info`) is skipped here, not mapped — NFT
    /// activity keeps riding Alchemy's dedicated erc721/erc1155 categories
    /// unconditionally (see `WalletIngest.fetch`), since this file has no
    /// measured Zerion NFT-transfer schema to map from and guessing wrong
    /// would silently drop a real NFT receipt rather than degrade gracefully.
    struct Transfer {
        let hash: String
        /// Alchemy network id (mapped through `networkFor`).
        let network: String
        /// `true` when the wallet received this leg — Zerion's "in"/"self"
        /// map to received, "out"/"self" map to sent (a self-transfer counts
        /// as BOTH, matching how querying Alchemy in both directions would
        /// naturally report a from==to transfer).
        let received: Bool
        let symbol: String
        /// nil = native coin, matching `Holding.contract`'s same convention
        /// and passed through just as UNCHANGED.
        let contract: String?
        let amount: Double
        let counterparty: String?   // lowercased hex; the OTHER side of this leg
        let when: Date
        /// Zerion's own classification of the whole TRANSACTION this leg belongs
        /// to (2026-07-21) — already-decoded intent, which is exactly the thing
        /// a raw transfer read can't recover without calldata. The authoritative
        /// set, read back from the API's own validation error on a bogus
        /// `filter[operation_types]`: approve, bid, burn, claim, delegate,
        /// deploy, deposit, execute, mint, receive, revoke, revoke_delegation,
        /// send, trade, withdraw. Note there is no "stake" — staking arrives as
        /// deposit/withdraw. Consumed by `WalletVerbs.operationVerb`; nil when
        /// absent so the caller degrades to its old sentence.
        let operationType: String?
        /// What this leg was worth in USD when it moved — Zerion's own `value`,
        /// which the request has always asked for (`currency=usd`) and this
        /// parser used to discard (2026-08-01, for the flow band). nil when
        /// Zerion couldn't price the token, which is a real and common answer
        /// for a long-tail asset; never defaulted to zero, since "worth
        /// nothing" and "nobody knows" are different facts and the band draws
        /// them differently.
        let valueUSD: Double?
    }

    /// A wallet's recent fungible activity across the EVM chains Casberi
    /// reads, newest first — or nil when Zerion couldn't be reached at all
    /// (the fall-back-to-Alchemy signal; an EMPTY array is a real "nothing
    /// recent"). One request covers every chain and both directions at once
    /// — the replacement for Alchemy's up-to-10-requests-per-wallet fan-out
    /// (5 chains × 2 directions). Solana excluded (see `holdings`' measured
    /// `filter[chain_ids]` quirk); Solana activity is untouched, still riding
    /// `SolanaActivity`'s Alchemy calls (cheap already — 2 requests/wallet).
    static func transactions(address: String) async -> [Transfer]? {
        // THE DEMO REACHES NOTHING (2026-08-12). Gated at the network
        // boundary, not at a caller: holdings are read from `WalletWatch
        // .liveState` — a per-view read the foreground sweep's demo gate
        // cannot see — and the wallet room is the one room a demo opens with.
        // Found by `verify.sh`'s "Demo reaches nothing" step on its FIRST run,
        // after two earlier reaches of this same class had been found only by
        // reading. nil is the honest answer here: every caller already handles
        // an unreached wallet, and the demo's balances come from its own
        // seeded samples.
        if DemoMode.isActive { return nil }
        guard isConfigured,
              let auth = "\(key):".data(using: .utf8)?.base64EncodedString(),
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        let chains = networkFor.keys.filter { $0 != "solana" }.sorted().joined(separator: ",")
        let query = "currency=usd&filter[chain_ids]=\(chains)"
        let url = "https://api.zerion.io/v1/wallets/\(encoded)/transactions/?\(query)"

        guard let root = await IngestSupport.getJSON(url, auth: "Basic \(auth)") as? [String: Any],
              let data = root["data"] as? [[String: Any]] else { return nil }

        var out: [Transfer] = []
        for tx in data {
            guard let attrs = tx["attributes"] as? [String: Any],
                  (attrs["status"] as? String ?? "confirmed") == "confirmed",
                  let hash = attrs["hash"] as? String,
                  let when = IngestSupport.isoDate(attrs["mined_at"])
            else { continue }

            guard let chainId = ((tx["relationships"] as? [String: Any])?["chain"]
                    as? [String: Any])?["data"] as? [String: Any],
                  let zid = chainId["id"] as? String,
                  let network = networkFor[zid] else { continue }

            let operation = (attrs["operation_type"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
            guard let transfers = attrs["transfers"] as? [[String: Any]] else { continue }
            for t in transfers {
                // Fungible-only — an NFT transfer carries no `fungible_info`
                // and is skipped (see the type doc above).
                guard let info = t["fungible_info"] as? [String: Any],
                      let symbol = (info["symbol"] as? String).flatMap({ $0.isEmpty ? nil : $0 }),
                      let quantity = t["quantity"] as? [String: Any],
                      let amount = doubleValue(quantity["float"]), amount > 0,
                      let direction = t["direction"] as? String
                else { continue }
                let contract = implementationAddress(info["implementations"], chainId: zid)
                let sender = (t["sender"] as? String)?.lowercased()
                let recipient = (t["recipient"] as? String)?.lowercased()
                // Through the same finite/positive guard every other number
                // off this API takes — an infinite or negative "value" would
                // otherwise reach the flow band's own scale and flatten every
                // ribbon beside it.
                let value = doubleValue(t["value"]).flatMap { $0 > 0 ? $0 : nil }

                if direction == "in" || direction == "self" {
                    out.append(Transfer(hash: hash, network: network, received: true,
                                        symbol: clean(symbol), contract: contract, amount: amount,
                                        counterparty: sender, when: when, operationType: operation,
                                        valueUSD: value))
                }
                if direction == "out" || direction == "self" {
                    out.append(Transfer(hash: hash, network: network, received: false,
                                        symbol: clean(symbol), contract: contract, amount: amount,
                                        counterparty: recipient, when: when, operationType: operation,
                                        valueUSD: value))
                }
            }
        }
        return out
    }

    // MARK: - Parsing helpers

    /// The implementation address for a given chain id, or nil for the native
    /// coin (no implementation, or one whose address is null/empty). Passed
    /// through UNCHANGED — never case-folded (see `Holding.contract`).
    private static func implementationAddress(_ raw: Any?, chainId: String) -> String? {
        guard let impls = raw as? [[String: Any]] else { return nil }
        for impl in impls where impl["chain_id"] as? String == chainId {
            if let addr = impl["address"] as? String, !addr.isEmpty { return addr }
            return nil   // matched the chain but native (no address)
        }
        return nil
    }

    /// A JSON number tolerant of Double / Int / String encodings, rejecting a
    /// non-finite value (`Double("1e400")` is `.infinity`, not nil) — the same
    /// guard `WalletIngest.firstPrice` and `DefiLlamaPrices.priceValue` keep, so
    /// a poison quantity/price can't reach the treemap's `Int(...)`.
    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double, d.isFinite { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }

    /// Trims a symbol the way `WalletIngest.clean` does at the boundary — one
    /// copy here so this file stays self-contained. A symbol is a short ticker;
    /// newlines and surrounding whitespace are never part of it.
    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if DEBUG
    /// The `-zerionProbe <address>` walk: what Zerion actually returns for one
    /// wallet — reachability, holding count, priced-vs-unpriced, and the first
    /// rows (symbol / network / amount / price) — so its parity with the Alchemy
    /// treemap can be eyeballed in one launch before it's trusted. Reads only.
    static func diagnostic(address: String) async -> [String] {
        guard isConfigured else {
            return ["Zerion probe: NO KEY set (ZerionAPI.key empty) — Alchemy fallback is live"]
        }
        guard let holdings = await holdings(address: address) else {
            return ["Zerion probe: FAILED — unreachable (offline / bad key / bad address)"]
        }
        guard !holdings.isEmpty else {
            return ["Zerion probe: reached, 0 holdings (a real 'holds nothing', not a miss)"]
        }
        let priced = holdings.filter { $0.price != nil }.count
        var out = [String(format: "Zerion probe: %d holding(s), %d priced, %d unpriced",
                          holdings.count, priced, holdings.count - priced)]
        for h in holdings.prefix(15) {
            out.append(String(format: "  %@ [%@] amt=%@ price=%@",
                              h.symbol, h.network,
                              String(format: "%g", h.amount),
                              h.price.map { String(format: "$%.4f", $0) } ?? "—"))
        }
        if holdings.count > 15 { out.append("  … +\(holdings.count - 15) more") }
        return out
    }

    /// The `-zerionActivityProbe <address>` walk: what Zerion's transactions
    /// endpoint returns for one wallet — reachability, leg count, and the
    /// first rows (hash / chain / direction / symbol / amount) — so it can be
    /// eyeballed against the Wallet feed's recent activity before it's
    /// trusted as the EVM-activity source. Reads only.
    static func activityDiagnostic(address: String) async -> [String] {
        guard isConfigured else {
            return ["Zerion activity probe: NO KEY set — Alchemy fallback is live"]
        }
        guard let legs = await transactions(address: address) else {
            return ["Zerion activity probe: FAILED — unreachable (offline / bad key / bad address)"]
        }
        guard !legs.isEmpty else {
            return ["Zerion activity probe: reached, 0 fungible legs (a real 'nothing recent', not a miss)"]
        }
        var out = [String(format: "Zerion activity probe: %d leg(s)", legs.count)]
        for l in legs.prefix(15) {
            out.append(String(format: "  %@ [%@] %@ %@ %@ cp=%@",
                              String(l.hash.prefix(10)), l.network, l.received ? "recv" : "send",
                              String(format: "%g", l.amount), l.symbol, l.counterparty ?? "—"))
        }
        if legs.count > 15 { out.append("  … +\(legs.count - 15) more") }
        return out
    }
    #endif
}
