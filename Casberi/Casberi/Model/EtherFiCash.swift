import Foundation
import SwiftData

/// ether.fi Cash (2026-07-31) — the Visa card that settles ONCHAIN, and the
/// credit line behind it. Rides the watched wallets like Gnosis Pay: no
/// account, no key, no connect switch, keyless reads against Optimism.
///
/// Cash migrated from Scroll to OP Mainnet (announced Feb 2026; 70k active
/// cards, 300k accounts), so everything here is chain 10. A Cash account is an
/// `EtherFiSafe` — a smart account holding your collateral — and every card
/// purchase emits a `Spend` on one shared `CashEventEmitter` with the safe
/// INDEXED, so one filtered `eth_getLogs` per account finds every purchase.
///
/// **WHAT YOU WATCH IS THE SAFE, NOT YOUR EOA — and that is forced, not
/// chosen.** There is no onchain reverse lookup from an owner to their Cash
/// account, and this was established by measurement rather than assumed:
/// the factory's deploy event indexes only the safe and carries an opaque
/// backend salt (`getDeterministicAddress(salt)` reproduces the safe exactly,
/// but the salt is not derived from the owner — checked against three real
/// safes); every safe measured had exactly one owner, and that owner appears
/// only in event DATA, never in a topic, so `eth_getLogs` cannot filter for it.
/// Enumerating the factory's 300k safes to find one owner is not a phone's
/// job. So the seat is gated on `isEtherFiSafe(watched address)` — one
/// `eth_call` per watched wallet — and a person points Casberi at the Cash
/// account address ether.fi's own app shows them. A wallet that is not a Cash
/// safe costs exactly that one call and nothing else.
///
/// Honesty boundaries, inherited from Gnosis Pay's ruling (prd §222):
/// - CAPTURE ONLY. Nothing here spends, borrows, repays, freezes or signs.
/// - NO MERCHANT NAMES. The merchant, MCC and original currency never reach
///   the chain. Rows say what was spent and when, never where.
/// - The borrow position is READ. "Ready to claim"-style nudges belong to the
///   unstake queue; a debt gets a risk crossing and nothing more.
///
/// MEASURED (2026-07-31, live against OP Mainnet — re-measure before
/// "fixing" any of these; each fails silently or wrongly if re-derived):
/// - Every event topic was matched against real chain data rather than
///   trusted from source: `Spend` = `0x244f4cc0…` (1,408 in a ~1h window),
///   `Cashback` = `0x89d3571a…`, `RepayDebtManager`, `WithdrawalRequested`,
///   `WithdrawalProcessed` and `ModeSet` all confirmed the same way. The
///   canonical signature spells both enums as `uint8`.
/// - **`totalUsdAmt` rides the event in fixed 6-decimal USD**, so there is NO
///   per-token decimals trap here — the exact inverse of Gnosis Pay's USDCe
///   bug. It sits at data word 3 (after three dynamic-array offsets) with
///   `mode` at word 4; verified against real spends of $21.79, $6.58 and
///   $1,741.66. The token/amount arrays are deliberately not decoded — the
///   USD figure is the honest headline and needs no nested-dynamic decode
///   (the `AerodromeDeFi`/`VeSugar` rule).
/// - `Mode { Credit = 0, Debit = 1 }` — confirmed against source AND
///   cross-validated on chain: the two sampled mode-1 safes carried zero
///   debt while the mode-0 safe carried $2,880.
/// - `mainnet.optimism.io` hard-caps `eth_getLogs` at 10,000 blocks but
///   **ERRORS explicitly** rather than returning `[]` (better than Gnosis
///   Pay's silent-zero trap). `optimism.gateway.tenderly.co` served 2,000,000
///   blocks in 0.54s, and a wide read there was verified IDENTICAL to the sum
///   of 9k-block chunks from the official host over the same range — same 8
///   spends, no truncation. Hence the two hosts below carry their own
///   measured ranges instead of sharing one.
/// - The DebtManager answers plain single-return calls, so no struct decoding
///   is guessed at. On a real borrower: collateral $4,148.11, debt $2,880.42,
///   remaining capacity $398.10 — and `getMaxBorrowAmount(user, true)` equals
///   `debt + remaining` exactly, which is the read checking itself.
enum EtherFiCash {

    // Production Optimism deployment (`cash-v3`, deployments/mainnet/10).
    private static let dataProvider = "0xDC515Cb479a64552c5A11a57109C314E40A1A778"
    private static let eventEmitter = "0x380B2e96799405be6e3D965f4044099891881acB"
    private static let debtManager = "0x0078C5a459132e279056B2371fE8A8eC973A9553"

