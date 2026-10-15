import Foundation
import SwiftData

/// Plasma One — the fourth card that settles ONCHAIN (2026-10-15, prd §1311).
/// A stablecoin card issued through Rain on Plasma (chain 9745). Rides the
/// watched wallets like Gnosis Pay, MetaMask Card and ether.fi Cash: no
/// account, no key, no connect switch — watching the wallet is the consent.
///
/// **A ROW IS A DAY, NOT A PURCHASE, and that is the chain's shape rather
/// than a choice.** Nothing reaches the chain when the card is tapped; Rain
/// sweeps every card's day out of its card contract once, at 12:31–12:34 UTC
/// (`PlasmaOneSettlement`'s header has the ten days of measurements). So this
/// seat lands "Settled $246.31 of card spending" once a day per card, every
/// settlement that day summed into one row, and the head counts DAYS
/// (`CardSpendRoom.Unit.settledDay`). A row that claimed to be a purchase, or
/// a count that called a day "1 spend", would be §83's fake status.
///
/// **WHICH ADDRESS.** The owner is indexed on the settlement, so the person
/// watches their own Plasma One account and the card is found by one topic
/// filter — no second address to paste. Watching the card contract itself
/// works too: its `owner()` names the account. A plain key (no code on
/// Plasma) can hold no card, so it costs one `eth_getCode`, re-asked daily,
/// and no scan (`Role`).
///
/// Honesty boundaries, inherited from Gnosis Pay's ruling (prd §222):
/// - CAPTURE ONLY. Nothing here spends, tops up, withdraws, changes a limit or
///   signs.
/// - NO MERCHANT NAMES. Not even a purchase reaches the chain; the merchant
///   never could.
/// - NOT A LEDGER. Which purchases a day's settlement covers, and how a refund
///   nets, are Rain's books. The row says what the card paid out that day.
///
/// MEASURED hosts (2026-10-15 — re-measure before editing one):
/// - `rpc.plasma.to` (Plasma's own): `eth_getLogs` capped at 10,000 blocks
///   AND 20,000 results, and BOTH ERROR explicitly ("limited to a 10,000
///   range", "query exceeds max results 20000"). Batches are served, but the
///   host allows 25 requests a second: a batch of 61 lost 36 to "-32007
///   25/second request limit reached", batches of 20 a second apart lost none.
/// - `9745.rpc.thirdweb.com`: 1,000 blocks a read, erroring past it; refuses
///   batches outright. It agrees with plasma.to exactly (5,706 = 5,706 over a
///   batch window, and 10 × 1k = one 10k), so it is a true fallback — a
///   slower one, which its smaller `budget` says.
/// - NOT USED: Routescan's Etherscan API answered `status 1, []` for a block
///   range holding a known settlement (the silent zero); `api.plasmascan.to`
///   wants an Etherscan V2 key; nodeflare and drpc's free plan do not serve
///   Plasma.
/// - Both hosts put `blockTimestamp` on every log, so a settlement is dated by
///   its own log; a host that ever drops it falls back to the block.
enum PlasmaOneCard {

    /// The room, and the catalogue name.
    static let source = "Plasma One"

    /// Where a settlement's permalink opens, in the PERSON's browser — never
    /// fetched by this app. Answers 200 on `/tx/` and `/address/` (measured).
    static let explorer = "https://plasmascan.to/tx/"

    /// One host and what it answered.
    struct Host {
        let url: String
        /// Blocks per `eth_getLogs`, inclusive span − 1.
        let maxRange: Int
        /// Calls per HTTP request — 1 where the host refuses a batch.
        let batch: Int
        /// Log calls per wallet per pass. A wallet further behind catches up
        /// over passes, walking forward; the cursor persists whether or not
        /// the head is reached.
        let budget: Int
    }

    /// In preference order. 60 × 10,000 blocks is 6.9 days at ~1.0s a block,
    /// which covers the backfill below in one pass; the fallback covers 17
    /// hours a pass and walks the rest on the next ones.
    static let hosts = [
        Host(url: "https://rpc.plasma.to", maxRange: 9_999, batch: 20, budget: 60),
        Host(url: "https://9745.rpc.thirdweb.com", maxRange: 999, batch: 1, budget: 60),
    ]

