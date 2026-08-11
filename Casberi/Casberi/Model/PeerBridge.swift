import Foundation
import SwiftData

/// Peer (peer.xyz, the protocol formerly ZKP2P) — fiat↔crypto trades that
/// settle onchain into the person's OWN wallet (2026-07-17, prd §113). The
/// seat rides the Wallet bridge the way Strava rides Apple Health: no
/// account, no key, no OAuth — Peer's identity IS the wallet, so connecting
/// just switches on a log sweep over the already-watched addresses. Without
/// this seat a Peer buy still lands as a bare transfer; what the seat adds is
/// the WHY — "Bought 25 USDC with Venmo on Peer" instead of "received 25
/// USDC from 0x77…".
///
/// The read is the WalletApprovals shape (cursors, running guard, fail-closed,
/// land-before-advance) against Peer's two orchestrators on Base — V3 is the
/// production protocol and Base is its home chain; other chains arrive via
/// bridge hooks and still settle the Base leg through these contracts. A
/// fulfilled intent emits `IntentFulfilled(intentHash, fundsTransferredTo,
/// amount, isManualRelease)` with the RECEIVING WALLET INDEXED — so one
/// filtered `eth_getLogs` per wallet per pass answers "did Peer pay this
/// wallet", server-side, tiny. The story behind each fill — payment platform,
/// fiat currency, conversion rate — rides its `IntentSignaled` event (indexed
/// by the same intentHash), and the settled TOKEN comes off the escrow's
/// `getDeposit` view. All addresses, event shapes, and the payment-method /
/// fiat-currency hash tables below are from Peer's own published deployment
/// package (@zkp2p/contracts-v2 0.3.0, generated 2026-07-15); the hash scheme
/// was verified against it (keccak256("USD") reproduces their USD constant)
/// before any of this was written.
///
/// Three more reads round out the picture (prd §237, "what else can we do
/// with Peer", 2026-07-29), all still capture-only:
///  1. SELLS — the maker/offramp side, landed as "Sold X with Venmo on Peer".
///     A buy is easy (the recipient is INDEXED on IntentFulfilled); a sell
///     has no such shortcut — the maker's address only ever appears as the
///     DEPOSITOR of the liquidity a buyer later draws from, which is a
///     different event on the escrow contract entirely. So the read walks:
///     escrow `DepositReceived`-equivalent (depositor indexed → depositId) →
///     `IntentSignaled` scoped to (escrow, depositId) (all three indexed,
///     cheap) → `IntentFulfilled` batched by the resulting intentHash set.
///     An open deposit is tracked in a small persisted watchlist (the
///     Privacy Pools pending-list shape) so a maker's liquidity that sits
///     for days before being taken is never missed.
///  2. STUCK INTENTS — the same watchlist's other branch. Peer's own
///     INTENT_EXPIRATION releases a signaled-but-unfulfilled intent back to
///     the deposit after ~6h; today that reclaim is invisible. Once an
///     intent against a WATCHED deposit is old enough with no matching
///     IntentFulfilled, it lands once: "A buyer's payment fell through —
///     your money's available again on Peer." This only works from the
///     MAKER's side — a BUYER's own stuck intent can't be found this way,
///     because (unlike depositId) the buyer's address is never an indexed
///     topic on either event; the §113 ruling below ("a signaled-but-
///     unfulfilled intent … never lands") still holds for buys.
///  3. RATE CONTEXT — every fill already decodes `conversionRate` and
///     `fiatCurrency` and then threw them away. Now, when the currency is
///     USD, the fiat paid and the live market price (keyless, via
///     `DefiLlamaPrices`) turn into one `enrichedText` line: "You paid
///     $30.00 for 34.13 USDC — about 0.3% above market." Non-USD currencies
///     still show the fiat amount, never a spread (no FX cross-rate on
///     hand — inventing one would be a guess, and this app doesn't guess).
///
/// Honesty boundaries, by ruling (prd §113):
/// - CAPTURE ONLY. Nothing here (or anywhere) starts a trade — same line as
///   Bankr's "answer only" and the Wallet screen's "watching can never trade
///   or move funds".
/// - A thing lands when a trade SETTLES, and not before. A signaled-but-
///   unfulfilled BUY intent is a limbo the app would have to poll and could
///   mis-report; it never lands. (A SELL-side stuck intent is different —
///   prd §237 — because there the "limbo resolved to reclaim" fact is itself
///   the news, not a guess about an outcome still pending.)
/// - The ZK design keeps the fiat leg private — the chain shows platform,
///   token, amount, and rate, never the counterparty or the person's Venmo
///   side. Titles state only what the events carry; an unknown payment-method
///   hash lands as plain "Bought … on Peer", never a guess.
enum PeerBridge {

    /// The `Thing.source` every row here lands under. Named so
    /// `PeerRoomSource` filters on a constant rather than on a literal of its
    /// own — a room that spells its own source name is a room that empties
    /// silently the day the seat is renamed. The landing sites below still
    /// spell it inline; `scripts/wallet-rooms-selftest.sh` drift-guards that
    /// they still agree with this.
    static let sourceName = "Peer"

    /// Peer's home chain. The RPC hosts and range cap are the Wallet bridge's
    /// measured Base values (WalletApprovals, 2026-07-16) — same public host,
    /// same 9k-block getLogs ceiling; don't raise without re-measuring.
    private static let rpcs = ["https://mainnet.base.org"]
    private static let maxRange = 9_000
    private static let maxChunks = 16
    static let network = "base-mainnet"

    /// Both live orchestrators (V3 shipped a second generation beside the
    /// first; fills flow through whichever the maker's escrow is registered
    /// with, so the sweep watches both — one getLogs takes an address ARRAY,
    /// so watching two costs nothing extra).
    static let orchestrators = [
        "0x88888883ed048ff0a415271b28b2f52d431810d0",   // Orchestrator
        "0x888888359e981b5225ca48fbcdceff702fc3b888",   // OrchestratorV2
    ]