    /// `Spend(address indexed safe, bytes32 indexed txId, BinSponsor indexed
    /// binSponsor, address[] tokens, uint256[] amounts, uint256[] amountInUsd,
    /// uint256 totalUsdAmt, Mode mode)` — matched against live logs.
    private static let spendTopic =
        "0x244f4cc0665ad7ee4709aa59b30d3ea581cecde1b0430a3f23a5dc609d4890fc"

    /// Amounts on this product are USD with six decimals, everywhere — the
    /// `Spend` event's `totalUsdAmt` and every DebtManager read alike.
    private static let usdScale: Double = 1_000_000

    private struct Host {
        let url: String
        /// The widest `eth_getLogs` span this host actually answers — measured
        /// per host, not shared. Do not raise either without re-measuring.
        let maxRange: Int
    }
    private static let hosts: [Host] = [
        Host(url: "https://optimism.gateway.tenderly.co", maxRange: 1_000_000),
        Host(url: "https://mainnet.optimism.io", maxRange: 9_000),
    ]

    /// ~6 days of OP blocks (2s each). Same reasoning as Gnosis Pay's: a card
    /// is used often enough that a long first backfill would bury the feed on
    /// the day someone starts watching.
    private static let backfillBlocks = 250_000
    /// Blocks scanned per pass; a wallet further behind catches up over
    /// several passes because `scanned` persists either way.
    private static let scanBudget = 500_000

    /// Which watched wallets are actually Cash accounts. Same reasoning as
    /// Gnosis Pay's: most wallets hold no card, and a seat claiming otherwise
    /// is fake status.
    static let evidence = WalletSeatEvidence("etherficash.accounts")

    static func accounts() -> [String] { evidence.addresses }

    private static func cursorKey(_ address: String) -> String {
        "etherficash.cursor.\(address.lowercased())"
    }
    private static func riskKey(_ address: String) -> String {
        "etherficash.risk.\(address.lowercased())"
    }

    static func clearState(address: String) {
        let a = address.lowercased()
        UserDefaults.standard.removeObject(forKey: cursorKey(a))
        UserDefaults.standard.removeObject(forKey: riskKey(a))
        evidence.forget(a)
    }

    // MARK: - Book (live state)

    /// One Cash account's credit position. Collateral and debt are USD;
    /// `healthFactor` is derived from the contract's own liquidation-threshold
    /// maximum rather than a ratio this file invents.
    struct Account: Equatable, Sendable {
        let safe: String
        let collateralUSD: Double
        let debtUSD: Double
        /// What could still be borrowed against the current collateral.
        let remainingUSD: Double
        /// `maxBorrow(atLiquidationThreshold) / debt` — nil with no debt, which
        /// cannot be at risk of losing anything.
        let healthFactor: Double?
        /// The contract's own verdict, not a derived one.
        let liquidatable: Bool
    }

    struct Book: Equatable, Sendable {
        var accounts: [Account] = []
        var isEmpty: Bool { accounts.isEmpty }
        var collateralUSD: Double { accounts.reduce(0) { $0 + $1.collateralUSD } }
        var debtUSD: Double { accounts.reduce(0) { $0 + $1.debtUSD } }
    }