    /// First sight looks back six days — Linea's MetaMask Card window, so the
    /// head's "not following long enough to compare" reads the same on both.
    /// Blocks are ~1.00s (100,000 blocks spanned 100,013s).
    static let backfillBlocks = 6 * 86_400

    /// Which watched wallets have a card that settled. The seat appears only
    /// once a settlement is seen — Gnosis Pay's rule: "watching 3 wallets"
    /// for someone who holds no card is a fake status.
    static let evidence = WalletSeatEvidence("plasmaone.accounts")

    static func accounts() -> [String] { evidence.addresses }

    // MARK: - What a watched address is

    /// What a watched address is on Plasma, cached because two of the three
    /// never change: a card contract is a card forever, and an account with
    /// code keeps it. A plain key is re-asked after a day — a new account is
    /// a counterfactual smart account with no code until its first move.
    enum Role: Equatable {
        case card(owner: String)
        case account
        case key(checked: Date)
    }

    private static func roleKey(_ a: String) -> String { "plasmaone.role.\(a.lowercased())" }
    private static func cursorKey(_ a: String) -> String { "plasmaone.cursor.\(a.lowercased())" }
    private static func cardKey(_ a: String) -> String { "plasmaone.card.\(a.lowercased())" }
    private static let balancesKey = "plasmaone.balances"

    static func storedRole(_ address: String) -> Role? {
        guard let raw = UserDefaults.standard.string(forKey: roleKey(address)) else { return nil }
        if raw == "account" { return .account }
        if raw.hasPrefix("card:") { return .card(owner: String(raw.dropFirst(5))) }
        if raw.hasPrefix("key:"), let t = TimeInterval(raw.dropFirst(4)) {
            return .key(checked: Date(timeIntervalSince1970: t))
        }
        return nil
    }

    private static func store(_ role: Role, for address: String) {
        let raw: String
        switch role {
        case .card(let owner): raw = "card:\(owner)"
        case .account: raw = "account"
        case .key(let checked): raw = "key:\(Int(checked.timeIntervalSince1970))"
        }
        UserDefaults.standard.set(raw, forKey: roleKey(address))
    }

    /// nil when Plasma could not be asked — never cached, so a transient
    /// failure is not remembered as "a plain key".
    private static func role(_ address: String) async -> Role? {
        if let known = storedRole(address) {
            if case .key(let checked) = known,
               Date.now.timeIntervalSince(checked) > 86_400 {
                // stale: ask again below
            } else {
                return known
            }
        }
        guard let code = await call(method: "eth_getCode",
                                    params: [address, "latest"]) as? String
        else { return nil }
        let role: Role
        if PlasmaOneSettlement.isCardCode(code) {
            guard let word = await call(method: "eth_call",
                                        params: [["to": address,
                                                  "data": PlasmaOneSettlement.ownerSelector],
                                                 "latest"]) as? String,
                  let owner = PlasmaOneSettlement.address(fromTopic: word)
            else { return nil }
            role = .card(owner: owner)
            UserDefaults.standard.set(address.lowercased(), forKey: cardKey(address))
        } else if PlasmaOneSettlement.hasCode(code) {
            role = .account
        } else {
            role = .key(checked: .now)
        }
        store(role, for: address)
        return role
    }

    /// Wallet unwatch takes everything this seat keeps for the address —
    /// called from WalletStore beside the siblings'. A cursor left behind sits
    /// ahead of blocks never read, so re-watching would land nothing.
    static func clearState(address: String) {
        let a = address.lowercased()
        let defaults = UserDefaults.standard
        if let card = defaults.string(forKey: cardKey(a)) {
            var balances = storedBalances()
            balances.removeValue(forKey: card)
            defaults.set(balances.mapValues { [$0.amount, $0.at.timeIntervalSince1970] },
                         forKey: balancesKey)
        }
        for key in [roleKey(a), cursorKey(a), cardKey(a)] {
            defaults.removeObject(forKey: key)
        }
        evidence.forget(a)
    }

    // MARK: - The card's balance