    /// `IntentFulfilled(bytes32 indexed intentHash, address indexed
    /// fundsTransferredTo, uint256 amount, bool isManualRelease)`
    private static let fulfilledTopic =
        "0xd50b3b21bc45b85ddfaec58dbf56fe9b88754d08f47dcf5143b63258a57ad944"
    /// `IntentSignaled(bytes32 indexed intentHash, address indexed escrow,
    /// uint256 indexed depositId, bytes32 paymentMethod, address owner,
    /// address to, uint256 amount, bytes32 fiatCurrency,
    /// uint256 conversionRate, uint256 timestamp)`
    private static let signaledTopic =
        "0xf8c114f83581b2cf0b9f130782a93024aa8933e7d188901156bd68bdd558a20a"

    /// keccak256(method name) → what people call it — Peer's own registry
    /// (paymentMethods/base, 0.3.0). A hash not listed here is a method added
    /// after this table; the title simply omits the platform.
    private static let paymentMethods: [String: String] = [
        "0x90262a3db0edd0be2369c6b28f9e8511ec0bac7136cefbada0880602f87e7268": "Venmo",
        "0x617f88ab82b5c1b014c539f7e75121427f0bb50a4c58b187a238531e7d58605d": "Revolut",
        "0x10940ee67cfb3c6c064569ec92c0ee934cd7afa18dd2ca2d6a2254fcb009c17d": "Cash App",
        "0x554a007c2217df766b977723b276671aee5ebb4adaea0edb6433c88b3e61dac5": "Wise",
        "0xa5418819c024239299ea32e09defae8ec412c03e58f5c75f1b2fe84c857f5483": "Mercado Pago",
        "0xf752c7d19698ecb0bb8988abf9b9a53a4c3657f3bc8850a6fb59fdf3e3ce8cd3": "Zelle",
        "0x3ccc3d4d5e769b1f82dc4988485551dc0cd3c7a3926d7d8a4dde91507199490f": "PayPal",
        "0x62c7ed738ad3e7618111348af32691b5767777fbaf46a2d8943237625552645c": "Monzo",
        "0xcac9daea62d7b89d75ac73af4ee14dcf25721012ae82b568c2ea5c808eaa04ff": "Alipay",
        "0x5908bb0c9b87763ac6171d4104847667e7f02b4c47b574fe890c1f439ed128bb": "Chime",
    ]

    /// keccak256(ISO code) → the code — the currencies Peer's methods quote
    /// today (same package; USD verified by recomputation). Unknown hash →
    /// the title omits the fiat side rather than inventing one.
    private static let currencies: [String: String] = [
        "0xc4ae21aac0c6549d71dd96035b7e0bdb6c79ebdba8891b666115bc976d16a29e": "USD",
        "0xfff16d60be267153303bbfa66e593fb8d06e24ea5ef24b6acca5224c2ca6b907": "EUR",
        "0x90832e2dc3221e4d56977c1aa8f6a6706b9ad6542fbbdaac13097d0fa5e42e67": "GBP",
        "0xcb83cbb58eaa5007af6cad99939e4581c1e1b50d65609c30f303983301524ef3": "AUD",
        "0x221012e06ebf59a20b82e3003cf5d6ee973d9008bdb6e2f604faa89a27235522": "CAD",
        "0xfe13aafd831cb225dfce3f6431b34b5b17426b6bff4fccabe4bbe0fe4adc0452": "JPY",
        "0xc241cc1f9752d2d53d1ab67189223a3f330e48b75f73ebf86f50b2c78fe8df88": "SGD",
        "0xa156dad863111eeb529c4b3a2a30ad40e6dcff3b27d8f282f82996e58eee7e7d": "HKD",
        "0xdbd9d34f382e9f6ae078447a655e0816927c7c3edec70bd107de1d34cb15172e": "NZD",
        "0xc9d84274fd58aa177cabff54611546051b74ad658b939babaad6282500300d36": "CHF",
        "0xa94b0702860cb929d0ee0c60504dd565775a058bf1d2a2df074c1db0a66ad582": "MXN",
        "0xfaaa9c7b2f09d6a1b0971574d43ca62c3e40723167c09830ec33f06cec921381": "CNY",
        "0x8895743a31faedaa74150e89d06d281990a1909688b82906f0eb858b37f82190": "SEK",
        "0x8fb505ed75d9d38475c70bac2c3ea62d45335173a71b2e4936bd9f05bf0ddfea": "NOK",
        "0x5ce3aa5f4510edaea40373cbe83c091980b5c92179243fe926cb280ff07d403e": "DKK",
        "0x9a788fb083188ba1dfb938605bc4ce3579d2e085989490aca8f73b23214b7c1d": "PLN",
        "0x128d6c262d1afe2351c6e93ceea68e00992708cfcbc0688408b9a23c0c543db2": "TRY",
        "0x53611f0b3535a2cfc4b8deb57fa961ca36c7b2c272dfe4cb239a29c48e549361": "ZAR",
        "0x4dab77a640748de8588de6834d814a344372b205265984b969f3e97060955bfa": "AED",
        "0x326a6608c2a353275bd8d64db53a9d772c1d9a5bc8bfd19dfc8242274d1e9dd4": "THB",
        "0xf998cbeba8b7a7e91d4c469e5fb370cdfa16bd50aea760435dc346008d78ed1f": "SAR",
        "0xd783b199124f01e5d0dde2b7fc01b925e699caea84eae3ca92ed17377f498e97": "CZK",
        "0x7766ee347dd7c4a6d5a55342d89e8848774567bcf7a5f59c3e82025dbde3babb": "HUF",
        "0x2dd272ddce846149d92496b4c3e677504aec8d5e6aab5908b25c9fe0a797e25f": "RON",
    ]

