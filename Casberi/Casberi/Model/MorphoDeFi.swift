import Foundation
import SwiftData

/// Morpho positions (2026-07-21) — a wallet's vault deposits, market
/// collateral/debt, and per-market health factor on Morpho, read from
/// Morpho's own public GraphQL API (`blue-api.morpho.org/graphql` — keyless,
/// measured live 2026-07-21). The Aave shape (`WalletDeFi`), with one
/// structural difference the API forces: Morpho positions are PER MARKET
/// (isolated pairs), not one account-wide number, and unlike Aave they can't
/// be enumerated on-chain without already knowing every market id — which is
/// exactly what the GraphQL API answers in one request. Modeled in THREE
/// parts:
///
/// (1) `book(addresses:)` is LIVE STATE — market positions + vault deposits
///     for every watched wallet across the chains both Morpho and Casberi
///     read, one batched request (`userAddress_in`/`chainId_in`), never
///     landed, never persisted beyond view state.
/// (2) `sync(...)` is a DISCRETE ALERT — lands a thing only when a wallet's
///     worst health factor on a chain crosses INTO risk (below 1.5), the
///     WalletDeFi bucket pattern verbatim, including the paid-for reset:
///     no debt is a definitive "safe", never a stale "at-risk" bucket.
/// (3) `syncActivity(...)` lands SETTLED Morpho events (supply, borrow,
///     repay, vault deposits/withdrawals, liquidations) as things — the
///     PeerBridge cursor shape, timestamp-based because the API filters on
///     `timestamp_gte`. Capture-only by ruling: settled events, never a
///     pending intent, never a path that trades.
///
/// Measured quirks (2026-07-21, don't "fix" without re-measuring): the API
/// answers keyless POSTs with no auth header at all; `state.collateralUsd`
/// can be NULL while `healthFactor` still reads (unpriced collateral — a
/// real position, don't drop it); dust is EVERYWHERE (the burn address holds
/// hundreds of sub-cent vault positions people dusted it with), so the USD
/// floor below is load-bearing, not cosmetic; transaction amounts are raw
/// BigInt (sometimes a JSON number, sometimes a string) scaled by the
/// asset's own `decimals`; and the schema drifts (fields renamed since the
/// docs I first wrote against) — the introspection queries in the session
/// log are how to re-derive it.
enum MorphoDeFi {

    private static let endpoint = "https://blue-api.morpho.org/graphql"

    /// Morpho chain id → the network id the rest of the app keys on. Only
    /// the overlap of Morpho's deployments and Casberi's readable chains —
    /// a Morpho position on Katana/HyperEVM/etc. is skipped, never
    /// mis-mapped (the ZerionAPI.networkFor rule).
    private static let chains: [(id: Int, network: String)] = [
        (1, "eth-mainnet"), (8453, "base-mainnet"), (42161, "arb-mainnet"),
        (10, "opt-mainnet"), (137, "matic-mainnet"),
    ]

    /// Same warning line Aave wears — 1.0 is liquidation itself, 1.5 is the
    /// heads-up margin. One definition for both (`DeFiRisk.floor`, 2026-07-25);
    /// this comment used to point at Aave's private copy, which is the
    /// codebase noticing the duplication without fixing it.
    private static var riskThreshold: Double { DeFiRisk.floor }

    /// Positions below this stay invisible — `WalletIngest.holdingFloor`,
    /// the same line the treemap draws. Without it the measured dust
    /// (sub-cent vault shares people spray at every address) becomes rows.
    private static var floor: Double { WalletIngest.holdingFloor }

    /// Which watched wallets actually hold a Morpho position — the catalog
    /// seat's gate (2026-07-30). See `WalletSeatEvidence` for why a seat is
    /// evidence-gated rather than lit for every watched wallet.
    static let evidence = WalletSeatEvidence("morpho.accounts")

    /// One isolated-market position: collateral posted, debt drawn, and the
    /// market's own health factor. `collateralUSD` is optional because the
    /// API measurably returns null for unpriced collateral while the health
    /// factor still reads — absence of a price, not absence of collateral.
    struct Position: Equatable, Sendable {
        let network: String
        let address: String
        /// "kBTC / RLUSD" for a borrow market, the loan symbol alone when
        /// the market has no collateral asset (idle/supply-only markets).
        let marketLabel: String
        let collateralUSD: Double?
        let supplyUSD: Double
        let borrowUSD: Double
        /// nil = no debt in this market (nothing to liquidate), never 0.
        let healthFactor: Double?
    }

    /// One market slice of a vault's allocation — a collateral symbol and
    /// how much of the vault's assets currently sit against it. `collateral`
    /// is nil for the vault's own idle/loan-only slot (a market with no
    /// collateral asset), grouped under "idle" by `shares(for:)`.
    struct AllocationSlice: Equatable, Sendable {
        let collateral: String?
        let usd: Double
    }

