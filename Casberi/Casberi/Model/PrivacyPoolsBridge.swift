import Foundation
import SwiftData

/// Privacy Pools (0xBow) — compliant onchain privacy whose seat RIDES the
/// watched wallets (2026-07-21, prd §162; the Peer shape: no account, no key,
/// no OAuth — depositing happens from the person's own wallet, so connecting
/// is one switch over the already-watched addresses). Two reads:
///
///  1. DEPOSITS — a deposit into any Privacy Pool lands as a thing ("Put
///     0.07 ETH into Privacy Pools"), read off Ethereum's public chain. All
///     14 mainnet pools emit through ONE Entrypoint whose `Deposited` event
///     indexes the depositor, so one filtered `eth_getLogs` per wallet per
///     pass answers "did this wallet deposit", server-side, tiny.
///  2. ASP STATUS — the differentiated read. A deposit sits in review until
///     0xBow's Association Set Provider approves it (only then can it be
///     withdrawn with the compliant proof); people otherwise poll a website
///     for that flip. Casberi polls 0xBow's public ASP API and lands a thing
///     the moment a watched pending deposit clears ("ready to withdraw
///     privately") or is declined.
///
/// Three more reads round out the lifecycle (prd §228), all still capture-only:
///  3. RAGEQUIT — the exit, landed as "Reclaimed X from Privacy Pools". A
///     normal withdrawal is unlinkable by design (fresh address) so we never
///     see it; a ragequit returns to the ORIGINAL depositor, indexed, so it's
///     honestly ours to close the loop on.
///  4. POI_REQUIRED — the one status the person must act on. When a watched
///     deposit flips into proof-of-innocence-required, alert once ("open 0xBow
///     to respond"), then keep watching for its eventual clear/decline.
///  5. ANONYMITY-SET COVER — each deposit carries, on `enrichedText`, how many
///     accepted deposits share its pool: the honest measure of how strong its
///     privacy is. Context, never a tally-thing (module doctrine).
///
/// Honesty boundaries, by ruling (prd §162):
/// - CAPTURE ONLY. Nothing here deposits, withdraws, proves, or signs — the
///   same line as Peer's "lands settled fills, never a path that trades".
/// - The WITHDRAWAL leg is unlinkable BY DESIGN (that's the product): the
///   chain can't tie a withdrawal to its deposit, so Casberi never sees or
///   claims to see that side. Copy never pretends otherwise.
/// - Alerts are NEWS: only a transition observed while watching lands one. A
///   backfilled deposit that was already approved months ago lands as the
///   deposit alone — no stale "cleared!" theater.
///
/// MEASURED (2026-07-22, all live — don't "fix" without re-measuring):
/// - `rpc.mevblocker.io` served the depositor-filtered Entrypoint read over
///   the FULL history (deploy block 22153707 → head, ~3.4M blocks) in 0.33s;
///   `publicnode` now token-walls eth_getLogs entirely, `drpc` caps at 10k
///   blocks — hence this host order, not WalletApprovals' exact pair.
/// - The ASP API (`api.0xbow.io`) is fully keyless: `/{chainId}/public/…`
///   routes 200 bare, CORS `*`, no key/JWT anywhere in the read path, no 429
///   across a 12-request burst. Pool selection rides the `X-Pool-Scope`
///   header (a decimal uint256 per pool, from 0xBow's own chainData.ts);
///   labels batch comma-joined in `X-Labels`. Labels/roots are DECIMAL
///   strings, timestamps epoch MILLISECONDS.
/// - `reviewStatus` enum: pending | approved | declined | exited | spent |
///   poi_required (0xBow's src/types/events.ts). exited/spent are terminal
///   non-news (the person acted elsewhere); poi_required polls on like
///   pending but never alerts (unmeasured live — re-measure before inventing
///   UX for it).
/// - A real deposit round-tripped end-to-end: block 25581320's 0.07 ETH
///   deposit decoded off both events and came back from deposits-by-label
///   with matching label/txHash/amount and `reviewStatus: approved`.
///
/// V2 (deployed 2026-09-01, read here since 2026-10-21) is a SECOND protocol
/// beside v1, not a migration: v1's pools still hold money and can still be
/// reclaimed from, so both are read, each from its own cursor. MEASURED
/// 2026-10-21 against mainnet and `api-v2.0xbow.io`:
/// - A plain deposit indexes the depositor on the v2 Entrypoint
///   (`Deposited(asset indexed, depositor indexed, amount, fee)`); a YIELD
///   deposit (ppUSDC/ppETH/ppUSDT, ~87% of v2's first 167 deposits) goes
///   through a per-share PPRouter whose own `Deposited` indexes the person
///   FIRST — the Entrypoint sees the router as the depositor. Two reads.
/// - The LABEL is encrypted to the ASP at deposit (`LabelRegistered(bytes)`
///   is ciphertext), so v2 keys a deposit by its COMMITMENT — the PoolVault
///   `Deposited`'s first word, which is also the second word of the
///   `Ragequit` that undoes it (all nine live ragequits matched).
/// - Review status is keyless: `/1/public/events` under an `X-Asset` header
///   (the SHARE token for a yield deposit), pages from 1, newest first, each
///   deposit carrying `txHash` and `reviewStatus` — joined by transaction.
///   `deposits-by-label` answers `[]` for every v2 deposit tried.
/// - Status values are v1's minus the terminal pair: pending | approved |
///   declined | poi_required (0xBow's website-v2 `services/api-types.ts`).
/// - v2 has no `pools-stats`; its per-asset `acceptedDepositsCount` is at
///   `/1/public/assets-stats` and is NOT read yet, so a v2 deposit lands
///   without a cover line rather than with v1's figure.
/// - Mainnet only, like v1: BNB Chain and Citrea run the same addresses and
///   wait until someone here deposits there.
enum PrivacyPoolsBridge {

    /// Mainnet only for now — Optimism/Arbitrum share a different Entrypoint
    /// (0x44192215…d15E) and Base is delisted in 0xBow's own config; add L2s
    /// only after measuring their hosts the way mainnet was.
    private static let rpcs = ["https://rpc.mevblocker.io",
                               "https://gateway.tenderly.co/public/mainnet"]
    private static let maxRange = 900_000
    private static let maxChunks = 16

    /// The one Entrypoint every mainnet pool deposits through.
    static let entrypoint = "0x6818809eefce719e480a7526d76bd3e561526b46"
    /// The ETH pool's deploy block — the earliest any Privacy Pool existed,
    /// so the honest floor for the connect-time backfill.
    private static let deployBlock = 22_153_707

    /// Entrypoint `Deposited(address indexed _depositor, IPrivacyPool indexed
    /// _pool, uint256 _commitment, uint256 _amount)`.
    private static let depositedTopic =
        "0xf5681f9d0db1b911ac18ee83d515a1cf1051853a9eae418316a2fdf7dea427c5"
    /// Pool-level `Deposited(address indexed _depositor, uint256 _commitment,
    /// uint256 _label, uint256 _value, uint256 _precommitmentHash)` — the
    /// read that carries the LABEL the ASP is keyed by.
    private static let poolDepositedTopic =
        "0xe3b53cd1a44fbf11535e145d80b8ef1ed6d57a73bf5daa7e939b6b01657d6549"
    /// Pool-level `Ragequit(address indexed _ragequitter, uint256 _commitment,
    /// uint256 _label, uint256 _value)` — the EXIT that's linkable to the
    /// watched wallet (prd §228). A normal withdrawal lands at a fresh,
    /// unlinkable address by design, so Casberi never sees it; a ragequit —
    /// the escape hatch after a decline, or a depositor pulling out — returns
    /// to the ORIGINAL depositor, indexed here, so it's honestly ours to land.
    /// topic0 keccak-derived and validated against the two Deposited topics
    /// above (same method, both matched); a real ragequit is rare, so this is
    /// spec-derived pending a live one, like the deposit path was measured but
    /// the exit wasn't. Emitted on the POOL contracts, not the Entrypoint.
    private static let ragequitTopic =
        "0xd2b3e868ae101106371f2bd93abc8d5a4de488b9fe47ed122c23625aa7172f13"