    /// The one escrow every OrchestratorV2 intent settles against — MEASURED
    /// live 2026-07-29 (1,021 real `IntentSignaled` events swept across
    /// ~135k recent Base blocks, one escrow every single time). The legacy
    /// "Orchestrator" (V1) address above carries zero traffic in that same
    /// window — its escrow is unconfirmed and deliberately out of scope for
    /// the sell-side read below; don't extend it there without re-measuring.
    private static let escrow = "0x777777779d229cdf3110e9de47943791c26300ef"

    /// Escrow deposit-creation event — topic0 MEASURED live (matched by
    /// scanning the escrow's own logs for one already known depositor, not
    /// derived from a signature string). `topics[1]` = depositId, `topics[2]`
    /// = depositor, `topics[3]` = token — all three indexed, cross-checked
    /// against `getDeposit(depositId)`'s own depositor/token words for six
    /// independent deposits. NOTE: Peer's public GitHub `main` branch shows a
    /// DIFFERENT (non-indexed-token) shape for this event — that's a newer or
    /// otherwise undeployed version; what's live at the address above is what
    /// this bridge reads, and this topic0 is proof of that, not a guess.
    private static let depositCreatedTopic =
        "0x1236dbdc184b6c8721974cce53dabb6018679bca9a43784ab2ad71bcdb1d7dd1"

    /// How long a signaled-but-unfulfilled SELL-side intent is given before
    /// Casberi calls it stuck (prd §237). Peer's own INTENT_EXPIRATION is the
    /// ~6h window `signalStory`'s own backward search already banks on
    /// (`floor = fill.block - 12_000`, ≈6h of Base blocks); this adds a
    /// 30-minute buffer against clock/finality skew before landing the alert
    /// — a false "fell through" would be worse than a slightly late one.
    private static let intentExpirySeconds: TimeInterval = 6.5 * 3600

    // MARK: - The seat (automatic — rides the watched wallets)

    /// There is no connect switch anymore (2026-07-25, prd §207, user:
    /// "if you use a wallet in peer … it should automatically watch them").
    /// Peer's identity IS the wallet, so watching a wallet is the consent to
    /// read its fills — the sweep runs for every watched wallet and no-ops
    /// when none are (the `!addresses.isEmpty` guard below). The old
    /// `seatKey`/`connected`/`disconnect()` toggle is gone; unwatching a
    /// wallet still drops that wallet's cursor from `WalletStore` via
    /// `clearCursor`, which was the whole of disconnect's teardown, per
    /// address — so a re-watch still seeds a fresh baseline, honest at zero.

    private static func cursorKey(_ address: String) -> String {
        "peer.cursor.\(address.lowercased())"
    }

    /// Wallet unwatch takes this seat's cursor for that address with it —
    /// called beside WalletApprovals.clearCursors from WalletStore. Also
    /// drops that wallet's open-deposits watchlist entries (prd §237) — a
    /// stale entry would keep polling (and could alert "funds available
    /// again") for a deposit belonging to a wallet no longer watched.
    static func clearCursor(address: String) {
        UserDefaults.standard.removeObject(forKey: cursorKey(address))
        let wallet = address.lowercased()
        setOpenDeposits(openDeposits().filter { $0["wallet"] != wallet })
        // …and the catalog seat's mark, or the seat stays lit for a wallet
        // that's gone (`WalletSeatEvidence` rule 2).
        evidence.forget(address)
    }

    /// Which watched wallets have actually traded on Peer — the catalog
    /// seat's gate (2026-07-30). Until now the seat lit for ANY watched
    /// wallet, which claimed a relationship most people don't have; see
    /// `WalletSeatEvidence` for why evidence beats a bare watch.
    static let evidence = WalletSeatEvidence("peer.accounts")

    // MARK: - Open deposits watchlist (maker/sell side, prd §237)

    private static let openDepositsKey = "peer.openDeposits"

    /// Each entry: depositId (decimal string), wallet (lowercased hex),
    /// lastBlock (string int — how far this deposit's own IntentSignaled
    /// range has been scanned). No per-intent state is kept here: once an
    /// intentHash resolves (sold or expired), the global `existing` sourceRef
    /// dedup is what stops it landing twice, the same as every other bridge
    /// in this app — so a deposit that accumulates hundreds of intents over
    /// its life costs this list nothing extra.
    private static func openDeposits() -> [[String: String]] {
        (UserDefaults.standard.array(forKey: openDepositsKey) as? [[String: String]]) ?? []
    }

    private static func setOpenDeposits(_ entries: [[String: String]]) {
        UserDefaults.standard.set(entries, forKey: openDepositsKey)
    }

    static func openDepositsSummary() -> String {
        let entries = openDeposits()
        guard !entries.isEmpty else { return "0 open deposits" }
        return "\(entries.count) open: " + entries.map { "#\($0["depositId"] ?? "?")" }.joined(separator: ", ")
    }

    // MARK: - Sync

    /// Two passes racing (the probe beside a foreground refresh) could each
    /// read the same cursor and double-land — one runs, the other returns 0.
    @MainActor private static var running = false