    /// What sits in the card contract — the money the card can still spend —
    /// read with one `balanceOf` per card per pass. Keyed by CARD, so watching
    /// both the account and the card contract counts it once.
    static func storedBalances() -> [String: (amount: Double, at: Date)] {
        let raw = UserDefaults.standard.dictionary(forKey: balancesKey) as? [String: [Double]] ?? [:]
        return raw.compactMapValues { pair in
            pair.count == 2 ? (pair[0], Date(timeIntervalSince1970: pair[1])) : nil
        }
    }

    /// The watched cards' balance, summed, with the oldest reading's time —
    /// nil when no watched wallet has a card read yet.
    static func balance(watched: Set<String>) -> (amount: Double, at: Date)? {
        let defaults = UserDefaults.standard
        let cards = Set(watched.compactMap { defaults.string(forKey: cardKey($0)) })
        let balances = storedBalances()
        let read = cards.compactMap { balances[$0] }
        guard !read.isEmpty else { return nil }
        return (read.reduce(0) { $0 + $1.amount }, read.map(\.at).min() ?? .now)
    }

    private static func readBalance(card: String) async {
        let data = PlasmaOneSettlement.balanceOfSelector
            + String(PlasmaOneSettlement.topic(card).dropFirst(2))
        guard let word = await call(method: "eth_call",
                                    params: [["to": PlasmaOneSettlement.usdt0, "data": data],
                                             "latest"]) as? String,
              word.count == 66,
              let amount = PlasmaOneSettlement.dollars(String(word.dropFirst(2)))
        else { return }
        var raw = UserDefaults.standard.dictionary(forKey: balancesKey) as? [String: [Double]] ?? [:]
        raw[card] = [amount, Date.now.timeIntervalSince1970]
        UserDefaults.standard.set(raw, forKey: balancesKey)
    }

    // MARK: - Sync

    @MainActor private static var running = false

