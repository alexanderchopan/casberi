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
enum PrivacyPoolsBridge {

    /// Mainnet only for now — Optimism/Arbitrum share a different Entrypoint
    /// (0x44192215…d15E) and Base is delisted in 0xBow's own config; add L2s
    /// only after measuring their hosts the way mainnet was.
    private static let rpcs = ["https://rpc.mevblocker.io",
                               "https://eth.api.onfinality.io/public"]
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

    private static let aspBase = "https://api.0xbow.io/1/public"

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

    // MARK: - The seat

    /// Internal so the setup screen's @AppStorage binds the SAME spelling
    /// (the Peer lesson, review 2026-07-17).
    static let seatKey = "privacypools.connected"

    static var connected: Bool {
        get { UserDefaults.standard.bool(forKey: seatKey) }
        set { UserDefaults.standard.set(newValue, forKey: seatKey) }
    }

    /// Disconnect drops the seat, the cursors, AND the pending-status
    /// watchlist — re-connecting starts honest, at a fresh backfill.
    static func disconnect() {
        connected = false
        for entry in WalletStore.shared.addresses {
            clearState(address: entry.address)
        }
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    private static func cursorKey(_ address: String) -> String {
        "privacypools.cursor.\(address.lowercased())"
    }

    /// Wallet unwatch takes this seat's cursor and that wallet's pending
    /// entries with it — called from WalletStore beside the siblings'.
    static func clearState(address: String) {
        UserDefaults.standard.removeObject(forKey: cursorKey(address))
        let wallet = address.lowercased()
        setPending(pending().filter { $0["wallet"] != wallet })
    }

    // MARK: - Pending-status watchlist (flat UserDefaults, keyless seat)

    private static let pendingKey = "privacypools.pending"

    /// Each entry: label (decimal), scope (decimal), symbol, amount (display
    /// string), wallet (lowercased hex), status (last seen; "" = just landed,
    /// baseline unknown).
    private static func pending() -> [[String: String]] {
        (UserDefaults.standard.array(forKey: pendingKey) as? [[String: String]]) ?? []
    }

    private static func setPending(_ entries: [[String: String]]) {
        UserDefaults.standard.set(entries, forKey: pendingKey)
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
        guard connected else { return 0 }
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
        guard connected, !running else { return 0 }
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
        var added = 0

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
            var logs: [[String: Any]] = []
            while scanned < latest {
                let to = min(scanned + maxRange, latest)
                guard let chunk = await fetchDeposits(wallet: address,
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
                // Land and SAVE before advancing (the WalletApprovals rule).
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            defaults.set(scanned, forKey: key)
        }

        // The status poll rides every pass, reachable-RPC or not — the ASP
        // is its own host, and a pending flip is the seat's whole point.
        let alerts = await pollStatuses(context: context, existing: existing)
        added += alerts
        return added
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

    /// The probe's status line — what the pending watchlist holds right now.
    static func pendingSummary() -> String {
        let entries = pending()
        guard !entries.isEmpty else { return "0 pending" }
        let parts = entries.map { e in
            "\(e["amount"] ?? "?") \(e["symbol"] ?? "?")=\(e["status"]?.isEmpty == false ? e["status"]! : "unpolled")"
        }
        return "\(entries.count) watched: " + parts.joined(separator: ", ")
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
            let ref = "privacypools:dep:" + (label ?? deposit.commitment)
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }

            let amount = pool.map {
                WalletIngest.format(deposit.rawAmount / pow(10, Double($0.decimals)))
            }
            let what = pool.map { "\(amount ?? "") \($0.symbol)" } ?? "crypto"
            let capturedAt = times[deposit.block] ?? .now
            let thing = Thing(
                kind: .transaction,
                title: String(localized: "Put \(what) into Privacy Pools"),
                content: "https://etherscan.io/tx/\(deposit.txHash)",
                source: "Privacy Pools",
                capturedAt: capturedAt,
                sourceRef: ref)
            thing.walletAddress = wallet
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

    // MARK: - ASP status poll

    /// Polls 0xBow's public deposits-by-label route for every watched label,
    /// batched per pool scope (the API's own batching: comma-joined
    /// X-Labels under one X-Pool-Scope). Lands alert things on watched
    /// transitions, prunes terminal entries. Returns alerts landed.
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
                if watching {
                    let what = "\(e["amount"] ?? "") \(e["symbol"] ?? "")"
                        .trimmingCharacters(in: .whitespaces)
                    let title = status == "approved"
                        ? String(localized: "Privacy Pools cleared your \(what) deposit — ready to withdraw privately")
                        : String(localized: "Privacy Pools declined your \(what) deposit — you can reclaim it to your wallet")
                    let ref = "privacypools:status:\(label)"
                    if !existing.contains(ref) {
                        let thing = Thing(kind: .transaction, title: title,
                                          content: "https://app.0xbow.io",
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
            default:
                // pending / poi_required / anything new: keep watching. A ""
                // baseline records the first-seen status silently here.
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