    /// Reads new fills for the given (resolved, hex) addresses and lands them
    /// as things — called inside `WalletIngest.refresh`'s pass beside
    /// WalletApprovals.sync, so it rides every path that syncs the wallet
    /// under that pass's stagger, sharing its resolved addresses and dedupe
    /// set. Returns the landed count, nil when Base couldn't be reached at
    /// all — callers fold nil to 0 landed, and only LANDED fills vouch for
    /// reach (the approvals rule: things that landed are proof in their own
    /// right; an empty pass never is). Peer refs ("peer:…") can't collide
    /// with the wallet pass's own refs, so `existing` staying fixed across
    /// the pass is sound.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        // Automatic: no seat gate. Runs for whatever wallets this pass
        // resolved; `syncLocked` returns 0 when there are none.
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses,
                                existing: existing)
    }

    /// The setup screen's own entry — resolves the watch list the way the
    /// wallet refresh does (a wallet watched as "vitalik.eth" sweeps as its
    /// hex), so Connect syncs without dragging the whole wallet pass along.
    @MainActor
    static func syncNow(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched)
            .filter { ENS.isHexAddress($0) }
        return await syncLocked(context: context, addresses: addresses,
                                existing: IngestSupport.existingSourceRefs(context, source: "Peer"))
    }

    /// The pass body — callers must hold `running`. nil = Base unreachable.
    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String],
                                   existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let latest = await blockNumber() else { return nil }
        let defaults = UserDefaults.standard
        var added = 0
        // Peer's seat is evidence-gated (2026-07-30), and this sweep reads
        // FORWARD from a cursor — so fills that landed before the mark
        // existed are already behind it and no future pass would ever see
        // them. One fetch over what they landed reconstructs the mark; runs
        // once, ever. See `backfillFromCorpus`.
        evidence.backfillFromCorpus(context, source: "Peer")

        for address in addresses {
            let key = cursorKey(address)
            guard let cursor = defaults.object(forKey: key) as? Int else {
                // First sight: seed the baseline silently — the NFT-arrival
                // idiom; history before the watch isn't ours to dump. (The
                // probe's rewind is how past fills land deliberately.)
                defaults.set(latest, forKey: key)
                continue
            }
            guard latest > cursor else { continue }
            var from = cursor + 1
            let budget = maxRange * maxChunks
            if latest - from >= budget { from = latest - budget + 1 }   // hole accepted
            // Chunked forward scan — a mid-scan failure keeps the cursor at
            // the last DURABLE point so the remainder retries next pass.
            var scanned = from - 1
            var logs: [[String: Any]] = []
            var depositLogs: [[String: Any]] = []
            while scanned < latest {
                let to = min(scanned + maxRange, latest)
                guard let chunk = await fetchFulfills(wallet: address,
                                                      from: scanned + 1, to: to)
                else { break }
                logs += chunk
                // Sell-side discovery rides the SAME chunk range (prd §237):
                // a wallet's own deposit-creation events, one extra filtered
                // call per chunk. A failure here shouldn't strand the buy
                // side, so it's best-effort, not a `break`.
                if let dep = await fetchDepositsCreated(wallet: address,
                                                        from: scanned + 1, to: to) {
                    depositLogs += dep
                }
                scanned = to
            }
            guard scanned > cursor else { continue }   // nothing read — transient
            let landed = await things(from: logs, wallet: address, existing: existing)
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                // Land and SAVE before advancing the cursor — a cursor that
                // runs ahead of durability turns an app kill into permanently
                // lost fills (the WalletApprovals lesson, 2026-07-16).
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            // A fill or a maker deposit under this wallet is proof it trades
            // on Peer — the catalog seat's evidence (2026-07-30). Keyed off
            // the LOGS, not what landed, matching Gnosis Pay and Privacy
            // Pools: a rescanned window dedupes to zero landed things while
            // still proving the fills are theirs. Keying it on `landed` cost
            // the seat forever for anyone who unwatched and re-watched — the
            // re-watch seeds silently at head, so nothing ever lands again
            // (found in review, 2026-07-30; it's the hazard `GnosisPayBridge`
            // already documents in prose).
            if !logs.isEmpty || !depositLogs.isEmpty { evidence.remember(address) }
            registerNewDeposits(from: depositLogs, wallet: address)
            defaults.set(scanned, forKey: key)
        }

        // One poll over the whole open-deposits watchlist, restricted to
        // this pass's wallets (an entry for an unwatched wallet was already
        // dropped by `clearCursor` — this filter is belt-and-suspenders).
        added += await pollOpenDeposits(context: context, addresses: Set(addresses.map { $0.lowercased() }),
                                        existing: existing)
        return added
    }

    /// `-peerProbe <blocksBack|YES>` — runs the sweep headlessly. A numeric
    /// spec first rewinds every watched wallet's cursor that many blocks
    /// below the Base head, so real past fills land and the whole path
    /// (logs → signal join → deposit token → titles → things) verifies
    /// without waiting for a live trade. Holds the running guard across the
    /// rewind (abandoned rewound cursors would land the old window into the
    /// real feed outside any probe — the -approvalProbe lesson). Seeds
    /// missing cursors before rewinding so a fresh install probes too.
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
                UserDefaults.standard.set(max(0, latest - back),
                                          forKey: cursorKey(address))
            }
        }
        return await syncLocked(context: context, addresses: addresses,
                                existing: IngestSupport.existingSourceRefs(context, source: "Peer"))
    }

    /// `-peerSeedDeposit "<depositId>[|wallet]"` — plants an open-deposits
    /// watchlist entry for a REAL depositId directly, skipping the "wait for
    /// a fresh deposit-creation event" step, so the next `-peerProbe`
    /// exercises the sell/expired landing paths against a real deposit's
    /// actual signal history instead of waiting for a fresh one to be made
    /// (the `-privacyPoolsSeedPending` idiom). `lastBlock` seeds at 0 so the
    /// scan walks the deposit's ENTIRE signaled-intent history (still
    /// budget-capped like every other chunked scan here). Pair `wallet` with
    /// whatever address is ALSO passed to `-walletAddress` — a seeded entry
    /// only gets polled for wallets this pass actually resolved. Declared
    /// BEFORE `-peerProbe` (hooks run in list order). DEBUG-only by
    /// construction — nothing else in the app writes this state.
    static func seedDeposit(spec: String) {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        guard let idText = parts.first, let idDecimal = UInt64(idText) else { return }
        let idHex = String(idDecimal, radix: 16)
        let hexTopic = "0x" + String(repeating: "0", count: 64 - idHex.count) + idHex
        let wallet = (parts.count > 1 ? parts[1] : "").lowercased()
        var entries = openDeposits().filter { $0["depositId"] != hexTopic }
        entries.append(["depositId": hexTopic, "wallet": wallet, "lastBlock": "0"])
        setOpenDeposits(entries)
    }

    // MARK: - Landing

    private struct Fill {
        let intentHash: String
        let orchestrator: String
        let rawAmount: Double
        let block: Int
        let txHash: String
    }

    /// Turns one wallet's fulfill logs into things — newest 10 only (a busy
    /// gap folds to its recent tail), deduped against the corpus and within
    /// the pass on the intent hash: one intent settles exactly once, so the
    /// hash is the natural sourceRef even across the two orchestrators.
    @MainActor
    private static func things(from logs: [[String: Any]], wallet: String,
                               existing: Set<String>) async -> [Thing] {
        var fills: [Fill] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count == 3,
                  let contract = (log["address"] as? String)?.lowercased(),
                  let intentHash = topics.dropFirst().first?.lowercased(),
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String
            else { continue }
            let data = (log["data"] as? String) ?? "0x"
            fills.append(Fill(
                intentHash: intentHash,
                orchestrator: contract,
                rawAmount: word(data, 0).map(WalletIngest.hexToDouble) ?? 0,
                block: WalletIngest.hexToInt(blockHex),
                txHash: txHash))
        }
        fills = Array(fills.suffix(10))
        guard !fills.isEmpty else { return [] }

        // Batched/memoized enrichment (review 2026-07-17): block timestamps
        // dedupe like WalletApprovals.blockTimes, and the deposit-token read
        // memoizes per (escrow, deposit) — one maker serves many takers, so
        // ten fills usually mean ONE deposit, not ten reads.
        let times = await blockTimes(blocks: fills.map(\.block))
        var tokenCache: [String: (address: String, symbol: String?, decimals: Int?)?] = [:]

        var out: [Thing] = []
        var seen = Set<String>()
        for fill in fills {
            let ref = "peer:\(fill.intentHash)"
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }
            var story = await signalStory(for: fill)
            if let escrow = story.escrow, let depositId = story.depositId {
                let key = "\(escrow)|\(depositId)"
                if let cached = tokenCache[key] {
                    story.token = cached
                } else {
                    let token = await depositToken(escrow: escrow, depositId: depositId)
                    tokenCache[key] = token
                    story.token = token
                }
            }
            let decimals = story.token?.decimals ?? 0
            let tokenAmount = fill.rawAmount / pow(10, Double(decimals))
            let thing = Thing(
                kind: .transaction,
                title: title(for: fill, story: story),
                content: "https://basescan.org/tx/\(fill.txHash)",
                source: "Peer",
                capturedAt: times[fill.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = wallet
            // The RAIL as data, not just as words in the title (2026-08-05,
            // prd §311). `story.method` has always been resolved — it is what
            // makes the title say "with Venmo" rather than "received" — and it
            // was only ever interpolated into a string, so nothing could group
            // on it. `authorHandle` is the groupable slot every other room
            // ranks on (Instagram's saved authors, X's liked authors), and a
            // funding rail is exactly that kind of fact: a small fixed
            // vocabulary you'd want counted. No new field.
            thing.authorHandle = story.method
            // Rate context (prd §237): a decimals-less token can't honestly
            // scale rawAmount into a real-units figure, so the line stays off.
            if story.token?.decimals != nil {
                thing.enrichedText = await rateLine(story: story, tokenAmount: tokenAmount)
            }
            out.append(thing)
        }
        return out
    }

    private struct Story {
        var method: String?      // "Venmo" — nil when the hash is unknown
        var currency: String?    // "USD" — nil when unknown
        var escrow: String?      // the fill's escrow contract, for the token read
        var depositId: String?   // raw 32-byte topic hex
        var token: (address: String, symbol: String?, decimals: Int?)?
        /// `conversionRate`, fiat units per one whole token, ×1e18 — the raw
        /// word straight off IntentSignaled's data (word 5). Real-units fiat
        /// paid is `tokenAmount * conversionRateRaw / 1e18` (prd §237's rate
        /// line); nil when the signal itself couldn't be found.
        var conversionRateRaw: Double?
    }

    /// Joins a fill to its IntentSignaled event (same orchestrator, indexed by
    /// the intent hash) for the platform + fiat + deposit coordinates. The
    /// signal lands minutes before the fulfill in the common case (at most
    /// INTENT_EXPIRATION, 6h ≈ 11k Base blocks), so the scan walks NEWEST
    /// window first and almost always answers in one getLogs. Every miss
    /// degrades the TITLE only — the fill still lands, wearing what's
    /// honestly known.
    private static func signalStory(for fill: Fill) async -> Story {
        var story = Story()
        let floor = max(0, fill.block - 12_000)
        var signal: [String: Any]?
        var to = fill.block
        while to > floor, signal == nil {
            let from = max(floor, to - maxRange + 1)
            let params: [String: Any] = [
                "fromBlock": hex(from), "toBlock": hex(to),
                "address": fill.orchestrator,
                "topics": [signaledTopic, fill.intentHash],
            ]
            guard let logs = await call(method: "eth_getLogs",
                                        params: [params]) as? [[String: Any]]
            else { break }
            signal = logs.first
            to = from - 1
        }
        guard let signal, let data = signal["data"] as? String else { return story }
        // data words: paymentMethod, owner, to, amount, fiatCurrency,
        // conversionRate, timestamp
        if let m = word(data, 0) { story.method = paymentMethods["0x" + m] }
        if let c = word(data, 4) { story.currency = currencies["0x" + c] }
        if let r = word(data, 5) { story.conversionRateRaw = WalletIngest.hexToDouble("0x" + r) }
        if let topics = signal["topics"] as? [String], topics.count == 4 {
            story.escrow = "0x" + topics[2].suffix(40)
            story.depositId = topics[3]
        }
        return story
    }

    /// "You paid $30.00 for 34.13 USDC — about 0.3% above market" (prd §237).
    /// USD only: a spread claim needs a market price on the same footing as
    /// the fiat, and the keyless price read (`DefiLlamaPrices`) is USD-
    /// denominated — a non-USD currency would need an FX cross-rate this app
    /// doesn't have, and inventing one would be a guess. Non-USD currencies
    /// still show the fiat amount, just without the spread clause. Silent
    /// (nil) when the currency, rate, or token isn't honestly known.
    private static func rateLine(story: Story, tokenAmount: Double) async -> String? {
        guard let currency = story.currency, let rate = story.conversionRateRaw,
              tokenAmount > 0 else { return nil }
        let fiatPaid = tokenAmount * rate / 1e18
        guard fiatPaid > 0 else { return nil }
        let fiatText = "\(currencySymbol(currency))\(WalletIngest.format(fiatPaid))"
        let whatText = story.token?.symbol.map { "\(WalletIngest.format(tokenAmount)) \($0)" }
            ?? WalletIngest.format(tokenAmount)
        guard currency == "USD", let token = story.token else {
            return String(localized: "You paid \(fiatText) for \(whatText) on Peer.")
        }
        let priced = await DefiLlamaPrices.prices(
            for: [(network: PeerBridge.network, contract: token.address)])
        guard let market = priced["\(PeerBridge.network)|\(token.address)"],
              market.confidence >= DefiLlamaPrices.confidenceFloor, market.price > 0
        else {
            return String(localized: "You paid \(fiatText) for \(whatText) on Peer.")
        }
        let paidPerToken = fiatPaid / tokenAmount
        let spreadPct = (paidPerToken - market.price) / market.price * 100
        if abs(spreadPct) < 0.5 {
            return String(localized: "You paid \(fiatText) for \(whatText) on Peer — right at market price.")
        }
        let direction = spreadPct > 0
            ? String(localized: "above market")
            : String(localized: "below market")
        let pctText = WalletIngest.format(abs(spreadPct))
        return String(localized: "You paid \(fiatText) for \(whatText) on Peer — about \(pctText)% \(direction).")
    }

    /// Only symbols that are UNAMBIGUOUS on their own — "$" alone could mean
    /// USD, AUD, CAD, MXN, … (all in §113's `currencies` map), and showing it
    /// for the wrong one would misstate the amount, not just its styling. So
    /// this covers only the four that don't collide within that table; every
    /// other code falls back to "CODE " (space-suffixed: "SGD 30.00", never
    /// "SGD30.00") rather than guess at a shared glyph.
    private static func currencySymbol(_ code: String) -> String {
        switch code {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        default: return "\(code) "
        }
    }

    /// "Bought 25 USDC with Venmo on Peer" — each clause only when honestly
    /// known: unknown token → the raw amount stays silent (a uint without
    /// decimals is not a number people should read), unknown platform → plain
    /// "Bought USDC on Peer", both unknown → "Bought crypto on Peer".
    private static func title(for fill: Fill, story: Story) -> String {
        var what = "crypto"
        if let symbol = story.token?.symbol {
            if let decimals = story.token?.decimals {
                let amount = WalletIngest.format(
                    fill.rawAmount / pow(10, Double(decimals)))
                what = "\(amount) \(symbol)"
            } else {
                what = symbol
            }
        }
        if let method = story.method {
            return String(localized: "Bought \(what) with \(method) on Peer")
        }
        return String(localized: "Bought \(what) on Peer")
    }

    // MARK: - Sell-side (maker) landing (prd §237)

    /// A newly-seen deposit-creation log — one per depositId, added to the
    /// open-deposits watchlist if not already tracked. Doesn't land anything
    /// itself (making a deposit isn't news; a deposit being TAKEN is).
    private static func registerNewDeposits(from logs: [[String: Any]], wallet: String) {
        guard !logs.isEmpty else { return }
        var entries = openDeposits()
        let known = Set(entries.compactMap { $0["depositId"] })
        var added = false
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count == 4,
                  let blockHex = log["blockNumber"] as? String
            else { continue }
            let depositId = topics[1]   // full 32-byte hex topic — reused verbatim as the topic filter later
            guard !known.contains(depositId) else { continue }
            entries.append([
                "depositId": depositId, "wallet": wallet.lowercased(),
                "lastBlock": String(WalletIngest.hexToInt(blockHex) - 1),
            ])
            added = true
        }
        if added { setOpenDeposits(entries) }
    }

    private struct Signal {
        let intentHash: String
        let block: Int
        let timestamp: Double
        let rawAmount: Double
        let method: String?
        let currency: String?
        let conversionRateRaw: Double?
    }

    /// Walks every watched maker deposit forward: new `IntentSignaled`s
    /// against it since `lastBlock`, resolved against a batched
    /// `IntentFulfilled` lookup over the same range. A resolved intent lands
    /// (sold, or — past `intentExpirySeconds` with no fulfillment — expired);
    /// an unresolved one holds the cursor back to just before its own block,
    /// so it's re-checked next pass instead of silently skipped. Once
    /// everything known is resolved, a closed deposit (`acceptingIntents ==
    /// false`) is dropped from the watchlist — bounding it for a maker who
    /// stopped using Peer instead of polling them forever.
    @MainActor
    private static func pollOpenDeposits(context: ModelContext, addresses: Set<String>,
                                         existing: Set<String>) async -> Int {
        let all = openDeposits()
        guard !all.isEmpty else { return 0 }
        guard let latest = await blockNumber() else { return 0 }
        var added = 0
        var kept: [[String: String]] = []

        for var entry in all {
            guard let wallet = entry["wallet"], addresses.contains(wallet) else {
                kept.append(entry)   // out of this pass's scope — untouched
                continue
            }
            guard let depositId = entry["depositId"] else { continue }   // malformed, drop
            let lastBlock = Int(entry["lastBlock"] ?? "") ?? (latest - 1)
            guard latest > lastBlock else { kept.append(entry); continue }

            var from = lastBlock + 1
            let budget = maxRange * maxChunks
            if latest - from >= budget { from = latest - budget + 1 }
            var scanned = from - 1
            var signalLogs: [[String: Any]] = []
            while scanned < latest {
                let to = min(scanned + maxRange, latest)
                guard let chunk = await fetchSignalsForDeposit(depositId: depositId,
                                                               from: scanned + 1, to: to)
                else { break }
                signalLogs += chunk
                scanned = to
            }
            guard scanned > lastBlock else { kept.append(entry); continue }   // nothing read — transient

            var signals: [Signal] = []
            for log in signalLogs {
                guard (log["removed"] as? Bool) != true,
                      let topics = log["topics"] as? [String], topics.count == 4,
                      let data = log["data"] as? String,
                      let blockHex = log["blockNumber"] as? String,
                      let amountWord = word(data, 3),
                      let tsWord = word(data, 6)
                else { continue }
                signals.append(Signal(
                    intentHash: topics[1],
                    block: WalletIngest.hexToInt(blockHex),
                    timestamp: WalletIngest.hexToDouble("0x" + tsWord),
                    rawAmount: WalletIngest.hexToDouble("0x" + amountWord),
                    method: word(data, 0).flatMap { paymentMethods["0x" + $0] },
                    currency: word(data, 4).flatMap { currencies["0x" + $0] },
                    conversionRateRaw: word(data, 5).map { WalletIngest.hexToDouble("0x" + $0) }))
            }

            var fulfilled: [String: [String: Any]] = [:]   // intentHash → its IntentFulfilled log
            if !signals.isEmpty,
               let fLogs = await fetchFulfilledBatch(
                   intentHashes: signals.map(\.intentHash), from: from, to: scanned) {
                for log in fLogs {
                    guard let topics = log["topics"] as? [String], topics.count == 3 else { continue }
                    fulfilled[topics[1]] = log
                }
            }

            let landed = await sellThings(signals: signals, fulfilled: fulfilled,
                                          wallet: wallet, depositId: depositId, existing: existing)
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                if context.saveHonestly() { added += landed.count }
            }

            let now = Date.now.timeIntervalSince1970
            let unresolvedBlocks = signals.compactMap { s -> Int? in
                guard fulfilled[s.intentHash] == nil,
                      now - s.timestamp <= intentExpirySeconds
                else { return nil }
                return s.block
            }
            if let holdAt = unresolvedBlocks.min() {
                entry["lastBlock"] = String(holdAt - 1)
                kept.append(entry)
                continue
            }
            entry["lastBlock"] = String(scanned)
            if let accepting = await depositAcceptingIntents(escrow: escrow, depositId: depositId),
               !accepting {
                continue   // closed and nothing left pending — retire
            }
            kept.append(entry)
        }
        setOpenDeposits(kept)
        return added
    }

    /// Turns resolved signals into things: a fulfillment → "Sold …", an
    /// expiry with no fulfillment → the stuck-funds alert. A still-pending
    /// signal (not yet fulfilled, not yet past `intentExpirySeconds`) lands
    /// nothing — it isn't news yet.
    @MainActor
    private static func sellThings(signals: [Signal], fulfilled: [String: [String: Any]],
                                   wallet: String, depositId: String,
                                   existing: Set<String>) async -> [Thing] {
        guard !signals.isEmpty else { return [] }
        let token = await depositToken(escrow: escrow, depositId: depositId)
        let now = Date.now.timeIntervalSince1970
        var out: [Thing] = []
        var seen = Set<String>()

        for signal in signals {
            let decimals = token?.decimals ?? 0
            let tokenAmount = signal.rawAmount / pow(10, Double(decimals))
            let what: String = {
                guard let symbol = token?.symbol else { return "crypto" }
                guard token?.decimals != nil else { return symbol }
                return "\(WalletIngest.format(tokenAmount)) \(symbol)"
            }()

            if let fLog = fulfilled[signal.intentHash] {
                let ref = "peer:sell:\(signal.intentHash)"
                guard !existing.contains(ref), seen.insert(ref).inserted else { continue }
                let txHash = (fLog["transactionHash"] as? String) ?? ""
                let title = signal.method.map { String(localized: "Sold \(what) with \($0) on Peer") }
                    ?? String(localized: "Sold \(what) on Peer")
                let thing = Thing(
                    kind: .transaction, title: title,
                    content: "https://basescan.org/tx/\(txHash)",
                    source: "Peer",
                    capturedAt: Date(timeIntervalSince1970: signal.timestamp),
                    sourceRef: ref)
                thing.walletAddress = wallet
                // The rail, on the SELL side too — a board that ranked only
                // buys would be a ranking of half the room.
                thing.authorHandle = signal.method
                if token?.decimals != nil {
                    let story = Story(method: signal.method, currency: signal.currency,
                                      escrow: nil, depositId: nil, token: token,
                                      conversionRateRaw: signal.conversionRateRaw)
                    thing.enrichedText = await rateLine(story: story, tokenAmount: tokenAmount)
                }
                out.append(thing)
            } else if now - signal.timestamp > intentExpirySeconds {
                let ref = "peer:expired:\(signal.intentHash)"
                guard !existing.contains(ref), seen.insert(ref).inserted else { continue }
                let title = signal.method.map {
                    String(localized: "A buyer's \($0) payment fell through — your \(what) is back on Peer")
                } ?? String(localized: "A buyer's payment fell through — your \(what) is back on Peer")
                let thing = Thing(
                    kind: .transaction, title: title,
                    content: "https://basescan.org/address/\(escrow)",
                    source: "Peer", capturedAt: .now, sourceRef: ref)
                thing.walletAddress = wallet
                out.append(thing)
            }
        }
        return out
    }

    // MARK: - RPC reads (Base public host, the wallet bridge's measured one)

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

    /// IntentFulfilled logs where fundsTransferredTo is this wallet — both
    /// orchestrators in one call (address takes an array), filtered
    /// server-side by the indexed recipient topic. nil = host refused/errored.
    private static func fetchFulfills(wallet: String, from: Int,
                                      to: Int) async -> [[String: Any]]? {
        let walletTopic = "0x000000000000000000000000" + wallet.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": orchestrators,
            "topics": [fulfilledTopic, nil, walletTopic],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// Deposit-creation logs where this wallet is the depositor — the
    /// sell-side entry point (prd §237), server-side filtered on the escrow's
    /// own indexed depositor topic exactly like `fetchFulfills` filters on
    /// the recipient.
    private static func fetchDepositsCreated(wallet: String, from: Int,
                                             to: Int) async -> [[String: Any]]? {
        let walletTopic = "0x000000000000000000000000" + wallet.dropFirst(2).lowercased()
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": escrow,
            "topics": [depositCreatedTopic, nil, walletTopic],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// Every `IntentSignaled` against one specific deposit — escrow AND
    /// depositId are both indexed on this event, so this is a cheap,
    /// server-side-exact join, not a firehose scan (measured live 2026-07-29:
    /// 16 signals found against one real deposit this way, in one call).
    private static func fetchSignalsForDeposit(depositId: String, from: Int,
                                               to: Int) async -> [[String: Any]]? {
        let escrowTopic = "0x" + String(repeating: "0", count: 24) + escrow.dropFirst(2)
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": orchestrators,
            "topics": [signaledTopic, nil, escrowTopic, depositId],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// `IntentFulfilled` for a whole batch of intent hashes in ONE call —
    /// `topics` accepts an array at a position for OR-matching, the same way
    /// `orchestrators` already does for the `address` field. Measured live
    /// 2026-07-29 against 16 real hashes: found exactly the 2 that had
    /// actually settled, none of the other 14.
    private static func fetchFulfilledBatch(intentHashes: [String], from: Int,
                                            to: Int) async -> [[String: Any]]? {
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": orchestrators,
            "topics": [fulfilledTopic, intentHashes],
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// The settled token: `getDeposit(depositId)` on the fill's own escrow
    /// (the deposit tuple's third word), then symbol + decimals read straight
    /// off the token contract via keyless `eth_call` (2026-07-19, replacing
    /// `alchemy_getTokenMetadata`) — the same `symbol()`-falling-back-to-
    /// `name()` decode `WalletApprovals.tokenMetadata` uses, on the same
    /// `mainnet.base.org` host every other Peer read already rides. In
    /// practice this is USDC nearly always — but read, never assumed.
    private static func depositToken(escrow: String, depositId: String)
        async -> (address: String, symbol: String?, decimals: Int?)? {
        let selector = "0x9f9fb968"   // keccak256("getDeposit(uint256)")[:4]
        let data = selector + depositId.dropFirst(2)
        guard let ret = await call(method: "eth_call",
                                   params: [["to": escrow, "data": data],
                                            "latest"]) as? String,
              let tokenWord = word(ret, 2)
        else { return nil }
        let token = "0x" + tokenWord.suffix(40)

        async let symbolRet = call(method: "eth_call",
                                   params: [["to": token, "data": "0x95d89b41"], "latest"])
        async let decimalsRet = call(method: "eth_call",
                                     params: [["to": token, "data": "0x313ce567"], "latest"])
        var symbol = (await symbolRet as? String).flatMap(IngestSupport.decodeABIString)
        if symbol == nil {
            let nameRet = await call(method: "eth_call",
                                     params: [["to": token, "data": "0x06fdde03"], "latest"])
            symbol = (nameRet as? String).flatMap(IngestSupport.decodeABIString)
        }
        let decimals = (await decimalsRet as? String).map(WalletIngest.hexToInt)
        guard symbol != nil || decimals != nil else { return nil }
        return (token, symbol, decimals)
    }

    /// The depositor of a given deposit — `getDeposit(depositId)`'s own first
    /// word (measured against six live deposits, cross-checked against the
    /// deposit-creation event's own indexed depositor topic every time).
    /// Used only to confirm a freshly-discovered depositId still belongs to
    /// the wallet the creation event named (defense against a future escrow
    /// upgrade quietly reusing depositIds) — not on the hot path.
    private static func depositor(escrow: String, depositId: String) async -> String? {
        let selector = "0x9f9fb968"
        let data = selector + depositId.dropFirst(2)
        guard let ret = await call(method: "eth_call",
                                   params: [["to": escrow, "data": data],
                                            "latest"]) as? String,
              let ownerWord = word(ret, 0)
        else { return nil }
        return "0x" + ownerWord.suffix(40)
    }

    /// `getDeposit(depositId)`'s own `acceptingIntents` flag (word 5) — used
    /// to retire a closed/emptied deposit from the open-deposits watchlist so
    /// a maker who stops using Peer doesn't get polled forever. `nil` on an
    /// unreachable read (keep watching; a network hiccup shouldn't retire a
    /// live deposit).
    private static func depositAcceptingIntents(escrow: String, depositId: String) async -> Bool? {
        let selector = "0x9f9fb968"
        let data = selector + depositId.dropFirst(2)
        guard let ret = await call(method: "eth_call",
                                   params: [["to": escrow, "data": data],
                                            "latest"]) as? String,
              let flagWord = word(ret, 5)
        else { return nil }
        return flagWord != String(repeating: "0", count: 64)
    }

    /// Real timestamps for the fills' blocks (deduped, capped — the
    /// WalletApprovals shape) — a fill found after a week away lands dated
    /// when it settled, not when the app next opened. A block past the cap
    /// stamps .now, close enough for the tail of a busy pass.
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

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }
}