    /// One vault (earn) deposit — no health factor; vaults only lend.
    struct VaultHolding: Equatable, Sendable {
        let network: String
        let address: String
        let vaultName: String
        let assetSymbol: String
        let usd: Double
        /// The vault CONTRACT's own address — distinct from `address` (the
        /// wallet holding the deposit), needed to key the reallocation
        /// snapshot and the rate-comparison bucket per vault.
        let vaultAddress: String
        /// The vault's own total assets (every depositor, not just this
        /// wallet's slice) — the denominator `shares(for:)` divides by, so
        /// "38% of the vault is now in wstETH markets" is a fact about the
        /// vault, not skewed by how much of it is this one wallet's.
        let totalAssetsUsd: Double?
        /// Net APY straight off Morpho's own `state.netApy` — a fraction
        /// (0.04 = 4%), never separately computed here.
        let netApy: Double?
        /// Every market with a non-zero allocation (MEASURED 2026-07-30: a
        /// vault's allocation list includes every market it's CONFIGURED
        /// for, most at $0 supplied — zero entries are dropped at parse
        /// time, not carried as noise).
        let allocation: [AllocationSlice]
    }

    struct Book: Equatable, Sendable {
        var positions: [Position] = []
        var vaults: [VaultHolding] = []
        var isEmpty: Bool { positions.isEmpty && vaults.isEmpty }
    }

    /// Coalesced like `WalletDeFi`'s account read — the refresh arm, the
    /// feed's live state, and the kept ask all want this same read every
    /// foreground pass.
    private static let cache = CoalescingCache<Book>()

    // MARK: - Live state