    private static let cache = CoalescingCache<Book>()

    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty else { return Book() }
        let key = addresses.map { $0.lowercased() }.sorted().joined(separator: ",")
        return await cache.value(key: key, ttl: 60) {
            await fetchBook(addresses: addresses)
        }
    }

    private static func fetchBook(addresses: [String]) async -> Book? {
        var book = Book()
        var reached = false
        for address in addresses {
            guard let isSafe = await isEtherFiSafe(address) else { continue }
            reached = true
            guard isSafe else { continue }
            evidence.remember(address)
            guard let account = await fetchAccount(safe: address) else { continue }
            book.accounts.append(account)
        }
        return reached ? book : nil
    }

    /// The gate — one `eth_call`, and the only cost for a wallet that has no
    /// Cash account. nil means the chain wasn't reached (a different thing
    /// from "not a Cash safe", which is `false`).
    private static func isEtherFiSafe(_ address: String) async -> Bool? {
        guard let hex = await ethCall(to: dataProvider,
            data: selector("isEtherFiSafe(address)") + padAddress(address)),
            let w = word(hex, 0) else { return nil }
        return WalletIngest.hexToInt("0x" + w) != 0
    }

    private static func fetchAccount(safe: String) async -> Account? {
        let arg = padAddress(safe)
        guard let collateralHex = await ethCall(to: debtManager,
            data: selector("getCollateralValueInUsd(address)") + arg),
            let collateralWord = word(collateralHex, 0) else { return nil }
        let collateral = WalletIngest.hexToDouble("0x" + collateralWord) / usdScale

        // `borrowingOf(address)` returns `(TokenData[], uint256)` — word 0 is
        // the array offset, word 1 the total. Only the total is read; the
        // per-token array is a dynamic decode this file does not need.
        var debt: Double = 0
        if let hex = await ethCall(to: debtManager,
            data: selector("borrowingOf(address)") + arg), let w = word(hex, 1) {
            debt = WalletIngest.hexToDouble("0x" + w) / usdScale
        }

        var remaining: Double = 0
        if let hex = await ethCall(to: debtManager,
            data: selector("remainingBorrowingCapacityInUSD(address)") + arg),
           let w = word(hex, 0) {
            remaining = WalletIngest.hexToDouble("0x" + w) / usdScale
        }

        // `false` asks for the maximum at the LIQUIDATION threshold (`true`
        // would be the lower LTV cap), so this ratio is the same shape as
        // Aave's health factor and can share `DeFiRisk.floor`.
        var healthFactor: Double? = nil
        if debt > 0,
           let hex = await ethCall(to: debtManager,
            data: selector("getMaxBorrowAmount(address,bool)") + arg + padUint(0)),
           let w = word(hex, 0) {
            let maxAtLiquidation = WalletIngest.hexToDouble("0x" + w) / usdScale
            if maxAtLiquidation > 0 { healthFactor = maxAtLiquidation / debt }
        }

        var liquidatable = false
        if let hex = await ethCall(to: debtManager,
            data: selector("liquidatable(address)") + arg), let w = word(hex, 0) {
            liquidatable = WalletIngest.hexToInt("0x" + w) != 0
        }

        return Account(safe: safe.lowercased(), collateralUSD: collateral,
                       debtUSD: debt, remainingUSD: remaining,
                       healthFactor: healthFactor, liquidatable: liquidatable)
    }

    // MARK: - Spends

    @MainActor private static var running = false

    /// Lands new card spends for the given resolved hex addresses — called
    /// inside `WalletIngest.refresh`'s pass beside `GnosisPayBridge.sync`.
    /// Returns the landed count, nil when Optimism couldn't be reached.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses, existing: existing)
    }

    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String],
                                   existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let latest = await blockNumber() else { return nil }
        let defaults = UserDefaults.standard
        var added = 0

        for address in addresses {
            // The gate again — a non-Cash wallet never reaches a log scan.
            guard let isSafe = await isEtherFiSafe(address), isSafe else { continue }
            evidence.remember(address)

            let key = cursorKey(address)
            let cursor = (defaults.object(forKey: key) as? Int)
                ?? max(0, latest - backfillBlocks) - 1
            guard latest > cursor else { continue }
            var from = cursor + 1
            if latest - from >= scanBudget { from = latest - scanBudget + 1 }
            guard let logs = await fetchSpends(safe: address, from: from, to: latest)
            else { continue }   // transient — keep the cursor, retry next pass

            let landed = await things(from: logs, safe: address, existing: existing)
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                // Land and SAVE before advancing the cursor (the
                // WalletApprovals rule) — a cursor ahead of a failed save
                // loses those spends permanently.
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            defaults.set(latest, forKey: key)
        }
        return added
    }

    private struct Spend {
        let usd: Double
        let onCredit: Bool
        let block: Int
        let txHash: String
        let logIndex: Int
    }

    @MainActor
    private static func things(from logs: [[String: Any]], safe: String,
                               existing: Set<String>) async -> [Thing] {
        var spends: [Spend] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String,
                  let data = log["data"] as? String,
                  let totalWord = word(data, 3), let modeWord = word(data, 4)
            else { continue }
            let usd = WalletIngest.hexToDouble("0x" + totalWord) / usdScale
            guard usd > 0 else { continue }
            spends.append(Spend(usd: usd,
                                onCredit: WalletIngest.hexToInt("0x" + modeWord) == 0,
                                block: WalletIngest.hexToInt(blockHex),
                                txHash: txHash,
                                logIndex: WalletIngest.hexToInt(indexHex)))
        }
        guard !spends.isEmpty else { return [] }

        // No `suffix(N)` cap, for Gnosis Pay's reason: card spends are not
        // rare, so capping would discard history the cursor then skips
        // forever. The ~6-day backfill bounds the first landing instead.
        let times = await blockTimes(blocks: spends.map(\.block))
        var out: [Thing] = []
        var seen = Set<String>()

        for spend in spends {
            let ref = "etherficash:spend:\(spend.txHash.lowercased()):\(spend.logIndex)"
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }
            let money = PriceFormat.string(spend.usd, currency: "USD")
                ?? "$\(WalletIngest.format(spend.usd))"
            // Credit and debit are genuinely different acts — one borrows, the
            // other spends what's there — and the event says which, so the row
            // does too rather than flattening both into "spent".
            let title = spend.onCredit
                ? String(localized: "Spent \(money) with ether.fi Cash — on credit")
                : String(localized: "Spent \(money) with ether.fi Cash")
            let thing = Thing(kind: .transaction, title: title,
                              content: "https://optimistic.etherscan.io/tx/\(spend.txHash)",
                              source: "ether.fi Cash",
                              capturedAt: times[spend.block] ?? .now,
                              sourceRef: ref)
            thing.walletAddress = safe
            thing.transferAmount = money
            thing.transferDirection = "sent"
            thing.priceValue = spend.usd
            thing.priceCurrency = "USD"
            out.append(thing)
        }
        return out
    }

    // MARK: - Borrow risk

    /// Lands a thing only on a NEW crossing into risk — the Aave/Morpho rule.
    /// A position already under the floor when watching starts DOES fire, on
    /// purpose (the `HyperliquidDeFi` precedent): a credit line near
    /// liquidation the day you start watching is exactly what you want told.
    @MainActor
    static func syncRisk(context: ModelContext, addresses: [String],
                         existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let book = await book(addresses: addresses) else { return nil }
        let defaults = UserDefaults.standard
        var added = 0

        for account in book.accounts {
            guard let hf = account.healthFactor else {
                defaults.removeObject(forKey: riskKey(account.safe))
                continue
            }
            let atRisk = account.liquidatable || hf < DeFiRisk.floor
            let wasAtRisk = defaults.bool(forKey: riskKey(account.safe))
            defaults.set(atRisk, forKey: riskKey(account.safe))
            guard atRisk, !wasAtRisk else { continue }

            let ref = "etherficash:risk:\(account.safe):\(Int(Date.now.timeIntervalSince1970))"
            guard !existing.contains(ref) else { continue }
            let debt = PriceFormat.string(account.debtUSD, currency: "USD")
                ?? "$\(WalletIngest.format(account.debtUSD))"
            let title = account.liquidatable
                ? String(localized: "Your ether.fi Cash credit line can be liquidated — \(debt) owed")
                : String(localized: "Your ether.fi Cash credit line is close to its limit (health \(String(format: "%.2f", hf))) — \(debt) owed")
            let thing = Thing(kind: .link, title: title,
                              content: "https://app.ether.fi/cash",
                              source: "Wallet", capturedAt: .now, sourceRef: ref)
            thing.walletAddress = account.safe
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { _ = context.saveHonestly() }
        return added
    }

    // MARK: - RPC

    private static func post(_ url: String, method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": method, "params": params]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
              let result = root["result"], !(result is NSNull) else { return nil }
        return result
    }

    private static func call(method: String, params: [Any]) async -> Any? {
        for host in hosts {
            if let result = await post(host.url, method: method, params: params) {
                return result
            }
        }
        return nil
    }

    private static func ethCall(to: String, data: String) async -> String? {
        await call(method: "eth_call", params: [["to": to, "data": data], "latest"]) as? String
    }

    private static func blockNumber() async -> Int? {
        guard let hex = await call(method: "eth_blockNumber", params: []) as? String
        else { return nil }
        return WalletIngest.hexToInt(hex)
    }

    /// Every `Spend` for this safe in a block range. Each host is asked within
    /// its OWN measured range — the wide host answers the span in one call,
    /// the official one is chunked at 9k. A host that fails any chunk hands
    /// the whole range to the next rather than returning a partial answer,
    /// because a short read here is indistinguishable from "spent nothing".
    private static func fetchSpends(safe: String, from: Int, to: Int) async -> [[String: Any]]? {
        guard to >= from else { return [] }
        for host in hosts {
            var out: [[String: Any]] = []
            var cursor = from
            var ok = true
            while cursor <= to {
                let end = min(cursor + host.maxRange - 1, to)
                guard let chunk = await logs(host: host.url, safe: safe,
                                             from: cursor, to: end) else {
                    ok = false
                    break
                }
                out += chunk
                cursor = end + 1
            }
            if ok { return out }
        }
        return nil
    }

    private static func logs(host: String, safe: String,
                             from: Int, to: Int) async -> [[String: Any]]? {
        let params: [String: Any] = [
            "fromBlock": "0x" + String(from, radix: 16),
            "toBlock": "0x" + String(to, radix: 16),
            "address": eventEmitter,
            "topics": [spendTopic, topic(safe)],
        ]
        return await post(host, method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// Block timestamps, batched — one request per 50 blocks rather than one
    /// per spend (the Gnosis Pay shape).
    private static func blockTimes(blocks: [Int]) async -> [Int: Date] {
        let wanted = Array(Set(blocks)).sorted(by: >)
        guard !wanted.isEmpty else { return [:] }
        var out: [Int: Date] = [:]
        for slice in stride(from: 0, to: wanted.count, by: 50).map({
            Array(wanted[$0..<min($0 + 50, wanted.count)])
        }) {
            let body: [[String: Any]] = slice.enumerated().map { i, block in
                ["id": i, "jsonrpc": "2.0", "method": "eth_getBlockByNumber",
                 "params": ["0x" + String(block, radix: 16), false]]
            }
            var rows: [[String: Any]]?
            for host in hosts {
                if let r = await IngestSupport.postJSONArray(host.url, body: body) {
                    rows = r
                    break
                }
            }
            // Read the block number off each RESULT — a batch answers in
            // whatever order it likes.
            for row in rows ?? [] {
                guard let result = row["result"] as? [String: Any],
                      let numberHex = result["number"] as? String,
                      let ts = result["timestamp"] as? String else { continue }
                out[WalletIngest.hexToInt(numberHex)] =
                    Date(timeIntervalSince1970: WalletIngest.hexToDouble(ts))
            }
        }
        return out
    }

    // MARK: - ABI helpers

    private static func topic(_ address: String) -> String {
        "0x000000000000000000000000" + address.dropFirst(2).lowercased()
    }

    private static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }

    private static func padAddress(_ address: String) -> String {
        let hex = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex.lowercased()
    }

    private static func padUint(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    private static func word(_ hex: String, _ n: Int) -> String? {
        let s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let start = n * 64, end = start + 64
        guard s.count >= end else { return nil }
        let i0 = s.index(s.startIndex, offsetBy: start)
        let i1 = s.index(s.startIndex, offsetBy: end)
        return String(s[i0..<i1]).lowercased()
    }

    #if DEBUG
    /// `-etherfiCashProbe <blocksBack|YES>` — reports, per watched wallet,
    /// whether it is a Cash account at all, then its credit position, then
    /// runs the spend sweep and the risk check. A numeric spec rewinds the
    /// cursors that many blocks so real past spends land headlessly. ONE LINE
    /// PER FACT (the `-todayProbe` truncation lesson). The is-a-safe verdict
    /// is printed separately from the position because "not a Cash account"
    /// and "couldn't reach Optimism" are different failures that a zero count
    /// would render identically.
    @MainActor
    static func probe(context: ModelContext, blocksBack: Int?) async -> [String] {
        for _ in 0..<60 where running {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return ["no EVM wallets watched"] }
        var lines: [String] = []
        for address in addresses {
            switch await isEtherFiSafe(address) {
            case .none: lines.append("\(WalletStore.shortAddress(address)): UNREACHABLE")
            case .some(false): lines.append("\(WalletStore.shortAddress(address)): not a Cash account")
            case .some(true): lines.append("\(WalletStore.shortAddress(address)): Cash account")
            }
        }
        if let book = await book(addresses: addresses) {
            if book.isEmpty { lines.append("no Cash accounts among the watched wallets") }
            for account in book.accounts {
                let hf = account.healthFactor.map { String(format: "%.3f", $0) } ?? "—"
                lines.append("\(WalletStore.shortAddress(account.safe)): collateral=\(WalletIngest.format(account.collateralUSD)) debt=\(WalletIngest.format(account.debtUSD)) remaining=\(WalletIngest.format(account.remainingUSD)) hf=\(hf) liquidatable=\(account.liquidatable)")
            }
        } else {
            lines.append("book UNREACHABLE")
        }
        if let back = blocksBack, let latest = await blockNumber() {
            for address in addresses {
                UserDefaults.standard.set(max(0, latest - back) - 1, forKey: cursorKey(address))
            }
        }
        guard !running else { return lines + ["sync: busy"] }
        running = true
        let spends = await syncLocked(
            context: context, addresses: addresses,
            existing: IngestSupport.existingSourceRefs(context, source: "ether.fi Cash"))
        running = false
        lines.append("spends: \(spends.map(String.init) ?? "FAILED") landed")
        let risk = await syncRisk(context: context, addresses: addresses,
                                  existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
        lines.append("risk: \(risk.map(String.init) ?? "FAILED") landed")
        return lines
    }
    #endif
}
