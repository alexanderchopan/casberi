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
/// Honesty boundaries, by ruling (prd §113):
/// - CAPTURE ONLY. Nothing here (or anywhere) starts a trade — same line as
///   Bankr's "answer only" and the Wallet screen's "watching can never trade
///   or move funds".
/// - A thing lands when a trade SETTLES, and not before. A signaled-but-
///   unfulfilled intent is a limbo the app would have to poll and could
///   mis-report; it never lands.
/// - The ZK design keeps the fiat leg private — the chain shows platform,
///   token, amount, and rate, never the counterparty or the person's Venmo
///   side. Titles state only what the events carry; an unknown payment-method
///   hash lands as plain "Bought … on Peer", never a guess.
enum PeerBridge {

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
    /// called beside WalletApprovals.clearCursors from WalletStore.
    static func clearCursor(address: String) {
        UserDefaults.standard.removeObject(forKey: cursorKey(address))
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
            while scanned < latest {
                let to = min(scanned + maxRange, latest)
                guard let chunk = await fetchFulfills(wallet: address,
                                                      from: scanned + 1, to: to)
                else { break }
                logs += chunk
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
            defaults.set(scanned, forKey: key)
        }
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
        var tokenCache: [String: (symbol: String?, decimals: Int?)?] = [:]

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
            let thing = Thing(
                kind: .transaction,
                title: title(for: fill, story: story),
                content: "https://basescan.org/tx/\(fill.txHash)",
                source: "Peer",
                capturedAt: times[fill.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = wallet
            out.append(thing)
        }
        return out
    }

    private struct Story {
        var method: String?      // "Venmo" — nil when the hash is unknown
        var currency: String?    // "USD" — nil when unknown
        var escrow: String?      // the fill's escrow contract, for the token read
        var depositId: String?   // raw 32-byte topic hex
        var token: (symbol: String?, decimals: Int?)?
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
        if let topics = signal["topics"] as? [String], topics.count == 4 {
            story.escrow = "0x" + topics[2].suffix(40)
            story.depositId = topics[3]
        }
        return story
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

    /// The settled token: `getDeposit(depositId)` on the fill's own escrow
    /// (the deposit tuple's third word), then symbol + decimals read straight
    /// off the token contract via keyless `eth_call` (2026-07-19, replacing
    /// `alchemy_getTokenMetadata`) — the same `symbol()`-falling-back-to-
    /// `name()` decode `WalletApprovals.tokenMetadata` uses, on the same
    /// `mainnet.base.org` host every other Peer read already rides. In
    /// practice this is USDC nearly always — but read, never assumed.
    private static func depositToken(escrow: String, depositId: String)
        async -> (symbol: String?, decimals: Int?)? {
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
        return (symbol, decimals)
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