    /// The whole Morpho book for the given (resolved, hex) addresses across
    /// active chains — or nil when the API couldn't be reached at all (an
    /// EMPTY book is a real "no positions"). One GraphQL request covers
    /// every wallet and chain: both position queries batch on
    /// `userAddress_in` + `chainId_in` (measured 2026-07-21).
    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty else { return Book() }
        let active = Set(WalletChainStore.activeNetworkIDs())
        let ids = chains.filter { active.contains($0.network) }.map(\.id)
        guard !ids.isEmpty else { return Book() }
        let key = addresses.map { $0.lowercased() }.sorted().joined(separator: ",")
            + "|" + ids.map(String.init).joined(separator: ",")
        return await cache.value(key: key, ttl: 60) {
            await fetchBook(addresses: addresses, chainIds: ids)
        }
    }

    private static func fetchBook(addresses: [String], chainIds: [Int]) async -> Book? {
        let users = addresses.map { "\"\($0)\"" }.joined(separator: ",")
        let ids = chainIds.map(String.init).joined(separator: ",")
        let query = """
        { marketPositions(first: 100, where: { userAddress_in: [\(users)], chainId_in: [\(ids)] }) { items { \
        healthFactor user { address } \
        state { collateralUsd supplyAssetsUsd borrowAssetsUsd } \
        market { loanAsset { symbol } collateralAsset { symbol } morphoBlue { chain { id } } } } } \
        vaultPositions(first: 100, where: { userAddress_in: [\(users)], chainId_in: [\(ids)] }) { items { \
        user { address } state { assetsUsd } \
        vault { address name chain { id } asset { symbol } \
        state { totalAssetsUsd netApy allocation { supplyAssetsUsd market { collateralAsset { symbol } } } } } } } }
        """
        guard let data = await graphQL(query) else { return nil }
        var book = Book()

        for item in (data["marketPositions"] as? [String: Any])?["items"]
                as? [[String: Any]] ?? [] {
            guard let owner = ((item["user"] as? [String: Any])?["address"] as? String)?.lowercased(),
                  let market = item["market"] as? [String: Any],
                  let chainId = (((market["morphoBlue"] as? [String: Any])?["chain"]
                        as? [String: Any])?["id"]).flatMap(intValue),
                  let network = chains.first(where: { $0.id == chainId })?.network
            else { continue }
            let state = item["state"] as? [String: Any]
            let collateral = doubleValue(state?["collateralUsd"])
            let supply = doubleValue(state?["supplyAssetsUsd"]) ?? 0
            let borrow = doubleValue(state?["borrowAssetsUsd"]) ?? 0
            let hfRaw = doubleValue(item["healthFactor"])
            // No debt ⇒ no health factor to warn on (the Aave sentinel rule).
            let hf: Double? = borrow > 0 ? hfRaw : nil
            // The dust floor — but a live BORROW below it still shows: debt
            // is the one number too load-bearing to floor away.
            guard borrow > 0 || supply >= floor || (collateral ?? 0) >= floor else { continue }
            let loan = (market["loanAsset"] as? [String: Any])?["symbol"] as? String ?? "?"
            let coll = (market["collateralAsset"] as? [String: Any])?["symbol"] as? String
            book.positions.append(Position(
                network: network, address: owner,
                marketLabel: coll.map { "\($0) / \(loan)" } ?? loan,
                collateralUSD: collateral, supplyUSD: supply, borrowUSD: borrow,
                healthFactor: hf))
        }

        for item in (data["vaultPositions"] as? [String: Any])?["items"]
                as? [[String: Any]] ?? [] {
            guard let owner = ((item["user"] as? [String: Any])?["address"] as? String)?.lowercased(),
                  let vault = item["vault"] as? [String: Any],
                  let chainId = ((vault["chain"] as? [String: Any])?["id"]).flatMap(intValue),
                  let network = chains.first(where: { $0.id == chainId })?.network,
                  let usd = doubleValue((item["state"] as? [String: Any])?["assetsUsd"]),
                  usd >= floor
            else { continue }
            let symbol = (vault["asset"] as? [String: Any])?["symbol"] as? String ?? "?"
            let vaultState = vault["state"] as? [String: Any]
            var allocation: [AllocationSlice] = []
            for slice in vaultState?["allocation"] as? [[String: Any]] ?? [] {
                guard let sliceUsd = doubleValue(slice["supplyAssetsUsd"]), sliceUsd > 0 else { continue }
                let market = slice["market"] as? [String: Any]
                let collateral = (market?["collateralAsset"] as? [String: Any])?["symbol"] as? String
                allocation.append(AllocationSlice(collateral: collateral, usd: sliceUsd))
            }
            book.vaults.append(VaultHolding(
                network: network, address: owner,
                vaultName: vault["name"] as? String ?? symbol,
                assetSymbol: symbol, usd: usd,
                vaultAddress: (vault["address"] as? String)?.lowercased() ?? "",
                totalAssetsUsd: doubleValue(vaultState?["totalAssetsUsd"]),
                netApy: doubleValue(vaultState?["netApy"]),
                allocation: allocation))
        }
        return book
    }

    // MARK: - Risk alert (the WalletDeFi.sync pattern)

    private static func riskKey(_ network: String, _ address: String) -> String {
        "wallet.defi.morpho.risk.\(network).\(address.lowercased())"
    }

    /// Lands a thing only on a NEW crossing into risk of the wallet's WORST
    /// health factor on a chain (Morpho positions are per market; the worst
    /// one is the one that liquidates first). Same fail-closed / definitive-
    /// safe-reset rules WalletDeFi paid for.
    @MainActor
    static func sync(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int {
        guard !addresses.isEmpty else { return 0 }
        guard let book = await book(addresses: addresses) else { return 0 }
        // Every open position's health factor, sampled — the trajectory the
        // Lending row's subtitle reads ("drifting down for 4 days"), keyed
        // PER MARKET (not the aggregated worst-per-chain below), since two
        // isolated positions on the same chain can drift in different
        // directions. Piggybacks on this pass's own `book` read rather than
        // a separate one.
        for position in book.positions {
            guard let hf = position.healthFactor else { continue }
            recordHFSample(network: position.network, address: position.address,
                           marketLabel: position.marketLabel, hf: hf)
        }
        // The catalog seat's evidence mark (2026-07-30) — a wallet holding a
        // real Morpho position or vault deposit is a wallet Morpho is part
        // of, and that is what lights the seat. Read off this pass's own
        // `book`, so it costs nothing extra; never unstamped on an empty
        // book (see `WalletSeatEvidence`'s stamp-never-unstamp rule).
        for address in addresses {
            let a = address.lowercased()
            guard book.positions.contains(where: { $0.address == a })
                    || book.vaults.contains(where: { $0.address == a }) else { continue }
            evidence.remember(a)
        }
        let defaults = UserDefaults.standard
        let active = Set(WalletChainStore.activeNetworkIDs())
        var added = 0
        for (_, network) in chains where active.contains(network) {
            for address in addresses {
                let key = riskKey(network, address)
                let mine = book.positions.filter {
                    $0.network == network && $0.address == address.lowercased()
                }
                let worst = mine.compactMap(\.healthFactor).min()
                guard let hf = worst else {
                    // No debt anywhere on this chain — a definitive safe.
                    defaults.set("safe", forKey: key)
                    continue
                }
                let bucket = hf < riskThreshold ? "at-risk" : "safe"
                let lastBucket = defaults.string(forKey: key)
                defaults.set(bucket, forKey: key)
                guard bucket == "at-risk", lastBucket != "at-risk" else { continue }
                let ref = "wallet:defi:morpho:\(network):\(address.lowercased()):"
                    + String(Int(Date.now.timeIntervalSince1970))
                guard !existing.contains(ref) else { continue }
                let chainName = WalletIngest.displayName(forNetwork: network) ?? network
                let title = String(localized:
                    "Your Morpho position on \(chainName) is close to liquidation — health factor \(WalletIngest.format(hf))")
                let thing = Thing(kind: .transaction, title: title,
                                  content: "https://app.morpho.org/", source: "Wallet",
                                  sourceRef: ref)
                thing.walletAddress = address
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    // MARK: - Health-factor trajectory (2026-07-30)
    //
    // "Health 1.82" is a static fact; what's actually interesting is that it
    // was 2.4 four days ago and has been sliding since — the app noticing a
    // trend before the risk threshold does. A small history, sampled
    // whenever `sync()` runs (which already reads `book`, so this costs
    // nothing extra), throttled and aged the `WalletStore.ValueSample` way.

    private struct HFSample: Codable {
        let at: Date
        let hf: Double
    }

    private static func hfHistoryKey(_ network: String, _ address: String, _ marketLabel: String) -> String {
        "morpho.hf.history.\(network).\(address.lowercased()).\(marketLabel)"
    }

    private static func hfSamples(key: String) -> [HFSample] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let samples = try? JSONDecoder().decode([HFSample].self, from: data)
        else { return [] }
        return samples
    }

    /// At most one sample per 6 hours, capped at 120 (~30 days at that
    /// resolution) — enough to say "drifting down for four days" without a
    /// point for every single refresh.
    private static func recordHFSample(network: String, address: String, marketLabel: String, hf: Double) {
        let key = hfHistoryKey(network, address, marketLabel)
        var samples = hfSamples(key: key)
        if let last = samples.last, Date.now.timeIntervalSince(last.at) < 6 * 3600 { return }
        samples.append(HFSample(at: .now, hf: hf))
        if samples.count > 120 { samples.removeFirst(samples.count - 120) }
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// "drifting down for 4 days" / "recovering for 4 days" / nil when flat
    /// or there isn't a day of history yet — compares the latest sample to
    /// the oldest one at least a full day old, so one volatile pass can't
    /// claim a trend. A >=2% move over that stretch is the threshold;
    /// smaller than that is the ordinary wobble a health factor has anyway.
    /// Public: `WalletFeedTiles`' Lending row reads this for its subtitle.
    static func hfTrend(network: String, address: String, marketLabel: String) -> String? {
        let samples = hfSamples(key: hfHistoryKey(network, address, marketLabel))
        guard let latest = samples.last, latest.hf.isFinite,
              let anchor = samples.first(where: { latest.at.timeIntervalSince($0.at) >= 86_400 }),
              anchor.hf > 0
        else { return nil }
        let days = max(1, Int(latest.at.timeIntervalSince(anchor.at) / 86_400))
        let change = (latest.hf - anchor.hf) / anchor.hf
        if change <= -0.02 {
            return days == 1 ? String(localized: "drifting down for a day")
                              : String(localized: "drifting down for \(days) days")
        } else if change >= 0.02 {
            return days == 1 ? String(localized: "recovering")
                              : String(localized: "recovering for \(days) days")
        }
        return nil
    }

    // MARK: - Vault delight (2026-07-30) — reallocation alert + rate compare
    //
    // Two things a MetaMorpho vault does that no Morpho UI surfaces as news:
    // its curator moves your money between isolated markets continuously,
    // and its own rate can quietly fall behind the pool it forks from. Both
    // read off ONE `book(addresses:)` call — no separate network round.

    private static func chainId(_ network: String) -> Int? { chains.first(where: { $0.network == network })?.id }

    /// Runs both vault-side passes over one shared `book` read: the
    /// reallocation alert (lands a Thing) and the rate-comparison moment (a
    /// toast, never a thing — module doctrine again, a rate isn't a tally).
    @MainActor
    static func syncVaultDelight(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int {
        guard !addresses.isEmpty, let book = await book(addresses: addresses) else { return 0 }
        let added = syncReallocations(context: context, vaults: book.vaults, existing: existing)
        await checkRateComparison(vaults: book.vaults)
        return added
    }

    private static func allocationKey(_ chainId: Int, _ vaultAddress: String) -> String {
        "morpho.allocation.\(chainId).\(vaultAddress.lowercased())"
    }

    /// A vault's allocation shifts CONTINUOUSLY as its curator reallocates —
    /// unlike a risk crossing this isn't binary, so "changed" means one
    /// collateral's SHARE of the vault moved by at least this many
    /// percentage points since the last-seen snapshot. Below this, ordinary
    /// week-to-week curator rebalancing would fire constantly and the alert
    /// would stop meaning anything.
    private static let allocationShiftFloor = 0.15

    /// Collateral symbol (or "idle" for the vault's own loan-only slot) →
    /// share of the vault's TOTAL assets, 0...1. Markets sharing a
    /// collateral symbol are summed (a vault can hold the same collateral
    /// across more than one isolated market, e.g. two different LLTV
    /// tiers) — what this app cares about is "how much of the vault is
    /// against this asset", not which specific market carries it.
    private static func shares(for vault: VaultHolding) -> [String: Double] {
        guard let total = vault.totalAssetsUsd, total > 0 else { return [:] }
        var totals: [String: Double] = [:]
        for slice in vault.allocation {
            totals[slice.collateral ?? "idle", default: 0] += slice.usd
        }
        return totals.mapValues { $0 / total }
    }

    /// Lands a thing when a held vault's collateral mix has shifted
    /// materially since the last time this ran — the thing the curator did
    /// with your money that no Morpho UI surfaces as news. First sight of a
    /// vault seeds its snapshot silently (there's no "before" to compare
    /// against yet, the same doctrine every other alert here follows).
    @MainActor
    private static func syncReallocations(context: ModelContext, vaults: [VaultHolding],
                                          existing: Set<String>) -> Int {
        let defaults = UserDefaults.standard
        var added = 0
        for vault in vaults {
            guard vault.usd > 0, !vault.vaultAddress.isEmpty,
                  let cid = chainId(vault.network)
            else { continue }
            let shares = shares(for: vault)
            guard !shares.isEmpty else { continue }
            let key = allocationKey(cid, vault.vaultAddress)
            guard let data = defaults.data(forKey: key),
                  let last = try? JSONDecoder().decode([String: Double].self, from: data)
            else {
                save(shares, forKey: key)
                continue
            }
            save(shares, forKey: key)
            // The biggest single mover, named — a dump of every market that
            // moved a little is noise; the one that moved the most is the
            // fact worth a heads-up.
            let allLabels = Set(shares.keys).union(last.keys)
            guard let biggest = allLabels
                .map({ ($0, (shares[$0] ?? 0) - (last[$0] ?? 0)) })
                .max(by: { abs($0.1) < abs($1.1) }),
                abs(biggest.1) >= allocationShiftFloor
            else { continue }
            let ref = "wallet:defi:morpho:realloc:\(cid):\(vault.vaultAddress):"
                + String(Int(Date.now.timeIntervalSince1970))
            guard !existing.contains(ref) else { continue }
            let (label, delta) = biggest
            let nowPct = Int(((shares[label] ?? 0) * 100).rounded())
            let title = delta > 0
                ? String(localized: "Your \(vault.vaultName) vault moved into \(label) markets — now \(nowPct)% of the vault")
                : String(localized: "Your \(vault.vaultName) vault moved out of \(label) markets — now \(nowPct)% of the vault")
            let thing = Thing(kind: .transaction, title: title,
                              content: "https://app.morpho.org/", source: "Wallet",
                              sourceRef: ref)
            thing.walletAddress = vault.address
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    private static func save(_ shares: [String: Double], forKey key: String) {
        guard let data = try? JSONEncoder().encode(shares) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func rateAheadKey(_ chainId: Int, _ vaultAddress: String) -> String {
        "morpho.rateahead.\(chainId).\(vaultAddress.lowercased())"
    }

    /// A meaningful gap, in percentage points — under this, Aave and a
    /// vault's own rate wobble past each other constantly and a moment
    /// would fire every week for nothing.
    private static let rateGapFloor = 0.01

    /// A one-time toast (`SourceMoments`) the moment a held vault's own rate
    /// falls meaningfully behind Aave Core's for the same asset — never a
    /// persistent line on the card (a rate isn't a tally), and never
    /// repeated for the same vault while the gap holds (a bucket, the same
    /// shape as the liquidation-risk bucket, so it can re-fire if the gap
    /// closes and reopens later). A vault BEATING Aave never fires — this
    /// is specifically the "you're leaving yield on the table" nudge, not a
    /// running commentary on every rate wobble. First sight seeds silently.
    @MainActor
    private static func checkRateComparison(vaults: [VaultHolding]) async {
        let defaults = UserDefaults.standard
        for vault in vaults {
            guard vault.usd > 0, let vaultApy = vault.netApy,
                  let cid = chainId(vault.network), !vault.vaultAddress.isEmpty,
                  let aaveApy = await AaveRates.coreApy(network: vault.network, symbol: vault.assetSymbol)
            else { continue }
            let key = rateAheadKey(cid, vault.vaultAddress)
            let gap = aaveApy - vaultApy
            let ahead = gap >= rateGapFloor
            let hadPriorReading = defaults.object(forKey: key) != nil
            let wasAhead = defaults.bool(forKey: key)
            defaults.set(ahead, forKey: key)
            guard hadPriorReading, ahead, !wasAhead else { continue }
            let points = Int((gap * 100).rounded())
            guard points > 0 else { continue }
            SourceMoments.shared.fire(
                String(localized: "Aave pays about \(points) point more on \(vault.assetSymbol) than your \(vault.vaultName) vault"),
                source: "Wallet")
        }
    }

    // MARK: - Activity (the PeerBridge cursor shape, timestamps not blocks)

    /// Two passes racing (the probe beside a foreground refresh) could each
    /// read the same cursor and double-land — one runs, the other returns 0.
    @MainActor private static var running = false

    private static func cursorKey(_ address: String) -> String {
        "morpho.cursor.\(address.lowercased())"
    }

    /// Wallet unwatch takes this seat's per-address state with it (the Peer
    /// rule): the activity cursor (a stale one would back-fill the unwatched
    /// gap on re-watch) AND the risk buckets (a stale "at-risk" bucket would
    /// silently suppress a real alert on re-watch).
    static func clearState(address: String) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: cursorKey(address))
        for (_, network) in chains {
            defaults.removeObject(forKey: riskKey(network, address))
        }
        // …and the catalog seat's mark, or the seat stays lit for a wallet
        // that's gone (`WalletSeatEvidence` rule 2).
        evidence.forget(address)
    }

    /// Newest events landed per wallet per pass — a long gap folds to its
    /// recent tail (the Peer cap's rationale).
    private static let maxLanded = 12

    /// Overlap re-scanned each pass so API indexing lag can't lose an event
    /// on the boundary — dedupe on sourceRef makes the overlap free.
    private static let overlap = 300

    /// Lands settled Morpho events for the given (resolved, hex) addresses.
    /// First sight of a wallet seeds the cursor silently (history before the
    /// watch isn't ours to dump; the probe's rewind is the deliberate door).
    /// Returns landed count, nil when the API was unreachable for every
    /// wallet that had a cursor to advance.
    @MainActor
    static func syncActivity(context: ModelContext, addresses: [String],
                             existing: Set<String>) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncActivityLocked(context: context, addresses: addresses,
                                        existing: existing)
    }

    @MainActor
    private static func syncActivityLocked(context: ModelContext, addresses: [String],
                                           existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        let active = Set(WalletChainStore.activeNetworkIDs())
        let ids = chains.filter { active.contains($0.network) }.map(\.id)
        guard !ids.isEmpty else { return 0 }
        let defaults = UserDefaults.standard
        let now = Int(Date.now.timeIntervalSince1970)
        var added = 0
        var reachedAny = false
        var seededOnly = true

        for address in addresses {
            guard let cursor = defaults.object(forKey: cursorKey(address)) as? Int else {
                defaults.set(now, forKey: cursorKey(address))
                continue
            }
            seededOnly = false
            let since = max(0, cursor - overlap)
            guard let events = await fetchEvents(address: address, chainIds: ids,
                                                 since: since) else { continue }
            reachedAny = true
            var landed: [Thing] = []
            for event in events.suffix(maxLanded) {
                guard !existing.contains(event.ref),
                      !landed.contains(where: { $0.sourceRef == event.ref }) else { continue }
                let thing = Thing(kind: .transaction, title: event.title,
                                  content: event.link, source: "Wallet",
                                  sourceRef: event.ref)
                thing.walletAddress = address
                landed.append(thing)
            }
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                // Land and SAVE before advancing the cursor — a cursor that
                // runs ahead of durability turns an app kill into
                // permanently lost events (the WalletApprovals lesson).
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            defaults.set(max(cursor, events.last?.timestamp ?? now, now), forKey: cursorKey(address))
        }
        return (reachedAny || seededOnly) ? added : nil
    }

    private struct Event {
        let ref: String
        let title: String
        let link: String
        let timestamp: Int
    }

    /// Both event streams (market + vault) for one wallet since a timestamp,
    /// oldest first — one GraphQL request. nil = unreachable. Schema
    /// asymmetry, measured 2026-07-21: market transactions order by
    /// `Timestamp`, vault transactions by `Time` — same field, two enum
    /// names; the API 400s the whole document if either is wrong.
    private static func fetchEvents(address: String, chainIds: [Int],
                                    since: Int) async -> [Event]? {
        let ids = chainIds.map(String.init).joined(separator: ",")
        let query = """
        { marketTransactions(first: 50, orderBy: Timestamp, orderDirection: Desc, \
        where: { userAddress_in: ["\(address)"], chainId_in: [\(ids)], timestamp_gte: \(since) }) { items { \
        txHash timestamp type logIndex chain { id } \
        market { loanAsset { symbol decimals } collateralAsset { symbol decimals } } \
        data { __typename \
        ... on MarketTransactionTransferData { assets } \
        ... on MarketTransactionCollateralTransferData { assets } \
        ... on MarketTransactionLiquidationData { repaidAssets seizedAssets } } } } \
        vaultV1Transactions(first: 50, orderBy: Time, orderDirection: Desc, \
        where: { userAddress_in: ["\(address)"], chainId_in: [\(ids)], timestamp_gte: \(since), type_in: [Deposit, Withdraw] }) { items { \
        txHash timestamp type logIndex assets chain { id } \
        vault { name asset { symbol decimals } } } } }
        """
        guard let data = await graphQL(query) else { return nil }
        var out: [Event] = []

        for item in (data["marketTransactions"] as? [String: Any])?["items"]
                as? [[String: Any]] ?? [] {
            guard let event = marketEvent(item) else { continue }
            out.append(event)
        }
        for item in (data["vaultV1Transactions"] as? [String: Any])?["items"]
                as? [[String: Any]] ?? [] {
            guard let event = vaultEvent(item) else { continue }
            out.append(event)
        }
        return out.sorted { $0.timestamp < $1.timestamp }
    }

    private static func marketEvent(_ item: [String: Any]) -> Event? {
        guard let hash = item["txHash"] as? String,
              let ts = intValue(item["timestamp"]),
              let type = item["type"] as? String,
              let chainId = ((item["chain"] as? [String: Any])?["id"]).flatMap(intValue),
              let network = chains.first(where: { $0.id == chainId })?.network,
              let market = item["market"] as? [String: Any]
        else { return nil }
        let logIndex = intValue(item["logIndex"]) ?? 0
        let data = item["data"] as? [String: Any]
        let loan = asset(market["loanAsset"])
        let collateral = asset(market["collateralAsset"])

        let title: String?
        switch type {
        case "Supply":
            title = amount(data?["assets"], loan).map { String(localized: "Lent \($0) on Morpho") }
        case "Withdraw":
            title = amount(data?["assets"], loan).map { String(localized: "Withdrew \($0) from Morpho") }
        case "Borrow":
            title = amount(data?["assets"], loan).map { amt in
                collateral.map { c in String(localized: "Borrowed \(amt) on Morpho against \(c.symbol)") }
                    ?? String(localized: "Borrowed \(amt) on Morpho")
            }
        case "Repay":
            title = amount(data?["assets"], loan).map { String(localized: "Repaid \($0) on Morpho") }
        case "SupplyCollateral":
            title = amount(data?["assets"], collateral).map { String(localized: "Added \($0) collateral on Morpho") }
        case "WithdrawCollateral":
            title = amount(data?["assets"], collateral).map { String(localized: "Withdrew \($0) collateral on Morpho") }
        case "Liquidation":
            title = amount(data?["seizedAssets"], collateral).map { String(localized: "Liquidated on Morpho — \($0) seized") }
        default:
            title = nil
        }
        guard let title else { return nil }
        return Event(ref: "morpho:tx:\(chainId):\(hash.lowercased()):\(type):\(logIndex)",
                     title: title,
                     link: link(network: network, hash: hash),
                     timestamp: ts)
    }

    private static func vaultEvent(_ item: [String: Any]) -> Event? {
        guard let hash = item["txHash"] as? String,
              let ts = intValue(item["timestamp"]),
              let type = item["type"] as? String,
              let chainId = ((item["chain"] as? [String: Any])?["id"]).flatMap(intValue),
              let network = chains.first(where: { $0.id == chainId })?.network,
              let vault = item["vault"] as? [String: Any]
        else { return nil }
        let logIndex = intValue(item["logIndex"]) ?? 0
        let vaultAsset = asset(vault["asset"])
        let name = vault["name"] as? String ?? vaultAsset?.symbol ?? "a vault"
        let title: String?
        switch type {
        case "Deposit":
            title = amount(item["assets"], vaultAsset).map { String(localized: "Deposited \($0) into \(name) on Morpho") }
        case "Withdraw":
            title = amount(item["assets"], vaultAsset).map { String(localized: "Withdrew \($0) from \(name) on Morpho") }
        default:
            title = nil
        }
        guard let title else { return nil }
        return Event(ref: "morpho:tx:\(chainId):\(hash.lowercased()):Vault\(type):\(logIndex)",
                     title: title,
                     link: link(network: network, hash: hash),
                     timestamp: ts)
    }

    // MARK: - Parsing helpers

    private struct AssetInfo { let symbol: String; let decimals: Int }

    private static func asset(_ raw: Any?) -> AssetInfo? {
        guard let dict = raw as? [String: Any],
              let symbol = dict["symbol"] as? String else { return nil }
        return AssetInfo(symbol: symbol, decimals: intValue(dict["decimals"]) ?? 18)
    }

    /// "1,204.5 RLUSD" — a raw BigInt amount scaled by the asset's decimals.
    /// nil when either half is missing: a title must never claim an amount
    /// it didn't read (honesty rule), so the event is skipped instead.
    private static func amount(_ raw: Any?, _ asset: AssetInfo?) -> String? {
        guard let asset, let value = doubleValue(raw), value > 0 else { return nil }
        let scaled = value / pow(10, Double(asset.decimals))
        guard scaled.isFinite, scaled > 0 else { return nil }
        return "\(WalletIngest.format(scaled)) \(asset.symbol)"
    }

    private static func link(network: String, hash: String) -> String {
        WalletIngest.explorerURL(forNetwork: network).map { $0 + hash }
            ?? "https://app.morpho.org/"
    }

    /// One keyless POST; nil on transport failure, non-200, or a GraphQL
    /// error body (data null) — every caller treats nil as "unreachable,
    /// retry next pass", never as an empty result.
    private static func graphQL(_ query: String) async -> [String: Any]? {
        guard let root = await IngestSupport.postJSON(endpoint, body: ["query": query])
                as? [String: Any] else { return nil }
        return root["data"] as? [String: Any]
    }

    /// Tolerant of Double / Int / String encodings, rejecting non-finite
    /// values — the ZerionAPI.doubleValue guard, same rationale.
    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double, d.isFinite { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double, d.isFinite { return Int(d) }
        if let s = raw as? String { return Int(s) ?? Double(s).flatMap { Int($0) } }
        return nil
    }

    #if DEBUG
    /// `-morphoProbe <daysBack|YES>` — NSLogs every watched wallet's Morpho
    /// book (market positions with health factors, vault deposits) or the
    /// honest miss. A numeric spec ALSO rewinds every activity cursor that
    /// many DAYS (timestamps, not blocks — the API filters on time) and runs
    /// the activity sweep, so real past events land and the whole path
    /// (fetch → titles → things) verifies headlessly. Pairs with
    /// `-walletAddress`.
    @MainActor
    static func probe(context: ModelContext, daysBack: Int?) async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        var lines: [String] = []
        if let book = await book(addresses: addresses) {
            if book.isEmpty {
                lines.append("no Morpho positions (a real empty book, not a miss)")
            }
            for p in book.positions {
                let chainName = WalletIngest.displayName(forNetwork: p.network) ?? p.network
                let hfLine = p.healthFactor.map { "hf=\(WalletIngest.format($0))" } ?? "no debt"
                let collLine = p.collateralUSD.map { "$\(WalletIngest.format($0))" } ?? "unpriced"
                let trendLine = hfTrend(network: p.network, address: p.address, marketLabel: p.marketLabel)
                    .map { " trend=\($0)" } ?? ""
                lines.append("\(WalletStore.shortAddress(p.address)) \(chainName) \(p.marketLabel): collateral=\(collLine) supply=$\(WalletIngest.format(p.supplyUSD)) debt=$\(WalletIngest.format(p.borrowUSD)) \(hfLine)\(trendLine)")
            }
            for v in book.vaults {
                let chainName = WalletIngest.displayName(forNetwork: v.network) ?? v.network
                let apyLine = v.netApy.map { "apy=\(WalletIngest.format($0 * 100))%" } ?? "apy=?"
                let shareLine = shares(for: v).sorted { $0.value > $1.value }
                    .map { "\($0.key)=\(Int(($0.value * 100).rounded()))%" }.joined(separator: ",")
                lines.append("\(WalletStore.shortAddress(v.address)) \(chainName) vault \(v.vaultName): $\(WalletIngest.format(v.usd)) \(apyLine) allocation=[\(shareLine)]")
            }
        } else {
            lines.append("book UNREACHABLE")
        }
        if let back = daysBack {
            for _ in 0..<60 where running {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if running {
                lines.append("activity: BUSY")
            } else {
                running = true
                defer { running = false }
                let now = Int(Date.now.timeIntervalSince1970)
                for address in addresses {
                    UserDefaults.standard.set(now - back * 86_400,
                                              forKey: cursorKey(address))
                }
                let landed = await syncActivityLocked(
                    context: context, addresses: addresses,
                    existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
                lines.append("activity: \(landed.map { "\($0) landed" } ?? "UNREACHABLE")")
            }
        }
        return lines.joined(separator: " | ")
    }

    /// `-morphoDelightProbe YES` — seeds a DELIBERATELY DIFFERENT fake
    /// "last seen" allocation snapshot for the first held vault with a live
    /// allocation (its real current shares, with the single biggest slice
    /// zeroed out and folded into "idle"), so the reallocation alert has
    /// something real to diff against without waiting days for a curator to
    /// actually move funds — then runs `syncVaultDelight` once and reports
    /// what landed. The rate-comparison moment can't be forced the same way
    /// (it depends on live Aave data this probe doesn't control), so this
    /// only PROVES the reallocation half deterministically; a fired rate
    /// moment shows up as a bonus, not an expectation.
    @MainActor
    static func probeDelight(context: ModelContext) async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        guard let book = await book(addresses: addresses),
              let vault = book.vaults.first(where: { !$0.allocation.isEmpty })
        else { return "no vault with a live allocation to probe" }
        guard let cid = chainId(vault.network) else { return "vault on an unmapped chain" }
        var fakeLast = shares(for: vault)
        if let biggest = fakeLast.max(by: { $0.value < $1.value }) {
            fakeLast[biggest.key] = 0
            fakeLast["idle", default: 0] += biggest.value
        }
        save(fakeLast, forKey: allocationKey(cid, vault.vaultAddress))
        let existing = IngestSupport.existingSourceRefs(context, source: "Wallet")
        let landed = await syncVaultDelight(context: context, addresses: addresses, existing: existing)
        let moments = SourceMoments.shared.drain().map(\.text)
        return "\(vault.vaultName): fakeLast=\(fakeLast) landed=\(landed) moments=\(moments)"
    }
    #endif
}