    /// Reads new settlements for the given (resolved, hex) addresses and lands
    /// them — called inside `WalletIngest.refresh`'s pass beside the other
    /// card seats. Returns rows landed or grown, nil when Plasma could not be
    /// reached for anyone.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses)
    }

    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String]) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        var added = 0
        var answered = false
        for address in addresses.map({ $0.lowercased() }) {
            guard let role = await role(address) else { continue }
            answered = true
            let owner: String
            switch role {
            case .key: continue
            case .account: owner = address
            case .card(let o): owner = o
            }
            guard let n = await syncOwner(owner, watched: address, context: context)
            else { continue }
            added += n
        }
        return answered ? added : nil
    }

    /// One watched address's pass: walk from the cursor, pair what settled,
    /// land it by day, then read the card's balance. nil when no host
    /// answered; the cursor moves only past windows that answered AND saved.
    @MainActor
    private static func syncOwner(_ owner: String, watched: String,
                                  context: ModelContext) async -> Int? {
        for host in hosts {
            guard let latest = await blockNumber(host) else { continue }
            let defaults = UserDefaults.standard
            let cursor = (defaults.object(forKey: cursorKey(watched)) as? Int)
                ?? max(0, latest - backfillBlocks) - 1
            guard latest > cursor else { return 0 }

            let (logs, scanned) = await walk(host, owner: owner, after: cursor, to: latest)
            guard scanned > cursor else { continue }   // nothing answered here

            var cards = Set(logs.compactMap { ($0["address"] as? String)?.lowercased() })
            if case .card = storedRole(watched) { cards.insert(watched) }
            if let card = cards.first {
                defaults.set(card, forKey: cardKey(watched))
            }
            // Evidence keys on settlements FOUND, never on rows landed —
            // Gnosis Pay's rule: a re-watch re-reads days that are already
            // rows, lands nothing new, and must still light the seat.
            if !logs.isEmpty { evidence.remember(watched) }

            var added = 0
            if !logs.isEmpty {
                guard let transfers = await pairedTransfers(host, settled: logs) else { continue }
                var read = PlasmaOneSettlement.settlements(settled: logs, transfers: transfers)
                if read.rejected > 0 {
                    NSLog("[Casberi] plasmaOne| %d settlement(s) refused (no paired transfer or a hash that disagrees)",
                          read.rejected)
                }
                read.paired = await dated(host, read.paired)
                let touched = land(PlasmaOneSettlement.days(read.paired),
                                   watched: watched, context: context)
                if !touched.isEmpty {
                    // Land and SAVE before the cursor moves (the
                    // WalletApprovals rule): a cursor that runs ahead of a
                    // failed save loses those days for good.
                    guard context.saveHonestly() else { continue }
                    SpotlightIndex.index(touched)
                }
                added = touched.count
            }
            defaults.set(scanned, forKey: cursorKey(watched))
            if let card = defaults.string(forKey: cardKey(watched)) {
                await readBalance(card: card)
            }
            return added
        }
        return nil
    }

    /// Settlement logs for one owner from `after + 1` toward `latest`, at most
    /// the host's budget of windows. Returns what was read and the last block covered by an
    /// UNBROKEN run of answered windows — a window that failed stops the walk
    /// there, so the cursor can never pass blocks nobody read.
    private static func walk(_ host: Host, owner: String, after cursor: Int,
                             to latest: Int) async -> (logs: [[String: Any]], scanned: Int) {
        // FORWARD from the cursor, never a jump to the head: a wallet further
        // behind than one pass's reach catches up over the next passes, so a
        // week away leaves no silent gap of days that read as "nothing spent".
        // The first sight's window is `backfillBlocks`, set by the caller.
        let from = cursor + 1
        let reach = (host.maxRange + 1) * host.budget
        let until = min(latest, from + reach - 1)
        var windows: [(Int, Int)] = []
        var start = from
        while start <= until {
            let end = min(start + host.maxRange, until)
            windows.append((start, end))
            start = end + 1
        }
        let filter: (Int, Int) -> [String: Any] = { a, b in
            ["fromBlock": hex(a), "toBlock": hex(b),
             "topics": [PlasmaOneSettlement.settledBalanceTopic,
                        PlasmaOneSettlement.topic(owner),
                        PlasmaOneSettlement.topic(PlasmaOneSettlement.settlementSafe)]]
        }
        let results = await batch(host, method: "eth_getLogs",
                                  params: windows.map { [filter($0.0, $0.1)] })
        var logs: [[String: Any]] = []
        var scanned = from - 1
        var answered = 0
        for (window, result) in zip(windows, results) {
            guard let chunk = result as? [[String: Any]] else { break }
            logs += chunk
            scanned = window.1
            answered += 1
        }
        #if DEBUG
        NSLog("[Casberi] plasmaOneWalk| %@ | %d of %d windows answered | %d settlement(s) | blocks %d…%d",
              host.url, answered, windows.count, logs.count, from, scanned)
        #endif
        return (logs, scanned)
    }

    /// The USDT0 transfers the settlements were paid with — one filtered read
    /// per settlement BLOCK (a card settles one to three times a day, so this
    /// is a handful), each naming the card and the Safe.
    private static func pairedTransfers(_ host: Host,
                                        settled: [[String: Any]]) async -> [[String: Any]]? {
        var wanted: [String: (block: Int, card: String)] = [:]
        for log in settled {
            guard let card = (log["address"] as? String)?.lowercased(),
                  let block = (log["blockNumber"] as? String).flatMap(PlasmaOneSettlement.hexInt)
            else { continue }
            wanted["\(block)|\(card)"] = (block, card)
        }
        let reads = Array(wanted.values)
        let results = await batch(host, method: "eth_getLogs", params: reads.map { r in
            [["fromBlock": hex(r.block), "toBlock": hex(r.block),
              "address": PlasmaOneSettlement.usdt0,
              "topics": [PlasmaOneSettlement.transferTopic,
                         PlasmaOneSettlement.topic(r.card),
                         PlasmaOneSettlement.topic(PlasmaOneSettlement.settlementSafe)]]]
        })
        var out: [[String: Any]] = []
        for result in results {
            guard let chunk = result as? [[String: Any]] else { return nil }
            out += chunk
        }
        return out
    }

    /// A settlement whose host left out `blockTimestamp` is dated by its block;
    /// one that still cannot be dated is HELD (it joins no day), never dated
    /// now (§790). Both measured hosts carry the field, so this asks nothing.
    private static func dated(_ host: Host,
                              _ settlements: [PlasmaOneSettlement.Settlement]) async
        -> [PlasmaOneSettlement.Settlement] {
        let missing = Array(Set(settlements.filter { $0.at == nil }.map(\.block)))
        guard !missing.isEmpty else { return settlements }
        let results = await batch(host, method: "eth_getBlockByNumber",
                                  params: missing.map { [hex($0), false] })
        var times: [Int: Date] = [:]
        for (block, result) in zip(missing, results) {
            guard let row = result as? [String: Any],
                  let ts = (row["timestamp"] as? String).flatMap(PlasmaOneSettlement.hexInt)
            else { continue }
            times[block] = Date(timeIntervalSince1970: TimeInterval(ts))
        }
        return settlements.map { s in
            guard s.at == nil, let at = times[s.block] else { return s }
            return .init(owner: s.owner, card: s.card, txHash: s.txHash,
                         logIndex: s.logIndex, block: s.block, at: at, amount: s.amount)
        }
    }

    // MARK: - Probe

    /// `-plasmaOneProbe <blocksBack|YES>` — runs the sweep over the watched
    /// wallets headlessly. A number rewinds every cursor that many blocks
    /// below the head first (86,400 is a day here), so past settlements land
    /// without waiting for tomorrow's batch. Pair with `-walletAddress <a
    /// Plasma One account>`. One NSLog per row, never one joined message (the
    /// `-todayProbe` truncation).
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
            .filter { ENS.isHexAddress($0) }.map { $0.lowercased() }
        var head: Int?
        for host in hosts where head == nil { head = await blockNumber(host) }
        guard let latest = head else {
            NSLog("[Casberi] plasmaOneChain| UNREACHABLE")
            return nil
        }
        NSLog("[Casberi] plasmaOneChain| head %d | backfill %d | rewind %@",
              latest, backfillBlocks, blocksBack.map(String.init) ?? "none")
        for address in addresses {
            if let back = blocksBack {
                UserDefaults.standard.set(max(0, latest - back) - 1, forKey: cursorKey(address))
            }
            let role = await role(address)
            NSLog("[Casberi] plasmaOneRole| %@ | %@", WalletStore.shortAddress(address),
                  role.map { "\($0)" } ?? "UNREACHABLE")
        }
        let n = await syncLocked(context: context, addresses: addresses)
        dumpRows(context: context)
        if let b = balance(watched: Set(addresses)) {
            NSLog("[Casberi] plasmaOneBalance| %.2f USDT0 | read %@", b.amount,
                  ISO8601DateFormatter().string(from: b.at))
        }
        return n
    }

    @MainActor
    private static func dumpRows(context: ModelContext) {
        let name = source
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 12
        let rows = (try? context.fetch(descriptor)) ?? []
        NSLog("[Casberi] plasmaOneRows: %d shown", rows.count)
        let stamp = ISO8601DateFormatter()
        for row in rows where row.isLive {
            NSLog("[Casberi] plasmaOneRow| %@ | %@ | %@ %@ | parts %d | %@",
                  stamp.string(from: row.capturedAt), row.title,
                  row.priceValue.map { String(format: "%.2f", $0) } ?? "—",
                  row.priceCurrency ?? "—", keptParts(row).count, row.content)
        }
    }

    /// The probe's status line — which watched wallets have a card.
    static func accountSummary() -> String {
        let known = accounts()
        guard !known.isEmpty else { return "no card accounts seen" }
        return "card accounts \(known.count): "
            + known.map { WalletStore.shortAddress($0) }.joined(separator: ", ")
    }

    // MARK: - Landing days

    /// One row per day: inserted the first time the day is seen, GROWN when a
    /// later pass finds another settlement that day. The parts already on a row
    /// are its rowless `.settlement` facts, so a rewound cursor or a re-watch
    /// adds nothing twice. Returns the rows inserted or grown, UNSAVED — the
    /// caller saves before it moves the cursor.
    @MainActor
    private static func land(_ days: [PlasmaOneSettlement.Day], watched: String,
                             context: ModelContext) -> [Thing] {
        var touched: [Thing] = []
        for day in days {
            let ref = day.ref
            var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
            descriptor.fetchLimit = 1
            let row = (try? context.fetch(descriptor))?.first(where: { $0.isLive })
            let kept = Set(keptParts(row).map(\.key))
            let fresh = PlasmaOneSettlement.newParts(of: day, alreadyKept: kept)
                .compactMap(PlasmaOneSettlement.factValue)
            guard !fresh.isEmpty else { continue }
            let thing: Thing
            if let row {
                thing = row
            } else {
                // `describe` below re-derives title, money, time and door from
                // the kept parts; these are its first values, never shown alone.
                thing = Thing(kind: .transaction, title: "",
                              content: explorer + (day.newest?.txHash ?? ""),
                              source: source, capturedAt: day.newest?.at ?? .now,
                              sourceRef: ref)
                thing.walletAddress = watched
                thing.transferDirection = "sent"
                context.insert(thing)
            }
            thing.facts += fresh.map { ThingFact("Settlement", $0, .settlement).encoded }
            describe(thing)
            touched.append(thing)
        }
        return touched
    }

    private static func keptParts(_ thing: Thing?) -> [PlasmaOneSettlement.Kept] {
        (thing?.factList ?? []).filter { $0.action == .settlement }
            .compactMap { PlasmaOneSettlement.Kept($0.value) }
    }

    /// Re-derives a day row from its parts. The parts are the record; the
    /// total, the title, the time and the link are always recomputed, so a row
    /// that grew can never disagree with what it holds.
    @MainActor
    private static func describe(_ thing: Thing) {
        guard let (amount, newest) = PlasmaOneSettlement.total(of: keptParts(thing)) else { return }
        let money = PriceFormat.string(amount, currency: "USD")
            ?? "\(WalletIngest.format(amount)) USDT0"
        thing.title = String(localized: "Settled \(money) of card spending")
        thing.content = explorer + newest.txHash
        thing.capturedAt = newest.at
        thing.transferAmount = "\(WalletIngest.format(amount)) USDT0"
        // USDT0 is a dollar stablecoin and the card a dollar card, so the
        // amount IS the money: both fields, never one (a `priceValue` with no
        // currency reads as dollars everywhere downstream anyway).
        thing.priceValue = amount
        thing.priceCurrency = "USD"
    }

    // MARK: - RPC

    /// One call, through each host in order; the first real result wins.
    private static func call(method: String, params: [Any]) async -> Any? {
        for host in hosts {
            if let result = await single(host, method: method, params: params) {
                return result
            }
        }
        return nil
    }

    private static func single(_ host: Host, method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0", "method": method, "params": params]
        guard let root = await IngestSupport.postJSON(host.url, body: body) as? [String: Any],
              let result = root["result"], !(result is NSNull)
        else { return nil }
        return result
    }

    private static func blockNumber(_ host: Host) async -> Int? {
        (await single(host, method: "eth_blockNumber", params: []) as? String)
            .flatMap(PlasmaOneSettlement.hexInt)
    }

    /// Many calls of one method on one host, in its batch size, a second apart
    /// between batches (`rpc.plasma.to`'s 25-a-second limit). Results align
    /// with `params`; an element is nil where the call errored or the request
    /// failed — the caller decides what a gap means.
    private static func batch(_ host: Host, method: String,
                              params: [[Any]]) async -> [Any?] {
        var out = [Any?](repeating: nil, count: params.count)
        var first = true
        for start in stride(from: 0, to: params.count, by: host.batch) {
            // A second between BATCHES only; a one-call host is paced by its
            // own round trip.
            if !first, host.batch > 1 { try? await Task.sleep(nanoseconds: 1_050_000_000) }
            first = false
            let slice = start..<min(start + host.batch, params.count)
            if host.batch == 1 {
                out[start] = await single(host, method: method, params: params[start])
                continue
            }
            let body: [[String: Any]] = slice.map {
                ["id": $0, "jsonrpc": "2.0", "method": method, "params": params[$0]]
            }
            guard let rows = await IngestSupport.postJSONArray(host.url, body: body) else { continue }
            // A batch answers in any order: place each by its own id.
            for row in rows {
                guard let id = row["id"] as? Int, slice.contains(id),
                      let result = row["result"], !(result is NSNull) else { continue }
                out[id] = result
            }
        }
        return out
    }

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }
}