    /// Every pool address, for the ragequit `eth_getLogs` (one call, address
    /// array) and the same server-side depositor-topic filter deposits use.
    private static var poolAddresses: [String] { Array(pools.keys) }

    private static let aspBase = "https://api.0xbow.io/1/public"

    /// Where each version's deposits are managed — the door a status row
    /// opens. `app.0xbow.io` stopped resolving by 2026-10-21; v1 lives at the
    /// project's own domain now and v2 at its subdomain.
    static let v1AppURL = "https://privacypools.com"
    static let v2AppURL = "https://v2.privacypools.com"

    // MARK: - V2 (same addresses on every v2 chain; mainnet read only)

    static let v2Entrypoint = "0xca1e072236d231130059eea6bfceb7f4e9a1f0c3"
    static let v2PoolVault = "0x0eb42804bf897662af851370eaeadcdbec1b97ed"
    /// PoolVault's `Initialized` block — nothing v2 exists before it.
    private static let v2DeployBlock = 25_884_277
    private static let v2ASPBase = "https://api-v2.0xbow.io/1/public"

    /// Entrypoint `Deposited(address indexed asset, address indexed depositor,
    /// uint256 amount, uint256 fee)`. Same topic0 as v1's Entrypoint (same
    /// shape), different contract — the address keeps the reads apart.
    private static let v2DepositedTopic = depositedTopic
    /// PPRouter `Deposited(address indexed depositor, address indexed share,
    /// uint256 shares, uint256 underlyingIn, uint256 sharesOut)`.
    private static let v2RouterDepositedTopic =
        "0x8bab6aed5a508937051a144e61d6e61336834a66aaee250a00613ae6f744c422"
    /// PoolVault `Deposited(uint256 commitment, address indexed asset,
    /// uint256 value, address indexed entrypoint)` — the commitment.
    private static let v2PoolDepositedTopic =
        "0xed45e0df2bf0e287a792a7b79b19292af5cbab76cc8819049bf37aa067bf8501"
    /// PoolVault `Ragequit(address indexed ragequitter, address indexed asset,
    /// uint256 value, uint256 commitment, uint256 nullifierHash, uint256 label)`.
    private static let v2RagequitTopic =
        "0x507455b25c1a4595720da5b6a8f6b76e4aa36db987a63b47266112d3cbf2e103"

    struct V2Asset {
        let symbol: String
        let decimals: Int
    }

    /// What a v2 pool holds, keyed by lowercased asset address — the
    /// Entrypoint's topics[1], the Ragequit's topics[2] and the ASP's
    /// `X-Asset`. The yield shares are 18-decimal ERC-4626 wrappers over Aave
    /// (read off each contract, 2026-10-21). An asset missing here still
    /// lands and still polls; it is titled "crypto" and carries no figure.
    static let v2Assets: [String: V2Asset] = [
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee": V2Asset(symbol: "ETH", decimals: 18),
        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": V2Asset(symbol: "USDC", decimals: 6),
        "0xc246afb23482ff9596e9cee5f1f678efe0eb1ad6": V2Asset(symbol: "ppUSDC", decimals: 18),
        "0x66051920d25af4e3596a8a46309f4d045f9d83b7": V2Asset(symbol: "ppETH", decimals: 18),
        "0xa4cf419558ef36cc6ffb666195684dc963910426": V2Asset(symbol: "ppUSDT", decimals: 18),
    ]

    struct V2Router {
        /// The share token the router deposits — the asset the ASP files it under.
        let share: String
        /// What the person paid in, which is what the row states.
        let underlying: V2Asset
    }

    /// The three mainnet PPRouters (one per yield share, from the Entrypoint's
    /// own deposit log), keyed by lowercased router address. Each one's
    /// `UNDERLYING()` was read live; ppETH's router runs in native mode, so
    /// what goes in is ETH. A router the factory adds later is not read until
    /// it is listed here.
    static let v2Routers: [String: V2Router] = [
        "0xe76e793d776c1e207ad7a7fa7c57d27420d85110": V2Router(
            share: "0xc246afb23482ff9596e9cee5f1f678efe0eb1ad6",
            underlying: V2Asset(symbol: "USDC", decimals: 6)),
        "0x77613d670bb9fd48a9898d0eac8ebf21b566f960": V2Router(
            share: "0x66051920d25af4e3596a8a46309f4d045f9d83b7",
            underlying: V2Asset(symbol: "ETH", decimals: 18)),
        "0x13a0b86bac3e0c29bd64fed7bcd2ee84f371f41c": V2Router(
            share: "0xa4cf419558ef36cc6ffb666195684dc963910426",
            underlying: V2Asset(symbol: "USDT", decimals: 6)),
    ]

    struct Pool {
        let symbol: String
        let decimals: Int
        /// The ASP's pool key (`X-Pool-Scope`) — a decimal uint256 from
        /// 0xBow's chainData.ts, verified live against the ETH pool.
        let scope: String
    }

    /// All 14 mainnet pools (0xBow chainData.ts, fetched 2026-07-22), keyed
    /// by lowercased pool address (the Entrypoint event's topics[2]). A pool
    /// added after this table still lands its deposit — titled "crypto",
    /// with no status polling (no scope to ask with) — honest, never a guess.
    static let pools: [String: Pool] = [
        "0xf241d57c6debae225c0f2e6ea1529373c9a9c9fb": Pool(symbol: "ETH", decimals: 18,
            scope: "4916574638117198869413701114161172350986437430914933850166949084132905299523"),
        "0x05e4dbd71b56861eed2aaa12d00a797f04b5d3c0": Pool(symbol: "USDS", decimals: 18,
            scope: "10083421949316970946867916491567109470259179563818386567305777802830033294482"),
        "0xbbda2173cdfea1c3bd7f2908798f1265301d750c": Pool(symbol: "sUSDS", decimals: 18,
            scope: "2712591485699559808625639968151776585195565171751537345918418329806863214557"),
        "0x1c31c03b8cb2ee674d0f11de77135536db828257": Pool(symbol: "DAI", decimals: 18,
            scope: "15036211945525489305347805074288289358577232744970551616130812771908439733411"),
        "0xe859c0bd25f260baee534fb52e307d3b64d24572": Pool(symbol: "USDT", decimals: 6,
            scope: "15021418340692283880916004685565940332387258944710606800522765380598358159605"),
        "0xb419c2867ab3cbc78921660cb95150d95a94ce86": Pool(symbol: "USDC", decimals: 6,
            scope: "16452108168275993030962142353354044100680963945240756716593099151407051066232"),
        "0x1a604e9dfa0efdc7ffda378af16cb81243b61633": Pool(symbol: "wstETH", decimals: 18,
            scope: "472674026048933344947929992064610492276304547390666782210980269768303717449"),
        "0xf973f4b180a568157cd7a0e6006449139e6bfc32": Pool(symbol: "wBTC", decimals: 8,
            scope: "9583811136054309663087994285053104517603064138421869930481915957893514499997"),
        "0xe6d36b33b00a7c0cb0c2a8d39d07e7db0c526abc": Pool(symbol: "USDe", decimals: 18,
            scope: "14948241600724488898497604617894553378727680542246736212613234875544074387056"),
        "0xc0a8bc0f4f982b4d4f1ffae8f4fccb58c9b29c98": Pool(symbol: "USD1", decimals: 18,
            scope: "2226641097145324517602489545296816163847340455393839014355318716099039951794"),
        "0xc6c769fac7aabeadd31a03fae5ca0ec5b4c50f84": Pool(symbol: "frxUSD", decimals: 18,
            scope: "6204545812131907406091007816562088763876564430686560668923081212690640630114"),
        "0x7d2959bcfb936a84531518e8391ddba844e03ebe": Pool(symbol: "WOETH", decimals: 18,
            scope: "16898919049235900033552063077301976558571004961846668515709160815006981236808"),
        "0xd14f4b36e1d1d98c218db782c49149876042bc56": Pool(symbol: "fxUSD", decimals: 18,
            scope: "18721688563067625530889443380856806549268759616049984113232683385397425859801"),
        "0xb4b5fd38fd4788071d7287e3cb52948e0d10b23e": Pool(symbol: "BOLD", decimals: 18,
            scope: "12594345321156708920712766274402096360984745412708601457862140420990105325804"),
    ]

    // MARK: - The seat (automatic — rides the watched wallets)

    /// No connect switch (2026-07-25, prd §207): watching a wallet is the
    /// consent to read its Privacy Pools deposits and poll their screening
    /// status — the sweep runs for every watched wallet and no-ops when none
    /// are. The old `seatKey`/`connected`/`disconnect()` toggle is gone;
    /// unwatching a wallet still drops that wallet's cursor AND its pending
    /// entries via `clearState`, so unwatching the last wallet clears all of
    /// them and a re-watch starts honest at a fresh backfill.

    private static func cursorKey(_ address: String) -> String {
        "privacypools.cursor.\(address.lowercased())"
    }

    /// Wallet unwatch takes this seat's cursor and that wallet's pending
    /// entries with it — called from WalletStore beside the siblings'.
    /// V2's own cursor: v1's has long passed v2's deploy block, so sharing it
    /// would skip every v2 deposit made before today.
    private static func v2CursorKey(_ address: String) -> String {
        "privacypools.v2cursor.\(address.lowercased())"
    }

    static func clearState(address: String) {
        UserDefaults.standard.removeObject(forKey: cursorKey(address))
        UserDefaults.standard.removeObject(forKey: v2CursorKey(address))
        let wallet = address.lowercased()
        setPending(pending().filter { $0["wallet"] != wallet })
        // …and the catalog seat's mark, or the seat stays lit for a wallet
        // that's gone (`WalletSeatEvidence` rule 2).
        evidence.forget(address)
    }

    /// Which watched wallets have actually deposited into Privacy Pools —
    /// the catalog seat's gate (2026-07-30). Until now the seat lit for ANY
    /// watched wallet; see `WalletSeatEvidence` for why evidence beats a
    /// bare watch.
    static let evidence = WalletSeatEvidence("privacypools.accounts")

    /// What a DEPOSIT row's `sourceRef` begins with. One constant because the
    /// landing and the status poll's `retag` must agree on it and, from §311
    /// until 2026-08-10, silently did not — see `retag`. `PrivacyPoolsRoomSource`
    /// reads it too, so the room's own count of deposits can never drift from
    /// what the bridge actually lands.
    static let depositRefPrefix = PrivacyPoolsRoom.depositPrefix

    /// The `Thing.source` every row here lands under — see
    /// `PeerBridge.sourceName` for why the room reads a constant rather than
    /// spelling its own copy.
    static let sourceName = "Privacy Pools"

    // MARK: - Pending-status watchlist (flat UserDefaults, keyless seat)

    private static let pendingKey = "privacypools.pending"

    /// Each entry: label (decimal), scope (decimal), symbol, amount (display
    /// string), wallet (lowercased hex), status (last seen; "" = just landed,
    /// baseline unknown). A v2 entry adds `v: "2"`, its `tx` and its `asset`
    /// (the ASP answers v2 by transaction under an asset) and has no scope;
    /// its `label` is the deposit's commitment, the key its row lands under.
    private static func pending() -> [[String: String]] {
        (UserDefaults.standard.array(forKey: pendingKey) as? [[String: String]]) ?? []
    }

    private static func setPending(_ entries: [[String: String]]) {
        UserDefaults.standard.set(entries, forKey: pendingKey)
    }

    // MARK: - Anonymity-set cover (prd §228)

    /// Per-pass memo of each pool's accepted-deposit count — the anonymity set
    /// a deposit hides in. `nil` until first read this pass (reset at the top
    /// of `syncLocked`), so a status-only pass with nothing landing never buys
    /// the call. Keyed by `scope` (matching `Pool.scope`).
    @MainActor private static var coverThisPass: [String: (count: Int, symbol: String)]?

    /// Reads 0xBow's public `pools-stats` once per pass and returns per-pool
    /// accepted-deposit counts. `acceptedDepositsCount` (not total, not
    /// pending) is the real set: only ASP-approved deposits sit in the merkle
    /// tree a withdrawal proof draws from, so it's the honest measure of how
    /// much cover a deposit has. Empty when unreachable — enrichment then just
    /// doesn't attach, the deposit lands bare (never a guessed number).
    @MainActor
    private static func cover() async -> [String: (count: Int, symbol: String)] {
        if let c = coverThisPass { return c }
        var out: [String: (count: Int, symbol: String)] = [:]
        if let root = await IngestSupport.getJSON("\(aspBase)/pools-stats") as? [String: Any],
           let list = root["pools"] as? [[String: Any]] {
            for p in list {
                guard let scope = p["scope"] as? String,
                      let count = p["acceptedDepositsCount"] as? Int else { continue }
                out[scope] = (count, (p["tokenSymbol"] as? String) ?? "")
            }
        }
        coverThisPass = out
        return out
    }

    /// The set-size line stored on a deposit's `enrichedText` — shown in the
    /// thing sheet and fed to search. Rounded to two significant figures: the
    /// exact count is noise, the ORDER OF MAGNITUDE is the privacy fact.
    private static func coverLine(symbol: String, count: Int) -> String {
        let approx = roundedSet(count)
        return String(localized: "Privacy Pools' \(symbol) pool holds about \(approx) accepted deposits — the anonymity set your deposit hides in.")
    }

    /// "3,900" from 3,947, "12" from 12 — two significant figures, taken from
    /// `PrivacyPoolsRoom` rather than spelled again (2026-08-17, prd §397).
    /// The room's cover line and this sentence state the same pool's set size
    /// on two surfaces, and rounding them separately is how the sheet and the
    /// card end up disagreeing by a hundred deposits about the same number —
    /// the `depositRefPrefix` lesson, applied before it could be earned twice.
    private static func roundedSet(_ n: Int) -> String {
        PrivacyPoolsRoom.roundedSet(n)
    }

    // MARK: - Cover refresh (prd §397)

    /// Re-reads every pool's accepted-deposit count at most once a day and
    /// keeps it as a NUMBER, so the room can state the anonymity set as it is
    /// NOW rather than as it was when each deposit landed (`PrivacyPoolsCover`
    /// has the whole argument).
    ///
    /// Gated on `evidence`, not on a watch: most watched wallets have never
    /// touched Privacy Pools, and buying a request a day for all of them would
    /// spend it on people who will never see a cover line. Costs one keyless
    /// GET, reuses this pass's memo when a deposit already bought it, and
    /// writes nothing when the host is unreachable.
    @MainActor
    private static func refreshCoverIfDue() async {
        guard !evidence.isEmpty, PrivacyPoolsCover.needsRefresh() else { return }
        let readings = await cover()
        guard !readings.isEmpty else { return }
        // Keyed by OUR table's symbol, never the API's `tokenSymbol` — the
        // room joins cover to holdings through `Thing.priceCurrency`, which is
        // stamped from `Pool.symbol`. See `PrivacyPoolsCover`.
        var bySymbol: [String: Int] = [:]
        for pool in pools.values {
            if let reading = readings[pool.scope], reading.count > 0 {
                bySymbol[pool.symbol] = reading.count
            }
        }
        PrivacyPoolsCover.save(current: bySymbol)
    }

    // MARK: - Sync

    @MainActor private static var running = false

    /// Reads new deposits for the given (resolved, hex) addresses, lands
    /// them, then polls the ASP for every watched pending deposit — called
    /// inside `WalletIngest.refresh`'s pass beside PeerBridge.sync, under
    /// that pass's running guard. Returns landed count (deposits + status
    /// alerts), nil when mainnet couldn't be reached at all.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        // Automatic: no seat gate. `syncLocked` returns 0 when no wallets.
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses,
                                existing: existing)
    }

    /// The setup screen's own entry — resolves the watch list the way the
    /// wallet refresh does.
    @MainActor
    static func syncNow(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched)
            .filter { ENS.isHexAddress($0) }
        return await syncLocked(context: context, addresses: addresses,
                                existing: IngestSupport.existingSourceRefs(context, source: "Privacy Pools"))
    }

    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String],
                                   existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let latest = await blockNumber() else { return nil }
        let defaults = UserDefaults.standard
        coverThisPass = nil   // fresh per pass; filled lazily only if something lands
        var added = 0
        // This seat is evidence-gated (2026-07-30) and this sweep reads
        // FORWARD from a cursor, so deposits that landed before the mark
        // existed sit behind it. One fetch over what they landed rebuilds
        // the mark; runs once, ever. See `backfillFromCorpus`.
        evidence.backfillFromCorpus(context, source: "Privacy Pools")

        for address in addresses {
            let key = cursorKey(address)
            // No silent baseline seed here — DIVERGES from Peer on purpose
            // (prd §162): the ASP alert's primary case is a deposit made
            // BEFORE connecting, and deposits are rare (the ETH pool holds
            // ~4k EVER), so first sight backfills from the deploy block,
            // capped to the newest 10 like every wallet landing path.
            let cursor = (defaults.object(forKey: key) as? Int) ?? (deployBlock - 1)
            guard latest > cursor else { continue }
            var from = cursor + 1
            let budget = maxRange * maxChunks
            if latest - from >= budget { from = latest - budget + 1 }
            var scanned = from - 1
            var depositLogs: [[String: Any]] = []
            var ragequitLogs: [[String: Any]] = []
            while scanned < latest {
                let to = min(scanned + maxRange, latest)
                guard let chunk = await fetchDeposits(wallet: address,
                                                      from: scanned + 1, to: to)
                else { break }
                depositLogs += chunk
                // Ragequits ride the SAME range/cursor (prd §228) — the exit
                // can only follow the deposit, so it's inside this window. A
                // ragequit read failing shouldn't strand deposits, so it's a
                // best-effort add, not a `break`.
                if let rq = await fetchRagequits(wallet: address,
                                                 from: scanned + 1, to: to) {
                    ragequitLogs += rq
                }
                scanned = to
            }
            guard scanned > cursor else { continue }   // nothing read — transient
            // A deposit found under this wallet is proof it uses Privacy
            // Pools — the catalog seat's evidence (2026-07-30). Keyed off
            // the LOGS, not what landed: a re-scanned window dedupes to zero
            // landed things while still proving the deposit is theirs.
            if !depositLogs.isEmpty { evidence.remember(address) }
            var landed = await things(from: depositLogs, wallet: address, existing: existing)
            landed += await ragequitThings(from: ragequitLogs, wallet: address,
                                           existing: existing, context: context)
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                closeReclaims(landed, context: context)
                // Land and SAVE before advancing (the WalletApprovals rule).
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            defaults.set(scanned, forKey: key)
        }
        for address in addresses {
            added += await syncV2(context: context, wallet: address,
                                  latest: latest, existing: existing)
        }

        // The status poll rides every pass, reachable-RPC or not — the ASP
        // is its own host, and a pending flip is the seat's whole point.
        let alerts = await pollStatuses(context: context, existing: existing)
        added += alerts
        // Ragequits that landed BEFORE the loop-closing pass shipped — runs
        // once, ever. See `healReclaimed`.
        healReclaimed(context: context)
        // …and the direction stamp, for rows that landed before 2026-08-26.
        healDirections(context: context)
        // At most one keyless GET a day, and only for a wallet that has
        // actually deposited (prd §397).
        await refreshCoverIfDue()
        return added
    }

    /// The one-time repair for reclaims that landed before 2026-08-17
    /// (prd §397).
    ///
    /// `PrivacyPoolsRoom` does this join itself and treats the ragequit ROW as
    /// the authority, so the CARD is right on every device the moment this
    /// ships, with or without this function. What this fixes is the stored
    /// TAG, which is what search, the §308 facets and the row's own chrome
    /// read — without it a deposit reclaimed last month keeps saying
    /// "Declined" everywhere except the card, and a card disagreeing with the
    /// row beneath it is worse than either being wrong alone.
    ///
    /// Forward-only sweeps cannot reach these rows: the cursor has long since
    /// passed the block the ragequit was in, so nothing re-reads it. Keyed by
    /// a done-flag like `ObsidianIngest.readerEpoch`, and cheap — one fetch
    /// over one source, once.
    @MainActor
    private static func healReclaimed(context: ModelContext) {
        let key = "privacypools.healedReclaims"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let source = sourceName
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source })
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows where row.isLive {
            guard let ref = row.sourceRef,
                  ref.hasPrefix(PrivacyPoolsRoom.reclaimedPrefix),
                  let label = PrivacyPoolsRoom.label(ref: ref) else { continue }
            retag(label: label, to: PrivacyPoolsRoom.State.reclaimed.rawValue,
                  context: context)
        }
        _ = context.saveHonestly()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// The one-time repair for rows that landed before the direction stamp
    /// (prd §485, 2026-08-26) — `healReclaimed`'s shape and its reasoning.
    ///
    /// Forward-only cursors cannot reach these rows, so without it the ledger
    /// column would only ever appear on deposits made from today on: a room
    /// half in prose and half in figures, which reads worse than either. The
    /// side is recoverable exactly because the ref already carries it — the
    /// same two prefixes the room head groups by — so nothing is guessed.
    @MainActor
    private static func healDirections(context: ModelContext) {
        let key = "privacypools.healedDirections"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let source = sourceName
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source })
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows where row.isLive {
            guard row.transferDirection == nil, let ref = row.sourceRef else { continue }
            if ref.hasPrefix(PrivacyPoolsRoom.depositPrefix) {
                row.transferDirection = "sent"
            } else if ref.hasPrefix(PrivacyPoolsRoom.reclaimedPrefix) {
                row.transferDirection = "received"
            }
        }
        _ = context.saveHonestly()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// `-privacyPoolsProbe <blocksBack|YES>` — switches the seat on upstream
    /// and runs the sweep + status poll headlessly. A numeric spec rewinds
    /// every cursor that many blocks below the head first; on a fresh install
    /// the plain run already backfills from the deploy block by design.
    @MainActor
    static func probe(context: ModelContext, blocksBack: Int?) async -> Int? {
        for _ in 0..<60 where running {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched)
            .filter { ENS.isHexAddress($0) }
        if let back = blocksBack, let latest = await blockNumber() {
            for address in addresses {
                UserDefaults.standard.set(max(deployBlock - 1, latest - back),
                                          forKey: cursorKey(address))
                UserDefaults.standard.set(max(v2DeployBlock - 1, latest - back),
                                          forKey: v2CursorKey(address))
            }
        }
        return await syncLocked(context: context, addresses: addresses,
                                existing: IngestSupport.existingSourceRefs(context, source: "Privacy Pools"))
    }

    /// `-privacyPoolsSeedPending "<label>[|<scope>]"` — plants a PENDING
    /// baseline for a real deposit label so the status-alert path can be
    /// verified end to end against the live ASP (the `-seedWalletHistory`
    /// idiom). The alert only ever fires on a transition observed WHILE
    /// watching, and a resolved deposit's flip already happened — so without
    /// a seeded baseline the branch can only be exercised by waiting days
    /// for someone's review to clear. Scope defaults to the ETH pool's.
    /// DEBUG-only by construction: nothing in the app writes this state.
    static func seedPending(spec: String) {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        guard let label = parts.first, !label.isEmpty else { return }
        let scope = parts.count > 1
            ? parts[1]
            : (pools["0xf241d57c6debae225c0f2e6ea1529373c9a9c9fb"]?.scope ?? "")
        let symbol = pools.values.first { $0.scope == scope }?.symbol ?? "ETH"
        var entries = pending().filter { $0["label"] != label }
        entries.append([
            "label": label, "scope": scope, "symbol": symbol,
            "amount": "", "wallet": "",
            "status": "pending",
        ])
        setPending(entries)
    }

    /// Probe-only (prd §228): a one-line snapshot of the largest pools'
    /// accepted-set sizes, so the anonymity-set read verifies headlessly.
    /// Clears the per-pass memo so it can't leak a stale cover into a real
    /// sweep that runs after the probe.
    @MainActor
    static func coverSummary() async -> String {
        let c = await cover()
        coverThisPass = nil
        guard !c.isEmpty else { return "cover: unreachable" }
        let top = c.values.sorted { $0.count > $1.count }.prefix(3)
            .map { "\($0.symbol) ~\($0.count)" }
        return "cover: " + top.joined(separator: ", ")
    }

    /// The probe's status line — what the pending watchlist holds right now.
    static func pendingSummary() -> String {
        let entries = pending()
        guard !entries.isEmpty else { return "0 pending" }
        let parts = entries.map { e in
            "\(e["amount"] ?? "?") \(e["symbol"] ?? "?")=\(e["status"]?.isEmpty == false ? e["status"]! : "unpolled")"
        }
        return "\(entries.count) followed: " + parts.joined(separator: ", ")
    }

    // MARK: - Landing deposits

    private struct Deposit {
        let commitment: String    // 32-byte hex, no 0x, lowercased
        let poolAddress: String   // lowercased hex
        let rawAmount: Double
        let block: Int
        let txHash: String
    }

    @MainActor
    private static func things(from logs: [[String: Any]], wallet: String,
                               existing: Set<String>) async -> [Thing] {
        var deposits: [Deposit] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count == 3,
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let data = log["data"] as? String,
                  let commitment = word(data, 0),
                  let amount = word(data, 1)
            else { continue }
            deposits.append(Deposit(
                commitment: commitment,
                poolAddress: "0x" + topics[2].suffix(40).lowercased(),
                rawAmount: WalletIngest.hexToDouble("0x" + amount),
                block: WalletIngest.hexToInt(blockHex),
                txHash: txHash))
        }
        deposits = Array(deposits.suffix(10))
        guard !deposits.isEmpty else { return [] }

        let times = await blockTimes(blocks: deposits.map(\.block))
        var out: [Thing] = []
        var seen = Set<String>()
        var watchlist = pending()

        for deposit in deposits {
            let pool = pools[deposit.poolAddress]
            // The label is the ASP's key — read off the pool's own Deposited
            // event in the same block, matched by commitment. A miss lands
            // the deposit anyway (keyed by commitment), just without status
            // polling — the thing is real either way.
            let label = await label(for: deposit, wallet: wallet)
            let ref = depositRefPrefix + (label ?? deposit.commitment)
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }

            // The size in the token's own units, kept as a NUMBER beside the
            // display string. `WalletIngest.format` rounds and groups by
            // locale, so parsing it back is both lossy and locale-dependent —
            // which is exactly why the room reads `priceValue` and never
            // `transferAmount` (`MetaMaskCardRoomSource`'s rule).
            let value = pool.map { deposit.rawAmount / pow(10, Double($0.decimals)) }
            let amount = value.map { WalletIngest.format($0) }
            let what = pool.map { "\(amount ?? "") \($0.symbol)" } ?? "crypto"
            let capturedAt = times[deposit.block] ?? .now
            let thing = depositThing(what: what, value: value, symbol: pool?.symbol,
                                     capturedAt: capturedAt, txHash: deposit.txHash,
                                     ref: ref, wallet: wallet)
            // Anonymity-set context (prd §228): how much cover this deposit
            // has, on `enrichedText` (the thing sheet's body + search), never
            // the title — it's context, not a tally-thing. Snapshot at landing;
            // reads bare when pools-stats is unreachable.
            if let pool, let c = (await cover())[pool.scope], c.count > 0 {
                thing.enrichedText = coverLine(symbol: pool.symbol, count: c.count)
                // …and the same count as a NUMBER, so the room can later say
                // the set GREW (prd §397). Written once per label and never
                // overwritten — see `PrivacyPoolsCover.snapshot`.
                if let label {
                    PrivacyPoolsCover.snapshot(label: label, count: c.count)
                }
            }
            out.append(thing)

            // Watch the label for its ASP flip. Baseline rule (alerts are
            // news): a deposit younger than a day seeds as "pending" so its
            // approval ALERTS; older backfill seeds "" and the first poll
            // records silently — its review already resolved before watching.
            if let label, let pool {
                let fresh = Date.now.timeIntervalSince(capturedAt) < 86_400
                watchlist.append([
                    "label": label, "scope": pool.scope,
                    "symbol": pool.symbol, "amount": amount ?? "",
                    "wallet": wallet.lowercased(),
                    "status": fresh ? "pending" : "",
                ])
            }
        }
        setPending(watchlist)
        return out
    }

    /// A deposit row, either version. `value` and `symbol` are nil together
    /// when the asset did not resolve, and then `what` is the word "crypto".
    private static func depositThing(what: String, value: Double?, symbol: String?,
                                     capturedAt: Date, txHash: String,
                                     ref: String, wallet: String) -> Thing {
        let thing = Thing(
            kind: .transaction,
            title: String(localized: "Put \(what) into Privacy Pools"),
            content: "https://etherscan.io/tx/\(txHash)",
            source: "Privacy Pools",
            capturedAt: capturedAt,
            tags: ["Shielded", "Pending"],
            sourceRef: ref)
        thing.walletAddress = wallet
        // The amount as DATA (prd §369, 2026-08-12) — the same
        // `transferAmount` slot the cards and Railgun already fill. Until
        // this it existed only inside the localized title, so the receipt
        // could not state a figure without parsing a sentence, which is the
        // one thing it refuses to do. Only when the asset resolved: `what`
        // falls back to the word "crypto", and "crypto" is not an amount.
        // An existing field — no CloudKit deploy — and rows landed before
        // today simply keep leading with their title.
        if symbol != nil { thing.transferAmount = what }
        // The DIRECTION, so the room's rows read as a ledger (prd §485).
        // `BandRow.moneyColumn` needs the pair — an amount with no
        // direction has no sign, so it stays inside the sentence — and
        // until this the pair was half-stamped: §369 landed the amount and
        // nothing ever landed the side it went. Money into the pool is
        // money out of the wallet, which is what "sent" means everywhere
        // else in this app.
        thing.transferDirection = "sent"
        // The size as STRUCTURED data (prd §397, 2026-08-17) — the same
        // `priceValue`/`priceCurrency` pair Railgun and the cards already
        // stamp, and the only reason the room can state what is in the
        // pools per asset. §349 refused that figure because the amount
        // lived solely inside a localized title; this is what retires the
        // refusal. Both existing fields — no CloudKit deploy — and
        // deposits landed before today stay `unpriced`, counted and named
        // on the card rather than silently missing from the total.
        if let symbol, let value {
            thing.priceValue = value
            thing.priceCurrency = symbol
        }
        return thing
    }

    /// The pool-level Deposited event in the deposit's own block, matched by
    /// commitment → the label, as a DECIMAL string (the ASP's own encoding).
    private static func label(for deposit: Deposit, wallet: String) async -> String? {
        let walletTopic = "0x000000000000000000000000" + wallet.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(deposit.block), "toBlock": hex(deposit.block),
            "address": deposit.poolAddress,
            "topics": [poolDepositedTopic, walletTopic],
        ]
        guard let logs = await call(method: "eth_getLogs",
                                    params: [params]) as? [[String: Any]]
        else { return nil }
        for log in logs {
            guard let data = log["data"] as? String,
                  word(data, 0) == deposit.commitment,
                  let labelHex = word(data, 1)
            else { continue }
            return decimalString(hexWord: labelHex)
        }
        return nil
    }

    // MARK: - V2 deposits and exits (2026-10-21)

    /// One wallet's v2 window: plain and yield deposits, then exits, landed
    /// and saved before the cursor moves (the v1 loop's rule). Returns landed.
    @MainActor
    private static func syncV2(context: ModelContext, wallet: String, latest: Int,
                               existing: Set<String>) async -> Int {
        let defaults = UserDefaults.standard
        let key = v2CursorKey(wallet)
        // First sight backfills from the deploy block, as v1 does — the
        // alert's main case is a deposit made before watching.
        let cursor = (defaults.object(forKey: key) as? Int) ?? (v2DeployBlock - 1)
        guard latest > cursor else { return 0 }
        var from = cursor + 1
        let budget = maxRange * maxChunks
        if latest - from >= budget { from = latest - budget + 1 }
        var scanned = from - 1
        var deposits: [[String: Any]] = []
        var exits: [[String: Any]] = []
        while scanned < latest {
            let to = min(scanned + maxRange, latest)
            guard let plain = await fetchV2Deposits(wallet: wallet, from: scanned + 1, to: to),
                  let yield = await fetchV2RouterDeposits(wallet: wallet, from: scanned + 1, to: to)
            else { break }
            deposits += plain + yield
            if let rq = await fetchV2Ragequits(wallet: wallet, from: scanned + 1, to: to) {
                exits += rq
            }
            scanned = to
        }
        guard scanned > cursor else { return 0 }
        if !deposits.isEmpty { evidence.remember(wallet) }
        var landed = await v2Things(from: deposits, wallet: wallet, existing: existing)
        landed += await landExits(v2Exits(from: exits), wallet: wallet,
                                  existing: existing, context: context)
        if !landed.isEmpty {
            for thing in landed {
                context.insert(thing)
                SpotlightIndex.index([thing])
            }
            closeReclaims(landed, context: context)
            guard context.saveHonestly() else { return 0 }
        }
        defaults.set(scanned, forKey: key)
        return landed.count
    }

    private struct V2Deposit {
        /// The asset the ASP files it under: the pool asset, or the yield share.
        let asset: String
        /// What the person put in, for the row — the underlying on a yield deposit.
        let paid: V2Asset?
        let raw: Double
        let block: Int
        let txHash: String
    }

    @MainActor
    private static func v2Things(from logs: [[String: Any]], wallet: String,
                                 existing: Set<String>) async -> [Thing] {
        var deposits: [V2Deposit] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let contract = (log["address"] as? String)?.lowercased(),
                  let topics = log["topics"] as? [String], topics.count == 3,
                  let txHash = (log["transactionHash"] as? String)?.lowercased(),
                  let blockHex = log["blockNumber"] as? String,
                  let data = log["data"] as? String
            else { continue }
            let block = WalletIngest.hexToInt(blockHex)
            if let router = v2Routers[contract] {
                // Router: shares, underlyingIn, sharesOut — the row states
                // what was paid in, the ASP knows it by the share.
                guard let paid = word(data, 1) else { continue }
                deposits.append(V2Deposit(asset: router.share, paid: router.underlying,
                                          raw: WalletIngest.hexToDouble("0x" + paid),
                                          block: block, txHash: txHash))
            } else {
                // Entrypoint: asset is topics[1], amount the first word.
                guard let amount = word(data, 0) else { continue }
                let asset = "0x" + topics[1].suffix(40).lowercased()
                deposits.append(V2Deposit(asset: asset, paid: v2Assets[asset],
                                          raw: WalletIngest.hexToDouble("0x" + amount),
                                          block: block, txHash: txHash))
            }
        }
        deposits = Array(deposits.sorted { $0.block < $1.block }.suffix(10))
        guard !deposits.isEmpty else { return [] }

        let times = await blockTimes(blocks: deposits.map(\.block))
        var out: [Thing] = []
        var seen = Set<String>()
        var watchlist = pending()
        for deposit in deposits {
            // The commitment is the key a later ragequit names; a miss keys
            // the row by its transaction, which still polls but cannot join.
            let commitment = await v2Commitment(for: deposit)
            let key = commitment ?? "v2:\(deposit.txHash)"
            let ref = depositRefPrefix + key
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }
            let value = deposit.paid.map { deposit.raw / pow(10, Double($0.decimals)) }
            let amount = value.map { WalletIngest.format($0) }
            let what = deposit.paid.map { "\(amount ?? "") \($0.symbol)" } ?? "crypto"
            let capturedAt = times[deposit.block] ?? .now
            out.append(depositThing(what: what, value: value, symbol: deposit.paid?.symbol,
                                    capturedAt: capturedAt, txHash: deposit.txHash,
                                    ref: ref, wallet: wallet))
            let fresh = Date.now.timeIntervalSince(capturedAt) < 86_400
            watchlist.append([
                "v": "2", "label": key, "tx": deposit.txHash, "asset": deposit.asset,
                "symbol": deposit.paid?.symbol ?? "", "amount": amount ?? "",
                "wallet": wallet.lowercased(),
                "status": fresh ? "pending" : "",
            ])
        }
        setPending(watchlist)
        return out
    }

    /// The PoolVault `Deposited` in the deposit's own transaction → its
    /// commitment, as a decimal string.
    private static func v2Commitment(for deposit: V2Deposit) async -> String? {
        let assetTopic = "0x000000000000000000000000" + deposit.asset.dropFirst(2)
        let params: [String: Any] = [
            "fromBlock": hex(deposit.block), "toBlock": hex(deposit.block),
            "address": v2PoolVault,
            "topics": [v2PoolDepositedTopic, assetTopic],
        ]
        guard let logs = await call(method: "eth_getLogs",
                                    params: [params]) as? [[String: Any]]
        else { return nil }
        for log in logs {
            guard (log["transactionHash"] as? String)?.lowercased() == deposit.txHash,
                  let data = log["data"] as? String,
                  let commitment = word(data, 0)
            else { continue }
            return decimalString(hexWord: commitment)
        }
        return nil
    }

    /// v2 `Ragequit` data words: value, commitment, nullifierHash, label —
    /// keyed by the COMMITMENT, which is what the deposit landed under.
    private static func v2Exits(from logs: [[String: Any]]) -> [Exit] {
        logs.compactMap { log in
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count == 3,
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let data = log["data"] as? String,
                  let valueHex = word(data, 0),
                  let commitment = word(data, 1)
            else { return nil }
            let asset = v2Assets["0x" + topics[2].suffix(40).lowercased()]
            return Exit(label: decimalString(hexWord: commitment),
                        symbol: asset?.symbol, decimals: asset?.decimals ?? 0,
                        raw: WalletIngest.hexToDouble("0x" + valueHex),
                        block: WalletIngest.hexToInt(blockHex), txHash: txHash)
        }
    }

    /// Review status for v2 deposits, by transaction: the ASP's events feed
    /// for each asset with something watched, newest first, paged until every
    /// watched transaction is found or five pages are read. Returns tx → status;
    /// an unreachable asset answers nothing and its entries wait a pass.
    private static func v2Statuses(for entries: [[String: String]]) async -> [String: String] {
        var wanted: [String: Set<String>] = [:]   // asset → tx hashes
        for e in entries {
            guard let asset = e["asset"], let tx = e["tx"] else { continue }
            wanted[asset, default: []].insert(tx)
        }
        var out: [String: String] = [:]
        for (asset, txs) in wanted {
            var missing = txs
            for page in 1...5 where !missing.isEmpty {
                guard let root = await IngestSupport.getJSON(
                        "\(v2ASPBase)/events?page=\(page)&perPage=100",
                        headers: ["X-Asset": asset]) as? [String: Any],
                      let events = root["events"] as? [[String: Any]], !events.isEmpty
                else { break }
                for event in events where (event["type"] as? String) == "deposit" {
                    guard let tx = (event["txHash"] as? String)?.lowercased(),
                          missing.contains(tx),
                          let status = event["reviewStatus"] as? String else { continue }
                    out[tx] = status
                    missing.remove(tx)
                }
            }
        }
        return out
    }

    // MARK: - Ragequit exits (prd §228)

    /// Turns a wallet's ragequit logs into "came back out" things — the honest
    /// closing bookend a normal (unlinkable) withdrawal can never be. Data
    /// words: commitment, label, value. Keyed on the label so it can't collide
    /// with the deposit's own ref, and pruned from the pending watchlist (a
    /// ragequit resolves it — it's out of the pool now). Newest 10, like every
    /// wallet landing path.
    /// The reclaim join again, once this window's rows are inserted.
    /// `landExits` retags as it decodes, which reaches a deposit landed in an
    /// EARLIER window; a deposit and its ragequit read in the SAME window
    /// (every first sight of a wallet that has already exited) are not in the
    /// context yet at that moment, so the deposit kept `Pending` (measured
    /// 2026-10-21 on a live v2 ragequit).
    @MainActor
    private static func closeReclaims(_ landed: [Thing], context: ModelContext) {
        for thing in landed {
            guard let ref = thing.sourceRef, ref.hasPrefix(PrivacyPoolsRoom.reclaimedPrefix),
                  let label = PrivacyPoolsRoom.label(ref: ref) else { continue }
            retag(label: label, to: PrivacyPoolsRoom.State.reclaimed.rawValue, context: context)
        }
    }

    /// One exit, decoded — v1 keys it by label, v2 by commitment, and each
    /// resolves its own asset; past that they land identically.
    private struct Exit {
        let label: String
        let symbol: String?
        let decimals: Int
        let raw: Double
        let block: Int
        let txHash: String
    }

    @MainActor
    private static func ragequitThings(from logs: [[String: Any]], wallet: String,
                                       existing: Set<String>,
                                       context: ModelContext) async -> [Thing] {
        var exits: [Exit] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let contract = (log["address"] as? String)?.lowercased(),
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let data = log["data"] as? String,
                  let labelHex = word(data, 1),
                  let valueHex = word(data, 2)
            else { continue }
            let pool = pools[contract]
            exits.append(Exit(label: decimalString(hexWord: labelHex),
                              symbol: pool?.symbol, decimals: pool?.decimals ?? 0,
                              raw: WalletIngest.hexToDouble("0x" + valueHex),
                              block: WalletIngest.hexToInt(blockHex),
                              txHash: txHash))
        }
        return await landExits(exits, wallet: wallet, existing: existing, context: context)
    }

    @MainActor
    private static func landExits(_ decoded: [Exit], wallet: String,
                                  existing: Set<String>,
                                  context: ModelContext) async -> [Thing] {
        let exits = Array(decoded.suffix(10))
        guard !exits.isEmpty else { return [] }

        let times = await blockTimes(blocks: exits.map(\.block))
        var out: [Thing] = []
        var seen = Set<String>()
        var watchlist = pending()
        for exit in exits {
            let ref = PrivacyPoolsRoom.reclaimedPrefix + exit.label
            // THE LOOP CLOSES HERE (prd §397, 2026-08-17). Deliberately ABOVE
            // the dedupe guard: a ragequit that already landed still needs its
            // deposit's tag moved, or a window re-scanned after this shipped
            // would land nothing and repair nothing. The deposit is the SAME
            // deposit — it is not declined any more, it is out — so the state
            // moves in place exactly as the ASP verdicts do, and the ragequit
            // row remains the news that it happened.
            retag(label: exit.label, to: PrivacyPoolsRoom.State.reclaimed.rawValue,
                  context: context)
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }
            let value = exit.symbol.map { _ in exit.raw / pow(10, Double(exit.decimals)) }
            let what = exit.symbol.map { "\(WalletIngest.format(value ?? 0)) \($0)" } ?? "crypto"
            let thing = Thing(
                kind: .transaction,
                title: String(localized: "Reclaimed \(what) from Privacy Pools"),
                content: "https://etherscan.io/tx/\(exit.txHash)",
                source: "Privacy Pools",
                capturedAt: times[exit.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = wallet
            // The same structured pair the deposit carries (prd §397), so the
            // exit draws a real money receipt (§363) instead of leading with
            // its title. The ROOM never counts a reclaim toward holdings —
            // this money is out of the pools — so these fields feed the sheet,
            // not the card.
            if let symbol = exit.symbol, let value {
                thing.transferAmount = what
                thing.priceValue = value
                thing.priceCurrency = symbol
            }
            // Outside the priced branch on purpose: which way the money went
            // is known even when the pool did not resolve, and a direction is
            // a fact about the row rather than a companion to the figure.
            thing.transferDirection = "received"
            out.append(thing)
            // Out of the pool — stop watching its screening status.
            watchlist.removeAll { $0["label"] == exit.label }
        }
        setPending(watchlist)
        return out
    }

    // MARK: - ASP status poll

    /// Polls 0xBow's public deposits-by-label route for every watched label,
    /// batched per pool scope (the API's own batching: comma-joined
    /// X-Labels under one X-Pool-Scope). Lands alert things on watched
    /// transitions, prunes terminal entries. Returns alerts landed.
    /// Moves a deposit row's state tag as the ASP answers (prd §311).
    ///
    /// One tag from a fixed set at a time — `Pending` → `Cleared` / `Declined`
    /// / `Needs proof` — so a row always states exactly one state and the
    /// room's distribution can never double-count a deposit that changed its
    /// mind. `Shielded` stays on regardless: it says what the row IS, not how
    /// the review went.
    ///
    /// Silent when the deposit isn't here — a status can arrive for a label
    /// whose deposit predates the tag or was removed, and inventing a row for
    /// it would be worse than saying nothing.
    ///
    /// The ref is built from `depositRefPrefix` rather than spelled again, and
    /// that is a FIX, not tidiness. §311 shipped this lookup spelled
    /// `"privacypools:deposit:"` while `landDeposits` lands
    /// `"privacypools:dep:"`, so the fetch matched nothing, ever: every deposit
    /// on every device stayed tagged `Pending` for life, including the ones the
    /// ASP had already cleared. Nothing could see it — the alert row still
    /// landed and still rained, the deposit row still drew, and the only
    /// casualty was the tag nobody was reading yet. One constant, so the two
    /// halves cannot disagree about a string again.
    @MainActor
    private static func retag(label: String, to state: String, context: ModelContext) {
        let ref = depositRefPrefix + label
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        guard let thing = (try? context.fetch(descriptor))?.first, thing.isLive else { return }
        var tags = thing.tags.filter { !PrivacyPoolsRoom.states.contains($0) }
        tags.append(state)
        guard tags != thing.tags else { return }
        thing.tags = tags
    }

    @MainActor
    private static func pollStatuses(context: ModelContext,
                                     existing: Set<String>) async -> Int {
        let entries = pending()
        guard !entries.isEmpty else { return 0 }

        var byScope: [String: [String]] = [:]
        for e in entries {
            guard let scope = e["scope"], let label = e["label"] else { continue }
            byScope[scope, default: []].append(label)
        }
        var statuses: [String: String] = [:]   // label → reviewStatus
        for (scope, labels) in byScope {
            guard let rows = await IngestSupport.getJSON(
                "\(aspBase)/deposits-by-label",
                headers: ["X-Pool-Scope": scope,
                          "X-Labels": labels.joined(separator: ",")]) as? [[String: Any]]
            else { continue }   // ASP unreachable — keep entries, retry next pass
            for row in rows {
                guard let label = row["label"] as? String,
                      let status = row["reviewStatus"] as? String else { continue }
                statuses[label] = status
            }
        }
        // v2 answers by transaction; filed back under the entry's own key so
        // the switch below treats both versions alike.
        let v2 = entries.filter { $0["v"] == "2" }
        if !v2.isEmpty {
            let byTx = await v2Statuses(for: v2)
            for e in v2 {
                guard let tx = e["tx"], let label = e["label"],
                      let status = byTx[tx] else { continue }
                statuses[label] = status
            }
        }
        guard !statuses.isEmpty else { return 0 }

        var alerts = 0
        var kept: [[String: String]] = []
        for var e in entries {
            guard let label = e["label"], let status = statuses[label] else {
                kept.append(e)   // not answered this pass — keep watching
                continue
            }
            let stored = e["status"] ?? ""
            let watching = stored == "pending" || stored == "poi_required"
            switch status {
            case "approved", "declined":
                // The deposit's OWN row learns its state (2026-08-05, prd
                // §311). Until now the status lived in the alert's title text
                // and a UserDefaults watchlist, so nothing could group or
                // filter on it — the room could not say how much was still
                // waiting, and "what's pending" had no answer. Re-tagged in
                // place rather than landed as a new row: a deposit clearing is
                // the SAME deposit, and its alert is already the news.
                retag(label: label, to: status == "approved" ? "Cleared" : "Declined",
                      context: context)
                if watching {
                    let what = "\(e["amount"] ?? "") \(e["symbol"] ?? "")"
                        .trimmingCharacters(in: .whitespaces)
                    let title = status == "approved"
                        ? String(localized: "Privacy Pools cleared your \(what) deposit — ready to withdraw privately")
                        : String(localized: "Privacy Pools declined your \(what) deposit — reclaim it to your account")
                    let ref = "privacypools:status:\(label)"
                    if !existing.contains(ref) {
                        let thing = Thing(kind: .transaction, title: title,
                                          content: e["v"] == "2" ? v2AppURL : v1AppURL,
                                          source: "Privacy Pools",
                                          capturedAt: .now, sourceRef: ref)
                        thing.walletAddress = e["wallet"]
                        context.insert(thing)
                        SpotlightIndex.index([thing])
                        if context.saveHonestly() { alerts += 1 }
                    }
                }
                // Resolved either way — done watching this label.
            case "exited", "spent":
                break   // terminal, the person acted elsewhere — drop silently
            case "poi_required":
                // The one status the person must ACT on (prd §228): 0xBow
                // needs proof-of-innocence before it can clear this deposit.
                // Alert once, on the transition INTO poi from a watched
                // pending — not on a "" backfill baseline (that's news that
                // already happened) and not every pass (the ref guards it).
                // Then keep watching: poi can still resolve to approved or
                // declined, which alerts through the case above. UNMEASURED
                // live — built to the documented enum, re-measure before
                // trusting the copy.
                retag(label: label, to: "Needs proof", context: context)
                if watching, stored == "pending" {
                    let what = "\(e["amount"] ?? "") \(e["symbol"] ?? "")"
                        .trimmingCharacters(in: .whitespaces)
                    let ref = "privacypools:poi:\(label)"
                    if !existing.contains(ref) {
                        let thing = Thing(
                            kind: .transaction,
                            title: String(localized: "Privacy Pools needs proof for your \(what) deposit — open 0xBow"),
                            content: e["v"] == "2" ? v2AppURL : v1AppURL,
                            source: "Privacy Pools",
                            capturedAt: .now, sourceRef: ref)
                        thing.walletAddress = e["wallet"]
                        context.insert(thing)
                        SpotlightIndex.index([thing])
                        if context.saveHonestly() { alerts += 1 }
                    }
                }
                e["status"] = status
                kept.append(e)
            default:
                // pending / anything new: keep watching. A "" baseline records
                // the first-seen status silently here.
                e["status"] = status
                kept.append(e)
            }
        }
        setPending(kept)
        return alerts
    }

    // MARK: - RPC reads (mainnet public hosts, first that answers wins)

    private static func call(method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": method, "params": params]
        for rpc in rpcs {
            if let root = await IngestSupport.postJSON(rpc, body: body) as? [String: Any],
               let result = root["result"], !(result is NSNull) {
                return result
            }
        }
        return nil
    }

    private static func blockNumber() async -> Int? {
        guard let hex = await call(method: "eth_blockNumber", params: []) as? String
        else { return nil }
        return WalletIngest.hexToInt(hex)
    }

    /// Entrypoint Deposited logs where the depositor is this wallet —
    /// every pool in one call, filtered server-side by the indexed topic.
    private static func fetchDeposits(wallet: String, from: Int,
                                      to: Int) async -> [[String: Any]]? {
        let walletTopic = "0x000000000000000000000000" + wallet.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": entrypoint,
            "topics": [depositedTopic, walletTopic],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// Ragequit logs where the ragequitter is this wallet — every pool in one
    /// call (address array), filtered server-side by the indexed depositor
    /// topic, exactly like the deposit read. nil = host refused/errored.
    private static func fetchRagequits(wallet: String, from: Int,
                                       to: Int) async -> [[String: Any]]? {
        let walletTopic = "0x000000000000000000000000" + wallet.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": poolAddresses,
            "topics": [ragequitTopic, walletTopic],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// v2 Entrypoint deposits by this wallet — the depositor is topics[2].
    private static func fetchV2Deposits(wallet: String, from: Int,
                                        to: Int) async -> [[String: Any]]? {
        let walletTopic = "0x000000000000000000000000" + wallet.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": v2Entrypoint,
            "topics": [v2DepositedTopic, NSNull(), walletTopic],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// v2 yield deposits by this wallet, every router in one call — the
    /// person is the router event's topics[1].
    private static func fetchV2RouterDeposits(wallet: String, from: Int,
                                              to: Int) async -> [[String: Any]]? {
        let walletTopic = "0x000000000000000000000000" + wallet.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": Array(v2Routers.keys),
            "topics": [v2RouterDepositedTopic, walletTopic],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// v2 ragequits by this wallet. v2 notes can change hands, so the
    /// ragequitter is whoever held the note — a reclaim of a note this wallet
    /// was sent lands too, and joins no deposit, which is the truth.
    private static func fetchV2Ragequits(wallet: String, from: Int,
                                         to: Int) async -> [[String: Any]]? {
        let walletTopic = "0x000000000000000000000000" + wallet.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": v2PoolVault,
            "topics": [v2RagequitTopic, walletTopic],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    private static func blockTimes(blocks: [Int]) async -> [Int: Date] {
        var out: [Int: Date] = [:]
        for block in Set(blocks).sorted(by: >).prefix(8) {
            guard let b = await call(method: "eth_getBlockByNumber",
                                     params: [hex(block), false]) as? [String: Any],
                  let ts = b["timestamp"] as? String else { continue }
            out[block] = Date(timeIntervalSince1970: WalletIngest.hexToDouble(ts))
        }
        return out
    }

    /// The nth 32-byte word of ABI-encoded hex data (past the 0x), lowercased.
    private static func word(_ data: String, _ n: Int) -> String? {
        let hex = data.hasPrefix("0x") ? String(data.dropFirst(2)) : data
        let start = n * 64, end = start + 64
        guard hex.count >= end else { return nil }
        let s = hex.index(hex.startIndex, offsetBy: start)
        let e = hex.index(hex.startIndex, offsetBy: end)
        return String(hex[s..<e]).lowercased()
    }

    /// A 32-byte hex word as the decimal string the ASP speaks. Labels are
    /// uint256 — far past every native integer — so this is schoolbook
    /// base-conversion on bytes, exact by construction (a Double round-trip
    /// here would corrupt every label silently).
    static func decimalString(hexWord: String) -> String {
        var bytes: [UInt8] = []
        var iter = hexWord.makeIterator()
        while let hi = iter.next(), let lo = iter.next() {
            guard let h = hi.hexDigitValue, let l = lo.hexDigitValue else { return "0" }
            bytes.append(UInt8(h << 4 | l))
        }
        var digits: [UInt8] = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in digits.indices {   // digits × 256 + byte, little-endian
                let v = Int(digits[i]) * 256 + carry
                digits[i] = UInt8(v % 10)
                carry = v / 10
            }
            while carry > 0 {
                digits.append(UInt8(carry % 10))
                carry /= 10
            }
        }
        return String(digits.reversed().map { Character(String($0)) })
    }

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }
}
